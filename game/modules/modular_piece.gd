@tool
extends StaticBody3D

enum Piece {
	FLOOR,
	LOW_WALL,
	HIGH_WALL,
	CORNER,
	DOORWAY,
	PLANTER,
	RAMP,
	ROOF,
	STAIRS,
	TABLE,
	CHAIR,
	CABINET,
	COUNTER,
	BENCH,
	COLUMN,
	RAILING,
	WINDOW_WALL,
	SEALED_DOOR,
	ROOF_FLAT,
	ROOF_GABLE,
	STAIR_FLIGHT,
	BED,
	SOFA,
	KITCHEN,
	STORE_SHELF,
	FREEZER,
	CRATE,
	SIDE_TABLE,
	LAMP_POST,
	RUG,
	DISPLAY_CASE,
	TERMINAL,
	AIRSHIP_WRECK,
	TOWN_SIGN,
	COAT_RACK,
	BAKERY_SHELF,
}

enum District { ANT_HILL, M_TOWN }

@export var piece: Piece = Piece.FLOOR:
	set(value):
		piece = value
		_rebuild_if_ready()

@export var district: District = District.ANT_HILL:
	set(value):
		district = value
		_rebuild_if_ready()

@export var roof_tiles := Vector2i(2, 2):
	set(value):
		roof_tiles = Vector2i(maxi(1, value.x), maxi(1, value.y))
		_rebuild_if_ready()

@export var interaction_name: String = ""
@export var display_model := false:
	set(value):
		display_model = value
		_rebuild_if_ready()

const UNIT := 2.0
const FLOOR_DEPTH := 0.16
const LOW_HEIGHT := 0.88
const HIGH_HEIGHT := 2.8

static var _material_cache: Dictionary = {}
static var _city_textures: Dictionary = {}
var _built := false


func _ready() -> void:
	_built = true
	_rebuild()


func _rebuild_if_ready() -> void:
	if _built and is_inside_tree():
		_rebuild()


