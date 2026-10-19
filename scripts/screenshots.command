#!/bin/bash
# 双击运行：用演示数据重新生成 README 里的截图（docs/screenshots/*.png）。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build docs/screenshots
exec > >(tee build/screenshots.log) 2>&1
source scripts/_build-preview.sh
"$APP/Contents/MacOS/YorkPreview" --export "$(pwd)/docs/screenshots"
echo "✓ 截图已更新：docs/screenshots"
