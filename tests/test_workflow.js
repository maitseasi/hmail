const assert = require("assert")
const { load, deepEqual } = require("./load")

const workflow = load("Workflow.js")
const NOW = Date.parse("2026-08-20T10:00:00Z")

// ------------------------------------------------------ sender normalization

assert.strictEqual(workflow.normalizeSender("Jane Smith <Jane@Example.COM>"), "jane@example.com")
assert.strictEqual(workflow.normalizeSender("\"Smith, Jane\" <Jane@Example.COM>"), "jane@example.com")
assert.strictEqual(workflow.normalizeSender("<news@example.com>"), "news@example.com")
assert.strictEqual(workflow.normalizeSender("news@example.com"), "news@example.com")
assert.strictEqual(workflow.normalizeSender({ email: "Ada+Mail@Example.com" }), "ada+mail@example.com")
assert.strictEqual(workflow.normalizeSender("me@example.com"), "me@example.com", "self-sent mail is still a sender")
assert.strictEqual(workflow.normalizeSender(""), "")
assert.strictEqual(workflow.normalizeSender(null), "")
assert.strictEqual(workflow.normalizeSender("Not an address"), "")
assert.strictEqual(workflow.normalizeSender("missing@"), "")
assert.strictEqual(workflow.normalizeSender("two@example.com, other@example.com"), "")

// --------------------------------------------------------------- empty store

deepEqual(workflow.emptyStore("Ada@Example.COM"), {
  version: workflow.VERSION,
  account: "ada@example.com",
  senders: {},
  threads: {},
  domainRules: {},
  settings: {
    initialized: false,
    mirrorGmailLabels: false,
    routeRepliesToInbox: true
  }
})
assert.strictEqual(workflow.workflowLabelNames().length, 8)
assert.strictEqual(workflow.labelNameFor("feed", {}), "Oma/Feed")
assert.strictEqual(workflow.labelNameFor("inbox", { pile: "reply_later" }), "Oma/ReplyLater")
assert.strictEqual(workflow.labelNameFor("inbox", { bubbleUpAt: "2026-08-21T00:00:00Z" }), "Oma/BubbleUp")
deepEqual(workflow.workflowLabelChanges(["Label_inbox", "STARRED"], {
  "Oma/Inbox": "Label_inbox",
  "Oma/Feed": "Label_feed"
}, "feed", {}), {
  add: ["Label_feed"],
  remove: ["Label_inbox"]
})
const convergentLabels = workflow.workflowLabelChanges([], {
  "Oma/Inbox": "Label_inbox",
  "Oma/Feed": "Label_feed",
  "Oma/PaperTrail": "Label_paper"
}, "feed", {})
deepEqual(convergentLabels, {
  add: ["Label_feed"],
  remove: ["Label_inbox", "Label_paper"]
})
assert.strictEqual(convergentLabels.remove.indexOf(convergentLabels.add[0]), -1)
const mirrored = workflow.setSetting(workflow.emptyStore("ada@example.com"),
  "mirrorGmailLabels", true)
assert.strictEqual(mirrored.settings.mirrorGmailLabels, true)
assert.strictEqual(workflow.emptyStore("ada@example.com").settings.mirrorGmailLabels, false)

// -------------------------------------------------------------- sender rules

let store = workflow.emptyStore("ada@example.com")
const untouched = JSON.stringify(store)
store = workflow.setSenderRule(store, "News <NEWS@example.com>", {
  decision: "accepted",
  destination: "feed",
  note: "keep this unknown field"
}, NOW)

assert.strictEqual(JSON.stringify(workflow.emptyStore("ada@example.com")), untouched)
assert.strictEqual(workflow.getSenderRule(store, "news@example.com").destination, "feed")
assert.strictEqual(workflow.getSenderRule(store, "NEWS@EXAMPLE.COM").decision, "accepted")
assert.strictEqual(workflow.getSenderRule(store, "news@example.com").note, "keep this unknown field")
assert.strictEqual(workflow.getSenderRule(store, "news@example.com").createdAt, "2026-08-20T10:00:00.000Z")

const originalCreatedAt = workflow.getSenderRule(store, "news@example.com").createdAt
store = workflow.setSenderRule(store, "news@example.com", {
  decision: "accepted",
  destination: "inbox"
}, NOW + 1000)
assert.strictEqual(workflow.getSenderRule(store, "news@example.com").destination, "inbox")
assert.strictEqual(workflow.getSenderRule(store, "news@example.com").createdAt, originalCreatedAt)
assert.strictEqual(workflow.getSenderRule(store, "news@example.com").updatedAt, "2026-08-20T10:00:01.000Z")

store = workflow.setSenderRule(store, "blocked@example.com", {
  decision: "screened_out",
  destination: "feed"
}, NOW)
assert.strictEqual(workflow.getSenderRule(store, "blocked@example.com").destination, null)
assert.strictEqual(workflow.senderRuleList(store).length, 2)
assert.strictEqual(workflow.senderRuleList(store)[0].sender, "blocked@example.com")

