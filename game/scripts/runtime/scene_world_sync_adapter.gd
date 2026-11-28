extends WorldSyncAdapter
class_name SceneWorldSyncAdapter


var _view: RuntimeWorldView


func _init(view: RuntimeWorldView) -> void:
	_view = view


func prepare(_previous: Dictionary, candidate: Dictionary, changes: Dictionary) -> Dictionary:
	if _view == null:
		return {"ok": false, "errors": [{"code": "MISSING_VIEW"}]}
	var prepared: Dictionary = {"terrain": null, "changed": {}, "removed": changes.get("removed_ids", []).duplicate()}
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
		var node: Node2D = _view.make_entity_node(entities[id])
		if node == null:
			_discard(prepared)
			return {"ok": false, "errors": [{"code": "INVALID_ENTITY", "id": id}]}
		prepared.changed[id] = node
	return {"ok": true, "prepared": prepared, "errors": []}


func _discard(prepared: Dictionary) -> void:
	# Staged nodes have no parent and must be released on every rejected prepare.
	if prepared.get("terrain") != null:
		prepared.terrain.free()
	for node: Node in prepared.get("changed", {}).values():
		node.free()


func activate(prepared: Dictionary) -> bool:
	if prepared.get("terrain") != null:
		_view.replace_terrain(prepared.terrain)
	for id: int in prepared.get("removed", []):
		_view.remove_entity(id)
	for id: int in prepared.get("changed", {}):
		_view.replace_entity(id, prepared.changed[id])
	return true
