return {
  name = "cargo tool update",
  request = {
    action = "update",
    system = "nosys",
    packages = {
      { name = "ripgrep", version = "14.1.1", packageType = "tool" }
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
      match = "cargo install --color never --force --version 14.1.1 ripgrep",
      exitCode = 0,
      stdout = "update ok\n",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    commands = {
      "cargo install --color never --force --version 14.1.1 ripgrep"
    },
    stdout = {
      "update ok\n"
    },
    events = { "updated", "success" },
  }
}
