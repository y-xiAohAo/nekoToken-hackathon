# SDD Feature Spec：模块 7 玩家助手联络与剩余动态命令

层级：Feature Spec。创建：2026-11-28（Asia/Shanghai）。工作区：`D:\nekoToken\nekoToken-hackathon`。

**当前阶段：REVIEW（仅 7A）。批准状态：Plan Approved（用户于 2026-11-28 明确批准）。状态：同行复审后 REVIEW PASS（7A 范围）；当前完整共享 runner 受并行模块 5 周期开发影响未全绿。** 7B、7C 和真实桥接不在本次批准范围；模块 5 的 W2 计划不当作已验收接口。

## 0. 当前裁决与优先级

1. [主设计 Spec v0.45 的末尾迁移段](../../PRELIMINARY_DESIGN_SPEC.md)已把模块 5 最新裁决写回，替换该文上方部分旧权限描述；[模块 5 最新 §0 与 §P](2026-11-28_14-55_module-5-simulated-agent-guess-cycle.md)优先于文件后半保留的旧版踏板-only Plan。7A 规划时模块 5 尚未获批准；实施期间用户另行批准模块 5 W1，当前已开始世界模型与公开视图迁移。完整系统周期 W2、Gateway 和历史接口仍不能当作已实现代码。本 Spec 不以旧版 §10 签名作为存在的接口。
2. 模块 7 沿用模块 5 最新 §0.8 的助手合同：**助手提议，玩家确认不可变的完整命令**；每次联络最多一条设备命令、一个目标。一个摄像头逻辑命令可同时包含 `scan_center`、`scan_half_angle`，不按底层字段逐项计数。机器人 `SetPatrolPath` 属于模块 7 后续集成，**不进入 7A**。这取代了早期讨论中“逐字段计项、正式上限取 1 或 2”的 7A 口径；正式玩法的其它数值仍待试玩。
3. 玩家不需要知道或输入内部设备 ID。玩家在游戏画面标记一台显示中的摄像头；可信游戏代码生成仅在本次联络有效的不透明目标句柄。助手只收到句柄、玩家描述、通用工具结构、自身历史和安全回执，不得到目标坐标、设备目录、系统地图或报告。只有游戏代码把句柄解析成内部 ID。
4. 助手文本用于交流；世界变化只能来自经过严格解析的结构化提案、玩家确认和 `WorldCommandService` 校验。不得从自然语言建议抽取设备、参数或数值并直接改世界。
5. 联络成功进入即消耗该点会话；非法提案不返还。无改动须由玩家明确选择 KEEP_CURRENT；失败不自动转成该选择。成功部署在仍暂停时同步，随后立即生效并恢复 ACTION。联络时序见[主 Spec §6](../../PRELIMINARY_DESIGN_SPEC.md)和[机制基准 §4](../../侦测定位_机制草案.md)；助手权限以主 Spec v0.45 末尾迁移段和模块 5 最新 §0.8 为准。

## 1. Goal、任务单元与 Done Contract

最终目标：玩家在联络点用自然语言描述现场，个人助手据此追问、比较并提出有限设备动作；游戏程序凭结构化动作、玩家确认和可信权限校验提交变更。联络结束后，新配置影响下一物理步；系统 Agent 仍只在正常上报边界获得配置更新。

当前可独立验收的 **7A**：在模块 0–4B 当前代码上，做一台已显示摄像头的场景标记、模拟助手对话、单条摄像头扫描配置提案、玩家确认、安全提交、明确 KEEP_CURRENT、拒绝与重试。验收限定在单个灰盒轮次、首次猜测前；使用确定性模拟助手和可替换 fixture，不宣称真实模型或完整一局。

7A 完成须有实际运行证据：

- 玩家靠近未用联络点才能进入；进入后整个模拟、感知、上报和目标进度冻结，场景 UI 仍可交互。
- 标记在游戏画面中显示的一台摄像头，助手只收到本次句柄和玩家主动提供的信息；请求和回执无地图、设备位置、系统报告、隐藏玩家坐标或活动联络来源。
- 模拟助手可给纯文字回复，或一条对当前句柄的 `SetCameraScan` 结构化提案。文字回复不能修改世界。
- 玩家看到完整待改字段并确认同一份不可变提案；成功时程序把一条逻辑提案转换成至多两条针对**同一内部设备 ID**的底层 `SetDeviceParameter`，经现有命令服务原子提交。确认前改动、重新标记或旧请求回复不能偷换已展示的命令。
- 禁止第二目标、第二设备提案、未标记目标、越权字段、机器人/踏板/地图/报告动作；合法性或同步准备失败不留下部分修改、不恢复模拟。程序级同步激活故障继续按现有故障锁处理。
- 明确 KEEP_CURRENT 不改世界、不增加部署 revision、不消耗设备命令名额，但已使用的联络点保持 used。非法提案不自动 KEEP_CURRENT。
- 7A 新验收与 0–4B 回归通过，并记录真实结果；不复用历史测试计数当作模块 7 成绩。

## 2. In Scope / Out of Scope

### 7A In Scope

- 联络会话 UI：玩家文字输入、助手文字、已标记目标、待确认的完整动作、安全错误回执、确认和明确 KEEP_CURRENT。
- 单个屏幕中显示的摄像头标记与本次联络不透明句柄；不增加玩家视觉遮挡、迷雾、全设备列表或内部 ID 输入。
- 玩家助手的严格 plain-data 请求/响应 DTO，角色隔离和当前 `protocol_version/role/request_id/round_id/branch_id/guess_cycle_id` 身份检查。
- 确定性模拟助手，支持对话、合法/非法/迟到提案的脚本化验收，不接真实网络或模型密钥。
- `SetCameraScan` 一条逻辑命令，可含 `scan_center`、`scan_half_angle` 的非空子集；每次联络最多一个目标、一条获准设备命令。具体角度上下界从关卡/服务注入的原型规则读取，不把 fixture 当正式玩法值。
- 玩家确认后可信协调层构造 `WorldCommandBatch`；`GameSession.end_contact()` 仍负责离开暂停的门槛，`WorldCommandService` 仍负责角色白名单、参数、候选世界和同步。
- 对安全 REJECTED 的单会话内人工修正、换新请求身份及安全回执；不自动反复调用模拟助手。

### 7A Out of Scope

- 机器人 `SetPatrolPath` 的玩家助手工具与 UI；它保留在模块 7 后续切片，须按模块 5 最新世界/路线合同重新核对。
- 系统 Agent 的新增摄像头/机器人、移动组合障碍、踏板调度、公开世界状态、猜测和调度；这些属于模块 5 的独立实施与验收范围。
- 局部 RESET、整轮重启、四轮、旧分支历史恢复与跨周期重放；由模块 6 和模块 7 后续集成验收。
- 真实模型、真实 Gateway、墙钟超时/断线恢复、最终聊天轮数/字符数、正式关卡与数值平衡；由模块 8 前完成相应决策。
- 把玩家手动选择目标变成绕过助手的设备编辑菜单；玩家只绑定目标和确认/拒绝助手提出的完整动作。

## 3. Research：已实现事实与依赖图

下表记录 7A 规划时的 0–4B 基线；实施期间模块 5 同期迁移，现行代码与复审结果见 §8。

| 能力 | 当前事实 | 7A 使用方式 |
| --- | --- | --- |
| 联络入口 | 3B 的 `InteractionSystem` 生成 contact 请求；`GameRuntime` 处理 `used`、`active_contact_id`、猜测刻优先；暂停时 E 键目前仅 KEEP_CURRENT | 原样复用进入/消耗与阶段门槛，新增窗口，不增加另一个 used 写入口 |
| 阶段和请求 | `GameSession.begin_contact/end_contact/renew_world_request` 已有；`end_contact` 只接受可信 `WorldCommandResult` | 用当前 context，不接受助手自报 success；拒绝后新方案换 request_id |
| 命令服务 | `WorldCommandBatch` 目前只有单字段 `SetDeviceParameter`；`WorldCommandService` 有角色 policy、`max_commands`、原子候选和场景同步 | 7A 的一条逻辑命令在可信层展开为 1–2 条同 ID 底层命令；逻辑单目标约束在严格 DTO/可信协调层验证，服务仍做最终参数和世界校验 |
| 感知与报告 | 4B 已在行动步读当前权威世界，正常上报边界更新系统视图；事件时记录不能改写 | 验证改参后下一步观察受影响，既有观察不变，配置不提前进入系统视图 |
| 助手协议 | `AgentProtocol.make_player_assistant_request` 仅有基础投影；`response_matches` 不验证动作 payload；没有助手 Gateway | 新增助手专用严格合同与模拟端；现有通用 serializer 不能作为工具安全证明 |
| 主场景 | `Main` 当前给 `WorldCommandService` 传空 policy；`DeviceView` 内有实体 ID metadata，但画面不显示 ID | 注入只为 7A 的可信原型 policy；新增视觉目标选择，不把 metadata 或完整注册表交给助手 |

