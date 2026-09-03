# ③ 特性开发工作流（从基础版到 PR）

> 模板用法：照此流程走，产出物提交给 CIE（PR）。五条铁律见 DESIGN.md §4。

## 1. 起点：基于①发布的基础版本

```bash
git clone -b <平台分支> <交付仓>
bash scripts/fetch_sources.sh ~/src          # 生成源码树 = 基线 + 全部 patch
docker run -d --name dev --device /dev/davinci0 ... \
  -v ~/src/verl:/workspace-verl/verl \
  -v ~/src/vllm-ascend:/workspace-verl/vllm-ascend \
  <基础版镜像 vN> sleep infinity             # 外挂源码，即改即生效
```

## 2. 开发与自验

- 改 `~/src/<组件>/...` → 容器内直接生效 → 冒烟（preflight 全绿 + step1 正常）
- **特性生效实证**：拿到量化指标（加速比/接受率/吞吐对比），"没报错"不算
- **精度不回退**：check_health ≥5 步对照基础版基线
- **可回退**：特性开关关闭后走原路径正常

## 3. 回流（整树重生成，铁律 1-3）

```bash
cd ~/src/<组件>
git add -A
git diff HEAD > /tmp/<组件>.patch            # ★git diff HEAD（含 staged）
# 全新文件（stock 不存在）拷 overlay/new-files/ 并登记放置路径
```

## 4. 提交 CIE（PR 内容清单）

- [ ] 新版 `<组件>.patch`（覆盖 overlay/ 同名文件）
- [ ] 新文件在 `overlay/new-files/` + fetch_sources 的 cp 行
- [ ] check_health 输出（≥5 步全 OK）
- [ ] 特性实证指标（A/B 对比数据）
- [ ] overlay/README 文件计数更新

## 5. 等待班车

CIE 合并（G1）→ 构建（G2）→ 下一次定期班车随其他特性一起正式发布（vN.x-<特性集>）。
紧急情况可申请插班。
