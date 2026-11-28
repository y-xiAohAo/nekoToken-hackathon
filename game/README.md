# 神启双地图探索原型

在 Godot 4.7.2 中打开 `game/project.godot`，按 F5 进入主菜单。「开始调查」播放两页序章，「继续调查」读取已有存档。两张地图都使用 2 × 2 米单元拼装，地面各为 26 × 18 格。归岸镇用暖色像素贴图，明日镇用蓝白铺装、玻璃和灯带。

接手开发时可从[神启 Godot 协同开发指南](../docs/godot-handoff.md)找到具体场景、数据和验证步骤。

- WASD 移动，Shift 奔跑，Tab 切换全景，R 返回当前地图入口。
- 靠近道具、NPC 或出入口时按 E 交互。可用鼠标或方向键选择话题，Enter 确认，Esc 关闭。
- 序章中按 Enter 补全当前段，按 Esc 跳过。完整播完后选择「进入归岸镇」。
- 在归岸镇收齐飞艇的两条线索后，可按 2 或从南侧出口进入明日镇。按 1 或走明日镇南侧出口返回归岸镇。两镇累计收集 10 件不同道具后，镇长办公室会出现通往晨星演示室的传送门。[关卡解锁说明](关卡解锁说明.md)
- 在晨星演示室中按 J 攻击、K 闪避、R 重试。
- 共 15 件道具。道具卡使用现有像素图和文案，进度保存在 Godot 的用户目录。归岸镇有贾斯珀，明日镇有艾琳、卡尔和晨星。米娅、海普、索菲亚的角色素材可在编辑器中查看。

明日镇的沃斯门柱上有左右扫描的摄像头，广场北侧有带环形蓝灯的直线巡逻机器人。尺寸、分层、摆放和设备参数见[单元建模说明](modules/单元建模说明.md)。地图效果见[归岸镇](../docs/previews/world2-guian-current.png)和[明日镇](../docs/previews/world2-mtown-overview.png)。

归岸镇南入口旁有驻点守望员，中央广场北沿有直线往返的巡街员。两人的摆放点在主场景的 `MapMount/Guian/WatchNPCs`。[归岸镇守望人物三视图](../docs/previews/guian-watch-models.png)

这一原型用于验证空间、美术和叙事交互。[设计 Spec v0.39](../PRELIMINARY_DESIGN_SPEC.md) 仍记录四轮维护预演的规则和设计边界。

## 从干净检出验证

```powershell
& 'C:\path\to\Godot.exe' --headless --path game --import
& 'C:\path\to\Godot.exe' --headless --path game --quit-after 120
& 'C:\path\to\Godot.exe' --headless --path game --fixed-fps 60 --script res://tests/opening_smoke.gd
& 'C:\path\to\Godot.exe' --headless --path game --fixed-fps 60 --script res://tests/world2_smoke.gd
& 'C:\path\to\Godot.exe' --headless --path game --script res://tests/hidden_boss_smoke.gd
```

烟雾测试覆盖主菜单、序章、双地图资源与楼梯、道具收集和存档、巡逻单位及隐藏关战斗。地图运行场景为 `world2.tscn`。标题背景由本项目使用 ImageGen 生成。角色像素图和道具图片来自本项目的神启工程，分别保存在 `actors/` 与 `props/`。建筑和灯具可直接从 `modules/` 拖入场景。仓库保留早期的蚁穴场景生成脚本供参考。重跑它会覆盖现有主场景。Pillow 只用于重建蚁穴的贴图。
