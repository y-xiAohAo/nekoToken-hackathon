extends Node3D

signal cleared

const PLAYER := preload("res://player.gd")
const DISPLAY := preload("res://districts/morning_star/arena_display.gd")
const BOSS_VISUAL := preload("res://districts/morning_star/boss_visual.gd")
const HUD := preload("res://districts/morning_star/combat_hud.gd")
const TUNING := preload("res://districts/morning_star/combat_tuning.gd")
const AUDIO := preload("res://districts/morning_star/combat_audio.gd")
const DIRECTOR := preload("res://districts/morning_star/boss_director.gd")

const ARENA_RADIUS := 12.3
const BOSS_MAX := TUNING.BOSS_HEALTH
const PLAYER_MAX := TUNING.PLAYER_HEALTH
const PUNCH_DAMAGE := TUNING.PUNCH_DAMAGE
const MAX_PUNCHES_PER_OPENING := TUNING.PUNCHES_PER_OPENING
const WALL_ANGLE := TUNING.WALL_ANGLE
const WALL_SAFE := TUNING.WALL_SAFE
const DASH_WIDTH := TUNING.DASH_WIDTH
const PREDICT_RADIUS := TUNING.PREDICT_RADIUS
const DEFEAT_DURATION := TUNING.DEFEAT_TIME

enum Phase { INTRO, REPOSITION, WINDUP, STRIKE, LINK, RECOVER, SHIFT, DEFEAT, WON, LOST }
const Move := TUNING.Move

@export var encounter_music: AudioStream
var phase := Phase.INTRO
var tier := 1
var boss_health := BOSS_MAX
var player_health := PLAYER_MAX

var _player: PLAYER
var _theme: Theme
var _display: DISPLAY
var _boss: BOSS_VISUAL
var _hud: HUD
var _audio: AUDIO
var _director := DIRECTOR.new()
var _move: int = Move.WALL
var _phase_time := 0.0
var _clock := 0.0
var _cycle := 0
var _combo_step := 0
var _queued_move := -1
var _signature := false
var _signature_debut := false
var _recover_until := TUNING.RECOVERY_MIN
var _open_hits := 0
var _attack_hit := false
var _hit_flash := 0.0
var _hit_pause := 0.0
var _hit_direction := Vector2.ZERO
var _shake := 0.0
var _shake_time := 0.0
var _shake_axis := Vector2.RIGHT
var _wall_direction := 0.0
var _boss_ground := Vector2.ZERO
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _prediction := Vector2.ZERO

@onready var _spawn: Marker3D = $Markers/Spawn


func configure(player: PLAYER, theme: Theme) -> void:
	_player = player
	_theme = theme


func _ready() -> void:
	_display = DISPLAY.new()
	_display.name = "ArenaDisplay"
	add_child(_display)
	_display.build(ARENA_RADIUS)
	_boss = BOSS_VISUAL.new()
	_boss.name = "Boss"
	add_child(_boss)
	_boss.build()
	_hud = HUD.new()
	_hud.name = "CombatHUD"
	add_child(_hud)
	_hud.build(_theme, BOSS_MAX, PLAYER_MAX)
	_audio = AUDIO.new()
	_audio.name = "CombatAudio"
	add_child(_audio)
	_audio.build(encounter_music)
	if is_instance_valid(_player):
		_player.attack_contact.connect(_on_punch)
		_player.attack_swing.connect(_on_swing)
		_player.dodge_started.connect(_on_dodge)
		restart()
	else:
		# The room is also openable as a standalone scene for layout inspection.
		set_physics_process(false)


func _exit_tree() -> void:
	if is_instance_valid(_player) and _player.attack_contact.is_connected(_on_punch):
		_player.attack_contact.disconnect(_on_punch)
		_player.attack_swing.disconnect(_on_swing)
		_player.dodge_started.disconnect(_on_dodge)


