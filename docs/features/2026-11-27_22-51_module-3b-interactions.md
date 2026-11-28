# SDD Feature Spec：模块 3B 目标、联络点与出口交互

层级：Feature Spec。创建：2026-11-27 22:51（Asia/Shanghai）。分支：`team/branch-1`。

**阶段：REVIEW 完成。Plan Approval：Plan Approved。Implementation Verdict：PASS（模块 3B 范围）。** B0–B6 已完成；独立复核的 2 个 P2 及测试盲点均已修复并复核关闭。后续并键复评的小修复后，当前正式检查 81/223/47/344 条通过；主场景和 Windows 导出已复验。真实感知、完整 RESET、四轮和真实 Agent 不属于本模块通过范围。

## 0. Open Questions

以下事项属于后续原型配置或 Execute 验收：

- [x] 确定交互协调器、目标操作状态、联络请求和出口检测的具体签名及文件落点。
- [x] 确定联络 `used=true` 与 `GameSession.begin_contact()` 的提交顺序，保证进入失败不消耗、成功进入必消耗、非法部署不返还。
- [x] 确认 G1 多目标必须全部完成；取消 G2 额外优先级，当前布局保证目标与联络点交互区不重叠。
- [x] 注入交互距离、目标操作时长、输入键位等原型值；这些值是灰盒 fixture，不是最终玩法结论。
- [x] 以真实物理场景回归验证目标操作被机器人推出、猜测暂停恢复、出口碰撞和报告/猜测优先顺序。

小游戏已明确放弃，不再作为待选方案或后续隐藏扩展。

## 1. Goal 与当前任务单元

在模块 3A 的真实运行时之上，实现玩家与固定设施的最小完整交互：到场停留完成核验装置操作、在联络点进入一次受限会话、完成目标后触碰出口形成撤离条件。所有交互只产生可信世界状态和 WorldFrame 条件，GameSession 继续独占暂停、猜测和通关裁决。

Done Contract（当前已在 3B 范围验收，证据见 §11）：

- 玩家必须接近装置才能操作；按一次开始后原地停留，外部世界继续，操作按模拟 tick 推进。
- 多个核验装置分别保存独立进度，同一玩家同一时刻最多一个装置 active；中断清零，暂停后按规则继续。
- 联络点只有接近且未使用时才能发起；成功进入即消耗，保持现状也消耗，非法批次可留在会话内重试。
- 出口保持实心，通过真实滑动碰撞形成 `at_exit`；模块 3B 不直接宣布通关，猜测优先规则保持不变。
- 目标操作只产生少量准确领域事件，供模块 4 后续构造报告；不逐 tick 生成进度事件。
- 真实 Godot 场景与 headless 回归共同证明下述验收场景，实际证据回写本 Spec。

## 2. In Scope / Out of Scope

In Scope：

- 固定设施的接近检测、交互输入和运行时交互协调。
- 多核验装置的 `active / progress / complete` 状态及必要的小数校验。
- 目标操作开始、取消、完成、暂停恢复和领域事件。
- 联络点使用状态、当前 `active_contact_id`、联络请求及与 GameSession 的衔接。
- 出口实体 ID 的真实碰撞识别和 WorldFrame 的 `goal_complete / at_exit`。
- 与模块 3A 单步候选提交、模块 1 报告/猜测顺序的集成测试。

Out of Scope：

- 小游戏、游标、随机序列、密码、文件选择、连线、额外解谜和 RNG 状态。
- 摄像头/机器人视觉、踏板事件、ObservationRecord、ReportBatch 和 Agent 视图。
- 真实 Agent、AgentGateway、模型超时/断线/退款策略和聊天服务的内部实现。
- 完整局部 RESET、整轮重启、四轮评分和剧情结算。
- 通用 Interaction 插件、复杂交互状态机、正式美术和最终数值平衡。

## 3. Context Sources

