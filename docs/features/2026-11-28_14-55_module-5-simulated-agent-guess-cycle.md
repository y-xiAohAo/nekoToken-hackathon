# SDD Feature Spec：模块 5 模拟系统 Agent 与一个完整猜测周期

层级：Feature Spec。创建：2026-11-28 14:55（Asia/Shanghai）。目标工程：Godot 4.7.2 stable。

**当前阶段：REVIEW COMPLETE。批准状态：Plan Approved（用户于 2026-11-28 在后续消息明确批准）。状态：模块 5 实施与本机验证完成。** §0 为最新裁决，§P 为唯一获批的实施合同。后方 §A 的旧 Research/Plan 仅供追溯，不得执行；最终证据见 §P9。

本文件中的定位尺寸、设备总量、调度尝试数、禁区大小和关卡数值均为可替换原型配置，不冒充已经试玩定案的正式数值。

## 0. 最新裁决汇总（v2，当前 Research 合同）

本节是 2026-11-28 后续讨论的用户裁决汇总，优先级高于下方旧版踏板-only Plan。旧版 §A1–§13 保留为早期研究和取舍记录，**不再作为执行或验收合同**。本节裁决由 §P 细化为待批准的新 Plan；不能因为旧文含有 File Changes/Checklist 就进入 Execute。

### 0.1 模块边界与实施顺序

模块 5 仍只负责系统 Agent 的一个猜测周期，但系统调度权限扩展为摄像头、机器人和已有组合障碍整体移动。建议按两个可独立验收的检查点实施：

1. **世界模型与公开视图迁移**：独立摄像头、多格障碍实例、空间查询、场景同步、快照字段和猜测刻公开世界状态。
2. **系统 Agent 周期**：严格 DTO、冻结帧 hit、系统调度、拒绝回执、有限重试、故障门控和主场景验收。

玩家助手实际接入仍不属于模块 5。模块 5 只提供可复用的角色 policy、命令校验、原子提交和历史接缝；助手对话与玩家确认 UI 留给后续助手模块。

命中进入 `RESET_CHOICE`；未命中且冻结帧已满足通关条件直接进入 `ROUND_END/SUCCESS`；其余未命中进入一次调度窗口。成功调度后仍停在 `CYCLE_START_PENDING`，完整快照和 RESET 归模块 6，不调用 `resume_cycle(true)` 伪造恢复条件。

### 0.2 猜测刻公开世界状态与信息白名单

系统 Agent 在每个猜测刻获得当前公开地图状态，并在未命中的调度窗口继续使用同一冻结公开状态：

- 当前基础地形和组合障碍实例。
- 摄像头配置及扫描相位。
- 机器人配置及实际运动锚点：position、所在格、path_index、段进度、travel_direction、transition 和 patrol_path。
- goal/contact/exit 的类型、稳定 ID 和位置。
- 当前部署 revision、设备总量和公开调度规则。

公开视图必须是显式白名单，不能采用“完整 WorldState 仅删除玩家字段”的投影。继续排除：

- 玩家连续位置、玩家格、速度和活动联络来源。
- `contact.used`、`active_contact_id`。
- `goal.active/progress/complete`；目标事实继续由既有目标操作报告表达。
- 内部 ID 高水位、缓存、prepared 结果和未公开运行时字段。

正常统一报告仍按 4B 边界交付，保留事件时 R/P、原 tick 和配置 sidecar。为支持扫描相位决策，视觉记录的公开 sidecar 需补事件时 heading/scan_direction；历史事实不按后续部署重算。

### 0.3 系统与助手的权限矩阵

| 对象 | 系统 Agent | 后续玩家助手 |
| --- | --- | --- |
| 摄像头 | 允许新增、删除、移动；总量上限；任意结构合法锚格 | 只能修改一台已有摄像头，不允许增删 |
| 摄像头字段 | `scan_center / scan_half_angle / heading / scan_direction` | 仅 `scan_center / scan_half_angle`，不能直接写扫描相位 |
| 摄像头固定项 | 首版不开放 `view_radius / fov_angle / scan_speed` | 同左 |
| 机器人 | 允许新增、删除和 `SetPatrolPath`；总量上限；新增须给合法初始路线 | 只能对一台已有机器人提交受限 `SetPatrolPath`，不允许增删 |
| 机器人运动状态 | 猜测刻可读；不能直接写连续位置、路径进度或折返状态 | 不直接读取或写入 |
| 组合障碍 | 只允许移动现有实例；不增删，不开放任意 `SetMapCell` | 不开放 |
| 踏板 | 沿用已获准的新增、删除、移动权限，受合法区域和总量上限约束 | 不开放 |
| 固定设施及未列对象 | 不因框架能力自动授权 | 不开放 |

系统修改只在未命中后的 `DISPATCH_PAUSED` 提交；助手修改只在 `CONTACT_PAUSED` 结束、恢复行动前提交。双方不存在额外优先级，同一控制项按实际成功提交顺序覆盖，无关项保留。

### 0.4 摄像头安装与放置矩阵

摄像头改为**单锚格、非实心、不依赖墙体**的独立设备。墙体仍遮挡视觉，但不再决定摄像头安装是否成立；移除后续实现对 `mount_type / wall_side / 支撑墙` 的依赖。

首版共格与放置矩阵：

| 组合 | 规则 |
| --- | --- |
| 摄像头 + 摄像头 | 同锚格最多一台 |
| 摄像头 + 踏板 | 允许 |
| 摄像头 + 玩家/机器人 | 允许，不阻挡通行 |
| 摄像头 + 实心障碍/固定设施 | 拒绝 |
| 新增机器人 + 玩家/其它机器人 | 实际重叠时拒绝 |
| 组合障碍 + 摄像头锚格 | 拒绝 |
| 组合障碍 + 踏板/固定设施 | 拒绝 |
| 组合障碍 + 玩家/机器人 | 拒绝 |

机器人换路继续遵守真实暂停位置或未完成段终点锚定、四邻接、驻守/折返和不瞬移；新增机器人出生格必须属于其合法初始路线，不能通过驻守或 MoveDevice 传送。

### 0.5 组合障碍表示与移动

采用“基础地形 + 稳定障碍实例 + 固定模板 + 派生覆盖格”：

```text
ObstacleTemplate：template_id、固定局部 footprint、移动/视觉阻挡、固定素材或 PackedScene
ObstacleInstance：obstacle_id、template_id、anchor_cell
```

不保存 orientation，不允许旋转、拆分、合并或逐格改写。贴图按模板局部位置组织；房子整体平移时不得根据全局邻接重新自动铺砖。优先使用整张预合成贴图或固定 PackedScene，素材模板可以是 1×1、1×2 或任意固定多格形状。

障碍实例具有稳定 ID，逻辑占用格由模板 offset 与 anchor_cell 派生，供碰撞、视觉、路径、共存和快照查询使用。连通区域只能作为地图编码，不能代替可移动房子的实例身份。

系统只提交整个实例的 `MoveObstacle`。程序对新 footprint 整体检查地图边界、固定设施、其它障碍、演员占位、摄像头锚格、机器人路径和玩家禁区；任一格非法则整个操作拒绝，不裁剪、不留下半座房子。允许玩法上切断玩家到目标或出口的路线，但不允许产生结构性非法世界。

### 0.6 玩家部署保护区

玩家位置仍只供程序校验，不交给系统 Agent。程序按猜测刻冻结玩家格生成配置化的正方形部署禁区：

- 额外半径禁区只用于实体组合障碍移动。
- 障碍任意 footprint 格与禁区相交即整个操作拒绝。
- 摄像头不使用额外半径禁区；新增机器人只检查真实演员重叠，不增加额外半径。
- 禁区仅在正式候选提交时检查，不提供任意坐标预检工具。
- 禁区中心不进入公开视图、历史或 Agent 回执。
- 下一次调度按新的冻结帧重新计算，不形成第二份长期权威状态。

该规则限制系统部署和围堵能力，不改变定位矩形或 hit 算法，也不能被表述为彻底消除位置探测。

### 0.7 非法调度回执、有限重试与模型异常 stop

必须区分“格式合法但世界规则拒绝”和“模型/协议异常”。

**可修正的调度拒绝：**Agent 响应通过严格 DTO，但命令因权限、位置、共格、路径、设备上限或禁区而被 WorldCommandService 拒绝时：

- 返回结构化 `status=REJECTED` 和安全 `errors[{code,command_index}]`，不是只有 success=false。
- world、revision、报告和 simulation_tick 不变，phase 保持 `DISPATCH_PAUSED`。
- 当前 request_id 失效，程序通过 `renew_world_request()` 领取新 request_id；下一请求携带安全拒绝回执。
- 每次拒绝连同原请求身份进入调度历史。
- 隐藏占位、玩家禁区等统一返回 `PLACEMENT_REJECTED`，不返回禁区中心、真实坐标或合法位置建议。
- `max_dispatch_attempts` 限制正式尝试总数；首版 fixture 为 2，即首次提交加一次修正。达到上限仍被拒绝则 STOP。
- APPLIED、UNCHANGED 或显式 KEEP_CURRENT 才正常结束调度；拒绝不自动转 KEEP_CURRENT，也不推进猜测周期。

**模型或协议异常：**当前猜测/调度出现超时、空回复、断线、畸形字段、未知动作、错误身份、非法定位形状/尺寸/边界或 Agent 自报 hit/phase/success 时，立即 runtime fault / STOP，不自动重试，不转成 miss。旧请求的迟到回调直接丢弃。

可信 envelope 的 INVALID_CONTEXT、STALE_BRANCH、INVALID_PHASE、内部 revision 不一致和同步 activate 失败属于程序或协议故障，不伪装成 Agent 可修正的普通 REJECTED。

### 0.8 后续玩家助手合同

玩家助手不接地图、公开世界状态或系统报告，只接受玩家描述、通用工具结构、自身历史和执行回执。采用**方案 B：助手提议、玩家确认**：

- 每次联络最多一条设备命令、一个目标设备，只能修改已有摄像头或已有机器人；不再保留“一台摄像头加一台机器人”的双命令额度。
- 一个摄像头命令可包含多个获准扫描字段；机器人一次命令为一条完整 SetPatrolPath。
- 未使用名额不转存、不转让；KEEP_CURRENT 是结束会话选择，不算设备命令。
- 玩家确认不可变的完整命令，程序核对确认内容与实际提交内容完全一致；确认后 Agent 不能替换。
- 修改方案必须生成新批次和新 request_id；任一非法则整批不提交，不自动 KEEP_CURRENT。
- 进入联络成功仍按既有规则消耗该点会话，非法命令不返还联络点。
- 助手的安全 REJECTED、重试和真实异常 UI 在后续助手 Spec 中落实，不扩大模块 5。

### 0.9 仍需 Plan 落实但不构成玩法阻塞的事项

