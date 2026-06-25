#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
install_root="${LOGIC_RIPPER_INSTALL_ROOT:-$HOME/.local/share/logic-ripper}"
bin_dir="${LOGIC_RIPPER_BIN_DIR:-$HOME/.local/bin}"
pwsh_version="${LOGIC_RIPPER_PWSH_VERSION:-7.4.17}"

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
exec "$install_root/powershell/pwsh" -NoLogo -NoProfile -File ./build.ps1 -Test
EOF
chmod +x "$bin_dir/logic-ripper-test"

echo "Logic Ripper installed."
echo "Add this to PATH if needed: export PATH=\"$bin_dir:\$PATH\""
echo "Start: $bin_dir/logic-ripper status"
echo "Test:  $bin_dir/logic-ripper-test"