func _rebuild() -> void:
	for child in get_children():
		if child.has_meta("generated_piece"):
			remove_child(child)
			child.queue_free()

	var base := _material("base")
	var trim := _material("trim")
	var inset := _material("inset")
	var accent := _material("accent")
	var soil := _material("soil")
	var wood := _material("wood")
	var fabric := _material("fabric")
	var metal := _material("metal")
	var glass := _material("glass")

	match piece:
		Piece.FLOOR:
			_box("地面基座", Vector3(0, -0.08, 0), Vector3(UNIT, FLOOR_DEPTH, UNIT), base, true)
			if district == District.M_TOWN:
				_box("铺装接缝", Vector3(-0.986, 0.004, 0), Vector3(0.028, 0.008, UNIT), inset)
				_box("铺装接缝", Vector3(0, 0.004, -0.986), Vector3(UNIT, 0.008, 0.028), inset)
			else:
				for edge in [-0.5, 0.5]:
					_box("铺装接缝", Vector3(edge, 0.006, 0), Vector3(0.012, 0.012, UNIT), inset)
					_box("铺装接缝", Vector3(0, 0.006, edge), Vector3(UNIT, 0.012, 0.012), inset)
		Piece.LOW_WALL:
			_wall("矮墙", 0, LOW_HEIGHT, base, trim, inset)
		Piece.HIGH_WALL:
			_wall("高墙", 0, HIGH_HEIGHT, base, trim, inset)
		Piece.CORNER:
			_wall("转角横段", -0.6, LOW_HEIGHT, base, trim, inset)
			_box("转角纵段", Vector3(-0.85, LOW_HEIGHT * 0.5, -0.65),
				Vector3(0.3, LOW_HEIGHT, 1.3), base, true)
			_box("转角压顶", Vector3(-0.85, LOW_HEIGHT + 0.035, -0.65),
				Vector3(0.36, 0.08, 1.34), trim)
		Piece.DOORWAY:
			_box("门洞左墙", Vector3(-0.78, 1.4, 0), Vector3(0.44, HIGH_HEIGHT, 0.3), base, true)
			_box("门洞右墙", Vector3(0.78, 1.4, 0), Vector3(0.44, HIGH_HEIGHT, 0.3), base, true)
			_box("门楣", Vector3(0, 2.57, 0), Vector3(1.18, 0.46, 0.34), trim, true)
			_box("门槛", Vector3(0, 0.025, 0), Vector3(1.14, 0.05, 0.34), inset)
			_box("左侧标记", Vector3(-0.52, 1.5, -0.172), Vector3(0.04, 1.65, 0.012), accent)
		Piece.PLANTER:
			_box("花坛底座", Vector3(0, 0.18, 0), Vector3(UNIT, 0.36, 1.0), base)
			# Match the full planter footprint up to the top of its rim.
			_box_collision("花坛", Vector3(0, 0.255, 0), Vector3(UNIT, 0.51, 1.0))
			_box("内层土壤", Vector3(0, 0.375, 0), Vector3(1.65, 0.05, 0.64), soil)
			for side in [-1.0, 1.0]:
				_box("长边压顶", Vector3(0, 0.45, side * 0.43),
					Vector3(UNIT, 0.12, 0.14), trim)
				_box("短边压顶", Vector3(side * 0.93, 0.45, 0),
					Vector3(0.14, 0.12, 0.84), trim)
			if district == District.ANT_HILL:
				for x in [-0.55, 0, 0.55]:
					_box("植株", Vector3(x, 0.64, 0), Vector3(0.18, 0.42, 0.18), accent)
			else:
				_box("设备检修盖", Vector3(0, 0.41, 0), Vector3(1.36, 0.06, 0.38), inset)
				_box("状态灯", Vector3(0, 0.45, -0.21), Vector3(0.9, 0.03, 0.04), accent)
		Piece.RAMP:
			_box("低端平台", Vector3(0, -0.08, 1.6), Vector3(UNIT, 0.16, 0.8), base, true)
			_box("高端平台", Vector3(0, 0.52, -1.6), Vector3(UNIT, 0.16, 0.8), base, true)
			_ramp_surface(base)
			for side in [-0.95, 0.95]:
				_box("坡道侧缘", Vector3(side, 0.32, 0), Vector3(0.1, 0.08, 2.4), trim)
		Piece.STAIRS:
			_box("低端平台", Vector3(0, -0.08, 1.6), Vector3(UNIT, 0.16, 0.8), base, true)
			_box("高端平台", Vector3(0, 0.52, -1.6), Vector3(UNIT, 0.16, 0.8), base, true)
			for step in range(6):
				var height := (step + 1) * 0.1
				var center_z := 1.0 - step * 0.4
				_box("踏步%02d" % (step + 1), Vector3(0, height * 0.5, center_z),
					Vector3(UNIT, height, 0.4), base, true)
				_box("踏步边缘%02d" % (step + 1), Vector3(0, height + 0.007, center_z + 0.17),
					Vector3(1.86, 0.014, 0.04), inset)
			for side in [-0.96, 0.96]:
				_box("楼梯侧缘", Vector3(side, 0.32, 0), Vector3(0.08, 0.08, 2.4), trim)
		Piece.ROOF:
			_box("屋檐底板", Vector3(0, 2.74, 0), Vector3(UNIT, 0.12, UNIT), base, true)
			_roof_slope(-1.0, 0.0, trim)
			_roof_slope(0.0, 1.0, trim)
			_box("屋脊", Vector3(0, 3.21, 0), Vector3(UNIT, 0.09, 0.13), accent)
			for x in [-0.75, -0.25, 0.25, 0.75]:
				_box("屋面拼缝", Vector3(x, 3.03, 0), Vector3(0.025, 0.025, 1.95), inset)
		Piece.TABLE:
			_box("桌面", Vector3(0, 0.75, 0), Vector3(1.5, 0.11, 0.85), wood, true)
			for x in [-0.61, 0.61]:
				for z in [-0.29, 0.29]:
					_box("桌腿", Vector3(x, 0.35, z), Vector3(0.12, 0.7, 0.12), metal, true)
			_box("桌边", Vector3(0, 0.68, 0.43), Vector3(1.5, 0.08, 0.04), trim)
		Piece.CHAIR:
			_box("椅座", Vector3(0, 0.46, 0), Vector3(0.72, 0.13, 0.68), fabric, true)
			_box("靠背", Vector3(0, 0.82, -0.31), Vector3(0.72, 0.69, 0.12), fabric, true)
			for x in [-0.28, 0.28]:
				for z in [-0.25, 0.25]:
					_box("椅腿", Vector3(x, 0.2, z), Vector3(0.075, 0.4, 0.075), metal)
			_box("椅背框", Vector3(0, 1.15, -0.31), Vector3(0.74, 0.055, 0.14), metal)
		Piece.CABINET:
			_box("柜体", Vector3(0, 0.95, 0), Vector3(1.55, 1.9, 0.56), wood, true)
			_box("柜脚", Vector3(0, 0.07, 0), Vector3(1.6, 0.14, 0.62), metal)
			for x in [-0.38, 0.38]:
				_box("柜门", Vector3(x, 1.02, 0.297), Vector3(0.71, 1.62, 0.035), trim)
				_box("把手", Vector3(x + (0.24 if x < 0 else -0.24), 1.04, 0.325),
					Vector3(0.035, 0.18, 0.035), metal)
			_box("柜顶", Vector3(0, 1.94, 0), Vector3(1.64, 0.07, 0.63), trim)
		Piece.COUNTER:
			_box("柜台主体", Vector3(0, 0.48, 0), Vector3(1.82, 0.96, 0.73), wood, true)
			_box("服务台面", Vector3(0, 1.02, 0), Vector3(1.92, 0.12, 0.82), trim, true)
			_box("柜台底脚", Vector3(0, 0.08, 0.39), Vector3(1.8, 0.16, 0.055), metal)
			for x in [-0.51, 0.51]:
				_box("前面板", Vector3(x, 0.55, 0.378), Vector3(0.8, 0.72, 0.025), base)
		Piece.BENCH:
			_box("长椅座面", Vector3(0, 0.43, 0), Vector3(1.9, 0.13, 0.67), fabric)
			_box_collision("长椅底座", Vector3(0, 0.2475, -0.01), Vector3(1.9, 0.495, 0.69))
			_box("长椅背", Vector3(0, 0.81, -0.3), Vector3(1.9, 0.74, 0.11), fabric, true)
			for x in [-0.78, 0.78]:
				_box("长椅脚", Vector3(x, 0.2, 0), Vector3(0.09, 0.4, 0.58), metal)
			for x in [-0.32, 0.32]:
				_box("座位分缝", Vector3(x, 0.505, 0), Vector3(0.018, 0.012, 0.64), inset)
		Piece.COLUMN:
			_box("立柱", Vector3(0, 1.4, 0), Vector3(0.32, 2.8, 0.32), base, true)
			_box("柱脚", Vector3(0, 0.16, 0), Vector3(0.5, 0.32, 0.5), trim)
			_box("柱头", Vector3(0, 2.68, 0), Vector3(0.5, 0.24, 0.5), trim)
		Piece.RAILING:
			_box("护栏底框", Vector3(0, 0.12, 0), Vector3(2.0, 0.24, 0.12), base, true)
			_box("护栏挡板", Vector3(0, 0.48, 0), Vector3(2.0, 0.72, 0.065), metal, true)
			_box("护栏扶手", Vector3(0, 0.89, 0), Vector3(2.0, 0.1, 0.19), trim, true)
			for x in [-0.9, 0.9]:
				_box("护栏立杆", Vector3(x, 0.52, 0), Vector3(0.1, 0.8, 0.16), trim)
		Piece.WINDOW_WALL:
			_box("实墙", Vector3(0, 1.4, 0), Vector3(2.0, 2.8, 0.3), base, true)
			if district == District.ANT_HILL:
				for face in [-0.159, 0.159]:
					_box("褪色青绿墙裙", Vector3(0, 0.44, face),
						Vector3(2.0, 0.88, 0.018), _material("band"))
			_box("窗面", Vector3(0, 1.65, -0.166), Vector3(1.34, 0.97, 0.025), glass)
			for x in [-0.71, 0.71]:
				_box("窗框竖条", Vector3(x, 1.65, -0.18), Vector3(0.08, 1.1, 0.07), metal)
			for y in [1.1, 2.2]:
				_box("窗框横条", Vector3(0, y, -0.18), Vector3(1.5, 0.08, 0.07), metal)
			_box("窗中梃", Vector3(0, 1.65, -0.19), Vector3(0.05, 1.1, 0.06), metal)
		Piece.SEALED_DOOR:
			_box("封闭外墙", Vector3(0, 1.4, 0), Vector3(2.0, 2.8, 0.3), base, true)
			if district == District.ANT_HILL:
				for x in [-0.78, 0.78]:
					_box("门侧墙裙", Vector3(x, 0.44, -0.159),
						Vector3(0.44, 0.88, 0.018), _material("band"))
			_box("门板", Vector3(0, 1.11, -0.176), Vector3(1.12, 2.13, 0.055), wood)
			_box("门框左", Vector3(-0.61, 1.18, -0.2), Vector3(0.1, 2.33, 0.08), metal)
			_box("门框右", Vector3(0.61, 1.18, -0.2), Vector3(0.1, 2.33, 0.08), metal)
			_box("门框顶", Vector3(0, 2.33, -0.2), Vector3(1.32, 0.09, 0.08), metal)
			_box("门把手", Vector3(0.4, 1.07, -0.222), Vector3(0.06, 0.22, 0.05), trim)
		Piece.ROOF_FLAT:
			var roof_width := roof_tiles.x * UNIT + 0.3
			var roof_depth := roof_tiles.y * UNIT + 0.3
			_box("整栋平屋顶", Vector3(0, 2.88, 0), Vector3(roof_width, 0.18, roof_depth), base, true)
			for side in [-1.0, 1.0]:
				_box("长边女儿墙", Vector3(0, 3.15, side * (roof_depth * 0.5 - 0.09)),
					Vector3(roof_width, 0.45, 0.18), trim, true)
				_box("短边女儿墙", Vector3(side * (roof_width * 0.5 - 0.09), 3.15, 0),
					Vector3(0.18, 0.45, roof_depth), trim, true)
			for column in range(1, roof_tiles.x):
				var seam_x := -roof_tiles.x + column * 2.0
				_box("平屋顶接缝", Vector3(seam_x, 2.976, 0),
					Vector3(0.025, 0.012, roof_depth - 0.3), inset)
		Piece.ROOF_GABLE:
			_gable_roof(roof_tiles.x * UNIT + 0.3,
				roof_tiles.y * UNIT + 0.3, trim, inset)
		Piece.STAIR_FLIGHT:
			_box("楼梯低端平台", Vector3(0, -0.08, 4.25), Vector3(2.0, 0.16, 1.5), base, true)
			_box("楼梯高端平台", Vector3(0, 2.72, -4.25), Vector3(2.0, 0.16, 1.5), base, true)
			for step in range(14):
				var step_height := (step + 1) * 0.2
				var step_z := 3.25 - step * 0.5
				_box("二层踏步%02d" % (step + 1), Vector3(0, step_height * 0.5, step_z),
					Vector3(2.0, step_height, 0.5), base, true)
				_box("二层踏步边%02d" % (step + 1), Vector3(0, step_height + 0.008, step_z + 0.21),
					Vector3(1.88, 0.016, 0.045), inset)
				for side in [-0.97, 0.97]:
					_box("随踏步升高的侧护栏", Vector3(side, step_height + 0.36, step_z),
						Vector3(0.07, 0.72, 0.5), trim)
		Piece.BED:
			_box("床架", Vector3(0, 0.22, 0), Vector3(1.6, 0.3, 1.95), wood, true)
			_box("床垫", Vector3(0, 0.41, 0), Vector3(1.48, 0.13, 1.82), fabric, true)
			_box("床头", Vector3(0, 0.62, -0.94), Vector3(1.64, 0.86, 0.1), wood, true)
			for x in [-0.4, 0.4]:
				_box("枕头", Vector3(x, 0.53, -0.58), Vector3(0.56, 0.12, 0.34), trim)
			_box("薄毯", Vector3(0, 0.49, 0.45), Vector3(1.42, 0.04, 0.72), accent)
		Piece.SOFA:
			_box("沙发座", Vector3(0, 0.42, 0), Vector3(1.82, 0.32, 0.78), fabric, true)
			_box("沙发背", Vector3(0, 0.81, -0.32), Vector3(1.82, 0.64, 0.16), fabric, true)
			for x in [-0.86, 0.86]:
				_box("扶手", Vector3(x, 0.59, 0), Vector3(0.14, 0.58, 0.8), wood, true)
			_box("坐垫分缝", Vector3(0, 0.59, 0.07), Vector3(0.018, 0.015, 0.58), inset)
		Piece.KITCHEN:
			_box("灶台柜体", Vector3(0, 0.43, 0), Vector3(1.84, 0.86, 0.72), wood, true)
			_box("操作台面", Vector3(0, 0.9, 0), Vector3(1.92, 0.09, 0.78), metal, true)
			for x in [-0.52, -0.17]:
				_box("炉盘", Vector3(x, 0.953, -0.04), Vector3(0.25, 0.018, 0.25), inset)
			_box("水槽", Vector3(0.48, 0.953, -0.02), Vector3(0.55, 0.018, 0.38), glass)
			_box("水龙头", Vector3(0.48, 1.08, -0.26), Vector3(0.055, 0.28, 0.055), metal)
			for x in [-0.42, 0.42]:
				_box("橱门", Vector3(x, 0.48, 0.373), Vector3(0.75, 0.63, 0.024), trim)
		Piece.STORE_SHELF, Piece.BAKERY_SHELF:
			_box("货架背板", Vector3(0, 0.96, -0.3), Vector3(1.78, 1.92, 0.1), wood, true)
			for x in [-0.82, 0.82]:
				_box("货架支柱", Vector3(x, 0.96, 0), Vector3(0.09, 1.92, 0.68), metal, true)
			for y in [0.28, 0.78, 1.28, 1.78]:
				_box("货架层板", Vector3(0, y, 0), Vector3(1.7, 0.09, 0.66), wood, true)
			for x in [-0.52, 0.0, 0.52]:
				for y in [0.47, 0.97, 1.47]:
					if piece == Piece.BAKERY_SHELF:
						_box("面包", Vector3(x, y - 0.06, 0.05), Vector3(0.32, 0.16, 0.28), _material("bread"))
						_box("烤色", Vector3(x, y + 0.025, 0.05), Vector3(0.26, 0.025, 0.22), _material("crust"))
					else:
						_box("陈列盒", Vector3(x, y, 0.05), Vector3(0.26, 0.28, 0.27), accent)
		Piece.FREEZER:
			_box("冷柜主体", Vector3(0, 0.55, 0), Vector3(1.82, 1.1, 0.78), base, true)
			_box("冷柜玻璃盖", Vector3(0, 1.11, 0), Vector3(1.72, 0.045, 0.69), glass)
			_box("冷柜边框", Vector3(0, 1.14, -0.37), Vector3(1.86, 0.08, 0.06), metal)
			_box("冷柜灯带", Vector3(0, 0.8, 0.405), Vector3(1.4, 0.05, 0.025), accent)
		Piece.CRATE:
			_box("物资箱", Vector3(0, 0.38, 0), Vector3(0.92, 0.76, 0.8), wood, true)
			for y in [0.12, 0.64]:
				_box("木箱横箍", Vector3(0, y, 0.411), Vector3(0.98, 0.07, 0.035), trim)
			for x in [-0.32, 0.32]:
				_box("木箱立条", Vector3(x, 0.38, 0.411), Vector3(0.055, 0.74, 0.035), trim)
		Piece.SIDE_TABLE:
			_box("小桌面", Vector3(0, 0.55, 0), Vector3(0.72, 0.09, 0.72), wood, true)
			for x in [-0.28, 0.28]:
				for z in [-0.28, 0.28]:
					_box("小桌腿", Vector3(x, 0.26, z), Vector3(0.08, 0.52, 0.08), metal)
		Piece.LAMP_POST:
			_box("路灯柱", Vector3(0, 1.3, 0), Vector3(0.13, 2.6, 0.13), metal, true)
			_box("灯头支架", Vector3(0, 2.65, 0), Vector3(0.38, 0.12, 0.38), trim)
			_box("灯罩", Vector3(0, 2.82, 0), Vector3(0.5, 0.25, 0.5), _material("light"))
			_box("灯座", Vector3(0, 0.09, 0), Vector3(0.32, 0.18, 0.32), base)
			_add_lamp_light()
		Piece.RUG:
			_box("地毯底色", Vector3(0, 0.016, 0), Vector3(1.9, 0.025, 1.62), fabric)
			_box("地毯边", Vector3(0, 0.032, 0), Vector3(1.76, 0.008, 1.48), trim)
		Piece.DISPLAY_CASE:
			_box("展台", Vector3(0, 0.45, 0), Vector3(1.88, 0.9, 0.92), base, true)
			_box("台沿", Vector3(0, 0.9, 0), Vector3(1.92, 0.08, 0.96), trim)
			_box("玻璃罩", Vector3(0, 1.25, 0), Vector3(1.83, 0.62, 0.87), _material("clear_glass"))
			_box("展台灯带", Vector3(0, 0.68, 0.467), Vector3(1.63, 0.035, 0.02), accent)
			if display_model:
				_box("积木底板", Vector3(0, 0.97, 0), Vector3(1.4, 0.06, 0.63), _material("wood"))
				for x in [-0.34, 0.34]:
					_box("小屋墙身", Vector3(x, 1.12, 0), Vector3(0.49, 0.25, 0.48), _material("crust"))
					_box("屋顶底层", Vector3(x, 1.28, 0), Vector3(0.58, 0.09, 0.55), _material("bread"))
					_box("屋顶上层", Vector3(x, 1.35, 0), Vector3(0.36, 0.08, 0.51), _material("bread"))
				_box("橘黄窗", Vector3(0.34, 1.15, 0.25), Vector3(0.11, 0.13, 0.024), _material("amber"))
		Piece.TERMINAL:
			_box("底座", Vector3(0, 0.075, 0), Vector3(0.62, 0.15, 0.55), trim, true)
			_box("终端立座", Vector3(0, 0.63, 0), Vector3(0.34, 1.12, 0.32), base, true)
			_box("终端边框", Vector3(0, 1.22, 0), Vector3(0.61, 0.36, 0.27), metal)
			_box("屏幕", Vector3(0, 1.23, 0.144), Vector3(0.5, 0.25, 0.02), accent)
		Piece.AIRSHIP_WRECK:
			_box("残舱底板", Vector3(0, -0.04, 0), Vector3(3.95, 0.12, 4.8), metal, true)
			_box("机头", Vector3(0, 0.78, -2.2), Vector3(2.7, 1.52, 0.64), metal, true)
			_box("破损风挡", Vector3(-0.47, 1.39, -1.92), Vector3(1.49, 0.53, 0.05), glass)
			_box("左舱壁", Vector3(-1.73, 0.56, -0.37), Vector3(0.29, 1.12, 3.5), base, true)
			_box("右舱壁残段", Vector3(1.73, 0.45, -1.27), Vector3(0.29, 0.9, 1.6), base, true)
			for side in [-1.0, 1.0]:
				_box("发动机短舱", Vector3(side * 2.05, 0.45, -0.94), Vector3(0.72, 0.65, 1.64), inset, true)
				_box("短舱金属接缝", Vector3(side * 2.05, 0.78, -0.98), Vector3(0.58, 0.045, 0.5), trim)
			var beam := Vector3(0.16, 1.45, 1.32)
			_box("断开的舱架", Vector3(-1.47, 0.72, 1.11), beam, metal)
		Piece.TOWN_SIGN:
			for side in [-0.57, 0.57]:
				_box("牌柱", Vector3(side, 0.69, 0), Vector3(0.09, 1.38, 0.1), metal, true)
			_box("外框", Vector3(0, 1.43, 0), Vector3(1.58, 0.52, 0.12), trim, true)
			_box("牌面", Vector3(0, 1.43, 0.07), Vector3(1.43, 0.39, 0.025), accent)
		Piece.COAT_RACK:
			_box("衣帽架底座", Vector3(0, 0.04, 0), Vector3(0.48, 0.08, 0.48), metal)
			_box("衣帽架立杆", Vector3(0, 0.85, 0), Vector3(0.105, 1.7, 0.105), metal, true)
			for y in [1.28, 1.52]:
				_box("衣帽挂钩", Vector3(0, y, 0.03), Vector3(0.53, 0.075, 0.085), trim)


