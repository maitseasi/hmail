const assert = require("assert")
const fs = require("fs")
const path = require("path")
const { ROOT } = require("./load")

const account = fs.readFileSync(path.join(ROOT, "MailAccount.qml"), "utf8")
const app = fs.readFileSync(path.join(ROOT, "App.qml"), "utf8")
const list = fs.readFileSync(path.join(ROOT, "components/MessageList.qml"), "utf8")
const tabs = fs.readFileSync(path.join(ROOT, "components/MailboxTabs.qml"), "utf8")
const sidebar = fs.readFileSync(path.join(ROOT, "components/MailboxSidebar.qml"), "utf8")
const more = fs.readFileSync(path.join(ROOT, "components/MailboxMore.qml"), "utf8")
const appMenu = fs.readFileSync(path.join(ROOT, "components/AppMenu.qml"), "utf8")
const feed = fs.readFileSync(path.join(ROOT, "components/FeedView.qml"), "utf8")
const thread = fs.readFileSync(path.join(ROOT, "components/ThreadView.qml"), "utf8")

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
assert.ok(app.includes('root.currentView === "reader" ? reader.scrollBy(Style.space(40))'),
  "j/k scroll inside a thread instead of jumping between messages")
assert.ok(app.includes('root.currentView === "reader"')
  && app.includes("reader.moveMessage(1)"),
  "Shift+J/K retain explicit thread-message navigation")
assert.ok(thread.includes("function moveMessage"),
  "the thread still exposes intentional message-to-message movement")
assert.ok(sidebar.includes("primaryEntries")
  && sidebar.includes("libraryEntries"),
  "the permanent sidebar is organized around workflow destinations")
assert.ok(sidebar.includes("visible: count > 0"),
  "empty workflow piles stay out of the permanent sidebar")
assert.ok(!sidebar.includes("model: Model.MAILBOXES")
  && !sidebar.includes("model: root.userLabels"),
  "Gmail folders and labels do not clutter the permanent sidebar")
assert.ok(more.includes("model: root.rows")
  && more.includes('currentTab === "folders"')
  && more.includes('currentTab === "labels"'),
  "More provides one shared folders and labels browser")
assert.ok(more.includes('kind: "workflow"')
  && more.includes('Number(counts[piles[j].key] || 0) === 0'),
  "More keeps empty workflow piles reachable")
assert.ok(more.includes("list.forceActiveFocus()")
  && more.includes("onClosed: root.dismissed()"),
  "More supports keyboard focus and announces dismissal")
assert.ok(app.includes("!root.sidebarCollapsed")
  && !app.includes("root.sidebarCollapsed ? Style.space(44)"),
  "the sidebar hides fully instead of collapsing to an icon rail")
assert.ok(app.includes("entries: sidebar.compactEntries")
  && app.includes("mailboxMore.openAt(sceneX, sceneY)"),
  "compact workflow tabs share the More browser")
assert.ok(appMenu.includes("showNavigation")
  && app.includes("onMoreNavigationRequested: mailboxMore.openCentered()"),
  "the header menu restores More access while the sidebar is hidden")
assert.ok(app.includes('sequence: "g,m"'),
  "More has a discoverable keyboard route")

console.log("test_workflow_navigation.js ok")
