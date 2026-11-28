# SDD Feature Spec：模块 2 世界状态、设备注册表与受校验命令

层级：Feature Spec。创建：2026-11-27 20:53（Asia/Shanghai）。分支：`team/branch-1`。

**阶段：REVIEW 完成。Plan Approval：Plan Approved。Implementation Verdict：PASS（模块 2 范围）。** §20 的 R1–R3 已修复，最终 304 项正式检查通过，并经原评审者独立复核关闭；当前认定以 §21 为准。用户随后明确授权本模块一次 commit 和 push 至 `team/branch-1`；禁止清理或覆盖其他会话改动。

> 2026-11-28 后续裁决：踏板改用运动前后演员所在格判定，`occupants / baseline_ready` 仅作为遗留兼容字段保留，4A/4B 不读取或写入，也不再需要部署基线写回。下文相关基线内容保留为模块 2 历史合同，待全部模块完成后统一清理；现行玩法以设计 Spec v0.44、机制 v0.25 为准。

## 1. Goal 与当前任务单元

为游戏提供一份独立于 Godot 场景节点的权威世界数据，以及唯一、受校验、可原子提交的动态世界命令入口。证明模板初始化、稳定 ID、空间合法性、原子性、同步门槛与分支隔离可用，再交给后续运动、感知和 RESET 模块。

当前任务单元：实现内存中的 LevelTemplate、WorldState、DeviceRegistry、WorldCommandService，接入模块 1 的联络/调度结束门槛，并以少量 headless 场景验收。主场景仍是工程壳，不宣称形成可玩关卡。

Done Contract：本文件的 Acceptance Scenarios 通过；模块 1 受影响的阶段与报告顺序回归通过；Godot 4.7.2 导入、headless runner、仓库及链接检查通过；实际证据回写本 Spec。新规则未验证前，不沿用旧的“75 passed”作为模块 2 证据。

## 2. In Scope / Out of Scope

In Scope：

- 内存模板、网格与坐标转换、实体注册表、当前玩家和机器人状态的可复制表示。
- 摄像头、机器人、单格踏板、目标装置、联络点、出口的类型字段与空间关系；墙/地面作为地图单元。
- SetMapCell、AddDevice、RemoveDevice、MoveDevice、SetDeviceParameter、SetPatrolPath 的框架实现及严格结构校验。
- 整批预检、候选副本、最终世界约束、原子提交、基本幂等和明确保持现状。
- 必要派生同步的接口与测试替身；联络结束即刻生效、部署成功才离开暂停。
- 内存 snapshot / deep copy / plain-data 编解码，以及后续 RESET 的对接合同。
- 可注入的能力/参数限制配置；测试中使用的角色策略不代表最终 Agent 授权。

Out of Scope：

- 玩家控制器、真实碰撞形状、输入按键绑定、接近交互、机器人行走、摄像头扫描动画。
- 实际视线计算、踏板进入检测、ObservationRecord / ReportBatch 的完整内容。
- 门、规则性灯、多格设备、自动寻路与行动中重新规划。
- 完整 RESET、Agent 记忆管理、文件读写/存档、资源目录或外部文件系统接入。
- 真实 Agent、DeepSeek、AgentGateway、聊天 UI、网络请求、模型重试循环。
- 正式关卡、数值平衡、最终动作额度、评分、四轮完整集成。
- 模块 1 payload 全面 DTO 化、猜测范围与 hit 验证的补实现。

## 3. 已确定规则与本轮 Grill 结论

| 事项 | 当前决定 |
| --- | --- |
| 实体种类 | 摄像头、机器人、踏板、目标装置、联络点、出口进入同一注册表；玩家状态另归 WorldState；墙/地面不分配设备 ID |
| 固定设施权限 | 系统 Agent 不得动态增删或移动目标装置、联络点、出口；游戏程序可以推进目标与联络状态 |
| 稳定 ID | 初始与新增实体均由世界分配；模板不预置运行时 ID；移动和改参不换 ID |
| 安装方式 | 墙装/顶装是同一种摄像头的安装方式；允许转向范围、扫描区间、瞬时视野分别表达 |
| 踏板占位 | 每块一格，同格最多一块；不能叠墙或阻挡设施；可与顶装摄像头共格 |
| 移动实体与踏板 | 玩家/机器人可以站在或经过踏板；部署在其脚下合法，不得因隐藏占位拒绝或回传占位 |
| 踏板触发 | 玩家或机器人移动进入时产生匿名事件；部署不触发，已在范围内须先离开再进入；实际触发留给感知模块 |
| 固定交互 | 目标装置、联络点阻挡通行；玩家靠近并按交互键发起操作或会话，具体键位/距离后定 |
| 出口 | 有实体体积；条件不足时阻挡；条件满足后触碰产生通关条件，无须按键；仍服从猜测优先 |
| 实心规则 | 当前所有阻挡路的静态内容均按实心处理，也遮挡视线；两种查询分开，配置不开放为可任意拆开的 Agent 开关 |
| 路线 | 整数格对应格心，仅上下左右相邻；空路线非法；单点驻守；多点沿原路折返 |
| 换路 | 暂停时真实位置不能改写；在格间则先走完当前段，再接以该段终点开头的新路线；该衔接只执行一次 |
| 机器人视野 | 默认以自身为圆心的圆形，受墙体及实心遮挡限制；半径是配置值，视野不依赖运动朝向 |
| 联络生效 | 联络结束、恢复模拟之前提交并同步成功，立即生效；不等上报边界 |
| 系统调度 | 只在猜错且本轮继续后的调度暂停；完成部署后进入下一猜测周期，先同步再保存周期起点 |
| 无改动 | 允许主动选择保持现状并结束部署；不消耗设备改动额度，不撤销联络会话使用；非法批次不自动转为无改动 |
| 报告时机 | 仍按正常边界统一上传；同批允许含配置变化前后记录，历史事实不按最新配置重算 |
| RESET | 当前猜测周期起点；旧分支历史保留但失效，新 branch_id 拒绝旧命令；本模块不实现完整恢复流程 |

以上由本会话明确决定。以下章节记录获批准并已落实的工程合同；实际运动、感知、角色授权等后置项仍按各节边界处理。

## 4. Research Findings（实施前基线）

来源按优先级为用户最新决定、[设计 Spec](../../PRELIMINARY_DESIGN_SPEC.md)、[机制基准](../../侦测定位_机制草案.md)、[框架 Spec](../minimal-framework-spec.md)、实际代码及测试、旧 context bundle。

