# SDD Feature Spec：模块 4A 纯数据感知与报告内核

层级：Feature Spec。创建：2026-11-27 23:31（Asia/Shanghai）。目标基线：模块 0–2 的干净工程；并行开发时使用独立 worktree 或干净副本。

**阶段：REVIEW PASS（4A 纯数据范围）。Plan Approval：Plan Approved（用户于 2026-11-28 明确批准 4A）。Execute：已完成。** §21 是 4A 实施合同；4B 后来单独获 Plan Approved 并通过其真实运行时范围 Review，不属于本文件的 4A 验收。

**当前合同摘要：** 4A 是不依赖 3A/3B 的纯数据内核。玩家单物理 tick 实际位移必须小于且通常远小于一格；程序每 tick 检查视觉与踏板，但不使用 ActorTrack。视觉经“连续圆形/扇形与格子正面积重叠生成候选 → supercover 格心线段严格遮挡”得到事件时可靠格集合 R。每条观察携带 R，同一设备同一 tick 只有发现/未发现/无法确定一种结果。报告生成采用“首次发现或目击格变化补报、可见转不可见补一条完整观察、每批末强制完整观察”，持续同格可见不逐 tick 重复；长度 N 的批次末是 `end_tick-1`，记录周期号由 `floor(event_tick/N)+1` 校验，所有记录按原 tick 在正常边界统一交付。踏板使用本步临时 `previous_actor_cells` 与 candidate 比较，前外后内匿名触发，提交成功后才发布；遗留 occupants 字段不读取或写入，无部署基线。4A 只生成设备报告包，不接目标事件、真实运行时、Agent、RESET 或共享 CI；目标事件由 4B 统一合批。

§3–16 保留为 Grill 和方案推导历史，其中 ActorTrack、逐感知步全量上传、连续可见多边形、无 R 的正面记录及两条生成规则等被后续修订取代，不作为实施合同。实施以本摘要、§17 的已确认视野/遮挡合同、§18 的 3A 核验和 §19–20 的 occupants 裁决为准。

用户已确认两项原子时间口径：首轮在 tick 0 做一次完整视觉观察；同一设备每个 tick 最多一条视觉记录，若状态变化发生在批次最后 tick，该记录同时充当批次末完整观察，不再重复。首轮和后续踏板判定只使用运动前后演员格，无需 occupants 初始化或部署写回。

## 1. Goal、当前任务单元与独立完成定义

最终目标是为模块 4 提供一个不依赖模块 3A/3B 的纯数据内核：根据显式世界、设备、格子采样和时间输入，生成视觉观察、匿名踏板激活及设备报告批次，并由独立 headless runner 验证。

当前任务单元仅覆盖人工构造 fixture 上的确定性逻辑。独立完成的定义是：

- 从模块 0–2 干净基线出发，只新增 4A 文件即可导入和运行独立测试。
- 不引用、不修改模块 3A/3B，不修改模块 1/2、共享 runner、主场景或 CI。
- 证明视觉、踏板、原始记录和感知批次的既定纯数据语义。
- 不宣称真实物理、运行时接线、部署写回、真实暂停、目标事件生成、Agent 视图、RESET、统一 CI 或真实场景性能已经通过。

## 2. Requirement Sources / 已核实事实

- [现行设计 Spec](../../PRELIMINARY_DESIGN_SPEC.md) §4–8、§11：视觉、踏板、上报、信息边界和待验收场景。
- [机制基准](../../侦测定位_机制草案.md) §2–5：逐 tick 内部检测、状态变化与批次末观察、R/P 语义；踏板匿名进入事件；部署不触发；统一批次。
- [最小游戏框架 Spec](../minimal-framework-spec.md) §2–8：同一候选世界、报告边界、Agent 视图及模块 4 检查点。
- [模块 3A Spec](2026-11-27_22-25_module-3a-runtime-scene.md) §8、§11：运动 → 交互 → 感知 → 单次提交 → GameSession → 封批/视图的运行时顺序。
- [模块 3B Spec](2026-11-27_22-51_module-3b-interactions.md) §4、§7：目标领域事件及后续报告衔接。
- `WorldState` 已提供地形、连续玩家坐标、格坐标转换和整格遮挡查询；没有 tick 内运动轨迹。
- `DeviceRegistry` 已提供摄像头 heading/FOV、机器人连续位置和踏板 occupants/baseline_ready。
- `WorldCommandService` 在新增或实际移动踏板后设置空 occupants 和 baseline_ready=false。
- `ReportBoundary` 已提供报告身份、1 基 report_period_id 和半开窗口边界。
- 当前 `CycleState` 只有时钟和计数，没有待上传记录或有效报告集合。

干净基线证据：从当前 HEAD 导出模块 0–2 工程到 `tmp/module4a-independence-baseline-884`，Godot 4.7.2 导入成功，SessionKernelTests 81/81、WorldCommandTests 223/223 通过。该证据只证明独立基线可运行，不是 4A 验证。

## 3. In Scope / Out of Scope

### In Scope

- 4A 自有的严格 plain-data DTO、深拷贝和输入校验。
- 摄像头扇形和机器人圆形视觉的纯数据判定及可靠格集合 R。
- 有人、可靠未检测到、无法确定的记录语义。
- 使用 `previous_actor_cells` 与 candidate 的踏板进入/离开检测；不使用 ActorTrack，不读写 occupants。
- 视觉/踏板原始记录 buffer、深拷贝快照和感知批次封存。
- 独立 fixture、独立 suite 和独立 SceneTree runner；失败必须返回非零。

### Out of Scope

- 真实 Godot 节点、物理运动、扫描推进和场景显示。
- GameRuntime、WorldStepResult、commit_runtime_step、WorldCommandService 或活跃 WorldState 写入。
- occupants/baseline_ready 的清理、部署写回或兼容迁移。
- 目标操作事件生成、3B 集成、AgentProtocol、Agent 视图和猜测。
- GameSession/CycleState 修改、局部或整轮 RESET。
- 共享 run_tests.gd、CI、正式数值、最终模型 payload 大小和真实场景性能。

## 4. Grill：进入 Plan 前必须关闭的 P0 问题

### G1. 可靠覆盖区域 R 的几何算法尚未选定

风险最高。格心可见不能推出整格可见；有限采样也不能无条件证明整格无遮挡。若把部分可见格全部写入可靠无人 R，会错误排除偏心玩家。

必须在 Plan 前选择并写明：

- R 是连续多边形、矩形集合、格集合，还是实际检查过的射线/扇区集合。
- 若用格集合，如何保守证明整格可靠可见。
- 遮挡边缘、墙角接触和部分覆盖如何处理。
- 正面发现时是否同时报告可靠负面子区域，还是只报告 D 与必要上下文。

建议：优先研究保守欠近似，宁可将不确定部分留在 UNKNOWN，也不扩大可靠无人范围。没有明确算法前不能写几何实现 Plan。

### G2. 玩家目标体积和摄像头感知原点未固定

当前草案曾写“玩家按点检测”和“D 可用所在单格”，它们只能是 fixture 决定，不能冒充正式玩法决定。墙装摄像头还缺少感知原点相对安装格/墙面的明确公式；原点错误可能导致支撑墙自遮挡。

需固定：点目标或体积目标、墙装/顶装原点、角度零方向与弧度、边界 epsilon、FOV/视距端点是否包含、支撑墙处理。后续场景显示必须复用同一纯数据 helper。

### G3. ActorTrack 的合同仍不完整

只比较上一/当前 WorldState 会漏掉单 tick 外→内→外；直线起终点插值也不能代表真实滑动折线。ActorTrack 是 4A 独立检测多次进入的必要输入，但还需定义：

- 玩家内部 key=0、机器人 key=实体 ID 的合法性和唯一性。
- 单点驻留轨迹是否合法；空轨迹、非有限点、重复点如何处理。
- 首点与上一权威位置、末点与当前权威位置是否必须一致。
- 同 tick 多个事件如何保存确定顺序；是否需要 segment_index/event_ordinal。
- 轨迹校验失败是否整步拒绝，禁止部分记录和状态更新。

