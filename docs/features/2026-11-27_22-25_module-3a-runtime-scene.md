# SDD Feature Spec：模块 3A 场景同步、运行时协调与运动

层级：Feature Spec。创建：2026-11-27 22:25（Asia/Shanghai）。分支：`team/branch-1`。

**阶段：REVIEW 完成。Plan Approval：Plan Approved。Implementation Verdict：PASS（模块 3A 范围）。** P0–P7 已完成；独立复核的 2 个 P1、1 个 P2 及测试盲点均已修复并复核关闭。最终正式检查 81/223/31/253 条通过，真实持续灰盒和 Windows 导出已复验；真实感知、3B 交互、完整 RESET 与 Agent 不属于本模块通过范围。

## 0. Open Questions

以下事项属于后续 Execute、集成或 Review，不影响本 Plan 的架构决策成立：

- [x] 在 Plan 中确定具体文件名、类名、公开签名、测试套件和原子实施顺序。
- [x] 在 Plan 中明确可信运行时写回入口及 `world_revision` 的“部署版本”语义；实施时同步相关文档，不改写模块 2 的历史验证证据。
- [x] 用真实灰盒场景验证完整候选复制、物理推送和默认 60 Hz 下的性能，不预设优化框架。
- [x] 用最小 `AnimatableBody2D` 场景验证机器人推动玩家及挤压暂停行为；探针 10 项通过，未增加复杂推挤系统。
- [x] 目标操作、联络语义和出口判定已在模块 3B 的 D/E/F Research 中另行收敛，不属于 3A 实现。

## 1. Goal 与当前任务单元

将模块 2 的纯数据世界接入真实 Godot 场景，使玩家、机器人和摄像头能够按统一模拟 tick 行动，并保证部署后的节点、碰撞和权威 WorldState 一致。模块 3A 建立可信运行时协调、单物理步提交、真实场景同步和运动能力，为模块 3B 交互及模块 4 感知上报提供唯一接入点。

Done Contract（后续执行验收目标，不是当前完成声明）：

- 玩家在灰盒地图中连续移动、加减速并碰撞墙体；机器人沿固定路线折返、驻守、换路并能作为移动墙影响玩家；摄像头按模拟时间扫描。
- 每个完成的物理步只提交一次完整候选 WorldState；GameSession 只接受该步对应的 WorldFrame，暂停时不推进模拟。
- 真实 `SceneWorldSyncAdapter` 遵守模块 2 的 prepare/activate 合同；部署失败不伪造成功，未改设备运行状态不重置。
- 机器人路径失效仍由部署校验和同批显式修复处理，运行时没有自动寻路。
- 纯数据测试和真实 Godot 场景测试共同覆盖下述验收场景；实际性能、运行日志和限制回写本 Spec。

## 2. In Scope / Out of Scope

In Scope：

- `GameRuntime` 可信协调：阶段门控、单步顺序、运行时写回、报告边界协调和模块 4 接入点。
- 完整候选 WorldState、独立 `WorldStepResult` 及可信内部提交结果；不扩大 `WorldFrame` 职责。
- 真实 `WorldSyncAdapter` 子类、实体 ID 与节点映射、地形和设备派生同步。
- 玩家 `CharacterBody2D` 连续移动、简单加速/减速和碰撞。
- 机器人 `AnimatableBody2D` 固定路线运动、驻守、折返、当前段衔接、推动玩家及挤压暂停。
- 摄像头 heading / scan_direction 的模拟时间推进，不包含视觉判定。
- 单层灰盒 `TileMapLayer`，只有地板和墙；输入动作名和可注入运动参数。
- 独立运行时/场景测试及与模块 1、2 的必要集成回归。

Out of Scope：

- 模块 3B 的目标操作、联络点使用、出口触碰及最终交互数值。
- 模块 4 的视觉几何、踏板事件、ObservationRecord、ReportBatch 和 Agent 视图。
- 完整局部 RESET、整轮重启、四轮评分、真实 Agent、聊天 UI 和网络服务。
- 自动寻路、运行时绕路、通用 ECS、通用事务框架、通用角色手感系统。
- 冲刺、惯性状态、地面摩擦、不同地表规则及正式美术。
- 多层地形、自动地形规则、导航层和额外地形玩法。

## 3. Context Sources / Codemap / Context Snapshot

Requirement Sources：

