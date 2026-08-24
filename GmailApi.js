.pragma library

// URL construction and response shaping for the Gmail REST API. No transport
// lives here — GmailApi.qml owns XMLHttpRequest, this file owns every string
// and every decision about what a response means, which is what the tests can
// reach without a compositor.

var API_BASE = "https://gmail.googleapis.com/gmail/v1"
var WEB_BASE = "https://mail.google.com/mail/u"

// System labels the panel treats as mailboxes. Gmail returns these ids for
// every account regardless of language, unlike user labels whose names are
// whatever the user typed.
var SYSTEM_LABELS = {
  INBOX: "Inbox",
  STARRED: "Starred",
  IMPORTANT: "Important",
  SENT: "Sent",
  DRAFT: "Drafts",
  SPAM: "Spam",
  TRASH: "Trash",
  UNREAD: "Unread",
  CATEGORY_PERSONAL: "Personal",
  CATEGORY_SOCIAL: "Social",
  CATEGORY_PROMOTIONS: "Promotions",
  CATEGORY_UPDATES: "Updates",
  CATEGORY_FORUMS: "Forums"
}

function encode(value) {
  return encodeURIComponent(String(value === undefined || value === null ? "" : value))
}

// Query values may repeat (metadataHeaders, labelIds), so an array value
// becomes one key=value pair per entry rather than a joined string.
function appendQuery(url, values) {
  if (!values) return url
  var parts = []
  for (var key in values) {
    var value = values[key]
    if (value === undefined || value === null || value === "") continue
    if (Array.isArray(value)) {
      for (var i = 0; i < value.length; i++) {
        if (value[i] === undefined || value[i] === null || value[i] === "") continue
        parts.push(encode(key) + "=" + encode(value[i]))
      }
    } else {
      parts.push(encode(key) + "=" + encode(value))
    }
  }
  if (parts.length === 0) return url
  return url + (url.indexOf("?") < 0 ? "?" : "&") + parts.join("&")
}

