import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../Message.js" as Mail
import "../Html.js" as Html

Item {
  id: root

  required property var service
  required property color textColor
  required property color backgroundColor
  required property color accentColor
  required property color linkColor
  required property color dimColor
  required property color dimmerColor
  required property string panelFontFamily
  property real zoom: 1.0
  property int messageIndex: -1
  property bool replyOpen: false
  property var drafts: ({})
  property string draftThreadId: ""
  readonly property bool replying: replyOpen
  readonly property var messages: service ? service.selectedThreadMessages : []
  readonly property var latest: messages.length > 0
    ? messages[messages.length - 1] : null

  signal backRequested()
  signal forwardRequested()
  signal actionRequested(string action)

  function revealMessage(index) {
    if (messages.length === 0) return
    messageIndex = Math.max(0, Math.min(messages.length - 1, index))
    thread.positionViewAtIndex(messageIndex, ListView.Contain)
  }

  function moveMessage(delta) {
    revealMessage(messageIndex < 0
      ? (delta < 0 ? messages.length - 1 : 0)
      : messageIndex + Number(delta || 0))
  }

  function scrollBy(pixels) {
    thread.contentY = Math.max(0, Math.min(
      Math.max(0, thread.contentHeight - thread.height),
      thread.contentY + Number(pixels || 0)))
  }

  function scrollToEnd(toEnd) {
    if (toEnd) {
      messageIndex = Math.max(0, messages.length - 1)
      thread.positionViewAtEnd()
    } else {
      messageIndex = 0
      thread.positionViewAtBeginning()
    }
  }

  function focusReply() {
    if (!latest) return
    replyOpen = true
    Qt.callLater(function() { replyEdit.forceActiveFocus() })
  }

  function dismissReply() {
    replyOpen = false
    forceActiveFocus()
  }

  function submitReply() {
    if (!latest || !latest.summary || replyEdit.text.trim() === "") return
    var summary = latest.summary
    var address = summary.replyTo && summary.replyTo.email
      ? summary.replyTo.email : (summary.from ? summary.from.email : "")
    service.send({
      to: address,
      cc: "",
      subject: Mail.replySubject(summary.subject),
      body: replyEdit.text,
      threadId: service.selectedThreadId,
      inReplyTo: summary.messageId,
      references: Mail.replyReferences(summary)
    })
  }

  function loadDraft(threadId) {
    draftThreadId = String(threadId || "")
    replyEdit.text = String(drafts["thread:" + draftThreadId] || "")
    replyOpen = false
  }

  onMessagesChanged: Qt.callLater(function() {
    if (root.messages.length === 0) return
    // A thread with replies scrolls to the latest one; a single message
    // starts at the top so you read from the beginning.
    if (root.messages.length > 1) root.scrollToEnd(true)
    else { messageIndex = 0; thread.positionViewAtBeginning() }
  })
  Component.onCompleted: loadDraft(service ? service.selectedThreadId : "")

  ListView {
    id: thread
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: replyDock.top
    anchors.margins: Style.space(12)
    clip: true
    spacing: Style.space(10)
    model: root.messages
    cacheBuffer: Style.space(700)
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    header: Column {
      width: thread.width - Style.space(12)
      spacing: Style.space(5)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Button {
          visible: root.width < Style.space(760)
          text: "Back"
          foreground: root.dimColor
          bordered: false
          fontSize: Style.font.caption
          onClicked: root.backRequested()
        }

        Text {
          width: parent.width
          text: root.latest && root.latest.summary
            ? root.latest.summary.subject : "Conversation"
          textFormat: Text.PlainText
          color: root.textColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          wrapMode: Text.Wrap
        }
      }

      Text {
        width: parent.width
        text: root.messages.length === 1 ? "1 message"
          : root.messages.length + " messages"
        color: root.dimColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
      }

      Item { width: 1; height: Style.space(8) }
    }

    delegate: Rectangle {
      id: card
      required property var modelData
      required property int index

      readonly property var summary: modelData.summary || ({})
      readonly property bool mine: summary.from
        && String(summary.from.email || "").toLowerCase()
          === String(root.service.accountEmail || "").toLowerCase()

      width: thread.width - Style.space(12)
      height: messageColumn.implicitHeight + Style.space(22)
      radius: Style.cornerRadius
      color: root.messageIndex === index || mine
        ? Style.normalFillFor(root.textColor, root.accentColor)
        : "transparent"
      border.width: root.messageIndex === index ? 1 : 0
      border.color: root.accentColor

      Column {
        id: messageColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(11)
        spacing: Style.space(7)

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width - messageTime.width - Style.space(8)
            text: card.mine ? "You" : (card.summary.from
              ? card.summary.from.display : "Unknown sender")
            textFormat: Text.PlainText
            color: root.textColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            id: messageTime
            text: card.summary.fullTime || card.summary.time || ""
            textFormat: Text.PlainText
            color: root.dimColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          visible: card.modelData.html === ""
          width: parent.width
          text: card.modelData.text || ""
          textFormat: Text.PlainText
          color: root.textColor
          font.family: root.panelFontFamily
          font.pixelSize: Math.round(Style.font.bodySmall * root.zoom)
          wrapMode: Text.Wrap
        }

        TextEdit {
          visible: card.modelData.html !== ""
          width: parent.width
          height: visible ? implicitHeight : 0
          text: card.modelData.html || ""
          textFormat: TextEdit.RichText
          readOnly: true
          selectByMouse: true
          wrapMode: TextEdit.Wrap
          color: root.textColor
          font.family: root.panelFontFamily
          font.pixelSize: Math.round(Style.font.bodySmall * root.zoom)
          onLinkActivated: function(link) {
            var image = Html.imageLinkIndex(link)
            if (image > 0) {
              var sources = card.modelData.images || []
              if (image <= sources.length) imagePopover.show(sources[image - 1])
              return
            }
            Qt.openUrlExternally(link)
          }
        }

        Button {
          visible: card.modelData.remoteImages > 0
          text: "Load images for this message..."
          foreground: root.dimColor
          bordered: false
          fontSize: Style.font.caption
          onClicked: root.service.loadThreadRemoteImages(card.modelData.id)
        }

        Repeater {
          model: card.modelData.attachments || []

          Text {
            required property var modelData
            width: messageColumn.width
            text: "Attachment: " + (modelData.filename || modelData.name || "file")
            textFormat: Text.PlainText
            color: root.dimColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideMiddle
          }
        }
      }

      PanelSeparator {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: card.index < root.messages.length - 1
        foreground: root.dimColor
      }

      TapHandler { onTapped: root.revealMessage(card.index) }
    }
  }

  ReaderBlankSlate {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: replyDock.top
    visible: root.messages.length === 0
      && !(root.service && root.service.detailLoading)
    service: root.service
    textColor: root.textColor
    accentColor: root.accentColor
    dimColor: root.dimColor
    dimmerColor: root.dimmerColor
    panelFontFamily: root.panelFontFamily
  }

  ReaderSkeleton {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: replyDock.top
    visible: root.messages.length === 0
      && root.service && root.service.detailLoading
    textColor: root.textColor
    panelFontFamily: root.panelFontFamily
  }

  Rectangle {
    id: replyDock
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: !root.latest ? 0 : (root.replyOpen ? Style.space(190) : Style.space(54))
    color: root.backgroundColor

    PanelSeparator {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      foreground: root.textColor
    }

    Button {
      visible: !root.replyOpen
      anchors.left: parent.left
      anchors.leftMargin: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      text: replyEdit.text === "" ? "Reply" : "Continue reply"
      foreground: root.textColor
      bordered: true
      fontSize: Style.font.bodySmall
      enabled: !!root.latest
      onClicked: root.focusReply()
    }

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(14)
      visible: root.replyOpen
      spacing: Style.space(7)

      Text {
        width: parent.width
        text: root.latest && root.latest.summary && root.latest.summary.from
          ? "Reply to " + root.latest.summary.from.display : "Reply"
        textFormat: Text.PlainText
        color: root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
      }

      Rectangle {
        width: parent.width
        height: Style.space(105)
        color: Style.normalFillFor(root.textColor, root.accentColor)
        radius: Style.cornerRadius
        border.width: replyEdit.activeFocus ? 1 : 0
        border.color: root.accentColor

        TextEdit {
          id: replyEdit
          anchors.fill: parent
          anchors.margins: Style.space(8)
          color: root.textColor
          selectionColor: root.accentColor
          selectedTextColor: root.backgroundColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: TextEdit.Wrap
          selectByMouse: true
          Keys.onEscapePressed: function(event) {
            root.dismissReply()
            event.accepted = true
          }
          onTextChanged: {
            if (root.draftThreadId === "") return
            var next = {}
            for (var key in root.drafts) next[key] = root.drafts[key]
            next["thread:" + root.draftThreadId] = text
            root.drafts = next
          }
        }
      }

      Row {
        spacing: Style.space(7)

        Button {
          text: root.service && root.service.sending ? "Sending…" : "Send · Ctrl+Enter"
          foreground: root.textColor
          bordered: true
          fontSize: Style.font.caption
          enabled: root.service && !root.service.sending
            && replyEdit.text.trim() !== ""
          onClicked: root.submitReply()
        }

        Button {
          text: "Close"
          foreground: root.dimColor
          bordered: false
          fontSize: Style.font.caption
          onClicked: root.dismissReply()
        }
      }
    }
  }

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onSelectedThreadIdChanged() {
      root.loadDraft(root.service.selectedThreadId)
    }
    function onReplySent() {
      var next = {}
      for (var key in root.drafts) {
        if (key !== "thread:" + root.draftThreadId) next[key] = root.drafts[key]
      }
      root.drafts = next
      replyEdit.text = ""
      root.replyOpen = false
      Qt.callLater(function() { root.scrollToEnd(true) })
    }
  }

  ImagePopover {
    id: imagePopover
    textColor: root.textColor
    dimColor: root.dimColor
    panelFontFamily: root.panelFontFamily
  }

  Shortcut {
    sequence: "Ctrl+Return"
    enabled: root.visible && root.replyOpen
    onActivated: root.submitReply()
  }
}
