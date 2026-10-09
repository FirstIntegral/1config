import QtQuick
import QtQuick.Shapes
import qs.Commons

// Static ring of what 1config is. Centre is the brain. Six parts sit on
// the orbit. No force simulation: positions are a function of size.
// The 30 fps clock runs only while active (panel open and map mode).
// The canvas repaints on size, theme, hover, or selection. The sweep is
// a Shape, so the clock does not repaint the canvas.
Item {
  id: root

  property var pillars: []
  property string selectedId: ""
  property bool alarming: false
  property bool active: false
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color background: Color.popups.background
  property string monoFamily: Style.font.family

  signal picked(string id)

  property real phase: 0
  property int hoverIndex: -1

  readonly property real cx: width / 2
  readonly property real cy: height / 2
  readonly property real orbitR: Math.max(48, Math.min(width / 2 - 108, height / 2 - 56))
  readonly property int nodeCount: 1 + (pillars ? pillars.length : 0)

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function css(c, a) {
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")"
  }

  function nodeAt(i) {
    if (i <= 0) return { x: 0, y: 0, r: 11, lead: true, id: "core", name: "1config", hot: false }
    var n = Math.max(1, root.pillars.length)
    var pillar = root.pillars[i - 1] || {}
    var angle = -Math.PI / 2 + (i - 1) * (Math.PI * 2 / n)
    return {
      x: Math.cos(angle) * root.orbitR,
      y: Math.sin(angle) * root.orbitR,
      r: 6.5,
      lead: false,
      id: String(pillar.id || ""),
      name: String(pillar.name || ""),
      hot: String(pillar.id || "") === "usage" && root.alarming
    }
  }

  function haloText(ctx, text, x, y, color) {
    ctx.lineWidth = 3
    ctx.strokeStyle = root.css(root.background, 0.85)
    ctx.strokeText(text, x, y)
    ctx.fillStyle = color
    ctx.fillText(text, x, y)
  }

  Timer {
    interval: 33
    repeat: true
    running: root.active && root.visible
    onTriggered: root.phase += interval / 1000
  }

  Canvas {
    id: field
    anchors.fill: parent
    property color fg: root.foreground
    property color ac: root.accent
    property string sel: root.selectedId
    property int hov: root.hoverIndex
    property int rev: root.pillars ? root.pillars.length : 0
    property bool hot: root.alarming
    onFgChanged: requestPaint()
    onAcChanged: requestPaint()
    onSelChanged: requestPaint()
    onHovChanged: requestPaint()
    onRevChanged: requestPaint()
    onHotChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var W = width
      var H = height
      var X = root.cx
      var Y = root.cy
      var orbit = root.orbitR
      if (W < 8 || H < 8) return
      var fg = field.fg
      var ac = field.ac
      var hasSel = root.selectedId !== ""

      ctx.lineWidth = 1
      ctx.strokeStyle = root.css(fg, 0.10)
      ctx.beginPath()
      ctx.arc(X, Y, orbit, 0, Math.PI * 2)
      ctx.stroke()

      var count = root.nodeCount
      for (var e = 1; e < count; e++) {
        var end = root.nodeAt(e)
        var dim = hasSel && end.id !== root.selectedId
        var lit = hasSel && end.id === root.selectedId
        var base = dim ? 0.08 : (lit ? 0.78 : 0.22)
        var col = end.hot || lit ? ac : fg
        var layers = lit && !dim ? [[4, 0.12], [1.5, 1]] : [[1, 1]]
        for (var l = 0; l < layers.length; l++) {
          ctx.lineWidth = layers[l][0]
          ctx.strokeStyle = root.css(col, base * layers[l][1])
          ctx.beginPath()
          ctx.moveTo(X, Y)
          ctx.lineTo(X + end.x, Y + end.y)
          ctx.stroke()
        }
      }

      ctx.font = "11px " + root.monoFamily
      ctx.textBaseline = "middle"
      for (var i = 0; i < count; i++) {
        var node = root.nodeAt(i)
        var nx = X + node.x
        var ny = Y + node.y
        var fade = (hasSel && !node.lead && node.id !== root.selectedId) ? 0.35 : 1
        var tone = node.hot ? ac : fg
        if (node.lead) {
          ctx.beginPath()
          ctx.arc(nx, ny, node.r + 3.5, 0, Math.PI * 2)
          ctx.lineWidth = 1
          ctx.strokeStyle = root.css(ac, 0.45)
          ctx.stroke()
          ctx.beginPath()
          ctx.arc(nx, ny, node.r, 0, Math.PI * 2)
          ctx.fillStyle = root.css(ac, 0.30)
          ctx.fill()
          ctx.lineWidth = 1.2
          ctx.strokeStyle = root.css(ac, 0.95)
          ctx.stroke()
        } else {
          ctx.beginPath()
          for (var k = 0; k < 6; k++) {
            var ha = -Math.PI / 2 + k * Math.PI / 3
            var px = nx + Math.cos(ha) * node.r
            var py = ny + Math.sin(ha) * node.r
            if (k === 0) ctx.moveTo(px, py)
            else ctx.lineTo(px, py)
          }
          ctx.closePath()
          ctx.fillStyle = root.css(tone, (node.hot ? 0.30 : 0.12) * fade)
          ctx.fill()
          ctx.lineWidth = 1.2
          ctx.strokeStyle = root.css(tone, 0.95 * fade)
          ctx.stroke()
          ctx.beginPath()
          ctx.arc(nx, ny, 1.6, 0, Math.PI * 2)
          ctx.fillStyle = root.css(tone, fade)
          ctx.fill()
        }
        if (node.id === root.selectedId) {
          ctx.beginPath()
          ctx.arc(nx, ny, node.r + 6, 0, Math.PI * 2)
          ctx.lineWidth = 1.4
          ctx.strokeStyle = root.css(ac, 0.95)
          ctx.stroke()
        } else if (i === root.hoverIndex) {
          ctx.beginPath()
          ctx.arc(nx, ny, node.r + 4.5, 0, Math.PI * 2)
          ctx.lineWidth = 1
          ctx.strokeStyle = root.css(fg, 0.6)
          ctx.stroke()
        }
        if (!node.lead) {
          var label = node.name
          var ux = node.x / (orbit || 1)
          var uy = node.y / (orbit || 1)
          var lx = nx + ux * (node.r + 22)
          var ly = ny + uy * (node.r + 22)
          ctx.textAlign = Math.abs(ux) < 0.35 ? "center" : (ux > 0 ? "left" : "right")
          root.haloText(ctx, label, lx, ly, root.css(tone, 0.82 * fade))
        }
      }
    }
  }

  Shape {
    id: sweep
    width: Math.max(8, root.orbitR * 2)
    height: width
    x: root.cx - width / 2
    y: root.cy - height / 2
    visible: root.active && root.nodeCount > 1
    opacity: 0.10
    rotation: (root.phase * 14) % 360
    ShapePath {
      strokeWidth: 0
      strokeColor: "transparent"
      fillGradient: ConicalGradient {
        centerX: sweep.width / 2
        centerY: sweep.height / 2
        angle: 0
        GradientStop { position: 0.0; color: root.alpha(root.accent, 0.9) }
        GradientStop { position: 0.10; color: root.alpha(root.accent, 0.0) }
        GradientStop { position: 1.0; color: root.alpha(root.accent, 0.0) }
      }
      startX: sweep.width / 2
      startY: sweep.height / 2
      PathAngleArc {
        centerX: sweep.width / 2
        centerY: sweep.height / 2
        radiusX: sweep.width / 2
        radiusY: sweep.height / 2
        startAngle: 0
        sweepAngle: 360
      }
    }
  }

  Repeater {
    model: root.active && root.alarming ? 1 : 0
    Rectangle {
      readonly property var usage: {
        for (var i = 1; i < root.nodeCount; i++) {
          var node = root.nodeAt(i)
          if (node.hot) return node
        }
        return null
      }
      readonly property real wave: (root.phase * 0.55) % 1
      visible: usage !== null
      width: usage ? (usage.r + 2 + wave * 10) * 2 : 0
      height: width
      radius: width / 2
      x: usage ? root.cx + usage.x - width / 2 : 0
      y: usage ? root.cy + usage.y - height / 2 : 0
      color: "transparent"
      border.width: 1
      border.color: root.accent
      opacity: (1 - wave) * 0.55
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.hoverIndex > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
    onPositionChanged: function(mouse) { root.hoverIndex = root.hit(mouse.x, mouse.y) }
    onExited: root.hoverIndex = -1
    onClicked: function(mouse) {
      var hit = root.hit(mouse.x, mouse.y)
      if (hit <= 0) root.picked("")
      else root.picked(root.nodeAt(hit).id)
    }
  }

  function hit(x, y) {
    var best = -1
    var bestD = 22 * 22
    for (var i = 0; i < root.nodeCount; i++) {
      var node = root.nodeAt(i)
      var dx = x - (root.cx + node.x)
      var dy = y - (root.cy + node.y)
      var d = dx * dx + dy * dy
      var reach = (node.r + 12) * (node.r + 12)
      if (d <= reach && d < bestD) {
        best = i
        bestD = d
      }
    }
    return best
  }
}
