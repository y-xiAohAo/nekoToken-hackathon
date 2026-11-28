extends RefCounted
class_name SensingKernelTests

var passed: int = 0
var failed: int = 0

func run() -> Dictionary:
	for scenario: Callable in [_dto_and_window, _tick_sequence, _dto_validation, _buffer_atomicity, _plate_entries, _device_change_and_error, _visual_transitions, _deployment_and_restore, _same_cell_walk_and_copy]:
		_check(scenario.call() == true, "scenario completed: " + scenario.get_method())
	return {"passed": passed, "failed": failed}

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("SENSING KERNEL FAILED: " + label)

func _dto_and_window() -> bool:
	var buffer := ReportBuffer.new(3)
	var first: ObservationRecord = ObservationRecord.make({"round_id": 1, "branch_id": 1, "guess_cycle_id": 1, "report_cycle_id": 1, "device_id": 1, "sense_tick": 0, "result": "NOT_DETECTED", "reliable_cells": [Vector2i(1, 1)], "player_cell": null, "reason": ""})
	_check(first != null and buffer.append_visual(first), "tick zero record appended")
	var bad: ObservationRecord = ObservationRecord.make({"round_id": 1, "branch_id": 1, "guess_cycle_id": 1, "report_cycle_id": 1, "device_id": 1, "sense_tick": 3, "result": "NOT_DETECTED", "reliable_cells": [Vector2i(1, 1)], "player_cell": null, "reason": ""})
	_check(bad != null and not buffer.append_visual(bad), "wrong cycle rejected")
	var batch: SensingReportBatch = buffer.seal(ReportBoundary.new(1, 1, 1, 1, 0, 3, false))
	_check(batch != null and batch.records.size() == 1, "first half-open window sealed")
	return true

func _tick_sequence() -> bool:
	var world := WorldState.new()
	world.grid_size = Vector2i(4, 4)
	world.cell_size = 1.0
	world.origin = Vector2.ZERO
	world.player_position = Vector2(1.5, 1.5)
	for y: int in 4:
		world.terrain.append(["FLOOR", "FLOOR", "FLOOR", "FLOOR"])
	world.registry._put({"id": 1, "kind": "camera", "cell": [1, 1], "runtime_state": {"heading": 0.0}, "parameters": {"enabled": true, "view_radius": 2.0, "fov_angle": TAU}})
	var initial: SensingStepResult = SensingKernel.initialize_round(world, {"round_id": 1, "branch_id": 1, "guess_cycle_id": 1, "report_cycle_id": 1, "sense_tick": 0}, 3)
	_check(initial.succeeded() and initial.visual_records.size() == 1, "tick zero full observation")
	var buffer := ReportBuffer.new(3)
	_check(buffer.append_all(initial.visual_records, initial.plate_records), "tick zero enters first report period")
	var states: Dictionary = initial.next_visual_states
	for tick: int in [1, 2, 3]:
		if tick == 3:
			world.player_position = Vector2(2.5, 1.5)
		var result: SensingStepResult = SensingKernel.step(states, SensingKernel.actor_cells(world), world, {"round_id": 1, "branch_id": 1, "guess_cycle_id": 1, "report_cycle_id": tick / 3 + 1, "sense_tick": tick}, 3)
		_check(result.succeeded(), "tick %d accepted" % tick)
		_check(result.visual_records.size() == (0 if tick == 1 else 1), "tick %d emission count" % tick)
		_check(buffer.append_all(result.visual_records, result.plate_records), "tick %d enters matching report period" % tick)
		states = result.next_visual_states
	var first_batch: SensingReportBatch = buffer.seal(ReportBoundary.new(1, 1, 1, 1, 0, 3, false))
	_check(first_batch != null and first_batch.records.map(func(entry: Dictionary) -> int: return entry.data.sense_tick) == [0, 2] and buffer.pending_count() == 1, "integrated N=3 first batch takes ticks zero and two")
	var second_batch: SensingReportBatch = buffer.seal(ReportBoundary.new(1, 1, 1, 2, 3, 6, false))
	_check(second_batch != null and second_batch.records.size() == 1 and second_batch.records[0].data.sense_tick == 3 and second_batch.records[0].data.report_cycle_id == 2, "integrated N=3 tick three stays next batch")
	var one_tick_initial: SensingStepResult = SensingKernel.initialize_round(world, _context(0), 1)
	_check(one_tick_initial.succeeded() and one_tick_initial.visual_records.size() == 1, "N=1 tick zero serves as first period end")
	var one_tick_next: SensingStepResult = SensingKernel.step(one_tick_initial.next_visual_states, SensingKernel.actor_cells(world), world, {"round_id": 1, "branch_id": 1, "guess_cycle_id": 1, "report_cycle_id": 2, "sense_tick": 1}, 1)
	_check(one_tick_next.succeeded() and one_tick_next.visual_records.size() == 1, "N=1 next tick serves as second period end")
	return true

