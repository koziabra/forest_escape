extends Node3D
# Forest Escape — Godot-порт HTML-версии v20.
# Пологий холмистый лес, ели/лиственные/сухие деревья, парящие осколки-тетраэдры,
# двуногие оборотни (бег/дыхание/вой/пульс глаз), ворота со столбом света и пьедесталом,
# градиентное небо с луной и звёздами, туман, светлячки, дымка, свечение (bloom).

const WORLD := 240.0
const EYE := 1.6
const PLAYER_SPEED := 5.0       # обычная ходьба
const SPRINT_SPEED := 9.0       # спринт (Shift)
const JUMP_VELOCITY := 5.4      # прыжок (Space)
const GRAVITY := 15.0
const MAX_HEALTH := 3
const PLAYER_R := 0.4
const TREE_COUNT := 4000
const SHARD_COUNT := 5
const WOLF_COUNT := 6
const WOLF_DETECT_LIT := 22.0
const WOLF_DETECT_DARK := 6.5
const WOLF_CATCH := 1.6
const WOLF_WANDER_SPEED := 2.8
const WOLF_CHASE_SPEED := 6.0
const ALERT_RADIUS := 28.0
const SEARCH_TIME := 9.0
const SENS := 0.005
const BATTERY_DRAIN := 1.0 / 200.0
const STAMINA_DRAIN := 1.0 / 13.0    # спринт на ~13 сек
const STAMINA_REGEN := 1.0 / 7.0     # полное восстановление ~7 сек
const TREE_R := 0.55
const BRANCH_COUNT := 26
const DISTRACT_RADIUS := 24.0

var player: Node3D
var cam: Camera3D
var flashlight: SpotLight3D
var yaw := 0.0
var pitch := 0.0
var bob_phase := 0.0
var game_time := 0.0
var player_vel := Vector3.ZERO
var crouching := false
var sprinting := false
var stamina := 1.0
var stamina_exhausted := false
var cam_eye := EYE
var jump_h := 0.0
var jump_vy := 0.0
var was_airborne := false
var health := MAX_HEALTH
var invuln := 0.0
var hidden := false
var bush_grid: Dictionary = {}
var heartbeat_t := 0.0

var move_index := -1
var move_origin := Vector2.ZERO
var move_vec := Vector2.ZERO
var look_index := -1

var shards: Array = []
var wolves: Array = []
var collected := 0
var running := false
var ended := false
var light_on := true
var battery := 1.0

var phase := "collect"           # collect → escape
var gate: Node3D = null
var carry_star: Node3D = null
var exit_pos := Vector3.ZERO
var inserted := 0
var gate_arm_mats: Array = []

var glow_tex: GradientTexture2D
var tetra_mesh: ArrayMesh
var shard_frag_mesh: ArrayMesh
var star_mesh: ArrayMesh
var grass_img_tex: ImageTexture
var foliage_img_tex: ImageTexture
var bark_img_tex: ImageTexture

# атмосфера
var fireflies_mm: MultiMesh
var ff_base: PackedVector3Array = PackedVector3Array()
var ff_phase: PackedFloat32Array = PackedFloat32Array()
var mist: Array = []

# столкновения с деревьями (пространственная сетка)
var tree_grid: Dictionary = {}
const GRID_CELL := 6.0
var grid_origin := 0.0

# ветки-приманки
var branch_count := 0
var branch_pickups: Array = []
var thrown_branches: Array = []
var branch_mesh: ArrayMesh
var throw_btn: Button

# звук (синтез)
var audio_players: Array = []
var audio_idx := 0
var wind_player: AudioStreamPlayer
var step_time := 0.0
var any_chasing := false

# HUD
var hud_count: Label
var inv_slots: Array = []
var hud_msg: Label
var status_timer := 0.0
var battery_fill: ColorRect
var stamina_fill: ColorRect
var health_slots: Array = []
var damage_rect: ColorRect
var light_btn: Button
var menu_panel: Control
var end_panel: Control
var end_title: Label
var end_msg: Label


func _ready() -> void:
	var _icon := Image.new()
	if _icon.load("res://icon.png") == OK:
		DisplayServer.set_icon(_icon)
	get_window().title = "Forest Escape"
	glow_tex = _make_glow_tex()
	grass_img_tex = _grass_img()
	foliage_img_tex = _foliage_img()
	bark_img_tex = _bark_img()
	tetra_mesh = _make_tetra_mesh(0.36)
	shard_frag_mesh = _make_shard_fragment()
	star_mesh = _make_star_mesh(5, 0.5, 0.21, 0.16)
	_build_environment()
	_build_terrain()
	_build_trees()
	_build_grass()
	_build_rocks()
	_build_leaves()
	_build_logs()
	_build_mushrooms()
	_build_bushes()
	_build_flowers()
	_build_shards()
	_build_wolves()
	_build_branches()
	_build_fireflies()
	_build_player()
	_build_hud()
	_build_menu()


# ---------- высота рельефа (пологие волны, как в HTML) ----------
func _terrain_h(x: float, z: float) -> float:
	return sin(x * 0.045) * 2.8 + cos(z * 0.05) * 2.8 + sin((x + z) * 0.025) * 1.8 + cos(x * 0.12 - z * 0.1) * 0.9


# ---------- текстуры ----------
func _make_glow_tex() -> GradientTexture2D:
	var g := Gradient.new()
	# профиль как в HTML (яркое ядро → мягкое затухание), но в чёрный — чтобы круг, а не квадрат
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.35, Color(0.6, 0.6, 0.6, 0.55))
	g.set_color(1, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	return gt


# закрашивает прямоугольник (с заворотом по краям) — «квадратик» пятна
func _blot(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	var iw := img.get_width()
	var ih := img.get_height()
	for dy in h:
		for dx in w:
			img.set_pixel((x + dx) % iw, (y + dy) % ih, col)


func _blot_circle(img: Image, cx: int, cy: int, r: int, col: Color) -> void:
	var iw := img.get_width()
	var ih := img.get_height()
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				img.set_pixel((cx + dx + iw * 4) % iw, (cy + dy + ih * 4) % ih, col)


# земля — зелёные «камешки» с коричневыми промежутками
func _grass_img() -> ImageTexture:
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.22, 0.14, 0.08))   # коричневые промежутки (земля между камешками)
	var step := 20
	var gy := 0
	while gy < s + step:
		var gx := 0
		while gx < s + step:
			var cx := gx + (randi() % 9 - 4)
			var cy := gy + (randi() % 9 - 4)
			var r := 11 + randi() % 4
			var g := randf_range(0.09, 0.21)
			_blot_circle(img, cx, cy, r, Color(g * 0.5, g, g * 0.42))
			gx += step
		gy += step
	return ImageTexture.create_from_image(img)


# листва — мозаика из мелких пятен-«листьев»
func _foliage_img() -> ImageTexture:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.32, 0.45, 0.26))
	for i in 340:
		var g := randf_range(0.44, 0.68)
		var col := Color(randf_range(0.24, 0.38), g, randf_range(0.26, 0.40))
		_blot(img, randi() % s, randi() % s, 2 + randi() % 3, 2 + randi() % 3, col)
	return ImageTexture.create_from_image(img)


# кора — вертикальные штрихи-квадратики
func _bark_img() -> ImageTexture:
	var w := 64
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.24, 0.19, 0.13))
	for i in 70:
		var v := randf_range(0.16, 0.30)
		var col := Color(v, v * 0.8, v * 0.55)
		var cx := randi() % w
		var y := 0
		while y < h:
			_blot(img, (cx + (randi() % 3 - 1) + w) % w, y, 2, 8, col)
			y += 8
	return ImageTexture.create_from_image(img)


# луна — светлый диск с тёмными «морями» и кратерами
func _moon_img() -> ImageTexture:
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.93, 0.94, 0.99))
	for i in 44:
		var d := randf_range(0.70, 0.85)
		_blot(img, randi() % s, randi() % s, 6 + randi() % 18, 6 + randi() % 18, Color(d, d, d * 1.03))
	for i in 130:
		var d := randf_range(0.62, 0.80)
		_blot(img, randi() % s, randi() % s, 2 + randi() % 4, 2 + randi() % 4, Color(d, d, d))
	return ImageTexture.create_from_image(img)


func _img_mat(tex: Texture2D, uvscale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.uv1_scale = Vector3(uvscale, uvscale, uvscale)
	m.roughness = 1.0
	return m


func _noise_tex(freq: float) -> NoiseTexture2D:
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.frequency = freq
	nt.noise = fn
	nt.seamless = true
	nt.width = 128
	nt.height = 128
	return nt


func _tex_mat(col: Color, freq := 0.1, uvscale := 6.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.98
	m.albedo_texture = _noise_tex(freq)
	m.uv1_scale = Vector3(uvscale, uvscale, uvscale)
	return m


# ---------- окружение: небо, луна, звёзды, свет, туман, свечение ----------
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.01, 0.015, 0.04)
	sky_mat.sky_horizon_color = Color(0.04, 0.06, 0.14)
	sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.03)
	sky_mat.ground_horizon_color = Color(0.03, 0.05, 0.10)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.3

	# кинематографичный тонмаппинг — глубже тени, теплее свет
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.9

	# туман: гуще у земли (приземная дымка) + воздушная перспектива вдаль
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.03, 0.07)
	env.fog_light_energy = 1.0
	env.fog_density = 0.02
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.1
	env.fog_height = 16.0
	env.fog_height_density = 0.07

	# свечения (осколки, светлячки, луна) ярко выделяются в темноте
	env.glow_enabled = true
	env.glow_intensity = 0.95
	env.glow_bloom = 0.3
	env.glow_strength = 1.1
	env.glow_hdr_threshold = 0.8

	# лёгкая цветокоррекция — глубже контраст, богаче цвет
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12

	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.light_energy = 0.68
	moon.light_color = Color(0.62, 0.7, 0.9)
	moon.rotation_degrees = Vector3(-42, -120, 0)
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 90.0
	moon.shadow_bias = 0.06
	add_child(moon)

	# луна — яркий светящийся бело-голубой шар (bloom даёт мягкий ореол), как в HTML
	var moon_disc := MeshInstance3D.new()
	var msph := SphereMesh.new()
	msph.radius = 13.0
	msph.height = 26.0
	msph.radial_segments = 32
	msph.rings = 16
	moon_disc.mesh = msph
	var mmat := StandardMaterial3D.new()
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmat.albedo_color = Color(0.93, 0.96, 1.0)
	mmat.emission_enabled = true
	mmat.emission = Color(0.87, 0.93, 1.0)
	mmat.emission_energy_multiplier = 8.0
	moon_disc.material_override = mmat
	moon_disc.position = Vector3(-160, 130, -240)
	moon_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(moon_disc)

	_build_stars()


