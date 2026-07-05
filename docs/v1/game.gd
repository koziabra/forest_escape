extends Node3D
# Forest Escape — обновлённое ядро на Godot 4.
# Новое: меню/финал, текстуры, 3 вида деревьев (много), новый оборотень,
# кристаллы-осколки, финальные ворота.

const TREE_COUNT := 900
const SHARD_COUNT := 5
const WOLF_COUNT := 6
const WORLD := 90.0
const SPEED := 6.0
const SENS := 0.005
const WOLF_DETECT_LIT := 18.0
const WOLF_DETECT_DARK := 5.0
const WOLF_SPEED := 5.2
const WOLF_WANDER := 2.6
const WOLF_CATCH := 1.4

var player: CharacterBody3D
var cam: Camera3D
var flashlight: SpotLight3D
var yaw := 0.0
var pitch := 0.0

var move_index := -1
var move_origin := Vector2.ZERO
var move_vec := Vector2.ZERO
var look_index := -1

var shards: Array = []
var wolves: Array = []
var collected := 0
var running := false

var gate: Node3D
var gate_core_mat: StandardMaterial3D
var gate_light: OmniLight3D
var gate_active := false

var hud_count: Label
var hud_msg: Label
var menu_panel: Control
var end_panel: Control
var end_title: Label


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_trees()
	_build_shards()
	_build_wolves()
	_build_gate()
	_build_player()
	_build_hud()
	_build_menu()


# ---------- материалы / текстуры ----------
func _tex_mat(col: Color, freq := 0.1, uvscale := 6.0, emit := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.frequency = freq
	nt.noise = fn
	nt.seamless = true
	nt.width = 128
	nt.height = 128
	m.albedo_texture = nt
	m.uv1_scale = Vector3(uvscale, uvscale, uvscale)
	if emit:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 2.5
	return m


func _plain_mat(col: Color, emit := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if emit:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 2.5
	return m


# ---------- окружение ----------
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.04, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.25, 0.4)
	env.ambient_light_energy = 0.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.05, 0.11)
	env.fog_density = 0.025
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_energy = 0.3
	moon.light_color = Color(0.7, 0.78, 1.0)
	moon.rotation_degrees = Vector3(-50, -120, 0)
	add_child(moon)


func _build_ground() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(WORLD * 2.6, WORLD * 2.6)
	mi.mesh = pm
	mi.material_override = _tex_mat(Color(0.1, 0.16, 0.09), 0.08, 26.0)
	add_child(mi)


# ---------- деревья (3 вида, MultiMesh для скорости) ----------
func _add_multimesh(mesh: Mesh, mat: Material, transforms: Array) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


func _build_trees() -> void:
	var pine_trunk: Array = []
	var pine_can: Array = []
	var oak_trunk: Array = []
	var oak_can: Array = []
	var birch_trunk: Array = []
	var birch_can: Array = []

	for i in TREE_COUNT:
		var x := randf_range(-WORLD, WORLD)
		var z := randf_range(-WORLD, WORLD)
		if Vector2(x, z).length() < 6.0:
			continue
		var s := randf_range(0.8, 1.4)
		var b := Basis(Vector3.UP, randf() * TAU).scaled(Vector3(s, s, s))
		var t := randi() % 3
		if t == 0:
			pine_trunk.append(Transform3D(b, Vector3(x, 1.1 * s, z)))
			pine_can.append(Transform3D(b, Vector3(x, 3.4 * s, z)))
		elif t == 1:
			oak_trunk.append(Transform3D(b, Vector3(x, 1.2 * s, z)))
			oak_can.append(Transform3D(b, Vector3(x, 3.0 * s, z)))
		else:
			birch_trunk.append(Transform3D(b, Vector3(x, 1.5 * s, z)))
			birch_can.append(Transform3D(b, Vector3(x, 3.6 * s, z)))

	var bark := _tex_mat(Color(0.3, 0.21, 0.12), 0.12, 3.0)
	var birch_bark := _tex_mat(Color(0.82, 0.83, 0.78), 0.12, 3.0)
	var pine_leaf := _tex_mat(Color(0.08, 0.2, 0.11), 0.15, 4.0)
	var oak_leaf := _tex_mat(Color(0.13, 0.27, 0.13), 0.15, 4.0)
	var birch_leaf := _tex_mat(Color(0.16, 0.3, 0.14), 0.15, 4.0)

	var pine_trunk_mesh := CylinderMesh.new()
	pine_trunk_mesh.top_radius = 0.18
	pine_trunk_mesh.bottom_radius = 0.28
	pine_trunk_mesh.height = 2.2
	var pine_can_mesh := CylinderMesh.new()
	pine_can_mesh.top_radius = 0.0
	pine_can_mesh.bottom_radius = 1.4
	pine_can_mesh.height = 3.0

	var oak_trunk_mesh := CylinderMesh.new()
	oak_trunk_mesh.top_radius = 0.32
	oak_trunk_mesh.bottom_radius = 0.5
	oak_trunk_mesh.height = 2.4
	var oak_can_mesh := SphereMesh.new()
	oak_can_mesh.radius = 1.8
	oak_can_mesh.height = 3.6

	var birch_trunk_mesh := CylinderMesh.new()
	birch_trunk_mesh.top_radius = 0.12
	birch_trunk_mesh.bottom_radius = 0.16
	birch_trunk_mesh.height = 3.0
	var birch_can_mesh := SphereMesh.new()
	birch_can_mesh.radius = 1.0
	birch_can_mesh.height = 2.0

	_add_multimesh(pine_trunk_mesh, bark, pine_trunk)
	_add_multimesh(pine_can_mesh, pine_leaf, pine_can)
	_add_multimesh(oak_trunk_mesh, bark, oak_trunk)
	_add_multimesh(oak_can_mesh, oak_leaf, oak_can)
	_add_multimesh(birch_trunk_mesh, birch_bark, birch_trunk)
	_add_multimesh(birch_can_mesh, birch_leaf, birch_can)


