#!/bin/bash
# G4 运行门禁 —— ≥N 步训练，指标对照基线（CIE，发布前最后一关）
# 用法: bash g4_run_acceptance.sh <训练日志> [最少步数]
# 判定: pearson≥0.995 无漂移 / score≥0.80 / TPOT≤15 / clip_ratio≤0.5
#        / 零乱码 / 零崩溃特征
# 字段格式取自 verl 控制台日志实测（DSpark Run C/D 验证）
set -euo pipefail

LOG="${1:?用法: bash g4_run_acceptance.sh <训练日志> [最少步数]}"
MIN_STEPS="${2:-5}"

echo "=== G4 运行验收（要求 ≥$MIN_STEPS 步） ==="
printf "%-5s %-9s %-8s %-7s %-8s %-7s %s\n" STEP PEARSON SCORE TPOT_ms RESP_LEN CLIPR STATUS
echo "----------------------------------------------------------------------"

total=0; pass=0
while read -r line; do
  step=$(echo "$line"    | grep -oE "^step:[0-9]+"                | cut -d: -f2)
  pearson=$(echo "$line" | grep -oE "pearson_corr:[0-9.]+"        | cut -d: -f2)
  score=$(echo "$line"   | grep -oE "critic/score/mean:[0-9.]+"   | cut -d: -f2)
  tpot=$(echo "$line"    | grep -oE "timing_per_token_ms/gen:[0-9.]+" | cut -d: -f2)
  rlen=$(echo "$line"    | grep -oE "response_length/mean:[0-9.]+"     | cut -d: -f2)
  clipr=$(echo "$line"   | grep -oE "response_length/clip_ratio:[0-9.]+" | cut -d: -f2)

  st="OK"
  awk -v p="$pearson" 'BEGIN{exit !(p<0.995)}' && st="WARN(pearson<0.995,查权重同步)"
  awk -v t="$tpot"   'BEGIN{exit !(t>15)}'    && [ "$st" = OK ] && st="WARN(TPOT>15,查投机接受率)"
  awk -v s="$score"  'BEGIN{exit !(s<0.80)}'  && [ "$st" = OK ] && st="WARN(score<0.80,查训练数学)"
  awk -v c="$clipr"  'BEGIN{exit !(c>0.5)}'   && [ "$st" = OK ] && st="WARN(全截断,模型没在学)"
  [ "$st" = "OK" ] && pass=$((pass+1))
  total=$((total+1))
  printf "%-5s %-9s %-8s %-7s %-8s %-7s %s\n" "$step" "$pearson" "$score" "$tpot" "$rlen" "$clipr" "$st"
done < <(grep -oE "step:[0-9]+ - .*timing_per_token_ms/gen:[0-9.]+" "$LOG" 2>/dev/null)

echo "----------------------------------------------------------------------"
garbled=$(grep "REWARD_DEBUG" "$LOG" 2>/dev/null | grep -cP "[\x{0400}-\x{04FF}\x{0370}-\x{03FF}\x{AC00}-\x{D7AF}]" || true)
crash=$(grep -ciE "ACL stream synchronize failed|aicpu exception|sample_tokens RPC timeout" "$LOG" 2>/dev/null || true)
echo "乱码特征行: $garbled（0 为正常） | 崩溃特征行: $crash（0 为正常）"

echo "----------------------------------------------------------------------"
if [ "$total" -lt "$MIN_STEPS" ]; then
  echo "[FAIL] 仅 $total 步（要求 ≥$MIN_STEPS）"; exit 1
fi
if [ "$garbled" != 0 ] || [ "$crash" != 0 ] || [ "$pass" != "$total" ]; then
  echo "[FAIL] 存在异常项（上方 WARN/乱码/崩溃），不可发布"; exit 1
fi
echo "[PASS] $total/$total 步全部达标 —— G4 通过，可进入正式发布"
echo "       （S1 首版：把本输出的 pearson/TPOT/score 均值回填 manifest 的 baseline）"
