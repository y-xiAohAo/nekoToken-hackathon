extends RefCounted
class_name WorldCommandService
## Sole active-world writer. Callers supply trusted session context and policy.

var _world: WorldState
var _policy: Dictionary = {}
var _sync: WorldSyncAdapter
var _busy: bool = false
var _activation_failed: bool = false
var _request_key: Array = []
var _cached_batch: Dictionary = {}
var _cached_result: WorldCommandResult


func _init(initial_world: WorldState, policy: Dictionary, sync_adapter: WorldSyncAdapter) -> void:
	_world = initial_world.snapshot_copy() if initial_world != null else null
	_policy = policy.duplicate(true) if DeviceRegistry.plain(policy) else {}
	_sync = sync_adapter


func get_world_snapshot() -> WorldState:
	return _world.snapshot_copy() if _world != null else null


func commit_runtime_step(
	expected_tick: int,
	step: WorldStepResult,
	session_snapshot: Dictionary,
	cycle_snapshot: Dictionary
) -> Dictionary:
	if _activation_failed:
		return _runtime_error("SYNC_ACTIVATION_FAILED")
	if _busy or _world == null or step == null:
		return _runtime_error("INVALID_COMMAND")
	if session_snapshot.get("phase") != SessionPhase.Phase.ACTION:
		return _runtime_error("INVALID_PHASE")
	if expected_tick <= 0 or cycle_snapshot.get("simulation_tick") != expected_tick - 1:
		return _runtime_error("INVALID_TICK")
	if step.world_frame == null or step.world_frame.simulation_tick != expected_tick:
		return _runtime_error("INVALID_TICK")
	if step.candidate_world == null:
		return _runtime_error("INVALID_WORLD")
	var candidate: WorldState = step.candidate_world.snapshot_copy()
	if candidate == null:
		return _runtime_error("INVALID_WORLD")
	var validation_errors: Array[Dictionary] = candidate.validate()
	if not validation_errors.is_empty():
		return {"ok": false, "errors": validation_errors}
	if candidate.world_revision != _world.world_revision:
		return _runtime_error("STALE_WORLD")
	if not step.world_frame.player_world_position.is_equal_approx(candidate.player_position):
		return _runtime_error("INVALID_FRAME")
	if not _runtime_structure_unchanged(_world, candidate):
		return _runtime_error("INVALID_WORLD")
	_busy = true
	_world = candidate
	_busy = false
	return {"ok": true, "tick": expected_tick}


func _runtime_error(code: String) -> Dictionary:
	return {"ok": false, "errors": [{"code": code}]}


func _runtime_structure_unchanged(current: WorldState, candidate: WorldState) -> bool:
	var before: Dictionary = current.to_snapshot()
	var after: Dictionary = candidate.to_snapshot()
	for field: String in ["template_key", "grid_size", "cell_size", "origin", "terrain", "obstacle_templates", "obstacle_instances", "next_obstacle_id", "device_rules", "next_entity_id"]:
		if before[field] != after[field]:
			return false
	if before.entities.size() != after.entities.size():
		return false
	for index: int in before.entities.size():
		var old_entity: Dictionary = before.entities[index].duplicate(true)
		var new_entity: Dictionary = after.entities[index].duplicate(true)
		if old_entity.get("id") != new_entity.get("id"):
			return false
		old_entity.erase("runtime_state")
		new_entity.erase("runtime_state")
		if old_entity != new_entity:
			return false
	return true


func validate_batch(batch: WorldCommandBatch, expected_context: Dictionary) -> WorldCommandResult:
	var result: WorldCommandResult = _check_context(batch, expected_context)
	if not result.errors.is_empty():
		return result
	var candidate: WorldState = _build_candidate(batch.to_data(), result, false)
	if candidate != null:
		result.status = "VALID"
		# Candidate allocation is private: callers cannot rely on preview IDs.
		result.created_ids.clear()
	return result


