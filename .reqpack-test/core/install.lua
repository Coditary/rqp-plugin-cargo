return {
  name = "cargo tool install",
  request = {
    action = "install",
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
      match = "cargo install --list --quiet --color never",
      exitCode = 0,
      stdout = "",
      stderr = "",
      success = true,
    },
    {
      match = "cargo install --color never --version 14.1.1 ripgrep",
      exitCode = 0,
      stdout = "install ok\n",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    commands = {
      "cargo install --list --quiet --color never",
      "cargo install --color never --version 14.1.1 ripgrep"
    },
    stdout = {
      "install ok\n"
    },
    events = { "installed", "success" },
  }
}
