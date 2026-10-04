-- OpenCore BIOS for OpenComputers (Lua architecture).
-- Stage-2 boot manager and setup UI, loaded from /ocbios.lua on disk.
local ci=component.invoke
local pack=table.pack or function(...) return {n=select("#",...),...} end
local unpackv=table.unpack or unpack
local function call(a,m,...)
  local r=pack(pcall(ci,a,m,...))
  if not r[1] then return nil,tostring(r[2]) end
  return unpackv(r,2,r.n)
end
local ee=component.list("eeprom")()
if not ee then error("OpenCore BIOS: EEPROM missing",0) end
local cfg={addr="",timeout=5,sound=true,logo=true}
local raw=call(ee,"getData")
if type(raw)=="string" then
  local a,t,s,l=raw:match("^OCB1|([^|]*)|(%d+)|([01])|([01])$")
  if a then cfg.addr=a;cfg.timeout=math.min(10,tonumber(t) or 5);cfg.sound=s=="1";cfg.logo=l=="1"
  elseif raw~="" then cfg.addr=raw end
end
local function save()
  return call(ee,"setData",string.format("OCB1|%s|%d|%d|%d",cfg.addr,cfg.timeout,cfg.sound and 1 or 0,cfg.logo and 1 or 0))
end
computer.getBootAddress=function() return cfg.addr~="" and cfg.addr or nil end
computer.setBootAddress=function(a) cfg.addr=a or "";return save() end
local scr=component.list("screen")()
local gpu=component.list("gpu")()
if gpu and scr then call(gpu,"bind",scr) end
local w,h=50,16
if gpu then local x,y=call(gpu,"getResolution");w=x or w;h=y or h end
local function put(y,text,color)
  if not gpu or y<1 or y>h then return end
  text=tostring(text or "")
  if #text>w then text=text:sub(1,w) end
  if color then call(gpu,"setForeground",color) end
  call(gpu,"set",1,y,text)
