# nekoToken · 2042

AI PLAY 72H 游戏项目工作区。正式游戏名待定；旧名《请本人到场》已停用。

远程仓库：[y-xiAohAo/nekoToken-hackathon](https://github.com/y-xiAohAo/nekoToken-hackathon)。2026-11-27 复核为公开仓库；本轮整理未修改可见性。主分支使用 `main`。

当前以 [2042 剧情与玩法设计 Spec v0.41](PRELIMINARY_DESIGN_SPEC.md) 为准：哥哥追查妹妹被转送后的接收地点，通过四轮维护预演规划现场核验与撤离。玩家、个人助手和系统 Agent 各有信息与操作边界，实时移动、感知、权限和命中判定由 Godot 执行。

## 当前状态

截至 2026-11-27，仓库已包含 Godot 工程壳和独立运行的最小规则内核，但仍无可玩原型。当前检查点锁定 Godot 4.7.2；Windows 工程导出已本地验证，Linux headless 契约 CI 已配置。模块 1 尚未接入玩家场景、设备感知、完整报告内容或真实 AgentGateway。详细赛事规则以主办方发布的信息为准。

## 阅读入口

1. [设计 Spec](PRELIMINARY_DESIGN_SPEC.md)：现行剧情、完整玩法、候选参数与验收场景。
2. [工作区架构](ARCHITECTURE.md)：文件职责、规则优先级和迭代记录。
3. [世界观与故事主线](source_materials/story/当前故事主线_2042.md)：两份故事原文的关系与人物信息边界；玩法改编以 Spec 为准。
4. [侦测定位机制](侦测定位_机制草案.md)：报告、定位、联络、重启与回退细则。
5. [赛前环境检查](handoff/赛前环境检查_2026-11-26.md)：本机实测结果、工具缺口与平台注册建议。

[AGENTS.md](AGENTS.md) 是开发协作入口；[阅读说明](README_先读这里.md)提供更完整的资料导航。归档材料用于追溯，不覆盖最新 Spec。

开始开发前阅读 [CONTRIBUTING](CONTRIBUTING.md) 和[开发约定](docs/development.md)。后续改动使用短期任务分支和 PR，变更记录见 [CHANGELOG](CHANGELOG.md)。

## 内容范围与本地配置

- `source_materials/`：故事和其他来源材料。
- `game/`：Godot 工程壳、场景、模块 1 规则内核与 headless 契约测试。
- `docs/`：开发约定、框架 Spec、Feature Spec 和重要工程决策。
- `archive/`、`output/`：历次方案、图示与文档产物。
- `handoff/`：迁移、讨论和环境记录，机器状态以较新复核为准。
- `.agents/skills/`、`.kimi/skills/`：随项目保存的开发说明与支持文件。
- `scripts/`、`tests/`：跨平台仓库检查与回归测试。
- `archive/production/`：旧生成器、预览、抓取记录和迁移工具；原始字节与路径映射已保留。
- `tmp/`：新的临时文件，Git 忽略。

本地模型凭据、附带运行时 `tools/`、依赖缓存和构建输出不入库。克隆后应自行配置 Git、Godot 与所需模型服务；`.env.example` 只提供空字段，不代表游戏已经实现读取或接入。游戏工程的运行和导出需要按 `game/README.md` 使用匹配版本。

## 克隆后的检查

只需要 Git 和 Python 3.12，不依赖 `tools/` 或模型账号：

```powershell
python -m unittest discover -s tests -v
python scripts/check_repository.py
python scripts/check_project_links.py --all
```

Windows 可运行 `powershell -ExecutionPolicy Bypass -File scripts/Check-Workspace.ps1`。GitHub Actions 对 PR 和 `main` 执行同样的 Windows、Linux 检查。仓库检查不替代 Godot 运行、导出与模型服务验收；当前工程壳已完成一次本地启动和 Windows 导出验证。
