return {
  name = "template outdated",
  request = {
    action = "outdated",
    system = "template",
  },
  fakeExec = {},
  expect = {
    success = true,
    events = { "outdated" },
    eventPayloads = {
      outdated = "{}",
    },
    resultCount = 0,
  }
}
