# nekoToken · 2042

AI PLAY 72H 游戏项目工作区。正式游戏名待定；旧名《请本人到场》已停用。

远程仓库：[y-xiAohAo/nekoToken-hackathon](https://github.com/y-xiAohAo/nekoToken-hackathon)（私有）。主分支使用 `main`。

远程仓库：[y-xiAohAo/nekoToken-hackathon](https://github.com/y-xiAohAo/nekoToken-hackathon)（私有）。主分支使用 `main`。

当前以 [2042 剧情与玩法设计 Spec v0.39](PRELIMINARY_DESIGN_SPEC.md) 为准：哥哥追查妹妹被转送后的接收地点，通过四轮维护预演规划现场核验与撤离。玩家、个人助手和系统 Agent 各有信息与操作边界，实时移动、感知、权限和命中判定由 Godot 执行。

## 当前状态

截至 2026-11-27，仓库内容包含设计、世界观原稿、机制说明、历史产物、开发技能与工作区检查工具，尚无正式 Godot 游戏工程或可玩原型。独立环境探针不属于游戏实现。本机已有 Godot 4.2.2 和 Windows 导出模板并完成基础验证，团队最终使用的小版本尚未锁定。详细赛事规则以主办方发布的信息为准。

## 阅读入口

1. [设计 Spec](PRELIMINARY_DESIGN_SPEC.md)：现行剧情、完整玩法、候选参数与验收场景。
2. [工作区架构](ARCHITECTURE.md)：文件职责、规则优先级和迭代记录。
3. [世界观与故事主线](source_materials/story/当前故事主线_2042.md)：两份故事原文的关系与人物信息边界；玩法改编以 Spec 为准。
4. [侦测定位机制](侦测定位_机制草案.md)：报告、定位、联络、重启与回退细则。
5. [赛前环境检查](handoff/赛前环境检查_2026-11-26.md)：本机实测结果、工具缺口与平台注册建议。

[AGENTS.md](AGENTS.md) 是开发协作入口；[阅读说明](README_先读这里.md)提供更完整的资料导航。归档材料用于追溯，不覆盖最新 Spec。

## 内容范围与本地配置

- `source_materials/`：故事和其他来源材料。
- `archive/`、`output/`：历次方案、图示与文档产物。
- `handoff/`：迁移、讨论和环境记录，机器状态以较新复核为准。
- `.agents/skills/`、`.kimi/skills/`：随项目保存的开发说明与支持文件。
- `scripts/`：材料清单与链接校验；`tmp/` 保留既有生成器和可追溯产物，不作为设计依据。

本地模型凭据、附带运行时 `tools/`、依赖缓存和构建输出不入库。克隆后应自行配置 Git、Godot 与所需模型服务；`.env.example` 只提供空字段，不代表游戏已经实现读取或接入。

安装 Python 后可用 `python scripts/check_project_links.py --all` 检查入口与归档链接。`scripts/Check-Workspace.ps1` 和完整材料检查另需原迁移包中的 `tools/`；Git 克隆不包含这套本地运行时，不能将其缺失误判为游戏代码损坏。