func _dto_validation() -> bool:
	var source: Dictionary = {"round_id": 1, "branch_id": 2, "guess_cycle_id": 3, "report_cycle_id": 1, "device_id": 4, "sense_tick": 0, "result": "DETECTED", "reliable_cells": [Vector2i(1, 1), Vector2i(2, 1)], "player_cell": Vector2i(2, 1), "reason": ""}
	var record: ObservationRecord = ObservationRecord.make(source)
	_check(record != null and record.to_data().player_cell == [2, 1], "detected DTO roundtrip")
	source.reliable_cells[0] = Vector2i(9, 9)
	_check(record.reliable_cells[0] == Vector2i(1, 1), "DTO input detached")
	var copied: ObservationRecord = record.snapshot_copy()
	copied.reliable_cells[0] = Vector2i(0, 0)
	_check(record.reliable_cells[0] == Vector2i(1, 1), "DTO copy detached")
	var encoded: Dictionary = record.to_data()
	encoded["actor_id"] = 0
	_check(ObservationRecord.from_data(encoded) == null, "visual actor identity rejected")
	encoded.erase("actor_id")
	encoded.player_cell = [4, 4]
	_check(ObservationRecord.from_data(encoded) == null, "player outside R rejected")
	encoded = record.to_data()
	encoded.reliable_cells = [[2, 1], [1, 1]]
	_check(ObservationRecord.from_data(encoded) == null, "unsorted R rejected")
	encoded = record.to_data()
	encoded.reliable_cells.append([2, 1])
	_check(ObservationRecord.from_data(encoded) == null, "duplicate R rejected")
	var plate_data: Dictionary = {"round_id": 1, "branch_id": 1, "guess_cycle_id": 1, "report_cycle_id": 1, "device_id": 3, "event_tick": 1, "cell": Vector2i(2, 2)}
	var plate: PlateActivationRecord = PlateActivationRecord.make(plate_data)
	_check(plate != null and plate.to_data().cell == [2, 2], "plate DTO roundtrip")
	plate_data["actor_id"] = 7
	_check(PlateActivationRecord.make(plate_data) == null, "anonymous plate rejects actor key")
	return true

