# SDD Feature Spec：模块 4B 真实感知与统一报告运行时集成

层级：Feature Spec。创建：2026-11-28 10:44（Asia/Shanghai）。目标分支：包含模块 3A 真实运行时及后续合法改动的共同基线。

**阶段：REVIEW PASS（4B 范围）。Plan Approval：Plan Approved（用户于 2026-11-28 明确批准 4B）。Execute：已完成，Review 证据见 §14。** 本文件规定模块 4A 纯数据内核接入真实 Godot 运行时的文件、签名、单步顺序与验收；模块 4A 已单独获批并通过其纯数据范围 Review。

## 0. 范围裁决与待验证项

用户已裁决：3B 的目标操作领域事件在 4B 纳入视觉/踏板同一上报批次。4A 仍只负责纯数据设备子包；4B 负责统一报告聚合，不修改 3B 文件。以下属于 Execute 验证或后续模块：

- [x] 真实场景 600 tick 中玩家单步最大 3 px、机器人最大 1 px，均小于 64 px 一格；推挤已有 3A 场景回归，尚未单独量测推挤瞬间的 4B 视野。
- [x] 已测正常路线的记录量、`step_once` 耗时和 Windows 导出启动；数值与限制见 §14。
- [ ] 模块 6 决定完整周期快照与 RESET 编排；本模块只提供感知状态和 buffer 的快照接口。
- [x] 已复核 3B 的 `WorldStepResult.domain_events` 与共同工作树，4B 只消费其事件，未改 3B 生产文件。

## 1. Goal 与 Done Contract

将模块 4A 的 `VisionGeometry`、`SensingKernel`、`ReportBuffer` 和设备 DTO 接入模块 3A 的真实单物理步，消费 3B 已提交的目标领域事件，在正常报告边界形成包含视觉、踏板和目标操作的角色安全统一报告。

Done Contract（后续验收目标，不是当前完成声明）：

- 每步在运动与 3B 交互之后、世界提交之前准备感知；world 和 GameSession 提交成功后才发布感知状态与事件。
- 摄像头/机器人观察携带事件时 R，踏板只使用运动前后演员格，不读写遗留 occupants，不做部署基线写回。
- tick 0 完整观察、逐 tick 状态变化、批次末去重、暂停冻结和半开窗口在真实运行时成立；长度 N 的 `[0,N)` 批次末为 N-1，tick N 属于下一批。
- 部署在脚下不触发，部署后首次进入正常触发；新增机器人、回退/重启后的采样点均有明确输入。
- 3B 的开始、取消、完成事件仅在 world/session 提交成功后入统一报告；系统视图不含玩家连续坐标、联络来源或踏板触发者；真实 Agent 和完整 RESET 不在本模块范围。
- 原模块 1/2/3A 回归及新真实场景测试通过，实际性能、记录量和限制回写本 Spec。

## 2. In Scope / Out of Scope

### In Scope

- `RuntimeSensingCoordinator`：视觉状态、待上传 buffer、提交后发布和快照接口。
- `UnifiedReportBatch`、`GoalOperationRecord` 和聚合缓冲：3B 领域事件与 4A 设备子包在同一半开窗口合批。
- `SystemAgentView`：静态地图、公开设备配置、已封存统一报告及空历史占位的安全投影。
- GameRuntime 感知准备/提交、报告边界回调和 Main 的 tick 0 初始化。
- 运动前 `previous_actor_cells` 提取、运动后踏板检测、部署/回退/重启连续性边界重新采样。
- 真实场景感知、暂停、部署、报告顺序、记录量和故障测试。
- 必要的 fixture 视距整数格调整、共享 runner 登记和实际证据回写。

### Out of Scope

- 修改 4A 已批准的纯数据算法或绕过其独立 runner。
- occupants/baseline_ready 的读取、写入、部署基线或立即清理。
- WorldCommandService、SceneWorldSyncAdapter、CycleState、WorldStepResult、AgentProtocol 的修改；GameSession 只增加一个只读周期长度 getter。
- 真实/模拟 AgentGateway、猜测、命中、调度、真实联络部署 UI。
- 完整 RESET、四轮结算、正式关卡数值和美术。
- 为视觉另写 Godot RayCast2D、ActorTrack 或第二套场景权威状态。

## 3. Context Sources / 当前代码事实

