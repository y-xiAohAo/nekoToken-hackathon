extends RefCounted
class_name SystemAgentView
## Only information authorized for the system Agent.

const FIELDS: Array[String] = ["world", "reports", "history"]
const WORLD_FIELDS: Array[String] = ["grid_size", "cell_size", "origin", "terrain", "obstacle_templates", "obstacle_instances", "cameras", "robots", "fixed_entities", "world_revision", "device_counts", "dispatch_rules"]
const FORBIDDEN: Array[String] = ["player_world_position", "player_position", "player_velocity", "contact_source", "actor_id", "occupants", "baseline_ready", "runtime_state", "active_contact_id", "next_entity_id", "next_obstacle_id", "scene_path", "prepared", "used", "complete"]

var _data: Dictionary = {}

func initialize(world: WorldState, dispatch_rules: Dictionary = {}) -> bool:
	if world == null or not world.validate().is_empty():
		return false
	var candidate: Dictionary = {"world": public_world(world, dispatch_rules), "reports": [], "history": []}
	if not _valid(candidate):
		return false
	_data = candidate
	return true

func update_configuration(committed_world: WorldState) -> bool:
	if _data.is_empty() or committed_world == null or not committed_world.validate().is_empty():
		return false
	var candidate: Dictionary = _data.duplicate(true)
	candidate.world = public_world(committed_world, candidate.world.dispatch_rules)
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


func set_branch_lineage(lineage: Array[Dictionary]) -> bool:
	if _data.is_empty():
		return false
	var candidate: Dictionary = _data.duplicate(true)
	candidate["view_schema_version"] = 2
	candidate["branch_lineage"] = lineage.duplicate(true)
	if not _valid(candidate):
		return false
	_data = candidate
	return true


static func public_world(world: WorldState, dispatch_rules: Dictionary) -> Dictionary:
	if world == null:
		return {}
	var fixed: Array[Dictionary] = []
	var cameras: Array[Dictionary] = []
	var robots: Array[Dictionary] = []
	var counts: Dictionary = {"camera": 0, "robot": 0, "pressure_plate": 0}
	for entity: Dictionary in world.registry.to_snapshot():
		match entity.kind:
			"camera":
				counts.camera += 1
				cameras.append(public_device_configuration(entity))
			"robot":
				counts.robot += 1
				var state: Dictionary = entity.runtime_state
				var cell: Vector2i = world.world_to_cell(DeviceRegistry.vector(state.position))
				robots.append({"id": entity.id, "position": state.position.duplicate(true), "cell": [cell.x, cell.y],
					"path_index": state.path_index, "progress": state.progress, "travel_direction": state.travel_direction,
					"transition": state.transition.duplicate(true), "patrol_path": entity.patrol_path.duplicate(true),
					"parameters": entity.parameters.duplicate(true)})
			"pressure_plate":
				counts.pressure_plate += 1
				fixed.append({"id": entity.id, "kind": entity.kind, "cell": entity.cell.duplicate(true)})
			"goal", "contact", "exit":
				fixed.append({"id": entity.id, "kind": entity.kind, "cell": entity.cell.duplicate(true)})
	var templates: Array[Dictionary] = []
	for raw: Dictionary in world.obstacle_templates:
		templates.append({"template_id": raw.template_id, "footprint": raw.footprint.duplicate(true),
			"blocks_movement": raw.blocks_movement, "blocks_vision": raw.blocks_vision})
	var rules: Dictionary = {}
	for key: String in ["commands", "parameters", "max_commands", "allowed_cells", "device_limits", "obstacle_protection_radius", "max_dispatch_attempts"]:
		if dispatch_rules.has(key):
			rules[key] = dispatch_rules[key].duplicate(true) if dispatch_rules[key] is Array or dispatch_rules[key] is Dictionary else dispatch_rules[key]
	return {"grid_size": [world.grid_size.x, world.grid_size.y], "cell_size": world.cell_size,
		"origin": DeviceRegistry.pair(world.origin), "terrain": world.terrain.duplicate(true),
		"obstacle_templates": templates, "obstacle_instances": world.obstacle_instances.duplicate(true),
		"cameras": cameras, "robots": robots, "fixed_entities": fixed,
		"world_revision": world.world_revision, "device_counts": counts, "dispatch_rules": rules}

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
				"parameters": entity.parameters.duplicate(true), "heading": entity.runtime_state.heading,
				"scan_direction": entity.runtime_state.scan_direction}
		"robot":
			return {"id": entity.id, "kind": "robot", "patrol_path": entity.patrol_path.duplicate(true),
				"parameters": entity.parameters.duplicate(true)}
		"pressure_plate":
			return {"id": entity.id, "kind": "pressure_plate", "cell": entity.cell.duplicate(true)}
	return {}