func _build_stars() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 6
	sph.rings = 3
	mm.mesh = sph
	var n := 1600
	mm.instance_count = n
	for i in n:
		var a := randf() * TAU
		var e := randf_range(0.03, 1.55)
		var r := randf_range(300.0, 470.0)
		var pos := Vector3(cos(a) * cos(e) * r, sin(e) * r + 16.0, sin(a) * cos(e) * r)
		var sc := randf_range(0.6, 1.6)   # разный размер звёзд
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(sc, sc, sc)), pos))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.88, 0.92, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.88, 0.92, 1.0)
	m.emission_energy_multiplier = 5.0
	m.disable_receive_shadows = true
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


# ---------- земля ----------
func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lo := -(WORLD + 40.0)
	var hi := WORLD + 40.0
	var step := 5.0
	var x := lo
	while x < hi:
		var z := lo
		while z < hi:
			var x2 := x + step
			var z2 := z + step
			var p00 := Vector3(x, _terrain_h(x, z), z)
			var p10 := Vector3(x2, _terrain_h(x2, z), z)
			var p01 := Vector3(x, _terrain_h(x, z2), z2)
			var p11 := Vector3(x2, _terrain_h(x2, z2), z2)
			_terr_tri(st, p00, p01, p11)
			_terr_tri(st, p00, p11, p10)
			z += step
		x += step
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := _img_mat(grass_img_tex, 34.0)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# карта рельефа (bump) — как bumpMap в HTML: земля ловит свет неровностями
	var nrm := NoiseTexture2D.new()
	var nfn := FastNoiseLite.new()
	nfn.frequency = 0.2
	nrm.noise = nfn
	nrm.as_normal_map = true
	nrm.bump_strength = 2.0
	nrm.seamless = true
	nrm.width = 128
	nrm.height = 128
	mat.normal_enabled = true
	mat.normal_texture = nrm
	mat.normal_scale = 0.8
	mi.material_override = mat
	add_child(mi)


func _terr_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, b, c]:
		var t: float = clamp(v.y * 0.15 + 0.5, 0.0, 1.0)
		# нейтральный тон — чтобы цвета камешков/промежутков были настоящими
		st.set_color(Color(0.62, 0.62, 0.58).lerp(Color(0.8, 0.8, 0.74), t))
		st.set_uv(Vector2(v.x, v.z) * 0.03)
		st.add_vertex(v)


# ---------- MultiMesh ----------
func _add_mm(mesh: Mesh, mat: Material, transforms: Array, colors: Array = [], cast_shadow := true) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	if not colors.is_empty():
		mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		if not colors.is_empty():
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	if not cast_shadow:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


# ---------- деревья: ели (конусы), лиственные (кроны), сухие (только ствол) ----------
func _conifer_canopy() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 2.6
	for c in 4:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 1.5 - c * 0.28
		cone.height = 1.6
		cone.radial_segments = 8
		st.append_from(cone, 0, Transform3D(Basis(), Vector3(0, y, 0)))
		y += 0.8
	return st.commit()


func _broad_canopy() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var spots := [
		[0.0, 3.4, 0.0, 1.35], [0.85, 3.2, 0.2, 0.95], [-0.7, 3.3, -0.3, 1.0],
		[0.2, 3.95, -0.4, 0.9], [-0.35, 3.65, 0.65, 0.85], [0.45, 3.4, 0.5, 0.8],
	]
	for s in spots:
		var sph := SphereMesh.new()
		sph.radius = s[3]
		sph.height = s[3] * 2.0
		sph.radial_segments = 6
		sph.rings = 4
		st.append_from(sph, 0, Transform3D(Basis(), Vector3(s[0], s[1], s[2])))
	return st.commit()


func _build_trees() -> void:
	grid_origin = -(WORLD + 6.0)
	var trunk_t: Array = []
	var con_t: Array = []
	var con_c: Array = []
	var broad_t: Array = []
	var broad_c: Array = []

	for i in TREE_COUNT:
		var x := randf_range(-WORLD, WORLD)
		var z := randf_range(-WORLD, WORLD)
		if Vector2(x, z).length() < 8.0 or Vector2(x, z).length() > WORLD:
			continue
		var s := randf_range(0.8, 1.7)
		var b := Basis(Vector3.UP, randf() * TAU).scaled(Vector3(s, s, s))
		var tr := Transform3D(b, Vector3(x, _terrain_h(x, z), z))
		trunk_t.append(tr)
		_grid_add(x, z, TREE_R * s)
		var col := Color.from_hsv(0.28 + randf_range(-0.03, 0.05), 0.48, randf_range(0.2, 0.32))
		var r := randf()
		if r < 0.46:
			con_t.append(tr)
			con_c.append(col)
		elif r < 0.93:
			broad_t.append(tr)
			broad_c.append(col)
		# иначе — сухое дерево (только ствол)

	var bark := _img_mat(bark_img_tex, 1.0)
	bark.uv1_scale = Vector3(1, 2, 1)
	var foliage := _img_mat(foliage_img_tex, 2.0)
	foliage.vertex_color_use_as_albedo = true

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.16
	trunk_mesh.bottom_radius = 0.26
	trunk_mesh.height = 2.6
	var tst := SurfaceTool.new()
	tst.begin(Mesh.PRIMITIVE_TRIANGLES)
	tst.append_from(trunk_mesh, 0, Transform3D(Basis(), Vector3(0, 1.3, 0)))
	var trunk_based := tst.commit()

	_add_mm(trunk_based, bark, trunk_t)
	_add_mm(_conifer_canopy(), foliage, con_t, con_c)
	_add_mm(_broad_canopy(), foliage, broad_t, broad_c)


# ---------- трава (травинки, заполняют землю) ----------
func _make_grass_tuft() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base_col := Color(0.04, 0.08, 0.045)
	var tip_col := Color(0.07, 0.14, 0.07)
	for bi in 6:
		var ang := TAU * float(bi) / 6.0 + randf() * 0.5
		var dirx := cos(ang)
		var dirz := sin(ang)
		var w := 0.05
		var h := randf_range(0.18, 0.36)
		var lean := 0.14
		var px := -dirz * w
		var pz := dirx * w
		st.set_color(base_col); st.add_vertex(Vector3(px, 0, pz))
		st.set_color(base_col); st.add_vertex(Vector3(-px, 0, -pz))
		st.set_color(tip_col); st.add_vertex(Vector3(dirx * lean, h, dirz * lean))
	st.generate_normals()
	return st.commit()


func _build_grass() -> void:
	var trans: Array = []
	for i in 100000:
		var x := randf_range(-WORLD, WORLD)
		var z := randf_range(-WORLD, WORLD)
		var rr := Vector2(x, z).length()
		if rr > WORLD or rr < 3.0:
			continue
		var gy := _terrain_h(x, z)
		var s := randf_range(0.7, 1.5)
		var b := Basis(Vector3.UP, randf() * TAU).scaled(Vector3(s, s, s))
		trans.append(Transform3D(b, Vector3(x, gy, z)))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # травинки видны с обеих сторон
	mat.roughness = 1.0
	_add_mm(_make_grass_tuft(), mat, trans, [], false)


# ---------- камни (разнообразие на земле) ----------
func _build_rocks() -> void:
	var trans: Array = []
	var cols: Array = []
	for i in 1800:
		var x := randf_range(-WORLD, WORLD)
		var z := randf_range(-WORLD, WORLD)
		var rr := Vector2(x, z).length()
		if rr > WORLD or rr < 4.0:
			continue
		var gy := _terrain_h(x, z)
		var s := randf_range(0.15, 0.5)
		if randf() < 0.06:
			s = randf_range(0.8, 1.8)   # редкие валуны
		var axis := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5).normalized()
		var b := Basis(axis, randf() * TAU).scaled(Vector3(s, s * randf_range(0.55, 0.85), s))
		trans.append(Transform3D(b, Vector3(x, gy + s * 0.25, z)))
		var g := randf_range(0.16, 0.32)
		cols.append(Color(g, g * 0.98, g * 0.93))
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 5
	mesh.rings = 3
	var mat := _tex_mat(Color(1, 1, 1), 0.3, 1.2)
	mat.vertex_color_use_as_albedo = true
	_add_mm(mesh, mat, trans, cols, false)


# ---------- опавшие листья (плоские пятна на земле) ----------
func _build_leaves() -> void:
	var trans: Array = []
	var cols: Array = []
	var palette := [
		Color(0.34, 0.20, 0.09), Color(0.5, 0.30, 0.11), Color(0.44, 0.36, 0.13),
		Color(0.22, 0.28, 0.12), Color(0.4, 0.24, 0.10),
	]
	for i in 22000:
		var x := randf_range(-WORLD, WORLD)
		var z := randf_range(-WORLD, WORLD)
		var rr := Vector2(x, z).length()
		if rr > WORLD or rr < 3.0:
			continue
		var gy := _terrain_h(x, z)
		var s := randf_range(0.6, 1.3)
		var b := (Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, -PI / 2.0)).scaled(Vector3(s, s, s))
		trans.append(Transform3D(b, Vector3(x, gy + 0.03, z)))
		cols.append(palette[randi() % palette.size()])
	var q := QuadMesh.new()
	q.size = Vector2(0.28, 0.28)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	_add_mm(q, mat, trans, cols, false)


# ---------- упавшие брёвна ----------
func _build_logs() -> void:
	var trans: Array = []
	for i in 90:
		var x := randf_range(-WORLD, WORLD)
		var z := randf_range(-WORLD, WORLD)
		var rr := Vector2(x, z).length()
		if rr > WORLD or rr < 6.0:
			continue
		var gy := _terrain_h(x, z)
		var s := randf_range(0.8, 1.6)
		var yaw := randf() * TAU
		# положить цилиндр горизонтально + случайный поворот по земле
		var b := (Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), PI / 2.0)).scaled(Vector3(s, s, s))
		trans.append(Transform3D(b, Vector3(x, gy + 0.22 * s, z)))
		# коллизия: несколько точек вдоль бревна (игрок и оборотни огибают)
		var axis := Basis(Vector3.UP, yaw) * Vector3(-1, 0, 0)
		var half_len := 1.4 * s
		var col_r := 0.38 * s
		for k in [-1.0, -0.4, 0.4, 1.0]:
			_grid_add(x + axis.x * half_len * k, z + axis.z * half_len * k, col_r)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.2
	mesh.bottom_radius = 0.24
	mesh.height = 3.0
	var mat := _img_mat(bark_img_tex, 1.0)
	mat.uv1_scale = Vector3(1, 2, 1)
	_add_mm(mesh, mat, trans)


