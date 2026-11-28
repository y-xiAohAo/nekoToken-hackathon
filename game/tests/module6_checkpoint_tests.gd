extends RefCounted
class_name Module6CheckpointTests
## Module 6 checkpoint and non-restorable run metadata contracts.

var passed: int = 0
var failed: int = 0


func run() -> Dictionary:
	_check(_initial_capture_is_deep(), "S0 stores an independent complete snapshot")
	_check(_rejects_bad_identity_and_schema(), "checkpoint rejects mismatched identities and schema")
	_check(_captures_after_dispatch_without_public_revision_match(), "S1 accepts unpublished dispatch configuration")
	_check(_run_metadata_survives_fork(), "run budget and ID allocation do not roll back")
	return {"passed": passed, "failed": failed}


func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("MODULE 6 CHECKPOINT TEST FAILED: " + label)


func _fixture() -> Dictionary:
	var world: WorldState = LevelTemplate.from_data(PrototypeConfig.level_data()).instantiate_world()
	var session := GameSession.new(PrototypeConfig.make_session_rules())
	var sensing := RuntimeSensingCoordinator.new()
	var context: Dictionary = {"round_id": 1, "branch_id": 1, "guess_cycle_id": 1,
		"report_cycle_id": 1, "sense_tick": 0}
	if world == null or not sensing.initialize_round(world, context, session.get_ticks_per_report_period(), PrototypeConfig.system_dispatch_policy()):
		return {}
	return {"world": world, "session": session, "sensing": sensing}


func _initial_capture_is_deep() -> bool:
	var f: Dictionary = _fixture()
	if f.is_empty():
		return false
	var checkpoint: CycleCheckpoint = CycleCheckpoint.capture(f.world, f.session, f.sensing)
	if checkpoint == null:
		return false
	var saved: Dictionary = checkpoint.to_data()
	var original: Dictionary = saved.duplicate(true)
	saved.world.player_position = [999.0, 999.0]
	saved.sensing.device_buffer.pending.clear()
	return checkpoint.to_data() == original and original.source.simulation_tick == 0 \
		and original.active_report_count == 0


func _rejects_bad_identity_and_schema() -> bool:
	var f: Dictionary = _fixture()
	if f.is_empty():
		return false
	var valid: Dictionary = CycleCheckpoint.capture(f.world, f.session, f.sensing).to_data()
	var bad_schema: Dictionary = valid.duplicate(true)
	bad_schema.schema_version = 2
	var bad_branch: Dictionary = valid.duplicate(true)
	bad_branch.sensing.branch_id = 2
	var bad_count: Dictionary = valid.duplicate(true)
	bad_count.active_report_count = 1
	return CycleCheckpoint.from_data(bad_schema) == null and CycleCheckpoint.from_data(bad_branch) == null \
		and CycleCheckpoint.from_data(bad_count) == null


func _captures_after_dispatch_without_public_revision_match() -> bool:
	var f: Dictionary = _fixture()
	if f.is_empty():
		return false
	f.session._state.phase = SessionPhase.Phase.CYCLE_START_PENDING
	f.session._state.guess_cycle_id = 2
	f.world.world_revision += 1
	var checkpoint: CycleCheckpoint = CycleCheckpoint.capture(f.world, f.session, f.sensing)
	return checkpoint != null and checkpoint.to_data().world.world_revision == 1 \
		and checkpoint.to_data().sensing.system_view.world.world_revision == 0


func _run_metadata_survives_fork() -> bool:
	var f: Dictionary = _fixture()
	if f.is_empty():
		return false
	var checkpoint: CycleCheckpoint = CycleCheckpoint.capture(f.world, f.session, f.sensing)
	var run := RunState.new(f.world)
	var branch_world: WorldState = f.world.snapshot_copy()
	branch_world.next_entity_id += 2
	branch_world.next_obstacle_id += 1
	var prepared: Dictionary = run.prepare_local_fork(checkpoint, branch_world)
	if prepared.is_empty():
		return false
	run.accept_prepared(prepared)
	var snapshot: Dictionary = run.snapshot()
	return snapshot.remaining_local_resets == 2 and snapshot.next_entity_id >= branch_world.next_entity_id \
		and snapshot.next_obstacle_id >= branch_world.next_obstacle_id and snapshot.next_branch_id > 2