func _wall(name: String, offset_z: float, height: float,
		base: Material, trim: Material, inset: Material) -> void:
	_box(name, Vector3(0, height * 0.5, offset_z), Vector3(UNIT, height, 0.3), base, true)
	_box("压顶", Vector3(0, height + 0.035, offset_z),
		Vector3(UNIT, 0.08, 0.37), trim)
	_box("墙脚", Vector3(0, 0.14, offset_z - 0.17),
		Vector3(UNIT, 0.28, 0.035), trim)
	if height > 1.0:
		_box("分层线", Vector3(0, 1.05, offset_z - 0.158),
			Vector3(UNIT, 0.035, 0.016), inset)
	if district == District.ANT_HILL:
		if height > 1.0:
			for face in [-0.159, 0.159]:
				_box("褪色青绿墙裙", Vector3(0, 0.44, offset_z + face),
					Vector3(UNIT, 0.88, 0.018), _material("band"))
	else:
		for x in [-0.67, 0.67]:
			_box("板缝", Vector3(x, height * 0.5, offset_z + 0.158),
				Vector3(0.012, height - 0.12, 0.014), inset)
		_box("检修灯带", Vector3(0, minf(height - 0.16, 0.64), offset_z + 0.18),
			Vector3(1.55, 0.045, 0.025), _material("accent"))


