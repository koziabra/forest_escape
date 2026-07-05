extends Node3D
# Forest Escape — v2.
# Большая карта с холмами, тысячи деревьев/кустов/цветов (MultiMesh),
# новые оборотни с анимацией ходьбы/бега, звёзды-осколки лежат на земле,
# портал с кармашком: вставил звезду — портал открылся на время, успей забежать.

const WORLD := 200.0            # радиус игрового мира
const TER_MARGIN := 40.0        # запас рельефа за краем мира
const HILL_HEIGHT := 8.0        # высота холмов
const TERRAIN_STEP := 4.0       # шаг сетки рельефа (меньше = детальнее, тяжелее)

const TREE_COUNT := 3500
const BUSH_COUNT := 2200
const FLOWER_COUNT := 3000
const SHARD_COUNT := 5
const WOLF_COUNT := 8

const SPEED := 6.5
const SENS := 0.005
const WOLF_DETECT_LIT := 20.0
const WOLF_DETECT_DARK := 6.0
const WOLF_SPEED := 5.4
const WOLF_WANDER := 2.4
const WOLF_CATCH := 1.5
const PORTAL_OPEN_SECS := 9.0   # сколько секунд портал открыт

var terrain_noise := FastNoiseLite.new()

var player: CharacterBody3D
var cam: Camera3D
var flashlight: SpotLight3D
var yaw := 0.0
var pitch := 0.0
var game_time := 0.0

var move_index := -1
var move_origin := Vector2.ZERO
var move_vec := Vector2.ZERO
var look_index := -1

var shards: Array = []
var wolves: Array = []
var collected := 0
var running := false

# --- портал / кармашек ---
var gate: Node3D
var portal_quad: MeshInstance3D
var portal_mat: StandardMaterial3D
var portal_light: OmniLight3D
var socket_star: Node3D
var portal_center := Vector3.ZERO
var socket_pos := Vector3.ZERO
var portal_open := false
var portal_time_left := 0.0

var hud_count: Label
var hud_msg: Label
var hud_timer: Label
var menu_panel: Control
var end_panel: Control
var end_title: Label


func _ready() -> void:
	_setup_noise()
	_build_environment()
	_build_terrain()
	_build_trees()
	_build_bushes()
	_build_flowers()
	_build_shards()
	_build_wolves()
	_build_gate()
	_build_player()
	_build_hud()
	_build_menu()


# ---------- рельеф / высота ----------
func _setup_noise() -> void:
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	terrain_noise.frequency = 0.006
	terrain_noise.fractal_octaves = 4
	terrain_noise.seed = 1337


func _terrain_y(x: float, z: float) -> float:
	return terrain_noise.get_noise_2d(x, z) * HILL_HEIGHT


# ---------- материалы / текстуры ----------
func _tex_mat(col: Color, freq := 0.1, uvscale := 6.0, emit := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.95
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
	m.roughness = 0.9
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
	env.ambient_light_color = Color(0.22, 0.27, 0.42)
	env.ambient_light_energy = 0.25
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.06, 0.13)
	env.fog_density = 0.012
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_energy = 0.35
	moon.light_color = Color(0.7, 0.78, 1.0)
	moon.rotation_degrees = Vector3(-50, -120, 0)
	add_child(moon)


# ---------- земля с холмами ----------
func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := -(WORLD + TER_MARGIN)
	var hi := WORLD + TER_MARGIN
	var x := lo
	while x < hi:
		var z := lo
		while z < hi:
			var x2 := x + TERRAIN_STEP
			var z2 := z + TERRAIN_STEP
			var p00 := Vector3(x, _terrain_y(x, z), z)
			var p10 := Vector3(x2, _terrain_y(x2, z), z)
			var p01 := Vector3(x, _terrain_y(x, z2), z2)
			var p11 := Vector3(x2, _terrain_y(x2, z2), z2)
			_terrain_tri(st, p00, p01, p11)
			_terrain_tri(st, p00, p11, p10)
			z += TERRAIN_STEP
		x += TERRAIN_STEP
	st.generate_normals()
	var mesh := st.commit()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := _tex_mat(Color(1.0, 1.0, 1.0), 0.08, 40.0)
	mat.vertex_color_use_as_albedo = true
	mi.material_override = mat
	add_child(mi)


