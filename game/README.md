# 游戏工程落点

工程入口为 `project.godot` 和 `scenes/main.tscn`。当前包含规则内核、内存世界与命令服务、真实灰盒运动、模块 3B 交互及模块 4B 真实感知与统一报告：玩家可用 WASD 移动，接近核验装置按 E 开始停留操作，多个目标需全部完成；联络点成功进入即消耗，可按 E 明确 KEEP_CURRENT 离开；全部目标完成后真实触碰出口形成通关条件。AgentGateway、完整 RESET 和四轮玩法仍由后续模块接入。

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

覆盖时钟、边界、暂停、猜测优先、基础视图隔离、世界命令、单步写回、玩家加减速和碰撞、机器人驻守/折返/换路/推挤/挤压暂停、摄像头扫描、真实部署同步及运行时故障锁；3B 另覆盖目标操作、暂停恢复、联络消耗与重试、KEEP_CURRENT、出口碰撞和通关优先级。测试地图、数值与角色策略仅为 fixture。模块 1 的 payload DTO 与 hit 上游校验限制仍保留；4B 已替换 GameRuntime 的空报告回调。

CI 下载固定的 Godot 4.7.2 Linux 编辑器，执行导入和同一个 runner，并扫描错误日志。本轮续接未运行远端 CI；Windows 导出已在上述本机记录中验证。

## 模块 4A 纯数据感知独立测试

4A 已按 [Feature Spec](../docs/features/2026-11-27_23-31_module-4a-sensing-kernel.md) 的批准范围新增 `scripts/sensing/` 与独立 runner；4B 已将其接入 `GameRuntime`。从仓库根目录运行：

```powershell
tools/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game --import
tools/godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/run_sensing_tests.gd
```

2026-11-28 干净模块 0–2 副本加 4A 新文件的结果：Godot 导入退出 0；SensingGeometryTests 26 passed、SensingKernelTests 88 passed，0 failed；失败探针退出 1；原有 SessionKernelTests 81、WorldCommandTests 223 均通过。4A 只输出视觉与踏板设备子包；当前真实物理接线、目标事件合批和报告回调由 4B 负责。

## 模块 4B 真实感知与统一报告

从仓库根目录运行 `--import` 后，用上文 `res://tests/run_tests.gd` 执行共享套件；4A 的 `res://tests/run_sensing_tests.gd` 继续独立运行。4B 新增 `RuntimeSensingCoordinator`、`SystemAgentView`、`GoalOperationRecord`、`UnifiedReportBatch`，Main 在 tick 0 初始化。报告边界失败使本局进入终止性 fault，报告不发布，也不自动重试。

2026-11-28 本机复验：Godot 导入退出 0；4A 独立套件 26/88 通过；共享套件 SessionKernelTests 81、WorldCommandTests 229、RuntimeMotionTests 47、RuntimeSceneTests 344、SensingRuntimeTests 129 项通过，合计 **830 passed / 0 failed**；失败探针退出 1。120 帧主场景及 Windows release 导出程序均输出 `RUNTIME_SENSING_READY` 并退出 0。固定左右移动的 600 tick、20 批生成 42 条统一记录，种子 2042 换向的 300 tick、10 批生成 22 条，两者非注入故障均为 0。多次固定路线 headless `step_once` 平均值约 13.7–41.3 ms、单次最高约 53.8–153.5 ms，玩家和机器人每 tick 最大位移分别 3/1 px；耗时波动不能推断渲染帧率。最终测试日志位于 `tmp/module4b-final-review-tests.log`；本机 `tmp/` 和 `build/` 均不入库。限制见 [4B Spec](../docs/features/2026-11-28_10-44_module-4b-runtime-sensing.md) 的 Review 记录。

首个实现依据 [Spec](../PRELIMINARY_DESIGN_SPEC.md)、[机制说明](../侦测定位_机制草案.md)和[开发约定](../docs/development.md)。创建工程的同一轮应补充实际版本、启动方式、测试入口和导出目标，本页不能用占位数字冒充验证结果。