static func _valid(value: Dictionary) -> bool:
	if not DeviceRegistry.plain(value) or not DeviceRegistry.fields(value, FIELDS, ["view_schema_version", "branch_lineage"]) or not _no_forbidden(value):
		return false
	var has_schema: bool = value.has("view_schema_version") or value.has("branch_lineage")
	if has_schema and (not DeviceRegistry.fields(value, FIELDS + ["view_schema_version", "branch_lineage"]) or value.view_schema_version != 2 or not value.branch_lineage is Array or not _lineage_valid(value.branch_lineage)):
		return false
	if not DeviceRegistry.fields(value.world, WORLD_FIELDS):
		return false
	var map: Dictionary = value.world
	if not DeviceRegistry.cell(map.grid_size) or map.grid_size[0] <= 0 or map.grid_size[1] <= 0 or not DeviceRegistry.number(map.cell_size) or map.cell_size <= 0 or not DeviceRegistry.vector_point(map.origin):
		return false
	if not WorldState.terrain_valid(map.terrain, DeviceRegistry.grid(map.grid_size)) or typeof(map.world_revision) != TYPE_INT or map.world_revision < 0:
		return false
	if not map.obstacle_templates is Array or not map.obstacle_instances is Array or not map.cameras is Array or not map.robots is Array or not map.fixed_entities is Array:
		return false
	if not DeviceRegistry.fields(map.device_counts, ["camera", "robot", "pressure_plate"]) or not DeviceRegistry.fields(map.dispatch_rules, [],
		["commands", "parameters", "max_commands", "allowed_cells", "device_limits", "obstacle_protection_radius", "max_dispatch_attempts"]):
		return false
	for kind: String in ["camera", "robot", "pressure_plate"]:
		if typeof(map.device_counts[kind]) != TYPE_INT or map.device_counts[kind] < 0:
			return false
	var templates: Dictionary = {}
	for template: Variant in map.obstacle_templates:
		if not DeviceRegistry.fields(template, ["template_id", "footprint", "blocks_movement", "blocks_vision"]) or not template.template_id is String or template.template_id.is_empty() or templates.has(template.template_id):
			return false
		if not template.footprint is Array or template.footprint.is_empty() or typeof(template.blocks_movement) != TYPE_BOOL or typeof(template.blocks_vision) != TYPE_BOOL:
			return false
		var offsets: Array = []
		for offset: Variant in template.footprint:
			if not DeviceRegistry.cell(offset) or offset[0] < 0 or offset[1] < 0 or offset in offsets:
				return false
			offsets.append(offset)
		if [0, 0] not in offsets:
			return false
		templates[template.template_id] = true
	var obstacle_ids: Dictionary = {}
	for obstacle: Variant in map.obstacle_instances:
		if not DeviceRegistry.fields(obstacle, ["obstacle_id", "template_id", "anchor_cell"]) or typeof(obstacle.obstacle_id) != TYPE_INT or obstacle.obstacle_id < 1 or obstacle_ids.has(obstacle.obstacle_id) or not templates.has(obstacle.template_id) or not DeviceRegistry.cell(obstacle.anchor_cell):
			return false
		obstacle_ids[obstacle.obstacle_id] = true
	var camera_count: int = 0
	for camera: Variant in map.cameras:
		if not camera is Dictionary or not UnifiedReportBatch.public_device_configuration_valid(camera, camera.get("id", 0), "visual"):
			return false
		camera_count += 1
	if camera_count != map.device_counts.camera or map.robots.size() != map.device_counts.robot:
		return false
	for robot: Variant in map.robots:
		if not DeviceRegistry.fields(robot, ["id", "position", "cell", "path_index", "progress", "travel_direction", "transition", "patrol_path", "parameters"]):
			return false
		if typeof(robot.id) != TYPE_INT or robot.id < 1 or not DeviceRegistry.vector_point(robot.position) or not DeviceRegistry.cell(robot.cell) or not robot.patrol_path is Array or robot.patrol_path.is_empty():
			return false
		if typeof(robot.path_index) != TYPE_INT or robot.path_index < 0 or robot.path_index >= robot.patrol_path.size() or not DeviceRegistry.number(robot.progress) or robot.progress < 0 or robot.progress >= 1 or robot.travel_direction not in [-1, 1]:
			return false
		if not robot.transition is Dictionary or not DeviceRegistry.fields(robot.parameters, DeviceRegistry.ROBOT_NUMBERS):
			return false
		if not DeviceRegistry.number(robot.parameters.view_radius) or not DeviceRegistry.number(robot.parameters.move_speed):
			return false
		var actual: Vector2i = Vector2i(((DeviceRegistry.vector(robot.position) - DeviceRegistry.vector(map.origin)) / float(map.cell_size)).floor())
		if robot.cell != [actual.x, actual.y]:
			return false
		for waypoint: Variant in robot.patrol_path:
			if not DeviceRegistry.cell(waypoint):
				return false
	var last_id: int = 0
	for fixed: Variant in map.fixed_entities:
		if not DeviceRegistry.fields(fixed, ["id", "kind", "cell"]) or typeof(fixed.id) != TYPE_INT or fixed.id <= last_id or fixed.kind not in DeviceRegistry.FIXED + ["pressure_plate"] or not DeviceRegistry.cell(fixed.cell):
			return false
		last_id = fixed.id
	if not value.reports is Array or not value.history is Array:
		return false
	var plate_count: int = 0
	for fixed: Dictionary in map.fixed_entities:
		if fixed.kind == "pressure_plate":
			plate_count += 1
	if plate_count != map.device_counts.pressure_plate or not _history_valid(value.history):
		return false
	return _reports_valid(value.reports, value.get("branch_lineage", []))


