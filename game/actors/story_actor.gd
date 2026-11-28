extends StaticBody3D

var actor_visual: Sprite3D
var viewer: Node3D
var poses: AtlasTexture


func configure(model: PackedScene, player: Node3D) -> void:
	viewer = player
	actor_visual = model.instantiate() as Sprite3D
	poses = (actor_visual.texture as AtlasTexture).duplicate() as AtlasTexture
	actor_visual.texture = poses
	actor_visual.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	actor_visual.position.y = 0.02
	add_child(actor_visual)

	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.5
	collider.shape = capsule
	collider.position.y = capsule.height / 2.0
	add_child(collider)


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var right := camera.global_basis.x.slide(Vector3.UP).normalized()
	var back := right.cross(Vector3.UP)
	var height_scale := 1.0 / maxf(camera.global_basis.y.y, 0.5)
	actor_visual.global_basis = Basis(right, Vector3.UP * height_scale, back)

	var towards_viewer := viewer.global_position - global_position
	var lateral := towards_viewer.dot(right)
	var depth := towards_viewer.dot(back)
	var region := poses.region
	region.position.x = region.size.x if absf(lateral) > absf(depth) else (
		0.0 if depth >= 0.0 else region.size.x * 2.0)
	if poses.region != region:
		poses.region = region
	actor_visual.flip_h = region.position.x == region.size.x and lateral < 0.0