4A 只消费人工轨迹；真实轨迹采集仍属于 4B。

### G4. 踏板基线与状态更新原子性需固定

部署基线必须取部署后、恢复运动前的快照，不能首次感知时用运动后位置懒初始化。4A 可纯函数计算基线，但不能宣称真实写回完成。

需固定：初始轮是否复用同一初始化函数；baseline_ready=false 时 advance 的错误；输出 plate_state_updates 的字段；多函数输入非法时是否无任何部分输出。occupants 属于内部状态，不得混入匿名报告。

### G5. 多演员、多进入事件的语义需明确

机制要求玩家或机器人从外进入均产生记录，原始记录不去重。因此两个演员同 tick 进入同一踏板应产生两条匿名记录；同一演员同 tick 两次进入也产生两条。

occupants 应按演员分别跟踪：一个演员离开而另一个仍在格内，不应错误清空全部占用。测试需覆盖同格多演员、交叉轨迹、同 tick 离开/进入次序和匿名重复记录。

### G6. 视觉记录的“每步一条”与区域结构存在歧义

一个设备在一个感知步可能同时具有正面 D、可靠负面 R 和未知区域。当前草案没有确定：

- 每设备每步严格一条记录，还是允许多个区域记录。
- 正面发现时 R 是否保留，以及未知原因如何表达。
- disabled 设备、无可靠覆盖和完全遮挡时是 UNKNOWN 记录还是无记录。
- UNKNOWN 是否带区域；如何避免把“视野外”误写成整个地图的负面事实。

需先确定记录基数和互斥/组合规则，再定 DTO 和测试。

### G7. 感知批次是否接收 external_records 是范围分叉

统一玩法批次最终还含目标操作事件，但 4A 不接 3B。直接接受未定义 payload 的 external_records 会造成严格 DTO、信息边界和排序语义不完整，也可能把 3B 未决字段提前塞入 4A。

两个可选收敛方向：

1. 4A 只产出 `SensingReportBatch`，统一批次组合留到 4B；独立边界最干净。
2. 4A 定义严格的外部记录 envelope 和 validator，再测试人工目标记录；工作量与耦合更高。

在选定前，不得宣称 4A 已完成“统一 ReportBatch”。

### G8. tick、report_period_id 与首周期语义需逐项对齐

ReportBoundary 使用 1 基 report_period_id；period_for_event_tick 返回 0 基索引。运动完成 tick N+1 后的感知应记 N+1，封存严格选择 start_tick <= event_tick < end_tick。

还需解释首个窗口：若没有 tick 0 的初始感知，首批 [0,N) 只含完成 tick 1…N-1 的记录，完成 tick N 的记录留到下一批。是否需要 tick 0 感知属于运行时集成语义，但 4A fixture 必须明确并能测试，不能用示例掩盖 off-by-one。

建议记录创建时不凭调用方随意写 report_cycle_id；由可信上下文生成并在封批时校验归属。最终字段归属仍需在 DTO 合同中明确。

### G9. 错误、隐私和快照边界未形成统一规则

需定义非法身份、负 tick、非有限轨迹、缺失基线、重复 actor、非法外部记录和坏快照的结构化错误；失败不得返回半批记录或部分状态更新。

需要区分内部与外部数据：ActorTrack、真实玩家位置、occupants actor key 只能短暂存在于可信输入/内部状态，不能进入观察记录、批次、错误回执或 buffer 快照。buffer 不应保存 ActorTrack 或玩家连续坐标。

### G10. “独立完成”需要可执行检查，而不是口头边界

独立 runner 必须有失败探针和完成计数。还应验证在干净模块 0–2 副本中只加入 4A 文件即可运行，避免主工作树半成品脚本影响导入。

共享 runner、Feature 索引和 CI 登记属于后续集成。4A 独立通过不等于总测试入口已覆盖。

## 5. P1 风险与测试缺口

| 风险 | 需要的控制或测试 |
| --- | --- |
| 浮点边界和角度环绕 | 手写预期覆盖 FOV 边界、±π 环绕、视距端点、墙角接触、重复点和零长线段；统一 epsilon，不能用过宽容差制造目击 |
| 测试 oracle 与实现同源 | 关键几何、批次窗口和穿越案例使用人工计算预期，不只比较函数自生成快照 |
| 报告体量膨胀 | 4A 记录结构测试和简单规模统计；不借“无压缩”规则之外偷偷去重，也不宣称真实模型等待已验证 |
| 深拷贝假隔离 | 修改原 WorldState、轨迹、记录、批次和快照后互不影响；覆盖嵌套数组/字典 |
| 集成时接口漂移 | 4A 自有 DTO，不引用 3A 类型；4B 单独编写 ActorTrack 采集和 plate_state_updates 应用适配器 |
| 范围膨胀 | 不在 4A 加自动寻路、扫描推进、Agent 推理、RESET、真实暂停或通用几何框架 |
| 算法复杂度低估 | 可靠 R 的保守几何、折线跨格和遮挡边缘应先做最小探针；未探针前不把难度定为低 |

## 6. 当前 Done Contract 草案（待 P0 关闭后确认）

- 干净模块 0–2 工程仅新增 4A 文件即可导入，独立 suite 和 runner 全部通过，失败探针返回非零。
- 视觉测试证明遮挡/视野外不形成虚假可靠无人，连续观察不去重，旧 R/D 不随新配置重算。
- 踏板测试证明部署不触发、离开后重进、停留不重复、单 tick 穿越、同 tick 多事件、多演员匿名及状态迁移正确。
- 批次测试证明半开窗口、1 基/0 基编号转换、边界留批、空批、重复记录、稳定顺序和深拷贝。
- 所有输出不含玩家连续坐标、联络来源或踏板触发者身份；非法输入不产生部分结果。
- Spec 明确区分 fixture 参数、4A 纯数据验收和 4B 集成验收；没有将独立通过表述为真实玩法通过。

## 7. Research Verdict / Next Action

当前 verdict：**RESEARCH NO-GO，暂不进入 Plan。** 独立开发路线成立，但 G1–G10 中至少 G1、G2、G3、G6、G7、G8 仍会直接改变核心 DTO 或算法，不能仅靠编码时补细节。

下一步仍在 Research：先收敛 R/目标几何、ActorTrack、记录基数、感知批次范围和 tick 语义；其余问题随后写入同一 Spec。只有这些决定落盘并形成可验证 Done Contract 后，才讨论 File Changes、Signatures 和原子 Checklist。未收到精确 `Plan Approved` 前不进入 Execute。

## 8. 格子离散与点采样讨论（Research 候选，尚未定案）

用户提出：所有视野结果严格按整数格离散；当前及未来楼层都分别处理，玩家所属格明确；Agent 只获得采样点或事件并自行推测轨迹。该方向可消除“格心可见但整格不完全可见”的误判，也让 D/R 直接表示格集合。但它会改变现行机制中机器人圆形视野、摄像头连续瞬时夹角的表面表述，定案后须同步总 Spec 和机制基准，不能只当底层实现技巧。

仍需区分三项决定：视野候选格模板如何由整数参数生成；摄像头连续扫描是否保留、是否量化方向；格间遮挡采用哪种确定规则。格子离散输出不等于完全不需要遮挡算法。

ActorTrack 原本只是可信程序内部的 tick 内折线，用于发现起终点都在踏板外、中途却穿过踏板的情况，从不计划发送给 Agent。如果踏板也确定为每 tick 只读取演员所在格，则可直接删除 ActorTrack：只比较该演员此前是否在踏板格与本次采样是否在格内，外→内产生一次激活；两个采样点之间发生但未落在采样点的穿越不再视为可观察事件。此简化必须明确写入机制，不能一边使用点采样一边承诺捕获 tick 内全部穿越。

视觉报告可进一步简化为每台设备每个感知步一条记录：记录本次可靠检查的格集合 R；玩家在其中时标记发现并给出玩家所在格 D，否则标记未检测到；没有可靠检查格时标记无法确定并给出原因。R 之外的格子一律不表达无人，通常不必另发巨大的 UNKNOWN 格集合。该单记录方案仍需用户确认。