依赖与验收边界：

```text
模块 0–4B 已实现
    └─ 7A 摄像头联络最小切片：单轮、首次猜测前可独立验收

模块 5 最新 §0 的世界模型迁移 W1（已批准并在实施）与系统周期 W2（尚未完成）
    ├─ 7B 机器人工具和双 Agent 覆盖顺序集成
    └─ 模块 6 完整快照/分支/RESET（尚未实现）
         └─ 7C 联络点 used、助手历史、旧请求在两类 RESET 后的验收

模块 8 真实桥接与整场：真实助手、异常恢复、四轮体验
```

7A 仅依赖当前 0–4B 的**现有**接口。模块 5 的独立摄像头模型将改变设备表示和场景绘制，7A 应只依赖稳定的 `kind=camera`、目标 ID 解析和 `scan_center/scan_half_angle` 语义；若模块 5 先合入，7A Plan 的文件和测试 fixture 须据实际代码复核后再 Execute。不能让 7A 提前实施模块 5 的新 `MoveObstacle`、新相位字段或旧版 §10 Gateway 签名。

| 验收切片 | 必需前置 | 不以何者冒充已验收 |
| --- | --- | --- |
| 7A 摄像头联络 | 1 的 `GameSession` 暂停/身份、2 的命令服务与场景同步、3B 的联络入口、4B 的感知/统一报告 | 不要求 5 的系统 Agent，也不能把单窗口成功称为完整猜测周期 |
| 7B 机器人与双 Agent | 7A；模块 5 最新 §0 的世界/路线迁移、系统猜测和调度**实际实施并通过其范围验收** | 不能只凭模块 5 W1 进度或旧踏板-only Plan 验收 |
| 7C 回退与历史 | 7A/7B 所需联络状态；6 的周期起点快照、新分支身份、局部与整轮恢复**实际实施** | 人工修改 context 或复制 WorldState 不能代替真实 RESET |
| 真实助手与整场 | 7A–7C；8 的真实桥接、模型异常策略和四轮流程 | 确定性模拟助手不证明自然语言理解或真实网络恢复 |

## 4. 职责、接口与数据流（7A 拟议合同）

| 组件 | 职责 | 禁止事项 |
| --- | --- | --- |
| 玩家助手/模拟端 | 接收玩家文字、通用工具结构、自身历史及安全回执；回复文字或结构化单目标提案 | 不读地图、设备目录/位置、系统报告、玩家内部位置；不自行修改世界、宣告提交成功 |
| 游戏 UI | 收集文字；让玩家点选画面显示的摄像头；展示完整提案和安全结果；收取显式确认/KEEP_CURRENT | 不从建议文本解析动作、不自行判定权限或写世界 |
| `PlayerAssistantContract` | 严格构造角色视图、解析提案和限定字段；拒绝额外键/错误类型/错误身份 | 不持有或读取完整 `WorldState`，不提交命令 |
| 可信联络协调层（拟新增） | 维护当前句柄→内部 ID、待确认提案和身份；检查一条逻辑命令/一个目标；确认后展开底层批次并调用现有服务 | 不把内部 ID、坐标或内部错误详情写回助手请求/回执 |
| `GameSession` | 独占 phase、tick、当前请求身份、结束联络的成功回执门槛 | 不直接消费助手自然语言或自报结果 |
| `WorldCommandService` | 按可信 role policy 重验当前阶段、世界版本、参数范围、候选及同步；返回内部回执 | 不作为助手可调用的任意目标预检工具 |

拟议 DTO，具体 GDScript 名称可在 Plan Review 中按模块 5 合入状态调整，但语义不得放宽：

```text
ContactRequest = {
  context: 精确六字段（role="player_assistant"）, request_type: "contact",
  view: { player_text, selected_target: {ref, kind="camera"} | null,
          available_tools, tool_receipts, conversation }
}

ContactResponse = {context, status="ok", payload:
  {kind="MESSAGE", text}
  或 {kind="PROPOSAL", text, action:
      {type="SetCameraScan", target_ref, values:
       {scan_center?: finite_number, scan_half_angle?: finite_number}}}
}
```

`values` 至少一个字段，最多上述两个；额外 `id/cell/map/reports/heading/scan_direction/hit/success/phase` 或第二 action 均拒绝。`text` 只显示，不被解析为命令。`available_tools` 给工具**结构**和本次会话额度，不列出其它设备；`selected_target.ref` 是不透明会话句柄，不编码坐标或内部 ID。标记只发生在游戏画面已显示的摄像头节点上，不在 7A 新增玩家视线/迷雾系统。未标记时可以对话，但不能提交设备动作。

拟议可信接口：

```gdscript
static func make_contact_request(context: Dictionary, view: Dictionary) -> Dictionary
static func parse_contact_response(data: Variant, expected_context: Dictionary, selected_ref: String) -> Dictionary

func select_displayed_camera(entity_id: int) -> bool
func submit_player_text(text: String) -> bool
func receive_assistant_response(data: Dictionary) -> bool
func confirm_pending_proposal(proposal_token: String) -> bool
func choose_keep_current() -> bool
```

前两个静态函数属于 `PlayerAssistantContract`；非法 builder 返回空数据，parser 返回 `{ok, value, errors}` 的隔离结果，不在失败时给出部分可执行提案。其余为**游戏内部/UI→可信协调层**接口，不是对 Agent 公开的工具。`entity_id` 只来自玩家在场景中的点击命中和可信节点，不来自聊天文本或模型参数；UI 不显示内部整数。确认只传待确认提案令牌，程序使用此前冻结的提案副本、当前 context、当前目标句柄映射及当前 revision 构造批次；不接受 UI 另传一组不同字段。待确认时若改选目标、请求身份变化或世界版本变化，旧令牌失效，须重新提议并展示。成功或 KEEP_CURRENT 后清除当前句柄、待确认提案和 `active_contact_id`。

时序：

```text
ACTION 玩家到联络点 → 3B 提交本步 used=true → GameSession.begin_contact()
  → CONTACT_PAUSED：玩家标记画面中的摄像头并描述现场
  → 程序构造隔离 ContactRequest → 模拟助手文字/结构化提案
  → 严格解析、保存不可变提案 → UI 展示完整目标与字段
  → 玩家确认 → 可信层解析本次句柄为内部 ID
  → 生成 1–2 条同 ID SetDeviceParameter 的单批 WorldCommandBatch
  → GameSession.end_contact(deploy) → WorldCommandService 校验/准备/同步/提交
  → APPLIED 或合法 UNCHANGED：ACTION；下一个物理步读新配置
  → REJECTED：原世界、原 tick、CONTACT_PAUSED；安全回执和新 request_id 后可重提

或玩家明确 KEEP_CURRENT → 现有空批次路径 → ACTION
```

底层服务的 `max_commands=2` 仅容纳一个摄像头逻辑命令的两项字段，**不是两台设备的授权**；可信协调层须验证所有展开命令同一 ID，且一次联络最多一次成功设备提交。`WorldCommandService` 再以 `player_assistant` 的窄 policy 验证每条底层命令及参数范围。安全拒绝回执只含是否接受、通用错误码和必要的字段标识，不回传内部 ID、玩家占位、地图/坐标、合法位置建议或完整内部 `WorldCommandResult`。正式失败/超时的人机恢复策略仍由模块 8 定案；7A 只验收确定性模拟失败、拒绝后手动重提和故障门控。

## 5. Plan Draft：文件变化与原子检查点（仅 7A）

