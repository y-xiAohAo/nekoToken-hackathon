extends Node3D

const SURFACE := preload("res://districts/morning_star/portal.gdshader")


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.03, 2.80)
	var material := ShaderMaterial.new()
	material.shader = SURFACE
	var portal := MeshInstance3D.new()
	portal.mesh = quad
	portal.material_override = material
	portal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	portal.position = Vector3(0, 1.42, 0)
	add_child(portal)

	var light := OmniLight3D.new()
	light.light_color = Color("#6fe8f3")
	light.light_energy = 0.70
	light.omni_range = 2.7
	light.position = Vector3(0, 0.85, 0.30)
	add_child(light)
