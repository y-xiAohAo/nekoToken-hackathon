extends RefCounted
class_name WorldSyncAdapter
## Data-only adapter. Future scene adapters must stage work without side effects.


func prepare(_previous: Dictionary, _candidate: Dictionary, changes: Dictionary) -> Dictionary:
	return {"ok": true, "prepared": changes.duplicate(true), "errors": []}


func activate(_prepared: Dictionary) -> bool:
	return true