func restart() -> void:
	phase = Phase.INTRO
	tier = 1
	_phase_time = 0.0
	_clock = 0.0
	_cycle = 0
	_combo_step = 0
	_queued_move = -1
	_signature = false
	_signature_debut = false
	_director.reset()
	_open_hits = 0
	_attack_hit = false
	_hit_flash = 0.0
	_hit_pause = 0.0
	_shake = 0.0
	_shake_time = 0.0
	_audio.stop_cues()
	_audio.start_music()
	_audio.play(AUDIO.Cue.LOCK)
	_boss_ground = Vector2.ZERO
	_boss.reset()
	_boss.update_live(_boss_ground, 0.0, 0.0, 0.0, 0.0, 0)
	_boss.reveal(0.0)
	_boss.reset_physics_interpolation()
	_display.clear_attack()
	_display.set_phase_tone(TUNING.STAGE_TINTS[0], 0.0)
	_display.effects.clear_feedback()
	_display.show_exit(false)
	boss_health = BOSS_MAX
	player_health = PLAYER_MAX
	_hud.set_health(boss_health, player_health, PLAYER_MAX)
	_hud.set_stage(1)
	_hud.set_opening(0.0)
	_hud.set_finished(false)
	_hud.set_message("投影正在接管")
	_player.controls_locked = false
	_player.set_combat_enabled(true)
	_player.facing = &"n"
	_player.spawn_position = _spawn.global_position
	_player.respawn()


func can_restart() -> bool:
	return phase != Phase.DEFEAT


func can_leave() -> bool:
	return phase != Phase.DEFEAT


func has_finished() -> bool:
	return phase == Phase.WON or phase == Phase.LOST


func victory_camera_weight() -> float:
	if phase == Phase.DEFEAT:
		return smoothstep(0.0, 0.88, _phase_time)
	return 1.0 if phase == Phase.WON else 0.0


func arrival_camera_weight() -> float:
	if phase != Phase.INTRO:
		return 0.0
	return 1.0 - smoothstep(0.06, TUNING.INTRO_TIME, _phase_time)


func victory_camera_target() -> Vector3:
	return Vector3(_boss_ground.x, 1.82, _boss_ground.y)


func camera_kick(delta: float, camera_basis: Basis) -> Vector3:
	_shake_time = maxf(0.0, _shake_time - delta)
	var fade := _shake_time / TUNING.SHAKE_DURATION
	var elapsed := TUNING.SHAKE_DURATION - _shake_time
	var kick := cos(elapsed * 89.0) * _shake * fade * fade
	return camera_basis.x * kick * _shake_axis.x + camera_basis.y * kick * _shake_axis.y * 0.63


