import QtQuick
import Quickshell
import Quickshell.Io

import "Cache.js" as Cache
import "Workflow.js" as Workflow

// Durable, per-account workflow metadata. Unlike CacheStore, this lives under
// XDG data and refuses to overwrite malformed or unsupported data.
Item {
  id: root

  visible: false
  width: 0
  height: 0

  readonly property string dataHome: Quickshell.env("XDG_DATA_HOME")
    || (Quickshell.env("HOME") + "/.local/share")
  readonly property string directory: dataHome + "/hmail/workflow"

  property string accountId: ""
  readonly property string path: accountId === ""
    ? ""
    : directory + "/" + Cache.fileName(accountId)

  property var store: Workflow.emptyStore(accountId)
  property bool loaded: false
  property bool writable: false
  property string lastError: ""
  property string preparingPath: ""

  signal restored()
  signal saved()
  signal changed()

  function commit(next) {
    if (!writable || !next || next === store) return false
    store = next
    scheduleSave()
    changed()
    return true
  }

  function getSenderRule(sender) {
    return Workflow.getSenderRule(store, sender)
  }

  function setSenderRule(sender, rule) {
    if (!writable) return false
    var next = Workflow.setSenderRule(store, sender, rule, Date.now())
    if (next === store) return false
    return commit(next)
  }

  function removeSenderRule(sender) {
    if (!writable) return false
    var next = Workflow.removeSenderRule(store, sender)
    if (next === store) return false
    return commit(next)
  }

  function getThreadState(threadId) {
    return Workflow.getThreadState(store, threadId)
  }

  function setThreadState(threadId, state) {
    if (!writable) return false
    var next = Workflow.setThreadState(store, threadId, state, Date.now())
    if (next === store) return false
    return commit(next)
  }

  function projectThreadPlacement(threadId, state) {
    if (!writable) return false
    var next = Workflow.projectThreadPlacement(store, threadId, state)
    if (next === store) return false
    // This changes only the local Gmail projection. Persist it for offline UI,
    // but do not mark Drive pending or create a portable revision.
    return commit(next)
  }

  function markSeen(threadId, messageId) {
    if (!writable) return false
    var next = Workflow.markSeen(store, threadId, messageId, Date.now())
    if (next === store) return false
    return commit(next)
  }

  function markUnseen(threadId) {
    if (!writable) return false
    var next = Workflow.markUnseen(store, threadId, Date.now())
    if (next === store) return false
    return commit(next)
  }

  function setPile(threadId, pile) {
    if (!writable) return false
    var next = Workflow.setPile(store, threadId, pile, Date.now())
    if (next === store) return false
    return commit(next)
  }

  function scheduleBubble(threadId, at) {
    if (!writable) return false
    var next = Workflow.scheduleBubble(store, threadId, at, Date.now())
    if (next === store) return false
    return commit(next)
  }

  function cancelBubble(threadId) {
    if (!writable) return false
    var next = Workflow.cancelBubble(store, threadId, Date.now())
    if (next === store) return false
    return commit(next)
  }

  function processDueBubbles() {
    if (!writable) return []
    var result = Workflow.processDueBubbles(store, Date.now())
    if (result.store !== store) commit(result.store)
    return result.threadIds
  }

  function setSetting(name, value) {
    if (!writable) return false
    var next = Workflow.setSetting(store, name, value)
    if (next === store) return false
    return commit(next)
  }

  function initializeExistingInbox(messages) {
    if (!writable) return false
    var next = Workflow.initializeExistingInbox(store, messages, Date.now())
    if (next === store) return false
    return commit(next)
  }

  function setCloudState(values) {
    if (!writable) return false
    return commit(Workflow.setCloudState(store, values))
  }

  function mergeCloud(remote) {
    if (!writable) return { ok: false, error: "Local workflow data is read-only" }
    var result = Workflow.mergeCloud(store, remote)
    if (result.ok) commit(result.store)
    return result
  }

  function queueGmailOperation(threadId, labelName) {
    if (!writable) return false
    return commit(Workflow.queueGmailOperation(store, threadId, labelName, Date.now()))
  }

  function acknowledgeGmailOperation(threadId, labelName, queuedAt) {
    if (!writable) return false
    return commit(Workflow.acknowledgeGmailOperation(
      store, threadId, labelName, queuedAt))
  }

  function scheduleSave() {
    if (loaded && writable) saveTimer.restart()
  }

  function prepare() {
    if (accountId === "" || preparer.running) return
    preparingPath = path
    // Pre-creating the target at 0600 means Quickshell's atomic replacement
    // preserves restrictive permissions from the first real write onward.
    preparer.command = [
      "sh", "-c",
      "umask 077; mkdir -p \"$1\" && chmod 700 \"$1\""
        + " && touch \"$2\" && chmod 600 \"$2\"",
      "sh", directory, preparingPath
    ]
    preparer.running = true
  }

  Component.onCompleted: prepare()

  onAccountIdChanged: {
    saveTimer.stop()
    loaded = false
    writable = false
    lastError = ""
    store = Workflow.emptyStore(accountId)
    if (accountId !== "") prepare()
  }

  Process {
    id: preparer
    onExited: function(exitCode, exitStatus) {
      if (root.preparingPath !== root.path) {
        root.prepare()
        return
      }
      if (exitCode !== 0) {
        root.loaded = true
        root.lastError = "Could not prepare the workflow data directory"
        root.restored()
        return
      }
      file.reload()
    }
  }

  FileView {
    id: file
    path: root.path
    atomicWrites: true
    printErrors: false

    onLoaded: {
      var result = Workflow.load(text(), root.accountId)
      root.loaded = true
      root.writable = result.ok
      root.lastError = result.error
      if (result.ok) {
        var next = result.store
        if (!next.deviceId) {
          var generated = "device_" + Date.now().toString(36)
            + "_" + Math.floor(Math.random() * 0x7fffffff).toString(36)
          next = Workflow.setDeviceId(next, generated)
        }
        root.store = next
        root.scheduleSave()
      }
      root.restored()
    }

    onLoadFailed: {
      root.loaded = true
      root.writable = false
      root.lastError = "Could not read workflow data"
      root.restored()
    }
  }

  Timer {
    id: saveTimer
    interval: 250
    onTriggered: {
      file.setText(Workflow.serialize(root.store))
      root.saved()
    }
  }
}
