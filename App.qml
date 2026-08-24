import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui

import "Model.js" as Model
import "components"

// The application window. The shell loads this entry point when the plugin is
// summoned and calls open()/close() on it; the FloatingWindow follows.
//
// Compose is a second window rather than a column. Hyprland tiles it beside
// the mailbox, so the message being answered stays on screen instead of being
// covered by the form.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false
  property bool closingFromHost: false

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "hmail"

  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  // Mixed toward the ground rather than Qt.darker: on a light theme darkening
  // an almost-black foreground makes secondary text heavier than body text.
  readonly property color dim: Qt.rgba(
    foreground.r * 0.68 + background.r * 0.32,
    foreground.g * 0.68 + background.g * 0.32,
    foreground.b * 0.68 + background.b * 0.32, 1)
  readonly property color dimmer: Qt.rgba(
    foreground.r * 0.45 + background.r * 0.55,
    foreground.g * 0.45 + background.g * 0.55,
    foreground.b * 0.45 + background.b * 0.55, 1)
  // Omarchy's palette has no separate "primary": `accent` is it. This theme's
  // accent is near fully saturated, which is right for a 5px unread dot and
  // wrong for a link sitting inside a paragraph. Same hue, same lightness,
  // capped saturation — calm enough to read past, still clearly a link.
  readonly property color link: Qt.hsla(accent.hslHue,
    Math.min(accent.hslSaturation, 0.55),
    accent.hslLightness, 1.0)

  readonly property string fontFamily: Style.font.family

  // Two breakpoints, not a continuum: three columns, list-plus-reader with the
  // workflow sidebar hidden, and a single column that swaps list for reader.
  readonly property bool wide: window.width >= Style.space(1000)
  readonly property bool compact: window.width < Style.space(760)

  property string currentView: "list"
  property string cursorId: ""
  property var selectedIds: ({})
  property int selectedCount: 0
  readonly property bool multiSelectActive: selectedCount > 0

  function toggleSelect(id) {
    var s = selectedIds
    if (s[id]) { delete s[id] } else { s[id] = true }
    selectedIds = s
    selectedCount = Object.keys(s).length
  }
  function clearSelection() {
    selectedIds = {}
    selectedCount = 0
  }
  function bulkAct(fn) {
    var ids = Object.keys(selectedIds)
    for (var i = 0; i < ids.length; i++) fn(ids[i])
    clearSelection()
  }

  property var readTogetherQueue: []
  property int readTogetherIndex: 0
  readonly property bool readingTogether: readTogetherQueue.length > 0

  property bool replyTogetherMode: false

  function startReadTogether() {
    var ids = Object.keys(selectedIds)
    if (ids.length === 0) return
    clearSelection()
    replyTogetherMode = false
    readTogetherQueue = ids
    readTogetherIndex = 0
    openMessage(ids[0])
  }
  function startReplyTogether() {
    var ids = Object.keys(selectedIds)
    if (ids.length === 0) return
    clearSelection()
    replyTogetherMode = true
    readTogetherQueue = ids
    readTogetherIndex = 0
    openMessage(ids[0])
    Qt.callLater(function() { reader.focusReply() })
  }
  function nextReadTogether() {
    if (readTogetherIndex + 1 >= readTogetherQueue.length) {
      readTogetherQueue = []
      readTogetherIndex = 0
      replyTogetherMode = false
      backToList()
      return
    }
    readTogetherIndex++
    openMessage(readTogetherQueue[readTogetherIndex])
    if (replyTogetherMode) {
      Qt.callLater(function() { reader.focusReply() })
    }
  }
  function exitReadTogether() {
    readTogetherQueue = []
    readTogetherIndex = 0
    replyTogetherMode = false
  }

  // Kept across messages: somebody who wants plain text wants it for their
  // mail, not for one message.
  property bool plainTextForced: false
  // Reading zoom for the message body only. The window's own chrome follows
  // the theme's font scale, which is Omarchy's to set, not this app's.
  property real bodyZoom: 1.0
  // 0 means "proportional"; anything else is a width somebody dragged to.
  property real listWidth: 0

  function zoomBy(step) {
    bodyZoom = Math.max(0.6, Math.min(2.5, Math.round((bodyZoom + step) * 20) / 20))
  }
  property bool shortcutHelpVisible: false
  property bool setupVisible: false
  property bool settingsVisible: false
  // Something the window needs to say that no account is reporting — refusing a
  // duplicate mailbox, for one. Cleared on a timer so it cannot outlive its
  // moment on the status line.
  property string notice: ""
  onNoticeChanged: if (notice !== "") noticeTimer.restart()
  // The stored preference used to mean "collapse to an icon rail". It now means
  // hide the sidebar completely; the compact workflow tabs and More browser
  // keep every destination reachable.
  readonly property bool sidebarCollapsed: !!service && service.sidebarCollapsed
  function toggleSidebar() {
    if (service) service.setSidebarCollapsed(!service.sidebarCollapsed)
  }

  readonly property bool ready: !!service && service.ready
  // The walkthrough is for having no mailbox at all. A mailbox that has been
  // added but not signed in yet belongs in settings, next to the ones that are.
  readonly property bool anyReady: !!service && service.anyAccountReady
  readonly property bool showSetup: setupVisible || !anyReady
  readonly property bool showSettings: settingsVisible && !showSetup
  // Anything the window goes *into*. The mail chrome stands down for all of it.
  readonly property bool showPage: showSetup || showSettings
  readonly property bool composing: compose.opened
  readonly property bool showingFeed: !!service && service.workflowEnabled
    && service.workflowKey === "feed"
  readonly property bool imboxSinglePane: !!service && service.workflowEnabled
    && service.workflowKey === "inbox" && currentView === "list"
  property bool powerThroughActive: false
  // Exit power-through whenever the user navigates away.
  onCurrentViewChanged: powerThroughActive = false
  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onWorkflowKeyChanged() { root.powerThroughActive = false }
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(String(payloadJson || "{}")) || ({}) } catch (e) {}
    closingFromHost = false
    opened = true
    if (service) service.windowOpen = true
    if (payload.mailbox && service) service.selectMailbox(String(payload.mailbox))
    if (payload.compose === true) startCompose("new")
    Qt.callLater(function() { focusScope.forceActiveFocus() })
  }

  function close() {
    closingFromHost = true
    opened = false
    if (service) service.windowOpen = false
    closingFromHost = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  // Plain text is a preference and survives; the heavy-document override is a
  // per-message decision about one specific message and does not.
  function openMessage(id) {
    if (!service) return
    cursorId = String(id || "")
    service.select(cursorId)
    currentView = "reader"
  }

  function backToList() {
    if (service) service.clearSelection()
    currentView = "list"
    Qt.callLater(function() { focusScope.forceActiveFocus() })
  }

  function moveCursor(delta) {
    if (!service) return
    var next = service.selectOffset(delta, cursorId)
    if (next === "") return
    cursorId = next
    Qt.callLater(followCursor)
    // Moving is not opening. This used to open whatever it landed on while the
    // reader was up, which made stepping through a list a way to mark half of
    // it read without having looked at any of it. Enter and "o" open.
  }

  function jumpCursor(toEnd) {
    if (!service || service.messages.length === 0) return
    cursorId = service.messages[toEnd ? service.messages.length - 1 : 0].id
    Qt.callLater(followCursor)
  }

  function followCursor() {
    if (showingFeed) feedView.revealCursor()
    else list.ensureCursorVisible()
  }

  function startCompose(mode) {
    compose.begin(String(mode || "new"),
      service ? service.selectedMessage : null,
      service ? service.selectedBody.text : "")
  }

  // Acting on the open message closes it: it is about to leave this list.
  function actOnCursor(action) {
    if (!service || cursorId === "") return
    var wasOpen = currentView === "reader" && service.selectedId === cursorId
    var next = service.selectOffset(1, cursorId)
    service.act(cursorId, action)
    if (wasOpen && !Model.survivesAction(service.mailboxKey, action)) {
      if (next !== "" && next !== cursorId) openMessage(next)
      else backToList()
    }
  }

  function goMailbox(key) {
    if (!service) return
    service.selectMailbox(key)
    backToList()
  }

  function goWorkflow(key) {
    if (!service) return
    clearSelection()
    service.selectWorkflow(key)
    backToList()
    Qt.callLater(function() {
      root.cursorId = service.messages.length > 0 ? service.messages[0].id : ""
      root.followCursor()
    })
  }

  function routeCursor(destination) {
    if (!service || cursorId === "") return
    if (service.workflowKey === "screener") service.routeSender(cursorId, destination)
    else service.moveThread(cursorId, destination)
    Qt.callLater(function() {
      root.cursorId = service.messages.length > 0 ? service.messages[0].id : ""
    })
  }

  function pileCursor(pile) {
    if (!service || cursorId === "") return
    service.setWorkflowPile(cursorId, pile)
    Qt.callLater(function() {
      root.cursorId = service.messages.length > 0 ? service.messages[0].id : ""
    })
  }

  function bubbleCursor() {
    if (!service || cursorId === "") return
    service.scheduleWorkflowBubble(cursorId, new Date(Date.now() + 24 * 60 * 60 * 1000))
  }

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onReplySent() {
      compose.finish()
      if (root.replyTogetherMode && root.readingTogether) {
        Qt.callLater(function() { root.nextReadTogether() })
      }
    }
    // A new account has no mailbox yet, so the only useful place to be is the
    // page that gives it one.
    // A new mailbox appears as a row in Settings, waiting to be signed in.
    // Sending the window to the first-run walkthrough instead showed a setup
    // that was already finished, for a different account.
    function onDuplicateAccount(email) {
      root.notice = email + " is already added"
    }
    function onAccountAdded() {
      root.setupVisible = false
      root.settingsVisible = true
    }
    function onMessagesChanged() {
      if (!root.service || root.service.messages.length === 0) {
        root.cursorId = ""
        return
      }
      if (Model.indexById(root.service.messages, root.cursorId) < 0)
        root.cursorId = root.service.messages[0].id
    }
  }

  FloatingWindow {
    id: window
    visible: root.opened
    title: "Hmail"
    color: root.background
    implicitWidth: Style.space(980)
    implicitHeight: Style.space(720)
    minimumSize: Qt.size(Style.space(760), Style.space(520))

    onVisibleChanged: {
      if (!visible && root.opened && !root.closingFromHost) root.requestClose()
    }

    FocusScope {
      id: focusScope
      anchors.fill: parent
      focus: true

      // Every shortcut below is a bare letter, so all of them stand down while
      // text is being typed. The search field is the only input in this window
      // — compose is a window of its own — so it is the only thing to ask.
      readonly property bool typing: searchBar.fieldFocused || root.composing
        || reader.replying

      // ------------------------------------------------------------ header

      Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(48)

        // Identity first, controls after, with a rule between them: the mark
        // and the name say what this window is, and everything to their right
        // does something.
        Row {
          id: headerLeft
          anchors.left: parent.left
          anchors.leftMargin: Style.space(14)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Hmail"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          // Next to the mark: this is the window's own menu, not an action on
          // the mailbox. Anchored to the button's own edge so it lands in the
          // same place however the control was pressed.
          IconButton {
            id: menuButton
            anchors.verticalCenter: parent.verticalCenter
            iconName: "menu"
            tooltipText: "Menu"
            foreground: root.dim
            hoverColor: root.foreground
            fontFamily: root.fontFamily
            selected: appMenu.opened
            onClicked: {
              var scene = mapToGlobal(0, height)
              appMenu.openAt(scene.x, scene.y)
            }
          }
        }

        // The slot is whatever the two clusters leave, so the field shrinks with
        // the window instead of running underneath Check mail. Centring it in
        // the header and reserving a fixed width could not work: the reserve is
        // split evenly either side, while the controls are all on the left.
        Item {
          id: searchSlot
          anchors.left: headerLeft.right
          anchors.right: headerRight.left
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          height: searchBar.implicitHeight

          SearchBar {
            id: searchBar
            anchors.verticalCenter: parent.verticalCenter
            // Centred on the header rather than on the gap, so it lines up with
            // the window instead of with whatever the controls happen to leave.
            // Clamped into the slot, which is what keeps it off Check mail when
            // the two clusters are not the same width.
            x: Math.max(0, Math.min(parent.width - width,
              (header.width - width) / 2 - parent.x))
            // Capped well short of the gap it is given: a search field as wide
            // as the window looks like the window's main event, and it is not.
            width: Math.min(Style.space(340), parent.width)
            // Below this it is a slot too small to type in; the shortcut still
            // works and reopens it as the window grows.
            visible: !root.showPage && parent.width >= Style.space(120)
          textColor: root.foreground
          accentColor: root.accent
          panelFontFamily: root.fontFamily
          // A search replaces the list, so the message still open in the
          // reader is almost certainly not in the results any more.
          onSubmitted: function(query) {
            if (!root.service) return
            root.service.search(query)
            root.backToList()
          }
          onCleared: {
            if (!root.service) return
            root.service.search("")
            root.backToList()
          }
          }
        }

        Row {
          id: headerRight
          anchors.right: parent.right
          anchors.rightMargin: Style.space(14)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          // Checking for mail and writing one are both things you do to the
          // mailbox as a whole, so they sit together. The menu is the window's
          // own, and it stays on the left with the mark.
          IconButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.showPage
            iconName: "refresh"
            tooltipText: root.service && root.service.listLoading
              ? "Checking for mail…" : "Check mail · F5"
            foreground: root.dim
            hoverColor: root.foreground
            fontFamily: root.fontFamily
            enabled: root.ready && !(root.service && root.service.listLoading)
            onClicked: if (root.service) root.service.refresh()
          }

          IconButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.showPage
            iconName: "send"
            tooltipText: "Compose · c"
            foreground: root.dim
            hoverColor: root.foreground
            fontFamily: root.fontFamily
            enabled: root.ready
            onClicked: root.startCompose("new")
          }

        }

        PanelSeparator {
          anchors.bottom: parent.bottom
          width: parent.width
          foreground: root.foreground
        }
      }

      // -------------------------------------------------------------- body

      Item {
        id: body
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: statusBar.top

        MailboxSidebar {
          id: sidebar
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: Style.space(164)
          visible: !root.compact && !root.sidebarCollapsed
            && !root.showPage && !root.composing
          collapsed: false
          service: root.service
          textColor: root.foreground
          accentColor: root.accent
          dimColor: root.dim
          panelFontFamily: root.fontFamily
          switcherOpen: accountSwitcher.opened
          onSwitcherRequested: function(sceneX, sceneY) { accountSwitcher.openAt(sceneX, sceneY) }
          onWorkflowSelected: function(key) { root.goWorkflow(key) }
          onMoreRequested: function(sceneX, sceneY) {
            mailboxMore.openAt(sceneX, sceneY)
          }
        }

        // Narrow windows lose the sidebar; the same mailboxes come back as a
        // scrolling strip above the list.
        MailboxTabs {
          id: tabs
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: Style.space(14)
          visible: false
          textColor: root.foreground
          panelFontFamily: root.fontFamily
          entries: sidebar.compactEntries
          counts: root.service ? root.service.workflowCounts : ({})
          current: root.service && root.service.workflowEnabled
            ? root.service.workflowKey : ""
          unread: 0
          onSelected: function(key) { root.goWorkflow(key) }
          onMoreRequested: function(sceneX, sceneY) {
            mailboxMore.openAt(sceneX, sceneY)
          }
        }

        Item {
          id: listColumn
          anchors.left: sidebar.visible ? sidebar.right : parent.left
          anchors.top: tabs.visible ? tabs.bottom : parent.top
          anchors.bottom: parent.bottom
          anchors.topMargin: tabs.visible ? Style.space(8) : 0
          // Proportional until somebody drags the divider, then whatever they
          // dragged it to. The floor is low on purpose: at a hundred pixels the
          // column is a strip of times and initials, which is a legitimate way
          // to work when the message is what you are reading. Refusing to go
          // there was the app deciding how someone else should use their screen.
          width: root.powerThroughActive ? 0
            : root.imboxSinglePane ? parent.width
            : root.compact
              ? (root.currentView === "list" ? parent.width : 0)
              : Math.max(Style.space(100),
                  Math.min(parent.width - Style.space(360),
                    root.listWidth > 0 ? root.listWidth
                      : Math.min(Style.space(460), Math.round(parent.width * 0.34))))
          visible: width > 0 && !root.showPage && !root.composing && !root.showingFeed

          // Normal message list
          Flickable {
            id: listFlick
            anchors.fill: parent
            contentWidth: width
            contentHeight: list.implicitHeight + Style.space(16)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            MessageList {
              id: list
              y: Style.space(8)
              width: root.imboxSinglePane
                ? Math.min(Style.space(680), listFlick.width - Style.space(28))
                : listFlick.width - Style.space(14)
              anchors.horizontalCenter: root.imboxSinglePane ? parent.horizontalCenter : undefined
              service: root.service
              textColor: root.foreground
              accentColor: root.accent
              dimColor: root.dim
              panelFontFamily: root.fontFamily
              cursorId: root.cursorId
              viewport: listFlick
              checkedIds: root.selectedIds
              onMessageActivated: function(id) {
                if (root.multiSelectActive) root.toggleSelect(id)
                else root.openMessage(id)
              }
              onRowHovered: function(id, isHovered) { if (isHovered) root.cursorId = id }
              onMenuRequested: function(id, sceneX, sceneY) {
                root.cursorId = id
                rowMenu.openAt(id, sceneX, sceneY)
              }
              onQuickActionsRequested: function(id, sceneX, sceneY) {
                root.cursorId = id
                quickActions.openAt(id, sceneX, sceneY)
              }
              onSelectToggled: function(id) { root.toggleSelect(id) }
              onScreenerRequested: root.goWorkflow("screener")
              onPowerThroughRequested: root.powerThroughActive = true
            }
          }

          Item {
            anchors.fill: parent
            visible: !!root.service && root.service.workflowEnabled
              && root.service.workflowKey === "screener"
              && root.service.listLoaded
              && root.service.messages.length === 0
            z: 5

            Column {
              anchors.centerIn: parent
              spacing: Style.space(16)

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "\u2728"
                font.pixelSize: Style.space(48)
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "You\u2019re all caught up!"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No first-time senders to screen."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: scrBackLabel.implicitWidth + Style.space(24)
                height: Style.space(36)
                radius: Style.cornerRadius
                color: scrBackHover.hovered ? root.accent : Qt.darker(root.accent, 1.15)
                Text {
                  id: scrBackLabel
                  anchors.centerIn: parent
                  text: "Back to Imbox"
                  color: Qt.rgba(1, 1, 1, 1)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
                HoverHandler { id: scrBackHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.goWorkflow("inbox") }
              }
            }
          }

        }

        FeedView {
          id: feedView
          anchors.left: sidebar.visible ? sidebar.right : parent.left
          anchors.right: parent.right
          anchors.top: tabs.visible ? tabs.bottom : parent.top
          anchors.topMargin: tabs.visible ? Style.space(8) : 0
          anchors.bottom: parent.bottom
          visible: root.showingFeed && root.currentView === "list"
            && !root.showPage && !root.composing
          service: root.service
          textColor: root.foreground
          backgroundColor: root.background
          accentColor: root.accent
          dimColor: root.dim
          panelFontFamily: root.fontFamily
          cursorId: root.cursorId
          onMessageFocused: function(id) { root.cursorId = id }
          onMessageActivated: function(id) { root.openMessage(id) }
        }

        // The divider between the list and the message, and the handle that
        // moves it. A hairline is the right thing to look at and the wrong
        // thing to aim at, so the grab area is wider than the rule it draws.
        Item {
          id: listSplitter
          anchors.left: listColumn.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: Style.space(5)
          visible: listColumn.visible && !root.compact && !root.imboxSinglePane
          z: 5

          PanelSeparator {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            foreground: root.foreground
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.SplitHCursor
            property real grabbedAt: 0
            property real grabbedWidth: 0

            onPressed: function(mouse) {
              grabbedAt = mapToItem(body, mouse.x, mouse.y).x
              grabbedWidth = listColumn.width
            }
            onPositionChanged: function(mouse) {
              if (!pressed) return
              var moved = mapToItem(body, mouse.x, mouse.y).x - grabbedAt
              root.listWidth = grabbedWidth + moved
            }
            // Back to the proportional default, which is what most people
            // want after one bad drag.
            onDoubleClicked: root.listWidth = 0
          }
        }

        // Power Through New — full-width centered view, same layout as Feed.
        Item {
          id: powerThroughPane
          anchors.left: sidebar.visible ? sidebar.right : parent.left
          anchors.right: parent.right
          anchors.top: tabs.visible ? tabs.bottom : parent.top
          anchors.bottom: parent.bottom
          anchors.topMargin: tabs.visible ? Style.space(8) : 0
          visible: root.powerThroughActive && !root.showPage && !root.composing

          function expandCurrent() {
            for (var i = 0; i < ptRepeater.count; i++) {
              var item = ptRepeater.itemAt(i)
              if (item && item.summary && item.summary.id === root.cursorId) {
                item.toggleExpand()
                return
              }
            }
          }

          function scrollBy(delta) {
            var newY = ptFlick.contentY + delta
            ptFlick.contentY = Math.max(0, Math.min(ptFlick.contentHeight - ptFlick.height, newY))
          }

          function moveCursor(delta) {
            var msgs = root.service ? root.service.workflowNewMessages : []
            if (!msgs || msgs.length === 0) return
            var idx = -1
            for (var i = 0; i < msgs.length; i++) {
              if (msgs[i].id === root.cursorId) { idx = i; break }
            }
            if (idx < 0) idx = 0
            else idx = Math.max(0, Math.min(msgs.length - 1, idx + delta))
            root.cursorId = msgs[idx].id
          }

          Item {
            id: ptTopBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: Style.space(16)
            anchors.rightMargin: Style.space(16)
            height: Style.space(44)

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              text: "New for You"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Button {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(14)
              anchors.verticalCenter: parent.verticalCenter
              text: "Done · Shift+H"
              foreground: root.foreground
              bordered: true
              fontSize: Style.font.caption
              onClicked: root.powerThroughActive = false
            }
          }

          PanelSeparator {
            id: ptTopSep
            anchors.top: ptTopBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            foreground: root.foreground
          }

          Flickable {
            id: ptFlick
            anchors.top: ptTopSep.bottom
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width - Style.space(80), Style.space(720))
            contentWidth: width
            contentHeight: ptCol.implicitHeight + Style.space(20)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            visible: root.service && root.service.workflowNewMessages.length > 0

            Column {
              id: ptCol
              width: ptFlick.width
              spacing: Style.space(14)
              topPadding: Style.space(10)
              bottomPadding: Style.space(10)

              Repeater {
                id: ptRepeater
                model: root.service ? root.service.workflowNewMessages : []

                FeedCard {
                  required property var modelData
                  width: ptCol.width
                  summary: modelData
                  service: root.service
                  textColor: root.foreground
                  backgroundColor: root.background
                  accentColor: root.accent
                  dimColor: root.dim
                  panelFontFamily: root.fontFamily
                  focused: root.cursorId === modelData.id
                  onCardFocused: root.cursorId = modelData.id
                }
              }
            }
          }

          Item {
            anchors.fill: parent
            visible: !root.service || root.service.workflowNewMessages.length === 0
            z: 5

            Column {
              anchors.centerIn: parent
              spacing: Style.space(16)

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "\u2728"
                font.pixelSize: Style.space(48)
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "You\u2019re all caught up!"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No new messages to power through."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: ptBackLabel.implicitWidth + Style.space(24)
                height: Style.space(36)
                radius: Style.cornerRadius
                color: ptBackHover.hovered ? root.accent : Qt.darker(root.accent, 1.15)
                Text {
                  id: ptBackLabel
                  anchors.centerIn: parent
                  text: "Back to Imbox"
                  color: Qt.rgba(1, 1, 1, 1)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
                HoverHandler { id: ptBackHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.powerThroughActive = false }
              }
            }
          }
        }

        ThreadView {
          id: reader
          anchors.left: listSplitter.visible ? listSplitter.right : parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          visible: !root.powerThroughActive && !root.showPage && !root.composing
            && (!root.showingFeed || root.currentView === "reader")
            && (!root.compact || root.currentView === "reader")
            && !root.imboxSinglePane
          service: root.service
          textColor: root.foreground
          backgroundColor: root.background
          accentColor: root.accent
          linkColor: root.link
          dimColor: root.dim
          dimmerColor: root.dimmer
          panelFontFamily: root.fontFamily
          zoom: root.bodyZoom
          onBackRequested: {
            if (root.readingTogether) root.exitReadTogether()
            root.backToList()
          }
          onForwardRequested: root.startCompose("forward")
          onReplyAllRequested: root.startCompose("replyAll")
          onLabelRequested: {
            if (root.service && root.service.selectedId !== "")
              labelPicker.openFor(root.service.selectedId)
          }
          onCollectionRequested: {
            if (root.service && root.service.selectedId !== "")
              collectionPicker.openFor(root.service.selectedId)
          }
          onSenderSearchRequested: function(email) {
            root.backToList()
            if (root.service) root.service.search("from:" + email)
          }
          onActionRequested: function(action) {
            if (root.service && root.service.selectedId !== "") {
              root.cursorId = root.service.selectedId
              root.actOnCursor(action)
            }
          }
        }

        // Composing takes the whole body. Omarchy's panel mechanism would give
        // a second window its own region, which is not what a reply is.
        Rectangle {
          visible: root.readingTogether && root.currentView === "reader"
          anchors.top: reader.top
          anchors.horizontalCenter: reader.horizontalCenter
          anchors.topMargin: Style.space(8)
          z: 20
          width: rtLabel.implicitWidth + Style.space(20)
          height: Style.space(26)
          radius: Style.space(13)
          color: Color.popups.background
          border.width: 1; border.color: Color.popups.border
          Row {
            id: rtLabel
            anchors.centerIn: parent
            spacing: Style.space(6)
            Text {
                text: (root.replyTogetherMode ? "Replying " : "Reading ")
                + (root.readTogetherIndex + 1)
                + " of " + root.readTogetherQueue.length
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              text: "Shift+N \u2192 next"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        ComposeView {
          id: compose
          anchors.fill: parent
          visible: root.composing && !root.showPage
          service: root.service
          textColor: root.foreground
          backgroundColor: root.background
          accentColor: root.accent
          dimColor: root.dim
          dimmerColor: root.dimmer
          panelFontFamily: root.fontFamily
        }

        // Setup takes the whole body: there is nothing else to look at until
        // the mailbox is connected.
        Flickable {
          id: setupFlick
          anchors.fill: parent
          anchors.margins: Style.space(18)
          visible: root.showSetup
          contentWidth: width
          contentHeight: setupHolder.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          // A holder the width of the viewport, so the page below can centre
          // against something real. Anchoring beats arithmetic here: a
          // Flickable reparents its children, and an x binding written against
          // the Flickable's own width lands before that reparenting settles.
          Item {
            id: setupHolder
            width: setupFlick.width
            implicitHeight: setup.implicitHeight

          SetupPage {
            id: setup
            // A measure this long is unreadable across a wide window, so it is
            // capped rather than stretched.
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(setupHolder.width, Style.space(560))
            service: root.service
            textColor: root.foreground
            dimColor: root.dim
            panelFontFamily: root.fontFamily
            canLeave: root.anyReady
            onBackRequested: root.setupVisible = false
          }
          }
        }

        // The settings page, which is where mailboxes are added and removed.
        Flickable {
          id: settingsFlick
          anchors.fill: parent
          anchors.margins: Style.space(18)
          visible: root.showSettings
          contentWidth: width
          contentHeight: settingsHolder.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Item {
            id: settingsHolder
            width: settingsFlick.width
            implicitHeight: settings.implicitHeight

            SettingsPage {
              id: settings
              anchors.horizontalCenter: parent.horizontalCenter
              width: Math.min(settingsHolder.width, Style.space(560))
              service: root.service
              textColor: root.foreground
              dimColor: root.dim
              accentColor: root.accent
              urgentColor: root.urgent
              panelFontFamily: root.fontFamily
              onBackRequested: root.settingsVisible = false
              onClientSetupRequested: root.setupVisible = true
              onAddRequested: if (root.service) root.service.addAccount()
              onSignInRequested: function(index) {
                if (!root.service) return
                root.service.switchToIndex(index)
                root.service.signIn()
              }
              onSignOutRequested: function(index) {
                if (!root.service) return
                root.service.switchToIndex(index)
                root.service.signOut()
              }
              onRemoveRequested: function(index) {
                if (root.service) root.service.removeAccountAt(index)
              }
            }
          }
        }
      }

      // ── HEY-style pile cards (Imbox bottom) ────────────────────────────

      readonly property bool showActionTray: !!root.service
        && root.service.workflowEnabled
        && root.service.workflowKey === "inbox"
        && root.currentView === "list"
        && !root.showPage && !root.composing
        && !root.powerThroughActive && !root.showingFeed
        && !root.multiSelectActive

      Row {
        id: actionTray
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: statusBar.top
        anchors.bottomMargin: Style.space(4)
        spacing: Style.space(8)
        visible: parent.showActionTray
        z: 10

        readonly property var counts: root.service ? root.service.workflowCounts : ({})
        readonly property int rlCount: Number(counts["reply_later"] || 0)
        readonly property int saCount: Number(counts["set_aside"] || 0)

        function _avatarHue(email) {
          var s = email || ""
          var h = 0
          for (var i = 0; i < s.length; i++)
            h = (h * 31 + s.charCodeAt(i)) % 360
          return h / 360
        }

        PileCard {
          id: rlCard
          visible: actionTray.rlCount > 0
          icon: "\u21A9"
          pileLabel: "Reply Later"
          count: actionTray.rlCount
          preview: root.service ? root.service.replyLaterPreview : []
          goLabel: "Go to Focus & Reply\u2026"
          onActivated: {
            if (count <= 1) { root.goWorkflow("reply_later"); return }
            rlPopup.open()
          }
          onGoRequested: root.goWorkflow("reply_later")

          Popup {
            id: rlPopup
            x: 0; y: -implicitHeight - Style.space(6)
            width: Style.space(320)
            implicitHeight: rlPopupCol.implicitHeight + Style.space(8)
            padding: Style.space(4); modal: false; focus: true
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
            background: Rectangle { radius: Style.cornerRadius; color: Color.popups.background; border.width: 1; border.color: Color.popups.border }
            contentItem: Column {
              id: rlPopupCol; spacing: Style.space(2)
              Text {
                leftPadding: Style.space(6); topPadding: Style.space(4); bottomPadding: Style.space(2)
                text: "REPLY LATER (" + actionTray.rlCount + ")"
                color: root.dim; font.family: root.fontFamily
                font.pixelSize: Style.font.caption; font.bold: true
              }
              Repeater {
                model: root.service ? root.service.replyLaterPreview : []
                PilePreviewRow {
                  required property var modelData
                  required property int index
                  subject: modelData.subject || ""
                  senderName: modelData.from ? modelData.from.display : ""
                  senderEmail: modelData.from ? modelData.from.email : ""
                  avatarHue: actionTray._avatarHue(senderEmail)
                  onActivated: { rlPopup.close(); root.openMessage(modelData.id) }
                }
              }
              Text {
                visible: actionTray.rlCount > 4
                leftPadding: Style.space(6); topPadding: Style.space(4)
                text: "+ " + (actionTray.rlCount - 4) + " more\u2026"
                color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
              }
              Rectangle {
                width: parent.width; implicitHeight: Style.space(32)
                color: "transparent"; radius: Style.cornerRadius
                Text {
                  anchors.centerIn: parent
                  text: "Go to Focus & Reply\u2026"
                  color: root.accent; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { rlPopup.close(); root.goWorkflow("reply_later") } }
              }
            }
          }
        }

        PileCard {
          id: saCard
          visible: actionTray.saCount > 0
          icon: "\u{1F4CC}"
          pileLabel: "Set Aside"
          count: actionTray.saCount
          preview: root.service ? root.service.setAsidePreview : []
          goLabel: "Go to Set Aside\u2026"
          onActivated: {
            if (count <= 1) { root.goWorkflow("set_aside"); return }
            saPopup.open()
          }
          onGoRequested: root.goWorkflow("set_aside")

          Popup {
            id: saPopup
            x: 0; y: -implicitHeight - Style.space(6)
            width: Style.space(320)
            implicitHeight: saPopupCol.implicitHeight + Style.space(8)
            padding: Style.space(4); modal: false; focus: true
            closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
            background: Rectangle { radius: Style.cornerRadius; color: Color.popups.background; border.width: 1; border.color: Color.popups.border }
            contentItem: Column {
              id: saPopupCol; spacing: Style.space(2)
              Text {
                leftPadding: Style.space(6); topPadding: Style.space(4); bottomPadding: Style.space(2)
                text: "SET ASIDE (" + actionTray.saCount + ")"
                color: root.dim; font.family: root.fontFamily
                font.pixelSize: Style.font.caption; font.bold: true
              }
              Repeater {
                model: root.service ? root.service.setAsidePreview : []
                PilePreviewRow {
                  required property var modelData
                  required property int index
                  subject: modelData.subject || ""
                  senderName: modelData.from ? modelData.from.display : ""
                  senderEmail: modelData.from ? modelData.from.email : ""
                  avatarHue: actionTray._avatarHue(senderEmail)
                  onActivated: { saPopup.close(); root.openMessage(modelData.id) }
                }
              }
              Text {
                visible: actionTray.saCount > 4
                leftPadding: Style.space(6); topPadding: Style.space(4)
                text: "+ " + (actionTray.saCount - 4) + " more\u2026"
                color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
              }
              Rectangle {
                width: parent.width; implicitHeight: Style.space(32)
                color: "transparent"; radius: Style.cornerRadius
                Text {
                  anchors.centerIn: parent
                  text: "Go to Set Aside\u2026"
                  color: root.accent; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { saPopup.close(); root.goWorkflow("set_aside") } }
              }
            }
          }
        }
      }

      component PileCard: Rectangle {
        id: pc
        property string icon; property string pileLabel
        property int count: 0
        property var preview: []
        property string goLabel: ""
        signal activated()
        signal goRequested()

        readonly property string _firstSender: preview.length > 0 && preview[0].from
          ? preview[0].from.display : ""
        readonly property string _firstEmail: preview.length > 0 && preview[0].from
          ? preview[0].from.email : ""
        readonly property string _firstSubject: preview.length > 0
          ? (preview[0].subject || pileLabel) : pileLabel

        function _hue(email) {
          var s = email || ""; var h = 0
          for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 360
          return h / 360
        }

        width: pcRow.implicitWidth + Style.space(20)
        height: Style.space(44); radius: Style.cornerRadius
        color: pcHover.hovered ? Color.popups.background
          : Qt.rgba(Color.popups.background.r, Color.popups.background.g,
            Color.popups.background.b, 0.85)
        border.width: 1; border.color: Color.popups.border
        Row {
          id: pcRow; anchors.centerIn: parent; spacing: Style.space(8)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: pc.icon; font.pixelSize: Style.font.bodySmall
          }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(26); height: Style.space(26); radius: Style.space(13)
            color: Qt.hsla(pc._hue(pc._firstEmail), 0.50, 0.42, 1.0)
            Text {
              anchors.centerIn: parent
              text: pc._firstSender.length > 0
                ? pc._firstSender.charAt(0).toUpperCase() : "?"
              color: Qt.rgba(1, 1, 1, 1); font.family: root.fontFamily
              font.pixelSize: Style.font.caption; font.bold: true
            }
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter; spacing: 0
            Text {
              text: pc._firstSubject; textFormat: Text.PlainText
              color: root.foreground; font.family: root.fontFamily
              font.pixelSize: Style.font.caption; elide: Text.ElideRight
              width: Math.min(implicitWidth, Style.space(160))
            }
            Text {
              text: pc._firstSender; textFormat: Text.PlainText
              color: root.dim; font.family: root.fontFamily
              font.pixelSize: Style.font.caption; elide: Text.ElideRight
              width: Math.min(implicitWidth, Style.space(160))
            }
          }
          Rectangle {
            visible: pc.count > 1; anchors.verticalCenter: parent.verticalCenter
            width: pcCountText.implicitWidth + Style.space(8)
            height: Style.space(18); radius: Style.space(9)
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
            Text {
              id: pcCountText; anchors.centerIn: parent
              text: String(pc.count); color: root.dim
              font.family: root.fontFamily; font.pixelSize: Style.font.caption
            }
          }
        }
        HoverHandler { id: pcHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: pc.activated() }
      }

      component PilePreviewRow: Rectangle {
        id: ppr
        property string subject; property string senderName
        property string senderEmail; property real avatarHue: 0
        signal activated()
        width: parent ? parent.width : 0
        implicitHeight: Style.space(48); radius: Style.cornerRadius
        color: pprHover.hovered
          ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
          : "transparent"
        Row {
          anchors.left: parent.left; anchors.leftMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(8)
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(30); height: Style.space(30); radius: Style.space(15)
            color: Qt.hsla(ppr.avatarHue, 0.50, 0.42, 1.0)
            Text {
              anchors.centerIn: parent
              text: ppr.senderName.length > 0
                ? ppr.senderName.charAt(0).toUpperCase() : "?"
              color: Qt.rgba(1, 1, 1, 1); font.family: root.fontFamily
              font.pixelSize: Style.font.caption; font.bold: true
            }
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(1)
            Text {
              text: ppr.subject; textFormat: Text.PlainText; color: root.foreground
              font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              width: Math.min(implicitWidth, Style.space(240))
            }
            Text {
              text: ppr.senderName; textFormat: Text.PlainText; color: root.dim
              font.family: root.fontFamily; font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: Math.min(implicitWidth, Style.space(240))
            }
          }
        }
        HoverHandler { id: pprHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ppr.activated() }
      }

      // ── Bubble Up menu (list view) ─────────────────────────────────────

      Popup {
        id: bubbleMenu
        x: Math.round((parent.width - width) / 2)
        y: actionTray.y - implicitHeight - Style.space(6)
        width: Style.space(240)
        implicitHeight: bubbleCol.implicitHeight + Style.space(8)
        padding: Style.space(4); modal: false; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { radius: Style.cornerRadius; color: Color.popups.background; border.width: 1; border.color: Color.popups.border }
        function scheduleBubble(ms) { var id = root.cursorId; if (!root.service || id === "") return; root.service.scheduleWorkflowBubble(id, new Date(Date.now() + ms)); bubbleMenu.close() }
        function bubbleNow() { var id = root.cursorId; if (!root.service || id === "") return; root.service.scheduleWorkflowBubble(id, new Date()); bubbleMenu.close() }
        function nextWeekday(dayOfWeek, hour) { var d = new Date(); d.setHours(hour, 0, 0, 0); var diff = (dayOfWeek - d.getDay() + 7) % 7; if (diff === 0) diff = 7; d.setDate(d.getDate() + diff); return d }
        function timeLabel(ms) { var d = new Date(Date.now() + ms); var days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]; return days[d.getDay()] + ", " + d.getHours() + (d.getMinutes() === 0 ? "" : ":" + ("0" + d.getMinutes()).slice(-2)) + (d.getHours() < 12 ? "am" : "pm") }
        function dateLabelFor(d) { var days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]; return days[d.getDay()] + ", " + d.getHours() + (d.getMinutes() === 0 ? "" : ":" + ("0" + d.getMinutes()).slice(-2)) + (d.getHours() < 12 ? "am" : "pm") }
        contentItem: Column {
          id: bubbleCol; spacing: Style.space(2)
          Text { leftPadding: Style.space(9); topPadding: Style.space(4); bottomPadding: Style.space(4); text: "BUBBLE THIS UP\u2026"; textFormat: Text.PlainText; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
          BubbleRow { label: "Now"; hint: ""; onActivated: bubbleMenu.bubbleNow() }
          BubbleRow { label: "Later today"; hint: bubbleMenu.timeLabel(4 * 3600000); onActivated: bubbleMenu.scheduleBubble(4 * 3600000) }
          BubbleRow { label: "Tomorrow"; hint: bubbleMenu.timeLabel(24 * 3600000); onActivated: bubbleMenu.scheduleBubble(24 * 3600000) }
          BubbleRow { property var sat: bubbleMenu.nextWeekday(6, 8); label: "This weekend"; hint: bubbleMenu.dateLabelFor(sat); onActivated: { var id = root.cursorId; if (!root.service || id === "") return; root.service.scheduleWorkflowBubble(id, sat); bubbleMenu.close() } }
          BubbleRow { property var mon: bubbleMenu.nextWeekday(1, 8); label: "Next week"; hint: bubbleMenu.dateLabelFor(mon); onActivated: { var id = root.cursorId; if (!root.service || id === "") return; root.service.scheduleWorkflowBubble(id, mon); bubbleMenu.close() } }
          BubbleRow { label: "Surprise me"; hint: "\u{1F3B2}"; onActivated: { var ms = 3600000 + Math.floor(Math.random() * 6 * 86400000); bubbleMenu.scheduleBubble(ms) } }
          Item { width: parent.width; implicitHeight: Style.space(7); PanelSeparator { anchors.verticalCenter: parent.verticalCenter; width: parent.width; foreground: root.foreground } }
          BubbleRow { label: "Pick a date\u2026"; hint: ""; onActivated: { bubbleMenu.close(); appBubbleDatePicker.open() } }
        }
      }

      Popup {
        id: appBubbleDatePicker
        x: Math.round((parent.width - width) / 2)
        y: actionTray.y - implicitHeight - Style.space(6)
        width: Style.space(260)
        implicitHeight: appDateCol.implicitHeight + Style.space(8)
        padding: Style.space(4); modal: false; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { radius: Style.cornerRadius; color: Color.popups.background; border.width: 1; border.color: Color.popups.border }
        contentItem: Column {
          id: appDateCol; spacing: Style.space(6)
          Text { leftPadding: Style.space(9); topPadding: Style.space(4); text: "PICK A DATE & TIME"; textFormat: Text.PlainText; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
          Row {
            anchors.horizontalCenter: parent.horizontalCenter; spacing: Style.space(6)
            TextField {
              id: appDateField
              width: Style.space(120)
              placeholderText: "YYYY-MM-DD"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.foreground
              placeholderTextColor: root.dim
              background: Rectangle {
                radius: Style.cornerRadius
                color: Qt.rgba(root.foreground.r, root.foreground.g,
                  root.foreground.b, 0.06)
                border.width: 1
                border.color: Qt.rgba(root.foreground.r, root.foreground.g,
                  root.foreground.b, 0.15)
              }
              Component.onCompleted: {
                var d = new Date(Date.now() + 86400000)
                text = d.getFullYear() + "-"
                  + String(d.getMonth() + 1).padStart(2, "0") + "-"
                  + String(d.getDate()).padStart(2, "0")
              }
            }
            TextField {
              id: appTimeField
              width: Style.space(80)
              placeholderText: "HH:MM"
              text: "09:00"
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              color: root.foreground
              placeholderTextColor: root.dim
              background: Rectangle {
                radius: Style.cornerRadius
                color: Qt.rgba(root.foreground.r, root.foreground.g,
                  root.foreground.b, 0.06)
                border.width: 1
                border.color: Qt.rgba(root.foreground.r, root.foreground.g,
                  root.foreground.b, 0.15)
              }
            }
          }
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter; width: appSchedLabel.implicitWidth + Style.space(24); height: Style.space(30); radius: Style.cornerRadius
            color: appSchedHover.hovered ? root.accent : Qt.darker(root.accent, 1.15)
            Text { id: appSchedLabel; anchors.centerIn: parent; text: "Schedule"; textFormat: Text.PlainText; color: Qt.rgba(1,1,1,1); font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
            HoverHandler { id: appSchedHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: { var parts = appDateField.text.split("-"); var time = appTimeField.text.split(":"); if (parts.length < 3 || time.length < 2) return; var d = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]), parseInt(time[0]), parseInt(time[1]), 0, 0); if (isNaN(d.getTime())) return; var id = root.cursorId; if (!root.service || id === "") return; root.service.scheduleWorkflowBubble(id, d); appBubbleDatePicker.close() } }
          }
          Item { width: 1; implicitHeight: Style.space(2) }
        }
      }

      component BubbleRow: Rectangle {
        id: bRow; required property string label; required property string hint; signal activated()
        width: bubbleMenu.width - bubbleMenu.leftPadding - bubbleMenu.rightPadding
        implicitHeight: Style.spacing.popupRowHeight; radius: Style.cornerRadius
        color: bHover.hovered ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"
        Text { anchors.left: parent.left; anchors.leftMargin: Style.space(9); anchors.verticalCenter: parent.verticalCenter; text: bRow.label; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
        Text { anchors.right: parent.right; anchors.rightMargin: Style.space(9); anchors.verticalCenter: parent.verticalCenter; visible: bRow.hint !== ""; text: bRow.hint; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
        HoverHandler { id: bHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: bRow.activated() }
      }

      // ── Bulk actions bar (multi-select) ──────────────────────────────
      Rectangle {
        id: bulkBar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: statusBar.top; anchors.bottomMargin: Style.space(10)
        visible: root.multiSelectActive && root.currentView === "list" && !root.showPage && !root.composing
        z: 15
        width: bulkBarContent.implicitWidth + Style.space(16)
        height: bulkBarContent.implicitHeight + Style.space(12)
        radius: Style.space(12)
        color: Color.popups.background; border.width: 1; border.color: Color.popups.border
        Column {
          id: bulkBarContent; anchors.centerIn: parent; spacing: Style.space(4)
          Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.selectedCount + " selected"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          Row { spacing: Style.space(4)
            BulkButton { label: "Reply Later"; shortcut: "L"; onActivated: { root.bulkAct(function(id) { root.service.setWorkflowPile(id, "reply_later") }) } }
            BulkButton { label: "Set Aside"; shortcut: "A"; onActivated: { root.bulkAct(function(id) { root.service.setWorkflowPile(id, "set_aside") }) } }
            BulkButton { label: "Mark Seen"; shortcut: "E"; onActivated: { root.bulkAct(function(id) { root.service.markWorkflowSeen(id, true) }) } }
          }
          Row { spacing: Style.space(4)
            BulkButton { label: "To Feed"; shortcut: "D"; onActivated: { root.bulkAct(function(id) { root.service.moveThread(id, "feed") }) } }
            BulkButton { label: "Paper Trail"; shortcut: "P"; onActivated: { root.bulkAct(function(id) { root.service.moveThread(id, "paper_trail") }) } }
            BulkButton { label: "Bubble Up"; shortcut: "Z"; onActivated: bulkBubbleMenu.open() }
            BulkButton { label: "Read Together"; shortcut: "O"; onActivated: root.startReadTogether() }
            BulkButton { label: "Reply Together"; onActivated: root.startReplyTogether() }
          }
          Item { width: parent.width; implicitHeight: Style.space(5); PanelSeparator { anchors.verticalCenter: parent.verticalCenter; width: parent.width; foreground: root.foreground } }
          Row { spacing: Style.space(4)
            BulkButton { label: "Star"; shortcut: "S"; onActivated: { root.bulkAct(function(id) { root.service.toggleStar(id) }) } }
            BulkButton { label: "Archive"; onActivated: { root.bulkAct(function(id) { root.service.act(id, "archive") }) } }
            BulkButton { label: "Label\u2026"; shortcut: "B"; onActivated: { var ids = Object.keys(root.selectedIds); labelPicker.openForBulk(ids) } }
            BulkButton { label: "Collection\u2026"; onActivated: { var ids = Object.keys(root.selectedIds); collectionPicker.openForBulk(ids) } }
            BulkButton { label: "Ignore"; onActivated: { root.bulkAct(function(id) { root.service.ignoreThread(id) }) } }
            BulkButton { label: "Spam"; tone: root.urgent; onActivated: { root.bulkAct(function(id) { root.service.reportSpam(id) }) } }
            BulkButton { label: "Trash"; shortcut: "T"; tone: root.urgent; onActivated: { root.bulkAct(function(id) { root.service.act(id, "trash") }) } }
          }
        }
        Rectangle {
          anchors.right: parent.right; anchors.top: parent.top
          anchors.rightMargin: Style.space(6); anchors.topMargin: Style.space(6)
          width: Style.space(24); height: Style.space(24); radius: width / 2
          color: bulkCloseHover.hovered
            ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
            : "transparent"
          Text {
            anchors.centerIn: parent; text: "\u2715"
            color: root.dim; font.pixelSize: Style.font.body
          }
          HoverHandler { id: bulkCloseHover; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: root.clearSelection() }
        }
      }

      Popup {
        id: bulkBubbleMenu
        x: Math.round((parent.width - width) / 2); y: bulkBar.y - implicitHeight - Style.space(4)
        width: Style.space(240); implicitHeight: bbCol.implicitHeight + Style.space(8); padding: Style.space(4); modal: false; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { radius: Style.cornerRadius; color: Color.popups.background; border.width: 1; border.color: Color.popups.border }
        function scheduleAll(ms) { var at = new Date(Date.now() + ms); root.bulkAct(function(id) { root.service.scheduleWorkflowBubble(id, at) }); bulkBubbleMenu.close() }
        contentItem: Column {
          id: bbCol; spacing: Style.space(2)
          Text { leftPadding: Style.space(9); topPadding: Style.space(4); bottomPadding: Style.space(4); text: "BUBBLE ALL UP\u2026"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
          BubbleRow { label: "Now"; hint: ""; onActivated: bulkBubbleMenu.scheduleAll(0) }
          BubbleRow { label: "Later today"; hint: bubbleMenu.timeLabel(4 * 3600000); onActivated: bulkBubbleMenu.scheduleAll(4 * 3600000) }
          BubbleRow { label: "Tomorrow"; hint: bubbleMenu.timeLabel(24 * 3600000); onActivated: bulkBubbleMenu.scheduleAll(24 * 3600000) }
          BubbleRow { property var sat: bubbleMenu.nextWeekday(6, 8); label: "This weekend"; hint: bubbleMenu.dateLabelFor(sat); onActivated: { var at = sat; root.bulkAct(function(id) { root.service.scheduleWorkflowBubble(id, at) }); bulkBubbleMenu.close() } }
          BubbleRow { property var mon: bubbleMenu.nextWeekday(1, 8); label: "Next week"; hint: bubbleMenu.dateLabelFor(mon); onActivated: { var at = mon; root.bulkAct(function(id) { root.service.scheduleWorkflowBubble(id, at) }); bulkBubbleMenu.close() } }
        }
      }

      // ── Screener: Accept All bar ───────────────────────────────────────
      Rectangle {
        id: screenerBar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: statusBar.top; anchors.bottomMargin: Style.space(10)
        visible: !!root.service && root.service.workflowEnabled
          && root.service.workflowKey === "screener"
          && root.service.messages.length > 0
          && root.currentView === "list"
          && !root.showPage && !root.composing
          && !root.multiSelectActive
        z: 15
        width: screenerBarRow.implicitWidth + Style.space(24)
        height: Style.space(40)
        radius: Style.space(12)
        color: Color.popups.background; border.width: 1; border.color: Color.popups.border

        Row {
          id: screenerBarRow
          anchors.centerIn: parent
          spacing: Style.space(10)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.service
              ? root.service.messages.length + (root.service.messages.length === 1
                ? " sender" : " senders") + " to screen"
              : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: acceptAllLabel.implicitWidth + Style.space(18)
            height: Style.space(28)
            radius: Style.cornerRadius
            color: acceptAllHover.hovered ? root.accent
              : Qt.darker(root.accent, 1.15)

            Text {
              id: acceptAllLabel
              anchors.centerIn: parent
              text: "Accept All"
              color: Qt.rgba(1, 1, 1, 1)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            HoverHandler { id: acceptAllHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: screenerConfirm.open() }
          }
        }
      }

      Popup {
        id: screenerConfirm
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Style.space(340)
        implicitHeight: screenerConfirmCol.implicitHeight + Style.space(16)
        padding: Style.space(12); modal: true; focus: true; z: 60
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { radius: Style.cornerRadius; color: Color.popups.background; border.width: 1; border.color: Color.popups.border }

        contentItem: Column {
          id: screenerConfirmCol
          spacing: Style.space(12)

          Text {
            width: parent.width
            text: "Accept all " + (root.service ? root.service.messages.length : 0)
              + " senders?"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: "Every first-time sender currently in the Screener will be moved to Imbox."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Row {
            anchors.right: parent.right
            spacing: Style.space(8)

            Rectangle {
              width: cancelConfirmLabel.implicitWidth + Style.space(20)
              height: Style.space(32)
              radius: Style.cornerRadius
              color: cancelConfirmHover.hovered
                ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
                : "transparent"
              border.width: 1
              border.color: Qt.rgba(root.foreground.r, root.foreground.g,
                root.foreground.b, 0.25)

              Text {
                id: cancelConfirmLabel
                anchors.centerIn: parent
                text: "Cancel"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              HoverHandler { id: cancelConfirmHover; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: screenerConfirm.close() }
            }

            Rectangle {
              width: confirmAcceptLabel.implicitWidth + Style.space(20)
              height: Style.space(32)
              radius: Style.cornerRadius
              color: confirmAcceptHover.hovered ? root.accent
                : Qt.darker(root.accent, 1.15)

              Text {
                id: confirmAcceptLabel
                anchors.centerIn: parent
                text: "Accept All"
                color: Qt.rgba(1, 1, 1, 1)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              HoverHandler { id: confirmAcceptHover; cursorShape: Qt.PointingHandCursor }
              TapHandler {
                onTapped: {
                  root.service.acceptAllScreener()
                  screenerConfirm.close()
                }
              }
            }
          }
        }
      }

      component BulkButton: Rectangle {
        id: bb; property string label; property string shortcut: ""; property color tone: root.foreground; signal activated()
        width: Math.max(bbLabel.implicitWidth + Style.space(16), Style.space(80)); height: Style.space(38); radius: Style.cornerRadius
        color: bbHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : Style.normalFillFor(root.foreground, root.accent)
        Column { anchors.centerIn: parent; spacing: Style.space(1)
          Text { id: bbLabel; anchors.horizontalCenter: parent.horizontalCenter; text: bb.label; color: bb.tone; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          Text { visible: bb.shortcut !== ""; anchors.horizontalCenter: parent.horizontalCenter; text: bb.shortcut; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
        }
        HoverHandler { id: bbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: bb.activated() }
      }

      // ── Quick actions popup (avatar click / . key) ─────────────────────

      Item {
        id: quickActions; anchors.fill: parent; z: 55; visible: qaMenu.opened
        property string messageId: ""
        function openAt(id, sceneX, sceneY) {
          quickActions.messageId = String(id || ""); if (!root.service) return
          var local = quickActions.mapFromGlobal(sceneX, sceneY)
          qaMenu.x = Math.max(0, Math.min(local.x - qaMenu.width / 2, quickActions.width - qaMenu.width))
          qaMenu.y = local.y + qaMenu.implicitHeight > quickActions.height ? Math.max(0, local.y - qaMenu.implicitHeight) : local.y
          qaMenu.open()
        }
        function close() { qaMenu.close() }
        function run(action) { var id = quickActions.messageId; qaMenu.close(); if (!root.service || id === "") return; root.cursorId = id; root.actOnCursor(action) }

        Popup {
          id: qaMenu; width: Style.space(280); implicitHeight: qaCol.implicitHeight + Style.space(8); padding: Style.space(4); modal: false; focus: true
          closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
          background: Rectangle { radius: Style.cornerRadius; color: Color.popups.background; border.width: 1; border.color: Color.popups.border }
          contentItem: Column {
            id: qaCol; spacing: Style.space(2)
            Row { width: parent.width; spacing: Style.space(4)
              QaButton { width: (parent.width - Style.space(8)) / 3; label: "Reply Later"; shortcut: "L"; onActivated: { qaMenu.close(); if (root.service) root.service.setWorkflowPile(quickActions.messageId, "reply_later") } }
              QaButton { width: (parent.width - Style.space(8)) / 3; label: "Set Aside"; shortcut: "A"; onActivated: { qaMenu.close(); if (root.service) root.service.setWorkflowPile(quickActions.messageId, "set_aside") } }
              QaButton { width: (parent.width - Style.space(8)) / 3; label: "Mark Seen"; shortcut: "E"; onActivated: { qaMenu.close(); if (root.service) root.service.markWorkflowSeen(quickActions.messageId, true) } }
            }
            Row { width: parent.width; spacing: Style.space(4)
              QaButton { width: (parent.width - Style.space(8)) / 3; label: "To Feed"; shortcut: "D"; onActivated: { qaMenu.close(); if (root.service) root.service.moveThread(quickActions.messageId, "feed") } }
              QaButton { width: (parent.width - Style.space(8)) / 3; label: "Paper Trail"; shortcut: "P"; onActivated: { qaMenu.close(); if (root.service) root.service.moveThread(quickActions.messageId, "paper_trail") } }
              QaButton { width: (parent.width - Style.space(8)) / 3; label: "Forward"; shortcut: "F"; onActivated: { qaMenu.close(); root.openMessage(quickActions.messageId); root.startCompose("forward") } }
            }
            Item { width: parent.width; implicitHeight: Style.space(7); PanelSeparator { anchors.verticalCenter: parent.verticalCenter; width: parent.width; foreground: root.foreground } }
            QaRow { visible: !!root.service && root.service.workflowEnabled; text: "Route sender to Imbox"; onActivated: { qaMenu.close(); if (root.service) root.service.routeSender(quickActions.messageId, "inbox") } }
            QaRow { visible: !!root.service && root.service.workflowEnabled; text: "Route sender to Feed"; onActivated: { qaMenu.close(); if (root.service) root.service.routeSender(quickActions.messageId, "feed") } }
            QaRow { visible: !!root.service && root.service.workflowEnabled; text: "Route sender to Paper Trail"; onActivated: { qaMenu.close(); if (root.service) root.service.routeSender(quickActions.messageId, "paper_trail") } }
            Item { visible: !!root.service && root.service.workflowEnabled; width: parent.width; implicitHeight: Style.space(7); PanelSeparator { anchors.verticalCenter: parent.verticalCenter; width: parent.width; foreground: root.foreground } }
            QaRow { text: "Reply"; shortcut: "R"; onActivated: { qaMenu.close(); root.openMessage(quickActions.messageId); Qt.callLater(function() { reader.focusReply() }) } }
            QaRow { text: "Bubble Up"; shortcut: "Z"; onActivated: { qaMenu.close(); root.cursorId = quickActions.messageId; bubbleMenu.open() } }
            QaRow { text: "Star"; shortcut: "S"; onActivated: { qaMenu.close(); if (root.service) root.service.toggleStar(quickActions.messageId) } }
            QaRow { text: "Archive"; onActivated: quickActions.run("archive") }
            QaRow { text: "Label\u2026"; shortcut: "B"; onActivated: { qaMenu.close(); labelPicker.openFor(quickActions.messageId) } }
            QaRow { text: "Collection\u2026"; onActivated: { qaMenu.close(); collectionPicker.openFor(quickActions.messageId) } }
            QaRow { visible: !!root.service && root.service.workflowEnabled; text: "Ignore thread"; onActivated: { qaMenu.close(); if (root.service) root.service.ignoreThread(quickActions.messageId) } }
            QaRow { text: "Report spam"; tone: root.urgent; onActivated: { qaMenu.close(); if (root.service) root.service.reportSpam(quickActions.messageId) } }
            QaRow { text: "Trash"; shortcut: "T"; tone: root.urgent; onActivated: quickActions.run("trash") }
            QaRow { text: "Open in browser"; tone: root.dim; onActivated: { qaMenu.close(); if (root.service) root.service.openInBrowser(quickActions.messageId) } }
          }
        }

        component QaButton: Rectangle {
          id: qab; property string label; property string shortcut: ""; signal activated()
          height: Style.space(36); radius: Style.cornerRadius
          color: qabHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : Style.normalFillFor(root.foreground, root.accent)
          Column { anchors.centerIn: parent; spacing: Style.space(1)
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: qab.label; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            Text { visible: qab.shortcut !== ""; anchors.horizontalCenter: parent.horizontalCenter; text: qab.shortcut; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          }
          HoverHandler { id: qabHover; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: qab.activated() }
        }

        component QaRow: Rectangle {
          id: qar; property string text; property string shortcut: ""; property color tone: root.foreground; signal activated()
          width: parent ? parent.width : 0; implicitHeight: Style.spacing.popupRowHeight; radius: Style.cornerRadius
          color: qarHover.hovered ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"
          Text { anchors.left: parent.left; anchors.leftMargin: Style.space(9); anchors.verticalCenter: parent.verticalCenter; text: qar.text; color: qar.tone; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
          Text { anchors.right: parent.right; anchors.rightMargin: Style.space(9); anchors.verticalCenter: parent.verticalCenter; visible: qar.shortcut !== ""; text: qar.shortcut; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          HoverHandler { id: qarHover; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: qar.activated() }
        }
      }

      // ── Label picker popup ─────────────────────────────────────────────

      Popup {
        id: labelPicker; property string targetId: ""; property var targetIds: []; property bool bulk: false; property string filter: ""
        function openFor(id) { targetId = String(id || ""); targetIds = []; bulk = false; filter = ""; labelFilterField.text = ""; open() }
        function openForBulk(ids) { targetId = ""; targetIds = ids; bulk = true; filter = ""; labelFilterField.text = ""; open() }
        readonly property var filteredLabels: { if (!root.service) return []; var all = root.service.userLabels; var f = filter.toLowerCase(); if (f === "") return all; var result = []; for (var i = 0; i < all.length; i++) { if (all[i].name.toLowerCase().indexOf(f) >= 0) result.push(all[i]) }; return result }
        x: Math.round((parent.width - width) / 2); y: Math.round((parent.height - height) / 2)
        width: Style.space(280); implicitHeight: Math.min(labelPickerCol.implicitHeight + Style.space(8), parent.height * 0.6)
        padding: Style.space(4); modal: true; focus: true; closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside; z: 50
        background: Rectangle { radius: Style.cornerRadius; color: Color.popups.background; border.width: 1; border.color: Color.popups.border }
        contentItem: Column {
          id: labelPickerCol; spacing: Style.space(4)
          Text { leftPadding: Style.space(6); topPadding: Style.space(4); text: "APPLY LABEL"; textFormat: Text.PlainText; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
          TextField { id: labelFilterField; width: parent.width; placeholderText: "Filter labels\u2026"; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; color: root.foreground; placeholderTextColor: root.dim; onTextChanged: labelPicker.filter = text; background: Rectangle { radius: Style.cornerRadius; color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06); border.width: 1; border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15) } }
          Flickable {
            width: parent.width; height: Math.min(labelListCol.implicitHeight, labelPicker.height - Style.space(80)); contentHeight: labelListCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds; ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Column { id: labelListCol; width: parent.width; spacing: Style.space(2)
              Repeater { model: labelPicker.filteredLabels
                Rectangle { required property var modelData; required property int index; width: labelListCol.width; implicitHeight: Style.spacing.popupRowHeight; radius: Style.cornerRadius; color: lblHover.hovered ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08) : "transparent"
                  Text { anchors.left: parent.left; anchors.leftMargin: Style.space(9); anchors.verticalCenter: parent.verticalCenter; text: modelData.name; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
                  HoverHandler { id: lblHover; cursorShape: Qt.PointingHandCursor }
                  TapHandler { onTapped: { var lid = modelData.id; if (labelPicker.bulk) { var ids = labelPicker.targetIds; for (var i = 0; i < ids.length; i++) root.service.applyLabel(ids[i], lid) } else { root.service.applyLabel(labelPicker.targetId, lid) }; labelPicker.close() } }
                }
              }
              Text { visible: labelPicker.filteredLabels.length === 0; leftPadding: Style.space(9); topPadding: Style.space(8); bottomPadding: Style.space(8); text: "No labels found"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
            }
          }
        }
      }

      // ── Collection picker popup ───────────────────────────────────────

      Popup {
        id: collectionPicker
        property string targetId: ""
        property var targetIds: []
        property bool bulk: false
        property string filter: ""
        property bool creating: false

        function openFor(id) {
          targetId = String(id || ""); targetIds = []; bulk = false
          filter = ""; collFilterField.text = ""; creating = false; open()
        }
        function openForBulk(ids) {
          targetId = ""; targetIds = ids; bulk = true
          filter = ""; collFilterField.text = ""; creating = false; open()
        }

        readonly property var filteredCollections: {
          if (!root.service) return []
          var all = root.service.collectionLabels
          var f = filter.toLowerCase()
          if (f === "") return all
          var result = []
          for (var i = 0; i < all.length; i++) {
            if (all[i].name.toLowerCase().indexOf(f) >= 0) result.push(all[i])
          }
          return result
        }

        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Style.space(300)
        implicitHeight: Math.min(collPickerCol.implicitHeight + Style.space(8),
          parent.height * 0.6)
        padding: Style.space(4); modal: true; focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside; z: 50
        background: Rectangle {
          radius: Style.cornerRadius; color: Color.popups.background
          border.width: 1; border.color: Color.popups.border
        }

        contentItem: Column {
          id: collPickerCol; spacing: Style.space(4)

          Text {
            leftPadding: Style.space(6); topPadding: Style.space(4)
            text: collectionPicker.creating ? "NEW COLLECTION" : "ADD TO COLLECTION"
            color: root.dim; font.family: root.fontFamily
            font.pixelSize: Style.font.caption; font.bold: true
          }

          TextField {
            id: collFilterField
            width: parent.width
            placeholderText: collectionPicker.creating
              ? "Collection name\u2026" : "Filter or create\u2026"
            font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
            color: root.foreground; placeholderTextColor: root.dim
            onTextChanged: collectionPicker.filter = text
            Keys.onReturnPressed: {
              if (collectionPicker.creating && text.trim() !== "") {
                root.service.createCollection(text.trim(), function(label) {
                  if (!label) return
                  function applyToTargets() {
                    if (collectionPicker.bulk) {
                      for (var i = 0; i < collectionPicker.targetIds.length; i++)
                        root.service.addToCollection(
                          collectionPicker.targetIds[i], label.id)
                    } else {
                      root.service.addToCollection(
                        collectionPicker.targetId, label.id)
                    }
                    collectionPicker.close()
                  }
                  applyToTargets()
                })
              }
            }
            background: Rectangle {
              radius: Style.cornerRadius
              color: Qt.rgba(root.foreground.r, root.foreground.g,
                root.foreground.b, 0.06)
              border.width: 1
              border.color: Qt.rgba(root.foreground.r, root.foreground.g,
                root.foreground.b, 0.15)
            }
          }

          Flickable {
            visible: !collectionPicker.creating
            width: parent.width
            height: Math.min(collListCol.implicitHeight,
              collectionPicker.height - Style.space(100))
            contentHeight: collListCol.implicitHeight; clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            Column {
              id: collListCol; width: parent.width; spacing: Style.space(2)
              Repeater {
                model: collectionPicker.filteredCollections
                Rectangle {
                  required property var modelData
                  required property int index
                  width: collListCol.width
                  implicitHeight: Style.spacing.popupRowHeight
                  radius: Style.cornerRadius
                  color: collHover.hovered
                    ? Qt.rgba(root.foreground.r, root.foreground.g,
                      root.foreground.b, 0.08) : "transparent"
                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(9)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name; color: root.foreground
                    font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
                  }
                  HoverHandler { id: collHover; cursorShape: Qt.PointingHandCursor }
                  TapHandler {
                    onTapped: {
                      var lid = modelData.id
                      if (collectionPicker.bulk) {
                        var ids = collectionPicker.targetIds
                        for (var i = 0; i < ids.length; i++)
                          root.service.addToCollection(ids[i], lid)
                      } else {
                        root.service.addToCollection(
                          collectionPicker.targetId, lid)
                      }
                      collectionPicker.close()
                    }
                  }
                }
              }
              Text {
                visible: collectionPicker.filteredCollections.length === 0
                  && !collectionPicker.creating
                leftPadding: Style.space(9); topPadding: Style.space(8)
                bottomPadding: Style.space(8)
                text: "No collections yet"
                color: root.dim; font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }

          Rectangle {
            width: parent.width; implicitHeight: Style.space(32)
            color: "transparent"; radius: Style.cornerRadius
            Text {
              anchors.centerIn: parent
              text: collectionPicker.creating ? "Cancel" : "+ New collection"
              color: root.accent; font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler {
              onTapped: {
                collectionPicker.creating = !collectionPicker.creating
                collFilterField.text = ""
                collFilterField.forceActiveFocus()
              }
            }
          }
        }
      }

      // --------------------------------------------------------- status bar

      Item {
        id: statusBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(28)

        PanelSeparator {
          anchors.top: parent.top
          width: parent.width
          foreground: root.foreground
        }

        // The rail's own switch, at the far left of the status line. On the rail
        // it cost a whole row above the mailboxes; in the header it was a
        // button about the sidebar sitting among buttons about the mailbox.
        // The status line is where a view toggle belongs.
        IconButton {
          id: railToggle
          anchors.left: parent.left
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          visible: !root.compact && !root.showPage && !root.composing
          iconName: "sidebar"
          tooltipText: root.sidebarCollapsed ? "Show the sidebar" : "Hide the sidebar"
          // No fill for the open state. The sidebar standing there is the state,
          // said far better than a lit square on the status line could say it,
          // and this control has no business drawing attention to itself.
          foreground: root.dim
          hoverColor: root.foreground
          iconSize: Style.font.iconSmall
          size: Style.space(20)
          fontFamily: root.fontFamily
          onClicked: root.toggleSidebar()
        }

        Text {
          id: accountLine
          anchors.left: railToggle.visible ? railToggle.right : parent.left
          anchors.leftMargin: railToggle.visible ? Style.space(8) : Style.space(14)
          // An invisible sibling still holds its place, so the hints must only
          // take room from this line while they are actually on screen.
          anchors.right: statusBar.hasNotice
            ? notice.left
            : (keyHints.visible ? keyHints.left : parent.right)
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          // The account already has a home in the sidebar's user bar, so this
          // says something the window does not say anywhere else: how current
          // the list is. When the sidebar is hidden it takes the account back,
          // because then nothing else is carrying it.
          text: {
            if (!root.service) return "Not connected"
            if (!root.ready) return "Not connected"
            if (root.compact)
              return root.service.accountEmail + " · " + root.service.inboxUnread + " unread"
            return Model.statusSummary(root.service.syncedLabel,
              root.service.resultSummary, root.service.listLoading)
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight

        }

        // The right of the status line carries one of two things: what the
        // window most needs to say, or — when it has nothing to report — what
        // the keyboard can do from where you are standing.
        readonly property bool hasNotice: root.notice !== ""
          || (!!root.service
            && (root.service.actionStatus !== "" || root.service.lastError !== ""))

        Text {
          id: notice
          anchors.right: parent.right
          anchors.rightMargin: Style.space(14)
          anchors.verticalCenter: parent.verticalCenter
          visible: statusBar.hasNotice
          width: Math.min(implicitWidth, parent.width / 2)
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
          text: {
            if (root.notice !== "") return root.notice
            if (!root.service) return ""
            if (root.service.actionStatus !== "") return root.service.actionStatus
            return root.service.lastError
          }
          color: root.service && root.service.lastError !== "" && root.service.actionStatus === ""
            ? root.urgent
            : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        KeyHints {
          id: keyHints
          anchors.right: parent.right
          anchors.rightMargin: Style.space(14)
          anchors.verticalCenter: parent.verticalCenter
          visible: !statusBar.hasNotice && !root.compact
          textColor: root.foreground
          dimColor: root.dimmer
          panelFontFamily: root.fontFamily
          hints: {
            if (root.showPage) return [({ key: "Esc", label: "back" })]
            if (root.composing) return [
              ({ key: "Ctrl+Enter", label: "send" }),
              ({ key: "Esc", label: "close" })
            ]
            if (root.currentView === "reader") return [
              ({ key: "Esc", label: "back" }),
              ({ key: "r", label: "reply" }),
              ({ key: "e", label: "archive" }),
              ({ key: "d", label: "trash" })
            ]
            return [
              ({ key: "j / k", label: "move" }),
              ({ key: "o", label: "open" }),
              ({ key: "e", label: "archive" }),
              ({ key: "c", label: "compose" })
            ]
          }
        }
      }

      // The account menu. It has no trigger of its own: the sidebar's user bar
      // opens it, and so does the status bar when the sidebar is hidden.
      AppMenu {
        id: appMenu
        anchors.fill: parent
        textColor: root.foreground
        accentColor: root.accent
        dimColor: root.dim
        panelFontFamily: root.fontFamily
        signedIn: root.ready
        accountCount: root.service ? root.service.accountCount : 1
        workflowCounts: root.service ? root.service.workflowCounts : ({})
        onWorkflowRequested: function(key) { root.goWorkflow(key) }
        onMarkAllReadRequested: if (root.service) root.service.markAllRead()
        onOpenWebRequested: if (root.service) root.service.openWebInbox()
        onMoreNavigationRequested: mailboxMore.openCentered()
        onShortcutsRequested: root.shortcutHelpVisible = true
        onSetupRequested: root.settingsVisible = true
        onSwitchAccountRequested: accountSwitcher.openCentered()
        onProjectRequested: if (root.service) root.service.openProjectPage()
        onAuthorRequested: if (root.service) root.service.openAuthorPage()
      }

      MailboxMore {
        id: mailboxMore
        anchors.fill: parent
        service: root.service
        textColor: root.foreground
        accentColor: root.accent
        dimColor: root.dim
        panelFontFamily: root.fontFamily
        onMailboxSelected: function(key) { root.goMailbox(key) }
        onWorkflowSelected: function(key) { root.goWorkflow(key) }
        onLabelSelected: function(labelId, name) {
          root.service.search("label:" + name)
          root.backToList()
        }
        onDismissed: Qt.callLater(function() { focusScope.forceActiveFocus() })
      }

      Timer {
        id: noticeTimer
        interval: 6000
        onTriggered: root.notice = ""
      }

      AccountSwitcher {
        id: accountSwitcher
        anchors.fill: parent
        textColor: root.foreground
        accentColor: root.accent
        urgentColor: root.urgent
        dimColor: root.dim
        panelFontFamily: root.fontFamily
        accounts: root.service ? root.service.accountSummaries : []
        onAccountChosen: function(index) {
          if (root.service) root.service.switchToIndex(index)
          root.backToList()
        }
        onAddAccountRequested: if (root.service) root.service.addAccount()
        onRemoveAccountRequested: function(index) {
          if (root.service) root.service.removeAccountAt(index)
        }
      }

      MessageMenu {
        id: rowMenu
        service: root.service
        textColor: root.foreground
        urgentColor: root.urgent
        dimColor: root.dim
        panelFontFamily: root.fontFamily
        onComposeRequested: function(mode, id) {
          root.openMessage(id)
          root.startCompose(mode)
        }
        onActionRequested: function(action, id) {
          root.cursorId = id
          root.actOnCursor(action)
        }
      }

      ShortcutHelp {
        id: shortcutHelp
        anchors.fill: parent
        visible: root.shortcutHelpVisible
        textColor: root.foreground
        backgroundColor: root.background
        dimColor: root.dim
        panelFontFamily: root.fontFamily
        onDismissed: root.shortcutHelpVisible = false
      }

      // ---------------------------------------------------------- keyboard

      Keys.onEscapePressed: function(event) {
        if (root.shortcutHelpVisible) root.shortcutHelpVisible = false
        else if (screenerConfirm.opened) screenerConfirm.close()
        else if (collectionPicker.opened) collectionPicker.close()
        else if (labelPicker.opened) labelPicker.close()
        else if (qaMenu.opened) quickActions.close()
        else if (bulkBubbleMenu.opened) bulkBubbleMenu.close()
        else if (root.multiSelectActive) root.clearSelection()
        else if (rowMenu.opened) rowMenu.close()
        else if (mailboxMore.opened) mailboxMore.close()
        else if (appMenu.opened) appMenu.close()
        else if (accountSwitcher.opened) accountSwitcher.close()
        else if (root.composing) compose.finish()
        else if (reader.replying) reader.dismissReply()
        else if (root.currentView === "reader") root.backToList()
        else if (root.setupVisible) root.setupVisible = false
        else if (root.settingsVisible) root.settingsVisible = false
        else if (root.service && root.service.searchQuery !== "") root.service.search("")
        else root.requestClose()
        event.accepted = true
      }

      Shortcut { sequence: "Ctrl+K"; onActivated: searchBar.focusField() }
      Shortcut { sequence: "/"; enabled: !focusScope.typing; onActivated: searchBar.focusField() }
      Shortcut {
        sequence: "j"
        enabled: !focusScope.typing
        onActivated: root.shortcutHelpVisible
          ? shortcutHelp.scrollBy(Style.space(40))
          : (root.currentView === "reader" ? reader.scrollBy(Style.space(40))
            : (root.powerThroughActive ? powerThroughPane.scrollBy(Style.space(40))
              : (root.showingFeed ? feedView.scrollBy(Style.space(40)) : root.moveCursor(1))))
      }
      Shortcut {
        sequence: "k"
        enabled: !focusScope.typing
        onActivated: root.shortcutHelpVisible
          ? shortcutHelp.scrollBy(-Style.space(40))
          : (root.currentView === "reader" ? reader.scrollBy(-Style.space(40))
            : (root.powerThroughActive ? powerThroughPane.scrollBy(-Style.space(40))
              : (root.showingFeed ? feedView.scrollBy(-Style.space(40)) : root.moveCursor(-1))))
      }
      Shortcut {
        sequence: "Ctrl+D"
        enabled: !focusScope.typing
        onActivated: root.shortcutHelpVisible
          ? shortcutHelp.scrollBy(shortcutHelp.height / 2)
          : (root.currentView === "reader" ? reader.scrollBy(reader.height / 2)
            : (root.showingFeed ? feedView.scrollBy(feedView.height / 2) : root.moveCursor(5)))
      }
      Shortcut {
        sequence: "Ctrl+U"
        enabled: !focusScope.typing
        onActivated: root.shortcutHelpVisible
          ? shortcutHelp.scrollBy(-shortcutHelp.height / 2)
          : (root.currentView === "reader" ? reader.scrollBy(-reader.height / 2)
            : (root.showingFeed ? feedView.scrollBy(-feedView.height / 2) : root.moveCursor(-5)))
      }
      Shortcut {
        sequence: "g,g"
        enabled: !focusScope.typing
        onActivated: root.shortcutHelpVisible
          ? shortcutHelp.scrollToEnd(false)
          : (root.currentView === "reader" ? reader.scrollToEnd(false)
            : (root.showingFeed ? feedView.scrollToEnd(false) : root.jumpCursor(false)))
      }
      Shortcut {
        sequence: "Shift+G"
        enabled: !focusScope.typing
        onActivated: root.shortcutHelpVisible
          ? shortcutHelp.scrollToEnd(true)
          : (root.currentView === "reader" ? reader.scrollToEnd(true)
            : (root.showingFeed ? feedView.scrollToEnd(true) : root.jumpCursor(true)))
      }
      Shortcut {
        sequence: "Shift+J"
        enabled: !focusScope.typing
          && (root.showingFeed || root.powerThroughActive || root.currentView === "reader")
        onActivated: root.currentView === "reader"
          ? reader.moveMessage(1)
          : (root.powerThroughActive ? powerThroughPane.moveCursor(1) : root.moveCursor(1))
      }
      Shortcut {
        sequence: "Shift+K"
        enabled: !focusScope.typing
          && (root.showingFeed || root.powerThroughActive || root.currentView === "reader")
        onActivated: root.currentView === "reader"
          ? reader.moveMessage(-1)
          : (root.powerThroughActive ? powerThroughPane.moveCursor(-1) : root.moveCursor(-1))
      }
      Shortcut {
        sequence: "Return"
        enabled: !focusScope.typing
        onActivated: {
          if (root.powerThroughActive) powerThroughPane.expandCurrent()
          else if (root.showingFeed) feedView.expandCurrent()
          else if (root.currentView === "list") root.openMessage(root.cursorId)
        }
      }
      // "o" for open, same behaviour as Enter in list mode.
      Shortcut { sequence: "o"; enabled: !focusScope.typing && root.currentView === "list" && !root.powerThroughActive && !root.showingFeed; onActivated: root.openMessage(root.cursorId) }
      // Shift+H exits Power Through or The Feed, returning to the Imbox list.
      Shortcut {
        sequence: "Shift+H"
        enabled: !focusScope.typing
        onActivated: {
          if (root.powerThroughActive) { root.powerThroughActive = false }
          else if (root.showingFeed) { root.goWorkflow("inbox") }
        }
      }
      Shortcut {
        sequence: "x"
        enabled: !focusScope.typing && root.currentView === "list" && root.cursorId !== ""
        onActivated: root.toggleSelect(root.cursorId)
      }
      Shortcut {
        sequence: "."
        enabled: !focusScope.typing && root.currentView === "list"
          && root.cursorId !== "" && !!root.service && root.service.workflowEnabled
        onActivated: quickActions.openAt(root.cursorId, window.width / 2, window.height / 2)
      }
      Shortcut { sequence: "e"; enabled: !focusScope.typing; onActivated: root.actOnCursor("archive") }
      Shortcut { sequence: "d"; enabled: !focusScope.typing; onActivated: root.actOnCursor("trash") }
      Shortcut { sequence: "s"; enabled: !focusScope.typing; onActivated: if (root.service) root.service.toggleStar(root.cursorId) }
      Shortcut { sequence: "Shift+I"; enabled: !focusScope.typing; onActivated: root.actOnCursor("markRead") }
      Shortcut { sequence: "Shift+U"; enabled: !focusScope.typing; onActivated: root.actOnCursor("markUnread") }
      Shortcut { sequence: "r"; enabled: !focusScope.typing && root.currentView === "reader"; onActivated: reader.focusReply() }
      Shortcut { sequence: "a"; enabled: !focusScope.typing && root.currentView === "reader"; onActivated: root.startCompose("replyAll") }
      Shortcut { sequence: "f"; enabled: !focusScope.typing && root.currentView === "reader"; onActivated: root.startCompose("forward") }
      Shortcut {
        sequence: "Shift+N"
        enabled: !focusScope.typing && root.readingTogether
        onActivated: root.nextReadTogether()
      }
      Shortcut {
        sequence: "b"
        enabled: !focusScope.typing && root.currentView === "list"
          && root.cursorId !== "" && !!root.service
        onActivated: labelPicker.openFor(root.cursorId)
      }
      Shortcut { sequence: "c"; enabled: !focusScope.typing; onActivated: root.startCompose("new") }
      Shortcut {
        sequence: "h"
        enabled: !focusScope.typing && root.currentView === "reader"
        onActivated: root.backToList()
      }
      Shortcut {
        sequence: "v"
        enabled: !focusScope.typing && !!root.service && root.service.workflowEnabled
        onActivated: root.service.markWorkflowSeen(root.cursorId, true)
      }
      Shortcut {
        sequence: "u"
        enabled: !focusScope.typing && !!root.service && root.service.workflowEnabled
        onActivated: root.service.markWorkflowSeen(root.cursorId, false)
      }
      Shortcut { sequence: "1"; enabled: !focusScope.typing; onActivated: root.goWorkflow("inbox") }
      Shortcut { sequence: "2"; enabled: !focusScope.typing; onActivated: root.goWorkflow("feed") }
      Shortcut { sequence: "3"; enabled: !focusScope.typing; onActivated: root.goWorkflow("paper_trail") }
      Shortcut { sequence: "4"; enabled: !focusScope.typing; onActivated: root.goWorkflow("reply_later") }
      Shortcut { sequence: "5"; enabled: !focusScope.typing; onActivated: root.goWorkflow("set_aside") }
      Shortcut { sequence: "6"; enabled: !focusScope.typing; onActivated: root.goWorkflow("bubble_up") }
      Shortcut { sequence: "9"; enabled: !focusScope.typing; onActivated: root.goWorkflow("previously_seen") }
      Shortcut {
        sequence: "x"
        enabled: !focusScope.typing && root.currentView === "list"
          && !!root.service && root.service.workflowEnabled && root.service.workflowKey === "screener"
        onActivated: root.routeCursor("screened_out")
      }
      Shortcut {
        sequence: "i"
        enabled: !focusScope.typing && root.currentView === "list"
          && !!root.service && root.service.workflowEnabled
        onActivated: root.routeCursor("inbox")
      }
      Shortcut {
        sequence: "p"
        enabled: !focusScope.typing && root.currentView === "list"
          && !!root.service && root.service.workflowEnabled
        onActivated: root.routeCursor("paper_trail")
      }
      Shortcut {
        sequence: "f"
        enabled: !focusScope.typing && root.currentView === "list"
          && !!root.service && root.service.workflowEnabled
        onActivated: root.routeCursor("feed")
      }
      Shortcut {
        sequence: "l"
        enabled: !focusScope.typing && !!root.service && root.service.workflowEnabled
        onActivated: root.pileCursor("reply_later")
      }
      Shortcut {
        sequence: "a"
        enabled: !focusScope.typing && root.currentView === "list"
          && !!root.service && root.service.workflowEnabled
        onActivated: root.pileCursor("set_aside")
      }
      Shortcut {
        sequence: "z"
        enabled: !focusScope.typing && !!root.service && root.service.workflowEnabled
          && root.currentView === "list" && root.cursorId !== ""
        onActivated: bubbleMenu.open()
      }
      Shortcut { sequence: "g,i"; enabled: !focusScope.typing; onActivated: root.goMailbox("inbox") }
      Shortcut { sequence: "g,s"; enabled: !focusScope.typing; onActivated: root.goMailbox("starred") }
      Shortcut { sequence: "g,u"; enabled: !focusScope.typing; onActivated: root.goMailbox("unread") }
      Shortcut { sequence: "g,t"; enabled: !focusScope.typing; onActivated: root.goMailbox("sent") }
      Shortcut { sequence: "g,e"; enabled: !focusScope.typing; onActivated: root.goWorkflow("everything") }
      Shortcut {
        sequence: "g,m"
        enabled: !focusScope.typing
        onActivated: mailboxMore.openCentered()
      }
      Shortcut { sequence: "Ctrl++"; onActivated: root.zoomBy(0.1) }
      Shortcut { sequence: "Ctrl+="; onActivated: root.zoomBy(0.1) }
      Shortcut { sequence: "Ctrl+-"; onActivated: root.zoomBy(-0.1) }
      Shortcut { sequence: "Ctrl+0"; onActivated: root.bodyZoom = 1.0 }
      Shortcut { sequence: "Ctrl+/"; onActivated: root.shortcutHelpVisible = !root.shortcutHelpVisible }
      Shortcut { sequence: "Ctrl+?"; onActivated: root.shortcutHelpVisible = !root.shortcutHelpVisible }
      Shortcut { sequence: "?"; enabled: !focusScope.typing; onActivated: root.shortcutHelpVisible = !root.shortcutHelpVisible }
      Shortcut { sequence: "F5"; onActivated: if (root.service) root.service.refresh() }
    }
  }

}