# ---------- осколки (кристаллы) ----------
func _build_shards() -> void:
	var mat := _plain_mat(Color(1.0, 0.85, 0.3), true)
	for i in SHARD_COUNT:
		var x := randf_range(-WORLD + 6, WORLD - 6)
		var z := randf_range(-WORLD + 6, WORLD - 6)
		var n := Node3D.new()
		n.position = Vector3(x, 1.0, z)

		var up_cone := MeshInstance3D.new()
		var uc := CylinderMesh.new()
		uc.top_radius = 0.0
		uc.bottom_radius = 0.22
		uc.height = 0.5
		up_cone.mesh = uc
		up_cone.material_override = mat
		up_cone.position.y = 0.25
		n.add_child(up_cone)

		var dn_cone := MeshInstance3D.new()
		var dc := CylinderMesh.new()
		dc.top_radius = 0.0
		dc.bottom_radius = 0.22
		dc.height = 0.5
		dn_cone.mesh = dc
		dn_cone.material_override = mat
		dn_cone.position.y = -0.25
		dn_cone.rotation_degrees = Vector3(180, 0, 0)
		n.add_child(dn_cone)

		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.3)
		l.light_energy = 1.6
		l.omni_range = 8.0
		n.add_child(l)

		add_child(n)
		shards.append(n)


# ---------- оборотни ----------
func _build_wolves() -> void:
	var fur := _tex_mat(Color(0.13, 0.11, 0.1), 0.3, 2.0)
	var eye_mat := _plain_mat(Color(1.0, 0.1, 0.05), true)
	for i in WOLF_COUNT:
		var ang := TAU * float(i) / float(WOLF_COUNT)
		var r := randf_range(35.0, 60.0)
		var n := Node3D.new()
		n.position = Vector3(cos(ang) * r, 0, sin(ang) * r)

		var torso := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.6, 0.55, 1.1)
		torso.mesh = tb
		torso.material_override = fur
		torso.position = Vector3(0, 0.85, 0)
		n.add_child(torso)

		var head := MeshInstance3D.new()
		var hb := BoxMesh.new()
		hb.size = Vector3(0.42, 0.42, 0.42)
		head.mesh = hb
		head.material_override = fur
		head.position = Vector3(0, 1.05, -0.6)
		n.add_child(head)

		var snout := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.2, 0.2, 0.3)
		snout.mesh = sb
		snout.material_override = fur
		snout.position = Vector3(0, 0.98, -0.85)
		n.add_child(snout)

		for ex in [-0.13, 0.13]:
			var ear := MeshInstance3D.new()
			var pr := PrismMesh.new()
			pr.size = Vector3(0.16, 0.24, 0.08)
			ear.mesh = pr
			ear.material_override = fur
			ear.position = Vector3(ex, 1.32, -0.5)
			n.add_child(ear)

		for ex2 in [-0.1, 0.1]:
			var eye := MeshInstance3D.new()
			var es := SphereMesh.new()
			es.radius = 0.06
			es.height = 0.12
			eye.mesh = es
			eye.material_override = eye_mat
			eye.position = Vector3(ex2, 1.08, -0.82)
			n.add_child(eye)

		for lx in [-0.22, 0.22]:
			for lz in [-0.35, 0.35]:
				var leg := MeshInstance3D.new()
				var lc := CylinderMesh.new()
				lc.top_radius = 0.08
				lc.bottom_radius = 0.08
				lc.height = 0.7
				leg.mesh = lc
				leg.material_override = fur
				leg.position = Vector3(lx, 0.35, lz)
				n.add_child(leg)

		var tail := MeshInstance3D.new()
		var tc := CylinderMesh.new()
		tc.top_radius = 0.0
		tc.bottom_radius = 0.12
		tc.height = 0.7
		tail.mesh = tc
		tail.material_override = fur
		tail.rotation_degrees = Vector3(60, 0, 0)
		tail.position = Vector3(0, 1.0, 0.6)
		n.add_child(tail)

		add_child(n)
		wolves.append({"node": n, "target": _rand_target()})


