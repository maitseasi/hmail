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

    delegate: Rectangle {
      id: card
      required property var modelData

      width: feed.width - Style.space(8)
      height: content.implicitHeight + Style.space(24)
      color: cursorId === modelData.id
        ? Style.selectedFillFor(root.textColor, root.accentColor)
        : "transparent"
      radius: Style.cornerRadius

      readonly property var body: root.service.feedBody(modelData.id)

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
          text: card.modelData.snippet || "Loading message…"
          textFormat: Text.PlainText
          color: root.dimColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        TextEdit {
          visible: !!card.body
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