end
local function draw(title,rows,sel,foot)
  if not gpu then return end
  call(gpu,"setBackground",0x071522);call(gpu,"fill",1,1,w,h," ")
  call(gpu,"setForeground",0x38BDF8)
  if cfg.logo then
    put(1,"+----------------------+",0x38BDF8)
    put(2,"|    OPENCORE BIOS     |",0x38BDF8)
    put(3,"|   [==] BOOT SYSTEM   |",0x38BDF8)
    put(4,"+----------------------+",0x38BDF8)
  else put(1,"OPENCORE BIOS",0x38BDF8) end
  put(5,title,0xFFFFFF)
  local max=math.max(1,h-8)
  local first=math.max(1,(sel or 1)-max+1)
  for i=first,math.min(#rows,first+max-1) do
    local marker=i==(sel or 0) and "> " or "  "
    put(6+i-first,marker..rows[i],i==(sel or 0) and 0xFBBF24 or 0xD1D5DB)
  end
  if foot then put(h,foot,0x94A3B8) end
end
local function readInit(addr)
  local handle,why=call(addr,"open","/init.lua")
  if not handle then return nil,why or "missing /init.lua" end
  local chunks={}
  while true do
    local s,e=call(addr,"read",handle,8192)
    if s then chunks[#chunks+1]=s elseif e then call(addr,"close",handle);return nil,e else break end
  end
  call(addr,"close",handle)
  local fn,err=load(table.concat(chunks),"=init")
  if not fn then return nil,err end
  return fn
end
local disks,bootableCount={},0
for a in component.list("filesystem") do
  local handle=call(a,"open","/init.lua")
  local bootable=handle~=nil
  if handle then call(a,"close",handle);bootableCount=bootableCount+1 end
  local label=call(a,"getLabel")
  if type(label)~="string" or label=="" then label="FS "..a:sub(1,8) end
  disks[#disks+1]={addr=a,label=label,bootable=bootable}
end
local function defaultIndex()
  for i,d in ipairs(disks) do if d.addr==cfg.addr and d.bootable then return i end end
  for i,d in ipairs(disks) do if d.bootable then return i end end
  return 1
end
local function start(i)
  local d=disks[i]
  if not d then return false,"No bootable devices found" end
  if not d.bootable then return false,d.label..": data filesystem; /init.lua is missing" end
  local fn,err=readInit(d.addr)
  if not fn then return false,d.label..": "..tostring(err) end
  cfg.addr=d.addr;save()
  if cfg.sound and computer.beep then pcall(computer.beep,1000,0.08) end
  return true,fn()
end
local function key(ev,ch,code)
  if ev~="key_down" then return nil end
  if code==200 then return "up" elseif code==208 then return "down"
  elseif code==203 then return "left" elseif code==205 then return "right"
  elseif code==28 or ch==13 then return "enter"
  elseif code==1 or ch==27 then return "escape"
  elseif ch==115 or ch==83 then return "setup" end
end
local function setup()
  local old={addr=cfg.addr,timeout=cfg.timeout,sound=cfg.sound,logo=cfg.logo}
  local bootOptions={{addr="",label="Auto / first available"}}
  for _,d in ipairs(disks) do if d.bootable then bootOptions[#bootOptions+1]=d end end
  local pick=1
  for i,d in ipairs(bootOptions) do if d.addr==cfg.addr then pick=i end end
  local item=1
  local names={"Default boot device","Boot timeout","Startup sound","Logo","Save and return","Discard changes"}
  while true do
    local values={bootOptions[pick].label,
      cfg.timeout==0 and "Off / wait for key" or (cfg.timeout.." seconds"),
      cfg.sound and "On" or "Off",cfg.logo and "On" or "Off"}
    local rows={}
    for i,n in ipairs(names) do rows[i]=n..(values[i] and (": "..values[i]) or "") end
    draw("SETUP  |  Left/Right changes value",rows,item,"Up/Down select   Enter apply   Esc return")
    local ev,_,ch,code=computer.pullSignal()
    local k=key(ev,ch,code)
    if k=="up" then item=(item-2)%#names+1
    elseif k=="down" then item=item%#names+1
    elseif k=="left" or k=="right" then
      local step=k=="right" and 1 or -1
      if item==1 then pick=(pick-1+step)%#bootOptions+1
      elseif item==2 then cfg.timeout=(cfg.timeout+step)%11
      elseif item==3 then cfg.sound=not cfg.sound
      elseif item==4 then cfg.logo=not cfg.logo end
    elseif k=="enter" then
      if item==5 then cfg.addr=bootOptions[pick].addr;save();return
      elseif item==6 then cfg=old;return
      elseif item==1 then pick=pick%#bootOptions+1
      elseif item==2 then cfg.timeout=(cfg.timeout+1)%11
      elseif item==3 then cfg.sound=not cfg.sound
      elseif item==4 then cfg.logo=not cfg.logo end
    elseif k=="escape" then cfg=old;return end
  end
end
local function menu()
  local selected=defaultIndex()
  local elapsed=0
  while true do
    local rows={}
    for i,d in ipairs(disks) do
      local state=d.bootable and " [bootable]" or " [data/no init]"
      rows[i]=(d.addr==cfg.addr and "[default] " or "")..d.label:sub(1,16).." "..d.addr:sub(1,6)..state
    end
    if #rows==0 then rows[1]="No filesystem components detected";selected=1 end
    local countdown=bootableCount==0 and "No bootable filesystem found" or (cfg.timeout>0 and ("Auto boot in "..math.max(0,cfg.timeout-elapsed).."s") or "Auto boot disabled")
    draw("BOOT MENU  |  OpenCore BIOS",rows,selected,"Up/Down select  Enter boot  S setup  |  "..countdown)
    local ev,_,ch,code=computer.pullSignal(1)
    local k=key(ev,ch,code)
    if k then
      elapsed=0
      if k=="up" and #disks>0 then selected=(selected-2)%#disks+1
      elseif k=="down" and #disks>0 then selected=selected%#disks+1
      elseif k=="setup" then setup();selected=defaultIndex()
      elseif k=="enter" and #disks>0 then
        local ok,result=start(selected)
        if ok then return result end
        draw("BOOT ERROR",{tostring(result),"Press any key to return"},1)
        computer.pullSignal()
      elseif k=="escape" and bootableCount>0 then
        local ok,result=start(defaultIndex())
        if ok then return result end
      end
    else elapsed=elapsed+1 end
    if cfg.timeout>0 and elapsed>=cfg.timeout and bootableCount>0 then
      local ok,result=start(defaultIndex())
      if ok then return result end
      draw("BOOT ERROR",{tostring(result),"Press any key to retry"},1)
      computer.pullSignal();elapsed=0
    end
  end
end
if not gpu or not scr then
  local tried={}
  if cfg.addr~="" then tried[cfg.addr]=true;for i,d in ipairs(disks) do if d.addr==cfg.addr then local ok,r=start(i);if ok then return r end end end end
  for i,d in ipairs(disks) do if not tried[d.addr] then local ok,r=start(i);if ok then return r end end end
  error("OpenCore BIOS: no bootable medium found",0)
end
return menu()