func commit_batch(batch: WorldCommandBatch, expected_context: Dictionary) -> WorldCommandResult:
	var result: WorldCommandResult = _check_context(batch, expected_context)
	if not result.errors.is_empty():
		return result
	var data: Dictionary = batch.to_data()
	var key: Array = []
	for field: String in AgentProtocol.CONTEXT_FIELDS:
		key.append(data.context[field])
	# Check retries before base revision: a successful request advanced the world.
	if key == _request_key and _cached_result != null:
		if data == _cached_batch:
			return _cached_result.snapshot_copy()
		return _reject(result, "REQUEST_REUSE")
	var candidate: WorldState = _build_candidate(data, result, true)
	if candidate == null:
		_remember(key, data, result)
		return result
	var before: Dictionary = _world.to_snapshot()
	var after: Dictionary = candidate.to_snapshot()
	if before == after:
		result.status = "UNCHANGED"
		_remember(key, data, result)
		return result
	if _sync == null:
		_reject(result, "SYNC_PREPARE_FAILED")
		_remember(key, data, result)
		return result
	candidate.world_revision += 1
	after = candidate.to_snapshot()
	_busy = true
	var prepared: Dictionary = _sync.prepare(before.duplicate(true), after.duplicate(true), _changes(before, after))
	if prepared.get("ok") != true or not prepared.get("prepared") is Dictionary:
		_busy = false
		_reject(result, "SYNC_PREPARE_FAILED")
		_remember(key, data, result)
		return result
	# activate must only publish prepared resources; no I/O or fallible validation.
	var activated: Variant = _sync.activate(prepared.prepared)
	if activated != true:
		# A programming fault may have partially changed external derived state.
		# Keep simulation gated; do not retry or claim scene rollback.
		_activation_failed = true
		_busy = false
		return _reject(result, "SYNC_ACTIVATION_FAILED")
	_world = candidate
	_busy = false
	result.status = "APPLIED"
	for command_result: Dictionary in result.command_results:
		command_result["status"] = "APPLIED"
	result.revision_after = _world.world_revision
	_remember(key, data, result)
	return result


func _check_context(batch: WorldCommandBatch, expected: Dictionary) -> WorldCommandResult:
	var result := WorldCommandResult.new()
	if _world != null:
		result.revision_before = _world.world_revision
		result.revision_after = _world.world_revision
	if _activation_failed:
		return _reject(result, "SYNC_ACTIVATION_FAILED")
	if _busy or _world == null or batch == null:
		return _reject(result, "INVALID_COMMAND")
	var data: Dictionary = batch.to_data()
	if WorldCommandBatch.from_data(data) == null:
		return _reject(result, "INVALID_COMMAND")
	result.context = data.context.duplicate(true)
	if data.context.branch_id != expected.get("branch_id"):
		return _reject(result, "STALE_BRANCH")
	if not AgentProtocol.contexts_match(data.context, expected):
		return _reject(result, "INVALID_CONTEXT")
	var phase: Variant = expected.get("phase")
	var contact: bool = phase == SessionPhase.Phase.CONTACT_PAUSED
	var dispatch: bool = phase == SessionPhase.Phase.DISPATCH_PAUSED
	if not contact and not dispatch:
		return _reject(result, "INVALID_PHASE")
	if data.source != ("contact" if contact else "dispatch") or data.context.role != (AgentProtocol.PLAYER_ASSISTANT if contact else AgentProtocol.SYSTEM_AGENT):
		return _reject(result, "INVALID_CONTEXT")
	return result


