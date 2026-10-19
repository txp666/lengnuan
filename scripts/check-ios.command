#!/bin/bash
# 双击运行：不签名地编译一遍 iPhone 版（App + 小组件），检查代码有没有错误。
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
exec > >(tee build/check-ios.log) 2>&1
echo "▶ $(xcodebuild -version | head -1)，正在编译 iPhone 版…"
xcodebuild -project YorkAC.xcodeproj -scheme YorkAC -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build/ios \
  CODE_SIGNING_ALLOWED=NO build > build/ios-full.log 2>&1
code=$?
grep -E "error:|warning:" build/ios-full.log | grep -v "^ld: warning" | sort -u | head -80
tail -3 build/ios-full.log
if [ $code -eq 0 ]; then echo "✓ iPhone 版编译通过"; else echo "✗ 编译失败（完整日志 build/ios-full.log）"; fi
