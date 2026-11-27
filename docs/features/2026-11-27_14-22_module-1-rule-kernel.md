# SDD Feature Spec：模块 1 规则内核与 Agent 契约

阶段：`REVIEW`。批准状态：`Plan Approved`。本文件记录模块 1 的实施契约、验证结果和剩余集成边界。

## 0. 已确认的规则与范围

- 时间有三层：猜测周期含若干上报周期，上报周期含若干物理采样刻。`simulation_tick` 是唯一整数模拟时钟；上报长度和猜测批数从配置注入，不固定玩法值。设备工作期间高频离散感知，每次感知保留独立记录；不承诺捕获两次采样间的极短擦边暴露。具体感知频率和几何算法留给感知模块。
- 所有设备在一个上报边界组成**一批统一报告**。只提交本上报周期 `[start_tick, end_tick)` 内的原始记录，不合并、去重或压缩；`end_tick` 的新记录进下一批。未检测到玩家也可产生有效负面记录，没有可靠观察时周期仍计数。
- 报告边界在游戏内部按确定顺序同步处理：封存整批旧记录 → 应用到期玩家配置 → 更新系统 Agent 视图 → 若累计批数已满则暂停并请求猜测。报告生成是游戏内部确定操作，不设计逐设备异步回执或常规重试；传输失败属于后续 AgentGateway。
- 猜测刻优先于通关，玩家不能操作；猜测未命中且目标、出口均已满足时本轮成功并跳过调度。非猜测刻达成目标和出口立即成功；若恰逢普通上报边界，先完成该批统一上报再结束本轮。
- 局部 RESET 回到**被命中的当前猜测周期起点**。该起点之后旧分支的报告在新分支中失效，但作为带旧分支标记的 Agent 记忆保留；周期起点以前的有效报告保留。新 `branch_id` 使旧 Agent 回复失效。本模块固定身份与数据契约，完整快照恢复留给后续模块。
- 当前工程基线为 Godot 4.7.2 stable。黑客松阶段 CI 保持轻量，不在每个 PR 导出 Windows 程序或调用真实模型。

## 1. Requirements (Context)

- **Final Goal**：在工程壳上建立标准游戏框架，再接入玩家交互、感知上报、Agent、动态世界和 RESET。
- **Current Task Unit**：完成独立于场景节点的规则内核、周期状态边界与双角色 Agent 请求契约。
- **In-Scope**：单一整数时钟与阶段守卫；三层时间映射；统一报告边界的同步协调接口；猜测与通关优先级；SessionState/CycleState 所有权；双角色视图和回复身份校验；少量 headless 测试与轻量 CI。
- **Out-of-Scope**：玩家控制和碰撞、真实地图、设备感知与报告内容、动态世界命令、完整 RESET 快照、真实模型 API、聊天 UI、四轮结算、Windows 自动导出。
- **Done Contract**：Godot 4.7.2 能导入并启动项目；headless 测试覆盖时间冻结、上报归属与边界、猜测结算、过期回复和角色信息隔离；测试失败返回非零进程码。

### Context Sources

- [现行玩法 Spec](../../PRELIMINARY_DESIGN_SPEC.md) §5、§7–8；[机制基准](../../侦测定位_机制草案.md) §3、§5；[最小游戏框架 Spec](../minimal-framework-spec.md) §2–4、§6–8。
- 本轮对话定案：三层时间、高频离散感知、全设备统一批次、同步串行报告、旧报告在新分支无效但 Agent 记忆保留、黑客松轻量 CI。
- [项目规则](../../AGENTS.md)；[SDD 流程](../../.agents/skills/sdd-riper-one/SKILL.md)；[工程入口图](../codemap/2026-11-27_14-14_game-project-map.md)；[框架上下文快照](../context/2026-11-27_14-14_framework-context-bundle.md)。

## 2. Research Findings 与架构