若采用上述方向，4A 可只生成设备报告包，目标操作报告到 4B 合入；时间规则用具体 tick 示例说明，不再引入额外中间概念。此前 G1/G3 及单 tick 折线穿越验收可能由新决定替代，不能同时保留互相冲突的完成标准。

## 9. 连续视野转格子与原子时间梳理（2026-11-27 续）

用户补充的大前提是：物理 tick 足够小，任何玩家单 tick 位移严格小于一格；踏板每个物理 tick 都检查玩家和机器人当前所在格。在“只判断采样点状态、不还原采样点之间事件”的规则下，4A 不再需要 ActorTrack，也不需要单 tick 外→内→外的穿越验收。每块踏板只需按演员比较此前占用与本次所在格，采样外→内产生一次激活。

连续摄像头转动可以与格子报告共存。当前推荐继续研究的方案是：连续圆形/扇形区域先与地图格矩形求交，得到候选格集合，再用固定的格间遮挡规则筛出可靠检查格。判定必须针对整个视野区域与格子的交集，不能只检查边界曲线是否穿过，否则会漏掉完全位于区域内部、边界曲线未经过的格子。是否“任意接触即算”、要求正面积重叠或采用覆盖阈值，以及遮挡规则，仍未定案。连续运动/扫描、离散感知输出并不冲突。

时间名称按现有 Spec 校正：simulation_tick 是唯一原子模拟时钟，3A Plan 让一个完成的 Godot 物理步对应一个 simulation_tick；视觉感知步使用该时钟的 sense_tick 作为时间戳，但现行框架没有规定每个 simulation_tick 都必须视觉感知，感知频率仍是可替换配置。踏板按用户本次要求每物理 tick 检查。若后续决定视觉也每 tick 感知，只是 sense_interval=1，不另造时钟。

同一设备在同一个感知刻只能有一种结果：可靠检查格非空且玩家所在格在其中时为“发现”；可靠检查格非空且玩家不在其中时为“未检测到”；没有任何可靠检查格时为“无法确定”。发现记录也可携带本次可靠检查格，但这不构成第二个“未检测到”结果。同一上报批次可以包含不同感知刻的不同结果，不能把跨时刻差异误读为同一刻矛盾。

每条未检测到记录只断言“该感知刻，玩家不在该刻可靠检查格内”。一个上报周期有多个感知刻时，各条保留各自时间和区域；不能压缩成“两个上报边界之间的所有位置都无人”。若每个原子 tick 都感知且本周期全部为未检测到，也只能说“本周期每个感知刻，玩家均不在当刻可靠检查格内”，仍不能排除可靠区域之外的位置。

## 10. 视觉采样粒度与剩余开放项

用户担心较低视觉频率容易漏判。当前建议是首个原型先让每个 simulation_tick 都进行视觉判定，而不是新增亚 tick 感知时钟：simulation_tick 已是规则、报告和恢复使用的原子时间；玩家单 tick 位移小于一格且判定按格进行，每 tick 采样通常足以覆盖格子状态变化。摄像头单 tick 扫描角速度仍须限制并试玩。完成 tick 内曾经相交、结束时不相交的瞬时情况仍不属于点采样承诺；若实测不可接受，优先调整物理频率或运动/扫描速度，不引入第二套亚 tick 时间。

进入 Plan 前仍需关闭的设计问题：

1. 视觉是否正式定为每 simulation_tick 采样，以及如何实测原始记录量。
2. 连续视野区域转格子的交集规则：任意接触、正面积重叠或覆盖阈值；建议正面积重叠。
3. 格间遮挡算法、墙角规则、摄像头感知原点及支撑墙处理。
4. 首轮是否在 tick 0 产生初始视觉记录；没有初始记录时，明确首批实际覆盖的完成 tick。
5. 每设备每 tick 一条记录的最终字段，以及可靠检查格集合的编码方式；格子列表、行段等表示不能改变原始记录不合并、不去重的规则。
6. 4A 是否只生成设备报告包，目标操作报告到 4B 合入；推荐保持设备报告包以维持独立性。

可留到 Plan、4B 或试玩的项目：具体视距/FOV/扫描速度/物理频率、真实部署基线写回、目标事件接入、Agent 视图、真实模型输入规模和等待、共享 runner/CI 及性能验收。它们不能反向改变已确定的原子时间、格子判定和单记录互斥语义。

## 11. 长暴露下的报告量问题（Research 候选）

用户指出：玩家长时间暴露在摄像头下随机游走时，如果每个 simulation_tick 都为每台设备上传一条完整观察，报告量会失控。该担忧成立；格子列表编码只能降低单条大小，不能解决条数随物理频率增长。单纯降低视觉采样频率又会重新引入漏判。

推荐研究“每 tick 内部判定、状态变化才形成报告事件”的方案：程序仍每 tick 计算可见状态，但同一设备持续看到玩家在同一格时不逐 tick 重复；首次发现、玩家所在格改变、从发现变为未发现时分别记录。每批结束可追加一次当前状态心跳，避免长暴露后没有最新状态。长期未发现时，只在约定的检查点发送当时的可靠检查格，不把其他 tick 的未发送记录解释为无人。

这样持续同格暴露由每 tick 一条降为首次发现＋每批心跳；跨格随机游走只在实际换格时增加记录，报告量由有意义的格子状态变化驱动，而不是直接由帧率驱动。所有事件仍保留原发生 tick，只在正常上报边界交付，不即时增加定位机会。

该方案会修改现行“每个视觉感知步都产生独立记录、相同记录不合并不去重”的规则，定案前不得由 4A 偷偷过滤。若必须保留现行全量原始记录，则只能采用更紧凑的区域引用/由设备位姿重建覆盖、原始记录只读查询等传输方案；这些主要减少字节数或模型首屏输入，不能减少内部记录条数，并会增加接口复杂度。推荐先由用户确认是否接受把“感知步”与“报告事件”分离，再同步总 Spec、机制基准和最小框架 Spec。

## 12. 对状态变化上报的反证与误判风险

该方案主要减少重复正面目击，并不保证严格报告上限，也不天然优于全量采样。需要明确以下缺点：

1. **负面证据会变稀疏。** 摄像头在两次固定检查点之间扫过许多格子，即使程序每 tick 都知道当时无人，Agent 也收不到这些逐 tick 负面约束。正确结果应是 Agent 的可能性范围更宽，而不是把未发送时间误判为有人或无人。
2. **“丢失目标”容易被误读。** 玩家仍在原地但摄像头转走、被墙挡住或设备停用时，也会从发现变为未发现。报告只能写“该 tick 未在当前可靠检查格内发现”，不能写成玩家已经离开某片大区域。
3. **视野边界抖动仍可能产生大量事件。** 玩家或摄像头位于格子判定边缘时，发现/未发现可能频繁交替；事件方案在路径抖动下仍会膨胀。首版不应通过延迟或去抖吞掉真实短暂目击，否则会产生事实性漏报。
4. **持续可见但视野仍变化时会丢失其他区域的负面信息。** 玩家同格不动只保留心跳，可以减少重复目击，但摄像头同时扫过的其他格子不再逐 tick 上报。
5. **事件时间和批次末状态容易混淆。** 心跳必须使用本批最后一个原子 tick 的 as_of 时间，不能把上传边界 tick 当成观察 tick，也不能用上传时的设备配置回算旧事件。
6. **分支恢复更复杂。** 每设备此前可见状态、最后目击格和待上传事件都须进入周期快照；否则回退后可能重复首次发现、漏掉状态变化或产生错误的结束事件。Agent 收到的旧分支事件仍只能标为历史。
7. **模型推理门槛更高。** 全量记录每条可独立理解；事件流要求模型理解状态变化、无事件不代表无人、心跳时间和批次快照。模拟 Agent 必须先证明不会把这些语义混淆。

