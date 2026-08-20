.pragma library

// Durable workflow metadata. Message bodies and Gmail data do not belong here;
// this store only remembers user decisions about senders and threads.

var VERSION = 1
var DESTINATIONS = {
  inbox: true,
  feed: true,
  paper_trail: true
}
var LABEL_NAMES = {
  inbox: "Oma/Inbox",
  feed: "Oma/Feed",
  paper_trail: "Oma/PaperTrail",
  screener: "Oma/Screener",
  screened_out: "Oma/ScreenedOut",
  reply_later: "Oma/ReplyLater",
  set_aside: "Oma/SetAside",
  bubble_up: "Oma/BubbleUp"
}

function trimmed(value) {
  return String(value === undefined || value === null ? "" : value).trim()
}

function isObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

function copyObject(source) {
  var out = {}
  if (!isObject(source)) return out
  for (var key in source) {
    if (Object.prototype.hasOwnProperty.call(source, key)) out[key] = source[key]
  }
  return out
}

function copyMap(source) {
  return copyObject(source)
}

function normalizeAccountId(value) {
  return trimmed(value).toLowerCase()
}

// Accepts either Message.parseAddress's result or a raw From header. Routing
// uses only the address; display names are untrusted presentation text.
function normalizeSender(value) {
  var raw = isObject(value) ? trimmed(value.email) : trimmed(value)
  if (!raw) return ""

  var angled = raw.match(/<([^<>]*)>\s*$/)
  if (angled) raw = trimmed(angled[1])
  else raw = raw.replace(/^\s*<|>\s*$/g, "").trim()

  if (!raw || /[\s<>,;]/.test(raw)) return ""
  var at = raw.lastIndexOf("@")
  if (at <= 0 || at !== raw.indexOf("@") || at >= raw.length - 1) return ""
  return raw.toLowerCase()
}

function emptyStore(accountId) {
  return {
    version: VERSION,
    account: normalizeAccountId(accountId),
    senders: {},
    threads: {},
    domainRules: {},
    settings: {
      initialized: false,
      // Server mutations stay opt-in until routing is integrated and proven.
      mirrorGmailLabels: false,
      routeRepliesToInbox: true
    }
  }
}

// Keep fields this version does not understand. A future version may know
// about them, and loading then saving v1 must not silently erase them.
function copyStore(store) {
  var source = isObject(store) ? store : emptyStore("")
  var next = copyObject(source)
  next.version = VERSION
  next.account = normalizeAccountId(source.account)
  next.senders = copyMap(source.senders)
  next.threads = copyMap(source.threads)
  next.domainRules = copyMap(source.domainRules)
  next.settings = copyObject(source.settings)
  return next
}

function setSetting(store, name, value) {
  var key = String(name || "")
  if (key !== "mirrorGmailLabels" && key !== "routeRepliesToInbox") return store
  var next = copyStore(store)
  next.settings[key] = value === true
  return next
}

function workflowLabelNames() {
  var out = []
  for (var key in LABEL_NAMES) {
    if (Object.prototype.hasOwnProperty.call(LABEL_NAMES, key)) out.push(LABEL_NAMES[key])
  }
  return out
}

function labelNameFor(destination, state) {
  var thread = isObject(state) ? state : {}
  if (thread.bubbleUpAt) return LABEL_NAMES.bubble_up
  if (thread.pile === "reply_later") return LABEL_NAMES.reply_later
  if (thread.pile === "set_aside") return LABEL_NAMES.set_aside
  return LABEL_NAMES[String(destination || "")] || ""
}

function workflowLabelChanges(currentIds, labelIdsByName, destination, state) {
  var ids = isObject(labelIdsByName) ? labelIdsByName : {}
  var wantedName = labelNameFor(destination, state)
  var wantedId = wantedName ? String(ids[wantedName] || "") : ""
  var add = []
  var remove = []
  for (var key in LABEL_NAMES) {
    if (!Object.prototype.hasOwnProperty.call(LABEL_NAMES, key)) continue
    var id = String(ids[LABEL_NAMES[key]] || "")
    if (!id) continue
    if (id === wantedId) {
      if (add.indexOf(id) < 0) add.push(id)
    } else if (remove.indexOf(id) < 0) remove.push(id)
  }
  return { add: add, remove: remove }
}

