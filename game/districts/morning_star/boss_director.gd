extends RefCounted

const TUNE := preload("res://districts/morning_star/combat_tuning.gd")
const Move := TUNE.Move

var _can_cast_at := PackedFloat32Array([0, 0, 0, 0])
var _recent := PackedInt32Array()
var _signature_at := 0.0


func reset() -> void:
	_can_cast_at.fill(0.0)
	_recent.clear()
	_signature_at = 0.0


func choose(tier: int, now: float, player: Vector2, boss: Vector2, running: bool) -> int:
	if _recent.is_empty():
		return Move.WALL
	var gap := player.distance_to(boss)
	var rim := smoothstep(6.5, 10.5, player.length())
	var scores := PackedFloat32Array([
		2.2 + rim * 5.4,
		1.4 + smoothstep(2.5, 8.5, gap) * 4.6 + (1.0 - rim) * 0.45,
		2.0 + (2.3 if running else 0.0) + smoothstep(3.0, 9.0, gap) * 1.4,
		1.5 + (1.0 - smoothstep(2.3, 5.5, gap)) * 5.2,
	])
	var best := -1
	var score := -INF
	var move_count := Move.size() if tier >= 2 else Move.PULSE
	for index in range(move_count):
		if not _ready(index, now):
			continue
		var recent_penalty := 6.0 if _recent[-1] == index else (1.1 if index in _recent else 0.0)
		var weight := scores[index] - recent_penalty
		if weight > score:
			score = weight
			best = index
	return best


func followup(move: int, now: float, player_gap: float) -> int:
	var best := Move.PREDICT
	match move:
		Move.PULSE: best = Move.DASH
		Move.DASH: best = Move.PREDICT
		Move.PREDICT: best = Move.PULSE if player_gap < TUNE.PULSE_RADIUS else Move.WALL
		Move.WALL: best = Move.PULSE if player_gap < TUNE.PULSE_RADIUS else Move.PREDICT
	return best if _ready(best, now) and best != _last_move() else -1


func signature_ready(now: float) -> bool:
	return now >= _signature_at and _last_move() != Move.PREDICT and _ready(Move.PREDICT, now)


func cast(move: int, now: float, signature: bool) -> void:
	_can_cast_at[move] = now + TUNE.SKILL_COOLDOWN[move]
	_recent.append(move)
	if _recent.size() > 2:
		_recent.remove_at(0)
	if signature:
		_signature_at = now + TUNE.SIGNATURE_COOLDOWN


func _ready(move: int, now: float) -> bool:
	return now >= _can_cast_at[move]


func _last_move() -> int:
	return -1 if _recent.is_empty() else _recent[-1]
