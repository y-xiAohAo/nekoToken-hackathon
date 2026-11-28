extends RefCounted
class_name SensingKernel
## Stateless visual/plate evaluation over a detached world candidate.

const CONTEXT_FIELDS: Array[String] = ["round_id", "branch_id", "guess_cycle_id", "report_cycle_id", "sense_tick"]
const STATE_FIELDS: Array[String] = ["visible_cell", "last_evaluated_tick", "last_emitted_tick"]

static func actor_cells(world: WorldState) -> Dictionary:
	var result: Dictionary = {}
	if world == null or not world.player_position.is_finite():
		return result
	result[0] = world.world_to_cell(world.player_position)
	for entity: Dictionary in world.registry.to_snapshot():
		if entity.kind == "robot" and DeviceRegistry.vector_point(entity.runtime_state.position):
			result[entity.id] = world.world_to_cell(DeviceRegistry.vector(entity.runtime_state.position))
	return result

static func copy_visual_states(states: Dictionary) -> Dictionary:
	return states.duplicate(true)

static func restore_visual_states(data: Dictionary, world: WorldState) -> Dictionary:
	var errors: Array[Dictionary] = []
	var expected: Dictionary = {}
	if world == null:
		return {"ok": false, "states": {}, "errors": [{"code": "INVALID_WORLD"}]}
	for entity: Dictionary in world.registry.to_snapshot():
		if entity.kind in ["camera", "robot"]:
			expected[entity.id] = true
	if data.size() != expected.size():
		errors.append({"code": "INVALID_VISUAL_STATES"})
	var restored: Dictionary = {}
	var key_type: int = TYPE_NIL
	for key: Variant in data:
		if key_type == TYPE_NIL:
			key_type = typeof(key)
		if typeof(key) != key_type or key_type not in [TYPE_INT, TYPE_STRING]:
			errors.append({"code": "INVALID_VISUAL_STATES"})
			continue
		var id: int = 0
		if key_type == TYPE_INT:
			id = key
		else:
			if not key.is_valid_int() or str(key.to_int()) != key:
				errors.append({"code": "INVALID_VISUAL_STATES"})
				continue
			id = key.to_int()
		if not expected.has(id) or restored.has(id) or not DeviceRegistry.fields(data[key], STATE_FIELDS):
			errors.append({"code": "INVALID_VISUAL_STATES"})
			continue
		var state: Dictionary = data[key].duplicate(true)
		if key_type == TYPE_STRING and state.visible_cell != null:
			if not DeviceRegistry.cell(state.visible_cell):
				errors.append({"code": "INVALID_VISUAL_STATES"})
				continue
			state.visible_cell = DeviceRegistry.grid(state.visible_cell)
		if not _valid_state(state) or (state.visible_cell != null and not world.in_bounds(state.visible_cell)):
			errors.append({"code": "INVALID_VISUAL_STATES"})
			continue
		restored[id] = state
	for id: int in expected:
		if not restored.has(id):
			errors.append({"code": "INVALID_VISUAL_STATES"})
	return {"ok": errors.is_empty(), "states": restored if errors.is_empty() else {}, "errors": errors}

static func initialize_round(world: WorldState, context: Dictionary, ticks_per_report_period: int) -> SensingStepResult:
	var output := SensingStepResult.new()
	if not _valid_context(context, ticks_per_report_period) or context.sense_tick != 0 or world == null or not world.player_position.is_finite():
		return _error("INVALID_CONTEXT")
	for entity: Dictionary in world.registry.to_snapshot():
		if entity.kind not in ["camera", "robot"]:
			continue
		var observation: Dictionary = _observe(world, entity, context)
		if observation.get("ok") != true:
			return _error(str(observation.get("error", "INVALID_SENSOR")))
		output.visual_records.append(observation.record)
		output.next_visual_states[entity.id] = {"visible_cell": observation.visible_cell, "last_evaluated_tick": 0, "last_emitted_tick": 0}
	return output

