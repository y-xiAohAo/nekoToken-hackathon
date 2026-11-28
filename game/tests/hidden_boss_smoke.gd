extends SceneTree

const ARENA := preload("res://districts/morning_star/arena.gd")
const TUNE := preload("res://districts/morning_star/combat_tuning.gd")
const DIRECTOR := preload("res://districts/morning_star/boss_director.gd")
const WORLD := preload("res://world2.tscn")

var _passed := 0
var _failed := 0
var _scratch: String


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_scratch = ProjectSettings.globalize_path("res://.godot/hidden-smoke-%d.cfg" % OS.get_process_id())
	if not await _check_chapter_progress():
		_finish("chapter progression did not complete")
		return
	var world = WORLD.instantiate()
	world._save_path = _scratch
	root.add_child(world)
	await process_frame
	await _frames(4)
	_check(world.collected.size() == 9 and world._guian_cleared(), "chapter completion survives reloading the collection")
	_check(_maps_to(KEY_J, &"combat_attack") and _maps_to(KEY_K, &"combat_dodge"), "physical J and K bindings")
	_check_director()

	await _tap(KEY_2)
	var town := world.map_mount.get_node_or_null("TomorrowTown") as Node3D
	if town == null:
		_finish("did not enter Tomorrow Town (map %s, dialog open %s, mounted %s)" % [
			world.map_index, world._ui.is_open(), world.map_mount.get_children()])
		return
	await _check_town_security(town)
	var gate := town.get_node("Markers/HiddenGate") as Marker3D
	_check(not gate.visible, "portal invisible with nine unique items")
	world.player.move_to(gate.global_position + Vector3.UP * 0.04)
	await _frames(7)
	await _tap(KEY_E)
	_check(world.map_index == 1 and world._nearby != gate, "locked portal cannot be used")

	var tenth := town.get_node("Markers/town_blocks") as Marker3D
	world.player.move_to(tenth.global_position + Vector3.UP * 0.06)
	await _frames(7)
	await _tap(KEY_E)
	_check(world.collected.size() == 10 and world.collected.has("town_blocks"), "E collects the tenth item")
	_check(gate.visible, "office portal unlocks immediately")
	await _tap(KEY_ESCAPE)
	await _tap(KEY_E)
	_check(world.collected.size() == 10, "reopening a collected prop does not increment the total")
	await _tap(KEY_ESCAPE)
	world.player.move_to(gate.global_position + Vector3(0, 0.06, 0.85))
	await _frames(7)
	_check(world._nearby == gate, "portal offers an E prompt on the office floor")
	await _tap(KEY_E)
	var arena := world.map_mount.get_child(0) as ARENA
	if arena == null:
		_finish("did not enter arena through the office portal")
		return
	_check(world.map_index == 2 and world.player.combat_enabled, "entered hidden map with combat enabled")
	_check(arena.boss_health == 140 and arena.player_health == 5, "combat starts at full health")
	_check(arena._audio._bed.playing and arena._audio._rhythm.playing, "both battle music layers start")
	var player = world.player

	await _frames(60)
	_check(is_equal_approx(world.camera.size, 13.8), "arena zooms in after the entrance shot")
	var camera_start: Vector3 = world.camera.global_position
	var before: Vector3 = player.global_position
	Input.action_press(&"move_right")
	await _frames(8)
	Input.action_release(&"move_right")
	var walk: float = player.global_position.x - before.x
	before = player.global_position
	Input.action_press(&"move_right")
	Input.action_press(&"sprint")
	await _frames(8)
	Input.action_release(&"move_right")
	Input.action_release(&"sprint")
	_check(player.global_position.x - before.x > walk * 1.3 and walk > 0.27, "Shift increases WASD speed")
	_check(world.camera.global_position.x - camera_start.x > 0.40, "camera follows horizontal movement")

	before = player.global_position
	Input.action_press(&"move_right")
	await _tap(KEY_K)
	Input.action_release(&"move_right")
	_check(player.visual.animation == &"dodge_side" and player.dodge_protects(), "K plays dodge with protection")
	await _frames(20)
	_check(player.global_position.x - before.x >= 1.65 and not player.dodge_protects(),
		"dodge has short displacement and protection expires")
	var in_view: Vector2 = world.camera.unproject_position(player.global_position)
	_check(absf(in_view.x - world.get_viewport().get_visible_rect().size.x * 0.5) < 64.0,
		"dodge keeps William inside the close framing")
	await _tap(KEY_R)
	_check(arena.phase == ARENA.Phase.INTRO and player.global_position.z > 8, "R restarts from entry")
	await _check_cancels(player)
	await _tap(KEY_R)

	await _point_at_and_punch(player, Vector2.ZERO, true, arena._display.effects)
	_check(arena.boss_health == ARENA.BOSS_MAX, "punches cannot damage a closed shield")
	player.move_to(Vector3(0, 0.04, 8.7))
	_check(await _wait_phase(arena, ARENA.Phase.STRIKE), "wall sweep begins")
	await _frames(5)
	_check(arena._display._sweep_crest.visible, "wall strike draws a moving projection crest")
	_check(await _wait_phase(arena, ARENA.Phase.RECOVER), "wall attack reaches a recovery phase")
	_check(arena._move == ARENA.Move.WALL and arena.player_health == 4, "wall sweep damages a player in its sector")
	_check(not arena._display._sweep_crest.visible, "wall strike effect clears during recovery")

	await _point_at_and_punch(player, arena._boss_ground, false)
	_check(arena.boss_health == ARENA.BOSS_MAX, "punch facing away misses")
	await _point_at_and_punch(player, arena._boss_ground, true)
	await _point_at_and_punch(player, arena._boss_ground, true)
	_check(arena.boss_health == ARENA.BOSS_MAX - 2 * ARENA.PUNCH_DAMAGE, "two normal J punches deal 40 damage")
	await _point_at_and_punch(player, arena._boss_ground, true)
	_check(arena.boss_health == ARENA.BOSS_MAX - 2 * ARENA.PUNCH_DAMAGE, "each recovery accepts at most two hits")

	player.move_to(Vector3(6, 0.04, 4))
	_check(await _wait_phase(arena, ARENA.Phase.SHIFT) and arena.tier == 2, "first cable pair introduces tier two")
	_check(arena._hud._stage == 2, "HUD follows the actual phase transition")
	_check(await _wait_phase(arena, ARENA.Phase.WINDUP), "dash telegraphs before moving")
	_check(arena._move == ARENA.Move.DASH, "a distant stationary target invites the dash")
	var hype := arena._boss.get_node("Airborne/Hype") as Sprite3D
	var morning := arena._boss.get_node("Airborne/MorningStar") as Sprite3D
	before = hype.global_position
	Input.action_press(&"move_right")
	await _tap(KEY_K)
	Input.action_release(&"move_right")
	_check(await _wait_phase(arena, ARENA.Phase.STRIKE), "dash begins after its telegraph")
	await _frames(8)
	_check(arena._display.effects._dash_lines[0].visible, "dash draws elevated motion lines")
	_check(await _wait_phase(arena, ARENA.Phase.LINK), "dash can lead into a separately warned followup")
	_check(hype.global_position.distance_to(before) > 4.0 and hype.get_parent() == morning.get_parent()
		and hype.position.is_equal_approx(morning.position) and hype.global_position.y > 0.25,
		"Morning Star and Hype share the same airborne dash")
	_check(arena.player_health == 4, "side step clears the dash lane")
	_check(await _wait_phase(arena, ARENA.Phase.WINDUP) and arena._move == ARENA.Move.PREDICT,
		"tier two dash links into a prediction")
	Input.action_press(&"move_left")
	await _tap(KEY_K)
	Input.action_release(&"move_left")
	_check(await _wait_phase(arena, ARENA.Phase.RECOVER), "combo has a recovery window")
	_check(arena._hud._opening.visible, "counterattack timer is shown when the shield opens")
	await _point_at_and_punch(player, arena._boss_ground, true)
	await _point_at_and_punch(player, arena._boss_ground, true)
	_check(arena.boss_health == ARENA.BOSS_MAX - 4 * ARENA.PUNCH_DAMAGE, "second opening damages the same boss")

	player.move_to(Vector3(1, 0.04, 6))
	_check(await _wait_phase(arena, ARENA.Phase.SHIFT) and arena.tier == 3, "second cable pair introduces the final tier")
	_check(await _wait_phase(arena, ARENA.Phase.WINDUP), "prediction gets its own windup")
	_check(arena._move == ARENA.Move.PREDICT and arena._signature and arena._display._ghost.visible,
		"final tier debuts with dual prediction")
	var first_lock := arena._prediction
	Input.action_press(&"move_right")
	await _tap(KEY_K)
	Input.action_release(&"move_right")
	_check(await _wait_phase(arena, ARENA.Phase.STRIKE), "prediction beam begins")
	_check(arena._display._beam.visible and not arena._display._ghost.visible, "beam replaces ghost")
	_check(arena._display.effects._beam_rings[0].visible, "prediction beam adds a visible shock ring")
	_check(await _wait_phase(arena, ARENA.Phase.LINK), "first beam clears before the second lock")
	_check(await _wait_phase(arena, ARENA.Phase.WINDUP)
		and arena._prediction.distance_to(first_lock) > 1.0, "second lock resamples player position")
	Input.action_press(&"move_left")
	await _tap(KEY_K)
	Input.action_release(&"move_left")
	_check(await _wait_phase(arena, ARENA.Phase.RECOVER), "prediction has a counterattack window")
	_check(arena.player_health == 4, "changing direction evades the locked beam")

	await _point_at_and_punch(player, arena._boss_ground, true)
	await _point_at_and_punch(player, arena._boss_ground, true)
	_check(arena.boss_health == ARENA.PUNCH_DAMAGE and arena._severed_pairs() == 2,
		"another hit is needed and the last pair stays connected")
	player.move_to(Vector3(0, 0.04, 0))
	_check(await _wait_phase(arena, ARENA.Phase.WINDUP), "boss launches a fourth attack")
	_check(await _wait_phase(arena, ARENA.Phase.RECOVER), "fourth attack exposes the final opening")
	await _point_at_and_punch(player, arena._boss_ground, true)
	_check(arena.boss_health == 0 and arena.phase == ARENA.Phase.DEFEAT, "last punch triggers defeat scene")
	await _frames(25)
	_check(arena._boss._kneel.visible and arena._boss._projection.visible, "Hype kneels while the projection is still dissolving")
	_check(await _wait_phase(arena, ARENA.Phase.WON), "defeat animation completes")
	_check(arena._boss._kneel.visible and not arena._boss._projection.visible, "Morning Star is gone and Hype stays kneeling")
	_check(is_equal_approx(world.camera.size, 11.2), "victory hands framing to the boss close-up")
	_check(not arena._audio._bed.playing and not arena._audio._rhythm.playing, "battle music fades before victory")
	var progress := ConfigFile.new()
	_check(world.hidden_cleared and progress.load(_scratch) == OK
		and progress.get_value("hidden_stage", "cleared", false) and world.collected.size() == 10,
		"victory saves without changing the collection")
	await _tap(KEY_E)
	_check(world.map_index == 1 and not player.combat_enabled and player.global_position.y > 2.65,
		"E returns to the upstairs office with combat disabled")

	world.player.move_to(gate.global_position + Vector3(0, 0.06, 0.85))
	await _frames(6)
	await _tap(KEY_E)
	arena = world.map_mount.get_child(0) as ARENA
	if arena == null:
		_finish("could not replay unlocked room")
		return
	arena._start_windup(ARENA.Move.PULSE)
	player.move_to(Vector3(2.8, 0.04, 0.0))
	_check(await _wait_phase(arena, ARENA.Phase.STRIKE), "chip pulse has its own visible windup")
	_check(await _wait_phase(arena, ARENA.Phase.RECOVER) and arena.player_health == 4,
		"chip pulse expands across and damages within the marked circle once")
	await _tap(KEY_R)
	arena.player_health = 1
	_check(await _wait_phase(arena, ARENA.Phase.LOST), "last damage enters failure state")
	await _tap(KEY_R)
	_check(arena.player_health == 5 and arena.boss_health == ARENA.BOSS_MAX and not player.controls_locked,
		"R restores both health bars and controls after failure")

	player.move_to(Vector3(ARENA.ARENA_RADIUS - 1.0, 0.04, 0))
	Input.action_press(&"move_right")
	Input.action_press(&"sprint")
	await _frames(35)
	Input.action_release(&"move_right")
	Input.action_release(&"sprint")
	_check(player.global_position.x < ARENA.ARENA_RADIUS and player.is_on_floor(), "holographic boundary holds at sprint speed")
	await _tap(KEY_ESCAPE)
	_check(world.map_index == 1, "Escape exits an active rematch")
	_finish()


