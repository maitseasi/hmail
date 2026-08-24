const assert = require("assert")
const fs = require("fs")
const path = require("path")
const { ROOT } = require("./load")

const account = fs.readFileSync(path.join(ROOT, "MailAccount.qml"), "utf8")
const selectStart = account.indexOf("function select(id)")
const selectEnd = account.indexOf("function renderSource", selectStart)
const select = account.slice(selectStart, selectEnd)

assert.ok(selectStart >= 0, "message selection exists")
assert.ok(select.includes("root.prepareThreadEntry(cachedSummary, cached, false)"),
  "a cached body is paired with the summary required to reveal the reader")
assert.ok(select.includes("root.applySelectedThreadEntry(entry)"),
  "the cache hit paints a complete thread entry")
assert.ok(select.includes("root.detailLoading = false"),
  "a cache hit removes the loading skeleton without waiting for Gmail")
assert.ok(select.includes("apiClient.getThread"),
  "a cache hit still allows a live Gmail conversation refresh")

console.log("test_reader_cache.js ok")
