import QtQuick
import qs.Commons
import qs.Ui

// A single expanded email card used in The Feed and Power Through New.
// Content is capped at maxBodyHeight; a "See more…" button reveals the rest.
Rectangle {
  id: root

  required property var summary
  required property var service
  required property color textColor
  required property color backgroundColor
  required property color accentColor
  required property color dimColor
  required property string panelFontFamily
  property bool focused: false

  // Emitted when the pointer enters the card — used by FeedView to move the
  // keyboard cursor without opening anything.
  signal cardFocused()
  // Emitted on an explicit tap. FeedView does NOT connect this; the card is
  // a self-contained reading surface. Power Through may connect it.
  signal activated()

  // Height of the body clip before the user expands it.
  readonly property int maxBodyHeight: Style.space(320)
  property bool expanded: false

  function toggleExpand() { expanded = !expanded }

  function _cardAvatarHue(email) {
    var h = 0
    for (var i = 0; i < email.length; i++)
      h = (h * 31 + email.charCodeAt(i)) % 360
    return h / 360
  }
  function _cardInitial(name) {
    return name && name.length > 0 ? name.charAt(0).toUpperCase() : "?"
  }

  readonly property var body: root.service.feedBody(root.summary.id)
  readonly property string bodyError: root.service.feedBodyError(root.summary.id)
  readonly property bool bodyLoading: root.service.feedBodyIsLoading(root.summary.id)

  Component.onCompleted: root.service.loadFeedBody(root.summary.id)
  onBodyChanged: if (!body) root.service.loadFeedBody(root.summary.id)

  // Reset expand state when a different message lands in this card slot.
  onSummaryChanged: expanded = false

  width: parent ? parent.width : 0
  height: content.implicitHeight + Style.space(24)
  radius: Style.cornerRadius
  color: root.focused
    ? Style.selectedFillFor(root.textColor, root.accentColor)
    : "transparent"

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(14)
    spacing: Style.space(8)

    // Subject — the headline
    Text {
      width: parent.width
      text: root.summary.subject || "(no subject)"
      textFormat: Text.PlainText
      color: root.textColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
      wrapMode: Text.Wrap
    }

    // Sender row with avatar
    Item {
      width: parent.width
      implicitHeight: Math.max(senderAvatar.height, senderInfo.implicitHeight)

      Rectangle {
        id: senderAvatar
        width: Style.space(28)
        height: width
        anchors.verticalCenter: parent.verticalCenter
        radius: width / 2
        color: Qt.hsla(_cardAvatarHue(root.summary.from ? root.summary.from.email : ""),
          0.55, 0.44, 1.0)

        Text {
          anchors.centerIn: parent
          text: _cardInitial(root.summary.from ? root.summary.from.display : "")
          textFormat: Text.PlainText
          color: Qt.rgba(1, 1, 1, 1)
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      Column {
        id: senderInfo
        anchors.left: senderAvatar.right
        anchors.leftMargin: Style.space(8)
        anchors.right: senderTime.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: root.summary.from ? root.summary.from.display : ""
          textFormat: Text.PlainText
          color: root.textColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: root.summary.from ? root.summary.from.email : ""
          textFormat: Text.PlainText
          color: root.dimColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        id: senderTime
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.summary.time || ""
        textFormat: Text.PlainText
        color: root.dimColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // Body — clipped to maxBodyHeight until expanded
    Item {
      id: bodyClip
      width: parent.width
      readonly property real fullHeight: bodyInner.implicitHeight
      readonly property bool overflows: fullHeight > root.maxBodyHeight
      height: root.expanded || !overflows ? fullHeight : root.maxBodyHeight
      clip: !root.expanded && overflows

      Column {
        id: bodyInner
        width: parent.width
        spacing: Style.space(6)

        Text {
          visible: !root.body
          width: parent.width
          text: root.bodyLoading
            ? "Loading\u2026"
            : (root.bodyError ? root.bodyError
              : (root.summary.snippet || "Loading\u2026"))
          textFormat: Text.PlainText
          color: root.dimColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        TextEdit {
          visible: !!root.body && root.body.html !== ""
          width: parent.width
          height: visible ? implicitHeight : 0
          text: root.body ? root.body.html : ""
          textFormat: TextEdit.RichText
          readOnly: true
          selectByMouse: true
          wrapMode: TextEdit.Wrap
          color: root.textColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: !!root.body && root.body.html === ""
          width: parent.width
          text: root.body ? root.body.text : ""
          textFormat: Text.PlainText
          color: root.textColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }
      }

      // Fade gradient at the cut-off point
      Rectangle {
        visible: bodyClip.overflows && !root.expanded
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.space(48)
        gradient: Gradient {
          GradientStop {
            position: 0.0
            color: Qt.rgba(root.backgroundColor.r, root.backgroundColor.g,
              root.backgroundColor.b, 0.0)
          }
          GradientStop {
            position: 1.0
            color: Qt.rgba(root.backgroundColor.r, root.backgroundColor.g,
              root.backgroundColor.b, 0.95)
          }
        }
      }
    }

    // "See more…" / "See less" toggle
    Rectangle {
      visible: bodyClip.overflows
      width: seeMoreLabel.implicitWidth + Style.space(18)
      height: Style.space(26)
      radius: Style.space(13)
      color: seeMoreHover.hovered
        ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.10)
        : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.06)
      border.width: 1
      border.color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.18)

      Text {
        id: seeMoreLabel
        anchors.centerIn: parent
        text: root.expanded ? "See less" : "See more\u2026"
        textFormat: Text.PlainText
        color: root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
      }

      HoverHandler { id: seeMoreHover; cursorShape: Qt.PointingHandCursor }
      TapHandler { onTapped: root.expanded = !root.expanded }
    }

    Button {
      visible: root.bodyError !== ""
      text: "Retry"
      foreground: root.textColor
      bordered: true
      fontSize: Style.font.caption
      onClicked: root.service.retryFeedBody(root.summary.id)
    }

    Button {
      visible: !!root.body && root.body.blockedImages > 0
      text: "Load images for this message\u2026"
      foreground: root.dimColor
      bordered: false
      fontSize: Style.font.caption
      onClicked: root.service.loadFeedRemoteImages(root.summary.id)
    }
  }

  HoverHandler {
    cursorShape: Qt.ArrowCursor
    onHoveredChanged: if (hovered) root.cardFocused()
  }
}
