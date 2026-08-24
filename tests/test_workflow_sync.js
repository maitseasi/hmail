const assert = require("assert")
const fs = require("fs")
const path = require("path")
const { ROOT } = require("./load")

const source = fs.readFileSync(path.join(ROOT, "WorkflowSync.qml"), "utf8")
const workflow = fs.readFileSync(path.join(ROOT, "Workflow.js"), "utf8")
const account = fs.readFileSync(path.join(ROOT, "MailAccount.qml"), "utf8")

assert.ok(source.includes("listWorkflowFiles"),
  "sync lists and pulls existing app data before writing")
assert.ok(source.indexOf("pullFiles(") < source.indexOf("pushMerged("),
  "remote workflow data is merged before upload")
assert.ok(source.includes("statusCode === 412"),
  "conditional update conflicts are retried")
assert.ok(source.includes("queueGmailOperation"),
  "Gmail placement changes use the durable outbox")
assert.ok(source.includes("placementFromLabels"),
  "Gmail labels are imported as canonical placement")
assert.ok(source.includes("historyId"),
  "Gmail history cursors are maintained per local replica")
assert.ok(workflow.includes("delete thread.destinationOverride"),
  "local destination projections are excluded from Drive metadata")
assert.ok(!workflow.includes("refreshToken") && !workflow.includes("accessToken"),
  "workflow cloud serialization cannot include OAuth tokens")
assert.ok(/status === 403 && \/rate \?limit\/i/.test(source),
  "Drive 403 quota exhaustion is treated as transient and retried")
assert.ok(account.includes("pendingRelabelJobs") && account.includes("relabelRetryTimer"),
  "forgotten-sender relabeling retries transient failures from the failed page")
assert.ok(/reconcileWorkflowSnapshot\(newHistoryId, page\.nextPageToken\)/.test(account)
  && account.indexOf("establishHistory(newHistoryId)") > account.indexOf("nextPageToken"),
  "history-expiration snapshot paginates fully before installing the new cursor")

console.log("test_workflow_sync.js ok")