- [现行设计 Spec](../../PRELIMINARY_DESIGN_SPEC.md) §4–8、§11：连续移动、设备行为、统一时间、联络/猜测优先级和验收边界。
- [机制基准](../../侦测定位_机制草案.md) §2–5：固定巡逻、实心设施、暂停与恢复语义。
- [最小游戏框架 Spec](../minimal-framework-spec.md) §2–8：`GameSession` 编排、WorldState 权威、派生同步及后续检查点。
- [模块 2 Feature Spec](2026-11-27_20-53_module-2-world-command.md) §5、§9–12、§20–21：世界写入口、候选副本、同步合同、路径同批修复和当前评审状态。

Code Terrain：

- [现有工程入口图](../codemap/2026-11-27_14-14_game-project-map.md)：历史入口索引；实际接口以当前代码为准。
- `game/scripts/core/game_session.gd`：阶段、tick、报告边界、联络和猜测顺序。
- `game/scripts/core/world_frame.gd`：位置、目标和出口的最小传递帧。
- `game/scripts/world/world_state.gd`：快照、坐标、空间和运行状态。
- `game/scripts/world/world_command_service.gd`：当前唯一活跃世界所有者及部署提交。
- `game/scripts/world/world_sync_adapter.gd`：prepare/activate 同步接口。
- `game/scripts/world/device_registry.gd`：六类实体及运行状态字段。

Context Bundle Snapshot（Lite）：

- 当前主场景仍是工程壳；规则内核和世界命令已有实现，但真实场景、物理写回和运动尚未形成。
- 模块 2 正在同行评审修复，R1 坐标表示、R2 向量有限性、R3 踏板基线与模块 3A 直接相关。Execute 前必须使用修复后的接口和回归证据，不能把旧测试通过当成真实物理就绪。
- 本轮采用现有文档和代码按需回读，没有新建重复 codemap 或 context bundle。

## 4. Research Findings 与架构边界

采用“Godot 节点执行物理，可信 GameRuntime 汇总并提交 WorldState”的路线。不采用纯数据重写碰撞，也不允许节点成为长期权威状态。

```text
Main：组合根，不裁决规则
└─ GameRuntime：Node，接收 Godot 物理步
   ├─ GameSession：阶段、时钟、报告边界、猜测、通关
   ├─ WorldCommandService：唯一活跃 WorldState 所有者
   ├─ RuntimeStepper：玩家/机器人/摄像头运动
   ├─ SensingSystem：模块 4 后续接入；模块 3A 使用空实现
   ├─ SceneWorldSyncAdapter：部署命令的真实场景同步
   └─ WorldView：节点、碰撞和显示
```

约束：

- `GameSession` 独占 phase、round_id、branch_id、guess_cycle_id 和 simulation_tick。
- 活跃 WorldState 仍只有一个所有者；玩家、机器人和交互节点不得直接改它。
- Agent 命令与可信物理写回是两条通道，不能复用角色权限或外部工具端点。
- 不使用全局 Autoload，不让 `SceneTree.pause` 或节点 Timer 成为规则权威。
- Godot 物理不要求跨机器确定性；程序以每个已完成物理步的实际状态写回权威世界，不伪造理论位置。

## 5. A 组决策：权威状态与提交

### A1. 运行时写回归属

采用第一种：模块 2 接口稳定后，在同一世界服务上增加可信内部运行时写回入口。研究方向为 `commit_runtime_step(expected_tick, step_result)`，具体签名留待 Plan。

- 不新建第二个活跃 WorldState 所有者。
- 不让设备节点直接修改权威世界。
- 不建立通用事务框架。

### A2. 完整候选副本

每个物理步使用完整隔离候选 WorldState：

- 运动和后续感知在同一候选上产生结果。
- 一次物理步只做一次完整提交，不做“运动一次、感知再一次”的双提交。
- 首版不设计 diff/patch 语言；性能问题先以实测证明，再局部优化。

### A3. tick 与 revision 分工

玩家移动不增加 `world_revision`：

- `simulation_tick` 判断物理步顺序和过期运行时结果。
- `world_revision` 只表示部署配置版本，继续服务 Agent 命令的 `base_world_revision` 校验。
- 集成时由模块 2 所有者同步文档措辞，避免再把 revision 解释为任意位置变化的版本；本轮不重命名字段。

### A4. 物理写回校验

物理写回不检查 Agent 角色权限、命令额度或合法部署区域，但必须检查：

