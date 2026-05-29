plugin = {}

local PLUGIN_NAME = "Cargo"
local PLUGIN_VERSION = "0.1.0"
local REQUIRED_BINARY = "cargo"
local DEFAULT_PACKAGE_TYPE = "tool"
local SEARCH_LIMIT = 20

local MANIFEST_HEADER_LINES = {
    "[package]",
    'name = "reqpack-cargo-cache"',
    'version = "0.0.0"',
    'edition = "2021"',
    "",
    "[dependencies]",
}

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function lower(value)
    return string.lower(tostring(value or ""))
end

local function split_lines(value)
    local text = tostring(value or ""):gsub("\r\n", "\n")
    local lines = {}

    if text == "" then
        return lines
    end

    for line in (text .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, line)
    end

    return lines
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

local function is_windows_host()
    local plugin_dir = tostring(_G.REQPACK_PLUGIN_DIR or "")
    if plugin_dir:find("\\", 1, true) ~= nil then
        return true
    end

    local host = reqpack and reqpack.host or nil
    local platform = host and host.platform or nil
    local os_info = host and host.os or nil
    local os_family = lower(trim(platform and platform.osFamily or ""))
    local os_id = lower(trim(os_info and os_info.id or ""))

    return os_family == "windows" or os_id == "windows"
end

local function path_separator()
    if is_windows_host() then
        return "\\"
    end

    return "/"
end

local function command_quote(value)
    if is_windows_host() then
        return cmd_quote(value)
    end

    return shell_quote(value)
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

local function tx_failed(context, message)
    if context == nil or context.tx == nil then
        return
    end

    local fn = context.tx.failed
    if type(fn) == "function" then
        fn(message)
    end
end

local function log_error(context, message)
    if context == nil or context.log == nil then
        return
    end

    local fn = context.log.error
    if type(fn) == "function" then
        fn(message)
    end
end

local function run_exec(context, command, options)
    if context ~= nil and context.exec ~= nil and type(context.exec.run) == "function" then
        if options ~= nil then
            return context.exec.run(command, options)
        end
        return context.exec.run(command)
    end

    if reqpack ~= nil and reqpack.exec ~= nil and type(reqpack.exec.run) == "function" then
        return reqpack.exec.run(command)
    end

    return {
        success = false,
        stdout = "",
        stderr = "missing ReqPack exec runner",
        exitCode = 127,
    }
end

local function command_exists(binary)
    local command
    if is_windows_host() then
        command = "where " .. cmd_quote(binary) .. " >nul 2>nul"
    else
        command = "command -v " .. shell_quote(binary) .. " >/dev/null 2>&1"
    end

    local result = run_exec(nil, command)
    return result ~= nil and result.success == true
end

local function build_command(parts)
    local quoted = {}

    for _, part in ipairs(parts or {}) do
        local text = trim(part)
        if text ~= "" then
            table.insert(quoted, command_quote(text))
        end
    end

    return table.concat(quoted, " ")
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

    if #parts == 0 then
        return "."
    end

    return table.concat(parts, path_separator())
end

local function parent_dir(path)
    return tostring(path or ""):match("^(.*)[/\\][^/\\]+$")
end

local function command_ok(ok, _, code)
    if ok == true then
        return true
    end

    if type(ok) == "number" then
        return ok == 0
    end

    return code == 0
end

local function ensure_directory(path)
    local dir = trim(path)
    if dir == "" or dir == "." then
        return true
    end

    if os == nil or type(os.execute) ~= "function" then
        return false
    end

    local command
    if is_windows_host() then
        command = "if not exist " .. cmd_quote(dir) .. " mkdir " .. cmd_quote(dir) .. " >nul 2>nul"
    else
        command = "mkdir -p " .. shell_quote(dir)
    end

    local ok, kind, code = os.execute(command)
    return command_ok(ok, kind, code)
end

local function read_file(path)
    local handle = io.open(path, "r")
    if handle == nil then
        return nil
    end

    local content = handle:read("*a")
    handle:close()
    return content
end

