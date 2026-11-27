# nekoToken · 2042 世界观工作区

本目录是从原 TMS 仓库的 hackathon 子目录迁出的独立游戏工作区。工作根目录以本文件所在目录为准，不能依赖原电脑的 D 盘路径或科研仓库。

## 接手顺序

先读 `ARCHITECTURE.md` 与 `PRELIMINARY_DESIGN_SPEC.md`，剧情读 `source_materials/story/当前故事主线_2042.md`，再按需查两份现行原文；实现机制时读 `侦测定位_机制草案.md`。当前剧情文稿为 v1.0；旧《请本人到场》世界观、v0.8 报告和过渡稿 v0.9 已归档。需要解释决策时查 `archive/README.md` 与 `handoff/历次讨论记录.md`；`handoff/接手说明.md` 是迁移时的状态快照。

规则优先级：用户最新明确决定 > 当前两份世界观原文和设计 Spec／机制基准 > 最新报告 > 旧草稿与归档素材。两份原文之间尚未明说的姓名和机构关系不得自行定案。报告示例、数值候选和迁移时新增的开发建议不能自动升级为已定规则。当前没有游戏实现或试玩结论。根目录历史候选已移至 `archive/concepts/`；旧世界观见 `archive/story/`，旧报告与旧速读见 `output/archive/`。

## 技术与设计

- 技术栈已定为 Godot。具体4.x小版本在参赛机验证后记录，不以技能标题中的4.7推断已安装版本。
- 使用 `.agents/skills/hackathon-spec`、相关 Godot 技能和关卡技能；中文修订用 `humanizer-zh`，PDF任务用 `pdf`。
- 10分钟是整场四轮、对话、推理、回退与结算的目标，尚未实测。
- 连续移动、碰撞、设备感知与结果校验由游戏程序执行。模型只在受限节点选择合法动作，不能读取越权情报、直接宣布命中或修改规则。
- 玩家侧游戏接入 skill 尚未实现。`.agents/skills` 是开发者技能库，不能直接当作给玩家的接口说明。
- 优先构建并验证一个完整行动周期，再加入助手、定位和两类 RESET。`handoff/开发起点.md` 是待实施建议，不是已获用户确认的数值或关卡变更。

## 保留的工程纪律

Python 编码遵守 `.kimi/skills/tms-coding-discipline/SKILL.md`：测试先于实现，公开函数有参数与返回类型，具体异常，logging输出，模块文档，依赖记录。新增游戏逻辑应有相应验收场景；文档改动无需为了形式增加无效测试。

原父目录规则完整留存在 `source_materials/engineering/AGENTS.parent.original.md`。与科研数据库、科研任务索引有关的入口属于原工程背景，本独立游戏目录没有对应科研代码，不要据此导入或修改其他项目。

用户明确要求按氛围编码规范执行时，读取 `.agents/skills/vibe-coding-harness/SKILL.md` 和 `source_materials/engineering/vibe_coding_agent.md`，遵守其中 Git/Spec 准入。用户要求 SDD/RIPER/MAP/DEBUG 等对应流程时，读取 `.agents/skills/sdd-riper-one/SKILL.md`，适用的 `Plan Approved` 等门禁保留。读取迁移材料或正常恢复上下文本身不代表所有可选流程都被主动启用。

不执行 `git clean`。不覆盖原稿；变更方案后回写 Spec。发送消息、提交外部报名或发布产物依照用户授权执行。

## 工具与路径

所有可迁移技能及支持文件在 `.agents/skills`；有些工具依赖宿主客户端、MCP或外部服务，见 `handoff/技能与环境.md`。不要仅凭存在SKILL.md就声称相关云端能力可用。

模型密钥在参赛机单独配置，不写入共享文件或日志。`Start-Workspace.ps1` 只为当前 PowerShell 加入附带工具路径，并在本地初始化独立 Git；不会安装客户端或自动恢复账户。