static func step(visual_states: Dictionary, previous_actor_cells: Dictionary, world: WorldState, context: Dictionary, ticks_per_report_period: int) -> SensingStepResult:
	if world == null or not world.player_position.is_finite() or not _valid_context(context, ticks_per_report_period) or context.sense_tick == 0:
		return _error("INVALID_CONTEXT")
	var current_actors: Dictionary = actor_cells(world)
	if current_actors.size() != previous_actor_cells.size():
		return _error("MISSING_ACTOR_SAMPLE" if current_actors.size() > previous_actor_cells.size() else "STALE_ACTOR_SAMPLE")
	for actor: Variant in current_actors:
		if not previous_actor_cells.has(actor) or not previous_actor_cells[actor] is Vector2i:
			return _error("MISSING_ACTOR_SAMPLE")
	for actor: Variant in previous_actor_cells:
		if not current_actors.has(actor):
			return _error("STALE_ACTOR_SAMPLE")
	var entities: Array[Dictionary] = world.registry.to_snapshot()
	var visual_ids: Dictionary = {}
	for entity: Dictionary in entities:
		if entity.kind in ["camera", "robot"]:
			visual_ids[entity.id] = true
	for id: Variant in visual_states:
		if typeof(id) != TYPE_INT or not _valid_state(visual_states[id]) or int(visual_states[id].last_evaluated_tick) >= context.sense_tick:
			return _error("INVALID_VISUAL_STATES")
		if visual_states[id].visible_cell != null and not world.in_bounds(visual_states[id].visible_cell):
			return _error("INVALID_VISUAL_STATES")
	var output := SensingStepResult.new()
	for entity: Dictionary in entities:
		if entity.kind not in ["camera", "robot"]:
			continue
		var previous: Dictionary = visual_states.get(entity.id, {})
		var newly_added: bool = previous.is_empty()
		if newly_added:
			previous = {"visible_cell": null, "last_evaluated_tick": context.sense_tick - 1, "last_emitted_tick": context.sense_tick - 1}
		var observation: Dictionary = _observe(world, entity, context)
		if observation.get("ok") != true:
			return _error(str(observation.get("error", "INVALID_SENSOR")))
		var visible_cell: Variant = observation.visible_cell
		var emit: bool = newly_added or (visible_cell != null and visible_cell != previous.visible_cell) or (visible_cell == null and previous.visible_cell != null)
		if context.sense_tick % ticks_per_report_period == ticks_per_report_period - 1:
			emit = true
		var emitted_tick: int = previous.last_emitted_tick
		if emit:
			output.visual_records.append(observation.record)
			emitted_tick = context.sense_tick
		output.next_visual_states[entity.id] = {"visible_cell": visible_cell, "last_evaluated_tick": context.sense_tick, "last_emitted_tick": emitted_tick}
	for entity: Dictionary in entities:
		if entity.kind != "pressure_plate":
			continue
		var plate_cell: Vector2i = DeviceRegistry.grid(entity.cell)
		var actors: Array = current_actors.keys()
		actors.sort()
		for actor: int in actors:
			if previous_actor_cells[actor] != plate_cell and current_actors[actor] == plate_cell:
				var data: Dictionary = _identity(context)
				data["device_id"] = entity.id
				data["event_tick"] = context.sense_tick
				data["cell"] = plate_cell
				var activation: PlateActivationRecord = PlateActivationRecord.make(data)
				if activation == null:
					return _error("INVALID_PLATE_RECORD")
				output.plate_records.append(activation)
	return output

static func _observe(world: WorldState, entity: Dictionary, context: Dictionary) -> Dictionary:
	var cells: Array[Vector2i] = []
	var reason: String = ""
	if entity.kind == "camera" and entity.parameters.enabled == false:
		reason = "DISABLED"
	else:
		var geometry: Dictionary = VisionGeometry.reliable_cells(world, entity)
		if geometry.get("ok") != true:
			return {"ok": false, "error": geometry.get("errors", [{"code": "INVALID_SENSOR"}])[0].code}
		cells.assign(geometry.cells)
		if cells.is_empty():
			reason = "NO_RELIABLE_CELLS"
	var player_cell: Vector2i = world.world_to_cell(world.player_position)
	var detected: bool = player_cell in cells
	var data: Dictionary = _identity(context)
	data["device_id"] = entity.id
	data["sense_tick"] = context.sense_tick
	data["result"] = "UNDETERMINED" if cells.is_empty() else ("DETECTED" if detected else "NOT_DETECTED")
	data["reliable_cells"] = cells
	data["player_cell"] = player_cell if detected else null
	data["reason"] = reason
	var record: ObservationRecord = ObservationRecord.make(data)
	return {"ok": record != null, "record": record, "visible_cell": player_cell if detected else null, "error": "INVALID_OBSERVATION"}

static func _identity(context: Dictionary) -> Dictionary:
	return {"round_id": context.round_id, "branch_id": context.branch_id, "guess_cycle_id": context.guess_cycle_id, "report_cycle_id": context.report_cycle_id}

static func _valid_context(context: Dictionary, ticks_per_report_period: int) -> bool:
	if ticks_per_report_period <= 0 or not DeviceRegistry.fields(context, CONTEXT_FIELDS):
		return false
	for key: String in CONTEXT_FIELDS.slice(0, 4):
		if typeof(context[key]) != TYPE_INT or context[key] < 1:
			return false
	if typeof(context.sense_tick) != TYPE_INT or context.sense_tick < 0:
		return false
	return context.report_cycle_id == context.sense_tick / ticks_per_report_period + 1

static func _valid_state(state: Variant) -> bool:
	if not DeviceRegistry.fields(state, STATE_FIELDS):
		return false
	if state.visible_cell != null and not state.visible_cell is Vector2i:
		return false
	return typeof(state.last_evaluated_tick) == TYPE_INT and state.last_evaluated_tick >= 0 and typeof(state.last_emitted_tick) == TYPE_INT and state.last_emitted_tick >= 0 and state.last_emitted_tick <= state.last_evaluated_tick

static func _error(code: String) -> SensingStepResult:
	var output := SensingStepResult.new()
	output.errors.append({"code": code})
	return output
