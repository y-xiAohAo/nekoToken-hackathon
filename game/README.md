# 蚁穴模块场景原型

本目录是可运行的 Godot 工程，入口为 `world2.tscn`。当前成果是蚁穴地图的模块组合与第一轮贴图：26 × 18 块、每块 2 × 2 米，共 52 × 36 米。场景包含 804 个基础单元实例、开放式住家和超市、可走的室内楼梯与二层、错落的封闭房屋及东侧两格宽的贯通走廊。

这是一张空间与美术原型地图。角色可移动，家具可用 E 查看名称；[设计 Spec v0.39](../PRELIMINARY_DESIGN_SPEC.md) 中的设备报告、Agent 对抗、四轮和 RESET 尚未实现。原型包含的二层也不代表现行 Spec 的关卡规则已更改。

## 打开与操作

使用 Godot 4.x 打开 `game/project.godot`，按 F5 运行主场景。此次在 Windows 上用 Godot 4.7.2 测试；团队尚未锁定统一的引擎小版本。

- WASD 移动，E 查看附近家具名称。
- Tab 切换全景，V 切换蚁穴贴图与 M 镇配色预览，R 返回入口。

模块的尺寸、碰撞及搭建方法见[单元建模说明](modules/单元建模说明.md)。`modules/piece.tscn` 是可复用的单元场景，三个 `modules/*kit_preview.tscn` 场景用于查看单元组合。蚁穴外观使用 `modules/textures/anthill/` 中的 20 张像素贴图；M 镇仍是配色预览。

## 重新生成与验证

从仓库根目录运行：

```powershell
python game/modules/build_world2.py
python -m pip install -r game/requirements-asset-tools.txt
python game/modules/generate_ant_textures.py
& 'C:\path\to\Godot.exe' --headless --path game --import
& 'C:\path\to\Godot.exe' --headless --path game --script res://tests/world2_smoke.gd
& 'C:\path\to\Godot.exe' --headless --path game --quit-after 120
```

`build_world2.py` 会覆盖 `world2.tscn`；在编辑器里改动场景后请先保存副本。Pillow 只用于重建贴图，运行游戏不需要安装它。

2026-11-27 在 Godot 4.7.2 Windows 版执行了资源导入、主场景无界面启动和 `world2_smoke.gd`，均完成；检查结果为 8 项通过、0 项失败。Windows 导出也已实际尝试，但工程还没有 `export_presets.cfg`，因此 Godot 未生成程序包；本机同时未安装相应导出模板。导出前需确定团队使用的引擎版本并配置对应预设和模板。

整体效果见[蚁穴地图预览](../docs/previews/world2-anthill-overview.png)，另有[住家](../docs/previews/world2-home.png)和[超市](../docs/previews/world2-supermarket.png)局部图。