# ---------- грибы (ножка + шляпка) ----------
func _build_mushrooms() -> void:
	var stem_t: Array = []
	var cap_t: Array = []
	var cap_c: Array = []
	var palette := [
		Color(0.72, 0.16, 0.12), Color(0.55, 0.38, 0.22),
		Color(0.78, 0.70, 0.52), Color(0.48, 0.30, 0.44),
	]
	for i in 900:
		var x := randf_range(-WORLD, WORLD)
		var z := randf_range(-WORLD, WORLD)
		var rr := Vector2(x, z).length()
		if rr > WORLD or rr < 4.0:
			continue
		var gy := _terrain_h(x, z)
		var s := randf_range(0.5, 1.2)
		var yaw := Basis(Vector3.UP, randf() * TAU).scaled(Vector3(s, s, s))
		stem_t.append(Transform3D(yaw, Vector3(x, gy + 0.11 * s, z)))
		cap_t.append(Transform3D(yaw, Vector3(x, gy + 0.24 * s, z)))
		cap_c.append(palette[randi() % palette.size()])
	var stem := CylinderMesh.new()
	stem.top_radius = 0.035
	stem.bottom_radius = 0.05
	stem.height = 0.22
	stem.radial_segments = 6
	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.85, 0.82, 0.72)
	stem_mat.roughness = 0.9
	_add_mm(stem, stem_mat, stem_t, [], false)
	var cap := SphereMesh.new()
	cap.radius = 0.13
	cap.height = 0.18
	cap.radial_segments = 8
	cap.rings = 4
	var cap_mat := StandardMaterial3D.new()
	cap_mat.vertex_color_use_as_albedo = true
	cap_mat.roughness = 0.8
	_add_mm(cap, cap_mat, cap_t, cap_c, false)


# ---------- кусты ----------
func _build_bushes() -> void:
	var trans: Array = []
	var cols: Array = []
	var mesh_r := 1.0
	for i in 3600:
		var a := randf() * TAU
		var r := randf_range(8.0, WORLD - 4.0)
		var x := cos(a) * r
		var z := sin(a) * r
		var s := randf_range(1.0, 2.2)                 # крупнее — можно спрятаться
		var b := Basis(Vector3.UP, randf() * TAU).scaled(Vector3(s, s * 0.85, s))
		trans.append(Transform3D(b, Vector3(x, _terrain_h(x, z) + 0.4 * s, z)))
		cols.append(Color.from_hsv(0.28 + randf_range(-0.03, 0.05), 0.44, randf_range(0.18, 0.3)))
		_bush_add(x, z, mesh_r * s * 0.75)             # радиус укрытия
	var mesh := SphereMesh.new()
	mesh.radius = mesh_r
	mesh.height = mesh_r * 1.7
	mesh.radial_segments = 7
	mesh.rings = 5
	var mat := _img_mat(foliage_img_tex, 2.0)
	mat.vertex_color_use_as_albedo = true
	_add_mm(mesh, mat, trans, cols)


# ---------- цветы ----------
func _build_flowers() -> void:
	var stem_t: Array = []
	var bud_t: Array = []
	var bud_c: Array = []
	var palette := [
		Color(1.0, 0.36, 0.56), Color(1.0, 0.82, 0.29), Color(0.91, 0.91, 1.0),
		Color(0.61, 0.42, 1.0), Color(1.0, 0.55, 0.26), Color(0.4, 0.84, 1.0),
	]
	for i in 2400:
		var a := randf() * TAU
		var r := randf_range(6.0, WORLD - 4.0)
		var x := cos(a) * r
		var z := sin(a) * r
		var gy := _terrain_h(x, z)
		stem_t.append(Transform3D(Basis(), Vector3(x, gy + 0.2, z)))
		bud_t.append(Transform3D(Basis(), Vector3(x, gy + 0.42, z)))
		bud_c.append(palette[randi() % palette.size()])
	var stem := CylinderMesh.new()
	stem.top_radius = 0.015
	stem.bottom_radius = 0.02
	stem.height = 0.4
	_add_mm(stem, _tex_mat(Color(0.24, 0.42, 0.20), 0.2, 1.0), stem_t, [], false)
	var bud := SphereMesh.new()
	bud.radius = 0.12
	bud.height = 0.24
	bud.radial_segments = 6
	bud.rings = 4
	var bmat := StandardMaterial3D.new()
	bmat.vertex_color_use_as_albedo = true
	bmat.roughness = 0.8
	_add_mm(bud, bmat, bud_t, bud_c, false)


# ---------- меши: тетраэдр (осколок) и звезда ----------
func _make_tetra_mesh(size: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v := [
		Vector3(1, 1, 1) * size, Vector3(1, -1, -1) * size,
		Vector3(-1, 1, -1) * size, Vector3(-1, -1, 1) * size,
	]
	var faces := [[0, 1, 2], [0, 2, 3], [0, 3, 1], [1, 3, 2]]
	for f in faces:
		st.add_vertex(v[f[0]])
		st.add_vertex(v[f[1]])
		st.add_vertex(v[f[2]])
	st.generate_normals()
	return st.commit()


# луч звезды со случайным отломанным куском середины (каждый осколок уникален)
func _make_shard_ray() -> ArrayMesh:
	var hz := randf_range(0.05, 0.08)          # половина толщины
	var top := randf_range(0.52, 0.72)         # длина луча
	var w := randf_range(0.1, 0.15)            # полуширина (узкий луч)
	var s := 1.0 if randf() < 0.5 else -1.0    # сторона скола
	var bite := randf_range(0.28, 0.48)        # глубина скола
	var by := randf_range(0.22, 0.42)          # высота скола вдоль луча
	# профиль остриём вверх, маленький скол на верхней правой грани
	var pts: Array = [
		Vector2(0.0, top),
		Vector2(w, top * randf_range(0.44, 0.52)),
		Vector2(w * bite, top * (by + 0.06)),                 # скол внутрь
		Vector2(w * randf_range(0.85, 1.0), top * (by - 0.06)),
		Vector2(w * randf_range(0.5, 0.7), -0.2),
		Vector2(-w * randf_range(0.5, 0.7), -0.2),
		Vector2(-w * randf_range(0.85, 1.0), top * randf_range(0.4, 0.5)),
	]
	var poly := PackedVector2Array()
	for p in pts:
		poly.append(Vector2(p.x * s, p.y))     # отразить скол на случайную сторону
	var idx := Geometry2D.triangulate_polygon(poly)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# передняя и задняя грань
	var tri := idx.size() / 3
	for t in tri:
		var a: Vector2 = poly[idx[t * 3]]
		var b: Vector2 = poly[idx[t * 3 + 1]]
		var c: Vector2 = poly[idx[t * 3 + 2]]
		st.add_vertex(Vector3(a.x, a.y, hz)); st.add_vertex(Vector3(b.x, b.y, hz)); st.add_vertex(Vector3(c.x, c.y, hz))
		st.add_vertex(Vector3(a.x, a.y, -hz)); st.add_vertex(Vector3(c.x, c.y, -hz)); st.add_vertex(Vector3(b.x, b.y, -hz))
	# боковые грани
	var n := poly.size()
	for i in n:
		var p0: Vector2 = poly[i]
		var p1: Vector2 = poly[(i + 1) % n]
		st.add_vertex(Vector3(p0.x, p0.y, hz)); st.add_vertex(Vector3(p1.x, p1.y, hz)); st.add_vertex(Vector3(p1.x, p1.y, -hz))
		st.add_vertex(Vector3(p0.x, p0.y, hz)); st.add_vertex(Vector3(p1.x, p1.y, -hz)); st.add_vertex(Vector3(p0.x, p0.y, -hz))
	st.generate_normals()
	return st.commit()


# отломанный луч звезды — вытянутый гранёный кристалл (виден со всех сторон)
func _make_shard_fragment() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := Vector3(0, 0.58, 0)
	var bot := Vector3(0, -0.2, 0)
	var n := 4
	var ring: Array = []
	for i in n:
		var a := TAU * float(i) / float(n) + PI / 4.0
		ring.append(Vector3(cos(a) * 0.17, 0.03, sin(a) * 0.17))
	for i in n:
		var p0: Vector3 = ring[i]
		var p1: Vector3 = ring[(i + 1) % n]
		st.add_vertex(top); st.add_vertex(p0); st.add_vertex(p1)
		st.add_vertex(bot); st.add_vertex(p1); st.add_vertex(p0)
	st.generate_normals()
	return st.commit()


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
		st.add_vertex(Vector3(0, top, 0)); st.add_vertex(Vector3(a.x, top, a.z)); st.add_vertex(Vector3(b.x, top, b.z))
		st.add_vertex(Vector3(0, bot, 0)); st.add_vertex(Vector3(b.x, bot, b.z)); st.add_vertex(Vector3(a.x, bot, a.z))
		st.add_vertex(Vector3(a.x, top, a.z)); st.add_vertex(Vector3(b.x, top, b.z)); st.add_vertex(Vector3(b.x, bot, b.z))
		st.add_vertex(Vector3(a.x, top, a.z)); st.add_vertex(Vector3(b.x, bot, b.z)); st.add_vertex(Vector3(a.x, bot, a.z))
	st.generate_normals()
	return st.commit()


func _add_glow(parent: Node3D, size: float, color: Color) -> MeshInstance3D:
	# круглый светящийся ореол через сферу (billboard-квадраты в мобильном рендерере выходят квадратными)
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = size * 0.09
	s.height = size * 0.18
	s.radial_segments = 8
	s.rings = 4
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 6.0     # маленькое яркое ядро → мягкий ореол через bloom
	m.disable_receive_shadows = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _make_shard_star(color: Color, emit: Color, emit_energy: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = star_mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = emit
	m.emission_energy_multiplier = emit_energy
	m.roughness = 0.35
	m.metalness = 0.25
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	return mi


# ---------- осколки (парящие тетраэдры) ----------
func _build_shards() -> void:
	for i in SHARD_COUNT:
		# по кругу (мир круглый) — иначе осколок мог оказаться за краем карты
		var a := randf() * TAU
		var r := randf_range(12.0, WORLD - 12.0)
		var x := cos(a) * r
		var z := sin(a) * r
		var base_y := _terrain_h(x, z)
		var n := Node3D.new()
		n.position = Vector3(x, base_y + 0.55, z)

		var mi := MeshInstance3D.new()
		mi.mesh = shard_frag_mesh
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.91, 0.63)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.82, 0.29)
		m.emission_energy_multiplier = 6.5
		m.roughness = 0.3
		m.metalness = 0.3
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
		mi.scale = Vector3(1.3, 1.3, 1.3)
		mi.rotation = Vector3(randf() * 3, randf() * 3, randf() * 3)
		n.add_child(mi)

		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.82, 0.35)
		l.light_energy = 3.2
		l.omni_range = 15.0
		n.add_child(l)

		add_child(n)
		shards.append({"node": n, "mesh": mi, "x": x, "z": z, "base_y": base_y, "taken": false})


