-- OpenCore BIOS v1.3.1 installer for OpenOS.
local function fail(message)
  io.stderr:write("OpenCore BIOS installer: " .. message .. "\n")
  os.exit(1)
end
local function prompt(text)
  io.write(text)
  local value=io.read("*l")
  if not value or value=="" then fail("no path entered") end
  return value
end
local function readLocal(path)
  local f,err=io.open(path,"rb")
  if not f then fail("cannot read "..path..": "..tostring(err)) end
  local s=f:read("*a");f:close();return s
end
local function writeLocal(path,data)
  local f,err=io.open(path,"wb")
  if not f then fail("cannot save backup "..path..": "..tostring(err)) end
  f:write(data);f:close()
end
print("OpenCore BIOS installer v1.3.1")
local biosPath=prompt("Path to EEPROM BIOS (bios.lua): ")
local managerPath=prompt("Path to boot menu module (bootmgr.lua): ")
local biosCode=readLocal(biosPath)
local managerCode=readLocal(managerPath)
if #biosCode>4096 then fail(string.format("EEPROM BIOS is %d bytes; limit is 4096",#biosCode)) end

local component=require("component")
local eeprom=component.eeprom
if not eeprom then fail("no EEPROM component found") end
local readOk,oldEeprom=pcall(eeprom.get)
if not readOk or type(oldEeprom)~="string" then fail("could not read current EEPROM code: "..tostring(oldEeprom)) end
local dataOk,bootData=pcall(eeprom.getData)
local addr=dataOk and type(bootData)=="string" and (bootData:match("^OCB1|([^|]*)|") or bootData) or nil
if not addr or addr=="" then fail("cannot determine the current OpenOS boot filesystem") end
local ok,fs=pcall(component.proxy,addr)
if not ok or not fs then fail("cannot access boot filesystem "..tostring(addr)) end

local function readFS(path)
  local good,h,why=pcall(fs.open,path,"r")
  if not good or not h then return nil,why or h end
  local chunks={}
  while true do
    local r,data,err=pcall(fs.read,h,8192)
    if not r then pcall(fs.close,h);return nil,data end
    if data then chunks[#chunks+1]=data elseif err then pcall(fs.close,h);return nil,err else break end
  end
  pcall(fs.close,h)
  return table.concat(chunks)
end
local function writeFS(path,data)
  local good,h,err=pcall(fs.open,path,"w")
  if not good or not h then return false,err or h end
  local wrote,result=pcall(fs.write,h,data)
  pcall(fs.close,h)
  if not wrote or result==false then return false,result end
  return true
end
local function removeFS(path)
  if fs.remove then pcall(fs.remove,path) end
end
local moduleFile="/ocbios.lua"
local previousModule=readFS(moduleFile)
local stamp=tostring(os.time())
local backupPath="opencore-bios-backup-"..stamp..".lua"
local managerBackupPath="opencore-manager-backup-"..stamp..".lua"
writeLocal(backupPath,oldEeprom)
if previousModule then writeLocal(managerBackupPath,previousModule) end
print("EEPROM image: "..#biosCode.."/4096 bytes")
print("Menu module: "..#managerCode.." bytes -> "..moduleFile.." on "..addr)
print("EEPROM backup: "..backupPath)
if previousModule then print("Previous menu backup: "..managerBackupPath) end
print("This replaces the EEPROM BIOS and the boot-menu module on the current boot disk.")
io.write("Type INSTALL to continue: ")
if io.read("*l")~="INSTALL" then print("Cancelled; BIOS and disk were not changed.");return end

local copied,copyReason=writeFS(moduleFile,managerCode)
if not copied then fail("could not write boot-menu module: "..tostring(copyReason)) end
local verifyModule=readFS(moduleFile)
if verifyModule~=managerCode then
  if previousModule then writeFS(moduleFile,previousModule) else removeFS(moduleFile) end
  fail("boot-menu verification failed; previous module restored")
end
local flashed,flashResult=pcall(eeprom.set,biosCode)
if not flashed or flashResult==false then
  if previousModule then writeFS(moduleFile,previousModule) else removeFS(moduleFile) end
  fail("EEPROM write failed; previous boot-menu module restored: "..tostring(flashResult))
end
local verified,installed=pcall(eeprom.get)
if not verified or installed~=biosCode then
  pcall(eeprom.set,oldEeprom)
  if previousModule then writeFS(moduleFile,previousModule) else removeFS(moduleFile) end
  fail("EEPROM verification failed; attempted rollback of EEPROM and menu module")
end
print("OpenCore BIOS v1.3.1 installed and verified. Restart to open the boot menu.")