- [现行设计 Spec](../../PRELIMINARY_DESIGN_SPEC.md) §4–8、§11：固定设施、目标操作、联络暂停、出口与猜测优先及验收边界。
- [机制基准](../../侦测定位_机制草案.md) §2、§4–5：交互、联络权限、暂停与恢复语义。
- [最小游戏框架 Spec](../minimal-framework-spec.md) §2–6：阶段、权威状态、统一报告和通关顺序。
- [模块 2 Feature Spec](2026-11-27_20-53_module-2-world-command.md)：固定设施运行状态、部署回执和联络门槛。
- [模块 3A Feature Spec](2026-11-27_22-25_module-3a-runtime-scene.md)：单物理步、完整候选、移动墙、暂停和模块 4 接入点。
- `game/scripts/core/world_frame.gd`、`game/scripts/core/game_session.gd`、`game/scripts/world/device_registry.gd`：当前接口事实。

## 4. D 组决策：目标操作

### D1. 按一次开始

玩家进入核验装置交互区并按一次 `interact` 后开始操作，不要求持续按住。未完成且未 active 的装置才能开始；完成后不能重复刷取操作事件。

### D2. 必须停留

操作期间外部世界继续，但玩家必须留在装置交互区且不能主动移动：

- 开始操作后，方向输入按中断处理，不允许边移动边推进。
- 玩家残余速度若使其离开交互区，按离开中断；不新增“静止速度阈值”系统。
- 被机器人或其他物理作用推出交互区同样中断。
- `cancel_interaction` 可主动取消。

### D3. 中断清零

方向输入、主动取消或离开交互区均使本次操作中断：

- `active=false`。
- 事件记录中断前的 progress 后，将权威 progress 清零。
- complete 尚未成立，可以重新到场开始。
- 已完成的 complete 不被普通中断撤销；局部 RESET 和整轮重启由后续模块处理。

### D4. 暂停后继续

猜测、联络和调度等模拟暂停只冻结 active/progress，不自动取消：

- 暂停期间不推进进度、不接受操作输入。
- 恢复 ACTION 后，若玩家仍在交互区且没有中断条件，则继续。
- 局部 RESET 后续恢复周期起点的装置状态，不能沿用撤销分支的 active/progress。

### D5. 量化进度与事件

每个装置保存有限浮点 `progress`，范围为 `0.0–1.0`，UI 可显示百分比。普通停留模式按 fixed delta 和注入的操作时长推进，完成时 clamp 到 1.0。

只产生三类领域事件：

```text
GOAL_OPERATION_STARTED
GOAL_OPERATION_COMPLETED
GOAL_OPERATION_CANCELLED
```

每条至少包含 goal ID、事件 tick、事件类型和事件发生时 progress；开始为 0，完成为 1，取消保留中断前值。取消回执产生后再清零权威进度，不逐 tick 发送百分比。哪些字段进入系统 Agent 报告由模块 4 决定。

### D6. 多装置独立状态

每个 goal 在自己的 `runtime_state` 中保存：

```text
active: bool
progress: float
complete: bool
```

运行时保证同一玩家同一时刻最多一个 goal active，可通过注册表找到当前装置，不增加全局共享进度。新增 active 字段必须进入严格实体校验和快照，不允许只存在节点或 UI 中。

## 5. E 组决策：联络语义

### E1. 成功进入即使用

玩家必须接近未使用联络点并发起交互。GameRuntime 确认能够成功进入联络会话后，记录该点 `used=true` 和当前 `active_contact_id`；进入失败不得消耗。

联络与猜测互斥，外部世界不能在联络中插入猜测。联络期间移动、设备运动、目标进度、踏板、观察、上报和周期计时全部冻结，真实等待时间只用于 UI 和后续服务超时。

### E2. 保持现状仍消耗

`KEEP_CURRENT` 不改变设备、不消耗设备改动额度，也不返还联络会话。非法批次不能自动转换为 KEEP_CURRENT。

### E3. 非法方案可重试

非法批次保持原世界和联络暂停，玩家可在同一会话内修改并重新提交。新方案按模块 2 规则领取新 request ID，旧请求和离点追发均无效。模块 3B 不新增另一套重试状态机。

