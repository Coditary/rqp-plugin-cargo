return {
  name = "template remove",
  request = {
    action = "remove",
    system = "template",
    packages = {
      { name = "delta" }
    },
  },
  fakeExec = {},
  expect = {
    success = true,
    events = { "deleted", "success" },
    eventPayloads = {
      success = "ok",
    },
  }
}
