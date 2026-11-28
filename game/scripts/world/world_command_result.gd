extends RefCounted
class_name WorldCommandResult
## Internal receipt, never an Agent-provided success flag.

var status: String = "REJECTED"
var context: Dictionary = {}
var revision_before: int = 0
var revision_after: int = 0
var command_results: Array[Dictionary] = []
var created_ids: Array[Dictionary] = []
var errors: Array[Dictionary] = []


func snapshot_copy() -> WorldCommandResult:
	var result := WorldCommandResult.new()
	result.status = status
	result.context = context.duplicate(true)
	result.revision_before = revision_before
	result.revision_after = revision_after
	result.command_results = command_results.duplicate(true)
	result.created_ids = created_ids.duplicate(true)
	result.errors = errors.duplicate(true)
	return result


func completes(expected: Dictionary) -> bool:
	return status in ["APPLIED", "UNCHANGED"] and errors.is_empty() and AgentProtocol.contexts_match(context, expected)


func safe_dispatch_receipt() -> Dictionary:
	var safe_errors: Array[Dictionary] = []
	for error: Dictionary in errors:
		safe_errors.append({"code": str(error.get("code", "INVALID_COMMAND")),
			"command_index": int(error.get("command_index", -1))})
	return {"status": "REJECTED", "context": AgentProtocol.serialize_context(context), "errors": safe_errors}