- 设备总量、定位矩形、上报节奏、禁区半径和障碍灰盒模板均注入 fixture；`max_dispatch_attempts=2` 也只是原型值。
- 新 Plan 必须重新核对 LevelTemplate、WorldState、DeviceRegistry、WorldCommandBatch/Service、场景同步和 4A/4B 查询接缝，列出摄像头迁移、障碍实例、公开状态及快照的精确文件与签名。
- 实施前同步总设计 Spec、机制基准和最小框架 Spec：系统权限、独立摄像头、多格障碍、助手机器人权限、公开世界状态和非法调度重试均已改变旧合同。
- 新验收需覆盖整房子移动后的素材稳定、footprint 碰撞/遮挡、共格矩阵、禁区防探测、拒绝后新 request、两次尝试耗尽 stop、模型异常 stop及全部旧回归。
- 当前批准状态仍为 NOT APPROVED；下一步只是重写 Plan，不是 Execute。

## P. 当前实施 Plan（2026-11-28；后续已获 Plan Approved）

### P0. Research 核对、基线与执行边界

- 工作树起点：`team/branch-1` 上 `docs/features/2026-11-27_20-53_module-2-world-command.md`、`docs/features/README.md` 已修改，模块 5 本文件未跟踪。本轮保留这些内容，不执行 clean/reset/rebase、提交或推送。
- 已读 `AGENTS.md`、SDD/RIPER 与 hackathon 技能、总设计／机制／框架文档、模块 2/3A/3B/4A/4B Spec，并逐一核对所列世界、场景、感知、会话、协议、主场景及测试入口。`WorldState` 当前只有 FLOOR/WALL `terrain` 和设备注册表；摄像头定义/校验/报告 sidecar 仍含 `mount_type/wall_side`；`SystemAgentView` 仅静态地图、设备配置、报告和固定空历史；`WorldCommandService` 未有障碍实例与设备总量校验；`GameRuntime` 仅完成运动、交互、感知和报告发布，Main 使用超大猜测周期 fixture，没有 AgentGateway。
- 2026-11-28 本轮基线：Godot `4.7.2.stable.official.ed1daf0bf` headless import 退出 0；共享 runner：SessionKernel 81、WorldCommand 229、RuntimeMotion 47、RuntimeScene 344、SensingRuntime 129，共 **830 passed / 0 failed**；4A 独立 runner：SensingGeometry 26、SensingKernel 88，共 **114 passed / 0 failed**。导入日志 `tmp/module5-plan-import.log`；最终顺序重跑且使用独立 engine log，`tmp/module5-plan-shared-clean.log`、`tmp/module5-plan-4a-clean.log` 均退出 0、无日志文件争用。此前并行 runner 的默认日志轮转出现文件占用噪声，不影响断言。§P6 的最终验收仍须在实施后重新运行。
- 文档阶段检查：Python unittest 13/13；仓库检查 1186 files / 34 maintained documents / 0 issues；项目链接检查 73 documents / 0 broken；`git -c core.whitespace=cr-at-eol diff --check` 退出 0。日志分别在 `tmp/module5-plan-python.log`、`tmp/module5-plan-repository.log`、`tmp/module5-plan-links.log`。这些只证明当前文档与旧代码基线，不替代实施后验收。
- 本轮检查期间工作树另出现 `docs/features/2026-11-28_module-7-player-contact.md`、`game/scripts/agents/player_assistant_contract.gd`、`game/scripts/agents/simulated_player_assistant.gd` 等其它会话未跟踪文件。本轮未读取、修改或清理；实施前重新检查 status 和交叉接口，若与模块 5 计划冲突先回 Plan。
- 总设计 `PRELIMINARY_DESIGN_SPEC.md`、机制基准 `侦测定位_机制草案.md`、`docs/minimal-framework-spec.md` 已新增明确模块 5 迁移章节。模块 2–4B 的原测试数字和完成声明是历史证据，不因新合同改写。Innovate 不再另起方案：§0 已完成关键架构取舍（单锚摄像头、稳定障碍实例、公开白名单、有限调度重试）。
- 本任务为两个依序检查点：**W 世界模型与公开视图迁移**、**C 系统 Agent 猜测周期与调度**。每个检查点先写失败合同测试，再实现，再运行其目标测试；全部完成后进入 Review。无用户后续单独精确回复批准文本，不进入 W 的代码步骤。

### P1. 数据 Schema 与不可变边界

以下为 plain Dictionary/Array 的精确字段合同；内部 Godot 对象只通过显式转换产生 DTO，未知字段拒绝。所有格坐标为 `[x:int,y:int]`，非负且受地图界限；ID 为正整数，角度和连续位置为有限数。

| 数据 | 精确字段与语义 |
| --- | --- |
| `ObstacleTemplate` | `{template_id:String, footprint:Array[Array[int,int]], blocks_movement:bool, blocks_vision:bool, scene_path:String}`；footprint 非空、含 `[0,0]`、offset 唯一且非负；固定 `scene_path` 指向项目内 PackedScene，作为整个实例的素材，不由全局邻接重拼。首版原型模板均同时阻挡移动和视觉；类型字段仍分别保存。 |
| `ObstacleInstance` | `{obstacle_id:int, template_id:String, anchor_cell:[int,int]}`；不含 orientation。`LevelTemplate` 有 `obstacle_templates` 与 `initial_obstacles`，按稳定顺序分配 ID；`WorldState` snapshot schema 升为 2，含同名模板／实例数组、`next_obstacle_id`，并保留现有 world/device revision 与实体高水位。实例覆盖格只由模板 offset 加锚点派生，不能逐格持久化。 |
| 摄像头实体 | `{id,kind="camera",cell,parameters,runtime_state:{heading:number,scan_direction:-1|1}}`；删去 `mount_type/wall_side`。`parameters` 维持现有六字段及 `enabled`；`heading` 必须在扫描区间，`scan_direction` 是当前相位。摄像头锚格唯一，非实心。 |
| 机器人实体 | 维持 `{id,kind="robot",parameters,patrol_path,runtime_state:{position,path_index,progress,travel_direction,transition}}`；公开当前连续 `position` 与从真实位置换算的 `cell`。新增机器人的 `patrol_path[0] == birth_cell`，并符合现有四邻接、驻守、折返和 transition 规则。 |
| 公开世界 `PublicWorld` | `{grid_size,cell_size,origin,terrain,obstacle_templates,obstacle_instances,cameras,robots,fixed_entities,world_revision,device_counts,dispatch_rules}`。`obstacle_templates` 只投影 ID、footprint 和两个阻挡标志，不含 `scene_path`；实例只含三字段；摄像头仅 ID/格/参数/heading/scan_direction；机器人仅 ID/position/cell/path_index/progress/travel_direction/transition/patrol_path/获准公开参数；固定设施仅 kind/id/cell；`device_counts` 恰为 camera/robot/pressure_plate。显式组装，禁止从 WorldState 黑名单删减。 |
| 系统请求 | `{context,request_type,view,as_of,constraints}` 猜测；`{context,request_type,view,as_of,policy,previous_rejection}` 调度。`context` 恰为 protocol_version/role/request_id/round_id/branch_id/guess_cycle_id；`view={world:PublicWorld,reports:Array,history:Array}`，只含已经发布的统一报告；`as_of={simulation_tick,report_period_id}` 与猜测冻结边界一致。`previous_rejection` 首次为 null，重试为安全回执。 |
| 系统响应 | `{context,status:"ok",payload}`；猜测 `payload={shape:"rectangle",origin_cell:[x,y],size:[w,h]}`；调度 `payload={mode:"APPLY"|"KEEP_CURRENT",commands:Array}`。不接受 Agent 的 hit/phase/success/source/revision 等字段。`[x,x+w)×[y,y+h)` 必须在地图内且满足原型 `max_width/max_height/max_cells`。 |
| 调度命令 | 沿用严格 `AddDevice/RemoveDevice/MoveDevice/SetDeviceParameter/SetPatrolPath` 形状，并新增 `{type:"SetCameraScanState",id:int,heading:number,scan_direction:-1|1}` 与 `{type:"MoveObstacle",obstacle_id:int,anchor_cell:[x,y]}`。前者以一条命令原子设置扫描相位；后者只能移动已有实例。`MoveDevice` 不再接受安装字段；系统禁止 `SetMapCell`、障碍增删和任何直接机器人运动字段。 |
| 安全拒绝回执 | `{status:"REJECTED",context:原请求身份,errors:[{code:String,command_index:int}]}`；对隐藏演员占位／禁区统一 `PLACEMENT_REJECTED`，不含坐标、禁区中心、内部 world snapshot、建议合法位置。`command_index=-1` 仅批级拒绝。完整内部 `WorldCommandResult` 不直接向 Agent 序列化。 |
| 调度历史 | 猜测 `{kind:"guess",context,as_of,origin_cell,size,verdict:"HIT"|"MISS"}`；调度 `{kind:"dispatch",context,mode,commands,status:"APPLIED"|"UNCHANGED"|"REJECTED",revision_before,revision_after,errors}`。只写安全命令和回执；不写玩家位置、禁区中心或完整 WorldFrame。历史持久对象独立于 4B 当前有效 reports 的快照，模块 6 不能一并回滚。 |
| 新增快照状态 | `SessionState.snapshot()` 增 `active_request_type`、`dispatch_attempts`、`last_dispatch_rejection`，冻结 `WorldFrame.snapshot()` 增 `world_revision`；`GameRuntime.get_agent_snapshot()` 为 `{fault, pending_context, pending_request_type, pending_sent, history}` 的深拷贝，历史源于独立 `SystemAgentHistory.snapshot()`。`WorldState` 保存模板／实例／ID 高水位；4B snapshot 保存事件时新 sidecar。周期起点应没有 pending 请求或冻结帧；模块 6 才实现跨组件 restore 与新 branch 生成。 |

原型配置集中放 `PrototypeConfig`：12×8 灰盒、固定 2×2 房子模板、受限矩形、每种设备上限、显式合法格集合、正方形障碍额外保护半径、`max_dispatch_attempts=2`、有限上报批数。数值仅为可替换 fixture。服务 policy 单独校验合法区域、命令类型、每批命令数和最终设备总量；助手未来 policy 先限一条现有设备命令，不接 UI。猜测冻结玩家格只存于可信会话／程序路径，不进入 `PublicWorld`、history 或回执。现有 `validate_batch()` 不得变成 Agent 任意坐标预检入口；玩家真实占位与额外禁区只在 `commit_batch()` 的正式候选提交中检查。不得通过调用公开 validate 反复试探隐藏位置。

### P2. 精确 File Changes（获批后按 W → C）