func _terrain_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, b, c]:
		# цвет земли зависит от высоты: низины темнее, холмы светлее
		var t: float = clamp((v.y / HILL_HEIGHT) * 0.5 + 0.5, 0.0, 1.0)
		st.set_color(Color(0.09, 0.14, 0.08).lerp(Color(0.18, 0.24, 0.12), t))
		st.set_uv(Vector2(v.x, v.z) * 0.03)
		st.add_vertex(v)


# ---------- MultiMesh-помощники ----------
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


func _add_multimesh_colored(mesh: Mesh, mat: Material, transforms: Array, colors: Array) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


# ---------- деревья (сосны, дубы, берёзы) ----------
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
		if Vector2(x, z).length() < 7.0:
			continue
		var gy := _terrain_y(x, z)
		var s := randf_range(0.8, 1.6)
		var b := Basis(Vector3.UP, randf() * TAU).scaled(Vector3(s, s, s))
		var t := randi() % 3
		if t == 0:
			pine_trunk.append(Transform3D(b, Vector3(x, gy + 1.1 * s, z)))
			pine_can.append(Transform3D(b, Vector3(x, gy + 3.4 * s, z)))
		elif t == 1:
			oak_trunk.append(Transform3D(b, Vector3(x, gy + 1.2 * s, z)))
			oak_can.append(Transform3D(b, Vector3(x, gy + 3.2 * s, z)))
		else:
			birch_trunk.append(Transform3D(b, Vector3(x, gy + 1.5 * s, z)))
			birch_can.append(Transform3D(b, Vector3(x, gy + 3.6 * s, z)))

	var bark := _tex_mat(Color(0.3, 0.21, 0.12), 0.12, 3.0)
	var birch_bark := _tex_mat(Color(0.82, 0.83, 0.78), 0.12, 3.0)
	var pine_leaf := _tex_mat(Color(0.07, 0.19, 0.10), 0.15, 4.0)
	var oak_leaf := _tex_mat(Color(0.14, 0.30, 0.13), 0.15, 4.0)
	var birch_leaf := _tex_mat(Color(0.17, 0.33, 0.15), 0.15, 4.0)

	var pine_trunk_mesh := CylinderMesh.new()
	pine_trunk_mesh.top_radius = 0.16
	pine_trunk_mesh.bottom_radius = 0.28
	pine_trunk_mesh.height = 2.2
	var pine_can_mesh := CylinderMesh.new()
	pine_can_mesh.top_radius = 0.0
	pine_can_mesh.bottom_radius = 1.5
	pine_can_mesh.height = 3.4

	var oak_trunk_mesh := CylinderMesh.new()
	oak_trunk_mesh.top_radius = 0.34
	oak_trunk_mesh.bottom_radius = 0.55
	oak_trunk_mesh.height = 2.6
	var oak_can_mesh := SphereMesh.new()
	oak_can_mesh.radius = 2.1
	oak_can_mesh.height = 4.0

	var birch_trunk_mesh := CylinderMesh.new()
	birch_trunk_mesh.top_radius = 0.11
	birch_trunk_mesh.bottom_radius = 0.16
	birch_trunk_mesh.height = 3.0
	var birch_can_mesh := SphereMesh.new()
	birch_can_mesh.radius = 1.1
	birch_can_mesh.height = 2.2

	_add_multimesh(pine_trunk_mesh, bark, pine_trunk)
	_add_multimesh(pine_can_mesh, pine_leaf, pine_can)
	_add_multimesh(oak_trunk_mesh, bark, oak_trunk)
	_add_multimesh(oak_can_mesh, oak_leaf, oak_can)
	_add_multimesh(birch_trunk_mesh, birch_bark, birch_trunk)
	_add_multimesh(birch_can_mesh, birch_leaf, birch_can)


# ---------- кусты ----------
func _build_bushes() -> void:
	var trans: Array = []
	var cols: Array = []
	for i in BUSH_COUNT:
		var x := randf_range(-WORLD, WORLD)
		var z := randf_range(-WORLD, WORLD)
		if Vector2(x, z).length() < 5.0:
			continue
		var gy := _terrain_y(x, z)
		var s := randf_range(0.6, 1.3)
		var b := Basis(Vector3.UP, randf() * TAU).scaled(Vector3(s, s * 0.8, s))
		trans.append(Transform3D(b, Vector3(x, gy + 0.35 * s, z)))
		var g := randf_range(0.16, 0.30)
		cols.append(Color(g * 0.5, g, g * 0.45))
	var mesh := SphereMesh.new()
	mesh.radius = 0.6
	mesh.height = 1.0
	var mat := _tex_mat(Color(1, 1, 1), 0.2, 2.0)
	mat.vertex_color_use_as_albedo = true
	_add_multimesh_colored(mesh, mat, trans, cols)


