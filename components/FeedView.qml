import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
  id: root

  required property var service
  required property color textColor
  required property color backgroundColor
  required property color accentColor
  required property color dimColor
  required property string panelFontFamily
  property string cursorId: ""

  signal messageActivated(string id)
  signal messageFocused(string id)

  function revealCursor() {
    if (!service) return
    for (var i = 0; i < service.messages.length; i++) {
      if (service.messages[i].id === cursorId) {
        feed.currentIndex = i
        feed.positionViewAtIndex(i, ListView.Contain)
        return
      }
    }
  }

  function scrollBy(pixels) {
    feed.contentY = Math.max(0, Math.min(
      Math.max(0, feed.contentHeight - feed.height),
      feed.contentY + Number(pixels || 0)))
  }

  function scrollToEnd(end) {
    feed.contentY = end ? Math.max(0, feed.contentHeight - feed.height) : 0
  }

  onCursorIdChanged: Qt.callLater(revealCursor)

  ListView {
    id: feed
    anchors.fill: parent
    anchors.margins: Style.space(12)
    clip: true
    spacing: Style.space(14)
    boundsBehavior: Flickable.StopAtBounds
    model: root.service ? root.service.messages : []
    cacheBuffer: Style.space(500)
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.NoButton
      z: 10
      onWheel: function(wheel) {
        var amount = wheel.pixelDelta.y
        if (amount === 0)
          amount = (wheel.angleDelta.y / 120) * Style.space(140)
        root.scrollBy(-amount)
        wheel.accepted = true
      }
    }

    delegate: Rectangle {
      id: card
      required property var modelData

      width: feed.width - Style.space(8)
      height: content.implicitHeight + Style.space(24)
      color: root.cursorId === modelData.id
        ? Style.selectedFillFor(root.textColor, root.accentColor)
        : "transparent"
      radius: Style.cornerRadius

      readonly property var body: root.service.feedBody(modelData.id)
      readonly property string bodyError: root.service.feedBodyError(modelData.id)
      readonly property bool bodyLoading: root.service.feedBodyIsLoading(modelData.id)

      Component.onCompleted: root.service.loadFeedBody(modelData.id)
      onBodyChanged: if (!body) root.service.loadFeedBody(modelData.id)

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(12)
        spacing: Style.space(8)

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width - when.width - Style.space(8)
            text: card.modelData.from ? card.modelData.from.display : ""
            textFormat: Text.PlainText
            color: root.textColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            id: when
            text: card.modelData.time || ""
            textFormat: Text.PlainText
            color: root.dimColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          width: parent.width
          text: card.modelData.subject || "(no subject)"
          textFormat: Text.PlainText
          color: root.textColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          wrapMode: Text.Wrap
        }

        Text {
          visible: !card.body
          width: parent.width
          text: card.bodyLoading
            ? "Loading message…"
            : (card.bodyError ? card.bodyError : (card.modelData.snippet || "Loading message…"))
          textFormat: Text.PlainText
          color: root.dimColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        TextEdit {
          visible: !!card.body && card.body.html !== ""
          width: parent.width
          height: visible ? implicitHeight : 0
          text: card.body ? card.body.html : ""
          textFormat: TextEdit.RichText
          readOnly: true
          selectByMouse: true
          wrapMode: TextEdit.Wrap
          color: root.textColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: !!card.body && card.body.html === ""
          width: parent.width
          text: card.body ? card.body.text : ""
          textFormat: Text.PlainText
          color: root.textColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        Button {
          visible: card.bodyError !== ""
          text: "Retry loading message"
          foreground: root.textColor
          bordered: true
          fontSize: Style.font.caption
          onClicked: root.service.retryFeedBody(card.modelData.id)
        }

        Button {
          visible: !!card.body && card.body.blockedImages > 0
          text: "Load images for this message..."
          foreground: root.dimColor
          bordered: false
          fontSize: Style.font.caption
          onClicked: root.service.loadFeedRemoteImages(card.modelData.id)
        }
      }

      HoverHandler {
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: if (hovered) root.messageFocused(card.modelData.id)
      }
      TapHandler { onTapped: root.messageActivated(card.modelData.id) }
    }

    Text {
      anchors.centerIn: parent
      visible: feed.count === 0
      text: root.service && root.service.listLoading
        ? "Loading…"
        : "No senders are delivering here yet.\nMove a newsletter to Feed to start."
      textFormat: Text.PlainText
      horizontalAlignment: Text.AlignHCenter
      color: root.dimColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
