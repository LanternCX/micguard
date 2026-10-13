#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != Darwin ]]; then
    echo "MicGuard 仅支持 macOS。" >&2
    exit 1
fi

install_dir="$HOME/Library/Application Support/MicGuard"
agent_dir="$HOME/Library/LaunchAgents"
agent_plist="$agent_dir/local.micguard.plist"
service="gui/$(id -u)/local.micguard"

if [[ "${1:-}" == --uninstall ]]; then
    if launchctl print "$service" >/dev/null 2>&1; then
        launchctl bootout "$service"
    fi
    rm -f "$agent_plist"
    rm -rf "$install_dir"
    echo "MicGuard 已卸载。"
    exit 0
elif [[ $# -gt 0 ]]; then
    echo "用法：bash install.sh [--uninstall]" >&2
    exit 1
fi

if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "请先完成弹出的 Apple 命令行工具安装，然后重新运行本命令。" >&2
    xcode-select --install || true
    exit 1
fi

# Remote installs build in a temporary directory; checkouts use local source.
project_dir=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [[ -z "$project_dir" || ! -f "$project_dir/Sources/MicGuard.swift" ]]; then
    project_dir="$(mktemp -d "${TMPDIR:-/tmp}/micguard.XXXXXX")"
    trap 'rm -rf "$project_dir"' EXIT
    mkdir -p "$project_dir/Sources"
    curl --fail --silent --show-error --location --retry 3 \
        https://raw.githubusercontent.com/LanternCX/micguard/main/Sources/MicGuard.swift \
        -o "$project_dir/Sources/MicGuard.swift"
fi

mkdir -p "$project_dir/.build"
xcrun swiftc -parse-as-library -O "$project_dir/Sources/MicGuard.swift" -o "$project_dir/.build/micguard"

# Generate paths through plutil so spaces and XML characters are escaped.
build_plist="$project_dir/.build/local.micguard.plist"
rm -f "$build_plist"
plutil -create xml1 "$build_plist"
plutil -insert Label -string local.micguard "$build_plist"
plutil -insert ProgramArguments -json '[]' "$build_plist"
plutil -insert ProgramArguments.0 -string "$install_dir/micguard" "$build_plist"
plutil -insert RunAtLoad -bool YES "$build_plist"
plutil -insert KeepAlive -bool YES "$build_plist"
plutil -insert ThrottleInterval -integer 10 "$build_plist"
plutil -insert LimitLoadToSessionType -string Aqua "$build_plist"
plutil -insert StandardErrorPath -string "$install_dir/micguard.log" "$build_plist"
plutil -lint "$build_plist"

mkdir -p "$install_dir" "$agent_dir"
if launchctl print "$service" >/dev/null 2>&1; then
    launchctl bootout "$service"
fi
install -m 755 "$project_dir/.build/micguard" "$install_dir/micguard"
install -m 644 "$build_plist" "$agent_plist"
launchctl enable "$service"
launchctl bootstrap "gui/$(id -u)" "$agent_plist"
echo "MicGuard 已安装并启动。"
