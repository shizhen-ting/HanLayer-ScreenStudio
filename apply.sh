#!/bin/bash
# 重新应用中文层：从当前安装的 app 解包 → 打补丁 → 重新打包签名安装。
# 官方更新后直接跑一次即可；重复运行是幂等的。
set -e
APP="${1:-/Applications/Screen Studio.app}"
R="$(cd "$(dirname "$0")" && pwd)"
STAGE="$R/build/stage"
NODE="$(command -v node || true)"
[ -x "$NODE" ] || { echo "需要 Node.js（brew install node）"; exit 1; }

echo "==> 解包 $APP"
rm -rf "$STAGE"; mkdir -p "$STAGE"
python3 "$R/engine/asar_tool.py" extract "$APP/Contents/Resources/app.asar" "$STAGE" >/dev/null

echo "==> 打补丁 + 生成词典"
SS_STAGE="$STAGE" "$NODE" "$R/build/build.js"

echo "==> 给可执行文件补权限"
for f in bin/screen-studio-native bin/ffmpeg-darwin-arm64 bin/whisper-darwin-arm64 bin/arm64/mlx.metallib bin/arm64/screen-studio-speech; do
  [ -f "$STAGE/$f" ] && chmod 755 "$STAGE/$f"
done

echo "==> 打包 asar"
rm -rf "$R/build/app.asar" "$R/build/app.asar.unpacked"
python3 "$R/engine/asar_pack.py" "$STAGE" "$R/build/app.asar" bin node_modules/keytar node_modules/node-mac-permissions node_modules/wallpaper >/dev/null

echo "==> 安装 + 重签名"
bash "$R/build/install.sh"

echo "完成。若 macOS 提示权限，请到「系统设置 → 隐私与安全性」重新授权屏幕录制/辅助功能/摄像头。"