| 检查点 | 文件 | 变更 |
| --- | --- | --- |
| W | `game/scripts/world/obstacle_template.gd`、`obstacle_instance.gd` | 新增严格 plain DTO、footprint 派生与深拷贝。 |
| W | `game/scripts/world/level_template.gd`、`world_state.gd`、`device_registry.gd` | 模板实例化、schema 2 快照／恢复、空间查询、共格和机器人实际占位校验；移除摄像头安装字段。保留旧 `SetMapCell` 内部能力但系统 policy 禁用。 |
| W | `game/scripts/world/world_command_batch.gd`、`world_command_service.gd`、`world_command_result.gd` | 新命令形状与角色 policy；候选中整块移动、设备最终上限、玩家禁区与隐藏占位安全映射；可信 revision/phase 错误分类。 |
| W | `game/scripts/runtime/runtime_world_view.gd`、`scene_world_sync_adapter.gd`、`device_view.gd`、`robot_controller.gd` | 根据新覆盖格同步碰撞、障碍场景、演员／设备节点；准备阶段使用 candidate 世界，activate 后 view 只持有已提交世界。 |
| W | `game/scripts/runtime/obstacle_view.gd`、`game/scenes/runtime/obstacle_view.tscn`、`game/assets/graybox/house_2x2.svg` | 新增单一固定 PackedScene/整图素材，ID 节点与完整 footprint 碰撞；移动时整场景平移，不重拼 tile。 |
| W | `game/scripts/sensing/vision_geometry.gd`、`sensing_kernel.gd`、`game/scripts/runtime/runtime_sensing_coordinator.gd`、`game/scripts/reports/unified_report_batch.gd` | 覆盖格遮挡、运动前后演员格、事件时摄像头 heading/scan_direction sidecar 校验与快照；不改变 4A R/P/tick 语义。 |
| W | `game/scripts/agents/system_agent_view.gd`、`agent_protocol.gd` | 公开世界显式白名单和严格视图验证；请求 DTO 基础，报告与当前世界分层。 |
| W | `game/scripts/runtime/prototype_config.gd` | 更新摄像头和障碍原型 fixture、设备规则、公开 policy 与上限。 |
| C | `game/scripts/core/world_frame.gd`、`session_state.gd`、`game_session.gd` | 冻结世界 revision、request_type、调度尝试数／最后拒绝的会话快照；成功/拒绝/耗尽阶段入口，不在失败时推进 cycle。 |
| C | `game/scripts/agents/system_agent_history.gd`、`simulated_system_agent.gd`、`simulated_agent_gateway.gd` | 独立持久安全历史、确定性脚本 Agent、无网络/真实计时的 deferred/timeout/断线测试网关。 |
| C | `game/scripts/agents/agent_protocol.gd`、`system_agent_view.gd`、`game/scripts/runtime/game_runtime.gd`、`game/scripts/main.gd` | 严格 request/response DTO、报告发布后请求、回调复核、冻结 hit、真实命令提交、有限重试、故障锁、主场景单周期日志与停点。 |
| W/C | `game/tests/world_command_tests.gd`、`runtime_motion_tests.gd`、`runtime_scene_tests.gd`、`sensing_runtime_tests.gd`、`session_kernel_tests.gd` | 先加入失败的迁移合同用例，调整被新 schema 取代的旧 fixture，保留原行为回归。 |
| W/C | `game/tests/module5_world_tests.gd`、`game/tests/module5_cycle_tests.gd`、`game/tests/run_tests.gd` | 新独立场景／协议验收，接入共享 runner。`game/tests/run_sensing_tests.gd` 只运行验证，不改其独立入口。 |
| Review | `game/README.md`、本 Feature Spec | 回写真实命令、日志、Plan-Execution Diff、三轴 Review Matrix、剩余限制和模块 6 恢复边界。 |

不改旧模块 Feature Spec 的验证记录，不新增正式地图、美术流程、网络接入、玩家助手聊天／确认、完整 RESET、四轮结算或真实计时器。若实现发现必须触碰此表外游戏逻辑文件，先回 Research/Plan 增补并重新提交审批。

### P3. 公开 Signatures（获批后的目标接口）

```gdscript
# 世界值与校验
static func ObstacleTemplate.from_data(data: Dictionary) -> ObstacleTemplate
func ObstacleTemplate.to_data() -> Dictionary
func ObstacleTemplate.covered_cells(anchor_cell: Vector2i) -> Array[Vector2i]
static func ObstacleInstance.from_data(data: Dictionary) -> ObstacleInstance
func ObstacleInstance.to_data() -> Dictionary
func LevelTemplate.instantiate_world() -> WorldState
func WorldState.get_cell_profile(cell: Vector2i) -> Dictionary
func WorldState.obstacle_cells(obstacle_id: int) -> Array[Vector2i]
func WorldState.to_snapshot() -> Dictionary
static func WorldState.from_snapshot(data: Dictionary) -> WorldState
func WorldState.validate() -> Array[Dictionary]
static func DeviceRegistry.definition_valid(data: Variant, rules: Dictionary) -> bool
static func DeviceRegistry.entity_valid(entity: Variant, rules: Dictionary) -> bool
static func WorldCommandBatch.command_valid(command: Variant) -> bool
func WorldCommandService.commit_batch(batch: WorldCommandBatch, expected_context: Dictionary) -> WorldCommandResult
func WorldCommandService.validate_batch(batch: WorldCommandBatch, expected_context: Dictionary) -> WorldCommandResult
func WorldCommandResult.safe_dispatch_receipt() -> Dictionary

# 场景、感知与公开状态
func RuntimeWorldView.make_entity_node(entity: Dictionary, candidate: WorldState) -> Node2D
func RuntimeWorldView.make_obstacle_node(instance: Dictionary, candidate: WorldState) -> Node2D
func RuntimeWorldView.replace_obstacle(obstacle_id: int, node: Node2D) -> void
func RuntimeWorldView.remove_obstacle(obstacle_id: int) -> void
func RuntimeWorldView.accept_committed_world(world: WorldState) -> void
func SceneWorldSyncAdapter.prepare(previous: Dictionary, candidate: Dictionary, changes: Dictionary) -> Dictionary
func SceneWorldSyncAdapter.activate(prepared: Dictionary) -> bool
func ObstacleView.configure(instance: Dictionary, template: Dictionary, world: WorldState) -> bool
static func SystemAgentView.public_world(world: WorldState, dispatch_rules: Dictionary) -> Dictionary
func SystemAgentView.initialize(world: WorldState, dispatch_rules: Dictionary) -> bool
func SystemAgentView.update_configuration(committed_world: WorldState) -> bool
func SystemAgentView.snapshot() -> Dictionary
func RuntimeSensingCoordinator.update_system_view(boundary: ReportBoundary, committed_world: WorldState) -> bool
func RuntimeSensingCoordinator.snapshot() -> Dictionary
static func UnifiedReportBatch.public_device_configuration_valid(value: Variant, entity_id: int, record_type: String = "") -> bool

# 严格协议、历史、会话与运行时
static func AgentProtocol.make_location_request(context: Dictionary, view: Dictionary, as_of: Dictionary, constraints: Dictionary) -> Dictionary
static func AgentProtocol.make_dispatch_request(context: Dictionary, view: Dictionary, as_of: Dictionary, policy: Dictionary, previous_rejection: Variant) -> Dictionary
static func AgentProtocol.parse_location_response(raw: Variant, expected_context: Dictionary, constraints: Dictionary, grid_size: Vector2i) -> Dictionary
static func AgentProtocol.parse_dispatch_response(raw: Variant, expected_context: Dictionary) -> Dictionary
func SystemAgentHistory.append_guess(entry: Dictionary) -> bool
func SystemAgentHistory.append_dispatch(entry: Dictionary) -> bool
func SystemAgentHistory.snapshot() -> Dictionary
func SimulatedSystemAgent.respond(request: Dictionary, script: Dictionary) -> Variant
func SimulatedAgentGateway.submit(request: Dictionary, completion: Callable) -> bool
func SimulatedAgentGateway.complete_pending(result: Variant) -> bool
func GameSession.note_dispatch_rejection(context: Dictionary, receipt: Dictionary, max_attempts: int) -> Dictionary
func GameSession.get_state_snapshot() -> Dictionary
func GameRuntime.configure_agent(gateway: SimulatedAgentGateway, history: SystemAgentHistory, agent_rules: Dictionary) -> bool
func GameRuntime.pump_agent() -> Dictionary
func GameRuntime.on_agent_result(sent_context: Dictionary, request_type: String, result: Variant) -> void
func GameRuntime.get_agent_snapshot() -> Dictionary
```

`parse_*` 返回 `{ok:bool,payload:Dictionary,error:String}`；失败不改变任何状态。Gateway completion 传内部 `{kind:"response"|"timeout"|"disconnected"|"empty",raw:Variant}`，不是 Agent 有权提供的结果字段。`pump_agent()` 同一活动 request_id/type 仅提交一次，迟到 completion 先按发送时身份与当前活动请求比对：已失效的旧请求静默丢弃；当前请求返回错误身份或 DTO 则 STOP。`note_dispatch_rejection()` 仅接受当前 DISPATCH 请求和安全回执，返回 `{retry:bool,exhausted:bool,new_context:Dictionary}`，耗尽时 runtime fault；不会自行提交 KEEP 或推进 cycle。上述公开函数及所有新增 GDScript 公共函数均写明参数和返回类型。

### P4. 原子 Checklist（批准后依序执行；未执行项保持空）

- [x] **W1 测试先行**：写 schema 2 快照、旧安装字段拒绝、障碍稳定 ID/footprint/共格及摄像头无墙安装的失败合同测试。
- [x] **W2 世界值**：实现模板／实例 DTO、LevelTemplate 实例化和 WorldState 覆盖格查询；校验无旋转、无拆分、出界、冲突与路径失效；旧 snapshot schema 迁移测试明确拒绝或受控升级，不能静默误读。
- [x] **W3 场景与感知测试先行**：写整屋平移前后图像局部顺序、完整 footprint 物理碰撞及 supercover 遮挡、摄像头／踏板／演员共格和事件时 sidecar 的失败测试。
- [x] **W4 场景与感知实现**：固定 2×2 PackedScene 和完整碰撞、候选 prepare/activate、视觉覆盖格与 sidecar；调度后旧报告字节等价，快照可恢复新字段。
- [x] **W5 命令测试先行**：写摄像头／机器人／踏板／障碍权限、上限、合法区域、机器人不重叠及连续换路、保护区、整块拒绝、revision/SceneSync 原子性的失败合同测试。
- [x] **W6 命令实现**：经 WorldCommandService 实现系统角色 policy 与新命令；障碍任何覆盖格非法全拒绝，隐藏演员／禁区只在正式 `commit_batch` 检查并只给安全码，`validate_batch` 不形成坐标探针；`SetMapCell` 不授予系统；助手基础 policy 仅作独立校验 fixture。
- [x] **W7 公开视图测试先行**：写白名单、当前地形／障碍、扫描相位、机器人全运动锚点、固定设施、revision/count/rules、深拷贝及禁字段反例。
- [x] **W8 公开视图实现**：同步 SystemAgentView/AgentProtocol/4B 配置；保留事件时 R/P/tick/heading/direction，禁止用部署后世界改历史。
- [x] **W9 W 验收**：运行 W 用例、共享与 4A 旧回归；真实灰盒整屋移动，核对贴图、碰撞、遮挡及 SceneWorldSyncAdapter 原子提交。
- [x] **C1 测试先行**：严格请求／响应 DTO、受限矩形和完整 round/branch/cycle/request/type 反例；冻结帧 hit、猜测优先及报告 fault 零调用的失败用例。
- [x] **C2 协议与会话**：实现严格 parser、WorldFrame revision、SessionState 新字段／快照、猜测判定与 phase 门控；程序独立算 hit，不读取 Agent 自报结论。
- [x] **C3 测试先行**：首次世界 REJECTED→安全回执→旧 ID 失效→新请求修正成功，以及第二次拒绝耗尽 STOP；验证 world/revision/report/tick 不变、历史有原身份；再写异常／迟到/SceneSync 故障用例。
- [x] **C4 Gateway/历史/Runtime**：实现脚本 Agent、测试网关、独立历史、单在途泵、正式 WorldCommandService/SceneSync 提交、有限重试和 fault 锁；所有回调先验 fault、phase、request_type、完整身份。
- [x] **C5 主场景单周期**：把超大周期 fixture 改为有限原型 N 和批数；真实灰盒走完整发布→一次猜测→hit/成功/miss 调度分叉，调度成功停 `CYCLE_START_PENDING`，不调用 `resume_cycle(true)`。
- [x] **C6 验证与 Review**：执行 §P6 全命令，逐项记录证据；按 Spec 完成度、Spec-代码一致性、代码本身质量写 Review Matrix、Plan-Execution Diff、剩余限制到本 Spec 与 `game/README.md`。

