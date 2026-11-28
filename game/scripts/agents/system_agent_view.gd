extends RefCounted
class_name SystemAgentView
## Only information authorized for the system Agent.

const FIELDS: Array[String] = ["static_map", "device_configuration", "reports", "history"]
const FORBIDDEN: Array[String] = ["player_world_position", "player_position", "contact_source", "actor_id", "occupants", "baseline_ready", "runtime_state"]

var _data: Dictionary = {}

func initialize(world: WorldState) -> bool:
	if world == null or not world.validate().is_empty():
		return false
	var fixed: Array[Dictionary] = []
	for entity: Dictionary in world.registry.to_snapshot():
		if entity.kind in DeviceRegistry.FIXED:
			fixed.append({"id": entity.id, "kind": entity.kind, "cell": entity.cell.duplicate(true)})
	var candidate: Dictionary = {"static_map": {"grid_size": [world.grid_size.x, world.grid_size.y], "cell_size": world.cell_size,
		"origin": DeviceRegistry.pair(world.origin), "terrain": world.terrain.duplicate(true), "fixed_entities": fixed},
		"device_configuration": public_configurations(world), "reports": [], "history": []}
	if not _valid(candidate):
		return false
	_data = candidate
	return true

func update_configuration(committed_world: WorldState) -> bool:
	if _data.is_empty() or committed_world == null or not committed_world.validate().is_empty():
		return false
	var candidate: Dictionary = _data.duplicate(true)
	candidate.device_configuration = public_configurations(committed_world)
	if not _valid(candidate):
		return false
	_data = candidate
	return true

func append_batch(batch: UnifiedReportBatch) -> bool:
	if _data.is_empty() or batch == null:
		return false
	var verified: UnifiedReportBatch = UnifiedReportBatch.from_data(batch.to_data())
	if verified == null:
		return false
	var candidate: Dictionary = _data.duplicate(true)
	if not candidate.reports.is_empty():
		var previous: Dictionary = candidate.reports[-1]
		if verified.report_period_id != previous.report_period_id + 1 or verified.start_tick != previous.end_tick or verified.round_id != previous.round_id or verified.branch_id != previous.branch_id:
			return false
	candidate.reports.append(verified.to_data())
	if not _valid(candidate):
		return false
	_data = candidate
	return true

func to_data() -> Dictionary:
	return _data.duplicate(true)

func snapshot() -> Dictionary:
	return to_data()

func restore(data: Dictionary) -> bool:
	if not _valid(data):
		return false
	_data = data.duplicate(true)
	return true

static func public_configurations(world: WorldState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if world == null:
		return result
	for entity: Dictionary in world.registry.to_snapshot():
		var configuration: Dictionary = public_device_configuration(entity)
		if not configuration.is_empty():
			result.append(configuration)
	return result

static func public_device_configuration(entity: Dictionary) -> Dictionary:
	if typeof(entity.get("id")) != TYPE_INT or entity.id < 1:
		return {}
	match entity.get("kind"):
		"camera":
			return {"id": entity.id, "kind": "camera", "cell": entity.cell.duplicate(true),
				"mount_type": entity.mount_type, "wall_side": entity.get("wall_side", ""), "parameters": entity.parameters.duplicate(true)}
		"robot":
			return {"id": entity.id, "kind": "robot", "patrol_path": entity.patrol_path.duplicate(true),
				"parameters": entity.parameters.duplicate(true)}
		"pressure_plate":
			return {"id": entity.id, "kind": "pressure_plate", "cell": entity.cell.duplicate(true)}
	return {}

static func _valid(value: Dictionary) -> bool:
	if not DeviceRegistry.plain(value) or not DeviceRegistry.fields(value, FIELDS) or not _no_forbidden(value):
		return false
	if not DeviceRegistry.fields(value.static_map, ["grid_size", "cell_size", "origin", "terrain", "fixed_entities"]):
		return false
	var map: Dictionary = value.static_map
	if not DeviceRegistry.cell(map.grid_size) or map.grid_size[0] <= 0 or map.grid_size[1] <= 0 or not DeviceRegistry.number(map.cell_size) or map.cell_size <= 0 or not DeviceRegistry.vector_point(map.origin):
		return false
	if not WorldState.terrain_valid(map.terrain, DeviceRegistry.grid(map.grid_size)) or not map.fixed_entities is Array:
		return false
	var last_id: int = 0
	for fixed: Variant in map.fixed_entities:
		if not DeviceRegistry.fields(fixed, ["id", "kind", "cell"]) or typeof(fixed.id) != TYPE_INT or fixed.id <= last_id or fixed.kind not in DeviceRegistry.FIXED or not DeviceRegistry.cell(fixed.cell):
			return false
		last_id = fixed.id
	if not value.device_configuration is Array or not value.reports is Array or not value.history is Array or not value.history.is_empty():
		return false
	last_id = 0
	for config: Variant in value.device_configuration:
		if not config is Dictionary or typeof(config.get("id")) != TYPE_INT or config.id <= last_id or not UnifiedReportBatch.public_device_configuration_valid(config, config.id):
			return false
		last_id = config.id
	var previous: UnifiedReportBatch = null
	for raw_batch: Variant in value.reports:
		if not raw_batch is Dictionary:
			return false
		var batch: UnifiedReportBatch = UnifiedReportBatch.from_data(raw_batch)
		if batch == null:
			return false
		if previous != null and (batch.report_period_id != previous.report_period_id + 1 or batch.start_tick != previous.end_tick or batch.round_id != previous.round_id or batch.branch_id != previous.branch_id):
			return false
		previous = batch
	return true

static func _no_forbidden(value: Variant) -> bool:
	if value is Dictionary:
		for key: Variant in value:
			if key in FORBIDDEN or not _no_forbidden(value[key]):
				return false
	elif value is Array:
		for item: Variant in value:
			if not _no_forbidden(item):
				return false
	return true