func _buffer_atomicity() -> bool:
	var buffer := ReportBuffer.new(3)
	var base: Dictionary = {"round_id": 1, "branch_id": 1, "guess_cycle_id": 1, "report_cycle_id": 1, "device_id": 1, "sense_tick": 0, "result": "NOT_DETECTED", "reliable_cells": [Vector2i(1, 1)], "player_cell": null, "reason": ""}
	var first: ObservationRecord = ObservationRecord.make(base)
	base.sense_tick = 3
	var wrong: ObservationRecord = ObservationRecord.make(base)
	var records: Array[ObservationRecord] = [first, wrong]
	_check(not buffer.append_all(records, []) and buffer.pending_count() == 0, "append_all rejects whole invalid group")
	_check(buffer.append_visual(first), "valid first record accepted")
	_check(not buffer.append_visual(first) and buffer.pending_count() == 1, "duplicate visual tick rejected")
	_check(not buffer.append_visual(first) and buffer.pending_count() == 1, "duplicate visual tick rejected")
	base.sense_tick = 2
	var last: ObservationRecord = ObservationRecord.make(base)
	_check(buffer.append_visual(last), "tick two accepted")
	var activation: PlateActivationRecord = PlateActivationRecord.make({"round_id": 1, "branch_id": 1, "guess_cycle_id": 1, "report_cycle_id": 1, "device_id": 2, "event_tick": 1, "cell": Vector2i(2, 2)})
	_check(buffer.append_plate(activation), "plate record accepted")
	base.sense_tick = 3
	base.report_cycle_id = 2
	var next: ObservationRecord = ObservationRecord.make(base)
	_check(buffer.append_visual(next), "tick three belongs to second cycle")
	var before: Dictionary = buffer.snapshot()
	_check(buffer.seal(ReportBoundary.new(1, 1, 1, 2, 0, 3, false)) == null and buffer.snapshot() == before, "wrong boundary is atomic")
	var first_batch: SensingReportBatch = buffer.seal(ReportBoundary.new(1, 1, 1, 1, 0, 3, false))
	_check(first_batch != null and first_batch.records.size() == 3 and buffer.pending_count() == 1, "N=3 first seal excludes tick three")
	_check(first_batch.records.map(func(entry: Dictionary) -> String: return entry.record_type) == ["visual", "plate_activation", "visual"], "mixed batch keeps event chronology")
	var copied_batch: SensingReportBatch = first_batch.snapshot_copy()
	copied_batch.records[0].data.reliable_cells.clear()
	_check(first_batch.records[0].data.reliable_cells == [[1, 1]], "sealed batch copy is detached")
	_check(buffer.seal(ReportBoundary.new(1, 1, 1, 1, 0, 3, false)) == null, "duplicate seal rejected")
	_check(buffer.append_visual(first) == false, "late first-period record rejected")
	var copied: Dictionary = buffer.snapshot()
	copied.pending[0].data.report_cycle_id = 1
	_check(not buffer.restore(copied) and buffer.pending_count() == 1, "invalid restore is atomic")
	var restored := ReportBuffer.new(3)
	_check(restored.restore(buffer.snapshot()) and restored.pending_count() == 1, "valid snapshot restores")
	var second_batch: SensingReportBatch = restored.seal(ReportBoundary.new(1, 1, 2, 2, 3, 6, false))
	_check(second_batch != null and second_batch.records.size() == 1 and second_batch.records[0].data.guess_cycle_id == 1, "boundary tick retains earlier guess identity")
	var empty_batch: SensingReportBatch = restored.seal(ReportBoundary.new(1, 1, 2, 3, 6, 9, false))
	_check(empty_batch != null and empty_batch.records.is_empty(), "empty period still seals")
	return true

func _plate_entries() -> bool:
	var world: WorldState = _simple_world()
	world.player_position = Vector2(2.5, 1.5)
	world.registry._put({"id": 2, "kind": "pressure_plate", "cell": [2, 1], "parameters": {}, "runtime_state": {"occupants": [], "baseline_ready": false}})
	var robot: Dictionary = {"id": 3, "kind": "robot", "parameters": {"view_radius": 2.0}, "runtime_state": {"position": [2.5, 1.5]}}
	world.registry._put(robot)
	var previous: Dictionary = {0: Vector2i(1, 1), 3: Vector2i(1, 1)}
	var result: SensingStepResult = SensingKernel.step({}, previous, world, _context(1), 3)
	_check(result.succeeded() and result.plate_records.size() == 2, "two actors make two anonymous events")
	_check(result.plate_records[0].to_data() == result.plate_records[1].to_data(), "anonymous duplicates retained")
	previous = SensingKernel.actor_cells(world)
	result = SensingKernel.step(result.next_visual_states, previous, world, _context(2), 3)
	_check(result.succeeded() and result.plate_records.is_empty(), "staying on plate is silent")
	world.player_position = Vector2(1.5, 1.5)
	previous = {0: Vector2i(2, 1), 3: Vector2i(2, 1)}
	result = SensingKernel.step(result.next_visual_states, previous, world, _context(3), 3)
	_check(result.succeeded() and result.plate_records.is_empty(), "leaving plate is silent")
	return true

