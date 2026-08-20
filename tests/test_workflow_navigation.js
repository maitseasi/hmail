const assert = require("assert")
const fs = require("fs")
const path = require("path")
const { ROOT } = require("./load")

const account = fs.readFileSync(path.join(ROOT, "MailAccount.qml"), "utf8")
const app = fs.readFileSync(path.join(ROOT, "App.qml"), "utf8")
const list = fs.readFileSync(path.join(ROOT, "components/MessageList.qml"), "utf8")
const tabs = fs.readFileSync(path.join(ROOT, "components/MailboxTabs.qml"), "utf8")
const feed = fs.readFileSync(path.join(ROOT, "components/FeedView.qml"), "utf8")

const selectStart = account.indexOf("function selectOffset")
const selectEnd = account.indexOf("// -------------------------------------------------------------- actions",
  selectStart)
const selectOffset = account.slice(selectStart, selectEnd)

assert.ok(selectOffset.includes("fromId"), "list movement accepts the keyboard cursor")
assert.ok(!selectOffset.includes("selectedId"),
  "list movement must not restart from the separately opened message")
assert.ok(app.includes("service.selectOffset(delta, cursorId)"),
  "App passes the current Vim cursor into list movement")
assert.ok(list.includes("function ensureCursorVisible"),
  "j/k movement keeps the Inbox cursor inside the viewport")
assert.ok(tabs.includes("function revealCurrent"),
  "changing workflow views reveals the active compact tab")
assert.ok(app.includes("anchors.top: tabs.visible ? tabs.bottom : parent.top"),
  "Feed stays below compact workflow tabs")
assert.ok(feed.includes("function scrollBy"),
  "Feed provides explicit Vim and wheel scrolling")
assert.ok(feed.includes("wheel.angleDelta.y / 120"),
  "mouse-wheel notches use a useful fixed Feed distance")

console.log("test_workflow_navigation.js ok")
