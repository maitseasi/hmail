import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// The reference sheet behind Ctrl+?. A plain list rather than a dialog because
// it never needs an answer — Esc, Ctrl+? again, or a click puts it away.
Rectangle {
  id: root

  required property color textColor
  required property color backgroundColor
  required property color dimColor
  required property string panelFontFamily

  signal dismissed()

  function scrollBy(pixels) {
    shortcutScroll.contentY = Math.max(0, Math.min(
      shortcutScroll.contentHeight - shortcutScroll.height,
      shortcutScroll.contentY + Number(pixels || 0)))
  }

  function scrollToEnd(end) {
    shortcutScroll.contentY = end
      ? Math.max(0, shortcutScroll.contentHeight - shortcutScroll.height)
      : 0
  }

  onVisibleChanged: if (visible) shortcutScroll.contentY = 0

  readonly property var rows: [
    { keys: "j / k", action: "Move rows; scroll inside Feed" },
    { keys: "Feed J / K", action: "Next / previous Feed item" },
    { keys: "Ctrl+d / Ctrl+u", action: "Move down / up a page" },
    { keys: "gg / G", action: "Jump to first / last" },
    { keys: "Enter or o", action: "Open the selected message" },
    { keys: "h or Esc", action: "Back to the list" },
    { keys: "1–6 / 9", action: "Workflow views" },
    { keys: "Screener i/f/p/x", action: "Set sender route / screen out" },
    { keys: "List i / f / p", action: "Move this conversation only" },
    { keys: "l / a / z", action: "Reply Later / Set Aside / Bubble Up" },
    { keys: "v / u", action: "Workflow Seen / New" },
    { keys: "e", action: "Archive" },
    { keys: "d", action: "Move to trash" },
    { keys: "s", action: "Star or unstar" },
    { keys: "Shift+I / Shift+U", action: "Mark read / unread" },
    { keys: "r / a / f", action: "Reply, reply all, forward" },
    { keys: "c", action: "Compose" },
    { keys: "Ctrl+Enter", action: "Send" },
    { keys: "/ or Ctrl+K", action: "Search" },
    { keys: "g then i / s / u / t", action: "Inbox, starred, unread, sent" },
    { keys: "Right-click a row", action: "Archive, trash, spam, star" },
    { keys: "Ctrl+= / Ctrl+-", action: "Zoom the message body" },
    { keys: "Ctrl+0", action: "Reset the zoom" },
    { keys: "F5", action: "Check for mail" },
    { keys: "? or Ctrl+?", action: "Toggle this sheet" },
    { keys: "Esc", action: "Back, or close the window" }
  ]

  color: Qt.rgba(backgroundColor.r, backgroundColor.g, backgroundColor.b, 0.96)

  MouseArea {
    anchors.fill: parent
    onClicked: root.dismissed()
  }

  Flickable {
    id: shortcutScroll
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(80), Style.space(420))
    height: Math.min(parent.height - Style.space(40), shortcutColumn.implicitHeight)
    contentWidth: width
    contentHeight: shortcutColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: shortcutColumn
      width: shortcutScroll.width - Style.space(10)
      spacing: Style.space(6)

      Text {
        text: "Keyboard shortcuts"
        color: root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Item {
        width: parent.width
        implicitHeight: Style.space(6)
      }

      Repeater {
        model: root.rows

        Item {
          required property var modelData
          width: parent.width
          implicitHeight: Style.space(20)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(150)
            text: modelData.keys
            color: root.textColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(155)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.action
            color: root.dimColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