修正后的候选不是“只发变化、其余都可省略”，而是“每 tick 内部判定＋完整保留正面状态变化＋固定频率的负面检查＋每批强制状态快照”。事件必须带发生 tick 和当时的可靠覆盖或其不可变引用；无事件和无记录都不得自动表示无人。每批快照应明确截至本批最后一个原子 tick，而非上传边界。

是否会误判取决于两层：程序只要按采样事实生成记录，就不应产生虚假目击；Agent 则确实可能因负面证据减少和事件语义复杂而作出更差推断。因此需要与“降低固定采样频率但每步完整上报”的方案做同一模拟场景对照，比较报告量、短时目击保留、可能性范围扩张和定位正确率，再决定是否采用。当前不把状态变化方案认定为已安全定案。

## 13. 用户修正与“阳性补报＋定时完整观察”候选

用户进一步明确：同一设备同一感知刻只有一条结果；只要当前可靠视野中发现玩家，就上报玩家所在格，不再同时表达视野内其他格子的负面信息；只有整个可靠视野都未发现玩家时才上报负面记录。此前左/中/右示例只能解释为不同时间的独立记录，不能解释为同一次拆分上报。用户同时认为边界抖动不是首版主要风险，本方案不引入去抖或延迟确认。

据此推荐更简单的混合结构：

1. 程序每 simulation_tick 都计算当前可靠视野和玩家所在格。
2. 在约定的完整观察检查点，无论结果如何都产生一条独立记录：发现时写玩家格；整个可靠视野未发现时写可靠格集合；没有可靠视野时写无法确定及原因。
3. 两个完整观察检查点之间，只为额外正面信息补报：此前未发现、当前首次发现，或持续发现但玩家换了格子。持续同格发现不逐 tick 补报。
4. 不设置“丢失目标”事件。玩家离开或摄像头转开后的负面事实，由下一次完整观察自然表达，避免把转镜误写为玩家移动。
5. 每条记录仍可独立理解；两个正面记录之间不表示持续可见，两个负面记录之间也不表示持续无人。所有记录只在正常上报边界交付。

报告量因此由固定数量的完整观察加上实际首次发现/换格补报构成。持续同格暴露不会随帧率增长，长期未发现只保留固定检查点，跨格随机游走只增加实际新位置。正面补报只需设备 ID、发生 tick 和玩家格；完整负面观察才需要较大的可靠格集合。

该结构仍改变现行每感知步全量上传规则，尚未定案。需要保存的内部状态仅为上一实际可见状态/格子及待上传记录，并在回退时一并恢复。完整观察检查点应包含每批最后一个原子 tick，保证每批有当前状态；具体间隔通过报告量和定位效果实测。

可参考 Unreal AI Perception 的结构：感知更新通过事件通知，刺激包含成功感知与否、刺激位置、年龄和失效时间，而不是把逐帧画面直接交给行为逻辑。本项目只参考“事件＋位置＋成功状态＋时间”的组织方式，不采用其自动遗忘规则，因为现行设计保留 Agent 已接触的历史。

## 14. 单 tick 位移远小于一格下的最简方案

用户进一步明确必须成立的前提：玩家在一个物理 tick 内的实际移动距离小于、且通常远小于一格。该前提需要由移动参数和实际位移验收共同保证，包括机器人推挤等外部作用，而不只是输入速度。

这一前提使格子状态在相邻 tick 间变化缓慢，正面目击补报只会在实际进入可见状态或可见格改变时发生，同格随机游走不会放大报告量；也不需要 ActorTrack、亚 tick 感知、去抖/迟滞、轨迹重建、原始记录查询、报告硬上限或复杂压缩。

当前最简候选可收敛为两条生成规则：

1. 每 tick 内部判定。当前看到玩家的格子与上一 tick 不同，且本 tick 确实看到玩家，就追加一条独立正面记录（设备、发生 tick、玩家格）。从不可见到可见自然包含在同一规则中，不另设事件类型。
2. 每批最后一个原子 tick 生成一条完整观察。发现则写玩家格；整个可靠视野未发现则写可靠格集合；无可靠视野则写无法确定及原因。首批原型只要求每批一次，若负面证据不足再通过实测增加固定检查点。

所有记录继续按原发生 tick 在正常上报边界交付。两条正面记录之间不表示持续可见，两条负面记录之间不表示持续无人。内部只需保存上一 tick 的实际可见格和待上传记录，并随局部回退恢复。

该方案不再追求理论上的严格报告条数上限，而是用已保证的低格子变化率控制实际报告量。它比全量逐 tick 上报少很多重复信息，又比复杂事件模型更容易证明正确；仍需用户正式确认替换现行每感知步全量上传规则，并同步总 Spec 与机制基准。

## 15. 对“静止玩家离开后无法判断”的修正

用户指出：若玩家长时间静止在某格，正面状态一直不重复，之后离开视野，而规则又没有可见→不可见补报，系统就无法知道状态是在哪个 tick 改变的。该缺口成立。两条规则版本只能在下一次完整观察得到最新结果，不能精确表达中间发生的变化；若下一次可靠视野不再覆盖原格子，甚至不能判断玩家是否仍在原格。

最小修正是增加第三条生成规则：当某设备上一 tick 看到玩家、本 tick 不再看到玩家时，立即追加一条普通完整观察，发生 tick 仍取本 tick。此时可靠视野非空则报告该视野未发现，可靠视野为空则报告无法确定及原因。它不是“玩家已经离开”的特殊事件，也不要求 Agent 重建跟踪生命周期。

这样，玩家静止后实际离开可靠视野时，转变 tick 会留下记录；如果当时可靠视野仍覆盖原格子，系统可以确定原格子在该 tick 无人。若只是摄像头转走且可靠视野不覆盖原格子，记录只说明当前范围未发现，不断言玩家移动。持续同格可见仍不重复，报告量只增加实际可见→不可见的转变。

因此当前最小完整候选为：正面首次发现/换格补报＋可见转不可见时完整观察＋每批末完整观察。三种生成都使用同一套独立观察记录格式，不引入特殊“丢失目标”语义。

## 16. 所有观察统一携带事件时可靠视野

用户提出上报时同时携带当前视野范围。该补充成立，并能修复“持续正面目击时丢失其他可靠格子负面信息”的缺口，但前提是视野范围必须指观察发生 tick、经过遮挡过滤后的可靠检查格 R，而不是名义扇形/圆形，也不是上传时重新计算的视野。

统一记录语义为：R 非空且玩家格 P 在 R 中时，记录发现、R 和 P；因为只有一个玩家，这同时意味着当 tick R 中除 P 外的其他可靠格无人，不需要另发负面记录。R 非空且 P 不在 R 中时，记录未检测到和 R。R 为空时只记录无法确定及原因，不对位置作结论。

这样每条正面记录也同时提供其余可靠格的排除证据；可见转不可见记录能说明原格子是否仍在可靠视野内；每批末记录提供最新状态。三条生成规则仍负责避免逐 tick 重复，携带 R 不能替代这些规则，也不能解决频繁换格时的全部数据量问题。

首版直接保存并上报事件时的格子集合，不提前引入视野版本引用或查询机制。若实测数据量仍大，再只优化表示方式；不得用上传时最新配置重写历史 R。

## 17. 视野转格子与遮挡（用户已确认）

为保留连续扫描并避免连续可见多边形，推荐两阶段规则。

### 17.1 输入和观察原点

- 摄像头观察原点使用安装格的连续格心坐标；3A DeviceView 当前也按格心放置，二者一致。墙装支撑墙仍按普通墙处理，不额外偏移原点。
- 机器人观察原点使用 runtime_state 中当前实际连续位置；其所在格由 world_to_cell 得出。
- 玩家只取 world_to_cell(player_position)，格边界继续由现有 floor 规则决定。不同楼层未来分别计算，不引入高度。
- 视距以整数格数表达，或要求现有世界单位值严格等于 cell_size 的整数倍。当前 3A fixture 的 300/64 不是整数格，定案后须改 fixture，不能由 4A 暗中取整。
- 摄像头 heading、fov_angle 保持连续；每个 simulation_tick 在 3A 完成运动与扫描后计算。

