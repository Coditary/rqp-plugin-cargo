return {
  name = "cargo list",
  request = {
    action = "list",
    system = "nosys",
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
      match = "cargo install --list --quiet --color never",
      exitCode = 0,
      stdout = "exa v0.10.1:\n    exa\neza v0.23.4:\n    eza\n",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "listed" },
    resultCount = 2,
    resultName = "exa",
    resultVersion = "0.10.1",
  }
}
