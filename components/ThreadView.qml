import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
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
  signal replyAllRequested()
  signal senderSearchRequested(string email)
  signal labelRequested()
  signal collectionRequested()

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

            Text {
              id: msgMenuBtn
              anchors.verticalCenter: parent.verticalCenter
              text: "\u22EF"
              color: msgMenuHover.hovered ? root.textColor : root.dimColor
              font.pixelSize: Style.font.body
              visible: cardHover.hovered || msgMenuHover.hovered
              leftPadding: Style.space(6)

              HoverHandler { id: msgMenuHover; cursorShape: Qt.PointingHandCursor }
              TapHandler {
                onTapped: {
                  var msg = card.modelData
                  msgMenu.messageId = msg.summary ? msg.summary.id : ""
                  msgMenu.senderEmail = msg.summary && msg.summary.from ? msg.summary.from.email : ""
                  msgMenu.senderDisplay = msg.summary && msg.summary.from ? msg.summary.from.display : ""
                  msgMenu.isStarred = msg.summary ? !!msg.summary.starred : false
                  msgMenu.isUnread = msg.summary ? !!msg.summary.unread : false
                  var pos = msgMenuBtn.mapToItem(root, 0, msgMenuBtn.height)
                  msgMenu.x = pos.x
                  msgMenu.y = pos.y
                  msgMenu.open()
                }
              }
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

      HoverHandler { id: cardHover }
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
    clip: true

    PanelSeparator {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      foreground: root.textColor
    }

    Row {
      visible: !root.replyOpen
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      height: parent.height
      spacing: Style.space(12)

      ThreadAction {
        label: replyEdit.text === "" ? "Reply" : "Continue reply"
        shortcut: "R"
        onActivated: root.focusReply()
      }
      ThreadAction {
        visible: !!root.service && root.service.workflowEnabled
        label: "Reply Later"
        shortcut: "L"
        onActivated: if (root.service) root.service.setWorkflowPile(
          root.service.selectedId, "reply_later")
      }
      ThreadAction {
        visible: !!root.service && root.service.workflowEnabled
        label: "Set Aside"
        shortcut: "A"
        onActivated: if (root.service) root.service.setWorkflowPile(
          root.service.selectedId, "set_aside")
      }
      ThreadAction {
        visible: !!root.service && root.service.workflowEnabled
        label: "Bubble Up"
        shortcut: "Z"
        onActivated: bubbleMenu.open()
      }
      ThreadAction {
        label: "More"
        shortcut: "M"
        onActivated: moreMenu.open()
      }
    }

    Popup {
      id: moreMenu
      x: Math.round((parent.width - width) / 2)
      y: -implicitHeight - Style.space(4)
      width: Style.space(220)
      implicitHeight: moreCol.implicitHeight + Style.space(8)
      padding: Style.space(4)
      modal: false
      focus: true
      closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
      background: Rectangle {
        radius: Style.cornerRadius
        color: Color.popups.background
        border.width: 1
        border.color: Color.popups.border
      }
      contentItem: Column {
        id: moreCol
        spacing: Style.space(2)

        MoreRow {
          visible: !!root.service && root.service.workflowEnabled
          text: "Move to Imbox"
          onActivated: {
            moreMenu.close()
            if (root.service) root.service.moveThread(root.service.selectedId, "inbox")
          }
        }
        MoreRow {
          visible: !!root.service && root.service.workflowEnabled
          text: "Move to Feed"
          onActivated: {
            moreMenu.close()
            if (root.service) root.service.moveThread(root.service.selectedId, "feed")
          }
        }
        MoreRow {
          visible: !!root.service && root.service.workflowEnabled
          text: "Move to Paper Trail"
          onActivated: {
            moreMenu.close()
            if (root.service) root.service.moveThread(
              root.service.selectedId, "paper_trail")
          }
        }

        Item {
          visible: !!root.service && root.service.workflowEnabled
          width: parent.width; implicitHeight: Style.space(7)
          PanelSeparator {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; foreground: root.textColor
          }
        }

        MoreRow {
          text: "Forward"
          shortcut: "F"
          onActivated: { moreMenu.close(); root.forwardRequested() }
        }
        MoreRow {
          text: "Label\u2026"
          shortcut: "B"
          onActivated: { moreMenu.close(); root.labelRequested() }
        }
        MoreRow {
          text: "Collection\u2026"
          onActivated: { moreMenu.close(); root.collectionRequested() }
        }
        MoreRow {
          text: "Archive"
          shortcut: "E"
          onActivated: { moreMenu.close(); root.actionRequested("archive") }
        }
        MoreRow {
          visible: !!root.service && root.service.workflowEnabled
          text: "Ignore thread"
          onActivated: {
            moreMenu.close()
            if (root.service) root.service.ignoreThread(root.service.selectedId)
          }
        }
        MoreRow {
          text: "Report spam"
          tone: Qt.rgba(1, 0.45, 0.4, 1)
          onActivated: {
            moreMenu.close()
            if (root.service) root.service.reportSpam(root.service.selectedId)
          }
        }
        MoreRow {
          text: "Move to trash"
          shortcut: "T"
          tone: Qt.rgba(1, 0.45, 0.4, 1)
          onActivated: { moreMenu.close(); root.actionRequested("trash") }
        }

        Item {
          width: parent.width; implicitHeight: Style.space(7)
          PanelSeparator {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; foreground: root.textColor
          }
        }

        MoreRow {
          readonly property bool isUnread: root.latest && root.latest.summary
            && root.latest.summary.unread
          text: isUnread ? "Mark as read" : "Mark as unread"
          shortcut: isUnread ? "Shift+I" : "Shift+U"
          onActivated: {
            moreMenu.close()
            root.actionRequested(isUnread ? "markRead" : "markUnread")
          }
        }
        MoreRow {
          readonly property bool isStarred: root.latest && root.latest.summary
            && root.latest.summary.starred
          text: isStarred ? "Unstar" : "Star"
          shortcut: "S"
          onActivated: {
            moreMenu.close()
            if (root.service) root.service.toggleStar(root.service.selectedId)
          }
        }
        MoreRow {
          text: "Open in browser"
          tone: root.dimColor
          onActivated: {
            moreMenu.close()
            if (root.service) root.service.openInBrowser(root.service.selectedId)
          }
        }
      }
    }

    Popup {
      id: bubbleMenu
      x: Math.round((parent.width - width) / 2)
      y: -implicitHeight - Style.space(4)
      width: Style.space(240)
      implicitHeight: bubbleCol.implicitHeight + Style.space(8)
      padding: Style.space(4)
      modal: false
      focus: true
      closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
      background: Rectangle {
        radius: Style.cornerRadius
        color: Color.popups.background
        border.width: 1
        border.color: Color.popups.border
      }

      function schedule(ms) {
        if (!root.service) return
        root.service.scheduleWorkflowBubble(root.service.selectedId,
          new Date(Date.now() + ms))
        bubbleMenu.close()
      }
      function nextWeekday(day, hour) {
        var d = new Date(); d.setHours(hour, 0, 0, 0)
        var diff = (day - d.getDay() + 7) % 7
        if (diff === 0) diff = 7
        d.setDate(d.getDate() + diff); return d
      }
      function hint(ms) {
        var d = new Date(Date.now() + ms)
        var days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
        var h = d.getHours(); var ampm = h < 12 ? "am" : "pm"
        return days[d.getDay()] + ", " + (h % 12 || 12) + ampm
      }
      function hintDate(d) {
        var days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
        var h = d.getHours(); var ampm = h < 12 ? "am" : "pm"
        return days[d.getDay()] + ", " + (h % 12 || 12) + ampm
      }

      contentItem: Column {
        id: bubbleCol
        spacing: Style.space(2)
        Text {
          leftPadding: Style.space(9); topPadding: Style.space(4)
          bottomPadding: Style.space(4)
          text: "BUBBLE THIS UP\u2026"
          color: root.dimColor; font.family: root.panelFontFamily
          font.pixelSize: Style.font.caption; font.bold: true
        }
        MoreRow { text: "Now"; onActivated: { bubbleMenu.schedule(0) } }
        MoreRow {
          text: "Later today"; hint: bubbleMenu.hint(4 * 3600000)
          onActivated: bubbleMenu.schedule(4 * 3600000)
        }
        MoreRow {
          text: "Tomorrow"; hint: bubbleMenu.hint(24 * 3600000)
          onActivated: bubbleMenu.schedule(24 * 3600000)
        }
        MoreRow {
          property var sat: bubbleMenu.nextWeekday(6, 8)
          text: "This weekend"; hint: bubbleMenu.hintDate(sat)
          onActivated: {
            if (root.service) root.service.scheduleWorkflowBubble(
              root.service.selectedId, sat)
            bubbleMenu.close()
          }
        }
        MoreRow {
          property var mon: bubbleMenu.nextWeekday(1, 8)
          text: "Next week"; hint: bubbleMenu.hintDate(mon)
          onActivated: {
            if (root.service) root.service.scheduleWorkflowBubble(
              root.service.selectedId, mon)
            bubbleMenu.close()
          }
        }
        MoreRow {
          text: "Surprise me"
          hint: "\u{1F3B2}"
          onActivated: {
            var ms = 3600000 + Math.floor(Math.random() * 6 * 86400000)
            bubbleMenu.schedule(ms)
          }
        }

        Item {
          width: parent.width; implicitHeight: Style.space(7)
          PanelSeparator {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; foreground: root.textColor
          }
        }

        MoreRow {
          text: "Pick a date\u2026"
          onActivated: { bubbleMenu.close(); bubbleDatePicker.open() }
        }
      }
    }

    Popup {
      id: bubbleDatePicker
      x: Math.round((parent.width - width) / 2)
      y: -implicitHeight - Style.space(4)
      width: Style.space(260)
      implicitHeight: datePickerCol.implicitHeight + Style.space(8)
      padding: Style.space(4)
      modal: false; focus: true
      closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
      background: Rectangle {
        radius: Style.cornerRadius
        color: Color.popups.background
        border.width: 1; border.color: Color.popups.border
      }
      contentItem: Column {
        id: datePickerCol
        spacing: Style.space(6)
        Text {
          leftPadding: Style.space(9); topPadding: Style.space(4)
          text: "PICK A DATE & TIME"
          color: root.dimColor; font.family: root.panelFontFamily
          font.pixelSize: Style.font.caption; font.bold: true
        }
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(6)
          TextField {
            id: dateField
            width: Style.space(120)
            placeholderText: "YYYY-MM-DD"
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.bodySmall
            color: root.textColor
            placeholderTextColor: root.dimColor
            background: Rectangle {
              radius: Style.cornerRadius
              color: Qt.rgba(root.textColor.r, root.textColor.g,
                root.textColor.b, 0.06)
              border.width: 1
              border.color: Qt.rgba(root.textColor.r, root.textColor.g,
                root.textColor.b, 0.15)
            }
            Component.onCompleted: {
              var d = new Date(Date.now() + 86400000)
              text = d.getFullYear() + "-"
                + String(d.getMonth() + 1).padStart(2, "0") + "-"
                + String(d.getDate()).padStart(2, "0")
            }
          }
          TextField {
            id: timeField
            width: Style.space(80)
            placeholderText: "HH:MM"
            text: "09:00"
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.bodySmall
            color: root.textColor
            placeholderTextColor: root.dimColor
            background: Rectangle {
              radius: Style.cornerRadius
              color: Qt.rgba(root.textColor.r, root.textColor.g,
                root.textColor.b, 0.06)
              border.width: 1
              border.color: Qt.rgba(root.textColor.r, root.textColor.g,
                root.textColor.b, 0.15)
            }
          }
        }
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          width: scheduleLabel.implicitWidth + Style.space(24)
          height: Style.space(30)
          radius: Style.cornerRadius
          color: scheduleHover.hovered
            ? root.accentColor : Qt.darker(root.accentColor, 1.15)
          Text {
            id: scheduleLabel
            anchors.centerIn: parent
            text: "Schedule"
            color: Qt.rgba(1, 1, 1, 1)
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.bodySmall
          }
          HoverHandler { id: scheduleHover; cursorShape: Qt.PointingHandCursor }
          TapHandler {
            onTapped: {
              var parts = dateField.text.split("-")
              var time = timeField.text.split(":")
              if (parts.length < 3 || time.length < 2) return
              var d = new Date(
                parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]),
                parseInt(time[0]), parseInt(time[1]), 0, 0)
              if (isNaN(d.getTime())) return
              if (!root.service) return
              root.service.scheduleWorkflowBubble(root.service.selectedId, d)
              bubbleDatePicker.close()
            }
          }
        }
        Item { width: 1; implicitHeight: Style.space(2) }
      }
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

  Popup {
    id: msgMenu
    property string messageId: ""
    property string senderEmail: ""
    property string senderDisplay: ""
    property bool isStarred: false
    property bool isUnread: false

    width: Style.space(230)
    implicitHeight: msgMenuCol.implicitHeight + Style.space(8)
    padding: Style.space(4)
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    z: 60
    background: Rectangle {
      radius: Style.cornerRadius
      color: Color.popups.background
      border.width: 1
      border.color: Color.popups.border
    }

    contentItem: Column {
      id: msgMenuCol
      spacing: Style.space(2)

      MoreRow {
        text: "Reply"
        onActivated: { msgMenu.close(); root.focusReply() }
      }
      MoreRow {
        text: "Reply all"
        onActivated: { msgMenu.close(); root.replyAllRequested() }
      }
      MoreRow {
        text: "Forward"
        onActivated: { msgMenu.close(); root.forwardRequested() }
      }

      Item {
        width: parent.width; implicitHeight: Style.space(7)
        PanelSeparator {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width; foreground: root.textColor
        }
      }

      MoreRow {
        text: "Go to sender"
        onActivated: {
          var email = msgMenu.senderEmail; msgMenu.close()
          if (email) root.senderSearchRequested(email)
        }
      }
      MoreRow {
        text: msgMenu.isUnread ? "Mark as read" : "Mark as unread"
        onActivated: {
          msgMenu.close()
          root.actionRequested(msgMenu.isUnread ? "markRead" : "markUnread")
        }
      }
      MoreRow {
        text: msgMenu.isStarred ? "Unstar" : "Star"
        onActivated: {
          msgMenu.close()
          if (root.service) root.service.toggleStar(root.service.selectedId)
        }
      }
      MoreRow {
        text: "Report spam"
        tone: Qt.rgba(1, 0.45, 0.4, 1)
        onActivated: {
          msgMenu.close()
          if (root.service) root.service.reportSpam(root.service.selectedId)
        }
      }

      Item {
        width: parent.width; implicitHeight: Style.space(7)
        PanelSeparator {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width; foreground: root.textColor
        }
      }

      MoreRow {
        text: "View original"
        onActivated: {
          var mid = msgMenu.messageId; msgMenu.close()
          if (!root.service || !mid) return
          rawSourceView.loading = true
          rawSourceView.rawText = ""
          rawSourceView.open()
          root.service.getMessageRaw(mid, function(payload) {
            rawSourceView.loading = false
            if (!payload || !payload.raw) {
              rawSourceView.rawText = "(Could not fetch raw source)"
              return
            }
            rawSourceView.rawText = Qt.atob(
              payload.raw.replace(/-/g, "+").replace(/_/g, "/"))
          })
        }
      }
      MoreRow {
        text: "Download original"
        onActivated: {
          var mid = msgMenu.messageId; msgMenu.close()
          if (!root.service || !mid) return
          root.service.getMessageRaw(mid, function(payload) {
            if (!payload || !payload.raw) return
            var decoded = Qt.atob(
              payload.raw.replace(/-/g, "+").replace(/_/g, "/"))
            emlWriter.payload = decoded
            var home = Quickshell.env("HOME")
            emlWriter.command = ["sh", "-c",
              "mkdir -p \"$1/Downloads\"", "sh", home]
            emlWriter.emlPath = home + "/Downloads/" + mid + ".eml"
            emlWriter.running = true
          })
        }
      }
      MoreRow {
        text: "Open in browser"
        tone: root.dimColor
        onActivated: {
          msgMenu.close()
          if (root.service) root.service.openInBrowser(root.service.selectedId)
        }
      }
    }
  }

  Popup {
    id: rawSourceView
    property string rawText: ""
    property bool loading: false
    anchors.centerIn: parent
    width: parent.width * 0.85
    height: parent.height * 0.85
    padding: Style.space(12)
    modal: true; focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle {
      radius: Style.cornerRadius
      color: Color.popups.background
      border.width: 1; border.color: Color.popups.border
    }
    contentItem: Item {
      Text {
        anchors.centerIn: parent
        visible: rawSourceView.loading
        text: "Loading\u2026"
        color: root.dimColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.body
      }
      Flickable {
        anchors.fill: parent
        visible: !rawSourceView.loading
        contentWidth: rawContent.width
        contentHeight: rawContent.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        TextEdit {
          id: rawContent
          width: rawSourceView.width - Style.space(24)
          text: rawSourceView.rawText
          textFormat: TextEdit.PlainText
          readOnly: true
          selectByMouse: true
          wrapMode: TextEdit.Wrap
          color: root.textColor
          font.family: "monospace"
          font.pixelSize: Style.font.caption
        }
      }
      Rectangle {
        anchors.right: parent.right; anchors.top: parent.top
        width: Style.space(24); height: Style.space(24)
        radius: width / 2
        color: rawCloseHov.hovered
          ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.15)
          : "transparent"
        Text {
          anchors.centerIn: parent; text: "\u2715"
          color: root.dimColor; font.pixelSize: Style.font.body
        }
        HoverHandler { id: rawCloseHov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: rawSourceView.close() }
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

  Process {
    id: emlWriter
    property string payload: ""
    property string emlPath: ""
    onExited: {
      if (payload !== "" && emlPath !== "") {
        emlFile.path = emlPath
        emlFile.setText(payload)
        payload = ""
        emlPath = ""
      }
    }
  }

  FileView {
    id: emlFile
    path: ""
  }

  Shortcut {
    sequence: "Ctrl+Return"
    enabled: root.visible && root.replyOpen
    onActivated: root.submitReply()
  }

  component ThreadAction: Item {
    property string label
    property string shortcut: ""
    signal activated()
    width: taCol.implicitWidth + Style.space(16)
    height: parent.height

    Column {
      id: taCol
      anchors.centerIn: parent
      spacing: Style.space(1)
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: label
        color: taHover.hovered ? root.textColor : root.dimColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        visible: shortcut !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        text: shortcut
        color: root.dimColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.caption
      }
    }
    HoverHandler { id: taHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: activated() }
  }

  component MoreRow: Rectangle {
    property string text
    property string shortcut: ""
    property string hint: ""
    property color tone: root.textColor
    signal activated()
    width: parent ? parent.width : 0
    implicitHeight: Style.spacing.popupRowHeight
    radius: Style.cornerRadius
    color: mrHover.hovered
      ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.08)
      : "transparent"
    Text {
      anchors.left: parent.left; anchors.leftMargin: Style.space(9)
      anchors.verticalCenter: parent.verticalCenter
      text: parent.text; color: parent.tone
      font.family: root.panelFontFamily; font.pixelSize: Style.font.bodySmall
    }
    Text {
      anchors.right: parent.right; anchors.rightMargin: Style.space(9)
      anchors.verticalCenter: parent.verticalCenter
      visible: parent.shortcut !== "" || parent.hint !== ""
      text: parent.shortcut !== "" ? parent.shortcut : parent.hint
      color: root.dimColor
      font.family: root.panelFontFamily; font.pixelSize: Style.font.caption
    }
    HoverHandler { id: mrHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: parent.activated() }
  }
}
