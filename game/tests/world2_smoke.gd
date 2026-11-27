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
		push_error("Cannot load world2.tscn")
		quit(1)
		return
	var world: Node3D = packed.instantiate()
	root.add_child(world)
	world.set_process(false)
	await physics_frame
	await physics_frame

	var units := get_nodes_in_group("world2_units")
	_check(world.get_node("Ground").get_child_count() == 468, "26 x 18 ground tiles")
	_check(units.size() == 804, "804 reusable units")

	var mesh_count := 0
	var missing_textures := 0
	var used_textures := {}
	for unit in units:
		for child in unit.get_children():
			if child is MeshInstance3D and child.has_meta("generated_piece"):
				mesh_count += 1
				var material := child.material_override as StandardMaterial3D
				if material == null or material.albedo_texture == null:
					missing_textures += 1
				else:
					used_textures[material.albedo_texture.resource_path] = true
	_check(mesh_count > 4000, "generated meshes")
	_check(missing_textures == 0, "all ant-hill meshes textured")
	_check(used_textures.size() == 20, "all 20 surface textures used")

	var space := world.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(23, 0.8, 16.5), Vector3(23, 0.8, -16.5))
	_check(space.intersect_ray(query).is_empty(), "east corridor through route")

	var player: CharacterBody3D = world.get_node("Player")
	var camera: Camera3D = world.get_node("Camera")
	camera.global_position = Vector3(0, 18, 28)
	camera.look_at(Vector3(0, 0, -3))
	player.global_position = Vector3(-11, 0.05, -5)
	player.velocity = Vector3.ZERO
	await physics_frame
	Input.action_press("move_forward")
	var stair_peak := -100.0
	for i in range(175):
		await physics_frame
		stair_peak = maxf(stair_peak, player.global_position.y)
	Input.action_release("move_forward")
	_check(stair_peak > 2.6 and player.is_on_floor(), "walkable home second floor")

	player.global_position = Vector3(-21, 0.05, -7)
	player.velocity = Vector3.ZERO
	await physics_frame
	world._update_interaction()
	var prompt: Label = world.get_node("HUD/Prompt")
	_check(prompt.text.contains("沙发"), "home furniture interaction prompt")

	print("world2 smoke: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
