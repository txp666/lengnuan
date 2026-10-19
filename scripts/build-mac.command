#!/bin/bash
# 双击运行：编译 Mac 版（窗口 + 菜单栏），生成 build/YorkAC.app 并打开。
# 需要 Xcode。不需要开发者账号（本地临时签名）。
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
exec > >(tee build/build-mac.log) 2>&1
echo "▶ 编译 Mac 版…"
xcodebuild -project YorkAC.xcodeproj -scheme YorkAC-Mac -configuration Release \
  -derivedDataPath build/mac \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  build > build/mac-full.log 2>&1
code=$?
grep -E "error:|warning:" build/mac-full.log | grep -v "^ld: warning" | sort -u | head -60
if [ $code -ne 0 ]; then
  tail -5 build/mac-full.log
  echo "✗ 编译失败（完整日志 build/mac-full.log）"
  exit 1
fi
pkill -f "YorkAC.app/Contents/MacOS/YorkAC" 2>/dev/null || true
rm -rf build/YorkAC.app
cp -R build/mac/Build/Products/Release/YorkAC.app build/YorkAC.app
echo "✓ 完成：$(pwd)/build/YorkAC.app"
open build/YorkAC.app