func _box(name: String, at: Vector3, size: Vector3,
		material: Material, solid: bool = false) -> void:
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = name
	mesh_node.set_meta("generated_piece", true)
	var box := BoxMesh.new()
	box.size = size
	mesh_node.mesh = box
	mesh_node.material_override = material
	mesh_node.position = at
	add_child(mesh_node)
	if solid:
		_box_collision(name, at, size)


func _box_collision(name: String, at: Vector3, size: Vector3) -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = name + "碰撞"
	shape_node.set_meta("generated_piece", true)
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	shape_node.position = at
	add_child(shape_node)


func _add_lamp_light() -> void:
	var light := OmniLight3D.new()
	light.name = "暖色路灯光"
	light.set_meta("generated_piece", true)
	light.position = Vector3(0, 2.67, 0)
	light.light_color = Color("#ffbd70") if district == District.ANT_HILL else Color("#b5e7ff")
	light.light_energy = 1.05 if district == District.ANT_HILL else 0.68
	light.omni_range = 4.8
	light.shadow_enabled = false
	add_child(light)


func _ramp_surface(material: Material) -> void:
	# A single convex walkable wedge joins the two 2 m floor modules.
	var vertices := PackedVector3Array([
		Vector3(-1, 0, 1.2), Vector3(1, 0, 1.2),
		Vector3(1, 0.6, -1.2), Vector3(-1, 0.6, -1.2),
		Vector3(-1, -0.15, 1.2), Vector3(1, -0.15, 1.2),
		Vector3(1, 0.45, -1.2), Vector3(-1, 0.45, -1.2),
	])
	var shape_node := CollisionShape3D.new()
	shape_node.name = "坡面碰撞"
	shape_node.set_meta("generated_piece", true)
	var shape := ConvexPolygonShape3D.new()
	shape.points = vertices
	shape_node.shape = shape
	add_child(shape_node)
	_mesh_from_quads("坡面", vertices, [[0, 1, 2, 3], [3, 2, 6, 7]], material)