# ---------- цветы (стебель + бутон разных цветов) ----------
func _build_flowers() -> void:
	var stem_t: Array = []
	var bud_t: Array = []
	var bud_c: Array = []
	var palette := [
		Color(0.95, 0.3, 0.4), Color(0.95, 0.85, 0.35), Color(0.6, 0.4, 0.95),
		Color(0.95, 0.55, 0.25), Color(0.9, 0.9, 0.95), Color(0.4, 0.6, 0.95),
	]
	for i in FLOWER_COUNT:
		var x := randf_range(-WORLD, WORLD)
		var z := randf_range(-WORLD, WORLD)
		if Vector2(x, z).length() < 4.0:
			continue
		var gy := _terrain_y(x, z)
		var idn := Basis()
		stem_t.append(Transform3D(idn, Vector3(x, gy + 0.2, z)))
		bud_t.append(Transform3D(idn, Vector3(x, gy + 0.42, z)))
		bud_c.append(palette[randi() % palette.size()])
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.02
	stem_mesh.bottom_radius = 0.02
	stem_mesh.height = 0.4
	_add_multimesh(stem_mesh, _plain_mat(Color(0.2, 0.4, 0.16)), stem_t)
	var bud_mesh := SphereMesh.new()
	bud_mesh.radius = 0.12
	bud_mesh.height = 0.2
	var bud_mat := _plain_mat(Color(1, 1, 1))
	bud_mat.vertex_color_use_as_albedo = true
	bud_mat.emission_enabled = true
	bud_mat.emission = Color(1, 1, 1)
	bud_mat.emission_energy_multiplier = 0.35
	_add_multimesh_colored(bud_mesh, bud_mat, bud_t, bud_c)


# ---------- звезда-меш (лежит на земле) ----------
func _make_star_mesh(points: int, outer: float, inner: float, thickness: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points * 2
	var rim: Array = []
	for i in n:
		var ang := TAU * float(i) / float(n)
		var rad: float = outer if i % 2 == 0 else inner
		rim.append(Vector3(cos(ang) * rad, 0.0, sin(ang) * rad))
	var top := thickness * 0.5
	var bot := -thickness * 0.5
	for i in n:
		var a: Vector3 = rim[i]
		var b: Vector3 = rim[(i + 1) % n]
		# верхняя грань
		st.add_vertex(Vector3(0, top, 0))
		st.add_vertex(Vector3(a.x, top, a.z))
		st.add_vertex(Vector3(b.x, top, b.z))
		# нижняя грань
		st.add_vertex(Vector3(0, bot, 0))
		st.add_vertex(Vector3(b.x, bot, b.z))
		st.add_vertex(Vector3(a.x, bot, a.z))
		# боковая стенка
		st.add_vertex(Vector3(a.x, top, a.z))
		st.add_vertex(Vector3(b.x, top, b.z))
		st.add_vertex(Vector3(b.x, bot, b.z))
		st.add_vertex(Vector3(a.x, top, a.z))
		st.add_vertex(Vector3(b.x, bot, b.z))
		st.add_vertex(Vector3(a.x, bot, a.z))
	st.generate_normals()
	return st.commit()


# ---------- осколки-звёзды (лежат на земле) ----------
func _build_shards() -> void:
	var mat := _plain_mat(Color(1.0, 0.85, 0.3), true)
	mat.emission_energy_multiplier = 3.5
	var star_mesh := _make_star_mesh(5, 0.5, 0.2, 0.12)
	for i in SHARD_COUNT:
		var x := randf_range(-WORLD + 10, WORLD - 10)
		var z := randf_range(-WORLD + 10, WORLD - 10)
		var gy := _terrain_y(x, z)
		var n := Node3D.new()
		n.position = Vector3(x, gy + 0.08, z)

		var mi := MeshInstance3D.new()
		mi.mesh = star_mesh
		mi.material_override = mat
		n.add_child(mi)

		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.3)
		l.light_energy = 2.0
		l.omni_range = 10.0
		l.position.y = 0.6
		n.add_child(l)

		add_child(n)
		shards.append(n)