func _check_chapter_progress() -> bool:
	var receipt_id := "hospital_receipt"
	var recording_id := "usb_airship_audio"
	var items: Array = JSON.parse_string(FileAccess.get_file_as_string("res://props/props.json"))
	var ids: Array[String] = []
	for item in items:
		if item.id not in ["town_blocks", receipt_id, recording_id] and ids.size() < 7:
			ids.append(item.id)
	var old_save := ConfigFile.new()
	old_save.set_value("collection", "items", ids)
	if old_save.save(_scratch) != OK:
		return false

	var world = WORLD.instantiate()
	world._save_path = _scratch
	root.add_child(world)
	await _frames(4)
	_check(world.collected.size() == 7 and not world._guian_cleared() and not world.hidden_cleared,
		"legacy save keeps items and starts the first chapter without the two clues")
	await _check_guian_watch(world.map_mount.get_node("Guian"))
	await _tap(KEY_2)
	_check(world.map_index == 0 and world._ui.is_open(), "map shortcut stays in Guian and shows the chapter goal")
	await _tap(KEY_ESCAPE)
	var markers: Node3D = world.map_mount.get_node("Guian/Markers")
	var exit := markers.get_node("Portal") as Marker3D
	await _visit_marker(world, exit)
	_check(world.map_index == 0 and world._ui.is_open(), "the south exit uses the same chapter gate")
	await _tap(KEY_ESCAPE)
	await _visit_marker(world, markers.get_node(receipt_id) as Marker3D)
	_check(world.collected.has(receipt_id) and not world._guian_cleared(), "the first clue alone is insufficient")
	await _tap(KEY_ESCAPE)
	await _visit_marker(world, markers.get_node(recording_id) as Marker3D)
	_check(world.collected.size() == 9 and world._guian_cleared(), "the second clue clears chapter one")
	await _tap(KEY_ESCAPE)
	await _visit_marker(world, exit)
	var reached_town: bool = world.map_index == 1
	_check(reached_town, "the south exit opens after chapter one is cleared")
	if reached_town:
		var town_exit: Marker3D = world.map_mount.get_node("TomorrowTown/Markers/Portal")
		await _visit_marker(world, town_exit)
		_check(world.map_index == 0 and world._guian_cleared(), "returning to Guian preserves chapter completion")
	world.queue_free()
	await process_frame
	return reached_town


