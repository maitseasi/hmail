.pragma library

// Durable workflow metadata. Message bodies and Gmail data do not belong here;
// this store only remembers user decisions about senders and threads.

var VERSION = 2
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
    deviceId: "",
    syncCounter: 0,
    settingRevisions: {},
    senders: {},
    threads: {},
    domainRules: {},
    tombstones: {
      senders: {},
      threads: {},
      domainRules: {}
    },
    cloud: {
      enabled: false,
      fileId: "",
      etag: "",
      lastSyncAt: "",
      lastError: "",
      historyId: "",
      drivePending: false,
      gmailOutbox: []
    },
    settings: {
      initialized: false,
      // Server mutations stay opt-in until routing is integrated and proven.
      mirrorGmailLabels: false,
      routeRepliesToInbox: true,
      historicalScreenerMonths: 0
    }
  }
}

// Keep fields this version does not understand. A future version may know
// about them, and loading then saving v1 must not silently erase them.
function copyStore(store) {
  var source = isObject(store) ? store : emptyStore("")
  var sourceSettings = isObject(source.settings) ? source.settings : {}
  var next = copyObject(source)
  next.version = VERSION
  next.account = normalizeAccountId(source.account)
  next.deviceId = trimmed(source.deviceId)
  next.syncCounter = Math.max(0, Math.floor(Number(source.syncCounter) || 0))
  next.settingRevisions = copyMap(source.settingRevisions)
  next.senders = copyMap(source.senders)
  next.threads = copyMap(source.threads)
  next.domainRules = copyMap(source.domainRules)
  var tombstones = isObject(source.tombstones) ? source.tombstones : {}
  next.tombstones = {
    senders: copyMap(tombstones.senders),
    threads: copyMap(tombstones.threads),
    domainRules: copyMap(tombstones.domainRules)
  }
  var cloud = isObject(source.cloud) ? source.cloud : {}
  next.cloud = {
    enabled: cloud.enabled === true,
    fileId: trimmed(cloud.fileId),
    etag: trimmed(cloud.etag),
    lastSyncAt: trimmed(cloud.lastSyncAt),
    lastError: trimmed(cloud.lastError),
    historyId: trimmed(cloud.historyId),
    drivePending: cloud.drivePending === true,
    gmailOutbox: Array.isArray(cloud.gmailOutbox) ? cloud.gmailOutbox.slice() : []
  }
  next.settings = {
    initialized: sourceSettings.initialized === true,
    mirrorGmailLabels: sourceSettings.mirrorGmailLabels === true,
    routeRepliesToInbox: sourceSettings.routeRepliesToInbox !== false,
    historicalScreenerMonths: normalizeHistoricalScreenerMonths(
      sourceSettings.historicalScreenerMonths)
  }
  for (var setting in sourceSettings) {
    if (Object.prototype.hasOwnProperty.call(sourceSettings, setting)
        && next.settings[setting] === undefined)
      next.settings[setting] = sourceSettings[setting]
  }
  return next
}

function normalizeHistoricalScreenerMonths(value) {
  var months = Math.floor(Number(value) || 0)
  return months === 1 || months === 2 || months === 3 ? months : 0
}

