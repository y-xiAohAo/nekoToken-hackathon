# TMS Optimizer — Agent Guidelines

Project root: `D:\djh\search_agent\tms_optimizer`

---

## Streamfunction TMS Research Knowledge

For literature, coil design, winding manufacturability, or work-three research questions, start at `knowledge/tms-streamfunction/README.md` and `knowledge/tms-streamfunction/research-now.md`; open source pages and current experiment evidence as needed. Treat the knowledge files as a navigation layer and check `knowledge/tms-streamfunction/updates.md` for stale sources or verdicts.

---

## Coding Discipline (Enforced)

All code changes in this project MUST follow the engineering discipline defined in `.kimi/skills/tms-coding-discipline/SKILL.md`.

### Quick Reference

| Rule | Enforcement |
|------|------------|
| **TDD** | Test file must exist in `tests/` before implementation in `src/` |
| **Type annotations** | All public functions must have parameter + return types |
| **No bare except** | Catch specific exceptions only |
| **No print()** | Use `logging` module for all output |
| **Module docstring** | Every `.py` file starts with docstring |
| **Dependency tracking** | New deps go in `pyproject.toml` |

### Hooks

A `PreToolUse` hook is active at `.kimi/hooks/tms-coding-check.sh`. It blocks writes to `src/` without matching tests and runs automated lint checks.

- Exit `0` = allow
- Exit `2` = block (stderr fed back to LLM)

### Skills Auto-trigger

The following skills are available in `.kimi/skills/` and auto-trigger based on context:

| Skill | Triggers On |
|-------|------------|
| `tms-optimizer-project` | Any work in this project |
| `tms-optimizer-codebase` | Reading / modifying / debugging code |
| `tms-optimizer-experiment` | Running experiments, generating outputs, writing code |
| `tms-research-assistant` | Designing experiments, interpreting results |
| `tms-coding-discipline` | Writing or reviewing Python code |

---

---

## Vibe Coding Harness（氛围编码规范）

当用户要求 **"按氛围编码规范执行"**、**"按规范执行"** 或 **"氛围编码"** 时，严格遵循以下流程：

1. **强制读取规范文件**：`C:\Users\msn\.kimi\skills\vibe-coding-harness\SKILL.md`
2. **强制读取本地化约束**：`D:\djh\search_agent\tms_optimizer\agents\vibe_coding_agent.md`
3. **强制准入检查——Git**：开工前**必须先执行** `git rev-parse --git-dir` 验证仓库存在；若失败则**拒绝开工**，要求用户先运行 `git init`
4. **强制准入检查——Spec**：确认以下文件存在；若无，则**停止编码**，先按规范建立 Spec：
   - `CODEMAP.md`（项目根目录）— 代码地形与数据流
   - `.kimi/vibe_specs/README.md` — 规格索引
   - `.kimi/vibe_specs/[module]-spec.md` — 模块级规格（现有：`backend-api-spec.md`, `frontend-visualization-spec.md`, `optimization-spec.md`, `physics-spec.md`）
5. **四步检查点**：复述确认 → 实现+自检 → Spec/CodeMap 更新审批 → 同行评审（见 SKILL.md 全文）

> ⚠️ **关键：以上步骤不是建议，是开工前置条件。** Agent 必须在写入任何代码文件之前完成全部检查，否则视为违规。

---

## SDD-RIPER-ONE 协议路由（最小入口）

当用户指令命中 `sdd` / `SDD` / `RIPER` / `按 sdd-riper-one 执行` / `MAP` / `DEBUG` / `归档` / `new chat 恢复` 等触发词，或任务为高门禁长链路推进时，启用用户级 skill `C:\Users\msn\.kimi\skills\sdd-riper-one\SKILL.md`（按需读取其 references，勿全量加载）。

### 产物落点

| 产物 | 落点 |
|------|------|
| 任务级活跃 Spec（唯一真相源） | `mydocs/specs/YYYY-MM-DD_hh-mm_<task>.md` |
| 项目/特性总图 | `mydocs/codemap/` |
| Context Bundle | `mydocs/context/` |
| 归档沉淀 | `mydocs/archive/` |
| 项目级稳定真相 | `mydocs/project/PROJECT_SPEC.md` |

### 硬门禁（不可削弱）

1. **No Spec, No Code**：Spec 未落盘，不进入实现
2. **Restate First**：先复述最终目标、当前任务单元、边界，再规划
3. 未收到精确字样 `Plan Approved`，禁止进入 Execute
4. **Reverse Sync**：实现偏差、验证结论、用户决策必须回写 Spec
5. **Done by Evidence**：完成由测试/日志/验收证明
6. 永远不执行 `git clean`

### 与 Vibe Coding Harness 的分工

两套协议**互补不覆盖**，由触发词决定走哪套：
- `按氛围编码规范执行` → vibe harness：管**编码准入**（git/spec 准入检查、四步检查点），规格在 `.kimi/vibe_specs/`
- sdd-riper-one 触发词 → 本协议：管**任务全流程**（目标收敛→RIPER→归档），Spec 在 `mydocs/specs/`
- 两者可叠加：大型编码任务可先走 sdd-riper-one 流程，编码环节遵守 vibe harness 与编码纪律

### New Chat 恢复

1. 读本节确认路由 → 2. 找 `mydocs/specs/` 最新活跃 Spec 回读当前阶段区块 → 3. checkpoint 自总结（phase / approval / Goal / 下一步）→ 4. 从断点继续，勿全量重载

---

## Updates

If you modify coding standards, update BOTH:
1. `.kimi/skills/tms-coding-discipline/SKILL.md`
2. This file (`AGENTS.md`)