func _visit_marker(world, marker: Marker3D) -> void:
	world.player.move_to(marker.global_position + Vector3.UP * 0.06)
	await _frames(7)
	await _tap(KEY_E)


func _check_guian_watch(guian: Node3D) -> void:
	var lookout := guian.get_node_or_null("WatchNPCs/ResidentLookout") as Node3D
	var patroller := guian.get_node_or_null("WatchNPCs/StreetPatroller") as Node3D
	_check(lookout != null and patroller != null, "Guian loads its lookout and street patroller")
	if lookout == null or patroller == null:
		return
	var lookout_start := lookout.global_position
	var patrol_start := patroller.global_position
	await _frames(30)
	_check(lookout.global_position.is_equal_approx(lookout_start), "Guian lookout stays at the entrance")
	_check(patroller.global_position.x > patrol_start.x + 0.5, "Guian street patroller moves along the plaza")
	var sprite := patroller.get_node("Visual") as Sprite3D
	var atlas := sprite.texture as AtlasTexture
	var frame := atlas.region.position.x
	await _frames(12)
	_check(atlas.atlas.resource_path.ends_with("street_patroller_walk.png") and frame != atlas.region.position.x,
		"Guian street patroller plays its walking animation")


func _check_town_security(town: Node3D) -> void:
	var robot := town.get_node_or_null("SecurityUnits/PlazaPatrol") as Node3D
	var camera := town.get_node_or_null("SecurityUnits/VossEntryCamera/Swivel") as Node3D
	_check(robot != null and camera != null, "Tomorrow Town mounts the plaza robot and Voss camera")
	if robot == null or camera == null:
		return
	var robot_start := robot.global_position
	var camera_yaw := camera.rotation.y
	await _frames(26)
	_check(robot.global_position.distance_to(robot_start) > 0.2, "Tomorrow Town's robot moves on the plaza patrol route")
	_check(not is_equal_approx(camera_yaw, camera.rotation.y), "Tomorrow Town's security camera keeps scanning")