- Research 时 `game/scenes/main.tscn` 只有工程壳，尚无 WorldState、设备实体、触发区域、视觉检测或机器人控制器；并不存在已经实现后发生的“踏板缓存不同步”缺陷。现阶段主场景仍为工程壳，纯数据与命令已实现。
- 模块 1 已有时钟、暂停、报告边界、猜测优先与身份校验；75 条断言属于旧契约的历史证据。模块 2 实施后的回归结果见 §16。
- 实施前 `GameSession.process_report_boundary()` 为 seal → apply_config → update_view；`end_contact()` 和 `complete_dispatch()` 没有世界提交门槛。已按 §8 迁移。
- 旧“下一上报周期生效”来自一次明确的时间边界选择；本轮已改为联络结束立即生效。模块 1 Feature Spec 已补记迁移说明，原批准与历史测试保留。
- 旧 context bundle 是历史快照；不能据其延迟配置、缺少模块 1 等旧描述推断当前实现。
- 模块 1 已知限制继续保留：payload 尚非严格 DTO；hit 依赖上游验证；报告测试只是顺序桩。本模块仅严格约束自己的命令和内存数据，不借此宣布以上问题已解决。
- 首版无需通用 ECS、导航服务、分布式事务或完整场景回滚框架；当前验证目标可以用纯数据和同步准备接口覆盖。

## 5. 架构与依赖

`LevelTemplate → WorldState(DeviceRegistry + terrain + actor state)`

`可信协调层 → GameSession 暂停上下文 → WorldCommandService → 候选 WorldState → WorldSyncAdapter → 成功回执 → GameSession 放行`

- GameSession 仍独占 phase、round_id、branch_id、guess_cycle_id、simulation_tick；WorldState 不维护另一套可独立前进的身份或时钟。
- WorldCommandService 持有唯一可变的当前 WorldState；对外返回副本。DeviceRegistry 是其内部组成，不作为第二条写入口。
- LevelTemplate 的数据在构造时复制，此后不可原地编辑；修改模板应构造新模板，现有世界不随调用方字典变化。
- 后续运动适配器负责把完成物理步的玩家/机器人状态写回权威世界，再提供 WorldFrame 和感知输入。本模块固定状态与交接要求，不实现运动循环；运动与感知的具体实施单元另行定 Plan，不因本文件自动扩大模块 3。
- WorldFrame 是已完成某步的不可变传递快照，不能变成另一份长期可变世界。
- 后续感知模块读取实体状态与地形，生成事件时固定实际区域/位置；不使用上传时的最新实体位置重算旧事件。
- 权威位置、注册表与快照只供可信游戏代码；不可直接塞进 AgentProtocol 的 payload。

## 6. 数据模型

### 6.1 LevelTemplate

| 字段 | 形式与约束 |
| --- | --- |
| template_key | 非空字符串，标识模板，不作为实体 ID |
| grid_size | 两个正整数；地图尺寸由调用方配置 |
| cell_size / origin | 有限正尺度与世界原点，用于统一格坐标转换，不硬编码玩法尺寸 |
| terrain | 与 grid_size 匹配的 FLOOR/WALL 单元；格外不可通行 |
| player_spawn | 合法地面上的初始连续坐标 |
| initial_entities | 有序的实体初始描述列表，不含运行时 ID；初始化按列表顺序分配 ID |
| device_rules | 类型结构、参数合法范围和安装约束的可信配置；不能由设备命令修改 |

仅接受内存数据；不增加文件加载、ResourceLoader 路径或存档协议。测试地图与数值只是 fixture，明确不代表正式关卡。

### 6.2 WorldState 与坐标

保存 terrain、DeviceRegistry、player_position: Vector2、player_velocity: Vector2、world_revision: int、next_entity_id: int。玩家位置与速度由模板初始化并可复制，实际运动写回接口后续接入。实际目标/联络状态存于对应实体，整体通关判定仍由游戏规则汇总并交给 GameSession。

- 格坐标为 Vector2i；序列化为两个整数。路径点表示格心，不表示可任意挑选的浮点位置。
- 连续坐标为 Vector2；序列化为两个有限数。使用 `origin + (cell + 0.5) * cell_size` 推导格心。
- 从连续位置到格坐标采用 floor，统一处理负坐标和格界；地图外结果不会被自动夹入地图。
- 静态设备锚点按格/墙面表达，连续显示位置由转换推导；机器人当前连续位置与格心路线同时存在，分别表达当前位置与未来路径。
- world_revision 每次实际世界变更后递增；预检、拒绝、保持现状或无实际差异的有效提交不递增。
- 动态占位与静态通行分开。踏板合法性不得查询隐藏玩家/机器人占位；实心地图变更必须避免把当前实体封入新障碍，其内部校验结果不直接开放给模型。

### 6.3 DeviceRegistry

共同字段为 `id:int > 0`、`kind`、类型规定的安装/位置字段、`parameters`、`runtime_state`。三类可变设备与三类固定设施使用一个 ID 索引；各类型只接受自己的字段，不以任意键值字典替代类型约束。

| 类型 | 配置/位置字段 | 权威运行状态与后续 hook |
| --- | --- | --- |
| camera | mount_type=wall/ceiling、cell 锚点、墙装 wall_side；enabled、view_radius、fov_angle、scan_center、scan_half_angle、scan_speed | heading、scan_direction；真实扫描后续实现 |
| robot | 初始格、view_radius、move_speed、patrol_path | 连续 position、当前路径段/进度、折返方向、一次性衔接段；感知形状固定为 circle |
| pressure_plate | cell；覆盖固定一格，不允许命令修改覆盖尺寸 | 占用/进入基线的数据位置与后续初始化 hook；内部实体身份不得进入匿名报告 |
| goal | cell；实心、按键交互类型 | 操作进度/完成标记；推进规则后续实现 |
| contact | cell；实心、按键交互类型 | used 标记；会话内容不在实体中保存 |
| exit | cell；实心接触目标类型 | 与通关条件的关联 hook；条件不足不通关，条件满足触碰才交给 GameSession 裁决 |

墙装锚点用可安装地面格及其相邻墙面表示，顶装锚点用地面格表示；由统一转换推导节点位置。安装格须没有实心设施，墙装还须在最终候选地图中保有支撑墙。安装角度限制由可信配置给出，不能因顶装默认获得瞬时全向视觉。

