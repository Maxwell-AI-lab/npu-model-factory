# DSV4.1-Flash RL 镜像（dsv41-rl-stack）介绍与使用指南

> 2026-10-30 ｜ 作者：Maxwell ｜ 适用对象：DSV4.1-Flash NPU 后训练相关的同事
> 镜像已归档华为云 SWR，pull 即用；本文自包含（版本清单/使用命令/验收标准/已知问题/补丁说明）。

---

## 1. 这是什么

**DSV4.1-Flash 在昇腾 910b 上的"训练+推理"一体化 RL 全栈容器**：

- 基座：华为官方 CANN 镜像（9.2.0 / 9.1.0 双版本）
- 内容：menjiantong 四仓代码栈的 **commit 级完整复刻**（FSDPTurbo 训练引擎 + verl RL 编排 + vLLM v0.30.0 + vllm-ascend NPU 推理插件，含全套 AscendC DSA 内核）
- 已验证：单机 8 卡 GRPO 训练闭环跑通，训推一致性 pearson **0.9986**（远超 0.98 健康线）

## 2. 镜像身份

| 项 | CANN 9.2.0 版（推荐） | CANN 9.1.0 版（保守） |
|---|---|---|
| SWR tag | `verdaf3f7ee-cann9.2.0-910b-vllm0.30.0-fsdpturbo` | 同名 `…cann9.1.0-910b…`（待推送，tar 在 SFS） |
| digest | `sha256:3eda9fd7…661549a` | `sha256:3481bcd8…`（docker 本地） |
| 体积 | 21.9GB 解压 / 7.9GB 压缩 21 层 | 21.4GB / 7.3GB |
| L1 算子/卡上计算 | ✅（.131 实测） | ✅（.155 实测） |
| L2 8 卡引擎+生成 | ✅ | ✅ |
| L3 GRPO 训练闭环 | 9.1.0 同代码版 ✅（4 步全绿）；920 版进行中 | ✅ pearson 0.9986/0.0063 |

```bash
docker pull swr.ap-southeast-1.myhuaweicloud.com/aura_agentic/dsv41-rl-stack:verdaf3f7ee-cann9.2.0-910b-vllm0.30.0-fsdpturbo
```

**两版唯一差异 = CANN 基座**（其余逐字节同源）。选型依据：vllm-ascend README 钉 `CANN == 9.1.0`（含 10-28 的上游 main），9.2.0 为前瞻验证版（torch-npu 2.10.0.post4 × 9.2.0 已实测兼容）。

## 3. 内容四层

### 源码层（四仓完整源码，editable 安装=改码即生效）

| 目录（容器内） | 角色 | commit | 来源分支 |
|---|---|---|---|
| `/workspace-verl/FSDPTurbo` | 训练引擎：NPU FSDP2 并行框架（华为 Ascend 官方项目），V4.1 训练模型/TND packed/Engram 稀疏训练 | `74cc04d` | dev_dsv41_1019 |
| `/workspace-verl/verl` | RL 编排：注册 fsdp_turbo_dsv41 引擎、ZMQ 权重同步、pearson 一致性监控、60 个实验脚本（my_scripts/） | `daf3f7ee` | dev-dsv41-1028 |
| `/workspace-verl/vllm-ascend-v41-private` | 推理 NPU 插件：DSA 稀疏注意力 AscendC 全套内核（含 scatter 越界修复）、engram host-UVA、双平面注意力 | `6cc70b03` | local_run |
| `/workspace-verl/vllm` | 推理引擎本体：vLLM v0.30.0（empty 插件壳） | `ced6857af` | releases/v0.30.0 |

目录名特意对齐 menjiantong 的 PYTHONPATH 约定——**他的启动脚本拿来即用**。

### 系统层
CANN 9.2.0（toolkit+ops+NNAL）｜Ubuntu 22.04｜Python 3.12｜aarch64｜gcc/cmake/clang-15｜mooncake 0.3.11.post1

### 编译产物层
vllm_ascend_C 绑定 + libvllm_ascend_kernels + ACLNN 自定义算子包（DSA/QLI/scatter/GMM/MoE 全套 NPU 内核，按 ascend910b3 编译）+ catlass@41bf90da + Rust tool parser

### 不含（有意）
权重、数据集、.git——挂载使用

## 4. 组件版本全表（镜像内 importlib 实测）

