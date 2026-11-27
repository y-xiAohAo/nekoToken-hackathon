# SDD Feature Spec：模块 0 Godot 工程壳

状态：回顾性 SDD / 技术验收完成，保留流程偏差。代码已于本 Feature Spec 与实施计划之前落盘；本文不追认当时存在 `Plan Approved`。

## 0. Open Questions

- [x] 本检查点锁定本分支已验证的 Godot `4.7.2.stable.official.ed1daf0bf`；Windows 本机导出与 Linux headless CI 均使用该版本。

## 1. Requirements (Context)

- **Goal**：在 `game/` 建立最小、可启动、可见且可导出 Windows 的 Godot 工程壳，为后续模块提供稳定入口。
- **In-Scope**：Godot 项目配置、`Main/World/UI` 场景层级、启动自检、Windows x86_64 导出预设、可复现的本机验证记录。
- **Out-of-Scope**：玩家输入、移动碰撞、游戏规则、模拟时钟、Agent、传感器、地图机制、RESET、真实 API、最终团队版本决定。
- **SDD Status**：本 Feature Spec 是事后补录。工程创建和验证时没有独立 Feature Spec、审查计划或事前批准；这项流程偏差不可由补文档消除。

## 1.1 Context Sources

- Requirement Source：用户同意从框架顺序开始开发；工程目标见 [`最小游戏框架 Spec`](../minimal-framework-spec.md) §7。
- Design Refs：[`AGENTS.md`](../../AGENTS.md)、[`docs/development.md`](../development.md)。
- Code Terrain：[`Godot 工程入口图`](../codemap/2026-11-27_14-14_game-project-map.md)。
- Validation Evidence：[`game/README.md`](../../game/README.md)、本 Feature Spec §5。

## 1.5 Codemap Used (Feature/Project Index)

- Codemap Mode：`feature`
- Codemap File：[`docs/codemap/2026-11-27_14-14_game-project-map.md`](../codemap/2026-11-27_14-14_game-project-map.md)
- Key Index：`project.godot → scenes/main.tscn → scripts/main.gd._ready()`；导出由 `export_presets.cfg` 控制。

## 1.6 Context Bundle Snapshot (Lite)

- Bundle File：[`docs/context/2026-11-27_14-14_framework-context-bundle.md`](../context/2026-11-27_14-14_framework-context-bundle.md)
- Key Facts：工程此前为空壳目录；本机有 Godot 4.7.2 和匹配 Windows 模板；`tools/`、`build/` 被忽略，不是仓库交付内容。
- Open Questions：团队最终引擎小版本仍待确认。

## 1.7 Minimum Chaos Unit Assessment

- **Final Goal**：逐步形成可运行的游戏框架，并最终完成一个可玩的 Agent 预演循环。
- **Current Task Unit**：仅建立工程入口、空灰盒和可导出配置。
- **Why this unit is small enough**：不依赖玩法状态或外部服务；启动、渲染、导出都可独立验收。
- **In-Scope Boundary**：本文件 §1 所列。
- **Out-of-Scope Boundary**：所有玩法和模型服务。
- **Verification Evidence**：Godot 导入、主场景启动、渲染帧、Windows 导出及导出程序启动。
- **Failure / Rework Plan**：修正资源路径或导出预设后重跑导入、项目引用检查和构建。
- **Model Autonomy Space**：选择简单节点构成和状态文字；不决定团队引擎版本或玩法设计。
- **User Decision**：追溯性记录，不代表事前批准。

## 2. Research Findings

- 当前仓库在本任务开始时没有 `game/project.godot`。
- 现有工作区忽略 `tools/`、`.godot/` 和 `build/`；干净克隆必须自行安装相同 Godot 版本与导出模板。
- 灰盒画面通过 Polygon2D 地面和 CanvasLayer 状态面板表达；该画面只验证场景可显示。
- `4.7.2` 是实际运行版本，不等同团队已选择版本。
- 任务规模小，跳过 Innovate；单一场景结构满足当前壳的需要。

## 3. Plan (Retrospective Contract)

以下清单按已发生的实现重构，**不是事前获批计划**。

### 3.1 File Changes