### 17.2 第一阶段：连续视野区域生成候选格

- 机器人使用以观察原点为圆心、整数格视距为半径的圆形区域。
- 摄像头使用同一原点、当前 heading 为中心、fov_angle 为总夹角、视距为半径的扇形区域；TAU 特判为完整圆形。
- 遍历圆形包围盒覆盖的地图格。视野区域与格子矩形有正面积重叠时，该格进入候选；只在一个点或一条边界上相切不算。必须判断整个区域交集，而非仅判断边界曲线穿过。
- 地图外、墙格和实心固定设施格不进入最终可靠检查格。玩家、机器人和不阻挡通行的踏板不作为视觉遮挡。

### 17.3 第二阶段：固定的格间遮挡规则

- 对每个候选格，从连续观察原点向目标格格心作线段。
- 使用 supercover 格子遍历，把线段接触到的所有中间格纳入检查，而不是只走一个近似 Bresenham 格序列。
- 排除起点所在格和目标格；中间任一墙格或实心固定设施格使目标格不可靠。
- 线段恰过格角或沿格边时，按所有接触格处理：只要任一被接触的中间实心格阻挡，就不可见。首版采用严格禁穿角/边的规则，不另做连续偏移射线。
- 通过遮挡检查的候选格组成 R。此合同有意采用“正面积重叠决定候选、格心线段决定遮挡”的固定取舍：实现简单、结果确定，但边缘格可能比真实连续视觉更保守或更宽，需用灰盒画面验收。

### 17.4 必须覆盖的人工小地图

- 圆形/扇形完全覆盖格子、正面积擦边、单点相切、全圆 TAU。
- 直线遮挡、斜线遮挡、墙后目标、实心固定设施后目标。
- 线段穿格角、沿格边、目标格为实心、观察原点靠墙。
- 摄像头支撑墙、机器人跨格连续位置、玩家格边界、地图外。
- 同一 WorldState 重复计算结果一致；渲染可显示连续扇形，但另以格子高亮显示权威 R。

该规则不依赖 Godot RayCast2D；4A 与 4B 使用同一纯数据 helper，避免物理射线与数据感知形成两套结果。

## 18. 模块 3A 完成核验与 4B 准入

模块 3A 最新 Spec 已标记 REVIEW 完成、PASS（模块 3A 范围），P0–P7 全完成，独立复核问题关闭。2026-11-27 本轮再次实际运行当前工程导入和正式 runner，SessionKernelTests 81、WorldCommandTests 223、RuntimeMotionTests 31、RuntimeSceneTests 253 均通过，共 558/0；日志为 `tmp/module4-review-import.log` 和 `tmp/module4-review-tests.log`。日志中的 SYNC_ACTIVATION_FAILED 是预期故障测试文本，对应套件仍全部通过。

真实 GameRuntime、RuntimeWorldView、SceneWorldSyncAdapter 和 commit_runtime_step 已存在。当前 GameRuntime 在运动后、提交前尚未调用感知器，报告边界 seal/update 仍为空实现；3A 只提供接缝，不代表 4B 已实现。

因此：4B Research/Plan 可以进行；完整 Execute 仍需 4A 合同与实现可用，并取得 4B 自身 Plan Approval。4B 已按用户最新范围裁决纳入 3B 目标事件合批，但 4A 不依赖或修改 3B；真实联络部署恢复和完整玩法闭环仍由后续模块处理。

4B 基本落点包括运动前 previous_actor_cells 提取、运动后 candidate 感知、world/session 接受后发布、Main 组合注入、真实报告 seal/update、真实场景集成测试和共享 runner 登记。踏板只做前后位置比较，不修改 WorldState，不新增部署基线写入口，也不读写遗留 occupants。

当前 3A 代码与文档仍未提交。从当前 HEAD 新建 worktree 不会得到 3A，因此并行执行前必须先形成包含 3A 的可用共同基线，不能只依据工作树路径假设其他分支可见。

## 19. occupants 必要性复核（补充反例后的谨慎结论）

模块 2 的 occupants 是每块踏板内部保存的演员 ID 集合（玩家 0、机器人实体 ID），baseline_ready 表示该集合是否已按部署瞬间位置初始化。它不是玩法或 Agent 可见概念，而是实现“上一采样是否在踏板内”的一种存储方式。现行最小框架和模块 2 Spec 已明确把占用基线列入权威状态与快照，因此按当前合同不能直接删除；替换必须重新审批并迁移文档、代码和测试。

正常连续运动且 occupants 与演员位置一致时，比较运动前后演员所在格与维护 occupants 会产生相同事件。部署后的第一步使用部署后的采样点，因此部署在脚下自然内→内不触发，部署时在外、第一步进入则外→内正常触发。局部回退、整轮重启和新猜测周期必须在各自配置/分支连续性边界重新取得采样点，不能沿用撤销分支或上一轮的位置。事件只能在 candidate 提交成功后进入有效报告缓冲。

复核发现两个此前未覆盖的反例：

1. 当前 schema 允许 occupants 与演员实际位置不一致的快照。此时 occupants 方案与位置比较方案会产生不同事件；位置比较更直接，但旧快照迁移必须明确，不可宣称对所有现行可解码状态都天然等价。
2. 当前命令框架允许在既有踏板上新增机器人，而 occupants 失效逻辑只覆盖新增/移动踏板。若直接沿用 occupants，可能把部署时已在踏板上的新机器人误报为下一步进入；使用部署后的采样点则不会。这证明当前 occupants 合同本身也未闭合，而不是简化方案独有问题。

替换方案仍需遵守：同一感知步踏板配置不变；不能用旧踏板位置计算前态、新踏板位置计算后态；新增演员必须通过部署后的采样点获得“上一位置”，不能默认视为格外；提交失败的 candidate 与事件一并丢弃；多演员分别比较，匿名重复事件不去重。

性能上，当前 GameRuntime 并没有免费的第二份世界。可以每步保留 previous_world，也可在运动前只提取一次 previous_actor_cells，供 4A 与 candidate_world 比较；后者避免额外整世界深拷贝，但仍只是本步临时输入，不形成第二份长期权威状态。选择前后位置采样的理由是减少状态机和故障面，不是预设它一定更快。

模块 2 字段若仅保留但弃用，可维持旧快照和 4A 基线，减少短期改动；但现有失效、校验和机器人删除清理仍会产生副作用，不能声称复杂性已消失。完整删除字段更干净，却会改变内存快照 schema、模块 2 校验/部署逻辑与测试，适合作为独立的小清理，不应偷偷并入 4A 新文件范围。当前没有磁盘存档和完整 RESET，旧数据迁移压力较低，主要是合同与测试迁移。

本节记录当时的谨慎评估：occupants 不是实现现行踏板语义的逻辑必需品，但旧合同与快照需要处置。用户随后已确认“保留但不使用”，现行执行边界以 §20 和 §21 为准；本节不再提出 A/B 全量差分或旧版基线条款作为 4A 准入门槛。

## 20. “保留但不使用”的实际严重程度复核

用户要求避免把维护性担忧夸大为必然 Bug。代码复核后的结论如下：

- 新增/移动踏板时清空 occupants 并设 baseline_ready=false 是现有合法状态，不会导致校验失败或运行时故障；该逻辑继续执行本身不是 Bug。
- 若 4A/4B 从不写入 occupants，则正式游戏中的 occupants 会一直保持初始空数组。删除机器人时对空数组 erase 不改变踏板实体，因此不会必然触发额外场景同步。只有旧快照或测试已经填入非空 occupants 时，删除机器人才会修改相关踏板并进入 changed_ids；即使发生，也主要是额外节点替换和性能浪费，不是必然玩法错误。
- occupants 保留在快照中会增加少量数据和维护负担，但空或位置不一致的 occupants 只要不被读取，就不会造成踏板误报。现有机器人删除清理也避免了正常流程中的悬挂 ID。快照校验失败不是保留字段的必然后果。
- 真正风险是后续开发者误把遗留字段重新当成权威状态，形成两套判定。可通过明确标注“遗留字段、不得读取或写入”控制，属于维护风险而非运行时缺陷。

