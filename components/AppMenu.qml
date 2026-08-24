import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui

// The main navigation menu — a grid of destination tiles plus utility rows.
// Mirrors HEY's "H" menu: 6 workflow destinations up front, then folders
// and settings tucked below.
Item {
  id: root

  required property color textColor
  required property color accentColor
  required property color dimColor
  required property string panelFontFamily
  property bool signedIn: false
  property int accountCount: 1
  property var workflowCounts: ({})
  // Kept for API compatibility; grid always shows navigation.
  property bool showNavigation: true
  property bool showTrigger: false

  readonly property bool opened: menu.opened

  property real anchorX: 0
  property real anchorY: 0

  function openAt(sceneX, sceneY) {
    var local = root.mapFromGlobal(sceneX, sceneY)
    anchorX = local.x
    anchorY = local.y
    menu.open()
    place()
  }

  function place() {
    if (!menu.visible) return
    var tall = menu.height > 0 ? menu.height : menu.implicitHeight
    var wide = menu.width
    var x = Math.max(0, Math.min(anchorX, root.width - wide))
    var y = anchorY
    if (y + tall > root.height) y = anchorY - tall
    if (y + tall > root.height) y = root.height - tall
    if (y < 0) y = 0
    menu.x = x
    menu.y = y
  }

  function close() { menu.close() }

  signal workflowRequested(string key)
  signal markAllReadRequested()
  signal openWebRequested()
  signal moreNavigationRequested()
  signal shortcutsRequested()
  signal setupRequested()
  signal switchAccountRequested()
  signal projectRequested()
  signal authorRequested()

  anchors.fill: root.showTrigger ? undefined : parent
  implicitWidth: root.showTrigger ? Style.space(24) : 0
  implicitHeight: root.showTrigger ? Style.space(24) : 0
  z: 40

  Button {
    id: menuButton
    visible: root.showTrigger
    anchors.fill: parent
    text: "\u22EE"
    foreground: root.textColor
    bordered: false
    onClicked: menu.opened ? menu.close() : menu.open()
  }

  QQC.Popup {
    id: menu
    width: Style.space(340)
    implicitHeight: menuCol.implicitHeight + Style.space(16)
    padding: Style.space(8)
    modal: false
    focus: true
    closePolicy: QQC.Popup.CloseOnEscape | QQC.Popup.CloseOnPressOutside
    onHeightChanged: root.place()
    onOpened: root.place()

    background: Rectangle {
      radius: Style.cornerRadius
      color: Color.popups.background
      border.width: 1
      border.color: Color.popups.border
    }

    contentItem: Column {
      id: menuCol
      spacing: Style.space(10)

      // ── 2×3 destination grid ──────────────────────────────────────────
      readonly property var tiles: [
        { key: "inbox",       label: "Imbox",          number: "1", icon: "inbox"   },
        { key: "feed",        label: "The Feed",       number: "2", icon: "unread"  },
        { key: "paper_trail", label: "Paper Trail",    number: "3", icon: "archive" },
        { key: "reply_later", label: "Reply Later",    number: "4", icon: "reply"   },
        { key: "set_aside",   label: "Set Aside",      number: "5", icon: "label"   },
        { key: "bubble_up",   label: "Bubble Up",      number: "6", icon: "refresh" }
      ]

      Grid {
        id: tileGrid
        width: parent.width
        columns: 3
        rowSpacing: Style.space(6)
        columnSpacing: Style.space(6)

        readonly property real tileW: (width - columnSpacing * (columns - 1)) / columns

        Repeater {
          model: menuCol.tiles

          Rectangle {
            id: tile
            required property var modelData
            width: tileGrid.tileW
            height: Style.space(72)
            radius: Style.cornerRadius
            color: tileHover.hovered
              ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.10)
              : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.05)

            readonly property int tileCount: Number(root.workflowCounts[tile.modelData.key] || 0)

            // Keyboard number — top right
            Text {
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.topMargin: Style.space(6)
              anchors.rightMargin: Style.space(8)
              text: tile.modelData.number
              textFormat: Text.PlainText
              color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.35)
              font.family: root.panelFontFamily
              font.pixelSize: Style.font.caption
            }

            Column {
              anchors.centerIn: parent
              spacing: Style.space(5)

              ActionIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: tile.modelData.icon
                iconSize: Style.font.iconLarge
                color: root.textColor
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.modelData.label
                textFormat: Text.PlainText
                color: root.textColor
                font.family: root.panelFontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            // Count badge — bottom right, only for views that track counts
            Text {
              visible: tile.tileCount > 0
                && (tile.modelData.key === "inbox"
                  || tile.modelData.key === "reply_later"
                  || tile.modelData.key === "set_aside"
                  || tile.modelData.key === "bubble_up")
              anchors.bottom: parent.bottom
              anchors.right: parent.right
              anchors.bottomMargin: Style.space(6)
              anchors.rightMargin: Style.space(8)
              text: tile.tileCount > 99 ? "99+" : String(tile.tileCount)
              textFormat: Text.PlainText
              color: root.accentColor
              font.family: root.panelFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
              onTapped: {
                menu.close()
                root.workflowRequested(tile.modelData.key)
              }
            }
          }
        }
      }

      PanelSeparator {
        width: parent.width
        foreground: root.textColor
      }

      // ── Utility rows ──────────────────────────────────────────────────
      Column {
        width: parent.width
        spacing: Style.space(2)

        MenuRow {
          text: "Previously Seen"
          icon: "check"
          onActivated: { menu.close(); root.workflowRequested("previously_seen") }
        }
        MenuRow {
          text: "Folders and labels\u2026"
          icon: "archive"
          onActivated: { menu.close(); root.moreNavigationRequested() }
        }

        Item { width: 1; implicitHeight: Style.space(4) }

        PanelSeparator { width: parent.width; foreground: root.textColor }

        Item { width: 1; implicitHeight: Style.space(4) }

        MenuRow {
          text: "Mark these read"
          enabled: root.signedIn
          onActivated: { menu.close(); root.markAllReadRequested() }
        }
        MenuRow {
          text: "Open in Gmail"
          enabled: root.signedIn
          onActivated: { menu.close(); root.openWebRequested() }
        }
        MenuRow {
          visible: root.accountCount > 1
          text: "Switch account\u2026"
          onActivated: { menu.close(); root.switchAccountRequested() }
        }
        MenuRow {
          text: "Settings\u2026"
          onActivated: { menu.close(); root.setupRequested() }
        }
        MenuRow {
          text: "Keyboard shortcuts"
          onActivated: { menu.close(); root.shortcutsRequested() }
        }
      }
    }
  }

  component MenuRow: Rectangle {
    id: row
    required property string text
    property string icon: ""
    signal activated()

    width: menu.width - menu.leftPadding - menu.rightPadding
    implicitHeight: Style.spacing.popupRowHeight
    radius: Style.cornerRadius
    opacity: row.enabled ? 1.0 : 0.4
    color: rowHover.hovered
      ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.08)
      : "transparent"

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(9)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(9)
      anchors.verticalCenter: parent.verticalCenter
      text: row.text
      textFormat: Text.PlainText
      color: root.textColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: row.activated() }
  }
}
