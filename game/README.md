# 游戏工程落点

工程入口为 `project.godot` 和 `scenes/main.tscn`。当前包含规则内核、内存世界与命令服务、真实灰盒运动及模块 3B 交互：玩家可用 WASD 移动，接近核验装置按 E 开始停留操作，多个目标需全部完成；联络点成功进入即消耗，可按 E 明确 KEEP_CURRENT 离开；全部目标完成后真实触碰出口形成通关条件。感知上报、AgentGateway、完整 RESET 和四轮玩法仍由后续模块接入。

[模块 2](../docs/features/2026-11-27_20-53_module-2-world-command.md)、[模块 3A](../docs/features/2026-11-27_22-25_module-3a-runtime-scene.md) 和 [模块 3B](../docs/features/2026-11-27_22-51_module-3b-interactions.md) 均已按 Plan Approved 实施并通过各自范围 Review。运动只推进 `simulation_tick`，部署命令才推进 `world_revision`；目标与联络状态进入同一完整候选和唯一运行时写回。

本检查点以 Godot `4.7.2.stable.official.ed1daf0bf` 为开发基线，已用匹配的 Windows 导出模板验证启动和导出。以下命令从仓库根目录运行；`tools/` 是本机忽略目录，其他电脑可换成相同版本的 Godot 可执行文件：

```powershell
tools/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game --quit-after 3
New-Item -ItemType Directory -Force build/windows | Out-Null
tools/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game --export-release "Windows Desktop" ../build/windows/2042-framework.exe
```

2026-11-27 模块 3A 本机验证：主场景输出 `FRAMEWORK_SHELL_READY` 与 `RUNTIME_GRAYBOX_READY`；120 个真实渲染物理帧约 1.87 秒，灰盒 PNG 已人工查看，玩家和各类设备可见。Windows release 导出退出码 0，生成 `2042-framework.exe`（109,127,680 字节）和 `.pck`（414,840 字节），导出程序无窗口运行退出码 0 并输出相同标记。场景引用检查为 0 错误、0 警告。这些结果只覆盖灰盒运动和部署同步，不代表目标交互、真实感知、完整猜测周期或四轮玩法已完成。

在本目录保存游戏脚本、场景、源素材、UID 元数据和安全的导出配置。Godot 缓存、生成的程序包与 API 凭据留在 Git 之外；开发技能和历史文稿不复制进游戏资源目录。

## 模块 1/2/3A/3B headless 契约与场景测试

从仓库根目录运行：

```powershell
New-Item -ItemType Directory -Force tmp | Out-Null
$importLog = Join-Path (Get-Location) 'tmp/godot-import.log'
$testLog = Join-Path (Get-Location) 'tmp/godot-tests.log'
tools/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game --import --log-file $importLog
tools/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game --log-file $testLog --script res://tests/run_tests.gd
```

2026-11-27 模块 3A 结果：SessionKernelTests 81 passed、WorldCommandTests 223 passed、RuntimeMotionTests 31 passed、RuntimeSceneTests 253 passed，均为 0 failed；导入与 runner 均退出 0。失败探针返回退出码 1。runner 支持真实物理场景的异步 suite，并检查各场景执行完成。独立复核的主场景暂停和暂存节点泄漏已修复，全部评审发现已关闭。

2026-11-28 模块 3B 结果：SessionKernelTests 81 passed、WorldCommandTests 223 passed、RuntimeMotionTests 47 passed、RuntimeSceneTests 342 passed，合计 **693 passed / 0 failed**；续接复验的 Godot runner 退出 0，日志位于 `tmp/module3b-resume-tests.log`。交互、联络和出口的独立复核发现已关闭；主场景及 Windows release 导出程序均输出 `RUNTIME_INTERACTIONS_READY`。导出的 `2042-framework.exe` 为 109,127,680 字节，`.pck` 为 516,044 字节。Python 13/13、仓库检查 0 issues、链接检查 0 broken、CRLF 兼容 diff 检查通过。上述证据只覆盖 3B 已批准范围；目标事件尚未进入统一报告，真实感知、Agent 和 RESET 仍待后续模块实现。

后续并键复评：目标开始时同时按交互与取消会造成同 tick STARTED/CANCELLED 噪声，现已抑制并补两项回归；出口碰撞场景测试在传送后等待物理帧。当前 3B 正式 runner 连续两次 **695 passed / 0 failed**（81/223/47/344），日志为 `tmp/module3b-eq-review.log`；本轮未重跑 Windows 导出。

覆盖时钟、边界、暂停、猜测优先、基础视图隔离、世界命令、单步写回、玩家加减速和碰撞、机器人驻守/折返/换路/推挤/挤压暂停、摄像头扫描、真实部署同步及运行时故障锁；3B 另覆盖目标操作、暂停恢复、联络消耗与重试、KEEP_CURRENT、出口碰撞和通关优先级。测试地图、数值与角色策略仅为 fixture。模块 1 的 payload DTO、hit 上游校验与报告内容桩限制仍保留；当前 GameRuntime 的空感知回调不是实际报告实现。

CI 下载固定的 Godot 4.7.2 Linux 编辑器，执行导入和同一个 runner，并扫描错误日志。本轮续接未运行远端 CI；Windows 导出已在上述本机记录中验证。

首个实现依据 [Spec](../PRELIMINARY_DESIGN_SPEC.md)、[机制说明](../侦测定位_机制草案.md)和[开发约定](../docs/development.md)。创建工程的同一轮应补充实际版本、启动方式、测试入口和导出目标，本页不能用占位数字冒充验证结果。
