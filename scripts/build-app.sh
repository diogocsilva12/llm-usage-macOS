#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    printf '%s\n' 'Limitbar.app requires macOS 13+ and Xcode Command Line Tools. The core tests can run on Linux.' >&2
    exit 1
fi

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
if ! xcrun --find swift >/dev/null 2>&1; then
    printf '%s\n' 'Install Apple Command Line Tools with: xcode-select --install' >&2
    exit 1
fi

swift build --configuration release --product Limitbar
binary_dir="$(swift build --configuration release --show-bin-path)"
app_dir="$project_dir/dist/Limitbar.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/Limitbar" "$app_dir/Contents/MacOS/Limitbar"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
swift "$project_dir/scripts/make-icon.swift" "$app_dir/Contents/Resources/AppIcon.icns"
plutil -lint "$app_dir/Contents/Info.plist"
codesign --force --sign "${LIMITBAR_SIGN_IDENTITY:--}" "$app_dir"
codesign --verify --strict "$app_dir"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$project_dir/dist/Limitbar-macOS.zip"
printf '\n%s\n' 'Built dist/Limitbar.app and dist/Limitbar-macOS.zip.' 'Move Limitbar.app to Applications, then open it.'
