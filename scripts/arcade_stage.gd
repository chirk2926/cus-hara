extends Node3D
## ゲームセンターのステージ（クレーンゲーム中心）。すべてプリミティブで手続き生成する。
## StageWorld から生成され、build() / set_tension() が呼ばれる。
## 座標系: 床 y=0、カメラは (0,1.55,1.9) から -Z 方向を見る。お客さんは (0,0,-0.35) に立つ。

var label_font: Font = null

const PALETTE: Array = [
	Color(1.0, 0.37, 0.64), Color(0.18, 0.77, 1.0), Color(1.0, 0.82, 0.25), Color(0.65, 0.42, 1.0),
	Color(0.25, 0.88, 0.65), Color(1.0, 0.54, 0.24), Color(1.0, 0.3, 0.3), Color(0.3, 0.49, 1.0),
]
const PLUSH_COLORS: Array = [
	Color(0.80, 0.56, 0.36), Color(1.0, 0.75, 0.82), Color(0.96, 0.94, 0.90), Color(0.55, 0.78, 1.0),
	Color(0.74, 0.62, 0.95), Color(0.62, 0.90, 0.70), Color(1.0, 0.86, 0.45), Color(0.45, 0.45, 0.50),
]

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _box_mesh: BoxMesh = null
var _sphere_mesh: SphereMesh = null
var _cyl_mesh: CylinderMesh = null
var _cone_mesh: CylinderMesh = null
var _mats: Dictionary = {}
var _cranes: Array = []
var _blink_mats: Array = []
var _spinners: Array = []
var _tension_light: OmniLight3D = null
var _tension: float = 0.0
var _time: float = 0.0
var _built: bool = false


# ---------------------------------------------------------------- 共通ヘルパー

func _init_meshes() -> void:
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3.ONE
	_sphere_mesh = SphereMesh.new()
	_sphere_mesh.radius = 0.5
	_sphere_mesh.height = 1.0
	_sphere_mesh.radial_segments = 16
	_sphere_mesh.rings = 8
	_cyl_mesh = CylinderMesh.new()
	_cyl_mesh.top_radius = 0.5
	_cyl_mesh.bottom_radius = 0.5
	_cyl_mesh.height = 1.0
	_cyl_mesh.radial_segments = 16
	_cone_mesh = CylinderMesh.new()
	_cone_mesh.top_radius = 0.0
	_cone_mesh.bottom_radius = 0.5
	_cone_mesh.height = 1.0
	_cone_mesh.radial_segments = 12


## 色・発光・質感ごとにマテリアルを使い回す（描画のバッチ化のため）
func _mat(color: Color, emission: float = 0.0, rough: float = 0.7, metal: float = 0.0) -> StandardMaterial3D:
	var key: String = "%s|%.2f|%.2f|%.2f" % [color.to_html(), emission, rough, metal]
	if _mats.has(key):
		return _mats[key]
	var m: StandardMaterial3D = _new_mat(color, emission, rough, metal)
	_mats[key] = m
	return m


func _new_mat(color: Color, emission: float = 0.0, rough: float = 0.7, metal: float = 0.0) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if color.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = Color(color.r, color.g, color.b)
		m.emission_energy_multiplier = emission
	return m


