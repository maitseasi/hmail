import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// The message list. A Repeater in a Column rather than a ListView because the
// panel already owns one Flickable and nesting a second scroller inside it
// gives every wheel event two plausible targets.
Column {
  id: root

  required property var service
  required property color textColor
  required property color accentColor
  required property color dimColor
  required property string panelFontFamily
  property string cursorId: ""
  property var viewport: null
  readonly property string viewTitle: {
    if (!service || !service.workflowEnabled) return ""
    var labels = {
      screener: "SCREENER",
      inbox: "",
      feed: "FEED",
      paper_trail: "PAPER TRAIL",
      reply_later: "REPLY LATER",
      set_aside: "SET ASIDE",
      bubble_up: "BUBBLE UP",
      previously_seen: "PREVIOUSLY SEEN",
      everything: "EVERYTHING"
    }
    return labels[service.workflowKey] !== undefined
      ? labels[service.workflowKey] : "WORKFLOW"
  }

  signal messageActivated(string id)
  signal rowHovered(string id, bool isHovered)
  signal menuRequested(string id, real sceneX, real sceneY)

  function ensureCursorVisible() {
    if (!viewport || !service) return
    var index = Model.indexById(service.messages, cursorId)
    if (index < 0) return
    var item = rows.itemAt(index)
    if (!item) return
    var top = root.y + item.y
    var bottom = top + item.height
    if (top < viewport.contentY) viewport.contentY = Math.max(0, top)
    else if (bottom > viewport.contentY + viewport.height)
      viewport.contentY = Math.max(0, bottom - viewport.height)
  }

  width: parent ? parent.width : 0
  spacing: Style.space(2)

  Text {
    visible: root.viewTitle !== ""
    width: parent.width
    leftPadding: Style.space(8)
    rightPadding: Style.space(8)
    topPadding: Style.space(5)
    bottomPadding: Style.space(6)
    text: root.viewTitle
    textFormat: Text.PlainText
    color: root.dimColor
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  WorkflowActionBar {
    width: parent.width
    service: root.service
    messageId: root.cursorId
    textColor: root.textColor
    accentColor: root.accentColor
    dimColor: root.dimColor
    panelFontFamily: root.panelFontFamily
  }

  Repeater {
    id: rows
    model: root.service.messages

    Column {
      id: entry
      required property var modelData
      required property int index
      width: root.width
      spacing: Style.space(2)

      Text {
        visible: root.service.workflowEnabled && root.service.workflowKey === "inbox"
          && (entry.index === 0 || entry.index === root.service.workflowNewCount)
        width: parent.width
        leftPadding: Style.space(8)
        topPadding: entry.index === 0 ? Style.space(5) : Style.space(14)
        bottomPadding: Style.space(5)
        text: entry.index < root.service.workflowNewCount
          ? "NEW FOR YOU" : "PREVIOUSLY SEEN"
        textFormat: Text.PlainText
        color: root.dimColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      MessageRow {
        width: parent.width
        summary: entry.modelData
        textColor: root.textColor
        accentColor: root.accentColor
        dimColor: root.dimColor
        panelFontFamily: root.panelFontFamily
        dense: root.service.workflowEnabled && root.service.workflowKey === "paper_trail"
        senderFirst: root.service.workflowEnabled && root.service.workflowKey === "screener"
        hasCursor: root.cursorId === entry.modelData.id
        selected: root.service.selectedId === entry.modelData.id
        onActivated: root.messageActivated(entry.modelData.id)
        onStarToggled: root.service.toggleStar(entry.modelData.id)
        onArchiveRequested: root.service.act(entry.modelData.id, "archive")
        onTrashRequested: root.service.act(entry.modelData.id, "trash")
        onHovered: function(isHovered) { root.rowHovered(entry.modelData.id, isHovered) }
        onMenuRequested: function(sceneX, sceneY) {
          root.menuRequested(entry.modelData.id, sceneX, sceneY)
        }
      }
    }
  }

  // Three states share this slot, and only one of them is an error: still
  // loading, loaded and empty, or nothing loaded yet.
  Item {
    width: parent.width
    visible: root.service.messages.length === 0
    implicitHeight: Style.space(70)

    Text {
      anchors.centerIn: parent
      width: parent.width - Style.space(20)
      horizontalAlignment: Text.AlignHCenter
      text: root.service.listLoading
        ? "Loading…"
        : (root.service.listLoaded
          ? (root.service.searchQuery !== "" ? "Nothing matches that search"
            : (root.service.workflowEnabled && root.service.workflowKey === "screener"
              ? "Nothing waiting. You're all caught up."
              : (root.service.workflowEnabled && root.service.workflowKey === "feed"
                ? "No senders are delivering here yet."
                : "Nothing here")))
          : "")
      color: root.dimColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }
  }

  Item {
    width: parent.width
    visible: root.service.hasMore || root.service.messages.length > 0
    implicitHeight: Style.space(30)

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: root.service.resultSummary
      color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.42)
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
    }

    Button {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: root.service.hasMore
      text: root.service.listLoading ? "Loading…" : "Load more"
      foreground: root.textColor
      bordered: false
      fontSize: Style.font.caption
      enabled: !root.service.listLoading
      onClicked: root.service.loadMore()
    }
  }
}
