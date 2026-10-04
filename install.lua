-- OpenCore BIOS installer for OpenOS.
-- Usage: lua install.lua /path/to/bios.lua

local function fail(message)
  io.stderr:write("OpenCore BIOS installer: " .. message .. "\n")
  os.exit(1)
end

print("OpenCore BIOS installer v1.2")

-- OpenOS does not provide Lua's usual global `arg`; scripts receive shell
-- parameters through the shell library. Some launchers do not forward them,
-- so use a terminal prompt as a reliable fallback.
local sourcePath
local parameters = {...}
local unpackValues = table.unpack or unpack
local shellOk, shell = pcall(require, "shell")
local parsedOk, arguments = false, nil
if shellOk and shell and shell.parse then
  parsedOk, arguments = pcall(shell.parse, unpackValues(parameters))
end
if parsedOk and type(arguments) == "table" then
  sourcePath = arguments[1]
end
if not sourcePath and type(arg) == "table" then
  sourcePath = arg[1]
end
if not sourcePath then
  io.write("Path to bios.lua (for example /tmp/bios.lua): ")
  sourcePath = io.read("*l")
end
if not sourcePath or sourcePath == "" then
  fail("no BIOS file path provided")
end

local sourceFile, openReason = io.open(sourcePath, "rb")
if not sourceFile then
  fail("cannot read " .. tostring(sourcePath) .. ": " .. tostring(openReason))
end
local biosCode = sourceFile:read("*a")
sourceFile:close()

local EEPROM_LIMIT = 4096
if #biosCode > EEPROM_LIMIT then
  fail(string.format("BIOS is %d bytes; EEPROM limit is %d bytes", #biosCode, EEPROM_LIMIT))
end

local component = require("component")
local eeprom = component.eeprom
if not eeprom then
  fail("no EEPROM component found")
end

local ok, currentCode = pcall(eeprom.get)
if not ok or type(currentCode) ~= "string" then
  fail("could not read the current EEPROM code: " .. tostring(currentCode))
end

local backupPath = "opencore-bios-backup-" .. tostring(os.time()) .. ".lua"
local backupFile, backupReason = io.open(backupPath, "wb")
if not backupFile then
  fail("could not save EEPROM backup: " .. tostring(backupReason))
end
backupFile:write(currentCode)
backupFile:close()

print("BIOS image: " .. tostring(sourcePath) .. " (" .. #biosCode .. "/" .. EEPROM_LIMIT .. " bytes)")
print("EEPROM backup saved to: " .. backupPath)
print("This will replace the computer's current EEPROM boot code.")
io.write('Type INSTALL to continue: ')
if io.read("*l") ~= "INSTALL" then
  print("Cancelled; EEPROM was not changed.")
  return
end

local writeOk, writeResult = pcall(eeprom.set, biosCode)
if not writeOk or writeResult == false then
  fail("EEPROM write failed: " .. tostring(writeResult))
end

local verifyOk, installedCode = pcall(eeprom.get)
if not verifyOk or installedCode ~= biosCode then
  -- Best-effort rollback if the EEPROM accepted a partial or unexpected write.
  pcall(eeprom.set, currentCode)
  fail("verification failed; attempted to restore the previous EEPROM code")
end

print("OpenCore BIOS installed and verified. Restart the computer to boot it.")