### E4. 模型异常职责后置

AgentGateway 后续负责发现超时、空回复、非法 JSON、非法动作、断线和迟到响应，并以结构化失败返回；GameRuntime/GameSession 负责按已批准策略保持暂停、允许重试或结束。

模块 3B 不返还联络点、不自动跳过、不把失败伪装成部署成功或猜测未命中。是否返还及具体玩家反馈属于真实 Agent 接入前的异常策略。

### E5. 当前联络点 ID 的归属

`active_contact_id` 仅由可信 GameRuntime 用于当前暂停窗口、UI 和部署协调：

- 不进入系统 Agent context、报告或配置更新。
- 不作为玩家助手直接读取地图或设备位置的替代入口。
- 周期起点快照在 ACTION 保存时没有活动联络，不为此扩展系统 Agent 可见状态。

## 6. F 组决策：出口判定

### F1. 真实滑动碰撞

出口保持实心。玩家 `move_and_slide()` 后检查 `get_slide_collision()`，通过稳定实体 ID 识别出口并形成 `at_exit`，不另用可能大于实体体积的 Area2D 替代“触碰”。

### F2. 现有规则保持不变

- 未完成目标时出口仍阻挡通行；完成后也不要求先变成透明或可穿过。
- `at_exit` 只是 WorldFrame 条件，只有 `goal_complete && at_exit` 才满足撤离。
- 模块 3B 不直接修改 phase 或宣布成功，仍由 GameSession 处理普通边界、猜测优先和最终结果。
- 持续贴着出口可连续产生 at_exit，但 ROUND_END 后不得重复结算。

## 7. 单步与暂停集成边界

目标、联络和出口结果必须进入模块 3A 的同一完整候选和唯一物理步提交，不另建世界写入口。

- 目标操作事件供模块 4 消费，不塞进 WorldFrame。
- 联络请求属于控制信息，不属于观察报告。
- 同 tick 联络与猜测冲突时按 3A 已确定的“猜测优先、联络不排队”处理。
- 联络成功进入后的 used 记录必须与阶段状态一致，不能出现已暂停却未消耗或进入失败却消耗。
- 目标操作和出口不能直接调用 GameSession 完成本轮。

## 8. 验收场景（后续 Plan 展开）

| 编号 | 必须证明的行为 |
| --- | --- |
| B1 开始与进度 | 远程操作无效；接近后按一次开始，进度按模拟 tick 推进并显示 0–100% |
| B2 中断 | 方向输入、主动取消、残余移动或被机器人推出均中断并清零，取消事件保留中断前进度 |
| B3 多装置 | 两个装置各自保存进度，同一时刻最多一个 active，快照往返不丢失字段 |
| B4 暂停恢复 | 猜测/联络暂停不推进也不取消，恢复后继续；无重复开始或完成事件 |
| B5 联络使用 | 未接近或已使用不能进入；成功进入即消耗，进入失败不消耗，KEEP_CURRENT 不返还 |
| B6 非法与异常边界 | 非法批次可换请求重试且不改变世界；模型异常不由本模块伪造成功或退款 |
| B7 出口 | 未完成目标不能成功；完成后真实触碰形成条件，模块不直接结算，持续接触不重复结算 |
| B8 顺序 | 报告边界、猜测优先、联络互斥和同 tick 冲突行为符合模块 1/3A 合同 |

## 9. 风险与回炉条件

| 风险 | 处理 |
| --- | --- |
| 加减速残余速度导致非预期中断 | 用真实场景验证，不增加速度阈值或小游戏状态；必要时回 Plan 明确开始时机 |
| used 与 CONTACT_PAUSED 不一致 | Plan 必须固定进入和提交顺序，并覆盖进入失败、非法部署和 KEEP_CURRENT |
| 多装置 active 状态遗漏 | 纳入 DeviceRegistry 严格校验和快照测试，UI 不作为权威 |
| 出口 Area 触发偏离“触碰” | 使用真实滑动碰撞和稳定实体 ID |
| 范围重新膨胀 | 不恢复小游戏，不接真实模型，不顺带实现模块 4 或完整 RESET |

