# NPU 栈通用坑（跨模型，模型无关）

> 种子条目来自 DSpark/DSV4 适配实战（2026-08）。每分析一款模型：
> 模型无关的坑提升到这里，模型专属的留在该模型 reports。宁缺毋滥。

## G1 · 投机解码 + 随机采样的压缩词表路径 bug

- 现象：投机开启时输出尾部退化为多语言乱码
- 根因：`enable_reduce_sample=true` 的 top-k 压缩词表验收路径在
  "随机采样 + 投机"组合下有 bug（官方测试只覆盖 greedy）
- 通用规则：**任何"官方测试未覆盖的组合"都可能埋雷；偏离官方配置的
  每一项都要单独做过对照实验**

## G2 · MoE 权重同步的 w2 布局陷阱

- 现象：训推 pearson 逐 step 缓降（0.993→0.98x）
- 根因：权重同步链路中 MoE w2 的 shape 转置错误——训练侧正确但同步到
  推理侧部分错误
- 通用规则：**pearson 缓降先查权重同步域（CKSUM 探针 bit-exact 对账），
  别先怀疑算法**

## G3 · CP>1 × packed × 稀疏注意力 的段契约崩溃

- 现象：aicpu errorCode=0x2a 级联崩溃，仅 CP rank 1
- 根因：稀疏注意力 kernel 要求段相对索引，CP>1 下全局索引直喂越界
- 通用规则：**上下文并行 >1 是未验证路径；packed 多段 + SFA 组合尤其危险**

## G4 · 官方 python 镜像的 glibc 兼容性

- python:3.12-slim（trixie）要求 glibc ≥2.38；Ubuntu 22.04 底座（2.35）跑不了
- bookworm 变体实测在 2.35 上完全可用
- 通用规则：**COPY --from 提取二进制前先对 glibc；源码编译的 ensurepip
  需要 libssl-dev 等（装齐再编，或直接用官方镜像提取）**

## G5 · pip freeze 快照的安装法

- freeze 是历史叠加快照，内含声明冲突（如 hydra-core vs antlr4），
  新版 pip resolver 会拒装
- 通用规则：**安装 freeze 用 `--no-deps`（闭集快照无需 resolver 重解析）**

## G6 · docker commit 不固化 ENV / 容器与镜像脱节

- commit 只保存文件层；容器 ENV 是 commit 时点状态，后续 export 的改动
  不会进旧镜像
- 通用规则：**改动永远回流 patch（单一事实源）再重建镜像；
  "容器里能跑"不是交付依据**（曾发生容器与镜像差 3 个组件的事故）

## G7 · 强杀训练后的宿主机残留

- 容器重启清不掉宿主机侧 NPU 进程（曾占 57GB HBM 导致引擎起不来）
- 通用规则：**强杀后必须宿主机级清理 + 全量重置（preflight/full_reset 模式）**