func _roof_slope(start_z: float, end_z: float, material: Material) -> void:
	var edge_y := 2.82
	var ridge_y := 3.18
	var points := PackedVector3Array([
		Vector3(-1.04, edge_y if start_z < 0 else ridge_y, start_z),
		Vector3(1.04, edge_y if start_z < 0 else ridge_y, start_z),
		Vector3(1.04, ridge_y if start_z < 0 else edge_y, end_z),
		Vector3(-1.04, ridge_y if start_z < 0 else edge_y, end_z),
	])
	for point in points.slice(0, 4):
		points.append(point - Vector3(0, 0.12, 0))
	_mesh_from_quads("实体斜屋面", points,
		[[0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1], [1, 5, 6, 2],
		[2, 6, 7, 3], [3, 7, 4, 0]], material)
	var shape_node := CollisionShape3D.new()
	shape_node.name = "斜屋面碰撞"
	shape_node.set_meta("generated_piece", true)
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	shape_node.shape = shape
	add_child(shape_node)


func _gable_roof(width: float, depth: float, roof_material: Material,
		seam_material: Material) -> void:
	# One stretched roof covers the exact outer-wall footprint of a closed house.
	var edge_y := 2.9
	var ridge_y := 3.62
	for side in [-1.0, 1.0]:
		var near_z := -depth * 0.5 if side < 0 else 0.0
		var far_z := 0.0 if side < 0 else depth * 0.5
		var near_y := edge_y if side < 0 else ridge_y
		var far_y := ridge_y if side < 0 else edge_y
		var points := PackedVector3Array([
			Vector3(-width * 0.5, near_y, near_z),
			Vector3(width * 0.5, near_y, near_z),
			Vector3(width * 0.5, far_y, far_z),
			Vector3(-width * 0.5, far_y, far_z),
		])
		for point in points.slice(0, 4):
			points.append(point - Vector3(0, 0.15, 0))
		_mesh_from_quads("整栋坡屋面", points,
			[[0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1],
			[1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]], roof_material)
		var shape_node := CollisionShape3D.new()
		shape_node.name = "坡屋面碰撞"
		shape_node.set_meta("generated_piece", true)
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		shape_node.shape = shape
		add_child(shape_node)
	for side in [-1.0, 1.0]:
		var x: float = side * (width * 0.5 - 0.08)
		var gable := PackedVector3Array([
			Vector3(x, 2.8, -depth * 0.5),
			Vector3(x, 2.8, depth * 0.5),
			Vector3(x, ridge_y - 0.08, 0),
			Vector3(x, ridge_y - 0.08, 0),
		])
		_mesh_from_quads("山墙三角", gable, [[0, 1, 2, 3]], roof_material)
	_box("通长屋脊", Vector3(0, ridge_y + 0.03, 0),
		Vector3(width, 0.08, 0.16), seam_material)
	for side in [-1.0, 1.0]:
		_box("通长檐口", Vector3(0, edge_y - 0.04, side * depth * 0.5),
			Vector3(width, 0.16, 0.12), seam_material)


