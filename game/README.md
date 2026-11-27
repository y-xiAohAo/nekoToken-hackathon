# 游戏工程落点

基础 Godot 工程壳已创建，入口为 `project.godot` 和 `scenes/main.tscn`。当前包含 `Main/World/UI` 灰盒、规则内核的最小实现和启动自检；具体感知上报内容、AgentGateway、玩家交互和关卡玩法仍由后续模块接入。

本检查点以 Godot `4.7.2.stable.official.ed1daf0bf` 为开发基线，已用匹配的 Windows 导出模板验证启动和导出。以下命令从仓库根目录运行；`tools/` 是本机忽略目录，其他电脑可换成相同版本的 Godot 可执行文件：

```powershell
tools/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game --quit-after 3
New-Item -ItemType Directory -Force build/windows | Out-Null
tools/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game --export-release "Windows Desktop" ../build/windows/2042-framework.exe
```

2026-11-27 本机验证记录：工程导入退出码 0；主场景无窗口运行退出码 0，输出 `FRAMEWORK_SHELL_READY`；Windows release 导出退出码 0，生成 `2042-framework.exe`（109,127,680 字节）和 `.pck`（4,144 字节）；导出程序再以无窗口模式运行退出码 0，并输出相同启动标记。场景引用检查为 0 错误、0 警告。此记录只证明工程壳可启动和导出，不代表猜测周期或玩法已实现。

在本目录保存游戏脚本、场景、源素材、UID 元数据和安全的导出配置。Godot 缓存、生成的程序包与 API 凭据留在 Git 之外；开发技能和历史文稿不复制进游戏资源目录。

## 模块 1 headless 契约测试

从仓库根目录运行：

```powershell
tools/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game --log-file tmp/module1-godot.log --script res://tests/run_tests.gd
```

测试 runner 会以非零进程码报告失败；当前覆盖时钟、猜测周期边界、暂停、报告顺序、通关优先级、分支身份和双角色视图隔离。CI 只下载固定的 Godot 4.7.2 Linux 编辑器并执行导入和这套契约测试。

首个实现依据 [Spec](../PRELIMINARY_DESIGN_SPEC.md)、[机制说明](../侦测定位_机制草案.md)和[开发约定](../docs/development.md)。创建工程的同一轮应补充实际版本、启动方式、测试入口和导出目标，本页不能用占位数字冒充验证结果。
