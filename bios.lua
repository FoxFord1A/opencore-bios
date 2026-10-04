-- OpenCore BIOS stage 1. Keep below the 4096-byte EEPROM limit.
local ci=component.invoke
local function call(a,m,...)
  local ok,x,y=pcall(ci,a,m,...)
  if ok then return x,y end
  return nil,tostring(x)
end
local ee=component.list("eeprom")()
if not ee then error("OpenCore BIOS: EEPROM missing",0) end
local raw=call(ee,"getData") or ""
local preferred=type(raw)=="string" and (raw:match("^OCB1|([^|]*)|") or raw) or ""
local function read(a,path)
  local h,e=call(a,"open",path)
  if not h then return nil,e end
  local b={}
  while true do
    local s,r=call(a,"read",h,8192)
    if s then b[#b+1]=s elseif r then call(a,"close",h);return nil,r else break end
  end
  call(a,"close",h)
  return table.concat(b)
end
-- The interactive boot manager lives on the system disk so EEPROM code stays small.
for a in component.list("filesystem") do
  local src=read(a,"/ocbios.lua")
  if src then
    local fn=load(src,"=ocbios")
    if fn then return fn() end
  end
end
-- Recovery path: if the menu module is missing, retain normal OpenOS boot.
local tried={}
local function boot(a)
  if not a or a=="" or tried[a] then return false end
  tried[a]=true
  local src=read(a,"/init.lua")
  if src then
    local fn=load(src,"=init")
    if fn then
      if type(raw)=="string" and not raw:match("^OCB1|") then call(ee,"setData",a) end
      return true,fn()
    end
  end
  return false
end
local ok,result=boot(preferred)
if ok then return result end
for a in component.list("filesystem") do
  ok,result=boot(a)
  if ok then return result end
end
error("OpenCore BIOS: manager and bootable /init.lua not found",0)
