const assert = require("assert")
const fs = require("fs")
const path = require("path")
const { ROOT } = require("./load")

const account = fs.readFileSync(path.join(ROOT, "MailAccount.qml"), "utf8")
// FeedCard holds the rendering logic; FeedView holds the list scaffolding.
// Security properties are split across both files.
const feedView = fs.readFileSync(path.join(ROOT, "components/FeedView.qml"), "utf8")
const feedCard = fs.readFileSync(path.join(ROOT, "components/FeedCard.qml"), "utf8")
const feed = feedView + feedCard
const bodyCache = fs.readFileSync(path.join(ROOT, "BodyCache.qml"), "utf8")

const loaderStart = account.indexOf("function storeFeedBody")
const loaderEnd = account.indexOf("function clearSelection", loaderStart)
const loader = account.slice(loaderStart, loaderEnd)

assert.ok(loaderStart >= 0, "Feed has a dedicated body preparation path")
assert.ok(loader.includes("Html.sanitize"), "Feed passes HTML through the shared sanitizer")
assert.ok(loader.includes("allowRemoteImages: false"),
  "Feed cannot automatically enable remote images")
assert.ok(feed.includes("service.loadFeedBody"),
  "virtualized Feed delegates request bodies only when instantiated")
assert.ok(feed.includes("service.feedBody"),
  "Feed renders the sanitized result rather than raw Gmail payloads")
assert.ok(!feed.includes("showRemoteImages"),
  "Feed has no bulk image-enabling path")
assert.ok(feed.includes("loadFeedRemoteImages("),
  "remote images can only be enabled for one explicit Feed message")
assert.ok(bodyCache.includes("function drainReads"),
  "concurrent virtualized Feed delegates serialize body-cache reads")
assert.ok(feed.includes(".html === \"\""),
  "plain-text Feed messages render their text instead of a blank HTML view")

console.log("test_feed_security.js ok")