### P5. 可观察验收场景

| 场景 | 可观察结果 |
| --- | --- |
| W-01 无墙摄像头与共格 | 无支撑墙的合法 FLOOR 可安一台；同锚第二台失败；摄像头与踏板／玩家／机器人共格成功，与实心障碍／固定设施冲突失败。摄像头对演员无物理阻挡。 |
| W-02 整房移动 | 2×2 房子 ID 与固定纹理局部位置不变；四格碰撞和视觉遮挡随 anchor 平移；任一目标格越界、压演员／设备／固定设施、破坏机器人路线或落保护区则四格均不改变、revision 不增长。允许切断玩家路线。 |
| W-03 公开边界 | 猜测视图含§P1全部白名单字段，扫描相位与机器人连续状态为真实暂停值；无禁字段／scene_path／高水位；修改 DTO 深拷贝不改世界。部署后历史视觉 R/P/tick/配置/heading/direction 不变。 |
| W-04 保护区防探测 | 玩家同格更换隐藏位置时，障碍禁区和真实重叠拒绝均只暴露 `PLACEMENT_REJECTED`；摄像头不因额外半径拒绝，机器人只以真实重叠判断；没有坐标预检入口。 |
| C-01 报告后猜测 | 完整统一批发布前 Gateway 0 次；发布后同身份只调用一次；合法矩形程序以冻结帧 hit→RESET_CHOICE；冻结通关且 miss→ROUND_END/SUCCESS；普通 miss→DISPATCH_PAUSED。 |
| C-02 正常调度 | miss 后取得不同 request_id；摄像头/机器人/踏板/MoveObstacle 中各有真实服务及 SceneSync 成功例；revision 每次实际变化只加 1，最终停 CYCLE_START_PENDING，无伪快照。显式 KEEP 为 UNCHANGED。 |
| C-03 两次拒绝 | 第一次合法 DTO 的世界拒绝返回安全 code/index，历史记录旧身份；新 request 携前回执，旧响应失效；修正可成功，或第二次拒绝后 STOP，tick/report/world/revision 均未被拒绝改变。 |
| C-04 异常与并发 | 空／畸形／超时／断线、未知动作、错误当前身份、非法定位、自报 hit/success/phase、内部 revision 或 SceneSync activate 故障均 STOP；旧请求迟到丢弃；fault 后 Agent 调用 0 次，后续回调不能转阶段。 |
| C-05 快照边界 | 新障碍／扫描／机器人、session 尝试数与冻结帧、4B sidecar、独立历史均能输出深快照；模块 6 所需恢复顺序写明，但本模块没有实际 RESET。 |

### P6. Validation Plan、日志与回炉条件

1. **W 和 C 每次实现前**先运行相应新增失败合同测试，日志写 `tmp/module5-red-*.log`，确认失败指向尚未实现的合同；实现后运行对应用例及相关旧测试。旧断言因 schema 更新调整时，记录每项被替换的预期，不能删掉覆盖范围。
2. **最终顺序运行** Godot 4.7.2 `--headless --path game --import`；`--script res://tests/run_tests.gd`（共享＋新增）；`--script res://tests/run_sensing_tests.gd`（4A 独立）；共享 runner `-- --fail-probe` 确认退出非零。各项单独日志放 `tmp/module5-*.log`，记录退出码、套件明细和异常行。
3. 用真实 `RuntimeWorldView`、`WorldCommandService`、`SceneWorldSyncAdapter` 运行灰盒单猜测周期及组合障碍整体移动；检查固定材质局部像素/节点变换、全部 footprint 碰撞、遮挡和移动失败无部分同步。主场景 120 帧 headless smoke 及 Windows release 导出程序 smoke；检查明确停点标记和故障输出。
4. 执行 `python -m unittest discover -s tests -v`、`python scripts/check_repository.py`、`python scripts/check_project_links.py --all`、`git -c core.whitespace=cr-at-eol diff --check`。仅全部相关命令退出码正确且验收场景有证据，才考虑 Review PASS；不复用本次 830/114 基线数字作为完成证据。
5. 若发现 §0 与实现接口冲突、需要新的角色权限或世界命令、超出 §P2 文件范围、灰盒不能保证整房稳定素材、拒绝泄漏隐藏位置、无法隔离持久历史与有效报告、SceneSync 无法原子准备，立即停在对应 checkpoint，先修订 Spec/Plan 并重新求批准，不自行扩张 Execute。

### P7. 审批与 Resume 锚点

计划提交时为 `PLAN COMPLETE / NOT APPROVED / LOCKED`；后续批准与当前执行位置见 §P8。按 W1→C6 依序 Execute，无需每个检查点重复等待，但任何 §P6 回炉条件触发即停。模块 6 承接完整周期快照保存/恢复、branch 更新、持久历史与有效报告分离及 RESET；模块 5 只提供可恢复字段和 `CYCLE_START_PENDING` 停点。

### P8. Execute checkpoint（2026-11-28）

用户后续消息包含精确批准文本并要求开始开发，故进入 W1。执行前 `git status` 发现模块 7 另有未提交的设备选择 UI 改动：`runtime_world_view.gd` 新增摄像头标记/点击方法，`device_view.gd` 与 `device_view.tscn` 新增 Selection 节点；另有模块 7 独立文件。本模块在相关文件上只做增量编辑，保留上述接口与节点。已检查现有变更不改变 §P 计划的世界模型、场景同步签名或角色边界；每次相关编辑前复核工作树，若出现实际接口冲突则按 §P6 停止回 Plan。

### P9. Execute、Validation 与 Review（2026-11-28）

**实际实施。** 完成 W1–W9、C1–C5：新增稳定 `ObstacleTemplate`／`ObstacleInstance` 与 schema 2 世界快照，迁移无墙摄像头、固定 2×2 房屋场景／完整 footprint 物理和视觉阻挡、事件时扫描相位 sidecar；系统命令采用明确角色 policy、总量上限、合法区域、原子候选和安全保护区回执；公开世界由显式白名单构造。严格协议、冻结帧 hit、单在途模拟 Gateway、独立历史、最多两次调度提交及 STOP 门控已接入 GameRuntime。主场景的原型 fixture 为 30 tick／2 报告批，合法调度停 `CYCLE_START_PENDING`。新增测试在实现前运行并留下 `tmp/module5-red-*.log`；旧模块摄像头安装、快照和报告 fixture 仅迁移已废止的墙挂字段与 schema 预期，未改写其历史验证记录。

**最终验证命令与证据。** 在仓库根目录用 Godot `4.7.2.stable.official.ed1daf0bf` 运行：

| 验证 | 结果 | 日志／产物 |
| --- | --- | --- |
| `Godot --headless --path game --import` | exit 0，无解析错误 | `tmp/module5-review-import.log` |
| `Godot --headless --path game --script res://tests/run_tests.gd` | exit 0，**920 passed / 0 failed**：Session 81、World 226、Motion 47、Scene 344、SensingRuntime 130、Module5World 12、Module5Cycle 12、并行模块 7 Assistant 14／Contact 54 | `tmp/module5-review-shared.log` |
| `Godot --headless --path game --script res://tests/run_sensing_tests.gd` | exit 0，4A Geometry 26＋Kernel 88＝**114 passed / 0 failed** | `tmp/module5-review-4a.log` |
| 共享 runner 加 `-- --fail-probe` | **exit 1，符合失败门禁预期** | `tmp/module5-review-fail-probe.log` |
| 主场景 `--headless --quit-after 120` | exit 0；`RUNTIME_AGENT_READY`、`MODULE5_CYCLE_START_PENDING` | `tmp/module5-review-main.log` |
| `--export-release "Windows Desktop" ../tmp/module5-review-windows.exe`，再以 `--headless --quit-after 120` 运行 | 导出和程序均 exit 0；程序同样输出两个标记；EXE 109,127,680 字节 | `tmp/module5-review-export.log`、`tmp/module5-review-windows-engine.log` |
| `python -m unittest discover -s tests -v` | exit 0，13/13 | `tmp/module5-review-python.log` |
| `python scripts/check_repository.py`；`python scripts/check_project_links.py --all` | 均 exit 0；0 issues／0 broken | `tmp/module5-review-repository.log`、`tmp/module5-review-links.log` |
| `git -c core.whitespace=cr-at-eol diff --check` | exit 0；仅现有 CRLF 正规化提示 | `tmp/module5-review-diff-check.log` |

**可观察场景。** `Module5WorldTests` 用真实 `RuntimeWorldView`／`WorldCommandService`／`SceneWorldSyncAdapter` 提交摄像头、机器人、踏板与整屋移动；验证房屋保持同一预合成 Sprite 纹理、anchor 平移、四格物理命中与 supercover 遮挡；非法 footprint 移动的世界快照、场景位置和 revision 不变。保护区测试区分摄像头、机器人和实体障碍，并检验正式回执不泄露玩家格。`Module5CycleTests` 验证完整报告发布后的单次请求、冻结帧命中／通关／普通 miss 分流、第一次安全拒绝后的新 request_id 与修正成功、第二次拒绝耗尽 STOP、旧回调失效、空回复／断线／超时／身份和协议错误 STOP、报告 fault 时 Agent 0 次调用、SceneSync activate 故障 STOP。测试日志中注入故障的 `GAME RUNTIME FAULT` 行属于预期断言；最终主场景和 Windows smoke 无故障。

**Plan-Execution Diff。** 旧版 §A 的踏板-only 调度与立即 fault 方案未执行。§P 中的 W/C 顺序和角色边界保持；实际实现增加了 schema 2 旧快照显式拒绝和 `SystemAgentView` 历史正尺寸校验，属于既定严格 DTO／迁移合同。旧 WorldCommand 套件将依赖墙挂／支撑墙的断言换成无墙安装和拒绝旧字段，单套件 229→226；新增 Module5 套件 24 项，另有并行模块 7 测试 68 项，最终共享总数 830→920。工作树中的模块 7 联络 UI／助手文件由其它会话维护，本模块只在共享运行时／场景视图保留其接口并补充兼容；模块 5 的角色数据流没有向助手开放系统视图或报告。

