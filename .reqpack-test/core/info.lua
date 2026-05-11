return {
  name = "template info",
  request = {
    action = "info",
    system = "template",
    prompt = "delta",
  },
  fakeExec = {},
  expect = {
    success = true,
    events = { "informed" },
    eventPayloads = {
      informed = "{description=Replace this placeholder info result, name=delta, version=template}",
    },
    resultCount = 1,
    resultName = "delta",
    resultVersion = "template",
  }
}
