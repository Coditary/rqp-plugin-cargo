local separator = package.config:sub(1, 1)

local function trim(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function shell_quote(value)
  local text = tostring(value or "")
  if text:match("^[%w%+%-%._/%:@=,\\]+$") then
    return text
  end
  return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function cmd_quote(value)
  return '"' .. tostring(value or ""):gsub('"', '""') .. '"'
end

local function join_path(...)
  local parts = {}
  for index = 1, select("#", ...) do
    local part = trim(select(index, ...))
    if part ~= "" then
      if #parts == 0 then
        table.insert(parts, (part:gsub("[/\\]+$", "")))
      else
        table.insert(parts, (part:gsub("^[/\\]+", ""):gsub("[/\\]+$", "")))
      end
    end
  end
  return table.concat(parts, separator)
end

local function os_ok(ok, _, code)
  if ok == true then
    return true
  end
  if type(ok) == "number" then
    return ok == 0
  end
  return code == 0
end

local function mkdir_p(path)
  local command
  if separator == "\\" then
    command = "if not exist " .. cmd_quote(path) .. " mkdir " .. cmd_quote(path) .. " >nul 2>nul"
  else
    command = "mkdir -p " .. shell_quote(path)
  end
  local ok, kind, code = os.execute(command)
  return os_ok(ok, kind, code)
end

local function rm_rf(path)
  local command
  if separator == "\\" then
    command = "if exist " .. cmd_quote(path) .. " rmdir /s /q " .. cmd_quote(path)
  else
    command = "rm -rf " .. shell_quote(path)
  end
  local ok, kind, code = os.execute(command)
  return os_ok(ok, kind, code)
end

local function read_file(path)
  local handle = assert(io.open(path, "r"))
  local content = handle:read("*a")
  handle:close()
  return content
end

local function assert_equal(actual, expected, label)
  if actual ~= expected then
    error(label .. " mismatch\nexpected:\n" .. tostring(expected) .. "\nactual:\n" .. tostring(actual))
  end
end

local temp_root = os.tmpname()
os.remove(temp_root)
assert(mkdir_p(temp_root), "failed to create temp root")

REQPACK_PLUGIN_DIR = temp_root
REQPACK_PLUGIN_SCRIPT = join_path(temp_root, "run.lua")

local global_commands = {}

reqpack = {
  exec = {
    run = function(command)
      table.insert(global_commands, command)

      if command == "command -v cargo >/dev/null 2>&1" then
        return { success = true, exitCode = 0, stdout = "", stderr = "" }
      end

      if command == "cargo install --list --quiet --color never" then
        return {
          success = true,
          exitCode = 0,
          stdout = "ripgrep v14.1.1:\n    rg\n",
          stderr = "",
        }
      end

      return {
        success = false,
        exitCode = 127,
        stdout = "",
        stderr = "unexpected global exec: " .. tostring(command),
      }
    end,
  },
}

package.loaded["run"] = nil
dofile("run.lua")

local manifest_path = join_path(temp_root, ".reqpack-data", "cargo-cache", "Cargo.toml")
local seen = {}

local context = {
  exec = {
    run = function(command)
      table.insert(seen, command)

      if command == "cargo fetch --manifest-path " .. manifest_path .. " --quiet --color never" then
        return { success = true, exitCode = 0, stdout = "fetch ok\n", stderr = "" }
      end

      if command == "cargo install --list --quiet --color never" then
        return {
          success = true,
          exitCode = 0,
          stdout = "ripgrep v14.1.1:\n    rg\n",
          stderr = "",
        }
      end

      return {
        success = false,
        exitCode = 127,
        stdout = "",
        stderr = "unexpected command: " .. tostring(command),
      }
    end,
  },
  tx = {
    begin_step = function() end,
    success = function() end,
    failed = function(message)
      error("unexpected tx failure: " .. tostring(message))
    end,
  },
  events = {
    installed = function() end,
    deleted = function() end,
    updated = function() end,
    listed = function() end,
  },
  log = {
    error = function(message)
      error("unexpected log error: " .. tostring(message))
    end,
  },
}

local installed = plugin.install(context, {
  { name = "serde", version = "1.0.228", packageType = "library" },
  { name = "tokio", packageType = "library" },
})

if installed ~= true then
  error("library install should succeed")
end

assert_equal(seen[1], "cargo fetch --manifest-path " .. manifest_path .. " --quiet --color never", "fetch command")

local expected_manifest = table.concat({
  "[package]",
  'name = "reqpack-cargo-cache"',
  'version = "0.0.0"',
  'edition = "2021"',
  "",
  "[dependencies]",
  'serde = "=1.0.228"',
  'tokio = "*"',
  "",
}, "\n")

assert_equal(read_file(manifest_path), expected_manifest, "manifest after install")

local missing = plugin.getMissingPackages({
  { name = "serde", version = "1.0.228", packageType = "library" },
  { name = "tokio", packageType = "library" },
})

if #missing ~= 0 then
  error("installed libraries should not be missing")
end

local listed = plugin.list(context)
if #listed ~= 3 then
  error("expected merged list with 3 items")
end

assert_equal(listed[1].name, "ripgrep", "first list item")
assert_equal(listed[2].name, "serde", "second list item")
assert_equal(listed[3].name, "tokio", "third list item")

local removed = plugin.remove(context, {
  { name = "serde", packageType = "library" },
})

if removed ~= true then
  error("library remove should succeed")
end

local expected_after_remove = table.concat({
  "[package]",
  'name = "reqpack-cargo-cache"',
  'version = "0.0.0"',
  'edition = "2021"',
  "",
  "[dependencies]",
  'tokio = "*"',
  "",
}, "\n")

assert_equal(read_file(manifest_path), expected_after_remove, "manifest after remove")

rm_rf(temp_root)
print("library manifest verified")
