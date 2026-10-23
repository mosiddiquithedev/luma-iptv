#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
swift build -c "$configuration" --product Luma
app="$(pwd)/build/Luma.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp ".build/$configuration/Luma" "$app/Contents/MacOS/Luma.new"
mv -f "$app/Contents/MacOS/Luma.new" "$app/Contents/MacOS/Luma"
cp Resources/Info.plist "$app/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$app/Contents/Resources/"; fi
codesign --force --sign - --identifier app.luma.iptv "$app"
print "Built $app"