# ---------- оборотни ----------
func _build_wolves() -> void:
	var fur := _tex_mat(Color(0.12, 0.10, 0.10), 0.3, 2.0)
	var eye_mat := _plain_mat(Color(1.0, 0.1, 0.05), true)
	var leg_mesh := CylinderMesh.new()
	leg_mesh.top_radius = 0.09
	leg_mesh.bottom_radius = 0.07
	leg_mesh.height = 0.7

	for i in WOLF_COUNT:
		var ang := TAU * float(i) / float(WOLF_COUNT)
		var r := randf_range(40.0, WORLD - 20.0)
		var wx := cos(ang) * r
		var wz := sin(ang) * r
		var n := Node3D.new()
		n.position = Vector3(wx, _terrain_y(wx, wz), wz)

		# тело в отдельном узле, чтобы «покачивать» при беге
		var body := Node3D.new()
		n.add_child(body)

		var torso := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.55, 0.5, 1.2)
		torso.mesh = tb
		torso.material_override = fur
		torso.position = Vector3(0, 0.8, 0)
		body.add_child(torso)

		var neck := MeshInstance3D.new()
		var nb := BoxMesh.new()
		nb.size = Vector3(0.35, 0.4, 0.4)
		neck.mesh = nb
		neck.material_override = fur
		neck.position = Vector3(0, 0.9, -0.6)
		neck.rotation_degrees = Vector3(-25, 0, 0)
		body.add_child(neck)

		var head := MeshInstance3D.new()
		var hb := BoxMesh.new()
		hb.size = Vector3(0.38, 0.36, 0.44)
		head.mesh = hb
		head.material_override = fur
		head.position = Vector3(0, 1.08, -0.82)
		body.add_child(head)

		var snout := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.18, 0.18, 0.3)
		snout.mesh = sb
		snout.material_override = fur
		snout.position = Vector3(0, 1.0, -1.08)
		body.add_child(snout)

		for ex in [-0.13, 0.13]:
			var ear := MeshInstance3D.new()
			var pr := PrismMesh.new()
			pr.size = Vector3(0.16, 0.26, 0.08)
			ear.mesh = pr
			ear.material_override = fur
			ear.position = Vector3(ex, 1.34, -0.72)
			body.add_child(ear)

		for ex2 in [-0.1, 0.1]:
			var eye := MeshInstance3D.new()
			var es := SphereMesh.new()
			es.radius = 0.06
			es.height = 0.12
			eye.mesh = es
			eye.material_override = eye_mat
			eye.position = Vector3(ex2, 1.12, -1.02)
			body.add_child(eye)

		var tail := MeshInstance3D.new()
		var tc := CylinderMesh.new()
		tc.top_radius = 0.0
		tc.bottom_radius = 0.12
		tc.height = 0.8
		tail.mesh = tc
		tail.material_override = fur
		tail.rotation_degrees = Vector3(55, 0, 0)
		tail.position = Vector3(0, 0.95, 0.7)
		body.add_child(tail)

		# 4 лапы на шарнирах (порядок: FL, FR, BL, BR)
		var legs: Array = []
		var hips := [
			Vector3(-0.22, 0.72, -0.4), Vector3(0.22, 0.72, -0.4),
			Vector3(-0.22, 0.72, 0.4), Vector3(0.22, 0.72, 0.4),
		]
		for h in hips:
			var pivot := Node3D.new()
			pivot.position = h
			var leg := MeshInstance3D.new()
			leg.mesh = leg_mesh
			leg.material_override = fur
			leg.position = Vector3(0, -0.35, 0)
			pivot.add_child(leg)
			body.add_child(pivot)
			legs.append(pivot)

		add_child(n)
		wolves.append({
			"node": n, "body": body, "legs": legs,
			"target": _rand_target(), "phase": randf() * TAU, "run": false,
		})


func _rand_target() -> Vector3:
	var a := randf() * TAU
	var r := randf_range(8.0, WORLD - 6.0)
	return Vector3(cos(a) * r, 0, sin(a) * r)


