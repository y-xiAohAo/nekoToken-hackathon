extends RefCounted
class_name Module6SceneTests
## Prepared scene restoration must leave the active scene intact until activation.

var passed: int = 0
var failed: int = 0


func run() -> Dictionary:
	_check(await _player_pose_commit(), "prepared restore applies player position and velocity only on activation")
	_check(await _prepare_failure(), "failed prepare keeps old player and scene nodes")
	_check(await _robot_node_restore(), "prepared restore reinstantiates robot from candidate runtime state")
	return {"passed": passed, "failed": failed}


func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("MODULE 6 SCENE TEST FAILED: " + label)


func _fixture() -> Dictionary:
	var world: WorldState = LevelTemplate.from_data(PrototypeConfig.level_data()).instantiate_world()
	var view := RuntimeWorldView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	if world == null or not view.build_from_world(world):
		view.queue_free()
		return {}
	return {"world": world, "view": view, "adapter": SceneWorldSyncAdapter.new(view)}


func _cleanup(view: RuntimeWorldView) -> void:
	view.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame


func _player_pose_commit() -> bool:
	var f: Dictionary = _fixture()
	if f.is_empty():
		return false
	var player: PlayerController = f.view.get_player()
	var start: Vector2 = f.world.player_position
	player.global_position = start + Vector2(4, 0)
	player.velocity = Vector2(30, -20)
	player._touched_entity_ids.assign([41])
	var before: Vector2 = player.global_position
	var prepared: Dictionary = f.adapter.prepare(f.world.to_snapshot(), f.world.to_snapshot(),
		{"terrain_changed": false, "changed_ids": [], "removed_ids": [], "changed_obstacle_ids": [], "removed_obstacle_ids": [], "restore_player": true})
	var staged: bool = prepared.get("ok") == true and player.global_position == before and player.velocity == Vector2(30, -20)
	var activated: bool = f.adapter.activate(prepared.prepared) if staged else false
	var result: bool = staged and activated and player.global_position.is_equal_approx(start) \
		and player.velocity.is_equal_approx(f.world.player_velocity) and player.touched_entity_ids().is_empty()
	await _cleanup(f.view)
	return result


func _prepare_failure() -> bool:
	var f: Dictionary = _fixture()
	if f.is_empty():
		return false
	var player: PlayerController = f.view.get_player()
	player.global_position += Vector2(3, 0)
	player.velocity = Vector2(8, 9)
	var old_position: Vector2 = player.global_position
	var old_camera: Node2D = f.view.get_entity_node(1)
	var old_terrain: TileMapLayer = f.view._terrain
	var rejected: Dictionary = f.adapter.prepare(f.world.to_snapshot(), f.world.to_snapshot(),
		{"terrain_changed": true, "changed_ids": [1, 999999], "removed_ids": [],
		"changed_obstacle_ids": [], "removed_obstacle_ids": []})
	var result: bool = rejected.get("ok") == false and player.global_position == old_position \
		and player.velocity == Vector2(8, 9) and f.view.get_entity_node(1) == old_camera \
		and f.view._terrain == old_terrain
	await _cleanup(f.view)
	return result


func _robot_node_restore() -> bool:
	var f: Dictionary = _fixture()
	if f.is_empty():
		return false
	var robot_id: int = 0
	for entity: Dictionary in f.world.registry.to_snapshot():
		if entity.kind == "robot":
			robot_id = entity.id
			break
	if robot_id == 0:
		await _cleanup(f.view)
		return false
	var original: Node2D = f.view.get_entity_node(robot_id)
	original.position += Vector2(10, 0)
	var expected: Vector2 = DeviceRegistry.vector(f.world.registry.get_entity(robot_id).runtime_state.position)
	var prepared: Dictionary = f.adapter.prepare(f.world.to_snapshot(), f.world.to_snapshot(),
		{"terrain_changed": false, "changed_ids": [robot_id], "removed_ids": [],
		"changed_obstacle_ids": [], "removed_obstacle_ids": []})
	var staged: bool = prepared.get("ok") == true and f.view.get_entity_node(robot_id) == original
	var activated: bool = f.adapter.activate(prepared.prepared) if staged else false
	var restored: Node2D = f.view.get_entity_node(robot_id)
	var result: bool = staged and activated and restored != original and restored.position.is_equal_approx(expected)
	await _cleanup(f.view)
	return result