移动阻挡和视觉遮挡分别提供查询，当前实心地形/设施同时返回两种阻挡；不暴露两个独立的 Agent 可调开关。出口的“可完成撤离”与实体体积独立：满足条件触碰即可结束本轮，不要求先将其改成普通可走格或透明物体。实际接触几何与碰撞实现后置。

摄像头同挂点数量等未定布局约束通过显式策略输入表达；在开放对应 Agent 命令前确认，不凭本模块测试 fixture 自动赋予玩法权限。结构、有限数、可信配置给出的上下限与安装约束均须校验；本模块不替用户确定最终视距、速度、角度。

### 6.4 ID、复制与序列化

- 一轮内分配正整数 ID，按高水位单调增加；删除不回收。预检在候选副本分配临时结果，不消耗正式分配器。
- 成功回执以命令序号映射新增 ID；AddDevice 提供完整初始字段，同批暂不支持用临时引用继续操作刚新增设备。
- template_key 不充当实体 ID；重新初始化一轮可重新分配，历史实体引用必须结合 round/branch。
- snapshot 保存现存 ID 与 next_entity_id；未来 RESET 保留快照实体 ID，恢复时分配器使用当前与快照高水位的较大值，避免撤销分支新增 ID 被本轮重用。
- copy/编码逐字段复制数组、字典和对象；snapshot 只含基础值、数组和字典，不含 Node、Callable、Resource 或共享可变对象。
- 内存 decode/encode 不读写文件；完整 RESET、分支创建和历史迁移不在本模块执行。

## 7. 命令模型

WorldCommandBatch 字段：

| 字段 | 合同 |
| --- | --- |
| context | 沿用 AgentProtocol 的 protocol_version、role、request_id、round_id、branch_id、guess_cycle_id |
| source | 可信协调层标识的 contact / dispatch；必须与当前暂停阶段和角色匹配 |
| base_world_revision | 提交针对的世界版本；正式提交重验 |
| mode | APPLY 或 KEEP_CURRENT；KEEP_CURRENT 必须显式选择并携带空 commands，APPLY 不接受空数组 |
| commands | 有序类型化命令列表，拒绝未知字段、错误类型和非有限数 |

source/role 不是权限凭证：调用只经可信协调层，必须匹配 GameSession 当前期待上下文。请求来自真实模型还是测试替身不改变验证规则。本模块不提供通用外部工具端点。

校验配置分为两处：LevelTemplate.device_rules 提供 parameter_ranges、camera_mount_limits 和 camera_per_anchor；服务 policy 按角色配置 commands（命令到类型白名单）、parameters（类型到参数白名单），并可配置 max_commands 和 allowed_cells。allowed_cells 限制命令给出的目标格与整条新路径，适用于 SetMapCell、AddDevice、MoveDevice、SetPatrolPath，不是完整的对象访问控制策略。未声明的动作拒绝；未提供的必要参数限制不能被解释为无上限。最终改动计数、设备配额数值与额度扣减语义仍由玩法/授权模块决定，不建立隐含的最终额度规则。

| 命令 | payload 与关键约束 |
| --- | --- |
| SetMapCell | cell、cell_kind；只支持 FLOOR/WALL；最终地图不能覆盖静态设施/踏板或使有效路线及衔接段失效 |
| AddDevice | device 内含 kind、cell、parameters 及类型必需字段；运行时仅 camera/robot/pressure_plate；ID 由世界分配 |
| RemoveDevice | id；未知 ID 拒绝；固定设施不能经此 Agent 命令删除 |
| MoveDevice | id、新锚点；仅 camera/pressure_plate；机器人通过路线移动，不通过命令瞬移 |
| SetDeviceParameter | id、parameter、value；只接受类型声明且策略允许的有界参数；不改 ID、kind、权限、额度或规则上下限 |
| SetPatrolPath | robot_id、cells；空非法，单点驻守，多点四邻接折返；起点按当前状态锚定 |

摄像头候选参数包括 enabled、朝向、扫描中心/区间、扫描速度、视距与瞬时夹角；机器人候选参数包括移动速度与视距。具体对角色开放哪些字段由 policy 决定；踏板首版没有可改覆盖尺寸，目标进度和联络 used 也不是设备参数命令。

新路线首点必须是当前格心，或当前未完成段的终点；当前段先走完，后续按新路线折返。设单点路线不会立即停止在任意浮点处，也不会传送到远处驻守点。每对连续点必须曼哈顿距离为 1；非连续重复格允许，连续重复格不等于合法移动。

基本错误码：INVALID_CONTEXT、STALE_BRANCH、INVALID_PHASE、STALE_WORLD、PERMISSION_DENIED、INVALID_COMMAND、UNKNOWN_ID、INVALID_POSITION、OCCUPANCY_CONFLICT、INVALID_PARAMETER、INVALID_PATH、SYNC_PREPARE_FAILED、REQUEST_REUSE。SYNC_ACTIVATION_FAILED 表示不可继续部署的适配器程序故障，详见 §10。

## 8. 状态转换与模块 1 接入

联络：

`ACTION → CONTACT_PAUSED → 提案/预检 → 成功提交或明确 KEEP_CURRENT → ACTION`

调度：

`GUESS_PAUSED → 未命中且本轮继续 → DISPATCH_PAUSED → 成功提交或明确 KEEP_CURRENT → CYCLE_START_PENDING → 快照就绪 → ACTION`

- 命中、已满足通关并未命中等原分支保持原结算；不额外进入调度。
- 任何拒绝都不离开当前暂停、不推进 simulation_tick、不增加报告批数。
- 联络期间原始记录保留，结束部署不额外感知、封包或请求猜测。
- 报告边界改为封存整批 → 更新系统视图 → 原有猜测/通关分支；移除旧的“应用到期玩家配置”回调。
- GameSession 为联络或调度登记本次命令请求 context；预检可以反复修改候选。一次正式拒绝后若修改批次，重新领取 request_id；同请求重传只允许相同内容。
- 请求登记复用 SessionState 的 active_request_context，不再保存第二份轮/分支/周期身份；猜测与部署窗口互斥。
- end_contact / complete_dispatch 必须调用可信同步部署回调并核验 WorldCommandResult，不能接受 Agent 声称的 success 布尔值。未绑定部署回调或结果无效时保持暂停。
- 接口只依赖本地确定性操作；本模块不增加“Agent 必须无限重试”的阶段，也不自动把失败当作 KEEP_CURRENT。
- 规则内核仍可用测试部署回调独立测试；世界集成场景必须调用真实 WorldCommandService，不能只用成功桩证明提交门槛。

