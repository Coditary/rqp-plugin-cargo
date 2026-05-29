# Cargo Nosys Wrapper Design

## Goal

Turn template repository into ReqPack Lua wrapper plugin for Cargo.
Plugin is addressed through ReqPack system id `nosys`, not `cargo`.
Reason: Cargo itself is cross-platform host tooling that must first be installed on any supported system.

Plugin must support two Cargo-backed use cases:

- global Rust CLI tools installed through `cargo install`
- Rust library dependency cache warming so snapshot restore on another machine can pre-download crates before later project builds

Library support is intentionally cache-oriented.
It does not edit a real project `Cargo.toml`.

## Scope

In scope:

- plugin metadata and bundle manifest updates
- ReqPack host dependency declaration so Cargo is installed through `sys`
- `run.lua` implementation for required ReqPack methods
- support for package kinds `tool` and `library`
- local crate installation through `cargo install --path`
- plugin-owned synthetic Cargo manifest for library cache warming
- hermetic `.reqpack-test/core/` cases updated to Cargo behavior
- README updated from template wording to Cargo/Nosys plugin wording
- optional `outdated()`, `resolvePackage()`, and `getSecurityMetadata()` when behavior is deterministic

Out of scope:

- editing arbitrary project `Cargo.toml` files
- running `cargo add` or `cargo remove` against user projects
- precompiling dependencies for targets or profiles
- cleaning Cargo global cache on library removal
- advanced registry authentication workflows beyond delegating to installed Cargo
- automatic latest-version resolution beyond what stable Cargo CLI exposes reliably for this wrapper

## Design Choice

Use thin shell-wrapper design in one main `run.lua` file with small helpers.
Wrapper delegates real package operations to native Cargo commands and only keeps minimal extra state for library cache warming.

Chosen shape:

- ReqPack plugin id: `nosys`
- human-facing plugin name: `Cargo`
- bundle dependency in `reqpack.lua`: `depends = { "sys:cargo" }`
- package kinds:
  - `tool`: global install/remove/update through `cargo install` and `cargo uninstall`
  - `library`: plugin-managed synthetic manifest plus `cargo fetch --manifest-path ...`

This gives one wrapper that can restore both Cargo CLI tools and crate download cache from ReqPack snapshots without requiring a checked-out Rust project.

## Metadata And Bundle

### `metadata.json`

- `name` becomes `nosys`
- `summary` and `description` describe cross-platform Cargo wrapper behavior
- bundle version stays `0.1.0` for first implementation

### `reqpack.lua`

- keep `apiVersion = 1`
- set `depends = { "sys:cargo" }`

This means ReqPack can ensure host package manager support installs Cargo before the wrapper starts using it.

## Runtime Behavior

### Initialization

- `plugin.init()` checks `command -v cargo >/dev/null 2>&1`
- plugin assumes Cargo should already exist after ReqPack resolves `sys:cargo`
- init stays a simple availability check only

### Categories And File Extensions

- `plugin.getCategories()` returns cross-platform Rust package-manager categories
- `plugin.fileExtensions` includes no special local artifact extensions because Cargo local install support uses crate directory paths, not package archives

### Package Kind Rules

Package records may include `packageType`.
Supported values:

- `tool`
- `library`

If field is missing, wrapper defaults to `tool`.
This keeps generic ReqPack requests ergonomic while allowing snapshot data to distinguish CLI tools from library cache entries.

### Tool Packages

Tool packages represent globally installed Cargo binaries.

Commands:

- install: `cargo install <name>` or `cargo install <name> --version <version>`
- remove: `cargo uninstall <name>`
- update: `cargo install --force <name>` or `cargo install --force <name> --version <version>`
- list: `cargo install --list`
- search: `cargo search <prompt> --limit 20`
- info: `cargo info <name>`

`getMissingPackages()` for tools compares requested names against parsed `cargo install --list` output.

### Library Packages

Library packages represent crate downloads that should already be present in Cargo cache on a restored machine.

Wrapper does not mutate a real project manifest.
Instead it manages a synthetic manifest owned by plugin itself, then uses `cargo fetch` against that manifest.

Manifest location:

- `REQPACK_PLUGIN_DIR/.reqpack-data/cargo-cache/Cargo.toml`

Manifest shape:

- minimal `[package]` section with stable placeholder package name and edition
- `[dependencies]` section populated from ReqPack package list

Library actions:

- install: add dependency entry to synthetic manifest, then run `cargo fetch --manifest-path <manifest>`
- update: rewrite dependency entry to requested version, then run `cargo fetch --manifest-path <manifest>`
- remove: remove dependency entry from synthetic manifest
- list: return dependencies currently tracked in synthetic manifest
- search: `cargo search <prompt> --limit 20`
- info: `cargo info <name>`

Library remove does not try to purge Cargo global cache.
It only removes desired state from plugin-managed manifest.

### Local Install

`installLocal(context, path)` installs a local crate path as tool:

- command: `cargo install --path <path>`

This path is treated as local binary/tool installation, not library caching.

### Combined List Behavior

`plugin.list(context)` returns merged items from:

