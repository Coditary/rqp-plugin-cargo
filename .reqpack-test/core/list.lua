return {
  name = "template list",
  request = {
    action = "list",
    system = "template",
  },
  fakeExec = {},
  expect = {
    success = true,
    events = { "listed" },
    eventPayloads = {
      listed = "{}",
    },
    resultCount = 0,
  }
}