## 9. 原子提交、预检与幂等

1. 校验上下文、阶段、角色和权限，检查 request_id 与 base_world_revision。
2. 从当前 WorldState 深拷贝候选。按数组顺序检查命令结构、ID 引用及字段赋值，新增 ID 暂存在候选。
3. 检查最终候选世界的占位、安装支撑、参数和所有机器人路线/衔接段，不要求每个临时中间状态都满足最终空间约束。
4. 预检到此结束；返回是否合法及内部错误，不写世界、不刷新场景、不消耗 ID/额度、不发事件。通过预检不是正式提交凭证。
5. 正式提交重新校验当前上下文与版本；准备必要派生状态。
6. 准备成功后，在同一暂停内同步激活候选及其派生结果，完成后才返回成功。失败不得留下新地图、部分设备或已消耗的 ID。
7. 明确 KEEP_CURRENT 返回 unchanged；不调用设备更新、不增加 revision，也不作为非法方案的自动兜底。

最终状态校验允许同批修正地图与受影响路线/安装位置；未被合法修正的失效路线仍导致整批拒绝。命令顺序本身确定字段的最后值；ID 引用不能指向尚不存在或已移除的实例。

幂等记录只保存在内存，按完整请求 context 关联批次内容与终态结果。服务缓存最近一次正式提交；GameSession 同时只登记一个有效期待请求，换请求后旧请求即失效。同一有效部署窗口的相同请求重传返回原回执，不再分配 ID 或同步；同 ID 不同内容拒绝。窗口结束或分支变化后的旧请求直接失效，不重新执行；不为了返回历史回执而放宽分支校验。无需数据库、持久化日志或分布式锁。

WorldCommandResult 为内部回执：status、context、revision_before/after、command_results、created_ids、errors。status 固定为 VALID（仅预检）、APPLIED、UNCHANGED、REJECTED；GameSession 仅接受当前期待身份下的 APPLIED/UNCHANGED 作为结束部署依据，不接受 VALID。错误可包含 command_index；不得附带玩家坐标/隐藏占位详情。完整内部验证结果不等于 Agent 可见 DTO；尤其玩家助手不能通过任意坐标预检探测地图。角色安全工具视图留给后续模块，不直接开放本服务。

## 10. 派生系统同步

WorldSyncAdapter 为可替换同步接口：

- prepare 接收旧/候选状态的隔离副本和 change_set；构造暂存结果，不改活跃世界或场景。
- 准备失败时返回明确失败，丢弃候选，旧世界及活跃派生状态不变。
- activate 只发布已准备好的本地结果，不再做可能正常失败的校验、加载或外部 I/O；返回 true 确认执行到了结束点。激活完成前不恢复模拟，不允许回调重入提交。未收到 true 属于程序故障：服务锁定，GameSession 保持暂停，不把它当作可重试的准备拒绝，也不宣称已回滚真实场景。
- 真实场景适配器必须满足以上合同后才能接入；若激活阶段出现程序错误，应暴露为开发错误并停止模拟，不能伪造成功或引入模型重试来修复程序。
- 模块 2 使用数据模式适配器及拒绝准备的测试替身，验证调用与原子门槛；不声称已经验证真实 Godot 碰撞/视觉同步。
- 若后续检测每次直接读新 WorldState，则无需另造一份缓存；存在缓存时才刷新。地图变化须考虑没有直接改参的设备。
- 未改动的扫描相位、巡逻进度和踏板基线不重置。新增/移动踏板的基线初始化由后续感知适配器在恢复模拟前完成，部署不生成激活记录。

## 11. RESET 兼容接口与后续 hooks

本模块实现 snapshot_copy、to_snapshot、from_snapshot，以及必要字段的完整保留和隔离。单点驻守、折返方向、未完成旧段、安装参数和稳定 ID 不得遗漏。

仅预留以下衔接，不实现完整流程：

- 后续运动/感知模块：完成物理步后的玩家/机器人状态写回；踏板占用基线计算；视觉检测读取；事件时刻配置关联。具体任务单元另行明确。
- RESET 模块：同时恢复 WorldState/CycleState、生成新 branch_id、重建派生系统、维护旧历史并更新 ID 高水位。
- 交互模块：接近/按键、目标操作进度、联络点使用、出口触碰转成已验证 WorldFrame 条件。
- Agent 模块：角色安全 DTO、允许工具、额度和重试策略。模块 2 不补写聊天、网络或文件系统接口。

旧 branch_id 命令的拒绝通过传入新的可信期待上下文测试；不为此实现一次完整 RESET，也不向 Agent 暴露修改 branch_id 的方法。

## 12. Interface Contract（已实现签名）

以下签名对应 `game/scripts/world/` 和 `core/game_session.gd`。命令字段错误通过拒绝回执返回；构造器校验失败按表中空值合同处理，不隐式转换字符串数字或截断浮点路径点。

| 所属 | 接口 | 行为 |
| --- | --- | --- |
| LevelTemplate | `from_data(data: Dictionary) -> LevelTemplate`、`validate() -> Array[Dictionary]`、`instantiate_world() -> WorldState` | 构造时复制；校验失败不能产生半个世界，instantiate 返回 null |
| WorldState | `snapshot_copy() -> WorldState`、`to_snapshot() -> Dictionary`、`from_snapshot(data: Dictionary) -> WorldState` | 内存复制与编码；非法输入返回 null，不触碰当前世界 |
| WorldState | `cell_to_world(cell: Vector2i) -> Vector2`、`world_to_cell(position: Vector2) -> Vector2i`、`get_cell_profile(cell: Vector2i) -> Dictionary` | profile 分开返回地形、静态阻挡、遮挡、踏板及出口接触类型；不把出口自动变为普通通路 |
| DeviceRegistry | `get_entity(id: int) -> Dictionary`、`snapshot_copy() -> DeviceRegistry`、`to_snapshot() -> Array[Dictionary]` | 返回副本；不存在返回空值；增删仅由候选变更逻辑调用内部方法 |
| WorldCommandBatch | `from_data(data: Dictionary) -> WorldCommandBatch`、`to_data() -> Dictionary` | 严格字段构造；不含任意 Godot 对象引用 |
| WorldCommandService | `_init(initial_world: WorldState, policy: Dictionary, sync_adapter: WorldSyncAdapter)` | 复制初始世界和可信策略，保存私有可变状态 |
| WorldCommandService | `validate_batch(batch: WorldCommandBatch, expected_context: Dictionary) -> WorldCommandResult` | expected_context 由可信协调层提供，包含当前请求、phase；无副作用 |
| WorldCommandService | `commit_batch(batch: WorldCommandBatch, expected_context: Dictionary) -> WorldCommandResult`、`get_world_snapshot() -> WorldState` | 重验、同步、提交；读口始终隔离 |
| WorldSyncAdapter | `prepare(previous: Dictionary, candidate: Dictionary, changes: Dictionary) -> Dictionary`、`activate(prepared: Dictionary) -> bool` | prepare 返回 ok/prepared/errors；activate 不再正常失败，true 确认完成；意外中断锁定服务 |
| GameSession | `renew_world_request() -> Dictionary` | 仅 CONTACT_PAUSED / DISPATCH_PAUSED；按阶段选择角色、分配新 request_id、更新期待 context |
| GameSession | `end_contact(deploy: Callable = Callable()) -> bool`、`complete_dispatch(deploy: Callable = Callable()) -> bool` | deploy 接收期待上下文副本，返回内部 WorldCommandResult；成功/明确 unchanged 才转阶段；缺省回调返回 false |
| GameSession | `process_report_boundary(seal_batch: Callable, update_view: Callable) -> bool` | 删除延迟配置回调，保留报告/猜测排序和重入保护 |

