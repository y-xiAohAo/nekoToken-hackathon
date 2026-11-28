# 神启双地图探索原型

在 Godot 4.7.2 中打开 `game/project.godot`，按 F5 进入归岸镇。两张地图都使用 2 × 2 米单元拼装，地面各为 26 × 18 格。归岸镇用暖色像素贴图，明日镇用蓝白铺装、玻璃和灯带。

接手开发时可从[神启 Godot 协同开发指南](../docs/godot-handoff.md)找到具体场景、数据和验证步骤。

- WASD 移动，Shift 奔跑，Tab 切换全景，R 返回当前地图入口。
- 靠近道具、NPC 或出入口时按 E 交互。可用鼠标或方向键选择话题，Enter 确认，Esc 关闭。
- 按 1 前往归岸镇，按 2 前往明日镇。也可与两张地图南侧的出口交互。
- 共 15 件道具。道具卡使用现有像素图和文案，进度保存在 Godot 的用户目录。归岸镇有贾斯珀，明日镇有艾琳、卡尔和晨星。米娅、海普、索菲亚的角色素材可在编辑器中查看。

明日镇的沃斯门柱上有左右扫描的摄像头，广场北侧有带环形蓝灯的直线巡逻机器人。尺寸、分层、摆放和设备参数见[单元建模说明](modules/单元建模说明.md)。地图效果见[归岸镇](../docs/previews/world2-guian-current.png)和[明日镇](../docs/previews/world2-mtown-overview.png)。

这一原型用于验证空间、美术和叙事交互。[设计 Spec v0.39](../PRELIMINARY_DESIGN_SPEC.md) 仍记录四轮维护预演的规则和设计边界。

## 从干净检出验证

```powershell
& 'C:\path\to\Godot.exe' --headless --path game --import
& 'C:\path\to\Godot.exe' --headless --path game --quit-after 120
& 'C:\path\to\Godot.exe' --headless --path game --script res://tests/world2_smoke.gd
```

烟雾测试覆盖两张地图的资源载入、三处楼梯、道具弹窗和存档、摄像头摆动及机器人巡逻。两张地图的运行入口为 `world2.tscn`。建筑和灯具可直接从 `modules/` 拖入场景。角色像素图和图片均来自本项目的神启工程，分别保存在 `actors/characters_2046_v2/` 与 `props/`。仓库保留早期的蚁穴场景生成脚本供参考。重跑它会覆盖现有主场景。Pillow 只用于重建蚁穴的贴图。
