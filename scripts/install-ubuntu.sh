#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
install_root="${LOGIC_RIPPER_INSTALL_ROOT:-$HOME/.local/share/logic-ripper}"
bin_dir="${LOGIC_RIPPER_BIN_DIR:-$HOME/.local/bin}"
pwsh_version="${LOGIC_RIPPER_PWSH_VERSION:-7.4.17}"
gui_publish_dir="$repo_root/artifacts/LogicRipper.Gui-linux-x64"

mkdir -p "$install_root" "$bin_dir"

if [[ ! -x "$install_root/powershell/pwsh" ]]; then
  deb="/tmp/powershell_${pwsh_version}.deb"
  curl -L -o "$deb" "https://github.com/PowerShell/PowerShell/releases/download/v${pwsh_version}/powershell_${pwsh_version}-1.deb_amd64.deb"
  rm -rf "$install_root/powershell-pkg"
  mkdir -p "$install_root/powershell-pkg"
  dpkg -x "$deb" "$install_root/powershell-pkg"
  mkdir -p "$install_root/powershell"
  cp -a "$install_root/powershell-pkg/opt/microsoft/powershell/7/." "$install_root/powershell/"
  chmod +x "$install_root/powershell/pwsh"
fi

cat > "$bin_dir/logic-ripper" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$install_root/powershell/pwsh" -NoLogo -NoProfile -File "$repo_root/src/LogicRipper.Cli/Start-LogicRipperCli.ps1" "\$@"
EOF
chmod +x "$bin_dir/logic-ripper"

cat > "$bin_dir/logic-ripper-test" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "$repo_root"
export LOGIC_RIPPER_CLI="$bin_dir/logic-ripper"
exec "$install_root/powershell/pwsh" -NoLogo -NoProfile -File ./build.ps1 -Test
EOF
chmod +x "$bin_dir/logic-ripper-test"

if [[ ! -x "$gui_publish_dir/LogicRipper.Gui" ]]; then
  if command -v dotnet >/dev/null 2>&1; then
    bash "$repo_root/scripts/build-ubuntu-gui.sh" >/dev/null
  else
    echo "ERROR: LogicRipper GUI artifact is missing and dotnet SDK is not installed." >&2
    echo "Install .NET 8 SDK or provide artifacts/LogicRipper.Gui-linux-x64/LogicRipper.Gui, then rerun this installer." >&2
    exit 1
  fi
fi

if [[ ! -x "$gui_publish_dir/LogicRipper.Gui" ]]; then
  echo "ERROR: GUI binary is missing executable permission: $gui_publish_dir/LogicRipper.Gui" >&2
  exit 1
fi

cat > "$bin_dir/logic-ripper-gui" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "--version" ]]; then
  exec "$gui_publish_dir/LogicRipper.Gui" --version
fi
if [[ -z "\${DISPLAY:-}" && -z "\${WAYLAND_DISPLAY:-}" ]]; then
  if [[ -n "\${SSH_CONNECTION:-}" ]]; then
    echo "ERROR: LogicRipper GUI cannot open from this headless SSH session. Enable X forwarding or run inside Ubuntu Desktop." >&2
  else
    echo "ERROR: LogicRipper GUI needs an Ubuntu desktop session. DISPLAY and WAYLAND_DISPLAY are both missing." >&2
  fi
  exit 2
fi
export LOGIC_RIPPER_CLI="$bin_dir/logic-ripper"
exec "$gui_publish_dir/LogicRipper.Gui" "\$@"
EOF
chmod +x "$bin_dir/logic-ripper-gui"

echo "Logic Ripper installed."
echo "Add this to PATH if needed: export PATH=\"$bin_dir:\$PATH\""
echo "Start: $bin_dir/logic-ripper status"
echo "GUI:   $bin_dir/logic-ripper-gui"
echo "Test:  $bin_dir/logic-ripper-test"
