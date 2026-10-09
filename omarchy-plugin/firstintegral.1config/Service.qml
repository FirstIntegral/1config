import QtQuick
import Quickshell
import Quickshell.Io

// Headless reader for the 1config usage snapshot. Runs bin/usage.py on a timer.
// Read-only on the timer: that script does not call a provider. The panel's
// `u` key is the only path that runs omarchy-agent-usage-update.
Item {
  id: root

  property var shell: null
  property var settings: ({})

  property bool ready: false
  property bool loading: false
  property string state: "loading"
  property string message: "Reading usage…"
  property string barLabel: "…"
  property bool alarming: false
  property var tooltipLines: []
  property var agents: []
  property string generatedAt: ""
  property string hostname: ""
  property string note: ""
  property var brain: ({})
  property int revision: 0
  property string _stdout: ""
  property string _stderr: ""

  readonly property string scriptPath: {
    var home = String(Quickshell.env("HOME") || "")
    return home + "/.config/omarchy/plugins/firstintegral.1config/bin/usage.py"
  }

  readonly property int refreshIntervalSec: {
    var value = parseInt(String(setting("refreshIntervalSec", 120)), 10)
    if (!isFinite(value)) value = 120
    return Math.max(30, Math.min(3600, value))
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function refresh() {
    if (fetchProcess.running) return
    loading = true
    _stdout = ""
    _stderr = ""
    fetchProcess.command = ["python3", root.scriptPath]
    fetchProcess.running = true
  }

  function refreshLimits() {
    if (limitsProcess.running) return
    message = "Asking Omarchy for provider limits…"
    limitsProcess.running = true
  }

  function apply(raw) {
    try {
      var data = JSON.parse(String(raw || ""))
      var bar = data.bar || {}
      agents = Array.isArray(data.agents) ? data.agents : []
      barLabel = String(bar.label || "—")
      alarming = bar.alarm === true
      tooltipLines = Array.isArray(data.tooltip) ? data.tooltip : []
      generatedAt = String(data.generatedAt || "")
      hostname = String(data.hostname || "")
      note = String(data.note || "")
      brain = data.brain && typeof data.brain === "object" ? data.brain : {}
      ready = true
      state = "ready"
      message = ""
      revision++
    } catch (error) {
      state = "error"
      message = "usage snapshot unreadable"
    }
  }

  function tooltipText() {
    if (!ready && state === "error") return "1config · " + message
    if (!ready) return "1config · reading…"
    var lines = ["1config · " + hostname]
    for (var i = 0; i < tooltipLines.length; i++) lines.push(String(tooltipLines[i]))
    return lines.join("\n")
  }

  visible: false

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: fetchProcess
    running: false
    command: []
    onExited: function(exitCode) {
      root.loading = false
      var stdout = String(output.text || root._stdout || "")
      var stderr = String(errors.text || root._stderr || "").trim()
      if (exitCode === 0 && stdout.trim() !== "") {
        root.apply(stdout)
      } else {
        root.state = "error"
        root.message = stderr !== "" ? stderr.split("\n").slice(-1)[0] : "usage.py failed (exit " + exitCode + ")"
      }
    }
    stdout: StdioCollector {
      id: output
      waitForEnd: true
      onStreamFinished: root._stdout = text
    }
    stderr: StdioCollector {
      id: errors
      waitForEnd: true
      onStreamFinished: root._stderr = text
    }
  }

  Process {
    id: limitsProcess
    running: false
    command: ["omarchy-agent-usage-update", "--limits-only"]
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var stderr = String(limitErrors.text || "").trim()
        root.message = stderr !== "" ? stderr.split("\n").slice(-1)[0] : "limit refresh failed (exit " + exitCode + ")"
      }
      root.refresh()
    }
    stderr: StdioCollector {
      id: limitErrors
      waitForEnd: true
    }
  }
}