# ---------- финальные ворота с порталом и кармашком ----------
func _build_gate() -> void:
	var gz := -WORLD * 0.7
	var gy := _terrain_y(0.0, gz)
	gate = Node3D.new()
	gate.position = Vector3(0, gy, gz)
	var stone := _tex_mat(Color(0.32, 0.32, 0.36), 0.2, 2.0)

	for px in [-2.2, 2.2]:
		var pil := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(1.0, 5.4, 1.0)
		pil.mesh = pb
		pil.material_override = stone
		pil.position = Vector3(px, 2.7, 0)
		gate.add_child(pil)

	var beam := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(5.8, 1.0, 1.0)
	beam.mesh = bb
	beam.material_override = stone
	beam.position = Vector3(0, 5.8, 0)
	gate.add_child(beam)

	# поверхность портала (появляется, когда открыт)
	portal_mat = _plain_mat(Color(0.4, 0.75, 1.0), true)
	portal_mat.emission_energy_multiplier = 3.0
	portal_mat.albedo_color = Color(0.2, 0.5, 0.95, 0.85)
	portal_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	portal_quad = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(3.6, 4.8)
	portal_quad.mesh = qm
	portal_quad.material_override = portal_mat
	portal_quad.position = Vector3(0, 2.6, 0)
	portal_quad.visible = false
	gate.add_child(portal_quad)

	portal_light = OmniLight3D.new()
	portal_light.light_color = Color(0.4, 0.7, 1.0)
	portal_light.light_energy = 0.3
	portal_light.omni_range = 45.0
	portal_light.position = Vector3(0, 2.6, 0)
	gate.add_child(portal_light)

	# кармашек (пьедестал перед воротами)
	var ped := MeshInstance3D.new()
	var pedb := BoxMesh.new()
	pedb.size = Vector3(1.0, 1.0, 1.0)
	ped.mesh = pedb
	ped.material_override = stone
	ped.position = Vector3(0, 0.5, 5.0)
	gate.add_child(ped)

	# звезда, которая «вставится» в кармашек (пока скрыта)
	socket_star = Node3D.new()
	var ss_mat := _plain_mat(Color(1.0, 0.85, 0.3), true)
	ss_mat.emission_energy_multiplier = 4.0
	var ss_mi := MeshInstance3D.new()
	ss_mi.mesh = _make_star_mesh(5, 0.35, 0.14, 0.1)
	ss_mi.material_override = ss_mat
	ss_mi.rotation_degrees = Vector3(90, 0, 0)
	socket_star.add_child(ss_mi)
	socket_star.position = Vector3(0, 1.3, 5.0)
	socket_star.visible = false
	gate.add_child(socket_star)

	add_child(gate)
	portal_center = gate.global_position + Vector3(0, 2.6, 0)
	socket_pos = gate.global_position + Vector3(0, 1.0, 5.0)


func _open_portal() -> void:
	portal_open = true
	portal_time_left = PORTAL_OPEN_SECS
	portal_quad.visible = true
	portal_light.light_energy = 5.0
	socket_star.visible = true
	hud_msg.text = "Портал открыт! Успей забежать!"


func _close_portal() -> void:
	portal_open = false
	portal_quad.visible = false
	portal_light.light_energy = 0.3
	hud_timer.text = ""
	hud_msg.text = "Портал закрылся! Вернись к кармашку и вставь звезду снова."


# ---------- игрок ----------
func _build_player() -> void:
	player = CharacterBody3D.new()
	player.position = Vector3(0, _terrain_y(0, 0), 0)
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
	cam.far = 400.0
	player.add_child(cam)

	flashlight = SpotLight3D.new()
	flashlight.light_energy = 4.5
	flashlight.light_color = Color(1.0, 0.95, 0.8)
	flashlight.spot_range = 32.0
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

	hud_timer = Label.new()
	hud_timer.position = Vector2(20, 96)
	hud_timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_timer.add_theme_font_size_override("font_size", 26)
	hud_timer.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	layer.add_child(hud_timer)

	var hint := Label.new()
	hint.position = Vector2(20, 136)
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

	end_panel = _make_overlay("", "Нажми, чтобы начать заново", "Заново", _on_restart)
	var center := end_panel.get_child(1) as CenterContainer
	var vb := center.get_child(0) as VBoxContainer
	end_title = vb.get_child(0) as Label
	end_panel.hide()
	layer.add_child(end_panel)

	menu_panel = _make_overlay("FOREST ESCAPE", "Собери 5 звёзд, вставь их в кармашек у ворот и успей забежать в портал. Берегись оборотней!", "Играть", _on_play)
	layer.add_child(menu_panel)


