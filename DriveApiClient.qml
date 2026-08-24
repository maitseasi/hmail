import QtQuick

import "DriveApi.js" as Drive

// Authenticated transport dedicated to Drive's private appDataFolder. Keeping
// this separate from Gmail preserves both clients' fixed-host allowlists.
Item {
  id: root

  visible: false
  width: 0
  height: 0

  required property var auth
  property int inFlight: 0
  readonly property bool busy: inFlight > 0

  function request(method, url, body, contentType, etag, callback, retried) {
    if (String(url || "").indexOf(Drive.API_BASE + "/") !== 0
        && String(url || "").indexOf(Drive.UPLOAD_BASE + "/") !== 0) {
      if (typeof callback === "function")
        callback(0, null, "", "Refused an unsafe Google Drive URL")
      return
    }
    if (retried !== true) inFlight++
    auth.withAccessToken(function(token, tokenError) {
      if (!root) return
      if (!token) {
        root.inFlight = Math.max(0, root.inFlight - 1)
        if (typeof callback === "function")
          callback(0, null, "", tokenError || "Not signed in")
        return
      }
      var xhr = new XMLHttpRequest()
      xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE || !root) return
        var payload = Drive.parseJson(xhr.responseText, null)
        if (xhr.status === 401 && retried !== true) {
          root.auth.invalidateAccessToken()
          root.request(method, url, body, contentType, etag, callback, true)
          return
        }
        root.inFlight = Math.max(0, root.inFlight - 1)
        var ok = xhr.status >= 200 && xhr.status < 300
        var responseEtag = xhr.getResponseHeader
          ? String(xhr.getResponseHeader("ETag") || "") : ""
        if (typeof callback === "function")
          callback(xhr.status, payload, responseEtag,
            ok ? "" : Drive.responseError(xhr.status, payload))
      }
      xhr.open(String(method || "GET"), String(url))
      xhr.setRequestHeader("Authorization", "Bearer " + token)
      if (contentType) xhr.setRequestHeader("Content-Type", String(contentType))
      if (etag) xhr.setRequestHeader("If-Match", String(etag))
      if (body !== undefined && body !== null) xhr.send(String(body))
      else xhr.send()
    })
  }

  function listWorkflowFiles(callback) {
    request("GET", Drive.listUrl(), null, "", "", function(status, payload, etag, error) {
      if (typeof callback === "function")
        callback(error ? [] : Drive.parseFiles(payload), error, status)
    })
  }

  function downloadWorkflow(fileId, callback) {
    var url = Drive.downloadUrl(fileId)
    if (!url) {
      if (typeof callback === "function") callback("", "", "Invalid cloud file id")
      return
    }
    request("GET", url, null, "", "", function(status, payload, etag, error) {
      // Media downloads are parsed by the sync layer so malformed/newer data
      // can be rejected without replacing the local replica.
      if (typeof callback === "function")
        callback(error ? "" : JSON.stringify(payload), etag, error, status)
    })
  }

  function createWorkflow(jsonText, callback) {
    var boundary = "hmail_" + Date.now() + "_" + Math.floor(Math.random() * 1000000000)
    var body = Drive.multipartBody(jsonText, boundary)
    request("POST", Drive.createUrl(), body,
      "multipart/related; boundary=" + boundary, "", function(status, payload, etag, error) {
        if (typeof callback === "function")
          callback(error ? null : payload, etag, error, status)
      })
  }

  function updateWorkflow(fileId, jsonText, etag, callback) {
    var url = Drive.updateUrl(fileId)
    if (!url) {
      if (typeof callback === "function") callback(null, "", "Invalid cloud file id", 0)
      return
    }
    request("PATCH", url, jsonText, "application/json", etag,
      function(status, payload, nextEtag, error) {
        if (typeof callback === "function")
          callback(error ? null : payload, nextEtag, error, status)
      })
  }
}
