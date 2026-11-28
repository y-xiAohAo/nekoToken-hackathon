# 神启 Godot 协同开发指南

本指南面向接手地图、角色、叙事交互和设备单元的同事。共享工程在仓库的 `game/`，2026-11-28 的双地图试玩基线位于 `team/branch-2`，已用 Godot 4.7.2 Windows 版验证。[试玩基线提交](https://github.com/y-xiAohAo/nekoToken-hackathon/commit/2c4c732f89bee043972443ddf52b43c922ea7d54)

## 启动与试玩

首次取项目时检出双地图所在的分支。

```powershell
git clone --branch team/branch-2 https://github.com/y-xiAohAo/nekoToken-hackathon.git
cd nekoToken-hackathon
```

用 Godot 导入 [game/project.godot](../game/project.godot)，等待资源导入后按 **F5**。从主菜单选择「开始调查」播放序章，随后进入归岸镇。WASD 移动，Shift 奔跑，靠近道具、NPC 或出口时按 E 交互。Tab 切换全景，R 回当前地图入口。收齐飞艇两条线索后，可按 2 进入明日镇。按 1 返回归岸镇。对话可用鼠标或方向键选择，Enter 确认，Esc 关闭。[关卡解锁说明](../game/关卡解锁说明.md)

试玩包括两张可往返的地图、15 件叙事道具和 4 名可交谈 NPC。建筑按 2 × 2 米单元拼装，两镇各用 26 × 18 格。归岸镇采用暖色像素贴图，明日镇采用蓝白材质和冷色灯带。[归岸镇全景](previews/world2-guian-current.png) · [明日镇全景](previews/world2-mtown-overview.png)

## 按任务找文件

| 要改什么 | 从哪里开始 |
| --- | --- |
| 主菜单和两页序章 | [opening 目录](../game/opening/) |
| 主场景、归岸镇建筑、旧居、飞艇与镇口 | [world2.tscn](../game/world2.tscn) 的 `MapMount/Guian` |
| 明日镇建筑、住宅街和设备 | [modular_town.tscn](../game/districts/mtown/modular_town.tscn) 的功能区节点与 `SecurityUnits` |
| 地图切换、靠近提示、道具存档 | [world2.gd](../game/world2.gd) |
| 威廉的移动、碰撞和行走动画 | [player.gd](../game/player.gd) · [william.tscn](../game/actors/characters_2046_v2/william.tscn) |
| NPC 素材、朝向和对话 | [人物场景目录](../game/actors/characters_2046_v2) · [story_actor.gd](../game/actors/story_actor.gd) · [npc_dialogue.gd](../game/districts/npc_dialogue.gd) |
| 道具文案、图像和交互界面 | [props.json](../game/props/props.json) · [道具图鉴](../game/props/道具图鉴.md) · [interaction_ui.gd](../game/districts/interaction_ui.gd) |
| 墙、地砖、楼梯、柜台等可复用模块 | [piece.tscn](../game/modules/piece.tscn) · [单元尺寸与碰撞说明](../game/modules/单元建模说明.md) |
| 摄像头和巡逻机器人 | [security_camera.tscn](../game/modules/security_camera.tscn) · [patrol_robot.tscn](../game/modules/patrol_robot.tscn) |

`world2.gd` 负责装载当前地图并收集其 `Markers` 节点。归岸镇随主场景载入，明日镇在首次进入时实例化。切图会把威廉移到目标地图的 `Spawn`，并启用该地图的互动点。

## 修改地图与互动

### 地图和单元件

- 地面以 **Y = 0** 对齐，故居、镇长办公室和沃斯档案室的二楼地面为 **Y = 2.8 米**。改楼梯或平台时，跑一遍上下楼，并走到实际交互点检查碰撞。
- 明日镇三栋公共建筑彼此分开。纪念品店在镇长办公室一楼**朝广场的左前角**，柜台朝南。沃斯一楼是展厅、二楼是档案室。面包房夹在右侧南北两段住宅之间。移动柜台、展柜或柱子时，从步行视角和 Tab 全景各看一次遮挡。
- 建筑和家具实例沿用 `piece.tscn`。在检查器改 `piece` 选类型，`district` 选区域材质。旧的 `build_world2.py` 会直接覆盖主场景，日常摆放请编辑现行场景。 [单元建模说明](../game/modules/单元建模说明.md)

### 道具

1. 修改玩家看到的名称、介绍、图片时，从 `game/props/props.json` 入手。图片放在 `game/props/`，图鉴同步记录位置与文案。
2. 调整拾取位置时，归岸镇改 `MapMount/Guian/Markers`，明日镇改本场景的 `Markers`。普通道具的节点名对应 JSON 的 `id`。归岸镇门边柜 `drawer` 是共用入口，里面的采访截屏和毕业旅行折页由 `world2.gd` 里的 `DRAWER_ITEMS` 配对。
3. `Marker3D.position` 是玩家靠近的位置，`display_offset` 是图标相对标记点的偏移。比如柜台前放交互点，图标落在柜面上。移动道具时，记得从玩家实际能站到的一侧试按 E。

收集进度按道具 `id` 写入 `user://story_progress.cfg`。改名称、文案或位置时沿用原有 `id`，旧存档才能继续识别这件道具。 [道具清单](../game/props/props.json) · [道具图鉴](../game/props/道具图鉴.md)

### 角色与设备

- NPC 通过相应地图的 `npc_<id>` 标记和 `npc_dialogue.gd` 配对。归岸镇是贾斯珀，明日镇是卡尔、艾琳和晨星。**米娅、海普和索菲亚在当前故事里失踪**，角色素材仍在人物目录供后续剧情使用。
- 摄像头实例在明日镇 `SecurityUnits/VossEntryCamera`。局部 **−Z** 朝观察方向，摆角、周期、距离和视角可以在检查器调。墙体会遮挡视线，发现和失去目标分别发出 `target_spotted`、`target_lost`。
- 机器人实例在 `SecurityUnits/PlazaPatrol`。从场景实例原点沿局部 **−Z** 走到端点，再反向行驶。检查器可调距离、速度和端点等待时间。当前脚本实现直线巡逻与遇阻暂停，圆形探头和一圈蓝灯表达全向视野的外观设定。

## 提交前验证

从仓库根目录运行。在 PowerShell 中把第一行改成本机 Godot 路径。

```powershell
$godot = 'C:\Tools\Godot_v4.7.2-stable_win64.exe'
& $godot --headless --path game --import
& $godot --headless --path game --quit-after 120
& $godot --headless --path game --fixed-fps 60 --script res://tests/opening_smoke.gd
& $godot --headless --path game --fixed-fps 60 --script res://tests/world2_smoke.gd
& $godot --headless --path game --script res://tests/hidden_boss_smoke.gd

python -m unittest discover -s tests -v
python scripts/check_repository.py
python scripts/check_project_links.py --all
```

基线的 Godot 烟雾测试为 **37 项通过、0 项失败**。它覆盖两图加载、道具图片载入、三处楼梯、代表性道具交互、收集存档和设备运动。改布局、文案或设备时，再在 F5 里复查改动点。重点看切图后的提示、家具遮挡、对话能否关闭、机器人遇阻和摄像头遮挡。 [烟雾测试](../game/tests/world2_smoke.gd)

## 协作与交接

- 继续双地图原型时，可以从 `origin/team/branch-2` 开短期分支。多人并行时先约定谁负责同一个场景。地图改动提交对应 `.tscn`，剧情改动提交对应数据，尽量让每次提交只处理一个任务。
- 提交 Godot 源场景、脚本、素材以及对应的 `.uid` 和 `.import`。本机凭据、`.godot/` 缓存、临时截图和构建产物按仓库忽略规则管理。交接时写清改动点、可复现的试玩路线和实际验证结果。 [仓库协作约定](../CONTRIBUTING.md)
- 双地图原型用于验证空间、美术和叙事交互。四轮维护预演、设备上报、Agent 权限和 RESET 玩法按以下设计资料推进。 [设计 Spec](../PRELIMINARY_DESIGN_SPEC.md) · [侦测定位机制](../侦测定位_机制草案.md)
