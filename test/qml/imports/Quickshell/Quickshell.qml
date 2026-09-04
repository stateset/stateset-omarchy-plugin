pragma Singleton
import QtQml

QtObject {
  property var detachedCommands: []

  function env(name) {
    if (name === "HOME") return "/tmp/stateset-qml-test-home"
    if (name === "XDG_STATE_HOME") return "/tmp/stateset-qml-test-state"
    return ""
  }

  function execDetached(command) {
    var next = detachedCommands.slice()
    next.push(command)
    detachedCommands = next
  }

  function reset() {
    detachedCommands = []
  }
}
