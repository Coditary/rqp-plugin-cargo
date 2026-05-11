return {
  name = "template update",
  request = {
    action = "update",
    system = "template",
    packages = {
      { name = "delta" }
    },
  },
  fakeExec = {},
  expect = {
    success = true,
    events = { "updated", "success" },
    eventPayloads = {
      success = "ok",
    },
  }
}
