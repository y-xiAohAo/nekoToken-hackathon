extends WorldSyncAdapter
class_name SceneWorldSyncAdapter


var _view: RuntimeWorldView


func _init(view: RuntimeWorldView) -> void:
	_view = view


func prepare(_previous: Dictionary, candidate: Dictionary, changes: Dictionary) -> Dictionary:
	if _view == null:
		return {"ok": false, "errors": [{"code": "MISSING_VIEW"}]}
	var candidate_world: WorldState = WorldState.from_snapshot(candidate)
	if candidate_world == null:
		return {"ok": false, "errors": [{"code": "INVALID_WORLD"}]}
	var prepared: Dictionary = {"terrain": null, "changed": {}, "removed": changes.get("removed_ids", []).duplicate(),
		"obstacles": {}, "removed_obstacles": changes.get("removed_obstacle_ids", []).duplicate(), "world": candidate_world,
		"restore_player": changes.get("restore_player", false),
		"player_position": candidate_world.player_position, "player_velocity": candidate_world.player_velocity}
	if changes.get("terrain_changed", false):
		prepared.terrain = _view.make_terrain_layer(candidate)
		if prepared.terrain == null:
			_discard(prepared)
			return {"ok": false, "errors": [{"code": "INVALID_TERRAIN"}]}
	var entities: Dictionary = {}
	for entity: Dictionary in candidate.get("entities", []):
		entities[entity.id] = entity
	for id: int in changes.get("changed_ids", []):
		if not entities.has(id):
			_discard(prepared)
			return {"ok": false, "errors": [{"code": "UNKNOWN_ID", "id": id}]}
		var node: Node2D = _view.make_entity_node(entities[id], candidate_world)
		if node == null:
			_discard(prepared)
			return {"ok": false, "errors": [{"code": "INVALID_ENTITY", "id": id}]}
		prepared.changed[id] = node
	var obstacles: Dictionary = {}
	for instance: Dictionary in candidate_world.obstacle_instances:
		obstacles[instance.obstacle_id] = instance
	for id: int in changes.get("changed_obstacle_ids", []):
		if not obstacles.has(id):
			_discard(prepared)
			return {"ok": false, "errors": [{"code": "UNKNOWN_OBSTACLE"}]}
		var obstacle: Node2D = _view.make_obstacle_node(obstacles[id], candidate_world)
		if obstacle == null:
			_discard(prepared)
			return {"ok": false, "errors": [{"code": "INVALID_OBSTACLE"}]}
		prepared.obstacles[id] = obstacle
	return {"ok": true, "prepared": prepared, "errors": []}


func _discard(prepared: Dictionary) -> void:
	# Staged nodes have no parent and must be released on every rejected prepare.
	if prepared.get("terrain") != null:
		prepared.terrain.free()
	for node: Node in prepared.get("changed", {}).values():
		node.free()
	for node: Node in prepared.get("obstacles", {}).values():
		node.free()


func activate(prepared: Dictionary) -> bool:
	if prepared.get("terrain") != null:
		_view.replace_terrain(prepared.terrain)
	for id: int in prepared.get("removed", []):
		_view.remove_entity(id)
	for id: int in prepared.get("changed", {}):
		_view.replace_entity(id, prepared.changed[id])
	for id: int in prepared.get("removed_obstacles", []):
		_view.remove_obstacle(id)
	for id: int in prepared.get("obstacles", {}):
		_view.replace_obstacle(id, prepared.obstacles[id])
	if prepared.get("restore_player", false):
		_view.get_player().restore_motion_state(prepared.player_position, prepared.player_velocity)
	_view.accept_committed_world(prepared.world)
	return true
