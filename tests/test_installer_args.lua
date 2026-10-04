-- Verify that the OpenOS installer still works when the launcher supplies
-- no command-line arguments and the user enters the BIOS path interactively.
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
local originalWrite = io.write
local originalOpen = io.open
local originalPrint = print
local readCount = 0
local requestedImagePath
io.read = function()
  readCount = readCount + 1
  if readCount == 1 then return imagePath end -- requested BIOS filename
  return "CANCEL" -- decline EEPROM flash
end
io.write = function() end
io.open = function(path, mode)
  if mode == "rb" then requestedImagePath = path end
  if mode == "wb" and path:match("^opencore%-bios%-backup%-%d+%.lua$") then
    return {write = function() end, close = function() end}
  end
  return originalOpen(path, mode)
end
print = function() end
arg = nil

local chunk, reason = loadfile("install.lua")
assert(chunk, reason)
chunk() -- simulate OpenOS/launcher that passes no varargs

io.read = originalRead
io.write = originalWrite
io.open = originalOpen
print = originalPrint
os.remove(imagePath)

assert(parsedArguments and #parsedArguments == 0,
  "test should exercise the no-arguments launcher case")
assert(requestedImagePath == imagePath,
  "installer should prompt for and open the entered BIOS path")
assert(readCount == 2, "installer should ask for path and then confirmation")
assert(not writeAttempted, "cancellation must not flash the EEPROM")
print("OpenOS installer interactive-path test passed.")
