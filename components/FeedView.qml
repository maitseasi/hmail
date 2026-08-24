import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Item {
  id: root

  required property var service
  required property color textColor
  required property color backgroundColor
  required property color accentColor
  required property color dimColor
  required property string panelFontFamily
  property string cursorId: ""

  signal messageActivated(string id)
  signal messageFocused(string id)

  function expandCurrent() {
    var item = feed.currentItem
    if (item && item.summary && item.summary.id === root.cursorId)
      item.toggleExpand()
  }

  function revealCursor() {
    if (!service) return
    for (var i = 0; i < service.messages.length; i++) {
      if (service.messages[i].id === cursorId) {
        feed.currentIndex = i
        feed.positionViewAtIndex(i, ListView.Contain)
        return
      }
    }
  }

  function scrollBy(pixels) {
    feed.contentY = Math.max(0, Math.min(
      Math.max(0, feed.contentHeight - feed.height),
      feed.contentY + Number(pixels || 0)))
  }

  function scrollToEnd(end) {
    feed.contentY = end ? Math.max(0, feed.contentHeight - feed.height) : 0
  }

  onCursorIdChanged: Qt.callLater(revealCursor)

  ListView {
    id: feed
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    width: Math.min(parent.width - Style.space(80), Style.space(720))
    topMargin: Style.space(12)
    bottomMargin: Style.space(12)
    clip: true
    spacing: Style.space(14)
    boundsBehavior: Flickable.StopAtBounds
    model: root.service ? root.service.messages : []
    cacheBuffer: Style.space(500)
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.NoButton
      z: 10
      onWheel: function(wheel) {
        var amount = wheel.pixelDelta.y
        if (amount === 0)
          amount = (wheel.angleDelta.y / 120) * Style.space(140)
        root.scrollBy(-amount)
        wheel.accepted = true
      }
    }

    delegate: FeedCard {
      required property var modelData
      width: feed.width - Style.space(8)
      summary: modelData
      service: root.service
      textColor: root.textColor
      backgroundColor: root.backgroundColor
      accentColor: root.accentColor
      dimColor: root.dimColor
      panelFontFamily: root.panelFontFamily
      focused: root.cursorId === modelData.id
      onCardFocused: root.messageFocused(modelData.id)
      // onActivated intentionally not connected — Feed is a reading surface.
    }

    Text {
      anchors.centerIn: parent
      visible: feed.count === 0
      text: root.service && root.service.listLoading
        ? "Loading…"
        : "No senders are delivering here yet.\nMove a newsletter to Feed to start."
      textFormat: Text.PlainText
      horizontalAlignment: Text.AlignHCenter
      color: root.dimColor
      font.family: root.panelFontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
