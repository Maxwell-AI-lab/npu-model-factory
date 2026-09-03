#!/bin/bash
# 训练日志健康检查：提取关键指标并与 v30-fixed 基线对照
# 用法: bash check_health.sh /path/to/train.log
# 基线来源: doc/开发工作流与健康基线.md（Run C/D 65 步实测）

LOG="${1:?用法: bash check_health.sh /path/to/train.log}"
[ -f "$LOG" ] || { echo "日志不存在: $LOG"; exit 1; }

printf "%-5s %-9s %-8s %-7s %-8s %-7s %s\n" STEP PEARSON SCORE TPOT_ms RESP_LEN CLIPR STATUS
echo "--------------------------------------------------------------------------------"

n_pass=0; n_warn=0
grep -oE "step:[0-9]+ - .*timing_per_token_ms/gen:[0-9.]+" "$LOG" 2>/dev/null | \
while read -r line; do
  step=$(echo "$line"     | grep -oE "^step:[0-9]+"            | cut -d: -f2)
  pearson=$(echo "$line"  | grep -oE "pearson_corr:[0-9.]+"    | cut -d: -f2)
  score=$(echo "$line"    | grep -oE "critic/score/mean:[0-9.]+" | cut -d: -f2)
  tpot=$(echo "$line"     | grep -oE "timing_per_token_ms/gen:[0-9.]+" | cut -d: -f2)
  rlen=$(echo "$line"     | grep -oE "response_length/mean:[0-9.]+"    | cut -d: -f2)
  clipr=$(echo "$line"    | grep -oE "response_length/clip_ratio:[0-9.]+" | cut -d: -f2)

  # 基线判定（见 doc/开发工作流与健康基线.md）
  st="OK"
  awk -v p="$pearson" 'BEGIN{exit !(p<0.995)}'              && st="WARN(pearson<0.995,查权重同步)"
  awk -v t="$tpot"    'BEGIN{exit !(t>15)}'                 && [ "$st" = OK ] && st="WARN(TPOT>15,查投机接受率)"
  awk -v s="$score"   'BEGIN{exit !(s<0.80)}'               && [ "$st" = OK ] && st="WARN(score<0.80,查训练数学)"
  awk -v c="$clipr"   'BEGIN{exit !(c>0.5)}'                && [ "$st" = OK ] && st="WARN(全截断,模型没在学)"
  [ "$st" != "OK" ] && n_warn=$((n_warn+1)) || n_pass=$((n_pass+1))

  printf "%-5s %-9s %-8s %-7s %-8s %-7s %s\n" "$step" "$pearson" "$score" "$tpot" "$rlen" "$clipr" "$st"
done

echo "--------------------------------------------------------------------------------"
echo "乱码检查（REWARD_DEBUG 行内多语言字符特征，0 为正常）:"
garbled=$(grep "REWARD_DEBUG" "$LOG" 2>/dev/null | grep -cP "[\x{0400}-\x{04FF}\x{0370}-\x{03FF}\x{AC00}-\x{D7AF}\x{3040}-\x{30FF}]")
echo "  含多语言乱码特征的行数: $garbled （>0 = 生成乱码，查 enable_reduce_sample 是否被改开）"
echo "崩溃特征检查:"
grep -ciE "ACL stream synchronize failed|aicpu exception|sample_tokens RPC timeout" "$LOG" 2>/dev/null | \
  xargs -I{} echo "  崩溃特征行数: {} （>0 = 有崩溃记录，查 doc/DSpark_集成验证报告.md §7）"
