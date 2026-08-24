import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// The occasional navigation surface shared by the sidebar, compact tabs, and
// the header menu. Gmail's folder tree stays available without defining the
// shape of the everyday workflow.
Item {
  id: root

  required property var service
  required property color textColor
  required property color accentColor
  required property color dimColor
  required property string panelFontFamily

  readonly property bool opened: popup.opened
  property real anchorX: 0
  property real anchorY: 0
  property string currentTab: "folders"
  property int cursorIndex: 0

  signal mailboxSelected(string key)
  signal workflowSelected(string key)
  signal labelSelected(string labelId, string name)
  signal dismissed()

  readonly property var userLabels: {
    var all = root.service ? root.service.labels : []
    var out = []
    for (var i = 0; i < all.length; i++) {
      if (!all[i].system) out.push(all[i])
    }
    return out
  }
  readonly property bool filterVisible: currentTab === "labels"
    && userLabels.length > 8
  readonly property var rows: {
    var out = []
    if (currentTab === "folders") {
      for (var i = 0; i < Model.MAILBOXES.length; i++) {
        var mailbox = Model.MAILBOXES[i]
        out.push({
          kind: "mailbox",
          key: mailbox.key,
          label: mailbox.key === "inbox" ? "Gmail Inbox" : mailbox.label,
          icon: mailbox.icon,
          group: "Folders"
        })
      }
      var piles = [
        { key: "reply_later", label: "Reply Later", icon: "reply" },
        { key: "set_aside", label: "Set Aside", icon: "label" },
        { key: "bubble_up", label: "Bubble Up", icon: "refresh" }
      ]
      var counts = root.service ? root.service.workflowCounts : ({})
      for (var j = 0; j < piles.length; j++) {
        if (Number(counts[piles[j].key] || 0) === 0) {
          out.push({
            kind: "workflow",
            key: piles[j].key,
            label: piles[j].label,
            icon: piles[j].icon,
            group: "Empty workflow piles"
          })
        }
      }
      return out
    }

    var query = String(labelFilter.text || "").trim().toLowerCase()
    for (var k = 0; k < userLabels.length; k++) {
      var label = userLabels[k]
      if (query !== "" && String(label.name).toLowerCase().indexOf(query) < 0)
        continue
      out.push({
        kind: "label",
        key: label.id,
        rawName: label.rawName,
        label: label.name,
        icon: "label",
        count: Number(label.unread || 0),
        group: "Labels"
      })
    }
    return out
  }

  function openAt(sceneX, sceneY) {
    var local = root.mapFromGlobal(sceneX, sceneY)
    anchorX = local.x
    anchorY = local.y
    currentTab = "folders"
    labelFilter.text = ""
    popup.open()
    place()
  }

  function openCentered() {
    anchorX = Math.max(0, (root.width - popup.width) / 2)
    anchorY = Math.max(0, (root.height - popup.implicitHeight) / 2)
    currentTab = "folders"
    labelFilter.text = ""
    popup.open()
    place()
  }

  function close() { popup.close() }

  function place() {
    if (!popup.visible) return
    var tall = popup.height > 0 ? popup.height : popup.implicitHeight
    popup.x = Math.max(0, Math.min(anchorX, root.width - popup.width))
    popup.y = Math.max(0, Math.min(anchorY, root.height - tall))
  }

  function setTab(tab) {
    currentTab = tab
    cursorIndex = 0
    if (filterVisible) Qt.callLater(function() { labelFilter.forceActiveFocus() })
    else Qt.callLater(function() { list.forceActiveFocus() })
  }

  function activate(index) {
    var row = rows[index]
    if (!row) return
    popup.close()
    if (row.kind === "mailbox") root.mailboxSelected(row.key)
    else if (row.kind === "workflow") root.workflowSelected(row.key)
    else root.labelSelected(row.key, row.rawName)
  }

  anchors.fill: parent
  z: 45

  QQC.Popup {
    id: popup
    width: Math.min(Style.space(290), root.width)
    height: Math.min(Style.space(440), implicitHeight)
    implicitHeight: Math.min(Style.space(440),
      heading.implicitHeight + tabs.implicitHeight
        + (filterVisible ? labelFilter.implicitHeight + Style.space(6) : 0)
        + Math.max(Style.space(80), list.contentHeight) + Style.space(28))
    padding: Style.space(10)
    modal: false
    focus: true
    closePolicy: QQC.Popup.CloseOnEscape | QQC.Popup.CloseOnPressOutside
    onHeightChanged: root.place()
    onOpened: {
      root.cursorIndex = 0
      root.place()
      Qt.callLater(function() { list.forceActiveFocus() })
    }
    onClosed: root.dismissed()
    background: Rectangle {
      radius: Style.cornerRadius
      color: Color.popups.background
      border.width: 1
      border.color: Color.popups.border
    }

    contentItem: Column {
      spacing: Style.space(6)

      Text {
        id: heading
        width: parent.width
        text: "More"
        color: root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Row {
        id: tabs
        width: parent.width
        spacing: Style.space(4)

        Button {
          text: "Folders"
          selected: root.currentTab === "folders"
          foreground: root.textColor
          bordered: false
          onClicked: root.setTab("folders")
        }
        Button {
          text: "Labels"
          selected: root.currentTab === "labels"
          foreground: root.textColor
          bordered: false
          onClicked: root.setTab("labels")
        }
      }

      QQC.TextField {
        id: labelFilter
        visible: root.filterVisible
        width: parent.width
        placeholderText: "Filter labels"
        color: root.textColor
        font.family: root.panelFontFamily
        font.pixelSize: Style.font.bodySmall
        selectByMouse: true
        onTextChanged: root.cursorIndex = 0
        Keys.onDownPressed: function(event) {
          list.forceActiveFocus()
          event.accepted = true
        }
        background: Rectangle {
          radius: Style.cornerRadius
          color: Style.normalFillFor(root.textColor, root.accentColor)
          border.width: labelFilter.activeFocus ? 1 : 0
          border.color: root.accentColor
        }
      }

      ListView {
        id: list
        width: parent.width
        height: Math.max(Style.space(80),
          popup.height - heading.implicitHeight - tabs.implicitHeight
            - (root.filterVisible ? labelFilter.implicitHeight + Style.space(6) : 0)
            - Style.space(38))
        clip: true
        model: root.rows
        currentIndex: Math.min(root.cursorIndex, count - 1)
        boundsBehavior: Flickable.StopAtBounds
        section.property: "group"
        section.criteria: ViewSection.FullString
        section.delegate: Text {
          required property string section
          width: ListView.view.width
          height: Style.space(24)
          verticalAlignment: Text.AlignVCenter
          text: section.toUpperCase()
          color: root.dimColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.caption
        }

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
            root.cursorIndex = Math.min(count - 1, root.cursorIndex + 1)
            positionViewAtIndex(root.cursorIndex, ListView.Contain)
            event.accepted = true
          } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
            root.cursorIndex = Math.max(0, root.cursorIndex - 1)
            positionViewAtIndex(root.cursorIndex, ListView.Contain)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activate(root.cursorIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_H || event.key === Qt.Key_Left) {
            root.setTab("folders")
            event.accepted = true
          } else if (event.key === Qt.Key_L || event.key === Qt.Key_Right) {
            root.setTab("labels")
            event.accepted = true
          } else if (event.key === Qt.Key_Slash && root.filterVisible) {
            labelFilter.forceActiveFocus()
            event.accepted = true
          }
        }

        delegate: Rectangle {
          id: row
          required property var modelData
          required property int index
          width: ListView.view.width
          height: Style.spacing.popupRowHeight
          radius: Style.cornerRadius
          color: row.index === root.cursorIndex || hover.hovered
            ? Style.hoverFillFor(root.textColor, root.accentColor) : "transparent"

          ActionIcon {
            id: rowIcon
            anchors.left: parent.left
            anchors.leftMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            name: row.modelData.icon
            iconSize: Style.font.iconSmall
            color: root.dimColor
          }

          Text {
            anchors.left: rowIcon.right
            anchors.leftMargin: Style.space(8)
            anchors.right: unread.visible ? unread.left : parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: row.modelData.label
            color: root.textColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Text {
            id: unread
            visible: Number(row.modelData.count || 0) > 0
            anchors.right: parent.right
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: Model.badgeText(Number(row.modelData.count || 0), 999)
            color: root.accentColor
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.caption
          }

          HoverHandler {
            id: hover
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: if (hovered) root.cursorIndex = row.index
          }
          TapHandler { onTapped: root.activate(row.index) }
        }

        Text {
          anchors.centerIn: parent
          visible: list.count === 0
          text: root.currentTab === "labels" ? "No matching labels" : "Nothing hidden"
          color: root.dimColor
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
