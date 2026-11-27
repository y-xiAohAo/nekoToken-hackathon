# 氛围编码代理 — TMS Optimizer 本地化补充

> 核心方法论见用户级技能：`vibe-coding-harness`
> 本项目特殊约定如下：

---

## 技术栈约束

- 前端：React 19 + TypeScript + Vite + Three.js（`@react-three/fiber` + `@react-three/drei`）
- 后端：FastAPI + Pydantic + SQLAlchemy（SQLite）
- 测试：Vitest + Testing Library + Playwright
- 严禁引入新的前端框架（如 Vue / Svelte / Angular）
- 严禁引入新的三维渲染库（如 Babylon.js / VTK.js）

## 已知陷阱

- `electric_field_basis()` 实际计算的是 **per-unit-dI/dt 响应**，不是绝对伏特每米
  - 所有电场值的单位是 `(伏特/米) / (安培/秒)`
  - 换算到真实物理值需要乘以 `dI/dt / I_repr`
- `watch()` 返回值模式会导致无限重渲染（已修复，见 2026-06-02 补丁）
  - 正确做法：使用订阅回调模式 `watch(callback)` + `unsubscribe`
- Three.js 的 `Canvas` 组件在路由切换时不会自动释放 WebGL 上下文
  - 需要手动处理 `gl.dispose()` 或复用 Canvas

## 项目级严禁事项

- 不动 `src/tms_optimizer/core/spherical_harmonics.py` — 数学核心，冻结
- 不动 `src/tms_optimizer/physics/basis_field.py` 的公式结构 — 物理模型已验证
- 不动 `RESEARCH_LOG.md` 的前七章结构 — 只追加新的实验记录
- 不修改 `experiments/` 目录下的历史实验数据（只读）
- 不修改 `tasks/T-001` 至 `T-053.json` 的已完成任务定义

## 模块规格说明索引

| 模块 | 规格文件 | 状态 |
|------|----------|------|
| 前端可视化 | `.kimi/vibe_specs/frontend-visualization-spec.md` | 活跃开发 |
| 后端接口 | `.kimi/vibe_specs/backend-api-spec.md` | 稳定 |
| 优化算法 | `.kimi/vibe_specs/optimization-spec.md` | 稳定 |
| 物理模型 | `.kimi/vibe_specs/physics-spec.md` | 冻结 |

## 与现有代理体系的关系

| 代理 | 职责 | 与氛围编码代理的交互 |
|------|------|----------------------|
| 任务翻译员 | 翻译人类需求为任务定义 | 无直接交互 |
| 实验员 | 跑实验（配置、提交、监控） | 被剥夺写代码能力，需要新功能时向人类申请 |
| 数据分析师 | 分析实验数据 | 无直接交互 |
| 文献调研员 | 调研文献 | 无直接交互 |
| 同行评审代理 | 独立代码审查 | 由人类触发，干净上下文 |

## 更新记录

| 时间 | 更新人 | 内容 |
|------|--------|------|
| 2026-06-02 | human_scheduler | 初稿，基于水流理论 + 最小混沌单元 |
