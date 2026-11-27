# nekoToken · 2042 世界观方案

这是从原 TMS 仓库迁出的独立黑客松工作区。当前完成了玩法方案、示意图和预赛材料；**尚无 Godot 工程或可玩原型**。

## 从这里开始

1. [工作区架构与迭代脉络](ARCHITECTURE.md)：说明哪些文件有决策效力、旧方案为什么归档。
2. [设计 Spec v0.39](PRELIMINARY_DESIGN_SPEC.md)：现行规则、候选数值与未决问题。
3. [2026—2042 世界观与故事主线](source_materials/story/当前故事主线_2042.md)：2026 新片段和 2042 长篇的合并边界、哥哥寻妹的开场。
4. [侦测定位机制 v0.20](侦测定位_机制草案.md)：需要实现时读细则。
5. [2042 世界观整合方案 v1.0](output/pdf/AI_PLAY_72H_预赛方案_2042世界观整合_v1.0.md)：此前可编辑文稿，尚未同步 Spec v0.39；旧世界观已归档，旧项目名《请本人到场》已停用，正式游戏名待定。

[旧世界观及故事版本](archive/story/README.md)、[历史候选](archive/README.md)、[旧报告与图示](output/README.md)和[讨论记录](handoff/历次讨论记录.md)供追溯。旧文件里的“最新”只表示当时版本，不覆盖现行 Spec。

## 工作区现状

- 游戏：Godot 已定为技术栈；团队小版本未锁定。本机已发现 Steam 版 4.2.2 及导出模板，基础运行和导出验证见[赛前环境检查](handoff/赛前环境检查_2026-11-26.md)。先验证一轮行动周期，再接入两个 Agent 和两类 RESET。
- 技能：项目携带 49 个开发者技能的可迁移副本；当前用户级技能与这些副本的 `SKILL.md` 一致。项目直接相关的是 `hackathon-spec`、`game-jam`、`prototype-fast`、`level-design` 和 7 个 `godot-*`；`platformer` 属早期横版方向，现行方案不使用。其余是文档、图像、通用工具或原科研项目遗留，详情见[技能清单](handoff/技能与环境.md)。技能文件本身不代表插件或云端服务已连接。
- 工具：`tools/` 是迁移包携带的 Windows 运行时，已被 Git 忽略；`tmp/` 是生成器与临时产物，不能当作设计源。
- 版本：Git 在迁移后初始化，原项目的提交历史未迁入；当前仓库从此次工作区快照开始保存。更早的设计演变见[架构页](ARCHITECTURE.md)和[讨论记录](handoff/历次讨论记录.md)。

## 校验

在本目录运行 `powershell -ExecutionPolicy Bypass -File .\scripts\Check-Workspace.ps1`。现行 `MANIFEST.sha256.json` 只校验稳定项目材料；原迁移全量快照保存在 `handoff/migration/MANIFEST.sha256.json`。Python 缓存、附带运行时和 `tmp/` 会随使用变化，不按历史哈希核对；检查脚本单独检查附带工具能否运行。

模型密钥与账号配置留在本机环境，不能写入项目文件。旧机器的安装和接入过程见[环境记录](handoff/参赛机环境配置记录.md)，其中路径和版本是当日快照。
