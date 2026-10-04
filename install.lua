-- OpenCore BIOS installer for OpenOS.
-- Usage: lua install.lua /path/to/bios.lua

local function fail(message)
  io.stderr:write("OpenCore BIOS installer: " .. message .. "\n")
  os.exit(1)
end

-- OpenOS does not provide Lua's usual global `arg`; scripts receive shell
-- parameters as varargs and should parse them through the shell library.
local arguments = require("shell").parse(...)
local sourcePath = arguments[1]
if not sourcePath then
  fail("usage: lua install.lua /path/to/bios.lua")
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