- [设计 Spec v0.44](../../PRELIMINARY_DESIGN_SPEC.md)、[机制 v0.25](../../侦测定位_机制草案.md) 与 [最小框架 Spec](../minimal-framework-spec.md)：现行感知、报告和前后位置踏板规则。
- [模块 4A Spec](2026-11-27_23-31_module-4a-sensing-kernel.md) §21：本集成必须复用的 DTO、纯函数和独立验收。
- [模块 3A Spec](2026-11-27_22-25_module-3a-runtime-scene.md)：真实单步候选、场景同步和故障锁；已 REVIEW PASS。
- [模块 3B Spec](2026-11-27_22-51_module-3b-interactions.md)：交互事件的 `goal_id/tick/type/progress` 与 `WorldStepResult.domain_events`；4B 消费，不修改 3B 生产逻辑。
- `game/scripts/runtime/game_runtime.gd`：当前真实组合、3B 交互接入及空报告回调。
- `game/scripts/main.gd`：Main 组合根。

3A 的 558 项是历史模块证据，不代表当前共同树或 4B 通过。3B Spec 已为 REVIEW PASS；4B Execute 前共享 runner 基线为 81/223/47/344。实施时已回读 GameRuntime 和 3B Spec，未覆盖其目标事件生产逻辑；最终共享结果见 §14。

## 4. 单步与提交顺序

每个 ACTION 物理步严格按以下顺序：

1. 读取 session/cycle 和隔离 candidate，提取 `previous_actor_cells`。`round_id/branch_id/guess_cycle_id` 只取 `GameSession.get_state_snapshot()`，不取 Agent payload；从 `GameSession.get_ticks_per_report_period()` 取得可信 `N>0`；以 `period_for_event_tick(expected_tick)+1` 生成本 tick 的 1 基 `report_cycle_id`，并交给 4A 用 N 复核。不从 `CycleState.report_period_id` 直接当作下一事件的周期号（该字段是已封批计数）。
2. `RuntimeWorldView.step_motion()` 完成玩家、机器人、摄像头及 3B 交互。
3. `RuntimeSensingCoordinator.prepare_step()` 在同一 candidate、同一 `sense_tick=expected_tick` 上计算视觉与踏板结果；4A 按 `expected_tick % N == N-1` 判定批次末并补齐完整观察，不写活跃世界或 buffer。
4. 创建 WorldFrame/WorldStepResult，保留 3B domain_events，调用现有 `commit_runtime_step()`。
5. 调用 `GameSession.advance_physics_step()`。
6. 仅当 world 和 session 均接受后，调用 `RuntimeSensingCoordinator.commit_step(prepared, step.domain_events, committed_world, context)`，同时校验并采用下一视觉状态、设备记录、目标事件及事件时公开设备配置；全有或全无，不从 `get_last_domain_events()` 读取上一步缓存。
7. 若产生 ReportBoundary，由现有 seal/update 回调在 coordinator 的隔离副本中暂存设备子包、目标事件与视图更新。`GameSession.process_report_boundary()` 返回并检查回调错误后，才发布统一包及新视图；若任一回调失败，进入终止性 fault，不把部分封批暴露为有效报告。
8. 继续现有联络、猜测或其他阶段逻辑。

失败规则：

- prepare 失败：不提交世界，GameRuntime 进入 fault。
- world/session 失败：丢弃 prepared 结果，不发布感知状态或事件。world 已提交而 session 失败时，沿用 3A 的终止性 fault，不宣称 world/session 已原子回滚。
- commit/seal/update 程序故障：进入 fault，不伪装成有效报告或模型失败；commit 与报告暂存/发布必须全有或全无。现有 `GameSession.process_report_boundary(seal_batch, update_view) -> bool` 的回调返回 `void`，总返回值不表示封批成功；它即使在回调内部失败也会继续调用第二回调并推进 session。GameRuntime 必须用回调错误锁存和结束后的检查阻止报告发布，不能仅检查 `processed`。session 已前进时不声称可回滚，只允许 fault 锁住后续推进。
- 非 ACTION 不调用 prepare/commit，因此暂停中没有视觉状态推进、踏板事件或报告计数。

部署、局部回退和整轮重启后不执行特殊 occupants 初始化；下一步从新的已提交世界重新提取 previous_actor_cells，新增机器人也包含在内。踏板配置在同一感知步内不变，事件使用 candidate 中踏板位置。

**N=3 贯通例**：首轮 tick 0 初始化视觉完整观察，记录周期号 1。tick 2 是 `[0,3)` 的最后 tick；若该 tick 状态变化，变化记录兼作批末观察，否则补完整观察，均为周期号 1。tick 3 的视觉变化、踏板或目标操作事件均为周期号 2；`advance_physics_step` 在提交 tick 3 后给出 boundary `[0,3)`、`report_period_id=1`，`ReportBuffer.seal` 只取 tick 0/2 等周期 1 设备记录，目标聚合器同样只取 `[0,3)`；tick 3 记录留待 `[3,6)`。即使 tick 3 恰是猜测刻，也不把 tick 3 的事件塞进上一批或触发额外猜测；后续若猜测周期身份改变，tick 3 记录保留原事件身份并由下一批封存。N=1 时 tick 0 初始化记录只生成一次。