func _mesh_from_quads(name: String, vertices: PackedVector3Array,
		quads: Array, material: Material) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for quad in quads:
		for index in [0, 1, 2, 0, 2, 3]:
			surface.set_uv(Vector2(vertices[quad[index]].x, vertices[quad[index]].z))
			surface.add_vertex(vertices[quad[index]])
	surface.generate_normals()
	var node := MeshInstance3D.new()
	node.name = name
	node.set_meta("generated_piece", true)
	node.mesh = surface.commit()
	node.material_override = material
	add_child(node)


func _material(role: String) -> StandardMaterial3D:
	var ant := district == District.ANT_HILL
	var variant := _floor_variant() if piece == Piece.FLOOR else 0
	var cache_key := "%d:%d:%s:%d:%d:%d" % [
		district, piece, role, roof_tiles.x, roof_tiles.y, variant]
	if _material_cache.has(cache_key):
		return _material_cache[cache_key] as StandardMaterial3D
	var palette := {
		"base": Color("#9c7861") if ant else Color("#d9e4f1"),
		"trim": Color("#bd9b79") if ant else Color("#839dbb"),
		"inset": Color("#6b5448") if ant else Color("#506e91"),
		"accent": Color("#72905a") if ant else Color("#43c8f5"),
		"soil": Color("#665246") if ant else Color("#93a6b9"),
		"wood": Color("#786050") if ant else Color("#aabcca"),
		"fabric": Color("#6b7885") if ant else Color("#80a6c5"),
		"metal": Color("#45545b") if ant else Color("#466681"),
		"glass": Color("#435b61") if ant else Color("#5da8cb"),
		"clear_glass": Color("#b3eaff45"),
		"bread": Color("#ac693e"),
		"crust": Color("#e7b172"),
		"amber": Color("#ffa94a"),
		"band": Color("#4f706c") if ant else Color("#8fadc0"),
		"light": Color("#ffd88d") if ant else Color("#b5e7ff"),
	}
	var material := StandardMaterial3D.new()
	material.albedo_color = palette[role]
	material.roughness = 0.85 if ant else 0.56
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if ant:
		var texture_name := _texture_name(role, variant)
		var texture := load("res://modules/textures/anthill/%s.png" % texture_name) as Texture2D
		if texture != null:
			material.albedo_texture = texture
			material.albedo_color = Color.WHITE
	elif role == "base" and piece == Piece.FLOOR:
		material.albedo_color = [Color("#93a7bc"), Color("#9aacbf"),
			Color("#90a5b9"), Color("#9db0c4")][variant]
		material.albedo_texture = _city_texture("paving")
	elif role == "base" and piece in [Piece.HIGH_WALL, Piece.WINDOW_WALL, Piece.SEALED_DOOR]:
		material.albedo_texture = _city_texture("panel")
	elif role == "glass":
		material.albedo_texture = _city_texture("window")
	elif role == "accent":
		material.emission_enabled = true
		material.emission = Color("#1594d2")
		material.emission_energy_multiplier = 0.58
	if piece == Piece.ROOF_FLAT and role == "base":
		material.uv1_scale = Vector3(float(roof_tiles.x), 1.0, float(roof_tiles.y))
	if role == "metal":
		material.metallic = 0.32
		material.roughness = 0.68
	elif role == "glass":
		material.roughness = 0.25
	elif role == "clear_glass":
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness = 0.28
	elif role == "light":
		material.emission_enabled = true
		material.emission = Color("#ffd58c") if ant else Color("#8bdfff")
		material.emission_energy_multiplier = 0.65
	_material_cache[cache_key] = material
	return material


