# 游戏工程落点

基础 Godot 工程壳已创建，入口为 `project.godot` 和 `scenes/main.tscn`。当前包含 `Main/World/UI` 灰盒、规则内核、内存世界与命令服务和启动自检；具体感知上报内容、AgentGateway、玩家交互和关卡玩法仍由后续模块接入。

[模块 2](../docs/features/2026-11-27_20-53_module-2-world-command.md) 已按 Plan Approved 实施：LevelTemplate、WorldState、六类实体注册表、稳定 ID、预检与原子命令、派生同步合同及会话门槛。联络结束提交并同步成功后才恢复行动，报告边界不再调用延迟配置。当前同步适配器是纯数据模式，真实碰撞、视觉、踏板触发和运动写回仍按[最小游戏框架 Spec](../docs/minimal-framework-spec.md)后续接入。

本检查点以 Godot `4.7.2.stable.official.ed1daf0bf` 为开发基线，已用匹配的 Windows 导出模板验证启动和导出。以下命令从仓库根目录运行；`tools/` 是本机忽略目录，其他电脑可换成相同版本的 Godot 可执行文件：

```powershell
tools/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game --quit-after 3
New-Item -ItemType Directory -Force build/windows | Out-Null
tools/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game --export-release "Windows Desktop" ../build/windows/2042-framework.exe
```

2026-11-27 本机验证记录：工程导入退出码 0；主场景无窗口运行退出码 0，输出 `FRAMEWORK_SHELL_READY`；Windows release 导出退出码 0，生成 `2042-framework.exe`（109,127,680 字节）和 `.pck`（4,144 字节）；导出程序再以无窗口模式运行退出码 0，并输出相同启动标记。场景引用检查为 0 错误、0 警告。此记录只证明工程壳可启动和导出，不代表猜测周期或玩法已实现。

在本目录保存游戏脚本、场景、源素材、UID 元数据和安全的导出配置。Godot 缓存、生成的程序包与 API 凭据留在 Git 之外；开发技能和历史文稿不复制进游戏资源目录。

## 模块 1/2 headless 契约测试

从仓库根目录运行：

```powershell
New-Item -ItemType Directory -Force tmp | Out-Null
$importLog = Join-Path (Get-Location) 'tmp/godot-import.log'
$testLog = Join-Path (Get-Location) 'tmp/godot-tests.log'
tools/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game --import --log-file $importLog
tools/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game --log-file $testLog --script res://tests/run_tests.gd
```

2026-11-27 修复后结果：SessionKernelTests 81 passed、0 failed；WorldCommandTests 223 passed、0 failed；导入与 runner 均退出 0，日志无脚本错误。同行评审的坐标转换、向量有限性及踏板基线三个问题已修复并独立复核关闭，新增回归在修复前曾检出 28 个失败并返回退出码 1。runner 同时检查各场景执行完成，避免脚本中途停止却被计为通过。

覆盖时钟、边界、暂停、猜测优先、基础视图隔离，以及模板复制、空间/路线合法性、原子失败、幂等、旧分支拒绝、同步失败门槛和联络即时部署。测试地图、数值与角色策略仅为 fixture。模块 1 的 payload DTO、hit 上游校验与报告内容桩限制仍保留；本轮不证明真实设备感知或可玩关卡。

CI 下载固定的 Godot 4.7.2 Linux 编辑器，执行导入和同一个 runner，并扫描错误日志。远端 CI 本轮未运行，未重新导出游戏；上方 Windows 导出记录属于模块 0 历史证据。

首个实现依据 [Spec](../PRELIMINARY_DESIGN_SPEC.md)、[机制说明](../侦测定位_机制草案.md)和[开发约定](../docs/development.md)。创建工程的同一轮应补充实际版本、启动方式、测试入口和导出目标，本页不能用占位数字冒充验证结果。
