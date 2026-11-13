#!/bin/bash
# 一键构建：Swift 可执行文件 → App 包 → 重签名 → DMG
#
# 用法：
#   ./build.sh            # 用默认版本号 1.1
#   ./build.sh 1.2        # 指定版本号
#
# 依赖：Xcode 命令行工具（swiftc / codesign / iconutil）、python3 + dmgbuild
set -euo pipefail

VERSION="${1:-1.1}"
PYTHON="${PYTHON:-python3}"          # 需要装有 dmgbuild 的解释器
R="$(cd "$(dirname "$0")" && pwd)"
APP="$R/build-app/汉层 HanLayer.app"
ENGINE="$R/build-engine/dist/sszh-engine"
DMG="$R/build/HanLayer-v${VERSION}-ScreenStudio-4.1.0.dmg"

say() { printf "\n\033[1m==> %s\033[0m\n" "$1"; }
die() { printf "\033[31m✗ %s\033[0m\n" "$1" >&2; exit 1; }

# ---------- 前置检查 ----------
say "检查依赖"
command -v swiftc >/dev/null || die "缺少 swiftc（安装 Xcode 命令行工具：xcode-select --install）"
"$PYTHON" -c "import dmgbuild" 2>/dev/null || die "缺少 dmgbuild（$PYTHON -m pip install dmgbuild，或用 PYTHON=... 指定解释器）"
# 引擎缺失时尝试自动构建（PyInstaller 单文件）
if [ ! -f "$ENGINE" ]; then
  echo "  引擎缺失，尝试用 PyInstaller 构建…"
  "$PYTHON" -c "import PyInstaller" 2>/dev/null \
    || die "缺少汉化引擎，且未安装 PyInstaller。
  先执行：$PYTHON -m pip install pyinstaller"
  ( cd "$R/build-engine" && "$PYTHON" -m PyInstaller sszh-engine.spec --noconfirm >/dev/null 2>&1 ) \
    || die "引擎构建失败，请手动检查 build-engine/sszh-engine.spec"
  cp "$R/build-engine/dist/sszh-engine" "$ENGINE"
fi
echo "  swiftc  $(swiftc --version | head -1 | awk '{print $2}')"
echo "  引擎    $(ls -lh "$ENGINE" | awk '{print $5}')"

# ---------- 1. 编译 ----------
say "编译 Swift"
swiftc -O -o "$R/build/Localizer" \
  "$R/app-src/AppMain.swift" \
  "$R/app-src/Engine.swift"
echo "  $(ls -lh "$R/build/Localizer" | awk '{print $5}')"

# ---------- 2. 组装 App 包 ----------
say "组装 App 包"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/engine"

cp "$R/build/Localizer"                  "$APP/Contents/MacOS/Localizer"
chmod 755                                "$APP/Contents/MacOS/Localizer"
cp "$R/app-src/icon-hanlayer.icns"       "$APP/Contents/Resources/icon.icns"
cp "$R/app-src/Info.plist"               "$APP/Contents/Info.plist"
cp -R "$R/build/zh-Hans.lproj"           "$APP/Contents/Resources/"
cp "$ENGINE"                             "$APP/Contents/Resources/engine/sszh-engine"
chmod 755                                "$APP/Contents/Resources/engine/sszh-engine"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
echo "  版本 ${VERSION}，含图标 / zh-Hans / 引擎"

# ---------- 3. 签名 ----------
say "重签名"
find "$APP" -name '.DS_Store' -delete 2>/dev/null || true
xattr -cr "$APP"
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
rm -rf "$APP/Contents/_CodeSignature"
# Finder 有时会在签名瞬间写回 FinderInfo，失败就清理后重试一次
sign_ok=0
for attempt in 1 2 3; do
  if codesign --force --deep --sign - --identifier "com.local.ss-zh-localizer" "$APP" 2>/tmp/sign_err.txt; then
    sign_ok=1; break
  fi
  if grep -q 'detritus' /tmp/sign_err.txt; then
    echo "  清理扩展属性后重试（第 $attempt 次）"
    xattr -cr "$APP"
    xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
    find "$APP" -name '.DS_Store' -delete 2>/dev/null || true
    sleep 1
  else
    cat /tmp/sign_err.txt; break
  fi
done
rm -f /tmp/sign_err.txt
[ "$sign_ok" = "1" ] || die "签名失败"
codesign --verify --deep --strict "$APP"
echo "  ✓ 签名校验通过"

# ---------- 4. 打包 DMG ----------
say "打包 DMG"
rm -rf "/tmp/汉层 HanLayer.app"
ditto "$APP" "/tmp/汉层 HanLayer.app"
cd "$R/dmg"
rm -f "$DMG"
"$PYTHON" -m dmgbuild -s settings.py "汉层 HanLayer" "$DMG" 2>&1 | grep -v WARNING || true

echo
echo "────────────────────────────────────────────"
echo "✓ 构建完成"
echo "  App : $APP"
echo "  DMG : $DMG"
echo "  SHA : $(shasum -a 256 "$DMG" | awk '{print $1}')"
echo "────────────────────────────────────────────"