# ---------- оборотни (двуногие) ----------
func _make_werewolf() -> Dictionary:
	var g := Node3D.new()
	var fur := StandardMaterial3D.new(); fur.albedo_color = Color(0.14, 0.12, 0.11); fur.roughness = 1.0
	var fur_light := StandardMaterial3D.new(); fur_light.albedo_color = Color(0.24, 0.22, 0.20); fur_light.roughness = 1.0
	var dark := StandardMaterial3D.new(); dark.albedo_color = Color(0.055, 0.047, 0.047); dark.roughness = 1.0
	var teeth := StandardMaterial3D.new(); teeth.albedo_color = Color(0.91, 0.89, 0.82); teeth.roughness = 0.6
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.16, 0.09)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.6, 0.22, 0.12)
	eye_mat.emission_energy_multiplier = 6.0
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var body := Node3D.new()   # общий узел покачивания
	g.add_child(body)

	_box(body, Vector3(0.66, 0.5, 0.5), Vector3(0, 1.05, 0), fur)          # таз
	var torso := _box(body, Vector3(0.78, 1.0, 0.55), Vector3(0, 1.55, 0.06), fur)
	torso.rotation.x = 0.32
	var belly := _box(body, Vector3(0.5, 0.7, 0.18), Vector3(0, 1.5, 0.34), fur_light)
	belly.rotation.x = 0.32
	_box(body, Vector3(0.8, 0.45, 0.5), Vector3(0, 2.02, -0.12), fur)      # горб
	for i in 4:                                                            # гребень
		var sp := _cone(body, 0.08, 0.32, Vector3(0, 2.1 - i * 0.18, -0.18 - i * 0.06), fur)
		sp.rotation.x = -0.6
	_box(body, Vector3(0.34, 0.32, 0.34), Vector3(0, 2.0, 0.18), fur)      # шея
	var head := _box(body, Vector3(0.44, 0.42, 0.46), Vector3(0, 2.12, 0.42), fur)
	head.rotation.x = 0.15
	_box(head, Vector3(0.24, 0.16, 0.4), Vector3(0, 0.0, 0.32), fur)       # верхняя челюсть
	_box(head, Vector3(0.22, 0.1, 0.34), Vector3(0, -0.12, 0.28), fur)     # нижняя челюсть
	var fangL := _cone(head, 0.03, 0.1, Vector3(-0.07, -0.08, 0.4), teeth); fangL.rotation.x = PI
	var fangR := _cone(head, 0.03, 0.1, Vector3(0.07, -0.08, 0.4), teeth); fangR.rotation.x = PI
	_box(head, Vector3(0.1, 0.08, 0.1), Vector3(0, 0.04, 0.5), dark)       # нос
	var earL := _cone(head, 0.1, 0.34, Vector3(-0.16, 0.3, -0.08), fur); earL.rotation.z = 0.2
	var earR := _cone(head, 0.1, 0.34, Vector3(0.16, 0.3, -0.08), fur); earR.rotation.z = -0.2
	# глаза — светящиеся круглые сферы (мягкий красный ореол даёт bloom)
	_sphere(head, 0.075, Vector3(-0.11, 0.06, 0.22), eye_mat)
	_sphere(head, 0.075, Vector3(0.11, 0.06, 0.22), eye_mat)

	var armL := _limb(g, Vector3(-0.5, 1.95, 0.05), 0.95, true, fur, dark, teeth)
	var armR := _limb(g, Vector3(0.5, 1.95, 0.05), 0.95, true, fur, dark, teeth)
	var legL := _limb(g, Vector3(-0.24, 1.0, 0.0), 1.05, false, fur, dark, teeth)
	var legR := _limb(g, Vector3(0.24, 1.0, 0.0), 1.05, false, fur, dark, teeth)
	var tail := _cone(g, 0.16, 0.95, Vector3(0, 1.05, -0.45), fur)
	tail.rotation.x = PI / 2.1

	return {
		"node": g, "body": body, "head": head, "tail": tail,
		"legs": [legL, legR], "arms": [armL, armR],
		"eye_mat": eye_mat,
	}


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new(); b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _cone(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 5
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos
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


func _limb(parent: Node3D, pos: Vector3, length: float, clawed: bool, fur: Material, dark: Material, teeth: Material) -> Node3D:
	var hip := Node3D.new()
	hip.position = pos
	var m := _box(hip, Vector3(0.18, length, 0.18), Vector3(0, -length / 2.0, 0), fur)
	_box(hip, Vector3(0.2, 0.16, 0.26), Vector3(0, -length, 0), dark)
	if clawed:
		for c in [-1, 0, 1]:
			var cl := _cone(hip, 0.03, 0.14, Vector3(c * 0.06, -length - 0.02, 0.14), teeth)
			cl.rotation.x = -0.5
	parent.add_child(hip)
	return hip


func _build_wolves() -> void:
	for i in WOLF_COUNT:
		var ang := TAU * float(i) / float(WOLF_COUNT)
		var r := randf_range(60.0, WORLD * 0.75)
		var w := _make_werewolf()
		var pos := Vector3(cos(ang) * r, 0, sin(ang) * r)
		pos.y = _terrain_h(pos.x, pos.z)
		w["node"].position = pos
		add_child(w["node"])
		w["pos"] = pos
		w["vel"] = Vector3.ZERO
		w["state"] = "wander"
		w["target"] = _rand_target()
		w["repath"] = randf_range(2.0, 5.0)
		w["last_seen"] = Vector3.ZERO
		w["search"] = 0.0
		w["flank"] = ang
		w["phase"] = randf() * TAU
		w["howl"] = 0.0
		w["distracted"] = 0.0
		w["lure"] = Vector3.ZERO
		wolves.append(w)


func _rand_target() -> Vector3:
	var a := randf() * TAU
	var r := randf_range(8.0, WORLD - 6.0)
	return Vector3(cos(a) * r, 0, sin(a) * r)


# ---------- сетка столкновений с деревьями ----------
func _grid_add(x: float, z: float, r: float) -> void:
	var cx := int((x - grid_origin) / GRID_CELL)
	var cz := int((z - grid_origin) / GRID_CELL)
	var key := Vector2i(cx, cz)
	if not tree_grid.has(key):
		tree_grid[key] = []
	tree_grid[key].append(Vector3(x, z, r))


func _bush_add(x: float, z: float, r: float) -> void:
	var key := Vector2i(int((x - grid_origin) / GRID_CELL), int((z - grid_origin) / GRID_CELL))
	if not bush_grid.has(key):
		bush_grid[key] = []
	bush_grid[key].append(Vector3(x, z, r))


# игрок «спрятался», если стоит внутри куста
func _is_hidden() -> bool:
	var px := player.position.x
	var pz := player.position.z
	var cx := int((px - grid_origin) / GRID_CELL)
	var cz := int((pz - grid_origin) / GRID_CELL)
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var key := Vector2i(cx + dx, cz + dz)
			if bush_grid.has(key):
				for b in bush_grid[key]:
					var bv: Vector3 = b
					if Vector2(px - bv.x, pz - bv.y).length() < bv.z:
						return true
	return false


func _nearby_trees(x: float, z: float) -> Array:
	var out: Array = []
	var cx := int((x - grid_origin) / GRID_CELL)
	var cz := int((z - grid_origin) / GRID_CELL)
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var key := Vector2i(cx + dx, cz + dz)
			if tree_grid.has(key):
				for e in tree_grid[key]:
					out.append(e)
	return out


# отодвигает точку (nx,nz) из стволов деревьев; запись дерева = Vector3(x, z, r)
func _resolve_trees(nx: float, nz: float, extra: float) -> Vector2:
	for t in _nearby_trees(nx, nz):
		var tv: Vector3 = t
		var dx := nx - tv.x
		var dz := nz - tv.y
		var d := sqrt(dx * dx + dz * dz)
		var mn := tv.z + extra
		if d < mn and d > 0.0001:
			nx = tv.x + dx / d * mn
			nz = tv.y + dz / d * mn
	return Vector2(nx, nz)


# ---------- атмосфера: светлячки, дымка ----------
func _build_fireflies() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var sph := SphereMesh.new()
	sph.radius = 0.13
	sph.height = 0.26
	sph.radial_segments = 8
	sph.rings = 4
	mm.mesh = sph
	var n := 220
	mm.instance_count = n
	for i in n:
		var a := randf() * TAU
		var r := randf_range(6.0, WORLD - 6.0)
		var x := cos(a) * r
		var z := sin(a) * r
		var y := _terrain_h(x, z) + randf_range(0.8, 3.0)
		ff_base.append(Vector3(x, y, z))
		ff_phase.append(randf() * TAU)
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(x, y, z)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.9, 0.85, 0.55)
	m.emission_enabled = true
	m.emission = Color(0.9, 0.85, 0.55)
	m.emission_energy_multiplier = 2.2        # мягкое, неяркое свечение
	m.disable_receive_shadows = true
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	fireflies_mm = mm


func _build_mist() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = glow_tex
	m.albedo_color = Color(0.55, 0.62, 0.75, 0.16)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.disable_receive_shadows = true
	for i in 45:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(38, 38)
		mi.mesh = q
		mi.material_override = m
		var a := randf() * TAU
		var r := randf_range(8.0, WORLD - 8.0)
		var x := cos(a) * r
		var z := sin(a) * r
		mi.position = Vector3(x, _terrain_h(x, z) + 1.0, z)
		add_child(mi)
		mist.append({"node": mi, "dx": randf_range(-0.25, 0.25), "dz": randf_range(-0.25, 0.25)})


