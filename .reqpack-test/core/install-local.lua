return {
  name = "cargo install local",
  request = {
    action = "install",
    system = "nosys",
    localPath = "/tmp/ripgrep",
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
      match = "cargo install --path /tmp/ripgrep --color never",
      exitCode = 0,
      stdout = "local install ok\n",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "installed", "success" },
    eventPayloads = {
      installed = "{localTarget=true, path=/tmp/ripgrep}",
    },
  }
}
