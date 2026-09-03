#!/bin/bash
# G4 运行门禁 —— ≥N 步训练，指标对照基线（CIE，发布前最后一关）
# 用法: bash g4_run_acceptance.sh <训练日志> [最少步数]
# 实现: 明细解析复用 check_health.sh（单一解析源，②日常监控与 CIE 验收
#       共用一套字段规则——字段格式经 DSpark Run C/D 实测验证），
#       本脚本叠加步数门槛 + 乱码/崩溃判定 + 发布结论
set -euo pipefail

LOG="${1:?用法: bash g4_run_acceptance.sh <训练日志> [最少步数]}"
MIN_STEPS="${2:-5}"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "=== G4 运行验收（要求 ≥$MIN_STEPS 步） ==="

# --- 1. 明细与判定：复用 check_health（同一套解析）---
CH_OUT=$(bash "$HERE/check_health.sh" "$LOG" 2>/dev/null || true)
echo "$CH_OUT"

# --- 2. 步数门槛 ---
STEPS=$(echo "$CH_OUT" | grep -cE "^ *[0-9]+ +0?\.9" || echo "$CH_OUT" | grep -cE "pearson" )
STEPS=$(echo "$CH_OUT" | awk 'NR>2 && /^ *[0-9]+ /{n++} END{print n+0}')
if [ "$STEPS" -lt "$MIN_STEPS" ]; then
  echo "[FAIL] 仅 $STEPS 步（要求 ≥$MIN_STEPS）"; exit 1
fi

# --- 3. 异常项判定（WARN / 乱码 / 崩溃）---
WARNS=$(echo "$CH_OUT" | grep -c "WARN" || true)
GARBLED=$(echo "$CH_OUT" | grep -oE "乱码特征行数?[:：] *[0-9]+" | grep -oE "[0-9]+" || echo 0)
CRASH=$(echo "$CH_OUT"  | grep -oE "崩溃特征行数?[:：] *[0-9]+" | grep -oE "[0-9]+" || echo 0)
if [ "$WARNS" != 0 ];  then echo "[FAIL] 存在 $WARNS 条 WARN——不可发布"; exit 1; fi
if [ "$GARBLED" != 0 ]; then echo "[FAIL] 乱码特征 $GARBLED 行——不可发布"; exit 1; fi
if [ "$CRASH" != 0 ];  then echo "[FAIL] 崩溃特征 $CRASH 行——不可发布"; exit 1; fi

echo "----------------------------------------------------------------------"
echo "[PASS] $STEPS 步全部达标 —— G4 通过，可进入正式发布（release.sh）"
echo "       （S1 首版：把 check_health 输出的 pearson/TPOT/score 回填 manifest baseline）"
