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

  implicitHeight: actionable ? actions.implicitHeight + Style.space(12) : 0
  visible: actionable

  Flow {
    id: actions
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(5)

    Button {
      visible: root.screener
      text: "[x] No"
      foreground: root.textColor
      bordered: true
      fontSize: Style.font.caption
      onClicked: root.service.routeSender(root.messageId, "screened_out")
    }

    Button {
      visible: root.screener
      text: "[i] Inbox"
      foreground: root.textColor
      bordered: true
      fontSize: Style.font.caption
      onClicked: root.service.routeSender(root.messageId, "inbox")
    }

    Button {
      visible: root.screener
      text: "[f] Feed"
      foreground: root.textColor
      bordered: true
      fontSize: Style.font.caption
      onClicked: root.service.routeSender(root.messageId, "feed")
    }

    Button {
      visible: root.screener
      text: "[p] Paper Trail"
      foreground: root.textColor
      bordered: true
      fontSize: Style.font.caption
      onClicked: root.service.routeSender(root.messageId, "paper_trail")
    }

    Button {
      visible: !root.screener
      text: "[l] Reply Later"
      foreground: root.textColor
      bordered: false
      fontSize: Style.font.caption
      onClicked: root.service.setWorkflowPile(root.messageId, "reply_later")
    }

    Button {
      visible: !root.screener
      text: "[a] Set Aside"
      foreground: root.textColor
      bordered: false
      fontSize: Style.font.caption
      onClicked: root.service.setWorkflowPile(root.messageId, "set_aside")
    }

    Button {
      visible: !root.screener
      text: "Later today"
      foreground: root.textColor
      bordered: false
      fontSize: Style.font.caption
      onClicked: root.service.scheduleWorkflowBubble(root.messageId,
        new Date(Date.now() + 4 * 60 * 60 * 1000))
    }

    Button {
      visible: !root.screener
      text: "[z] Tomorrow"
      foreground: root.textColor
      bordered: false
      fontSize: Style.font.caption
      onClicked: root.service.scheduleWorkflowBubble(root.messageId,
        new Date(Date.now() + 24 * 60 * 60 * 1000))
    }

    Button {
      visible: !root.screener
      text: "Next week"
      foreground: root.textColor
      bordered: false
      fontSize: Style.font.caption
      onClicked: root.service.scheduleWorkflowBubble(root.messageId,
        new Date(Date.now() + 7 * 24 * 60 * 60 * 1000))
    }

    Button {
      visible: !root.screener && root.service.workflowKey === "bubble_up"
      text: "Cancel bubble"
      foreground: root.dimColor
      bordered: false
      fontSize: Style.font.caption
      onClicked: root.service.cancelWorkflowBubble(root.messageId)
    }

    Button {
      visible: !root.screener
        && (root.service.workflowKey === "reply_later"
          || root.service.workflowKey === "set_aside")
      text: "Done"
      foreground: root.textColor
      bordered: false
      fontSize: Style.font.caption
      onClicked: root.service.setWorkflowPile(root.messageId, null)
    }
  }
}
