import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui

// 1config brain HUD. The map is what this repo is. Usage is one part of it.
// Design tokens follow Projects/skills/brain-hud-design (the brwsk.brain look):
// theme colours only, accent for signal, sweep only while the map is open.
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
  readonly property var brain: service && service.brain ? service.brain : ({})
  readonly property var pillars: Array.isArray(brain.pillars) ? brain.pillars : []
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color cardBackground: Color.popups.background
  readonly property string proseFamily: "sans-serif"
  readonly property string monoFamily: Style.font.family

  property string mode: "usage"
  property string selectedId: ""

  function open() {
    root.mode = "usage"
    root.controller.show()
  }
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

  function tint(a) {
    return Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, a)
  }
  function accentA(a) { return Qt.rgba(root.accent.r, root.accent.g, root.accent.b, a) }
  function pad2(n) {
    var v = Math.max(0, Math.round(Number(n) || 0))
    return (v < 10 ? "0" : "") + v
  }
  function clockLabel() {
    var g = service ? String(service.generatedAt || "") : ""
    var m = g.match(/T(\d\d:\d\d)/)
    return m ? m[1] : ""
  }
  function selectedPillar() {
    for (var i = 0; i < root.pillars.length; i++) {
      if (String(root.pillars[i].id || "") === root.selectedId) return root.pillars[i]
    }
    return null
  }
  function cycle(delta) {
    if (!root.pillars.length) return
    var i = -1
    for (var k = 0; k < root.pillars.length; k++) {
      if (String(root.pillars[k].id || "") === root.selectedId) i = k
    }
    if (i < 0) i = delta > 0 ? -1 : 0
    var n = (i + delta) % root.pillars.length
    if (n < 0) n += root.pillars.length
    root.selectedId = String(root.pillars[n].id || "")
    root.mode = "map"
  }
  function scrollBy(dy) {
    var max = Math.max(0, usageFlick.contentHeight - usageFlick.height)
    usageFlick.contentY = Math.max(0, Math.min(max, usageFlick.contentY + dy))
  }
  function resetsIn(iso) {
    var text = String(iso || "")
    if (!text) return ""
    var ms = Date.parse(text)
    if (!isFinite(ms)) return ""
    var left = ms - Date.now()
    if (!(left > 0)) return ""
    var minutes = Math.floor(left / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return "Resets in " + days + "d " + (hours % 24) + "h"
    if (hours > 0) return "Resets in " + hours + "h " + (minutes % 60) + "m"
    return "Resets in " + Math.max(1, minutes) + "m"
  }
  function peakOf(rows, field) {
    var peak = 1
    var list = rows || []
    for (var i = 0; i < list.length; i++) {
      var n = Number(list[i][field]) || 0
      if (n > peak) peak = n
    }
    return peak
  }
  function handleTextKey(t) {
    if (t === "r" || t === "R") root.refresh()
    else if (t === "u" || t === "U") root.refreshLimits()
    else if (t === "g" || t === "G") root.mode = "map"
    else if (t === "s" || t === "S") root.mode = "usage"
    else if (t === "h" || t === "H") root.cycle(-1)
    else if (t === "l" || t === "L") root.cycle(1)
  }

  readonly property var panelBorder: {
    var spec = Border.flat(root.accent, 1)
    spec.gradient = {
      colors: [root.accentA(0.85), root.accentA(0.18), root.tint(0.10), root.accentA(0.55)],
      angle: 135,
      enabled: true
    }
    return spec
  }

  readonly property real screenW: panel.screenW > 0 ? panel.screenW : 1600
  readonly property real screenH: panel.screenH > 0 ? panel.screenH : 1025
  // Drops from the bar icon. Wide enough for one usage card, short enough to leave the desktop.
  readonly property int cardWidth: Math.round(Math.min(Style.space(640), Math.max(Style.space(400), 0.38 * screenW)))
  readonly property int cardHeight: Math.round(Math.min(Style.space(820), Math.max(Style.space(480), 0.68 * screenH)))

  component SectionHeader: Item {
    id: sh
    property string label: ""
    property string count: ""
    property color tone: Color.foreground
    property color countTone: Color.accent
    property string family: Style.font.family
    implicitHeight: shText.implicitHeight
    width: parent ? parent.width : implicitWidth
    Rectangle {
      id: shTick
      width: Style.space(3)
      height: Math.round(shText.font.pixelSize * 0.9)
      radius: 1
      color: sh.countTone
      anchors.verticalCenter: shText.verticalCenter
    }
    Text {
      id: shText
      anchors.left: shTick.right
      anchors.leftMargin: Style.space(7)
      text: sh.label
      color: sh.tone
      opacity: 0.8
      font.family: sh.family
      font.pixelSize: Style.font.body
      font.capitalization: Font.SmallCaps
      font.letterSpacing: 0.4
      font.bold: true
    }
    Text {
      id: shCount
      anchors.left: shText.right
      anchors.leftMargin: Style.space(8)
      anchors.baseline: shText.baseline
      visible: sh.count !== ""
      text: sh.count
      color: sh.countTone
      font.family: sh.family
      font.pixelSize: Style.font.body
      font.bold: true
    }
    Rectangle {
      anchors.left: shCount.visible ? shCount.right : shText.right
      anchors.leftMargin: Style.space(10)
      anchors.right: parent.right
      anchors.verticalCenter: shText.verticalCenter
      height: 1
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Qt.rgba(sh.tone.r, sh.tone.g, sh.tone.b, 0.28) }
        GradientStop { position: 1.0; color: Qt.rgba(sh.tone.r, sh.tone.g, sh.tone.b, 0.0) }
      }
    }
  }

  component Stat: Column {
    id: st
    property string value: "0"
    property string label: ""
    property color tone: Color.foreground
    property bool hot: false
    property string family: Style.font.family
    spacing: 0
    Text {
      text: st.value
      color: st.hot ? Color.accent : st.tone
      font.family: st.family
      font.pixelSize: Style.font.subtitle
      font.weight: Font.Light
      font.letterSpacing: 0
    }
    Text {
      text: st.label
      color: st.hot ? Color.accent : st.tone
      opacity: st.hot ? 0.85 : 0.5
      font.family: st.family
      font.pixelSize: Style.font.bodySmall
      font.capitalization: Font.SmallCaps
      font.letterSpacing: 0.3
    }
  }

  component Meter: Item {
    id: meter
    property real ratio: 0
    property bool hot: false
    property bool today: false
    implicitHeight: Math.max(Style.space(8), 8)
    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: root.tint(0.14)
    }
    Rectangle {
      width: Math.max(0, Math.min(1, meter.ratio)) * parent.width
      height: parent.height
      radius: height / 2
      color: meter.hot ? root.accent : (meter.today ? root.contentForeground : root.tint(0.55))
    }
  }

  component ShareRow: Item {
    id: share
    property string name: ""
    property string value: ""
    property real ratio: 0
    property bool today: false
    property bool hot: false
    implicitHeight: Math.max(shareName.implicitHeight, shareValue.implicitHeight) + Style.space(8)
    Text {
      id: shareName
      width: Style.space(168)
      text: share.name
      color: share.today ? root.contentForeground : root.tint(0.72)
      font.family: root.monoFamily
      font.pixelSize: Style.font.body
      font.bold: share.today
      elide: Text.ElideRight
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      id: shareValue
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: share.value
      color: share.today || share.hot ? root.contentForeground : root.tint(0.72)
      font.family: root.monoFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: share.today
    }
    Meter {
      anchors.left: shareName.right
      anchors.right: shareValue.left
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      ratio: share.ratio
      today: share.today
      hot: share.hot
    }
  }

  component UsageCard: Column {
    id: card
    required property var modelData
    readonly property var agent: modelData || ({})
    readonly property var dayRows: agent.days || []
    readonly property var modelRows: agent.models || []
    readonly property real dayPeak: root.peakOf(dayRows, "tokens")
    readonly property real modelPeak: root.peakOf(modelRows, "tokens")
    width: parent ? parent.width : implicitWidth
    spacing: Style.space(12)

    Item {
      width: parent.width
      implicitHeight: cardName.implicitHeight
      Text {
        id: cardName
        text: String(card.agent.name || card.agent.id || "")
        color: root.contentForeground
        font.family: root.monoFamily
        font.pixelSize: Style.font.subtitle
        font.capitalization: Font.SmallCaps
        font.letterSpacing: 0.4
        font.bold: true
        anchors.left: parent.left
        anchors.right: cardTotal.left
        anchors.rightMargin: Style.space(12)
        elide: Text.ElideRight
      }
      Text {
        id: cardTotal
        anchors.right: parent.right
        anchors.verticalCenter: cardName.verticalCenter
        text: String(card.agent.headline || card.agent.weekCostLabel || "")
        color: root.contentForeground
        font.family: root.monoFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }
    }

    Text {
      visible: card.dayRows.length === 0 && String(card.agent.weekLabel || "—") !== "—"
      width: parent.width
      text: "today " + String(card.agent.todayLabel || "—") + "    ·    7d " + String(card.agent.weekLabel || "—")
      color: root.contentForeground
      opacity: 0.7
      font.family: root.monoFamily
      font.pixelSize: Style.font.bodySmall
    }

    Repeater {
      model: card.agent.limits || []
      delegate: Column {
        required property var modelData
        width: card.width
        spacing: Style.space(6)
        Item {
          width: parent.width
          implicitHeight: limitName.implicitHeight
          Text {
            id: limitName
            text: String(modelData.label || "Limit")
            color: root.contentForeground
            font.family: root.monoFamily
            font.pixelSize: Style.font.body
            anchors.left: parent.left
            anchors.right: limitPct.left
            anchors.rightMargin: Style.space(12)
            elide: Text.ElideRight
          }
          Text {
            id: limitPct
            anchors.right: parent.right
            text: Math.round(Number(modelData.usedPct) || 0) + "% used"
            color: Number(modelData.usedPct) >= 80 ? root.accent : root.contentForeground
            font.family: root.monoFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
        }
        Meter {
          width: parent.width
          ratio: (Number(modelData.usedPct) || 0) / 100
          hot: Number(modelData.usedPct) >= 80
        }
        Text {
          visible: text !== ""
          width: parent.width
          text: String(modelData.detail || "") !== "" ? String(modelData.detail) : root.resetsIn(modelData.resetsAt)
          color: root.contentForeground
          opacity: 0.55
          font.family: root.monoFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }

    Column {
      visible: card.dayRows.length > 0
      width: parent.width
      spacing: Style.space(2)
      Text {
        text: "This week"
        color: root.contentForeground
        opacity: 0.55
        font.family: root.monoFamily
        font.pixelSize: Style.font.bodySmall
        font.capitalization: Font.SmallCaps
        font.letterSpacing: 0.3
      }
      Repeater {
        model: card.dayRows
        delegate: ShareRow {
          required property var modelData
          width: card.width
          name: String(modelData.label || "")
          value: {
            var bits = [String(modelData.tokenLabel || "0")]
            if (modelData.costLabel) bits.push(String(modelData.costLabel))
            return bits.join("   ")
          }
          ratio: (Number(modelData.tokens) || 0) / card.dayPeak
          today: modelData.today === true
        }
      }
    }

    Column {
      visible: card.modelRows.length > 0
      width: parent.width
      spacing: Style.space(2)
      Text {
        text: "By model"
        color: root.contentForeground
        opacity: 0.55
        font.family: root.monoFamily
        font.pixelSize: Style.font.bodySmall
        font.capitalization: Font.SmallCaps
        font.letterSpacing: 0.3
      }
      Repeater {
        model: card.modelRows
        delegate: ShareRow {
          required property var modelData
          width: card.width
          name: String(modelData.id || "")
          value: {
            var bits = [String(modelData.label || "")]
            if (modelData.costLabel) bits.push(String(modelData.costLabel))
            return bits.join("   ")
          }
          ratio: (Number(modelData.tokens) || 0) / card.modelPeak
        }
      }
    }

    Text {
      visible: String(card.agent.status || "") !== ""
      width: parent.width
      text: String(card.agent.status || "")
      color: Color.urgent
      font.family: root.proseFamily
      renderType: Text.NativeRendering
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }

    Rectangle {
      width: parent.width
      height: 1
      color: root.tint(0.08)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    borderSpec: root.panelBorder
    centerOnBar: false
    contentWidth: panel.fittedContentWidth(root.cardWidth)
    contentHeight: panel.cappedContentHeight(root.cardHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      clip: true
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy === 0) return
        if (root.mode === "usage") root.scrollBy(dy * Style.space(48))
        else root.cycle(dy > 0 ? 1 : -1)
      }
      onActivateRequested: root.refresh()
      onTextKey: function(t) { root.handleTextKey(t) }

      Canvas {
        id: backdrop
        anchors.fill: parent
        z: -1
        property color fg: root.contentForeground
        property color ac: root.accent
        onFgChanged: requestPaint()
        onAcChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var W = width
          var H = height
          function css(c, a) {
            return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")"
          }
          var glow = ctx.createLinearGradient(0, 0, 0, Math.min(H, 140))
          glow.addColorStop(0, css(ac, 0.07))
          glow.addColorStop(1, css(ac, 0))
          ctx.fillStyle = glow
          ctx.fillRect(0, 0, W, Math.min(H, 140))
        }
      }

      Column {
        anchors.fill: parent
        anchors.margins: Style.space(18)
        spacing: Style.space(16)

        Item {
          id: header
          width: parent.width
          implicitHeight: headerRow.implicitHeight + Style.space(8)
          Column {
            id: headerRow
            width: parent.width
            spacing: Style.space(4)
            Row {
              id: titleLine
              width: parent.width
              spacing: Style.space(8)
            Loader {
              id: titleMark
              width: Style.space(28)
              height: width
              anchors.verticalCenter: parent.verticalCenter
              source: Qt.resolvedUrl("RingMark.qml")
              onLoaded: {
                item.width = Qt.binding(function() { return titleMark.width })
                item.height = Qt.binding(function() { return titleMark.height })
                item.color = Qt.binding(function() { return root.accent })
                item.family = root.monoFamily
              }
            }
            Column {
              id: titleCol
              width: Math.max(Style.space(80), titleLine.width - switchBox.implicitWidth - titleMark.width - Style.space(16))
              spacing: Style.space(2)
              Text {
                text: "1config"
                color: root.contentForeground
                opacity: 0.85
                font.family: root.monoFamily
                font.pixelSize: Style.font.subtitle
                font.capitalization: Font.SmallCaps
                font.letterSpacing: 0.6
                font.bold: true
              }
              Text {
                width: titleCol.width
                text: {
                  var bits = []
                  var host = root.service ? String(root.service.hostname || "") : ""
                  var branch = String(root.brain.branch || "")
                  var remote = String(root.brain.remoteLabel || "FirstIntegral/1config")
                  var clock = root.clockLabel()
                  var slip = String(root.brain.slip || "")
                  if (host) bits.push(host)
                  bits.push(remote)
                  if (branch) bits.push(branch)
                  if (root.brain.dirty === true) bits.push("dirty")
                  if (slip && slip !== "unknown") bits.push(slip)
                  if (clock) bits.push(clock)
                  var msg = root.service ? String(root.service.message || "") : ""
                  if (msg) bits.push(msg)
                  return bits.join("  ·  ")
                }
                color: root.brain.dirty === true ? root.accent : root.contentForeground
                opacity: root.brain.dirty === true ? 0.9 : 0.6
                font.family: root.monoFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }
            Rectangle {
              id: switchBox
              radius: Style.space(5)
              color: root.tint(0.04)
              border.width: 1
              border.color: root.tint(0.12)
              implicitWidth: switchRow.implicitWidth + Style.space(6)
              implicitHeight: switchRow.implicitHeight + Style.space(6)
              Row {
                id: switchRow
                anchors.centerIn: parent
                spacing: Style.space(2)
                Repeater {
                  model: [{ id: "map", t: "map" }, { id: "usage", t: "spend" }]
                  Rectangle {
                    id: seg
                    required property var modelData
                    readonly property bool on: root.mode === modelData.id
                    implicitWidth: segText.implicitWidth + Style.space(16)
                    implicitHeight: segText.implicitHeight + Style.space(8)
                    radius: Style.space(4)
                    color: seg.on ? root.accentA(0.18) : "transparent"
                    border.width: 1
                    border.color: seg.on ? root.accentA(0.55) : "transparent"
                    Text {
                      id: segText
                      anchors.centerIn: parent
                      text: seg.modelData.t
                      color: seg.on ? root.accent : root.contentForeground
                      opacity: seg.on ? 1 : 0.7
                      font.family: root.monoFamily
                      font.pixelSize: Style.font.bodySmall
                      font.capitalization: Font.SmallCaps
                      font.letterSpacing: 0.4
                      font.bold: seg.on
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.mode = seg.modelData.id
                    }
                  }
                }
              }
            }
            }
            Row {
              id: statRow
              spacing: Style.space(12)
              Stat {
                value: String(root.brain.commit || "----")
                label: root.brain.dirty === true ? "dirty" : "commit"
                hot: root.brain.dirty === true
                family: root.monoFamily
                tone: root.contentForeground
              }
              Stat {
                value: root.pad2(root.brain.links)
                label: "links"
                hot: root.ready && Number(root.brain.links) < Number(root.brain.linksExpected || 3)
                family: root.monoFamily
                tone: root.contentForeground
              }
              Stat {
                value: {
                  var n = 0
                  var tools = root.brain.tools || []
                  for (var i = 0; i < tools.length; i++) if (tools[i].present) n++
                  return root.pad2(n)
                }
                label: "tools"
                family: root.monoFamily
                tone: root.contentForeground
              }
              Stat {
                value: root.service ? String(root.service.barLabel || "—") : "…"
                label: "limit"
                hot: root.service ? root.service.alarming === true : false
                family: root.monoFamily
                tone: root.contentForeground
              }
            }
          }
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: root.accentA(0.7) }
              GradientStop { position: 0.6; color: root.accentA(0.12) }
              GradientStop { position: 1.0; color: root.accentA(0.0) }
            }
          }
        }

        Item {
          id: body
          width: parent.width
          height: Math.max(Style.space(200), parent.height - header.implicitHeight - footer.implicitHeight - Style.space(24))

          Column {
            anchors.fill: parent
            visible: root.mode === "map"
            spacing: Style.space(18)
            Item {
              id: mapFrame
              width: parent.width
              height: Math.max(Style.space(260), parent.height * 0.62)
              Loader {
                id: mapLoader
                anchors.fill: parent
                anchors.margins: Style.space(8)
                source: Qt.resolvedUrl("BrainMap.qml")
                onLoaded: {
                  var map = item
                  map.pillars = Qt.binding(function() { return root.pillars })
                  map.selectedId = Qt.binding(function() { return root.selectedId })
                  map.alarming = Qt.binding(function() { return root.service ? root.service.alarming === true : false })
                  map.active = Qt.binding(function() { return root.opened && root.mode === "map" })
                  map.foreground = Qt.binding(function() { return root.contentForeground })
                  map.accent = Qt.binding(function() { return root.accent })
                  map.background = Qt.binding(function() { return root.cardBackground })
                  map.monoFamily = Qt.binding(function() { return root.monoFamily })
                  map.picked.connect(function(id) { root.selectedId = id })
                }
              }
            }
            Item {
              id: detailPane
              width: parent.width
              height: Math.max(Style.space(120), parent.height - mapFrame.height - Style.space(18))
              Flickable {
                id: detailFlick
                anchors.fill: parent
                anchors.margins: Style.space(12)
                contentWidth: width
                contentHeight: detailCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                  id: detailCol
                  width: detailFlick.width
                  spacing: Style.space(14)
                  SectionHeader {
                    width: parent.width
                    label: root.selectedPillar() ? String(root.selectedPillar().name || "") : "What this is"
                    count: root.selectedPillar() ? "" : root.pad2(root.pillars.length)
                    tone: root.contentForeground
                    family: root.monoFamily
                  }
                  Text {
                    width: parent.width
                    text: {
                      var pillar = root.selectedPillar()
                      if (pillar) return String(pillar.blurb || "")
                      var lines = root.brain.about || []
                      if (lines.length) return lines.join(" ")
                      return "1config is the global brain for Claude, Grok, and OpenCode."
                    }
                    color: root.contentForeground
                    opacity: 0.9
                    font.family: root.proseFamily
                    renderType: Text.NativeRendering
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                  }
                  Repeater {
                    model: root.selectedPillar() ? (root.selectedPillar().points || []) : []
                    Text {
                      required property string modelData
                      width: detailCol.width
                      text: modelData
                      color: root.accent
                      opacity: 0.9
                      font.family: root.monoFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }
                  }
                  Column {
                    width: parent.width
                    visible: !root.selectedPillar()
                    spacing: Style.space(16)
                    Repeater {
                      model: root.pillars
                      Item {
                        id: partRow
                        required property var modelData
                        width: detailCol.width
                        implicitHeight: partCol.implicitHeight
                        Rectangle {
                          x: 0
                          y: 0
                          width: Style.space(2)
                          height: partName.implicitHeight
                          color: partMouse.containsMouse ? root.accent : root.tint(0.25)
                        }
                        Column {
                          id: partCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.leftMargin: Style.space(12)
                          spacing: Style.space(3)
                          Text {
                            id: partName
                            width: parent.width
                            text: String(partRow.modelData.name || "")
                            color: partMouse.containsMouse ? root.accent : root.contentForeground
                            font.family: root.monoFamily
                            font.pixelSize: Style.font.subtitle
                            font.bold: true
                          }
                          Text {
                            width: parent.width
                            text: String(partRow.modelData.blurb || "")
                            color: root.contentForeground
                            opacity: 0.75
                            font.family: root.proseFamily
                            renderType: Text.NativeRendering
                            font.pixelSize: Style.font.body
                            wrapMode: Text.WordWrap
                          }
                        }
                        MouseArea {
                          id: partMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.selectedId = String(partRow.modelData.id || "")
                        }
                      }
                    }
                  }
                  Column {
                    width: parent.width
                    visible: root.selectedId === "usage"
                    spacing: Style.space(8)
                    Repeater {
                      model: root.agents
                      UsageCard { width: detailCol.width }
                    }
                  }
                  Text {
                    visible: root.service && root.service.state === "error"
                    width: parent.width
                    text: String(root.service ? root.service.message : "")
                    color: Color.urgent
                    font.family: root.proseFamily
                    renderType: Text.NativeRendering
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.WordWrap
                  }
                }
              }
            }
          }

          Flickable {
            id: usageFlick
            anchors.fill: parent
            visible: root.mode === "usage"
            contentWidth: width
            contentHeight: usageCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {
              policy: usageFlick.contentHeight > usageFlick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            }
            Column {
              id: usageCol
              width: usageFlick.width
              spacing: Style.space(18)
              SectionHeader {
                width: parent.width
                label: "Spend on this machine"
                count: root.pad2(root.agents.length)
                tone: root.contentForeground
                family: root.monoFamily
              }
              Text {
                width: parent.width
                text: root.service && root.service.note
                  ? String(root.service.note)
                  : "OpenCode Go is rolling, weekly, and monthly. u refreshes the other providers and reads Go again."
                color: root.contentForeground
                opacity: 0.7
                font.family: root.proseFamily
                renderType: Text.NativeRendering
                font.pixelSize: Style.font.body
                wrapMode: Text.WordWrap
              }
              Repeater {
                model: root.agents
                UsageCard { width: usageCol.width }
              }
            }
          }
        }

        Flow {
          id: footer
          width: parent.width
          spacing: Style.space(6)
          Repeater {
            model: [
              { k: "esc", t: "close" },
              { k: "r", t: "re-read" },
              { k: "u", t: "limits" },
              { k: "g", t: "map" },
              { k: "s", t: "spend" },
              { k: "h/l", t: "cycle" }
            ]
            Rectangle {
              id: chip
              required property var modelData
              implicitWidth: chipRow.implicitWidth + Style.space(12)
              implicitHeight: chipRow.implicitHeight + Style.space(6)
              radius: Style.space(4)
              color: root.tint(0.04)
              border.color: root.tint(0.10)
              border.width: 1
              Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: Style.space(5)
                Text {
                  text: chip.modelData.k
                  color: root.accent
                  opacity: 0.9
                  font.family: root.monoFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
                Text {
                  text: chip.modelData.k === "r" && root.service && root.service.loading ? "sync…" : chip.modelData.t
                  color: root.contentForeground
                  opacity: 0.8
                  font.family: root.monoFamily
                  font.pixelSize: Style.font.bodySmall
                  font.capitalization: Font.SmallCaps
                  font.letterSpacing: 0.3
                }
              }
            }
          }
        }
      }
    }
  }
}