func _physics_process(delta: float) -> void:
	if has_finished():
		return
	if _hit_pause > 0.0:
		_hit_pause = maxf(0.0, _hit_pause - delta)
		if _hit_pause < 0.00001:
			_hit_pause = 0.0
		return
	_phase_time += delta
	if phase == Phase.DEFEAT:
		_boss.update_defeat(_phase_time)
		var remainder := 1.0 - clampf(_phase_time / DEFEAT_DURATION, 0.0, 1.0)
		_display.set_phase_tone(TUNING.STAGE_TINTS[tier - 1].lerp(Color("#436f83"), 1.0 - remainder), remainder * 0.6)
		if _phase_time >= DEFEAT_DURATION:
			_finish_victory()
		return

	_clock += delta
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	var lean := 0.0
	var glow := 0.0
	match phase:
		Phase.INTRO:
			var intro := clampf(_phase_time / TUNING.INTRO_TIME, 0.0, 1.0)
			_boss.reveal(smoothstep(0.0, 0.76, intro))
			glow = 0.44 * sin(intro * PI)
			if intro >= 1.0:
				_start_reposition()
		Phase.REPOSITION:
			_boss_ground = _from.lerp(_to, smoothstep(0.0, TUNING.REPOSITION_TIME, _phase_time))
			lean = clampf(-(_to.x - _from.x) * 0.018, -0.10, 0.10)
			if _phase_time >= TUNING.REPOSITION_TIME:
				_choose_attack()
		Phase.WINDUP:
			var duration := TUNING.ECHO_WINDUP if _signature and _combo_step == 1 else TUNING.WINDUP[_move]
			var ratio := clampf(_phase_time / duration, 0.0, 1.0)
			glow = 0.18 + 0.74 * ratio
			_display.animate_warning(ratio)
			_display.effects.charge(Vector3(_boss_ground.x, 0, _boss_ground.y),
				TUNING.TELEGRAPH_TINTS[_move], ratio, _move)
			match _move:
				Move.WALL: lean = cos(_wall_direction) * ratio * 0.13
				Move.DASH: lean = signf(_to.x - _from.x) * ratio * 0.17
				Move.PREDICT: lean = sin(ratio * PI) * 0.05
				Move.PULSE: lean = sin(ratio * TAU) * 0.06
			if ratio >= 1.0:
				_start_strike()
		Phase.STRIKE:
			glow = 0.90
			lean = _advance_strike(clampf(_phase_time / TUNING.STRIKE[_move], 0.0, 1.0))
			if phase == Phase.STRIKE and _phase_time >= TUNING.STRIKE[_move]:
				_finish_attack()
		Phase.LINK:
			glow = 0.24
			if _phase_time >= TUNING.COMBO_BREATH:
				_start_windup(_queued_move)
		Phase.RECOVER:
			glow = 0.06
			lean = sin(_phase_time * 13.0) * maxf(0.0, 0.42 - _phase_time) * 0.21
			_hud.set_opening(1.0 - _phase_time / _recover_until if _open_hits < MAX_PUNCHES_PER_OPENING else 0.0)
			if _phase_time >= _recover_until:
				_cycle += 1
				var next_tier := _tier_for_health()
				if next_tier > tier:
					_start_stage(next_tier)
				else:
					_start_reposition()
		Phase.SHIFT:
			var shift := clampf(_phase_time / TUNING.PHASE_TRANSITION, 0.0, 1.0)
			glow = sin(shift * PI) * 0.97
			lean = sin(shift * TAU * 2.0) * (1.0 - shift) * 0.12
			if shift >= 1.0:
				_start_reposition()

	lean -= _hit_direction.x * (_hit_flash / 0.16) * 0.095
	_boss.update_live(_boss_ground, _clock, lean, glow, _hit_flash / 0.16, _severed_pairs())


func _start_reposition() -> void:
	phase = Phase.REPOSITION
	_phase_time = 0.0
	_from = _boss_ground
	_to = Vector2.ZERO
	if _cycle > 0:
		var player_at := _ground(_player.global_position)
		var bearing := player_at.angle() if player_at.length_squared() > 0.36 else _clock * 0.62
		var side := 1.0 if _cycle % 2 == 0 else -1.0
		_to = Vector2.from_angle(bearing + side * 0.87) * TUNING.ORBIT_RADIUS
	_hud.set_message("")
	_hud.set_opening(0.0)


func _choose_attack() -> void:
	var player_at := _ground(_player.global_position)
	var running := _ground(_player.get_real_velocity()).length() > 4.5
	var signature := tier == 3 and (not _signature_debut or _director.signature_ready(_clock))
	var next_move := Move.PREDICT if signature else _director.choose(tier, _clock, player_at, _boss_ground, running)
	if next_move < 0:
		return
	_signature = signature
	_combo_step = 0
	_queued_move = -1
	if _signature:
		_signature_debut = true
	_start_windup(next_move)


