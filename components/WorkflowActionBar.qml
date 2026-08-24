import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  required property var service
  required property string messageId
  required property color textColor
  required property color accentColor
  required property color dimColor
  required property string panelFontFamily

  readonly property bool screener: service && service.workflowKey === "screener"
  readonly property bool actionable: service && service.workflowEnabled && messageId !== ""

  implicitHeight: actionable ? content.implicitHeight + Style.space(12) : 0
  visible: actionable

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)

    // ── Screener: the gatekeeper interaction ─────────────────────────────
    // One row of destination buttons. "Yes" is the primary action (accent
    // background); the negative answer is the only one that is destructive.
    Row {
      visible: root.screener
      spacing: Style.space(6)

      // Block — no more from this sender
      Rectangle {
        id: noBtn
        width: noLabel.implicitWidth + Style.space(20)
        height: Style.space(28)
        radius: Style.cornerRadius
        color: noHover.hovered
          ? Style.hoverFillFor(root.textColor, root.accentColor)
          : "transparent"
        border.color: Qt.rgba(root.textColor.r, root.textColor.g,
          root.textColor.b, 0.25)
        border.width: 1

        Text {
          id: noLabel
          anchors.centerIn: parent
          text: "Block"
          textFormat: Text.PlainText
          color: root.textColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
        }

        HoverHandler { id: noHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
          onTapped: root.service.routeSender(root.messageId, "screened_out")
        }
      }

      // Let them in → Imbox (the obvious default)
      Rectangle {
        id: yesBtn
        width: yesLabel.implicitWidth + Style.space(20)
        height: Style.space(28)
        radius: Style.cornerRadius
        color: yesHover.hovered
          ? Qt.rgba(root.accentColor.r, root.accentColor.g,
              root.accentColor.b, 0.85)
          : root.accentColor

        Text {
          id: yesLabel
          anchors.centerIn: parent
          text: "Yes, to Imbox"
          textFormat: Text.PlainText
          color: Qt.rgba(1, 1, 1, 1)
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }

        HoverHandler { id: yesHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
          onTapped: root.service.routeSender(root.messageId, "inbox")
        }
      }

      // To The Feed
      Rectangle {
        id: feedBtn
        width: feedLabel.implicitWidth + Style.space(20)
        height: Style.space(28)
        radius: Style.cornerRadius
        color: feedHover.hovered
          ? Style.hoverFillFor(root.textColor, root.accentColor)
          : "transparent"
        border.color: Qt.rgba(root.textColor.r, root.textColor.g,
          root.textColor.b, 0.25)
        border.width: 1

        Text {
          id: feedLabel
          anchors.centerIn: parent
          text: "The Feed"
          textFormat: Text.PlainText
          color: root.dimColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
        }

        HoverHandler { id: feedHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
          onTapped: root.service.routeSender(root.messageId, "feed")
        }
      }

      // To The Paper Trail
      Rectangle {
        id: trailBtn
        width: trailLabel.implicitWidth + Style.space(20)
        height: Style.space(28)
        radius: Style.cornerRadius
        color: trailHover.hovered
          ? Style.hoverFillFor(root.textColor, root.accentColor)
          : "transparent"
        border.color: Qt.rgba(root.textColor.r, root.textColor.g,
          root.textColor.b, 0.25)
        border.width: 1

        Text {
          id: trailLabel
          anchors.centerIn: parent
          text: "Paper Trail"
          textFormat: Text.PlainText
          color: root.dimColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
        }

        HoverHandler { id: trailHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
          onTapped: root.service.routeSender(root.messageId, "paper_trail")
        }
      }
    }

    // ── Non-screener: pile and bubble actions ────────────────────────────
    Flow {
      visible: !root.screener
      width: parent.width
      spacing: Style.space(5)

      Button {
        text: "Reply Later"
        foreground: root.textColor
        bordered: false
        fontSize: Style.font.caption
        onClicked: root.service.setWorkflowPile(root.messageId, "reply_later")
      }

      Button {
        text: "Set Aside"
        foreground: root.textColor
        bordered: false
        fontSize: Style.font.caption
        onClicked: root.service.setWorkflowPile(root.messageId, "set_aside")
      }

      Button {
        text: "Later today"
        foreground: root.textColor
        bordered: false
        fontSize: Style.font.caption
        onClicked: root.service.scheduleWorkflowBubble(root.messageId,
          new Date(Date.now() + 4 * 60 * 60 * 1000))
      }

      Button {
        text: "Tomorrow"
        foreground: root.textColor
        bordered: false
        fontSize: Style.font.caption
        onClicked: root.service.scheduleWorkflowBubble(root.messageId,
          new Date(Date.now() + 24 * 60 * 60 * 1000))
      }

      Button {
        text: "Next week"
        foreground: root.textColor
        bordered: false
        fontSize: Style.font.caption
        onClicked: root.service.scheduleWorkflowBubble(root.messageId,
          new Date(Date.now() + 7 * 24 * 60 * 60 * 1000))
      }

      Button {
        visible: root.service.workflowKey === "bubble_up"
        text: "Cancel bubble"
        foreground: root.dimColor
        bordered: false
        fontSize: Style.font.caption
        onClicked: root.service.cancelWorkflowBubble(root.messageId)
      }

      Button {
        visible: root.service.workflowKey === "reply_later"
          || root.service.workflowKey === "set_aside"
        text: "Done"
        foreground: root.textColor
        bordered: false
        fontSize: Style.font.caption
        onClicked: root.service.setWorkflowPile(root.messageId, null)
      }
    }
  }
}
