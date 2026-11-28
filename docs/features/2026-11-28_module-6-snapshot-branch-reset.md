# SDD Feature Spec：模块 6 周期快照、分支与双重 RESET

创建：2026-11-28（Asia/Shanghai）。分支：`team/branch-1`。

**阶段：REVIEW COMPLETE（6A／6B 均已按批准范围验收）。批准状态：Plan Approved（用户于 2026-11-28 明确批准）。** A0→B3 已执行；实际证据、独立复核与 Plan-Execution Diff 见 §8。7C 玩家助手持久记忆 UI 与模块 8 真实 Gateway／完整四轮体验不在本次通过范围内。

## 0. 依据与当前基线

优先级为用户最新裁决、[主设计 Spec §5、§8](../../PRELIMINARY_DESIGN_SPEC.md)、[现行机制基准 §5 及末尾迁移](../../侦测定位_机制草案.md)、[框架检查点 6](../minimal-framework-spec.md)、[模块 5 最新 §0／§P](2026-11-28_14-55_module-5-simulated-agent-guess-cycle.md)、当前代码。旧版模块 5 踏板限定 Plan 和上游文档中被末尾迁移取代的权限文字不是本模块依据。

模块 0–4B 已有各自范围的 Review。模块 5 最新 Feature Spec 已标 `REVIEW COMPLETE`，记录 Godot 共享套件 **920/920**、4A 独立套件 **114/114**、主场景及 Windows smoke 通过；已提供世界 schema 2、模拟系统 Agent、猜测／调度停点和安全历史，但没有真实周期快照与 RESET。模块 7A 摄像头联络切片在其范围 Review PASS；7B、7C 未获 Plan Approved。当前 Git 工作树仍有大量未提交的模块 5／7 改动，模块 6 Execute 前须复核实际接口与共享文件，不能以文档里的历史签名代替现行代码。

## 1. Goal 与已定规则

模块 6 要让当前单周期玩法产生真实、可恢复的周期起点；在系统猜测命中后由玩家选择局部回退或结束本轮；在一轮成功／最终失败后提供整轮重启的受控边界。任何恢复都由游戏程序执行，不由 Agent 宣称成功、直接写世界或修改额度。

已定玩法合同：

1. 初始配置完成、首周期行动开始前保存起点；以后每次未命中且继续本轮，系统调度完成、设备同步成功后，于 `CYCLE_START_PENDING` 保存下一起点，才恢复 `ACTION`。局部回退不能任意选时点，也不额外插入系统调度。
2. 仅定位命中后可选局部回退；整场共享三次，用一次扣一次。玩家放弃或次数耗尽则本轮失败。局部回退恢复起点的玩家位置／速度、设备及障碍实例、模拟时钟、目标进度、联络点 `used`、感知内部状态、待上传记录和当前有效报告。起点前已完成的目标或已使用联络点仍保持起点状态。
3. 初始轮加三次整轮重启，共四轮；每轮成功或最终失败后若仍有下一轮，沿同一地图按下一轮合法设备配置初始化。目标重新开始、联络点全部可用、新建有效报告序列。整场回退余额及已结算成绩不恢复、不补充。
4. 两名 Agent 各自已经接触的信息和经历保留，但只能保留其获准看到的内容；撤销分支的报告不能伪装成当前观察。旧分支／旧轮次／旧请求的回复不得改变新分支。玩家助手仍不能获得系统地图、报告、隐藏玩家坐标或越权设备信息。
5. 踏板在回退／重启后从恢复后的演员位置重新取得下一步的运动前采样；恢复本身不产生激活或即时报告。事件时 R、P、tick、配置与来源身份不因回退重算。

本模块不把三次、四轮等确定次数替换成试玩候选，也不自行决定下一轮设备的具体数值配置。

## 2. 现有接口核对与真实缺口

| 来源 | 已存在，可直接作为起点 | 模块 6 必须补上的接缝 |
| --- | --- | --- |
| 模块 1／5 `GameSession` | `RESET_CHOICE`、`CYCLE_START_PENDING`、`resume_cycle(snapshot_saved)`、session/cycle 快照和完整请求身份 | 没有可信的 session/cycle restore、扣减／放弃回退、整轮转换；`snapshot_saved` 目前只是布尔入参，须由实际保存成功的协调器调用 |
| 模块 2／5 `WorldState` | schema 2 `to_snapshot/from_snapshot` 覆盖实体运行状态、玩家运动状态、障碍模板／实例和高水位 | `WorldCommandService` 没有可信快照替换入口；场景节点与内存世界的恢复要一起验证和提交，不能借 Agent 命令批次伪装 RESET |
| 模块 3A／3B 场景和交互 | `RuntimeWorldView.build_from_world` 可重建场景；目标进度和联络点 `used` 位于世界实体运行状态 | 重建失败时不得留下半恢复的可运行场景；恢复后节点运动状态须与世界一致 |
| 模块 4A／4B 感知与报告 | `RuntimeSensingCoordinator.snapshot/restore` 覆盖视觉状态、buffer、目标待发事件、事件时 sidecar 和 `SystemAgentView` | 当前 restore 要求相同 `branch_id`；`SystemAgentView` 要求报告同分支连续。新分支继承起点前有效报告时，必须先明确祖先报告语义与验证规则 |
| 模块 5 系统 Agent | 模拟 Gateway、严格 context、猜测／调度流程、`SystemAgentHistory.snapshot` 和安全回执 | 历史当前只存猜测／调度，没有独立保存系统已收到的撤销分支报告；`GameRuntime` 也无恢复／撤销在途请求入口 |
| 模块 7A 玩家助手 | 联络窗口、待确认动作和会话内文本／回执 | 当前会话记录在每次打开时清空，没有跨 RESET 的助手持久记忆；7C 负责 UI／历史接入，不能以 7A 会话数组冒充完整两 Agent 记忆验收 |

