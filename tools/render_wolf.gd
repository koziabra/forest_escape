extends SceneTree
# Рендерит игрового оборотня СИЛУЭТОМ на зелёном фоне (для вырезания) -> res://wolf_sil.png
# Запуск: godot --path . --script res://tools/render_wolf.gd

var _f := 0

func _initialize() -> void:
	DisplayServer.window_set_size(Vector2i(256, 256))
	var root := get_root()

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 1, 0)     # хромакей
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	we.environment = env
	root.add_child(we)

	root.add_child(_build_wolf())

	var cam := Camera3D.new()
	cam.fov = 34.0
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0.25, 1.3, 4.3), Vector3(0, 1.25, 0.28), Vector3.UP)

	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_f += 1
	if _f == 14:
		var img := get_root().get_texture().get_image()
		img.save_png("res://wolf_sil.png")
		print("Rendered: res://wolf_sil.png")
		quit(0)


func _dm() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.05, 0.05, 0.08)   # тёмный силуэт
	return m


func _eye() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.28, 0.12)     # красные глаза
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new(); b.size = size
	mi.mesh = b; mi.material_override = mat; mi.position = pos; mi.rotation = rot
	parent.add_child(mi); return mi


func _cone(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0; c.bottom_radius = radius; c.height = height; c.radial_segments = 6
	mi.mesh = c; mi.material_override = mat; mi.position = pos; mi.rotation = rot
	parent.add_child(mi)


func _sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new(); s.radius = radius; s.height = radius * 2.0
	s.radial_segments = 12; s.rings = 8
	mi.mesh = s; mi.material_override = mat; mi.position = pos
	parent.add_child(mi)


func _limb(parent: Node3D, pos: Vector3, length: float, clawed: bool, fur: Material) -> void:
	var hip := Node3D.new(); hip.position = pos
	_box(hip, Vector3(0.18, length, 0.18), Vector3(0, -length / 2.0, 0), fur)
	_box(hip, Vector3(0.2, 0.16, 0.26), Vector3(0, -length, 0), fur)
	if clawed:
		for c in [-1, 0, 1]:
			_cone(hip, 0.03, 0.14, Vector3(c * 0.06, -length - 0.02, 0.14), fur, Vector3(-0.5, 0, 0))
	parent.add_child(hip)


func _build_wolf() -> Node3D:
	var g := Node3D.new()
	var fur := _dm()
	var eye := _eye()
	_box(g, Vector3(0.66, 0.5, 0.5), Vector3(0, 1.05, 0), fur)
	_box(g, Vector3(0.78, 1.0, 0.55), Vector3(0, 1.55, 0.06), fur, Vector3(0.32, 0, 0))
	_box(g, Vector3(0.8, 0.45, 0.5), Vector3(0, 2.02, -0.12), fur)
	for i in 4:
		_cone(g, 0.08, 0.32, Vector3(0, 2.1 - i * 0.18, -0.18 - i * 0.06), fur, Vector3(-0.6, 0, 0))
	_box(g, Vector3(0.34, 0.32, 0.34), Vector3(0, 2.0, 0.18), fur)
	var head := _box(g, Vector3(0.44, 0.42, 0.46), Vector3(0, 2.12, 0.42), fur, Vector3(0.15, 0, 0))
	_box(head, Vector3(0.24, 0.16, 0.4), Vector3(0, 0.0, 0.32), fur)
	_box(head, Vector3(0.22, 0.1, 0.34), Vector3(0, -0.12, 0.28), fur)
	_cone(head, 0.1, 0.34, Vector3(-0.16, 0.3, -0.08), fur, Vector3(0, 0, 0.2))
	_cone(head, 0.1, 0.34, Vector3(0.16, 0.3, -0.08), fur, Vector3(0, 0, -0.2))
	_sphere(head, 0.08, Vector3(-0.11, 0.06, 0.22), eye)
	_sphere(head, 0.08, Vector3(0.11, 0.06, 0.22), eye)
	_limb(g, Vector3(-0.5, 1.95, 0.05), 0.95, true, fur)
	_limb(g, Vector3(0.5, 1.95, 0.05), 0.95, true, fur)
	_limb(g, Vector3(-0.24, 1.0, 0.0), 1.05, false, fur)
	_limb(g, Vector3(0.24, 1.0, 0.0), 1.05, false, fur)
	_cone(g, 0.16, 0.95, Vector3(0, 1.05, -0.45), fur, Vector3(PI / 2.1, 0, 0))
	return g