## 10. Plan：实施合同

本 Plan 复用 3A 的真实物理步、完整候选和唯一世界写入口，不新增第二套交互状态或通用 Interaction 框架。主场景提供最小交互提示和 KEEP_CURRENT 退出，不接真实助手。

### 10.1 最终 Grill 决策

- **G1 已确认**：多个核验装置必须全部 complete，才设置 WorldFrame.goal_complete。当前地图仍只有一个目标，不增加指定目标 ID 或多任务配置。
- **G2 已取消**：当前布局必须保证目标与联络点交互区不重叠，一次输入只处理一个设施；本版不增加通用目标/联络冲突优先级或交互仲裁框架。

其余实现默认，不需要再扩大玩法讨论：

- 同 tick 有方向输入时不开始新 goal，避免 STARTED/CANCELLED 同帧噪声；已 active 的 goal 收到方向输入则取消。
- 同 tick 同时触发 interact 和 cancel_interaction 时，不开始新的 goal；已有 active goal 仍按取消处理。此规则不扩展联络点的输入合同。
- 主场景只显示交互提示，CONTACT_PAUSED 下按 interact 明确 KEEP_CURRENT 并结束会话；不是自动跳过，也不提供真实助手或模型失败退款。

### 10.2 File Changes

| 文件 | 计划变化 |
| --- | --- |
| `game/scripts/runtime/interaction_system.gd` | 新增纯规则目标操作、联络请求、出口条件和领域事件计算 |
| `game/scripts/runtime/game_runtime.gd` | 扩展交互输入、同候选 used 提交、联络进入/退出、事件读取和最小 KEEP_CURRENT |
| `game/scripts/runtime/runtime_world_view.gd` | 在玩家/机器人实际运动后调用 InteractionSystem，输出最近一步交互结果 |
| `game/scripts/runtime/player_controller.gd` | 记录 move_and_slide 碰撞中的稳定实体 ID，供出口判定 |
| `game/scripts/runtime/device_view.gd` | 在实心设施 StaticBody2D metadata 写入 entity_id |
| `game/scripts/runtime/prototype_config.gd` | 注入交互距离、目标时长等 fixture；保持小游戏排除 |
| `game/scripts/world/device_registry.gd` | goal 增加 active，校验 progress 0–1、active/complete 布尔 |
| `game/scripts/world/world_state.gd` | 校验同一世界最多一个 goal active，保留多 goal 独立状态 |
| `game/scripts/core/game_session.gd` | 新增只读 `is_guess_tick()`，用于联络/猜测优先级，不改变现有阶段行为 |
| `game/project.godot` | 增加 interact、cancel_interaction 输入动作 |
| `game/scripts/main.gd` | 显示目标进度、联络状态和 KEEP_CURRENT 操作提示，不新增聊天 UI |
| `game/tests/runtime_motion_tests.gd` | 增加 goal active/progress、非法状态和多 goal 快照校验 |
| `game/tests/runtime_scene_tests.gd` | 增加目标操作、联络、出口、优先级和真实碰撞验收 |
| `game/README.md`、本 Spec、Feature Spec 索引 | 实施后回写实际验证、Plan-Execution Diff 和 Review |
| 新脚本 `.gd.uid` | 由 Godot 导入产生并入库 |

不改 WorldStepResult 字段、WorldCommandService 写入口、AgentProtocol、CI 工作流、现有模块 1/2 命令行为。模块 4 报告、完整 RESET、真实 Agent 和四轮不在本 Plan 内。

### 10.3 InteractionSystem 签名

```gdscript
static func advance(
    candidate: WorldState,
    player: PlayerController,
    input_vector: Vector2,
    interact_pressed: bool,
    cancel_pressed: bool,
    expected_tick: int,
    delta: float,
    rules: Dictionary
) -> Dictionary
```

返回：

```text
events: Array[Dictionary]
goal_complete: bool
at_exit: bool
contact_requested: bool
contact_id: int
errors: Array[Dictionary]
```