func _device_change_and_error() -> bool:
	var world: WorldState = _simple_world()
	var initial: SensingStepResult = SensingKernel.initialize_round(world, _context(0), 3)
	_check(initial.succeeded() and initial.visual_records.size() == 1, "initial camera emits")
	var copied: SensingStepResult = initial.snapshot_copy()
	copied.visual_records[0].reliable_cells.clear()
	_check(not initial.visual_records[0].reliable_cells.is_empty(), "step result copy is detached")
	world.registry._remove(1)
	var updated: SensingStepResult = SensingKernel.step(initial.next_visual_states, SensingKernel.actor_cells(world), world, _context(1), 3)
	_check(updated.succeeded() and updated.next_visual_states.is_empty(), "removed camera state dropped")
	var camera: Dictionary = {"id": 4, "kind": "camera", "cell": [1, 1], "parameters": {"enabled": false, "view_radius": 2.0, "fov_angle": TAU}, "runtime_state": {"heading": 0.0}}
	world.registry._put(camera)
	updated = SensingKernel.step(updated.next_visual_states, SensingKernel.actor_cells(world), world, _context(2), 3)
	_check(updated.succeeded() and updated.visual_records.size() == 1 and updated.visual_records[0].result == "UNDETERMINED", "new disabled camera emits unknown")
	var invalid: Dictionary = updated.next_visual_states.duplicate(true)
	invalid[4].last_evaluated_tick = 10
	var failed_step: SensingStepResult = SensingKernel.step(invalid, SensingKernel.actor_cells(world), world, _context(3), 3)
	_check(not failed_step.succeeded() and failed_step.visual_records.is_empty(), "invalid state has no partial records")
	return true

func _visual_transitions() -> bool:
	var world: WorldState = _simple_world()
	world.player_position = Vector2(2.0, 1.5)
	_check(SensingKernel.actor_cells(world)[0] == Vector2i(2, 1), "player grid boundary uses floor cell")
	world.player_position = Vector2(1.5, 1.5)
	var initial: SensingStepResult = SensingKernel.initialize_round(world, _context(0), 5)
	_check(initial.succeeded() and initial.visual_records[0].result == "DETECTED", "initial positive observation")
	world.player_position = Vector2(2.5, 1.5)
	var changed: SensingStepResult = SensingKernel.step(initial.next_visual_states, SensingKernel.actor_cells(world), world, {"round_id": 1, "branch_id": 1, "guess_cycle_id": 1, "report_cycle_id": 1, "sense_tick": 1}, 5)
	_check(changed.succeeded() and changed.visual_records.size() == 1 and changed.visual_records[0].player_cell == Vector2i(2, 1), "visible player changed cell")
	world.player_position = Vector2(3.5, 3.5)
	var lost: SensingStepResult = SensingKernel.step(changed.next_visual_states, SensingKernel.actor_cells(world), world, {"round_id": 1, "branch_id": 1, "guess_cycle_id": 1, "report_cycle_id": 1, "sense_tick": 2}, 5)
	_check(lost.succeeded() and lost.visual_records.size() == 1 and lost.visual_records[0].result == "NOT_DETECTED", "visible to absent emits full negative")
	var still_absent: SensingStepResult = SensingKernel.step(lost.next_visual_states, SensingKernel.actor_cells(world), world, {"round_id": 1, "branch_id": 1, "guess_cycle_id": 1, "report_cycle_id": 1, "sense_tick": 3}, 5)
	_check(still_absent.succeeded() and still_absent.visual_records.is_empty(), "continued absence does not repeat")
	var period_end: SensingStepResult = SensingKernel.step(still_absent.next_visual_states, SensingKernel.actor_cells(world), world, {"round_id": 1, "branch_id": 1, "guess_cycle_id": 1, "report_cycle_id": 1, "sense_tick": 4}, 5)
	_check(period_end.succeeded() and period_end.visual_records.size() == 1, "last atomic tick has full observation")
	return true