func _build_candidate(data: Dictionary, result: WorldCommandResult, authoritative: bool) -> WorldState:
	if data.base_world_revision != _world.world_revision:
		_reject(result, "STALE_WORLD")
		return null
	var candidate: WorldState = _world.snapshot_copy()
	if data.mode == "KEEP_CURRENT":
		return candidate
	var role_policy: Variant = _policy.get(data.context.role, {})
	if not role_policy is Dictionary:
		_reject(result, "PERMISSION_DENIED")
		return null
	if role_policy.has("max_commands") and (typeof(role_policy.max_commands) != TYPE_INT or data.commands.size() > role_policy.max_commands):
		_reject(result, "PERMISSION_DENIED")
		return null
	for index: int in data.commands.size():
		if authoritative and _hidden_placement_blocked(candidate, data.commands[index], role_policy):
			_reject(result, "PLACEMENT_REJECTED", index)
			return null
		var code: String = _apply(candidate, data.commands[index], role_policy, result, index)
		if not code.is_empty():
			_reject(result, code, index)
			return null
		result.command_results.append({"command_index": index, "status": "VALID"})
	if not _limits_valid(candidate, role_policy):
		_reject(result, "DEVICE_LIMIT")
		return null
	if _new_robot_overlap(candidate, result.created_ids, authoritative):
		_reject(result, "PLACEMENT_REJECTED")
		return null
	# Intermediate moves are private; only the final placement changes the baseline.
	for entity: Dictionary in candidate.registry.to_snapshot():
		if entity.kind != "pressure_plate":
			continue
		var previous: Dictionary = _world.registry.get_entity(entity.id)
		if previous.is_empty() or previous.cell != entity.cell:
			entity["runtime_state"] = {"occupants": [], "baseline_ready": false}
			candidate.registry._put(entity)
	# Reconcile only affected camera headings, not every device's running phase.
	for command: Dictionary in data.commands:
		if command.type != "SetDeviceParameter" or command.parameter not in ["scan_center", "scan_half_angle"]:
			continue
		var entity: Dictionary = candidate.registry.get_entity(command.id)
		if entity.get("kind") == "camera" and DeviceRegistry.configuration_valid(entity, candidate.device_rules):
			var offset: float = wrapf(entity.runtime_state.heading - entity.parameters.scan_center, -PI, PI)
			if absf(offset) > entity.parameters.scan_half_angle + 0.000001:
				entity["runtime_state"]["heading"] = entity.parameters.scan_center + clampf(offset, -entity.parameters.scan_half_angle, entity.parameters.scan_half_angle)
				candidate.registry._put(entity)
	var errors: Array[Dictionary] = candidate.validate(not authoritative)
	if not errors.is_empty():
		var code: String = errors[0].code
		if role_policy.has("obstacle_protection_radius") and code in ["OCCUPANCY_CONFLICT", "INVALID_POSITION"] and _has_placement_command(data.commands):
			code = "PLACEMENT_REJECTED"
		_reject(result, code)
		return null
	return candidate


