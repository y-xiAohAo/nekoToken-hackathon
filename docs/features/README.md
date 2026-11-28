# Feature Specs

- [模块 0：Godot 工程壳](2026-11-27_14-22_module-0-project-shell.md)：回顾性 SDD 记录与技术验收证据。
- [模块 1：规则内核与 Agent 契约](2026-11-27_14-22_module-1-rule-kernel.md)：内部时间与阶段内核已实现并通过本地契约测试；真实 AgentGateway 接入仍有条件。
- [模块 2：世界状态、注册表与命令](2026-11-27_20-53_module-2-world-command.md)：Plan Approved，REVIEW PASS（本模块范围）；同行评审的 3 项 P2 已修复并独立复核关闭，正式检查 81/223 条通过。真实物理、感知、RESET 和 Agent 接入后置。
- [模块 3A：场景同步、运行时协调与运动](2026-11-27_22-25_module-3a-runtime-scene.md)：Plan Approved，REVIEW PASS（本模块范围）；P0–P7 已完成，独立复核发现已全部关闭。该模块验收时正式检查 81/223/31/253 条通过，灰盒持续运行和 Windows 导出已复验；其后 3B/4A/4B 分别完成交互与感知报告。
- [模块 3B：目标、联络点与出口交互](2026-11-27_22-51_module-3b-interactions.md)：Plan Approved，REVIEW PASS（本模块范围）；B0–B6 已完成，独立复核发现全部关闭，并键输入边界已补修。目标停留/多目标、联络消耗与重试/KEEP_CURRENT、真实出口通关已验收；当前正式检查 81/223/47/344 条通过。
- [模块 4A：纯数据感知与设备报告内核](2026-11-27_23-31_module-4a-sensing-kernel.md)：Plan Approved，REVIEW PASS（4A 范围）；P0–P7 已完成，干净模块 0–2 副本的独立测试 26/88 条通过，原有 81/223 条回归通过。真实运行时和统一报告由 4B 另行验收。
- [模块 4B：真实感知与统一报告运行时集成](2026-11-28_10-44_module-4b-runtime-sensing.md)：Plan Approved，REVIEW PASS（4B 范围）；真实单步感知、3B 目标事件同批、安全视图和终止性报告故障处理已接入；共享套件 830 项通过，后续 RESET 与 Agent 限制见该 Spec。
- [模块 5：模拟系统 Agent 与一个完整猜测周期](2026-11-28_14-55_module-5-simulated-agent-guess-cycle.md)：其范围 REVIEW COMPLETE；Feature Spec §P9 记录共享套件 920/920、4A 独立套件 114/114 及主场景、Windows smoke 通过。真实 RESET 留给模块 6。
- [模块 6：周期快照、分支与双重 RESET](2026-11-28_module-6-snapshot-branch-reset.md)：Plan Approved，6A／6B REVIEW COMPLETE；真实周期快照、局部回退、分支报告历史与确定性轮间重启已验收。模块 6 专项 25/25、当前共享套件 959/959；独立复核发现已关闭。7C 助手记忆 UI 与模块 8 真实 Gateway／完整四轮体验仍后置。
- [模块 7：玩家助手联络与动态命令](2026-11-28_module-7-player-contact.md)：7A 独立同行复审后 REVIEW PASS，专属检查 68/0；7B B0–B5 及主会话三轴 Review 已完成，范围 PASS，专项 113/0、联络 154/0、共享 1046/0、4A 114/0，主场景与 Windows smoke 通过；§11–§12 记录验证、Plan-Execution Diff 与评审边界。7C RESET 与真实桥接仍后置。