**Review Matrix。**

| 轴 | 结论 | 证据与边界 |
| --- | --- | --- |
| Spec 完成度 | PASS | §0 A–E 的世界、公开视图、调度、保护区、单周期和有限重试均有对应代码与灰盒断言；§0 F 明确留给后续模块。 |
| Spec—代码一致性 | PASS | 命令经过真实服务与 SceneSync，回调先核 fault／phase／type／完整身份；Agent 不提供 hit；安全拒绝不改变 world、tick、报告或 revision；旧版 §A 未被用作实施合同。 |
| 代码本身质量 | PASS（原型范围） | Godot import、920/920 共享、114/114 独立、失败探针、双 smoke 与仓库检查通过；固定素材避免搬运后自动拼接，DTO 与快照边界有负例。真实模型、计时和跨进程恢复未做性能／端到端验证。 |

**剩余限制与模块 6 恢复边界。** 本地脚本 Agent 只用于确定性原型，不代表推理质量；未接网络、真实超时服务、完整局部 RESET／整轮重启／四轮结算、正式地图、美术和数值平衡。模块 6 应在同一周期起点成组保存／恢复 WorldState（含障碍和设备运行态）、SessionState／CycleState（含尝试数、revision、冻结帧身份）、RuntimeSensingCoordinator 的当前有效报告与事件时 sidecar、SceneSync 派生状态；持久猜测／调度历史不随局部回退回滚，旧 branch/request 回调失效。当前仅提供快照字段和停点，没有执行恢复。

### P10. 独立提交分支复核（2026-11-28）

为只提交模块 5，从模块 4B HEAD 建立 `feat/module5-simulated-agent-cycle` 独立工作树。将世界、感知、协议、会话、运行时、场景、测试与设计迁移文档的模块 5 改动移入；共享 `main.gd`、`game_runtime.gd`、`prototype_config.gd`、`runtime_world_view.gd` 和 runner 只保留模块 5 接线。原共享工作树中模块 6 草案、模块 7 玩家助手聊天／确认 UI、场景节点和测试留在原处，未进入本分支；原工作树未被清理或重置。§P9 的 920 项是原共享工作树验证证据，其中包含并行模块 7 的 68 项；独立分支须以本节结果作为提交门禁。

独立分支重新运行 Godot 4.7.2 `--import`：exit 0；共享 runner：Session 81、World 226、Motion 47、Scene 344、SensingRuntime 130、Module5World 12、Module5Cycle 12，共 **852 passed / 0 failed**、exit 0；4A 独立 26＋88＝**114 passed / 0 failed**、exit 0；失败探针 exit 1（符合预期）。主场景与 Windows release 导出程序各运行 120 帧，均 exit 0，均输出 `RUNTIME_AGENT_READY` 和 `MODULE5_CYCLE_START_PENDING`。Python unittest 13/13、exit 0。原工作区忽略目录中保存 `tmp/module5-publish-import.log`、`tmp/module5-publish-shared.log`、`tmp/module5-publish-4a.log`、`tmp/module5-publish-probe.log`、`tmp/module5-publish-main.log`、`tmp/module5-publish-export.log`、`tmp/module5-publish-windows-engine.log`、`tmp/module5-publish-python.log`。仓库检查、链接检查与暂存差异检查在提交前完成；任何失败均不得推送。

本次隔离不改变 §0 决策、公开 DTO、命令权限、拒绝重试或模块 6 恢复边界。Review Matrix 沿用 §P9 三轴结论，但以本分支 852/852 和 114/114 复测确认，避免把并行模块 7 的测试或文件误算进模块 5 提交。

## A. 旧版 Research / Plan（已被 §0 最新裁决取代）

以下旧文保留了早期踏板-only 方案、空 history 起点和所有非法调度即 fault 的取舍。凡与 §0 冲突，均以 §0 为准；旧 File Changes、Signatures 和 Checklist 不可直接执行。

## A1. 旧版 Open Questions

不阻塞本模块 Plan 的后置项：

- [ ] 正式玩法的定位形状、尺寸、每批命令额度、踏板总量上限和合法区域仍需试玩决定；模块 5 只注入可替换 fixture。
- [ ] 真实模型的墙钟超时、重试、断线恢复、玩家反馈和同局继续策略留给真实桥接模块；模块 5 只验证收到超时/空/非法/迟到结果时不会误结算。
- [ ] 模块 6 决定完整周期起点快照、局部 RESET、整轮重启、旧分支报告归档及持久 Agent 历史的恢复编排。
- [ ] 动态地形对系统 Agent 的可见时机仍按 4B 边界后置；模块 5 不开放地形命令。
- [ ] 玩家助手请求、聊天 UI 和联络工具接入留给模块 7；现有联络 KEEP_CURRENT 行为不扩展。

模块 5 自身没有必须再靠编码时临时决定的 DTO、命中或阶段问题。下列原型裁决随 Plan 一并待用户审查：受限轴对齐矩形、当前请求失败即终止本局、合法调度后停在 `CYCLE_START_PENDING`。

## 1. Goal、当前任务单元与 Done Contract

### Goal

在模块 4B 已封存的统一报告之上，用本地、确定性的模拟系统 Agent 和模拟 AgentGateway 跑通一个猜测周期：猜测刻暂停并构造合法请求，程序严格校验回复，程序按冻结 `WorldFrame` 判定命中，再按规则进入命中选择、通关或未命中后的单次合法调度。

### 当前最小任务单元

只覆盖**首次猜测及其直接后续分流**。未命中且本轮继续时，允许模拟系统 Agent 提交一次受策略限制的踏板调度；实际命令经 `WorldCommandService` 和真实场景同步提交。成功后停在 `CYCLE_START_PENDING`，等待模块 6 实现真实周期起点快照，不能用 `resume_cycle(true)` 伪造快照已经保存。

### Done Contract（后续验收目标，不是完成声明）

- 猜测请求只在完整统一报告发布后出现一次；请求包含正确身份、报告截止位置和受限定位规则，不含冻结真坐标。
- 模拟 Agent 只依据请求视图和测试脚本回应；不接收 `WorldState`、`WorldFrame` 或隐藏命中标签。
- 程序拒绝错误身份、越界、非矩形、超限、空、畸形、超时和迟到回复；任何这些结果都不会转成 `hit=false`。
- 合法回复不含命中声明；程序以冻结位置与冻结地图坐标变换计算 hit。
- 命中进入 `RESET_CHOICE`；未命中且冻结帧已满足通关条件进入 `ROUND_END/SUCCESS` 并跳过调度；其余未命中只进入一次 `DISPATCH_PAUSED`。
- 合法调度经现有唯一世界命令入口提交；非法调度不改变世界、不自动转为 KEEP_CURRENT。成功后进入 `CYCLE_START_PENDING`，模拟时钟仍冻结。
- 4B 报告 fault、世界同步 fault 或运行时 fault 后，所有系统 Agent 入口和迟到回调均无效。
- 新验收与既有共享/4A 独立套件均通过，实际证据回写本 Spec。

## 2. In Scope / Out of Scope

### In Scope

- 系统 Agent 的严格猜测与调度请求/响应 plain-data DTO。
- 本地模拟系统 Agent、单在途请求的模拟 AgentGateway，以及测试控制的 deferred/timeout/late 结果。
- `GameRuntime` 的猜测/调度编排、重入保护、身份与阶段复核、冻结帧 hit 计算和 fault 门控。
- 系统 Agent 已收到的成功猜测及调度回执的最小历史；4B 统一报告继续保留事件时身份。
- 系统调度对踏板 `AddDevice / RemoveDevice / MoveDevice` 的窄权限 fixture、每批命令上限、合法格集合和最终踏板总量上限。
- 纯 DTO/命中测试、真实运行时单周期测试、故障与过期回复测试及共享 runner 登记。

### Out of Scope

- 真实模型、DeepSeek、网络、API 密钥、线程、真实墙钟超时服务或复杂 Agent 框架。
- 完整局部 RESET、整轮重启、四轮结算、真实周期快照保存和恢复行动。
- 玩家助手聊天 UI、联络工具协议扩展或模块 7 的真实助手。
- 正式地图、美术、数值平衡、模型推理质量或命中率指标。
- 摄像头、机器人、墙体、固定目标/联络点/出口的新增系统 Agent 权限。
- 把非法、空、超时或旧回复转换成猜测未命中、默认定位或 KEEP_CURRENT。

## 3. Context Sources / Codemap / Context Snapshot

Requirement Sources：

- [现行设计 Spec](../../PRELIMINARY_DESIGN_SPEC.md) §3、§5、§7–8、§11。
- [机制基准](../../侦测定位_机制草案.md) §1、§3–5、§7。
- [最小框架 Spec](../minimal-framework-spec.md) §2–8，尤其检查点 5 与检查点 6 的边界。
- [模块 1](2026-11-27_14-22_module-1-rule-kernel.md)、[模块 2](2026-11-27_20-53_module-2-world-command.md)、[模块 3A](2026-11-27_22-25_module-3a-runtime-scene.md)、[模块 3B](2026-11-27_22-51_module-3b-interactions.md)、[模块 4A](2026-11-27_23-31_module-4a-sensing-kernel.md)、[模块 4B](2026-11-28_10-44_module-4b-runtime-sensing.md)。

Codemap Used：

- 复用 [工程入口图](../codemap/2026-11-27_14-14_game-project-map.md) 作为历史索引；它只覆盖模块 0–2，当前接口以实际代码为准。
- 本轮没有新建重复 codemap。按调用链直接核对 `GameRuntime → GameSession / RuntimeSensingCoordinator / WorldCommandService` 和 `SystemAgentView → AgentProtocol`。

Context Bundle Snapshot（Lite）：

- 统一报告、系统安全视图和真实运行时已经存在；严格 Agent payload、Gateway、hit 验证和真实调度编排不存在。
- 本轮没有另建 context bundle；14 份指定材料、模块 2 补充合同及实际代码构成研究输入。
- 工作树存在其他会话的未提交改动。本轮只新增本 Spec，不清理、不重置、不覆盖这些改动。

## 4. 当前代码事实与文档核对

### 4.1 已核实的执行链