因此“保留但不使用、后续统一清理”在本项目当前场景属于低严重程度技术债，是可接受的 72 小时取舍，不需要为了理论纯净提前做模块 2 清理，也不需要强制 A/B 全量差分验收。4A/4B 只验收前后位置采样合同；在部署、回退和重启连续性边界重新取得 previous_actor_cells，提交成功后才发布事件。现有字段不参与这些逻辑，待所有模块完成后统一删除即可。

## 21. Plan：实施合同

本 Plan 只新增纯数据脚本、独立测试和文档，不修改现有游戏代码。实施顺序以 DTO 与几何先行、内核与踏板随后、报告和独立验收最后为准；任何签名或单步语义变化先回写本节。

### 21.1 File Changes

| 文件 | 计划变化 |
| --- | --- |
| `game/scripts/sensing/observation_record.gd` | 新增视觉记录 DTO，严格字段、结果类型、深拷贝与 plain-data 编解码 |
| `game/scripts/sensing/plate_activation_record.gd` | 新增匿名踏板激活 DTO，严格字段与深拷贝 |
| `game/scripts/sensing/vision_geometry.gd` | 新增连续圆形/扇形转候选格、supercover 遮挡与可靠 R 计算 |
| `game/scripts/sensing/sensing_step_result.gd` | 新增一步感知结果容器：下一视觉状态、视觉/踏板记录和结构化错误 |
| `game/scripts/sensing/sensing_kernel.gd` | 新增 tick 0、逐 tick 视觉状态迁移、批次末观察、演员格提取和踏板事件 |
| `game/scripts/sensing/sensing_report_batch.gd` | 新增设备报告包 DTO，包含边界与有序视觉/踏板记录 |
| `game/scripts/sensing/report_buffer.gd` | 新增待上传记录缓存、半开窗口封批、深拷贝快照与恢复 |
| `game/tests/sensing_geometry_tests.gd` | 新增人工小地图几何、边界和遮挡测试 |
| `game/tests/sensing_kernel_tests.gd` | 新增视觉原子性、踏板、DTO、buffer、快照及错误测试 |
| `game/tests/run_sensing_tests.gd` | 新增独立 SceneTree runner，不登记到共享 `run_tests.gd` |
| 新脚本 `.gd.uid` | 由 Godot 导入生成并随对应新文件入库 |
| 本 Spec、Feature 索引、`game/README.md` | 实施后回写真实运行证据、限制和剩余问题；不在 Plan 阶段修改 |

不修改 `GameRuntime`、`GameSession`、`CycleState`、`WorldCommandService`、`DeviceRegistry`、`WorldState`、3A/3B 文件、`AgentProtocol`、共享测试入口或 CI。遗留 `occupants / baseline_ready` 保持原样且不得被新代码引用。

### 21.2 公共数据格式

`ObservationRecord`（RefCounted，`class_name ObservationRecord`）：

- 字段：`round_id:int`、`branch_id:int`、`guess_cycle_id:int`、`report_cycle_id:int`、`device_id:int`、`sense_tick:int`、`result:String`、`reliable_cells:Array[Vector2i]`、`player_cell:Variant`、`reason:String`。
- `result` 只能为 `DETECTED / NOT_DETECTED / UNDETERMINED`。
- `DETECTED` 要求 R 非空、`player_cell` 属于 R；`NOT_DETECTED` 要求 R 非空且 `player_cell=null`；`UNDETERMINED` 要求 R 为空、`player_cell=null` 且 reason 非空。
- R 不重复，按 y 后 x 排序；`player_cell` 只用 Vector2i，不接受连续坐标。

签名：

```gdscript
static func make(data: Dictionary) -> ObservationRecord
static func from_data(data: Dictionary) -> ObservationRecord
func to_data() -> Dictionary
func snapshot_copy() -> ObservationRecord
```

非法字段、缺失字段、错误类型、非法 ID/tick、重复格、错误结果组合或包含 `player_world_position / contact_source / actor_id` 等越权键时返回 null，不隐式修正。

`PlateActivationRecord`（RefCounted，`class_name PlateActivationRecord`）：

- 字段：与视觉相同的四个身份字段及 `device_id`，另有 `event_tick:int`、`cell:Vector2i`。
- 只表示踏板格进入，不含触发者或连续坐标。

签名：

```gdscript
static func make(data: Dictionary) -> PlateActivationRecord
static func from_data(data: Dictionary) -> PlateActivationRecord
func to_data() -> Dictionary
func snapshot_copy() -> PlateActivationRecord
```

`SensingStepResult`（RefCounted，`class_name SensingStepResult`）：

```gdscript
var next_visual_states: Dictionary
var visual_records: Array[ObservationRecord]
var plate_records: Array[PlateActivationRecord]
var errors: Array[Dictionary]
func succeeded() -> bool
func snapshot_copy() -> SensingStepResult
```

`next_visual_states` 以设备 ID 为键，每项包含 `visible_cell:Variant`、`last_evaluated_tick:int`、`last_emitted_tick:int`。调用方只有在对应 world/session 提交成功后才采用该状态；失败结果只含 errors，不含部分记录。

### 21.3 VisionGeometry 签名与算法

```gdscript
class_name VisionGeometry

static func observer_position(world: WorldState, entity: Dictionary) -> Vector2
static func reliable_cells(world: WorldState, entity: Dictionary) -> Dictionary
static func is_cell_reliable(world: WorldState, origin: Vector2, target: Vector2i) -> bool
```

`reliable_cells` 返回 `{"ok": bool, "cells": Array[Vector2i], "errors": Array[Dictionary]}`；失败不返回部分 R。摄像头原点为 `world.cell_to_world(DeviceRegistry.grid(entity.cell))`，机器人为 `DeviceRegistry.vector(entity.runtime_state.position)`。摄像头 `enabled=false` 时由 SensingKernel 直接令 R 为空、结果为 `UNDETERMINED` 且 `reason=DISABLED`，不调用候选几何。

线性与角度容差分别为 `cell_size * 0.000001` 和 `0.000001` 弧度，仅用于几何比较，不作为玩法范围参数。视距除以 `cell_size` 必须在容差内为正整数，否则返回 `INVALID_VIEW_RADIUS`。

候选阶段：

1. 摄像头取当前 heading 为中心的扇形，机器人取圆形；TAU 特判为全圆。
2. 只遍历半径包围盒与地图的交集。
3. 用圆/扇形与轴对齐格矩形的解析相交测试判断正面积重叠；覆盖原点的格、格顶点在区域内、区域边与格边相交、弧与格边相交分别处理。只相切于点或边界不算；不能仅测试边界曲线。
4. 墙格、地图外和 `DeviceRegistry.FIXED` 实心设施格不进入最终 R。

遮挡阶段：

1. 从观察原点到候选格格心作线段，以参数化格边界交点构造 supercover 格序列。
2. 同参数 t 的角点/边接触格全部保留，排除起点格和目标格；中间任一 WALL 或 FIXED 实心格返回 false。
3. 玩家、机器人、摄像头和踏板不参与遮挡；同一世界与实体重复计算顺序和结果一致。

`is_cell_reliable` 负责单一候选的遮挡判定，不使用 Godot RayCast2D，不读取场景节点。

### 21.4 SensingKernel 签名与状态语义

```gdscript
class_name SensingKernel

static func actor_cells(world: WorldState) -> Dictionary
static func copy_visual_states(states: Dictionary) -> Dictionary
static func restore_visual_states(data: Dictionary, world: WorldState) -> Dictionary

static func initialize_round(world: WorldState, context: Dictionary, ticks_per_report_period: int) -> SensingStepResult
static func step(
    visual_states: Dictionary,
    previous_actor_cells: Dictionary,
    world: WorldState,
    context: Dictionary,
    ticks_per_report_period: int
) -> SensingStepResult
```

