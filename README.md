# reqpack-plugin-template-wrapper

GitHub template for new ReqPack wrapper plugins.

It ships a tiny no-op bundle skeleton that shows where plugin metadata, runtime code, install/remove hook stubs, and plugin tests belong.
Template is meant to be copied, renamed, then filled in with real package-manager logic.

## Included Files

- `metadata.json`: plugin id and bundle metadata
- `reqpack.lua`: plugin bundle manifest with `apiVersion` and `depends`
- `run.lua`: full wrapper skeleton with common entry points
- `scripts/install.lua`: package install hook stub required by bundle format
- `scripts/remove.lua`: package remove hook stub required by bundle format
- `API.md`: fuller runtime and testing reference based on `ReqPack.wiki`
- `.reqpack-test/core/*.lua`: starter conformance cases for core wrapper paths

## Five-Minute Conversion Path

1. Create a new repository from this template.
2. Edit `metadata.json` so `name` matches your plugin id.
3. Read `API.md` once.
4. Replace placeholder metadata in `run.lua` methods such as `getName()`, `getVersion()`, and `getCategories()`.
5. Replace all `template` placeholders in `.reqpack-test/core/*.lua`.
6. Add real package-manager logic to `getMissingPackages`, `install`, `installLocal`, `remove`, `update`, `list`, `search`, `info`, and `outdated`.
7. Add binary/tool check in `plugin.init()` if wrapper needs one.
8. Run `rqp test-plugin --plugin . --preset core` from template root.

## Recommended Workflow

For most wrapper plugins, this repository already contains enough to start.
Use full ReqPack wiki only when a runtime detail is still unclear.

Work in this order:

1. Edit `metadata.json` first.
2. Replace all `template` placeholders.
3. Add package-manager existence check in `plugin.init()`.
4. Add plugin dependencies to `reqpack.lua` `depends` if your wrapper needs other ReqPack systems.
5. Implement wrapper methods.
6. Update `.reqpack-test/core/*.lua`.
   If `init()` runs commands, add matching `fakeExec` rules in tests.
7. Run `rqp test-plugin --plugin . --preset core` from template root.

## File Guide

Read `API.md` before filling in real behavior.
It explains lifecycle timing, `context`, `reqpack.*`, exec results, optional hooks, and test-case anatomy.

### `run.lua`

Main wrapper file.

Important sections:

- helper functions at top for small reusable utilities
- metadata methods for plugin name, version, requirements, categories
- command methods for install/remove/update/list/search/info
- lifecycle methods `init()` and `shutdown()`

Important lifecycle note:

- `run.lua` executes before `plugin.init()`
- ReqPack may read `getName()`, `getVersion()`, `getSecurityMetadata()`, and `plugin.fileExtensions` before `init()`

Shipped implementation is intentionally empty.
It returns safe defaults and emits example events so test cases show expected result shapes.

### `metadata.json`

Bundle metadata.

- `name` is plugin id used for discovery
- `version` is bundle version
- `summary`, `description`, and `license` are required

### `reqpack.lua`

Bundle manifest.

- keep `apiVersion = 1`
- declare plugin dependencies in `depends = { "sys:java" }` style when needed

### `scripts/install.lua` and `scripts/remove.lua`

Required bundle hook files.

Wrapper plugins usually keep these as tiny `return true` stubs.
ReqPack requires them for bundle validity even when wrapper logic lives in `run.lua`.

### `.reqpack-test/core/*.lua`

Hermetic plugin tests.

Template ships starter cases for:

- `install`
- `installLocal`
- `remove`
- `update`
- `list`
- `search`
- `info`
- `outdated`

They show how ReqPack test cases are structured:

- `request`
- `fakeExec`
- `expect`

`fakeExec` rules use substring matching.
If no rule matches executed command, test runner returns failure with `exitCode = 127`.

## Running Plugin Tests

From template root, run:

```bash
rqp test-plugin --plugin . --preset core
```

Or point at bundle directory from parent directory:

```bash
rqp test-plugin --plugin ./your-plugin-dir --preset core
```

You can also run one case directly:

```bash
rqp test-plugin --plugin . --case ./.reqpack-test/core/info.lua
```

## CI

Template repo validates itself in GitHub Actions.

- Linux amd64 and arm64 jobs use Podman with published `ghcr.io/coditary/reqpack:<tag>` runtime.
- macOS arm64 job downloads published Darwin release bundle and runs it natively.
- CI checks direct bundle-directory execution and copied bundle-directory execution.

Copied-bundle test matters because template should still work after repository rename and plugin-id replacement, not only while living in original template directory.

If template starts depending on newer ReqPack runtime behavior, update workflow variable `REQPACK_RUNTIME_TAG`.

## Read Next

- `API.md`: fuller runtime and testing reference
- `ReqPack.wiki/Extending-Writing-Lua-Plugins.md`: source-backed engine contract
- `ReqPack.wiki/Extending-Testing-Lua-Plugins.md`: deeper `rqp test-plugin` reference

## Notes

- Keep comments short.
- Prefer small helper functions over repeated shell string building.
- Emit `context.events.*` when returning package information so ReqPack can record useful results.
- Once plugin does real work, update tests before expanding behavior.