| 文件 | 拟议变化 |
| --- | --- |
| `game/scripts/agents/player_assistant_contract.gd`（新） | 精确角色请求/响应 DTO、结构化 `SetCameraScan` 和安全回执校验 |
| `game/scripts/agents/simulated_player_assistant.gd`（新） | 可脚本化文字、合法/非法提案与迟到回复；无网络、真实模型或世界读取 |
| `game/scripts/runtime/contact_session_controller.gd`（新） | 当前联络句柄、单目标/单命令限制、冻结待确认提案、确认与拒绝后新身份协调 |
| `game/scripts/runtime/game_runtime.gd` | 在既有 3B 联络入口挂载协调层；保持原物理步、报告和故障顺序；成功后明确清理活动联络状态 |
| `game/scripts/runtime/device_view.gd`、`game/scripts/runtime/runtime_world_view.gd` | 提供可信的屏幕目标选择/反馈；内部 ID 不出现在玩家文案或 Agent payload；不新增另一份设备权威状态 |
| `game/scenes/main.tscn`、`game/scripts/main.gd` | 增加联络窗口、目标标记、完整动作确认与 KEEP_CURRENT；Main 只组合组件和原型配置 |
| `game/scripts/runtime/prototype_config.gd` | 注入 7A 摄像头白名单、角度规则和模拟对话 fixture；不写正式平衡数值 |
| `game/tests/player_assistant_contract_tests.gd`、`game/tests/runtime_contact_tests.gd`（新） | 角色视图、DTO、确认/重试、真实场景与 4B 报告接缝验收 |
| `game/tests/run_tests.gd` | 注册新套件和失败码；保留已有测试入口 |
| `game/scripts/world/world_command_service.gd`、`game/scripts/core/game_session.gd` | 预期不改签名或规则；若实际代码需要改角色 policy 语义或阶段合同，先回本 Spec 重新审查 |

原子检查点：

1. **P0 基线/风险测试**：在当前工作树确认 0–4B 现有接口、模块 5 是否已变更；先补“文字不改世界、跨目标拒绝、确认不被偷换”的可失败测试。
2. **P1 严格 DTO 与模拟端**：角色白名单、完整字段、当前身份、单条逻辑命令、无坐标/报告泄漏；模拟端输入不含 `WorldState` 或系统视图。
3. **P2 画面标记与冻结提案**：玩家无需内部 ID；只接受已显示摄像头点击；当前联络句柄不可用于另一窗口；重选使旧提案失效。
4. **P3 可信提交与失败路径**：玩家确认后才展开同 ID 底层批次；真实命令服务和场景同步成功才结束暂停；拒绝后旧世界和时钟不变、换新请求；显式 KEEP_CURRENT 独立成立。
5. **P4 4B 与主场景验收**：部署下一步感知使用新配置；原记录保留事件时事实；系统配置只在下一正常边界更新；真实场景与旧回归通过。
6. **P5 证据回写**：记录测试、主场景、错误日志、实际文件差异、仍未验收的 5/6/8 接缝；未通过则留在 Plan/Execute 修正，不声称 Review PASS。

本节是已获用户 `Plan Approved` 的 7A 实施合同。P0–P5 已按本节执行；并行模块 5 的 W1 迁移已另行批准，但其 W2/旧 Plan 不作为本模块的实现基线。若需扩大到机器人、系统调度或 RESET，先回本 Spec 重新讨论范围。

## 6. 可观察验收场景

| 编号 | 场景和必须观察到的结果 | 验收阶段 |
| --- | --- | --- |
| C7-01 进入与冻结 | 到达未用点后进入 CONTACT_PAUSED、used=true；模拟 tick、机器人、目标进度、感知与报告不前进；点外/已用点不进入 | 7A |
| C7-02 无 ID 标记 | 玩家点击屏幕中显示的摄像头，UI 只示“已标记目标”；助手请求只有临时 ref，无内部 ID、位置或设备目录；未标记时不能提交 | 7A |
| C7-03 文字隔离 | 回复文本含“调转摄像头”或类似措辞，但无合法结构化 proposal：world/revision/phase 均不变 | 7A |
| C7-04 单逻辑命令 | 一条提案同时含两个获准扫描字段，玩家确认后展开成同一内部 ID 的两条底层命令，部署 revision 至多增加一次；第二设备或第二逻辑动作拒绝 | 7A |
| C7-05 确认完整性 | UI 展示后模拟端再回新值、玩家改选目标或旧请求迟到：旧确认令牌失效，未展示内容不能提交；仅当前已展示原样提案可提交 | 7A |
| C7-06 非法与重试 | 未知/过期 ref、越权字段、无界值、错误身份、旧分支、服务 REJECTED 均无部分变化；安全回执不泄露地图/占位；可修正拒绝后新 request_id，仍暂停 | 7A |
| C7-07 KEEP_CURRENT | 玩家明确选择后 ACTION 恢复、used 仍 true，设备、revision 不变；非法 proposal 不自动触发它 | 7A |
| C7-08 即时与上报 | 提交前旧记录不被改写；提交后首个 ACTION 感知步读新参数；配置更新只在下一统一上报边界进入系统视图，不附联络来源 | 7A |
| C7-09 故障门控 | 同步 prepare 拒绝则仍暂停且世界不变；activate 意外失败保持故障锁，不能用 KEEP_CURRENT 绕开 | 7A |
| C7-10 双 Agent 顺序 | 系统合法调度与助手改动按真实成功提交顺序覆盖同一控制项；两个 Agent 不同时持有可执行窗口 | 5+7B |
| C7-11 机器人助手 | 只对标记的一台已有机器人提出一条完整合法路线；锚点、四邻接、衔接和不瞬移由实际 5 合入后的世界服务校验 | 5+7B |
| C7-12 RESET | 局部回退恢复周期起点的 contact.used/世界/报告；旧句柄与回复作废，助手历史保留但标为旧分支；整轮重启各点重开 | 6+7C |
| C7-13 真实桥接 | 真正的助手模型按同一 DTO 提议，超时/断线/畸形输出有已批准恢复和玩家反馈；四轮内不越权、不从自然语言修改世界 | 8 |

## 7. 模块接缝与技术风险

- **模块 5**：其最新 §0 改摄像头表示、系统公开视图、机器人调度和组合障碍，且旧 Plan 已失效。7A 不引用其拟议接口；合入时复核 7A 的摄像头选择、参数名、服务 policy 和 4B 感知。7B 再接机器人工具与双 Agent 同项覆盖，不能把系统的公开地图或扫描相位给助手。
- **模块 6**：周期起点快照须包含 `WorldState` 中联络点 used、设备与 4B 待报记录；助手已接触文字和回执作为历史保留。周期起点在 ACTION，不应保存活动联络句柄；新 branch/round 使旧请求和句柄失效。7A 的成功只证明单窗口，不宣称 RESET 正确。
- **模块 8**：真实 Gateway 应沿用 7A 的严格提案 DTO 与玩家确认门槛；模型异常策略、墙钟超时和对话长度属于后续批准。密钥和完整内部状态不进入 Godot 共享项目或日志。
- **共享文件/并行**：模块 5 W1 同期修改了 `prototype_config.gd`、`runtime_world_view.gd`、`world_command_service.gd`、公开视图与共享 runner；模块 6 还会修改恢复编排。7A 保留同期改动，并在实际 W1 工作树上复测。`docs/features/README.md` 原有其它未提交条目保留，仅追加 7A 索引；模块 2 Spec 未触碰。
- **主风险**：把助手完整内部 ID/地图投影、任意目标预检或错误详情当工具；将两个底层参数误算成两条设备授权；确认后响应替换；把可修正 REJECTED 与不可恢复同步故障混为一谈；在模块 5/6 尚未存在时假验收双 Agent 或 RESET。

## 8. Validation、Plan Review 与 Resume

批准前仅做文档 Research / Grill / Plan Draft；当时未执行 Godot 测试或修改游戏代码。用户批准后执行了 7A。使用 Godot `4.7.2.stable.official.ed1daf0bf`，2026-11-28 初次实施验收的本机结果：

