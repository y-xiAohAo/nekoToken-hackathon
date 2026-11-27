---
name: tms-research-assistant
description: Research companion for transcranial magnetic stimulation (TMS) coil optimization, especially multi-target focality, spherical-harmonics-based inverse design, and NSGA-II objective-function engineering. Use when designing experiments, interpreting results, scouting literature, or writing TMS-focused reports.
skill_role: research
---

# TMS Research Assistant

## 1. 领域背景与核心问题

### 1.1 TMS 线圈优化的本质

TMS 线圈设计是一个**逆问题**：给定目标皮层区域的期望电场分布，反推线圈表面（或球面）上的电流分布，使得诱导电场最接近期望。

关键物理：
- 时变电流 → 时变磁场（Biot-Savart）→ 感应电场（Faraday 定律）
- 在准静态近似下，电场可表示为磁矢势 A 的时间导数：E = -∂A/∂t
- 对于球面电流分布，可用**球谐函数（Spherical Harmonics）**展开，解析计算远场

### 1.2 多靶区刺激的核心挑战

> **本项目的阶段性目标：实现三个靶区的完全分离。**

定义：
- **完全分离** = 每个靶区内部电场集中（聚焦面积小）+ 靶区之间间隙地带电场尽可能低（接近零）

当前问题：
- 单线圈/单电流分布要在空间分离的多个位置同时产生强电场，必然在中间区域也产生显著电场
- 传统的"聚焦度"指标只考虑单个靶区，不考虑靶区间耦合

---

## 2. 关键文献与知识地图

### 2.1 本地参考文献（用户课题组）

| 文献 | 核心贡献 | 与本项目关系 |
|------|---------|-------------|
| Carmona et al., IEEE TMAG 2022 | 提出 specific focality (sf) 和 focality form factor (dn)，统一聚焦度评估框架 | 聚焦度指标可扩展为多靶区版本 |
| 刘冀成等, J Biomed Eng 2005 | 遗传算法优化线圈阵列电流幅值/相位，实现多靶区同时聚焦 | **证明 GA 可用于多靶区优化** |
| Mäkinen et al., JAP 2020 (bfieldtools) | 表面流函数 + 三角网格离散 + 球谐/面 Laplacian 展开 | **球谐方法的理论基础** |
| 张文哲硕士论文 | 真实脑模型重建 + Maxwell 仿真 + 24 种线圈结构对比 | 课题组方法学传承 |
| IBEM + streamfunction 系列 | 逆边界元方法计算最优表面电流 | 与球谐方法互补 |

### 2.2 外部关键文献

| 文献 | 核心贡献 | 与本项目关系 |
|------|---------|-------------|
| **Numssen et al., Brain Stimulation 2026** | mTMS 多通道聚焦度优化框架；目标函数 `min |E|²` (off-target)，约束 `|E_target| = e`；指标 Focality / Target2Max / OverstimulatedArea | **最关键参照**：展示了如何用约束优化实现多靶区聚焦，但用的是通道电流而非球谐系数 |
| Liu et al., URSI 2020 | 直接设置目标电场求解流函数，实现 3/4/5 靶点线圈 | 展示了"硬编码目标电场"的逆问题解法 |
| fdTMS (PMC 2026) | 最大聚焦度 + 深度线圈；整数线性规划 + 流函数 + 多层绕组 | 聚焦度-深度权衡的 Pareto 前沿设计 |
| Koponen et al. | 球谐分解用于电流分布优化 | 与当前代码方法直接相关 |

### 2.3 检索策略

**关键词组合**：
```
"multi-target TMS optimization"
"multichannel TMS focality"
"spherical harmonics TMS coil design"
"stream function TMS optimization"
"transcranial magnetic stimulation steering"
"TMS multi-locus coil"
```

**优先数据库**：arXiv, PubMed, Google Scholar, IEEE Xplore (开放获取)
**核心期刊**：Brain Stimulation, IEEE TBME, NeuroImage, J Neural Eng

---

## 3. 方法论：从文献到代码

### 3.1 当前代码的方法论定位

本项目的方法论链条：
```
球谐基函数展开（Mäkinen 2020, Koponen et al.）
    ↓
NSGA-II 多目标优化（刘冀成 2005 的 GA 思路扩展）
    ↓
流函数等高线 → 线圈绕组（标准做法）
```

这与 Numssen 2026 的 mTMS 框架有本质区别：
| 维度 | Numssen 2026 (mTMS) | 本项目 (SH-based) |
|------|---------------------|-------------------|
| 自由度 | 有限通道电流（5-12ch） | 无限自由度（球谐系数） |
| 优化方法 | 约束单目标优化（BFGS） | 多目标进化算法（NSGA-II） |
| 目标函数 | `min |E|²` off-target | `-E_m`, `var(E)`, `penalty(E_else)` |
| 物理模型 | FEM 真实头模型 | 球形头模型 + 解析场 |