GameSession 首次进入联络或调度时自动登记一次期待命令 context；renew 用于正式拒绝后的新方案。deploy 回调是可信游戏协调器，不是模型可执行代码。模块 1 的 get_state_snapshot 可继续提供隔离 context；不新增把 WorldState 交给 Agent 的读取接口。

工程实现若需改变上述职责或签名，先回写 Plan；不能顺便迁移 AgentProtocol 全部 payload、修改 hit 规则或新增运动控制器。

## 13. File Changes（已落实）

| 文件 | 变化 |
| --- | --- |
| `game/scripts/world/level_template.gd` | 新增不可变模板与初始化校验 |
| `game/scripts/world/world_state.gd` | 新增网格、空间查询、状态复制与内存快照 |
| `game/scripts/world/device_registry.gd` | 新增六种实体字段校验、稳定 ID 与类型化占位 |
| `game/scripts/world/world_command_batch.gd` | 新增命令 envelope、mode 与严格 payload |
| `game/scripts/world/world_command_result.gd` | 新增内部验证/提交回执 |
| `game/scripts/world/world_command_service.gd` | 新增预检、策略校验、候选批次、幂等和提交 |
| `game/scripts/world/world_sync_adapter.gd` | 新增 prepare/activate 合同与纯数据模式 |
| `game/scripts/core/game_session.gd` | 调整报告签名、登记部署请求、联络/调度提交门槛 |
| `game/tests/world_command_tests.gd` | 新增数据和提交场景，测试替身放在测试文件中 |
| `game/tests/session_kernel_tests.gd` | 迁移原回调测试，增加新阶段门槛回归 |
| `game/tests/run_tests.gd` | 汇总两套测试并保持失败非零退出 |
| `.github/workflows/godot.yml` | 仅更新任务名称/说明为框架契约测试，沿用固定引擎与运行入口 |
| `game/README.md`、本 Spec | 回写真实验证范围与结果；不预写测试通过 |
| 新脚本对应 `.gd.uid` | 由 Godot 导入产生并按工程约定保留 |

`game/scenes/main.tscn`、`game/scripts/main.gd`、AgentProtocol 与外部连接配置未改。同步更新既有文档入口和索引，避免继续称模块 2 为 Pending/零实现；历史模块 1 的批准和 75 条断言证据保留，并补记当前迁移状态。

## 14. Acceptance Scenarios

采用少量行为场景，每个场景可有多条断言，不为每个 getter 单独堆测试。

| 编号 | 场景与必须证明的行为 |
| --- | --- |
| A1 模板与隔离 | 一个含六类实体的小 fixture 初始化成功；ID 唯一且世界分配；修改模板输入、返回实体或深层 snapshot 不污染当前世界；内存往返保留字段 |
| A2 空间关系 | 同格顶装摄像头+踏板合法；第二块踏板、踏板+墙/实心设施拒绝；目标/联络点有移动及视线阻挡；出口保留体积和触碰类型；条件与猜测优先由内核测试组合验证 |
| A3 稳定设备与限参 | 新增/移动踏板或摄像头成功；移动不换 ID；非法挂墙、未知 ID、未知参数、越界值、非有限数拒绝；系统不能增删移动固定设施 |
| A4 路线 | 对角、跳格、穿墙、空路线拒绝；单点驻守有效；多点折返字段正确；格间换路必须接当前段终点，不允许任意起点；圆形受遮挡配置可保存，不声称已实现视线算法 |
| A5 原子性与最终世界 | 一条合法一条非法的批次完全不变，包括 revision/ID/运行状态；同批合法修正支撑/路线可通过；未修正路径失效拒绝 |
| A6 预检与幂等 | 多次预检不改状态、不消耗 ID、不调用同步；有效窗口重复提交只执行一次；同 request_id 异内容拒绝；未知 ID 的新 Remove 不能冒充重试 |
| A7 同步门槛 | prepare 被调用且看见完整候选；prepare 拒绝则 active world 和已激活替身不变；成功只 activate 一次，结果成功后才能放行；KEEP_CURRENT 不刷新设备 |
| A8 身份与阶段 | 旧 branch、错误 round/cycle/request/role、ACTION 中提交被拒绝；新请求不沿用旧分支回执；使用测试期待上下文，不实现完整 RESET |
| A9 会话集成回归 | 联络结束改动在下个物理步前可读；失败继续暂停；明确保持现状可以结束；调度成功后才进入 CYCLE_START_PENDING；报告不再应用延迟玩家配置；保留半开区间、猜测优先、暂停冻结与原有隔离测试 |

不测试真实 Agent、真实视觉几何、实际踏板触发、最终权限平衡或最终关卡。A2 的设施与出口检查是数据/内核合同测试，不是实际碰撞验收。

## 15. 风险与明确后置项