static func _history_valid(entries: Array) -> bool:
	return SystemAgentHistory.from_snapshot({"entries": entries.duplicate(true)}) != null


static func _lineage_valid(lineage: Array) -> bool:
	if lineage.is_empty():
		return true
	var known: Dictionary = {}
	var round_id: int = -1
	for edge: Variant in lineage:
		if not DeviceRegistry.fields(edge, ["round_id", "branch_id", "parent_branch_id", "fork_tick", "fork_report_period_id"]):
			return false
		for field: String in ["round_id", "branch_id", "parent_branch_id", "fork_tick", "fork_report_period_id"]:
			if typeof(edge[field]) != TYPE_INT:
				return false
		if edge.round_id < 1 or edge.branch_id < 1 or edge.parent_branch_id < 0 or edge.fork_tick < 0 or edge.fork_report_period_id < 0:
			return false
		if round_id < 0:
			round_id = edge.round_id
		var key: String = "%d:%d" % [edge.round_id, edge.branch_id]
		if edge.round_id != round_id or known.has(key):
			return false
		if edge.parent_branch_id == 0:
			if not known.is_empty() or edge.fork_tick != 0 or edge.fork_report_period_id != 0:
				return false
		else:
			var parent_key: String = "%d:%d" % [edge.round_id, edge.parent_branch_id]
			if not known.has(parent_key):
				return false
		known[key] = edge
	return true