### 3.2 目标函数设计的文献启示

**Numssen 2026 的核心公式**（值得借鉴）：
```
Objective:   min |E|² = Jᵀ · Lᵀ · L · J
Constraint:  |E_target|² = Jᵀ · L_targetᵀ · L_target · J = e²
```

**启示**：
1. 他们把"靶区电场恒定"作为**硬约束**嵌入，而不是像我们现在一样作为优化目标（f1 = -E_m）
2. 他们的目标是**单目标**（off-target 能量最小），这避免了多目标之间的内在竞争
3. 代价是：需要为每个靶点单独优化一次，不直接给出"同时多靶区"的解

**对于本项目的改进方向**：
- **方向 A**：引入类似 Numssen 的"off-target 能量最小化"作为独立目标函数 f4
- **方向 B**：将 f1 从"最大化 E_m"改为"最小化 |E_gap|²"（间隙能量），同时用约束保证靶区电场
- **方向 C**：采用加权单目标替代纯多目标，减少 Pareto 竞争

### 3.3 评价指标体系

从文献中提取的关键指标：

| 指标 | 定义 | 来源 |
|------|------|------|
| **FWHM 面积** | 电场超过半峰值的区域面积 | Roth et al., 常规 |
| **Specific Focality (sf)** | 考虑靶区面积、焦距距离、E_max 的无量纲聚焦度 | Carmona 2022 |
| **Focality Form Factor (dn)** | 刺激区域与靶区几何匹配度 | Carmona 2022 |
| **Target2Max** | 靶区电场与全局最大电场的比值 | Numssen 2026 |
| **OverstimulatedArea** | 电场超过阈值的非靶区面积 | Numssen 2026 |
| **Inter-target Gap E** | 靶区对之间走廊地带的平均/最大电场 | **本项目自定义** |

---

## 4. 实验设计指南

### 4.1 目标函数调优的系统性方法

当"降低 threshold_ratio 无效"时（已验证），应尝试：

**阶段 1：惩罚形式改进**
- 线性惩罚 → 平方惩罚：`f3 = Σ W_i · (E_i - threshold)²`
- 理由：线性惩罚对"刚好超过 threshold"和"严重超标"一视同仁，平方惩罚更能驱动"深度抑制"

**阶段 2：绝对阈值**
- 当前：`threshold = E_m × ratio`（相对阈值，随 E_m 水涨船高）
- 改进：`threshold = constant`（如 1e-4 V/m），切断 f1 与 f3 的耦合

**阶段 3：间隙专用目标函数 f4**
- `f4 = mean(E_gap)` 或 `f4 = max(E_gap)`
- Gap 区域定义：对于每对靶区 (i,j)，delta < tolerance 的 remaining_points
- 从 3 目标扩展到 4 目标，评估 NSGA-II 在 4D Pareto 空间中的表现

**阶段 4：加权单目标替代**
- `F = w1·(-E_m) + w2·var(E) + w3·f3 + w4·f4`
- 用网格搜索或贝叶斯优化确定权重，而非依赖 NSGA-II 的 Pareto 探索

### 4.2 参数扫描规范

任何新目标函数的验证必须包含：
1. **与基线的对比实验**（相同 seed, 相同 gen/pop）
2. **Pareto 前沿形态分析**（f1-f3 散点图的变化）
3. **间隙电场定量评估**（tight/broad corridor 的 E_mean, E_max）
4. **聚焦面积变化**（各靶区 FWHM）
5. **解的物理可实现性检查**（电流系数是否在合理范围）

### 4.3 代码修改检查清单

当修改 `ObjectiveConfig` 或 `TMSProblem` 时：
- [ ] `config/schemas.py` 中的 Pydantic 模型字段更新
- [ ] `nsga2_optimizer.py` 中的 `_evaluate_single` 逻辑更新
- [ ] `experiment.py` 中的参数传递链路检查
- [ ] `scripts/run_experiment.py` 的 CLI 参数同步
- [ ] 至少跑一个 gen=10 的快速 smoke test 验证不报错
- [ ] 全链路实验（gen=100）验证结果合理

---

## 5. 当前研究状态

> **本 skill 不存储易变的实验结论**。具体结论和待解决问题以以下文件为准：
> - `index/GLOBAL_INDEX.md` — 已知结论索引 + 待解决问题索引
> - `docs/experiment-patterns.md` — 当前最优配置和实验范式
> - `RESEARCH_LOG.md` — 完整研究历史

---

## 6. 工具使用

### 文献检索
- 优先使用 `SearchWeb` + `FetchURL`
- arXiv 论文可用 `https://arxiv.org/abs/{id}` 获取摘要，`https://arxiv.org/pdf/{id}.pdf` 获取全文
- PubMed 用 `https://pubmed.ncbi.nlm.nih.gov/?term={query}`