1. `GameRuntime.step_once()` 在真实运动和 3B 交互后准备感知，依次提交 world、推进 session、发布感知，再处理统一报告边界（`game/scripts/runtime/game_runtime.gd:54-125`）。
2. `GameSession` 在猜测边界完成报告回调后进入 `GUESS_PAUSED`，保存冻结 `WorldFrame` 并登记系统 Agent 请求上下文（`game/scripts/core/game_session.gd:73-97`）。
3. `accept_guess_result(context, hit)` 已实现猜测优先：hit → `RESET_CHOICE`；miss + 冻结通关条件 → `ROUND_END/SUCCESS`；其他 miss → `DISPATCH_PAUSED`（`game_session.gd:134-150`）。它信任调用方已经验证 hit，本身不验证 Agent payload。
4. `complete_dispatch()` 只接受真实 `WorldCommandResult` 的 APPLIED/UNCHANGED，随后增加 `guess_cycle_id`、清零本周期已封批数并进入 `CYCLE_START_PENDING`（`game_session.gd:153-189`）。
5. `RuntimeSensingCoordinator` 先暂存封批和视图更新，`finish_report_boundary()` 成功后才发布；失败由 `GameRuntime` 进入终止性 fault。session 可能已经前进，因此新 Agent 入口必须另查 runtime fault，不能只看 phase。
6. `SystemAgentView` 当前含静态地图、公开设备配置和已封存统一报告；`history` 被严格限制为空数组。每条统一记录已有 round/branch/guess-cycle/report-cycle 和事件 tick，设备记录另有事件时公开配置 sidecar。
7. `WorldCommandService` 已校验完整 context、`source=contact/dispatch`、阶段、角色、base revision、命令白名单、参数和 allowed_cells，并经 prepare/activate 原子提交。`max_commands` 只限制单批；当前没有设备总量上限。未提供 `allowed_cells` 时通用服务语义是不限区域，因此模块 5 必须显式注入非空合法格集合。
8. 当前 `AgentProtocol.response_matches()` 只检查基础 envelope/status/context；现有测试甚至以空 `payload={}` 证明基础身份匹配。它不是合法定位回复校验器。`serialize_request()` 会投影允许字段，不能替代严格 DTO 的未知字段拒绝。
9. 当前主 fixture 使用 `SessionRules.new(30, 1000000)`，有意避免进入尚未实现的猜测流程；Main 的空调度策略也不能支持 APPLY。模块 5 接入时需改为明确的小型可触发 fixture，并注入窄权限策略。
10. 当前没有 `AgentGateway`、模拟系统 Agent 或猜测结果验证器文件；`game/README.md` 与模块 4B Spec 对此描述一致。

### 4.2 不一致判定

未发现所读现行文档与代码在“哪些能力已经实现”上的关键事实冲突。上述第 5、6、8、9 项是文档明确留下的接缝，不应误报成既有模块回归，也不能继续留到模块 5 编码时临时补决定。

### 4.3 本轮重新运行的基线

2026-11-28 本轮实际使用 Godot `4.7.2.stable.official.ed1daf0bf`：

- headless import 退出 0；日志 `tmp/module5-research-import.log`。
- 共享 runner：Session 81、World 229、Motion 47、Scene 344、SensingRuntime 129，合计 **830 passed / 0 failed**；日志 `tmp/module5-research-shared-tests.log`。
- 4A 独立 runner：Geometry 26、Kernel 88，合计 **114 passed / 0 failed**；日志 `tmp/module5-research-sensing-tests.log`。
- 日志中的预期故障文本对应既有故障注入测试；本研究没有新增游戏故障或修改测试。

## 5. Grill 裁决

### G1. 系统 Agent、玩家助手、Gateway 和程序的职责

| 角色/组件 | 本模块职责 | 明确不能做 |
| --- | --- | --- |
| 模拟系统 Agent | 从合法系统视图选择定位矩形；未命中后从公开调度策略选择踏板命令或显式 KEEP_CURRENT | 不读真坐标；不宣布 hit；不改 phase、报告、时钟、额度、revision 或规则 |
| 玩家助手 | 不在模块 5 接入；现有联络和 KEEP_CURRENT 保持不变 | 不共享系统请求，不获得系统报告或调度权限 |
| 模拟 AgentGateway | 把严格请求交给模拟 Agent；返回一次结构化完成结果；为测试提供 deferred 和模拟 timeout 通知 | 不直接调用 `accept_guess_result`、WorldCommandService 或场景节点；不把异常映射成 miss |
| GameRuntime / GameSession | 构造请求、门控入口、验证响应、计算 hit、转换阶段、重建可信命令 envelope、提交调度并记录历史 | 不把 Agent 自报 success/hit 当裁决；不在 fault 后继续调用 Agent |
| WorldCommandService | 重验调度身份、阶段、角色、额度、区域、空间和最终设备上限，准备并激活候选世界 | 不直接暴露给 Agent；不返回隐藏占位信息 |

### G2. 严格 DTO 与 AgentProtocol 收紧

保留现有六字段身份：

```text
protocol_version / role / request_id / round_id / branch_id / guess_cycle_id
```

所有 ID 为正整数，角色必须为 `system_agent`，协议版本必须完全匹配。内部 `expected_context` 可继续附带 phase 供服务校验，但线上请求和响应的 `context` 必须恰好只有六字段。

**猜测请求**恰好包含：

```text
context
request_type = "location_guess"
view = { static_map, device_configuration, reports, history }
as_of = { simulation_tick, report_period_id }
constraints = { shape = "rectangle", max_width, max_height, max_cells }
```

`as_of.simulation_tick` 是冻结猜测刻；`as_of.report_period_id` 是已经发布的最后统一批号。两者是输入快照身份，不是新时钟，也不允许 Agent 修改。

**猜测成功响应**恰好包含：

```text
context
status = "ok"
payload = { shape = "rectangle", origin_cell = [x,y], size = [width,height] }
```

**调度请求**恰好包含 `context / request_type="dispatch" / view / as_of / policy`。`policy` 是程序生成的安全公开策略投影：允许命令及类型、max_commands、allowed_cells、device_limits，不含内部缓存、隐藏占位或完整 WorldState。

**调度成功响应**恰好包含 `context / status="ok" / payload={mode,commands}`；`mode` 为 APPLY 或 KEEP_CURRENT，服从现有空命令规则。Agent 不提供 `source` 和 `base_world_revision`；程序用当前可信值重建 `WorldCommandBatch`。

收紧规则：

- 新系统请求/响应 DTO 对每一层执行精确字段集合、类型和值校验；未知字段、缺失字段、字符串数字、浮点格坐标和额外 `hit / success / phase / commands` 均拒绝。
- 新严格解析器不得像通用 serializer 一样静默丢弃未知字段。通用旧 builder 可保留给既有基础测试，但模块 5 运行路径不得依赖它证明 payload 合法。
- `response_matches()` 可继续作为基础 envelope 检查，但应收紧为精确三字段和精确响应 context；模块 5 还必须再经过操作专属 parser，不能仅凭它结算。
- Gateway 的 timeout/empty/malformed 是内部 `GatewayResult`，不是 `status="ok"` 的成功响应，也不进入猜测 payload parser 冒充合法定位。

### G3. 统一报告、事件时身份和历史

- 猜测请求直接消费 `RuntimeSensingCoordinator.get_system_view()` 的深拷贝，不读取 buffer、prepared 结果、冻结 WorldFrame 或完整 session snapshot。
- 入口必须验证视图最后一批存在，且 `report_period_id == as_of.report_period_id`、`end_tick == as_of.simulation_tick`，round/branch 与当前请求一致。猜测批的批头 guess_cycle_id 也必须对应当前猜测周期。
- 首版发送全部已发布当前有效 reports，而不是 delta，避免引入游标同步和缺包恢复。`as_of` 防止把旧视图当作新批已交付；后续输入规模优化不得改变原始事件。
- 不改写记录中的 `guess_cycle_id/report_cycle_id/event_tick`；边界 tick 属于下一批的 4A/4B 规则继续成立。历史 R、P、踏板位置和 sidecar 不按调度后的配置重算。
- 模块 5 将 `history` 从固定空数组扩展为严格白名单的成功动作历史：猜测记录保存原请求身份、as_of、所猜范围和程序 verdict；调度记录保存原请求身份、mode、commands、APPLIED/UNCHANGED 和 revision。不得写入冻结玩家格或连续坐标。
- miss 后的调度请求因此能看到刚才猜测及 MISS 结果；hit/miss 是程序事后授予系统的结果信息，不是 Agent 自报字段。
- 当前有效 reports 与持久 Agent 历史语义不同。模块 6 局部回退时恢复前者，但不得把后续猜测/调度历史一起回滚或伪装成当前观察；旧分支报告的归档仍由模块 6 完成。

### G4. 定位形状、大小和坐标

采用**轴对齐矩形、整数格、半开区间**作为模块 5 原型协议：

- `origin_cell=[x,y]` 是地图零基左上角；`size=[w,h]` 为正整数。
- 覆盖格为 `x <= px < x+w`、`y <= py < y+h`。矩形可包含墙格，因为它是位置范围而非可通行区域声明。
- `w <= max_width`、`h <= max_height`、`w*h <= max_cells`；constraints 自身也必须为正整数并可由当前地图容纳。
- 整个矩形必须位于地图内；越界一律拒绝，不裁剪、不取模、不夹入边界。边界检查先验证尺寸再用地图尺寸减去尺寸比较，避免加法溢出。
- 不接受任意格列表、多个矩形、负尺寸、零尺寸、浮点、重复格或全图默认范围。固定 5×5 不是本合同；测试和 Main 均从约束配置注入小值。

### G5. 冻结帧 hit 与非法/超时回复

- hit 的输入仅为已验证矩形、session 中冻结的 `WorldFrame` 和猜测刻已提交世界的只读坐标变换。
- 程序验证 frozen tick 等于当前 cycle tick，当前世界玩家位置仍与 frozen frame 一致；再以同一 `origin/cell_size` 执行 `world_to_cell(frozen.player_world_position)`。地图外玩家或世界/帧不一致是程序 fault，不是 miss。
- 玩家所在格位于矩形半开范围即 hit，否则 miss。不得使用 Agent 回复到达后的实时位置，也不得读取回复中的 hit。
- 当前请求的空、畸形、超时、身份错误、范围非法均进入明确 `AGENT_*` runtime fault，phase 保持原暂停状态，world/tick/report 不变。本模块没有无响应死循环，也没有自动 miss。
- 已经与当前活动回调 context 不符的旧 round/branch/cycle/request 结果按 stale/late 丢弃，不改变世界，也不产生新 fault；若此前 timeout 已使 runtime fault，fault 继续锁定所有回调。

### G6. 未命中后的调度

- 只有 `accept_guess_result()` 已确认 miss、冻结帧未通关、phase 为 `DISPATCH_PAUSED` 且 runtime 无 fault 时才构造调度请求。
- `GameSession` 已把活动请求换成新 request_id；猜测与调度不能使用同一请求身份。
- 模块 5 只开放踏板 Add/Remove/Move；固定设施、摄像头、机器人、地图和参数命令均由现有服务拒绝。
- `max_commands` 限制本批；`allowed_cells` 必须是显式非空 fixture 集合并约束 Add/Move 目标格；新增 `device_limits.pressure_plate` 在最终候选世界上限制踏板总数，Remove 不得绕过其它校验。
- 一次 miss 只可能进入一次调度暂停。正式 APPLY/KEEP_CURRENT 经 `session.complete_dispatch()` 提交；服务 REJECTED 时不离开暂停、不改世界，随后模块 5 进入 fault，不自动 KEEP、不自动换请求重试。
- 显式 KEEP_CURRENT 是模拟 Agent 的合法选择，不是异常兜底。合法 APPLY 只提交一次并只增加一次部署 revision；无实际差异按现有服务返回 UNCHANGED。
- 成功后只到 `CYCLE_START_PENDING`。本模块不调用 `resume_cycle(true)`，不生成即时报告或额外猜测。

