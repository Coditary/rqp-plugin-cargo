return {
  name = "cargo info",
  request = {
    action = "info",
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
      match = "cargo info serde --quiet --color never",
      exitCode = 0,
      stdout = "serde #serde #serialization #no_std\nA generic serialization/deserialization framework\nversion: 1.0.228\nlicense: MIT OR Apache-2.0\nrust-version: 1.56\ndocumentation: https://docs.rs/serde\nhomepage: https://serde.rs\nrepository: https://github.com/serde-rs/serde\ncrates.io: https://crates.io/crates/serde/1.0.228\n",
      stderr = "",
      success = true,
    },
  },
  expect = {
    success = true,
    events = { "informed" },
    resultCount = 1,
    resultName = "serde",
    resultVersion = "1.0.228",
  }
}
