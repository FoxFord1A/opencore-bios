local f=assert(io.open("bootmgr.lua","rb"))
local managerCode=f:read("*a");f:close()
local eepromData="OCB1||5|1|1"
local filesystems={
  ["FS-1"]={label="System disk",manager=managerCode,init="return 'wrong disk'"},
  ["FS-2"]={label="Games disk",init="return 'selected disk'"}
}
local reads={}
local display={}
local rendered={}
local events={
  {"key_down","KB",115,31}, -- S: open setup
  {"key_down","KB",0,208},   -- select boot timeout
  {"key_down","KB",0,205},   -- increment to six seconds
  {"key_down","KB",0,208},   -- startup sound
  {"key_down","KB",0,208},   -- logo
  {"key_down","KB",0,208},   -- save and return
  {"key_down","KB",13,28},   -- save
  {"key_down","KB",0,208},   -- choose second disk
  {"key_down","KB",13,28}    -- boot it
}
local kinds={EEPROM="eeprom",["FS-1"]="filesystem",["FS-2"]="filesystem",GPU="gpu",SCREEN="screen"}
local function list(kind)
  local result={}
  for address,k in pairs(kinds) do if k==kind then result[#result+1]=address end end
  table.sort(result)
  local n=0
  return function() n=n+1;return result[n] end
end
component={
  list=list,
  invoke=function(address,method,...)
    if address=="EEPROM" then
      if method=="getData" then return eepromData end
      if method=="setData" then eepromData=(...);return true end
    elseif kinds[address]=="filesystem" then
      local fs=filesystems[address]
      if method=="open" then
        local path=(...)
        local src=path=="/ocbios.lua" and fs.manager or path=="/init.lua" and fs.init
        if not src then return nil,"file not found" end
        local id=address..path
        reads[id]={data=src,used=false}
        return id
      elseif method=="read" then
        local state=reads[(...)]
        if state and not state.used then state.used=true;return state.data end
        return nil
      elseif method=="close" then return true
      elseif method=="getLabel" then return fs.label end
    elseif address=="GPU" then
      if method=="getResolution" then return 50,20 end
      if method=="set" then local _,y,text=...;display[y]=text;rendered[#rendered+1]=text;return true end
      return true
    end
    error("unexpected invoke "..address..":"..method)
  end
}
computer={
  beep=function() end,
  pullSignal=function()
    local event=table.remove(events,1)
    if event then return table.unpack(event) end
    return nil
  end
}
local bios=assert(loadfile("bios.lua"))
local ok,result=pcall(bios)
assert(ok and result=="selected disk","boot manager should launch selected filesystem")
assert(eepromData=="OCB1|FS-2|6|1|1","device and setup changes should persist")
assert(display[2] and display[2]:find("OPENCORE BIOS",1,true),"splash logo should render")
assert(display[5] and display[5]:find("BOOT MENU",1,true),"boot menu should render")
assert(table.concat(rendered,"\n"):find("SETUP",1,true),"setup menu should render")
print("OpenCore BIOS menu selection test passed.")
