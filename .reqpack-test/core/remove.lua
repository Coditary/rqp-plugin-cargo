return {
  name = "cargo tool remove",
  request = {
    action = "remove",
    system = "nosys",
    packages = {
      { name = "ripgrep", packageType = "tool" }
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
    {
      match = "cargo install --list --quiet --color never",
      exitCode = 0,
      stdout = "ripgrep v14.1.1:\n    rg\n",
      stderr = "",
      success = true,
    },
    {
      match = "cargo uninstall ripgrep --color never",
      exitCode = 0,
      stdout = "remove ok\n",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    commands = {
      "cargo install --list --quiet --color never",
      "cargo uninstall ripgrep --color never"
    },
    stdout = {
      "ripgrep v14.1.1:\n    rg\n",
      "remove ok\n"
    },
    events = { "deleted", "success" },
  }
}
