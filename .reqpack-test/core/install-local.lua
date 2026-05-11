return {
  name = "template install local",
  request = {
    action = "install",
    system = "template",
    localPath = "/tmp/delta.tgz",
  },
  fakeExec = {},
  expect = {
    success = true,
    events = { "installed", "success" },
    eventPayloads = {
      installed = "{localTarget=true, path=/tmp/delta.tgz}",
      success = "ok",
    },
  }
}
