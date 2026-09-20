#!/usr/bin/env bash
#
# 使用 Node.js 官方 SEA (Single Executable Application) 将服务器编译为单文件可执行程序
# 要求: Node.js >= 20
# 用法: npm run build:sea
# 产物: dist/fan-random
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

APP_NAME="fan-random"
CONFIG="sea-config.json"
PREP_BLOB="sea-prep.blob"
OUT_DIR="dist"
OUT="$OUT_DIR/$APP_NAME"
FUSE="NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2"

if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: node not found in PATH"
  exit 1
fi

echo "1/4 Generating SEA preparation blob..."
node --experimental-sea-config "$CONFIG"

echo "2/4 Copying Node runtime..."
mkdir -p "$OUT_DIR"
cp "$(command -v node)" "$OUT"
chmod +x "$OUT"

echo "3/4 Injecting application code..."
npx --yes postject "$OUT" NODE_SEA_BLOB "$PREP_BLOB" --sentinel-fuse "$FUSE"

echo "4/4 Cleaning up..."
rm -f "$PREP_BLOB"

echo ""
echo "Build complete: $(pwd)/$OUT"
echo "The binary reads images from the public/ directory next to it."
echo "Run 'fan-random --help' inside it will switch to CLI mode."
echo "Copy/Mount public/ alongside the binary to serve images."