| 组件 | 版本 | 钉定来源 |
|---|---|---|
| CANN | 9.2.0 / 9.1.0 | 基座镜像 tag |
| vllm | 0.30.0+empty | vllm-ascend Dockerfile VLLM_TAG |
| vllm-ascend | 0.30.0 | local_run 分支 |
| FSDPTurbo | 0.1.0 | — |
| verl | 0.10.0.dev0 | fork |
| torch | 2.10.0+cpu | vllm-ascend requirements.txt |
| torch-npu | 2.10.0.post4 | 同上（×CANN 9.2 兼容性已 L1 实证） |
| triton-ascend | 3.2.2 | 同上 |
| transformers | 5.10.4 | vllm 0.30 自带 pin |
| ray | 2.48.0 | Dockerfile |
| fla-core / flash-linear-attention | 0.6.0 | FSDPTurbo [npu] extra |
| cann-ops-transformer | 1.0.0（占位⚠️） | pip（完整包缺失→eager 慢路径，见 §8） |
| TransferQueue | 0.1.12.dev0 | verl requirements-npu |
| numpy / pandas | 2.5.4 / 3.0.6 ⚠️ | 见 §8 |

## 5. 使用方法

### 三大必要条件（缺一翻车，均实测踩出）

1. `-e PYTHONPATH=/workspace-verl/vllm:/workspace-verl/vllm-ascend-v41-private:/workspace-verl/FSDPTurbo:/workspace-verl/verl`（否则 import vllm 被仓库名劫持）
2. `--shm-size 64g`（默认 64M 引擎通信必炸）
3. `-e ASCEND_VISIBLE_DEVICES=<卡号>` + `-e DEVICE=npu`（宿主 docker 默认 runtime=ascend 时设备自动注入；DEVICE 显式传防自动探测被驱动警告污染）

### 场景 A：交互探索

```bash
docker run -it --network host --shm-size 64g \
  -e ASCEND_VISIBLE_DEVICES=0 -e DEVICE=npu -e PYTHONPATH=<同上> \
  -v /data:/data dsv41-rl-stack:920 bash
# 进容器: source /etc/profile.d/ascend.sh
# 自检: python3 -c "import torch,torch_npu;import vllm_ascend.vllm_ascend_C;print(torch.npu.is_available())"
```

### 场景 B：推理 serve

```bash
docker run -d --name serve --network host --shm-size 32g \
  -e ASCEND_VISIBLE_DEVICES=0-7 -e PYTHONPATH=<同上> -v /data:/data:ro dsv41-rl-stack:920 \
  bash -c "source /etc/profile.d/ascend.sh && vllm serve /data/<模型目录> \
    --tensor-parallel-size 8 --max-model-len 4096 --gpu-memory-utilization 0.5 \
    --enforce-eager --tokenizer-mode deepseek_v41 --port 8109"
curl http://localhost:8109/v1/completions -H 'Content-Type: application/json' \
  -d '{"model":"/data/<模型目录>","prompt":"1+1=","max_tokens":32}'
```
模型目录需含 config.json + tokenizer.json + tokenizer_config.json（带 chat_template）。快速冒烟可加 `--load-format dummy`。

### 场景 C：GRPO 训练（colocate 单机 8 卡）

```bash
docker run -d --name rl --network host --shm-size 64g \
  -e ASCEND_VISIBLE_DEVICES=0-7 -e DEVICE=npu -e PYTHONPATH=<同上> \
  -e USE_KL=0 -e VLLM_ENGRAM_DP_SHARED_MEMORY=0 -e MAX_RESPONSE_LEN=256 \
  -e MODEL_PATH=/data/<权重目录> -e TOKENIZER_PATH=/data/<权重目录> \
  -e TRAIN_FILE=/data/<train.parquet> -e TEST_FILE=/data/<test.parquet> \
  -e CKPTS_DIR=/data/<ckpt输出> -e WORKING_DIR=/workspace-verl -e EXPERIMENT_NAME=exp1 \
  -v <补丁目录>/trainer_base.py:/workspace-verl/verl/verl/trainer/ppo/v1/trainer_base.py:ro \
  -v <补丁目录>/verl_model.py:/workspace-verl/verl/verl/utils/model.py:ro \
  -v /data:/data dsv41-rl-stack:920 \
  bash -c "source /etc/profile.d/ascend.sh && cd /workspace-verl && bash <l3-run.sh 路径>"
```

**物料三件**（全套现成样例=权重切片/启动脚本/补丁/数据，向作者索取）：
1. **权重**：HF 格式目录，`engram_layer_ids` 置空（单机放不下 engram 表）；切片模板=top16/（40 层×16 专家 61GB 真实权重，含切片脚本）
2. **数据 parquet**：列 `data_source/prompt/reward_model`；data_source 用 `math_dapo` 或 `openai/gsm8k`（奖励白名单）
3. **两个补丁必须挂载**（fork 的 KL-off GRPO 缺陷修复，见 §7）

**验收指标**（step 日志自动打印）：`rollout_actor_probs_pearson_corr ≥0.98`、`rollout_probs_diff_mean ~1e-2`、`timing_s/*` 分段耗时。