1. 当前 `Main/World/UI` 是静态工程壳。规则放在 `game/scripts/core/`，Agent DTO 放在 `game/scripts/agents/`；场景节点只提供物理结果，不直接裁决阶段。
2. `GameSession` 是唯一编排者。每个固定物理步结束后收到 `WorldFrame(k)`，其中 k 是已完成的整数模拟刻；暂停期间不收下一帧，也不推进设备模拟计时。感知可以按较小固定间隔发生，但模块 1 不实现感知。
3. `SessionState` 只管流程：`phase`、`round_id`、`guess_cycle_id`、`branch_id`、活动请求、冻结猜测帧和回合结果。阶段至少为 `ACTION`、`CONTACT_PAUSED`、`REPORT_BOUNDARY`、`GUESS_PAUSED`、`DISPATCH_PAUSED`、`CYCLE_START_PENDING`、`RESET_CHOICE`、`ROUND_END`。`CycleState` 只管可恢复的当前周期：时钟、上报周期编号、已封存批数；原始记录、有效报告和待生效命令预留给后续模块。时钟和批数各只有一份可变权威值，`GameSession` 对外提供深拷贝状态快照。
4. 模块 1 以 `ReportBoundary` 表达“全设备统一批次到期”，并用模拟协调器按封存、配置、视图的顺序处理。协调器完成后一次性通知内核；内核再转入下一行动段或猜测暂停。没有半批报告可见状态，也没有逐设备 ACK 协议。
5. Agent 请求关联至少含 `protocol_version`、`role`、`request_id`、`round_id`、`branch_id`、`guess_cycle_id`。系统 Agent 可见静态地图、已知配置、当前有效报告及带分支标记的历史；不见内部玩家真坐标或联络来源。玩家助手只见玩家文字、获准工具与自身历史；不见地图和系统报告。玩法 payload 后定。
6. 模拟时钟可在未来 RESET 时回到快照刻，因此不能单靠 tick 识别事件；身份需同时含轮次和分支。旧分支报告转为历史，不计入新分支批数或实时报告。

## 3. Plan (Contract)

### 3.1 File Changes

- `game/scripts/core/session_phase.gd`：阶段与回合结果常量。
- `game/scripts/core/session_rules.gd`：上报周期 tick 长度与每次猜测累计批数的正值校验。
- `game/scripts/core/simulation_clock.gd`：唯一整数模拟时钟。
- `game/scripts/core/world_frame.gd`：物理步完成后的坐标、目标和出口状态。
- `game/scripts/core/session_state.gd`：流程状态及只读快照，不保存时钟或批数副本。
- `game/scripts/core/cycle_state.gd`：本周期的时钟、上报序号与批数；不实现实际报告内容。
- `game/scripts/core/report_boundary.gd`：统一批次的轮/分支/周期 ID、半开时间窗和猜测边界标记。
- `game/scripts/core/game_session.gd`：时钟、阶段、报告边界和猜测结算协调。
- `game/scripts/core/physics_step_result.gd`：物理刻推进结果和可选的冻结报告边界。
- `game/scripts/agents/agent_protocol.gd`：角色视图、请求上下文、响应 envelope、显式允许字段序列化。
- `game/tests/run_tests.gd`、`game/tests/session_kernel_tests.gd`：最小 headless 契约测试与失败码。
- `game/README.md`：本地 import、test、启动烟测命令。
- `.github/workflows/godot.yml`：PR 和 `team/branch-1` push 上的单一 Linux Godot headless 作业；不做每 PR Windows 导出。

### 3.2 Interface Contract

- `SessionRules.is_valid() -> bool`。
- `GameSession.advance_physics_step(frame: WorldFrame) -> PhysicsStepResult`：非上报边界返回无边界结果；上报边界冻结模拟并返回唯一的本批描述。暂停阶段调用不改变状态。该返回值比原计划的裸 `ReportBoundary` 多承载拒绝原因，便于 headless 测试和调用方诊断。
- `GameSession.process_report_boundary(seal_batch: Callable, apply_config: Callable, update_view: Callable) -> bool`：仅在报告边界调用；按此顺序同步调用三个操作，每个操作接收只读边界副本，然后内核累计一批并转入 `ACTION` 或 `GUESS_PAUSED`。无逐设备回执或重试状态机。
- `GameSession.period_for_event_tick(event_tick: int) -> int`：使用 `[start,end)`；`end_tick` 事件属于下一周期。
- `GameSession.begin_contact() -> bool`、`end_contact() -> bool`：只做合法阶段转换，联络暂停冻结模拟时间。
- `GameSession.accept_guess_result(context, hit: bool) -> bool`：只接收已由程序验证的合法猜测结果；模型超时、非法输出不得变成 `hit = false`。
- `GameSession.complete_dispatch() -> bool`：调度规则完成后进入 `CYCLE_START_PENDING`，初始化下一猜测周期的内核计数；此时仍暂停。真实配置同步由后续世界模块完成。
- `GameSession.resume_cycle(snapshot_saved: bool) -> bool`：只有调用方确认周期起点快照已保存才进入 `ACTION`。模块 1 用模拟确认测试该顺序，不实现实际快照。
- `AgentProtocol.response_matches(response, expected_context) -> bool`：角色、协议版本和全部身份字段必须匹配；旧分支回复不可修改新分支。

