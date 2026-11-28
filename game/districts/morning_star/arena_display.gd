extends Node3D

const PORTAL := preload("res://districts/morning_star/portal_visual.gd")
const WALL_SHADER := preload("res://districts/morning_star/arena_wall.gdshader")
const SWEEP_SHADER := preload("res://districts/morning_star/sweep_energy.gdshader")
const BEAM_SHADER := preload("res://districts/morning_star/projection_beam.gdshader")
const COMBAT_EFFECTS := preload("res://districts/morning_star/combat_effects.gd")
const SIDES := 60
const WALL_PANELS := 32
const WALL_HEIGHT := 2.72
const MARGIN := 0.12
const WARN_FILL := Color("#f4ad4847")
const WARN_EDGE := Color("#ffca70e8")
const STRIKE_FILL := Color("#70eeff96")
const STRIKE_EDGE := Color("#defeffec")

var effects: COMBAT_EFFECTS
var _radius := 0.0
var _fill: MeshInstance3D
var _edge: MeshInstance3D
var _wall_flash: MeshInstance3D
var _sweep_crest: MeshInstance3D
var _sweep_angle := INF
var _wall_flash_shape := Vector3(INF, INF, INF)
var _wall_surface: ShaderMaterial
var _beam: Node3D
var _ghost: Sprite3D
var _exit_portal: Node3D


func build(radius: float) -> void:
	_radius = radius
	_build_floor()
	_build_wall()

	_fill = _make_mesh(null, WARN_FILL, Vector3(0, 0.024, 0))
	_edge = _make_mesh(null, WARN_EDGE, Vector3(0, 0.038, 0))
	_wall_flash = _make_mesh(null, WARN_EDGE, Vector3.ZERO)
	_sweep_crest = _make_mesh(null, STRIKE_EDGE, Vector3.ZERO)
	_sweep_crest.name = "SweepCrest"
	var sweep_material := ShaderMaterial.new()
	sweep_material.shader = SWEEP_SHADER
	_sweep_crest.material_override = sweep_material

	effects = COMBAT_EFFECTS.new()
	effects.name = "CombatEffects"
	add_child(effects)
	effects.build()

	_beam = Node3D.new()
	_beam.name = "PredictionBeam"
	add_child(_beam)
	var beam_widths := [1.12, 0.41, 0.14]
	var beam_colors := [Color("#51d4f33b"), Color("#6dedffb8"), Color("#e0fffff4")]
	for index in range(3):
		var column := CylinderMesh.new()
		column.top_radius = beam_widths[index]
		column.bottom_radius = beam_widths[index]
		column.height = 6.2
		column.radial_segments = 12
		var instance := _make_mesh(column, beam_colors[index], Vector3(0, 3.11, 0))
		var beam_material := ShaderMaterial.new()
		beam_material.shader = BEAM_SHADER
		beam_material.set_shader_parameter("tint", beam_colors[index])
		instance.material_override = beam_material
		instance.reparent(_beam, false)

	_ghost = Sprite3D.new()
	_ghost.name = "PredictedWilliam"
	_ghost.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_ghost.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.pixel_size = 0.048
	_ghost.offset = Vector2(0, 20)
	_ghost.modulate = Color("#5feaf3a3")
	add_child(_ghost)

	_exit_portal = PORTAL.new()
	_exit_portal.name = "ReturnPortal"
	add_child(_exit_portal)
	_exit_portal.position = Vector3(0, 0.02, 10.25)
	show_exit(false)
	clear_attack()


func show_exit(enabled: bool) -> void:
	_exit_portal.visible = enabled


func clear_attack() -> void:
	_fill.hide()
	_edge.hide()
	_wall_flash.hide()
	_sweep_crest.hide()
	_ghost.hide()
	_beam.hide()
	effects.clear_skill()


func animate_warning(progress: float) -> void:
	var amount := 0.18 * sin(progress * TAU * 2.0) + 0.25 * progress
	(_edge.material_override as StandardMaterial3D).albedo_color = WARN_EDGE.lerp(Color("#fff0b8"), maxf(amount, 0.0))


func set_phase_tone(tone: Color, intensity: float) -> void:
	_wall_surface.set_shader_parameter("phase_color", tone)
	_wall_surface.set_shader_parameter("phase_energy", intensity)


func mark_sector(angle: float, half_angle: float, safe_center: float) -> void:
	_set_ground(_arc(Vector2.ZERO, safe_center, _radius, angle - half_angle, 2.0 * half_angle, 22),
		_sector_rails(angle, half_angle, safe_center),
		WARN_FILL, WARN_EDGE)
	_show_wall_arc(angle, half_angle, WARN_EDGE, 0.60)


func sweep_sector(angle: float, half_angle: float, front: float, back: float) -> void:
	_set_ground(_arc(Vector2.ZERO, front, back, angle - half_angle, 2.0 * half_angle, 22),
		_arc(Vector2.ZERO, front, minf(front + 0.17, back), angle - half_angle, 2.0 * half_angle, 22),
		Color("#70eeff69"), STRIKE_EDGE)
	_show_wall_arc(angle, half_angle, STRIKE_FILL, 0.89)
	_show_sweep_crest(angle, half_angle, front + 0.08)


