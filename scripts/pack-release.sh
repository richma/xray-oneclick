#!/usr/bin/env bash
# 打包可离线安装的完整发布物 (install.sh + lib/ + conf/)
# 用法: bash scripts/pack-release.sh [版本号] [输出目录]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER="${1:-}"
if [ -z "$VER" ]; then
  VER="$(sed -n 's/^VERSION="\([^"]*\)"/\1/p' "$ROOT/install.sh" | head -1)"
fi
[ -n "$VER" ] || { echo "无法解析 VERSION" >&2; exit 1; }
OUT="${2:-$ROOT/dist}"
STAGE="$OUT/xray-oneclick"
rm -rf "$STAGE"
mkdir -p "$STAGE/lib" "$STAGE/conf" "$STAGE/docs"

cp -a "$ROOT/install.sh" "$STAGE/"
chmod +x "$STAGE/install.sh"
cp -a "$ROOT/lib/"*.sh "$STAGE/lib/"
cp -a "$ROOT/conf/xray-config.template.json" "$ROOT/conf/sysctl-xray.conf" "$STAGE/conf/"
cp -a "$ROOT/LICENSE" "$ROOT/README.md" "$ROOT/SECURITY.md" "$STAGE/"
if [ -f "$ROOT/docs/部署与使用手册.md" ]; then
  cp -a "$ROOT/docs/部署与使用手册.md" "$STAGE/docs/"
fi

# Windows / core.autocrlf 检出的工作区会把 CR 带进发布包, Linux 上 bash 直接崩;
# 打包前统一归一为 LF, 并断言没有任何 .sh 残留 CR.
find "$STAGE" -type f \( -name '*.sh' -o -name '*.conf' -o -name '*.json' -o -name '*.md' \) \
  -exec sed -i 's/\r$//' {} +
if find "$STAGE" -type f -name '*.sh' -exec grep -lI $'\r' {} + | grep -q .; then
  echo "错误: 发布包内仍有 CRLF 脚本" >&2
  exit 1
fi

TAR="xray-oneclick-v${VER}.tar.gz"
tar -C "$OUT" -czf "$OUT/$TAR" xray-oneclick
cp -f "$OUT/$TAR" "$OUT/xray-oneclick.tar.gz"
(cd "$OUT" && sha256sum "$TAR" xray-oneclick.tar.gz > SHA256SUMS)
echo "$OUT/$TAR"