| 验证 | 实际结果 |
| --- | --- |
| `--editor --quit` 导入 | 退出码 0，最近一次无脚本解析错误 |
| `run_tests.gd -- --contact-only` | `PlayerAssistantContractTests` 14/0，`RuntimeContactTests` 52/0，退出码 0；包括真实 `main.tscn` UI 入口 |
| `run_sensing_tests.gd` | `SensingGeometryTests` 26/0，`SensingKernelTests` 88/0，退出码 0 |
| 完整共享 `run_tests.gd` | 0–4B 原有套件分别 81/0、226/0、47/0、344/0、129/0；并行模块 5 W1 新套件 6/0；7A 新套件 14/0、52/0。合计 **899 passed / 0 failed**，退出码 0。W1 新套件通过不等于模块 5 全部完成。 |
| `--contact-only --fail-probe` | 7A 两套仍 14/0、52/0，故意注入失败使 runner 退出码 1 |
| 主场景 | `FRAMEWORK_SHELL_READY`、`RUNTIME_GRAYBOX_READY`、`RUNTIME_INTERACTIONS_READY`、`RUNTIME_SENSING_READY`、`RUNTIME_CONTACT_READY` 均出现；真实主场景的联络窗口/发送/确认由测试调用并通过 |

7A 验收中，点击画面内摄像头产生临时句柄；结构化双字段提案在确认前不改世界，确认后同 ID 单批提交、revision 只进一次。暂停期间世界/感知/时钟不前进；事件时旧配置保留，新配置在下一行动步用于感知并到正常上报边界才进入系统视图。纯文字、非法字段、过期身份、越界值和同步 prepare 拒绝均不改世界；activate 故障锁住窗口，不能借 KEEP_CURRENT 继续。并行模块 5 W1 后续继续修改共享模型时仍须重跑集成测试。

Plan Review 关注：一条逻辑命令与底层 1–2 条的权限闭合、玩家确认完整性、角色视图泄漏、3B 消耗与 4B 报告时序、模块 5 世界模型迁移后的文件冲突。若评审发现接口必须扩大到真实模型、系统调度或 RESET，先修订本 Spec 并重新讨论范围。

### 同行复审（2026-11-28）

独立评审者按本 Spec 与当前代码复核，发现一项 7A P2：普通 `Label` 在长对话中会撑开固定高度联络面板，使提案或按钮离开可视区域。已将记录区改为 `RichTextLabel` 内部滚动，并在真实主场景连续 16 轮文字后验证滚动跟随最新提案、确认/KEEP_CURRENT 按钮仍可见；评审者独立复跑并确认关闭。随后将文本更新改为仅内容变化时赋值，新增手动上滚回看不被每帧刷新打断的检查。最终复测 `--contact-only`：`PlayerAssistantContractTests` 14/0、`RuntimeContactTests` 54/0，合计 **68/0**、退出码 0。仓库检查 `1213 files / 0 issues`，链接检查 `73 documents / 0 broken`。

评审同时记录后续接缝：通用 `AgentProtocol.serialize_request()` 的玩家白名单目前不含 `selected_target`，若模块 8 直接复用会静默丢失临时句柄；模块 5 的组合角色 policy 已出现，且并行实现已把 `Main` 改为 `combined_policy()`，其系统周期仍需独立验收。服务层 `max_commands=2` 本身不约束同一目标；7A 的单目标约束由可信协调层完成，真实 Gateway 不得直接连接 `commit_batch()`。同步 activate 故障会令协调层拒绝 KEEP_CURRENT，当前未发现可达绕过。

复审时并行模块 5 正在新增周期代码。最近一次完整共享 runner：原 0–4B 套件 81/0、226/0、47/0、344/0、129/0；模块 5 世界 7/1（私有历史注入检查失败）、周期 6/0；7A 14/0、54/0，合计 **908 passed / 1 failed**、退出码 1。初次实施验收的 899/0 是当时 W1 工作树的历史结果，不能写成**当前**完整共享入口全绿；剩余失败需模块 5 收敛后复测。

### Review Matrix（7A）

| 轴 | 结论 | 依据与限制 |
| --- | --- | --- |
| Spec 质量与达成 | PASS | C7-01–09 的 7A 可观测场景已由新套件覆盖；C7-10–13 明列后续依赖，未冒充完成。最终平衡数值仍仅为 fixture。 |
| Spec 与代码一致性 | PASS | `PlayerAssistantContract` 精确 DTO；`ContactSessionController` 冻结提案/句柄映射/单目标展开；`Main` 只编排；`GameSession` 和 `WorldCommandService` 仍分别控制阶段与命令。代码未从助手文字提取动作。 |
| 代码自身质量 | PASS（7A），共享集成待收敛 | 同行发现的长对话 P2 已修复并独立复核；另补手动滚动检查，7A 68/0。最近完整共享入口 908/1，唯一失败在模块 5 世界新测试，不能宣称当前整体通过。 |

Overall Verdict：**PASS（仅 7A 范围；独立同行复审 P2 已关闭）**。当前完整共享 runner 因并行模块 5 周期施工未全绿；7B、7C、真实助手和四轮流程未验收。

### Plan-Execution Diff

- 并行模块 5 在 7A 开发期间开始更换摄像头世界模型并修改 `RuntimeWorldView`、`PrototypeConfig`、`WorldCommandService`、共享 runner；7A 保留其改动，只把自身方法合入，未采用模块 5 未完成的系统调度接口。主场景和测试均以实际迁移中的当前模型运行。
- `parse_contact_response` 入参从拟议 `Dictionary` 收紧为可接受任意 `Variant` 并安全拒绝非对象输出；这是畸形回复防护，不扩大工具权限。
- 共享 runner 新增 `--contact-only` 选择以单独验证 7A；主场景 UI 功能测试、同步 prepare/activate 故障测试比 Plan 最小清单更具体。未新增机器人或 RESET 逻辑。
- 同行复审后把联络记录区改为可滚动 `RichTextLabel`，仅内容变化时重赋文本；新增长对话后最新提案/按钮可视与手动回看检查，7A 专属检查由 66 增至 68 项。

Resume：当前 phase=`REVIEW`（仅 7A），approval=`Plan Approved`，status=`REVIEW PASS（7A 范围），完整共享入口受模块 5 周期开发影响待复测`。模块 5 周期改动收敛后重跑完整入口，核对摄像头 DTO/白名单与主场景组合 policy；7B/7C 不随本次批准启动。

## 9. 7B／7C 待 Grill（均非 Plan Approved）

已定边界不重开：7B 只能选一台**已有**机器人，单次联络的一条完整路线命令，由玩家确认并经程序校验；助手不读地图、系统报告、机器人隐藏坐标或玩家坐标，也不改机器人实时位置。7C 的局部回退恢复周期起点 `contact.used`，整轮重启重开联络点；两类 RESET 都保留各 Agent 已接触的历史并废止旧请求，不能把旧分支事实当当前观察。

真正待裁决的 7B 问题是**无地图的助手如何给出可校验路线**：底层 `SetPatrolPath` 要求整数格列表，但助手当前只收到玩家描述和不透明目标句柄。候选方案是让助手提出从可信当前段终点开始的有限方向序列，游戏程序在确认前展开成完整 `SetPatrolPath`、画面预览并最终校验；这不向助手泄露起点格或地图。另一方案是玩家通过 UI 显式提供格点，助手再提议完整路径，但必须防止玩家直接绕过助手形成设备编辑菜单。两者均未获批准；路线长度、重试次数和可见范围仍为待试玩配置。

### 9.1 7B Grill Round 1（2026-11-28；Research / LOCKED）

本轮只质询 7B，不修改游戏代码，不进入 Plan／Execute；7A 的 Review PASS 和既有权限边界不重开。核对依据包括主 Spec §4／§13、机制基准 §2／§8、模块 5 当前路线实现，以及 7A 的 `PlayerAssistantContract`、`ContactSessionController`。**结论：NO-GO 进入完整 Plan，先裁决 G7B-1、G7B-2、G7B-3、G7B-5；其余项可作为派生合同进入后续 Plan。**