依赖方向：

```text
0–4B 的世界、场景、交互、感知与报告
       + 模块 5 实际代码中的猜测／调度停点和安全系统历史
       └─ 模块 6：周期起点 → 局部回退／新分支 → 整轮重启边界
                         ├─ 模块 7C：玩家助手记忆、联络点与旧请求的双 RESET 集成
                         └─ 模块 8：真实 Gateway、完整四轮与整场验收
```

## 3. 已裁定切片边界与待细化的验收

### 6A：单轮周期快照与局部回退

在首次行动前和每次成功调度后保存完整起点。命中后展示玩家选择；确认回退才扣一次整场额度，按同一份不可变起点恢复世界、场景、session/cycle、感知与有效报告，生成新分支身份并废止旧请求；放弃或额度为零进入本轮失败。系统 Agent 已收到的旧分支信息作为历史保留。此切片可在确定性模拟系统 Agent、单轮灰盒中独立验收。

### 6B：整轮重启原语

从 `ROUND_END` 进入下一轮，保持地图布局，按受校验的下一轮配置建立新世界和首周期起点；重置目标、联络点与有效报告，保留整场额度、成绩和双方各自历史。用读取系统安全历史的确定性模拟系统策略提出合法配置并验证一次轮间转换；真实 Agent 策略、真实 Gateway 与完整四轮体验由模块 8 接入。6B 不得通过重建 `GameSession` 顺手丢掉跨轮身份高水位或已获知历史。

模块 6 自身的 Review 可分别标记 6A、6B 的实际通过范围。模块 7C 接入前，不称“两名 Agent 的 RESET 记忆与 UI”完整验收；模块 8 接入前，不称真实四轮整场完成。

## 4. 职责与数据流概览（精确接口见 §P；未批准）

```text
ACTION 起点：可信协调器从 WorldCommandService / GameSession /
RuntimeSensingCoordinator 取同一时刻的完整快照 → 验证并保存 CycleCheckpoint
→ 若为 CYCLE_START_PENDING，凭保存成功的结果调用 resume_cycle(true)

RESET_CHOICE：玩家选择 → GameSession 验证阶段与余额 → 协调器预检起点
→ 使旧请求失效，恢复 WorldState 与场景、session/cycle、有效报告和感知状态
→ 切换新 branch_id，保留 RunMeta 与各自的安全历史 → ACTION
```

- `GameSession` 独占阶段、轮次／分支／周期身份、回退选择门槛和结果；整场余额、成绩与 ID 高水位放在不随周期快照回滚的可信状态中。如何组织为 `RunState`／`ResetCoordinator` 留待 Plan 定名。
- `WorldCommandService` 仍是活动世界唯一写入口；RESET 使用程序专用的完整世界恢复入口，先校验候选和场景同步，再发布。不得把 RESET 伪造成 Agent 的 `WorldCommandBatch`，也不得靠直接改 `RuntimeWorldView` 使其与权威世界脱节。
- 感知／报告恢复必须区分**当前有效报告**与**历史上已交付给系统的报告**。有效报告恢复起点状态；撤销后缀进入持久、安全、带来源身份的系统历史。未发布 buffer 不进入系统历史。每条旧观察保持原事件字段，不重算或改写。
- `GameRuntime` 在恢复边界统一暂停泵、清理旧在途身份／临时拒绝回执／联络待确认动作，并以新身份重新启动；旧回调即使迟到也只能被丢弃。系统历史与玩家助手历史各自隔离，不能相互复制。
- 失败处理按 §P2 分级：预检或 prepare 拒绝保持原暂停状态、世界和余额；activate 故障锁住运行时并进入 STOP，不能继续运行半恢复世界。

## 5. Research 阶段的候选范围与可观察验收（以 §P 精确文件表为准）

本节保留 Research 时定义的验收场景；文件归属、目标签名和原子 Checklist 已在 §P3–§P5 收敛。模块 5 的 Review 现已完成，Execute 前仍须按 §P0 核对共享工作树的实际接口。

