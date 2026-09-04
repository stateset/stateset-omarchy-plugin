#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
omarchy_path=${OMARCHY_PATH:-}
[[ -n $omarchy_path && -f $omarchy_path/shell/shell.qml && -f $omarchy_path/config/omarchy/shell.json ]] || {
  echo "OMARCHY_PATH must point to a complete Omarchy checkout" >&2
  exit 2
}

runtime_root=$(mktemp -d /tmp/stateset-headless-e2e.XXXXXX)
shell_pid=""
weston_pid=""
cleanup() {
  set +e
  [[ -n $shell_pid ]] && kill "$shell_pid" 2>/dev/null
  [[ -n $weston_pid ]] && kill "$weston_pid" 2>/dev/null
  wait "$shell_pid" "$weston_pid" 2>/dev/null
  rm -rf "$runtime_root"
}
trap cleanup EXIT INT TERM HUP

export HOME="$runtime_root/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_RUNTIME_DIR="$runtime_root/runtime"
export XDG_STATE_HOME="$runtime_root/state"
export WAYLAND_DISPLAY=wayland-stateset
export QT_QPA_PLATFORM=wayland
export QT_QUICK_BACKEND=software
export OMARCHY_PATH="$omarchy_path"
export STATESET_DEMO_STATE_DIR="$runtime_root/controller-state"
export PATH="$repo_root/demo/bin:$omarchy_path/bin:$PATH"

mkdir -p "$XDG_CONFIG_HOME/omarchy/plugins" "$XDG_RUNTIME_DIR" "$XDG_STATE_HOME"
chmod 700 "$XDG_RUNTIME_DIR" "$XDG_STATE_HOME"
rsync -a --delete --exclude '.git/' "$repo_root/" "$XDG_CONFIG_HOME/omarchy/plugins/com.stateset.icommerce/"
jq '.bar.layout.right = [{"id":"com.stateset.icommerce"}]' \
  "$omarchy_path/config/omarchy/shell.json" >"$XDG_CONFIG_HOME/omarchy/shell.json"

weston --backend=headless-backend.so --socket="$WAYLAND_DISPLAY" --idle-time=0 \
  >"$runtime_root/weston.log" 2>&1 &
weston_pid=$!
for _ in $(seq 1 100); do
  [[ -S $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY ]] && break
  sleep 0.1
done
[[ -S $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY ]] || {
  echo "Headless Wayland compositor did not start" >&2
  exit 1
}

ipc() {
  quickshell ipc -n -p "$omarchy_path/shell" --any-display call -- "$@"
}

launch_shell() {
  export STATESET_DEMO_SCENARIO=$1
  quickshell -p "$omarchy_path/shell" >"$runtime_root/quickshell-$1.log" 2>&1 &
  shell_pid=$!
}

wait_for_status() {
  local expression=$1 value=""
  for _ in $(seq 1 200); do
    value=$(ipc com.stateset.icommerce status 2>/dev/null || true)
    if [[ -n $value ]] && jq -e "$expression" >/dev/null 2>&1 <<<"$value"; then
      printf '%s\n' "$value"
      return 0
    fi
    kill -0 "$shell_pid" 2>/dev/null || break
    sleep 0.1
  done
  echo "Plugin status did not satisfy: $expression" >&2
  echo "Last plugin status: ${value:-<none>}" >&2
  quickshell ipc -n -p "$omarchy_path/shell" --any-display show >&2 || true
  ipc shell listPlugins >&2 || true
  sed -n '1,240p' "$runtime_root/quickshell-$STATESET_DEMO_SCENARIO.log" >&2
  return 1
}

launch_shell healthy
healthy=$(wait_for_status '.ready == true and .refreshing == false')
contract=$(<"$repo_root/contract.json")
if ! jq -e --argjson contract "$contract" '
  .configured == true and .stale == false and .counts.orders == 248
  and .controller.version == $contract.controllerVersion
  and .controller.capabilities == $contract.capabilities
' >/dev/null <<<"$healthy"; then
  echo "Healthy IPC contract assertion failed: $healthy" >&2
  exit 1
fi
ipc com.stateset.icommerce open >/dev/null
ipc com.stateset.icommerce close >/dev/null

state_dir="$XDG_STATE_HOME/stateset-icommerce"
for state_file in notifications.json snapshot.json; do
  secure_mode=""
  for _ in $(seq 1 20); do
    if [[ -f $state_dir/$state_file ]]; then
      secure_mode=$(stat -c '%a' "$state_dir/$state_file")
      [[ $secure_mode == 600 ]] && break
    fi
    sleep 0.1
  done
  [[ -f $state_dir/$state_file ]] || { echo "Missing state file: $state_file" >&2; exit 1; }
  [[ $secure_mode == 600 ]] || {
    echo "Unsafe state file mode: $state_file" >&2
    exit 1
  }
done

quickshell kill -p "$omarchy_path/shell" --any-display >/dev/null
wait "$shell_pid" 2>/dev/null || true
shell_pid=""
launch_shell controller-missing
restored=$(wait_for_status '.refreshing == false and .snapshotRestored == true')
if ! jq -e '
  .ready == false and .stale == true and .hasSnapshot == true
  and .failureKind == "controller-missing" and .counts.orders == 248
' >/dev/null <<<"$restored"; then
  echo "Restored IPC contract assertion failed: $restored" >&2
  exit 1
fi

echo "StateSet headless Omarchy shell E2E passed"