static func _reports_valid(reports: Array, lineage: Array) -> bool:
	var previous: UnifiedReportBatch = null
	for raw_batch: Variant in reports:
		if not raw_batch is Dictionary:
			return false
		var batch: UnifiedReportBatch = UnifiedReportBatch.from_data(raw_batch)
		if batch == null:
			return false
		if not lineage.is_empty() and _lineage_edge(lineage, batch.round_id, batch.branch_id).is_empty():
			return false
		if lineage.is_empty():
			for record: Dictionary in batch.records:
				if record.has("origin_branch_id"):
					return false
		else:
			for record: Dictionary in batch.records:
				if record.has("origin_branch_id") and not _is_ancestor(lineage, record.origin_branch_id, batch.branch_id, batch.round_id):
					return false
		if previous != null:
			if batch.report_period_id != previous.report_period_id + 1 or batch.start_tick != previous.end_tick or batch.round_id != previous.round_id:
				return false
			if batch.branch_id != previous.branch_id:
				if lineage.is_empty() or not _branch_continues_at_fork(lineage, previous, batch):
					return false
		previous = batch
	for edge: Dictionary in lineage:
		if not _fork_anchor_valid(lineage, reports, edge):
			return false
	return true


static func _branch_continues_at_fork(lineage: Array, previous: UnifiedReportBatch, batch: UnifiedReportBatch) -> bool:
	var branch_id: int = batch.branch_id
	var seen: Dictionary = {}
	while branch_id > 0 and not seen.has(branch_id):
		seen[branch_id] = true
		var edge: Dictionary = _lineage_edge(lineage, batch.round_id, branch_id)
		if edge.is_empty() or edge.fork_tick != previous.end_tick or edge.fork_report_period_id != previous.report_period_id:
			return false
		if edge.parent_branch_id == previous.branch_id:
			return true
		var parent: Dictionary = _lineage_edge(lineage, batch.round_id, edge.parent_branch_id)
		if parent.is_empty() or parent.fork_tick != edge.fork_tick or parent.fork_report_period_id != edge.fork_report_period_id:
			return false
		branch_id = edge.parent_branch_id
	return false


static func _fork_anchor_valid(lineage: Array, reports: Array, edge: Dictionary) -> bool:
	if edge.parent_branch_id == 0 or edge.fork_report_period_id == 0:
		return true
	var parent: Dictionary = _lineage_edge(lineage, edge.round_id, edge.parent_branch_id)
	if not parent.is_empty() and parent.parent_branch_id > 0 and parent.fork_tick == edge.fork_tick and parent.fork_report_period_id == edge.fork_report_period_id:
		return true
	for raw_batch: Dictionary in reports:
		if raw_batch.round_id == edge.round_id and raw_batch.branch_id == edge.parent_branch_id and raw_batch.report_period_id == edge.fork_report_period_id and raw_batch.end_tick == edge.fork_tick:
			return true
	return false


static func _lineage_edge(lineage: Array, round_id: int, branch_id: int) -> Dictionary:
	for edge: Dictionary in lineage:
		if edge.round_id == round_id and edge.branch_id == branch_id:
			return edge
	return {}


static func _is_ancestor(lineage: Array, ancestor_id: int, branch_id: int, round_id: int) -> bool:
	var current: int = branch_id
	var seen: Dictionary = {}
	while current > 0 and not seen.has(current):
		if current == ancestor_id:
			return true
		seen[current] = true
		var edge: Dictionary = _lineage_edge(lineage, round_id, current)
		if edge.is_empty():
			return false
		current = edge.parent_branch_id
	return false

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