### G7. 报告 fail-stop 与 runtime fault 门控

每个 Agent 入口和完成回调都按以下顺序检查：

1. GameRuntime 已配置且 `_fault` 为空。
2. phase、request_type 和当前活动 request context 完全匹配。
3. 没有另一个在途 Agent 请求；同一请求最多提交一次 Gateway。
4. 猜测入口额外验证第 G3 节的已发布报告截止位置。
5. 回调再次检查 fault/phase/context，然后才解析和结算。

4B seal/view/publish 失败时，即使 session 已为 `GUESS_PAUSED`，Gateway 调用次数也必须为 0。手动注入后续结果不得进入 hit、dispatch、RESET 或 ROUND_END。部署 activate 故障同样锁定后续 Agent 入口；不得把同步程序错误当成可重试的模型失败。

### G8. 后续 RESET 状态边界

周期起点可恢复状态必须成组包含：

- 完整 `WorldState`：地形、注册表、玩家/机器人运行状态、goal/contact 状态、world_revision、next_entity_id 和设备参数。
- `CycleState` 与必要 session 身份：simulation_tick、report_period_id、本猜测周期封批数、round/branch/guess-cycle；周期起点不应存在活动 Agent 请求或 frozen guess frame。
- `RuntimeSensingCoordinator.snapshot()`：视觉状态、设备/目标待上传 buffer、事件时配置 sidecar、当前有效 reports 和当时公开配置。
- 场景派生同步所需的同一世界版本，以及部署后重新提取 previous_actor_cells 的连续性边界。

不随局部快照回滚的状态包括整场剩余回退、已结算成绩和持久 Agent 历史。旧请求必须失效，旧分支内容只能以明确历史身份保留。由于 4B 将 reports/history 放在同一 SystemAgentView 数据结构中，模块 6 不能盲目整对象回滚；需分别恢复当前有效视图并保留/合并持久历史。

模块 5 只记录上述合同并使用现有快照接口，不实现快照保存、branch 切换、恢复或 RESET 选择。

### G9. 模拟 Agent 的可控规则

模拟端明确是脚本化测试替身，不宣称推理：

- `LATEST_DETECTED`：从请求 reports 中选择稳定排序后的最新 DETECTED 视觉记录，以其中公开 P 构造合法矩形；没有正面记录时使用脚本给出的合法 fallback 或返回脚本指定的空结果。它不读取当前真实位置。
- `SCRIPTED_RANGE`：返回测试预置的合法或非法矩形，用于稳定 miss、越界、错误形状和超限测试。测试 oracle 独立设置冻结玩家位置，Agent 不接收“本例应 hit/miss”的隐藏标签。
- `SCRIPTED_DISPATCH`：依据公开 device_configuration 中的 ID 返回预置踏板命令，或显式 KEEP_CURRENT；越权用例可脚本指定固定设施/摄像头/地图命令。
- 协议故障脚本覆盖错误 context、额外 hit、缺字段、错误类型、空响应、畸形响应、timeout 和 deferred。迟到回调用测试 Gateway 保存旧 completion 后在新阶段再次注入。
- 不使用随机数、网络、真实计时器、WorldState/WorldFrame 参数或场景节点。同一请求和脚本必须得到相同输出。

## 6. 单周期时序

```text
ACTION：真实运动/交互/感知
  → 提交 world 与 WorldFrame
  → 封存并发布完整统一报告和公开配置
  → GameSession 进入 GUESS_PAUSED，冻结 WorldFrame
  → GameRuntime 检查 fault、phase、request、报告截止位置
  → 构造 location_guess 请求并提交模拟 Gateway（一次）
  → 基础 envelope + 操作 DTO + 身份 + 矩形边界/尺寸校验
  → 程序以冻结帧计算 hit
  → 追加严格猜测历史
  → GameSession.accept_guess_result(已验证 verdict)
       ├─ HIT → RESET_CHOICE；不调用调度，不实现 RESET
       ├─ MISS + 冻结通关条件 → ROUND_END/SUCCESS；不调用调度
       └─ MISS + 本轮继续 → DISPATCH_PAUSED，新 request_id
                              → 构造 dispatch 请求（一次）
                              → 校验响应并重建可信 WorldCommandBatch
                              → WorldCommandService 校验/准备/激活
                              → complete_dispatch 只接受 APPLIED/UNCHANGED
                              → 追加调度历史
                              → CYCLE_START_PENDING；不伪造快照，不恢复 ACTION
```

任何当前请求失败都不得落入 MISS 分支。普通非猜测刻通关和既有联络顺序不由本模块改变。

## 7. 备选方案与取舍

| 方案 | 优点 | 缺点 | 结论 |
| --- | --- | --- | --- |
| 受限矩形 | DTO、边界和 hit 都简单；能覆盖尺寸与越权测试 | 不能表达任意遮挡形状 | 模块 5 采用；正式形状仍后置 |
| 任意格列表 | 表达力强 | 重复、连通性、形状和大小校验复杂，容易变成全图枚举 | 不采用 |
| 固定 offset mask | 形状最严格，响应只需 anchor | 需要另一套 mask 配置/schema；当前只需一个周期 | 留作正式形状确定后的替代 |
| 当前请求失败即 fault | 不会软锁等待或误 miss；与 4B fail-stop 一致，验收明确 | 不是真实游戏的友好恢复策略 | 模块 5 采用；真实重试/继续留给桥接模块 |
| 失败后自动换 request 重试 | 可测试恢复 | 需要请求吊销、重试次数和玩家反馈策略 | 不在本模块提前实现 |
| 失败默认 miss/KEEP_CURRENT | 表面能继续 | 违反明确禁止项，伪造对手判断或部署选择 | 禁止 |
| 全量已发布 reports | 无游标/丢包状态，最符合当前视图 | 长局输入会增长 | 单周期采用；真实模型前再测量优化 |
| 调度后直接 `resume_cycle(true)` | 看似继续玩 | 伪造快照，破坏 RESET 前提 | 禁止；停在 CYCLE_START_PENDING |

## 8. 可观察验收场景

| 编号 | 场景与必须观察的结果 |
| --- | --- |
| M5-01 正常 hit | 完整报告发布后只产生一次 guess 请求；请求 as_of 与最后批一致；LATEST_DETECTED 只使用报告 P；程序判 hit 后进入 RESET_CHOICE，无 dispatch 调用 |
| M5-02 正常 miss + APPLY | 合法非覆盖矩形进入 DISPATCH_PAUSED；新 request_id；一条合法踏板命令经真实 WorldCommandService/SceneSync 提交；revision 只变一次；phase=CYCLE_START_PENDING，tick 不变 |
| M5-03 显式 KEEP_CURRENT | 只有明确脚本选择才提交 KEEP_CURRENT；无世界变化、无 revision 增长，仍进入 CYCLE_START_PENDING |
| M5-04 猜测优先 | 冻结 goal_complete+at_exit 时 hit 仍进 RESET_CHOICE；miss 立即 ROUND_END/SUCCESS 且 Gateway 无 dispatch；普通非猜测刻通关回归不变 |
| M5-05 范围边界 | 地图四角、单格、max_width、max_height、max_cells 正例通过；右边/下边恰好越界、零/负/浮点尺寸、超宽/超高/超面积均拒绝且不裁剪 |
| M5-06 严格 DTO | 错协议/角色/round/branch/cycle/request、缺字段、额外 hit/success/phase、错误 shape、字符串数字、非 plain data 均拒绝；基础 response_matches 通过不足以结算 |
| M5-07 空/畸形/timeout | 当前请求分别进入明确 AGENT fault；phase 不前进，无 miss、dispatch、RESET、ROUND_END、world/revision/report 变化 |
| M5-08 迟到与旧身份 | 旧 guess 在 DISPATCH/CYCLE_START_PENDING/RESET_CHOICE/ROUND_END 到达无效；旧 dispatch 在新 cycle 无效；旧 round/branch/cycle/request 均不改状态 |
| M5-09 越权调度 | 超 max_commands、allowed_cells 外、超踏板总量、camera/robot/map/goal/contact/exit 命令均拒绝；无部分世界变化、无自动 KEEP_CURRENT |
| M5-10 报告 fault | seal/view/publish 注入失败后 runtime fault；即使 phase=GUESS_PAUSED，Gateway 调用为 0，手工回调和后续 step 均无效 |
| M5-11 事件身份与历史 | N=3 的 tick 3 记录不混入 `[0,3)`；历史 R/P/sidecar 不被调度改写；guess/dispatch history 保留原 request/cycle/as_of，不含真坐标 |
| M5-12 快照门槛 | 调度后没有真实 snapshot_saved 证据，runtime 不调用 resume_cycle(true)；现有 snapshot 数据包含 world/cycle/sensing/view 所需字段，持久历史不回滚语义已记录 |
| M5-13 模拟诚实性 | 模拟 Agent 输入只有请求和脚本；固定输入输出确定，无网络/RNG/场景读取；hit/miss 由测试外部断言而非脚本自报 |
| M5-14 回归 | 原 830 项与 4A 114 项及新增套件全部通过；失败探针非零；主场景可观察一个周期并明确停在后续模块门槛 |

## 9. 风险与回炉条件

| 风险 | 控制与回炉 |
| --- | --- |
| 同步回调重入造成重复 guess/dispatch | 单在途请求、request_id 与 request_type 双重检查；若无法避免重入，返回 Plan，不用无限循环泵 |
| 4B 边界已推进 session 但视图未发布 | 入口同时检查 fault 和最后批 as_of；任一不符不得调用 Agent |
| history 与有效 reports 一起被未来 RESET 回滚 | 本 Spec 明确分属；模块 6 必须单独验收，不在 5 假装解决 |
| allowed_cells 缺省变成全图授权 | Main/测试 fixture 强制非空；模块 5 配置校验失败即不启动 Agent |
| 只限制批命令数导致无限增踏板 | WorldCommandService 在最终候选增加 device_limits 校验；覆盖新增、删除后再加及重复请求 |
| 模拟 Agent 偷看真位置形成假验收 | 签名不接收 World/Frame；测试扫描请求越权字段，正常 hit 由报告 fixture 驱动 |
| 严格内部 int DTO 与未来 JSON 数字解码不一致 | 本模块不接 JSON 网络；真实桥接必须另定规范化解码，不能在模块 5 静默宽松转换 |
| Main 在首周期后停止被误认为完整可玩 | UI/日志明确 CYCLE_START_PENDING 或 RESET_CHOICE 是模块 6 门槛，不宣称整场可玩 |
| 范围膨胀 | 若出现真实计时器、聊天、RESET 或更多设备权限需求，先回本 Spec Grill/Plan |

## 10. Plan：实施合同

### 10.1 File Changes