func _rand_target() -> Vector3:
	var a := randf() * TAU
	var r := randf_range(8.0, WORLD - 6.0)
	return Vector3(cos(a) * r, 0, sin(a) * r)


# ---------- финальные ворота ----------
func _build_gate() -> void:
	gate = Node3D.new()
	gate.position = Vector3(0, 0, -WORLD * 0.7)
	var stone := _tex_mat(Color(0.32, 0.32, 0.36), 0.2, 2.0)

	for px in [-2.0, 2.0]:
		var pil := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.9, 5.0, 0.9)
		pil.mesh = pb
		pil.material_override = stone
		pil.position = Vector3(px, 2.5, 0)
		gate.add_child(pil)

	var beam := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(5.4, 0.9, 0.9)
	beam.mesh = bb
	beam.material_override = stone
	beam.position = Vector3(0, 5.4, 0)
	gate.add_child(beam)

	gate_core_mat = _plain_mat(Color(0.15, 0.15, 0.2))
	var core := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.6
	cm.height = 1.2
	core.mesh = cm
	core.material_override = gate_core_mat
	core.position = Vector3(0, 2.6, 0)
	gate.add_child(core)

	gate_light = OmniLight3D.new()
	gate_light.light_color = Color(0.5, 0.8, 1.0)
	gate_light.light_energy = 0.0
	gate_light.omni_range = 40.0
	gate_light.position = Vector3(0, 2.6, 0)
	gate.add_child(gate_light)

	add_child(gate)


func _activate_gate() -> void:
	gate_active = true
	gate_core_mat.emission_enabled = true
	gate_core_mat.emission = Color(0.5, 0.85, 1.0)
	gate_core_mat.emission_energy_multiplier = 4.0
	gate_light.light_energy = 4.0
	hud_msg.text = "Все осколки собраны! Иди к светящимся воротам!"


# ---------- игрок ----------
func _build_player() -> void:
	player = CharacterBody3D.new()
	player.position = Vector3.ZERO
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.6
	col.shape = cap
	col.position.y = 0.9
	player.add_child(col)

	cam = Camera3D.new()
	cam.position = Vector3(0, 1.6, 0)
	cam.fov = 75.0
	player.add_child(cam)

	flashlight = SpotLight3D.new()
	flashlight.light_energy = 4.0
	flashlight.light_color = Color(1.0, 0.95, 0.8)
	flashlight.spot_range = 30.0
	flashlight.spot_angle = 35.0
	cam.add_child(flashlight)

	add_child(player)


# ---------- интерфейс ----------
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)

	hud_count = Label.new()
	hud_count.position = Vector2(20, 20)
	hud_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_count.add_theme_font_size_override("font_size", 28)
	layer.add_child(hud_count)

	hud_msg = Label.new()
	hud_msg.position = Vector2(20, 60)
	hud_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_msg.add_theme_font_size_override("font_size", 22)
	layer.add_child(hud_msg)

	var hint := Label.new()
	hint.position = Vector2(20, 100)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_size_override("font_size", 16)
	hint.text = "Слева — идти, справа — смотреть"
	layer.add_child(hint)

	var btn := Button.new()
	btn.text = "Фонарь"
	btn.anchor_left = 1.0
	btn.anchor_top = 1.0
	btn.anchor_right = 1.0
	btn.anchor_bottom = 1.0
	btn.offset_left = -170.0
	btn.offset_top = -120.0
	btn.offset_right = -20.0
	btn.offset_bottom = -20.0
	btn.pressed.connect(_toggle_light)
	layer.add_child(btn)

	_update_hud()


func _make_overlay(title: String, subtitle: String, btn_text: String, cb: Callable) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	c.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(center)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	center.add_child(vb)

	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 46)
	vb.add_child(t)

	var st := Label.new()
	st.text = subtitle
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.add_theme_font_size_override("font_size", 20)
	vb.add_child(st)

	var b := Button.new()
	b.text = btn_text
	b.custom_minimum_size = Vector2(240, 72)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(cb)
	vb.add_child(b)

	return c


