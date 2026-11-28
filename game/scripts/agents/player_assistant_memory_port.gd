extends RefCounted
class_name PlayerAssistantMemoryPort
## Module 7C seam. The module 6 fake keeps no hidden world or system report state.


func snapshot() -> Dictionary:
	return {"schema_version": 1, "entries": []}


func on_branch_change(context: Dictionary) -> bool:
	return DeviceRegistry.fields(context, ["round_id", "branch_id", "parent_branch_id"]) \
		and typeof(context.round_id) == TYPE_INT and context.round_id >= 1 \
		and typeof(context.branch_id) == TYPE_INT and context.branch_id >= 1 \
		and typeof(context.parent_branch_id) == TYPE_INT and context.parent_branch_id >= 0
