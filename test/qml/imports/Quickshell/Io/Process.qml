import QtQml

QtObject {
  id: root

  property bool running: false
  property var command: []
  property var stdout: null
  property var stderr: null
  property var signals: []

  signal started()
  signal exited(int exitCode)

  onRunningChanged: if (running) started()

  function signal(value) {
    var next = signals.slice()
    next.push(value)
    signals = next
  }

  function complete(exitCode, stdoutText, stderrText) {
    if (stdout) stdout.read(String(stdoutText || ""))
    if (stderr) stderr.read(String(stderrText || ""))
    running = false
    exited(exitCode)
  }

  Component.onCompleted: ProcessRegistry.add(root)
  Component.onDestruction: ProcessRegistry.remove(root)
}