# ---------- игрок ----------
func _build_player() -> void:
	player = Node3D.new()
	player.position = Vector3(0, _terrain_h(0, 0), 0)
	cam = Camera3D.new()
	cam.position = Vector3(0, EYE, 0)
	cam.fov = 72.0
	cam.far = 650.0
	player.add_child(cam)
	flashlight = SpotLight3D.new()
	flashlight.light_energy = 12.0
	flashlight.light_color = Color(1.0, 0.94, 0.8)
	flashlight.spot_range = 62.0
	flashlight.spot_angle = 36.0
	flashlight.spot_attenuation = 0.5
	flashlight.shadow_enabled = true
	flashlight.shadow_bias = 0.03
	flashlight.shadow_blur = 1.5
	flashlight.position = Vector3(0, 0, 0.2)
	flashlight.rotation_degrees = Vector3(-7, 0, 0)
	cam.add_child(flashlight)
	add_child(player)


# ---------- интерфейс ----------
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)

	hud_count = Label.new()
	hud_count.position = Vector2(20, 18)
	hud_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_count.add_theme_font_size_override("font_size", 28)
	layer.add_child(hud_count)

	# красный экран урона
	damage_rect = ColorRect.new()
	damage_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_rect.color = Color(0.7, 0.05, 0.03, 0.0)
	damage_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(damage_rect)

	# здоровье (квадраты-сердца)
	var hp := HBoxContainer.new()
	hp.position = Vector2(20, 52)
	hp.add_theme_constant_override("separation", 6)
	hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hp)
	health_slots.clear()
	for i in MAX_HEALTH:
		var h := Panel.new()
		h.custom_minimum_size = Vector2(24, 24)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hsb := StyleBoxFlat.new()
		hsb.bg_color = Color(0.9, 0.2, 0.18, 0.95)
		hsb.set_corner_radius_all(6)
		hsb.set_border_width_all(2)
		hsb.border_color = Color(1, 0.5, 0.45)
		h.add_theme_stylebox_override("panel", hsb)
		hp.add_child(h)
		health_slots.append(hsb)

	# ряд ячеек-осколков (по центру вверху), как в HTML
	var inv := HBoxContainer.new()
	inv.alignment = BoxContainer.ALIGNMENT_CENTER
	inv.add_theme_constant_override("separation", 8)
	inv.anchor_left = 0.0
	inv.anchor_right = 1.0
	inv.offset_top = 16.0
	inv.offset_bottom = 60.0
	inv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(inv)
	inv_slots.clear()
	for i in 6:
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(42, 42)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.35)
		sb.set_corner_radius_all(9)
		sb.set_border_width_all(2)
		sb.border_color = Color(1, 1, 1, 0.18)
		slot.add_theme_stylebox_override("panel", sb)
		var lbl := Label.new()
		lbl.text = "★" if i == 5 else ""
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", Color(0.3, 0.35, 0.45))
		slot.add_child(lbl)
		inv.add_child(slot)
		inv_slots.append({"sb": sb, "lbl": lbl})

	hud_msg = Label.new()
	hud_msg.position = Vector2(0, 96)
	hud_msg.size = Vector2(get_viewport().get_visible_rect().size.x, 30)
	hud_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_msg.add_theme_font_size_override("font_size", 20)
	layer.add_child(hud_msg)

	var hint := Label.new()
	hint.position = Vector2(20, 84)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	hint.text = "WASD — идти · Shift — бежать · Ctrl — присесть · Space — прыжок · F — фонарь · Q — ветка · в кустах прячешься"
	layer.add_child(hint)

	# полоска заряда фонаря
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.anchor_left = 1.0; bg.anchor_right = 1.0
	bg.offset_left = -140.0; bg.offset_top = 20.0; bg.offset_right = -20.0; bg.offset_bottom = 34.0
	layer.add_child(bg)
	battery_fill = ColorRect.new()
	battery_fill.color = Color(0.42, 1.0, 0.54)
	battery_fill.anchor_left = 1.0; battery_fill.anchor_right = 1.0
	battery_fill.offset_left = -140.0; battery_fill.offset_top = 20.0; battery_fill.offset_right = -20.0; battery_fill.offset_bottom = 34.0
	layer.add_child(battery_fill)

	# полоска стамины (под зарядом фонаря)
	var sbg := ColorRect.new()
	sbg.color = Color(0, 0, 0, 0.45)
	sbg.anchor_left = 1.0; sbg.anchor_right = 1.0
	sbg.offset_left = -140.0; sbg.offset_top = 40.0; sbg.offset_right = -20.0; sbg.offset_bottom = 54.0
	layer.add_child(sbg)
	stamina_fill = ColorRect.new()
	stamina_fill.color = Color(0.45, 0.7, 1.0)
	stamina_fill.anchor_left = 1.0; stamina_fill.anchor_right = 1.0
	stamina_fill.offset_left = -140.0; stamina_fill.offset_top = 40.0; stamina_fill.offset_right = -20.0; stamina_fill.offset_bottom = 54.0
	layer.add_child(stamina_fill)

	light_btn = Button.new()
	light_btn.text = "Фонарь: вкл"
	light_btn.anchor_left = 1.0; light_btn.anchor_top = 1.0
	light_btn.anchor_right = 1.0; light_btn.anchor_bottom = 1.0
	light_btn.offset_left = -200.0; light_btn.offset_top = -104.0
	light_btn.offset_right = -20.0; light_btn.offset_bottom = -30.0
	light_btn.add_theme_font_size_override("font_size", 22)
	_style_button(light_btn, Color(1.0, 0.82, 0.4))
	light_btn.pressed.connect(_toggle_light)
	layer.add_child(light_btn)

	throw_btn = Button.new()
	throw_btn.text = "Ветка (0)"
	throw_btn.anchor_left = 1.0; throw_btn.anchor_top = 1.0
	throw_btn.anchor_right = 1.0; throw_btn.anchor_bottom = 1.0
	throw_btn.offset_left = -200.0; throw_btn.offset_top = -186.0
	throw_btn.offset_right = -20.0; throw_btn.offset_bottom = -114.0
	throw_btn.add_theme_font_size_override("font_size", 22)
	_style_button(throw_btn, Color(0.78, 0.62, 0.36))
	throw_btn.pressed.connect(_throw_branch)
	layer.add_child(throw_btn)

	_update_hud()


func _style_button(b: Button, accent: Color) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(14)
		sb.set_border_width_all(2)
		sb.set_content_margin_all(14)
		sb.border_color = accent
		if state == "hover":
			sb.bg_color = Color(accent.r * 0.5, accent.g * 0.5, accent.b * 0.5, 0.95)
		elif state == "pressed":
			sb.bg_color = Color(accent.r * 0.3, accent.g * 0.3, accent.b * 0.3, 0.98)
		else:
			sb.bg_color = Color(0.10, 0.12, 0.18, 0.95)
			sb.border_color = Color(accent.r, accent.g, accent.b, 0.7)
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))


func _make_overlay(title: String, subtitle: String, btn_text: String, cb: Callable, accent := Color(1.0, 0.82, 0.4)) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	c.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(center)
	var panel := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.06, 0.08, 0.13, 0.97)
	psb.set_corner_radius_all(24)
	psb.set_border_width_all(2)
	psb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	psb.set_content_margin_all(46)
	psb.shadow_size = 26
	psb.shadow_color = Color(0, 0, 0, 0.55)
	panel.add_theme_stylebox_override("panel", psb)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 22)
	panel.add_child(vb)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 54)
	t.add_theme_color_override("font_color", accent)
	vb.add_child(t)
	var st := Label.new()
	st.text = subtitle
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.custom_minimum_size = Vector2(500, 0)
	st.add_theme_font_size_override("font_size", 20)
	st.add_theme_color_override("font_color", Color(0.74, 0.80, 0.90))
	vb.add_child(st)
	var b := Button.new()
	b.text = btn_text
	b.custom_minimum_size = Vector2(260, 74)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 28)
	_style_button(b, accent)
	b.pressed.connect(cb)
	vb.add_child(b)
	return c


func _build_menu() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Menu"
	add_child(layer)

	end_panel = _make_overlay("", "", "Играть снова", _on_restart)
	var center := end_panel.get_child(1) as CenterContainer
	var panel := center.get_child(0) as PanelContainer
	var vb := panel.get_child(0) as VBoxContainer
	end_title = vb.get_child(0) as Label
	end_msg = vb.get_child(1) as Label
	end_panel.hide()
	layer.add_child(end_panel)

	menu_panel = _build_start_menu()
	layer.add_child(menu_panel)


func _build_start_menu() -> Control:
	var accent := Color(1.0, 0.82, 0.4)
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06, 0.78)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	c.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(center)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 12)
	center.add_child(vb)

	var img := Image.new()
	if img.load("res://icon.png") == OK:
		var logo := TextureRect.new()
		logo.texture = ImageTexture.create_from_image(img)
		logo.custom_minimum_size = Vector2(150, 150)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(logo)

	var t := Label.new()
	t.text = "FOREST ESCAPE"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 56)
	t.add_theme_color_override("font_color", accent)
	t.add_theme_color_override("font_outline_color", Color(0.14, 0.07, 0.0))
	t.add_theme_constant_override("outline_size", 8)
	vb.add_child(t)

	var tag := Label.new()
	tag.text = "Соберись во тьме. Собери звезду. Уцелей."
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 18)
	tag.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	vb.add_child(tag)

	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 8)
	vb.add_child(sp)

	var b := Button.new()
	b.text = "Войти в лес"
	b.custom_minimum_size = Vector2(280, 78)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 30)
	_style_button(b, accent)
	b.pressed.connect(_on_play)
	vb.add_child(b)

	var leg := Label.new()
	leg.text = "WASD — идти · Shift — бежать · Ctrl — присесть · Space — прыжок\nF — фонарь · Q — бросить ветку · прячься в кустах от оборотней"
	leg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leg.add_theme_font_size_override("font_size", 14)
	leg.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85))
	vb.add_child(leg)
	return c


func _on_play() -> void:
	menu_panel.hide()
	running = true
	_init_audio()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_restart() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


func _toggle_light() -> void:
	if not light_on and battery <= 0.0:
		_flash("Заряд фонаря кончился")
		return
	light_on = not light_on
	flashlight.visible = light_on
	light_btn.text = "Фонарь: вкл" if light_on else "Фонарь: выкл"