`context` 严格包含 `round_id / branch_id / guess_cycle_id / report_cycle_id / sense_tick`；四个身份字段为正整数，`sense_tick` 为非负整数。另传可信、正整数的 `ticks_per_report_period=N`（原型配置，不是玩法定案）。4A 必须校验 `report_cycle_id = floor(sense_tick / N) + 1`，不得仅信任调用方填入的周期号。初始化只允许 tick 0，故其 `report_cycle_id=1`；后续 tick 必须严格大于各设备 `last_evaluated_tick`。批次末由内核按 `sense_tick % N == N - 1` 计算，不接受调用方单独传入的布尔值。首轮 tick 0 已执行完整初始化观察；当 `N=1` 时该条同时满足首批末要求，不重复生成。

`actor_cells` 返回 `{0: 玩家格, robot_id: 机器人格}`。`previous_actor_cells` 必须恰好覆盖 candidate 中当前玩家和全部机器人；缺失返回 `MISSING_ACTOR_SAMPLE`，多余返回 `STALE_ACTOR_SAMPLE`，不得把新增演员默认放在格外。

`initialize_round` 在 tick 0 为所有摄像头和机器人生成完整观察，记录 R、结果和可见格；初始化各设备 `visible_cell` 及 `last_evaluated_tick=0`、`last_emitted_tick=0`。踏板不生成初始化事件。

`step` 先对齐视觉设备集合：删除已移除设备的状态；新增设备以 `visible_cell=null`、`last_evaluated_tick=context.sense_tick-1`、`last_emitted_tick=context.sense_tick-1` 初始化，并在首次评估时强制生成一条完整观察。新增设备可以是新摄像头或机器人，避免部署后缺少状态或把持续不可见误当成状态变化。

随后按设备 ID 顺序处理：

- 摄像头 `enabled=false` 时令 R 为空、`visible_cell=null`、结果 `UNDETERMINED` 且 `reason=DISABLED`；其他设备计算当前 R 与玩家格是否属于 R。
- 当前可见格非空且不同于上一可见格，生成一条正面记录。
- 当前可见格为空且上一可见格非空，生成一条当前完整观察。
- 持续同格可见不重复；持续不可见不生成常规视觉记录。
- `sense_tick % N == N - 1` 且本设备本 tick 尚未生成记录时，补一条完整观察；状态变化记录已存在时不重复。
- 更新 `last_evaluated_tick`，有记录时更新 `last_emitted_tick`。
- 随后按踏板 ID、演员 ID 顺序比较 `previous_actor_cells` 与 candidate 当前格，前外后内生成匿名激活；不修改任何 WorldState。

`copy_visual_states` 深拷贝状态；`restore_visual_states` 返回 `{"ok": bool, "states": Dictionary, "errors": Array[Dictionary]}`，严格校验设备集合、字段、tick 和可选玩家格，不在失败时产生部分恢复。恢复输入既可使用内存态的整数设备 ID / `Vector2i`，也可使用 plain-data 快照的十进制 ID 字符串 / `[x,y]`；混用、非规范 ID、重复 ID 或越界格一律拒绝，成功后统一返回整数键和 `Vector2i`，便于 4B 保存不含对象的快照。

### 21.5 ReportBuffer 与设备报告包

`SensingReportBatch`（RefCounted，`class_name SensingReportBatch`），`from_data` 须校验边界长度/周期号、每条记录的半开窗口归属及 round/branch 身份，不接受越界或混入其它分支的记录；记录的 `guess_cycle_id` 保留事件时值，允许边界 tick 的记录跨猜测暂停后在下一批封存：

```gdscript
var round_id: int
var branch_id: int
var guess_cycle_id: int
var report_period_id: int
var start_tick: int
var end_tick: int
var records: Array[Dictionary]

static func from_data(data: Dictionary) -> SensingReportBatch
func to_data() -> Dictionary
func snapshot_copy() -> SensingReportBatch
```

每条 record 用 `record_type = visual / plate_activation` 区分，内容分别为对应 DTO 的 plain data；按 `sense_tick/event_tick`、设备 ID、record_type 和原始顺序稳定排序，不合并不同事件。

`ReportBuffer`（RefCounted，`class_name ReportBuffer`），仅封设备视觉/踏板记录；目标操作事件由 4B 或后续统一报告层合批，不能把设备子包冒充完整统一上报：

```gdscript
func _init(ticks_per_report_period: int) -> void
func append_visual(record: ObservationRecord) -> bool
func append_plate(record: PlateActivationRecord) -> bool
func append_all(visual_records: Array[ObservationRecord], plate_records: Array[PlateActivationRecord]) -> bool
func seal(boundary: ReportBoundary) -> SensingReportBatch
func snapshot() -> Dictionary
func restore(data: Dictionary) -> bool
func pending_count() -> int
```

- append 只接受有效 DTO，并以构造时的 N 校验 `report_cycle_id = floor(event_tick / N) + 1`；已封周期的迟到记录及同一分支、同设备、同 tick 的重复视觉记录拒绝，匿名踏板同 tick 多演员事件不去重。调用方保证 world/session 提交成功后才调用。`append_all` 先校验全部记录，全部合法才一次性追加，任一失败保持 buffer 不变，供 4B 实现提交的全有或全无。恢复快照也重验该关系、N 与 `last_sealed_period_id`，不允许错误周期号经恢复进入 buffer。
- seal 先校验 boundary 的 `start_tick >= 0`、`end_tick - start_tick == N`、`start_tick % N == 0`、`report_period_id == floor(start_tick / N) + 1 == last_sealed_period_id + 1`，以及本窗口待封记录的 round/branch 身份；无效、重复或跳期边界返回 null 且不改变 buffer。合法时仅取 `record.report_cycle_id == boundary.report_period_id` 且 `start_tick <= event_tick < end_tick` 的记录，成功后更新 `last_sealed_period_id`；`event_tick == end_tick` 留在下一批。每条记录保留发生时的身份，不以封批时的猜测周期身份改写历史。
- 没有符合条件的记录也返回合法空批次。
- snapshot 只含 plain data，包括 N 与初始为 0 的 `last_sealed_period_id`；restore 严格校验，失败保持原 buffer，不保存 Node、Callable、ActorTrack 或玩家连续坐标。

**N=3 的半开窗口验收例**：首轮 tick 0 初始化生成完整视觉观察，`report_cycle_id=1`；tick 2 是 `[0,3)` 最后一个原子 tick，必须为每台仍存在的视觉设备补完整观察（若同 tick 已因状态变化生成则复用），两条均归周期 1。tick 3 属于 `[3,6)`，其状态变化观察和踏板事件均为 `report_cycle_id=2`，不得作为上一批的“批末”记录。GameSession 在提交 tick 3 后才产生 boundary `[0,3)`；`ReportBuffer.seal` 只取 tick 0、2 等周期 1 记录，tick 3 留在 buffer；下次 boundary `[3,6)` 才封 tick 3。若 tick 3 恰为猜测边界且随后 guess_cycle_id 变化，tick 3 记录仍保留旧事件身份，在下一报告周期封存，不因批头身份不同而丢弃。`N=1` 时 tick 0 初始化观察兼作首批末观察。错误 `report_cycle_id` 的输入、恢复快照及无效 boundary 均须拒绝，不能静默丢记录或误归下一批。

### 21.6 原子 Checklist

