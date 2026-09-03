# 质量门禁 G1-G4 详规（CIE 执行手册）

每道门禁：时机 / 验什么 / 通过标准 / 工具 / 未过处置。
原则：门禁未过的版本**到不了训练工程师手里**——这是设计约束，不是流程建议。

## G1 代码门禁（PR 合入前）

| 项 | 内容 |
|---|---|
| 时机 | ①补丁归档 / ③PR / ②故障回流修复，任一进入分支前 |
| 验什么 | patch 可应用性（基线校验）、关键 import、PR 自验完整性 |
| 通过标准 | `git apply --check` 干净通过；import 自检 OK；PR 附 check_health ≥5 步输出；特性 PR 附实证指标 |
| 工具 | `cie/g1_code_gate.sh` |
| 未过处置 | 拒收。要求提交者从最新分支重 fetch_sources 后整树重生成（铁律 1/2） |

## G2 构建门禁（Dockerfile build 后）

| 项 | 内容 |
|---|---|
| 时机 | CIE 构建出新镜像后、登记前 |
| 验什么 | 与上一版镜像逐项对账：Python 版本 / 7 组件 git 状态（HEAD+diff 统计）/ 关键文件 md5 / import 自检 |
| 通过标准 | 无预期外差异。**有差异 ≠ 自动失败**——每条 DIFF 必须能对应到本次变更目标，出现说明不了的差异即停 |
| 工具 | `cie/g2_build_compare.sh`（方法论：DSpark 归档实战，曾抓出 patch 与镜像差 3 组件的事故） |
| 未过处置 | 排查漂移来源（常见：staged 改动丢失、容器直改未回流、基础镜像变化） |

## G3 镜像门禁（发布登记前）

| 项 | 内容 |
|---|---|
| 时机 | G2 通过后 |
| 验什么 | 冒烟（容器能起 + 关键 import）+ manifest 三元组登记完整性 |
| 通过标准 | 冒烟 IMPORT-OK；manifest 条目含镜像 sha256、权重/数据 sha256、场景类型、基线占位 |
| 工具 | `cie/g3_image_register.sh`（tar 已导出时自动算 sha256） |
| 锁定件 | `cie/verify_runtime.sh`——发布锁定与②起跑校验共用一套（不匹配拒绝起跑） |
| 未过处置 | 补全登记项；sha256 由提供方（①或 CIE）实测填写，不留空发布 |

## G4 运行门禁（发布前最后一关）

| 项 | 内容 |
|---|---|
| 时机 | G3 通过后、release 前 |
| 验什么 | ≥5 步训练：pearson ≥0.995 且无逐 step 漂移 / score ≥0.80 / TPOT ≤15ms / clip_ratio ≤0.5 / 零乱码 / 零崩溃特征 |
| 通过标准 | 全部步 OK + 乱码 0 + 崩溃 0；S1 首版同时把实测均值回填 manifest baseline |
| 工具 | `cie/g4_run_acceptance.sh`（日志格式经 DSpark Run C/D 实测验证） |
| 未过处置 | 按 WARN 提示定位（pearson↓→权重同步；TPOT↑→投机接受率；全截断→训练没学）|

## 与场景矩阵的对应

G4 的验收深度按 `docs/acceptance-matrix.md` 的 S1-S5 场景调整：
S5 重构只到 G2（等价性证明）即可；S1/S3 需全 G1-G4 + 历史坑复查。

## 起跑校验（verify_runtime.sh，②侧）

manifest 三元组的消费端：②起跑前执行，权重/数据 sha256 实测对账，
不匹配直接拒绝——避免"换批权重/数据被重新生成"导致基线对照失真。
CIE 发布时用同一脚本生成目录指纹回填登记。

前置 manifest 中该 tag `acceptance: "PASS"`。产出交付包：
使用说明 README（取镜像/起跑/健康对照/异常回流四段）+ check_health + 三元组清单。
Stable 晋级完成即分发给②。