## 5. RuntimeSensingCoordinator 合同

新增 `game/scripts/runtime/runtime_sensing_coordinator.gd`，`class_name RuntimeSensingCoordinator extends RefCounted`：

```gdscript
func initialize_round(world: WorldState, context: Dictionary, ticks_per_report_period: int) -> bool
func prepare_step(
    previous_actor_cells: Dictionary,
    candidate: WorldState,
    context: Dictionary
) -> SensingStepResult
func commit_step(prepared: SensingStepResult, domain_events: Array[Dictionary], committed_world: WorldState, context: Dictionary) -> bool
func seal_report_batch(boundary: ReportBoundary) -> bool
func update_system_view(boundary: ReportBoundary, committed_world: WorldState) -> bool
func finish_report_boundary() -> bool
func discard_report_boundary() -> void
func get_system_view() -> Dictionary
func get_ticks_per_report_period() -> int
func snapshot() -> Dictionary
func restore(data: Dictionary) -> bool
```

职责：

- `initialize_round` 在注入运行时前调用；Main 先验证 session 时钟为 0、阶段为 ACTION，以当前身份、`sense_tick=0` 和 `period_for_event_tick(0)+1=1` 建 context，并从只读 getter 取得 N。coordinator 调用 `SensingKernel.initialize_round(world, context, N)`，采用视觉状态并把 tick 0 记录及对应事件时公开配置加入 buffer，初始化 SystemAgentView；失败不启动运行时。首轮初始化只执行一次。
- `prepare_step` 调用 4A `SensingKernel.step(..., N)` 并返回隔离结果，短暂保存本次结果的深拷贝与 context 供提交校验，不修改 `_visual_states` 或缓冲；失败清除待提交结果。批次末由 4A 用同一 N 当场计算。4B 不另传容易算错的 `is_report_period_end`。
- `commit_step` 只接受与最近一次 prepare 深拷贝内容和 context 一致的结果；先对 3B 的 `goal_id/tick/type/progress` 做严格白名单与身份校验：仅接受 `GOAL_OPERATION_STARTED/CANCELLED/COMPLETED`、有效目标 ID、`tick == context.sense_tick`、有限 0–1 进度；把本 tick 的 `report_cycle_id` 由可信 N 生成，不信任领域事件自带周期号。报告仅传事件类型、目标 ID 和发生 tick，不传 3B 内部进度数值。使用隔离副本试追加 4A `ReportBuffer.append_all()`、目标缓冲和事件时公开配置，全部通过才一次性采用这些状态及 `next_visual_states`；任一失败不发布任何感知或目标记录。`committed_world` 仅用于读取本步已提交的公开配置，不向视图透传整个世界。
- `seal_report_batch` 在隔离副本上调用 4A `ReportBuffer.seal()`，并以同一 `[start_tick,end_tick)` 与周期号提取目标记录，形成待发布的 `UnifiedReportBatch`。`update_system_view` 只在待发布副本上调用 `SystemAgentView.update_configuration(committed_world)` 和 `append_batch()`。两回调返回 bool 供 GameRuntime 锁存错误；`finish_report_boundary` 仅在 GameSession 已返回成功且两回调成功时原子发布，`discard_report_boundary` 丢弃暂存。任一失败后 GameRuntime 锁死，不继续下一步。
- snapshot 保存已提交的视觉状态、设备 buffer、目标 buffer、事件时公开配置关联和系统视图 plain data；不保存未提交的 prepared 结果或边界暂存。restore 严格校验 N、身份、周期归属与各子结构，失败保持原状态；恢复后下一步重新提取演员格。它不实现完整 CycleState/RESET。

`previous_actor_cells` 由 `SensingKernel.actor_cells()` 在运动前世界生成，键为玩家 0 和机器人实体 ID；必须恰好覆盖 candidate 当前演员。

### 5.1 统一报告 DTO 与聚合

