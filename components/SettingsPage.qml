import QtQuick
import qs.Commons
import qs.Ui

// Where mailboxes are managed.
//
// Adding one used to drop the user on the first-run walkthrough, which by then
// had nothing left to ask: the client was connected and an account was already
// signed in, so the page showed a finished setup for the *other* mailbox and
// there was no way forward. Adding a mailbox belongs here, next to the ones
// that already exist, and signing it in happens on its own row rather than by
// sending the window somewhere else.
Column {
  id: root

  required property var service
  required property color textColor
  required property color dimColor
  required property color accentColor
  required property color urgentColor
  required property string panelFontFamily

  signal backRequested()
  signal clientSetupRequested()
  signal addRequested()
  signal signInRequested(int index)
  signal signOutRequested(int index)
  signal removeRequested(int index)

  readonly property var accounts: service ? service.accountSummaries : []
  readonly property var auth: service ? service.auth : null

  spacing: Style.space(16)

  BackBar {
    textColor: root.textColor
    dimColor: root.dimColor
    panelFontFamily: root.panelFontFamily
    onActivated: root.backRequested()
  }

  Text {
    text: "Settings"
    color: root.textColor
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.heading
    font.bold: true
  }

  // ------------------------------------------------------------- mailboxes

  Text {
    text: "MAILBOXES"
    color: root.dimColor
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
  }

  Column {
    width: parent.width
    spacing: Style.space(2)

    Repeater {
      model: root.accounts

      Rectangle {
        id: row
        required property var modelData
        required property int index

        width: parent.width
        implicitHeight: Math.max(rowText.implicitHeight, rowActions.implicitHeight)
          + Style.space(16)
        radius: Style.cornerRadius
        color: modelData.active
          ? Style.selectedFillFor(root.textColor, root.accentColor)
          : Style.normalFillFor(root.textColor, root.accentColor)

        Column {
          id: rowText
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.right: rowActions.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: row.modelData.email !== "" ? row.modelData.email : "New mailbox"
            color: root.textColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: row.modelData.active
            elide: Text.ElideMiddle
          }

          Text {
            width: parent.width
            text: {
              if (row.modelData.error !== undefined && row.modelData.error !== "")
                return row.modelData.error
              if (!row.modelData.signedIn) return "Not signed in yet"
              var count = row.modelData.unread
              var unread = count === 0 ? "No unread mail"
                : (count === 1 ? "1 unread message" : count + " unread messages")
              return row.modelData.active ? unread + " · showing now" : unread
            }
            color: row.modelData.error !== undefined && row.modelData.error !== ""
              ? root.urgentColor : root.dimColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Row {
          id: rowActions
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          IconTextButton {
            visible: !row.modelData.signedIn
            iconName: "gmail"
            text: "Sign in"
            foreground: root.textColor
            fontFamily: root.panelFontFamily
            tooltipText: "Sign this mailbox in with Google"
            onClicked: root.signInRequested(row.index)
          }

          IconTextButton {
            visible: row.modelData.signedIn
            text: "Sign out"
            foreground: root.dimColor
            fontFamily: root.panelFontFamily
            onClicked: root.signOutRequested(row.index)
          }

          // The last mailbox has no Remove: taking it away would leave the
          // window with nothing to show and no way to get anything back.
          IconTextButton {
            visible: root.accounts.length > 1
            text: "Remove"
            foreground: root.dimColor
            accent: root.urgentColor
            fontFamily: root.panelFontFamily
            tooltipText: "Forget this mailbox on this machine"
            onClicked: root.removeRequested(row.index)
          }
        }
      }
    }
  }

  IconTextButton {
    iconName: "plus"
    text: "Add a mailbox"
    foreground: root.textColor
    fontFamily: root.panelFontFamily
    tooltipText: "Sign in to another Gmail account"
    onClicked: root.addRequested()
  }

  PanelSeparator {
    width: parent.width
    foreground: root.textColor
  }

  Text {
    text: "WORKFLOW"
    color: root.dimColor
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
  }

  Item {
    width: parent.width
    implicitHeight: Math.max(workflowText.implicitHeight, workflowButton.implicitHeight)

    Column {
      id: workflowText
      anchors.left: parent.left
      anchors.right: workflowButton.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: "Mirror workflow labels to Gmail"
        color: root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        width: parent.width
        text: "Optional. Local sender decisions remain canonical."
        color: root.dimColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }

    Button {
      id: workflowButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: root.service && root.service.workflowMirroring ? "On" : "Off"
      foreground: root.textColor
      selected: root.service && root.service.workflowMirroring
      bordered: true
      fontSize: Style.font.bodySmall
      enabled: root.service && root.service.workflowWritable
      onClicked: root.service.setWorkflowMirroring(!root.service.workflowMirroring)
    }
  }

  Button {
    text: "Treat loaded Inbox as Previously Seen"
    foreground: root.textColor
    bordered: true
    fontSize: Style.font.bodySmall
    enabled: root.service && root.service.workflowWritable
      && root.service.allMessages.length > 0
    onClicked: root.service.initializeExistingWorkflow()
  }

  Text {
    visible: root.service && root.service.workflowSenderRules.length > 0
    text: "SCREENER HISTORY"
    color: root.dimColor
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
  }

  Column {
    visible: root.service && root.service.workflowSenderRules.length > 0
    width: parent.width
    spacing: Style.space(2)

    Repeater {
      model: root.service ? root.service.workflowSenderRules : []

      Rectangle {
        id: ruleRow
        required property var modelData
        width: parent.width
        implicitHeight: ruleText.implicitHeight + ruleActions.implicitHeight + Style.space(14)
        radius: Style.cornerRadius
        color: Style.normalFillFor(root.textColor, root.accentColor)

        Column {
          id: ruleText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(8)
          spacing: Style.space(2)

          Text {
            width: parent.width
            text: ruleRow.modelData.sender
            textFormat: Text.PlainText
            color: root.textColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideMiddle
          }

          Text {
            width: parent.width
            text: ruleRow.modelData.decision === "screened_out"
              ? "Screened out" : "Delivering to " + ruleRow.modelData.destination.replace("_", " ")
            textFormat: Text.PlainText
            color: root.dimColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Row {
          id: ruleActions
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.margins: Style.space(6)
          spacing: Style.space(3)

          Button {
            text: "Inbox"
            foreground: root.textColor
            bordered: false
            fontSize: Style.font.caption
            onClicked: root.service.setSenderDestination(ruleRow.modelData.sender, "inbox")
          }
          Button {
            text: "Feed"
            foreground: root.textColor
            bordered: false
            fontSize: Style.font.caption
            onClicked: root.service.setSenderDestination(ruleRow.modelData.sender, "feed")
          }
          Button {
            text: "Paper"
            foreground: root.textColor
            bordered: false
            fontSize: Style.font.caption
            onClicked: root.service.setSenderDestination(ruleRow.modelData.sender, "paper_trail")
          }
          Button {
            text: "No"
            foreground: root.textColor
            bordered: false
            fontSize: Style.font.caption
            onClicked: root.service.setSenderDestination(ruleRow.modelData.sender, "screened_out")
          }
          Button {
            text: "Reset"
            foreground: root.dimColor
            bordered: false
            fontSize: Style.font.caption
            onClicked: root.service.forgetSender(ruleRow.modelData.sender)
          }
        }
      }
    }
  }

  PanelSeparator {
    width: parent.width
    foreground: root.textColor
  }

  // ---------------------------------------------------------- oauth client

  Text {
    text: "GOOGLE OAUTH CLIENT"
    color: root.dimColor
    font.family: root.panelFontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
  }

  Item {
    width: parent.width
    implicitHeight: Math.max(clientText.implicitHeight, clientButton.implicitHeight)

    Column {
      id: clientText
      anchors.left: parent.left
      anchors.right: clientButton.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        width: parent.width
        text: root.auth && root.auth.credentialsPresent
          ? root.auth.clientDescription : "No client yet"
        color: root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideMiddle
      }

      Text {
        width: parent.width
        // Every mailbox signs in through this one client, which is why adding
        // an account never asks for another.
        text: "Shared by every mailbox above"
        color: root.dimColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }

    IconTextButton {
      id: clientButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: root.auth && root.auth.credentialsPresent ? "Change..." : "Set up..."
      foreground: root.dimColor
      fontFamily: root.panelFontFamily
      onClicked: root.clientSetupRequested()
    }
  }
}