| 编号 | 质询与风险 | 推荐收口（尚非用户裁决） |
| --- | --- | --- |
| G7B-1 公开路线表示 | 直接把底层整数格 `cells` 暴露给助手会变相提供坐标／地图工具；让玩家自由编辑格点又可能绕开助手形成设备编辑菜单。 | 公开逻辑动作使用有限 `N/E/S/W` 方向序列，不公开 `SetPatrolPath.cells`。可信程序从当前段终点展开完整格路线；不采用玩家自由格点编辑器。 |
| G7B-2 驻守与长度 | 底层空路线非法，但单点路线表示驻守；若空方向序列也一律非法，助手无法让机器人在当前段终点驻守。步数若无上限，DTO、预览和模型输出均无界。 | 空方向序列明确展开为 `[anchor]`，表示**驻守当前段终点**；KEEP_CURRENT 仍表示保留旧路线，二者不得混淆。非空序列逐步四邻接；`max_route_steps` 由原型 policy 注入，首版不在本 Grill 定正式数值，不额外禁止往返或重复格。 |
| G7B-3 “一个目标”与重选 | §0 的“每次联络最多一个目标”若解释为首次标记后锁死，会与 7A 已验收的“重选使旧提案失效”冲突；若允许跨设备重选，又须防止一次会话成功提交多目标。 | 保持 7A 现行语义：确认前可重选画面中的摄像头／机器人，重选作废旧提案、回执身份和预览；每条提案及每次成功提交仍只能有一个目标，每次联络至多一次成功设备命令。若需“首次标记即锁定”，必须另改 7A 合同并重验。 |
| G7B-4 展开与确认一致性 | 助手给方向、程序给格路线，若玩家只确认方向而未看到展开结果，就不满足“确认完全一致的不可变内容”；若把展开格路线回传给助手，又会泄漏锚点和地图。 | 确认前冻结目标句柄、方向序列、可信锚点、展开后的完整格路线、world revision 和请求身份。**完整格路线只向玩家预览，不进入助手请求或回执**；玩家确认同一份方向提案及其展开结果。重选、迟到回复、身份或 revision 变化均使预览和确认令牌失效。 |
| G7B-5 拒绝回执成为地图探针 | 逐格错误码、失败索引、合法位置建议或无限重试会让助手用接受／拒绝反推隐藏起点与地图，即使没有直接地图字段。 | 世界／路径合法性失败只给助手统一 `ROUTE_REJECTED`，不含失败步、格、锚点、合法建议或内部结果；DTO 结构错误仍可用不具空间信息的通用协议错误。路线正式尝试次数由配置限制，耗尽后仍暂停且只允许玩家明确 KEEP_CURRENT 或放弃路线工具，不自动 KEEP、不因普通路线拒绝 STOP。 |
| G7B-6 隐藏玩家与路径校验 | 若助手路线因隐藏玩家占位而接受／拒绝，回执会泄露玩家位置；系统调度的新增机器人禁区规则不能无意复制到助手换路。 | 助手换路只校验公开静态结构、现有设备规则、路线衔接和助手 policy，不读取或依赖玩家真实位置，不附加系统 `obstacle_protection_radius`。路径与演员共格的既有运动规则继续由程序处理；增加“玩家位于候选路线不改回执”的验收。 |
| G7B-7 工具与目标隔离 | 摄像头和机器人共用会话后，额外字段、混合动作或以文本指定另一台设备可能绕过单目标限制；把机器人现有 `patrol_path`、位置或内部 ID 放进工具描述也会越权。 | 严格按当前标记类型提供唯一工具：摄像头仅 `SetCameraScan`，机器人仅方向路线动作；目标仍是不透明会话句柄。助手请求不得包含内部 ID、当前／旧路径、锚点、格坐标、地图、系统报告或玩家位置；文本不能选择目标或生成世界变更。 |
| G7B-8 双 Agent 覆盖与报告边界 | 只测“助手成功”不能证明系统与助手顺序覆盖安全；并发窗口或旧 revision 提交可能覆盖较新的合法配置。 | 沿用互斥 phase、当前 request identity 和 world revision。验收系统→助手、助手→系统两种合法顺序，同项由后一次真实成功提交覆盖、无关项保留；不存在同时可执行窗口，旧提案不能覆盖新 revision。路线配置仍只在下一正常统一上报边界进入系统视图。 |

推荐的最小裁决包是：**方向序列；空序列驻守；确认前可重选但仅一次成功提交；完整路径只给玩家预览；有界路线尝试与统一安全拒绝。**这是对现有规则改动最小、信息边界最闭合的组合，不等于已经获得批准。路线最大步数、正式重试次数和真实模型对话轮数继续是可替换原型／后续模块 8 配置，不在本轮编造数值。

后续 Plan 还必须列出公开 DTO、可信展开与预览的数据归属、机器人画面标记、policy、双顺序验收及失败原子性。当前共享 runner 另有模块 6 在途代码导致的编译阻塞（缺少 `RuntimeSensingCoordinator.from_cycle_checkpoint()`、`SystemAgentHistory.from_snapshot()`）；这不是 7B 设计否决项，但 **Execute 前必须恢复可编译基线并重跑 5／7A 回归，不能用历史 920/0 或 68/0 代替当前证据**。7B 不实现 RESET 历史 UI、真实模型或四轮整场。

### 9.2 7B Grill 裁决（2026-11-28；用户明确“同意这些决策”）

本节是 7B 当前设计合同，取代 §9.1 中“待裁决／尚非用户裁决”的状态；§9.1 保留为质询记录。用户批准的是以下设计决定，**不是 Plan Approved，不授权 Execute**。

1. **G7B-1 采用方向序列。**助手公开逻辑动作只含有限 `N/E/S/W` 序列，不开放底层整数格 `SetPatrolPath.cells`，也不采用玩家自由格点编辑器。可信程序从暂停时当前段终点展开完整格路线。
2. **G7B-2 明确驻守和有界长度。**空方向序列展开为 `[anchor]`，表示驻守当前段终点；KEEP_CURRENT 保留旧路线，二者不等价。非空序列逐步四邻接，允许既有规则下的往返和重复格；`max_route_steps` 由原型 policy 注入，正式数值仍待试玩。
3. **G7B-3 保持确认前可重选。**玩家可在确认前重选画面中的摄像头或机器人；重选作废旧提案、回执身份和预览。每条提案及每次成功提交只有一个目标，每次联络至多一次成功设备命令，不修改成首次标记即锁定。
4. **G7B-4 玩家确认完整展开结果。**确认前冻结目标句柄、方向序列、可信锚点、完整格路线、world revision 和请求身份。完整格路线只向玩家预览，不进入助手请求或回执；重选、迟到回复、身份或 revision 变化均使预览和确认令牌失效。
5. **G7B-5 有界尝试与统一安全拒绝。**世界／路径合法性失败只向助手返回 `ROUTE_REJECTED`，不含失败步、格、锚点、合法建议或内部结果；DTO 结构错误只给不具空间信息的通用协议错误。路线正式尝试次数由配置限制；耗尽后路线工具关闭，会话仍暂停，只能由玩家明确 KEEP_CURRENT 结束，不自动 KEEP、不因普通路线拒绝 STOP。
6. **G7B-6 至 G7B-8 按推荐收口。**助手换路不得读取或依赖玩家真实位置，不附加系统 `obstacle_protection_radius`；按当前标记类型提供唯一工具，请求不含内部 ID、当前／旧路径、锚点、格坐标、地图、系统报告或玩家位置。双 Agent 验收两种合法覆盖顺序，互斥 phase、当前身份和 revision 共同阻止并发及旧提案覆盖；路线配置只在下一正常统一上报边界进入系统视图。

7B 当前 phase=`RESEARCH COMPLETE / READY FOR PLAN`，approval=`Plan NOT APPROVED`。下一步可编写精确 DTO、文件变化、公开签名、原子 Checklist 和 Validation Plan；路线最大步数、正式尝试次数及真实模型对话限制仍为配置或模块 8 决策。

7C 的游戏规则已足够明确，主要需等模块 6 给出真实快照、分支和整轮恢复接口，再裁定**旧分支对话在玩家 UI 中的呈现**：推荐将已发生的描述、提案与安全回执保留为带轮次/分支标记的可查看历史，当前联络单独显示；旧目标句柄、待确认令牌和在途响应一律不恢复。此处是 UI／历史 DTO 设计问题，不改变 RESET 次数、联络点恢复或记忆保留规则。

## 10. 模块 7B 详细实施 Plan（2026-11-28；Plan Approved / REVIEW COMPLETE）

### P0. Goal、范围、Done Contract 与执行基线

目标：在已验收的 7A 联络窗口中增加一台已显示机器人的标记、方向路线提案、可信展开、完整路径预览、玩家确认、原子提交和双 Agent 顺序覆盖；全程不向助手开放地图、坐标、内部 ID、现有路径或系统报告。

