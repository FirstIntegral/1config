import QtQuick
import qs.Commons

// One circle, one numeral, three nodes. The mark for 1config:
// one config on this machine, three tools on the circle.
// Colours come from the caller so the mark follows the theme.
Item {
  id: root
  property color color: Color.accent
  property string family: Style.font.family
  implicitWidth: Style.space(18)
  implicitHeight: implicitWidth

  Canvas {
    id: field
    anchors.fill: parent
    property color ink: root.color
    onInkChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width
      var h = height
      var cx = w / 2
      var cy = h / 2
      var r = Math.max(4, Math.min(w, h) / 2 - 1.25)
      function css(a) {
        return "rgba(" + Math.round(ink.r * 255) + "," + Math.round(ink.g * 255) + "," + Math.round(ink.b * 255) + "," + a + ")"
      }
      ctx.lineWidth = Math.max(1, r * 0.08)
      ctx.strokeStyle = css(0.9)
      ctx.beginPath()
      ctx.arc(cx, cy, r, 0, Math.PI * 2)
      ctx.stroke()
      var nodes = [-Math.PI / 2, Math.PI / 6, 5 * Math.PI / 6]
      ctx.fillStyle = css(1)
      for (var i = 0; i < nodes.length; i++) {
        ctx.beginPath()
        ctx.arc(cx + Math.cos(nodes[i]) * r, cy + Math.sin(nodes[i]) * r, Math.max(1.2, r * 0.12), 0, Math.PI * 2)
        ctx.fill()
      }
      ctx.fillStyle = css(0.95)
      ctx.font = "bold " + Math.max(7, Math.round(r * 0.9)) + "px \"" + root.family + "\""
      ctx.textAlign = "center"
      ctx.textBaseline = "middle"
      ctx.fillText("1", cx, cy + r * 0.06)
    }
  }
}
