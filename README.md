# NPU Model Factory

> 昇腾 NPU 大模型适配 × 后训练 RL 全流程平台方案：四角色协作、CIE 质量中枢、
> 两级发布、全程可溯源。

**[📊 打开交互全景图](https://maxwell-ai-lab.github.io/npu-model-factory/)** ——
四角色泳道 / CIE 串行管线 / G1-G4 门禁 / 两级发布节奏，一图看懂。

## 方案设计（先读）

[DESIGN.md](DESIGN.md) —— 四角色体系、CIE 串行管线（合并管理→质量门禁→
镜像制作→正式发布）、两级发布（基础版事件驱动 / 正式版定期班车）、
资产与溯源铁律、G1-G4 与 S1-S5 体系总纲。

## 按角色进入

| 你是 | 入口 | 你要做的 |
|---|---|---|
| **① 模型适配工程师** | [roles/ROLES.md](roles/ROLES.md) §① + [templates/model-workspace/](templates/model-workspace/) | 新模型 → 9宫格分析 → 分层验证 → 补丁归档 |
| **③ 特性开发工程师** | [roles/ROLES.md](roles/ROLES.md) §③ + [templates/feature-dev/WORKFLOW.md](templates/feature-dev/WORKFLOW.md) | 基于基础版外挂开发 → 整树重生成 patch → PR |
| **CIE 工程师** | [docs/quality-gates.md](docs/quality-gates.md) + [cie/](cie/) | G1-G4 门禁 → 镜像制作 → 定期班车发布 |
| **② 训练工程师** | [registry/manifest.yaml](registry/manifest.yaml) + 交付包内 README-USE | docker load → preflight → 训练 → check_health |

## 核心目录

```
├── DESIGN.md / index.html    # 方案总纲 / 全景图
├── roles/                    # 四角色职责与输入输出
├── cie/                      # G1-G4 门禁 + release + check_health（可执行）
├── registry/                 # 镜像台账（三元组）+ 数据集登记
├── templates/                # ①工作区 / ③流程 / Dockerfile 模板
├── docs/                     # 门禁详规 + S1-S5 验收场景矩阵
└── knowledge/                # NPU 通用坑（G1-G7 种子，来自实战）
```

## 已实战验证的部分

本方案不是纸面设计——DSpark（DeepSeek V4 Flash + 投机解码 RL，TPOT 2.6×、
65 步 pearson 0.996+）完整交付即按此流程走通：完整 Dockerfile 重建 + 双镜像
对比验收、check_health 日志门禁、五条铁律、S1+S2 复合验收，全部落地过。
实战交付仓：[versatile-ai/automodelwire · model-factory-deepseek](https://github.com/versatile-ai/automodelwire/tree/model-factory-deepseek)。

## License

MIT
