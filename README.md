# reqpack-plugin-cargo

ReqPack Lua wrapper plugin for Cargo.

ReqPack system id is `nosys`.
Cargo itself is treated as host tooling and is pulled in through plugin dependency `sys:cargo`.

## Supported Package Kinds

- `tool`: global Cargo CLI tools installed with `cargo install`
- `library`: Rust crate dependencies tracked in plugin-owned synthetic manifest and prefetched with `cargo fetch`

Library support is cache warming only.
Plugin does not edit real project `Cargo.toml` files.

## Supported Operations

- install Cargo tools with `cargo install`
- install local crate paths with `cargo install --path`
- remove Cargo tools with `cargo uninstall`
- update Cargo tools with `cargo install --force`
- prefetch library dependencies with `cargo fetch --manifest-path ...`
- list installed Cargo tools plus tracked cached libraries
- search crates with `cargo search`
- inspect crate metadata with `cargo info`
- return empty deterministic result for outdated checks

## Dependency Bootstrap

Plugin bundle declares:

```lua
return {
  apiVersion = 1,
  depends = { "sys:cargo" }
}
```

That lets ReqPack install Cargo first through host system package-manager support.

## Request Semantics

ReqPack requests must target system `nosys`.

Example shape:

```lua
packages = {
  { name = "ripgrep", version = "14.1.1", packageType = "tool" },
  { name = "serde", version = "1.0.228", packageType = "library" },
}
```

If `packageType` is omitted, plugin defaults to `tool`.

## Synthetic Library Manifest

Tracked libraries are written to:

```text
.reqpack-data/cargo-cache/Cargo.toml
```

This file is plugin-owned state and ignored by git.

## Testing

Run plugin conformance tests from repository root:

```bash
rqp test-plugin --plugin ./run.lua --preset core
```

Run one case directly:

```bash
rqp test-plugin --plugin ./run.lua --case ./.reqpack-test/core/info.lua
```

Run local helper checks:

```bash
lua ./.reqpack-test/local/verify-library-manifest.lua
```

Additional core coverage exists for library install/remove behavior using isolated synthetic manifest paths.

## Notes

- `plugin.init()` verifies Cargo with `command -v cargo` on Unix-like hosts and `where cargo` on Windows
- `outdated()` stays empty in v1 because Cargo has no simple stable command for both tool and library states here
- `list()` merges installed tools and cached library dependencies
- security metadata uses `purlType = "cargo"` and `osvEcosystem = "crates.io"`
