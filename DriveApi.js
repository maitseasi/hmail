.pragma library

// Google Drive appDataFolder helpers. Authenticated URLs are built only from
// these fixed bases; workflow data must never be sent to an arbitrary host.
var API_BASE = "https://www.googleapis.com/drive/v3"
var UPLOAD_BASE = "https://www.googleapis.com/upload/drive/v3"
var FILE_NAME = "hmail-workflow-v2.json"

function encode(value) {
  return encodeURIComponent(String(value === undefined || value === null ? "" : value))
}

function appendQuery(url, values) {
  var parts = []
  var source = values || {}
  for (var key in source) {
    if (!Object.prototype.hasOwnProperty.call(source, key)) continue
    var value = source[key]
    if (value === undefined || value === null || value === "") continue
    parts.push(encode(key) + "=" + encode(value))
  }
  return parts.length > 0 ? url + "?" + parts.join("&") : url
}

function safeUrl(base, path, query) {
  if (base !== API_BASE && base !== UPLOAD_BASE) return ""
  var value = String(path || "")
  if (value.charAt(0) !== "/" || value.indexOf("..") >= 0
      || /[\s<>"'\\]/.test(value)) return ""
  return appendQuery(base + value, query)
}

function filePath(id) {
  var value = String(id || "")
  return /^[A-Za-z0-9_-]+$/.test(value) ? "/files/" + encode(value) : ""
}

function listUrl() {
  return safeUrl(API_BASE, "/files", {
    spaces: "appDataFolder",
    q: "name = '" + FILE_NAME + "' and trashed = false",
    fields: "files(id,name,modifiedTime,version)"
  })
}

function downloadUrl(id) {
  var path = filePath(id)
  return path ? safeUrl(API_BASE, path, { alt: "media" }) : ""
}

function createUrl() {
  return safeUrl(UPLOAD_BASE, "/files", {
    uploadType: "multipart",
    fields: "id,name,modifiedTime,version"
  })
}

function updateUrl(id) {
  var path = filePath(id)
  return path ? safeUrl(UPLOAD_BASE, path, {
    uploadType: "media",
    fields: "id,name,modifiedTime,version"
  }) : ""
}

function parseJson(text, fallback) {
  try {
    var parsed = JSON.parse(String(text || ""))
    return parsed === null || parsed === undefined ? fallback : parsed
  } catch (error) {
    return fallback
  }
}

function parseFiles(payload) {
  var source = payload && Array.isArray(payload.files) ? payload.files : []
  var out = []
  for (var i = 0; i < source.length; i++) {
    var id = String(source[i] && source[i].id || "")
    if (!filePath(id) || String(source[i].name || "") !== FILE_NAME) continue
    out.push({
      id: id,
      name: FILE_NAME,
      modifiedTime: String(source[i].modifiedTime || ""),
      version: String(source[i].version || "")
    })
  }
  out.sort(function(a, b) { return a.id.localeCompare(b.id) })
  return out
}

function multipartBody(jsonText, boundary) {
  var safeBoundary = String(boundary || "")
  if (!/^[A-Za-z0-9_-]{16,80}$/.test(safeBoundary)) return ""
  var metadata = JSON.stringify({
    name: FILE_NAME,
    parents: ["appDataFolder"],
    mimeType: "application/json"
  })
  return "--" + safeBoundary + "\r\n"
    + "Content-Type: application/json; charset=UTF-8\r\n\r\n"
    + metadata + "\r\n"
    + "--" + safeBoundary + "\r\n"
    + "Content-Type: application/json\r\n\r\n"
    + String(jsonText || "") + "\r\n"
    + "--" + safeBoundary + "--\r\n"
}

function redact(text) {
  return String(text === undefined || text === null ? "" : text)
    .replace(/(access_token|refresh_token|client_secret)=[^&\s"']+/gi, "$1=[redacted]")
    .replace(/\bya29\.[A-Za-z0-9._-]+/g, "[redacted]")
}

function responseError(status, payload) {
  var detail = payload && payload.error
    ? String(payload.error.message || payload.error_description || payload.error)
    : ""
  if (status === 401) return "Google rejected the Drive session. Reconnect cloud sync"
  if (status === 403 && /Drive API has not been used|disabled/i.test(detail))
    return "Enable the Google Drive API for this OAuth project"
  if (status === 403 && /insufficient|scope|permission/i.test(detail))
    return "Reconnect Google to grant private app-data access"
  if (status === 412) return "Cloud workflow data changed on another device"
  if (status === 429) return "Google Drive is rate limiting workflow sync"
  if (status === 0) return "Could not reach Google Drive"
  if (status >= 500) return "Google Drive is temporarily unavailable"
  return detail ? redact(detail) : "Google Drive could not synchronize workflow data"
}