const beforeInvalidRule = store
assert.strictEqual(workflow.setSenderRule(store, "bad", {
  decision: "accepted", destination: "feed"
}, NOW), beforeInvalidRule)
assert.strictEqual(workflow.setSenderRule(store, "news@example.com", {
  decision: "accepted", destination: "somewhere"
}, NOW), beforeInvalidRule)

store = workflow.removeSenderRule(store, "NEWS@example.com")
assert.strictEqual(workflow.getSenderRule(store, "news@example.com"), null)
assert.strictEqual(workflow.removeSenderRule(store, "missing@example.com"), store)

// -------------------------------------------------------------- thread state

const beforeThread = store
store = workflow.setThreadState(store, "18c9_ab-CD", {
  seenAt: null,
  pile: "reply_later",
  futureField: { value: 1 }
}, NOW)
assert.notStrictEqual(store, beforeThread)
assert.strictEqual(workflow.getThreadState(store, "18c9_ab-CD").pile, "reply_later")
assert.strictEqual(workflow.getThreadState(store, "18c9_ab-CD").updatedAt, "2026-08-20T10:00:00.000Z")

store = workflow.setThreadState(store, "18c9_ab-CD", { seenAt: "2026-08-20T11:00:00Z" }, NOW + 1)
assert.strictEqual(workflow.getThreadState(store, "18c9_ab-CD").pile, "reply_later", "updates merge")
deepEqual(workflow.getThreadState(store, "18c9_ab-CD").futureField, { value: 1 })
assert.strictEqual(workflow.setThreadState(store, "../escape", {}, NOW), store)
assert.strictEqual(workflow.getThreadState(store, "__proto__"), null)

// ------------------------------------------------------------ routing engine

function message(id, threadId, sender, date) {
  return {
    id: id,
    threadId: threadId,
    from: { name: sender.split("@")[0], email: sender },
    date: new Date(date)
  }
}

let routes = workflow.emptyStore("ada@example.com")
const unknown = message("m1", "t1", "unknown@example.com", NOW)
assert.strictEqual(workflow.classifyIncoming(routes, unknown), "screener")

routes = workflow.setSenderRule(routes, "person@example.com", {
  decision: "accepted", destination: "inbox"
}, NOW)
routes = workflow.setSenderRule(routes, "news@example.com", {
  decision: "accepted", destination: "feed"
}, NOW)
routes = workflow.setSenderRule(routes, "orders@example.com", {
  decision: "accepted", destination: "paper_trail"
}, NOW)
routes = workflow.setSenderRule(routes, "blocked@example.com", {
  decision: "screened_out", destination: null
}, NOW)

assert.strictEqual(workflow.classifyIncoming(routes,
  message("m2", "t2", "person@example.com", NOW)), "inbox")
assert.strictEqual(workflow.classifyIncoming(routes,
  message("m3", "t3", "news@example.com", NOW)), "feed")
assert.strictEqual(workflow.classifyIncoming(routes,
  message("m4", "t4", "orders@example.com", NOW)), "paper_trail")
assert.strictEqual(workflow.classifyIncoming(routes,
  message("m5", "t5", "blocked@example.com", NOW)), "screened_out")
assert.strictEqual(workflow.messagesForView(routes, [
  message("m5", "t5", "blocked@example.com", NOW)
], "everything").length, 1, "Everything remains an escape hatch")

routes = workflow.setThreadState(routes, "t3", { destinationOverride: "inbox" }, NOW)
assert.strictEqual(workflow.classifyIncoming(routes,
  message("m3", "t3", "news@example.com", NOW)), "inbox", "thread override wins")

routes.domainRules["example.org"] = { decision: "accepted", destination: "feed" }
assert.strictEqual(workflow.classifyIncoming(routes,
  message("m6", "t6", "anyone@example.org", NOW)), "feed", "domain is optional fallback")
routes = workflow.setSenderRule(routes, "anyone@example.org", {
  decision: "accepted", destination: "paper_trail"
}, NOW)
assert.strictEqual(workflow.classifyIncoming(routes,
  message("m6", "t6", "anyone@example.org", NOW)), "paper_trail", "sender beats domain")

// ----------------------------------------------------------- seen and piles

const first = message("m7", "conversation", "person@example.com", NOW)
const reply = message("m8", "conversation", "person@example.com", NOW + 60000)
assert.strictEqual(workflow.isNewForUser(routes, first), true)
routes = workflow.markSeen(routes, "conversation", "m7", NOW)
assert.strictEqual(workflow.isNewForUser(routes, first), false)
assert.strictEqual(workflow.isNewForUser(routes, reply), true, "a newer message re-enters New")
routes = workflow.markUnseen(routes, "conversation", NOW + 1)
assert.strictEqual(workflow.isNewForUser(routes, first), true)

routes = workflow.setPile(routes, "conversation", "reply_later", NOW)
assert.strictEqual(workflow.getThreadState(routes, "conversation").pile, "reply_later")
routes = workflow.setPile(routes, "conversation", "set_aside", NOW)
assert.strictEqual(workflow.getThreadState(routes, "conversation").pile, "set_aside")
assert.strictEqual(workflow.setPile(routes, "conversation", "invalid", NOW), routes)
routes = workflow.setPile(routes, "conversation", null, NOW)
assert.strictEqual(workflow.getThreadState(routes, "conversation").pile, null)

