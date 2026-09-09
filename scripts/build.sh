#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
swift build -c release --product agentnotify
bundle="$repo_root/dist/AgentNotify.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
swift scripts/icon.swift "$repo_root/dist/AgentNotify.iconset"
iconutil -c icns "$repo_root/dist/AgentNotify.iconset" -o "$bundle/Contents/Resources/AgentNotify.icns"
cp .build/release/agentnotify "$bundle/Contents/MacOS/AgentNotify"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.arthack.agentnotify</string>
<key>CFBundleName</key><string>AgentNotify</string>
<key>CFBundleDisplayName</key><string>AgentNotify</string>
<key>CFBundleExecutable</key><string>AgentNotify</string>
<key>CFBundleIconFile</key><string>AgentNotify</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>AgentNotifyInstaller</key><string>agentnotify/scripts/install.sh</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Add :AgentNotifySourceRevision string $(git rev-parse HEAD)" "$bundle/Contents/Info.plist"
codesign --force --sign "${AGENTNOTIFY_SIGNING_IDENTITY:--}" --options runtime "$bundle"
codesign --verify --strict "$bundle"
printf 'Built %s\n' "$bundle"