| 风险 | 处理及边界 |
| --- | --- |
| 状态与节点各自成为权威 | 写入口归 WorldCommandService；后续物理适配器有明确写回顺序；公开 getter 深拷贝 |
| 新旧配置混入一批 | 事件发生时固化事实；报告模块完成版本关联，不在模块 2 实现完整报告 |
| prepare 成功后真实场景仍失败 | 当前仅验证接口；真实适配器接入前必须验证 activate 合同，不以测试替身冒充物理验收 |
| 单点驻守被误当瞬移 | 复用当前段衔接规则；单点仅在合法锚点驻守 |
| 布局校验泄漏隐藏位置 | 踏板不依赖移动占位；内部服务不直接开放 Agent；角色安全预检工具留到授权模块 |
| 模块 1 迁移破坏时序 | 修改报告回调与部署回调的相关测试，保持时钟、猜测优先、hit 与 RESET 语义 |
| final-world 验证范围不清 | 格式/引用顺序检查与最终空间约束明确分开；失败不分配正式 ID |
| 未定玩法被默认值固化 | 数值/配额/摄像头同挂点策略显式注入，fixture 不视为玩法；没有权限项就拒绝，不自动放开 |
| 工程范围膨胀 | 无 ECS、自动寻路、真实场景适配器、存档、模型循环或通用事务框架 |

仍属玩法：具体合法区域、设备数量与额度、参数上下限、交互距离/按键、是否始终保证玩家到目标/出口可达、真实模型超时策略。模块 2 可预留策略校验入口，不在此选择最终数值或开放动作。

## 16. CI/CD 与 Validation

本次沿用 Godot 4.7.2.stable.official.ed1daf0bf。CI 仍为一个 Linux headless job：固定下载与哈希、导入、运行 `res://tests/run_tests.gd`；不增加真实模型、每 PR 导出或自动发布。

本地验证方式：

- Godot headless 导入，检查无脚本/解析错误。
- 运行两套契约测试，记录实际断言数与退出码；首次接入新 suite 时确认它的失败能传递为 runner 非零。
- `python scripts/check_repository.py`、`python scripts/check_project_links.py --all`。
- 检查本次 diff；保留原有文件换行，使用 `git -c core.whitespace=cr-at-eol diff --check` 检查既有 CRLF 文档，不全文件格式化。
- 日志用 workspace 内绝对路径，避免此前相对 log-file 的 user://D: 路径问题。

首次实施验证记录（2026-11-27，修复前历史；当前结果见 §21）：

| 检查 | 实际结果 |
| --- | --- |
| Godot headless 导入 | 退出码 0；日志无 SCRIPT ERROR / Parse Error / ERROR |
| SessionKernelTests | 81 passed、0 failed；其中 75 条既有行为断言随新合同迁移，另含 6 个场景完成检查 |
| WorldCommandTests | 164 passed、0 failed；六个组合场景覆盖 A1–A9，含场景完成检查 |
| runner 失败退出 | 实施调试中实际新套件失败已得到退出码 1；修复后最终 runner 退出码 0，脚本场景中断也计为失败 |
| 仓库检查 | 1117 files、28 maintained documents、0 issues |
| 全量文档链接 | 67 documents、0 broken links / missing entries |
| whitespace | CRLF 兼容的 git diff --check 通过 |

本机日志位于忽略目录 `tmp/module2-import.log`、`tmp/module2-tests.log`。仓库与链接检查只证明文档卫生；headless 不证明真实碰撞或可玩关卡。远端 CI 未运行，本会话没有提交或推送。

## 17. Checklist

- [x] Research：读现行设计、模块 1 代码及测试，区分旧 context。
- [x] Grill：实体占位、实心规则、固定交互、出口、四邻接、驻守/折返、即时生效与保持现状已收敛。
- [x] Plan：列出模型、命令、原子提交、依赖、文件、接口与验收。
- [x] 获得用户精确文本 `Plan Approved`。
- [x] 实现模板/注册表/WorldState 与深拷贝，验证 A1–A2。
- [x] 实现严格命令、路线和空间校验，验证 A3–A5。
- [x] 实现预检、幂等和同步准备/提交，验证 A6–A8。
- [x] 接入模块 1 部署与报告边界，验证 A9 和既有回归。
- [x] 完成导入、headless、文档和 CI 配置检查。
- [x] 回写实测证据、Plan-Execution Diff 与 Review。

## 18. Review Matrix

以下保留实施完成时的主会话自审记录；首轮独立同行评审见 §20，修复后的当前结论见 §21。

| 评审项 | 当前结论 | 依据/限制 |
| --- | --- | --- |
| Spec 清晰度与可验收性 | PASS（计划层） | §1–3、§14 明确已定规则、排除项及行为场景 |
| 文件与接口可执行性 | PASS（计划层） | §8、§12–13 列明模块 1 迁移和新文件；真实物理写回明确后置 |
| 原子性/分支/风险覆盖 | PASS（计划层） | §9–11、§15；prepare 与 activate 合同及后续物理验证范围明确 |
| Spec-Code Fidelity | PASS（本模块范围） | A1–A9 由六个组合场景覆盖；联络立即部署、报告删除旧回调；真实物理/感知仍后置 |
| Code Intrinsic Quality | PASS（本地） | 严格结构、隔离副本、最终候选验证、重入与激活故障门槛；两套测试共 245 条检查通过；代码自审完成 |
| 最终玩法及 Agent 授权 | OUT OF SCOPE | 只验证框架策略，不把测试权限开放给 Agent |

Readiness Verdict：GO。Plan Approval：Plan Approved。Implementation Verdict：PASS（本模块范围）。Overall Verdict：模块 2 可交接；不能据此批准真实物理、AgentGateway 或最终玩法。

评审必须分别报告：

1. 已实现框架能力：模块 0 工程壳、模块 1 时序内核，以及模块 2 纯数据、命令、校验、复制、同步接口和阶段门槛。
2. 已验证的范围：内存世界及命令服务、同步测试替身、真实 GameSession 集成；未形成可玩关卡。
3. 仅保留的后续接口：物理/感知、触发基线、完整 RESET、角色安全工具与真实 Agent。
4. 当前不对任何真实 Agent 开放本服务；踏板玩法授权已有决定，但尚无可调用的运行时接口。
5. 玩法未决项与模块 1 的 DTO/hit/报告桩风险仍单独保留，不能被本模块测试掩盖。

## 19. Resume / Handoff 与变更记录