// Every request goes through here, so a path that somehow arrived from a
// response body cannot point the authenticated client at another host.
function safeApiUrl(path) {
  var value = String(path || "")
  if (value.charAt(0) !== "/") return ""
  if (value.indexOf("..") >= 0) return ""
  if (/[\s<>"'\\]/.test(value)) return ""
  return API_BASE + value
}

function parseJson(text, fallback) {
  try {
    var parsed = JSON.parse(String(text || ""))
    return parsed === null || parsed === undefined ? fallback : parsed
  } catch (e) {
    return fallback
  }
}

function redact(text) {
  return String(text === undefined || text === null ? "" : text)
    .replace(/(access_token|refresh_token|client_secret)=[^&\s"']+/gi, "$1=[redacted]")
    .replace(/\bya29\.[A-Za-z0-9._-]+/g, "[redacted]")
}

// Gmail's failures are worth translating: the raw messages are written for
// somebody reading a server log, not for somebody who just clicked Archive.
function responseError(status, payload, fallback) {
  var detail = ""
  if (payload && payload.error) {
    if (typeof payload.error === "string") detail = payload.error_description || payload.error
    else detail = payload.error.message || ""
  }
  var reason = ""
  if (payload && payload.error && payload.error.errors && payload.error.errors.length > 0)
    reason = String(payload.error.errors[0].reason || "")

  if (status === 401) return "Google rejected the session. Sign in again"
  if (status === 403 && reason === "rateLimitExceeded") return "Gmail is rate limiting this account. Try again shortly"
  if (status === 403 && /Gmail API has not been used/i.test(detail))
    return "The Gmail API is not enabled for this Google Cloud project"
  if (status === 403) return detail ? redact(detail) : "Google refused this request"
  if (status === 404) return "That message is no longer in the mailbox"
  if (status === 429) return "Gmail is rate limiting this account. Try again shortly"
  if (status === 0) return "Could not reach Gmail. Check the network connection"
  if (status >= 500) return "Gmail is having trouble right now. Try again shortly"
  if (detail) return redact(detail)
  return fallback || "Gmail could not complete this request"
}

function rateLimitSuffix(retryAfter) {
  var seconds = Math.ceil(Number(retryAfter))
  if (!isFinite(seconds) || seconds <= 0) return ""
  if (seconds < 60) return " (retry in " + seconds + "s)"
  return " (retry in " + Math.ceil(seconds / 60) + " min)"
}

// ------------------------------------------------------------------ paths

function messagesPath() { return "/users/me/messages" }
function messagePath(id) { return "/users/me/messages/" + encode(id) }
function modifyPath(id) { return "/users/me/messages/" + encode(id) + "/modify" }
function trashPath(id) { return "/users/me/messages/" + encode(id) + "/trash" }
function untrashPath(id) { return "/users/me/messages/" + encode(id) + "/untrash" }
function batchModifyPath() { return "/users/me/messages/batchModify" }
function sendPath() { return "/users/me/messages/send" }
function threadPath(id) { return "/users/me/threads/" + encode(id) }
function modifyThreadPath(id) { return "/users/me/threads/" + encode(id) + "/modify" }
function labelsPath() { return "/users/me/labels" }
function labelPath(id) { return "/users/me/labels/" + encode(id) }
function profilePath() { return "/users/me/profile" }
function historyPath() { return "/users/me/history" }
function attachmentPath(messageId, attachmentId) {
  return "/users/me/messages/" + encode(messageId) + "/attachments/" + encode(attachmentId)
}

function listQuery(query, maxResults, pageToken) {
  return {
    q: String(query || "").trim(),
    maxResults: Math.max(1, Math.min(100, Math.floor(Number(maxResults) || 25))),
    pageToken: String(pageToken || "")
  }
}

// `metadata` is a quarter of the payload of `full` and is all a list row needs.
var LIST_HEADERS = ["From", "To", "Subject", "Date", "List-Unsubscribe"]

function metadataQuery() {
  return { format: "metadata", metadataHeaders: LIST_HEADERS }
}

function fullQuery() {
  return { format: "full" }
}

function rawQuery() {
  return { format: "raw" }
}

function historyQuery(startHistoryId, pageToken) {
  return {
    startHistoryId: String(startHistoryId || ""),
    historyTypes: ["labelAdded", "labelRemoved"],
    pageToken: String(pageToken || ""),
    maxResults: 100
  }
}

function parseHistory(payload) {
  var body = payload && typeof payload === "object" ? payload : {}
  var history = Array.isArray(body.history) ? body.history : []
  var threadIds = []
  var seen = {}
  var latestLabelIdByThread = {}
  for (var i = 0; i < history.length; i++) {
    var groups = ["labelsAdded", "labelsRemoved"]
    for (var g = 0; g < groups.length; g++) {
      var entries = Array.isArray(history[i][groups[g]]) ? history[i][groups[g]] : []
      for (var j = 0; j < entries.length; j++) {
        var messages = entries[j] && Array.isArray(entries[j].messages)
          ? entries[j].messages : []
        for (var k = 0; k < messages.length; k++) {
          var threadId = String(messages[k] && messages[k].threadId || "")
          if (threadId && !seen[threadId]) {
            seen[threadId] = true
            threadIds.push(threadId)
          }
          var changedLabels = Array.isArray(entries[j].labelIds)
            ? entries[j].labelIds : []
          if (threadId && changedLabels.length > 0) {
            if (groups[g] === "labelsAdded")
              latestLabelIdByThread[threadId] =
                String(changedLabels[changedLabels.length - 1] || "")
            else if (changedLabels.indexOf(latestLabelIdByThread[threadId]) >= 0)
              latestLabelIdByThread[threadId] = ""
          }
        }
      }
    }
  }
  return {
    historyId: String(body.historyId || ""),
    nextPageToken: String(body.nextPageToken || ""),
    threadIds: threadIds,
    latestLabelIdByThread: latestLabelIdByThread
  }
}

function parseThread(payload) {
  var body = payload && typeof payload === "object" ? payload : {}
  var messages = arrayValues(body.messages).slice()
  messages.sort(function(a, b) {
    return (Number(a && a.internalDate) || 0) - (Number(b && b.internalDate) || 0)
  })
  return {
    id: String(body.id || ""),
    historyId: String(body.historyId || ""),
    messages: messages
  }
}

// ---------------------------------------------------------------- parsing

function arrayValues(value) {
  return Array.isArray(value) ? value : []
}

function parseMessageList(payload) {
  var body = payload && typeof payload === "object" ? payload : {}
  var messages = arrayValues(body.messages)
  var ids = []
  var threadIds = []
  for (var i = 0; i < messages.length; i++) {
    var id = String(messages[i] && messages[i].id ? messages[i].id : "")
    if (!id) continue
    ids.push(id)
    threadIds.push(String(messages[i].threadId || ""))
  }
  return {
    ids: ids,
    threadIds: threadIds,
    nextPageToken: String(body.nextPageToken || ""),
    // Gmail is explicit that this is an estimate; the panel labels it as one.
    estimate: Math.max(0, Math.floor(Number(body.resultSizeEstimate) || 0))
  }
}

function labelDisplayName(label) {
  var id = String(label && label.id ? label.id : "")
  if (SYSTEM_LABELS[id]) return SYSTEM_LABELS[id]
  return String(label && label.name ? label.name : id)
}

function parseLabels(payload) {
  var labels = arrayValues(payload && payload.labels)
  var result = []
  for (var i = 0; i < labels.length; i++) {
    var label = labels[i]
    var id = String(label && label.id ? label.id : "")
    if (!id) continue
    result.push({
      id: id,
      name: labelDisplayName(label),
      rawName: String(label.name || id),
      system: String(label.type || "user") === "system",
      unread: Math.max(0, Math.floor(Number(label.messagesUnread) || 0)),
      total: Math.max(0, Math.floor(Number(label.messagesTotal) || 0)),
      threadsUnread: Math.max(0, Math.floor(Number(label.threadsUnread) || 0))
    })
  }
  return result
}

function parseLabel(payload) {
  var labels = parseLabels({ labels: [payload] })
  return labels.length > 0 ? labels[0] : null
}

function createLabelBody(name) {
  return {
    name: String(name || "").trim(),
    labelListVisibility: "labelShow",
    messageListVisibility: "show"
  }
}

function parseLabelCounts(payload) {
  var body = payload && typeof payload === "object" ? payload : {}
  return {
    id: String(body.id || ""),
    unread: Math.max(0, Math.floor(Number(body.messagesUnread) || 0)),
    total: Math.max(0, Math.floor(Number(body.messagesTotal) || 0)),
    threadsUnread: Math.max(0, Math.floor(Number(body.threadsUnread) || 0))
  }
}

function parseProfile(payload) {
  var body = payload && typeof payload === "object" ? payload : {}
  return {
    email: String(body.emailAddress || ""),
    messagesTotal: Math.max(0, Math.floor(Number(body.messagesTotal) || 0)),
    threadsTotal: Math.max(0, Math.floor(Number(body.threadsTotal) || 0)),
    historyId: String(body.historyId || "")
  }
}

// --------------------------------------------------------------- browsing

// Gmail's web UI addresses accounts by index, not address, and there is no way
// to map one to the other from the API. Index 0 is right for the common
// single-account case and wrong in a way the user can see and fix, which beats
// a link that silently opens somebody else's mailbox.
function webMessageUrl(messageId, accountIndex) {
  var index = Math.max(0, Math.floor(Number(accountIndex) || 0))
  return WEB_BASE + "/" + index + "/#all/" + encode(messageId)
}

function webSearchUrl(query, accountIndex) {
  var index = Math.max(0, Math.floor(Number(accountIndex) || 0))
  return WEB_BASE + "/" + index + "/#search/" + encode(String(query || ""))
}