- globally installed Cargo tools parsed from `cargo install --list`
- tracked library dependencies parsed from synthetic manifest

Returned records include `packageType` so future snapshots preserve distinction.

### Search And Info

`search()` and `info()` are registry-oriented and shared by both package kinds.

- `search()` parses `cargo search` lines like `<name> = "<version>" # <summary>`
- `info()` parses `cargo info <name>` human-readable metadata

When Cargo cannot find package metadata, wrapper returns empty results instead of failing entire query path.

### Outdated

`outdated()` returns empty array in v1.

Reason:

- Cargo stable CLI does not provide one simple deterministic command that covers both installed tools and synthetic library manifest state for this wrapper
- returning empty result is better than misleading or expensive heuristics

## Planning: `getMissingPackages(packages)`

Planner should reduce unnecessary work.

Rules:

- tool install: missing only when tool name absent from installed-tool list
- tool remove: missing only when tool name present in installed-tool list
- tool update: always treat as missing so explicit update request runs
- library install: missing only when dependency entry absent from synthetic manifest or requested version differs
- library remove: missing only when dependency entry exists in synthetic manifest
- library update: always treat as missing so manifest rewrite and fetch run
- unknown or empty names are ignored

This keeps planning simple and deterministic without trying to infer registry latest versions.

## Synthetic Manifest Details

Synthetic manifest is plugin-owned state, not user project state.

Proposed content shape:

```toml
[package]
name = "reqpack-cargo-cache"
version = "0.0.0"
edition = "2021"

[dependencies]
serde = "1.0.228"
tokio = "*"
```

Rules:

- explicit ReqPack version becomes exact dependency string written by wrapper
- missing ReqPack version becomes `"*"`
- package names must be preserved exactly as provided after trimming
- entries sorted alphabetically when writing to keep diffs and tests deterministic

Wrapper may create parent directory on demand.

## Parsing Strategy

Parsing stays conservative and line-oriented.

- `cargo install --list`:
  - package header lines like `exa v0.10.1:` become tool entries
  - indented binary lines are ignored for package identity
- `cargo search`:
  - parse name, version, summary from first line format Cargo emits
- `cargo info`:
  - parse simple `key: value` fields such as version, license, homepage, repository, documentation, rust-version
  - collect tags from first heading line when present
- synthetic manifest:
  - wrapper uses minimal deterministic TOML writing and only parses subset it owns
  - parser only needs `[dependencies]` entries of form `name = "value"`

Ignore lines that do not match expected formats.
Prefer partially filled package info tables over brittle parsing.

## Error Handling

- mutating methods call `context.tx.begin_step(...)` before work when meaningful
- command failures call `context.tx.failed(...)` and return `false`
- query methods return empty results on not-found or unsupported cases
- empty package arrays short-circuit successfully for mutating operations
- malformed synthetic manifest state should be treated as plugin error and logged clearly
- manifest write path should be atomic enough for deterministic tests: write full desired contents in one pass

## Security Metadata

`plugin.getSecurityMetadata()` should describe wrapper as:

- `role = "package-manager"`
- `capabilities = { "exec" }`
- `ecosystemScopes = { "cargo", "crates.io", "rust" }`
- `privilegeLevel = "user"`
- `osvEcosystem = "crates.io"`
- `purlType = "cargo"`
- version handling remains case-sensitive

No direct network capability is declared beyond Cargo execution because wrapper delegates remote access to Cargo CLI.

## Tests

Update `.reqpack-test/core/` from template placeholders to Cargo/Nosys behavior.

Core cases:

- `install.lua`: tool install expects `cargo install ...`
- `install-local.lua`: local tool install expects `cargo install --path ...`
- `remove.lua`: tool remove expects `cargo uninstall ...`
- `update.lua`: tool update expects `cargo install --force ...`
- `list.lua`: parse `cargo install --list` output
- `search.lua`: parse `cargo search ... --limit 20` output
- `info.lua`: parse `cargo info ...` output
- `outdated.lua`: returns empty result deterministically

Add library-focused hermetic cases if template structure allows new files without breaking preset expectations:

- library install writes synthetic manifest state and runs `cargo fetch --manifest-path ...`
- library remove rewrites manifest without removed dependency
- combined list includes both tool and library entries

If core preset must stay fixed to existing filenames only, library behavior should still be covered by at least one existing install/list/remove case using `packageType = "library"`.

If tests execute `plugin.init()`, each case must include fake exec rule for:

- `command -v cargo >/dev/null 2>&1`

## README

README should describe:

- plugin id `nosys`
- host dependency on `sys:cargo`
- supported package kinds `tool` and `library`
- library semantics as Cargo cache warming, not project manifest editing
- local crate path install support
- test command from plugin root

## Success Criteria

Implementation is complete when:

- template placeholders are removed from metadata, README, code, and tests
- bundle metadata uses `nosys` and `sys:cargo`
- tool flows work through Cargo CLI commands
- library flows maintain synthetic manifest and prefetch crates with `cargo fetch`
- list/search/info behavior is deterministic and test-covered
- snapshot restore can represent both Cargo tools and cached library dependencies without requiring a user project checkout