| 场景 | 可观察结果 |
| --- | --- |
| 首周期真实起点 | 初始配置、tick 0 感知状态与首批待发记录保存成功后才可行动；没有用常量 `true` 绕过快照门槛 |
| 调度后起点 | 新设备配置已同步，`CYCLE_START_PENDING` 仍冻结；保存新起点后进入 `ACTION`，下一步使用新配置，无额外猜测／报告 |
| 局部回退 | 在周期中移动玩家与机器人、调整摄像头／障碍／踏板、消耗联络点、推进目标、积累未发记录后命中；选择回退，所有可回滚状态与起点一致，余额减 1、历史不丢、新分支不接受旧回复 |
| 有效报告与旧历史 | 起点前已经发布的报告仍按其真实来源可用；撤销分支已发布的后缀只作带来源标记的历史，不混入新分支当前报告；未发布记录被撤销，旧 R/P/tick/配置不变 |
| 失败／耗尽 | 玩家放弃或三次已用尽后本轮失败；非法阶段选择、重复点击和坏快照不扣额／不产生部分恢复；故障时模拟保持暂停 |
| 整轮重启 | 一轮结束后用确定性合法配置开始下一轮；地图相同，目标和联络点重置，新报告序列独立，回退余额／成绩与安全历史保留；第四轮后无第五轮 |
| Agent 隔离 | 系统新请求只含获准的当前视图及带来源的系统历史；助手新会话不因 RESET 获得地图、系统报告、玩家隐藏坐标或旧目标句柄 |

## 6. G1–G5 裁定记录

### 6.1 先把三种转场分清（2026-11-28；“系统 Agent 失败”的含义已获用户澄清）

把“周期结束、下一周期开始的点”称为**检查点**。首周期在初始配置完成后也有一个检查点，虽然此前没有一个周期。按现行主 Spec：

```text
初始检查点 S0 → 周期 1 → 系统猜错、玩家未通关 → 合法调度 → 保存 S1 → 周期 2
周期 2 → 系统猜中 → 玩家选择局部回退 → 返回 S1，开启新分支（不再调度）
周期 2 → 系统猜中、玩家放弃／次数耗尽 → 本轮失败 → 下一轮初始检查点 S0'
完成目标并到出口 → 玩家本轮成功／系统 Agent 本轮失败 → 下一轮初始检查点 S0'（若恰逢猜测，先结算猜测）
```

用户明确澄清：**“系统 Agent 失败”指玩家成功到达终点并满足通关条件**，不指系统在某次猜测中未命中。因此单次猜错只推进到下一周期，不触发回退；玩家本轮成功后才按整轮规则进入下一轮。局部回退只返回**刚结束的当前猜测周期的起点**，不是更早或任意周期的点；整轮重启进入**下一轮的初始检查点**。

### 6.2 G1–G5：白话说明、裁定与难度

G1／G2 的玩法语义由主 Spec §8 的“有效报告回到起点、系统保留已接触历史”确定，用户已同意以下报告前缀、历史后缀及轻量分支元数据路线。具体 schema、签名和原子提交顺序留给 Plan；不能把这两个裁定扩大为整个 Plan 获批。

| 编号 | 白话问题 | 已裁定口径（实施仍待 Plan Approved） | 相对实现难度 |
| --- | --- | --- |
| G1（已裁定） | 回到 S1 后，S1 之前系统已经收到的报告还算不算当前分支的证据？ | **算。** 将检查点保存的有效报告前缀原样恢复，保留原 round/branch/tick；新行动用新分支身份。仅允许可信检查点记录的父子分支切换，不放宽成任意混合分支。还需处理检查点处可能已生成、但尚未上报的边界 tick 记录。 | **高**：现有报告批次、buffer、感知恢复和系统视图都假定同一分支。 |
| G2（已裁定） | 回退前系统在被撤销分支里已经看到的报告和做过的猜测／调度，要不要记得？ | **要。** 只把确实交付过、而现在不在有效前缀中的报告后缀归档为带原身份的旧分支历史；轮间重启时把上一轮已交付报告归档。猜测／调度历史继续只追加。未交付的 buffer 不进入记忆；旧历史不当当前观察，也不携带内部玩家坐标。 | **中高**：现有 `SystemAgentHistory` 只接猜测／调度，须扩安全 DTO 和请求投影；与 G1 合做可避免双份数据。 |
| G3（已裁定） | 下一轮初始设备配置由谁提出，模块 6 验收到哪一步？转场触发与目标检查点已按 §6.1 澄清。 | 模块 6 用读取系统安全历史的确定性模拟策略提出下一轮合法配置，游戏校验；真实 Agent 策略与完整四轮体验交给模块 8。猜错且玩家未通关时仍只调度并推进周期；玩家本轮成功（系统 Agent 本轮失败）或最终失败后才进入下一轮 S0'。 | **中高**：阶段转换、世界／场景重建与一份新的轮间结构化配置合同；真实模型再增加独立工作量。 |
| G4（已裁定） | 回退后玩家助手还记得此前聊过什么吗？ | **记得获准接触的对话、提案和安全回执。** 玩家侧单独存只追加日志，保留原分支标记；新联络是新会话，旧目标句柄、待确认令牌和迟到回复全部失效。模块 6 留接口，7C 做实际记录和 UI。 | **中**：跨分支身份／UI 投影与 7A 接线；不应拖进系统 Agent 日志。 |
| G5（已裁定） | 被撤销分支新建过的设备编号，后来能否分给另一台设备？ | **不重用新建编号。** 起点原有设备恢复原 ID；撤销分支用过的编号记在整场只增不减的分配高水位中，新分支／新轮新增设备取更大的 ID。历史仍用 round/branch 标来源。 | **低到中**：多一个持久高水位并在恢复时合并，需覆盖重复 ID 回归。 |