func _start_windup(move: int) -> void:
	phase = Phase.WINDUP
	_phase_time = 0.0
	_move = move
	_director.cast(_move, _clock, _signature and _combo_step == 0)
	var player_at := _ground(_player.global_position)
	match _move:
		Move.WALL:
			_wall_direction = player_at.angle() if player_at.length_squared() > 0.1 else PI / 2.0
			_display.mark_sector(_wall_direction, WALL_ANGLE, WALL_SAFE)
			_hud.set_message("投影墙扫掠")
		Move.DASH:
			_from = _boss_ground
			var aim := player_at - _from
			var direction := aim.normalized() if aim.length_squared() > 0.005 else Vector2.DOWN
			var boundary := ARENA_RADIUS - TUNING.DASH_WALL_MARGIN
			var projection := _from.dot(direction)
			var to_wall := sqrt(maxf(boundary * boundary - _from.length_squared() + projection * projection, 0.0))
			_to = _from + direction * minf(to_wall - projection,
				maxf(TUNING.DASH_MIN_LENGTH, aim.length() + TUNING.DASH_OVERSHOOT))
			_display.mark_dash(_from, _to, DASH_WIDTH)
			_hud.set_message("浮空冲刺")
		Move.PREDICT:
			_prediction = (player_at + _ground(_player.get_real_velocity()) * TUNING.PREDICT_LEAD).limit_length(ARENA_RADIUS - 0.8)
			var ghost_frame := _player.visual.sprite_frames.get_frame_texture(_player.visual.animation, _player.visual.frame)
			_display.mark_prediction(_prediction, PREDICT_RADIUS, ghost_frame)
			_hud.set_message("双重残影  %d / 2" % (_combo_step + 1) if _signature else "残影预判")
			_audio.play(AUDIO.Cue.LOCK)
		Move.PULSE:
			_display.mark_pulse(_boss_ground, TUNING.PULSE_RADIUS)
			_hud.set_message("芯片校准脉冲")


func _start_strike() -> void:
	phase = Phase.STRIKE
	_phase_time = 0.0
	_attack_hit = false
	_display.effects.end_charge()
	match _move:
		Move.WALL: _audio.play(AUDIO.Cue.WALL)
		Move.DASH: _audio.play(AUDIO.Cue.DASH)
		Move.PREDICT:
			_audio.play(AUDIO.Cue.BEAM)
			_display.strike_prediction(_prediction, PREDICT_RADIUS)
		Move.PULSE:
			_audio.play(AUDIO.Cue.PULSE)
			_display.effects.sparks(Vector3(_boss_ground.x, 0.42, _boss_ground.y),
				TUNING.TELEGRAPH_TINTS[_move], 16, 1.75, 0.29)
	_advance_strike(0.0)


func _finish_attack() -> void:
	var followup := -1
	if _combo_step == 0:
		if _signature:
			followup = Move.PREDICT
		elif tier >= 2:
			followup = _director.followup(_move, _clock, _ground(_player.global_position).distance_to(_boss_ground))
	if followup < 0:
		_start_recovery()
		return
	_queued_move = followup
	_combo_step = 1
	phase = Phase.LINK
	_phase_time = 0.0
	_display.clear_attack()
	_hud.set_message("残影正在重锁" if _signature else "晨星准备追击")


func _advance_strike(progress: float) -> float:
	var at := _ground(_player.global_position)
	match _move:
		Move.WALL:
			var front := lerpf(ARENA_RADIUS - 0.11, WALL_SAFE, progress)
			var back := minf(front + TUNING.WALL_DEPTH, ARENA_RADIUS)
			_display.sweep_sector(_wall_direction, WALL_ANGLE, front, back)
			var radius := at.length()
			if radius >= front - 0.07 and radius <= back and absf(angle_difference(_wall_direction, at.angle())) <= WALL_ANGLE:
				_hit_player(-at)
			return -cos(_wall_direction) * (1.0 - progress) * 0.12
		Move.DASH:
			var previous := _boss_ground
			_boss_ground = _from.lerp(_to, progress)
			var start_of_trail := _from.lerp(_to, maxf(0.0, progress - 0.34))
			_display.strike_dash(start_of_trail, _boss_ground, DASH_WIDTH)
			var closest := Geometry2D.get_closest_point_to_segment(at, previous, _boss_ground)
			if at.distance_squared_to(closest) <= DASH_WIDTH * DASH_WIDTH:
				_hit_player(_to - _from, 1.23)
			return signf(_from.x - _to.x) * 0.11
		Move.PREDICT:
			_display.fade_beam(progress)
			if at.distance_squared_to(_prediction) <= PREDICT_RADIUS * PREDICT_RADIUS:
				_hit_player(at - _prediction, 0.78)
		Move.PULSE:
			var outer := lerpf(0.26, TUNING.PULSE_RADIUS, progress)
			var inner := maxf(0.0, outer - TUNING.PULSE_THICKNESS)
			_display.strike_pulse(_boss_ground, inner, outer)
			var gap := at - _boss_ground
			if gap.length() >= inner and gap.length() <= outer:
				_hit_player(gap, 1.14)
			return sin(progress * PI) * 0.085
	return 0.0


