extends RefCounted
class_name SensingGeometryTests

var passed: int = 0
var failed: int = 0

func run() -> Dictionary:
	for scenario: Callable in [_circle_and_sector, _sector_boundary, _supercover, _fixed_occlusion, _scaled_radius_and_wall_mount, _point_tangent_and_repeat]:
		_check(scenario.call() == true, "scenario completed: " + scenario.get_method())
	return {"passed": passed, "failed": failed}

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("SENSING GEOMETRY FAILED: " + label)

func _world() -> WorldState:
	var world := WorldState.new()
	world.grid_size = Vector2i(7, 7)
	world.cell_size = 1.0
	world.origin = Vector2.ZERO
	for y: int in 7:
		var row: Array = []
		for x: int in 7:
			row.append("FLOOR")
		world.terrain.append(row)
	return world

func _circle_and_sector() -> bool:
	var world: WorldState = _world()
	var robot: Dictionary = {"kind": "robot", "runtime_state": {"position": [3.5, 3.5]}, "parameters": {"view_radius": 2.0}}
	var result: Dictionary = VisionGeometry.reliable_cells(world, robot)
	_check(result.ok and Vector2i(3, 3) in result.cells, "circle contains origin cell")
	_check(Vector2i(5, 3) in result.cells, "circle positive overlap beyond target center")
	robot.parameters.view_radius = 2.1
	_check(not VisionGeometry.reliable_cells(world, robot).ok, "noninteger radius rejected")
	var camera: Dictionary = {"kind": "camera", "cell": [3, 3], "runtime_state": {"heading": 0.0}, "parameters": {"view_radius": 2.0, "fov_angle": PI / 2.0}}
	result = VisionGeometry.reliable_cells(world, camera)
	_check(result.ok and Vector2i(5, 3) in result.cells and Vector2i(1, 3) not in result.cells, "sector faces east")
	return true

func _supercover() -> bool:
	var world: WorldState = _world()
	world.terrain[1][2] = "WALL"
	_check(not VisionGeometry.is_cell_reliable(world, Vector2(1.5, 1.5), Vector2i(3, 3)), "corner contact wall blocks")
	world.terrain[1][2] = "FLOOR"
	_check(VisionGeometry.is_cell_reliable(world, Vector2(1.5, 1.5), Vector2i(3, 3)), "open corner passes")
	world.terrain[2][2] = "WALL"
	_check(not VisionGeometry.is_cell_reliable(world, Vector2(1.5, 1.5), Vector2i(3, 3)), "middle wall blocks")
	return true

func _sector_boundary() -> bool:
	var world: WorldState = _world()
	var robot: Dictionary = {"kind": "robot", "runtime_state": {"position": [3.0, 3.5]}, "parameters": {"view_radius": 2.0}}
	var circle: Dictionary = VisionGeometry.reliable_cells(world, robot)
	_check(Vector2i(5, 3) not in circle.cells and Vector2i(4, 3) in circle.cells, "circle tangent edge excluded")
	var camera: Dictionary = {"kind": "camera", "cell": [3, 3], "runtime_state": {"heading": 0.0}, "parameters": {"view_radius": 3.0, "fov_angle": PI / 2.0}}
	var sector: Dictionary = VisionGeometry.reliable_cells(world, camera)
	_check(Vector2i(3, 2) not in sector.cells, "sector ray corner contact excluded")
	camera.parameters.fov_angle = TAU
	var full: Dictionary = VisionGeometry.reliable_cells(world, camera)
	_check(Vector2i(1, 3) in full.cells, "TAU includes rear cell")
	camera.parameters.fov_angle = PI * 1.5
	var wide: Dictionary = VisionGeometry.reliable_cells(world, camera)
	_check(Vector2i(1, 3) not in wide.cells and Vector2i(3, 1) in wide.cells, "wide sector split is correct")
	return true

func _fixed_occlusion() -> bool:
	var world: WorldState = _world()
	world.registry._put({"id": 9, "kind": "goal", "cell": [3, 2], "parameters": {}, "runtime_state": {"active": false, "progress": 0.0, "complete": false}})
	_check(not VisionGeometry.is_cell_reliable(world, Vector2(3.5, 1.5), Vector2i(3, 3)), "fixed facility blocks")
	_check(not VisionGeometry.is_cell_reliable(world, Vector2(3.5, 1.5), Vector2i(3, 2)), "solid target excluded")
	return true

func _scaled_radius_and_wall_mount() -> bool:
	var world: WorldState = _world()
	world.cell_size = 64.0
	var camera: Dictionary = {"kind": "camera", "cell": [3, 3], "runtime_state": {"heading": -PI / 2.0}, "parameters": {"view_radius": 320.0, "fov_angle": PI / 2.0}}
	var accepted: Dictionary = VisionGeometry.reliable_cells(world, camera)
	_check(accepted.ok and Vector2i(3, 2) in accepted.cells, "64/320 five-cell radius accepted")
	camera.parameters.view_radius = 300.0
	_check(not VisionGeometry.reliable_cells(world, camera).ok, "64/300 noninteger radius rejected")
	camera.parameters.view_radius = 384.0
	_check(VisionGeometry.reliable_cells(world, camera).ok, "64/384 six-cell radius accepted")
	world.terrain[2][3] = "WALL"
	var occluded: Dictionary = VisionGeometry.reliable_cells(world, camera)
	_check(occluded.ok and Vector2i(3, 1) not in occluded.cells, "support wall blocks behind")
	return true

func _point_tangent_and_repeat() -> bool:
	var world := WorldState.new()
	world.grid_size = Vector2i(10, 10)
	world.cell_size = 1.0
	world.origin = Vector2.ZERO
	for y: int in 10:
		var row: Array = []
		for x: int in 10:
			row.append("FLOOR")
		world.terrain.append(row)
	var robot: Dictionary = {"kind": "robot", "runtime_state": {"position": [3.0, 3.0]}, "parameters": {"view_radius": 5.0}}
	var first: Dictionary = VisionGeometry.reliable_cells(world, robot)
	var second: Dictionary = VisionGeometry.reliable_cells(world, robot)
	_check(first.ok and first.cells == second.cells, "repeated geometry is deterministic")
	_check(Vector2i(6, 7) not in first.cells, "point tangent at 3-4-5 corner excluded")
	_check(Vector2i(5, 6) in first.cells, "neighbor with positive overlap accepted")
	return true