| 文件 | 计划变化 |
| --- | --- |
| `game/scripts/agents/agent_protocol.gd` | 收紧基础响应 envelope/context 的精确字段校验；旧通用 request builder 不充当模块 5 payload 验证 |
| `game/scripts/agents/system_agent_contract.gd` | 新增严格 guess/dispatch 请求与响应 DTO、constraints/policy 校验、矩形解析及冻结帧 hit 纯函数 |
| `game/scripts/agents/simulated_system_agent.gd` | 新增 LATEST_DETECTED、SCRIPTED_RANGE、SCRIPTED_DISPATCH 和故障脚本输出 |
| `game/scripts/agents/simulated_agent_gateway.gd` | 新增单在途请求、结构化完成结果、deferred 和模拟 timeout；无网络/线程/真实 Timer |
| `game/scripts/agents/system_agent_view.gd` | 将 history 从仅空数组扩展为严格 guess/dispatch 历史；保持其它安全投影与深拷贝 |
| `game/scripts/runtime/runtime_sensing_coordinator.gd` | 新增原子 append_system_history 委托；快照继续包含视图，不暴露可变内部对象 |
| `game/scripts/runtime/game_runtime.gd` | 接入模拟 Gateway、guess/dispatch 泵、单在途和重入保护、响应校验、冻结 hit、历史、fault 与旧回调门控 |
| `game/scripts/world/world_command_service.gd` | 在现有角色 policy 最终候选校验中增加可选 device_limits；不改命令类型和公开提交签名 |
| `game/scripts/runtime/prototype_config.gd` | 增加明确标记 fixture 的可触发猜测节奏、矩形约束、窄踏板调度策略和上限 |
| `game/scripts/main.gd` | 创建并注入模拟 Agent/Gateway；显示猜测、调度和后续模块门槛，不添加聊天或 RESET UI |
| `game/tests/agent_contract_tests.gd` | 新增 DTO、范围、冻结 hit、历史、模拟规则和 fault result 纯数据测试 |
| `game/tests/runtime_agent_tests.gd` | 新增真实运行时 M5-01～14 的集成/故障/迟到/猜测优先/调度验收 |
| `game/tests/world_command_tests.gd` | 增加 device_limits 最终候选和既有命令回归 |
| `game/tests/run_tests.gd` | 登记两个新 suite，保留现有异步 runner 与失败码 |
| 新脚本 `.gd.uid` | Godot 导入生成并按工程约定保留 |
| `game/README.md`、本 Spec、Feature 索引 | 实施后回写真实证据、限制、Plan-Execution Diff 和 Review；当前只先登记 Spec |

默认不修改 `GameSession`、`WorldFrame`、`CycleState`、`WorldCommandBatch`、4A 感知算法、3B 交互生产逻辑或 CI。若实施证明必须改这些合同，先回本 Plan 说明原因并重新获得批准。

### 10.2 Signatures

`SystemAgentContract`（RefCounted 静态纯函数）：

```gdscript
static func make_guess_request(context: Dictionary, view: Dictionary, as_of: Dictionary, constraints: Dictionary) -> Dictionary
static func make_dispatch_request(context: Dictionary, view: Dictionary, as_of: Dictionary, policy: Dictionary) -> Dictionary
static func parse_guess_response(data: Dictionary, expected_context: Dictionary, constraints: Dictionary, grid_size: Vector2i) -> Dictionary
static func parse_dispatch_response(data: Dictionary, expected_context: Dictionary, policy: Dictionary) -> Dictionary
static func validate_constraints(constraints: Dictionary, grid_size: Vector2i) -> bool
static func validate_dispatch_policy(policy: Dictionary) -> bool
static func hit_for_frozen_frame(location: Dictionary, frame: WorldFrame, world: WorldState) -> Dictionary
```

builder 非法返回空 Dictionary；parser 返回 `ok/value/errors` 或 `ok/range/errors`，不在失败时给部分合法值。hit 返回 `ok/hit/errors`，不返回给 Agent，也不把内部玩家格写入 history。

`SimulatedSystemAgent`：

```gdscript
func configure(scenario: String, script: Dictionary = {}) -> bool
func guess_response(request: Dictionary) -> Variant
func dispatch_response(request: Dictionary) -> Variant
```

`SimulatedAgentGateway`：

```gdscript
func submit(request: Dictionary, completion: Callable) -> bool
func complete_deferred() -> bool
func expire_deferred() -> bool
func has_pending() -> bool
```

正常结果为 `status=ok + response`；timeout/transport 结果为结构化非 ok 状态和错误码。deferred 由测试显式完成，expire 只模拟超时通知，不宣称真实墙钟计时。迟到重复回调由测试 Gateway 注入，生产 Gateway 自身仍需防重复完成。

`SystemAgentView` / `RuntimeSensingCoordinator`：

```gdscript
func append_history(entry: Dictionary) -> bool
func append_system_history(entry: Dictionary) -> bool
```

coordinator 在隔离视图副本上追加，成功才替换；有报告边界暂存或输入非法时失败不污染已发布视图。

`GameRuntime`：

```gdscript
func configure_simulated_agent(gateway: SimulatedAgentGateway, agent_rules: Dictionary) -> bool
```

内部新增 `_pump_system_agent()`、guess/dispatch 请求函数和 `_on_agent_result(...)`；均先检查 `_fault`、phase、request_type、context 和单在途状态。配置只允许 tick 0、ACTION、无 fault、已配置 sensing 时进行。agent_rules 严格含 guess_constraints 和 dispatch_policy。

`PrototypeConfig`：

```gdscript
static func agent_rules() -> Dictionary
```

`WorldCommandService` 不改变公开方法签名；device_limits 属于可信 role policy 的最终候选校验，缺省不改变模块 2 其它调用方，模块 5 的 system_agent policy 必须显式提供 pressure_plate 上限。

### 10.3 原子 Checklist

- [ ] **P0 基线与红色合同测试**：保留本轮 830/114 基线；先为严格 DTO、矩形边界、hit 不读回复坐标、设备上限和错误不成 miss 建立可失败测试。
- [ ] **P1 严格系统契约**：实现 SystemAgentContract 和基础 envelope 收紧；通过全部字段/身份/形状/尺寸/越界/冻结帧测试。
- [ ] **P2 历史与模拟端**：实现严格 SystemAgentView history、coordinator 原子追加、SimulatedSystemAgent 和 Gateway；验证确定性、deferred、timeout 与无越权输入。
- [ ] **P3 调度额度**：在 WorldCommandService 增加 device_limits 最终候选检查；先证明超上限和越权批次完全不变。
- [ ] **P4 猜测运行时**：GameRuntime 只在有效报告后请求一次，完成严格验证和程序 hit；实现 hit/miss/exit 优先、fault 和 stale/late 门控。
- [ ] **P5 调度运行时**：接入新 dispatch request、可信 envelope 重建、真实 commit/complete_dispatch、历史和 CYCLE_START_PENDING；禁止自动 KEEP 与假 snapshot resume。
- [ ] **P6 Main 与共享验收**：注入 fixture、状态和就绪标记，登记共享测试；跑真实场景单周期、全部故障与既有回归。
- [ ] **P7 验证与回写**：执行 §10.4，检查实际 diff 和错误日志；回写 Validation、Review、Plan-Execution Diff 和剩余限制。

每个单元先补能失败的验收再实现。任一阶段若需要真实模型、完整 RESET、玩家助手或新增设备权限，立即停止 Execute 并返回本 Spec。

### 10.4 Validation Plan

1. Godot 4.7.2 headless import 无脚本/解析错误；共享 runner 和 4A 独立 runner 全通过，共享失败探针退出 1。
2. 纯 DTO 测试覆盖精确字段、identity、shape/size/bounds、正负边界和冻结位置；至少一个测试证明修改回复后的玩家坐标字段不会被用于 hit，而是因未知字段拒绝。
3. 真实运行时覆盖 M5-01～14，Gateway 调用次数、phase、tick、world revision、报告数量、history 和 fault 均作为断言，不只检查返回值。
4. 对报告 seal/view/publish fault 验证 Agent 调用为 0；对 deferred 旧回调在新 phase 注入，验证完全无副作用。
5. 调度走真实 WorldCommandService 和 SceneWorldSyncAdapter；非法批次无节点/注册表/revision 部分变化，激活失败锁定。
6. 主场景和 Windows 导出程序复验一个周期及明确停点；不把 fixture 数值、模拟命中或测试等待当成模型效果、正式平衡或真实网络性能。
7. 运行 `python -m unittest discover -s tests -v`、`python scripts/check_repository.py`、`python scripts/check_project_links.py --all`、`git -c core.whitespace=cr-at-eol diff --check`，并检查 Godot 错误日志。
8. 所有实际计数、日志路径、自然/注入故障和未验证限制回写本 Spec；不得沿用本轮 830/114 作为实施后的新功能证据。

### 10.5 Route Alignment

原路线是复用现有内核而不是重写周期状态机。本 Plan 只在 GameRuntime 增加系统 Agent 编排，hit 仍交给既有 `accept_guess_result`，部署仍走唯一 WorldCommandService，感知算法不改。新增文件服务于严格 DTO 和可控模拟，没有引入通用 Agent 框架。范围与最小框架检查点 5 一致，检查点 6 的快照仍明确后置。

## 11. Spec Review Notes（Plan 自检，非用户批准）

| Check | Verdict | Evidence |
| --- | --- | --- |
| Requirement clarity & acceptance | PASS | Goal/In/Out、G1–G9、单周期时序和 M5-01～14 可直接观察；正式玩法未决项没有伪装成 fixture 定案 |
| Plan executability | PASS | 文件、签名、P0–P7 和验证命令明确；不需要真实密钥、网络或完整 RESET |
| Risk / rollback readiness | PASS | fail-stop、stale、重入、额度、历史恢复和共享工作树风险均有边界；新增文件可独立回退 |

Readiness Verdict：**GO（仅表示可以提交用户审查 Plan）**。Approval Status 仍为 **NOT APPROVED**；本节不是 Execute 许可，也未执行独立 REVIEW SPEC。

## 12. Execute / Review / Plan-Execution Diff

- Execute Log：未开始；本轮没有游戏代码改动。
- Validation：仅有 §4.3 的研究基线复跑，不是模块 5 功能验证。
- Review Verdict：未开始。
- Plan-Execution Diff：无实施，因此无差异。
- Archive：任务未闭环，不归档。

## 13. Resume / Handoff

- 当前 phase：`PLAN`；approval：`NOT APPROVED`；spec：本文件。
- 当前任务单元：模拟系统 Agent 的严格请求/响应、程序 hit、单次调度与故障门控。
- 下一步：用户审查 G2/G4/G5/G6/G9 和 Plan；若需改动先修订本 Spec，只有精确 `Plan Approved` 才进入 Execute。
- 不得沿用模块 0–4 的 Plan Approved 作为模块 5 批准，不得因已有 File Changes/Checklist 自行实施。
- 当前工作树有其他会话改动；后续实施必须逐项核对并保留，不执行 git clean、reset 或覆盖。