In Scope：确定性模拟助手；单个灰盒联络；摄像头 7A 回归；机器人当前段终点锚定、移动路线与单点驻守；有界 DTO 和路线拒绝；真实场景、感知与统一报告接缝；系统→助手和助手→系统两种顺序。双顺序集成测试可使用当前 `ResetCoordinator.capture_initial_checkpoint/complete_cycle_start` 让真实系统调度后的周期继续行动，但不验收局部／整轮 RESET。

Out of Scope：玩家自由格点编辑器、自动寻路、斜向路线、实时改位置、7C 历史和 RESET UI、真实 Gateway／网络／模型异常策略、四轮整场和正式数值平衡。不得为通过测试调用 `resume_cycle(true)` 伪造未保存的检查点。

Done Contract：

1. 玩家只能点击画面内已有摄像头或机器人；助手请求只有临时 ref、目标 kind、对应工具、玩家文字、对话和安全回执。机器人工具不含当前位置、anchor、旧 `patrol_path`、格列表或内部 ID。
2. `SetPatrolRoute` 的 `steps` 只含 `N/E/S/W`，长度受配置限制；空数组合法并表示当前段终点驻守。任何原始 `SetPatrolPath`、格坐标、第二 action、跨目标、额外字段或混合类型提案均被 DTO 拒绝。
3. 可信层在暂停世界展开路径，在预览前用现有命令服务做非发布校验；非法路径不改变活动世界、revision、tick、报告或感知。合法路径只向玩家显示完整预览，确认时重新经真实 `end_contact/commit_batch/SceneWorldSyncAdapter` 提交。
4. 机器人在格心或段中均不瞬移：先完成原当前段，再接冻结的新路径；单点路径在当前段结束后驻守。KEEP_CURRENT 保留旧路径。
5. 路径／世界拒绝只向助手暴露 `ROUTE_REJECTED`；有界正式尝试耗尽后除明确 KEEP_CURRENT 外不能继续操作。隐藏玩家是否位于候选路径不改变校验结果或回执。
6. 重选、迟到回复、错误身份、旧 revision 和重复令牌不能提交；prepare 拒绝保持暂停和原世界，activate 故障继续锁定，不能借 KEEP_CURRENT 绕开。
7. 系统与助手两种成功顺序均满足同项后提交覆盖、无关项保留和 phase 互斥；助手路径只在正常上报边界进入系统视图，旧事件保留事件时配置。
8. 7B 专项、7A／5／6 及完整共享回归、4A 独立套件、失败探针、主场景和 Windows smoke 均有当前日志；不把历史计数当本模块结果。

**规划时实测基线。**当前共享 runner 已能编译，规划会话实跑合计 **940 passed / 1 failed**，唯一失败为 `RuntimeSceneTests` 的 `restored floor allows real player movement`；7A 当时为 14+54 通过，模块 5 为 12+12 通过。该结果只用于暴露基线风险。B0 必须在实际 Execute 工作树重新运行并要求全绿；不得修改该旧测试断言、跳过套件或在 7B 中顺带修复模块 6。若基线仍红，停在 B0 交回对应模块。

### P1. 精确公开 DTO 与可信内部数据

`ContactRequest` 顶层继续严格为 `{context, request_type:"contact", view}`，`view` 字段保持 `player_text/selected_target/available_tools/tool_receipts/conversation`。`selected_target` 扩展为：

```text
null
或 {ref: 非空本次会话字符串, kind: "camera"|"robot"}
```

未标记时 `available_tools=[]`，只能交流不能提案；摄像头时为 `[SetCameraScan tool]`，机器人时为 `[SetPatrolRoute tool]`。路线工具结构严格为：

```text
{name:"SetPatrolRoute", fields:["steps"], directions:["N","E","S","W"],
 max_actions:1, max_targets:1, max_route_steps:int >= 0}
```

路线响应沿用 `{context,status:"ok",payload:{kind:"PROPOSAL",text,action}}`，action 严格为：

```text
{type:"SetPatrolRoute", target_ref: 当前机器人 ref,
 values:{steps: Array[String]}}   // 每项仅 N/E/S/W，size <= max_route_steps；允许空数组
```

摄像头 DTO 和默认 7A 调用保持兼容。解析器按可信传入的 `selected_kind/max_route_steps` 校验动作类型；助手自报 kind、policy 或额度无效。`AgentProtocol.serialize_request()` 对 `request_type="contact"` 增加显式白名单序列化，保留 `selected_target` 且拒绝额外／禁止字段，不再落入系统 Agent 分支或静默丢句柄；它不替代 `PlayerAssistantContract` 的完整 DTO 校验。

可信层从当前权威机器人实体计算 anchor：有 `transition` 取其 `to_cell`；否则段进度大于零取运动方向上的下一格；否则取 `path_index` 对应格。展开结果为 `[anchor] + directions 逐格偏移`，空 steps 保持 `[anchor]`。展开只生成数据，不写世界；现有 `WorldState._set_patrol` 与展开共用同一 anchor helper，避免两套衔接语义漂移。

待确认路线冻结 `{action, selected_ref/id/kind, anchor, cells, context, base_world_revision, token}`。`cells` 和 anchor 只存在可信协调层及玩家 UI／场景预览，不进入 ContactRequest、对话、工具回执或模拟助手返回值。路线正式尝试计数只统计**结构合法、进入世界／路径校验但被拒绝**的提案；纯 DTO／身份错误不泄漏空间信息，也不计作一次世界路径尝试。

### P2. 提交流程、失败映射与 UI 状态

```text
CONTACT_PAUSED 点击画面机器人 → 新临时 ref，仅路线工具
→ 助手 SetPatrolRoute(steps) → 严格 DTO
→ 可信 anchor/cells 展开 + 单条 SetPatrolPath 的候选批次
→ WorldCommandService.validate_batch（非发布、无 SceneSync、无计数缓存）
→ 拒绝：统一 ROUTE_REJECTED，计一次路线尝试，清预览，换 request_id（未耗尽时）
→ 合法：冻结 action/anchor/cells/context/revision/token，场景显示完整路径
→ 玩家确认同一 token → end_contact → commit_batch → SceneSync → ACTION
```

- 确认时只使用冻结数据重建同一底层批次，UI 不得另传 cells。重选、改方案、收到迟到回复或检测身份／revision 不符时清除 pending 和预览。
- 路线在正式 commit 出现普通路径／权限／世界拒绝时同样映射 `ROUTE_REJECTED` 并计一次；`STALE_WORLD/STALE_BRANCH/INVALID_CONTEXT` 映射既有 `STALE_PROPOSAL`，不计路径尝试；`SYNC_PREPARE_FAILED` 保持 7A 的可恢复 `CHANGE_REJECTED`，不计路径尝试；`SYNC_ACTIVATION_FAILED` 保持终止故障。
- 每次拒绝保持原世界、tick、报告和暂停。达到 `max_route_attempts` 后进入 `route_locked`：选择、发送、改方案和确认均拒绝，UI 禁用相应控件，只保留明确 KEEP_CURRENT；不自动结束、不生成设备 revision、不 STOP。
- 摄像头路径继续使用 7A 的 `CHANGE_REJECTED` 和既有重试语义，不消耗路线尝试。每次成功 APPLIED／UNCHANGED 关闭联络，故不能出现第二次成功设备提交。
- 场景预览显示所有路径格及端点；多点用连线，单点驻守也必须有可见标记。关闭、重选、拒绝、提交、场景重建和 `invalidate_for_branch_change()` 均清理目标高亮与预览。
- Main 文案按 `selected_kind` 显示摄像头或机器人；路线提案显示方向和“驻守当前段终点”／完整场景预览，不显示内部 ref、ID 或坐标表。`route_locked` 时只保留 KEEP_CURRENT。

### P3. 精确文件变化

