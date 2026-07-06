extends SceneTree
# Инструмент: собирает модель оборотня из примитивов и экспортирует в wolf.glb.
# Запуск: godot --headless --script res://tools/export_wolf.gd

func _initialize() -> void:
	var wolf := _build_wolf()
	get_root().add_child(wolf)

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(wolf, state)
	if err != OK:
		push_error("append_from_scene error: %d" % err)
		quit(1)
		return
	err = doc.write_to_filesystem(state, "res://wolf.glb")
	if err != OK:
		push_error("write_to_filesystem error: %d" % err)
		quit(1)
		return
	print("Экспортировано: res://wolf.glb")
	quit(0)


func _mat(col: Color, rough := 1.0, emit := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	if emit:
		m.emission_enabled = true
		m.emission = col
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new(); b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _cone(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0; c.bottom_radius = radius; c.height = height; c.radial_segments = 6
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new(); s.radius = radius; s.height = radius * 2.0
	s.radial_segments = 12; s.rings = 8
	mi.mesh = s
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _limb(parent: Node3D, pos: Vector3, length: float, clawed: bool, fur: Material, dark: Material, teeth: Material) -> void:
	var hip := Node3D.new()
	hip.position = pos
	_box(hip, Vector3(0.18, length, 0.18), Vector3(0, -length / 2.0, 0), fur)
	_box(hip, Vector3(0.2, 0.16, 0.26), Vector3(0, -length, 0), dark)
	if clawed:
		for c in [-1, 0, 1]:
			_cone(hip, 0.03, 0.14, Vector3(c * 0.06, -length - 0.02, 0.14), teeth, Vector3(-0.5, 0, 0))
	parent.add_child(hip)


func _build_wolf() -> Node3D:
	var g := Node3D.new()
	g.name = "Werewolf"
	var fur := _mat(Color(0.14, 0.12, 0.11))
	var fur_light := _mat(Color(0.24, 0.22, 0.20))
	var dark := _mat(Color(0.055, 0.047, 0.047))
	var teeth := _mat(Color(0.91, 0.89, 0.82), 0.6)
	var eye_mat := _mat(Color(1.0, 0.16, 0.09), 0.4, true)

	_box(g, Vector3(0.66, 0.5, 0.5), Vector3(0, 1.05, 0), fur)                       # таз
	_box(g, Vector3(0.78, 1.0, 0.55), Vector3(0, 1.55, 0.06), fur, Vector3(0.32, 0, 0))
	_box(g, Vector3(0.5, 0.7, 0.18), Vector3(0, 1.5, 0.34), fur_light, Vector3(0.32, 0, 0))
	_box(g, Vector3(0.8, 0.45, 0.5), Vector3(0, 2.02, -0.12), fur)                   # горб
	for i in 4:
		_cone(g, 0.08, 0.32, Vector3(0, 2.1 - i * 0.18, -0.18 - i * 0.06), fur, Vector3(-0.6, 0, 0))
	_box(g, Vector3(0.34, 0.32, 0.34), Vector3(0, 2.0, 0.18), fur)                   # шея
	var head := _box(g, Vector3(0.44, 0.42, 0.46), Vector3(0, 2.12, 0.42), fur, Vector3(0.15, 0, 0))
	_box(head, Vector3(0.24, 0.16, 0.4), Vector3(0, 0.0, 0.32), fur)                 # верхняя челюсть
	_box(head, Vector3(0.22, 0.1, 0.34), Vector3(0, -0.12, 0.28), fur)              # нижняя челюсть
	_cone(head, 0.03, 0.1, Vector3(-0.07, -0.08, 0.4), teeth, Vector3(PI, 0, 0))
	_cone(head, 0.03, 0.1, Vector3(0.07, -0.08, 0.4), teeth, Vector3(PI, 0, 0))
	_box(head, Vector3(0.1, 0.08, 0.1), Vector3(0, 0.04, 0.5), dark)                # нос
	_cone(head, 0.1, 0.34, Vector3(-0.16, 0.3, -0.08), fur, Vector3(0, 0, 0.2))
	_cone(head, 0.1, 0.34, Vector3(0.16, 0.3, -0.08), fur, Vector3(0, 0, -0.2))
	_sphere(head, 0.075, Vector3(-0.11, 0.06, 0.22), eye_mat)
	_sphere(head, 0.075, Vector3(0.11, 0.06, 0.22), eye_mat)

	_limb(g, Vector3(-0.5, 1.95, 0.05), 0.95, true, fur, dark, teeth)
	_limb(g, Vector3(0.5, 1.95, 0.05), 0.95, true, fur, dark, teeth)
	_limb(g, Vector3(-0.24, 1.0, 0.0), 1.05, false, fur, dark, teeth)
	_limb(g, Vector3(0.24, 1.0, 0.0), 1.05, false, fur, dark, teeth)
	_cone(g, 0.16, 0.95, Vector3(0, 1.05, -0.45), fur, Vector3(PI / 2.1, 0, 0))     # хвост
	return g