- 当前为 ACTION。
- tick 连续且由可信 GameRuntime 调用。
- 候选 WorldState 完整、有限且合法。
- 提交成功后才能推进对应 GameSession。

### A5. WorldFrame 职责

WorldFrame 继续只包含 `simulation_tick`、玩家位置、`goal_complete`、`at_exit`，不携带观察记录或完整世界。感知事件另走模块 4 的事件和报告缓冲。

## 6. B 组决策：时间与暂停

### B1. 物理步与模拟 tick 1:1

一次 Godot 物理步等于一个 simulation_tick。该关系不要求每 tick 上报或调用 Agent；视觉内部检测频率后来已在设计 Spec v0.43／机制 v0.24 中确定为每 tick 一次，观察生成规则以模块 4A Spec 为准。

默认 60 Hz 只是引擎基线，不是玩法数值。完整候选复制和真实场景性能必须实测；若出现瓶颈，优先优化复制和同步，不引入多速率调度。

### B2. 暂停权威

不以 `get_tree().paused` 作为规则权威。只有 GameSession 为 ACTION 时 GameRuntime 才驱动物理步；联络、猜测、调度和回退选择期间 UI 与真实服务超时仍可运行。

### B3. 玩法计时

目标进度、摄像头扫描和巡逻均按物理步 fixed delta / tick 推进，不使用真实时间 Timer。真实 Timer 仅用于 UI 或后续模型服务超时。

### B4. 报告边界

设备只生成记录，GameRuntime 统一调用现有 `process_report_boundary(seal_batch, update_view)`。不引入逐设备异步 ACK，不让设备节点直接调用 GameSession。

### B5. 联络与猜测同 tick

猜测优先，本次联络输入不排队。完成本物理步及报告/猜测流程后，玩家可重新发起联络，避免猜测结束后意外弹出旧请求。

## 7. C 组决策：运动、碰撞与地形

### C1. 机器人是移动墙

- 玩家使用 `CharacterBody2D`；机器人优先验证 `AnimatableBody2D`。
- 玩家主动移动不能推动机器人，碰到机器人会被阻挡。
- 机器人沿固定路径移动，正常开阔区域中可以推动玩家，不偏离巡逻路线。
- 玩家被挤压在机器人与墙等实心物之间、没有足够空间时，机器人停在当前路径位置；通路恢复后继续。
- 准确语义是“玩家不能推动机器人，但能暂时阻挡机器人”。不引入抓捕、伤害、强制侧挤或额外失败。
- 阻挡会持续暴露于设备感知时，按感知步留下重复观察并在下一统一批次上报；不即时上报，也不增加猜测次数。

### C2 / C3. 路径失效与修复

- 保留最终候选世界校验：拓扑变化后任何机器人路线或衔接段失效，整批部署拒绝。
- 允许在同一部署批次中显式提交地形变化与受影响机器人的新路线，最终统一校验后原子提交。
- 新路线仍须遵守真实起点、完成当前段、四邻接、驻守/折返和不瞬移规则。
- 模块 3A 不做行动中自动寻路、路线截断、临时绕路或传送修复。
- 部署期自动路线建议器不属于本模块；未来确有需求时另行评审。

### C4. 玩家手感

玩家控制器内部支持 `max_speed`、`acceleration`、`deceleration` 三个注入参数，斜向输入归一化。机器人保持恒定巡逻速度。

- 利用现有 `player_velocity` 快照，不增加世界状态或通用运动组件。
- 不做冲刺、地面摩擦、惯性状态或通用手感系统。
- 数值由灰盒试玩调整，需关注停止距离及其对目标交互和暴露时间的影响。

### C5. 灰盒地形

采用单层 `TileMapLayer`，只有地板和墙。地形与碰撞由 WorldState 派生同步，不成为第二份权威地图。不增加自动地形、多层装饰或额外地形规则。

## 8. 单物理步合同

后续 Plan 应落实以下顺序，不允许各模块自行调换：

1. 检查 GameSession 为 ACTION，读取 tick N 的隔离 WorldState。
2. 收集玩家输入，执行玩家和机器人物理运动，推进摄像头扫描。
3. 形成完整候选 WorldState；模块 3B 后续加入交互结果。
4. 模块 4 基于同一候选状态执行感知并更新踏板等运行状态；模块 3A 使用空感知器。
5. 一次性提交完整候选；运动不增加部署 revision。
6. 构造 tick N+1 的最小 WorldFrame 并调用 GameSession。
7. 到达报告边界时由 GameRuntime 同步封存和更新视图。
8. 按新阶段继续行动、猜测、联络或结束；猜测同 tick 优先于联络请求。

