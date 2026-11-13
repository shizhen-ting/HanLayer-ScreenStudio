#!/bin/bash
# 彻底清理汉化留下的痕迹：先还原 Screen Studio，再删备份 / 证书 / 日志
APP="/Applications/Screen Studio.app"
TOOL="/Applications/汉层 HanLayer.app"
ENGINE="$TOOL/Contents/Resources/engine/sszh-engine"

if [ -x "$ENGINE" ] && [ -d "$APP" ]; then
  echo "1) 还原 Screen Studio 为英文原版…"
  "$ENGINE" --restore "$APP" || echo "   还原失败，可稍后手动重装 Screen Studio"
else
  echo "1) 跳过还原（工具或 app 不存在）"
fi

echo "2) 删除备份目录（约 250 MB）"
rm -rf "$HOME/Library/Application Support/Screen Studio 汉化"

echo "3) 删除本地签名证书"
security delete-certificate -c "Screen Studio Chinese Localizer" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1 && echo "   已删除" || echo "   没有找到证书（可能已删）"

echo "4) 清理系统里的授权记录（绑定旧签名的残留）"
for svc in ScreenCapture Accessibility Camera Microphone; do
  /usr/bin/tccutil reset "$svc" com.timpler.screenstudio >/dev/null 2>&1 && echo "   $svc 已重置"
done

echo "5) 删除工具日志"
rm -f "$HOME/Library/Logs/SSHanHua.log"

echo
echo "完成。若不再需要，可把「/Applications/汉层 HanLayer.app」也拖进废纸篓。"
