return {
  name = "cargo library install",
  request = {
    action = "install",
    system = "nosys",
    packages = {
      { name = "serde", version = "1.0.228", flags = { "packageType=library", "manifest-path=${fixtureRoot}/.reqpack-data/cargo-cache/Cargo.toml" } }
    },
  },
  fixtureDirs = {
    ".reqpack-data/cargo-cache",
  },
  fakeExec = {
    {
      match = "command -v cargo >/dev/null 2>&1",
      exitCode = 0,
      stdout = "",
      stderr = "",
      success = true,
    },
    {
      match = "cargo fetch --manifest-path ${fixtureRoot}/.reqpack-data/cargo-cache/Cargo.toml --quiet --color never",
      exitCode = 0,
      stdout = "Downloaded serde v1.0.228\n",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    stdout = {
      "Downloaded serde v1.0.228\n"
    },
    events = { "installed", "success" },
  }
}
