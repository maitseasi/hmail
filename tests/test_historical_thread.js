const assert = require("assert")
const fs = require("fs")
const path = require("path")
const { ROOT } = require("./load")

const account = fs.readFileSync(path.join(ROOT, "MailAccount.qml"), "utf8")
const service = fs.readFileSync(path.join(ROOT, "Service.qml"), "utf8")
const thread = fs.readFileSync(path.join(ROOT, "components/ThreadView.qml"), "utf8")
const client = fs.readFileSync(path.join(ROOT, "GmailApiClient.qml"), "utf8")

assert.ok(account.includes('"in:inbox newer_than:" + historicalScreenerMonths + "m"'),
  "historical screening is explicitly bounded to the chosen Inbox period")
assert.ok(account.includes("apiClient.listMessages(query, 100"),
  "historical scanning pages rather than requesting an unbounded list")
assert.ok(account.includes("list.slice(offset, offset + 20)"),
  "historical metadata requests use bounded batches")
assert.ok(account.includes("cancelHistoricalScreenerScan"),
  "a long historical scan can be paused")
assert.ok(account.includes("cacheStore.putQuery(historicalScreenerCacheKey"),
  "historical message summaries stay in the disposable account cache")
assert.ok(!account.includes('workflowStore.setSetting("historicalScreenerMessages"'),
  "historical message summaries never enter durable workflow metadata")

assert.ok(client.includes("function getThread"),
  "the reader retrieves complete Gmail conversations")
assert.ok(account.includes("Html.sanitize"),
  "every thread message passes through the shared HTML sanitizer")
assert.ok(thread.includes("loadThreadRemoteImages(card.modelData.id)"),
  "remote images are enabled for one explicit thread message only")
assert.ok(!thread.includes("showRemoteImages()"),
  "the thread has no bulk remote-image action")
assert.ok(thread.includes("Mail.replyReferences(summary)"),
  "inline replies preserve RFC thread references")
assert.ok(service.includes("selectedThreadMessages"),
  "thread state is exposed through the account service boundary")

console.log("test_historical_thread.js ok")