func mark_dash(start: Vector2, finish: Vector2, width: float) -> void:
	_set_ground(_lane(start, finish, width), _lane_outline(start, finish, width), WARN_FILL, WARN_EDGE)


func strike_dash(start: Vector2, finish: Vector2, width: float) -> void:
	_set_ground(_lane(start, finish, width * 0.66), _lane(start, finish, 0.11),
		STRIKE_FILL, STRIKE_EDGE)
	effects.dash_trail(start, finish)


func mark_pulse(at: Vector2, radius: float) -> void:
	_set_ground(_arc(at, 0.0, radius), _arc(at, radius - 0.12, radius), WARN_FILL, WARN_EDGE)


func strike_pulse(at: Vector2, inner: float, outer: float) -> void:
	var core := minf(inner + 0.17, outer)
	_set_ground(_arc(at, inner, outer), _arc(at, core, outer),
		Color("#8e94ff71"), Color("#beb1ffbf"))


func mark_prediction(at: Vector2, width: float, texture: Texture2D) -> void:
	_set_ground(_arc(at, 0.0, width), _arc(at, width - 0.13, width), WARN_FILL, WARN_EDGE)
	_ghost.texture = texture
	_ghost.position = Vector3(at.x, 0.06, at.y)
	_ghost.show()


func strike_prediction(at: Vector2, width: float) -> void:
	_set_ground(_arc(at, 0.0, width), _arc(at, width - 0.15, width), STRIKE_FILL, STRIKE_EDGE)
	_ghost.hide()
	_beam.position = Vector3(at.x, 0, at.y)
	_beam.scale = Vector3.ONE
	_beam.show()
	effects.beam_impact(at)


func fade_beam(progress: float) -> void:
	var width := 1.0 - 0.74 * progress
	_beam.scale = Vector3(width, 1.0, width)
	effects.beam_pulse(progress)


func _build_floor() -> void:
	var floor := StaticBody3D.new()
	floor.name = "ArenaFloor"
	add_child(floor)
	floor.position.y = -0.26
	var cylinder := CylinderShape3D.new()
	cylinder.radius = _radius + MARGIN
	cylinder.height = 0.52
	var ground_shape := CollisionShape3D.new()
	ground_shape.shape = cylinder
	floor.add_child(ground_shape)

	var slab := CylinderMesh.new()
	slab.top_radius = cylinder.radius
	slab.bottom_radius = cylinder.radius - 0.15
	slab.height = cylinder.height
	slab.radial_segments = SIDES * 2
	_make_mesh(slab, Color("#142336"), Vector3(0, -0.26, 0))
	_make_mesh(_arc(Vector2.ZERO, 0.0, _radius - 1.35), Color("#192b41"), Vector3(0, 0.008, 0))
	_make_mesh(_arc(Vector2.ZERO, _radius - 1.35, _radius - 1.29), Color("#102137"), Vector3(0, 0.013, 0))
	_make_mesh(_arc(Vector2.ZERO, _radius - 0.055, _radius + 0.03), Color("#5edee6"), Vector3(0, 0.014, 0))
	_make_mesh(_arc(Vector2.ZERO, _radius - 0.25, _radius - 0.225), Color("#326178"), Vector3(0, 0.015, 0))
	_make_mesh(_arc(Vector2.ZERO, 0.69, 0.74, PI / 4.0, TAU, 4), Color("#2a4a60"), Vector3(0, 0.015, 0))
	_make_mesh(_arc(Vector2.ZERO, 1.02, 1.05, PI / 4.0, TAU, 4), Color("#233d52"), Vector3(0, 0.015, 0))
	for index in range(24):
		var angle := float(index) * TAU / 24.0
		var outward := Vector2.from_angle(angle)
		var notch_length := 0.68 if index % 3 == 0 else 0.24
		var tone := Color("#3d7186") if index % 3 == 0 else Color("#294657")
		_make_mesh(_lane(outward * (_radius - 0.52 - notch_length),
			outward * (_radius - 0.52), 0.05), tone, Vector3(0, 0.015, 0))


func _build_wall() -> void:
	var barrier := StaticBody3D.new()
	barrier.name = "CircularBoundary"
	add_child(barrier)
	var wall_body := SurfaceTool.new()
	wall_body.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gap := TAU / float(WALL_PANELS)
	for index in range(WALL_PANELS):
		var angle := gap * float(index)
		_wall_panel(wall_body, angle + gap * 0.025, angle + gap * 0.975, WALL_HEIGHT)
	var wall := _make_mesh(wall_body.commit(), Color.WHITE, Vector3.ZERO)
	_wall_surface = ShaderMaterial.new()
	_wall_surface.shader = WALL_SHADER
	wall.material_override = _wall_surface

	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0 * (_radius + MARGIN) * tan(PI / SIDES) + 0.06, WALL_HEIGHT, 0.38)
	for index in range(SIDES):
		var angle := float(index) * TAU / SIDES
		var outward := Vector2.from_angle(angle) * (_radius + MARGIN)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position = Vector3(outward.x, WALL_HEIGHT * 0.5, outward.y)
		collider.rotation.y = PI / 2.0 - angle
		barrier.add_child(collider)