function timestamp(value) {
  var date = value instanceof Date ? value : new Date(value === undefined ? Date.now() : value)
  return isFinite(date.getTime()) ? date.toISOString() : new Date().toISOString()
}

function validDestination(value) {
  return DESTINATIONS[String(value || "")] === true
}

function normalizedRule(rule, existing, now) {
  if (!isObject(rule)) return null
  var decision = String(rule.decision || "")
  var destination = rule.destination === null ? null : String(rule.destination || "")
  if (decision !== "accepted" && decision !== "screened_out") return null
  if (decision === "accepted" && !validDestination(destination)) return null
  if (decision === "screened_out") destination = null

  var next = copyObject(rule)
  next.decision = decision
  next.destination = destination
  next.createdAt = existing && existing.createdAt
    ? String(existing.createdAt)
    : timestamp(now)
  next.updatedAt = timestamp(now)
  return next
}

function getSenderRule(store, sender) {
  var key = normalizeSender(sender)
  if (!key || !isObject(store) || !isObject(store.senders)) return null
  var rule = store.senders[key]
  return isObject(rule) ? rule : null
}

function setSenderRule(store, sender, rule, now) {
  var key = normalizeSender(sender)
  if (!key) return store
  var source = copyStore(store)
  var nextRule = normalizedRule(rule, source.senders[key], now)
  if (!nextRule) return store
  source.senders[key] = nextRule
  return source
}

function removeSenderRule(store, sender) {
  var key = normalizeSender(sender)
  if (!key || !getSenderRule(store, key)) return store
  var next = copyStore(store)
  delete next.senders[key]
  return next
}

function senderRuleList(store) {
  var source = isObject(store) && isObject(store.senders) ? store.senders : {}
  var out = []
  for (var sender in source) {
    if (!Object.prototype.hasOwnProperty.call(source, sender) || !isObject(source[sender])) continue
    out.push({
      sender: sender,
      decision: String(source[sender].decision || ""),
      destination: source[sender].destination === null
        ? null : String(source[sender].destination || ""),
      updatedAt: String(source[sender].updatedAt || "")
    })
  }
  out.sort(function(a, b) { return a.sender.localeCompare(b.sender) })
  return out
}

// Gmail thread ids are opaque but currently use this conservative alphabet.
// Rejecting separators and magic object keys also keeps them safe map keys.
function normalizeThreadId(value) {
  var id = trimmed(value)
  if (id === "__proto__" || id === "constructor" || id === "prototype") return ""
  return /^[A-Za-z0-9_-]+$/.test(id) ? id : ""
}

function getThreadState(store, threadId) {
  var key = normalizeThreadId(threadId)
  if (!key || !isObject(store) || !isObject(store.threads)) return null
  var state = store.threads[key]
  return isObject(state) ? state : null
}

function setThreadState(store, threadId, state, now) {
  var key = normalizeThreadId(threadId)
  if (!key || !isObject(state)) return store
  var next = copyStore(store)
  var existing = isObject(next.threads[key]) ? next.threads[key] : {}
  var merged = copyObject(existing)
  for (var field in state) {
    if (Object.prototype.hasOwnProperty.call(state, field)) merged[field] = state[field]
  }
  merged.updatedAt = timestamp(now)
  next.threads[key] = merged
  return next
}

function domainForSender(sender) {
  var address = normalizeSender(sender)
  var at = address.lastIndexOf("@")
  return at > 0 ? address.substring(at + 1) : ""
}

function destinationFromRule(rule) {
  if (!isObject(rule)) return ""
  if (rule.decision === "screened_out") return "screened_out"
  return rule.decision === "accepted" && validDestination(rule.destination)
    ? String(rule.destination)
    : ""
}

// Precedence is deliberate: a one-off thread move beats a sender decision,
// which beats an optional domain rule. No decision means Screener.
function effectiveDestination(store, sender, threadId) {
  var thread = getThreadState(store, threadId)
  if (thread && validDestination(thread.destinationOverride))
    return String(thread.destinationOverride)

  var senderDestination = destinationFromRule(getSenderRule(store, sender))
  if (senderDestination) return senderDestination

  var domain = domainForSender(sender)
  var domainRule = isObject(store) && isObject(store.domainRules)
    ? store.domainRules[domain]
    : null
  var domainDestination = destinationFromRule(domainRule)
  return domainDestination || "screener"
}