Godot 节点必须先实际运动才能得到碰撞结果。若后续候选校验或提交意外失败，节点可能已经移动：此时视为程序错误，停止 GameSession 推进并锁定运行时，不伪造场景已回滚，也不把它转成可重试的模型失败。

## 9. 验收场景（后续 Plan 展开）

| 编号 | 必须证明的行为 |
| --- | --- |
| A1 玩家运动 | 八方向归一化、加减速和停止距离符合注入配置，不能穿墙，节点与 WorldState 一致 |
| A2 固定巡逻 | 单点驻守、多点折返、跨端点和格间换路正确，无斜向路径、自动寻路或瞬移 |
| A3 移动墙 | 玩家不能推动机器人；开阔区域机器人可推动玩家；挤压时机器人暂停且双方不穿墙，恢复后继续 |
| A4 摄像头扫描 | 边界反向和跨边界处理正确，暂停不前进，无关部署不重置相位 |
| A5 部署同步 | 新增、移动、删除设备及地形后节点和碰撞与 WorldState 一致，未改设备状态保留 |
| A6 失败门槛 | prepare 失败保留旧场景；activate/运行时提交故障锁定，不伪造成功或继续 tick |
| A7 暂停与边界 | 各暂停阶段运动完全冻结；报告统一处理；同 tick 猜测优先于联络 |
| A8 快照兼容 | 运动状态经 snapshot 往返不丢失；本模块不宣称实现完整 RESET |
| A9 性能证据 | 默认物理频率下真实灰盒运行有帧时间和行为记录；未实测前不宣称性能通过 |

## 10. 风险与回炉条件

| 风险 | 处理 |
| --- | --- |
| `AnimatableBody2D` 推挤或挤压行为不符合合同 | 先用最小真实场景验证；失败返回 Research，不静默增加复杂推挤系统 |
| 节点与 WorldState 分叉 | 每步以实际物理结果形成候选；提交失败锁定，节点不得直接写权威世界 |
| 完整候选复制造成性能问题 | 先测量，再局部优化；不提前设计 patch 框架 |
| 玩家加减速影响目标操作 | 参数后置试玩；模块 3B 明确中断条件，不新增通用速度阈值系统 |
| 地形变化使路径失效 | 整批拒绝或同批显式修复；不运行时自动修复 |
| 共用工作树冲突 | 模块 2 现有文件、core、AgentProtocol 和共享测试入口由指定所有者修改；3A 新文件按后续 Plan 分配 |

## 11. Plan：实施合同

本 Plan 采用一个前置物理探针和七个实施单元。前置探针不通过则停止后续 Execute 并返回 Research，不能用自定义复杂推挤系统替代审批。模块 3B 不在本 Plan 中提前实现。

### 11.1 File Changes

