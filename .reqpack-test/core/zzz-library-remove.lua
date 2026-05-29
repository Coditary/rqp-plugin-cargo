return {
  name = "cargo library remove",
  request = {
    action = "remove",
    system = "nosys",
    packages = {
      { name = "serde", flags = { "packageType=library", "manifest-path=${fixtureRoot}/.reqpack-data/cargo-cache/Cargo.toml" } }
    },
  },
  fixtureDirs = {
    ".reqpack-data/cargo-cache",
  },
  fixtureFiles = {
    {
      path = ".reqpack-data/cargo-cache/Cargo.toml",
      content = "[package]\nname = \"reqpack-cargo-cache\"\nversion = \"0.0.0\"\nedition = \"2021\"\n\n[dependencies]\nserde = \"=1.0.228\"\n",
    },
  },
  fakeExec = {
    {
      match = "command -v cargo >/dev/null 2>&1",
      exitCode = 0,
      stdout = "",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "deleted", "success" },
  }
}
