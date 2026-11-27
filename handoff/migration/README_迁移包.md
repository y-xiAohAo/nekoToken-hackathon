# 《请本人到场》参赛机迁移包

打包日期：2026-11-26。队伍 nekoToken，队长王嘉璐，队员董骏豪。

这是当前黑客松工作区的完整材料快照，附加可迁移的技能、文档工具和接手说明。现阶段完成了玩法方案、示意图、预赛报告和成员介绍，**还没有 Godot 工程或可玩原型**。不要把预赛文档中的演示设想当作已经实现的效果。

## 到参赛机后

1. 完整解压本包到较短路径，例如 `D:\nekoToken`，保留 `.agents` 等隐藏目录。
2. 在该目录打开 PowerShell，运行 `powershell -ExecutionPolicy Bypass -File .\scripts\Check-Workspace.ps1`，核对材料校验和、技能与附带运行环境。
3. 在同一 PowerShell 中运行 `. .\Start-Workspace.ps1`，加入本包工具路径，创建独立 Git 仓库（仅在本目录没有 `.git` 时创建）。原来的 TMS 科研仓库没有混入迁移包。
4. 用参赛机上的 Agent 打开**解压目录本身**，先读 `AGENTS.md` 和 `handoff/接手说明.md`。可直接使用 `handoff/给参赛机Agent的首条消息.md`。
5. 检查 Godot、Git 与模型调用环境。原机没有 Godot 可执行文件，本包也没有锁定引擎小版本。需要在参赛机安装 Godot 4.x，记录实际版本并核对技能中的示例；部分技能写有 4.7，不代表团队已确定这一版本。

## 先看哪些材料

| 内容 | 入口 |
| --- | --- |
| 最新方案与规则边界 | `PRELIMINARY_DESIGN_SPEC.md`，v0.34 |
| 面向评审的玩法说明 | `output/pdf/AI_PLAY_72H_预赛方案_精炼特色版_v0.8.pdf` 及同名 Markdown，8页 |
| 机制基准 | `侦测定位_机制草案.md`，v0.20 |
| 玩法速读 | `output/预赛玩法框架_v0.4.md`，旧链接以当前 Spec 的入口为准 |
| 当前场景图 | `output/imagegen/请本人到场_检查区_名称标注_v6.png` 与 `请本人到场_检查区_路线示意_v6.png` |
| 流程框图源文件 | `output/pdf/figures/v08/`，含 SVG、PDF、PNG |
| 两份已引用故事原稿 | `source_materials/story/背景故事素材.docx`、`游戏背景v1(1).docx` |
| 成员介绍 | `output/pdf/董骏豪_AI_PLAY_参赛者介绍_v1.pdf` |
| 历次讨论文字 | `handoff/历次讨论记录.md` 与 `conversation.jsonl` |
| 下一步开发建议 | `handoff/开发起点.md` |
| 技能与外部能力 | `handoff/技能与环境.md`、`handoff/skills_inventory.json` |

## 包内组成

原工作区的根目录文档、`.agents/skills`、`output` 和 `tmp` 都保留；`tmp` 中包括旧版报告生成脚本、网页要求留存和图像生成依赖。补入原先放在工作区外的故事、简历来源，以及本次会话的可见讨论文字。

`tools/python` 是 Windows x64 的 Python 3.12，带本次文档及图像 API 脚本所需的已安装依赖；`tools/poppler` 提供 PDF 渲染，`tools/node` 提供 Node。`requirements.migration.lock.txt` 记录移入的 Python 分发包版本。其他操作系统应自行安装对应运行环境。

技能文件都收录在项目 `.agents/skills`，包括原有游戏开发技能、用户全局技能、当前可见内置技能和文档插件技能。复制技能说明不会复制云端模型、桌面插件服务、MCP 会话或账号权限，详见环境说明。

包内没有 API 密钥、账号登录态、完整 TMS 科研工程或其他聊天数据库。已有个人简历和联系方式随其材料保留。生成脚本中的原电脑工作区路径已在副本中改为相对定位，原文件未改动；历史记录和原始素材中的绝对路径保留用于追溯。

`MANIFEST.sha256.json` 记录每个文件的大小与 SHA-256；`handoff/workspace_coverage.json` 对照原工作区文件。迁移过程中产生的桌面截图和本次打包临时文件不属于项目材料，没有加入包内。

预赛规则页面最后一次留存复核在2026年11月15日。本次没有重新查询赛事要求、报名状态或截止时间；不要把旧文档里的报名待办和倒计时当作当前赛事状态。