| 文件 | 计划变化 |
| --- | --- |
| `game/scripts/runtime/world_step_result.gd` | 新增单步候选、WorldFrame、领域事件和联络请求的纯数据容器 |
| `game/scripts/runtime/game_runtime.gd` | 新增 ACTION 门控、单步编排、可信提交、GameSession 推进和故障锁 |
| `game/scripts/runtime/runtime_world_view.gd` | 新增场景根、ID→节点映射、初始构建和真实物理步适配 |
| `game/scripts/runtime/scene_world_sync_adapter.gd` | 新增真实 prepare/activate 子类，处理地形和设备差异 |
| `game/scripts/runtime/player_controller.gd` | 新增 CharacterBody2D 玩家加速/减速、碰撞及实际状态读取 |
| `game/scripts/runtime/robot_controller.gd` | 新增 AnimatableBody2D 固定巡逻、推挤预检和挤压暂停 |
| `game/scripts/runtime/device_motion.gd` | 新增纯数据摄像头扫描和巡逻目标状态计算 |
| `game/scripts/runtime/device_view.gd` | 新增摄像头、踏板和固定设施的灰盒显示/碰撞适配 |
| `game/scripts/runtime/prototype_config.gd` | 新增明确标记为 fixture 的小地图、移动参数和会话配置 |
| `game/scripts/world/world_command_service.gd` | 新增可信 `commit_runtime_step()`；不改变 Agent 命令签名和部署 revision 行为 |
| `game/scenes/runtime/player.tscn` | 新增玩家 CharacterBody2D、CollisionShape2D 和灰盒显示 |
| `game/scenes/runtime/robot.tscn` | 新增机器人 AnimatableBody2D、CollisionShape2D 和灰盒显示 |
| `game/scenes/runtime/device_view.tscn` | 新增通用设备灰盒根及可选实心碰撞，不承载规则裁决 |
| `game/scenes/runtime/runtime_test.tscn` | 新增独立物理验收场景，不作为正式关卡 |
| `game/assets/graybox/tiles.svg` | 新增地板/墙两格灰盒图集及导入元数据 |
| `game/scenes/runtime/graybox_tileset.tres` | 新增单层地形 TileSet，仅墙格带碰撞 |
| `game/project.godot` | 只增加四个移动输入动作，不加入 Autoload 或玩法全局配置 |
| `game/scenes/main.tscn`、`game/scripts/main.gd` | 最后接入可运行灰盒与调试状态；保留 UI 组合根职责 |
| `game/tests/runtime_motion_tests.gd` | 新增纯数据写回、扫描、巡逻和快照回归 |
| `game/tests/runtime_scene_tests.gd` | 新增真实玩家、移动墙、场景同步、暂停和边界场景 |
| `game/tests/run_tests.gd` | 统一登记两套测试并支持真实物理场景的异步 `run()` |
| `game/README.md` | 实施后回写真实运行、测试、性能和限制证据 |
| 模块 2 Feature Spec | 仅同步 revision 为部署版本的既定语义及运行时入口；保留其 REVIEW 证据，不扩大模块 2 验收声明 |
| 本 Spec、Feature Spec 索引 | 回写 Plan-Execution Diff、Validation、Review 和状态 |
| 新脚本 `.gd.uid`、SVG `.import` | 由 Godot 导入产生并入库 |

不改 `GameSession`、`WorldFrame`、`AgentProtocol`、现有模块 1/2 测试逻辑、CI 工作流或真实 Agent 配置。运行时写回不调用 `WorldSyncAdapter`，因为真实节点已经在本物理步完成运动；部署同步仍走原适配器。

### 11.2 单步数据与写回签名

`WorldStepResult`（RefCounted）：

```gdscript
var candidate_world: WorldState
var world_frame: WorldFrame
var domain_events: Array[Dictionary] = []
var contact_requested: bool = false
var contact_id: int = 0

func _init(p_candidate_world: WorldState, p_world_frame: WorldFrame) -> void
```

模块 3A 的 domain_events 始终为空、contact_requested 为 false、contact_id 为 0；字段只作为 3B 已批准的接口，不提前实现交互。

`WorldCommandService` 新增：

```gdscript
func commit_runtime_step(
    expected_tick: int,
    step: WorldStepResult,
    session_snapshot: Dictionary,
    cycle_snapshot: Dictionary
) -> Dictionary
```

返回 `{"ok": true, "tick": expected_tick}`，或 `{"ok": false, "errors": Array[Dictionary]}`。校验：

- 无部署 activate 故障锁、无重入，step/candidate/frame 非空。
- session phase 为 ACTION，cycle tick + 1 等于 expected_tick，WorldFrame tick 一致。
- candidate 通过现有深拷贝和 `validate()`，向量及路径状态合法。
- 模板、地形、设备配置、实体 ID 集合、ID 高水位和 world_revision 与当前世界一致；本入口只允许玩家位置/速度和实体 runtime_state 变化。
- 成功以完整 candidate 替换活跃世界，不增加 world_revision，不调用部署同步适配器。
- 失败不写活跃世界；GameRuntime 随后锁定，不推进 GameSession，不声称已经回滚真实节点。

### 11.3 场景与运动签名

`PlayerController`（CharacterBody2D）：

```gdscript
func advance(input_vector: Vector2, delta: float, rules: Dictionary) -> void
func motion_state() -> Dictionary
```

`advance` 读取 `max_speed / acceleration / deceleration`，归一化输入，用 `velocity.move_toward()` 后调用无参数 `move_and_slide()`；`motion_state` 返回实际 position/velocity 的 plain data。节点不自行推进 GameSession，也不另设 `_physics_process()` 驱动。

`DeviceMotion`（RefCounted 静态纯函数）：

