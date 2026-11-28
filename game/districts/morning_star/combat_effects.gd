extends Node3D

const CYAN := Color("#6df1ff")
const WHITE := Color("#e8fbff")
const WARM := Color("#ffd480")
const PARTICLE_CAP := 48
const GHOST_INTERVAL := 0.042
const GHOST_DURATION := 0.14

class Fleck:
	var mesh: MeshInstance3D
	var tone: Color
	var origin := Vector3.ZERO
	var motion := Vector3.ZERO
	var age := 0.0
	var lifetime := 0.0

var _dash_lines: Array[MeshInstance3D] = []
var _beam_rings: Array[MeshInstance3D] = []
var _charge_flecks: Array[MeshInstance3D] = []
var _feedback: Node3D
var _pixel: BoxMesh
var _ring_mesh: TorusMesh
var _flecks: Array[Fleck] = []
var _next_fleck := 0
var _ghosts: Array[Sprite3D] = []
var _ghost_times := PackedFloat32Array()
var _dodge_source: AnimatedSprite3D
var _dodge_age := 0.0
var _ghost_samples := 0


func build() -> void:
	_pixel = BoxMesh.new()
	_pixel.size = Vector3.ONE
	for index in range(6):
		var color := WHITE if index % 3 == 0 else CYAN
		var line := _mesh(self, _pixel, color, Vector3.ZERO)
		_dash_lines.append(line)
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.91
	_ring_mesh.outer_radius = 1.0
	_ring_mesh.rings = 40
	_ring_mesh.ring_segments = 5
	for index in range(2):
		var ring := _mesh(self, _ring_mesh, WHITE if index == 0 else CYAN, Vector3.ZERO)
		_beam_rings.append(ring)
	for index in range(6):
		_charge_flecks.append(_mesh(self, _pixel, CYAN, Vector3.ZERO))
	_feedback = Node3D.new()
	_feedback.name = "CombatFeedback"
	add_child(_feedback)
	for index in range(PARTICLE_CAP):
		var fleck := Fleck.new()
		fleck.mesh = _mesh(self, _pixel, WHITE, Vector3.ZERO)
		fleck.mesh.hide()
		_flecks.append(fleck)
	for index in range(3):
		var sprite := Sprite3D.new()
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sprite)
		sprite.hide()
		_ghosts.append(sprite)
		_ghost_times.append(0.0)
	clear_skill()


func clear_skill() -> void:
	for line in _dash_lines:
		line.hide()
	for ring in _beam_rings:
		ring.hide()
	end_charge()


func charge(at: Vector3, tone: Color, ratio: float, style: int) -> void:
	for index in range(_charge_flecks.size()):
		var bit := _charge_flecks[index]
		var offset := float(index) / _charge_flecks.size()
		var turn := Vector2.from_angle((offset + ratio * (0.22 + style * 0.12)) * TAU)
		var radius := lerpf(1.05, 0.46, ratio)
		var height := 2.22 + float(index % 3) * 0.24 + ratio * 0.44
		bit.global_position = at + Vector3(turn.x * radius, height, turn.y * radius)
		var size := 0.09 + ratio * 0.065
		bit.scale = Vector3(size, size * (1.8 if style == 2 else 1.0), size)
		var tint := tone
		tint.a = lerpf(0.35, 0.9, ratio)
		(bit.material_override as StandardMaterial3D).albedo_color = tint
		bit.show()


func end_charge() -> void:
	for bit in _charge_flecks:
		bit.hide()


func clear_feedback() -> void:
	for effect in _feedback.get_children():
		(effect as Node3D).hide()
		effect.queue_free()
	for fleck in _flecks:
		fleck.lifetime = 0.0
		fleck.mesh.hide()
	_dodge_source = null
	for index in range(_ghosts.size()):
		_ghost_times[index] = 0.0
		_ghosts[index].hide()


func _process(delta: float) -> void:
	for fleck in _flecks:
		if fleck.lifetime <= 0.0:
			continue
		fleck.age += delta
		var ratio := fleck.age / fleck.lifetime
		if ratio >= 1.0:
			fleck.lifetime = 0.0
			fleck.mesh.hide()
			continue
		fleck.mesh.global_position = fleck.origin + fleck.motion * (1.0 - (1.0 - ratio) * (1.0 - ratio))
		var tint := fleck.tone
		tint.a *= 1.0 - ratio
		(fleck.mesh.material_override as StandardMaterial3D).albedo_color = tint
	_update_dodge_trail(delta)


func begin_dodge(source: AnimatedSprite3D) -> void:
	_dodge_source = source
	_dodge_age = 0.0
	_ghost_samples = 0


func _update_dodge_trail(delta: float) -> void:
	if is_instance_valid(_dodge_source):
		_dodge_age += delta
		if _dodge_age >= GHOST_INTERVAL * _ghost_samples:
			var sprite := _ghosts[_ghost_samples]
			var source := _dodge_source
			sprite.texture = source.sprite_frames.get_frame_texture(source.animation, source.frame)
			sprite.offset = source.offset
			sprite.pixel_size = source.pixel_size
			sprite.flip_h = source.flip_h
			sprite.global_transform = source.global_transform
			sprite.reset_physics_interpolation()
			_ghost_times[_ghost_samples] = GHOST_DURATION
			_ghost_samples += 1
			sprite.show()
			if _ghost_samples == _ghosts.size():
				_dodge_source = null
	for index in range(_ghosts.size()):
		if _ghost_times[index] <= 0.0:
			continue
		_ghost_times[index] = maxf(0.0, _ghost_times[index] - delta)
		var tint := Color("#8cf4fc")
		tint.a = 0.43 * _ghost_times[index] / GHOST_DURATION
		_ghosts[index].modulate = tint
		_ghosts[index].visible = _ghost_times[index] > 0.0