职责：

- 以 candidate 的固定设施坐标和实际玩家位置判断交互距离，不另建权威 Area2D 状态。
- goal 按一次开始；有方向输入时不开始新 goal；active 后方向输入、cancel 或离开交互区取消并清零。
- progress 按 fixed delta / goal_duration 推进并 clamp 到 0–1；开始、取消、完成各产生一条含 goal_id/tick/progress 的事件。
- 取消事件先保留取消前进度，再将权威 progress 清零；完成时 active=false、complete=true、progress=1。
- 多 goal 独立推进，但同一世界最多一个 active；所有已注册 goal 均 complete 才汇总 goal_complete。
- 联络只返回请求，不直接调用 GameSession，不写入系统 Agent 视图。
- at_exit 来自 PlayerController 的真实滑动碰撞 ID，不通过距离或 Area 近似。

### 10.4 PlayerController / RuntimeWorldView 签名

`PlayerController` 新增：

```gdscript
func touched_entity_ids() -> Array[int]
```

每次 advance 清空并重新记录本步 `get_slide_collision()` 中带 `entity_id` metadata 的碰撞体；DeviceView 在固定设施 Solid 上写入该 metadata。

`RuntimeWorldView` 调整：

```gdscript
var last_interaction: Dictionary = {}

func step_motion(
    candidate: WorldState,
    input_vector: Vector2,
    delta: float,
    rules: Dictionary,
    expected_tick: int = 0,
    interact_pressed: bool = false,
    cancel_pressed: bool = false
) -> Array[Dictionary]
```

保持原运动顺序，在玩家和机器人实际运动完成后调用 `InteractionSystem.advance()` 并保存到 last_interaction。默认值只用于旧测试兼容，正式 3B 调用必须传 expected_tick。

### 10.5 GameRuntime 与联络提交顺序

```gdscript
func step_once(
    input_vector: Vector2,
    delta: float,
    interact_pressed: bool = false,
    cancel_pressed: bool = false
) -> Dictionary
func keep_current() -> bool
func get_active_contact_id() -> int
func get_last_domain_events() -> Array[Dictionary]
```

GameSession 新增只读接口：

```gdscript
func is_guess_tick(expected_tick: int) -> bool
```

联络采用一次候选、一次提交：

1. InteractionSystem 只返回联络请求，不写 used。
2. 仅当请求有效、expected_tick 不是猜测刻、且本 tick 未同时满足通关条件时，接受联络。
3. 接受后，在同一个 candidate 中将该 contact.used=true，再调用 commit_runtime_step。此处不新增第二次世界提交。
4. 完成 GameSession.advance 和必要的普通报告处理后，最终 phase 必须为 ACTION，随后调用 begin_contact；成功才记录 active_contact_id。
5. 猜测或通关优先时，不设置 used、不发起联络、请求不排队。普通报告边界不阻止联络，报告完成后进入。
6. begin_contact 在以上不变量下必须成功；若失败属于程序错误并锁定运行时，不返还 used 或伪造另一阶段。

`keep_current()`：

- 仅 CONTACT_PAUSED 可调用。
- 通过现有 end_contact(deploy) 和 WorldCommandService 提交 KEEP_CURRENT。
- 成功后清除 active_contact_id 并返回 ACTION；used 保持 true。
- 非联络阶段、非法部署或失败不返回成功，不自动重试。

`get_last_domain_events()` 返回本步领域事件深拷贝，供模块 4 的报告缓冲消费；不是长期报告历史。

### 10.6 目标与出口状态校验

DeviceRegistry goal 运行状态固定为 `active/progress/complete`：active/complete 为 bool，progress 有限且 0–1。WorldState 额外拒绝多个 goal 同时 active；goal/contact/exit 的其它配置与 runtime_state 仍由 commit_runtime_step 的结构不变检查保护。

出口使用真实碰撞 ID：