```gdscript
static func advance_camera(entity: Dictionary, delta: float) -> Dictionary
static func patrol_target(entity: Dictionary, delta: float, world: WorldState) -> Dictionary
```

分别返回新的 camera/robot runtime_state，不修改传入 entity。巡逻计算支持单点、折返、跨端点和 transition；不处理玩家、碰撞或寻路。

`RobotController`（AnimatableBody2D）：

```gdscript
func configure(entity_id: int) -> void
func advance(entity: Dictionary, world: WorldState, player: PlayerController, delta: float) -> Dictionary
func motion_state() -> Dictionary
```

`advance` 使用 `DeviceMotion.patrol_target()` 得到目标，按前置探针验证的方式处理推挤：

- 开阔区域由 AnimatableBody2D 原生运动影响玩家。
- 仅在机器人即将接触玩家时，用有限次数的 `test_move` 检查玩家能否沿同一运动方向被推动；无法推动则本步保持原巡逻状态，不推进路径进度。
- 不寻找侧向落点、不传送、不施加伤害，不引入持续推挤求解器。
- 成功后以实际节点位置和对应路径进度返回 runtime_state；若无法与合法路径状态一致则返回错误并触发运行时故障锁。

`RuntimeWorldView`（Node2D）：

```gdscript
func build_from_world(world: WorldState) -> bool
func step_motion(candidate: WorldState, input_vector: Vector2, delta: float, rules: Dictionary) -> Array[Dictionary]
func get_entity_node(entity_id: int) -> Node2D
func make_terrain_layer(world_data: Dictionary) -> TileMapLayer
func make_entity_node(entity: Dictionary) -> Node2D
```

- build 只用于初始场景；make_* 在 prepare 中创建未挂载节点，不产生活跃场景副作用。
- step_motion 依次推进玩家、机器人、摄像头，随后把实际玩家/机器人状态和扫描状态写入隔离 candidate。
- 玩家与机器人碰撞层按 C1 配置；SOLID 同时用于移动和遮挡，未实现的感知不读取私有节点状态。
- get_entity_node 只供可信适配器和测试，不提供给 Agent。

`SceneWorldSyncAdapter`：

```gdscript
func _init(view: RuntimeWorldView) -> void
func prepare(previous: Dictionary, candidate: Dictionary, changes: Dictionary) -> Dictionary
func activate(prepared: Dictionary) -> bool
```

prepare 构造暂存地形和新增/变更节点，不挂载、不加载外部资源、不改活跃节点。activate 只执行已准备的本地增删改、ID 映射更新和旧节点移除/queue_free；意外失败按模块 2 故障锁处理，不声称场景事务回滚。

### 11.4 GameRuntime 签名与顺序

```gdscript
func configure(
    world_service: WorldCommandService,
    session: GameSession,
    view: RuntimeWorldView,
    movement_rules: Dictionary
) -> void
func step_once(input_vector: Vector2, delta: float) -> Dictionary
func get_fault() -> String
```

`_physics_process()` 仅在 configure 完成、无 fault 且 ACTION 时读取移动输入并调用 `step_once()`；测试可关闭自动推进后直接调用该函数。

`step_once()`：

1. 读取 session/cycle 和隔离 WorldState，校验 ACTION 与下一 tick。
2. 调用 view.step_motion 形成完整 candidate；模块 4 位置保留空感知，不读取或写入遗留 occupants/baseline_ready。
3. 创建最小 WorldFrame（3A 的 goal_complete=false、at_exit=false）和 WorldStepResult。
4. 调用 commit_runtime_step；失败设置 fault 并返回，不推进 GameSession。
5. 调用 GameSession.advance_physics_step。
6. 若有报告边界，以本模块的空记录缓冲调用 `process_report_boundary()`；回调明确标记模块 4 替换点，不伪造观察报告。
7. 返回 ok、tick、当前 phase 和错误数组；非 ACTION 调用不改变任何状态。

### 11.5 Prototype Config 与主场景

```gdscript
static func level_data() -> Dictionary
static func movement_rules() -> Dictionary
static func make_session_rules() -> SessionRules
```

配置只含一张用于验收的小地图、必要设备、玩家出生点、移动/扫描参数及上报/猜测 tick 数。数值均标为 fixture，不回写为正式玩法。Main 负责创建 LevelTemplate、WorldState、GameSession、WorldCommandService、RuntimeWorldView、SceneWorldSyncAdapter 和 GameRuntime；不在节点脚本中另建世界副本。