新增 `GoalOperationRecord`（四个正整数身份字段 `round_id/branch_id/guess_cycle_id/report_cycle_id`、`goal_id:int`、`event_tick:int`、`type:String`）和 `UnifiedReportBatch`（与 4A 子包相同的批次身份、`report_period_id/start_tick/end_tick`，另含有序 `records:Array[Dictionary]`）。二者均提供 `from_data(data: Dictionary)`、`to_data()`、`snapshot_copy()`；DTO 严格校验字段和身份，聚合 buffer 以可信 N 复核目标记录周期号，统一包再校验每条记录的半开窗口归属，非法输入返回 null。目标记录不接受玩家坐标、联络来源、进度或未授权领域事件。`records` 的 `record_type` 限 `visual / plate_activation / goal_operation`，每项保留原 DTO plain data；视觉/踏板外层附该事件时的**公开设备配置副本**，以解释同批配置变更，不能从封批时配置重算旧 R 或踏板位置。目标事件按 `goal_id` 关联已知固定装置，不另发送玩家位置。排序按事件 tick、设备/目标 ID、record_type、原始稳定序号；同 tick 不同事件与多演员匿名踏板事件均保留，不上传时去重。即使没有记录也生成合法统一空批；4A 的 `SensingReportBatch` 只是内部设备子包，不直接作为系统完整上报。

目标缓冲与设备 buffer 使用同一个 N、半开窗口和快照/恢复校验。4B 在设备记录追加时按原始顺序保存公开配置 sidecar；封批按同一稳定序号与设备子包逐条配对，不能只以 tick/设备 ID 作键，因为同 tick 同踏板可有多个匿名激活。sidecar 数量或身份不一致时拒绝整批。统一包校验 round/branch 与窗口一致；`guess_cycle_id` 可因边界 tick 恰逢猜测而不同于下一批的批头身份，必须保留记录原值。4B 验证每个目标 `goal_id` 在已提交 world 中确为 goal，目标事件类型及进度由 3B 生成，不重新推导操作事实；当前原型将开始/取消/完成三类已生成事件全部上报，记录粒度仍属后续试玩平衡参数，不在此宣布永久玩法定案。提交后缓冲，不即时上传或追加猜测。`event_tick == end_tick` 留给下一批，不能因先前目标完成或出口结算而跳过已有正常边界。

## 6. SystemAgentView 合同

新增 `game/scripts/agents/system_agent_view.gd`，`class_name SystemAgentView extends RefCounted`：

```gdscript
func initialize(world: WorldState) -> bool
func update_configuration(committed_world: WorldState) -> bool
func append_batch(batch: UnifiedReportBatch) -> bool
func to_data() -> Dictionary
func snapshot() -> Dictionary
func restore(data: Dictionary) -> bool
```

`to_data()` 返回：

```text
static_map：grid_size、cell_size、origin、terrain，以及已知固定 goal/contact/exit 的 ID 与格位置；不含玩家位置
device_configuration：公开摄像头/机器人/踏板配置；不含运行时玩家/机器人隐藏位置或 occupants
reports：已封存的 UnifiedReportBatch plain data
history：本模块固定为空数组，完整分支历史留给模块 6
```

`initialize` 建立开局静态地图和设备配置。每个报告边界调用 `update_configuration`，以当前已提交 world 替换**公开配置字段**：摄像头安装格、启用状态、视距/FOV/扫描配置；机器人已授权巡逻路线与视距；踏板格位置及设备 ID。排除玩家及机器人运行时连续位置、速度、占位、目标运行进度和联络来源。动态地形何时进入系统 Agent 的地图视图仍是待定项，本函数暂保留开局 terrain，不暗中决定拓扑可见性。`update_configuration` 先构造并校验完整新投影后替换，失败保持旧视图；`append_batch` 仅接已校验统一包，不将 4A 设备子包直接当完整报告，失败不部分追加；`to_data` 和 `get_system_view` 返回深拷贝；`restore` 严格校验全部字段，失败保持原视图。

递归拒绝 `player_world_position / player_position / contact_source / actor_id / occupants` 等不应交付字段。设备配置按实体 ID 排序，只含 Agent 已知地图与配置字段，不把 WorldState 整体透传。

本模块不修改 `AgentProtocol`，不发起猜测，不调用真实或模拟 Agent。

## 7. GameRuntime / Main 改动

`GameSession` 的最小只读增量：

```gdscript
func get_ticks_per_report_period() -> int
```

`GameRuntime`：

- 增加 `_sensing: RuntimeSensingCoordinator` 和 `configure_sensing(sensing: RuntimeSensingCoordinator) -> bool`；不改变现有 `configure()` 签名。注入时校验 coordinator 已初始化且 N 等于 `GameSession.get_ticks_per_report_period()`；旧运动测试若不注入，显式沿用空回调，不伪造 4B 感知验收。
- 在 `step_motion` 前提取 previous_actor_cells；从 `session.period_for_event_tick(expected_tick)+1` 生成可信周期号，在交互处理后、WorldFrame 前 prepare。`GameSession.get_ticks_per_report_period() -> int` 是本模块唯一新增的只读核心接口，返回 `_rules.ticks_per_report_period`；不改变周期推进/封批行为。
- world/session 接受后用本步 `step.domain_events` 与感知结果一起 commit；其后若有边界才 seal/update。
- `_seal_report_batch` 与 `_update_system_view` 是现有 `void` 回调包装：分别调用 coordinator 并在失败时锁存 `_report_callback_error`，绝不靠返回值让 GameSession 中止。若 seal 已失败，第二回调只保留错误、不执行更新。`process_report_boundary()` 返回后检查 `processed`、错误锁存及 staged 状态；全成功才 `finish_report_boundary()`。失败则 `discard_report_boundary()` 并 fault。不可用 `_last_domain_events` 作为报告来源。

