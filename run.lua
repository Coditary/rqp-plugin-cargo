plugin = {}

-- `run.lua` executes as soon as ReqPack constructs the Lua bridge.
-- ReqPack reads plugin metadata from this file before optional `plugin.init()` runs.
-- Edit metadata.json first. metadata.json.name is plugin id used for discovery.
-- Convert this template bundle in this order:
-- 1. edit metadata.json fields
-- 2. replace all "template" placeholders in this file and .reqpack-test/core/*.lua
-- 3. add ReqPack system dependencies to reqpack.lua depends if needed
-- 4. add binary check in plugin.init()
-- 5. replace safe placeholder behavior with real package-manager commands

local PLUGIN_NAME = "Template Wrapper"
local PLUGIN_VERSION = "0.1.0"
local REQUIRED_BINARY = ""

-- Small helpers keep action methods easy to replace when you swap placeholder
-- behavior for real package-manager commands.
local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function emit_event(context, name, payload)
    if context == nil or context.events == nil then
        return
    end

    local fn = context.events[name]
    if type(fn) == "function" then
        fn(payload)
    end
end

local function begin_step(context, label)
    if context == nil or context.tx == nil then
        return
    end

    local fn = context.tx.begin_step
    if type(fn) == "function" then
        fn(label)
    end
end

local function tx_success(context)
    if context == nil or context.tx == nil then
        return
    end

    local fn = context.tx.success
    if type(fn) == "function" then
        fn()
    end
end

local function command_exists(binary)
    return reqpack.exec.run("command -v " .. shell_quote(binary) .. " >/dev/null 2>&1").success
end

-- Populate this when your wrapper installs local artifacts by extension.
-- ReqPack may read this table before plugin.init().
plugin.fileExtensions = {}

-- Keep these metadata methods side-effect free. ReqPack may call some of them
-- before plugin.init() while it is still loading plugin details.
function plugin.getName()
    return PLUGIN_NAME
end

function plugin.getVersion()
    return PLUGIN_VERSION
end

-- Planner and executor dependencies belong in reqpack.lua depends.
-- Keep this for runtime contract compatibility.
function plugin.getRequirements()
    return {}
end

function plugin.getCategories()
    return { "Template", "Wrapper" }
end

-- Planner uses this to filter work before action methods run.
-- `return packages` is valid, but real wrappers should detect installed/missing
-- state so ReqPack can avoid unnecessary work.
function plugin.getMissingPackages(packages)
    return packages or {}
end

-- Mutating action methods should usually emit tx/events so ReqPack can show
-- useful progress and result records.
function plugin.install(context, packages)
    begin_step(context, "install template packages")
    emit_event(context, "installed", packages or {})
    tx_success(context)
    return true
end

-- ReqPack calls installLocal when request uses localPath instead of packages.
function plugin.installLocal(context, path)
    begin_step(context, "install local template artifact")
    emit_event(context, "installed", { path = path, localTarget = true })
    tx_success(context)
    return true
end

function plugin.remove(context, packages)
    begin_step(context, "remove template packages")
    emit_event(context, "deleted", packages or {})
    tx_success(context)
    return true
end

function plugin.update(context, packages)
    begin_step(context, "update template packages")
    emit_event(context, "updated", packages or {})
    tx_success(context)
    return true
end

function plugin.list(context)
    local items = {}
    emit_event(context, "listed", items)
    return items
end

function plugin.outdated(context)
    local items = {}
    emit_event(context, "outdated", items)
    return items
end

-- Query methods return PackageInfo-like tables. Keep shapes deterministic so
-- search/info/list/outdated remain easy to test with `rqp test-plugin`.
function plugin.search(context, prompt)
    if trim(prompt) == "" then
        local empty = {}
        emit_event(context, "searched", empty)
        return empty
    end

    local items = {
        {
            name = trim(prompt),
            version = "template",
            type = "package",
            summary = "Replace this placeholder search result",
        }
    }

    emit_event(context, "searched", items)
    return items
end

function plugin.info(context, name)
    local item = {
        name = trim(name) ~= "" and trim(name) or "template-package",
        version = "template",
        description = "Replace this placeholder info result",
    }

    emit_event(context, "informed", item)
    return item
end

-- Use init() for runtime availability checks such as required binaries.
-- If tests exercise init(), add matching fakeExec rules so test-plugin can
-- satisfy the same command contract hermetically.
function plugin.init()
    if REQUIRED_BINARY ~= "" then
        return command_exists(REQUIRED_BINARY)
    end
    return true
end

-- Keep shutdown lightweight. Temp dirs created through context.fs.get_tmp_dir()
-- are cleaned up by ReqPack during bridge shutdown.
function plugin.shutdown()
    return true
end

return plugin