### 11.6 原子 Checklist

- [x] **P0 基线与物理探针**：模块 1/2 基线实测为 81/223 通过、0 失败；`tmp/module3a_animatable_probe.gd` 覆盖玩家不能推机器人、开阔推挤、墙角挤压暂停和恢复，最终 `10 passed, 0 failed`。证据为 `tmp/module3a-baseline-import.log`、`tmp/module3a-baseline-tests.log`、`tmp/module3a-animatable-probe.log`。
- [x] **P1 单步写回**：WorldStepResult 和 commit_runtime_step 已实现；RuntimeMotionTests 覆盖 ACTION、tick、结构不变、runtime_state 更新、revision 不变和失败隔离。
- [x] **P2 玩家运动**：PlayerController、玩家场景和移动输入已实现；归一化、加减速、停止、碰撞和实际状态写回通过真实场景测试。
- [x] **P3 设备运动**：DeviceMotion、RobotController 和摄像头扫描已实现；驻守、折返、跨端点、transition、挤压暂停及快照通过回归。
- [x] **P4 场景构建与部署同步**：灰盒 TileSet、RuntimeWorldView、DeviceView 和 SceneWorldSyncAdapter 已实现；新增/移动/删除、地形碰撞、状态保留、prepare 失败和 activate 故障锁通过回归。
- [x] **P5 运行时总装**：GameRuntime 与 Prototype Config 已接入 Main；单步提交、暂停冻结、报告边界、空感知替换点和故障锁通过回归。
- [x] **P6 正式测试入口**：runner 支持异步场景 suite 并登记两套测试；失败探针实际退出 1，全部新旧测试通过。
- [x] **P7 验收与回写**：导入、headless、真实灰盒、性能、Windows 导出和仓库检查完成；独立复核的 P1/P2 与测试盲点已修复并复核关闭，最终 Review 已回写。

每个单元先补能失败的最小验收，再实现；若需要改变本 Plan 的签名、单步顺序或文件职责，先回写 Plan，不顺带实现 3B/4。

### 11.7 Validation Plan

执行阶段必须保存并回写以下实际证据：

1. Godot 4.7.2 headless import 无脚本/解析错误。
2. 原 SessionKernelTests / WorldCommandTests 全通过，新 RuntimeMotionTests / RuntimeSceneTests 全通过；失败探针退出非零。
3. 真实物理场景证明移动、碰撞、推挤、挤压、巡逻、扫描和部署同步，不以纯数据替身代替。
4. 主场景灰盒运行记录默认物理频率下的帧时间、实际行为和故障日志；未测量前不宣称性能通过。
5. `python -m unittest discover -s tests -v`、`python scripts/check_repository.py`、`python scripts/check_project_links.py --all`。
6. `git -c core.whitespace=cr-at-eol diff --check`，以及场景资源引用和 Godot 错误日志检查。
7. Windows 导出仅在本模块形成可运行灰盒后复验；不沿用模块 0 的历史导出冒充本模块证据。

## 12. Review / Plan-Execution Diff / Resume

Spec Review：用户两次回复 `Plan Approved`，第二次要求按顺序执行全部 P；未另行执行 REVIEW SPEC。P0 曾按单步门禁停点，随后按用户指令连续完成 P1–P7。

Execute Log / Validation：

