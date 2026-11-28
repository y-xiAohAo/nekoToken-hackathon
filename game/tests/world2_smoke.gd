extends SceneTree

var passed := 0
var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("FAIL: " + label)


func _run() -> void:
	var packed := load("res://world2.tscn") as PackedScene
	if packed == null:
		push_error("Cannot load the prototype scene")
		quit(1)
		return

	var world = packed.instantiate()
	var args := OS.get_cmdline_user_args()
	var base := args[0] if not args.is_empty() else ProjectSettings.globalize_path("res://.godot")
	world._save_path = base.path_join("world2_smoke_%d.cfg" % OS.get_process_id())
	root.add_child(world)
	await _frames(4)

	var guian := world.get_node("MapMount/Guian") as Node3D
	var units := get_nodes_in_group("world2_units")
	_check(guian.get_node("Ground").get_child_count() == 468, "Guian 26 x 18 ground tiles")
	_check(units.size() >= 804, "Guian modular pieces")
	_check(_uses_guian_textures(units), "Guian generated geometry and all 20 surface textures")
	_check(world.props.size() == 15, "15 canonical props")
	_check(_target_names(world._targets, "npc_") == ["npc_jasper"], "Guian active NPC")
	var watch := guian.get_node("WatchNPCs")
	var lookout := watch.get_node("ResidentLookout") as Node3D
	var patroller := watch.get_node("StreetPatroller") as Node3D
	_check(watch.get_child_count() == 2, "Guian has one lookout and one street patrol")
	var lookout_position := lookout.global_position
	var patrol_position := patroller.global_position
	await _frames(30)
	_check(lookout.global_position.is_equal_approx(lookout_position), "Guian lookout keeps its post")
	_check(patroller.global_position.x > patrol_position.x + 0.5
		and is_equal_approx(patroller.global_position.z, patrol_position.z), "Guian NPC starts its straight patrol")
	var patrol_visual := patroller.get_node("Visual") as Sprite3D
	var patrol_atlas := patrol_visual.texture as AtlasTexture
	var frame_x := patrol_atlas.region.position.x
	await _frames(12)
	_check(patrol_atlas.atlas.resource_path.ends_with("street_patroller_walk.png")
		and patrol_atlas.region.position.x != frame_x, "Guian NPC cycles through walk frames")
	for id in world.props:
		_check(world._prop_texture(id) is Texture2D, "imported image for " + id)

	var space := guian.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(23, 0.8, 16.5), Vector3(23, 0.8, -16.5))
	_check(space.intersect_ray(query).is_empty(), "Guian east corridor through route")

	await _climb(world.player, Vector3(-11, 0.03, -4.6), -13.34, "Guian home stairs")
	await _open_prop(world, "photo_2026")
	await _open_prop(world, "hospital_receipt")
	await _open_prop(world, "usb_airship_audio")

	world._switch_map(1)
	await _frames(4)
	var town := world.get_node("MapMount/TomorrowTown") as Node3D
	_check(town.get_node("Ground").get_child_count() == 468, "Tomorrow Town 26 x 18 ground tiles")
	_check(_target_names(world._targets, "npc_") == ["npc_carl", "npc_eileen", "npc_morning_star"],
		"Tomorrow Town active NPCs")
	await _climb(world.player, Vector3(-23, 0.03, -3.8), -13.0, "mayor office stairs")
	await _climb(world.player, Vector3(20, 0.03, -3.8), -13.0, "Voss stairs")
	await _open_prop(world, "tomorrow_badge")
	var guard := town.get_node("SecurityUnits/VossEntryCamera/Swivel") as Node3D
	var robot := town.get_node("SecurityUnits/PlazaPatrol") as Node3D
	var yaw := guard.rotation.y
	var position := robot.global_position
	await _frames(24)
	_check(not is_equal_approx(guard.rotation.y, yaw), "security camera scans")
	_check(robot.global_position.distance_to(position) > 0.2, "robot moves on patrol")
	_check(is_equal_approx(robot.global_position.z, position.z), "robot stays on its line")
	_check(robot.get_node("Chassis/SensorBand").mesh is CylinderMesh, "robot has round sensor band")
	world._switch_map(0)
	_check(world.collected.size() == 4, "collection survives map changes")
	var save := ConfigFile.new()
	_check(save.load(world._save_path) == OK, "collection saved to disk")
	_check(save.get_value("collection", "items", []).size() == 4, "collection includes both maps")
	if FileAccess.file_exists(world._save_path):
		DirAccess.remove_absolute(world._save_path)

	print("world2 smoke: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _uses_guian_textures(units: Array[Node]) -> bool:
	var mesh_count := 0
	var textures := {}
	for unit in units:
		for child in unit.get_children():
			if child is MeshInstance3D and child.has_meta("generated_piece"):
				mesh_count += 1
				var material := child.material_override as StandardMaterial3D
				if material == null or material.albedo_texture == null:
					return false
				textures[material.albedo_texture.resource_path] = true
	return mesh_count > 4000 and textures.size() == 20


func _open_prop(world, id: String) -> void:
	var marker := world.map_mount.get_child(0).get_node("Markers/" + id) as Marker3D
	world.player.move_to(marker.global_position + Vector3.UP * 0.03)
	await _frames(6)
	_check(world._nearby == marker, "nearby prompt for " + id)
	var press := InputEventKey.new()
	press.physical_keycode = KEY_E
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await _frames(3)
	_check(world._ui.is_open() and world.collected.has(id), "E opens and collects " + id)
	world._ui.close()
	press.pressed = false
	Input.parse_input_event(press)
	Input.flush_buffered_events()


func _climb(player, start: Vector3, end_z: float, label: String) -> void:
	player.move_to(start)
	await _frames(6)
	Input.action_press(&"move_forward")
	for tick in range(180):
		await physics_frame
		if player.position.z <= end_z:
			break
	Input.action_release(&"move_forward")
	await _frames(4)
	_check(player.position.y > 2.68 and player.position.z <= end_z, label)


func _frames(steps: int) -> void:
	for tick in range(steps):
		await physics_frame


func _target_names(targets: Array[Marker3D], prefix: String) -> Array[String]:
	var names: Array[String] = []
	for target in targets:
		if String(target.name).begins_with(prefix):
			names.append(String(target.name))
	names.sort()
	return names
