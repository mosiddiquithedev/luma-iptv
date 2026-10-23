#!/bin/zsh
# Build a universal, ad-hoc signed macOS release. Requires Apple Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."
root="$PWD"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
name="Luma-${version}-macOS-universal"
output="$root/build/releases/$version"
mkdir -p "$output"
stage=$(mktemp -d "$root/build/luma-package.XXXXXX")
trap 'rm -rf "$stage"' EXIT

for arch in arm64 x86_64; do
    swift build -c release --product Luma --triple "$arch-apple-macosx14.0" --scratch-path ".build/$arch"
done

app="$stage/Luma.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
lipo -create ".build/arm64/arm64-apple-macosx/release/Luma" ".build/x86_64/x86_64-apple-macosx/release/Luma" -output "$app/Contents/MacOS/Luma"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/"
codesign --force --sign - --identifier app.luma.iptv "$app"
codesign --verify --deep --strict "$app"
lipo "$app/Contents/MacOS/Luma" -verify_arch arm64 x86_64
plutil -lint "$app/Contents/Info.plist"

cat > "$stage/INSTALL.txt" <<'EOF'
Luma for macOS

Requirements: macOS 14 Sonoma or later; Apple Silicon or Intel Mac.

Installation
1. Open the DMG and drag Luma to Applications. For the ZIP, extract it and
   move Luma.app to Applications.
2. Eject the disk image and open Luma from Applications.

This release is ad-hoc signed, not Developer ID signed or Apple notarized.
macOS may block the first launch. After trying to open the app, open
System Settings > Privacy & Security and use Open Anyway if offered.
Only do this if you trust the download. Managed Macs may restrict this.

Playback
Install the matching version of VLC from https://www.videolan.org/vlc/
in /Applications/VLC.app for broader IPTV format support. VLC is separate
and is not bundled. Without VLC, Luma uses AVPlayer for supported formats.

Connect your own Xtream-compatible account or M3U playlist. Luma provides
no channels, subscriptions, playlists, provider accounts or media content.

Project: https://github.com/mosiddiquithedev/luma-iptv
EOF
ln -s /Applications "$stage/Applications"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/$name.zip"
hdiutil create -volname "Luma $version" -srcfolder "$stage" -ov -format UDZO "$output/$name.dmg"
hdiutil verify "$output/$name.dmg"
cp "$stage/INSTALL.txt" "$output/INSTALL.txt"
(cd "$output" && shasum -a 256 "$name.dmg" "$name.zip" INSTALL.txt > SHA256SUMS.txt)
print "Release files: $output"