func dash_trail(start: Vector2, finish: Vector2) -> void:
	var motion := finish - start
	var trail_length := motion.length()
	if trail_length < 0.1:
		return
	var along := motion / trail_length
	var side := along.orthogonal()
	for index in range(_dash_lines.size()):
		var line := _dash_lines[index]
		var lane := index % 3
		var lateral := (float(lane) - 1.0) * 0.47
		var length := trail_length * (0.67 + 0.13 * lane)
		var at := finish - along * (length * 0.55 + 0.22) + side * lateral
		var height := 0.78 + float(lane) * 0.32 if index < 3 else 3.80 + float(lane) * 0.32
		line.position = Vector3(at.x, height, at.y)
		line.rotation.y = atan2(along.x, along.y)
		line.scale = Vector3(0.066, 0.056, length)
		var tint := WHITE if lane == 0 else CYAN
		tint.a = 0.84 - (lane * 0.13)
		(line.material_override as StandardMaterial3D).albedo_color = tint
		line.show()


func beam_impact(at: Vector2) -> void:
	for ring in _beam_rings:
		ring.position = Vector3(at.x, 0.10, at.y)
		ring.show()
	beam_pulse(0.0)
	sparks(Vector3(at.x, 0.19, at.y), CYAN, 12, 1.22, 0.32)


func beam_pulse(progress: float) -> void:
	for index in range(_beam_rings.size()):
		var pulse := clampf(progress * 1.28 - index * 0.28, 0.0, 1.0)
		var radius := lerpf(0.39, 1.43, ease(pulse, 0.55))
		var ring := _beam_rings[index]
		ring.scale = Vector3(radius, 0.36, radius)
		var tint := WHITE if index == 0 else CYAN
		tint.a = (1.0 - pulse) * (0.91 if index == 0 else 0.62)
		(ring.material_override as StandardMaterial3D).albedo_color = tint


func punch(origin: Vector3, direction: Vector3) -> void:
	var effect := _effect_at(origin + Vector3.UP * 1.34)
	effect.rotation.y = atan2(direction.x, direction.z)
	var fade := effect.create_tween().set_parallel(true)
	for index in range(3):
		var line := _mesh(effect, _pixel, WARM if index == 1 else WHITE,
			Vector3((float(index) - 1.0) * 0.135, float(index) * 0.080, 0.98 - index * 0.11))
		line.scale = Vector3(0.070, 0.070, 0.70 - index * 0.13)
		_fade(fade, line, 0.15)
		fade.tween_property(line, "position:z", line.position.z + 0.27, 0.15)
	fade.chain().tween_callback(effect.queue_free)


func sparks(at: Vector3, tone: Color, count: int, spread: float, duration: float) -> void:
	for index in range(mini(count, _flecks.size())):
		var axis := Vector2.from_angle(index * 2.39996)
		var height := 0.22 + (index % 4) * 0.18
		var direction := Vector3(axis.x, height, axis.y)
		var fleck := _flecks[_next_fleck]
		_next_fleck = (_next_fleck + 1) % _flecks.size()
		fleck.tone = WHITE if index % 3 == 0 else tone
		fleck.origin = at + direction * spread * 0.24
		fleck.motion = direction * spread * (0.36 + (index % 4) * 0.17)
		fleck.age = 0.0
		fleck.lifetime = duration
		var size := 0.090 + (index % 3) * 0.026
		fleck.mesh.scale = Vector3.ONE * size
		fleck.mesh.global_position = fleck.origin
		fleck.mesh.reset_physics_interpolation()
		(fleck.mesh.material_override as StandardMaterial3D).albedo_color = fleck.tone
		fleck.mesh.show()


func ripple(at: Vector3, tone: Color, radius: float, duration: float) -> void:
	var effect := _effect_at(at)
	var ring := _mesh(effect, _ring_mesh, tone, Vector3.ZERO)
	ring.scale = Vector3(0.28, 0.32, 0.28)
	var spread := effect.create_tween().set_parallel(true)
	_fade(spread, ring, duration)
	spread.tween_property(ring, "scale", Vector3(radius, 0.32, radius), duration).set_ease(Tween.EASE_OUT)
	spread.chain().tween_callback(effect.queue_free)


func _effect_at(world_position: Vector3) -> Node3D:
	var effect := Node3D.new()
	_feedback.add_child(effect)
	effect.global_position = world_position
	return effect


func _mesh(parent: Node3D, mesh: Mesh, color: Color, at: Vector3) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = at
	parent.add_child(instance)
	return instance


func _fade(tween: Tween, instance: MeshInstance3D, duration: float) -> void:
	var material := instance.material_override as StandardMaterial3D
	var transparent := material.albedo_color
	transparent.a = 0.0
	tween.tween_property(material, "albedo_color", transparent, duration)