## 6. 验证成绩单

| 级 | 内容 | 结果 |
|---|---|---|
| L0 | 构建期四仓 import 冒烟 | ✅ |
| L1 | NPU 识别 + 卡上计算 + DSA 六算子注册（npu_sparse_flash_mla / npu_scatter_nd_update_sk / npu_quant_lightning_indexer_v3 等） | ✅（910/920 双版本） |
| L2 | 8 卡 TP8 vLLM 引擎 + 真实生成请求 | ✅（双版本；920 与 910 的 dummy 生成几乎逐 token 一致=跨版本数值一致彩蛋） |
| L3 | GRPO 训练闭环（生成→奖励→优势→反向→权重同步） | ✅ 910 版 4 步全绿：**pearson 0.9986 / diff 0.0063，四步稳定**；920 版进行中 |
| 附 | grad_norm=0 属预期 | 随机/切片权重答不对题→奖励全 0→零优势；真训练需 SFT 起点权重（同 menjiantong top32-sft116 实践） |

## 7. 相对 menjiantong 原样的三处补丁（全部归档，bind-mount 应用、镜像 digest 不受影响）

| # | 文件 | 问题 | 修法 |
|---|---|---|---|
| 1 | `verl/.../trainer_base.py` | fork 缺陷：`_compute_advantage`/`_compute_metrics` 无条件 GET `ref_log_prob`/`values`，而 KL-off+GRPO 下无人写入 → TransferQueue 报 "not ready" | fields 按 use_reference_policy/use_critic 条件化；写回处补齐 token_level_rewards + 零值 values |
| 2 | `verl/.../utils/model.py` | 兜底导入 `patch_deepseek_v41_config` 只捕获 ImportError，驱动管理接口偶发故障（get_arch NULL）时 SystemError 打穿 | except 扩为 (ImportError, SystemError) |
| 3 | 构建层（已在镜像内） | git-archive 源码无 .git：setuptools-scm 推不出版本；build_aclnn 拉不到 catlass submodule | SETUPTOOLS_SCM_PRETEND_VERSION + catlass@41bf90da 预置 |

**建议回馈 menjiantong**：补丁 #1/#2 他的 KL-off 组合同样会踩。

## 8. 已知问题与边界

| 项 | 状态 | 影响 |
|---|---|---|
| cann-ops-transformer 只有占位轮 | fused 算子（attention-residuals 等）运行时探测失败→eager 慢路径 | 正确性无影响（pearson 覆盖）；性能慢数倍；v2 待办=从 menjiantong 环境取完整包 |
| numpy 2.5.4 违反 verl numpy<2 约束 | pip 冲突被忽略 | 已跑通 dataloader/训练；深水区理论风险；v2 钉回 |
| mc2 fullmesh_v2 | 910b3 硬件画像不支持 | 用 fullmesh v1（l3-run.sh 已改） |
| 多机训练 | 需 `VERL_DSV41_DIRECT_SHARD_LOAD=1`（跨机 Gloo 仅 30MB/s） | 参考 verl/my_scripts/dsv41_grpo_2node_new.sh |
| Engram | 单机不可用（表 197B 参数需 ~400GB host 起） | 全链路 engram 关闭；与 menjiantong full_noengram 生产线一致 |
| 首启 | ~20-25 分钟（装载+引擎） | 栈固有成本 |

## 9. 故障速查

| 症状 | 处置 |
|---|---|
| `ImportError: libtorch.so` | 先 import torch 再 import vllm_ascend.vllm_ascend_C |
| `Insufficient /dev/shm` | 加 --shm-size |
| `import vllm` 命中空命名空间 | PYTHONPATH 没带/顺序错 |
| `Reward function not implemented for data_source=…` | data_source 改 math_dapo/openai-gsm8k |
| `Fields ['values'] not ready` | 两个补丁没挂载 |
| `mc2 fullmesh_v2 not supported` | 换 fullmesh |
| `npu: False` 但有空卡 | 先 npu-smi 查占卡（同事容器/ray 集群），别急着怀疑镜像 |

## 10. 血统与复现

- 构建：外置 buildkit，配方=项目根 `Dockerfile.dsv41-rl-stack`（官方 vllm-ascend Dockerfile 扩展）+ 四仓 git-archive 导出 + catlass 预置；构建上下文钉死 commit，任何人可复现（缓存命中后重建分钟级）
- 排坑记录（10 构建坑 + 10 训练轮）：详见验证报告与 patches/ 归档（向作者索取）
- 素材：top16 权重切片、启动脚本+补丁+数据套件、双版本 tar（内网共享存储，向作者索取）

---

*本文由镜像构建与验证过程的第一手记录整理；所有版本号均为镜像内实测，所有验证结论均有日志证据。*