func _show_wall_arc(angle: float, half_angle: float, color: Color, height: float) -> void:
	var geometry := Vector3(angle, half_angle, height)
	if geometry != _wall_flash_shape:
		_wall_flash_shape = geometry
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var step_angle := TAU / WALL_PANELS
		for index in range(WALL_PANELS):
			var start := float(index) * step_angle
			if absf(angle_difference(angle, start + step_angle * 0.5)) <= half_angle + step_angle * 0.4:
				_wall_panel(surface, start + step_angle * 0.045, start + step_angle * 0.93, height)
		_wall_flash.mesh = surface.commit()
	(_wall_flash.material_override as StandardMaterial3D).albedo_color = color
	_wall_flash.show()


func _show_sweep_crest(angle: float, half_angle: float, radius: float) -> void:
	const PANELS := 18
	if _sweep_angle != angle:
		_sweep_angle = angle
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var panel_angle := 2.0 * half_angle / PANELS
		for index in range(PANELS):
			var start := angle - half_angle + panel_angle * index
			var height := 0.78 + float(index % 3) * 0.12
			_wall_panel(surface, start, start + panel_angle * 0.96, height, 1.0)
		_sweep_crest.mesh = surface.commit()
	_sweep_crest.scale = Vector3(radius, 1.0, radius)
	_sweep_crest.show()


func _wall_panel(surface: SurfaceTool, start: float, finish: float,
		height: float, radius: float = -1.0) -> void:
	const PIECES := 3
	var panel_radius := _radius if radius < 0.0 else radius
	for index in range(PIECES):
		var left := float(index) / PIECES
		var right := float(index + 1) / PIECES
		var a := Vector2.from_angle(lerpf(start, finish, left)) * panel_radius
		var b := Vector2.from_angle(lerpf(start, finish, right)) * panel_radius
		var points := PackedVector3Array([Vector3(a.x, 0.06, a.y), Vector3(b.x, 0.06, b.y),
			Vector3(a.x, height, a.y), Vector3(b.x, height, b.y)])
		var uvs := PackedVector2Array([Vector2(left, 1), Vector2(right, 1), Vector2(left, 0), Vector2(right, 0)])
		for corner in [0, 1, 2, 2, 1, 3]:
			surface.set_uv(uvs[corner])
			surface.add_vertex(points[corner])


func _set_ground(fill: Mesh, edge: Mesh, fill_color: Color, edge_color: Color) -> void:
	_fill.mesh = fill
	_edge.mesh = edge
	(_fill.material_override as StandardMaterial3D).albedo_color = fill_color
	(_edge.material_override as StandardMaterial3D).albedo_color = edge_color
	_fill.show()
	_edge.show()


func _make_mesh(mesh: Mesh, color: Color, at: Vector3) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if color.a < 1.0 or mesh == null:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = at
	add_child(instance)
	return instance


func _arc(center: Vector2, inner: float, outer: float,
		start: float = 0.0, sweep: float = TAU, segments: int = SIDES) -> Mesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(segments):
		var a := Vector2.from_angle(start + sweep * float(index) / segments)
		var b := Vector2.from_angle(start + sweep * float(index + 1) / segments)
		_quad(surface, center + a * inner, center + a * outer, center + b * inner, center + b * outer)
	return surface.commit()


func _lane(start: Vector2, finish: Vector2, width: float) -> Mesh:
	var offset := (finish - start).normalized().orthogonal() * width
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(surface, start - offset, start + offset, finish - offset, finish + offset)
	return surface.commit()


func _lane_outline(start: Vector2, finish: Vector2, width: float) -> Mesh:
	var along := (finish - start).normalized()
	var side := along.orthogonal()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for direction in [-1.0, 1.0]:
		var outer: Vector2 = side * width * direction
		var inner: Vector2 = side * (width - 0.072) * direction
		_quad(surface, start + outer, start + inner, finish + outer, finish + inner)
	_quad(surface, start - side * width, start + side * width,
		start - side * width + along * 0.072, start + side * width + along * 0.072)
	_quad(surface, finish - side * width, finish + side * width,
		finish - side * width - along * 0.072, finish + side * width - along * 0.072)
	return surface.commit()


func _sector_rails(angle: float, half_angle: float, inner: float) -> Mesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for edge_angle in [angle - half_angle, angle + half_angle]:
		var along := Vector2.from_angle(edge_angle)
		var side := along.orthogonal() * 0.038
		for index in range(14):
			var from := along * lerpf(inner, _radius, float(index) / 14.0)
			var to := along * lerpf(inner, _radius, (float(index) + 0.65) / 14.0)
			_quad(surface, from - side, from + side, to - side, to + side)
	return surface.commit()


func _quad(surface: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> void:
	for p in [a, b, c, c, b, d]:
		surface.add_vertex(Vector3(p.x, 0, p.y))
