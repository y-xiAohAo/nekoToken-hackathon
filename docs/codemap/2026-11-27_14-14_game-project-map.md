# Godot 工程入口图（2026-11-27）

> 历史工程快照：下文只记录 2026-11-27 的模块 0–2 状态。当前已接入 3A/3B 运动交互及 4A/4B 感知和统一报告；现行入口与验收见 [游戏工程说明](../../game/README.md) 和 [Feature 索引](../features/README.md)。

范围：当前 `game/` 工程壳、模块 1 规则内核及模块 2 世界命令。此图记录实际存在的文件，真实场景设备仍后置。

| 入口 | 当前职责 | 后续依赖 |
| --- | --- | --- |
| [`game/project.godot`](../../game/project.godot) | 入口场景、窗口与渲染设置 | 指向主场景，不存玩法状态 |
| [`game/scenes/main.tscn`](../../game/scenes/main.tscn) | `Main`、空 `World`、灰色 `Floor`、状态 `UI` | 权威世界、玩家控制和设备节点后续接入场景 |
| [`game/scripts/main.gd`](../../game/scripts/main.gd) | 启动标记与版本文字 | 后续只编排调用，不裁决规则 |
| [`game/scripts/core/`](../../game/scripts/core/) | `GameSession`、三层时间映射、报告边界、部署回执门槛与阶段转换 | 后续接入实际物理步、感知和报告内容 |
| [`game/scripts/world/`](../../game/scripts/world/) | LevelTemplate、WorldState、DeviceRegistry、命令数据/服务、WorldSyncAdapter | 纯数据同步；实际碰撞/感知适配器和 RESET 后置 |
| [`game/scripts/agents/agent_protocol.gd`](../../game/scripts/agents/agent_protocol.gd) | 双角色请求构造、身份字段和基础视图隔离 | 真实 AgentGateway 前须完成严格 DTO 和猜测结果校验 |
| [`game/tests/`](../../game/tests/) | SessionKernelTests 81 条、WorldCommandTests 223 条检查，单 runner 汇总 | 新模块按风险增加少量验收场景 |
| [`game/export_presets.cfg`](../../game/export_presets.cfg) | Windows x86_64 导出预设 | 不包含模型密钥 |
| [`.github/workflows/godot.yml`](../../.github/workflows/godot.yml) | 固定 Godot 4.7.2 的 headless 导入和契约测试 | 推送或 PR 时执行 |
| [`game/README.md`](../../game/README.md) | 启动、导出、headless 测试及本机证据 | 新模块的验证入口应继续补充 |

现有可视执行路径：`project.godot → main.tscn → main.gd._ready() → 状态文字和 FRAMEWORK_SHELL_READY`。规则内核与测试 runner 可独立 headless 运行；尚未接入玩家、真实设备感知、完整报告内容、AgentGateway 或 RESET。

运行时依赖方向：`LevelTemplate → WorldState(DeviceRegistry)`；`可信协调层 → GameSession 暂停上下文 → WorldCommandService → 候选校验/同步 → 部署回执 → GameSession 放行`。实际物理步将由后续适配器写回世界再提供 WorldFrame。场景树不是第二份权威状态；Agent 字段过滤仍非严格 schema，真实 AgentGateway 尚未实现。

合同与验收：[模块 2 Feature Spec](../features/2026-11-27_20-53_module-2-world-command.md) 已获 Plan Approved，world/ 已实现；同行评审的 3 项 P2 已修复并独立复核关闭，当前结论为 PASS（本模块范围），证据见该 Spec §21。同步测试替身不代表真实物理与视觉验收，权限 fixture 不代表 Agent 授权。

验证入口：本机 Godot 4.7.2 导入、主场景运行及 Windows 导出见 [`game/README.md`](../../game/README.md)；仓库级测试、链接与卫生检查见 [`docs/development.md`](../development.md)。
