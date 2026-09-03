#!/bin/bash
# G3 镜像门禁 —— 冒烟 + manifest 登记（三元组锁定）（CIE）
# 用法: bash g3_image_register.sh <镜像tag> <场景类型 S1-S5> [备注]
# 登记: 镜像 sha256 + 权重/数据 sha256（三元组）+ 基线指标占位
set -euo pipefail

TAG="${1:?用法: bash g3_image_register.sh <tag> <S1-S5> [备注]}"
SCENE="${2:-S1}"
NOTE="${3:-}"
REGISTRY="$(cd "$(dirname "$0")/.." && pwd)/registry/manifest.yaml"

echo "=== G3 镜像门禁: $TAG ($SCENE) ==="

# --- 1. 冒烟：容器能起、关键 import 通过 ---
docker run --rm --entrypoint /bin/bash "$TAG" -c '
  PYTHONPATH=/workspace-verl python3 -c "
from vllm_ascend.spec_decode.dspark_proposer import AscendDSparkProposer
print(\"smoke IMPORT-OK\")"' || { echo "[FAIL] 冒烟失败"; exit 1; }

# --- 2. 镜像 sha256 ---
IMG_SHA=$(docker inspect "$TAG" --format '{{.Id}}' | sed 's/sha256://;s/.\{16\}$/&/' | cut -c1-64)
TARBALL_SHA="(docker save 后 sha256sum 补填)"

# --- 3. 三元组登记（权重/数据 sha256 由提供方填） ---
DATE=$(date +%F)
cat >> "$REGISTRY" <<EOF

# ---- $TAG ($SCENE, $DATE) $NOTE ----
- tag: "$TAG"
  scene: "$SCENE"
  date: "$DATE"
  image:
    id: "sha256:${IMG_SHA:0:12}…"
    tarball_sha256: "$TARBALL_SHA"        # TODO: save 后补
  runtime_deps:                            # 三元组（起跑前 verify_runtime 校验）
    weights: {path: "", sha256: "TODO"}   # TODO: ①或CIE填写
    dataset:  {path: "", sha256: "TODO"}  # TODO
  baseline:                                # 该三元组下的健康基线（G4 实测后回填）
    pearson: ""
    tpot_ms: ""
    score: ""
  acceptance: "PENDING-G4"                 # G4 通过后改为 PASS + 结论链接
EOF
echo "[DONE] 已登记到 registry/manifest.yaml（TODO 项补全后才可发布）"
