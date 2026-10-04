-- Installer success smoke test with an in-memory EEPROM and filesystem.
local function tempFile(contents)
  local path=os.tmpname()
  local f=assert(io.open(path,"wb"));f:write(contents);f:close()
  return path
end
local biosPath=tempFile("new BIOS payload")
local managerPath=tempFile("new menu payload")
local eepromCode="old EEPROM payload"
local managerCode=nil
local handleState={}
local writes=0
local fs={
  open=function(path,mode)
    if path~="/ocbios.lua" then return nil,"not found" end
    if mode=="r" then
      if not managerCode then return nil,"not found" end
      handleState.reader={read=false};return "reader"
    end
    handleState.writer=true;return "writer"
  end,
  read=function(handle)
    if handle=="reader" and not handleState.reader.read then
      handleState.reader.read=true;return managerCode
    end
    return nil
  end,
  write=function(handle,data)
    assert(handle=="writer");managerCode=data;writes=writes+1;return true
  end,
  close=function() return true end,
  remove=function(path) if path=="/ocbios.lua" then managerCode=nil end;return true end
}
package.preload.component=function()
  return {
    eeprom={
      get=function() return eepromCode end,
      getData=function() return "FS-TEST" end,
      set=function(code) eepromCode=code;return true end
    },
    proxy=function(address) assert(address=="FS-TEST");return fs end
  }
end
computer=nil -- OpenOS programs may not expose the BIOS global table.
local oldRead,oldWrite,oldOpen,oldPrint=io.read,io.write,io.open,print
local inputs={biosPath,managerPath,"INSTALL"}
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
assert(inputIndex==3,"installer should request BIOS, module, and confirmation")
assert(eepromCode=="new BIOS payload","EEPROM should contain BIOS stage-1")
assert(managerCode=="new menu payload" and writes==1,"boot disk should receive menu module")
print("OpenCore BIOS installer success test passed.")
