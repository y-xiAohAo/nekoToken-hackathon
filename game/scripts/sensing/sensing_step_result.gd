extends RefCounted
class_name SensingStepResult
## Pure candidate result. A runtime coordinator decides whether to publish it.

var next_visual_states: Dictionary = {}
var visual_records: Array[ObservationRecord] = []
var plate_records: Array[PlateActivationRecord] = []
var errors: Array[Dictionary] = []

func succeeded() -> bool:
	return errors.is_empty()

func snapshot_copy() -> SensingStepResult:
	var copy := SensingStepResult.new()
	copy.next_visual_states = next_visual_states.duplicate(true)
	copy.errors.assign(errors.duplicate(true))
	for record: ObservationRecord in visual_records:
		copy.visual_records.append(record.snapshot_copy())
	for record: PlateActivationRecord in plate_records:
		copy.plate_records.append(record.snapshot_copy())
	return copy