- goal_complete 不满足时，at_exit 不产生成功。
- 所有已注册 goal 均 complete 的汇总结果与 at_exit 同时成立才写入 WorldFrame。
- 普通/报告/猜测结算继续由 GameSession 处理，不由 InteractionSystem 直接结束本轮。

### 10.7 原子 Checklist

- [x] **B0 基线与 fixture**：3A 基线 558 项通过；建立双 goal/contact/exit/墙体/摄像头/机器人交互 fixture，真实节点与交互区不重叠检查通过。新增 goal active 失败回归，实测 RuntimeMotionTests 38 passed / 2 failed，准确检出两个装置尚无 active；证据为 `tmp/module3b-b0-baseline.log`、`tmp/module3b-b0-red.log`。
- [x] **B1 状态 Schema**：扩展 goal active/progress 校验、单 active 约束和快照；覆盖多 goal 独立状态及非法 progress/active。
- [x] **B2 目标操作**：实现 InteractionSystem、真实接近/按键、停留进度、中断清零、暂停恢复和领域事件；验证一次输入只处理一个设施。
- [x] **B3 联络流程**：实现 is_guess_tick、同候选 used、active_contact_id、普通报告后联络、猜测不消耗和 KEEP_CURRENT；覆盖非法批次可重试且不返还。
- [x] **B4 出口与优先级**：实现真实碰撞 ID、全部目标完成汇总、WorldFrame 和 GameSession 集成；覆盖未完成不通关、完成后触碰、猜测优先和持续接触不重复。
- [x] **B5 主场景与全套验收**：接入输入、进度和联络提示，验证可持续灰盒、真实场景、全部新旧测试、性能和 Windows 导出。
- [x] **B6 Review 与回写**：独立缺陷复核，修复发现并补齐关键回归，回写实际结果、Plan-Execution Diff、Review 和剩余限制。

每个单元先建立可失败回归再实现；任何新增玩法、第二世界写入口、真实模型、小游戏或模块 4 范围扩张都先回 Plan。

### 10.8 Validation Plan

1. 原 558 项及新增 RuntimeMotion/RuntimeScene 检查全部通过，失败探针返回非零。
2. 真实场景证明目标开始、停留、取消、暂停恢复、多 goal、联络消耗/重试/保持现状和出口碰撞。
3. 同 tick 验证普通报告后联络、猜测不消耗和通关优先于联络；当前布局不构造目标/联络重叠场景。
4. 主场景持续可操作，CONTACT_PAUSED 可明确 KEEP_CURRENT 离开，不出现无恢复路径。
5. 复验 Windows 导出、Python/仓库/链接/场景引用/diff 检查；实际结果回写本 Spec，不用旧证据替代。

## 11. Review / Plan-Execution Diff / Resume

Spec Review：用户已批准 3B Plan；G1 确认为全部目标完成，G2 取消额外冲突优先级并以布局不重叠约束替代。没有剩余的 3B 玩法 Grill。B0–B6 已实施并完成本模块范围的 Review。

Execute Log / Validation：