func _deployment_and_restore() -> bool:
	var world: WorldState = _simple_world()
	world.registry._put({"id": 2, "kind": "pressure_plate", "cell": [1, 1], "parameters": {}, "runtime_state": {"occupants": [], "baseline_ready": false}})
	var initial: SensingStepResult = SensingKernel.initialize_round(world, _context(0), 3)
	var previous: Dictionary = SensingKernel.actor_cells(world)
	var no_phantom: SensingStepResult = SensingKernel.step(initial.next_visual_states, previous, world, _context(1), 3)
	_check(no_phantom.succeeded() and no_phantom.plate_records.is_empty(), "plate deployed under player does not fire")
	world.player_position = Vector2(2.5, 1.5)
	var left: SensingStepResult = SensingKernel.step(no_phantom.next_visual_states, previous, world, _context(2), 3)
	_check(left.succeeded() and left.plate_records.is_empty(), "leaving deployed plate silent")
	previous = SensingKernel.actor_cells(world)
	world.player_position = Vector2(1.5, 1.5)
	var entered: SensingStepResult = SensingKernel.step(left.next_visual_states, previous, world, _context(3), 3)
	_check(entered.succeeded() and entered.plate_records.size() == 1, "first postdeployment entry fires")
	world.registry._put({"id": 3, "kind": "robot", "parameters": {"view_radius": 2.0}, "runtime_state": {"position": [1.5, 1.5]}})
	var after_addition: SensingStepResult = SensingKernel.step(entered.next_visual_states, SensingKernel.actor_cells(world), world, _context(4), 3)
	_check(after_addition.succeeded() and after_addition.plate_records.is_empty(), "new robot already on plate is not phantom entry")
	var restored: Dictionary = SensingKernel.restore_visual_states(after_addition.next_visual_states, world)
	if restored.ok:
		restored.states[1].last_evaluated_tick = 100
	_check(restored.ok and after_addition.next_visual_states[1].last_evaluated_tick == 4, "visual state restore is detached")
	var plain_states: Dictionary = {}
	for id: int in after_addition.next_visual_states:
		var state: Dictionary = after_addition.next_visual_states[id].duplicate(true)
		if state.visible_cell is Vector2i:
			state.visible_cell = [state.visible_cell.x, state.visible_cell.y]
		plain_states[str(id)] = state
	var restored_plain: Dictionary = SensingKernel.restore_visual_states(plain_states, world)
	_check(restored_plain.ok and restored_plain.states.has(1) and restored_plain.states[1].visible_cell is Vector2i, "plain visual snapshot restores")
	var invalid: Dictionary = after_addition.next_visual_states.duplicate(true)
	invalid[1].last_emitted_tick = 100
	_check(not SensingKernel.restore_visual_states(invalid, world).ok, "invalid visual state rejected")
	var wrong_context: Dictionary = _context(3)
	wrong_context.report_cycle_id = 1
	_check(not SensingKernel.step(entered.next_visual_states, SensingKernel.actor_cells(world), world, wrong_context, 3).succeeded(), "wrong period identity rejected")
	return true

func _same_cell_walk_and_copy() -> bool:
	var world: WorldState = _simple_world()
	var initial: SensingStepResult = SensingKernel.initialize_round(world, {"round_id": 1, "branch_id": 1, "guess_cycle_id": 1, "report_cycle_id": 1, "sense_tick": 0}, 5)
	var states: Dictionary = initial.next_visual_states
	var emitted: Array[int] = [0]
	for tick: int in range(1, 10):
		world.player_position = Vector2(1.2 + float(tick % 4) * 0.15, 1.2 + float(tick % 3) * 0.15)
		var result: SensingStepResult = SensingKernel.step(states, SensingKernel.actor_cells(world), world, {"round_id": 1, "branch_id": 1, "guess_cycle_id": 1, "report_cycle_id": tick / 5 + 1, "sense_tick": tick}, 5)
		_check(result.succeeded(), "same-cell walk tick %d accepted" % tick)
		if not result.visual_records.is_empty():
			emitted.append(tick)
		states = result.next_visual_states
	_check(emitted == [0, 4, 9], "same-cell walk only initial and batch ends")
	var buffer := ReportBuffer.new(5)
	var record: ObservationRecord = initial.visual_records[0]
	var original_r: Array = record.to_data().reliable_cells.duplicate(true)
	_check(buffer.append_visual(record), "initial record stored")
	record.reliable_cells.clear()
	var sealed: SensingReportBatch = buffer.seal(ReportBoundary.new(1, 1, 1, 1, 0, 5, false))
	_check(sealed != null and sealed.records[0].data.reliable_cells == original_r, "buffer keeps event-time R after source mutation")
	return true

func _context(tick: int) -> Dictionary:
	return {"round_id": 1, "branch_id": 1, "guess_cycle_id": 1, "report_cycle_id": tick / 3 + 1, "sense_tick": tick}

func _simple_world() -> WorldState:
	var world := WorldState.new()
	world.grid_size = Vector2i(4, 4)
	world.cell_size = 1.0
	world.origin = Vector2.ZERO
	world.player_position = Vector2(1.5, 1.5)
	for y: int in 4:
		world.terrain.append(["FLOOR", "FLOOR", "FLOOR", "FLOOR"])
	world.registry._put({"id": 1, "kind": "camera", "cell": [1, 1], "parameters": {"enabled": true, "view_radius": 2.0, "fov_angle": TAU}, "runtime_state": {"heading": 0.0}})
	return world
