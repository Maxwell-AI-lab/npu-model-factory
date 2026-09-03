#!/bin/bash
# G1 代码门禁 —— PR 合入前执行（CIE）
# 用法: bash g1_code_gate.sh <patch 文件> [源码树根]
# 检查: 1) patch 可应用性（基线校验） 2) 新文件清单 3) import 自检
set -euo pipefail

PATCH="${1:?用法: bash g1_code_gate.sh <patch> [源码树根]}"
SRC="${2:-$HOME/dspark-src}"

echo "=== G1 代码门禁 ==="
echo "patch: $PATCH"
echo "源码树: $SRC"

# --- 1. 基线校验：patch 必须干净应用（基线不符即拒） ---
cd "$SRC/verl"
if git apply --check "$PATCH" 2>/dev/null; then
  echo "[PASS] patch 可干净应用（基线匹配）"
else
  echo "[FAIL] patch 无法应用——基线漂移或冲突，拒绝合入"
  echo "       修复: 从最新分支重新 fetch_sources，在其上重做改动后"
  echo "       git diff HEAD 整树重生成 patch（铁律 1/2）"
  exit 1
fi

# --- 2. 改动清单：文件数 + 新文件检查 ---
FILES=$(grep -c '^diff --git' "$PATCH" || true)
echo "[INFO] patch 涉及 $FILES 个文件"
NEW_FILES=$(git apply --numstat "$PATCH" 2>/dev/null | awk '$1=="0" && $2=="0"{print}' | wc -l || true)
echo "[INFO] 其中全新文件 $NEW_FILES 个（应同时提交到 overlay/new-files/）"

# --- 3. import 自检：关键类可导入（容器内或源码树直接跑） ---
if command -v python3 &>/dev/null; then
  PYTHONPATH="$SRC/vllm-ascend:$SRC/verl" python3 - <<'PYEOF' \
    && echo "[PASS] import 自检通过" \
    || { echo "[FAIL] import 自检失败"; exit 1; }
# 按模型替换关键类；此处为模板示例
import importlib, sys
checks = [
    ("vllm_ascend.spec_decode.dspark_proposer", "AscendDSparkProposer"),
]
ok = True
for mod, cls in checks:
    try:
        getattr(importlib.import_module(mod), cls)
        print(f"  [ok] {mod}.{cls}")
    except Exception as e:
        print(f"  [FAIL] {mod}.{cls}: {e}")
        ok = False
sys.exit(0 if ok else 1)
PYEOF
fi

# --- 4. PR 附自验输出检查（提示性） ---
cat <<'EOF'
[G1 清单] 合入前请确认 PR 包含:
  - check_health.sh 输出（≥5 步，全部 OK）
  - 特性 PR 附: 生效实证指标（加速比/接受率）
  - 新文件已放 overlay/new-files/（铁律 3）
EOF
echo "=== G1 通过 ==="