- `game/project.godot`：主场景、窗口与渲染设置。
- `game/scenes/main.tscn`：`Main`、`World/Floor`、`UI/StatusPanel`。
- `game/scripts/main.gd`、`game/scripts/main.gd.uid`：显示引擎版本并输出启动标记。
- `game/export_presets.cfg`：Windows x86_64 release 预设。
- `game/README.md`：启动、导出命令与验证证据。

### 3.2 Signatures

- `Main._ready() -> void`：显示 Godot 版本并打印 `FRAMEWORK_SHELL_READY`。
- 无公开游戏规则 API。

### 3.3 Implementation Checklist

- [x] 创建最小 Godot 工程和主场景。
- [x] 建立可见 `World` 与 `UI` 节点。
- [x] 配置 Windows x86_64 release 导出。
- [x] 运行工程导入、主场景、渲染帧、导出与导出程序启动。
- [x] 记录真实运行版本、导出产物和复现命令。

### 3.4 Spec Review Notes

| Check | Verdict | Evidence |
|---|---|---|
| Requirement clarity & acceptance | PARTIAL | 工程目标可验收；事前未形成 Feature Spec |
| Plan executability | PARTIAL | 实际实现路径简单；计划在实现后回构 |
| Risk / rollback readiness | PASS | 改动限于 `game/` 与说明文档，可逐文件重建 |

- Readiness Verdict：追溯审查，不用于事前放行。
- Risks：团队版本未统一；构建目录和引擎程序不入库。

## 4. Execute Log

- **Branch**：`team/branch-1`。
- **Godot**：`4.7.2.stable.official.ed1daf0bf`。
- **Import**：headless 导入退出码 0。
- **Runtime**：主场景无窗口运行退出码 0，输出 `FRAMEWORK_SHELL_READY`。
- **Visual Render**：项目与导出程序均生成 960×540 渲染帧；可见底色、地面和状态面板。
- **Windows Export**：release 导出退出码 0；本机生成 EXE 与 PCK，导出程序运行退出码 0。
- **Project Check**：场景引用检查 0 errors、0 warnings。
- **Repository Checks**：13 项 Python 单元测试通过；仓库检查 0 issues；链接检查 61 份文档、0 断链；`git diff --check` 通过。
- **Limit**：渲染帧和导出产物位于被忽略的 `tmp/`、`build/`，不是仓库工件；没有人工交互试玩。
- **Environment Note**：本机某次 Godot 无窗口启动曾提示 `user://` 日志目录不可写；指定绝对 `--log-file` 后启动自检无此日志错误。可视渲染时仍有 shader cache 的 `user://` 提示，但画面生成、EXE 导出与运行均成功；后续测试入口应显式设置可写日志路径，并在干净克隆环境复核。

## 5. Review Verdict

| Axis | Key Checks | Verdict | Evidence |
|---|---|---|---|
| Spec Quality & Requirement Completion | 壳的配置、可见场景、启动和导出是否可证 | PASS (technical) | §4 运行与构建结果；工程文件存在 |
| Spec-Code Fidelity | 是否与事前批准计划一致 | PARTIAL | 无事前 Feature Spec/Plan，无法声称事前一致 |
| Code Intrinsic Quality | 工程引用、启动、渲染和导出可靠性 | PASS for shell scope | 项目检查无错警告，项目与导出程序均启动 |

- **Overall Verdict**：技术验收通过，SDD 流程存在不可追认的事后补录偏差。
- **Blocking Issues**：未来规则内核开发须按独立 Feature Spec 和 Plan Approved 门禁执行；此项回顾任务无代码阻塞。
- **Regression Risk**：低（仅工程壳）。
- **Follow-ups**：其他开发机按 `game/README.md` 复现 Godot 4.7.2；若更换小版本，需同步更新 CI、README 和导出记录。

## 6. Plan-Execution Diff

- 代码和导出配置先于本 Feature Spec；没有事前 `Plan Approved`。
- 工程实际选择 4.7.2，但项目组版本选择仍未定。
- 计划与验收证据是按实际执行重建的，只能用于现在的评审和之后交接。

## 7. Project Sync Candidates

- 工程壳路径、版本证据和运行命令已同步至 `game/README.md`、`docs/development.md`、`AGENTS.md` 和根 README。
- 本 Feature Spec 作为模块 0 的审计记录保留；不把临时 EXE/PCK 或渲染帧纳入 Git。
