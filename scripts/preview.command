#!/bin/bash
# 双击运行：打开界面预览（演示数据，不联网）：iPhone 深色/浅色界面 + 所有小组件。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
exec > >(tee build/preview.log) 2>&1
source scripts/_build-preview.sh
pkill -x YorkPreview 2>/dev/null || true
echo "✓ 完成"
open "$APP"
