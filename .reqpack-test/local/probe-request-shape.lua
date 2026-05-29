reqpack = {
  exec = {
    run = function(command)
      if command == "command -v cargo >/dev/null 2>&1" then
        return { success = true, exitCode = 0, stdout = "", stderr = "" }
      end

      return {
        success = false,
        exitCode = 127,
        stdout = "",
        stderr = "unexpected command: " .. tostring(command),
      }
    end,
  },
}

package.loaded["run"] = nil
dofile("run.lua")

local sample = {
  name = "serde",
  version = "1.0.228",
  packageType = "library",
  kind = "library",
  type = "library",
  action = "install",
}

for key, value in pairs(sample) do
  print(key .. "=" .. tostring(value))
end

print("package_kind=" .. tostring((function()
  local ok, result = pcall(function()
    return plugin.getMissingPackages({ sample })
  end)
  return ok and #result or "error"
end)()))