`Main`：

- 创建 SessionRules、GameSession 和 coordinator（coordinator 内部持有 SystemAgentView）；以 session 当前 state/cycle 快照生成 tick 0 context，`report_cycle_id=session.period_for_event_tick(0)+1`，传 `session.get_ticks_per_report_period()` 初始化首轮。`CycleState.report_period_id` 初值为 0，是**已封批数**，不能直接填记录。初始化和注入完成后才允许 GameRuntime 自动推进。
- 初始化失败则不启动自动推进，并显示程序错误。

`PrototypeConfig` 仅把 `cell_size=64` 的 300 改为 320（5 格），保留 fixture 标记；不将数值升级为玩法定案。`runtime_scene_tests.gd` 两处 64/400 fixture 改为 64/384（6 格），其 100/400 fixture 和所有 `cell_size=1` 的 4/5 视距保持不变。复核由视距变化影响的预期，不为保持旧视野偷偷放宽校验。

`WorldState.validate()` 增加摄像头/机器人 `view_radius` 为 `cell_size` 正整数倍的校验，采用与 4A §21.3 相同的容差和正整数条件，非法时返回 `INVALID_PARAMETER`；模板、AddDevice、SetDeviceParameter 及快照恢复因此在部署前拒绝非整数格视距，而不是提交后才由感知器 fault。现有 DeviceRegistry 数值范围校验保持不变；4A 仍独立拒绝非法 world，防止绕过世界入口。

## 8. File Changes

| 文件 | 计划变化 |
| --- | --- |
| `game/scripts/runtime/runtime_sensing_coordinator.gd` | 新增运行时感知协调、提交后发布、封批与快照 |
| `game/scripts/reports/goal_operation_record.gd` | 新增 3B 目标领域事件的严格报告 DTO |
| `game/scripts/reports/unified_report_batch.gd` | 新增设备子包与目标事件的统一报告 DTO、稳定排序和隔离副本 |
| `game/scripts/agents/system_agent_view.gd` | 新增角色安全静态视图、边界配置更新、已封存统一报告与恢复 |
| `game/scripts/runtime/game_runtime.gd` | 增加感知注入、单步 prepare/commit 和真实报告回调；保留 3B 交互 |
| `game/scripts/main.gd` | 创建并注入感知系统，执行 tick 0 初始化 |
| `game/scripts/core/game_session.gd` | 仅增 `get_ticks_per_report_period() -> int` 只读接口；不改周期推进或回调签名 |
| `game/scripts/runtime/prototype_config.gd` | 仅调整整数格视距 fixture |
| `game/scripts/world/world_state.gd` | 增加整数格视距的最终世界校验，覆盖模板与命令候选 |
| `game/tests/world_command_tests.gd` | 增加非整数格视距的模板/命令拒绝回归 |
| `game/tests/runtime_scene_tests.gd` | 仅将两处 64/400 fixture 视距改为 64/384，保留 3B 测试与既有断言 |
| `game/tests/sensing_runtime_tests.gd` | 新增真实运行时、目标合批、部署、暂停、视图和故障验收 |
| `game/tests/run_tests.gd` | 登记新 suite，保持原套件与异步 runner |
| 新脚本 `.gd.uid` | Godot 导入生成并入库 |
| `game/README.md`、本 Spec、Feature 索引 | 实施后回写真实证据、限制和运行方式 |

默认不修改 `WorldCommandService`、`SceneWorldSyncAdapter`、`RuntimeWorldView`、`WorldStepResult`、`CycleState`、`AgentProtocol` 或 4A 文件；GameSession 仅作上述 getter 增量。若最新 3B 改动要求不同接缝，先回写本 Plan。

## 9. 原子 Checklist

