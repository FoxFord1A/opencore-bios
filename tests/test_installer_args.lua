-- Verify that the OpenOS installer reads its filename from shell.parse(...),
-- not from Lua's standard global `arg` table.
local imagePath = os.tmpname()
local image = assert(io.open(imagePath, "wb"))
image:write("test BIOS image")
image:close()

local parsedArguments
package.preload.shell = function()
  return {
    parse = function(...)
      parsedArguments = {...}
      return parsedArguments, {}
    end
  }
end

local writeAttempted = false
package.preload.component = function()
  return {
    eeprom = {
      get = function() return "existing EEPROM code" end,
      set = function() writeAttempted = true end
    }
  }
end

local originalRead = io.read
local originalOpen = io.open
local originalPrint = print
io.read = function() return "CANCEL" end
io.open = function(path, mode)
  if mode == "wb" and path:match("^opencore%-bios%-backup%-%d+%.lua$") then
    return {write = function() end, close = function() end}
  end
  return originalOpen(path, mode)
end
print = function() end
arg = nil

local chunk, reason = loadfile("install.lua")
assert(chunk, reason)
chunk(imagePath)

io.read = originalRead
io.open = originalOpen
print = originalPrint
os.remove(imagePath)

assert(parsedArguments and parsedArguments[1] == imagePath,
  "installer should parse the BIOS path passed by OpenOS")
assert(not writeAttempted, "cancellation must not flash the EEPROM")
print("OpenOS installer argument test passed.")
