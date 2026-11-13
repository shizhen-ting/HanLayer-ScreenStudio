#!/bin/bash
set -e
APP="/Applications/Screen Studio.app"
R="$(cd "$(dirname "$0")/.." && pwd)"
BK="$HOME/Library/Application Support/Screen Studio 汉化"
mkdir -p "$BK"
[ -f "$BK/app.asar.orig" ] || cp "$APP/Contents/Resources/app.asar" "$BK/app.asar.orig"
[ -f "$BK/Info.plist.orig" ] || cp "$APP/Contents/Info.plist" "$BK/Info.plist.orig"
pkill -f "Screen Studio.app/Contents/MacOS/Screen Studio" 2>/dev/null || true
sleep 1
cp "$R/build/app.asar" "$APP/Contents/Resources/app.asar"
rsync -a --delete "$R/build/app.asar.unpacked/" "$APP/Contents/Resources/app.asar.unpacked/"
/usr/libexec/PlistBuddy -c "Delete :ElectronAsarIntegrity" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
# 声明支持简体中文，让 AppKit 用中文生成本地化的系统菜单项（窗口平铺、表情符号、听写等）
mkdir -p "$APP/Contents/Resources/zh-Hans.lproj"
printf '"CFBundleName" = "Screen Studio";\n' > "$APP/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"
/usr/libexec/PlistBuddy -c "Delete :CFBundleLocalizations" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations array" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations:0 string en" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations:1 string zh-Hans" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
codesign --force --deep --sign - --options runtime --entitlements "$R/build/entitlements.plist" "$APP" 2>&1 | tail -5
codesign --verify --verbose=1 "$APP" 2>&1 | tail -3
echo INSTALLED
