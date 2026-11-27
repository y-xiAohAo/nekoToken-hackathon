# nekoToken · 2042 世界观方案

这是从原 TMS 仓库迁出的独立黑客松工作区。当前已有 Godot 工程壳、模块 1 规则内核和模块 2 内存世界/命令服务；**尚无可玩原型**。

## 从这里开始

1. [工作区架构与迭代脉络](ARCHITECTURE.md)：说明哪些文件有决策效力、旧方案为什么归档。
2. [设计 Spec v0.42](PRELIMINARY_DESIGN_SPEC.md)：现行规则、候选数值与未决问题。
3. [2026—2042 世界观与故事主线](source_materials/story/当前故事主线_2042.md)：2026 新片段和 2042 长篇的合并边界、哥哥寻妹的开场。
4. [侦测定位机制 v0.23](侦测定位_机制草案.md)：需要实现时读细则。
5. [最小框架 Spec](docs/minimal-framework-spec.md) 与 [模块 Feature Specs](docs/features/README.md)：工程边界和实施记录。
6. [2042 世界观整合方案 v1.0](output/pdf/AI_PLAY_72H_预赛方案_2042世界观整合_v1.0.md)：此前可编辑文稿，尚未同步 Spec v0.42 的踏板及移除门/灯决定；旧世界观已归档，旧项目名《请本人到场》已停用，正式游戏名待定。

[旧世界观及故事版本](archive/story/README.md)、[历史候选](archive/README.md)、[旧报告与图示](output/README.md)和[讨论记录](handoff/历次讨论记录.md)供追溯。旧文件里的“最新”只表示当时版本，不覆盖现行 Spec。

## 工作区现状

- 游戏：当前检查点锁定 Godot 4.7.2；工程壳启动与 Windows 导出已有历史证据，模块 1/2 共 304 条 headless 检查通过，模块 2 的同行评审问题已修复并复核关闭。世界命令和部署门槛可独立测试；玩家、实际感知、完整报告、RESET 和真实 Agent 尚未接入。旧环境检查见[赛前环境检查](handoff/赛前环境检查_2026-11-26.md)。
- 技能：项目携带 49 个开发者技能的可迁移副本；当前用户级技能与这些副本的 `SKILL.md` 一致。项目直接相关的是 `hackathon-spec`、`game-jam`、`prototype-fast`、`level-design` 和 7 个 `godot-*`；`platformer` 属早期横版方向，现行方案不使用。其余是文档、图像、通用工具或原科研项目遗留，详情见[技能清单](handoff/技能与环境.md)。技能文件本身不代表插件或云端服务已连接。
- 工具：`tools/` 是本机工具目录，已被 Git 忽略；旧 `tmp/` 文件已移入 `archive/production/`，新的 `tmp/` 只用于本地临时产物。
- 版本：Git 在迁移后初始化，原项目的提交历史未迁入；当前仓库从此次工作区快照开始保存。更早的设计演变见[架构页](ARCHITECTURE.md)和[讨论记录](handoff/历次讨论记录.md)。

## 校验

在本目录运行 `powershell -ExecutionPolicy Bypass -File .\scripts\Check-Workspace.ps1`，或按 [协作说明](CONTRIBUTING.md) 使用 Git 和 Python 3.12 执行检查。当前校验不依赖本机附带运行时；旧材料清单与脚本已移入 `archive/production/workspace-tools/`，不再要求每次开发都重建清单。原迁移全量快照仍在 `handoff/migration/`。

模型密钥与账号配置留在本机环境，不能写入项目文件。旧机器的安装和接入过程见[环境记录](handoff/参赛机环境配置记录.md)，其中路径和版本是当日快照。
