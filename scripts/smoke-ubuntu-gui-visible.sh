#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
timeout_seconds="${LOGIC_RIPPER_GUI_SMOKE_SECONDS:-5}"
screenshot_path="${LOGIC_RIPPER_GUI_SCREENSHOT:-$repo_root/artifacts/logic-ripper-gui-visible.png}"

if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    echo "FAIL: no graphical session detected. This looks like headless SSH; enable X forwarding or run inside Ubuntu Desktop." >&2
  else
    echo "FAIL: no graphical session detected. DISPLAY and WAYLAND_DISPLAY are both missing." >&2
  fi
  exit 2
fi

launcher="${LOGIC_RIPPER_GUI:-}"
if [[ -z "$launcher" ]]; then
  if command -v logic-ripper-gui >/dev/null 2>&1; then
    launcher="$(command -v logic-ripper-gui)"
  elif [[ -x "$repo_root/artifacts/LogicRipper.Gui-linux-x64/LogicRipper.Gui" ]]; then
    launcher="$repo_root/artifacts/LogicRipper.Gui-linux-x64/LogicRipper.Gui"
  else
    echo "FAIL: cannot find logic-ripper-gui or artifacts/LogicRipper.Gui-linux-x64/LogicRipper.Gui." >&2
    echo "Run: bash ./scripts/install-ubuntu.sh" >&2
    exit 1
  fi
fi

if [[ ! -x "$launcher" ]]; then
  echo "FAIL: GUI launcher is not executable: $launcher" >&2
  exit 1
fi

if ! "$launcher" --version >/tmp/logic-ripper-gui-visible-version.txt 2>&1; then
  echo "FAIL: GUI version command failed." >&2
  cat /tmp/logic-ripper-gui-visible-version.txt >&2
  exit 1
fi

if command -v logic-ripper >/dev/null 2>&1; then
  export LOGIC_RIPPER_CLI="$(command -v logic-ripper)"
fi

log_path="$(mktemp -t logic-ripper-gui-visible.XXXXXX.log)"
"$launcher" >"$log_path" 2>&1 &
gui_pid=$!

cleanup() {
  if kill -0 "$gui_pid" >/dev/null 2>&1; then
    kill "$gui_pid" >/dev/null 2>&1 || true
    wait "$gui_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

sleep "$timeout_seconds"

if ! kill -0 "$gui_pid" >/dev/null 2>&1; then
  echo "FAIL: GUI process exited before ${timeout_seconds}s." >&2
  cat "$log_path" >&2
  exit 1
fi

if command -v xdotool >/dev/null 2>&1; then
  if ! xdotool search --name 'LogicRipper' >/dev/null 2>&1; then
    echo "FAIL: GUI process is running, but no window titled LogicRipper was found." >&2
    cat "$log_path" >&2
    exit 1
  fi
fi

mkdir -p "$(dirname "$screenshot_path")"
if command -v gnome-screenshot >/dev/null 2>&1; then
  gnome-screenshot -f "$screenshot_path" >/dev/null 2>&1 || true
elif command -v import >/dev/null 2>&1; then
  import -window root "$screenshot_path" >/dev/null 2>&1 || true
fi

echo "PASS: LogicRipper GUI stayed open for ${timeout_seconds}s using $launcher"
if [[ -s "$screenshot_path" ]]; then
  echo "Screenshot: $screenshot_path"
else
  echo "Screenshot: not captured; install gnome-screenshot or ImageMagick import for screenshot evidence."
fi
