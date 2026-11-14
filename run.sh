#!/usr/bin/env bash
# Build Oree, wrap it in an app bundle, install it and start it.
# BUILD_ONLY=1 stops after the bundle is made.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/build/Oree.app"

cd "$ROOT"
# Use the native builder with its own cache to avoid the Swift Build
# deferred-task planning stall and contention with an earlier build.
BUILD_ARGS=(-c release --build-system native --scratch-path "$ROOT/.build/native")
swift build "${BUILD_ARGS[@]}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Library/LaunchAgents"
# What the system runs when Oree is the desktop: at login, and again if it
# stops in any way other than being asked to.
cat >"$APP/Contents/Library/LaunchAgents/space.oree.agent.plist" <<'AGENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>space.oree.agent</string>
    <key>BundleProgram</key><string>Contents/MacOS/Oree</string>
    <key>AssociatedBundleIdentifiers</key><string>space.oree.app</string>
    <key>EnvironmentVariables</key><dict><key>OREE_AGENT</key><string>1</string></dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>ProcessType</key><string>Interactive</string>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
AGENT
install -m 755 "$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/Oree" "$APP/Contents/MacOS/Oree"
cat >"$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Oree</string>
    <key>CFBundleIdentifier</key><string>space.oree.app</string>
    <key>CFBundleName</key><string>Oree</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleDocumentTypes</key>
    <array><dict>
        <key>CFBundleTypeName</key><string>Folder</string>
        <key>CFBundleTypeRole</key><string>Viewer</string>
        <key>LSHandlerRank</key><string>Alternate</string>
        <key>LSItemContentTypes</key><array><string>public.folder</string></array>
    </dict></array>
    <key>NSCalendarsFullAccessUsageDescription</key><string>Oree shows today's and tomorrow's events on the desktop.</string>
    <key>NSLocationWhenInUseUsageDescription</key><string>Oree shows the weather where you are.</string>
    <key>NSLocationUsageDescription</key><string>Oree shows the weather where you are.</string>
    <key>NSRemindersFullAccessUsageDescription</key><string>Oree shows your open reminders on the desktop and marks them done when you ask.</string>
    <key>NSAppleEventsUsageDescription</key><string>Oree shows files in Finder, shows your latest mail and what is playing, and lets you skip songs from the desktop.</string>
    <key>NSDesktopFolderUsageDescription</key><string>Oree shows the items in your Desktop folder.</string>
    <key>NSDocumentsFolderUsageDescription</key><string>Oree shows the items in your Documents folder.</string>
    <key>NSDownloadsFolderUsageDescription</key><string>Oree shows the items in your Downloads folder.</string>
</dict>
</plist>
EOF
# Sign with the first code-signing certificate in the keychain when there is
# one, and ad hoc when there is none. With a certificate, macOS treats each
# new build as the same app and keeps the permissions it was granted.
IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null | grep -m1 -oE '[0-9A-F]{40}' || true)"
codesign --force --sign "${IDENTITY:--}" --identifier space.oree.app "$APP" 2>/dev/null

[[ "${BUILD_ONLY:-0}" == "1" ]] && exit 0

# Oree runs from /Applications: the system will not keep a login item whose
# app can move, and a build folder is no place for one.
INSTALLED="/Applications/Oree.app"
ditto "$APP" "$INSTALLED"
if launchctl print "gui/$UID/space.oree.agent" >/dev/null 2>&1; then
  # Oree is the desktop: have the system start the new build.
  launchctl kickstart -k "gui/$UID/space.oree.agent"
else
  pkill -x Oree 2>/dev/null || true
  open "$INSTALLED"
fi