- 当前工作目录：`D:\nekoToken\nekoToken-hackathon`；分支：`team/branch-1`。
- 当前阶段：REVIEW 完成；批准：Plan Approved；R1–R3 已修复并独立复核关闭，正式检查 81 + 223 项通过。下一任务须先确定运动/感知、角色安全工具或 RESET 的独立合同，不自动扩展模块 2 范围。
- 本会话原有文档修改全部保留；模块 0/1 的 Git 基线为 `73ace82`，不要把旧交接中“仍未提交”视为当前 Git 状态。
- 本轮保留先前全部文档改动，新增 world/ 七个脚本与测试，并修改 GameSession 的部署和报告合同；主场景仍为工程壳。验证完成后，用户已授权把模块 2 相关代码与文档整理为一次提交并推送；其他会话的模块 3A 文档及索引行不纳入本次提交。
- 继续时先读 git status、本文批准状态与相关接口；不得 git clean、删除现有改动或覆盖其他会话。Git 授权限本次模块 2 提交和推送，不包含后续模块或强制推送。
- 2026-11-27：完成门/灯退出、踏板进入后的 Research/Grill；追溯并替换联络延迟生效规则。
- 2026-11-27：用户确认同格一个踏板、无障碍叠放、实心固定设施、接近按键、出口触碰、四邻接、单点驻守、圆形视野及明确保持现状；进入 PLAN。
- Execute 前细化：内存字典采用基础值/数组的严格字段格式；角度统一使用弧度（0 朝右、正向朝下）。摄像头扫描状态用 heading 与 scan_direction 表示，不复制可推导相位；修改扫描区间时仅将越界 heading 限制到新区间内并保留扫描方向。机器人用 path_index、progress、travel_direction 与 transition 字典（为空或含 from_cell/to_cell/progress）表示巡逻和一次性衔接；参数策略不添加最终玩法数值。以上属于既有模型字段的工程落实，不增加 Agent 权限。
- Execute 审查修订：activate 从 void 改为 bool 完成确认。Godot 的脚本函数异常中断不一定中断调用者；缺少确认可能把未完成激活当作成功。该改动用于落实既定“程序错误停止模拟”要求，不增加场景回滚系统。SYNC_ACTIVATION_FAILED 是锁定服务的程序错误；普通 prepare 拒绝仍可用新请求重试。
- Plan-Execution Diff：activate 增加 bool 完成确认（理由见上一条）；end_contact/complete_dispatch 的缺省回调明确拒绝；摄像头统一使用 cell 字段；参数范围与安装约束存于模板规则，角色白名单存于服务 policy。测试 runner 增加场景完成检查，防止 Godot 中断测试后出现假通过。功能范围未扩大，未引入最终数值、权限、真实 Agent 或物理系统。
- 2026-11-27：完成代码、Godot 导入、245 条检查、仓库/链接/whitespace 检查及主会话自审，回写以上证据与后置边界。
- 2026-11-27：按用户要求完成三位独立子 Agent 的同行评审；主会话复核三个最小失败场景，更新结论为 PARTIAL，详见下节。
- 2026-11-27：用户授权修复；完成 R1–R3、正式回归及原评审者复核，当前认定更新为 PASS（模块 2 范围），证据见 §21。

## 20. 独立同行评审（2026-11-27）

本节保留首轮发现及当时结论；三个问题随后已按 §21 修复并关闭，不作为当前未解决项。

评审方式：三位子 Agent 分别检查世界模型、命令事务、阶段门槛与测试；主会话复跑正式测试并复核发现。评审没有修改运行时代码、正式测试或 CI，仅更新评审状态，复现脚本/日志放在被忽略的 tmp。没有提交或推送 Git。

正式回归：Godot 4.7.2 导入退出 0，SessionKernelTests 81 passed / 0 failed，WorldCommandTests 164 passed / 0 failed，runner 退出 0。三个新增探针均实际暴露现有测试未覆盖的行为，不能用原套件通过推翻这些发现。

| 编号 | 等级 | 发现、复现与影响 | 修复方向 |
| --- | --- | --- | --- |
| R1 | P2 | `DeviceRegistry.cell()` 只验证整数类型，`grid()` 转 Vector2i 后才用于边界检查。将踏板移到 `[4294967299,2]` 返回 APPLIED；注册表保留大数，但空间查询认为踏板在 `[3,2]`。地图尺寸和路径点存在同源表示范围问题。违反非法位置拒绝与权威坐标一致性合同。 | 转换前验证整数可由目标向量无损表示，再进行地图边界检查；覆盖命令、模板尺寸和路径点。无需自定玩法地图尺寸。 |
| R2 | P2 | `WorldState.from_snapshot()` 仅检查输入数字有限，转换到 Vector2 后未复验。`player_velocity=[1e100,0]` 被接受成 `(inf,0)`，之后 snapshot_copy 返回 null。违反有效世界可深拷贝合同。 | 对实际存入世界的向量验证转换结果仍有限；补原点/玩家向量的表示范围用例。无需自定速度玩法上限。 |
| R3 | P2 | 同批将已占用踏板 A→B→A，最终位置没变，但 MoveDevice 在处理中间候选时已清空基线。实测 occupants 从 `[0]` 变空、baseline_ready 变 false，结果 APPLIED、revision+1、同步准备调用一次。按 §9 的最终候选提交和 §10 的基线保留要求，此处应保持原运行状态。 | 完成候选配置后比较旧世界与最终位置，只对新增或最终位置改变的踏板失效基线；补 A→B→A 返回 UNCHANGED、无同步、基线保留的回归。 |

R3 是当前数据合同偏差，尚无真实感知系统，不能宣称已发生真实触发误报。R1/R2 需要超出引擎表示范围的数值触发，未发现正常地图数值导致同类故障，等级均为 P2。

代码定位：R1 为 `game/scripts/world/device_registry.gd:60–61,87–88`；R2 为 `game/scripts/world/world_state.gd:80–83`；R3 为 `game/scripts/world/world_command_service.gd:208–209`。

本机复现证据：

- R1：`tmp/peer_model_coordinate_repro.gd`、主会话复核日志 `tmp/peer-root-coordinate.log`，退出 1（预期拒绝，实际 APPLIED）。
- R2：`tmp/peer_model_finite_vector_repro.gd`、`tmp/peer-root-finite-vector.log`，退出 1（接受无穷向量且无法复制）。
- R3：`tmp/peer_root_roundtrip_repro.gd`、`tmp/peer-root-roundtrip.log`，退出 1（预期 UNCHANGED，实际 APPLIED 并清空基线）。
- 门槛正向证据：`tmp/peer_session_callbacks.gd/.log` 故意让 activate 内发生 GDScript 错误，确认联络仍暂停、revision 不变、换新请求的 KEEP_CURRENT 也不能绕过故障锁；部署重入被拒绝。