func _try_jump() -> void:
	if not running:
		return
	if jump_h <= 0.001 and jump_vy == 0.0:
		jump_vy = JUMP_VELOCITY
		was_airborne = true
		_beep(320.0, 0.1, 0.08, 520.0)


func _hit_player(w: Dictionary) -> void:
	if invuln > 0.0:
		return
	health -= 1
	invuln = 1.6
	_update_health()
	if damage_rect != null:
		damage_rect.color = Color(0.7, 0.05, 0.03, 0.55)
	_beep(200.0, 0.3, 0.22, 80.0)
	# отбросить оборотня, чтобы не добил мгновенно
	var away := Vector3(w["pos"].x - player.position.x, 0, w["pos"].z - player.position.z)
	if away.length() < 0.01:
		away = Vector3(1, 0, 0)
	away = away.normalized() * 4.5
	var np: Vector3 = w["pos"] + away
	np.y = _terrain_h(np.x, np.z)
	w["pos"] = np
	w["node"].position = np
	w["state"] = "search"
	w["search"] = SEARCH_TIME
	if health <= 0:
		_lose()
	else:
		_flash("Оборотень ранил тебя! HP: %d" % health, Color(1.0, 0.4, 0.35))


func _update_hud() -> void:
	hud_count.text = "Осколки: %d / %d" % [collected, SHARD_COUNT]
	if inv_slots.is_empty():
		return
	for i in 5:
		var s: Dictionary = inv_slots[i]
		var sb: StyleBoxFlat = s["sb"]
		var lbl: Label = s["lbl"]
		if i < collected:
			sb.bg_color = Color(0.35, 0.28, 0.08, 0.6)
			sb.border_color = Color(1.0, 0.82, 0.29)
			lbl.text = "★"
			lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.4))
		else:
			sb.bg_color = Color(0, 0, 0, 0.35)
			sb.border_color = Color(1, 1, 1, 0.18)
			lbl.text = ""
	# ячейка-звезда справа
	var star: Dictionary = inv_slots[5]
	var star_sb: StyleBoxFlat = star["sb"]
	var star_lbl: Label = star["lbl"]
	if collected >= SHARD_COUNT:
		star_sb.bg_color = Color(0.1, 0.2, 0.35, 0.6)
		star_sb.border_color = Color(0.62, 0.82, 1.0)
		star_lbl.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	else:
		star_sb.bg_color = Color(0, 0, 0, 0.35)
		star_sb.border_color = Color(1, 1, 1, 0.18)
		star_lbl.add_theme_color_override("font_color", Color(0.3, 0.35, 0.45))


func _update_health() -> void:
	for i in health_slots.size():
		var sb: StyleBoxFlat = health_slots[i]
		if i < health:
			sb.bg_color = Color(0.9, 0.2, 0.18, 0.95)
			sb.border_color = Color(1, 0.5, 0.45)
		else:
			sb.bg_color = Color(0.15, 0.12, 0.13, 0.6)
			sb.border_color = Color(0.4, 0.3, 0.3)


func _flash(msg: String, col: Color = Color(0.95, 0.97, 1.0)) -> void:
	hud_msg.text = msg
	hud_msg.add_theme_color_override("font_color", col)
	status_timer = 2.2


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
	elif event is InputEventMouseButton and event.pressed and running and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		elif event.keycode == KEY_F:
			_toggle_light()
		elif event.keycode == KEY_Q:
			_throw_branch()
		elif event.keycode == KEY_E:
			_try_insert_shard()
		elif event.keycode == KEY_SPACE:
			_try_jump()


# ---------- главный цикл ----------
func _process(delta: float) -> void:
	if status_timer > 0.0:
		status_timer -= delta
		if status_timer <= 0.0 and not (phase == "escape"):
			hud_msg.text = ""

	_animate_shards(delta)
	_animate_atmosphere(delta)

	if not running:
		return
	game_time += delta
	if invuln > 0.0:
		invuln -= delta
	if damage_rect != null and damage_rect.color.a > 0.0:
		damage_rect.color.a = max(0.0, damage_rect.color.a - delta * 1.2)

	player.rotation.y = yaw
	cam.rotation.x = pitch

	var mv := move_vec
	if Input.is_key_pressed(KEY_W): mv.y = -1.0
	if Input.is_key_pressed(KEY_S): mv.y = 1.0
	if Input.is_key_pressed(KEY_A): mv.x = -1.0
	if Input.is_key_pressed(KEY_D): mv.x = 1.0
	if mv.length() > 1.0:
		mv = mv.normalized()

	var fwd := -player.global_transform.basis.z
	var right := player.global_transform.basis.x
	var dir := fwd * (-mv.y) + right * mv.x
	dir.y = 0.0
	crouching = Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_C)
	var wants_sprint := Input.is_key_pressed(KEY_SHIFT) and not crouching and mv.length() > 0.1
	if stamina <= 0.0:
		stamina_exhausted = true
	elif stamina > 0.3:
		stamina_exhausted = false
	sprinting = wants_sprint and not stamina_exhausted
	if sprinting:
		stamina = max(0.0, stamina - STAMINA_DRAIN * delta)
	else:
		stamina = min(1.0, stamina + STAMINA_REGEN * delta)
	_update_stamina()
	var pspeed := PLAYER_SPEED
	if crouching:
		pspeed = PLAYER_SPEED * 0.5
	elif sprinting:
		pspeed = SPRINT_SPEED
	player_vel = dir * pspeed
	var nx := player.position.x + dir.x * pspeed * delta
	var nz := player.position.z + dir.z * pspeed * delta
	var res := _resolve_trees(nx, nz, PLAYER_R)
	nx = res.x
	nz = res.y
	var pr := Vector2(nx, nz).length()
	if pr > WORLD:
		nx = nx / pr * WORLD
		nz = nz / pr * WORLD
	# прыжок / гравитация
	if jump_h > 0.0 or jump_vy != 0.0:
		jump_vy -= GRAVITY * delta
		jump_h += jump_vy * delta
		if jump_h <= 0.0:
			jump_h = 0.0
			jump_vy = 0.0
			if was_airborne:
				was_airborne = false
				_beep(120.0, 0.09, 0.06, 80.0)
	player.position = Vector3(nx, _terrain_h(nx, nz) + jump_h, nz)

	# покачивание головы + крен камеры при ходьбе
	var move_mag: float = min(1.0, mv.length())
	if move_mag > 0.1:
		bob_phase += delta * pspeed * move_mag * 1.4
		if not crouching:
			step_time += delta
			var step_int: float = 0.24 if sprinting else 0.34
			if step_time > step_int:
				step_time = 0.0
				_beep(90.0, 0.09, 0.05, 60.0)
	var target_eye: float = 0.95 if crouching else EYE
	cam_eye = lerp(cam_eye, target_eye, min(1.0, 10.0 * delta))
	cam.position.y = cam_eye + sin(bob_phase) * 0.07 * move_mag
	cam.rotation.z = sin(bob_phase * 0.5) * 0.012 * move_mag

	# фонарь тратит заряд
	if light_on:
		battery -= BATTERY_DRAIN * delta
		if battery <= 0.0:
			battery = 0.0
			light_on = false
			flashlight.visible = false
			light_btn.text = "Фонарь: выкл"
			_flash("Фонарь погас — заряд кончился")
	_update_battery()

	_check_shards()
	if carry_star != null:
		carry_star.get_child(0).rotation.y += delta * 1.6
		carry_star.position.y = -0.55 + sin(game_time * 2.0) * 0.04
	if gate != null:
		gate.get_node("ring").rotation.z += delta * 1.6

	_update_branches(delta)

	if phase == "escape":
		var d := Vector2(player.position.x - exit_pos.x, player.position.z - exit_pos.z).length()
		if d < 3.6:
			_flash("Нажми E — вставь осколок (%d/5)" % inserted, Color(0.6, 0.85, 1.0))
		else:
			_flash("Неси осколки к воротам! %d м" % int(d), Color(1.0, 0.42, 0.37))

	_update_wolves(delta)

	# контекстные подсказки
	if not ended and phase != "escape":
		if any_chasing:
			_flash("Оборотень гонится — беги, прячься или выключи фонарь!", Color(1.0, 0.42, 0.37))
		elif hidden:
			_flash("Ты спрятался в кустах — тебя не видно", Color(0.42, 1.0, 0.62))
		elif status_timer <= 0.0 and not light_on:
			_flash("В темноте оборотни почти слепы — крадись", Color(0.42, 1.0, 0.62))

	# сердцебиение при погоне
	if any_chasing:
		heartbeat_t -= delta
		if heartbeat_t <= 0.0:
			heartbeat_t = 0.6
			_beep(56.0, 0.12, 0.16, 42.0)
			get_tree().create_timer(0.17).timeout.connect(func() -> void: _beep(50.0, 0.1, 0.11, 40.0))
	else:
		heartbeat_t = 0.0


func _animate_shards(delta: float) -> void:
	for s in shards:
		if s["taken"]:
			continue
		var n: Node3D = s["node"]
		s["mesh"].rotation.y += delta * 1.5
		n.position.y = s["base_y"] + 0.9 + sin(game_time * 3.0 + s["x"]) * 0.1


func _animate_atmosphere(delta: float) -> void:
	var t := game_time
	if fireflies_mm != null:
		for i in ff_base.size():
			var b := ff_base[i]
			var ph := ff_phase[i]
			var p := Vector3(
				b.x + sin(t * 0.5 + ph) * 1.2,
				b.y + sin(t * 0.8 + ph * 1.7) * 0.4,
				b.z + cos(t * 0.45 + ph) * 1.2)
			fireflies_mm.set_instance_transform(i, Transform3D(Basis(), p))
	for m in mist:
		var node: Node3D = m["node"]
		node.position.x += m["dx"] * delta
		node.position.z += m["dz"] * delta


func _check_shards() -> void:
	if phase != "collect":
		return
	for s in shards:
		if s["taken"]:
			continue
		var d := Vector2(player.position.x - s["x"], player.position.z - s["z"]).length()
		if d < 1.4:
			s["taken"] = true
			_burst(Vector3(s["x"], s["base_y"] + 0.6, s["z"]), Color(1.0, 0.94, 0.69), 16)
			s["node"].queue_free()
			collected += 1
			_update_hud()
			_beep(660.0, 0.13, 0.16, 990.0)
			_flash("Осколок звезды найден!", Color(0.42, 1.0, 0.62))
			if collected >= SHARD_COUNT:
				_open_exit()


