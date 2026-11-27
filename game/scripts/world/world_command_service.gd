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


func validate_batch(batch: WorldCommandBatch, expected_context: Dictionary) -> WorldCommandResult:
	var result: WorldCommandResult = _check_context(batch, expected_context)
	if not result.errors.is_empty():
		return result
	var candidate: WorldState = _build_candidate(batch.to_data(), result)
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
	var candidate: WorldState = _build_candidate(data, result)
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


func _build_candidate(data: Dictionary, result: WorldCommandResult) -> WorldState:
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
		var code: String = _apply(candidate, data.commands[index], role_policy, result, index)
		if not code.is_empty():
			_reject(result, code, index)
			return null
		result.command_results.append({"command_index": index, "status": "VALID"})
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
	var errors: Array[Dictionary] = candidate.validate()
	if not errors.is_empty():
		_reject(result, errors[0].code)
		return null
	return candidate


func _apply(world: WorldState, command: Dictionary, policy: Dictionary, result: WorldCommandResult, index: int) -> String:
	var permissions: Variant = policy.get("commands", {})
	if not permissions is Dictionary or not permissions.get(command.type) is Array:
		return "PERMISSION_DENIED"
	var allowed: Array = permissions[command.type]
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
			if entity.kind == "pressure_plate":
				if command.has("mount_type") or command.has("wall_side"):
					return "INVALID_COMMAND"
			else:
				if command.get("mount_type") not in ["wall", "ceiling"]:
					return "INVALID_COMMAND"
				entity["mount_type"] = command.mount_type
				entity.erase("wall_side")
				if command.mount_type == "wall":
					if command.get("wall_side") not in DeviceRegistry.SIDES:
						return "INVALID_COMMAND"
					entity["wall_side"] = command.wall_side
				elif command.has("wall_side"):
					return "INVALID_COMMAND"
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
	var old_entities: Dictionary = {}
	for entity: Dictionary in before.entities:
		old_entities[entity.id] = entity
	for entity: Dictionary in after.entities:
		if old_entities.get(entity.id, {}) != entity:
			changed.append(entity.id)
		old_entities.erase(entity.id)
	for id: int in old_entities:
		removed.append(id)
	return {"terrain_changed": before.terrain != after.terrain, "changed_ids": changed, "removed_ids": removed}
