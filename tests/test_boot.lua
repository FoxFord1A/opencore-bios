local BIOS_PATH = "bios.lua"

local function runScenario(bootAddress, filesystems)
  local eepromData = bootAddress
  local comps = {eeprom = "EEPROM-1"}
  local byAddress = { [comps.eeprom] = "eeprom" }
  for i, fs in ipairs(filesystems) do
    local address = fs.address or ("FS-" .. i)
    fs.address = address
    comps["filesystem-" .. i] = address
    byAddress[address] = "filesystem"
  end

  local function componentList(kind)
    local addresses = {}
    for _, address in pairs(comps) do
      if byAddress[address] == kind then addresses[#addresses + 1] = address end
    end
    table.sort(addresses)
    local index = 0
    return function()
      index = index + 1
      return addresses[index]
    end
  end

  component = {
    invoke = function(address, method, ...)
      if byAddress[address] == "eeprom" then
        if method == "getData" then return eepromData end
        if method == "setData" then eepromData = (...) return true end
      elseif byAddress[address] == "filesystem" then
        local fs
        for _, candidate in ipairs(filesystems) do
          if candidate.address == address then fs = candidate break end
        end
        if method == "open" then
          local path = (...)
          if fs and path == "/ocbios.lua" and fs.managerSource then return 2 end
          if fs and path == "/init.lua" and fs.source then return 1 end
          return nil, "init.lua not found"
        elseif method == "read" then
          if fs and (...) == 2 and fs.managerSource then
            local source = fs.managerSource
            fs.managerSource = nil
            return source
          elseif fs and fs.source then
            local source = fs.source;fs.source = nil
            return source
          end
          return nil
        elseif method == "close" then
          return true
        end
      end
      error("unexpected component invocation: " .. tostring(method))
    end,
    list = function(kind)
      return componentList(kind)
    end
  }
  computer = { beep = function() end }
  local chunk, reason = loadfile(BIOS_PATH)
  assert(chunk, reason)
  local ok, result = pcall(chunk)
  return ok, result, eepromData
end

local ok, result, data = runScenario("FS-2", {
  {address = "FS-1", source = "return 'wrong disk'"},
  {address = "FS-2", source = "return 'preferred disk'"}
})
assert(ok and result == "preferred disk", "should boot from configured disk")
assert(data == "FS-2", "configured boot address should remain unchanged")

ok, result, data = runScenario("missing-disk", {
  {address = "FS-1", source = "return 'fallback disk'"}
})
assert(ok and result == "fallback disk", "should fall back to another bootable disk")
assert(data == "FS-1", "successful fallback should be remembered")

ok, result = runScenario(nil, {
  {address = "FS-1", source = "this is not valid Lua !!!"},
  {address = "FS-2", source = "return 'after syntax error'"}
})
assert(ok and result == "after syntax error", "should skip invalid init.lua")

ok, result = runScenario(nil, {
  {address = "FS-1"}
})
assert(not ok and tostring(result):find("manager and bootable /init.lua not found", 1, true),
  "should report when no bootable filesystem exists")

print("All OpenCore BIOS boot tests passed.")
