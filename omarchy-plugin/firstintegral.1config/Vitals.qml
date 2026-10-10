import QtQuick
import QtQuick.Controls
import qs.Commons

// Live checks for this checkout. Rays turn only while the panel is open
// on this view. Colours stay on the theme: accent for a clear or warn
// signal, urgent for a fault.
Item {
  id: root

  property var groups: []
  property var vitals: []
  property string verdict: ""
  property bool active: false
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color background: Color.popups.background
  property string proseFamily: "sans-serif"
  property string monoFamily: Style.font.family

  // A tile that carries detail (boot slip lines, uncommitted files) asks the
  // panel to open them. Tiles without detail are not clickable.
  signal detailRequested(string vitalId)

  property real spin: 0

  readonly property color ray: verdict === "fault" ? Color.urgent : accent
  readonly property int rayMs: verdict === "fault" ? 9000 : (verdict === "warn" ? 18000 : 36000)

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function tone(state) { return state === "fail" ? Color.urgent : root.accent }
  function verdictWord() {
    if (root.verdict === "clear") return "CLEAR"
    if (root.verdict === "warn") return "WARN"
    if (root.verdict === "fault") return "FAULT"
    return "READING"
  }
  function tally(state) {
    var n = 0
    var list = root.vitals || []
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].state || "") === state) n++
    }
    return n
  }
  function scrollBy(dy) {
    var max = Math.max(0, flick.contentHeight - flick.height)
    flick.contentY = Math.max(0, Math.min(max, flick.contentY + dy))
  }

  NumberAnimation on spin {
    running: root.active && root.visible
    loops: Animation.Infinite
    from: 0
    to: 360
    duration: root.rayMs
  }

  Item {
    id: halo
    width: parent.width
    height: Style.space(48)

    Item {
      id: markBox
      width: Style.space(40)
      height: width
      anchors.verticalCenter: parent.verticalCenter
      clip: true

      Repeater {
        model: 8
        Rectangle {
          required property int index
          width: 1
          height: Style.space(14)
          x: markBox.width / 2 - width / 2
          y: markBox.height / 2 - height
          transformOrigin: Item.Bottom
          rotation: index * 45 + root.spin
          antialiasing: true
          opacity: 0.8
          gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: root.alpha(root.ray, 0.0) }
            GradientStop { position: 1.0; color: root.alpha(root.ray, 0.75) }
          }
        }
      }

      Rectangle {
        id: core
        property real glowAlpha: 0.45
        width: Style.space(26)
        height: width
        radius: width / 2
        anchors.centerIn: parent
        color: root.alpha(root.background, 0.92)
        border.width: 1
        border.color: root.alpha(root.ray, core.glowAlpha)

        Loader {
          id: coreMark
          anchors.centerIn: parent
          width: Style.space(16)
          height: width
          source: Qt.resolvedUrl("RingMark.qml")
          onLoaded: {
            item.width = Qt.binding(function() { return coreMark.width })
            item.height = Qt.binding(function() { return coreMark.height })
            item.color = Qt.binding(function() { return root.ray })
            item.family = root.monoFamily
          }
        }
      }

      SequentialAnimation {
        running: root.active && root.visible
        loops: Animation.Infinite
        NumberAnimation {
          target: core
          property: "glowAlpha"
          to: 0.9
          duration: 1700
          easing.type: Easing.InOutSine
        }
        NumberAnimation {
          target: core
          property: "glowAlpha"
          to: 0.28
          duration: 1700
          easing.type: Easing.InOutSine
        }
      }
    }

    Column {
      anchors.left: markBox.right
      anchors.leftMargin: Style.space(8)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      Text {
        width: parent.width
        text: root.verdictWord()
        color: root.ray
        font.family: root.proseFamily
        font.pixelSize: Style.font.heading
        font.bold: true
        font.letterSpacing: 0.8
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: root.tally("ok") + " clear   " + root.tally("warn") + " warn   " + root.tally("fail") + " fault"
        color: root.foreground
        opacity: 0.72
        font.family: root.monoFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }
  }

  Flickable {
    id: flick
    anchors.top: halo.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentWidth: width
    contentHeight: listCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {
      policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
    }

    Column {
      id: listCol
      width: flick.width
      spacing: Style.space(14)

      Text {
        visible: !root.vitals || root.vitals.length === 0
        width: parent.width
        text: "Reading the checkout"
        color: root.foreground
        opacity: 0.75
        font.family: root.proseFamily
        font.pixelSize: Style.font.title
      }

      Repeater {
        model: root.groups
        delegate: Column {
          id: groupCol
          required property var modelData
          width: listCol.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: groupName.implicitHeight
            Rectangle {
              width: Style.space(3)
              height: Math.round(groupName.font.pixelSize * 0.72)
              radius: 1
              color: root.accent
              anchors.verticalCenter: groupName.verticalCenter
            }
            Text {
              id: groupName
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              text: String(groupCol.modelData.name || "")
              color: root.foreground
              font.family: root.proseFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              font.letterSpacing: 0.3
            }
          }

          Item {
            id: board
            width: parent.width
            readonly property int count: (groupCol.modelData.items || []).length
            readonly property int cellH: Style.space(32)
            readonly property int gap: Style.space(4)
            implicitHeight: count === 0 ? 0 : Math.ceil(count / 2) * cellH + Math.max(0, Math.ceil(count / 2) - 1) * gap
            height: implicitHeight

            Repeater {
              model: groupCol.modelData.items || []
              delegate: Rectangle {
                id: card
                required property int index
                required property var modelData
                readonly property string state: String(modelData.state || "")
                readonly property bool hasMore: !!(card.modelData.more && card.modelData.more.length > 0)
                readonly property int cellW: Math.max(40, Math.floor((board.width - board.gap) / 2))
                width: cellW
                height: board.cellH
                x: (index % 2) * (cellW + board.gap)
                y: Math.floor(index / 2) * (board.cellH + board.gap)
                radius: Style.space(6)
                color: root.alpha(root.foreground, card.state === "ok" ? 0.045 : 0.07)
                border.width: 1
                border.color: root.alpha(
                  root.tone(card.state),
                  (card.hasMore && cardTap.containsMouse) ? 1
                    : card.state === "ok" ? 0.28 : 0.8)

                Rectangle {
                  width: Style.space(3)
                  radius: width / 2
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  height: parent.height * 0.55
                  color: root.tone(card.state)
                  opacity: card.state === "ok" ? 0.4 : 1
                }

                Text {
                  id: stateText
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: (card.state === "ok" ? "CLEAR" : (card.state === "warn" ? "WARN" : "FAULT"))
                    + (card.hasMore ? "  ›" : "")
                  color: root.tone(card.state)
                  opacity: card.state === "ok" ? 0.55 : 0.95
                  font.family: root.monoFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 0.4
                }
                Text {
                  id: nameText
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.max(Style.space(88), (parent.width - stateText.implicitWidth - Style.space(36)) * 0.46)
                  text: String(card.modelData.name || "")
                  color: root.foreground
                  elide: Text.ElideRight
                  font.family: root.proseFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                Text {
                  anchors.left: nameText.right
                  anchors.leftMargin: Style.space(6)
                  anchors.right: stateText.left
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  text: String(card.modelData.detail || "")
                  color: card.state === "ok" ? root.foreground : root.tone(card.state)
                  opacity: card.state === "ok" ? 0.7 : 1
                  elide: Text.ElideRight
                  font.family: root.monoFamily
                  font.pixelSize: Style.font.bodySmall
                }

                MouseArea {
                  id: cardTap
                  anchors.fill: parent
                  enabled: card.hasMore
                  hoverEnabled: card.hasMore
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.detailRequested(String(card.modelData.id))
                }
              }
            }
          }
        }
      }
    }
  }
}