function threadIdFor(message) {
  var source = isObject(message) ? message : {}
  return normalizeThreadId(source.threadId || source.id)
}

function classifyIncoming(store, message) {
  var source = isObject(message) ? message : {}
  return effectiveDestination(store, source.from, threadIdFor(source))
}

function markSeen(store, threadId, messageId, now) {
  var id = normalizeThreadId(messageId)
  if (!id) return store
  return setThreadState(store, threadId, {
    seenAt: timestamp(now),
    seenMessageId: id
  }, now)
}

function markUnseen(store, threadId, now) {
  return setThreadState(store, threadId, {
    seenAt: null,
    seenMessageId: null
  }, now)
}

function isNewForUser(store, message) {
  var source = isObject(message) ? message : {}
  var state = getThreadState(store, threadIdFor(source))
  if (!state || !state.seenMessageId) return true
  return String(state.seenMessageId) !== String(source.id || "")
}

function setPile(store, threadId, pile, now) {
  var value = pile === null ? null : String(pile || "")
  if (value !== null && value !== "reply_later" && value !== "set_aside") return store
  return setThreadState(store, threadId, { pile: value }, now)
}

function scheduleBubble(store, threadId, at, now) {
  var date = at instanceof Date ? at : new Date(at)
  if (!isFinite(date.getTime())) return store
  var existing = getThreadState(store, threadId)
  return setThreadState(store, threadId, {
    bubbleUpAt: date.toISOString(),
    bubbledAt: null,
    bubbleOrigin: existing && existing.pile ? String(existing.pile) : null,
    pile: null
  }, now)
}

function cancelBubble(store, threadId, now) {
  return setThreadState(store, threadId, { bubbleUpAt: null }, now)
}

function processDueBubbles(store, now) {
  var at = now instanceof Date ? now.getTime() : Number(now)
  if (!isFinite(at)) at = Date.now()
  var next = copyStore(store)
  var due = []
  for (var threadId in next.threads) {
    if (!Object.prototype.hasOwnProperty.call(next.threads, threadId)) continue
    var state = next.threads[threadId]
    if (!isObject(state) || !state.bubbleUpAt) continue
    var scheduled = new Date(state.bubbleUpAt).getTime()
    if (!isFinite(scheduled) || scheduled > at) continue
    var updated = copyObject(state)
    updated.bubbleUpAt = null
    updated.bubbledAt = timestamp(at)
    updated.pile = null
    updated.destinationOverride = "inbox"
    updated.seenAt = null
    updated.seenMessageId = null
    updated.updatedAt = timestamp(at)
    next.threads[threadId] = updated
    due.push(threadId)
  }
  return { store: due.length > 0 ? next : store, threadIds: due }
}

function messageTime(message) {
  var source = isObject(message) ? message : {}
  var value = source.date instanceof Date ? source.date.getTime() : new Date(source.date || 0).getTime()
  return isFinite(value) ? value : 0
}

function effectiveSortTime(store, message) {
  var state = getThreadState(store, threadIdFor(message))
  var bubbled = state && state.bubbledAt ? new Date(state.bubbledAt).getTime() : NaN
  return isFinite(bubbled) ? bubbled : messageTime(message)
}

function newestThreads(messages) {
  var list = Array.isArray(messages) ? messages : []
  var byThread = {}
  var order = []
  for (var i = 0; i < list.length; i++) {
    var threadId = threadIdFor(list[i])
    if (!threadId) continue
    var key = "thread:" + threadId
    if (!byThread[key]) {
      byThread[key] = list[i]
      order.push(threadId)
    } else if (messageTime(list[i]) > messageTime(byThread[key])) {
      byThread[key] = list[i]
    }
  }
  var out = []
  for (var j = 0; j < order.length; j++) out.push(byThread["thread:" + order[j]])
  return out
}