func _mesh(parent: Node3D, mesh: Mesh, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos
	mi.scale = size
	return mi


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	return _mesh(parent, _box_mesh, size, pos, mat)


func _sph(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	return _mesh(parent, _sphere_mesh, size, pos, mat)


func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	return _mesh(parent, _cyl_mesh, Vector3(radius * 2.0, height, radius * 2.0), pos, mat)


func _node(parent: Node3D, pos: Vector3) -> Node3D:
	var n: Node3D = Node3D.new()
	parent.add_child(n)
	n.position = pos
	return n


func _text(parent: Node3D, txt: String, pos: Vector3, font_px: int, pixel: float, color: Color, outline: Color = Color(0, 0, 0, 0)) -> Label3D:
	var l: Label3D = Label3D.new()
	l.text = txt
	l.font_size = font_px
	l.pixel_size = pixel
	l.modulate = color
	if outline.a > 0.0:
		l.outline_size = int(font_px / 5.0)
		l.outline_modulate = outline
	else:
		l.outline_size = 0
	if label_font != null:
		l.font = label_font
	parent.add_child(l)
	l.position = pos
	return l


func _omni(pos: Vector3, color: Color, energy: float, light_range: float) -> OmniLight3D:
	var o: OmniLight3D = OmniLight3D.new()
	o.light_color = color
	o.light_energy = energy
	o.omni_range = light_range
	o.omni_attenuation = 1.2
	add_child(o)
	o.position = pos
	return o


# ---------------------------------------------------------------- ビルド

func build() -> void:
	if _built:
		return
	_built = true
	_rng.seed = 20261117
	_init_meshes()
	_build_environment()
	_build_room()
	_build_counter()
	_build_cranes()
	_build_extras()


func _build_environment() -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.8)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.12
	env.glow_strength = 1.05
	env.ssao_enabled = true
	env.ssr_enabled = true
	env.ssr_max_steps = 32
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.light_color = Color(0.8, 0.75, 1.0)
	sun.light_energy = 0.45
	sun.shadow_enabled = true
	add_child(sun)
	sun.rotation_degrees = Vector3(-62.0, 28.0, 0.0)

	# お客さんの顔がはっきり見えるよう、カウンター上に暖色のキーライトを置く
	var key: OmniLight3D = _omni(Vector3(0.3, 2.7, 0.9), Color(1.0, 0.93, 0.82), 2.2, 6.0)
	key.shadow_enabled = true
	_omni(Vector3(-3.2, 2.7, -2.4), Color(1.0, 0.35, 0.7), 1.6, 7.0)
	_omni(Vector3(2.8, 2.7, -4.6), Color(0.25, 0.8, 1.0), 1.6, 7.0)
	_omni(Vector3(-1.2, 2.6, -5.4), Color(0.7, 0.5, 1.0), 1.2, 6.0)
	_omni(Vector3(3.9, 2.4, -2.2), Color(1.0, 0.85, 0.5), 1.0, 5.0)

	_tension_light = _omni(Vector3(0.0, 2.2, -0.2), Color(1.0, 0.12, 0.08), 0.0, 6.5)


func _build_room() -> void:
	var floor_mat: StandardMaterial3D = _mat(Color(0.07, 0.06, 0.13), 0.0, 0.28, 0.35)
	var wall_mat: StandardMaterial3D = _mat(Color(0.10, 0.09, 0.20), 0.0, 0.85)
	var ceil_mat: StandardMaterial3D = _mat(Color(0.04, 0.04, 0.08), 0.0, 0.9)

	_box(self, Vector3(10.4, 0.1, 9.9), Vector3(0.0, -0.05, -2.25), floor_mat)
	_box(self, Vector3(10.4, 0.1, 9.9), Vector3(0.0, 3.25, -2.25), ceil_mat)
	_box(self, Vector3(10.4, 3.3, 0.1), Vector3(0.0, 1.6, -7.05), wall_mat)
	_box(self, Vector3(0.1, 3.3, 9.9), Vector3(-5.05, 1.6, -2.25), wall_mat)
	# 右の壁は入口（z=-3.7〜-2.3）を空ける
	_box(self, Vector3(0.1, 3.3, 3.3), Vector3(5.05, 1.6, -5.35), wall_mat)
	_box(self, Vector3(0.1, 3.3, 4.8), Vector3(5.05, 1.6, 0.1), wall_mat)
	_box(self, Vector3(0.1, 0.9, 1.4), Vector3(5.05, 2.8, -3.0), wall_mat)
	# 入口の外は明るい通り
	_box(self, Vector3(0.05, 2.4, 1.4), Vector3(5.4, 1.2, -3.0), _mat(Color(1.0, 0.95, 0.8), 1.6))
	_box(self, Vector3(0.12, 0.08, 1.5), Vector3(5.0, 2.36, -3.0), _mat(Color(0.2, 1.0, 0.6), 2.5))
	var entrance: Label3D = _text(self, "入口", Vector3(4.98, 2.62, -3.0), 96, 0.0022, Color(0.5, 1.0, 0.75))
	entrance.rotation_degrees = Vector3(0.0, -90.0, 0.0)

	# カーペット模様（床に散らばる幾何学柄）
	for i in range(46):
		var c: Color = PALETTE[_rng.randi() % PALETTE.size()]
		var px: float = _rng.randf_range(-4.7, 4.7)
		var pz: float = _rng.randf_range(-6.7, 0.3)
		var deco: MeshInstance3D = null
		if _rng.randf() < 0.5:
			deco = _box(self, Vector3(_rng.randf_range(0.2, 0.5), 0.004, 0.06), Vector3(px, 0.003, pz), _mat(c, 0.35, 0.6))
		else:
			deco = _cyl(self, _rng.randf_range(0.05, 0.11), 0.004, Vector3(px, 0.003, pz), _mat(c, 0.35, 0.6))
		deco.rotation_degrees = Vector3(0.0, _rng.randf_range(0.0, 180.0), 0.0)

	# 壁のネオンライン
	_box(self, Vector3(10.2, 0.05, 0.03), Vector3(0.0, 2.35, -6.98), _mat(Color(1.0, 0.3, 0.7), 3.0))
	_box(self, Vector3(10.2, 0.05, 0.03), Vector3(0.0, 3.12, -6.98), _mat(Color(0.2, 0.8, 1.0), 3.0))
	_box(self, Vector3(0.03, 0.05, 9.6), Vector3(-4.98, 2.35, -2.25), _mat(Color(0.2, 0.8, 1.0), 3.0))
	_box(self, Vector3(0.03, 0.05, 3.2), Vector3(4.98, 2.35, -5.35), _mat(Color(1.0, 0.82, 0.25), 3.0))

	# 奥の壁の大看板
	# 大看板はお客さんの頭に隠れないよう、中央を避けて左右に分ける
	_text(self, "ゲームパラダイス", Vector3(-2.9, 2.8, -6.96), 170, 0.003, Color(1.0, 0.45, 0.78), Color(0.35, 0.0, 0.25))
	_text(self, "クレーンゲーム", Vector3(2.0, 2.8, -6.96), 120, 0.003, Color(0.45, 0.9, 1.0), Color(0.0, 0.2, 0.35))
	_poster("取れるまで\n応援します", Vector3(-4.97, 1.5, -6.2), 90.0, Color(0.75, 0.2, 0.6), Color(1.0, 1.0, 1.0))
	var zone: Label3D = _text(self, "クレーンゲーム\nコーナー", Vector3(-4.96, 2.78, -3.2), 120, 0.0026, Color(0.45, 0.9, 1.0), Color(0.0, 0.2, 0.35))
	zone.rotation_degrees = Vector3(0.0, 90.0, 0.0)

	# 天井のネオン管
	for i in range(5):
		var zc: float = -6.0 + float(i) * 1.5
		var col: Color = Color(1.0, 0.3, 0.7) if i % 2 == 0 else Color(0.2, 0.8, 1.0)
		_box(self, Vector3(7.5, 0.03, 0.03), Vector3(0.0, 3.16, zc), _mat(col, 3.5))

	# 天井から吊るしたPOP
	_hanging_pop("新景品\n入荷！", Vector3(-2.3, 2.62, -1.9), Color(1.0, 0.82, 0.25), Color(0.75, 0.1, 0.2))
	_hanging_pop("1PLAY\n100円", Vector3(2.2, 2.62, -2.4), Color(1.0, 1.0, 1.0), Color(0.15, 0.35, 0.9))

	# 貼り紙
	_poster("夜間の年少者の\n入場について", Vector3(4.97, 1.55, -1.4), -90.0, Color(0.95, 0.95, 0.9), Color(0.75, 0.1, 0.1))
	_poster("台を揺らさないで\nください", Vector3(-4.97, 1.5, -1.3), 90.0, Color(1.0, 0.9, 0.3), Color(0.1, 0.1, 0.1))


func _hanging_pop(txt: String, pos: Vector3, text_color: Color, bg: Color) -> void:
	var root: Node3D = _node(self, pos)
	_box(root, Vector3(0.95, 0.5, 0.02), Vector3.ZERO, _mat(bg, 0.5, 0.6))
	_box(root, Vector3(0.99, 0.54, 0.012), Vector3(0.0, 0.0, -0.006), _mat(Color(1, 1, 1), 0.8))
	_cyl(root, 0.004, 0.4, Vector3(-0.38, 0.45, 0.0), _mat(Color(0.7, 0.7, 0.7)))
	_cyl(root, 0.004, 0.4, Vector3(0.38, 0.45, 0.0), _mat(Color(0.7, 0.7, 0.7)))
	_text(root, txt, Vector3(0.0, 0.0, 0.015), 72, 0.0024, text_color)
	root.rotation_degrees = Vector3(0.0, _rng.randf_range(-8.0, 8.0), 0.0)
	_spinners.append({"node": root, "phase": _rng.randf_range(0.0, 6.0), "base": root.rotation_degrees.y})


func _poster(txt: String, pos: Vector3, yaw: float, bg: Color, text_color: Color) -> void:
	var root: Node3D = _node(self, pos)
	root.rotation_degrees = Vector3(0.0, yaw, 0.0)
	_box(root, Vector3(0.7, 0.5, 0.01), Vector3.ZERO, _mat(bg, 0.25, 0.8))
	_text(root, txt, Vector3(0.0, 0.0, 0.012), 48, 0.0022, text_color)


func _build_counter() -> void:
	var body: StandardMaterial3D = _mat(Color(0.20, 0.13, 0.36), 0.0, 0.6)
	var top: StandardMaterial3D = _mat(Color(0.86, 0.84, 0.95), 0.0, 0.25, 0.1)
	_box(self, Vector3(3.2, 0.96, 0.5), Vector3(0.0, 0.48, 0.8), body)
	_box(self, Vector3(3.3, 0.05, 0.6), Vector3(0.0, 0.985, 0.8), top)
	# お客さん側の正面ネオン
	_box(self, Vector3(3.1, 0.04, 0.02), Vector3(0.0, 0.82, 0.54), _mat(Color(1.0, 0.3, 0.7), 3.0))
	_box(self, Vector3(3.1, 0.04, 0.02), Vector3(0.0, 0.2, 0.54), _mat(Color(0.2, 0.8, 1.0), 3.0))
	var staff: Label3D = _text(self, "スタッフカウンター", Vector3(0.0, 0.52, 0.535), 80, 0.0024, Color(1.0, 0.95, 0.6))
	staff.rotation_degrees = Vector3(0.0, 180.0, 0.0)

	# レジ
	var reg: Node3D = _node(self, Vector3(-1.2, 1.01, 0.82))
	_box(reg, Vector3(0.42, 0.12, 0.36), Vector3(0.0, 0.06, 0.0), _mat(Color(0.15, 0.15, 0.18), 0.0, 0.4))
	var screen: MeshInstance3D = _box(reg, Vector3(0.34, 0.24, 0.02), Vector3(0.0, 0.27, -0.05), _mat(Color(0.3, 0.9, 1.0), 1.2))
	screen.rotation_degrees = Vector3(18.0, 0.0, 0.0)
	_cyl(reg, 0.02, 0.14, Vector3(0.0, 0.16, -0.08), _mat(Color(0.2, 0.2, 0.22)))
	# 呼び出しベル
	_cyl(self, 0.06, 0.012, Vector3(-0.72, 1.016, 0.72), _mat(Color(0.1, 0.1, 0.1)))
	_sph(self, Vector3(0.1, 0.07, 0.1), Vector3(-0.72, 1.04, 0.72), _mat(Color(0.95, 0.8, 0.3), 0.0, 0.2, 0.9))
	# 補充用ぬいぐるみの箱
	var crate: Node3D = _node(self, Vector3(1.18, 1.01, 0.82))
	_box(crate, Vector3(0.5, 0.2, 0.36), Vector3(0.0, 0.1, 0.0), _mat(Color(0.72, 0.55, 0.36), 0.0, 0.9))
	_plush(crate, Vector3(-0.12, 0.17, 0.0), 0.17, 0, PLUSH_COLORS[1], true)
	_plush(crate, Vector3(0.12, 0.17, 0.02), 0.17, 3, PLUSH_COLORS[6], true)
	# 両替のトレー
	_box(self, Vector3(0.26, 0.012, 0.18), Vector3(0.72, 1.017, 0.74), _mat(Color(0.1, 0.35, 0.3), 0.0, 0.5))
	_cyl(self, 0.014, 0.004, Vector3(0.68, 1.026, 0.74), _mat(Color(0.9, 0.9, 0.92), 0.0, 0.2, 0.9))
	_cyl(self, 0.014, 0.004, Vector3(0.75, 1.026, 0.77), _mat(Color(0.95, 0.8, 0.3), 0.0, 0.2, 0.9))


func _build_cranes() -> void:
	var titles: Array = ["ぬいぐるみ", "うさねこ", "ぴよぴよ", "フィギュア", "おかし", "ぬいぐるみ", "うさねこ", "おかし"]
	var n: int = 0
	# 奥の壁沿い
	for i in range(5):
		_crane(Vector3(-4.2 + float(i) * 1.45, 0.0, -6.35), 0.0, n, titles[n % titles.size()], 1.0, false)
		n += 1
	# お客さんの真後ろの島（一番よく見えるので作り込む）
	_crane(Vector3(-2.5, 0.0, -3.7), 0.0, 0, "ぬいぐるみ", 1.0, true)
	_crane(Vector3(-1.25, 0.0, -3.7), 0.0, 2, "ぴよぴよ", 1.0, true)
	_crane(Vector3(0.0, 0.0, -3.7), 0.0, 3, "フィギュア", 1.0, true)
	_crane(Vector3(1.25, 0.0, -3.7), 0.0, 4, "おかし", 1.0, true)
	# 右奥の列
	_crane(Vector3(1.9, 0.0, -5.1), 0.0, 6, "うさねこ", 1.0, false)
	# 左の壁沿い
	_crane(Vector3(-4.35, 0.0, -2.5), 90.0, 7, "ぬいぐるみ", 1.0, true)
	_crane(Vector3(-4.35, 0.0, -3.9), 90.0, 1, "うさねこ", 1.0, false)
	_crane(Vector3(-4.35, 0.0, -5.15), 90.0, 5, "ぴよぴよ", 1.0, false)
	# 右の壁沿いと、右奥のジャンボ機
	_crane(Vector3(4.35, 0.0, -4.75), -90.0, 3, "おかし", 1.0, false)
	_crane(Vector3(3.55, 0.0, -6.15), 0.0, 5, "ジャンボ", 1.38, true)


## クレーンゲーム機を1台作る。正面はローカル +Z。
## theme: 景品と配色の種類 / detailed: 近くで見える台は景品を細かく作る
func _crane(pos: Vector3, yaw: float, theme: int, title: String, big: float, detailed: bool) -> void:
	var root: Node3D = _node(self, pos)
	root.rotation_degrees = Vector3(0.0, yaw, 0.0)
	root.scale = Vector3(big, big, big)
	var col: Color = PALETTE[theme % PALETTE.size()]
	var accent: Color = PALETTE[(theme + 3) % PALETTE.size()]
	var body: StandardMaterial3D = _mat(col, 0.0, 0.45)
	var dark: StandardMaterial3D = _mat(Color(0.08, 0.08, 0.12), 0.0, 0.5)
	var white: StandardMaterial3D = _mat(Color(0.95, 0.95, 0.97), 0.0, 0.4)
	# 金属部品。映り込む物が少ない暗い店内でも銀色に見えるよう、金属度は控えめにする
	var chrome: StandardMaterial3D = _mat(Color(0.88, 0.9, 0.94), 0.12, 0.3, 0.45)
	var neon: StandardMaterial3D = _mat(accent, 2.6)
	var blink: StandardMaterial3D = _new_mat(accent, 2.0)
	_blink_mats.append({"mat": blink, "phase": _rng.randf_range(0.0, 6.28), "speed": _rng.randf_range(2.0, 5.0)})

	# --- 本体（下部キャビネット）
	_box(root, Vector3(1.1, 0.8, 0.9), Vector3(0.0, 0.4, 0.0), body)
	_box(root, Vector3(1.12, 0.08, 0.92), Vector3(0.0, 0.04, 0.0), dark)
	_box(root, Vector3(1.0, 0.03, 0.02), Vector3(0.0, 0.74, 0.455), neon)
	_box(root, Vector3(1.0, 0.03, 0.02), Vector3(0.0, 0.12, 0.455), neon)
	# 景品取り出し口
	_box(root, Vector3(0.42, 0.3, 0.02), Vector3(-0.26, 0.34, 0.452), white)
	_box(root, Vector3(0.36, 0.24, 0.03), Vector3(-0.26, 0.34, 0.456), dark)
	var flap: MeshInstance3D = _box(root, Vector3(0.34, 0.2, 0.008), Vector3(-0.26, 0.35, 0.474), _mat(Color(0.7, 0.9, 1.0, 0.28), 0.0, 0.05))
	flap.rotation_degrees = Vector3(-10.0, 0.0, 0.0)
	# コイン投入口と料金表示
	_box(root, Vector3(0.12, 0.2, 0.02), Vector3(0.36, 0.42, 0.455), chrome)
	_box(root, Vector3(0.05, 0.008, 0.025), Vector3(0.36, 0.46, 0.46), dark)
	_box(root, Vector3(0.08, 0.05, 0.022), Vector3(0.36, 0.37, 0.458), blink)
	if detailed:
		_text(root, "100円", Vector3(0.36, 0.56, 0.47), 40, 0.0016, Color(1.0, 0.95, 0.5))
	# 操作パネル
	_box(root, Vector3(1.1, 0.16, 0.24), Vector3(0.0, 0.76, 0.52), body)
	var panel: MeshInstance3D = _box(root, Vector3(1.08, 0.03, 0.27), Vector3(0.0, 0.855, 0.53), dark)
	panel.rotation_degrees = Vector3(14.0, 0.0, 0.0)
	_cyl(root, 0.011, 0.1, Vector3(-0.28, 0.91, 0.55), chrome)
	_sph(root, Vector3(0.055, 0.055, 0.055), Vector3(-0.28, 0.97, 0.55), _mat(Color(0.95, 0.15, 0.2), 0.3, 0.25))
	_cyl(root, 0.042, 0.03, Vector3(0.06, 0.875, 0.56), blink)
	_cyl(root, 0.042, 0.03, Vector3(0.22, 0.875, 0.56), _mat(Color(0.3, 1.0, 0.5), 1.6))
	_cyl(root, 0.05, 0.014, Vector3(0.06, 0.862, 0.56), chrome)
	_cyl(root, 0.05, 0.014, Vector3(0.22, 0.862, 0.56), chrome)

	# --- ガラスケース
	_box(root, Vector3(1.04, 0.03, 0.84), Vector3(0.0, 0.815, 0.0), white)
	_box(root, Vector3(0.3, 0.034, 0.3), Vector3(-0.33, 0.817, 0.24), dark)
	var fence: StandardMaterial3D = _mat(Color(0.8, 0.95, 1.0, 0.22), 0.0, 0.05)
	_box(root, Vector3(0.008, 0.16, 0.3), Vector3(-0.18, 0.9, 0.24), fence)
	_box(root, Vector3(0.3, 0.16, 0.008), Vector3(-0.33, 0.9, 0.09), fence)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(root, Vector3(0.05, 1.05, 0.05), Vector3(0.525 * sx, 1.345, 0.425 * sz), chrome)
	var back_col: Color = col.lerp(Color(1, 1, 1), 0.55)
	_box(root, Vector3(1.0, 1.05, 0.02), Vector3(0.0, 1.345, -0.43), _mat(back_col, 0.55, 0.8))
	# 背面の模様（星の代わりの丸）
	for i in range(5):
		_cyl(root, _rng.randf_range(0.04, 0.09), 0.006, Vector3(_rng.randf_range(-0.4, 0.4), _rng.randf_range(1.25, 1.75), -0.416), _mat(accent.lerp(Color(1, 1, 1), 0.3), 0.9)).rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var glass: StandardMaterial3D = _mat(Color(0.75, 0.93, 1.0, 0.1), 0.0, 0.03, 0.2)
	_box(root, Vector3(1.0, 1.05, 0.012), Vector3(0.0, 1.345, 0.44), glass)
	_box(root, Vector3(0.012, 1.05, 0.8), Vector3(-0.54, 1.345, 0.0), glass)
	_box(root, Vector3(0.012, 1.05, 0.8), Vector3(0.54, 1.345, 0.0), glass)
	# ガラスの映り込み風ハイライト
	var shine: MeshInstance3D = _box(root, Vector3(0.06, 0.8, 0.004), Vector3(0.3, 1.4, 0.449), _mat(Color(1, 1, 1, 0.1), 0.0, 0.05))
	shine.rotation_degrees = Vector3(0.0, 0.0, -18.0)
	# 庫内照明
	_box(root, Vector3(0.9, 0.02, 0.1), Vector3(0.0, 1.86, 0.3), _mat(Color(1.0, 0.98, 0.92), 3.0))
	_box(root, Vector3(0.9, 0.02, 0.1), Vector3(0.0, 1.86, -0.3), _mat(Color(1.0, 0.98, 0.92), 3.0))

	_fill_prizes(root, theme, detailed, big)

	# --- クレーン機構
	var rail: MeshInstance3D = _box(root, Vector3(1.0, 0.03, 0.04), Vector3(0.0, 1.82, 0.0), chrome)
	_box(root, Vector3(0.03, 0.03, 0.8), Vector3(-0.5, 1.84, 0.0), chrome)
	_box(root, Vector3(0.03, 0.03, 0.8), Vector3(0.5, 1.84, 0.0), chrome)
	var carriage: Node3D = _node(root, Vector3(0.0, 1.78, 0.0))
	_box(carriage, Vector3(0.14, 0.07, 0.14), Vector3.ZERO, _mat(accent, 0.4, 0.4))
	var wire: MeshInstance3D = _cyl(carriage, 0.006, 1.0, Vector3(0.0, -0.1, 0.0), chrome)
	var claw: Node3D = _node(carriage, Vector3(0.0, -0.2, 0.0))
	_cyl(claw, 0.045, 0.06, Vector3.ZERO, chrome)
	_sph(claw, Vector3(0.05, 0.05, 0.05), Vector3(0.0, -0.03, 0.0), _mat(accent, 1.2))
	var prongs: Array = []
	for i in range(3):
		var arm: Node3D = _node(claw, Vector3.ZERO)
		arm.rotation_degrees = Vector3(0.0, 120.0 * float(i), 0.0)
		var hinge: Node3D = _node(arm, Vector3(0.04, -0.02, 0.0))
		_box(hinge, Vector3(0.014, 0.15, 0.03), Vector3(0.0, -0.075, 0.0), chrome)
		var tip: MeshInstance3D = _box(hinge, Vector3(0.05, 0.014, 0.03), Vector3(-0.02, -0.15, 0.0), chrome)
		tip.rotation_degrees = Vector3(0.0, 0.0, -20.0)
		prongs.append(hinge)

	# --- ヘッダー（看板）
	_box(root, Vector3(1.14, 0.3, 0.94), Vector3(0.0, 2.02, 0.0), body)
	_box(root, Vector3(1.0, 0.22, 0.02), Vector3(0.0, 2.02, 0.472), _mat(Color(0.06, 0.05, 0.12), 0.0, 0.4))
	_box(root, Vector3(1.04, 0.02, 0.025), Vector3(0.0, 2.14, 0.474), neon)
	_box(root, Vector3(1.04, 0.02, 0.025), Vector3(0.0, 1.9, 0.474), neon)
	_text(root, title, Vector3(0.0, 2.02, 0.486), 72, 0.0021, accent.lerp(Color(1, 1, 1), 0.45), Color(0, 0, 0, 0.6))
	var lamp_mat: StandardMaterial3D = _new_mat(Color(1.0, 0.85, 0.2), 2.0)
	_blink_mats.append({"mat": lamp_mat, "phase": _rng.randf_range(0.0, 6.28), "speed": 6.0})
	_cyl(root, 0.05, 0.03, Vector3(0.42, 2.185, 0.25), dark)
	_sph(root, Vector3(0.1, 0.1, 0.1), Vector3(0.42, 2.22, 0.25), lamp_mat)

	_cranes.append({
		"carriage": carriage, "rail": rail, "wire": wire, "claw": claw, "prongs": prongs,
		"phase": _rng.randf_range(0.0, 20.0), "speed": _rng.randf_range(0.35, 0.6),
	})


## ケースの中に景品を積む
func _fill_prizes(root: Node3D, theme: int, detailed: bool, big: float) -> void:
	var kind: int = theme % 6
	if big > 1.2:
		# ジャンボ機: 巨大ぬいぐるみを1体、どーんと置く
		_plush(root, Vector3(0.1, 0.83, -0.05), 0.5, 0, PLUSH_COLORS[0], true)
		_plush(root, Vector3(-0.3, 0.83, -0.25), 0.2, 3, PLUSH_COLORS[6], true)
		return
	var count: int = 11 if detailed else 8
	for i in range(count):
		var px: float = _rng.randf_range(-0.4, 0.4)
		var pz: float = _rng.randf_range(-0.32, 0.3)
		# 取り出し口の穴の上には置かない
		if px < -0.14 and pz > 0.05:
			px += 0.45
		var layer: float = 0.83 + (0.11 if i >= count - 3 else 0.0)
		var p: Vector3 = Vector3(px, layer, pz)
		var c: Color = PLUSH_COLORS[_rng.randi() % PLUSH_COLORS.size()]
		if kind == 0 or kind == 5:
			_plush(root, p, 0.19, _rng.randi() % 3, c, detailed)
		elif kind == 1 or kind == 6:
			_plush(root, p, 0.19, 1 + (_rng.randi() % 2), c.lerp(Color(1, 1, 1), 0.35), detailed)
		elif kind == 2:
			_plush(root, p, 0.18, 3, Color(1.0, 0.86, 0.3), detailed)
		elif kind == 3:
			_figure_box(root, p, PALETTE[_rng.randi() % PALETTE.size()])
		else:
			_snack(root, p, PALETTE[_rng.randi() % PALETTE.size()])


## ぬいぐるみ。kind: 0=くま 1=うさぎ 2=ねこ 3=ひよこ / s: 大きさ（高さの目安は s*1.4）
func _plush(parent: Node3D, pos: Vector3, s: float, kind: int, color: Color, detailed: bool) -> void:
	var root: Node3D = _node(parent, pos)
	root.rotation_degrees = Vector3(_rng.randf_range(-14.0, 14.0), _rng.randf_range(-50.0, 50.0), _rng.randf_range(-14.0, 14.0))
	var fur: StandardMaterial3D = _mat(color, 0.0, 0.95)
	var light: StandardMaterial3D = _mat(color.lerp(Color(1, 1, 1), 0.55), 0.0, 0.95)
	var black: StandardMaterial3D = _mat(Color(0.05, 0.05, 0.06), 0.0, 0.3)
	_sph(root, Vector3(0.9, 0.85, 0.8) * s, Vector3(0.0, 0.42 * s, 0.0), fur)
	_sph(root, Vector3(0.8, 0.74, 0.74) * s, Vector3(0.0, 0.98 * s, 0.0), fur)
	_sph(root, Vector3(0.09, 0.1, 0.06) * s, Vector3(-0.16 * s, 1.03 * s, 0.33 * s), black)
	_sph(root, Vector3(0.09, 0.1, 0.06) * s, Vector3(0.16 * s, 1.03 * s, 0.33 * s), black)
	if kind == 0:
		_sph(root, Vector3(0.28, 0.28, 0.16) * s, Vector3(-0.3 * s, 1.3 * s, 0.0), fur)
		_sph(root, Vector3(0.28, 0.28, 0.16) * s, Vector3(0.3 * s, 1.3 * s, 0.0), fur)
		_sph(root, Vector3(0.32, 0.24, 0.2) * s, Vector3(0.0, 0.9 * s, 0.31 * s), light)
		_sph(root, Vector3(0.1, 0.07, 0.06) * s, Vector3(0.0, 0.95 * s, 0.41 * s), black)
	elif kind == 1:
		_sph(root, Vector3(0.17, 0.6, 0.12) * s, Vector3(-0.16 * s, 1.55 * s, 0.0), fur)
		_sph(root, Vector3(0.17, 0.6, 0.12) * s, Vector3(0.16 * s, 1.55 * s, 0.0), fur)
		_sph(root, Vector3(0.09, 0.4, 0.05) * s, Vector3(-0.16 * s, 1.55 * s, 0.05 * s), _mat(Color(1.0, 0.7, 0.78), 0.0, 0.9))
		_sph(root, Vector3(0.09, 0.4, 0.05) * s, Vector3(0.16 * s, 1.55 * s, 0.05 * s), _mat(Color(1.0, 0.7, 0.78), 0.0, 0.9))
		_sph(root, Vector3(0.08, 0.06, 0.05) * s, Vector3(0.0, 0.93 * s, 0.37 * s), _mat(Color(1.0, 0.5, 0.6), 0.0, 0.6))
	elif kind == 2:
		_mesh(root, _cone_mesh, Vector3(0.26, 0.3, 0.14) * s, Vector3(-0.24 * s, 1.38 * s, 0.0), fur)
		_mesh(root, _cone_mesh, Vector3(0.26, 0.3, 0.14) * s, Vector3(0.24 * s, 1.38 * s, 0.0), fur)
		_sph(root, Vector3(0.07, 0.05, 0.05) * s, Vector3(0.0, 0.94 * s, 0.37 * s), _mat(Color(1.0, 0.5, 0.6), 0.0, 0.6))
	else:
		var beak: MeshInstance3D = _mesh(root, _cone_mesh, Vector3(0.16, 0.18, 0.16) * s, Vector3(0.0, 0.92 * s, 0.4 * s), _mat(Color(1.0, 0.5, 0.1), 0.0, 0.6))
		beak.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		_sph(root, Vector3(0.14, 0.2, 0.1) * s, Vector3(0.0, 1.38 * s, 0.0), fur)
	if detailed:
		_sph(root, Vector3(0.5, 0.48, 0.2) * s, Vector3(0.0, 0.42 * s, 0.3 * s), light)
		_sph(root, Vector3(0.26, 0.26, 0.26) * s, Vector3(-0.44 * s, 0.55 * s, 0.1 * s), fur)
		_sph(root, Vector3(0.26, 0.26, 0.26) * s, Vector3(0.44 * s, 0.55 * s, 0.1 * s), fur)
		_sph(root, Vector3(0.3, 0.22, 0.34) * s, Vector3(-0.24 * s, 0.1 * s, 0.26 * s), fur)
		_sph(root, Vector3(0.3, 0.22, 0.34) * s, Vector3(0.24 * s, 0.1 * s, 0.26 * s), fur)
		# ほっぺ
		_sph(root, Vector3(0.12, 0.08, 0.04) * s, Vector3(-0.27 * s, 0.92 * s, 0.3 * s), _mat(Color(1.0, 0.6, 0.65), 0.0, 0.9))
		_sph(root, Vector3(0.12, 0.08, 0.04) * s, Vector3(0.27 * s, 0.92 * s, 0.3 * s), _mat(Color(1.0, 0.6, 0.65), 0.0, 0.9))


func _figure_box(parent: Node3D, pos: Vector3, color: Color) -> void:
	var root: Node3D = _node(parent, pos + Vector3(0.0, 0.1, 0.0))
	root.rotation_degrees = Vector3(_rng.randf_range(-8.0, 8.0), _rng.randf_range(-35.0, 35.0), _rng.randf_range(-20.0, 20.0))
	_box(root, Vector3(0.15, 0.21, 0.09), Vector3.ZERO, _mat(color, 0.0, 0.5))
	_box(root, Vector3(0.1, 0.12, 0.004), Vector3(0.0, 0.02, 0.046), _mat(Color(0.85, 0.95, 1.0, 0.45), 0.0, 0.05))
	_sph(root, Vector3(0.05, 0.05, 0.03), Vector3(0.0, 0.045, 0.03), _mat(Color(1.0, 0.85, 0.7), 0.0, 0.7))
	_box(root, Vector3(0.04, 0.06, 0.02), Vector3(0.0, -0.005, 0.03), _mat(color.lerp(Color(1, 1, 1), 0.5), 0.0, 0.7))
	_box(root, Vector3(0.13, 0.03, 0.004), Vector3(0.0, -0.075, 0.046), _mat(Color(1.0, 0.95, 0.4), 0.4))


func _snack(parent: Node3D, pos: Vector3, color: Color) -> void:
	var root: Node3D = _node(parent, pos + Vector3(0.0, 0.05, 0.0))
	root.rotation_degrees = Vector3(_rng.randf_range(-25.0, 25.0), _rng.randf_range(0.0, 180.0), _rng.randf_range(-25.0, 25.0))
	var r: float = _rng.randf()
	if r < 0.4:
		_box(root, Vector3(0.17, 0.05, 0.11), Vector3.ZERO, _mat(color, 0.0, 0.4))
		_box(root, Vector3(0.1, 0.052, 0.06), Vector3.ZERO, _mat(Color(1, 1, 1), 0.0, 0.5))
	elif r < 0.75:
		_cyl(root, 0.045, 0.16, Vector3.ZERO, _mat(color, 0.0, 0.3, 0.2))
		_cyl(root, 0.047, 0.05, Vector3.ZERO, _mat(Color(1.0, 0.95, 0.5), 0.0, 0.4))
	else:
		_sph(root, Vector3(0.14, 0.1, 0.14), Vector3.ZERO, _mat(color, 0.0, 0.35))
		_box(root, Vector3(0.2, 0.03, 0.05), Vector3.ZERO, _mat(color.lerp(Color(1, 1, 1), 0.4), 0.0, 0.4))


## クレーン以外の小物（両替機・ビデオゲーム筐体・カゴ）
func _build_extras() -> void:
	# 両替機（入口の脇）
	var ex: Node3D = _node(self, Vector3(4.6, 0.0, -1.9))
	ex.rotation_degrees = Vector3(0.0, -90.0, 0.0)
	_box(ex, Vector3(0.7, 1.5, 0.5), Vector3(0.0, 0.75, 0.0), _mat(Color(0.85, 0.87, 0.9), 0.0, 0.35, 0.5))
	_box(ex, Vector3(0.5, 0.22, 0.02), Vector3(0.0, 1.2, 0.255), _mat(Color(0.2, 1.0, 0.5), 1.5))
	_box(ex, Vector3(0.3, 0.05, 0.02), Vector3(0.0, 0.85, 0.255), _mat(Color(0.05, 0.05, 0.05)))
	_box(ex, Vector3(0.36, 0.14, 0.06), Vector3(0.0, 0.5, 0.25), _mat(Color(0.1, 0.1, 0.1)))
	_text(ex, "両替機", Vector3(0.0, 1.2, 0.27), 64, 0.0022, Color(0.05, 0.2, 0.1))

	# ビデオゲーム筐体を2台だけ（手前左）
	for i in range(2):
		var cab: Node3D = _node(self, Vector3(-4.45, 0.0, -0.7 + float(i) * 0.95))
		cab.rotation_degrees = Vector3(0.0, 90.0, 0.0)
		var c: Color = PALETTE[(i * 3 + 1) % PALETTE.size()]
		_box(cab, Vector3(0.75, 1.75, 0.8), Vector3(0.0, 0.875, 0.0), _mat(Color(0.1, 0.1, 0.16), 0.0, 0.5))
		var scr_mat: StandardMaterial3D = _new_mat(c, 1.6)
		_blink_mats.append({"mat": scr_mat, "phase": float(i) * 2.0, "speed": 1.3})
		var scr: MeshInstance3D = _box(cab, Vector3(0.6, 0.45, 0.02), Vector3(0.0, 1.25, 0.39), scr_mat)
		scr.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
		_box(cab, Vector3(0.75, 0.06, 0.35), Vector3(0.0, 0.9, 0.5), _mat(c, 0.0, 0.4))
		_box(cab, Vector3(0.7, 0.18, 0.02), Vector3(0.0, 1.62, 0.41), _mat(c, 2.2))

	# 景品を入れるカゴの山
	var basket: StandardMaterial3D = _mat(Color(0.95, 0.35, 0.45), 0.0, 0.5)
	for i in range(3):
		_box(self, Vector3(0.42, 0.06, 0.3), Vector3(2.75, 0.03 + float(i) * 0.065, -6.55), basket)
	# 足元の「ここに並んでください」テープ
	_box(self, Vector3(1.2, 0.004, 0.06), Vector3(0.0, 0.004, 0.2), _mat(Color(1.0, 0.82, 0.25), 0.6))


# ---------------------------------------------------------------- 毎フレーム

func set_tension(t: float) -> void:
	_tension = clampf(t, 0.0, 1.0)


func _process(delta: float) -> void:
	if not _built:
		return
	_time += delta
	# クレーンが左右・前後に動き、ときどき降りてつかむ動作をする
	for item in _cranes:
		var cr: Dictionary = item
		var ph: float = _time * float(cr["speed"]) + float(cr["phase"])
		var cx: float = sin(ph) * 0.33
		var cz: float = sin(ph * 0.63 + 1.3) * 0.24
		var drop: float = pow(maxf(0.0, sin(ph * 0.5)), 10.0) * 0.52
		var carriage: Node3D = cr["carriage"]
		carriage.position = Vector3(cx, 1.78, cz)
		var rail: MeshInstance3D = cr["rail"]
		rail.position = Vector3(0.0, 1.82, cz)
		var length: float = 0.16 + drop
		var wire: MeshInstance3D = cr["wire"]
		wire.scale = Vector3(0.012, length, 0.012)
		wire.position = Vector3(0.0, -length * 0.5, 0.0)
		var claw: Node3D = cr["claw"]
		claw.position = Vector3(0.0, -length - 0.03, 0.0)
		var open: float = 34.0 - 26.0 * clampf(drop / 0.52, 0.0, 1.0)
		for h in (cr["prongs"] as Array):
			var hinge: Node3D = h
			hinge.rotation_degrees = Vector3(0.0, 0.0, open)
	# ボタンやランプの点滅
	for item in _blink_mats:
		var b: Dictionary = item
		var m: StandardMaterial3D = b["mat"]
		m.emission_energy_multiplier = 1.3 + 1.2 * sin(_time * float(b["speed"]) + float(b["phase"]))
	# 吊りPOPの揺れ
	for item in _spinners:
		var s: Dictionary = item
		var n: Node3D = s["node"]
		n.rotation_degrees = Vector3(0.0, float(s["base"]) + sin(_time * 0.8 + float(s["phase"])) * 6.0, sin(_time * 1.1 + float(s["phase"])) * 2.0)
	# お客さんがキレそうになると赤く明滅する
	if _tension_light != null:
		var pulse: float = 0.75 + 0.25 * sin(_time * (4.0 + 8.0 * _tension))
		_tension_light.light_energy = 4.0 * _tension * pulse