### 3.3 Atomic Checklist

- [x] 建立阶段、Rules、Clock、SessionState/CycleState；证明时钟和批数各有唯一所有者，暂停不推进。
- [x] 建立 WorldFrame、ReportBoundary；证明物理刻单调、半开归属及同一边界只触发一批；仅 GameSession 持有真坐标帧，报告回调收到的边界不含该帧。
- [x] 用模拟协调器验证同步边界顺序：封存整批 → 应用到期配置 → 更新视图 → 进入猜测或行动。
- [x] 实现猜测优先、非猜测刻通关、命中/未命中转移与过期回复拒绝。
- [x] 实现双角色视图的显式字段序列化，按角色投影字段并拒绝已知的嵌套越权字段，禁止传入完整权威状态。
- [x] 运行少量 headless 契约测试并确认失败码；加入单一轻量 CI job 与 README 命令。
- [x] 回写实际验证、偏差、剩余风险和 handoff。

### 3.4 Acceptance Scenarios

1. 行动推进 K 个物理刻后时钟为 K；联络、上报边界、猜测和调度暂停中均不前进。
2. 长度 N 的上报窗为 `[0,N)`：事件 `N-1` 属本批，`N` 属下一批；边界只触发一次，所有设备的模拟记录在同一批里，无半批可见。
3. 猜测边界先完成整批封存、到期配置和视图更新，再进入 `GUESS_PAUSED`；暂停期间不产生下一物理/感知刻。
4. 非猜测刻完成目标并抵达出口则成功；普通上报边界同刻先上报再成功；猜测刻同刻必须先猜，未命中才成功，命中进回退选择。
5. 猜测未命中但未通关进入调度暂停。请求角色、协议版本或任一 ID 不符时状态不变；模型失败不能当未命中。
6. 系统视图无玩家内部真坐标/联络来源；玩家助手视图无地图、设备位置/系统报告。序列化按角色重新投影允许字段，并拒绝相应的嵌套越权键；报告边界回调也拿不到冻结的真坐标帧。
7. 旧分支回复与新分支期望上下文不匹配。模块 1 只固定“旧报告不进入新分支有效集合、旧历史仍保留”的契约并测试身份比较；报告集合迁移和完整 RESET 恢复由后续模块验收。
8. 调度结束后仍处于 `CYCLE_START_PENDING`；未确认周期起点快照保存时不能继续物理刻，确认后才进入 `ACTION`。

## 4. 风险、CI/CD 与回炉

| 风险 | 应对 |
| --- | --- |
| 时钟、感知时间和报告边界混用 | 整数物理刻判断边界；事件时间独立；感知频率后续调参 |
| 两份权威时钟或批数 | Clock 和批数仅在 CycleState；SessionState 不复制 |
| 半批报告或旧报告冒充当前观察 | 同步统一边界；报告带轮/分支/周期身份；旧历史明确标记 |
| 过期模型回复污染新分支 | 全部上下文字段、角色、版本和正整数 ID 验证；失败状态不转为未命中 |
| Headless 测试假绿灯 | SceneTree runner 统计失败并显式 `quit(1)`，CI 设置超时 |
| 黑客松 CI 过重 | 现有仓库检查保留；新增一个 Linux Godot job；Windows 导出手动里程碑验收 |

