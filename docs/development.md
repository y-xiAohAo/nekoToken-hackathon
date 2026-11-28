# 开发与目录约定

## 从干净克隆开始

1. 克隆仓库，参与提交的账号需有写入权限；阅读 [README](../README.md)、[Spec](../PRELIMINARY_DESIGN_SPEC.md) 和 [AGENTS](../AGENTS.md)。
2. 准备 Git 和 Python 3.12，执行 [协作说明中的检查](../CONTRIBUTING.md#本地检查)。不需要旧电脑的 `tools/`、模型密钥或完整迁移包。
3. 本分支开发基线为 Godot `4.7.2.stable.official.ed1daf0bf`，匹配模板已验证；团队若选择其他 4.x 小版本，必须同步更新 `game/README.md` 和导出记录。
4. `game/` 已有正式工程壳。按[最小游戏框架 Spec](minimal-framework-spec.md)先用模拟 Agent 验证一个猜测周期，再接真实模型和完整四轮结构。

## 文件放在哪里

| 路径 | 职责 |
| --- | --- |
| 根目录 Spec、机制说明 | 现行设计依据；暂不迁移，保持既有引用稳定 |
| `game/` | `project.godot`、游戏代码、场景和运行时素材 |
| `docs/` | 框架与 Feature Spec、工程说明和重要决策，避免复制玩法正文 |
| `tests/`、`scripts/` | 仓库维护测试与跨平台检查；游戏测试随实际工程补充 |
| `source_materials/` | 原始故事与来源材料，内容不因工程整理被改写 |
| `output/` | 已选择保留的文稿、图示与历史成品，见其索引 |
| `archive/production/` | 旧生成器、预览、抓取记录及迁移工具快照 |
| `handoff/` | 讨论与机器状态证据；每份报告只说明记录时的状态 |
| `.agents/skills/`、`.kimi/skills/` | 随项目保存的技能和工程规则，不作为游戏运行时资源 |
| `tmp/`、`tools/`、`build/`、`exports/` | 本机暂存、工具与输出，Git 忽略 |

引擎项目放在 `game/` 可避免 Godot 把旧 PDF、技能库和讨论记录都当作游戏资源扫描或导出。模块 1/2 已实现规则内核、内存世界和命令入口，模块 3A/3B 已实现灰盒运动与交互，模块 4A/4B 已实现设备感知与统一报告。命中和权限校验始终由程序执行。

## 首个开发检查点

模块 1 规则内核、模块 2 世界命令、[模块 3A](features/2026-11-27_22-25_module-3a-runtime-scene.md) 灰盒运动、[模块 3B](features/2026-11-27_22-51_module-3b-interactions.md) 目标/联络/出口交互、[模块 4A](features/2026-11-27_23-31_module-4a-sensing-kernel.md) 纯数据感知及[模块 4B](features/2026-11-28_10-44_module-4b-runtime-sensing.md) 真实感知与统一报告均已通过各自范围 Review；共享 Godot 套件 830 项、4A 独立套件 114 项本地通过，Windows 导出已复验。完整 RESET 和真实 Agent 仍后置。模块 1 的 Agent payload 尚非严格 DTO，猜测结果入口依赖上游校验；这两项须在真实 AgentGateway 接入前解决。首个完整可玩切片仍需按玩法 Spec 验证猜测和回退。

真实模型接入前明确：两类 Agent 的输入字段、合法动作、超时和非法输出的恢复路径，以及演示时的密钥提供方式。`.env.example` 不会被 Godot 自动读取，当前也没有实现 `.env` 加载器。

每次开发先处理一个可验证目标。模块 1/2/3A/3B/4B 共用 Godot 4.7.2 headless runner 与轻量 CI；4A 另有独立 runner。CI 的远端实际结果以对应 PR / Actions 运行为准，不能由本地通过替代。

## 历史工具与素材

旧生成器的源文件、预览和锁文件已移至 [生成过程归档](../archive/production/README.md)。它们可能含原输出路径或旧机器路径，不能直接作为新项目脚手架运行。需复现时在独立工作区恢复旧版本，避免覆盖现行产物。

多个报告版本中的同名图示保留各自引用关系；本次没有为节省文件数改写历史报告，也没有清理本机已忽略的工具和缓存。第三方技能仍保留在原入口，不自动启用所有协议或安装所有外部服务。