func _city_texture(surface: String) -> Texture2D:
	if _city_textures.has(surface):
		return _city_textures[surface] as Texture2D
	var image := Image.create_empty(32, 32, false, Image.FORMAT_RGB8)
	image.fill(Color("#f8f8f8"))
	match surface:
		"paving":
			image.fill_rect(Rect2i(0, 0, 32, 1), Color("#e0e0e0"))
			image.fill_rect(Rect2i(0, 0, 1, 32), Color("#e0e0e0"))
			for corner in [Vector2i(4, 4), Vector2i(24, 24)]:
				image.fill_rect(Rect2i(corner, Vector2i(3, 1)), Color("#c9c9c9"))
				image.fill_rect(Rect2i(corner + Vector2i(0, 1), Vector2i(3, 1)), Color.WHITE)
		"panel":
			image.fill_rect(Rect2i(0, 15, 32, 1), Color("#d0d0d0"))
			image.fill_rect(Rect2i(0, 16, 32, 1), Color.WHITE)
			image.fill_rect(Rect2i(4, 10, 3, 2), Color("#dfdfdf"))
		"window":
			image.fill(Color("#d0dbe5"))
			for x in range(32):
				var y := 31 - x
				image.fill_rect(Rect2i(x, y, 1, mini(4, 32 - y)), Color("#e9f1f8"))
	var texture := ImageTexture.create_from_image(image)
	_city_textures[surface] = texture
	return texture


