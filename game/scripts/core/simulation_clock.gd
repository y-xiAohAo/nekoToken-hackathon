extends RefCounted
class_name SimulationClock


var tick: int = 0


func advance_one_tick() -> int:
	tick += 1
	return tick


func snapshot() -> Dictionary:
	return {"tick": tick}