| 文件 | 变化 |
| --- | --- |
| `game/scripts/agents/player_assistant_contract.gd` | 增加方向常量、路线工具描述、robot selected_target、严格 `SetPatrolRoute` 解析及步数上限；保持摄像头默认调用兼容 |
| `game/scripts/agents/agent_protocol.gd` | 修正 contact 白名单序列化，保留 `selected_target` 并拒绝地图／报告／坐标等禁止字段；不改系统 DTO |
| `game/scripts/agents/simulated_player_assistant.gd` | 按 selected kind 返回文字、摄像头提案或可脚本化路线提案；仍不接收 WorldState／SystemAgentView |
| `game/scripts/runtime/contact_session_controller.gd` | 通用目标选择、路线规则、展开与预校验、冻结 cells、玩家预览、确认、计数／锁定、安全回执及清理 |
| `game/scripts/world/world_state.gd` | 提取公共 patrol anchor helper 和纯方向展开；`_set_patrol` 复用 anchor，既有校验／运动语义不变 |
| `game/scripts/runtime/runtime_world_view.gd` | 同时命中 DeviceView 摄像头与 RobotController 机器人；通用高亮；完整路径／单点预览及全清理；保留 7A camera wrapper |
| `game/scripts/runtime/device_view.gd`、`game/scripts/runtime/robot_controller.gd`、`game/scenes/runtime/robot.tscn` | 摄像头高亮泛化及机器人 Selection 节点／接口，不新增设备权威状态 |
| `game/scripts/runtime/game_runtime.gd` | 屏幕点击改走通用 contact target；其余 phase、Agent 泵和提交职责不变 |
| `game/scripts/runtime/prototype_config.gd` | 助手 policy 增加已有机器人 `SetPatrolPath`；注入原型 `max_route_steps=4`、`max_route_attempts=2` 和确定性路线 fixture，均非正式数值 |
| `game/scripts/main.gd` | 注入路线规则／模拟 fixture，按目标类型展示提案、路径／驻守和锁定状态；输出 `RUNTIME_ROBOT_CONTACT_READY` |
| `game/tests/player_assistant_contract_tests.gd` | 扩展 DTO、序列化、信息白名单和畸形路线红测，保留全部摄像头用例 |
| `game/tests/runtime_robot_contact_tests.gd`（新） | 真实场景机器人选择、锚定、驻守、确认、拒绝、锁定、隐藏玩家、故障和报告接缝 |
| `game/tests/module7b_dual_agent_tests.gd`（新） | 两种真实成功顺序、互斥窗口、旧提案和正常配置上报；仅用真实检查点继续周期 |
| `game/tests/run_tests.gd` | 注册新套件；`--contact-only` 纳入 7A+7B 联络套件，新增 `--module7b-only` 选择；失败探针仍退出 1 |
| `game/README.md`、本 Feature Spec | Execute 后记录当前命令、计数、日志、Review、Plan-Execution Diff 和剩余边界 |

`game/scripts/core/game_session.gd`、`game/scripts/world/world_command_service.gd`、`game/scripts/world/world_command_batch.gd` 的公开签名和权限规则预期不变；`game/scenes/main.tscn` 不新增设备编辑控件。若实施证明必须修改这些核心合同，先回 Plan 审查，不直接扩张。

### P4. 目标公开签名

```gdscript
# PlayerAssistantContract
const DIRECTIONS: Array[String] = ["N", "E", "S", "W"]
static func route_tool_description(max_route_steps: int) -> Dictionary
static func parse_contact_response(data: Variant, expected_context: Dictionary, selected_ref: String, selected_kind: String = "camera", max_route_steps: int = -1) -> Dictionary
# make_contact_request(context, view) 与 tool_description() 签名不变，校验按目标类型收紧

# SimulatedPlayerAssistant
func _init(scan_values: Dictionary = {"scan_center": 0.2, "scan_half_angle": 0.4}, route_steps: Array = []) -> void

# ContactSessionController
func _init(session: GameSession, service: WorldCommandService, view: RuntimeWorldView, assistant: SimulatedPlayerAssistant, route_rules: Dictionary = {}) -> void
func select_displayed_target(entity_id: int) -> bool
func select_displayed_camera(entity_id: int) -> bool # 7A 兼容 wrapper
# submit/receive/discard/confirm/keep/invalidate 公开签名不变

# WorldState
static func patrol_anchor(entity: Dictionary) -> Array
func expand_patrol_path(entity_id: int, steps: Array) -> Array

# RuntimeWorldView
func is_contact_target_displayed(entity_id: int) -> bool
func contact_target_at_screen_position(screen_position: Vector2) -> int
func mark_contact_target(entity_id: int) -> void
func set_contact_route_preview(cells: Array) -> void
# is_camera_displayed/camera_at_screen_position/mark_camera 保留为 7A 兼容 wrapper

# RobotController
func set_marked(marked: bool) -> void

# PrototypeConfig
static func player_assistant_route_rules() -> Dictionary
static func simulated_assistant_route() -> Array
```

空 `route_rules={}` 表示机器人路线工具不可用，保证旧摄像头 fixture 默认安全；Main 和 7B fixture 必须显式注入精确 `{max_route_steps:int >= 0, max_route_attempts:int > 0}`。`expand_patrol_path` 只对合法机器人和方向返回新数组，空 steps 返回 `[anchor]`，其它无效输入返回 `[]`，不修改实体。`get_ui_snapshot()` 在现有字段上增加 `selected_kind/route_locked/route_attempts_remaining`；路线 proposal 增加仅供可信 UI 的 `anchor/preview_cells`，这些字段不得回传助手。

### P5. 原子 Checklist（获批后按顺序执行）

- [x] **B0 当前基线与红测准备**：复核 `git status` 和共享文件，保留所有未提交改动；重跑 import、完整共享和 4A 套件，要求当前全绿并保存 `tmp/module7b-baseline-*.log`。若仍有非 7B 失败则停止。随后新增 DTO／原始 cells／越界步数／序列化句柄红测，确认按预期失败。
- [x] **B1 严格合同与模拟端**：实现路线工具、selected kind、解析上限和 contact serializer；完成模拟机器人响应。跑合同套件，验证无 ID／anchor／cells／旧路径／地图／报告泄漏，摄像头旧用例不删不改义。
- [x] **B2 锚点、目标与预览红测／实现**：先写格心、段中、空 steps、往返、非法方向和单点预览失败用例；再实现 WorldState 纯展开、通用设备命中、机器人高亮和场景预览。验证 `_set_patrol` 旧回归及不瞬移。
- [x] **B3 可信路线会话红测／实现**：先写合法确认、路径拒绝、两次拒绝锁定、隐藏玩家等价、重选／迟到／旧 revision、prepare／activate 故障和 KEEP_CURRENT 用例；再实现协调层预校验、冻结、提交、安全回执与清理。任何失败均无部分世界变化。
- [x] **B4 主场景、报告和双 Agent**：接 Main／Runtime／fixture；新增 7B 两套真实场景套件。验证段中换路、驻守、完整预览、主 UI 按钮、下一正常边界配置更新、旧事件配置不变，以及系统→助手／助手→系统覆盖和互斥窗口；不得伪造 checkpoint。
- [x] **B5 全面验证与 Review**：执行 P6 全部门禁，记录实际计数和日志；按 Spec 质量／Spec—代码一致性／代码质量三轴 Review，回写 Plan-Execution Diff。只把实际通过的 7B 范围标 PASS，7C／8 不随本模块关闭。

### P6. Validation Plan 与回炉条件

从仓库根目录使用 Godot `4.7.2.stable.official.ed1daf0bf`：

1. `--headless --path game --import`：退出 0，无脚本解析错误。
2. `--headless --path game --script res://tests/run_tests.gd -- --module7b-only`：新 DTO、机器人联络和双顺序套件全绿。
3. `--headless --path game --script res://tests/run_tests.gd -- --contact-only`：7A 原有用例与 7B 联络全部通过，长对话滚动／按钮不回退。
4. 完整 `run_tests.gd` 与独立 `run_sensing_tests.gd`：当前共享及 4A 全绿；记录各 suite 和总计，不沿用 920/0、68/0 或规划时 940/1。
5. `--module7b-only --fail-probe`：退出 1；真实主场景 120 帧和 Windows Desktop release 导出程序均退出 0，包含 `RUNTIME_CONTACT_READY`、`RUNTIME_ROBOT_CONTACT_READY`、`RUNTIME_AGENT_READY`，无注入外故障。
6. 主场景／专项用例必须实际观察：机器人屏幕标记、合法路线预览、单点驻守标记、段中完成原段后接新路线、路线锁定后仅 KEEP_CURRENT；不能只断言 helper 输出。
7. 运行 `python -m unittest discover -s tests -v`、`python scripts/check_repository.py`、`python scripts/check_project_links.py --all`、`git -c core.whitespace=cr-at-eol diff --check`。日志放 `tmp/module7b-*.log`，导出程序放 `tmp/`，不提交密钥或生成包。

