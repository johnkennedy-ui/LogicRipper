#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifacts_dir="$repo_root/artifacts"
publish_dir="$artifacts_dir/LogicRipper.Gui-linux-x64"

if ! command -v dotnet >/dev/null 2>&1; then
  echo "ERROR: dotnet SDK is required to build the Avalonia GUI. Install .NET 8 SDK, then rerun this script." >&2
  exit 1
fi

mkdir -p "$artifacts_dir"
rm -rf "$publish_dir" "$artifacts_dir/LogicRipper.Gui-linux-x64.tar.gz"

dotnet build "$repo_root/src/LogicRipper.Gui.Avalonia/LogicRipper.Gui.Avalonia.csproj" -c Release
dotnet publish "$repo_root/src/LogicRipper.Gui.Avalonia/LogicRipper.Gui.Avalonia.csproj" \
  -c Release \
  -r linux-x64 \
  --self-contained true \
  -o "$publish_dir"

chmod +x "$publish_dir/LogicRipper.Gui"
tar -C "$artifacts_dir" -czf "$artifacts_dir/LogicRipper.Gui-linux-x64.tar.gz" LogicRipper.Gui-linux-x64

echo "$publish_dir/LogicRipper.Gui"
echo "$artifacts_dir/LogicRipper.Gui-linux-x64.tar.gz"