- [x] **P0 基线复核**：4A 独立 114 项通过；3B 最终事件接口为 `goal_id/tick/type/progress`，共同工作树原共享 runner 为 81/223/47/344，3B 生产文件未改。
- [x] **P1 报告 DTO 与安全视图**：GoalOperationRecord、UnifiedReportBatch、SystemAgentView 已实现，严格字段、事件时公开配置、历史隔离及递归越权字段检查已验收。
- [x] **P2 协调器**：tick 0、prepare/commit、设备与目标合批、暂存/发布、成组快照与失败不污染已验收；匿名同 tick 双踏板事件保留两条。
- [x] **P3 运行时接线与视距校验**：GameSession 只加 N getter；GameRuntime/Main 已接入；N=3 tick 0/2/3、回调失败锁、64/300→320 与 64/400→384 迁移已验收。
- [x] **P4 踏板与部署范围**：真实出生与离开/重进、3A 推挤回归、4B 双演员/部署脚下/新增机器人及新局采样 fixture 已通过。完整局部回退与整轮重启的编排仍由模块 6 验收。
- [x] **P5 视觉与统一报告**：4A 首次/变化/不可见/R/批末去重独立测试继续通过；4B 的 N=1/3 半开窗口、暂停冻结、3B 开始/取消/完成合批、边界配置更新和终局半批已通过。
- [x] **P6 故障与回归**：4B 注入 prepare/commit/seal/update 故障时均停机且不发布报告；3A 世界/会话故障回归保持通过；正式 4A 与共享套件均通过，失败探针退出 1。注入故障不计入自然频率。
- [x] **P7 性能、自然故障观察与回写**：600 tick 固定路线和 300 tick 种子 2042 换向路线、共 30 批无非注入故障；记录量、耗时、灰盒与 Windows 导出证据及限制见 §14，README 和索引已更新。

## 10. Validation Plan

1. 4A 独立 runner 保持通过；当前正式 runner 的原套件无回归，新 `SensingRuntimeTests` 全通过。
2. 真实场景证明每步只在运动/交互后感知，world/session 未接受时无事件发布；各暂停阶段无新记录。
3. 部署在玩家或机器人脚下不触发，部署后首次进入触发；既有踏板上新增机器人不产生 phantom 激活。
4. 局部回退/整轮重启 fixture 从恢复后世界重新提取 previous_actor_cells，不沿用撤销分支位置。
5. 每条视觉记录含事件时 R，发现时含玩家格；同设备每 tick 最多一条；批次末不重复，历史 R 不被部署重写。
6. 3B 的开始、取消、完成事件各有原 tick/goal ID，只在提交后入 buffer，与视觉/踏板同批封存；N=3 时 tick 3 目标事件留在下一批，不能被 `[0,3)` 误封。目标事件不新增猜测，空批和混合批均合法。
7. 系统视图无玩家连续坐标、联络来源、occupants 或踏板触发者；设备配置在每个报告边界按已提交 world 更新，事件时公开配置与历史 R 不被改写，地形可见性保持后置；空批和混合批顺序正确。
8. 持续同格暴露不逐 tick 重复；实际记录量、帧时间和日志写入 Spec，不把 fixture 数值当正式平衡。正常路径长时/多批次运行须单独统计非注入故障的次数、故障码、发生 tick、复现步骤和修复范围；不能用人为故障注入的触发次数推断正常故障概率，也不能在没有足够运行证据时给出概率百分比。若正常合法路径出现故障，先定位并修复或明确阻塞 Review，再复跑同一场景。
9. `python -m unittest discover -s tests -v`、仓库检查、链接检查、diff 检查、Godot 导入、灰盒及 Windows 导出按实际结果回写。

## 11. Plan Approval / Resume

用户已于 2026-11-28 明确回复 `Plan Approved`，4B 获准 Execute。4B 已纳入消费 3B 目标事件与统一合批，但不授权改写 3B 生产逻辑；4B 的批准也不覆盖真实 Agent 或完整 RESET。当前 4A 新文件和多份文档仍未提交，实施不得覆盖其内容，也不重置工作树。

## 12. 最终可执行性复核（Plan 阶段）

- **技术错误已按主 Spec 修正**：批末公式、tick 0 周期号、`GameSession` 只读 N、3B 事件提交后合批、`void` 回调失败锁存、整数格视距与当前 fixture 迁移均有接口和验收落点，不需再作玩法裁决。
- **范围选择已裁决并获批**：目标事件由 4B 聚合，3B 只生产领域事件；4A 和 3B 各自已通过范围内 Review。用户在 §13 风险 Grill 后选择报告处理失败即停止本局，随后明确批准 4B Plan。
- **剩余实施风险**：`process_report_boundary` 无回调拒绝能力，失败后 session 可能已前进，只能终止性 fault；完整 RESET 必须恢复或清理跨边界待封记录及事件身份；动态图扑对系统 Agent 的可见时机仍留后续权限设计；64/300、64/400 fixture 迁移后需复测真实视野和旧断言。上述均已指定验收或后续归属，不能在本阶段声称通过。

## 13. 执行前风险 Grill（2026-11-28，讨论记录）