- P0：基线导入与 runner 退出 0，SessionKernelTests 81、WorldCommandTests 223 均通过；AnimatableBody2D 探针覆盖玩家阻挡、开阔推挤、挤压暂停和恢复，10 passed / 0 failed。
- P1：WorldStepResult 与可信 commit_runtime_step 落地，校验 ACTION、连续 tick、WorldFrame、结构不变和完整候选；运动不增加部署 revision。
- P2：玩家 CharacterBody2D 加减速、归一化、停止距离和真实碰撞通过场景回归。
- P3：机器人驻守、折返、跨端点、transition、移动墙推挤/挤压暂停及摄像头扫描通过纯数据和真实场景回归；sync_to_physics 的延迟发布按实际引擎行为处理。
- P4：单层 TileMapLayer、设备 ID 映射和 SceneWorldSyncAdapter 落地；新增/移动/删除、固定设施碰撞、地形、状态保留、prepare 拒绝和 activate 故障锁通过回归。
- P5：GameRuntime 与 Prototype Config 接入 Main；每步一次提交、报告边界、暂停冻结和故障锁通过回归。主场景输出 `FRAMEWORK_SHELL_READY` 与 `RUNTIME_GRAYBOX_READY`。
- P6：正式 runner 支持异步场景 suite。最终 SessionKernelTests 81、WorldCommandTests 223、RuntimeMotionTests 31、RuntimeSceneTests 253，共 **558 passed / 0 failed**；失败探针实际退出 1。
- 真实灰盒：120 个渲染物理帧实测约 1.85–1.90 秒；生成并人工查看 `tmp/module3a-graybox.png`，玩家、摄像头、机器人、踏板、目标、联络点和出口均可见。修复后画面保持 `Tick 119 · Phase 0`，不再于约一秒后停在 GUESS_PAUSED；未用单点记录推断其他机器性能。
- Windows：release 导出退出 0，`2042-framework.exe` 为 109,127,680 字节、`.pck` 为 414,840 字节；导出程序无窗口运行退出 0 并输出相同就绪标记。
- 工程检查：Python 13/13；仓库检查 0 issues；链接检查 0 broken；场景引用 0 errors / 0 warnings；CRLF 兼容 diff 检查通过。最新 Godot 正式日志无脚本/解析错误；预期故障测试只产生文本诊断，不伪装为失败。
- 独立复核：初检的 2 个 P1、1 个 P2 及 P3 测试盲点已修复。主场景 fixture 避免进入未实现的猜测流程，prepare 失败释放全部暂存节点，真实驻守/折返/transition、玩家阻挡、各暂停阶段和部署后碰撞均进入正式回归。原评审者复核确认全部 CLOSED；推挤测试另补每步 ok 与实际位移断言，避免空转通过。

Review Matrix：

| 评审轴 | 结论 | 证据与限制 |
| --- | --- | --- |
| Spec Quality & Requirement Completion | PASS | P0–P7 验收均有实际运行证据；只覆盖灰盒运动、运行时写回和部署同步 |
| Spec-Code Fidelity | PASS | 独立复核发现已修复并关闭；最终 558 项检查通过，持续灰盒和导出复验通过 |
| Code Intrinsic Quality | PASS（本模块范围） | 无未关闭 P0/P1/P2；模块 4 感知、3B 交互、完整 RESET、真实 Agent 和远端 CI 仍不在本模块验收范围 |

Overall Verdict：**PASS（模块 3A 已批准范围）**。本地 Godot 4.7.2 与 Windows 导出验证通过；远端 CI 未运行，未宣称真实设备感知、完整猜测周期或可玩任务闭环。

Plan-Execution Diff：

- `AnimatableBody2D.sync_to_physics` 会在下一物理同步发布变换，不能在同次赋值后立即读取并断言新位置。实现返回经校验的目标运行状态，下一步读取已同步节点位置；未增加自定义推挤求解器。独立复核进一步确认 CharacterBody2D 的实际位移发生在玩家 move_and_slide 内，候选在读取前已包含该结果。
- DeviceView 在 prepare 阶段尚未进入场景树，因此 configure 显式取得子节点引用；灰盒多边形使用 Vector2 点数组，并加入非空绘制回归，避免 prepare/显示差异。
- 测试 runner 改为延迟调用并 await 各 suite，以覆盖真实物理帧；原同步套件保持不变。
- 预期故障测试通过结构化结果、运行时 fault 和文本日志验证，不让预期错误污染通过日志的错误扫描。
- PrototypeConfig 的 fixture 将猜测间隔设为 30/1000000，仅用于保持运动灰盒持续可操作；真实猜测和恢复不在本模块实现。
- SceneWorldSyncAdapter 增加 prepare 失败统一 discard，覆盖已创建地形和实体的释放；TrackingWorldView 正式回归证明未知 ID 的后置失败不会遗留暂存节点。
- world_revision 的部署版本语义已同步到模块 2 文档；未改变 Agent 命令签名、GameSession、WorldFrame、AgentProtocol 或 CI 工作流。
- 未实现 3B、真实感知、完整 RESET 或自动寻路，没有新增通用事务/交互/手感框架。

Resume：模块 3A Review 已完成。下一步基于真实 GameRuntime、WorldStepResult、commit_runtime_step 和 SceneWorldSyncAdapter 编写模块 3B Plan；3B 仍需独立 Plan Approval，不能沿用本批准直接实施。