func _open_exit() -> void:
	phase = "escape"
	inserted = 0
	var a := randf() * TAU
	var gx := cos(a) * (WORLD - 6.0)
	var gz := sin(a) * (WORLD - 6.0)
	var dl: float = max(Vector2(gx, gz).length(), 1.0)
	exit_pos = Vector3(gx - gx / dl * 2.4, 0, gz - gz / dl * 2.4)
	gate = _build_gate(Vector3(gx, 0, gz))
	add_child(gate)
	_beep(330.0, 0.6, 0.1, 660.0)
	_flash("Все осколки собраны! Неси их к воротам и вставь все 5 в гнездо-звезду (E)!", Color(1.0, 0.42, 0.37))


func _build_gate(pos: Vector3) -> Node3D:
	var g := Node3D.new()
	var stone := _tex_mat(Color(0.42, 0.44, 0.47), 0.2, 2.0)

	_box(g, Vector3(0.7, 4.4, 0.7), Vector3(-2.1, 2.2, 0), stone)
	_box(g, Vector3(0.7, 4.4, 0.7), Vector3(2.1, 2.2, 0), stone)
	_box(g, Vector3(5.4, 0.7, 0.9), Vector3(0, 4.55, 0), stone)

	# кольцо портала
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 1.5
	tor.outer_radius = 1.85
	ring.mesh = tor
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.16, 0.21, 0.31)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.25, 0.45, 0.85)
	ring_mat.emission_energy_multiplier = 1.5
	ring.material_override = ring_mat
	ring.name = "ring"
	ring.position = Vector3(0, 2.4, 0)
	g.add_child(ring)

	# столб света (чтобы найти ворота издалека)
	var beam := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.7
	bm.bottom_radius = 0.7
	bm.height = 80.0
	beam.mesh = bm
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.albedo_color = Color(0.62, 0.82, 1.0, 0.16)
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = beam_mat
	beam.position = Vector3(0, 40, 0)
	g.add_child(beam)

	# пьедестал с гнездом-звездой (перед воротами, к центру леса)
	var ped := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.9
	pm.bottom_radius = 1.1
	pm.height = 1.1
	ped.mesh = pm
	ped.material_override = stone
	ped.position = Vector3(0, 0.55, 2.4)
	g.add_child(ped)

	# гнездо-звезда из 5 лучей — заполняется по мере вставки осколков
	gate_arm_mats = []
	for i in 5:
		var arm := MeshInstance3D.new()
		arm.mesh = shard_frag_mesh
		var am := StandardMaterial3D.new()
		am.albedo_color = Color(0.16, 0.18, 0.24)
		am.emission_enabled = true
		am.emission = Color(1.0, 0.86, 0.4)
		am.emission_energy_multiplier = 0.0     # тёмный, пока не вставлен
		am.cull_mode = BaseMaterial3D.CULL_DISABLED
		arm.material_override = am
		var ang := TAU * float(i) / 5.0
		arm.transform = Transform3D(
			Basis(Vector3.UP, ang) * Basis(Vector3.RIGHT, PI / 2.0) * Basis().scaled(Vector3(0.95, 0.95, 0.95)),
			Vector3(0, 1.35, 2.4))
		g.add_child(arm)
		gate_arm_mats.append(am)
	_add_glow(g, 2.6, Color(0.62, 0.82, 1.0)).position = Vector3(0, 1.45, 2.4)

	var light := OmniLight3D.new()
	light.light_color = Color(0.62, 0.82, 1.0)
	light.light_energy = 1.4
	light.omni_range = 26.0
	light.position = Vector3(0, 3, 2)
	light.name = "glow_light"
	g.add_child(light)

	# развернуть ворота к центру мира
	var dl: float = max(Vector2(pos.x, pos.z).length(), 1.0)
	g.rotation.y = atan2(-pos.x / dl, -pos.z / dl)
	g.position = Vector3(pos.x, _terrain_h(pos.x, pos.z), pos.z)
	return g


func _insert_star() -> void:
	running = false
	ended = true
	if carry_star != null:
		carry_star.queue_free()
		carry_star = null
	if gate != null:
		var socket := gate.get_node("socket") as MeshInstance3D
		var sm := socket.material_override as StandardMaterial3D
		sm.albedo_color = Color(1.0, 0.95, 0.69)
		sm.emission = Color(1.0, 0.89, 0.48)
		sm.emission_energy_multiplier = 3.0
		(gate.get_node("glow_light") as OmniLight3D).light_energy = 4.5
		_burst((gate.get_node("socket") as Node3D).global_position, Color(1.0, 0.95, 0.69), 28)
	_win()


func _update_wolves(delta: float) -> void:
	var pp := player.position
	var t := game_time
	any_chasing = false
	hidden = _is_hidden()
	for w in wolves:
		var wpos: Vector3 = w["pos"]
		var dxp := pp.x - wpos.x
		var dzp := pp.z - wpos.z
		var dist := Vector2(dxp, dzp).length()
		var detect := WOLF_DETECT_LIT if light_on else WOLF_DETECT_DARK

		var speed := WOLF_WANDER_SPEED
		var dirx := 0.0
		var dirz := 0.0
		if w["distracted"] > 0.0:
			# отвлечён брошенной веткой — идёт на шум, игрока не замечает
			w["distracted"] -= delta
			var lure: Vector3 = w["lure"]
			dirx = lure.x - wpos.x
			dirz = lure.z - wpos.z
			if Vector2(dirx, dirz).length() < 2.5:
				dirx = cos(w["distracted"] * 6.0)
				dirz = sin(w["distracted"] * 6.0)
			speed = WOLF_CHASE_SPEED * 0.8
		else:
			# зрение (дальше при фонаре, ближе в присяде) + слух (по шагам)
			var moving := player_vel.length() > 0.5
			# в присяде оборотни почти слепы к тебе (сильно урезаны зрение и слух)
			var sight := detect * (0.22 if crouching else 1.0)
			var hearing := 2.0
			if moving:
				hearing = 2.5 if crouching else (16.0 if sprinting else 10.0)
			# в кустах не видят — но уже гонящийся оборотень всё равно находит
			var can_detect: bool = (not hidden) or w["state"] == "chase"
			var sees := can_detect and (dist < sight or dist < hearing)
			if sees:
				if w["state"] != "chase":
					_alert_pack(pp)
					w["howl"] = 1.3
					_beep(150.0, 0.5, 0.12, 70.0)
				w["state"] = "chase"
				w["last_seen"] = Vector3(pp.x, 0, pp.z)
			elif w["state"] == "chase":
				w["state"] = "search"
				w["search"] = SEARCH_TIME

			if w["state"] == "chase":
				any_chasing = true
				# упреждение: целимся туда, куда игрок бежит, + фланг; вблизи — рывок
				var lead: float = min(dist / WOLF_CHASE_SPEED, 0.8)
				var fl: float = min(dist * 0.3, 1.2)
				var ax: float = pp.x + player_vel.x * lead + cos(w["flank"]) * fl
				var az: float = pp.z + player_vel.z * lead + sin(w["flank"]) * fl
				dirx = ax - wpos.x
				dirz = az - wpos.z
				speed = WOLF_CHASE_SPEED * (1.15 if dist < 4.0 else 1.0)
			elif w["state"] == "search":
				w["search"] -= delta
				var ls: Vector3 = w["last_seen"]
				dirx = ls.x - wpos.x
				dirz = ls.z - wpos.z
				if Vector2(dirx, dirz).length() < 2.0 or w["search"] <= 0.0:
					w["state"] = "wander"
					w["target"] = _rand_target()
					w["repath"] = randf_range(2.0, 5.0)
				speed = WOLF_CHASE_SPEED * 0.72
			else:
				w["repath"] -= delta
				var tg: Vector3 = w["target"]
				if w["repath"] <= 0.0 or Vector2(wpos.x - tg.x, wpos.z - tg.z).length() < 2.0:
					w["target"] = _rand_target()
					w["repath"] = randf_range(2.0, 5.0)
					tg = w["target"]
				dirx = tg.x - wpos.x
				dirz = tg.z - wpos.z
				speed = WOLF_WANDER_SPEED

		var dl := Vector2(dirx, dirz).length()
		if dl > 0.001:
			dirx /= dl
			dirz /= dl
		var vel: Vector3 = w["vel"]
		var lerp_k := 0.13 if w["state"] == "chase" else 0.06
		vel.x += (dirx - vel.x) * lerp_k
		vel.z += (dirz - vel.z) * lerp_k
		w["vel"] = vel

		var vl := Vector2(vel.x, vel.z).length()
		var node: Node3D = w["node"]
		if vl > 0.001:
			var wx := wpos.x + (vel.x / vl) * speed * delta
			var wz := wpos.z + (vel.z / vl) * speed * delta
			var wres := _resolve_trees(wx, wz, 0.5)
			wx = wres.x
			wz = wres.y
			var rr := Vector2(wx, wz).length()
			if rr > WORLD:
				wx = wx / rr * WORLD
				wz = wz / rr * WORLD
			wpos = Vector3(wx, _terrain_h(wx, wz), wz)
			w["pos"] = wpos
			node.position = wpos
			node.rotation.y = atan2(vel.x, vel.z)
			_animate_wolf_run(w, delta, speed)
		else:
			_animate_wolf_idle(w, t)

		# пульс глаз + вой
		var eye_mat: StandardMaterial3D = w["eye_mat"]
		var chasing: bool = w["state"] == "chase"
		# пульс глаз: быстрее/сильнее при погоне
		var pulse: float = sin(t * (8.0 if chasing else 3.0) + w["flank"]) * (0.5 if chasing else 0.25)
		eye_mat.emission_energy_multiplier = 6.0 + pulse * 4.0
		var head: Node3D = w["head"]
		if w["howl"] > 0.0:
			w["howl"] -= delta
			head.rotation.x = -0.6 * sin(min(1.0, w["howl"]) * PI)
		else:
			head.rotation.x += (0.15 - head.rotation.x) * 0.1

		if dist < WOLF_CATCH:
			_hit_player(w)