Execute 前接口核对：单独公开 `complete_report_boundary()` 无法证明封包、配置和视图已按序完成；将其收敛为单次同步 `process_report_boundary(...)`，由 GameSession 控制调用顺序。WorldFrame、SessionRules 和 ReportBoundary 在进入内核时复制，避免调用方后续修改影响冻结结果。玩法范围不变。

CI 固定 Godot 4.7.2 stable 下载地址和 SHA-256。新克隆先 `--headless --import`，再运行 `--script res://tests/run_tests.gd`；无真实 API key、外网模型调用或实时等待。Windows 导出沿用模块 0 已验证的本地命令，在演示里程碑手动检查，不自动发布。发现规则或测试冲突先回到 Research/Plan 修订本 Spec；代码缺陷修复后重跑受影响测试。

## 5. Spec Review Notes (Pre-Execute)

| Check | Verdict | Evidence |
| --- | --- | --- |
| Requirement clarity & acceptance | PASS | §0–1 记录已定规则与排除项；§3.4 对应时间、报告、结算、角色隔离及未来 RESET 接口的可验证场景 |
| Plan executability | PASS | §3.1–3.3 列出目标文件、关键方法与原子步骤；报告内容、快照和真实模型均不在本模块实现 |
| Risk / rollback readiness | PASS | §4 列出时间、状态重复、分支污染、假绿灯和 CI 成本风险；新增脚本及单一 workflow 可独立回退 |

- Readiness Verdict：`GO`（Spec 可执行性评审结论；不代替 Execute 批准）。
- Phase Reminder：感知频率、报告内容、Agent payload 和完整 RESET 快照由后续模块定义；Godot CI 下载哈希在编写 workflow 时核对并固定。
- Plan Approval：`Plan Approved`；用户已在本轮明确批准执行。

## 6. Execute Log / Review / Plan-Execution Diff

- Execute：完成；规则内核、物理刻结果、双角色 Agent 契约、轻量 CI 和本地验证均已落地。
- Validation：Godot 4.7.2 headless 契约测试 `75 passed, 0 failed`；失败探针退出码 `1`；Godot 导入与启动烟测退出码 `0`；仓库单元测试 `13/13`；仓库检查 `0 issues`；链接检查 `0`。
- Review Matrix：

| Check | Verdict | Evidence |
| --- | --- | --- |
| Time and phase ownership | PASS | CycleState 是时钟和周期计数的唯一所有者；冻结边界只在完整同步回调后计数；暂停与重入测试通过。 |
| Guess / completion ordering | PASS | 猜测边界优先于出口结算；普通上报边界先处理后结算；对应 headless 场景通过。 |
| Agent boundary and stale replies | CONDITIONAL | 内核会校验身份并隔离基础视图；严格 payload DTO 和猜测结果的程序验证仍须在真实 AgentGateway 前补齐。 |
| Verification and CI scope | PASS | 本地 Godot 4.7.2、仓库检查通过；新增单 Linux headless 工作流并校验下载 SHA-256；未做 Windows PR 导出或真实模型调用。 |
| Remaining limits | ACCEPTED | CI 尚未在远程 GitHub runner 执行；感知/报告 schema、真实 AgentGateway、RESET 快照和配置回滚属于后续模块。同步回调不提供失败重试或事务回滚，符合本模块已批准的内部确定处理边界。 |

- Review Verdict：`INTERNAL KERNEL PASS; AGENTGATEWAY CONDITIONAL`。
- Plan-Execution Diff：新增 `PhysicsStepResult` 返回包装；报告回调视图从冻结真坐标帧中剥离；边界处理加同步重入锁；Agent 序列化出口按角色重新投影允许字段、拒绝已知嵌套内部状态键并验证身份；新增固定 Godot 4.7.2 Linux 下载、SHA-256 校验和 headless CI。其余计划接口保持不变。

## 7. Resume / Handoff

- 当前任务单元：模块 1 规则内核与 Agent 契约。目标分支：`team/branch-1`。
- 下一步：为模块 2 的权威世界状态、地图拓扑、设备注册表和受校验动态命令入口进行 SDD Grill 与 Feature Spec 编写；感知与原始报告 schema 在世界模型稳定后另行定 Spec。真实 AgentGateway 前须补齐严格 payload DTO 和猜测结果校验。模块 0/1 将作为同一基础框架 Git 检查点提交。