| 评审轴 | 当前结论 | 证据与限制 |
| --- | --- | --- |
| Spec 清晰度/边界 | PASS | 内存框架、未来接口、真实 Agent 授权与玩法未决项区分明确 |
| Spec-Code Fidelity | PARTIAL | R1/R2 破坏输入及复制合同；R3 未按最终候选保留踏板运行基线 |
| Code Intrinsic Quality | PARTIAL | 常规原子失败、幂等、旧分支拒绝和阶段故障门槛通过；三项 P2 待修复 |

首轮 Overall Verdict：未完全通过。未发现 P0/P1，当时要求修复 R1–R3 并补回归。该轮仅评审，后续修复和最终 PASS 见 §21；既有 Plan Approved 历史保留。

- [x] R1：拒绝不可表示的整数格坐标并补回归，独立复核关闭。
- [x] R2：拒绝转换后非有限的向量并补回归，独立复核关闭。
- [x] R3：按最终位置决定踏板基线是否失效并补回归，独立复核关闭。
- [x] 重新运行正式套件及新增用例，复核后更新最终结论。

非阻塞建议：正式测试可补真正的激活脚本中断场景；当前辅助断言函数为 void，局部脚本中断主要由 CI 日志扫描发现，可补完成标记。非法 transition/折返方向组合可补解码拒绝测试，目前不会由现有命令生成。

边界复核：已实现的是内存世界、命令、同步合同和会话门槛；真实运动/碰撞/感知、完整 RESET 仅为后续接口；服务没有开放给任何真实 Agent。权限、配额、数值及关卡仍是玩法决策。模块 1 的 payload 非严格 DTO、hit 依赖上游验证、报告内容测试为顺序桩三项风险仍保留，本轮没有扩展或修复它们。

## 21. 同行评审修复与重新认定

用户授权：执行 R1–R3 修复，然后重新认定。该轮继续既有模块 2 合同，不增加玩法权限或参数数值。

已落实修复：

- R1：在 DeviceRegistry.cell 的整数类型检查后验证 Vector2i 表示范围，使模板尺寸、设备锚点、路线和命令共用转换前校验；地图大小仍由模板决定。
- R2：新增 vector_point，为实际 Vector2 数据检查转换后有限性，应用于原点、玩家位置/速度及机器人位置；validate 复查已存入向量及首末格心，拒绝尺度计算溢出。保留 float64 参数区间的原有合法性规则，不将所有二元数值数组当成位置。
- R3：MoveDevice 仅累积候选位置，整批命令完成后才按旧/最终位置决定踏板基线失效；最终回到原位保留候选中已合法更新的基线，不能把同批删除的机器人占用引用恢复回来。
- 验证：将三个最小失败场景及相关正向边界加入正式 headless 套件，先确认失败基线，再通过原回归；原评审者独立复核修复，不以实现者自审替代。

实际代码文件：`game/scripts/world/device_registry.gd`、`world_state.gd`、`world_command_service.gd`、`level_template.gd`，以及 `game/tests/world_command_tests.gd`。同时更新现有文档的认定与测试计数；本轮没有再修改 GameSession、AgentProtocol、场景或 CI。

验证与证据：

| 检查 | 实际结果 |
| --- | --- |
| 修复前新增回归 | 内核 81/0，世界 190 passed / 28 failed，runner 退出 1；证明新增用例检出了原问题 |
| 最终 Godot 4.7.2 导入 | 退出 0，日志无脚本/解析错误 |
| 最终正式 runner | SessionKernelTests 81 passed / 0 failed；WorldCommandTests 223 passed / 0 failed；退出 0，无错误日志 |
| 覆盖增量 | 保留原六个世界场景，新增两个组合场景；世界检查从 164 增至 223，覆盖正负溢出、模板尺寸、实际向量/派生格心、正常数值及踏板最终位置 |
| R1/R2 独立复核 | 原两条失败探针均退出 0；另 9 项独立边界检查全部通过，保留 int32 端点、float64 参数上界、可表示大速度及正常平移/缩放 |
| R3 独立复核 | 原 A→B→A 探针返回 UNCHANGED、revision 0、基线保留；正式场景验证 A→B 仍失效基线，删除机器人处于批次前/中/后均不恢复已删占用 |
| 仓库及文档检查 | 1118 files、29 maintained documents、0 issues；68 documents 链接检查 0 错误；CRLF 兼容的 diff 检查及 GDScript 行尾检查通过 |

本机日志：`tmp/module2-fix-red.log`（失败基线）、`tmp/module2-fix-import.log`、`tmp/module2-fix-tests.log`；原评审者证据为 `tmp/peer_model_coordinate_after.log`、`tmp/peer_model_finite_vector_after.log`、`tmp/peer_model_fix_validation.log`、`tmp/peer_commands_r3_recheck.log`。这些是本机忽略目录中的证据，不属于可分发测试；所有关键回归已进入正式测试文件。

仓库文件计数包含期间由其他会话新增的模块 3a Spec；本会话未编辑该文件，也未因其出现扩展本轮实现范围。

重新认定由原模型评审者和命令事务评审者分别独立检查实际修补；第三位评审者负责新增正式回归，主会话执行失败基线和最终套件。没有用实现者自审替代复核。

| 评审轴 | 当前结论 | 依据与限制 |
| --- | --- | --- |
| Spec 与范围 | PASS | 无新增玩法数值、权限或新模块；表示范围检查只落实已有合法性合同 |
| Spec-Code Fidelity | PASS | R1/R2/R3 由正式回归与原失败探针复核关闭 |
| Code Intrinsic Quality | PASS（本地） | 共 304 项正式检查通过，修复未引入已发现的常规输入回归 |

Plan-Execution Diff：在原拟修复的向量字段守卫之外，补充实际存储向量及派生格心的有限性检查，防止有效模板经计算产生非有限坐标；未硬编码玩法地图或速度上限。新增内部辅助校验函数，既有对外调用签名保持一致。踏板基线按最终位置处理，候选中已删除的机器人占用引用不会恢复。

**Overall Verdict：PASS（模块 2 已批准范围）；R1–R3 CLOSED。** 真实物理、感知、完整 RESET 及 Agent 接入仍后置；模块 1 的 DTO/hit/报告桩风险仍保留。验证完成时尚未提交、推送或启动后续模块，远端 CI 未运行；后续用户已授权本模块一次 commit 和 push，实际提交与远端状态以 Git 记录为准。