func _animate_wolf_run(w: Dictionary, delta: float, speed: float) -> void:
	w["phase"] += delta * speed * 2.0
	var ph: float = w["phase"]
	var amp := 0.85
	var legs: Array = w["legs"]
	var arms: Array = w["arms"]
	legs[0].rotation.x = sin(ph) * amp
	legs[1].rotation.x = sin(ph + PI) * amp
	arms[0].rotation.x = sin(ph + PI) * amp * 0.7
	arms[1].rotation.x = sin(ph) * amp * 0.7
	var body: Node3D = w["body"]
	body.position.y = abs(sin(ph)) * 0.05
	w["tail"].rotation.z = sin(ph * 0.5) * 0.2


func _animate_wolf_idle(w: Dictionary, t: float) -> void:
	var body: Node3D = w["body"]
	body.position.y = sin(t * 1.6 + w["phase"]) * 0.03
	w["tail"].rotation.z = sin(t * 1.2 + w["phase"]) * 0.18
	var legs: Array = w["legs"]
	var arms: Array = w["arms"]
	legs[0].rotation.x *= 0.9
	legs[1].rotation.x *= 0.9
	arms[0].rotation.x *= 0.9
	arms[1].rotation.x *= 0.9


func _alert_pack(pos: Vector3) -> void:
	for w in wolves:
		if w["state"] != "chase" and Vector2(w["pos"].x - pos.x, w["pos"].z - pos.z).length() < ALERT_RADIUS:
			w["state"] = "search"
			w["last_seen"] = Vector3(pos.x, 0, pos.z)
			w["search"] = SEARCH_TIME


func _update_stamina() -> void:
	if stamina_fill == null:
		return
	var p: float = clamp(stamina, 0.0, 1.0)
	stamina_fill.offset_right = -140.0 + 120.0 * p
	if stamina_exhausted:
		stamina_fill.color = Color(1.0, 0.4, 0.3)
	elif p > 0.3:
		stamina_fill.color = Color(0.45, 0.7, 1.0)
	else:
		stamina_fill.color = Color(1.0, 0.72, 0.3)


func _update_battery() -> void:
	var p: float = clamp(battery, 0.0, 1.0)
	battery_fill.offset_right = -140.0 + 120.0 * p
	if p > 0.5:
		battery_fill.color = Color(0.42, 1.0, 0.54)
	elif p > 0.2:
		battery_fill.color = Color(1.0, 0.82, 0.29)
	else:
		battery_fill.color = Color(1.0, 0.35, 0.29)


func _try_insert_shard() -> void:
	if phase != "escape" or gate == null or inserted >= 5:
		return
	var d := Vector2(player.position.x - exit_pos.x, player.position.z - exit_pos.z).length()
	if d > 3.6:
		return
	# зажечь очередной луч звезды
	var am: StandardMaterial3D = gate_arm_mats[inserted]
	am.albedo_color = Color(1.0, 0.9, 0.6)
	am.emission_energy_multiplier = 4.0
	inserted += 1
	_beep(660.0, 0.13, 0.16, 990.0)
	_burst(Vector3(exit_pos.x, _terrain_h(exit_pos.x, exit_pos.z) + 1.4, exit_pos.z), Color(1.0, 0.9, 0.6), 14)
	if inserted >= 5:
		(gate.get_node("glow_light") as OmniLight3D).light_energy = 5.0
		_win()
	else:
		_flash("Осколок вставлен (%d/5)" % inserted, Color(0.6, 0.85, 1.0))


func _win() -> void:
	running = false
	ended = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var notes := [523.0, 659.0, 784.0, 1047.0]
	for i in notes.size():
		var f: float = notes[i]
		get_tree().create_timer(i * 0.12).timeout.connect(func() -> void: _beep(f, 0.22, 0.18))
	end_title.text = "Ворота открыты!"
	end_msg.text = "Звезда встала в гнездо, и древние ворота вспыхнули светом. Ты свободен!"
	end_panel.show()


func _lose() -> void:
	running = false
	ended = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_beep(300.0, 0.6, 0.2, 70.0)
	end_title.text = "Оборотень настиг тебя!"
	end_msg.text = "Стая была быстрее. Звезда потеряна во тьме леса."
	end_panel.show()


# ---------- звук (синтез, без файлов) ----------
func _init_audio() -> void:
	if not audio_players.is_empty():
		return
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		audio_players.append(p)
	wind_player = AudioStreamPlayer.new()
	wind_player.stream = _make_noise_stream(2.0)
	wind_player.volume_db = -26.0
	add_child(wind_player)
	wind_player.play()


func _make_noise_stream(dur: float) -> AudioStreamWAV:
	var rate := 22050
	var count := int(dur * rate)
	var data := PackedByteArray()
	data.resize(count * 2)
	var prev := 0.0
	for i in count:
		var white := randf() * 2.0 - 1.0
		prev = prev * 0.96 + white * 0.04     # грубый ФНЧ → шум ветра
		data.encode_s16(i * 2, int(clamp(prev * 4.0, -1.0, 1.0) * 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = count
	wav.data = data
	return wav


func _beep(freq: float, dur: float, vol: float, slide_to: float = 0.0) -> void:
	if audio_players.is_empty():
		return
	var rate := 22050
	var count := int(dur * rate)
	if count < 2:
		return
	var data := PackedByteArray()
	data.resize(count * 2)
	var ph := 0.0
	for i in count:
		var f := freq
		if slide_to > 0.0:
			f = lerp(freq, slide_to, float(i) / float(count))
		ph += TAU * f / float(rate)
		var attack: float = min(1.0, float(i) / (float(rate) * 0.012))
		var decay: float = clamp(1.0 - float(i) / float(count), 0.0, 1.0)
		var s := sin(ph) * attack * decay * vol
		data.encode_s16(i * 2, int(clamp(s, -1.0, 1.0) * 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	var p: AudioStreamPlayer = audio_players[audio_idx]
	audio_idx = (audio_idx + 1) % audio_players.size()
	p.stream = wav
	p.play()


# ---------- ветки-приманки ----------
func _make_branch() -> Node3D:
	var g := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.29, 0.17)
	mat.roughness = 1.0
	var main := MeshInstance3D.new()
	var mc := CylinderMesh.new()
	mc.top_radius = 0.05
	mc.bottom_radius = 0.06
	mc.height = 1.0
	main.mesh = mc
	main.material_override = mat
	main.rotation.z = PI / 2.0
	g.add_child(main)
	var twig := MeshInstance3D.new()
	var tc := CylinderMesh.new()
	tc.top_radius = 0.03
	tc.bottom_radius = 0.04
	tc.height = 0.4
	twig.mesh = tc
	twig.material_override = mat
	twig.position = Vector3(0.15, 0.12, 0)
	twig.rotation.z = 0.7
	g.add_child(twig)
	return g


func _build_branches() -> void:
	for i in BRANCH_COUNT:
		var x := randf_range(-WORLD + 4, WORLD - 4)
		var z := randf_range(-WORLD + 4, WORLD - 4)
		if Vector2(x, z).length() > WORLD - 2 or Vector2(x, z).length() < 6.0:
			continue
		var b := _make_branch()
		b.position = Vector3(x, _terrain_h(x, z) + 0.1, z)
		b.rotation.y = randf() * TAU
		_add_glow(b, 1.0, Color(0.78, 0.60, 0.35)).position.y = 0.2
		add_child(b)
		branch_pickups.append({"node": b, "x": x, "z": z, "taken": false})


func _update_branches(delta: float) -> void:
	for b in branch_pickups:
		if b["taken"]:
			continue
		var node: Node3D = b["node"]
		node.rotation.y += delta * 0.6
		if Vector2(player.position.x - b["x"], player.position.z - b["z"]).length() < 1.6:
			b["taken"] = true
			node.queue_free()
			branch_count += 1
			_update_branch_hud()
			_beep(520.0, 0.1, 0.12, 700.0)
			_flash("Подобрал ветку — брось, чтобы отвлечь оборотней", Color(0.42, 1.0, 0.62))
	for i in range(thrown_branches.size() - 1, -1, -1):
		var tb: Dictionary = thrown_branches[i]
		var n: Node3D = tb["node"]
		if tb["landed"] > 0.0:
			tb["landed"] -= delta
			if tb["landed"] <= 0.0:
				n.queue_free()
				thrown_branches.remove_at(i)
			continue
		var vel: Vector3 = tb["vel"]
		vel.y -= 20.0 * delta
		tb["vel"] = vel
		n.position += vel * delta
		n.rotation.x += tb["spin"].x * delta
		n.rotation.z += tb["spin"].z * delta
		var gh := _terrain_h(n.position.x, n.position.z)
		if n.position.y <= gh + 0.1:
			n.position.y = gh + 0.08
			tb["landed"] = 8.0
			tb["vel"] = Vector3.ZERO
			_beep(150.0, 0.18, 0.12, 90.0)
			_distract(Vector3(n.position.x, 0, n.position.z))


func _throw_branch() -> void:
	if not running:
		return
	if branch_count <= 0:
		_flash("Нет веток — найди их в лесу", Color(1.0, 0.42, 0.37))
		return
	branch_count -= 1
	_update_branch_hud()
	var b := _make_branch()
	b.position = Vector3(player.position.x, player.position.y + EYE, player.position.z)
	add_child(b)
	var fx := -sin(yaw)
	var fz := -cos(yaw)
	thrown_branches.append({
		"node": b, "vel": Vector3(fx * 16.0, 7.5, fz * 16.0), "landed": 0.0,
		"spin": Vector3(randf_range(4, 9), 0, randf_range(4, 9)),
	})
	_beep(200.0, 0.12, 0.1, 120.0)


func _distract(point: Vector3) -> void:
	var any := false
	for w in wolves:
		if Vector2(w["pos"].x - point.x, w["pos"].z - point.z).length() < DISTRACT_RADIUS:
			w["distracted"] = 4.5
			w["lure"] = point
			w["state"] = "search"
			any = true
	if any:
		_flash("Хруст ветки увёл оборотней в сторону!", Color(0.42, 1.0, 0.62))


func _update_branch_hud() -> void:
	if throw_btn != null:
		throw_btn.text = "Ветка (%d)" % branch_count


# ---------- вспышка частиц ----------
func _burst(pos: Vector3, color: Color, amount: int) -> void:
	var p := CPUParticles3D.new()
	p.position = pos
	p.amount = amount
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 0.9
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 1.6
	p.initial_velocity_max = 3.6
	p.gravity = Vector3(0, -4, 0)
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.28
	var q := QuadMesh.new()
	q.size = Vector2(0.4, 0.4)
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = glow_tex
	m.albedo_color = color
	m.disable_receive_shadows = true
	p.material_override = m
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)
