import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// The permanent navigation is the workflow, not Gmail's storage model.
// Occasional folders and labels live behind More so this column stays calm.
Item {
  id: root

  required property var service
  required property color textColor
  required property color accentColor
  required property color dimColor
  required property string panelFontFamily
  // Compatibility input while App migrates saved "collapsed" preferences to a
  // fully hidden sidebar.
  property bool collapsed: false

  signal workflowSelected(string key)
  signal moreRequested(real sceneX, real sceneY)

  property bool switcherOpen: false
  signal switcherRequested(real sceneX, real sceneY)

  readonly property var primaryEntries: [
    { key: "screener", label: "Screener", icon: "eye" },
    { key: "inbox", label: "Imbox", icon: "inbox" },
    { key: "feed", label: "The Feed", icon: "unread" },
    { key: "paper_trail", label: "The Paper Trail", icon: "archive" }
  ]
  readonly property var pileEntries: [
    { key: "reply_later", label: "Reply Later", icon: "reply" },
    { key: "set_aside", label: "Set Aside", icon: "label" },
    { key: "bubble_up", label: "Bubble Up", icon: "refresh" }
  ]
  readonly property var libraryEntries: [
    { key: "previously_seen", label: "Seen", icon: "check" },
    { key: "everything", label: "Everything", icon: "archive" }
  ]
  readonly property bool hasActivePiles: {
    var counts = root.service ? root.service.workflowCounts : ({})
    for (var i = 0; i < pileEntries.length; i++) {
      if (Number(counts[pileEntries[i].key] || 0) > 0) return true
    }
    return false
  }
  readonly property var compactEntries: {
    var out = primaryEntries.slice()
    var counts = root.service ? root.service.workflowCounts : ({})
    for (var i = 0; i < pileEntries.length; i++) {
      if (Number(counts[pileEntries[i].key] || 0) > 0) out.push(pileEntries[i])
    }
    out.push({ key: "more", label: "More", icon: "menu" })
    return out
  }

  PanelSeparator {
    id: edge
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: 1
    foreground: root.textColor
  }

  Flickable {
    id: flick
    anchors.left: parent.left
    anchors.right: edge.left
    anchors.top: parent.top
    anchors.bottom: footer.top
    contentWidth: width
    contentHeight: column.implicitHeight + Style.space(12)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: column
      x: Style.space(6)
      y: Style.space(10)
      width: flick.width - Style.space(12)
      spacing: Style.space(2)

      Repeater {
        model: root.primaryEntries
        Entry {
          required property var modelData
          label: modelData.label
          icon: modelData.icon
          showCount: modelData.key === "screener" || modelData.key === "inbox"
          count: root.workflowCount(modelData.key)
          selected: root.workflowSelectedKey(modelData.key)
          onActivated: root.workflowSelected(modelData.key)
        }
      }

      GroupRule { visible: root.hasActivePiles; topPad: Style.space(4) }

      Repeater {
        model: root.pileEntries
        Entry {
          required property var modelData
          visible: count > 0
          label: modelData.label
          icon: modelData.icon
          showCount: true
          count: root.workflowCount(modelData.key)
          selected: root.workflowSelectedKey(modelData.key)
          onActivated: root.workflowSelected(modelData.key)
        }
      }

      GroupRule { topPad: Style.space(4) }

      Repeater {
        model: root.libraryEntries
        Entry {
          required property var modelData
          label: modelData.label
          icon: modelData.icon
          selected: root.workflowSelectedKey(modelData.key)
          onActivated: root.workflowSelected(modelData.key)
        }
      }

      Entry {
        label: "More…"
        icon: "menu"
        onActivated: {
          var scene = mapToGlobal(width, 0)
          root.moreRequested(scene.x, scene.y)
        }
      }
    }
  }

  Column {
    id: footer
    anchors.left: parent.left
    anchors.right: edge.left
    anchors.bottom: parent.bottom

    PanelSeparator {
      width: parent.width
      foreground: root.textColor
    }

    UserBar {
      width: parent.width
      textColor: root.textColor
      accentColor: root.accentColor
      dimColor: root.dimColor
      panelFontFamily: root.panelFontFamily
      email: root.service ? root.service.accountEmail : ""
      accountCount: root.service ? root.service.accountCount : 1
      collapsed: false
      switcherOpen: root.switcherOpen
      onSwitcherRequested: function(sceneX, sceneY) {
        root.switcherRequested(sceneX, sceneY)
      }
    }
  }

  function workflowCount(key) {
    return root.service && root.service.workflowCounts
      ? Number(root.service.workflowCounts[key] || 0) : 0
  }

  function workflowSelectedKey(key) {
    return !!root.service && root.service.workflowEnabled
      && root.service.workflowKey === key
  }

  component GroupRule: Item {
    property real topPad: 0
    width: column.width
    implicitHeight: Style.space(14) + topPad
    PanelSeparator {
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(7)
      width: parent.width
      foreground: root.textColor
    }
  }

  component Entry: Rectangle {
    id: entry
    required property string label
    property string icon: ""
    property int count: 0
    property bool showCount: false
    property bool selected: false
    signal activated()

    width: column.width
    implicitHeight: Style.space(32)
    radius: Style.cornerRadius
    color: entry.selected
      ? Style.selectedFillFor(root.textColor, root.accentColor)
      : (hover.hovered
        ? Style.hoverFillFor(root.textColor, root.accentColor) : "transparent")

    ActionIcon {
      id: glyph
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      name: entry.icon
      iconSize: Style.font.icon
      color: entry.selected ? root.textColor : root.dimColor
    }

    Text {
      anchors.left: glyph.right
      anchors.leftMargin: Style.space(9)
      anchors.right: badge.visible ? badge.left : parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: entry.label
      color: entry.selected ? root.textColor : root.dimColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: entry.selected
      elide: Text.ElideRight
    }

    Text {
      id: badge
      visible: entry.showCount && entry.count > 0
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: Model.badgeText(entry.count, 999)
      color: root.accentColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: entry.activated() }

    PanelToolTip {
      visible: hover.hovered
      text: entry.showCount && entry.count > 0
        ? entry.label + " · " + entry.count : entry.label
      fontFamily: root.panelFontFamily
    }
  }
}
