extends Node3D

const ART := preload("res://actors/characters_2046_v2/hype_morning_star_boss_idle.png")
const KNEEL := preload("res://actors/characters_2046_v2/hype_boss_kneel.png")
const SPRITE_SHADER := preload("res://districts/morning_star/boss_sprite.gdshader")
const PIXEL_SIZE := 0.048
const HEIGHT_CORRECTION := 1.41421356

var _body: Sprite3D
var _projection: Sprite3D
var _kneel: Sprite3D
var _airborne: Node3D
var _shadow: MeshInstance3D
var _projection_material: ShaderMaterial
var _body_material: ShaderMaterial
var _kneel_textures: Array[AtlasTexture] = []
var _fall_height := 0.0


func build() -> void:
	_airborne = Node3D.new()
	_airborne.name = "Airborne"
	add_child(_airborne)
	_body = _new_sprite(&"Hype", ART, 50.0)
	_body_material = _apply_sprite_shader(_body, false)
	_projection = _new_sprite(&"MorningStar", ART, 50.0)
	_projection_material = _apply_sprite_shader(_projection, true)

	for column in range(2):
		var frame := AtlasTexture.new()
		frame.atlas = KNEEL
		frame.region = Rect2(column * 48, 0, 48, 48)
		_kneel_textures.append(frame)
	_kneel = _new_sprite(&"HypeKneeling", _kneel_textures[0], 20.0)
	_kneel.position.y = 0.025
	_kneel.reparent(self, false)

	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.60
	mesh.bottom_radius = 0.60
	mesh.height = 0.014
	mesh.radial_segments = 20
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#091726a6")
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow = MeshInstance3D.new()
	_shadow.mesh = mesh
	_shadow.material_override = material
	_shadow.position.y = 0.024
	_shadow.scale.z = 0.82
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)
	reset()


func reset() -> void:
	_projection_material.set_shader_parameter("dissolve", 0.0)
	_projection_material.set_shader_parameter("severed_pairs", 0)
	_projection.position = Vector3.ZERO
	_projection.show()
	_body.show()
	_kneel.hide()
	_airborne.rotation.z = 0.0
	_airborne.position.y = 0.48


func update_live(at: Vector2, clock: float, lean: float, glow: float, flash: float, severed: int) -> void:
	position = Vector3(at.x, 0.0, at.y)
	_airborne.position.y = 0.48 + sin(clock * 3.7) * 0.095 + glow * 0.095
	_airborne.rotation.z = lerp_angle(_airborne.rotation.z, lean, 0.30)
	_projection_material.set_shader_parameter("severed_pairs", severed)
	_projection_material.set_shader_parameter("glow", glow)
	_projection_material.set_shader_parameter("flash", flash)
	_body_material.set_shader_parameter("flash", flash * 0.55)


func reveal(amount: float) -> void:
	_projection.visible = amount > 0.0
	_projection_material.set_shader_parameter("dissolve", (1.0 - amount) * 0.97)


func begin_defeat() -> void:
	_fall_height = _airborne.position.y
	_projection.show()
	_projection_material.set_shader_parameter("severed_pairs", 3)
	_projection_material.set_shader_parameter("glow", 0.0)
	_projection_material.set_shader_parameter("flash", 0.0)
	_body_material.set_shader_parameter("flash", 0.0)


func update_defeat(elapsed: float) -> void:
	var fall := clampf(elapsed / 0.36, 0.0, 1.0)
	_airborne.position.y = _fall_height * (1.0 - fall * fall)
	_airborne.rotation.z = 0.09 * sin(fall * PI)
	_projection.position.y = _fall_height - _airborne.position.y + minf(elapsed, 1.75) * 0.36
	_projection_material.set_shader_parameter("dissolve", clampf((elapsed - 0.12) / 1.66, 0.0, 1.0))
	_body.visible = fall < 1.0
	_kneel.visible = fall >= 1.0
	_kneel.texture = _kneel_textures[0 if elapsed < 1.80 else 1]
	_projection.visible = elapsed < 1.83


func _new_sprite(id: StringName, texture: Texture2D, offset_y: float) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.name = id
	sprite.texture = texture
	sprite.pixel_size = PIXEL_SIZE
	sprite.offset = Vector2(0, offset_y)
	sprite.scale.y = HEIGHT_CORRECTION
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_airborne.add_child(sprite)
	return sprite


func _apply_sprite_shader(sprite: Sprite3D, projection: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SPRITE_SHADER
	material.set_shader_parameter("sprite_art", ART)
	material.set_shader_parameter("projection_layer", projection)
	sprite.material_override = material
	return material
