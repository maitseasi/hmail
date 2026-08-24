import QtQuick

import "DriveApi.js" as Drive
import "OAuth.js" as OAuth
import "Workflow.js" as Workflow

// Per-account convergence controller. Gmail owns thread placement; Drive's
// hidden appDataFolder owns portable workflow metadata; WorkflowStore remains
// the offline replica and durable retry queue.
Item {
  id: root

  visible: false
  width: 0
  height: 0

  required property var auth
  required property var driveApi
  required property var gmailApi
  required property var workflowStore
  property var labelIdsByName: ({})
  property bool busy: false
  property bool awaitingConsent: false
  property bool applyingRemote: false
  property bool syncAgain: false
  property bool gmailRequestInFlight: false
  property int conflictRetries: 0
  property var historyLabelWinners: ({})
  property bool historyRecoveryPending: false
  property string status: ""
  property string lastError: ""
  readonly property bool cloudEnabled: workflowStore && workflowStore.loaded
    && workflowStore.store.cloud.enabled
  readonly property string lastSyncAt: cloudEnabled
    ? String(workflowStore.store.cloud.lastSyncAt || "") : ""

  signal refreshRequested()
  signal profileRefreshRequested()
  signal labelsRequired()
  signal activated()

  function enable() {
    if (!workflowStore || !workflowStore.writable || busy) return
    awaitingConsent = true
    status = "Waiting for private Drive permission"
    lastError = ""
    auth.requestCloudAccess()
  }

  function disable() {
    if (!workflowStore || !workflowStore.writable) return
    awaitingConsent = false
    workflowStore.setCloudState({ enabled: false, lastError: "" })
    status = "Cloud sync off"
    lastError = ""
  }

  function consentCompleted() {
    if (!awaitingConsent) return
    awaitingConsent = false
    var missing = OAuth.missingScopes(auth.grantedScope, OAuth.cloudScopes())
    if (missing.length > 0) {
      lastError = auth.lastError || "Google did not grant private Drive access"
      status = "Cloud sync needs permission"
      return
    }
    workflowStore.setSetting("mirrorGmailLabels", true)
    workflowStore.setCloudState({
      enabled: true,
      drivePending: true,
      lastError: ""
    })
    labelsRequired()
    syncNow()
  }

  function syncNow() {
    if (!cloudEnabled || busy || !workflowStore.writable) return
    busy = true
    status = "Pulling workflow data"
    lastError = ""
    driveApi.listWorkflowFiles(function(files, error, statusCode) {
      if (error) {
        root.fail(error, root.transientDriveStatus(statusCode, error))
        return
      }
      root.pullFiles(files, 0, files.length > 0 ? files[0].id : "",
        files.length > 0 ? "" : "")
    })
  }

  function pullFiles(files, index, targetId, targetEtag) {
    if (index >= files.length) {
      pushMerged(targetId, targetEtag)
      return
    }
    driveApi.downloadWorkflow(files[index].id, function(text, etag, error, statusCode) {
      if (error) {
        root.fail(error, root.transientDriveStatus(statusCode, error))
        return
      }
      var parsed = Workflow.parseJson(text)
      if (!parsed.ok) {
        root.fail("Cloud workflow data is malformed; local data was kept", false)
        return
      }
      applyingRemote = true
      var merged = workflowStore.mergeCloud(parsed.value)
      applyingRemote = false
      if (!merged.ok) {
        root.fail(merged.error, false)
        return
      }
      var selectedEtag = files[index].id === targetId ? etag : targetEtag
      pullFiles(files, index + 1, targetId, selectedEtag)
    })
  }

  function pushMerged(fileId, etag) {
    status = "Saving workflow data"
    var text = Workflow.serializeCloud(workflowStore.store)
    if (!fileId) {
      driveApi.createWorkflow(text, function(payload, nextEtag, error, statusCode) {
        if (error) {
          root.fail(error, root.transientDriveStatus(statusCode, error))
          return
        }
        root.finishSync(String(payload && payload.id || ""), nextEtag)
      })
      return
    }
    driveApi.updateWorkflow(fileId, text, etag,
      function(payload, nextEtag, error, statusCode) {
        if (statusCode === 412 && conflictRetries < 2) {
          conflictRetries++
          busy = false
          syncNow()
          return
        }
        if (error) {
          root.fail(error, root.transientDriveStatus(statusCode, error))
          return
        }
        root.finishSync(fileId, nextEtag)
      })
  }

  function finishSync(fileId, etag) {
    conflictRetries = 0
    var pendingAgain = syncAgain
    syncAgain = false
    applyingRemote = true
    workflowStore.setCloudState({
      fileId: fileId,
      etag: etag,
      lastSyncAt: new Date().toISOString(),
      lastError: "",
      drivePending: pendingAgain
    })
    applyingRemote = false
    busy = false
    status = "Synced"
    activated()
    processGmailOutbox()
    if (pendingAgain) driveDebounce.restart()
  }

  function transientDriveStatus(statusCode, error) {
    var status = Number(statusCode) || 0
    if (status === 0 || status === 429 || status >= 500) return true
    // Drive reports quota exhaustion as 403 rateLimitExceeded /
    // userRateLimitExceeded; those recover on their own, unlike scope or
    // disabled-API 403s.
    return status === 403 && /rate ?limit/i.test(String(error || ""))
  }

  function fail(error, retryable) {
    var safe = String(error || "Workflow sync failed")
    applyingRemote = true
    workflowStore.setCloudState({ lastError: safe })
    applyingRemote = false
    busy = false
    lastError = safe
    status = "Sync paused"
    if (cloudEnabled && retryable === true) driveRetryTimer.restart()
  }

  function reconcileMessages(messages) {
    if (!cloudEnabled || !workflowStore.writable) return
    var list = Array.isArray(messages) ? messages : []
    var names = Workflow.workflowLabelNames()
    for (var i = 0; i < list.length; i++) {
      var summary = list[i]
      var threadId = Workflow.threadIdFor(summary)
      if (!threadId) continue
      var placement = Workflow.placementFromLabels(summary.labelIds, labelIdsByName,
        historyLabelWinners[threadId])
      if (placement) {
        var state = {
          destinationOverride: placement.destination,
          pile: placement.pile,
          placementLabel: placement.labelKey
        }
        var existing = workflowStore.getThreadState(threadId) || {}
        if (String(existing.destinationOverride || "") !== placement.destination
            || String(existing.pile || "") !== String(placement.pile || "")
            || String(existing.placementLabel || "") !== placement.labelKey)
          workflowStore.projectThreadPlacement(threadId, state)
        if (placement.conflict)
          workflowStore.queueGmailOperation(threadId, placement.labelName)
      } else {
        var destination = Workflow.classifyIncoming(workflowStore.store, summary)
        var localState = workflowStore.getThreadState(threadId) || {}
        var labelName = Workflow.labelNameFor(destination, localState)
        if (labelName) workflowStore.queueGmailOperation(threadId, labelName)
      }
    }
    processGmailOutbox()
  }

  function processGmailOutbox() {
    if (!cloudEnabled || busy || gmailRequestInFlight) return
    var queue = workflowStore.store.cloud.gmailOutbox
    if (!Array.isArray(queue) || queue.length === 0) return
    var operation = queue[0]
    var wantedId = String(labelIdsByName[operation.labelName] || "")
    if (!wantedId) {
      labelsRequired()
      return
    }
    var remove = []
    var names = Workflow.workflowLabelNames()
    for (var i = 0; i < names.length; i++) {
      var id = String(labelIdsByName[names[i]] || "")
      if (id && id !== wantedId) remove.push(id)
    }
    gmailRequestInFlight = true
    gmailApi.modifyThread(operation.threadId, [wantedId], remove,
      function(payload, error) {
        root.gmailRequestInFlight = false
        if (error) {
          root.lastError = error
          root.status = "Gmail placement retry pending"
          retryTimer.restart()
          return
        }
        workflowStore.acknowledgeGmailOperation(
          operation.threadId, operation.labelName, operation.queuedAt)
        root.processGmailOutbox()
      })
  }

  function pollHistory() {
    if (!cloudEnabled || busy) return
    var historyId = String(workflowStore.store.cloud.historyId || "")
    if (!historyId) return
    pollHistoryPage(historyId, "", false)
  }

  function pollHistoryPage(historyId, pageToken, touched) {
    gmailApi.listHistory(historyId, pageToken, function(result, error, expired) {
      if (expired) {
        workflowStore.setCloudState({ historyId: "" })
        historyRecoveryPending = true
        profileRefreshRequested()
        return
      }
      if (error || !result) return
      var changed = touched || result.threadIds.length > 0
      var winners = {}
      for (var previousThread in root.historyLabelWinners) {
        if (Object.prototype.hasOwnProperty.call(
            root.historyLabelWinners, previousThread))
          winners[previousThread] = root.historyLabelWinners[previousThread]
      }
      var pageWinners = result.latestLabelIdByThread || {}
      for (var threadId in pageWinners) {
        if (Object.prototype.hasOwnProperty.call(pageWinners, threadId))
          winners[threadId] = pageWinners[threadId]
      }
      root.historyLabelWinners = winners
      if (result.nextPageToken) {
        root.pollHistoryPage(historyId, result.nextPageToken, changed)
        return
      }
      if (changed) refreshRequested()
      if (result.historyId)
        workflowStore.setCloudState({ historyId: result.historyId })
    })
  }

  function establishHistory(historyId) {
    if (!cloudEnabled || !historyId) return
    historyRecoveryPending = false
    historyRetryTimer.stop()
    if (!workflowStore.store.cloud.historyId)
      workflowStore.setCloudState({ historyId: String(historyId) })
  }

  function historyRecoveryFailed(error) {
    historyRecoveryPending = true
    lastError = String(error || "Could not rebuild Gmail workflow state")
    status = "Gmail reconciliation retry pending"
    historyRetryTimer.restart()
  }

  Connections {
    target: root.auth
    function onLoginSucceeded() {
      if (root.awaitingConsent) root.consentCompleted()
    }
    function onCloudConsentSucceeded() { root.consentCompleted() }
  }

  Connections {
    target: root.workflowStore
    function onRestored() {
      if (root.cloudEnabled) {
        root.labelsRequired()
        root.syncNow()
      }
    }
    function onChanged() {
      if (!root.cloudEnabled || root.applyingRemote
          || !root.workflowStore.store.cloud.drivePending) return
      if (root.busy) {
        root.syncAgain = true
        return
      }
      driveDebounce.restart()
    }
  }

  Timer {
    id: driveDebounce
    interval: 1200
    onTriggered: root.syncNow()
  }

  Timer {
    id: retryTimer
    interval: 30000
    onTriggered: root.processGmailOutbox()
  }

  Timer {
    id: driveRetryTimer
    interval: 30000
    onTriggered: root.syncNow()
  }

  Timer {
    id: historyRetryTimer
    interval: 30000
    onTriggered: {
      if (root.historyRecoveryPending) root.profileRefreshRequested()
    }
  }

  Timer {
    interval: 120000
    repeat: true
    running: root.cloudEnabled
    onTriggered: root.pollHistory()
  }
}
