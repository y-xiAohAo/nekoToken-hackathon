"""Build the asymmetric ant-hill blockout from reusable Godot units."""

import logging
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
TILE = 2.0
GROUND_X = list(range(-25, 26, 2))
GROUND_Z = list(range(-17, 18, 2))
assert (len(GROUND_X), len(GROUND_Z)) == (26, 18)

groups = [
    "Ground", "Home", "Supermarket", "NorthClosedHouse",
    "OtherClosedHouses", "Courtyard", "EastCorridor", "Boundary",
]
nodes = []
counts = {}
occupied_corridor = []
INTERACTIVE_KINDS = {9, 10, 11, 12, 21, 22, 23, 24, 25, 26, 27}


def place(
    group: str,
    name: str,
    kind: int,
    x: float,
    y: float,
    z: float,
    rotation: float = 0,
    roof_tiles: tuple[int, int] | None = None,
) -> None:
    count = counts.get(name, 0) + 1
    counts[name] = count
    lines = [
        f'[node name="{name}_{count:03d}" parent="{group}" '
        'groups=["world2_units"] instance=ExtResource("piece")]',
        f"position = Vector3({x}, {y}, {z})",
    ]
    if rotation:
        lines.append(f"rotation_degrees = Vector3(0, {rotation}, 0)")
    if kind:
        lines.append(f"piece = {kind}")
    if roof_tiles:
        lines.append(f"roof_tiles = Vector2i({roof_tiles[0]}, {roof_tiles[1]})")
    if group in ("Home", "Supermarket") and kind in INTERACTIVE_KINDS:
        lines.append(f'interaction_name = "{name}"')
    nodes.append("\n".join(lines))
    if group not in ("Ground", "EastCorridor", "Boundary") and x >= 22:
        occupied_corridor.append((group, name, x, z))