难度仅指当前 Godot 代码的相对改造量，不是试玩数值或工期承诺。G1／G2 是主要技术风险；若把旧报告全部改成新分支身份或把系统历史随世界快照回滚，代码可能较少，但会破坏已经确定的事件来源与 Agent 记忆规则。

### 6.3 G1／G2 的代价与已接受的取舍

**玩法代价。** 回退后的系统记得旧分支已收到的线索，会更容易猜到玩家重复使用的路线；这正是“RESET 不清除对手经验”的既定机制，但可能让有限三次回退显得更难。试玩需让玩家理解系统保留了什么，观察是否过度压制重复尝试。历史事件必须保留发生时间和来源分支，不能让系统把旧分支的无人观察当成新分支此刻的无人证明。

**工程代价。** 当前 `SystemAgentView`、`UnifiedReportBatch`、`ReportBuffer` 与 `RuntimeSensingCoordinator` 都有同分支校验；新分支报告周期号也可能与旧分支重复。检查点边界恰好生成但尚未上传的事件尤其容易在重分支时丢失、重复或错误改写来源。报告发布、系统记忆归档与恢复必须有一致的提交边界；错误快照或旧回调不能造成半恢复或历史泄漏。

**体量代价。** 四轮和三次局部回退限制轮数与分支次数，却不自动限制一轮内经历多少猜测周期；视觉报告的 R 格集合也可能较大。真实模型每次重发全部旧报告会增加等待与输入量。模块 6 保存准确、安全的已交付事实；模块 8 再设计带来源标记的受控历史投影／检索，不得为了省输入而悄悄删除“系统已经知道”的事实。

用户已同意 G1／G2 的**玩法语义**及较小的实现路线：`CycleCheckpoint` 保存有效报告前缀；可信分支元数据只记父分支与分叉点；RESET 时把撤销的已交付后缀追加到系统历史，整轮重启时归档上一轮已交付报告。新请求分别投影“当前有效报告”和“旧分支／旧轮历史”，避免同一报告在两栏无标记地重复。6A 首版不建立通用事件溯源框架。

可接受的验收底线：恢复后有效报告恰等于检查点前缀；已交付后缀只在历史；未交付记录不进入系统记忆；报告原 round/branch/tick/R/P/事件时配置不变；新分支可继续封批且边界事件恰好交付一次；旧请求及坏快照不改变世界、报告或历史。若这些条件在当前代码中不能同时通过，需回 Plan 调整数据表示，而不是削弱来源校验。

已定而无需重开：整场三次局部回退、四轮上限、只有命中可回退、放弃／耗尽即本轮失败、联络点 `used` 随起点恢复、历史记忆保留但不越权、无额外调度、旧请求失效。RESET 选择按钮的具体外观、原型设备数值和回退动画可后续试玩，不阻塞数据合同。

## 7. Research → Plan 状态记录

G1–G5 已获裁定，§P 已列出目标签名、快照 schema、原子 Checklist、失败顺序与验收命令，现提交用户审查。模块 5 已完成其范围的 Review；进入 Execute 前仍要复核现行共享接口与测试。只有用户明确 `Plan Approved` 后进入 Execute。

## P. 详细实施 Plan（2026-11-28；Plan Approved）

### P0. 执行边界与基线

本 Plan 仅覆盖 §3 的 6A／6B：确定性模拟系统 Agent、内存运行、真实灰盒场景。6A 先于 6B；每段结束单独验收，6A 不因 6B 未完成而标作整模块通过。真实模型／网络、正式轮间策略、四轮评分剧情、7B 机器人助手工具及 7C 玩家助手记忆 UI 不在本 Plan。模块 6 为 7C 定义历史接缝和旧令牌失效，实际助手历史写入／展示由 7C 完成。主设计 Spec 确定的三次回退、四轮上限在 `RunState` 中实现，不用原型值替代。

Execute 前复核 `git status`、模块 5 §P9 的 `REVIEW COMPLETE` 证据、7A 现行接口及 `game/scripts/**` 的当前签名；不重置、不清理、不覆盖共享改动。若模块 5／7 的在途修改使下述接口或安全白名单不再成立，先修订本 Plan 再继续。模拟轮间配置只使用 `PrototypeConfig.round_setup_policy()` 注入的可替换**测试 policy**：首个 fixture 最多一条针对已有摄像头 `scan_center` 的合法命令，供验证新配置确实生效；其额度和角度不升格为正式玩法规则。

### P1. 快照、整场状态与分支数据合同

`CycleCheckpoint` 为内存 plain-data 深快照：

```text
{schema_version:1,
 source:{round_id:int, branch_id:int, guess_cycle_id:int, simulation_tick:int, report_period_id:int},
 world:WorldState.to_snapshot(), session:SessionState.snapshot(), cycle:CycleState.snapshot(),
 sensing:RuntimeSensingCoordinator.snapshot(), active_report_count:int}
```

只在初始 tick 0 的感知初始化完成、或 `CYCLE_START_PENDING` 的调度／场景同步成功后捕获。捕获时无活跃请求、冻结猜测帧、未完成报告发布或在途 Agent 回调；`sealed_reports_in_guess_cycle=0`，三份 tick／round／branch／cycle 身份一致，`active_report_count == sensing.system_view.reports.size()`。快照不含系统／助手持久历史、整场回退余额、成绩、分支及实体 ID 高水位、Gateway 或 Node。调度后当前权威世界可以比系统最后一次**已发布**的公开配置更新；快照验证不得要求两者 revision 相等，更不能为了对齐而即时上报。