func _on_play() -> void:
	menu_panel.hide()
	running = true


func _on_restart() -> void:
	get_tree().reload_current_scene()


func _toggle_light() -> void:
	flashlight.visible = not flashlight.visible


func _update_hud() -> void:
	hud_count.text = "Звёзды: %d / %d" % [collected, SHARD_COUNT]


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
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * SENS
		pitch = clamp(pitch - event.relative.y * SENS, -1.2, 1.2)


# ---------- игровой цикл ----------
func _physics_process(delta: float) -> void:
	if not running:
		return
	game_time += delta

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

	var pos := player.global_position + dir * SPEED * delta
	var flat := Vector2(pos.x, pos.z)
	if flat.length() > WORLD:
		flat = flat.normalized() * WORLD
		pos.x = flat.x
		pos.z = flat.y
	pos.y = _terrain_y(pos.x, pos.z)
	player.global_position = pos

	for s in shards:
		if s != null:
			s.rotate_y(delta * 0.9)

	_check_shards()
	_update_wolves(delta)
	_animate_wolves()
	_update_portal(delta)


func _check_shards() -> void:
	var pp := player.global_position
	for i in range(shards.size()):
		var s = shards[i]
		if s == null:
			continue
		var d := Vector2(pp.x - s.global_position.x, pp.z - s.global_position.z)
		if d.length() < 1.8:
			s.queue_free()
			shards[i] = null
			collected += 1
			_update_hud()
			if collected >= SHARD_COUNT:
				hud_msg.text = "Все звёзды собраны! Неси их к кармашку у ворот!"


func _update_portal(delta: float) -> void:
	var pp := player.global_position
	# вставка звезды в кармашек → открытие портала
	if collected >= SHARD_COUNT and not portal_open:
		if pp.distance_to(socket_pos) < 3.5:
			_open_portal()

	if portal_open:
		portal_time_left -= delta
		portal_mat.emission_energy_multiplier = 3.0 + sin(game_time * 6.0) * 1.5
		portal_quad.rotation.z = game_time * 0.6
		hud_timer.text = "До закрытия: %0.1f сек" % max(portal_time_left, 0.0)
		if pp.distance_to(portal_center) < 2.8:
			_win()
		elif portal_time_left <= 0.0:
			_close_portal()


func _update_wolves(delta: float) -> void:
	var pp := player.global_position
	for w in wolves:
		var n: Node3D = w["node"]
		var to_p := pp - n.global_position
		to_p.y = 0.0
		var dist := to_p.length()
		var det: float = WOLF_DETECT_LIT if flashlight.visible else WOLF_DETECT_DARK
		var dir := Vector3.ZERO
		var speed := WOLF_WANDER
		w["run"] = false
		if dist < det:
			dir = to_p.normalized()
			speed = WOLF_SPEED
			w["run"] = true
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
			var np := n.global_position + dir * speed * delta
			np.y = _terrain_y(np.x, np.z)
			n.global_position = np
			var look := np + dir
			look.y = np.y
			n.look_at(look, Vector3.UP)
		if dist < WOLF_CATCH:
			_lose()


func _animate_wolves() -> void:
	for w in wolves:
		var legs: Array = w["legs"]
		var body: Node3D = w["body"]
		var phase: float = w["phase"]
		var amp: float = 0.9 if w["run"] else 0.4
		var spd: float = 13.0 if w["run"] else 6.0
		for idx in legs.size():
			var pivot: Node3D = legs[idx]
			var off: float = 0.0 if (idx == 0 or idx == 3) else PI
			pivot.rotation.x = sin(game_time * spd + phase + off) * amp
		# лёгкое покачивание тела при беге
		var bob: float = 0.08 if w["run"] else 0.03
		body.position.y = abs(sin(game_time * spd + phase)) * bob


func _win() -> void:
	running = false
	end_title.text = "ПОБЕДА!"
	end_panel.show()


func _lose() -> void:
	running = false
	end_title.text = "ТЕБЯ ПОЙМАЛИ!"
	end_panel.show()
