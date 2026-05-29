return {
  name = "cargo search",
  request = {
    action = "search",
    system = "nosys",
    prompt = "serde",
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
      match = "cargo search serde --limit 20 --quiet --color never",
      exitCode = 0,
      stdout = "serde = \"1.0.228\"          # A generic serialization/deserialization framework\nserde_yml = \"0.0.12\"       # YAML support\n",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "searched" },
    resultCount = 2,
    resultName = "serde",
    resultVersion = "1.0.228",
  }
}