func _check_director() -> void:
	var brain := DIRECTOR.new()
	_check(brain.choose(1, 0, Vector2.ZERO, Vector2.ZERO, false) == ARENA.Move.WALL, "fixed teaching opener")
	brain.cast(ARENA.Move.WALL, 0.0, false)
	_check(brain.choose(1, 0.1, Vector2(0, 11), Vector2.ZERO, false) != ARENA.Move.WALL, "wall cooldown prevents immediate reuse")
	_check(brain.choose(2, 5.0, Vector2(1.5, 0), Vector2.ZERO, false) == ARENA.Move.PULSE, "director reads close distance")
	brain.cast(ARENA.Move.PULSE, 5.0, false)
	_check(brain.choose(2, 9.0, Vector2(0, 11), Vector2.ZERO, false) == ARENA.Move.WALL, "director reads arena rim")


func _check_cancels(player) -> void:
	Input.action_press(&"move_right")
	await _tap(KEY_J)
	await _tap(KEY_K)
	_check(player.visual.animation == &"punch_side", "early K preserves punch commitment")
	await _frames(5)
	_check(player.visual.animation == &"dodge_side" and player.dodge_protects(), "buffered K executes at the recovery cancel")
	await _frames(5)
	await _tap(KEY_J)
	await _frames(6)
	_check(player.visual.animation == &"punch_side", "buffered J executes at the end of dodge")
	Input.action_release(&"move_right")
	await _frames(22)
	var press := InputEventKey.new()
	press.physical_keycode = KEY_J
	press.pressed = true
	var release := InputEventKey.new()
	release.physical_keycode = KEY_J
	Input.parse_input_event(press)
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await _frames(3)
	_check(String(player.visual.animation).begins_with("punch_"), "press and release between ticks still queues J")


