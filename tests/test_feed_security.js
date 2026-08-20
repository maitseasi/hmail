const assert = require("assert")
const fs = require("fs")
const path = require("path")
const { ROOT } = require("./load")

const account = fs.readFileSync(path.join(ROOT, "MailAccount.qml"), "utf8")
const feed = fs.readFileSync(path.join(ROOT, "components/FeedView.qml"), "utf8")

const loaderStart = account.indexOf("function loadFeedBody")
const loaderEnd = account.indexOf("function clearSelection", loaderStart)
const loader = account.slice(loaderStart, loaderEnd)

assert.ok(loaderStart >= 0, "Feed has a dedicated lazy body loader")
assert.ok(loader.includes("Html.sanitize"), "Feed passes HTML through the shared sanitizer")
assert.ok(loader.includes("allowRemoteImages: false"),
  "Feed cannot automatically enable remote images")
assert.ok(feed.includes("service.loadFeedBody"),
  "virtualized Feed delegates request bodies only when instantiated")
assert.ok(feed.includes("service.feedBody"),
  "Feed renders the sanitized result rather than raw Gmail payloads")
assert.ok(!feed.includes("showRemoteImages"),
  "Feed has no bulk image-enabling path")
assert.ok(feed.includes("loadFeedRemoteImages(card.modelData.id)"),
  "remote images can only be enabled for one explicit Feed message")

console.log("test_feed_security.js ok")
