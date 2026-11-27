# 协作与提交约定

两人团队采用 `main` 加短期任务分支。`main` 保持可检查；未来游戏可运行后，合入改动还应保持可玩。没有长期 `develop` 分支，也不为每一份文案建立发布版本。

## 一次迭代怎样进行

1. 明确要解决的问题、涉及的 Spec 条目和可观察的验收结果。可使用仓库 Issue 模板记录；小修订直接写进 PR。
2. 从最新 `main` 建分支：`feat/<topic>`、`fix/<topic>`、`docs/<topic>` 或 `chore/<topic>`。名称使用简短英文小写和连字符，例如 `feat/report-cycle`。
3. 一次提交只包含一个完整目的，使用 `feat:`、`fix:`、`docs:`、`test:`、`chore:` 等前缀。提交前查看差异，确认没有凭据、缓存或无关文件。
4. 运行下面的检查；玩法变更还需完成 Spec 中对应的验收场景。测试失败时先修复；尚未验证的项目如实写出。
5. 推送分支并开 PR，说明变化原因、验证结果和需要复核的影响。可请队友复核；队友无法到场时记录自查依据，不虚构审阅。
6. 合并时优先 squash，使 `main` 上每个提交对应一个可回退的变更。通过 `git revert` 撤回共享提交，不改写已共享历史、不向 `main` 强制推送。

推荐流程参考 [GitHub flow](https://docs.github.com/en/get-started/using-github/github-flow)。本页是协作约定；是否已启用服务器端保护规则，要以 GitHub 仓库设置为准，文档不会自动强制执行。

## 本地检查

需要 Git 与 Python 3.12，检查脚本只使用标准库，不需要安装模型 SDK、文档依赖或 Godot：

```powershell
python -m unittest discover -s tests -v
python scripts/check_repository.py
python scripts/check_project_links.py --all
```

Windows 也可以运行 `powershell -ExecutionPolicy Bypass -File scripts/Check-Workspace.ps1`，会执行同样三项检查。文件移动或删除后先 `git add`，让校验读取的 Git 索引与本次改动一致；被忽略但早已入库的文件仍会被发现。

GitHub Actions 在 PR 和 `main` 更新时执行 Windows、Linux 检查。当前检查只覆盖仓库内容、链接与维护脚本，**不代表游戏可玩、模型可用或导出已经通过**。引擎版本锁定并创建工程后，再增加实际 Godot 测试与构建。

## 文档、素材与变更边界

- 玩法、剧情或权限变动先更新 [Spec](PRELIMINARY_DESIGN_SPEC.md)；原文事实和游戏改编补写保持区分。实现不得静默改变四轮结构、共享回退、Agent 信息边界。
- 大的技术选择记录到 `docs/decisions/`，说明原因、备选与代价；小修复不用另写决策文档。
- 新素材提交源文件、使用来源及授权记录。`.gd`、`.tscn`、`.tres`、`.uid` 和安全的 `export_presets.cfg` 应入库；`.godot/` 缓存不入库。[Godot 官方版本控制说明](https://docs.godotengine.org/en/stable/tutorials/best_practices/version_control_systems.html)
- 单个文件超过 50 MiB 时，先确定 Git LFS 或 Release 附件方案；当前没有大文件，不全量迁移 LFS，也不改写初始历史。
- 依赖按实际代码需要声明。仓库维护脚本没有第三方依赖；旧报告依赖锁文件只是迁移证据，不是游戏安装清单。
- `archive/` 和原始故事保留事实；日常整理不格式化、批量替换或删除历史原稿。第三方技能保留来源和许可证，不给整个项目擅自补开放源码许可证。
- API 密钥不进入 Git、日志、截图、发行包或 PR 内容。CI 不使用真实模型密钥，游戏的真实服务验证单独进行。

## 版本与交付

Spec 的 `v0.39` 是设计文档版本，不是软件发行版本。首个实际可玩版本完成后再使用 `v0.1.0` 等 Git 标签；不为当前资料整理假造游戏发布。每次可试玩交付在 [CHANGELOG](CHANGELOG.md) 记录变化、限制和验证范围，程序包放 Release 附件，源代码和导出配置留在 Git。