func _build_menu() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Menu"
	add_child(layer)

	end_title = Label.new()
	end_panel = _make_overlay("", "Нажми, чтобы начать заново", "Заново", _on_restart)
	# заменим заголовок на сохранённую ссылку, чтобы менять текст
	var center := end_panel.get_child(1) as CenterContainer
	var vb := center.get_child(0) as VBoxContainer
	end_title = vb.get_child(0) as Label
	end_panel.hide()
	layer.add_child(end_panel)

	menu_panel = _make_overlay("FOREST ESCAPE", "Собери 5 осколков и дойди до ворот. Берегись оборотней!", "Играть", _on_play)
	layer.add_child(menu_panel)


func _on_play() -> void:
	menu_panel.hide()
	running = true


func _on_restart() -> void:
	get_tree().reload_current_scene()


func _toggle_light() -> void:
	flashlight.visible = not flashlight.visible


func _update_hud() -> void:
	hud_count.text = "Осколки: %d / %d" % [collected, SHARD_COUNT]


# ---------- ввод ----------
func _unhandled_input(event: InputEvent) -> void:
	var half := get_viewport().get_visible_rect().size.x * 0.5
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < half and move_index == -1:
				move_index = event.index
				move_origin = event.position
			elif event.position.x >= half and look_index == -1:
				look_index = event.index
		else:
			if event.index == move_index:
				move_index = -1
				move_vec = Vector2.ZERO
			if event.index == look_index:
				look_index = -1
	elif event is InputEventScreenDrag:
		if event.index == move_index:
			move_vec = ((event.position - move_origin) / 80.0).limit_length(1.0)
		elif event.index == look_index:
			yaw -= event.relative.x * SENS
			pitch = clamp(pitch - event.relative.y * SENS, -1.2, 1.2)


# ---------- игровой цикл ----------
func _physics_process(delta: float) -> void:
	if not running:
		return

	player.rotation.y = yaw
	cam.rotation.x = pitch

	var mv := move_vec
	if Input.is_key_pressed(KEY_W): mv.y = -1.0
	if Input.is_key_pressed(KEY_S): mv.y = 1.0
	if Input.is_key_pressed(KEY_A): mv.x = -1.0
	if Input.is_key_pressed(KEY_D): mv.x = 1.0

	var fwd := -player.global_transform.basis.z
	var right := player.global_transform.basis.x
	var dir := fwd * (-mv.y) + right * mv.x
	dir.y = 0.0
	if dir.length() > 0.01:
		dir = dir.normalized()
	player.velocity = dir * SPEED
	player.move_and_slide()

	var p := player.global_position
	var flat := Vector2(p.x, p.z)
	if flat.length() > WORLD:
		flat = flat.normalized() * WORLD
		player.global_position = Vector3(flat.x, p.y, flat.y)

	var tms := Time.get_ticks_msec() / 1000.0
	for s in shards:
		if s != null:
			s.rotate_y(delta * 1.5)
			s.position.y = 1.0 + sin(tms * 2.0 + s.position.x) * 0.15

	_check_shards()
	_update_wolves(delta)

	if gate_active and player.global_position.distance_to(gate.global_position) < 3.5:
		_win()


func _check_shards() -> void:
	if gate_active:
		return
	var pp := player.global_position
	for i in range(shards.size()):
		var s = shards[i]
		if s == null:
			continue
		if pp.distance_to(s.global_position) < 1.6:
			s.queue_free()
			shards[i] = null
			collected += 1
			_update_hud()
			if collected >= SHARD_COUNT:
				_activate_gate()


func _update_wolves(delta: float) -> void:
	var pp := player.global_position
	for w in wolves:
		var n: Node3D = w["node"]
		var to_p := pp - n.global_position
		to_p.y = 0.0
		var dist := to_p.length()
		var det := WOLF_DETECT_LIT if flashlight.visible else WOLF_DETECT_DARK
		var dir := Vector3.ZERO
		var speed := WOLF_WANDER
		if dist < det:
			dir = to_p.normalized()
			speed = WOLF_SPEED
		else:
			var t: Vector3 = w["target"]
			var tt := t - n.global_position
			tt.y = 0.0
			if tt.length() < 2.0:
				w["target"] = _rand_target()
				tt = w["target"] - n.global_position
				tt.y = 0.0
			if tt.length() > 0.01:
				dir = tt.normalized()
		if dir.length() > 0.01:
			n.global_position += dir * speed * delta
			n.look_at(n.global_position + dir, Vector3.UP)
		if dist < WOLF_CATCH:
			_lose()


func _win() -> void:
	running = false
	end_title.text = "ПОБЕДА!"
	end_panel.show()


func _lose() -> void:
	running = false
	end_title.text = "ТЕБЯ ПОЙМАЛИ!"
	end_panel.show()