`RunState` 不随周期回滚：`remaining_local_resets=3`、`max_rounds=4`、`round_results:Array[{round_id,result}]`、`next_branch_id`、`next_entity_id`／`next_obstacle_id` 高水位，以及 `branch_edges:Array[{round_id,branch_id,parent_branch_id,fork_tick,fork_report_period_id}]`。初始分支是根，父 ID 为 0；局部回退生成新 child，整轮重启生成下一轮新根。`GameSession._next_request_id` 保持单调，不从 checkpoint 还原；已存在实体保留快照中的 ID，后续新实体从整场高水位继续分配。分支与报告的唯一身份至少使用 `(round_id,branch_id,report_period_id)`，不能只看周期号。

G1/G2 的最小表示：`SystemAgentView.reports` 保存当前有效祖先前缀及新分支报告，所有**已发布** batch 的原 round/branch/tick/R/P/事件时配置字节等价保留；系统历史只增加撤销的已交付后缀或已结束轮次的已交付报告，猜测／调度历史继续只追加。历史归档项严格为 `{kind:"archived_report",reason:"abandoned_branch"|"previous_round",batch:UnifiedReportBatch.to_data()}`，按原 round/branch/period 去重；6B 轮间配置的结构化提案与结果另以 `kind:"round_setup"` 的安全历史项记录。新请求的 `history` 投影与 `reports` 不无标记重复。公开 `branch_lineage` 只含上述分支关系和分叉 tick／报告期，不含玩家位置、contact 来源或内部高水位。系统视图增加 `view_schema_version=2`，通用 `AgentProtocol.PROTOCOL_VERSION` 与 7A 助手 context 不因本模块改变。

检查点处尚未上传、发生在分叉 tick 的 buffer／goal／sidecar 记录必须保留 R/P/tick/事件时设备配置。新分支提交时只对这些**未发布**记录重绑交付分支 ID，并在记录包装层添加原始 `origin_branch_id`；已发布 batch 绝不重绑。只能重绑与 checkpoint 完全相同、发生于 `fork_tick` 的待发记录，`origin_branch_id` 必须是已登记祖先；新分支首个正常批恰好交付一次。若实际快照含更早的待发 tick，捕获拒绝并回 Research 核对半开边界，不扩大通用校验器放行范围。

### P2. 原子恢复与轮间时序

**6A：** `RESET_CHOICE` 只接受玩家明确“回退”或“放弃”。余额为 0 时结算本轮失败；有余额且选回退时，先在私有候选中校验 checkpoint、当前有效报告以前缀精确匹配、历史归档后缀、child 分支、Session/Cycle、WorldState、Sensing、场景预制节点及 ID 高水位。准备阶段不改活动世界、余额、报告或历史。随后锁住物理／Agent 泵；`WorldCommandService` 使用程序专用 restore 入口和 `SceneWorldSyncAdapter.prepare/activate`，包含玩家位置／速度及机器人运行状态；成功后只做已验证对象的引用切换，清空命令幂等缓存、旧 pending context／拒绝回执／联络目标令牌，把余额减 1、branch 切到 child，恢复 `ACTION`。恢复本身不采样踏板、不生成报告；下一步从恢复后的演员格重新取运动前采样。预检或 prepare 拒绝保持 `RESET_CHOICE`、旧世界和余额；activate 程序故障进入 STOP，不能声称完整回滚或恢复行动。

**6B：** `ROUND_END` 先将本轮结果只记一次；第四轮直接到整场终态，不造第五轮。否则进入新 `ROUND_SETUP_PAUSED`（枚举追加在末尾，旧 phase 数值不移动），建立下一轮根分支与同一地图的干净 `LevelTemplate` 世界，目标／联络点重置，有效报告从空序列开始；已交付旧轮报告归档，整场余额／成绩／双 Agent 各自历史保留。确定性 `SimulatedRoundSetupAgent` 仅收到新轮公开世界、系统安全历史、可替换 policy 和新身份，返回 `{context,status,payload:{mode,commands}}`。首个 fixture 只调整已有摄像头扫描中心，验证新轮配置与旧轮不同且合法；不引入正式轮间额度裁决。程序严格解析并在**临时** `WorldCommandService` 上以 `source="round_setup"`、`ROUND_SETUP_PAUSED` 和单独 fixture policy 校验／提交，取得完整候选世界；不让模拟文本或 Agent payload 直接写活动世界。然后按 6A 的完整场景恢复通道一次发布候选，初始化新轮 tick 0 感知；`GameSession.complete_round_setup` 先进入 `CYCLE_START_PENDING`，保存 S0' checkpoint 并记录安全的轮间提案／结果后才调用 `resume_cycle(true)` 恢复 `ACTION`。非法提案／同步失败停在暂停或终止 fault，不自动 KEEP。真实轮间 Gateway 和正式权限由模块 8 接入同一严格 DTO 接缝。

### P3. 精确文件变化（获批后；不提前执行）