// --------------------------------------------------------------- Bubble Up

routes = workflow.scheduleBubble(routes, "conversation", NOW + 60000, NOW)
assert.strictEqual(workflow.getThreadState(routes, "conversation").bubbleUpAt,
  "2026-08-20T10:01:00.000Z")
let bubbles = workflow.processDueBubbles(routes, NOW + 59000)
assert.strictEqual(bubbles.store, routes, "a future bubble is inert")
deepEqual(bubbles.threadIds, [])
bubbles = workflow.processDueBubbles(routes, NOW + 60000)
deepEqual(bubbles.threadIds, ["conversation"])
assert.strictEqual(workflow.getThreadState(bubbles.store, "conversation").bubbleUpAt, null)
assert.strictEqual(workflow.getThreadState(bubbles.store, "conversation").seenMessageId, null)
assert.strictEqual(workflow.getThreadState(bubbles.store, "conversation").destinationOverride, "inbox")
assert.strictEqual(workflow.getThreadState(bubbles.store, "conversation").bubbledAt,
  "2026-08-20T10:01:00.000Z")

// ----------------------------------------------------------- workflow views

let views = workflow.emptyStore("ada@example.com")
views = workflow.setSenderRule(views, "person@example.com", {
  decision: "accepted", destination: "inbox"
}, NOW)
views = workflow.setSenderRule(views, "news@example.com", {
  decision: "accepted", destination: "feed"
}, NOW)
const rows = [
  message("old", "same-thread", "person@example.com", NOW),
  message("new", "same-thread", "person@example.com", NOW + 1000),
  message("feed", "feed-thread", "news@example.com", NOW + 2000),
  unknown
]
deepEqual(workflow.messagesForView(views, rows, "new_for_you").map(function(row) { return row.id }), ["new"])
deepEqual(workflow.messagesForView(views, rows, "feed").map(function(row) { return row.id }), ["feed"])
deepEqual(workflow.messagesForView(views, rows, "screener").map(function(row) { return row.id }), ["m1"])
views = workflow.markSeen(views, "same-thread", "new", NOW + 3000)
deepEqual(workflow.messagesForView(views, rows, "new_for_you"), [])
deepEqual(workflow.messagesForView(views, rows, "inbox")
  .map(function(row) { return row.id }), ["new"])
deepEqual(workflow.messagesForView(views, rows, "previously_seen")
  .map(function(row) { return row.id }), ["new"])
views = workflow.setPile(views, "same-thread", "reply_later", NOW + 4000)
deepEqual(workflow.messagesForView(views, rows, "reply_later")
  .map(function(row) { return row.id }), ["new"])

let initialized = workflow.initializeExistingInbox(
  workflow.emptyStore("ada@example.com"), rows, NOW)
assert.strictEqual(initialized.settings.initialized, true)
assert.strictEqual(workflow.getSenderRule(initialized, "person@example.com").destination, "inbox")
assert.strictEqual(workflow.isNewForUser(initialized, rows[1]), false)
assert.strictEqual(workflow.messagesForView(initialized, rows, "new_for_you").length, 0)
assert.ok(workflow.messagesForView(initialized, rows, "previously_seen").length > 0)

// ----------------------------------------------------------- load and schema

assert.strictEqual(workflow.load("", "ada@example.com").ok, true, "an empty prepared file is first-run state")
assert.strictEqual(workflow.load("{broken", "ada@example.com").ok, false)
assert.strictEqual(workflow.load("[]", "ada@example.com").ok, false)
assert.strictEqual(workflow.load(JSON.stringify({
  version: workflow.VERSION + 1,
  account: "ada@example.com",
  senders: {}, threads: {}, domainRules: {}, settings: {}
}), "ada@example.com").ok, false, "newer data is never partially loaded")
assert.strictEqual(workflow.load(workflow.serialize(store), "other@example.com").ok, false,
  "one account cannot load another account's data")

const withUnknownData = JSON.parse(workflow.serialize(store))
withUnknownData.futureTopLevel = { enabled: true }
withUnknownData.settings.futureSetting = "preserve me"
const loaded = workflow.load(JSON.stringify(withUnknownData), "ada@example.com")
assert.strictEqual(loaded.ok, true)
assert.strictEqual(loaded.store.futureTopLevel.enabled, true)
assert.strictEqual(loaded.store.settings.futureSetting, "preserve me")

const roundTrip = workflow.load(workflow.serialize(loaded.store), "ADA@EXAMPLE.COM")
assert.strictEqual(roundTrip.ok, true)
assert.strictEqual(roundTrip.store.account, "ada@example.com")
assert.strictEqual(roundTrip.store.futureTopLevel.enabled, true)
assert.strictEqual(roundTrip.store.settings.futureSetting, "preserve me")

console.log("test_workflow.js ok")
