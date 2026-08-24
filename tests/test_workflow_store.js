const assert = require("assert")
const fs = require("fs")
const path = require("path")
const { ROOT } = require("./load")

const source = fs.readFileSync(path.join(ROOT, "WorkflowStore.qml"), "utf8")

assert.ok(source.includes('Quickshell.env("XDG_DATA_HOME")'),
  "durable workflow data uses XDG data home")
assert.ok(source.includes('"/.local/share"'),
  "durable workflow data has the standard user-data fallback")
assert.ok(!source.includes("XDG_CACHE_HOME"),
  "workflow metadata must not live in the cache")
assert.ok(source.includes("atomicWrites: true"),
  "whole-store writes must use atomic replacement")
assert.ok(source.includes("chmod 700"),
  "the workflow directory is private")
assert.ok(source.includes("chmod 600"),
  "the workflow file is private")
assert.ok(source.includes("root.writable = result.ok"),
  "invalid workflow data disables writes instead of being overwritten")
assert.ok(source.includes("Workflow.mergeCloud"),
  "cloud data is merged through the tested workflow engine")
assert.ok(source.includes("queueGmailOperation"),
  "Gmail placement retries are persisted in the durable workflow store")
assert.ok(source.includes("device_"),
  "each local replica receives a stable device identity")

console.log("test_workflow_store.js ok")
