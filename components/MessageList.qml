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

  readonly property bool isImbox: !!service && service.workflowEnabled
    && service.workflowKey === "inbox"
  readonly property bool isScreener: !!service && service.workflowEnabled
    && service.workflowKey === "screener"
  readonly property int screenerCount: service
    ? Number(service.workflowCounts["screener"] || 0) : 0

  readonly property string viewTitle: {
    if (!service || !service.workflowEnabled) return ""
    var labels = {
      screener: "SCREENER",
      inbox: "",
      feed: "THE FEED",
      paper_trail: "THE PAPER TRAIL",
      reply_later: "REPLY LATER",
      set_aside: "SET ASIDE",
      bubble_up: "BUBBLE UP",
      previously_seen: "PREVIOUSLY SEEN",
      everything: "EVERYTHING"
    }
    return labels[service.workflowKey] !== undefined
      ? labels[service.workflowKey] : "WORKFLOW"
  }

  property var checkedIds: ({})

  signal messageActivated(string id)
  signal rowHovered(string id, bool isHovered)
  signal menuRequested(string id, real sceneX, real sceneY)
  signal quickActionsRequested(string id, real sceneX, real sceneY)
  signal selectToggled(string id)
  signal screenerRequested()
  signal powerThroughRequested()

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

  // ── Screen N first-time senders ──────────────────────────────────────
  // Shown at the top of the Imbox whenever the Screener has new senders
  // waiting. Not shown inside the Screener itself.
  Item {
    visible: root.isImbox && root.screenerCount > 0
    width: parent.width
    implicitHeight: Style.space(44)

    Rectangle {
      id: screenerPill
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      height: Style.space(28)
      width: screenerPillLabel.implicitWidth + Style.space(20)
      radius: Style.space(14)
      color: pillHover.hovered
        ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
        : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
      border.width: 1
      border.color: Qt.rgba(root.accentColor.r, root.accentColor.g,
        root.accentColor.b, 0.35)

      Text {
        id: screenerPillLabel
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: "\u270d Screen " + root.screenerCount
          + (root.screenerCount === 1 ? " first-time sender" : " first-time senders")
        color: root.accentColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }

      HoverHandler { id: pillHover; cursorShape: Qt.PointingHandCursor }
      TapHandler { onTapped: root.screenerRequested() }
    }
  }

  // ── View title (non-Imbox views) ─────────────────────────────────────
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

      // ── Section headers inside the Imbox ─────────────────────────────
      Item {
        visible: root.service.workflowEnabled && root.service.workflowKey === "inbox"
          && (entry.index === 0 || entry.index === root.service.workflowNewCount)
        width: parent.width
        implicitHeight: Style.space(32)

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: entry.index < root.service.workflowNewCount
            ? "NEW FOR YOU" : "PREVIOUSLY SEEN"
          textFormat: Text.PlainText
          color: root.dimColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        // "Power Through New" — only on the NEW FOR YOU header
        Rectangle {
          visible: entry.index === 0 && root.service.workflowNewCount > 0
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(22)
          width: ptnLabel.implicitWidth + Style.space(14)
          radius: Style.cornerRadius
          color: ptnHover.hovered
            ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
            : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)
          border.width: 1
          border.color: Qt.rgba(root.accentColor.r, root.accentColor.g,
            root.accentColor.b, 0.30)

          Text {
            id: ptnLabel
            anchors.centerIn: parent
            text: "\uD83D\uDE80 Power Through New"
            textFormat: Text.PlainText
            color: root.accentColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          HoverHandler { id: ptnHover; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: root.powerThroughRequested() }
        }
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
        checked: !!root.checkedIds[entry.modelData.id]
        onActivated: root.messageActivated(entry.modelData.id)
        onSelectToggled: root.selectToggled(entry.modelData.id)
        onStarToggled: root.service.toggleStar(entry.modelData.id)
        onArchiveRequested: root.service.act(entry.modelData.id, "archive")
        onTrashRequested: root.service.act(entry.modelData.id, "trash")
        onHovered: function(isHovered) { root.rowHovered(entry.modelData.id, isHovered) }
        onMenuRequested: function(sceneX, sceneY) {
          root.menuRequested(entry.modelData.id, sceneX, sceneY)
        }
        onQuickActionsRequested: function(sceneX, sceneY) {
          root.quickActionsRequested(entry.modelData.id, sceneX, sceneY)
        }
      }
    }
  }

  Item {
    width: parent.width
    visible: root.service.messages.length === 0
    implicitHeight: Style.space(70)

    Text {
      anchors.centerIn: parent
      width: parent.width - Style.space(20)
      horizontalAlignment: Text.AlignHCenter
      text: root.service.listLoading
        ? "Loading\u2026"
        : (root.service.listLoaded
          ? (root.service.searchQuery !== "" ? "Nothing matches that search"
            : (root.isScreener
              ? "Nothing waiting. You're all caught up."
              : (root.service.workflowEnabled && root.service.workflowKey === "feed"
                ? "No senders in The Feed yet.\nMove a newsletter here to start."
                : (root.service.workflowEnabled && root.service.workflowKey === "paper_trail"
                  ? "No receipts or transactions yet."
                  : "Nothing here"))))
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
      text: root.service.listLoading ? "Loading\u2026" : "Load more"
      foreground: root.textColor
      bordered: false
      fontSize: Style.font.caption
      enabled: !root.service.listLoading
      onClicked: root.service.loadMore()
    }
  }
}
