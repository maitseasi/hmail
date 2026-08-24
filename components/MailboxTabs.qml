import QtQuick
import qs.Commons
import qs.Ui

// Compact workflow navigation. Storage folders stay behind the final More
// segment instead of turning a narrow window into a horizontally scrolling
// Gmail tree.
Flickable {
  id: root

  required property color textColor
  required property string panelFontFamily
  property string current: "inbox"
  property int unread: 0
  property var entries: []
  property var counts: ({})
  property int cursorIndex: -1

  signal selected(string key)
  signal moreRequested(real sceneX, real sceneY)
  signal chipHovered(int index, bool isHovered)

  function revealCurrent() {
    if (current === "screener" || current === "inbox") {
      contentX = 0
      return
    }
    for (var i = 0; i < mailboxes.length; i++) {
      if (mailboxes[i].key !== current) continue
      var item = chipRepeater.itemAt(i)
      if (!item) return
      var left = track.x + item.x
      var right = left + item.width
      if (left < contentX) contentX = Math.max(0, left)
      else if (right > contentX + width)
        contentX = Math.min(Math.max(0, contentWidth - width), right - width)
      return
    }
  }

  onCurrentChanged: Qt.callLater(revealCurrent)
  onMailboxesChanged: Qt.callLater(revealCurrent)
  Component.onCompleted: Qt.callLater(revealCurrent)

  readonly property bool crowded: measure.implicitWidth > width && width > 0
  readonly property var mailboxes: root.entries

  width: parent ? parent.width : 0
  implicitHeight: track.height
  contentWidth: track.width
  contentHeight: track.height
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  flickableDirection: Flickable.HorizontalFlick
  interactive: contentWidth > width

  // One segmented control rather than loose chips. Separate chips left the
  // selected one's fill floating at a different left edge from the logo above
  // and the message text below; a single track has one edge, and that edge is
  // the one everything else lines up on.
  // Measured, not guessed: the labels are theme-dependent and this has to know
  // the width of the full set before deciding whether to show it.
  Row {
    id: measure
    visible: false
    spacing: 0
    Repeater {
      model: root.entries
      Button {
        required property var modelData
        text: modelData.label
        bordered: false
        fontSize: Style.font.bodySmall
      }
    }
  }

  Rectangle {
    id: track
    // Centred whenever the row has slack — which is the case once segments have
    // stood down. Left-aligned the moment it fills the width, so at the sizes
    // where it does span, its edge is still the one the logo and the message
    // text line up on.
    x: Math.max(0, (root.width - width) / 2)
    width: chips.implicitWidth
    height: chips.implicitHeight
    radius: Style.cornerRadius
    color: "transparent"
    border.width: 1
    border.color: Style.normalBorderFor(root.textColor, Color.accent)

    Row {
      id: chips
      spacing: 0

      Repeater {
        id: chipRepeater
        model: root.mailboxes

        Item {
          id: segment
          required property var modelData
          required property int index

          implicitWidth: chip.implicitWidth
          implicitHeight: chip.implicitHeight

          // Segments share an edge instead of standing apart, so the row reads
          // as one control with a current position.
          Rectangle {
            visible: segment.index > 0
            width: 1
            height: parent.height
            color: track.border.color
          }

          Button {
            id: chip
            anchors.fill: parent
            text: segment.modelData.key !== "feed"
                && segment.modelData.key !== "paper_trail"
                && Number(root.counts[segment.modelData.key] || 0) > 0
              ? segment.modelData.label + " " + root.counts[segment.modelData.key]
              : segment.modelData.label
            foreground: root.textColor
            bordered: false
            selected: root.current === segment.modelData.key
            hasCursor: root.cursorIndex === segment.index
            fontSize: Style.font.bodySmall
            onClicked: {
              if (segment.modelData.key === "more") {
                var scene = mapToGlobal(width, height)
                root.moreRequested(scene.x, scene.y)
              } else {
                root.selected(segment.modelData.key)
              }
            }
            onHovered: function(isHovered) { root.chipHovered(segment.index, isHovered) }
          }
        }
      }
    }
  }
}