function messagesForView(store, messages, view) {
  var list = newestThreads(messages)
  var wanted = String(view || "inbox")
  var out = []
  for (var i = 0; i < list.length; i++) {
    var message = list[i]
    var thread = getThreadState(store, threadIdFor(message))
    var destination = classifyIncoming(store, message)
    var pile = thread ? String(thread.pile || "") : ""
    var deferred = !!(thread && thread.bubbleUpAt)
    var include = false
    if (wanted === "screener") include = destination === "screener"
    else if (wanted === "reply_later") include = pile === "reply_later"
    else if (wanted === "set_aside") include = pile === "set_aside"
    else if (wanted === "bubble_up") include = !!(thread && thread.bubbleUpAt)
    else if (wanted === "previously_seen")
      include = destination === "inbox" && pile === "" && !deferred && !isNewForUser(store, message)
    else if (wanted === "new_for_you")
      include = destination === "inbox" && pile === "" && !deferred && isNewForUser(store, message)
    else if (wanted === "inbox")
      include = destination === "inbox" && pile === "" && !deferred
    else if (wanted === "feed" || wanted === "paper_trail")
      include = destination === wanted && pile === "" && !deferred
    else if (wanted === "everything") include = true
    if (include) out.push(message)
  }
  out.sort(function(a, b) {
    if (wanted === "inbox") {
      var aNew = isNewForUser(store, a)
      var bNew = isNewForUser(store, b)
      if (aNew !== bNew) return aNew ? -1 : 1
    }
    return effectiveSortTime(store, b) - effectiveSortTime(store, a)
  })
  return out
}

function initializeExistingInbox(store, messages, now) {
  var list = Array.isArray(messages) ? messages : []
  var next = store
  for (var i = 0; i < list.length; i++) {
    if (!getSenderRule(next, list[i].from)) {
      next = setSenderRule(next, list[i].from, {
        decision: "accepted",
        destination: "inbox"
      }, now)
    }
    var threadId = threadIdFor(list[i])
    if (threadId && normalizeThreadId(list[i].id))
      next = markSeen(next, threadId, list[i].id, now)
  }
  if (next !== store) {
    var initialized = copyStore(next)
    initialized.settings.initialized = true
    next = initialized
  }
  return next
}

function parseJson(text) {
  try {
    return { ok: true, value: JSON.parse(String(text || "")) }
  } catch (error) {
    return { ok: false, error: "Workflow data is not valid JSON" }
  }
}

// This explicit gate is where v1 -> v2 migrations will be chained. Refusing an
// unknown version is safer than partially reading it and overwriting its data.
function migrateWorkflow(raw) {
  if (!isObject(raw)) return { ok: false, error: "Workflow data is not an object" }
  var version = Number(raw.version)
  if (version !== VERSION)
    return { ok: false, error: "Unsupported workflow schema version: " + String(raw.version) }
  return { ok: true, store: raw }
}

function validateStore(raw, accountId) {
  var expected = normalizeAccountId(accountId)
  var actual = normalizeAccountId(raw.account)
  if (!expected) return { ok: false, error: "A workflow store requires an account" }
  if (actual && actual !== expected)
    return { ok: false, error: "Workflow data belongs to a different account" }
  if (!isObject(raw.senders) || !isObject(raw.threads)
      || !isObject(raw.domainRules) || !isObject(raw.settings))
    return { ok: false, error: "Workflow data has an invalid shape" }

  for (var sender in raw.senders) {
    if (!Object.prototype.hasOwnProperty.call(raw.senders, sender)) continue
    if (normalizeSender(sender) !== sender || !isObject(raw.senders[sender]))
      return { ok: false, error: "Workflow data contains an invalid sender rule" }
  }
  for (var threadId in raw.threads) {
    if (!Object.prototype.hasOwnProperty.call(raw.threads, threadId)) continue
    if (normalizeThreadId(threadId) !== threadId || !isObject(raw.threads[threadId]))
      return { ok: false, error: "Workflow data contains an invalid thread state" }
  }

  var next = copyStore(raw)
  next.account = expected
  return { ok: true, store: next, error: "" }
}

// An empty file is the prepared first-run state. Malformed or newer data is
// reported to the QML owner, which leaves it untouched and disables writes.
function load(text, accountId) {
  if (trimmed(text) === "") return { ok: true, store: emptyStore(accountId), error: "" }
  var parsed = parseJson(text)
  if (!parsed.ok) return { ok: false, store: null, error: parsed.error }
  var migrated = migrateWorkflow(parsed.value)
  if (!migrated.ok) return { ok: false, store: null, error: migrated.error }
  return validateStore(migrated.store, accountId)
}

function serialize(store) {
  return JSON.stringify(copyStore(store))
}