### 本地 PDF 分析
- 使用 `pdftotext` 提取文本：`pdftotext file.pdf - | head -n`
- 关键文献位置：`D:\djh\TMS\参考文献\`

### 实验评估
- 使用 `scripts/evaluate_inter_target_separation.py` 一键评估间隙电场

---

## 7. RESEARCH_LOG.md 撰写规范（强制）

> ⚠️ **本规范具有强制性**：所有新会话继续科研任务时，必须按此结构撰写 RESEARCH_LOG.md，不得另开时间线章节。

### 7.1 核心原则：按探索维度组织，而非时间顺序

科研日志必须反映研究的**逻辑结构**（正交探索维度），而非执行的时间顺序。时间顺序仅保留在每个维度内部的子章节中。

**错误示例**（禁止）：
```markdown
## 2026-05-17 实验批次：阶段 A — threshold_ratio 扫描
## 2026-05-17 实验批次：阶段 B — 目标函数重构
## 2026-05-18 实验批次：阶段 C — Pareto分析
## 2026-05-18 实验批次：阶段 D — 分辨率提升
```

**正确示例**（必须遵循）：
```markdown
## 一、问题诊断与基线确认
## 二、参数扫描（不改变目标函数数学形式）
### 2.1 threshold_ratio 扫描
### 2.2 迭代预算收敛验证
## 三、惩罚形式与阈值类型探索（f3重构）
### 3.1 新惩罚模式的设计与实现
### 3.2 全链路对比
## 四、f1聚合方式探索
## 五、f2均匀性定义与分辨率联合探索
## 六、Pareto前沿分析与物理极限
## 七、方法学总结与文献
```

### 7.2 七大部分的定义与内容范围

| 章节 | 内容范围 | 示例 |
|------|---------|------|
| **一、问题诊断与基线确认** | 复现基线、确认问题、记录基线指标、根因初步分析 | 基线配置表、基线指标、浮动阈值的缺陷 |
| **二、参数扫描** | **不改变目标函数数学形式**的参数调优 | threshold_ratio 扫描、gen 收敛验证、pop 大小 |
| **三、惩罚形式探索** | f3 的重构：新惩罚模式、阈值类型、机理分析 | B1/B2/B3 对比、平方惩罚机理、固定阈值优势 |
| **四、f1聚合方式探索** | f1 如何聚合靶区电场：mean/min/sum | f1_mode=min 实验、best_f1 解对比 |
| **五、f2均匀性定义探索** | f2 如何度量均匀性：var/std/cv/peak_correlation | peak_correlation 实现、2×2因子实验、精确峰值分析 |
| **六、Pareto前沿与物理极限** | 对已有结果的深入分析（非新实验）、物理约束 | 三解形态分析、单线圈自由度天花板、间隙定义 |
| **七、方法学总结与文献** | 跨维度的方法论贡献、评价指标、文献地图、代码基础设施 | 核心贡献表、文献对照表、脚本演进 |

### 7.3 如何判断实验归入哪个维度

**决策树**：
```
是否改变 f3 的数学形式？
  ├── 是（新惩罚模式 / 新阈值类型）→ 三、惩罚形式探索
  └── 否 → 是否改变 f1 的聚合方式？
        ├── 是（mean→min→sum）→ 四、f1聚合方式探索
        └── 否 → 是否改变 f2 的均匀性定义？
              ├── 是（var→peak_correlation→per_region_var）→ 五、f2均匀性定义探索
              └── 否 → 是否仅调整数值参数？
                    ├── 是（threshold_ratio / Nsteps / sampling / gen / pop）→ 二、参数扫描
                    └── 否 → 是否对已有结果做分析？
                          ├── 是 → 六、Pareto前沿与物理极限
                          └── 否 → 七、方法学总结 或 一、问题诊断
```

### 7.4 章节内部的撰写规范

每个子章节必须包含以下要素（如适用）：

1. **实验目的**（1-2 句话）
2. **实验设计表**（关键参数对比）
3. **实验结果表**（核心指标）
4. **结果分析**（分点论述，带 ✅/❌/⚠️ 标记）
5. **决策记录**（决策 + 理由 + 下一步）

### 7.5 新增实验时的操作流程

1. **判断维度**：用 7.3 决策树确定归入哪个章节
2. **定位插入点**：在对应章节内按时间顺序找到合适位置
3. **撰写内容**：遵循 7.4 的要素规范
4. **更新决策链条**：如果本实验推翻或修正了之前章节的结论，必须在原结论处添加 `[已修正：见 §X.X]` 引用

---

*Skill version: 2.0*
*Last updated: 2026-05-17*
*Based on: local refs (D:\djh\TMS\参考文献) + web search results*
