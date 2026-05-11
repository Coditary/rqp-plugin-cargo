return {
  name = "template install",
  request = {
    action = "install",
    system = "template",
    packages = {
      { name = "delta", version = "1.0.0" }
    },
  },
  fakeExec = {},
  expect = {
    success = true,
    events = { "installed", "success" },
    eventPayloads = {
      success = "ok",
    },
  }
}
