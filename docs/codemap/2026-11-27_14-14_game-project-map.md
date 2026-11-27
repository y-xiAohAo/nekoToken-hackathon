# Godot 工程入口图（2026-11-27）

范围：当前 `game/` 工程壳与模块 1 规则内核。此图记录实际存在的文件；拟建模块另行标注，不把设计图当作已实现代码。

| 入口 | 当前职责 | 后续依赖 |
| --- | --- | --- |
| [`game/project.godot`](../../game/project.godot) | 入口场景、窗口与渲染设置 | 指向主场景，不存玩法状态 |
| [`game/scenes/main.tscn`](../../game/scenes/main.tscn) | `Main`、空 `World`、灰色 `Floor`、状态 `UI` | 模块 2 接入玩家与静态地图 |
| [`game/scripts/main.gd`](../../game/scripts/main.gd) | 启动标记与版本文字 | 后续只编排调用，不裁决规则 |
| [`game/scripts/core/`](../../game/scripts/core/) | `GameSession`、三层时间映射、报告边界与阶段转换 | 后续接入权威世界状态、设备感知和报告内容 |
| [`game/scripts/agents/agent_protocol.gd`](../../game/scripts/agents/agent_protocol.gd) | 双角色请求构造、身份字段和基础视图隔离 | 真实 AgentGateway 前须完成严格 DTO 和猜测结果校验 |
| [`game/tests/`](../../game/tests/) | headless 规则内核契约测试 | 新模块按风险增加少量验收场景 |
| [`game/export_presets.cfg`](../../game/export_presets.cfg) | Windows x86_64 导出预设 | 不包含模型密钥 |
| [`.github/workflows/godot.yml`](../../.github/workflows/godot.yml) | 固定 Godot 4.7.2 的 headless 导入和契约测试 | 推送或 PR 时执行 |
| [`game/README.md`](../../game/README.md) | 启动、导出、headless 测试及本机证据 | 新模块的验证入口应继续补充 |

现有可视执行路径：`project.godot → main.tscn → main.gd._ready() → 状态文字和 FRAMEWORK_SHELL_READY`。规则内核与测试 runner 可独立 headless 运行；尚未接入玩家、真实设备感知、完整报告内容、AgentGateway 或 RESET。

运行时依赖方向：`Main/World（未来提供物理结果）→ GameSession（时钟与阶段）→ 边界事件`；`GameSession` 只接受已提交的物理状态，Agent 请求按角色构造，场景树不是规则的唯一事实源。当前 Agent 字段过滤不是严格 schema；真实 AgentGateway 和动态世界尚未实现。

验证入口：本机 Godot 4.7.2 导入、主场景运行及 Windows 导出见 [`game/README.md`](../../game/README.md)；仓库级测试、链接与卫生检查见 [`docs/development.md`](../development.md)。