### 13.1 已裁决的架构取舍：回调失败后 fail-stop

现有 `GameSession.process_report_boundary(seal_batch, update_view) -> bool` 会顺次调用两个 `void` 回调，然后推进 `report_period_id` 和阶段；返回 `true` 仅表示边界流程被执行，不表示两个回调成功。因此若 4B 封批失败，coordinator 可以丢弃暂存包、保持 SystemAgentView 不变并令 GameRuntime fault，但不能使 GameSession 回到尚未处理边界的状态。进入猜测边界时，session 甚至可能已转为 `GUESS_PAUSED`；任何后续 Agent 入口都必须先检查 runtime fault，不能把这次状态当成有效报告已交付。

**用户裁决（2026-11-28）：暂按“失败即停止本局”设计。** 4B 因此采用终止性 fault、不给 Agent 交付部分报告、不自动重试；后续物理步和报告发布均被锁住。它足以完成当前无真实 Agent 的原型切片，但不是可恢复事务。若以后要求报告失败后同局继续或重试，须扩展 GameSession 的边界 API 和快照/回滚合同，超出本 Plan 现有的“GameSession 只加 getter”边界；不能由 `processed == true` 掩盖内部失败。用户要求观察正常场景中的程序数据故障；本轮 900 tick、30 批未发现非注入故障，样本不足以估计罕见故障概率，也尚无真实自然故障可评价修复难度。

### 13.2 由主 Spec 已决定、但要补验收的终局半批语义

正常报告只在固定边界交付，通关无须等待下一次定位。故一轮若在非边界 tick 提前结束，该轮尚未封存的当前半批记录只留在内部 buffer，不临时上传、不追加一次猜测，也不进入系统 Agent 已收到的报告。若恰在边界 tick 结束，仍先封存 `[start_tick,end_tick)`；边界 tick 自身属于下一批，不能偷塞进终局包。模块 6 在整轮重启时负责丢弃或归档旧轮内部待封数据，不能泄漏到新轮的 Agent 视图。4B 应测提前通关与边界通关两例，并明确区分“已发生但未交付”与“已封存可见”；这条按现行主 Spec 直接落实，除非用户另行改变上报节奏。

### 13.3 实施风险和对应检查

| 风险 | 容易发生的错误 | 4B 验收抓手 |
| --- | --- | --- |
| tick 3 与猜测边界 | 取已封批计数作事件周期号，或将 tick 3 记录封入 `[0,3)` | N=3 从 tick 0 初始化、tick 2 批末感知、tick 3 的视觉/踏板/目标事件贯通至下一批；猜测时只看已封批。 |
| 运动节点先于世界提交 | prepare 或世界校验失败时真实节点可能已移动，而权威 world 未写回 | 进入终止性 fault；无感知/目标记录发布，无后续物理步；不声称场景节点已原子回滚。 |
| 设备记录与事件时配置配对 | 同 tick 同踏板可有多条完全相同的匿名事件；按 `tick/device_id` 建 sidecar 映射会丢条或错配 | 用追加顺序的稳定序号配对，封批前后核对数量、类型、身份与顺序；双演员同 tick 和同批配置变更测试。 |
| 3B 领域事件可信度 | `WorldCommandService.commit_runtime_step` 提交的是候选世界，不校验 `WorldStepResult.domain_events` | 只消费 GameRuntime 同步生成的 `step.domain_events`，在 world/session 接受后做白名单、goal ID、tick、进度校验；不得从上一 tick 缓存补取。 |
| 视距整数格迁移 | 64/300=4.6875、64/400=6.25 会使模板或部署失败 | 原型 300→320，两个 64/400 fixture→384；100/400 保持合法；WorldState 在提交前拒绝非法值并复跑实际视野断言。 |
| 快照与后续 RESET | 仅恢复视觉状态却丢失目标缓冲、配置 sidecar 或已封周期 | 4B 快照严格成组校验、失败不污染；真实局部/整轮 RESET 编排仍属模块 6。 |
| 地图与性能 | 合法动态墙改变 R，而当前系统视图暂留开局 terrain；每 tick 几何和世界查询可能增加帧耗时 | 4B 不开放新拓扑可见性规则，记录限制；测真实设备数的记录量和帧时间，若超预算再单独调整算法/范围。 |

### 13.4 范围判断与待验证问题

3B 事件纳入同批、三个已生成的目标事件类型、N=3 半开归属、tick 0、整数格视距、角色安全字段和当前 fail-stop 合同均已确定并获批，不需要再次作为玩法选择。动态地形可见时机、完整 RESET 与真实 Agent 故障恢复属于后续阶段。900 个合法正常 tick 未出现非注入故障；强制注入只证明停机与信息安全，不作为故障频率样本。当前无新增 Grill 裁决项；若未来自然故障出现，须记录复现条件和修复范围，再判断是否扩大 GameSession 边界合同。

