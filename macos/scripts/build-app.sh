#!/bin/bash
# 构建 ChatGPT 代理助手 .app（swift build → 手工组装 bundle → ad-hoc 签名）
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN=".build/$CONFIG/ChatGPTProxyHelper"

APP="build/ChatGPT 代理助手.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ChatGPTProxyHelper"
cp scripts/Info.plist "$APP/Contents/Info.plist"

# 图标：生成 1024 底图 → 缩放出 iconset → iconutil 打包 icns
swift scripts/make-icon.swift build/AppIcon.png >/dev/null
mkdir -p build/AppIcon.iconset
for s in 16 32 64 128 256 512; do
  sips -z $s $s build/AppIcon.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
done
for s in 16 32 128 256 512; do
  d=$((s * 2))
  sips -z $d $d build/AppIcon.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP" 2>/dev/null || true

echo "构建完成：$(pwd)/$APP"