| 切片 | 文件 | 变更 |
| --- | --- | --- |
| 6A 新增 | `game/scripts/core/cycle_checkpoint.gd`、`game/scripts/core/run_state.gd`、`game/scripts/runtime/reset_coordinator.gd`、`game/scripts/agents/player_assistant_memory_port.gd` | P1 schema、整场不可回滚状态、检查点捕获与候选恢复编排；玩家侧历史 port 的 fake 用于 6A 契约测试 |
| 6A 会话／世界 | `game/scripts/core/session_state.gd`、`game/scripts/core/cycle_state.gd`、`game/scripts/core/game_session.gd`、`game/scripts/world/world_command_service.gd` | 严格还原候选、命中放弃结算、保留 request 高水位、程序专用世界恢复和幂等缓存失效 |
| 6A 场景 | `game/scripts/runtime/runtime_world_view.gd`、`game/scripts/runtime/player_controller.gd`、`game/scripts/runtime/scene_world_sync_adapter.gd` | 完整场景差量预制、玩家位置／速度同步及失败锁定 |
| 6A 报告／历史 | `game/scripts/runtime/runtime_sensing_coordinator.gd`、`game/scripts/sensing/report_buffer.gd`、`game/scripts/sensing/sensing_report_batch.gd`、`game/scripts/reports/unified_report_batch.gd`、`game/scripts/agents/system_agent_view.gd`、`game/scripts/agents/system_agent_history.gd`、`game/scripts/agents/agent_protocol.gd` | 可信分支谱系、祖先批、分叉 tick 未发记录、已交付后缀归档和安全请求投影；默认旧 DTO 路径继续严格同分支 |
| 6A 运行时／联络 | `game/scripts/runtime/game_runtime.gd`、`game/scripts/runtime/contact_session_controller.gd` | 起点停点、RESET 选择、旧请求／提案失效；只接历史 port，不实现 7C 记忆 UI |
| 6B 新增 | `game/scripts/agents/simulated_round_setup_agent.gd` | 读取安全历史的确定性轮间模拟策略 |
| 6B 协议／配置 | `game/scripts/core/session_phase.gd`、`game/scripts/core/game_session.gd`、`game/scripts/world/world_command_batch.gd`、`game/scripts/world/world_command_service.gd`、`game/scripts/agents/agent_protocol.gd`、`game/scripts/runtime/prototype_config.gd` | 新 phase/source、严格轮间提案与独立 fixture policy；不赋予系统任意地图命令 |
| UI／验收 | `game/scripts/main.gd`、`game/scenes/main.tscn`、`game/tests/run_tests.gd`、`game/tests/module6_checkpoint_tests.gd`、`game/tests/module6_reset_tests.gd`、`game/tests/module6_round_tests.gd`、`game/README.md`、`docs/features/2026-11-28_module-6-snapshot-branch-reset.md` | RESET 选择与轮间状态、独立 suite、运行命令、验证证据与 Review 回写 |

`game/scripts/world/world_sync_adapter.gd` 保持现有接口。`SceneWorldSyncAdapter.prepare` 从已验证候选保存玩家位置／速度与待替换节点；`activate` 经 `PlayerController.restore_motion_state` 应用运动状态并清空旧触碰 ID，再发布候选世界。不得顺带实现 7B、7C UI、真实模型或正式平衡数值。

### P4. 公开签名目标（本 Plan 新增／修改的入口）

```gdscript
static func CycleCheckpoint.capture(world: WorldState, session: GameSession, sensing: RuntimeSensingCoordinator) -> CycleCheckpoint
static func CycleCheckpoint.from_data(data: Dictionary) -> CycleCheckpoint
func CycleCheckpoint.to_data() -> Dictionary
func RunState.snapshot() -> Dictionary
func RunState.prepare_local_fork(checkpoint: CycleCheckpoint, current_world: WorldState) -> Dictionary
func RunState.prepare_next_round(result: int) -> Dictionary
func RunState.accept_prepared(prepared: Dictionary) -> void
func GameSession.prepare_cycle_restore(checkpoint_state: Dictionary, checkpoint_cycle: Dictionary, new_branch_id: int) -> Dictionary
func GameSession.accept_cycle_restore(prepared: Dictionary) -> void
func GameSession.decline_local_reset() -> bool
func GameSession.begin_round_setup(next_branch_id: int) -> Dictionary
func GameSession.complete_round_setup(context: Dictionary, result: WorldCommandResult) -> bool
func WorldCommandService.restore_trusted_snapshot(world_data: Dictionary, expected_revision: int, min_next_entity_id: int, min_next_obstacle_id: int) -> Dictionary
func PlayerController.restore_motion_state(position: Vector2, velocity: Vector2) -> void
static func RuntimeSensingCoordinator.from_cycle_checkpoint(data: Dictionary, restored_world: WorldState, new_branch_id: int, lineage: Array[Dictionary], fork_tick: int) -> RuntimeSensingCoordinator
func ReportBuffer.rebranch_checkpoint_pending(new_branch_id: int, origin_branch_id: int, fork_tick: int) -> bool
static func SystemAgentHistory.from_snapshot(data: Dictionary) -> SystemAgentHistory
func SystemAgentHistory.append_archived_batches(batches: Array[Dictionary], reason: String) -> bool
func SystemAgentHistory.append_round_setup(entry: Dictionary) -> bool
static func AgentProtocol.make_round_setup_request(context: Dictionary, view: Dictionary, policy: Dictionary) -> Dictionary
static func AgentProtocol.parse_round_setup_response(raw: Variant, expected_context: Dictionary) -> Dictionary
static func SimulatedRoundSetupAgent.respond(request: Dictionary, fixture: Dictionary) -> Variant
func ResetCoordinator.capture_initial_checkpoint() -> bool
func ResetCoordinator.complete_cycle_start() -> bool
func ResetCoordinator.choose_local_reset() -> bool
func ResetCoordinator.decline_local_reset() -> bool
func ResetCoordinator.advance_round() -> bool
func ResetCoordinator.get_run_snapshot() -> Dictionary
func ContactSessionController.invalidate_for_branch_change() -> void
func PlayerAssistantMemoryPort.snapshot() -> Dictionary
func PlayerAssistantMemoryPort.on_branch_change(context: Dictionary) -> bool
func GameRuntime.configure_reset(coordinator: ResetCoordinator) -> bool
```