local function write_file(path, content)
    local dir = parent_dir(path)
    local tmp_path = path .. ".tmp"
    local handle = io.open(tmp_path, "w")
    if handle == nil then
        if dir ~= nil and dir ~= "" and not ensure_directory(dir) then
            return false
        end

        handle = io.open(tmp_path, "w")
    end

    if handle == nil then
        return false
    end

    handle:write(content)
    handle:close()

    if os == nil or type(os.remove) ~= "function" or type(os.rename) ~= "function" then
        local direct = io.open(path, "w")
        if direct == nil then
            return false
        end
        direct:write(content)
        direct:close()
        return true
    end

    os.remove(path)
    local ok = os.rename(tmp_path, path)
    if not ok then
        os.remove(tmp_path)
        return false
    end

    return true
end

local function object_field(object, key)
    if object == nil then
        return nil
    end

    local ok, value = pcall(function()
        return object[key]
    end)
    if ok then
        return value
    end

    return nil
end

local function object_flags(object)
    local value = object_field(object, "flags")
    if type(value) ~= "table" and type(value) ~= "userdata" then
        return {}
    end

    local flags = {}
    local ok = pcall(function()
        for _, flag in ipairs(value) do
            table.insert(flags, trim(flag))
        end
    end)

    if not ok then
        return {}
    end

    return flags
end