func _hit_player(away: Vector2, push_scale := 1.0) -> void:
	if _attack_hit or not _player.can_take_combat_hit():
		return
	_attack_hit = true
	player_health -= 1
	_hud.set_health(boss_health, player_health, PLAYER_MAX)
	var push := away if not away.is_zero_approx() else Vector2.DOWN
	_player.take_combat_hit(Vector3(push.x, 0, push.y), push_scale)
	_impact(TUNING.HURT_STOP, TUNING.HURT_SHAKE, away)
	_audio.play(AUDIO.Cue.HURT)
	_display.effects.sparks(_player.global_position + Vector3.UP * 0.75,
		Color("#66e7ff"), 6, 0.76, 0.23)
	if player_health == 0:
		phase = Phase.LOST
		_player.controls_locked = true
		_player.call_deferred("set_combat_enabled", false)
		_display.clear_attack()
		_display.show_exit(true)
		_audio.finish_music()
		_hud.set_finished(true)
		_hud.set_opening(0.0)
		_hud.set_message("挑战失败")


func _start_recovery() -> void:
	phase = Phase.RECOVER
	_phase_time = 0.0
	_open_hits = 0
	var approach := maxf(0.0, _ground(_player.global_position).distance_to(_boss_ground) - TUNING.PUNCH_REACH)
	_recover_until = clampf(approach / _player.run_speed + TUNING.STREAK_PUNISH_ROOM,
		TUNING.RECOVERY_MIN, TUNING.RECOVERY_MAX)
	_display.clear_attack()
	_display.effects.sparks(Vector3(_boss_ground.x, 2.11, _boss_ground.y),
		TUNING.TELEGRAPH_TINTS[_move], 5, 0.62, 0.28)
	_hud.set_opening(1.0)
	_hud.set_message("露出破绽  ·  J 近身攻击")


func _tier_for_health() -> int:
	if boss_health <= TUNING.TIER_THREE_HP:
		return 3
	return 2 if boss_health <= TUNING.TIER_TWO_HP else 1


func _start_stage(next_tier: int) -> void:
	phase = Phase.SHIFT
	_phase_time = 0.0
	tier = next_tier
	_display.clear_attack()
	_hud.set_stage(tier)
	_hud.set_opening(0.0)
	var tone := TUNING.STAGE_TINTS[tier - 1]
	var at := Vector3(_boss_ground.x, 0.12, _boss_ground.y)
	_display.set_phase_tone(tone, float(tier - 1) * 0.48)
	_display.effects.ripple(at, tone, 4.25, TUNING.PHASE_TRANSITION)
	_display.effects.sparks(at + Vector3.UP * 2.35, tone, 18, 2.35, 0.61)
	_audio.play(AUDIO.Cue.SHIFT)
	_audio.set_music_tier(tier)
	_hud.set_message("阶段 %d  ·  %s" % [tier, "追击同步" if tier == 2 else "双重锁定"])