## 14. Execute 与 Review 记录（2026-11-28）

### 14.1 实际文件与接口

- 新增 `GoalOperationRecord`、`UnifiedReportBatch`、`SystemAgentView`、`RuntimeSensingCoordinator` 和 `SensingRuntimeTests`，连同各自 `.gd.uid`；共享 runner 登记新套件。4A 源码及 3B 事件生产文件未改。
- `GameSession` 仅增加 `get_ticks_per_report_period()`。`GameRuntime.configure_sensing()` 只在 tick 0 的 ACTION 阶段注入；单步从 session 生成 `report_cycle_id = period_for_event_tick(expected_tick)+1`，4A 再按 N 校验。Main 先生成 tick 0 观察再开启物理推进。
- `GameRuntime` 在候选运动和 3B 交互后 prepare，在 world/session 接受后 commit。两个 `void` 报告回调通过错误锁存与隔离副本暂存；`process_report_boundary()` 返回后确认无错才发布。错误进入终止性 fault，后续物理步不再推进。
- `WorldState` 在模板、快照和命令提交前拒绝非整数格 `view_radius`。原型 64/300 改为 64/320，原 64/400 场景 fixture 改为 64/384；100/400 fixture 无需迁移。

### 14.2 验收证据

| 检查 | 结果 |
| --- | --- |
| Godot 4.7.2 导入与 4A 独立 runner | 导入退出 0；SensingGeometryTests 26、SensingKernelTests 88，均 0 failed。 |
| 共享 runner | SessionKernelTests 81、WorldCommandTests 229、RuntimeMotionTests 47、RuntimeSceneTests 344、SensingRuntimeTests 129，合计 **830 passed / 0 failed**。 |
| 故障探针 | 共享 runner `--fail-probe` 退出 1；人为 prepare、commit、seal、view 故障均停机且无有效报告发布。 |
| N=3 与合批 | tick 0 初始化，tick 2 封 `[0,3)`，tick 3 事件留 `[3,6)`；目标 STARTED/CANCELLED/COMPLETED 与视觉、踏板按事件 tick 排序；同 tick 两条匿名踏板事件无丢失。 |
| 真实场景与导出 | 主场景 120 帧及 Windows release 导出程序 120 帧均退出 0，并输出 `RUNTIME_SENSING_READY`。 |
| 仓库维护检查 | Python 13/13、`check_repository.py` 0 issues、`check_project_links.py --all` 0 broken。 |

正常路径观察与强制故障注入分开统计。固定左右路线运行 600 个物理 tick、20 批、42 条统一记录，非注入故障 0；玩家最大单步位移 3 px、机器人 1 px，均小于 64 px 一格。种子 2042 的四向换向路线运行 300 tick、10 批、22 条记录，非注入故障 0。多次固定路线本机 headless `step_once` 平均值约 13.7–41.3 ms，单次最高值约 53.8–153.5 ms；最后一次共享 runner 记录平均 16.4 ms、最高 58.5 ms，换向路线墙钟约 5.0 s。这些数值含本机调度、Godot debug 脚本和测试场景开销，不能推断渲染帧率或稳定性能预算。最终共享 runner 日志为本机 `tmp/module4b-final-review-tests.log`，导出包在忽略目录 `build/`。

### 14.3 Plan/Execute 差异与剩余风险

- 核心接缝、N=3 半开归属、tick 0、3B 事件合批和 fail-stop 均按 Plan 落地。为防止失败的 tick 0 初始化留下半成品，coordinator 在发布内部状态前先复制 world；Main 初始化失败时保留错误文字。
- 完整局部回退与整轮 RESET 尚未存在；4B 只提供成组快照和新局采样 fixture，模块 6 必须编排权威 world、session 与感知状态的同步恢复。模块 6 还须处理终局未封半批的丢弃或归档。
- 系统视图的 `static_map.terrain` 保持开局拓扑；动态墙的 Agent 可见时机仍待后续权限设计。当前没有真实 Agent 消费视图，接入前须按 runtime fault 检查报告是否真正发布。
- 900 tick、30 批未发现非注入数据故障，但不足以量化罕见故障概率，也没有自然故障样本可判断修复难度。若以后需要失败后同局重试，当前 `GameSession` 的 `void` 回调及不可回滚边界必须另行设计。耗时波动较大，正式画面帧率仍需在后续可玩切片测量。

**Review 结论：PASS（4B 已批准范围）。** 无新增 Grill 裁决阻塞；后续 Agent、RESET、动态拓扑信息权限与性能预算分别在对应模块继续验收。
