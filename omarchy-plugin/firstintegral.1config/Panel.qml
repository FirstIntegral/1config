import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui

// 1config brain HUD. The map is what this repo is. Usage is one part of it.
// Design tokens follow Projects/skills/brain-hud-design (the brwsk.brain look):
// theme colours only, accent for signal, grid painted once, sweep only while open.
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
  readonly property int cardWidth: Math.round(Math.min(Style.space(560), Math.max(Style.space(360), 0.34 * screenW)))
  readonly property int cardHeight: Math.round(Math.min(Style.space(720), Math.max(Style.space(420), 0.62 * screenH)))

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
      font.pixelSize: Style.font.bodySmall
      font.capitalization: Font.SmallCaps
      font.letterSpacing: 1.8
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
      font.pixelSize: Style.font.bodySmall
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
      font.pixelSize: Style.font.body
      font.weight: Font.Light
      font.letterSpacing: 0.5
    }
    Text {
      text: st.label
      color: st.hot ? Color.accent : st.tone
      opacity: st.hot ? 0.85 : 0.5
      font.family: st.family
      font.pixelSize: Style.font.caption
      font.capitalization: Font.SmallCaps
      font.letterSpacing: 1.4
    }
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
      color: meter.hot ? root.accent : root.tint(0.55)
    }
  }

  component UsageCard: Rectangle {
    id: card
    required property var modelData
    readonly property var agent: modelData || ({})
    width: parent ? parent.width : implicitWidth
    implicitHeight: cardBody.implicitHeight + Style.space(16)
    radius: Style.space(6)
    color: root.tint(0.02)
    border.width: 1
    border.color: root.tint(0.07)
    Column {
      id: cardBody
      x: Style.space(10)
      y: Style.space(8)
      width: parent.width - Style.space(20)
      spacing: Style.space(4)
      Row {
        width: parent.width
        spacing: Style.space(8)
        Text {
          text: String(card.agent.name || card.agent.id || "")
          color: root.contentForeground
          font.family: root.monoFamily
          font.pixelSize: Style.font.body
          font.capitalization: Font.SmallCaps
          font.letterSpacing: 1.2
          font.bold: true
        }
        Text {
          text: {
            var bits = []
            var limits = card.agent.limits || []
            for (var i = 0; i < limits.length; i++) {
              var used = Number(limits[i].usedPct)
              if (!isNaN(used)) bits.push(Math.round(used) + "%")
            }
            return bits.join("  ")
          }
          color: {
            var hot = false
            var limits = card.agent.limits || []
            for (var i = 0; i < limits.length; i++) if (Number(limits[i].usedPct) >= 80) hot = true
            return hot ? root.accent : root.contentForeground
          }
          font.family: root.monoFamily
          font.pixelSize: Style.font.body
        }
      }
      Text {
        width: parent.width
        text: "today " + String(card.agent.todayLabel || "—") + "   ·   7d " + String(card.agent.weekLabel || "—")
          + (card.agent.costLabel ? "   ·   " + String(card.agent.costLabel) : "")
        color: root.contentForeground
        opacity: 0.85
        font.family: root.monoFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
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
        font.family: root.proseFamily
        renderType: Text.NativeRendering
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
        font.family: root.proseFamily
        renderType: Text.NativeRendering
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
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
          ctx.lineWidth = 1
          ctx.strokeStyle = css(fg, 0.035)
          ctx.beginPath()
          var step = 18
          for (var x = 0.5; x < W; x += step) { ctx.moveTo(x, 0); ctx.lineTo(x, H) }
          for (var y = 0.5; y < H; y += step) { ctx.moveTo(0, y); ctx.lineTo(W, y) }
          ctx.stroke()
          ctx.strokeStyle = css(fg, 0.018)
          ctx.beginPath()
          for (var s = 1.5; s < H; s += 3) { ctx.moveTo(0, s); ctx.lineTo(W, s) }
          ctx.stroke()
        }
      }

      Column {
        anchors.fill: parent
        spacing: Style.space(8)

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
                font.pixelSize: Style.font.body
                font.capitalization: Font.SmallCaps
                font.letterSpacing: 2.2
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
                font.pixelSize: Style.font.caption
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
                      font.pixelSize: Style.font.caption
                      font.capitalization: Font.SmallCaps
                      font.letterSpacing: 1.2
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
                label: "spend"
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
            spacing: Style.space(8)
            Rectangle {
              id: mapFrame
              width: parent.width
              height: Math.max(Style.space(140), parent.height * 0.46)
              radius: Style.space(6)
              color: root.tint(0.02)
              border.width: 1
              border.color: root.tint(0.07)
              Loader {
                id: mapLoader
                anchors.fill: parent
                anchors.margins: Style.space(4)
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
            Rectangle {
              id: detailPane
              width: parent.width
              height: Math.max(Style.space(80), parent.height - mapFrame.height - Style.space(8))
              radius: Style.space(6)
              color: root.tint(0.02)
              border.width: 1
              border.color: root.tint(0.07)
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
                  spacing: Style.space(8)
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
                    font.pixelSize: Style.font.bodySmall
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
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }
                  Column {
                    width: parent.width
                    visible: !root.selectedPillar()
                    spacing: Style.space(6)
                    Repeater {
                      model: root.pillars
                      Rectangle {
                        id: partCard
                        required property var modelData
                        width: detailCol.width
                        implicitHeight: partCol.implicitHeight + Style.space(12)
                        radius: Style.space(5)
                        color: partMouse.containsMouse ? root.accentA(0.12) : root.accentA(0.05)
                        border.width: 1
                        border.color: root.accentA(0.30)
                        Rectangle {
                          width: Style.space(2)
                          anchors.left: parent.left
                          anchors.top: parent.top
                          anchors.bottom: parent.bottom
                          anchors.margins: 1
                          color: root.accentA(0.8)
                        }
                        Column {
                          id: partCol
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.leftMargin: Style.space(10)
                          anchors.rightMargin: Style.space(10)
                          anchors.top: parent.top
                          anchors.topMargin: Style.space(6)
                          spacing: Style.space(2)
                          Text {
                            width: parent.width
                            text: String(partCard.modelData.name || "")
                            color: root.accent
                            font.family: root.monoFamily
                            font.pixelSize: Style.font.caption
                            font.bold: true
                            font.capitalization: Font.SmallCaps
                            font.letterSpacing: 1.2
                          }
                          Text {
                            width: parent.width
                            text: String(partCard.modelData.blurb || "")
                            color: root.contentForeground
                            font.family: root.proseFamily
                            renderType: Text.NativeRendering
                            font.pixelSize: Style.font.bodySmall
                            wrapMode: Text.WordWrap
                          }
                        }
                        MouseArea {
                          id: partMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.selectedId = String(partCard.modelData.id || "")
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
                    font.pixelSize: Style.font.caption
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
              spacing: Style.space(8)
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
                  : "Timer reads this machine only. u asks Omarchy to refresh provider limits."
                color: root.contentForeground
                opacity: 0.7
                font.family: root.proseFamily
                renderType: Text.NativeRendering
                font.pixelSize: Style.font.bodySmall
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
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                Text {
                  text: chip.modelData.k === "r" && root.service && root.service.loading ? "sync…" : chip.modelData.t
                  color: root.contentForeground
                  opacity: 0.8
                  font.family: root.monoFamily
                  font.pixelSize: Style.font.caption
                  font.capitalization: Font.SmallCaps
                  font.letterSpacing: 1
                }
              }
            }
          }
        }
      }
    }
  }
}
