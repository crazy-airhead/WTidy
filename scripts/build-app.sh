#!/bin/bash
# 构建 WTidy.app：swift build → 组装 bundle → ad-hoc 签名
# 用法:
#   scripts/build-app.sh            仅构建到 build/WTidy.app
#   scripts/build-app.sh --install  构建并安装到 /Applications（会先退出运行中的 WTidy）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIG="${CONFIG:-release}"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="$ROOT/build/WTidy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/WTidy" "$APP/Contents/MacOS/WTidy"
cp "$ROOT/AppResources/Info.plist" "$APP/Contents/Info.plist"

# 图标：优先用仓库内 AppResources/AppIcon.icns；缺失时现场生成
ICON="$ROOT/AppResources/AppIcon.icns"
if [ ! -f "$ICON" ]; then
    echo "==> 生成应用图标"
    swift "$ROOT/scripts/make-icon.swift" "$ICON"
fi
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

echo "==> ad-hoc 签名"
codesign --force --sign - "$APP"
codesign --verify "$APP"
echo "✓ 构建完成: $APP"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> 安装到 /Applications"
    osascript -e 'quit app "WTidy"' 2>/dev/null || true
    sleep 1
    rm -rf "/Applications/WTidy.app"
    /usr/bin/ditto "$APP" "/Applications/WTidy.app"
    open "/Applications/WTidy.app"
    echo "✓ 已安装并启动 /Applications/WTidy.app"
    echo "  首次使用请在 系统设置 → 隐私与安全性 → 辅助功能 中授权 WTidy"
fi
