import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui

// 1config usage panel. One card per tool. r re-reads local files.
// u runs Omarchy's own limit collectors, which contact the provider.
Panel {
  id: root
  moduleName: "firstintegral.1config"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("firstintegral.1config") : null
  readonly property bool ready: service ? service.ready === true : false
  readonly property int revision: service ? service.revision : 0
  readonly property var agents: service && service.agents ? service.agents : []
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property string contentFontFamily: "sans-serif"
  readonly property string monoFamily: Style.font.family

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }
  function refresh() { if (root.service) root.service.refresh() }
  function refreshLimits() { if (root.service) root.service.refreshLimits() }

  function scrollBy(dy) {
    var max = Math.max(0, flick.contentHeight - flick.height)
    flick.contentY = Math.max(0, Math.min(max, flick.contentY + dy))
  }

  function handleTextKey(t) {
    if (t === "r" || t === "R") root.refresh()
    else if (t === "u" || t === "U") root.refreshLimits()
  }

  function clockLabel() {
    var g = service ? String(service.generatedAt || "") : ""
    var m = g.match(/T(\d\d:\d\d)/)
    return m ? m[1] : ""
  }

  function tint(a) {
    return Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, a)
  }

  component Meter: Item {
    id: meter
    property real value: 0
    property bool hot: false
    implicitHeight: Style.space(4)
    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: root.tint(0.12)
    }
    Rectangle {
      width: Math.max(0, Math.min(1, meter.value / 100)) * parent.width
      height: parent.height
      radius: height / 2
      color: meter.hot ? Color.urgent : root.accent
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      clip: true
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.scrollBy(dy * Style.space(48)) }
      onActivateRequested: root.refresh()
      onTextKey: function(t) { root.handleTextKey(t) }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: panelColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        ScrollBar.vertical: ScrollBar { policy: flick.contentHeight > flick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

        Column {
          id: panelColumn
          width: flick.width
          spacing: Style.space(10)

          Column {
            width: parent.width
            spacing: 0
            Text {
              text: "1config"
              color: root.accent
              font.family: root.monoFamily
              font.pixelSize: Style.font.body
              font.capitalization: Font.SmallCaps
              font.letterSpacing: 1.2
            }
            Text {
              width: parent.width
              text: {
                var host = root.service ? String(root.service.hostname || "") : ""
                var clock = root.clockLabel()
                var bits = []
                if (host) bits.push(host)
                if (clock) bits.push(clock)
                var msg = root.service ? String(root.service.message || "") : ""
                if (msg) bits.push(msg)
                return bits.join("  ·  ")
              }
              color: root.contentForeground
              opacity: 0.6
              font.family: root.monoFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          Text {
            visible: !root.ready
            width: parent.width
            text: root.service && root.service.state === "error"
              ? String(root.service.message || "usage unreadable")
              : "Reading this machine…"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: root.agents
            delegate: Rectangle {
              id: card
              required property var modelData
              required property int index
              property var agent: modelData
              width: panelColumn.width
              implicitHeight: cardBody.implicitHeight + Style.space(16)
              radius: Style.space(6)
              color: root.tint(0.04)
              border.width: 1
              border.color: root.tint(0.1)

              Column {
                id: cardBody
                x: Style.space(8)
                y: Style.space(8)
                width: parent.width - Style.space(16)
                spacing: Style.space(4)

                Row {
                  width: parent.width
                  spacing: Style.space(8)
                  Text {
                    text: String(card.agent.name || card.agent.id || "")
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    font.weight: Font.Medium
                  }
                  Text {
                    text: {
                      var bits = []
                      for (var i = 0; i < (card.agent.limits || []).length; i++) {
                        var used = Number(card.agent.limits[i].usedPct)
                        if (!isNaN(used)) bits.push(Math.round(used) + "%")
                      }
                      return bits.join("  ")
                    }
                    color: {
                      var hot = false
                      var limits = card.agent.limits || []
                      for (var i = 0; i < limits.length; i++) if (Number(limits[i].usedPct) >= 80) hot = true
                      return hot ? Color.urgent : root.accent
                    }
                    font.family: root.monoFamily
                    font.pixelSize: Style.font.body
                  }
                }

                Text {
                  width: parent.width
                  text: "today " + String(card.agent.todayLabel || "—")
                    + "   ·   7d " + String(card.agent.weekLabel || "—")
                  color: root.contentForeground
                  opacity: 0.85
                  font.family: root.monoFamily
                  font.pixelSize: Style.font.caption
                }

                Repeater {
                  model: card.agent.limits || []
                  delegate: Column {
                    required property var modelData
                    width: cardBody.width
                    spacing: Style.space(2)
                    Text {
                      width: parent.width
                      text: String(modelData.label || "Limit")
                        + (modelData.resetsAt ? "  ·  " + String(modelData.resetsAt).slice(0, 16) : "")
                      color: root.contentForeground
                      opacity: 0.55
                      font.family: root.monoFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                    Meter {
                      width: parent.width
                      value: Number(modelData.usedPct) || 0
                      hot: Number(modelData.usedPct) >= 80
                    }
                  }
                }

                Text {
                  visible: String(card.agent.status || "") !== ""
                  width: parent.width
                  text: String(card.agent.status || "")
                  color: Color.urgent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                Text {
                  visible: (card.agent.models || []).length > 0
                  width: parent.width
                  text: {
                    var bits = []
                    var models = card.agent.models || []
                    for (var i = 0; i < models.length; i++)
                      bits.push(String(models[i].id) + " " + String(models[i].label || ""))
                    return bits.join("  ·  ")
                  }
                  color: root.contentForeground
                  opacity: 0.55
                  font.family: root.monoFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: String(card.agent.sourceLabel || "")
                  color: root.contentForeground
                  opacity: 0.4
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }
          }

          Text {
            width: parent.width
            text: root.service && root.service.note
              ? String(root.service.note)
              : "Timer reads this machine only. u asks Omarchy to refresh provider limits."
            color: root.contentForeground
            opacity: 0.45
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Row {
            spacing: Style.space(12)
            Repeater {
              model: [["esc", "close"], ["r", "re-read"], ["u", "limits"], ["j/k", "scroll"]]
              Row {
                required property var modelData
                spacing: Style.space(4)
                Text {
                  text: modelData[0]
                  color: root.accent
                  font.family: root.monoFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  text: modelData[1]
                  color: root.contentForeground
                  opacity: 0.45
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }
      }
    }
  }
}