func _apply(world: WorldState, command: Dictionary, policy: Dictionary, result: WorldCommandResult, index: int) -> String:
	var permissions: Variant = policy.get("commands", {})
	if not permissions is Dictionary or not permissions.get(command.type) is Array:
		return "PERMISSION_DENIED"
	var allowed: Array = permissions[command.type]
	if command.type == "MoveObstacle":
		if "obstacle" not in allowed:
			return "PERMISSION_DENIED"
		for instance: Dictionary in world.obstacle_instances:
			if instance.obstacle_id != command.obstacle_id:
				continue
			var template: ObstacleTemplate = world.obstacle_template(instance.template_id)
			if template == null:
				return "INVALID_WORLD"
			for cell: Vector2i in template.covered_cells(DeviceRegistry.grid(command.anchor_cell)):
				if not _region_allowed([cell.x, cell.y], policy):
					return "PERMISSION_DENIED"
			instance["anchor_cell"] = command.anchor_cell.duplicate()
			return ""
		return "UNKNOWN_ID"
	if command.type == "SetCameraScanState":
		if "camera" not in allowed:
			return "PERMISSION_DENIED"
		var camera: Dictionary = world.registry.get_entity(command.id)
		if camera.get("kind") != "camera":
			return "UNKNOWN_ID"
		camera.runtime_state.heading = command.heading
		camera.runtime_state.scan_direction = command.scan_direction
		world.registry._put(camera)
		return ""
	if command.type == "SetMapCell":
		if "map" not in allowed or not _region_allowed(command.cell, policy):
			return "PERMISSION_DENIED"
		var cell: Vector2i = DeviceRegistry.grid(command.cell)
		if not world.in_bounds(cell):
			return "INVALID_POSITION"
		world.terrain[cell.y][cell.x] = command.cell_kind
		return ""
	if command.type == "AddDevice":
		var definition: Dictionary = command.device
		if definition.get("kind") not in ["camera", "robot", "pressure_plate"] or definition.get("kind") not in allowed:
			return "PERMISSION_DENIED"
		if not DeviceRegistry.definition_valid(definition, world.device_rules):
			return "INVALID_PARAMETER"
		if not _region_allowed(definition.cell, policy):
			return "PERMISSION_DENIED"
		if definition.kind == "robot":
			if definition.patrol_path[0] != definition.cell:
				return "INVALID_PATH"
			for waypoint: Array in definition.patrol_path:
				if not _region_allowed(waypoint, policy):
					return "PERMISSION_DENIED"
				if world.get_cell_profile(DeviceRegistry.grid(waypoint)).blocks_movement:
					return "INVALID_PATH"
		var id: int = world.next_entity_id
		world.registry._put(DeviceRegistry.make_entity(definition, id, world.cell_to_world(DeviceRegistry.grid(definition.cell))))
		world.next_entity_id += 1
		result.created_ids.append({"command_index": index, "id": id})
		return ""
	var id: int = command.get("robot_id", command.get("id", 0))
	var entity: Dictionary = world.registry.get_entity(id)
	if entity.is_empty():
		return "UNKNOWN_ID"
	if entity.kind not in allowed or entity.kind in DeviceRegistry.FIXED:
		return "PERMISSION_DENIED"
	match command.type:
		"RemoveDevice":
			world.registry._remove(id)
			# Removed robots must not leave dangling private occupancy references.
			for other: Dictionary in world.registry.to_snapshot():
				if other.kind == "pressure_plate":
					other.runtime_state.occupants.erase(id)
					world.registry._put(other)
			return ""
		"MoveDevice":
			if entity.kind not in ["camera", "pressure_plate"] or not _region_allowed(command.cell, policy):
				return "PERMISSION_DENIED"
			entity["cell"] = command.cell.duplicate()
		"SetDeviceParameter":
			var parameters: Variant = policy.get("parameters", {})
			if not parameters is Dictionary or not parameters.get(entity.kind) is Array or command.parameter not in parameters[entity.kind]:
				return "PERMISSION_DENIED"
			if not entity.parameters.has(command.parameter):
				return "INVALID_PARAMETER"
			if command.parameter == "enabled":
				if typeof(command.value) != TYPE_BOOL:
					return "INVALID_PARAMETER"
			elif not DeviceRegistry.number(command.value):
				return "INVALID_PARAMETER"
			entity.parameters[command.parameter] = command.value
		"SetPatrolPath":
			if entity.kind != "robot" or not world._set_patrol(entity, command.cells):
				return "INVALID_PATH"
			for cell: Array in command.cells:
				if not _region_allowed(cell, policy):
					return "PERMISSION_DENIED"
	world.registry._put(entity)
	return ""


func _region_allowed(cell: Array, policy: Dictionary) -> bool:
	if not policy.has("allowed_cells"):
		return true
	return policy.allowed_cells is Array and cell in policy.allowed_cells


func _limits_valid(world: WorldState, policy: Dictionary) -> bool:
	if not policy.has("device_limits"):
		return true
	if not policy.device_limits is Dictionary or not DeviceRegistry.fields(policy.device_limits, ["camera", "robot", "pressure_plate"]):
		return false
	var counts: Dictionary = {"camera": 0, "robot": 0, "pressure_plate": 0}
	for entity: Dictionary in world.registry.to_snapshot():
		if counts.has(entity.kind):
			counts[entity.kind] += 1
	for kind: String in counts:
		if typeof(policy.device_limits[kind]) != TYPE_INT or policy.device_limits[kind] < 0 or counts[kind] > policy.device_limits[kind]:
			return false
	return true