func _on_punch(origin: Vector3, direction: Vector3) -> void:
	var reach := _boss_ground - _ground(origin)
	if reach.length_squared() > TUNING.PUNCH_REACH * TUNING.PUNCH_REACH:
		return
	if reach.length_squared() > 0.16 and reach.normalized().dot(_ground(direction)) < TUNING.PUNCH_ARC_DOT:
		return
	_player.resolve_contact()
	var contact := Vector3(_boss_ground.x, 1.36, _boss_ground.y) - direction * 0.32
	var hit_axis := _ground(direction)
	if phase != Phase.RECOVER or _open_hits >= MAX_PUNCHES_PER_OPENING:
		if phase == Phase.INTRO or phase == Phase.SHIFT:
			_audio.play(AUDIO.Cue.IMMUNE)
			_display.effects.sparks(contact, Color("#8194ba"), 3, 0.44, 0.15)
		elif not has_finished() and phase != Phase.DEFEAT:
			_audio.play(AUDIO.Cue.GUARD)
			_display.effects.sparks(contact, Color("#74c7ff"), 5, 0.59, 0.17)
			_display.effects.ripple(contact - Vector3.UP * 1.25, Color("#77b9eb"), 0.85, 0.20)
			_impact(TUNING.GUARD_STOP, TUNING.GUARD_SHAKE, hit_axis)
		return
	var prior_pairs := _severed_pairs()
	_open_hits += 1
	boss_health = maxi(boss_health - PUNCH_DAMAGE, 0)
	_hit_flash = 0.16
	_hit_direction = hit_axis
	_hud.set_health(boss_health, player_health, PLAYER_MAX)
	var heavy := boss_health == 0 or _severed_pairs() > prior_pairs
	_audio.play(AUDIO.Cue.BREAK if heavy else AUDIO.Cue.HIT)
	_display.effects.sparks(contact, Color("#ffd480"), 14 if heavy else 8,
		1.32 if heavy else 0.87, 0.33 if heavy else 0.25)
	if heavy:
		_display.effects.ripple(contact - Vector3.UP * 1.26, Color("#ffcf8a"), 1.8, 0.33)
	_impact(TUNING.BREAK_STOP if heavy else TUNING.HIT_STOP,
		TUNING.BREAK_SHAKE if heavy else TUNING.HIT_SHAKE, hit_axis)
	if boss_health == 0:
		phase = Phase.DEFEAT
		_phase_time = 0.0
		_player.controls_locked = true
		_player.call_deferred("set_combat_enabled", false)
		_display.clear_attack()
		_boss.begin_defeat()
		_audio.finish_music()
		_hud.begin_cinematic()
		_hud.set_message("")
	elif _severed_pairs() > prior_pairs:
		_hud.set_message("一对连接熄灭")
	elif _open_hits == MAX_PUNCHES_PER_OPENING:
		_hud.set_message("护盾正在恢复")


func _severed_pairs() -> int:
	var hits_for_pair := PUNCH_DAMAGE * MAX_PUNCHES_PER_OPENING
	# The final pair breaks in the defeat animation, even with a higher max HP.
	return mini(2, floori(float(BOSS_MAX - boss_health) / hits_for_pair))


func _on_swing(origin: Vector3, direction: Vector3) -> void:
	_display.effects.punch(origin, direction)
	_audio.play(AUDIO.Cue.SWING)


func _on_dodge(_direction: Vector3) -> void:
	_display.effects.begin_dodge(_player.visual)
	_audio.play(AUDIO.Cue.DODGE)


func _impact(stop: float, strength: float, axis: Vector2) -> void:
	_hit_pause = maxf(_hit_pause, stop)
	_player.pause_combat(stop)
	_shake = minf(strength, TUNING.MAX_SHAKE)
	_shake_time = TUNING.SHAKE_DURATION
	_shake_axis = Vector2(axis.x, -axis.y).normalized() if not axis.is_zero_approx() else Vector2.RIGHT


func _finish_victory() -> void:
	phase = Phase.WON
	_display.show_exit(true)
	_hud.set_finished(true)
	_hud.set_message("隐藏关完成  ·  控制已解除")
	_audio.play(AUDIO.Cue.WIN)
	cleared.emit()


func _ground(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)