func _floor_variant() -> int:
	var column := floori((roundi(position.x) + 25) / 2.0)
	var row := floori((roundi(position.z) + 17) / 2.0)
	return posmod(column * 13 + row * 17 + column * row * 7, 4)


func _texture_name(role: String, variant: int) -> String:
	match role:
		"base":
			match piece:
				Piece.FLOOR:
					return "paving_%d" % variant
				Piece.LOW_WALL, Piece.CORNER, Piece.PLANTER:
					return "brick"
				Piece.RAMP, Piece.STAIRS, Piece.STAIR_FLIGHT:
					return "stairs"
				Piece.ROOF_FLAT:
					return "roof_concrete"
				Piece.ROOF, Piece.ROOF_GABLE:
					return "slate"
				Piece.COLUMN, Piece.LAMP_POST:
					return "stone"
				Piece.RAILING, Piece.FREEZER:
					return "metal"
				Piece.HIGH_WALL, Piece.DOORWAY, Piece.WINDOW_WALL, Piece.SEALED_DOOR:
					return "plaster"
				_:
					return "wood"
		"trim":
			if piece in [Piece.ROOF, Piece.ROOF_GABLE]:
				return "slate"
			if piece in [Piece.WINDOW_WALL, Piece.SEALED_DOOR,
					Piece.RAILING, Piece.LAMP_POST]:
				return "metal"
			return "stone"
		"inset":
			return "grout"
		"accent":
			if piece == Piece.STORE_SHELF:
				return "goods"
			if piece in [Piece.ROOF, Piece.ROOF_GABLE]:
				return "slate"
			return "foliage"
		"soil":
			return "soil"
		"wood":
			return "wood"
		"fabric":
			return "fabric"
		"metal":
			return "metal"
		"glass":
			return "glass"
		"band":
			return "paint_band"
		"light":
			return "lamp"
	return "plaster"
