#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gui_bin="$repo_root/artifacts/LogicRipper.Gui-linux-x64/LogicRipper.Gui"

if [[ ! -x "$gui_bin" ]]; then
  echo "ERROR: GUI binary is missing or not executable: $gui_bin" >&2
  echo "Run: bash ./scripts/build-ubuntu-gui.sh" >&2
  exit 1
fi

if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    echo "ERROR: no graphical session detected. You appear to be in headless SSH; enable X forwarding or run inside Ubuntu Desktop." >&2
  else
    echo "ERROR: no graphical session detected. DISPLAY and WAYLAND_DISPLAY are both missing." >&2
  fi
  exit 2
fi

if ! command -v logic-ripper >/dev/null 2>&1; then
  echo "ERROR: logic-ripper CLI is not on PATH. Run: bash ./scripts/install-ubuntu.sh" >&2
  exit 1
fi

export LOGIC_RIPPER_CLI="$(command -v logic-ripper)"
exec "$gui_bin" "$@"
