import QtQuick
import qs.Commons
import qs.Ui

// One message row. Subject leads — it is what the thread is about and what
// you scan a list for. Sender + snippet sit below in one dimmer line.
// Unread: bold subject, bright avatar, accent dot on the avatar corner.
Rectangle {
  id: root

  required property var summary
  required property color textColor
  required property color accentColor
  required property color dimColor
  required property string panelFontFamily
  property bool hasCursor: false
  property bool selected: false
  property bool checked: false
  property bool dense: false
  // In Screener the subject is the sender's email address; keep the prop
  // so callers need no changes.
  property bool senderFirst: false

  signal activated()
  signal starToggled()
  signal archiveRequested()
  signal trashRequested()
  signal menuRequested(real sceneX, real sceneY)
  signal quickActionsRequested(real sceneX, real sceneY)
  signal selectToggled()
  signal hovered(bool isHovered)

  readonly property bool hot: mouse.containsMouse || hasCursor

  function _avatarHue(email) {
    var s = email || ""
    var h = 0
    for (var i = 0; i < s.length; i++) {
      h = (h * 31 + s.charCodeAt(i)) % 360
    }
    return h / 360
  }

  function _initial(name) {
    if (!name || name.length === 0) return "?"
    return name.charAt(0).toUpperCase()
  }

  // Keep lightness below 0.50 so Qt.rgba(1,1,1,1) initials always contrast.
  readonly property color avatarColor: Qt.hsla(
    _avatarHue(root.summary.from ? root.summary.from.email : ""),
    root.summary.unread ? 0.60 : 0.28,
    root.summary.unread ? 0.42 : 0.46,
    1.0)

  width: parent ? parent.width : 0
  implicitHeight: body.implicitHeight + Style.space(dense ? 8 : 14)
  radius: Style.cornerRadius
  color: selected
    ? Style.selectedFillFor(textColor, accentColor)
    : (hot ? Style.hoverFillFor(textColor, accentColor) : "transparent")

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onEntered: root.hovered(true)
    onExited: root.hovered(false)
    onClicked: function(event) {
      if (event.button === Qt.RightButton) {
        var scene = mapToGlobal(event.x, event.y)
        root.menuRequested(scene.x, scene.y)
      } else if (event.button === Qt.MiddleButton) {
        root.archiveRequested()
      } else if (event.modifiers & Qt.ShiftModifier) {
        root.selectToggled()
      } else {
        root.activated()
      }
    }
  }

  Row {
    id: body
    anchors.left: parent.left
    anchors.right: actions.visible ? actions.left : parent.right
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(10)

    // Sender avatar
    Item {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(dense ? 28 : 32)
      height: width

      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: root.checked ? root.accentColor
          : (avatarHover.hovered ? Qt.lighter(root.avatarColor, 1.25)
            : root.avatarColor)

        Text {
          anchors.centerIn: parent
          text: root.checked ? "\u2713"
            : root._initial(root.summary.from ? root.summary.from.display : "")
          textFormat: Text.PlainText
          color: Qt.rgba(1, 1, 1, 1)
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }

        HoverHandler { id: avatarHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
          onTapped: root.checked
            ? root.selectToggled()
            : root.quickActionsRequested(root.mapToGlobal(0, root.height / 2).x,
                root.mapToGlobal(0, root.height / 2).y)
        }
      }

      // Unread dot — accent ring on the avatar's bottom-right corner
      Rectangle {
        visible: root.summary.unread
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Style.space(8)
        height: width
        radius: width / 2
        color: root.accentColor
        border.color: root.color
        border.width: 1
      }
    }

    // Text: subject on top (bold if unread), sender — snippet below
    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - Style.space(dense ? 28 : 32) - parent.spacing
      spacing: Style.space(2)

      Item {
        width: parent.width
        implicitHeight: Math.max(subjectText.implicitHeight, timeText.implicitHeight)

        Text {
          id: subjectText
          anchors.left: parent.left
          anchors.right: timeText.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          // Screener shows the sender name as the "subject" (what to scan for)
          text: root.senderFirst
            ? (root.summary.from ? root.summary.from.display : "")
            : root.summary.subject
          color: root.textColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.body
          font.bold: root.summary.unread
          elide: Text.ElideRight
        }

        Text {
          id: timeText
          anchors.right: parent.right
          anchors.verticalCenter: subjectText.verticalCenter
          textFormat: Text.PlainText
          text: root.summary.time
          color: root.dimColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.caption
        }
      }

      // Second line: "Sender — snippet" or just the email address in Screener
      Text {
        width: parent.width
        textFormat: Text.PlainText
        visible: !root.dense
        text: {
          if (root.senderFirst) {
            return root.summary.from ? root.summary.from.email : ""
          }
          var name = root.summary.from ? root.summary.from.display : ""
          var snip = root.summary.snippet || ""
          if (name && snip) return name + " \u2014 " + snip
          return name || snip
        }
        color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.50)
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        maximumLineCount: 1
      }
    }
  }

  Row {
    id: actions
    anchors.right: parent.right
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(1)
    visible: root.hot || root.summary.starred

    IconButton {
      iconName: "star"
      filled: root.summary.starred
      tooltipText: (root.summary.starred ? "Unstar" : "Star") + " · s"
      foreground: root.summary.starred ? root.accentColor : root.dimColor
      hoverColor: root.accentColor
      iconSize: Style.font.iconSmall
      size: Style.space(20)
      fontFamily: root.panelFontFamily
      onClicked: root.starToggled()
    }

    IconButton {
      visible: root.hot
      iconName: "archive"
      tooltipText: "Archive · e"
      foreground: root.dimColor
      hoverColor: root.textColor
      iconSize: Style.font.iconSmall
      size: Style.space(20)
      fontFamily: root.panelFontFamily
      onClicked: root.archiveRequested()
    }

    IconButton {
      visible: root.hot
      iconName: "trash"
      tooltipText: "Move to trash · d"
      foreground: root.dimColor
      hoverColor: root.textColor
      iconSize: Style.font.iconSmall
      size: Style.space(20)
      fontFamily: root.panelFontFamily
      onClicked: root.trashRequested()
    }
  }
}