func _point_at_and_punch(player, at: Vector2, toward: bool, inspect_effect: Node3D = null) -> void:
	var outside := 1.12 if at.x > ARENA.ARENA_RADIUS - 2.3 else -1.12
	player.move_to(Vector3(at.x + outside, 0.04, at.y))
	await _frames(3)
	var right := (outside < 0.0) == toward
	var key := &"move_right" if right else &"move_left"
	Input.action_press(key)
	await _tap(KEY_J)
	Input.action_release(key)
	await _frames(6)
	if inspect_effect != null:
		_check(inspect_effect.get_node("CombatFeedback").get_child_count() > 0,
			"punch wind appears on the contact frame even when blocked")
	await _frames(18)


func _wait_phase(arena: ARENA, target: ARENA.Phase) -> bool:
	for _tick in range(410):
		if arena.phase == target:
			return true
		await physics_frame
	return false


func _maps_to(key: Key, action: StringName) -> bool:
	var event := InputEventKey.new()
	event.physical_keycode = key
	return InputMap.event_is_action(event, action)


func _tap(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frames(3)
	var release := InputEventKey.new()
	release.physical_keycode = key
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await _frames(1)


func _frames(ticks: int) -> void:
	for _tick in range(ticks):
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + message)


func _finish(error := "") -> void:
	if not error.is_empty():
		_check(false, error)
	if FileAccess.file_exists(_scratch):
		DirAccess.remove_absolute(_scratch)
	print("hidden boss smoke: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