function setSetting(store, name, value) {
  var key = String(name || "")
  if (key !== "mirrorGmailLabels" && key !== "routeRepliesToInbox"
      && key !== "historicalScreenerMonths") return store
  var next = copyStore(store)
  next.settings[key] = key === "historicalScreenerMonths"
    ? normalizeHistoricalScreenerMonths(value)
    : value === true
  if (key === "routeRepliesToInbox" || key === "historicalScreenerMonths") {
    var revision = revisionFor(next, Date.now())
    next.syncCounter = revision.counter
    next.settingRevisions[key] = revision
    next.cloud.drivePending = true
  }
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

function revisionFor(store, now) {
  return {
    counter: Math.max(0, Math.floor(Number(store && store.syncCounter) || 0)) + 1,
    deviceId: trimmed(store && store.deviceId),
    updatedAt: timestamp(now)
  }
}

function stampRecord(store, record, now) {
  var revision = revisionFor(store, now)
  store.syncCounter = revision.counter
  record._rev = revision
  record.updatedAt = revision.updatedAt
  if (store.cloud) store.cloud.drivePending = true
  return record
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
  source.senders[key] = stampRecord(source, nextRule, now)
  delete source.tombstones.senders[key]
  return source
}

function removeSenderRule(store, sender, now) {
  var key = normalizeSender(sender)
  if (!key || !getSenderRule(store, key)) return store
  var next = copyStore(store)
  delete next.senders[key]
  var marker = {}
  next.tombstones.senders[key] = stampRecord(next, marker,
    now === undefined ? Date.now() : now)._rev
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
  next.threads[key] = stampRecord(next, merged, now)
  delete next.tombstones.threads[key]
  return next
}

// Gmail placement is a local projection of server state, not portable
// metadata. Updating it must not create a newer Drive revision.
function projectThreadPlacement(store, threadId, state) {
  var key = normalizeThreadId(threadId)
  if (!key || !isObject(state)) return store
  var next = copyStore(store)
  var existing = isObject(next.threads[key]) ? next.threads[key] : {}
  var merged = copyObject(existing)
  for (var field in state) {
    if (Object.prototype.hasOwnProperty.call(state, field)) merged[field] = state[field]
  }
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
  if (thread && (thread.placementLabel === "screener"
      || thread.placementLabel === "screened_out"))
    return String(thread.placementLabel)
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
  return setThreadState(store, threadId, {
    pile: value,
    placementLabel: value || "inbox"
  }, now)
}

function scheduleBubble(store, threadId, at, now) {
  var date = at instanceof Date ? at : new Date(at)
  if (!isFinite(date.getTime())) return store
  var existing = getThreadState(store, threadId)
  return setThreadState(store, threadId, {
    bubbleUpAt: date.toISOString(),
    bubbledAt: null,
    bubbleOrigin: existing && existing.pile ? String(existing.pile) : null,
    pile: null,
    placementLabel: "bubble_up"
  }, now)
}

function cancelBubble(store, threadId, now) {
  var existing = getThreadState(store, threadId)
  var origin = existing && existing.bubbleOrigin ? String(existing.bubbleOrigin) : ""
  return setThreadState(store, threadId, {
    bubbleUpAt: null,
    pile: origin === "reply_later" || origin === "set_aside" ? origin : null,
    placementLabel: origin || "inbox"
  }, now)
}

function processDueBubbles(store, now) {
  var at = now instanceof Date ? now.getTime() : Number(now)
  if (!isFinite(at)) at = Date.now()
  var next = store
  var due = []
  for (var threadId in store.threads) {
    if (!Object.prototype.hasOwnProperty.call(store.threads, threadId)) continue
    var state = store.threads[threadId]
    if (!isObject(state) || !state.bubbleUpAt) continue
    var scheduled = new Date(state.bubbleUpAt).getTime()
    if (!isFinite(scheduled) || scheduled > at) continue
    next = setThreadState(next, threadId, {
      bubbleUpAt: null,
      bubbledAt: timestamp(at),
      pile: null,
      destinationOverride: "inbox",
      placementLabel: "inbox",
      seenAt: null,
      seenMessageId: null
    }, at)
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

// Historical screening is about people, not mail volume. A busy newsletter
// gets one card — its newest — and an existing decision removes that sender
// immediately without rewriting the cached scan.
function historicalScreenerCandidates(store, messages, accountId) {
  var list = Array.isArray(messages) ? messages : []
  var mine = normalizeSender(accountId)
  var bySender = {}
  for (var i = 0; i < list.length; i++) {
    var message = list[i]
    var sender = normalizeSender(message && message.from)
    if (!sender || sender === mine || getSenderRule(store, sender)) continue
    var previous = bySender[sender]
    if (!previous || messageTime(message) > messageTime(previous))
      bySender[sender] = message
  }
  var out = []
  for (var key in bySender) {
    if (Object.prototype.hasOwnProperty.call(bySender, key)) out.push(bySender[key])
  }
  out.sort(function(a, b) { return messageTime(b) - messageTime(a) })
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
    var placementLabel = thread ? String(thread.placementLabel || "") : ""
    var pile = thread ? String(thread.pile || "") : ""
    if (!pile && placementLabel === "reply_later") pile = "reply_later"
    if (!pile && placementLabel === "set_aside") pile = "set_aside"
    var deferred = !!(thread && (thread.bubbleUpAt || placementLabel === "bubble_up"))
    var include = false
    if (wanted === "screener") include = destination === "screener"
    else if (wanted === "reply_later") include = pile === "reply_later"
    else if (wanted === "set_aside") include = pile === "set_aside"
    else if (wanted === "bubble_up") include = deferred
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

function setDeviceId(store, deviceId) {
  var value = trimmed(deviceId)
  if (!value || !/^[A-Za-z0-9_-]{16,96}$/.test(value)) return store
  var next = copyStore(store)
  next.deviceId = value
  return next
}

function revisionCompare(a, b) {
  var left = isObject(a) ? a : {}
  var right = isObject(b) ? b : {}
  var leftCounter = Math.max(0, Math.floor(Number(left.counter) || 0))
  var rightCounter = Math.max(0, Math.floor(Number(right.counter) || 0))
  if (leftCounter !== rightCounter) return leftCounter < rightCounter ? -1 : 1
  // Legacy v1 records have no Lamport counter. Their timestamps are used only
  // against other legacy records; clock skew cannot dominate stamped edits.
  if (leftCounter === 0) {
    var leftTime = new Date(left.updatedAt || 0).getTime()
    var rightTime = new Date(right.updatedAt || 0).getTime()
    if (!isFinite(leftTime)) leftTime = 0
    if (!isFinite(rightTime)) rightTime = 0
    if (leftTime !== rightTime) return leftTime < rightTime ? -1 : 1
  }
  return trimmed(left.deviceId).localeCompare(trimmed(right.deviceId))
}

function maximumCounter(records, tombstones) {
  var maximum = 0
  var sources = [isObject(records) ? records : {}, isObject(tombstones) ? tombstones : {}]
  for (var s = 0; s < sources.length; s++) {
    for (var key in sources[s]) {
      if (!Object.prototype.hasOwnProperty.call(sources[s], key)) continue
      var revision = s === 0 ? recordRevision(sources[s][key]) : sources[s][key]
      maximum = Math.max(maximum, Math.floor(Number(revision.counter) || 0))
    }
  }
  return maximum
}

function maximumRevisionCounter(revisions) {
  var source = isObject(revisions) ? revisions : {}
  var maximum = 0
  for (var key in source) {
    if (!Object.prototype.hasOwnProperty.call(source, key)) continue
    maximum = Math.max(maximum,
      Math.floor(Number(source[key] && source[key].counter) || 0))
  }
  return maximum
}

function recordRevision(record) {
  if (!isObject(record)) return {}
  if (isObject(record._rev)) return record._rev
  return { counter: 0, deviceId: "", updatedAt: trimmed(record.updatedAt) }
}

function mergeRecordMap(localRecords, remoteRecords, localDeleted, remoteDeleted) {
  var local = isObject(localRecords) ? localRecords : {}
  var remote = isObject(remoteRecords) ? remoteRecords : {}
  var localTombs = isObject(localDeleted) ? localDeleted : {}
  var remoteTombs = isObject(remoteDeleted) ? remoteDeleted : {}
  var records = {}
  var tombstones = {}
  var keys = {}
  var key
  for (key in local) if (Object.prototype.hasOwnProperty.call(local, key)) keys[key] = true
  for (key in remote) if (Object.prototype.hasOwnProperty.call(remote, key)) keys[key] = true
  for (key in localTombs) if (Object.prototype.hasOwnProperty.call(localTombs, key)) keys[key] = true
  for (key in remoteTombs) if (Object.prototype.hasOwnProperty.call(remoteTombs, key)) keys[key] = true
  for (key in keys) {
    if (!Object.prototype.hasOwnProperty.call(keys, key)) continue
    var candidates = []
    if (isObject(local[key])) candidates.push({ deleted: false, value: local[key],
      rev: recordRevision(local[key]), local: true })
    if (isObject(remote[key])) candidates.push({ deleted: false, value: remote[key],
      rev: recordRevision(remote[key]), local: false })
    if (isObject(localTombs[key])) candidates.push({ deleted: true, value: localTombs[key],
      rev: localTombs[key], local: true })
    if (isObject(remoteTombs[key])) candidates.push({ deleted: true, value: remoteTombs[key],
      rev: remoteTombs[key], local: false })
    var winner = null
    for (var i = 0; i < candidates.length; i++) {
      if (!winner || revisionCompare(candidates[i].rev, winner.rev) > 0
          || (revisionCompare(candidates[i].rev, winner.rev) === 0
            && candidates[i].local && !winner.local))
        winner = candidates[i]
    }
    if (!winner) continue
    if (winner.deleted) tombstones[key] = copyObject(winner.value)
    else records[key] = copyObject(winner.value)
  }
  return { records: records, tombstones: tombstones }
}

function cloudDocument(store) {
  var source = copyStore(store)
  var cloudThreads = {}
  for (var threadId in source.threads) {
    if (!Object.prototype.hasOwnProperty.call(source.threads, threadId)) continue
    var thread = copyObject(source.threads[threadId])
    delete thread.destinationOverride
    delete thread.pile
    delete thread.placementLabel
    delete thread.syncPending
    cloudThreads[threadId] = thread
  }
  return {
    version: VERSION,
    account: source.account,
    senders: source.senders,
    domainRules: source.domainRules,
    // Thread metadata is synchronized for seen state and schedules. Gmail
    // labels remain authoritative for destination and pile placement.
    threads: cloudThreads,
    tombstones: source.tombstones,
    settings: {
      routeRepliesToInbox: source.settings.routeRepliesToInbox,
      historicalScreenerMonths: source.settings.historicalScreenerMonths
    },
    settingRevisions: source.settingRevisions
  }
}

function serializeCloud(store) {
  return JSON.stringify(cloudDocument(store))
}

function mergeCloud(store, remote) {
  if (!isObject(remote) || Number(remote.version) !== VERSION)
    return { ok: false, store: store, error: "Unsupported cloud workflow data" }
  if (normalizeAccountId(remote.account) !== normalizeAccountId(store.account))
    return { ok: false, store: store, error: "Cloud workflow data belongs to another account" }
  var next = copyStore(store)
  var remoteTombs = isObject(remote.tombstones) ? remote.tombstones : {}
  var senderMerge = mergeRecordMap(next.senders, remote.senders,
    next.tombstones.senders, remoteTombs.senders)
  var threadMerge = mergeRecordMap(next.threads, remote.threads,
    next.tombstones.threads, remoteTombs.threads)
  var domainMerge = mergeRecordMap(next.domainRules, remote.domainRules,
    next.tombstones.domainRules, remoteTombs.domainRules)
  next.senders = senderMerge.records
  next.threads = threadMerge.records
  next.domainRules = domainMerge.records
  next.tombstones = {
    senders: senderMerge.tombstones,
    threads: threadMerge.tombstones,
    domainRules: domainMerge.tombstones
  }
  var remoteSettings = isObject(remote.settings) ? remote.settings : {}
  var remoteSettingRevisions = isObject(remote.settingRevisions)
    ? remote.settingRevisions : {}
  var portableSettings = ["routeRepliesToInbox", "historicalScreenerMonths"]
  for (var settingIndex = 0; settingIndex < portableSettings.length; settingIndex++) {
    var settingName = portableSettings[settingIndex]
    if (remoteSettings[settingName] === undefined) continue
    var localRevision = next.settingRevisions[settingName] || {}
    var remoteRevision = remoteSettingRevisions[settingName] || {}
    var localHasRevision = Object.keys(localRevision).length > 0
    var remoteHasRevision = Object.keys(remoteRevision).length > 0
    var localIsDefault = settingName === "historicalScreenerMonths"
      ? next.settings[settingName] === 0
      : next.settings[settingName] === true
    if (revisionCompare(remoteRevision, localRevision) > 0
        || (!localHasRevision && !remoteHasRevision && localIsDefault)) {
      next.settings[settingName] = settingName === "historicalScreenerMonths"
        ? normalizeHistoricalScreenerMonths(remoteSettings[settingName])
        : remoteSettings[settingName] !== false
      next.settingRevisions[settingName] = copyObject(remoteRevision)
    }
  }
  next.syncCounter = Math.max(next.syncCounter,
    maximumCounter(remote.senders, remoteTombs.senders),
    maximumCounter(remote.threads, remoteTombs.threads),
    maximumCounter(remote.domainRules, remoteTombs.domainRules),
    maximumRevisionCounter(remoteSettingRevisions))
  next.cloud.drivePending = true
  return { ok: true, store: next, error: "" }
}

function setCloudState(store, values) {
  var next = copyStore(store)
  var source = isObject(values) ? values : {}
  for (var key in source) {
    if (Object.prototype.hasOwnProperty.call(source, key)
        && Object.prototype.hasOwnProperty.call(next.cloud, key))
      next.cloud[key] = source[key]
  }
  return next
}

function queueGmailOperation(store, threadId, labelName, now) {
  var id = normalizeThreadId(threadId)
  var label = trimmed(labelName)
  if (!id || !label) return store
  var next = copyStore(store)
  var queue = next.cloud.gmailOutbox.slice()
  for (var i = 0; i < queue.length; i++) {
    if (queue[i].threadId === id) {
      queue[i] = { threadId: id, labelName: label, queuedAt: timestamp(now) }
      next.cloud.gmailOutbox = queue
      return next
    }
  }
  queue.push({ threadId: id, labelName: label, queuedAt: timestamp(now) })
  next.cloud.gmailOutbox = queue
  return next
}

function acknowledgeGmailOperation(store, threadId, labelName, queuedAt) {
  var id = normalizeThreadId(threadId)
  if (!id) return store
  var next = copyStore(store)
  var queue = []
  for (var i = 0; i < next.cloud.gmailOutbox.length; i++) {
    var operation = next.cloud.gmailOutbox[i]
    var exact = operation.threadId === id
      && String(operation.labelName || "") === String(labelName || "")
      && String(operation.queuedAt || "") === String(queuedAt || "")
    if (!exact)
      queue.push(next.cloud.gmailOutbox[i])
  }
  next.cloud.gmailOutbox = queue
  return next
}

function placementFromLabels(labelIds, labelIdsByName, preferredLabelId) {
  var current = Array.isArray(labelIds) ? labelIds : []
  var ids = isObject(labelIdsByName) ? labelIdsByName : {}
  var priority = [
    "bubble_up", "reply_later", "set_aside", "screened_out",
    "screener", "paper_trail", "feed", "inbox"
  ]
  var matches = []
  var preferredKey = ""
  for (var i = 0; i < priority.length; i++) {
    var id = String(ids[LABEL_NAMES[priority[i]]] || "")
    if (id && current.indexOf(id) >= 0) {
      matches.push(priority[i])
      if (id === String(preferredLabelId || "")) preferredKey = priority[i]
    }
  }
  if (matches.length === 0) return null
  var key = preferredKey || matches[0]
  var destination = key === "feed" || key === "paper_trail"
    || key === "inbox" || key === "screener" || key === "screened_out"
    ? key : "inbox"
  return {
    labelKey: key,
    labelName: LABEL_NAMES[key],
    destination: destination,
    pile: key === "reply_later" ? "reply_later"
      : (key === "set_aside" ? "set_aside" : null),
    bubble: key === "bubble_up",
    conflict: matches.length > 1
  }
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
  if (version === 1) {
    var migrated = copyStore(raw)
    migrated.version = VERSION
    // Existing records already have timestamps. Treat them as revision zero;
    // the first post-upgrade edit receives a device-stamped revision.
    return { ok: true, store: migrated }
  }
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
      || !isObject(raw.domainRules) || !isObject(raw.settings)
      || !isObject(raw.tombstones) || !isObject(raw.cloud))
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