def closed_house(
    group: str,
    label: str,
    columns: list[int],
    rows: list[int],
    stories: int,
    roof_kind: int,
) -> None:
    """A solid volume with a roof matching the wall exterior at every floor."""
    x0, x1 = min(columns) - 1, max(columns) + 1
    z0, z1 = min(rows) - 1, max(rows) + 1
    middle = columns[len(columns) // 2]
    for level in range(stories):
        y = level * 2.8
        for x in columns:
            rear_kind = 16 if x == middle else 2
            front_kind = 17 if level == 0 and x == middle else (
                16 if x in (columns[0], middle, columns[-1]) else 2
            )
            place(group, label + "后墙", rear_kind, x, y, z0, 180)
            place(group, label + "正面", front_kind, x, y, z1, 180)
        for z in rows:
            side_kind = 16 if z == rows[len(rows) // 2] else 2
            place(group, label + "西墙", side_kind, x0, y, z, 90)
            place(group, label + "东墙", side_kind, x1, y, z, -90)

    roof_x = (columns[0] + columns[-1]) * 0.5
    roof_z = (rows[0] + rows[-1]) * 0.5
    roof_width = len(columns) * TILE + 0.3
    roof_depth = len(rows) * TILE + 0.3
    assert abs(roof_x - roof_width * 0.5 - (x0 - 0.15)) < 0.0001
    assert abs(roof_x + roof_width * 0.5 - (x1 + 0.15)) < 0.0001
    assert abs(roof_z - roof_depth * 0.5 - (z0 - 0.15)) < 0.0001
    assert abs(roof_z + roof_depth * 0.5 - (z1 + 0.15)) < 0.0001
    place(group, label + "整栋屋顶", roof_kind, roof_x, (stories - 1) * 2.8,
          roof_z, roof_tiles=(len(columns), len(rows)))


# The full 26 x 18 tile ground remains a continuous 52 x 36 m canvas.
for x in GROUND_X:
    for z in GROUND_Z:
        place("Ground", "地砖", 0, x, 0, z)


# Northwest lived-in home: 14 x 12 m main room with a 6 x 4 m front porch.
# The front opens on the west and is partly enclosed on the east.
home_x = list(range(-23, -10, 2))
for x in home_x:
    place("Home", "住家后墙", 16 if x in (-21, -15) else 2, x, 0, -16, 180)
    place("Home", "住家二层后墙", 16 if x in (-21, -15) else 2, x, 2.8, -16, 180)
for z in range(-15, -4, 2):
    place("Home", "住家西墙", 16 if z == -11 else 2, -24, 0, z, 90)
    place("Home", "住家东墙", 16 if z == -11 else 2, -10, 0, z, -90)
for z in (-3, -1):
    place("Home", "前廊西墙", 1, -24, 0, z, 90)
for x in (-17, -15, -13, -11):
    kind = 4 if x == -15 else 2
    place("Home", "住家局部前墙", kind, x, 0, -4, 180)
for x in (-23, -21):
    place("Home", "前廊矮墙", 1, x, 0, 0)
place("Home", "前廊立柱", 14, -18, 0, 0)
place("Home", "前廊花坛", 5, -22, 0, -1)

# L-shaped, genuinely walkable second floor. A tile is omitted over the
# stairwell, and the high landing overlaps the rear floor by half a metre.
upper_home = [(x, z) for x in (-23, -21, -19, -17) for z in (-15, -13)]
upper_home += [(x, -15) for x in (-15, -13, -11)]
for x, z in upper_home:
    place("Home", "住家二层地板", 0, x, 2.8, z)
for x in (-23, -21, -19, -17):
    place("Home", "住家二层前护栏", 15, x, 2.8, -12)
for x in (-15, -13):
    place("Home", "住家回廊护栏", 15, x, 2.8, -14)
place("Home", "二层转角护栏", 15, -16, 2.8, -13, 90)
for x in (-24, -18, -10):
    place("Home", "住家支撑柱", 14, x, 0, -12)
place("Home", "住家室内楼梯", 20, -11, 0, -9.5)
place("Home", "楼上床", 21, -21, 2.8, -14)
place("Home", "楼上床头柜", 27, -23, 2.8, -14)
place("Home", "楼上衣柜", 11, -17, 2.8, -15)
place("Home", "楼上地毯", 29, -19, 2.8, -14)

# Domestic zones downstairs: cooking, eating, sitting and stored belongings.
for x in (-21, -19):
    place("Home", "家用灶台", 23, x, 0, -11.3)
place("Home", "家用柜", 11, -23, 0, -13)
place("Home", "餐桌", 9, -16, 0, -9)
place("Home", "餐椅", 10, -16, 0, -7.8)
place("Home", "餐椅", 10, -16, 0, -10.2, 180)
place("Home", "沙发", 22, -21, 0, -8)
place("Home", "起居地毯", 29, -21, 0, -6.7)
place("Home", "茶几", 27, -19.5, 0, -6.7)
place("Home", "生活储物箱", 26, -13, 0, -7)
place("Home", "门边柜", 11, -23, 0, -6)


# Centre-right supermarket is shifted two metres forward relative to the
# home. Its tall rear facade suggests a second storey without covering the
# playable ground floor.
store_x = list(range(-5, 8, 2))
for x in store_x:
    place("Supermarket", "超市后墙", 16 if x in (-3, 3) else 2, x, 0, -14, 180)
    place("Supermarket", "超市上层后墙", 16 if x in (-3, 3) else 2, x, 2.8, -14, 180)
for z in range(-13, -2, 2):
    place("Supermarket", "超市西墙", 2, -6, 0, z, 90)
    place("Supermarket", "超市东墙", 16 if z == -9 else 2, 8, 0, z, -90)
for z in (-13, -11):
    place("Supermarket", "超市上层西墙", 2, -6, 2.8, z, 90)
    place("Supermarket", "超市上层东墙", 2, 8, 2.8, z, -90)
for x in (-5, 7):
    place("Supermarket", "超市门面墙", 2, x, 0, -2, 180)
for x in (-3, -1, 1, 3, 5):
    place("Supermarket", "超市入口上沿", 1, x, 2.8, -2)
place("Supermarket", "超市左门柱", 14, -6, 0, -2)
place("Supermarket", "超市右门柱", 14, 8, 0, -2)
place("Supermarket", "收银台", 12, -3, 0, -5.3)
place("Supermarket", "收银椅", 10, -3, 0, -6.5, 180)
for x, z in [(-2, -10), (1, -10), (4, -10), (1, -7.5), (4, -7.5)]:
    place("Supermarket", "商品货架", 24, x, 0, z)
for x in (-3, 0, 3):
    place("Supermarket", "靠墙冷柜", 25, x, 0, -12.6)
for x, z in [(-4.5, -3.7), (5.5, -4.4), (6, -12)]:
    place("Supermarket", "补货木箱", 26, x, 0, z)
place("Supermarket", "超市门边储物柜", 11, 6.5, 0, -6)


# Third rear building: a tall sealed main volume with a lower, attached wing.
# The two roofs are separate stretched modules so each mass aligns precisely.
closed_house("NorthClosedHouse", "后方双层楼", [13, 15, 17, 19],
             [-15, -13, -11, -9], 2, 19)
closed_house("NorthClosedHouse", "前侧附属房", [15, 17, 19],
             [-7, -5], 1, 18)
for x in (15, 17):
    place("NorthClosedHouse", "封闭楼外挑阳台", 0, x, 2.8, -7)
    place("NorthClosedHouse", "阳台护栏", 15, x, 2.8, -6)
for x in (14, 18):
    place("NorthClosedHouse", "阳台支柱", 14, x, 0, -6)


# Irregular, smaller closed masses around the plaza.
closed_house("OtherClosedHouses", "西侧小屋", [-23, -21, -19, -17],
             [3, 5], 1, 18)
closed_house("OtherClosedHouses", "东侧机房", [13, 15, 17, 19],
             [1, 3, 5], 1, 18)
closed_house("OtherClosedHouses", "西南矮屋", [-23, -21, -19],
             [11, 13, 15], 1, 19)
closed_house("OtherClosedHouses", "东南仓房", [9, 11, 13],
             [11, 13], 1, 19)

# Offset planters, lights, short walls and seats shape a non-mirrored courtyard.
for x, z in [(-15, 1), (-11, 5), (-8, 11), (-2, 1), (5, 5),
             (7, 15), (16, 9), (-13, 15)]:
    place("Courtyard", "庭院花坛", 5, x, 0, z)
for x, z, rotation in [(-14, 3, 0), (-10, 9, 90), (-6, 13, 0),
                       (4, 3, 90), (7, 9, 0), (18, 11, 90)]:
    place("Courtyard", "庭院矮墙", 1, x, 0, z, rotation)
for x, z, rotation in [(-14, 8, 90), (-1, 6, 0), (5, 13, 90)]:
    place("Courtyard", "路边长椅", 13, x, 0, z, rotation)
for x, z in [(-9, -1), (-5, 10), (10, 5), (2, 15)]:
    place("Courtyard", "院内路灯", 28, x, 0, z)
for x, z in [(-7, 5), (5, 1), (15, 13)]:
    place("Courtyard", "庭院木箱", 26, x, 0, z)


# A continuous two-tile (4 m) east corridor. All structure stays to x <= 22.
# Decorations hug the outside edge; x=23 remains a clear through route.
for z in (-17, -15, -13, -11, -9, 1, 3, 5, 13, 15):
    place("EastCorridor", "走廊内侧矮墙", 1, 22, 0, z, 90)
for z in (-16, -8, 0, 8, 16):
    place("EastCorridor", "走廊路灯", 28, 25.35, 0, z)
for z in (-12, -3, 5, 13):
    place("EastCorridor", "走廊靠边物资箱", 26, 25.3, 0, z)
for z in (-5, 10):
    place("EastCorridor", "走廊靠边花坛", 5, 24.9, 0, z)

# Perimeter breaks at an offset south entrance and at both corridor ends.
for x in GROUND_X:
    if x not in (-7, -5, -3, 23, 25):
        place("Boundary", "南侧围墙", 1, x, 0, 18)
    if x not in (23, 25) and abs(x) > 9:
        place("Boundary", "北侧围墙", 1, x, 0, -18)
for z in GROUND_Z:
    if z not in (-5, -3, 7, 9):
        place("Boundary", "西侧围墙", 1, -26, 0, z, 90)
    if z not in (-17, -15, 15, 17):
        place("Boundary", "东侧围墙", 1, 26, 0, z, 90)

assert not occupied_corridor, occupied_corridor


scene = """[gd_scene format=3]

[ext_resource type="PackedScene" path="res://modules/piece.tscn" id="piece"]
[ext_resource type="Script" path="res://world2.gd" id="controller"]
[ext_resource type="Script" path="res://player.gd" id="player"]
[ext_resource type="Texture2D" path="res://actors/traveller.png" id="traveller"]

[sub_resource type="Environment" id="environment"]
background_mode = 1
background_color = Color(0.105, 0.14, 0.19, 1)
ambient_light_source = 2
ambient_light_color = Color(0.69, 0.73, 0.76, 1)
ambient_light_energy = 0.5

[sub_resource type="CapsuleShape3D" id="body"]
height = 1.65
radius = 0.25

[sub_resource type="SystemFont" id="font"]
font_names = PackedStringArray("Microsoft YaHei", "SimHei")

[sub_resource type="Theme" id="ui"]
default_font = SubResource("font")
default_font_size = 19
Label/colors/font_color = Color(1, 0.98, 0.93, 1)
Label/colors/font_outline_color = Color(0.04, 0.06, 0.08, 1)
Label/constants/outline_size = 6

[node name="ModularWorld" type="Node3D"]
script = ExtResource("controller")

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("environment")

[node name="Sun" type="DirectionalLight3D" parent="."]
rotation_degrees = Vector3(-52, -33, 0)
light_color = Color(1, 0.84, 0.67, 1)
light_energy = 0.72
shadow_enabled = true

[node name="Camera" type="Camera3D" parent="."]
projection = 1
size = 12.5
far = 180.0
current = true

[node name="Player" type="CharacterBody3D" parent="."]
position = Vector3(-5, 0.08, 15)
floor_snap_length = 0.3
floor_max_angle = 1.1
script = ExtResource("player")

[node name="Capsule" type="CollisionShape3D" parent="Player"]
position = Vector3(0, 0.825, 0)
shape = SubResource("body")

[node name="Traveller" type="Sprite3D" parent="Player"]
position = Vector3(0, 0.68, -0.78)
billboard = 1
texture_filter = 0
pixel_size = 0.028
texture = ExtResource("traveller")

[node name="HUD" type="CanvasLayer" parent="."]

[node name="Status" type="Label" parent="HUD"]
offset_left = 19
offset_top = 14
theme = SubResource("ui")

[node name="Controls" type="Label" parent="HUD"]
anchor_left = 1
anchor_right = 1
offset_left = -630
offset_right = -20
offset_top = 14
horizontal_alignment = 2
theme = SubResource("ui")
text = "WASD 移动   E 查看   Tab 全景   V 切换外观   R 回入口"

[node name="Prompt" type="Label" parent="HUD"]
anchor_left = 0.5
anchor_top = 1.0
anchor_right = 0.5
anchor_bottom = 1.0
offset_left = -300
offset_top = -70
offset_right = 300
offset_bottom = -24
horizontal_alignment = 1
theme = SubResource("ui")

"""

for group in groups:
    scene += f'[node name="{group}" type="Node3D" parent="."]\n\n'
scene += "\n\n".join(nodes) + "\n"
(ROOT / "world2.tscn").write_text(scene, encoding="utf-8")
logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logging.info(
    "Ground: %s x %s = %s tiles",
    len(GROUND_X), len(GROUND_Z), len(GROUND_X) * len(GROUND_Z),
)
logging.info("Scene: %s reusable unit instances", len(nodes))
logging.info("East corridor: two tiles, continuous from north to south")