`prepare_*` 只构造并校验候选，不发布状态；`accept_*` 只交换已验证数据，不能再有 I/O／可拒绝校验。`restore_trusted_snapshot` 只由可信协调器调用，不在 Agent 工具／动作白名单内，预检与 SceneSync prepare 失败时不改世界；activate 故障锁住运行时。`SystemAgentView.restore/append_batch`、`ReportBuffer.restore/seal`、`UnifiedReportBatch.from_data` 保持现有公开签名，内部增加严格的 `view_schema_version`／`branch_lineage` 与可选记录包装层 `origin_branch_id` 验证；旧无谱系输入继续按同分支规则验证，不将其自动解释成新分支祖先。若实现证明必须扩展签名，先在本 Plan 回写变更和调用点，再 Execute。

### P5. 原子 Checklist（获批后按顺序执行，未做保持空）

- [x] **A0 基线**：复核模块 5／7 共享文件及当前 suite；记录 `git status`、现行签名和正式测试结果，保留所有未提交改动。2026-11-28 当前共享 suite 920/920，日志 `tmp/module6-baseline-tests.log`；工作树保留现有模块 5／7 未提交改动。
- [x] **A1 快照红测**：先写 S0／S1 捕获、深拷贝、跨组件身份不一致、错误 schema、发布前后公开配置不同步但合法、ID 高水位与预算不回滚的失败合同测试。
- [x] **A2 快照实现**：实现 `CycleCheckpoint`、`RunState` 和 `GameSession` 候选还原；初始感知完成后才捕获 S0，调度成功仍暂停，捕获 S1 后才调用 `resume_cycle(true)`。
- [x] **A3 谱系／历史红测**：写有效祖先前缀、旧分支已交付后缀归档、重复周期号区分、未发 buffer 不归档、分叉 tick 边界记录恰交付一次、任意混合分支及历史越权字段拒绝的失败用例。
- [x] **A4 谱系／历史实现**：增加严格 branch_lineage、可选 `origin_branch_id`、安全历史归档及请求投影；旧模块 4B／5 同分支路径保持通过。
- [x] **A5 原子恢复红测**：真实灰盒中改变玩家速度／位置、机器人中途进度、摄像头扫描、2×2 障碍、目标进度、联络点 used、踏板与待发记录；验证坏快照／SceneSync prepare 拒绝不改变任何活动状态，activate 故障 STOP。
- [x] **A6 6A 实现／验收**：实现可信世界＋场景还原、感知候选、RESET 选择 UI、余额扣减、旧请求／目标令牌失效；成功恢复后下一物理步重新采样而无即时报告；6A 专项与共享回归全绿。
- [x] **B1 轮间红测**：成功与最终失败各触发一次下一轮；第四轮不生成第五轮；旧轮报告归档、目标／联络点清零、余额／成绩／历史保留；非法轮间结构化提案不改变活动世界。
- [x] **B2 6B 实现**：追加 `ROUND_SETUP_PAUSED`，严格 DTO 和独立 fixture policy；模拟系统策略仅读公开新轮世界与安全历史，临时服务验证候选，真实场景一次发布，tick 0 感知、S0' 捕获后 ACTION；轮间提案／结果入系统安全历史。
- [x] **B3 全面验证与 Review**：按 §P6 完成运行证据、代码与 Spec 三轴 Review、Plan-Execution Diff；仅实际通过的 6A／6B 范围标 PASS，不把 7C／8 称为完成。

### P6. Validation Plan 与回炉条件

每个 A/B 实现前保留相应失败合同日志于 `tmp/module6-red-*.log`，实现后运行 `--module6-only`、相关 4A／4B／5／7A 套件。最终顺序：Godot 4.7.2 `--headless --path game --import`；`--script res://tests/run_tests.gd` 完整共享 suite；`--script res://tests/run_sensing_tests.gd` 独立 4A；共享 runner `-- --fail-probe` 须退出非零；真实 `main.tscn` 120 帧 smoke 检查 S0 和正常 miss 后 S1；另由确定性集成用例分别驱动命中 RESET 选择、回退与下一轮；Windows Desktop release 导出并运行主场景 smoke。再运行 `python -m unittest discover -s tests -v`、`python scripts/check_repository.py`、`python scripts/check_project_links.py --all`、`git -c core.whitespace=cr-at-eol diff --check`。各自记录退出码、suite 计数、日志路径及有意注入的 fault；不复用模块 5 的 920/920 作为模块 6 完成证据。