func _hidden_placement_blocked(world: WorldState, command: Dictionary, policy: Dictionary) -> bool:
	if not policy.has("obstacle_protection_radius"):
		return false
	var player_cell: Vector2i = world.world_to_cell(world.player_position)
	if command.type == "MoveObstacle":
		var radius: int = int(policy.obstacle_protection_radius)
		if radius < 0:
			return true
		for instance: Dictionary in world.obstacle_instances:
			if instance.obstacle_id == command.obstacle_id:
				var template: ObstacleTemplate = world.obstacle_template(instance.template_id)
				if template != null:
					for cell: Vector2i in template.covered_cells(DeviceRegistry.grid(command.anchor_cell)):
						if absi(cell.x - player_cell.x) <= radius and absi(cell.y - player_cell.y) <= radius:
							return true
	if command.type == "MoveDevice":
		var entity: Dictionary = world.registry.get_entity(command.id)
		return entity.get("kind") in ["camera", "pressure_plate"] and DeviceRegistry.grid(command.cell) == player_cell
	if command.type == "AddDevice" and command.device.get("kind") in ["camera", "pressure_plate"] and DeviceRegistry.cell(command.device.get("cell")):
		return DeviceRegistry.grid(command.device.cell) == player_cell
	return false


func _new_robot_overlap(world: WorldState, created_ids: Array[Dictionary], authoritative: bool) -> bool:
	var half: float = minf(10.0, world.cell_size * 0.25)
	for created: Dictionary in created_ids:
		var robot: Dictionary = world.registry.get_entity(created.id)
		if robot.get("kind") != "robot":
			continue
		var position: Vector2 = DeviceRegistry.vector(robot.runtime_state.position)
		if authoritative and _actors_overlap(position, world.player_position, half):
			return true
		for other: Dictionary in world.registry.to_snapshot():
			if other.kind == "robot" and other.id != robot.id and _actors_overlap(position, DeviceRegistry.vector(other.runtime_state.position), half):
				return true
	return false


func _actors_overlap(a: Vector2, b: Vector2, half: float) -> bool:
	return absf(a.x - b.x) < half * 2.0 and absf(a.y - b.y) < half * 2.0


func _has_placement_command(commands: Array) -> bool:
	for command: Dictionary in commands:
		if command.type in ["AddDevice", "MoveDevice", "MoveObstacle"]:
			return true
	return false


func _reject(result: WorldCommandResult, code: String, index: int = -1) -> WorldCommandResult:
	result.status = "REJECTED"
	result.errors = [{"code": code, "command_index": index}]
	result.created_ids.clear()
	result.command_results.clear()
	return result


func _remember(key: Array, batch: Dictionary, result: WorldCommandResult) -> void:
	_request_key = key.duplicate()
	_cached_batch = batch.duplicate(true)
	_cached_result = result.snapshot_copy()


func _changes(before: Dictionary, after: Dictionary) -> Dictionary:
	var changed: Array[int] = []
	var removed: Array[int] = []
	var changed_obstacles: Array[int] = []
	var removed_obstacles: Array[int] = []
	var old_entities: Dictionary = {}
	for entity: Dictionary in before.entities:
		old_entities[entity.id] = entity
	for entity: Dictionary in after.entities:
		if old_entities.get(entity.id, {}) != entity:
			changed.append(entity.id)
		old_entities.erase(entity.id)
	for id: int in old_entities:
		removed.append(id)
	var old_obstacles: Dictionary = {}
	for instance: Dictionary in before.obstacle_instances:
		old_obstacles[instance.obstacle_id] = instance
	for instance: Dictionary in after.obstacle_instances:
		if old_obstacles.get(instance.obstacle_id, {}) != instance:
			changed_obstacles.append(instance.obstacle_id)
		old_obstacles.erase(instance.obstacle_id)
	for id: int in old_obstacles:
		removed_obstacles.append(id)
	return {"terrain_changed": before.terrain != after.terrain, "changed_ids": changed, "removed_ids": removed,
		"changed_obstacle_ids": changed_obstacles, "removed_obstacle_ids": removed_obstacles}