local function flag_value(context, prefix)
    for _, flag in ipairs((context and context.flags) or {}) do
        local text = trim(flag)
        if text:sub(1, #prefix) == prefix then
            return trim(text:sub(#prefix + 1))
        end
    end

    return ""
end

local function package_flag_value(pkg, prefix)
    for _, flag in ipairs(object_flags(pkg)) do
        local text = trim(flag)
        if text:sub(1, #prefix) == prefix then
            return trim(text:sub(#prefix + 1))
        end
    end

    return ""
end

local function package_name(pkg)
    return trim(object_field(pkg, "name") or object_field(pkg, "packageName") or object_field(pkg, "packageId"))
end

local function package_version(pkg)
    return trim(object_field(pkg, "version"))
end

local function package_kind(pkg)
    local kind = lower(trim(object_field(pkg, "packageType") or object_field(pkg, "kind") or object_field(pkg, "type")))
    if kind == "" then
        for _, flag in ipairs(object_flags(pkg)) do
            local normalized = lower(flag)
            if normalized == "packagetype=library" or normalized == "kind=library" or normalized == "type=library" then
                kind = "library"
                break
            end
        end
    end

    if kind == "library" then
        return "library"
    end
    return DEFAULT_PACKAGE_TYPE
end

local function get_plugin_dir()
    local dir = trim(_G.REQPACK_PLUGIN_DIR)
    if dir ~= "" then
        return dir
    end
    return "."
end

local function get_manifest_path(context)
    local override = flag_value(context, "manifest-path=")
    if override ~= "" then
        return override
    end

    return join_path(get_plugin_dir(), ".reqpack-data", "cargo-cache", "Cargo.toml")
end

local function get_manifest_path_for_packages(context, packages)
    for _, pkg in ipairs(packages or {}) do
        local override = package_flag_value(pkg, "manifest-path=")
        if override ~= "" then
            return override
        end
    end

    return get_manifest_path(context)
end

local function normalize_library_version(value)
    local text = trim(value)
    if text == "" then
        return "*"
    end

    if text:sub(1, 1) == "="
        or text:sub(1, 1) == "^"
        or text:sub(1, 1) == "~"
        or text:sub(1, 1) == "<"
        or text:sub(1, 1) == ">"
        or text:sub(1, 1) == "*"
        or text:find(",", 1, true) ~= nil then
        return text
    end

    return "=" .. text
end

local function display_library_version(value)
    local text = trim(value)
    if text:sub(1, 1) == "=" then
        return text:sub(2)
    end
    return text
end

local function parse_manifest_dependencies(content)
    local dependencies = {}
    local in_dependencies = false

    for _, line in ipairs(split_lines(content)) do
        local text = trim(line)

        if text:match("^%[.+%]$") then
            in_dependencies = text == "[dependencies]"
        elseif in_dependencies then
            local name, value = text:match('^([A-Za-z0-9_%-%.]+)%s*=%s*"([^"]+)"%s*$')
            if name ~= nil and value ~= nil then
                dependencies[name] = value
            end
        end
    end

    return dependencies
end

local function load_manifest_dependencies_from_path(manifest_path)
    local content = read_file(manifest_path)
    if content == nil or trim(content) == "" then
        return {}
    end

    return parse_manifest_dependencies(content)
end

local function load_manifest_dependencies(context)
    return load_manifest_dependencies_from_path(get_manifest_path(context))
end

local function sorted_keys(map)
    local keys = {}

    for key in pairs(map or {}) do
        table.insert(keys, key)
    end

    table.sort(keys)
    return keys
end

local function build_manifest_content(dependencies)
    local lines = {}

    for _, line in ipairs(MANIFEST_HEADER_LINES) do
        table.insert(lines, line)
    end

    for _, name in ipairs(sorted_keys(dependencies)) do
        table.insert(lines, string.format('%s = "%s"', name, dependencies[name]))
    end

    return table.concat(lines, "\n") .. "\n"
end

local function save_manifest_dependencies_to_path(manifest_path, dependencies)
    return write_file(manifest_path, build_manifest_content(dependencies))
end

local function save_manifest_dependencies(context, dependencies)
    return save_manifest_dependencies_to_path(get_manifest_path(context), dependencies)
end

local function cargo_command(parts)
    return build_command(parts)
end

local function cargo_list_command()
    return cargo_command({ REQUIRED_BINARY, "install", "--list", "--quiet", "--color", "never" })
end

local function cargo_search_command(prompt)
    return cargo_command({ REQUIRED_BINARY, "search", prompt, "--limit", tostring(SEARCH_LIMIT), "--quiet", "--color", "never" })
end

local function cargo_info_command(name)
    return cargo_command({ REQUIRED_BINARY, "info", name, "--quiet", "--color", "never" })
end

local function cargo_fetch_command(manifest_path)
    return cargo_command({ REQUIRED_BINARY, "fetch", "--manifest-path", manifest_path, "--quiet", "--color", "never" })
end

local function cargo_install_local_command(path)
    return cargo_command({ REQUIRED_BINARY, "install", "--path", path, "--color", "never" })
end

local function cargo_install_tool_command(pkg, force)
    local parts = { REQUIRED_BINARY, "install", "--color", "never" }
    if force then
        table.insert(parts, "--force")
    end

    local version = package_version(pkg)
    if version ~= "" then
        table.insert(parts, "--version")
        table.insert(parts, version)
    end

    table.insert(parts, package_name(pkg))
    return cargo_command(parts)
end

local function cargo_uninstall_tool_command(pkg)
    return cargo_command({ REQUIRED_BINARY, "uninstall", package_name(pkg), "--color", "never" })
end

local function cargo_progress_rules(default_step)
    local fallback = trim(default_step)
    if fallback == "" then
        fallback = "run cargo"
    end

    return {
        initial = fallback,
        rules = {
            {
                source = "line",
                regex = "^%s*Updating (.+)$",
                actions = {
                    { type = "progress", percent = "10" },
                    { type = "begin_step", label = "update ${1}" },
                },
            },
            {
                source = "line",
                regex = "^%s*Downloading (.+)$",
                actions = {
                    { type = "progress", percent = "25" },
                    { type = "begin_step", label = "download ${1}" },
                },
            },
            {
                source = "line",
                regex = "^%s*Installing (.+)%s+v([^%s]+).*$",
                actions = {
                    { type = "progress", percent = "70" },
                    { type = "begin_step", label = "install ${1} ${2}" },
                },
            },
            {
                source = "line",
                regex = "^%s*Replacing (.+)%s+v([^%s]+).*$",
                actions = {
                    { type = "progress", percent = "70" },
                    { type = "begin_step", label = "replace ${1} ${2}" },
                },
            },
            {
                source = "line",
                regex = "^%s*Removing (.+)%s+v([^%s]+).*$",
                actions = {
                    { type = "progress", percent = "70" },
                    { type = "begin_step", label = "remove ${1} ${2}" },
                },
            },
            {
                source = "line",
                regex = "^%s*Uninstalling (.+)%s+v([^%s]+).*$",
                actions = {
                    { type = "progress", percent = "70" },
                    { type = "begin_step", label = "uninstall ${1} ${2}" },
                },
            },
            {
                source = "line",
                regex = "^%s*Downloaded (.+)$",
                actions = {
                    { type = "progress", percent = "90" },
                    { type = "begin_step", label = "downloaded ${1}" },
                },
            },
            {
                source = "line",
                regex = "^warning:%s+(.+)$",
                actions = {
                    { type = "log", level = "warn", message = "${1}" },
                },
            },
            {
                source = "line",
                regex = "^error:%s+(.+)$",
                actions = {
                    { type = "log", level = "error", message = "${1}" },
                },
            },
        },
    }
end

local function parse_tool_list_output(stdout)
    local items = {}

    for _, line in ipairs(split_lines(stdout)) do
        local text = trim(line)
        local name, version = text:match("^([^%s]+)%s+v([^%s:]+).-:%s*$")

        if name ~= nil and version ~= nil then
            table.insert(items, {
                name = name,
                packageId = name,
                version = version,
                installed = true,
                status = "installed",
                type = "package",
                packageType = "tool",
            })
        end
    end

    return items
end

local function parse_search_output(stdout)
    local items = {}

    for _, line in ipairs(split_lines(stdout)) do
        local text = trim(line)
        local name, version, summary = text:match('^([A-Za-z0-9_%-%.]+)%s*=%s*"([^"]+)"%s*#%s*(.+)$')

        if name ~= nil and version ~= nil then
            table.insert(items, {
                name = name,
                packageId = name,
                version = version,
                summary = trim(summary),
                description = trim(summary),
                type = "package",
                packageType = DEFAULT_PACKAGE_TYPE,
            })
        end
    end

    return items
end

local function parse_info_output(stdout)
    local lines = {}

    for _, line in ipairs(split_lines(stdout)) do
        local text = trim(line)
        if text ~= "" then
            table.insert(lines, text)
        end
    end

    if #lines == 0 then
        return {}
    end

    local first_line = lines[1]
    local name = trim(first_line:match("^(%S+)") or "")
    if name == "" then
        return {}
    end

    local item = {
        name = name,
        packageId = name,
        type = "package",
        packageType = DEFAULT_PACKAGE_TYPE,
    }

    local tags = {}
    for tag in first_line:gmatch("#([^%s#]+)") do
        table.insert(tags, tag)
    end
    if #tags > 0 then
        item.tags = tags
    end

    local start_index = 2
    if lines[2] ~= nil and lines[2]:match("^[%w%-%.]+:%s*") == nil then
        item.summary = lines[2]
        item.description = lines[2]
        start_index = 3
    end

    for index = start_index, #lines do
        local key, value = lines[index]:match("^([%w%-%.]+):%s*(.*)$")
        if key == nil then
            break
        end

        local normalized_key = lower(trim(key))
        local normalized_value = trim(value)

        if normalized_key == "version" then
            item.version = normalized_value
        elseif normalized_key == "license" then
            item.license = normalized_value
        elseif normalized_key == "homepage" then
            item.homepage = normalized_value
        elseif normalized_key == "repository" then
            item.repository = normalized_value
        elseif normalized_key == "documentation" then
            item.documentation = normalized_value
        elseif normalized_key == "rust-version" then
            item.rustVersion = normalized_value
        elseif normalized_key == "crates.io" then
            item.registryUrl = normalized_value
        end
    end

    return item
end

local function manifest_items_from_dependencies(dependencies)
    local items = {}

    for _, name in ipairs(sorted_keys(dependencies)) do
        table.insert(items, {
            name = name,
            packageId = name,
            version = display_library_version(dependencies[name]),
            installed = true,
            status = "installed",
            type = "package",
            packageType = "library",
        })
    end

    return items
end

local function sort_items_by_name(items)
    table.sort(items, function(left, right)
        local left_name = trim(left and left.name)
        local right_name = trim(right and right.name)
        if left_name == right_name then
            return trim(left and left.packageType) < trim(right and right.packageType)
        end
        return left_name < right_name
    end)
end

local function load_installed_tool_lookup(context)
    local result = run_exec(context, cargo_list_command())
    if result == nil or result.success ~= true then
        if context ~= nil then
            log_error(context, "cargo tool list failed")
        end
        return {}, false
    end

    local lookup = {}
    for _, item in ipairs(parse_tool_list_output(result.stdout)) do
        lookup[item.name] = item.version
    end

    return lookup, true
end

local function is_not_found_result(result)
    local text = lower((result and result.stderr) or "") .. "\n" .. lower((result and result.stdout) or "")
    return text:find("could not find", 1, true) ~= nil
        or text:find("no packages found", 1, true) ~= nil
        or text:find("is not installed", 1, true) ~= nil
end

local function lookup_package_info(context, name)
    local result = run_exec(context, cargo_info_command(name))
    if result ~= nil and result.success == true then
        return parse_info_output(result.stdout)
    end

    if not is_not_found_result(result) then
        log_error(context, "cargo info failed for " .. name)
    end

    return {}
end

local function info_matches_request(pkg, item)
    if item == nil or trim(item.name) == "" then
        return false
    end

    local name = package_name(pkg)
    local version = package_version(pkg)

    if name ~= "" and trim(item.name) ~= name then
        return false
    end

    if version ~= "" and trim(item.version) ~= version then
        return false
    end

    return true
end

local function filter_packages_by_kind(packages, kind)
    local filtered = {}

    for _, pkg in ipairs(packages or {}) do
        if package_kind(pkg) == kind and package_name(pkg) ~= "" then
            table.insert(filtered, pkg)
        end
    end

    return filtered
end

local function apply_library_dependencies(context, packages, mode)
    local dependencies = load_manifest_dependencies_from_path(get_manifest_path_for_packages(context, packages))

    for _, pkg in ipairs(packages or {}) do
        local name = package_name(pkg)
        if name ~= "" then
            if mode == "remove" then
                dependencies[name] = nil
            else
                dependencies[name] = normalize_library_version(package_version(pkg))
            end
        end
    end

    return dependencies
end

local function ensure_library_state(context, packages)
    local dependencies = apply_library_dependencies(context, packages, "install")
    local manifest_path = get_manifest_path_for_packages(context, packages)

    if not save_manifest_dependencies_to_path(manifest_path, dependencies) then
        log_error(context, "cargo library manifest write failed")
        return false
    end

    local result = run_exec(context, cargo_fetch_command(manifest_path), cargo_progress_rules("fetch cargo libraries"))
    if result == nil or result.success ~= true then
        tx_failed(context, "cargo library fetch failed")
        return false
    end

    return true
end

local function update_library_state(context, packages)
    local dependencies = apply_library_dependencies(context, packages, "update")
    local manifest_path = get_manifest_path_for_packages(context, packages)

    if not save_manifest_dependencies_to_path(manifest_path, dependencies) then
        log_error(context, "cargo library manifest write failed")
        return false
    end

    local result = run_exec(context, cargo_fetch_command(manifest_path), cargo_progress_rules("refresh cargo libraries"))
    if result == nil or result.success ~= true then
        tx_failed(context, "cargo library fetch failed")
        return false
    end

    return true
end

local function remove_library_state(context, packages)
    local dependencies = apply_library_dependencies(context, packages, "remove")
    local manifest_path = get_manifest_path_for_packages(context, packages)

    if not save_manifest_dependencies_to_path(manifest_path, dependencies) then
        log_error(context, "cargo library manifest write failed")
        return false
    end

    return true
end

local function install_tool_packages(context, packages)
    local installed_lookup, lookup_ok = load_installed_tool_lookup(context)

    for _, pkg in ipairs(packages or {}) do
        local name = package_name(pkg)
        local version = package_version(pkg)
        local installed_version = installed_lookup[name]

        if name ~= "" then
            local needs_force = false
            if version ~= "" and installed_version ~= nil and installed_version ~= version then
                needs_force = true
            elseif lookup_ok and ((version == "" and installed_version ~= nil) or installed_version == version) then
                needs_force = nil
            end

            if needs_force ~= nil then
                local result = run_exec(context, cargo_install_tool_command(pkg, needs_force == true), cargo_progress_rules("install cargo tool"))
                if result == nil or result.success ~= true then
                    tx_failed(context, "cargo tool install failed")
                    return false
                end
            end
        end
    end

    return true
end

local function update_tool_packages(context, packages)
    for _, pkg in ipairs(packages or {}) do
        if package_name(pkg) ~= "" then
            local result = run_exec(context, cargo_install_tool_command(pkg, true), cargo_progress_rules("update cargo tool"))
            if result == nil or result.success ~= true then
                tx_failed(context, "cargo tool update failed")
                return false
            end
        end
    end

    return true
end

local function remove_tool_packages(context, packages)
    local installed_lookup, lookup_ok = load_installed_tool_lookup(context)

    for _, pkg in ipairs(packages or {}) do
        local name = package_name(pkg)
        if name ~= "" then
            if not lookup_ok or installed_lookup[name] ~= nil then
                local result = run_exec(context, cargo_uninstall_tool_command(pkg), cargo_progress_rules("remove cargo tool"))
                if result == nil or result.success ~= true then
                    tx_failed(context, "cargo tool remove failed")
                    return false
                end
            end
        end
    end

    return true
end

plugin.fileExtensions = {}

function plugin.getName()
    return PLUGIN_NAME
end

function plugin.getVersion()
    return PLUGIN_VERSION
end

function plugin.getRequirements()
    return {}
end

function plugin.getCategories()
    return { "Cross Platform", "Rust", "Package Manager" }
end

function plugin.getMissingPackages(packages)
    local missing = {}
    local manifest_dependencies = load_manifest_dependencies(nil)
    local installed_tools, tools_known = load_installed_tool_lookup(nil)

    for _, pkg in ipairs(packages or {}) do
        local name = package_name(pkg)
        local version = package_version(pkg)
        local action = trim(object_field(pkg, "action"))
        local kind = package_kind(pkg)

        if name ~= "" then
            if kind == "library" then
                local stored_value = manifest_dependencies[name]
                if action == "remove" then
                    if stored_value ~= nil then
                        table.insert(missing, pkg)
                    end
                elseif action == "update" then
                    table.insert(missing, pkg)
                elseif stored_value == nil then
                    table.insert(missing, pkg)
                elseif version ~= "" and stored_value ~= normalize_library_version(version) then
                    table.insert(missing, pkg)
                end
            else
                local installed_version = installed_tools[name]
                if action == "remove" then
                    if not tools_known or installed_version ~= nil then
                        table.insert(missing, pkg)
                    end
                elseif action == "update" then
                    table.insert(missing, pkg)
                elseif not tools_known then
                    table.insert(missing, pkg)
                elseif installed_version == nil then
                    table.insert(missing, pkg)
                elseif version ~= "" and installed_version ~= version then
                    table.insert(missing, pkg)
                end
            end
        end
    end

    return missing
end

function plugin.install(context, packages)
    local tool_packages = filter_packages_by_kind(packages, "tool")
    local library_packages = filter_packages_by_kind(packages, "library")

    if #tool_packages == 0 and #library_packages == 0 then
        return true
    end

    if #tool_packages > 0 then
        begin_step(context, "install cargo tools")
        if not install_tool_packages(context, tool_packages) then
            return false
        end
    end

    if #library_packages > 0 then
        begin_step(context, "cache cargo libraries")
        if not ensure_library_state(context, library_packages) then
            return false
        end
    end

    emit_event(context, "installed", packages or {})
    tx_success(context)
    return true
end

function plugin.installLocal(context, path)
    local local_path = trim(path)
    if local_path == "" then
        tx_failed(context, "cargo local install failed")
        return false
    end

    begin_step(context, "install local cargo crate")
    local result = run_exec(context, cargo_install_local_command(local_path), cargo_progress_rules("install local cargo crate"))
    if result == nil or result.success ~= true then
        tx_failed(context, "cargo local install failed")
        return false
    end

    emit_event(context, "installed", { path = local_path, localTarget = true })
    tx_success(context)
    return true
end

function plugin.remove(context, packages)
    local tool_packages = filter_packages_by_kind(packages, "tool")
    local library_packages = filter_packages_by_kind(packages, "library")

    if #tool_packages == 0 and #library_packages == 0 then
        return true
    end

    if #tool_packages > 0 then
        begin_step(context, "remove cargo tools")
        if not remove_tool_packages(context, tool_packages) then
            return false
        end
    end

    if #library_packages > 0 then
        begin_step(context, "remove cached cargo libraries")
        if not remove_library_state(context, library_packages) then
            tx_failed(context, "cargo library remove failed")
            return false
        end
    end

    emit_event(context, "deleted", packages or {})
    tx_success(context)
    return true
end

function plugin.update(context, packages)
    local tool_packages = filter_packages_by_kind(packages, "tool")
    local library_packages = filter_packages_by_kind(packages, "library")

    if #tool_packages == 0 and #library_packages == 0 then
        return true
    end

    if #tool_packages > 0 then
        begin_step(context, "update cargo tools")
        if not update_tool_packages(context, tool_packages) then
            return false
        end
    end

    if #library_packages > 0 then
        begin_step(context, "refresh cached cargo libraries")
        if not update_library_state(context, library_packages) then
            return false
        end
    end

    emit_event(context, "updated", packages or {})
    tx_success(context)
    return true
end

function plugin.list(context)
    local items = {}
    local tool_result = run_exec(context, cargo_list_command())

    if tool_result ~= nil and tool_result.success == true then
        for _, item in ipairs(parse_tool_list_output(tool_result.stdout)) do
            table.insert(items, item)
        end
    else
        log_error(context, "cargo tool list failed")
    end

    for _, item in ipairs(manifest_items_from_dependencies(load_manifest_dependencies(context))) do
        table.insert(items, item)
    end

    sort_items_by_name(items)
    emit_event(context, "listed", items)
    return items
end

function plugin.search(context, prompt)
    local search_prompt = trim(prompt)
    if search_prompt == "" then
        local empty = {}
        emit_event(context, "searched", empty)
        return empty
    end

    local items = {}
    local result = run_exec(context, cargo_search_command(search_prompt))
    if result ~= nil and result.success == true then
        items = parse_search_output(result.stdout)
    elseif not is_not_found_result(result) then
        log_error(context, "cargo search failed for " .. search_prompt)
    end

    emit_event(context, "searched", items)
    return items
end

function plugin.info(context, name)
    local package_name_value = trim(name)
    local item = {}

    if package_name_value ~= "" then
        item = lookup_package_info(context, package_name_value)
    end

    emit_event(context, "informed", item)
    return item
end

function plugin.outdated(context)
    local items = {}
    emit_event(context, "outdated", items)
    return items
end

function plugin.resolvePackage(context, package)
    local name = package_name(package)
    if name == "" then
        return nil
    end

    local item = lookup_package_info(context, name)
    if info_matches_request(package, item) then
        item.packageType = package_kind(package)
        return item
    end

    if trim(item.name) ~= "" then
        return {
            name = item.name,
            packageId = item.packageId,
            version = item.version,
            license = item.license,
            homepage = item.homepage,
            repository = item.repository,
            documentation = item.documentation,
            rustVersion = item.rustVersion,
            type = item.type,
            packageType = package_kind(package),
        }
    end

    return nil
end

function plugin.getSecurityMetadata()
    return {
        role = "package-manager",
        capabilities = { "exec" },
        ecosystemScopes = { "cargo", "crates.io", "rust" },
        privilegeLevel = "user",
        osvEcosystem = "crates.io",
        purlType = "cargo",
        versionCaseInsensitive = false,
    }
end

function plugin.init()
    return command_exists(REQUIRED_BINARY)
end

function plugin.shutdown()
    return true
end

return plugin
