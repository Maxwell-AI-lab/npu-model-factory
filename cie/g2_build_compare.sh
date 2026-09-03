#!/bin/bash
# G2 构建门禁 —— Dockerfile 构建后、与上一版镜像对比（CIE）
# 用法: bash g2_build_compare.sh <新镜像tag> <上一版镜像tag>
# 三对账: 1) 组件 git 状态 2) 关键文件 md5 3) import 自检
# 方法论来自 DSpark 归档实战（曾借此抓出 patch 与镜像差 3 个组件的事故）
set -euo pipefail

NEW="${1:?用法: bash g2_build_compare.sh <新tag> <上一版tag>}"
OLD="${2:?需要上一版镜像 tag 作对照}"
run_img() { docker run --rm --entrypoint /bin/bash "$1" -c "$2" 2>/dev/null; }

echo "=== G2 双镜像对比: $NEW vs $OLD ==="

# --- 1. Python 版本 ---
echo "--- Python 版本 ---"
o=$(run_img "$OLD" '/usr/local/python3*/bin/python3 -V 2>/dev/null || python3 -V')
n=$(run_img "$NEW" '/usr/local/python3*/bin/python3 -V 2>/dev/null || python3 -V')
[ "$o" = "$n" ] && echo "[PASS] $n" || { echo "[FAIL] $o vs $n"; exit 1; }

# --- 2. 组件 git 状态对账（HEAD + diff 统计全等） ---
echo "--- 组件 git 状态 ---"
FAIL=0
for comp in verl vllm-ascend MindSpeed-LLM Megatron-LM MindSpeed mbridge ops-transformer; do
  o=$(run_img "$OLD"  "cd /workspace-verl/$comp 2>/dev/null && git log --oneline -1 | cut -c1-8 && git diff HEAD --stat | tail -1" | tr '\n' ' ')
  n=$(run_img "$NEW"  "cd /workspace-verl/$comp 2>/dev/null && git log --oneline -1 | cut -c1-8 && git diff HEAD --stat | tail -1" | tr '\n' ' ')
  if [ "$o" = "$n" ]; then
    echo "  MATCH  $comp ($o)"
  else
    echo "  DIFF   $comp"; echo "    old: $o"; echo "    new: $n"
    FAIL=1
  fi
done
# 差异不一定是失败——预期内的差异（本次变更目标）须在验收说明中列出

# --- 3. 关键文件 md5 ---
echo "--- 关键文件 md5（按模型在 KEY_FILES 配置） ---"
KEY_FILES=(
  "/usr/local/python3*/lib/python3*/site-packages/vllm/config/speculative.py"
  # ... 按模型补充
)
for f in "${KEY_FILES[@]}"; do
  o=$(run_img "$OLD" "md5sum $f 2>/dev/null | cut -d' ' -f1")
  n=$(run_img "$NEW" "md5sum $f 2>/dev/null | cut -d' ' -f1")
  [ "$o" = "$n" ] && echo "  MATCH  $(basename $f)" || echo "  DIFF   $f"
done

# --- 4. import 自检 ---
echo "--- import 自检 ---"
CHECK='PYTHONPATH=/workspace-verl python3 -c "from vllm_ascend.spec_decode.dspark_proposer import AscendDSparkProposer" 2>/dev/null && echo IMPORT-OK || echo IMPORT-FAIL'
o=$(run_img "$OLD"  "$CHECK"); n=$(run_img "$NEW" "$CHECK")
echo "  old: $o | new: $n"

echo "=== G2 完成（DIFF 项须逐条核对为预期变更） ==="
[ "$FAIL" = 0 ] || echo "!! 存在组件差异——确认全部属于本次变更目标后才可过 G2"
