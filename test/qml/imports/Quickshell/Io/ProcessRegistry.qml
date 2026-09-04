pragma Singleton
import QtQml

QtObject {
  property var processes: []

  function add(process) {
    var next = processes.slice()
    next.push(process)
    processes = next
  }

  function remove(process) {
    var next = []
    for (var index = 0; index < processes.length; index += 1) {
      if (processes[index] !== process) next.push(processes[index])
    }
    processes = next
  }
}
