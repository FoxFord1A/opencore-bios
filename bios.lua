-- OpenCore BIOS for OpenComputers (Lua architecture)
-- Boots /init.lua from the configured filesystem, then scans available filesystems.
-- Designed to fit in a standard 4 KiB EEPROM.

local component_invoke = component.invoke
local pack = table.pack or function(...)
  return {n = select("#", ...), ...}
end
local unpack_values = table.unpack or unpack

local function invoke(address, method, ...)
  local result = pack(pcall(component_invoke, address, method, ...))
  if not result[1] then
    return nil, tostring(result[2])
  end
  return unpack_values(result, 2, result.n)
end

local eeprom = component.list("eeprom")()
if not eeprom then
  error("OpenCore BIOS: EEPROM component not found", 0)
end

-- Keep compatibility with software that expects these BIOS functions.
computer.getBootAddress = function()
  return invoke(eeprom, "getData")
end
computer.setBootAddress = function(address)
  return invoke(eeprom, "setData", address)
end

-- Bind the first GPU and screen so boot errors are visible on a display.
local screen = component.list("screen")()
local gpu = component.list("gpu")()
if gpu and screen then
  invoke(gpu, "bind", screen)
end

local function loadInit(address)
  local handle, reason = invoke(address, "open", "/init.lua")
  if not handle then
    return nil, reason or "cannot open /init.lua"
  end

  local chunks = {}
  while true do
    local chunk, readReason = invoke(address, "read", handle, 8192)
    if chunk then
      chunks[#chunks + 1] = chunk
    elseif readReason then
      invoke(address, "close", handle)
      return nil, readReason
    else
      break
    end
  end
  invoke(address, "close", handle)

  local source = table.concat(chunks)
  local init, compileReason = load(source, "=init")
  if not init then
    return nil, compileReason
  end
  return init
end

local tried = {}
local lastReason
local bootAddress = computer.getBootAddress()
local init

if bootAddress and bootAddress ~= "" then
  tried[bootAddress] = true
  init, lastReason = loadInit(bootAddress)
  if init then
    computer.beep(1000, 0.08)
    return init()
  end
end

for address in component.list("filesystem") do
  if not tried[address] then
    tried[address] = true
    local candidate, reason = loadInit(address)
    if candidate then
      computer.setBootAddress(address)
      computer.beep(1000, 0.08)
      return candidate()
    end
    lastReason = reason or lastReason
  end
end

local message = "OpenCore BIOS: no bootable medium found"
if lastReason then
  message = message .. ": " .. tostring(lastReason)
end
error(message, 0)
