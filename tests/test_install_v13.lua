-- Installer integration smoke test: cancel after paths/backups, before changes.
local function tempFile(contents)
  local path=os.tmpname()
  local f=assert(io.open(path,"wb"));f:write(contents);f:close()
  return path
end
local biosPath=tempFile("EEPROM BIOS test")
local managerPath=tempFile("boot manager test")
local eepromWrites=0
local diskWrites=0
local fs={
  open=function(path,mode)
    if mode=="r" then return nil,"not found" end
    diskWrites=diskWrites+1
    return 1
  end,
  write=function() return true end,
  close=function() return true end,
  remove=function() return true end
}
package.preload.component=function()
  return {
    eeprom={
      get=function() return "old EEPROM" end,
      getData=function() return "FS-TEST" end,
      set=function() eepromWrites=eepromWrites+1;return true end
    },
    proxy=function(address) assert(address=="FS-TEST");return fs end
  }
end
computer={getBootAddress=function() return "FS-TEST" end}
local oldRead,oldWrite,oldOpen,oldPrint=io.read,io.write,io.open,print
local inputs={biosPath,managerPath,"CANCEL"}
local inputIndex=0
io.read=function() inputIndex=inputIndex+1;return inputs[inputIndex] end
io.write=function() end
io.open=function(path,mode)
  if mode=="wb" and path:match("^opencore%-bios%-backup%-%d+%.lua$") then
    return {write=function() end,close=function() end}
  end
  return oldOpen(path,mode)
end
print=function() end
local chunk,reason=loadfile("install.lua")
assert(chunk,reason)
chunk()
io.read,io.write,io.open,print=oldRead,oldWrite,oldOpen,oldPrint
os.remove(biosPath);os.remove(managerPath)
assert(inputIndex==3,"installer should request both files and explicit confirmation")
assert(eepromWrites==0 and diskWrites==0,"cancellation must not change EEPROM or boot disk")
print("OpenCore BIOS installer cancellation test passed.")
