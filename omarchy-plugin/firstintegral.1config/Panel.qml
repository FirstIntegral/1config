import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui

// 1config brain HUD. Vitals say whether this checkout is actually correct.
// Spend is the other view. Rays run only inside the vitals view, and only
// while that view is open. Theme colours only.
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
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color cardBackground: Color.popups.background
  readonly property string proseFamily: "sans-serif"
  readonly property string monoFamily: Style.font.family

  property string mode: "vitals"
  property bool showQuiet: false
  property bool showModels: false
  property bool detailOpen: false
  property string detailTitle: ""
  property string detailNote: ""
  property var detailLines: []

  function open() {
    root.mode = "vitals"
    root.showQuiet = false
    root.detailOpen = false
    root.controller.show()
  }
  // Any show path, including the base Panel open, lands on vitals.
  onOpenedChanged: if (root.opened) {
    root.mode = "vitals"
    root.detailOpen = false
  }
  function close() { root.controller.hide() }
  function openDetail(vitalId) {
    var list = root.brain.vitals || []
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].id) !== String(vitalId)) continue
      var more = list[i].more || []
      if (!more.length) return
      root.detailTitle = String(list[i].name || vitalId)
      root.detailNote = String(list[i].moreNote || "")
      root.detailLines = more
      root.detailOpen = true
      return
    }
  }
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
  // Same tile as Vitals.qml: foreground wash, accent edge. Strong is the
  // warn weight. Fault is urgent, which vitals uses for a failed check.
  function tileFill(strong) {
    return Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, strong ? 0.07 : 0.045)
  }
  function tileEdge(strong, fault) {
    var c = fault ? Color.urgent : root.accent
    return Qt.rgba(c.r, c.g, c.b, (strong || fault) ? 0.8 : 0.28)
  }
  function pad2(n) {
    var v = Math.max(0, Math.round(Number(n) || 0))
    return (v < 10 ? "0" : "") + v
  }
  function clockLabel() {
    var g = service ? String(service.generatedAt || "") : ""
    var m = g.match(/T(\d\d:\d\d)/)
    return m ? m[1] : ""
  }
  function scrollBy(dy) {
    if (root.mode === "vitals") {
      if (vitalsLoader.item) vitalsLoader.item.scrollBy(dy)
      return
    }
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
  function quietCountOf(all) {
    var n = 0
    var list = all || []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].used === false) n++
    }
    return n
  }
  function filterSpend(all, showAll) {
    var list = all || []
    if (showAll) return list
    var kept = []
    for (var i = 0; i < list.length; i++) {
      if (!list[i] || list[i].used === false) continue
      kept.push(list[i])
    }
    return kept
  }
  readonly property int quietCount: quietCountOf(root.agents)
  readonly property var spendAgents: filterSpend(root.agents, root.showQuiet)
  function handleTextKey(t) {
    if (t === "r" || t === "R") root.refresh()
    else if (t === "u" || t === "U") root.refreshLimits()
    else if (t === "v" || t === "V" || t === "g" || t === "G") {
      root.mode = "vitals"
      root.detailOpen = false
    }
    else if (t === "s" || t === "S") {
      root.mode = "usage"
      root.detailOpen = false
    }
    else if (t === "a" || t === "A") root.showQuiet = !root.showQuiet
    else if (t === "m" || t === "M") root.showModels = !root.showModels
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
  readonly property int cardWidth: Math.round(Math.min(Style.space(760), Math.max(Style.space(440), 0.46 * screenW)))
  readonly property int cardHeight: Math.round(Math.min(Style.space(820), Math.max(Style.space(480), 0.68 * screenH)))

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
    implicitHeight: Math.max(Style.space(10), 10)
    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: root.tileFill(true)
    }
    Rectangle {
      width: Math.max(0, Math.min(1, meter.ratio)) * parent.width
      height: parent.height
      radius: height / 2
      color: meter.hot ? root.accent : root.accentA(0.55)
    }
  }

  component UsageCard: Item {
    id: card
    required property var modelData
    readonly property var agent: modelData || ({})
    readonly property bool quiet: agent.used === false
    readonly property var modelRows: agent.models || []
    readonly property real modelPeak: root.peakOf(modelRows, "tokens")
    function hotLimits() {
      if (quiet) return false
      var limits = agent.limits || []
      for (var i = 0; i < limits.length; i++) {
        if ((Number(limits[i].usedPct) || 0) >= 80) return true
      }
      return false
    }
    function faulted() {
      return !quiet && String(agent.status || "") !== ""
    }
    width: parent ? parent.width : implicitWidth
    implicitHeight: cardBox.implicitHeight
    height: implicitHeight

    function rowValue(row) {
      var bits = [String(row.tokenLabel || row.label || "0")]
      if (row.costLabel) bits.push(String(row.costLabel))
      return bits.join("   ")
    }

    Rectangle {
      id: cardBox
      width: card.width
      implicitHeight: cardCol.implicitHeight + Style.space(32)
      height: implicitHeight
      radius: Style.space(6)
      color: root.tileFill(card.hotLimits() || card.faulted())
      border.width: 1
      border.color: root.tileEdge(card.hotLimits(), card.faulted())

      Column {
        id: cardCol
        x: Style.space(16)
        y: Style.space(16)
        width: cardBox.width - Style.space(32)
        spacing: Style.space(12)

        Item {
          width: parent.width
          implicitHeight: cardName.implicitHeight
          Text {
            id: cardName
            text: String(card.agent.name || card.agent.id || "")
            color: root.contentForeground
            opacity: card.quiet ? 0.55 : 1
            font.family: root.proseFamily
            font.pixelSize: Style.font.heading
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
            visible: !card.quiet && text !== ""
            text: String(card.agent.headline || card.agent.weekCostLabel || "")
            color: card.faulted() ? Color.urgent : root.accent
            opacity: (card.hotLimits() || card.faulted()) ? 0.95 : 0.55
            font.family: root.monoFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }
        }

        Text {
          visible: card.quiet
          width: parent.width
          text: String(card.agent.status || (card.agent.present ? "No usage this week" : "Not on this machine"))
          color: root.contentForeground
          opacity: 0.7
          font.family: root.proseFamily
          font.pixelSize: Style.font.title
          wrapMode: Text.WordWrap
        }

        Repeater {
          model: card.quiet ? [] : (card.agent.limits || [])
          delegate: Rectangle {
            id: limitBox
            required property var modelData
            readonly property bool strong: (Number(modelData.usedPct) || 0) >= 80
            width: cardCol.width
            implicitHeight: limitCol.implicitHeight + Style.space(20)
            height: implicitHeight
            radius: Style.space(6)
            color: root.tileFill(strong)
            border.width: 1
            border.color: root.tileEdge(strong, false)
            Column {
              id: limitCol
              x: Style.space(12)
              y: Style.space(10)
              width: parent.width - Style.space(24)
              spacing: Style.space(6)
              Item {
                width: parent.width
                implicitHeight: limitName.implicitHeight
                Text {
                  id: limitName
                  text: String(modelData.label || "Limit")
                  color: root.contentForeground
                  font.family: root.proseFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  anchors.left: parent.left
                  anchors.right: limitPct.left
                  anchors.rightMargin: Style.space(12)
                  elide: Text.ElideRight
                }
                Text {
                  id: limitPct
                  anchors.right: parent.right
                  text: Math.round(Number(modelData.usedPct) || 0) + "% used"
                  color: root.accent
                  opacity: limitBox.strong ? 0.95 : 0.55
                  font.family: root.monoFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
              }
              Meter {
                width: parent.width
                implicitHeight: Math.max(Style.space(10), 10)
                ratio: (Number(modelData.usedPct) || 0) / 100
                hot: Number(modelData.usedPct) >= 80
              }
              Text {
                visible: text !== ""
                width: parent.width
                text: String(modelData.detail || "") !== "" ? String(modelData.detail) : root.resetsIn(modelData.resetsAt)
                color: root.contentForeground
                opacity: 0.7
                font.family: root.proseFamily
                font.pixelSize: Style.font.subtitle
              }
            }
          }
        }

        Column {
          visible: !card.quiet && root.showModels && card.modelRows.length > 0
          width: parent.width
          spacing: Style.space(8)
          Text {
            text: "By model"
            color: root.contentForeground
            font.family: root.proseFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Repeater {
            model: card.modelRows
            delegate: Rectangle {
              required property var modelData
              width: cardCol.width
              implicitHeight: modelCol.implicitHeight + Style.space(18)
              height: implicitHeight
              radius: Style.space(6)
              color: root.tileFill(false)
              border.width: 1
              border.color: root.tileEdge(false, false)
              Column {
                id: modelCol
                x: Style.space(12)
                y: Style.space(10)
                width: parent.width - Style.space(24)
                spacing: Style.space(6)
                Text {
                  width: parent.width
                  text: String(modelData.id || "")
                  color: root.contentForeground
                  font.family: root.proseFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignRight
                  text: card.rowValue(modelData)
                  color: root.accent
                  opacity: 0.55
                  font.family: root.monoFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Meter {
                  width: parent.width
                  implicitHeight: Math.max(Style.space(10), 10)
                  ratio: (Number(modelData.tokens) || 0) / card.modelPeak
                }
              }
            }
          }
        }

        Text {
          visible: !card.quiet && String(card.agent.status || "") !== ""
          width: parent.width
          text: String(card.agent.status || "")
          color: Color.urgent
          font.family: root.proseFamily
          font.pixelSize: Style.font.subtitle
          wrapMode: Text.WordWrap
        }
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
      onCloseRequested: {
        if (root.detailOpen) root.detailOpen = false
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy === 0) return
        root.scrollBy(dy * Style.space(48))
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
                  var verdict = String(root.brain.verdict || "")
                  if (verdict) bits.push(verdict)
                  bits.push(remote)
                  if (branch) bits.push(branch)
                  if (root.brain.dirty === true) bits.push("dirty")
                  if (slip && slip !== "unknown") bits.push(slip)
                  if (clock) bits.push(clock)
                  var msg = root.service ? String(root.service.message || "") : ""
                  var usageError = root.service && root.service.state === "error"
                  if (root.mode !== "vitals" && msg) bits.push(msg)
                  else if (usageError && msg) bits.push(msg)
                  return bits.join("  ·  ")
                }
                color: (root.brain.verdict === "fault" || root.brain.dirty === true) ? root.accent : root.contentForeground
                opacity: (root.brain.verdict === "fault" || root.brain.dirty === true) ? 0.9 : 0.6
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
                  model: [{ id: "vitals", t: "vitals" }, { id: "usage", t: "spend" }]
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
              visible: root.mode === "usage"
              spacing: Style.space(12)
              Stat {
                value: {
                  var verdict = String(root.brain.verdict || "")
                  if (verdict === "clear") return "CLEAR"
                  if (verdict === "warn") return "WARN"
                  if (verdict === "fault") return "FAULT"
                  return "…"
                }
                label: "brain"
                hot: root.brain.verdict === "fault" || root.brain.verdict === "warn"
                family: root.monoFamily
                tone: root.contentForeground
              }
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

          Loader {
            id: vitalsLoader
            anchors.fill: parent
            active: root.mode === "vitals"
            visible: active
            source: Qt.resolvedUrl("Vitals.qml")
            onLoaded: {
              var board = item
              board.groups = Qt.binding(function() { return root.brain.groups || [] })
              board.vitals = Qt.binding(function() { return root.brain.vitals || [] })
              board.verdict = Qt.binding(function() { return String(root.brain.verdict || "") })
              board.active = Qt.binding(function() { return root.opened && root.mode === "vitals" })
              board.foreground = Qt.binding(function() { return root.contentForeground })
              board.accent = Qt.binding(function() { return root.accent })
              board.background = Qt.binding(function() { return root.cardBackground })
              board.proseFamily = Qt.binding(function() { return root.proseFamily })
              board.monoFamily = Qt.binding(function() { return root.monoFamily })
              board.detailRequested.connect(function(vitalId) { root.openDetail(vitalId) })
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
              Text {
                width: parent.width
                text: "Spend"
                color: root.contentForeground
                font.family: root.proseFamily
                font.pixelSize: Style.font.display
                font.bold: true
              }
              Text {
                width: parent.width
                text: root.service && root.service.note
                  ? String(root.service.note)
                  : "Each tool is its own box. a shows quiet tools. By model starts off."
                color: root.contentForeground
                opacity: 0.8
                font.family: root.proseFamily
                font.pixelSize: Style.font.title
                wrapMode: Text.WordWrap
              }
              Row {
                spacing: Style.space(8)
                Rectangle {
                  visible: root.quietCount > 0
                  width: quietLabel.implicitWidth + Style.space(36)
                  implicitHeight: quietLabel.implicitHeight + Style.space(16)
                  height: implicitHeight
                  radius: Style.space(6)
                  color: root.showQuiet ? root.accentA(0.18) : root.tileFill(false)
                  border.width: 1
                  border.color: root.showQuiet ? root.tileEdge(true, false) : root.tileEdge(false, false)
                  Text {
                    id: quietLabel
                    anchors.centerIn: parent
                    text: root.showQuiet ? "Used only" : ("Show " + root.quietCount + " not in use")
                    color: root.contentForeground
                    font.family: root.proseFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showQuiet = !root.showQuiet
                  }
                }
                Rectangle {
                  width: modelToggleLabel.implicitWidth + Style.space(36)
                  implicitHeight: modelToggleLabel.implicitHeight + Style.space(16)
                  height: implicitHeight
                  radius: Style.space(6)
                  color: root.showModels ? root.accentA(0.18) : root.tileFill(false)
                  border.width: 1
                  border.color: root.showModels ? root.tileEdge(true, false) : root.tileEdge(false, false)
                  Text {
                    id: modelToggleLabel
                    anchors.centerIn: parent
                    text: "By model"
                    color: root.contentForeground
                    opacity: root.showModels ? 1 : 0.7
                    font.family: root.proseFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showModels = !root.showModels
                  }
                }
              }
              Text {
                visible: root.ready && root.spendAgents.length === 0
                width: parent.width
                text: "No usage on this machine this week."
                color: root.contentForeground
                opacity: 0.75
                font.family: root.proseFamily
                font.pixelSize: Style.font.title
                wrapMode: Text.WordWrap
              }
              Repeater {
                model: root.spendAgents
                UsageCard { width: usageCol.width }
              }
            }
          }

          // Click-through detail: slip lines, uncommitted files. Covers the
          // vitals board only; esc (or a click) goes back.
          Rectangle {
            id: detailLayer
            anchors.fill: parent
            visible: root.detailOpen
            z: 10
            radius: Style.space(6)
            color: root.cardBackground
            border.width: 1
            border.color: root.tileEdge(true, false)

            MouseArea {
              anchors.fill: parent
              onClicked: root.detailOpen = false
            }

            Column {
              id: detailCol
              anchors.fill: parent
              anchors.margins: Style.space(16)
              spacing: Style.space(8)

              Text {
                id: detailTitleText
                width: parent.width
                text: root.detailTitle
                color: root.contentForeground
                font.family: root.proseFamily
                font.pixelSize: Style.font.heading
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                id: detailNoteText
                visible: text !== ""
                width: parent.width
                text: root.detailNote
                color: root.contentForeground
                opacity: 0.7
                font.family: root.proseFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
              Flickable {
                id: detailFlick
                width: parent.width
                height: Math.max(Style.space(60),
                  detailCol.height - detailTitleText.implicitHeight
                    - (detailNoteText.visible ? detailNoteText.implicitHeight + detailCol.spacing : 0)
                    - detailEscText.implicitHeight - detailCol.spacing * 2)
                contentWidth: width
                contentHeight: detailLinesCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {
                  policy: detailFlick.contentHeight > detailFlick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                }
                Column {
                  id: detailLinesCol
                  width: detailFlick.width
                  spacing: Style.space(4)
                  Repeater {
                    model: root.detailLines
                    delegate: Text {
                      required property var modelData
                      width: detailLinesCol.width
                      text: String(modelData)
                      color: root.contentForeground
                      opacity: 0.92
                      wrapMode: Text.WordWrap
                      font.family: root.monoFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                  }
                }
              }
              Text {
                id: detailEscText
                width: parent.width
                text: root.detailTitle !== "" ? "esc or click  ·  back" : ""
                color: root.accent
                opacity: 0.8
                font.family: root.monoFamily
                font.pixelSize: Style.font.bodySmall
                font.capitalization: Font.SmallCaps
                font.letterSpacing: 0.3
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
              { k: "esc", t: "close", spend: false },
              { k: "r", t: "re-read", spend: false },
              { k: "s", t: "spend", spend: false },
              { k: "v", t: "vitals", spend: false },
              { k: "u", t: "limits", spend: true },
              { k: "a", t: "all", spend: true },
              { k: "m", t: "models", spend: true }
            ]
            Rectangle {
              id: chip
              required property var modelData
              visible: !modelData.spend || root.mode === "usage"
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
                  text: {
                    if (chip.modelData.k === "r" && root.service && root.service.loading) return "sync…"
                    if (chip.modelData.k === "esc" && root.detailOpen) return "back"
                    if (chip.modelData.k === "a") return root.showQuiet ? "used" : "quiet"
                    if (chip.modelData.k === "m") return root.showModels ? "on" : "off"
                    return chip.modelData.t
                  }
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