- [x] **P0 基线与失败测试**：在干净模块 0–2 副本记录 81/223 基线；先写几何、原子记录和封批失败用例，确认独立 runner 能返回非零。
- [x] **P1 DTO**：实现视觉/踏板记录、结果容器及报告包；覆盖严格字段、非法身份、重复格、越权键和深拷贝。
- [x] **P2 连续范围转格子**：实现圆形/扇形候选、整数格视距和解析相交；覆盖正面积擦边、相切、全圆、FOV 边界和原点格。
- [x] **P3 supercover 遮挡**：实现格心线段与严格角/边规则；覆盖直/斜墙、固定设施、支撑墙、格角、格边和机器人连续位置。
- [x] **P4 视觉内核**：实现 tick 0、逐 tick 状态迁移、可见转不可见、按 N 计算批次末并当场补报、新增/删除视觉设备和 DISABLED；覆盖 N=1/3、tick 0/2/3、同格不重复、换格、转镜、同 tick 原子性及状态快照。
- [x] **P5 踏板内核**：实现 previous_actor_cells 与前外后内检测；覆盖出生、停留、离开、重进、多演员、推挤 fixture、部署脚下、部署后首次进入及新增机器人。
- [x] **P6 报告缓存**：实现 append/append_all/seal/snapshot/restore；覆盖可信周期号校验、全有或全无、空批、混合批、N=3 半开边界留批、重复/跳期封批拒绝、R 历史不变、非法恢复不污染原状态。
- [x] **P7 独立验收**：在只含模块 0–2 与 4A 新文件的干净副本导入并运行全部测试；执行失败探针、仓库检查、链接检查和 diff 检查，回写实际证据与限制。

每个单元先补能失败的最小测试再实现；不得为了通过测试改写成 ActorTrack、每 tick 全量上传、Godot RayCast2D 或 occupants 状态机。

### 21.7 Validation Plan

1. Godot 4.7.2 headless import 无脚本/解析错误；独立 `run_sensing_tests.gd` 全部通过，失败探针退出 1。
2. 干净模块 0–2 的 SessionKernelTests 81、WorldCommandTests 223 保持通过；4A 新脚本不引用 3A/3B。
3. 人工小地图覆盖 §17.4、tick 0、同设备同 tick 原子性、可见状态三类变化、批次末去重、部署/回退后重新采样和新增机器人。
4. 所有视觉记录包含事件时 R，发现时包含合法玩家格；踏板记录匿名；输出与 buffer 不含连续玩家坐标、联络来源或 actor_id。
5. 记录至少验证一次持续暴露同格随机游走：除首次/批次末外无逐 tick 重复；换格与可见转不可见有记录；历史 R 不被后续配置修改。
6. `python -m unittest discover -s tests -v`、`python scripts/check_repository.py`、`python scripts/check_project_links.py --all`、`git -c core.whitespace=cr-at-eol diff --check`。
7. 仅证明纯数据内核与独立 runner；真实物理、部署、暂停、Agent 视图、性能和统一 CI 留待 4B，不沿用 3A 的 558 项作为 4A 验证。

### 21.8 Plan Approval 边界

用户于 2026-11-28 明确回复“针对4A Plan Approved”；当时仅 4A 获准 Execute。4B 可复用本节 DTO 和纯函数签名编写自己的 Plan，但不能由 4A 的批准推断 4B 自动获批。4B 后来取得单独批准并完成，见本页顶部与 4B Spec。

### 21.9 最终可执行性复核（Plan 阶段）

当前实施合同固定为本页顶部摘要及 §17–21；§3–16 的旧推导不参与验收。N 从调用方显式传入，由纯内核与 buffer 独立复核周期号及半开窗口；首轮 tick 0、N=3 的 tick 0/2/3、跨猜测边界的事件身份、重复/跳期封批均已由独立测试验证。4A 保持设备子包边界，4B 按已裁决范围负责 3B 目标事件统一合批。无剩余 4A Grill 问题；真实运行时、报告回调故障与整数格 fixture 迁移仍由 4B 验证。实际结果见 §23。

## 22. Execute checkpoint（2026-11-28）

当时任务单元：按 §21 新增 4A 纯数据感知、设备报告、独立测试与 runner，并在仅含模块 0–2 和 4A 的干净副本验证。当时禁止修改 3A/3B、共享 runner、现有世界代码或 4B；不覆盖未提交工作树。主要风险是连续扇形与格矩形正面积相交、supercover 严格角边规则和半开窗口归属；先写失败测试，再逐单元实现与运行。独立 headless 结果、失败探针、基线回归和仓库检查已回写 §23。

## 23. Validation 与 Review（2026-11-28）

本节记录 4A 独立验收当时的工作树状态；后续 4B 已单独通过 Review，现行集成结果见 [4B Spec](2026-11-28_10-44_module-4b-runtime-sensing.md)。

### 23.1 Validation

- 仅新增 §21.1 所列 7 个 `game/scripts/sensing/` 纯数据脚本、3 个独立测试/runner 脚本及其 UID；未修改现有游戏脚本、3A/3B 文件或共享 `run_tests.gd`。文档只回写本 Spec、Feature 索引和 `game/README.md`。
- 从模块 2 完成提交 `5e3857d` 导出 `game/` 到忽略目录 `tmp/module4a-execute-d4d9e73d/baseline/game`，只复制 4A 新文件；该副本不含 `game/scripts/runtime/`。Godot `4.7.2.stable.official.ed1daf0bf` headless 导入退出 0；独立 `run_sensing_tests.gd`：SensingGeometryTests 26/26、SensingKernelTests 88/88，均 0 failed、runner 退出 0。失败探针 `-- --fail-probe` 退出 1。干净副本原有 SessionKernelTests 81/81、WorldCommandTests 223/223，均 0 failed。日志：`tmp/module4a-final6-*.log`。
- 4A 独立验收当时的共享 runner 未登记 4A；原有 SessionKernelTests 81/81、WorldCommandTests 223/223、RuntimeMotionTests 47/47、RuntimeSceneTests 344/344，均 0 failed、退出 0。该项只作为新增全局类的兼容性检查，不把 3A/3B 算作 4A 验收。
- `python -m unittest discover -s tests -v`：13/13；`python scripts/check_repository.py`：0 issues；`python scripts/check_project_links.py --all`：0 broken；`git -c core.whitespace=cr-at-eol diff --check`：通过。新文件另行做空白检查。
- 关键人工 fixture 覆盖连续圆/扇形、正面积边界、点/边相切、TAU、宽扇形、整数格视距（`64/320` 与 `64/384` 通过，`64/300` 拒绝）、格角与墙/固定设施遮挡、设备新增/删除、相机禁用、玩家换格及不可见、踏板匿名双演员、部署脚下、状态和 buffer 快照隔离、N=1/3 与 tick 0/2/3 感知→append→半开封批贯通。

### 23.2 Review Matrix

| 轴 | 结果 | 证据与界限 |
| --- | --- | --- |
| Goal / Spec Completeness | PASS | §21 的文件、接口、P0–P7 和独立验收边界明确；4B 的运行时集成在本次 4A Review 当时另有未批准 Plan。 |
| Spec-Code Fidelity | PASS | 4A 只写新文件；DTO、几何、状态迁移、匿名踏板、report 周期校验及 `ReportBuffer.seal` 均按 §21，N=3 的 tick 3 留在下一批。 |
| Code Intrinsic Quality | PASS（4A 范围） | 严格输入校验、深拷贝、原子错误返回和失败探针经独立 runner 验证；未见阻塞缺陷。浮点几何使用 §21.3 容差，极近切线的数值边界仍需 4B 在实际地图复验。 |

**Overall Verdict：REVIEW PASS（模块 4A 纯数据内核）。Blocking Issues：无。** 这不是统一玩法报告、真实物理感知、Agent 集成或完整游戏的验收。

### 23.3 Plan-Execution Diff、剩余风险与交接

- 与 Plan 的接口和范围无偏差。补充测试了 `N=1` 的 tick 0 首批末、报告包深拷贝、空周期封存和玩家格边界；`restore_visual_states` 同时接受内存态整数 ID/`Vector2i` 与严格 plain-data 字符串 ID/`[x,y]`，已在 §21.4 回写。
- 4B 后来在运行时提交成功后采用 `SensingStepResult.next_visual_states` 和 `ReportBuffer.append_all`，处理回调失败、部署后 `previous_actor_cells`、目标操作事件统一合批及 `cell_size=64` 下的 300/400 视距 fixture 迁移；结果见 4B Spec §14。4A 本身未执行这些集成。
- 后续模块继续以本节和 §21 确认 4A 边界；不要清理或覆盖当前未提交工作树。