若 checkpoint 不能在边界保存完整待发记录、分支混合必须放宽任意来源校验、系统历史会暴露未交付报告／隐藏状态、世界与场景无法避免 prepare 阶段部分发布、轮间配置需要扩大已定 Agent 权限，立即停在对应 A/B 点回 Research／Plan；不靠自动 KEEP、改写旧记录或跳过 SceneSync 过关。

### P7. Plan 自检、审批与 Resume

Execute 后的 Plan-Execution Diff 按每个 A/B 项记录：计划文件与签名、实际文件与签名、偏差及理由、对应失败合同和通过证据、仍未满足的验收；无偏差也写“无”。任何影响 G1–G5、Agent 权限或恢复原子性的偏差，先暂停并回到 Plan 审查。

Spec 完成度：G1–G5、6A／6B、7C／8 接缝、schema、文件表、签名、原子 Checklist 和验收均已列出。Plan 于 2026-11-28 获用户明确批准；A0→B3 已完成，Review 结论见下节。

Resume：当前 phase=`REVIEW COMPLETE`，approval=`Plan Approved`，6A／6B 均已在确定性模拟、内存规则与真实灰盒场景范围通过。后续接 7C 玩家助手持久记忆 UI 和模块 8 真实 Gateway／整场体验；本模块未提交或推送 Git。

## 8. Review 与验证证据（2026-11-28）

### 8.1 实际运行结果

- Godot 4.7.2 headless import 退出 0，日志 `tmp/module6-final-import.log`。
- `--module6-only` **25 passed / 0 failed**：Checkpoint 4、Reset 6、Reports 5、RoundProtocol 4、Scene 3、Round 5。覆盖 S0/S1、非零同一起点连续两次回退、第二轮回退、prepare／activate 故障、已交付后缀归档、分叉 tick 待发记录、成功／失败转轮、第四轮终止及非法轮间响应。
- 完整共享 runner **959 passed / 0 failed**，日志 `tmp/module6-final-tests.log`。其中既有套件与并行模块 7 当前改动也全部通过；该总数是本次工作树结果，不回写为历史模块 5 的证据。
- 独立 4A runner **114 passed / 0 failed**，日志 `tmp/module6-final-sensing.log`；`--fail-probe` 按预期退出 1，日志 `tmp/module6-fail-probe.log`。日志中的 `GAME RUNTIME FAULT` 均为测试有意注入的拒绝、超时或同步故障。
- 主场景 120 帧 smoke 与 Windows Desktop release 导出程序 120 帧 smoke 均退出 0，输出既有 READY 标记并实际经过调度后的 `CYCLE_START_PENDING`／快照恢复接缝；日志 `tmp/module6-main-smoke.log`、`tmp/module6-export.log`、`tmp/module6-export-smoke.log`。导出文件为 `tmp/module6-review-windows.exe` 和对应 `.pck`。
- Python unittest **13/13**；`check_repository.py` 0 issues；`check_project_links.py --all` 0 broken；CRLF 兼容 `diff --check` 退出 0。

### 8.2 独立复核

只读独立审查发现两项专项测试未覆盖的阻断路径：旧轮 `branch_lineage` 混入当前视图导致第二轮 RESET 被拒绝，以及同一非零检查点连续分叉时父分支锚点报告不存在。实现已改为只投影当前轮谱系，并允许同一分叉点创建的合法分支链；新增第二轮 RESET、非零同一起点连续两次 RESET 及后续封批测试。原审查者复核确认两项关闭，未发现新的同类高严重度阻断缺陷。

### 8.3 Plan-Execution Diff

- 计划中的核心文件与公开入口均已落地；测试拆分为 `module6_round_protocol_tests.gd`、`module6_scene_tests.gd` 和端到端 `module6_round_tests.gd`，并保留中断时已有的测试文件，不强行改名。
- `SceneWorldSyncAdapter` 只有可信快照恢复传入 `restore_player=true` 时才应用玩家位置／速度。普通 Agent 部署继续保留实时玩家姿态，修复完整回归中发现的普通地形部署误传送问题；RESET 的原子 prepare／activate 语义不变。
- 旧 `SystemAgentView` 数据继续走同分支校验；设置可信谱系后才升级为 schema 2。目标待发记录在内部快照中携带可选来源字段，封批时统一输出 `origin_branch_id` 包装，不改写已发布事实。
- 轮间恢复合并旧世界的实体／障碍 ID 高水位；当前系统视图只接收当前轮谱系。这些是实现缺口修复，不改变 G1–G5、Agent 权限或原型数值。
- 未扩大范围：没有真实网络模型、正式轮间策略、完整四轮剧情／评分体验或 7C 玩家助手历史 UI；`PlayerAssistantMemoryPort` 仍只是隔离接缝。6A／6B 可标记 REVIEW COMPLETE，不据此宣称模块 7C／8 或十分钟试玩完成。
