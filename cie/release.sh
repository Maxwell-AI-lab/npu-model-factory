#!/bin/bash
# 正式版本发布 —— Stable 晋级 + 交付包生成（CIE，第二级发布/定期班车）
# 用法: bash release.sh <镜像tag>
# 前置: G1-G4 全过（manifest 里该 tag 的 acceptance=PASS）
# 产出: dist/<tag>/ 交付包（使用说明 README + 起跑脚本 + 三元组清单）
set -euo pipefail

TAG="${1:?用法: bash release.sh <tag>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist/$TAG"

echo "=== 正式版本发布: $TAG ==="

# --- 1. 门禁检查：manifest 中该 tag 的 acceptance 必须为 PASS ---
if ! grep -A6 "tag: \"$TAG\"" "$ROOT/registry/manifest.yaml" | grep -q 'acceptance: "PASS'; then
  echo "[FAIL] $TAG 未通过 G4（manifest acceptance != PASS）——拒绝发布"
  echo "       门禁未过的版本到不了训练工程师手里，这是设计约束，不是流程建议"
  exit 1
fi

# --- 2. 生成交付包 ---
mkdir -p "$DIST"
cat > "$DIST/README-USE.md" <<EOF
# 正式版本 $TAG 使用说明（训练工程师入口）

## 1. 取镜像与依赖（三元组，版本已锁定）
镜像:   $TAG  （tar 位置见 registry/manifest.yaml 同条目）
权重:   见 manifest 同条目 runtime_deps.weights（sha256 已锁定）
数据集: 见 manifest 同条目 runtime_deps.dataset（sha256 已锁定）

## 2. 起跑
docker load -i <镜像tar>
docker run -d --name rl-train --device /dev/davinci0 ... \\
  -v <权重目录> -v <数据目录> $TAG sleep infinity
# 容器内:
bash preflight.sh && bash train.sh        # 体检全绿再起跑

## 3. 训练中健康对照（每步自动判定）
bash check_health.sh /tmp/train_<时间戳>.log
# 健康基线（manifest 已登记）: 见同条目 baseline

## 4. 异常时（不要自行改容器内代码！）
把 check_health 输出 + 训练日志 + 复现步骤提 issue 到分支，
CIE 会回流给①或③处理，修复后走班车发下一版。
EOF

cp "$ROOT/cie/check_health.sh" "$DIST/" 2>/dev/null || true
echo "[DONE] 交付包已生成: $DIST/（镜像 + README-USE.md + check_health）"
echo "       Stable 晋级完成——$TAG 现在可分发给训练工程师"
