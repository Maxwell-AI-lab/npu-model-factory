#!/bin/bash
# 三元组起跑校验（②起跑前必跑 / CIE 发布时锁定）
# 用法: bash verify_runtime.sh <镜像tag> [manifest路径]
# 逻辑: 从 manifest 读该 tag 的 runtime_deps（权重/数据 sha256），
#       实测对账——不匹配直接拒绝起跑（镜像可信从"代码可复现"
#       扩展到"运行输入可锁定"的落地件）
# 约定: 文件（如 parquet）校验文件 sha256；
#       目录（如权重）校验目录指纹 = find+sort+逐文件sha256 汇总再 sha256
set -euo pipefail

TAG="${1:?用法: bash verify_runtime.sh <镜像tag> [manifest路径]}"
MANIFEST="${2:-$(cd "$(dirname "$0")/.." && pwd)/registry/manifest.yaml}"

echo "=== 三元组运行校验: $TAG ==="

# --- 从 manifest 提取该 tag 条目的 runtime_deps（无 yaml 依赖，awk 定位）---
section=$(awk -v tag="tag: \"$TAG\"" '
  $0 ~ tag {found=1} found && /runtime_deps:/{indep=1;next}
  indep && /^  [a-z]/ && !/weights|dataset/{exit}
  indep{print}' "$MANIFEST")

if [ -z "$section" ]; then
  echo "[FAIL] manifest 中未找到 $TAG 的 runtime_deps——未登记三元组的镜像不可起跑"; exit 1
fi

W_PATH=$(echo "$section" | grep -A1 'weights:' | grep 'path:' | awk '{print $2}')
D_PATH=$(echo "$section" | grep -A1 'dataset:'  | grep 'path:'  | awk '{print $2}')
W_SHA=$(echo "$section"  | grep -A1 'weights:' | grep 'sha256:' | awk -F'"' '{print $2}')
D_SHA=$(echo "$section"  | grep -A1 'dataset:'  | grep 'sha256:' | awk -F'"' '{print $2}')

fail=0
check_one() {  # $1=名称 $2=路径 $3=期望sha
  [ -z "$2" ] && { echo "[FAIL] $1 路径为空"; fail=1; return; }
  [ "$3" = "TODO" ] || [ -z "$3" ] && { echo "[FAIL] $1 sha256 未登记（TODO）——CIE 发布时必须锁定"; fail=1; return; }
  if [ -d "$2" ]; then
    actual=$(cd "$2" && find . -type f | sort | xargs sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1)
  else
    actual=$(sha256sum "$2" 2>/dev/null | cut -d' ' -f1)
  fi
  if [ "$actual" = "$3" ]; then echo "[PASS] $1 ($2)"; else
    echo "[FAIL] $1 不匹配！  期望 $3  实测 $actual —— 版本错配，拒绝起跑（对照 Wan2.2 分片损坏教训）"; fail=1
  fi
}

check_one "权重"   "$W_PATH" "$W_SHA"
check_one "数据集" "$D_PATH" "$D_SHA"

# 附：输出当前目录指纹（CIE 登记时用）
fingerprint() { [ -d "$1" ] && (cd "$1" && find . -type f | sort | xargs sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1) || sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }
echo "----- 登记辅助（CIE 用）-----"
echo "weights  fingerprint: $(fingerprint "$W_PATH" 2>/dev/null || echo '(路径无效)')"
echo "dataset fingerprint: $(fingerprint "$D_PATH" 2>/dev/null || echo '(路径无效)')"

[ "$fail" = 0 ] && echo "=== 三元组校验通过，可以起跑 ===" || { echo "=== 校验失败，拒绝起跑 ==="; exit 1; }