- B0：3A 基线为 Session 81、World 223、Motion 31、Scene 253，共 558 项通过；双目标 fixture 与 `active` 缺失失败探针有效，`RuntimeMotionTests` 38 passed / 2 failed 是实施前的预期红色结果，不是最终回归状态。
- B1：goal 状态 Schema、单 active 世界校验、非法状态和快照回归落地；阶段日志为 81/223/46/263，均 0 failed。
- B2：目标开始、停留、取消、完成、多目标独立进度、暂停恢复及领域事件接入真实单步；阶段日志为 81/223/46/281，均 0 failed。
- B3：联络同候选消耗、猜测优先、普通报告后进入、非法部署留在暂停、重新领取请求以及 KEEP_CURRENT 恢复落地；阶段日志为 81/223/46/298，均 0 failed。
- B4：出口使用滑动碰撞实体 ID；未完成目标不通关，全部目标完成后真实触碰出口才满足撤离，猜测刻优先；阶段日志为 81/223/46/305，均 0 failed。
- B5：主场景已接交互键、取消键、目标进度与联络提示，启动输出 `RUNTIME_INTERACTIONS_READY`；120 个渲染物理帧在本机约 1870.810 毫秒，截图保存成功并已查看。Windows release 导出退出 0，导出程序 smoke 也输出该标记。原型 `interaction_distance=56.0`、`goal_duration=2.0` 及键位仅作 fixture；该单机耗时不是跨设备性能结论。
- B6：独立复核指出的两个 P2（外部合法部署后 `active_contact_id` 清理、已完成目标进度一致性）已修复；补充机器人真实推出、残余速度取消、真实出口/猜测优先、普通报告边界事件、非法部署后合法重试和 E 键 KEEP_CURRENT 输入路径回归。原复核者再次确认这些发现关闭。最终 Kimi 正式日志及本次续接复验均为 Session 81、World 223、Motion 47、Scene 342，共 **693 passed / 0 failed**；本次复验 Godot runner 退出 0，日志为 `tmp/module3b-resume-tests.log`。Python 13/13、仓库检查 0 issues、链接检查 0 broken、CRLF 兼容 diff 检查通过。
- 后续并键复评：同帧 interact+cancel 原判 P2 偏高，重定为 P3 输入边界；新增启动抑制与两项回归。所谓“未激活但保留进度”的 Schema 缺口只靠注入异常快照触发，当前批准的 Schema 合同只要求类型、有限范围及已完成状态一致性，正常生产路径不会生成，故不作为 3B 待修缺陷；完整 RESET 的快照恢复合同制定时再评估是否收紧。出口碰撞测试曾偶发失败，传送后增加物理帧同步等待。当前正式 runner 连续两次 Session 81、World 223、Motion 47、Scene 344，均为 **695 passed / 0 failed**，后一轮日志为 `tmp/module3b-eq-review.log`；未重跑 Windows 导出或远端 CI。

Review Matrix：

| 评审轴 | 结论 | 证据与限制 |
| --- | --- | --- |
| Spec Quality & Requirement Completion | PASS | B0–B6 的交互、联络、出口和主场景验收均有代码及实际运行证据；原型数值尚未作为正式玩法定案 |
| Spec-Code Fidelity | PASS | 目标、联络和出口共用 3A 候选提交；领域事件保留发生 tick，猜测/普通报告/通关顺序有回归；当前 695 项通过 |
| Code Intrinsic Quality | PASS（3B 范围） | 独立复核的 P2 与测试盲点已关闭；真实感知、统一目标报告、完整 RESET、四轮和真实 Agent 未在本模块验收 |

Overall Verdict：**PASS（模块 3B 已批准范围）**。后续复评的小范围并键修复已验证；沿用 2026-11-28 已完成的 Windows 导出与导出程序 smoke 证据，未把模块 4 的空报告回调视为真实报告实现。远端 CI 未在本次续接运行。

Plan-Execution Diff：

- 保持 G1 全部目标完成与 G2 不重叠布局约束，未引入额外交互仲裁、小游戏、第二世界写入口或 Agent 行为。
- 为覆盖联络退出和目标完成的状态不变量，独立复核后加强 `active_contact_id` 的阶段清理及 complete/progress 校验；这些是已批准合同的缺陷修复。
- 增加针对真实物理帧、残余速度、外部合法部署和优先级接缝的回归；同 tick 成功通关与联络的同时请求通过受控 `ForcedInteractionView` 验证运行时裁决，不宣称当前自然布局会产生这种重叠。
- `get_last_domain_events()` 只返回单步深拷贝，不是跨 tick 待上传报告缓冲。目标事件必须在后续报告集成中按发生 tick 缓存、归属上报周期和封批；3B 本身不实现这一能力。

Resume：3B Review 已完成，无需从 B1 重做。后续模块可消费结构化目标领域事件，但 4A/4B 的感知、统一报告、Agent 视图及完整 RESET 仍须各自 Plan 和验收。3A/3B 随本提交进入 Git 基线；4B 接线前仍须核对当前共同工作树与模块 4 的未提交改动。