若需要向助手公开 anchor／cells／旧路径、依赖隐藏玩家校验、给予玩家自由格点编辑、绕过玩家确认／SceneSync、伪造检查点，或必须改变 GameSession／WorldCommandService 核心权限，立即停在对应 B 点回 Research／Plan。普通路线拒绝不得通过自动 KEEP、STOP 或放宽路径校验来消除。

### P7. Plan 自检、审批与 Resume

Plan 自检：已给出公开 DTO、可信展开、冻结确认、失败映射、隐藏信息边界、精确文件表、目标签名、原子 Checklist、真实场景与双顺序验收；7A 默认接口和既有命令服务保持兼容。原型 4 步／2 次仅是可替换 fixture，未升格为正式玩法。主要实施风险为机器人两类节点的高亮命中、段中 anchor 复用、预校验与正式提交的错误映射，以及共享模块 6 基线波动，均有独立红测和停止条件。

**审批记录：用户于 2026-11-28 明确回复 `Plan Approved`。**按单步 Execute 门禁进入 B0，不视为 B1–B5 的批量执行授权；仍须先取得当前全绿基线。

**B0 实际证据。**2026-11-28 保留现有工作树后，Godot import 退出 0（`tmp/module7b-baseline-import.log`）；完整共享套件 **945 passed / 0 failed**，退出 0（`tmp/module7b-baseline-shared.log`）；4A Geometry 26＋Kernel 88＝**114/0**，退出 0（`tmp/module7b-baseline-sensing.log`）。随后只扩展 `game/tests/player_assistant_contract_tests.gd`：contact-only 运行得到 Assistant **18 passed / 3 failed**、RuntimeContact **54/0**，runner 按预期退出 1（`tmp/module7b-red-contract.log`）。三个红项是 contact wire form、序列化保留临时目标、机器人路线工具请求；原始 cells／越界步数／非法方向负例已纳入。B0 未修改生产代码。

**批量执行授权。**用户随后明确要求“直接一口气完成B的所有环节”，构成 B1–B5 的 Batch Override；仍须逐项验证、遇合同冲突立即回 Plan，不代表预先通过 Review。

Resume：7B phase=`EXECUTE / B1–B5 BATCH`，approval=`Plan Approved`，spec=`docs/features/2026-11-28_module-7-player-contact.md` §10。当前从 B1 连续执行至 B5，逐项回写证据；不得把中间红测或单套件通过称为整个 7B 通过。7A 的 Review PASS、7B 的 Grill 裁决和 7C／8 的后置边界继续有效。

## 11. 7B Execute Validation 与 Plan-Execution Diff（2026-11-28）

B1 合同与 7A 回归为 Assistant 26/0、RuntimeContact 54/0（`tmp/module7b-b1-contract.log`）。B2 红测先确认缺少展开和通用目标接口（`tmp/module7b-b2-red.log`），实现后为 RobotContact 17/0；测试发现方向展开经 `DeviceRegistry.pair(Vector2)` 变成浮点格，已改为显式整数对。B3 最终 RobotContact 67/0，contact-only 合计 147/0（`tmp/module7b-b3.log`、`tmp/module7b-b3-contact.log`）。B4 主场景和双 Agent 接入后 `--module7b-only` 为合同 26＋RobotContact 74＋DualAgent 13＝**113/0**（`tmp/module7b-b4.log`）。

| 最终验证 | 实际结果 |
| --- | --- |
| Godot 4.7.2 import | 退出 0，无解析错误；`tmp/module7b-b4-import.log` |
| `--module7b-only` | **113/0**，退出 0 |
| `--contact-only` | Assistant 26、7A RuntimeContact 54、RobotContact 74，合计 **154/0**；`tmp/module7b-final-contact.log` |
| 完整共享 `run_tests.gd` | **1046 passed / 0 failed**，退出 0；`tmp/module7b-final-shared.log` |
| 4A 独立 `run_sensing_tests.gd` | Geometry 26＋Kernel 88＝**114/0**；`tmp/module7b-final-sensing.log` |
| `--module7b-only --fail-probe` | 各套件仍 113/0，注入失败使 runner 退出 1，符合门禁；`tmp/module7b-final-fail-probe.log` |
| 主场景 120 帧 | 退出 0，输出 `RUNTIME_CONTACT_READY`、`RUNTIME_ROBOT_CONTACT_READY`、`RUNTIME_AGENT_READY`；`tmp/module7b-final-main.log` |
| Windows Desktop release | 导出与导出程序 120 帧均退出 0，标记同上；EXE 109127680 字节、PCK 1485480 字节；`tmp/module7b-final-export.log`、`tmp/module7b-final-windows.log` |
| Python／仓库／链接／格式 | unittest 13/13；仓库 0 issues；74 documents／0 broken；CRLF 兼容 `diff --check` 退出 0 |

最终共享日志中的 `GAME RUNTIME FAULT` 行均来自既有故障注入断言，相关套件为 0 failed；主场景和 Windows smoke 无非注入 fault。1046 的总数包含同期模块 6 从 B0 基线继续增加的检查，不全部归为 7B 成绩；7B 自身的最终专项计数为 113。

**Plan-Execution Diff。**公开 DTO、`SetPatrolRoute`、空 steps 驻守、预校验、冻结预览、统一安全回执、路线锁定和双顺序验收均按 §10 实施。`GameSession`、`WorldCommandService`、`WorldCommandBatch` 与 `main.tscn` 未改合同；`AgentProtocol` 只补 contact 白名单序列化。`RuntimeWorldView` 保留 7A camera wrappers，机器人使用自身 Selection 节点，路径预览由可信场景节点绘制。原型 4 步／2 次配置未升格为正式数值。测试 fixture 为完成段中驻守观察而把首次猜测延后到第 120 tick，生产规则不变；双 Agent 仍通过真实报告、猜测、调度和 `ResetCoordinator` 检查点，不直接写 phase。没有以自动 KEEP、STOP、隐藏玩家校验或自由格点编辑绕过失败。

范围保持：7B 只证明确定性模拟助手、灰盒联络和两种 Agent 顺序；7C 的 RESET 历史 UI、模块 8 的真实 Gateway／异常恢复、正式路线数值和完整四轮体验仍未验收。

## 12. 7B Review Matrix（2026-11-28）

| 轴 | 结论 | 依据 |
| --- | --- | --- |
| Spec 质量与要求完成 | PASS（7B 范围） | §9.2 的八项 Grill 裁决均有 DTO、可信展开、预览、提交或测试落点；B0–B4 按序完成，§11 的当前运行证据覆盖 Done Contract。正式数值、7C 和真实模型仍明确后置。 |
| Spec—代码一致性 | PASS | 公开动作仅为方向 `steps`；anchor helper 与 `_set_patrol` 共用；合法路径经非发布校验后冻结，确认仍走 `end_contact/commit_batch/SceneSync`。普通路径拒绝统一、有界并锁定，未改 GameSession／命令服务核心权限；双顺序使用真实系统周期。 |
| 代码自身质量 | PASS（灰盒／模拟范围） | 严格字段和类型、深拷贝、当前身份／revision、单目标与故障锁保持；路线预览有完整生命周期清理，单点也有可见节点。7A 54 项及完整共享回归全绿，失败探针和导出程序均验证。无已知未关闭高优先缺陷。 |

作者 Review 未发现需要回 Plan 的合同偏差或可达的信息越权；残余风险集中在真实模型输出／网络恢复、正式路线长度与尝试次数、7C 跨 RESET 历史和完整体验，这些不属于本次通过范围。

Overall Verdict：**REVIEW COMPLETE / PASS（仅 7B，主会话三轴 Review）**。本结论不冒充独立同行评审；额外只读审查未形成结果，未作为通过依据。B0–B5 均已完成，当前通过依据为 §11 的实际运行日志和本矩阵。

Resume：7B phase=`REVIEW COMPLETE`，approval=`Plan Approved`，status=`PASS（确定性模拟助手与灰盒 7B 范围）`，spec=`docs/features/2026-11-28_module-7-player-contact.md` §9–§12。下一步才是独立的 7C 或模块 8 规划；本次不自动启动它们，也不声称真实助手、正式数值或完整四轮已验收。
