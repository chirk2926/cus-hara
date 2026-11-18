extends Node3D
## タイトルの背景だけに使う場面（要件#84。ショップの背景ガチャで手に入る）。
## メダルコーナー・ビデオゲームコーナー・音ゲーコーナー・事務所（人生に疲れた店長）・プリクラコーナー（あやしいおじさん）。
## カメラはタイトルのいつもの位置（main.gd の CAMERA_POS あたり。奥の -z を見る）から見る前提で並べる。

const CustomerScript = preload("res://scripts/customer_character.gd")

var label_font: Font = null
var _blink: Array = []      # {mat, base, speed, phase}
var _time: float = 0.0
var _flicker: OmniLight3D = null
var _spin_nodes: Array = []
var _rage_label: Label3D = null


func build(kind: String) -> void:
	match kind:
		"bg_medal":
			_build_medal()
		"bg_video":
			_build_video(false)
		"bg_video_rage":
			_build_video(true)
		"bg_rhythm":
			_build_rhythm()
		"bg_office":
			_build_office()
		"bg_purikura":
			_build_purikura()
		"bg_locker":
			_build_locker()
		"bg_toilet":
			_build_toilet()
		"bg_warehouse":
			_build_warehouse()
		"bg_manager_home":
			_build_manager_home()
		"bg_parents_home":
			_build_parents_home()
		_:
			_build_video(false)


func set_tension(_t: float) -> void:
	pass


func _process(delta: float) -> void:
	_time += delta
	for b in _blink:
		var d: Dictionary = b
		var m: StandardMaterial3D = d["mat"]
		m.emission_energy_multiplier = float(d["base"]) * (0.35 + 0.65 * (0.5 + 0.5 * sin(_time * float(d["speed"]) + float(d["phase"]))))
	for n in _spin_nodes:
		if is_instance_valid(n):
			(n as Node3D).rotation.y += delta * 2.0
	# 事務所の蛍光灯: 9秒に1回ほど、0.2秒だけ少し暗くなる（要件#86: チカチカしすぎて目に悪かった）
	if _flicker != null:
		var f: float = fmod(_time, 9.0)
		_flicker.light_energy = 0.85 if (f > 8.6 and f < 8.8) else 1.1
	# 台パンの「ドンッ！！」はたたくたびに見え隠れ
	if _rage_label != null:
		_rage_label.visible = absf(sin(_time * 4.5)) > 0.7


# ---------------------------------------------------------------- 部品

func _mat(c: Color, emission: float = 0.0, rough: float = 0.7, metal: float = 0.0) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	return m


func _blink_mat(c: Color, energy: float, speed: float, phase: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = _mat(c, energy)
	_blink.append({"mat": m, "base": energy, "speed": speed, "phase": phase})
	return m


func _glass() -> StandardMaterial3D:
	var m: StandardMaterial3D = _mat(Color(0.8, 0.9, 1.0, 0.18), 0.0, 0.05)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _node(parent: Node3D, pos: Vector3, yaw_deg: float = 0.0) -> Node3D:
	var n: Node3D = Node3D.new()
	n.position = pos
	n.rotation_degrees.y = yaw_deg
	parent.add_child(n)
	return n


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 20
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _label(parent: Node3D, txt: String, pos: Vector3, px: int, color: Color, pixel: float = 0.004, yaw_deg: float = 0.0) -> Label3D:
	var l: Label3D = Label3D.new()
	l.text = txt
	l.font_size = px
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.7)
	l.position = pos
	l.rotation_degrees.y = yaw_deg
	if label_font != null:
		l.font = label_font
	parent.add_child(l)
	return l


func _omni(pos: Vector3, color: Color, energy: float, rng: float) -> OmniLight3D:
	var o: OmniLight3D = OmniLight3D.new()
	o.position = pos
	o.light_color = color
	o.light_energy = energy
	o.omni_range = rng
	add_child(o)
	return o


func _env(bg: Color, ambient: Color, energy: float, glow: float) -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_energy = energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = glow > 0.0
	env.glow_intensity = glow
	env.glow_bloom = 0.1
	env.ssao_enabled = true
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.light_energy = 0.35
	sun.rotation_degrees = Vector3(-60.0, 25.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)


## 床・壁・天井（奥が -z。カメラは +z 側）
func _room(floor_c: Color, wall_c: Color, ceil_c: Color, w: float = 10.0, depth: float = 10.0, h: float = 3.2) -> void:
	_box(self, Vector3(w, 0.1, depth + 4.0), Vector3(0.0, -0.05, -depth * 0.5 + 2.0), _mat(floor_c, 0.0, 0.85))
	_box(self, Vector3(w, h, 0.1), Vector3(0.0, h * 0.5, -depth + 2.0), _mat(wall_c))
	for sx in [-1.0, 1.0]:
		_box(self, Vector3(0.1, h, depth + 4.0), Vector3(sx * w * 0.5, h * 0.5, -depth * 0.5 + 2.0), _mat(wall_c.darkened(0.1)))
	_box(self, Vector3(w, 0.1, depth + 4.0), Vector3(0.0, h, -depth * 0.5 + 2.0), _mat(ceil_c))


func _stool(pos: Vector3, seat_c: Color) -> void:
	var n: Node3D = _node(self, pos)
	_cyl(n, 0.03, 0.03, 0.6, Vector3(0.0, 0.3, 0.0), _mat(Color(0.6, 0.6, 0.65), 0.0, 0.3, 0.8))
	_cyl(n, 0.2, 0.2, 0.08, Vector3(0.0, 0.62, 0.0), _mat(seat_c, 0.0, 0.6))
	_cyl(n, 0.22, 0.22, 0.02, Vector3(0.0, 0.01, 0.0), _mat(Color(0.3, 0.3, 0.32), 0.0, 0.4, 0.6))


func _person(look: Dictionary, pos: Vector3, yaw: float, pose: String) -> Node3D:
	var c: Node3D = CustomerScript.new()
	add_child(c)
	c.call("setup", look)
	c.position = pos
	c.rotation.y = yaw
	c.set("hold_pose", pose)
	return c


# ---------------------------------------------------------------- メダルコーナー（にぎやかな見た目。ギャンブルではない。要件#86, #89）

func _slot(pos: Vector3, yaw: float, seed_i: int) -> void:
	var n: Node3D = _node(self, pos)
	n.rotation.y = yaw
	_box(n, Vector3(0.7, 1.7, 0.6), Vector3(0.0, 0.85, 0.0), _mat(Color(0.55, 0.06, 0.1), 0.0, 0.35, 0.3))
	_box(n, Vector3(0.74, 0.12, 0.64), Vector3(0.0, 1.76, 0.0), _mat(Color(0.95, 0.75, 0.25), 0.6, 0.3, 0.8))
	_box(n, Vector3(0.56, 0.3, 0.02), Vector3(0.0, 1.25, 0.31), _mat(Color(0.98, 0.95, 0.85), 0.3))
	for k in range(3):
		var sym: Color = [Color(0.95, 0.15, 0.2), Color(1.0, 0.8, 0.1), Color(0.2, 0.7, 1.0)][(k + seed_i) % 3]
		_box(n, Vector3(0.12, 0.16, 0.01), Vector3(-0.17 + 0.17 * float(k), 1.25, 0.325), _blink_mat(sym, 1.5, 3.0 + float(k), float(seed_i + k)))
	_box(n, Vector3(0.6, 0.35, 0.02), Vector3(0.0, 1.55, 0.31), _blink_mat(Color(1.0, 0.4, 0.6), 1.4, 2.0, float(seed_i)))
	_box(n, Vector3(0.6, 0.06, 0.25), Vector3(0.0, 0.95, 0.4), _mat(Color(0.15, 0.12, 0.12)))
	var lever: MeshInstance3D = _cyl(n, 0.015, 0.015, 0.4, Vector3(0.4, 1.25, 0.1), _mat(Color(0.8, 0.8, 0.85), 0.0, 0.3, 0.9))
	lever.rotation.z = -0.2
	_cyl(n, 0.045, 0.045, 0.06, Vector3(0.44, 1.46, 0.1), _mat(Color(0.95, 0.1, 0.15), 0.4))
	_stool(pos + Vector3(sin(yaw) * 0.75, 0.0, cos(yaw) * 0.75), Color(0.75, 0.1, 0.15))


func _chips(parent: Node3D, pos: Vector3) -> void:
	var cols: Array = [Color(0.9, 0.15, 0.15), Color(0.15, 0.3, 0.9), Color(0.1, 0.6, 0.3), Color(0.1, 0.1, 0.1), Color(0.95, 0.95, 0.95)]
	for i in range(4):
		var h: int = 3 + (i * 3) % 6
		for k in range(h):
			_cyl(parent, 0.035, 0.035, 0.012, pos + Vector3(float(i) * 0.08, 0.006 + 0.013 * float(k), 0.0), _mat(cols[(i + int(k / 3.0)) % cols.size()], 0.0, 0.5))


func _build_medal() -> void:
	_env(Color(0.04, 0.01, 0.02), Color(0.85, 0.6, 0.45), 0.5, 1.0)
	_room(Color(0.45, 0.06, 0.08), Color(0.18, 0.05, 0.08), Color(0.08, 0.04, 0.05))
	# 床の金の模様
	for i in range(6):
		_box(self, Vector3(9.8, 0.005, 0.05), Vector3(0.0, 0.003, 1.0 - 1.4 * float(i)), _mat(Color(0.85, 0.65, 0.2), 0.3))
	var gold: StandardMaterial3D = _mat(Color(0.95, 0.75, 0.25), 0.25, 0.25, 0.9)
	# 奥: ルーレットのテーブル
	var rt: Node3D = _node(self, Vector3(0.0, 0.0, -4.6))
	_cyl(rt, 1.3, 1.3, 0.1, Vector3(0.0, 0.85, 0.0), _mat(Color(0.05, 0.4, 0.2), 0.0, 0.8))
	_cyl(rt, 1.36, 1.36, 0.08, Vector3(0.0, 0.82, 0.0), _mat(Color(0.35, 0.18, 0.08), 0.0, 0.5))
	_cyl(rt, 0.3, 0.2, 0.8, Vector3(0.0, 0.4, 0.0), _mat(Color(0.3, 0.15, 0.06)))
	var wheel: Node3D = _node(rt, Vector3(0.0, 0.92, 0.0))
	_cyl(wheel, 0.45, 0.45, 0.06, Vector3.ZERO, _mat(Color(0.3, 0.15, 0.06), 0.0, 0.4))
	for k in range(16):
		var a: float = TAU * float(k) / 16.0
		_box(wheel, Vector3(0.09, 0.02, 0.05), Vector3(cos(a) * 0.36, 0.035, sin(a) * 0.36), _mat(Color(0.85, 0.1, 0.1) if k % 2 == 0 else Color(0.08, 0.08, 0.08)), Vector3(0.0, -a, 0.0))
	_cyl(wheel, 0.06, 0.06, 0.12, Vector3(0.0, 0.06, 0.0), gold)
	_spin_nodes.append(wheel)
	_chips(rt, Vector3(-0.8, 0.9, 0.5))
	_chips(rt, Vector3(0.5, 0.9, 0.7))
	# 左右: スロットマシン
	for i in range(4):
		_slot(Vector3(-3.6, 0.0, -0.8 - 1.0 * float(i)), PI * 0.5, i)
		_slot(Vector3(3.6, 0.0, -0.8 - 1.0 * float(i)), -PI * 0.5, i + 3)
	# 手前: カードのテーブル（半円）
	var ct: Node3D = _node(self, Vector3(-1.4, 0.0, -2.2))
	var felt: MeshInstance3D = _cyl(ct, 0.8, 0.8, 0.08, Vector3(0.0, 0.8, 0.0), _mat(Color(0.05, 0.45, 0.25), 0.0, 0.8))
	felt.scale = Vector3(1.0, 1.0, 0.6)
	_cyl(ct, 0.15, 0.2, 0.78, Vector3(0.0, 0.39, 0.0), _mat(Color(0.3, 0.15, 0.06)))
	for k2 in range(5):
		_box(ct, Vector3(0.08, 0.005, 0.12), Vector3(-0.4 + 0.2 * float(k2), 0.845, 0.15), _mat(Color(0.98, 0.98, 0.98)), Vector3(0.0, 0.2 * float(k2 - 2), 0.0))
	_chips(ct, Vector3(0.2, 0.84, -0.15))
	# 右手前: 大きなプッシャー
	var big: Node3D = _node(self, Vector3(1.6, 0.0, -2.4), -20.0)
	_box(big, Vector3(1.8, 1.0, 1.2), Vector3(0.0, 0.5, 0.0), _mat(Color(0.75, 0.12, 0.15), 0.0, 0.4))
	_box(big, Vector3(1.8, 0.8, 1.2), Vector3(0.0, 1.4, 0.0), _glass())
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	for i2 in range(70):
		_cyl(big, 0.045, 0.045, 0.012, Vector3(rng.randf_range(-0.8, 0.8), 1.04 + rng.randf_range(0.0, 0.2), rng.randf_range(-0.5, 0.5)), gold)
	# 看板と電球の枠
	# あくまでメダルゲーム（要件#89: ギャンブルではない。メダルは換金・景品交換できない）
	_label(self, "MEDAL GAME", Vector3(0.0, 2.75, -7.85), 180, Color(1.0, 0.85, 0.3))
	_label(self, "メダルコーナー", Vector3(0.0, 2.25, -7.85), 90, Color(1.0, 1.0, 1.0))
	# 注意書きは天井から手前に下げて、タイトルからも読めるように（要件#90）
	# 右の手前に立て看板（奥の看板と重ならない高さ）
	var stand: Node3D = _node(self, Vector3(0.55, 0.0, -1.2), -10.0)
	_box(stand, Vector3(0.05, 1.0, 0.05), Vector3(0.0, 0.5, 0.0), _mat(Color(0.3, 0.3, 0.32)))
	_box(stand, Vector3(1.35, 0.62, 0.03), Vector3(0.0, 1.15, 0.0), _mat(Color(1.0, 1.0, 1.0)))
	_label(stand, "メダルの払い戻し・\n景品との交換は\nできません", Vector3(0.0, 1.15, 0.025), 40, Color(0.85, 0.1, 0.1), 0.004)
	_label(self, "メダルはお店の中で遊ぶためだけのものです", Vector3(0.0, 1.85, -7.85), 64, Color(1.0, 1.0, 1.0), 0.004)
	for k3 in range(22):
		var x: float = -2.6 + 5.2 * float(k3) / 21.0
		_cyl(self, 0.05, 0.05, 0.03, Vector3(x, 3.1, -7.9), _blink_mat(Color(1.0, 0.85, 0.4), 3.0, 6.0, float(k3) * 0.8), Vector3(PI * 0.5, 0.0, 0.0))
		_cyl(self, 0.05, 0.05, 0.03, Vector3(x, 1.95, -7.9), _blink_mat(Color(1.0, 0.85, 0.4), 3.0, 6.0, float(k3) * 0.8 + 2.0), Vector3(PI * 0.5, 0.0, 0.0))
	# シャンデリア
	var ch: Node3D = _node(self, Vector3(0.0, 2.75, -3.5))
	for k4 in range(10):
		var a2: float = TAU * float(k4) / 10.0
		_cyl(ch, 0.02, 0.02, 0.3, Vector3(cos(a2) * 0.4, 0.0, sin(a2) * 0.4), _mat(Color(1.0, 0.95, 0.8), 2.5))
	_omni(Vector3(0.0, 2.6, -3.5), Color(1.0, 0.8, 0.5), 2.0, 8.0)
	_omni(Vector3(-3.0, 2.5, -2.0), Color(1.0, 0.35, 0.4), 1.0, 5.0)
	_omni(Vector3(3.0, 2.5, -2.0), Color(1.0, 0.75, 0.3), 1.0, 5.0)


# ---------------------------------------------------------------- ビデオゲームコーナー

func _cabinet(pos: Vector3, yaw: float, body_c: Color, screen_c: Color, seed_i: int) -> void:
	var n: Node3D = _node(self, pos)
	n.rotation.y = yaw   # yaw はラジアン
	_box(n, Vector3(0.8, 1.15, 0.9), Vector3(0.0, 0.575, 0.0), _mat(body_c, 0.0, 0.5))
	_box(n, Vector3(0.8, 0.5, 0.6), Vector3(0.0, 1.45, -0.15), _mat(body_c.darkened(0.2), 0.0, 0.5))
	var scr: MeshInstance3D = _box(n, Vector3(0.66, 0.42, 0.02), Vector3(0.0, 1.42, 0.16), _mat(screen_c, 1.6), Vector3(-0.35, 0.0, 0.0))
	var sp: Color = Color.from_hsv(fmod(screen_c.h + 0.45, 1.0), 0.8, 1.0)
	_box(scr, Vector3(0.1, 0.16, 0.01), Vector3(-0.15, -0.06, 0.012), _blink_mat(sp, 2.2, 2.0 + float(seed_i), float(seed_i)))
	_box(scr, Vector3(0.1, 0.16, 0.01), Vector3(0.15, -0.06, 0.012), _blink_mat(Color(1.0, 0.95, 0.4), 2.2, 2.6, float(seed_i) + 1.0))
	_box(scr, Vector3(0.5, 0.04, 0.01), Vector3(0.0, 0.15, 0.012), _mat(Color(1.0, 0.85, 0.2), 2.0))
	var panel: MeshInstance3D = _box(n, Vector3(0.8, 0.06, 0.38), Vector3(0.0, 1.12, 0.42), _mat(Color(0.12, 0.12, 0.15)), Vector3(0.25, 0.0, 0.0))
	_cyl(panel, 0.012, 0.012, 0.12, Vector3(-0.22, 0.07, 0.0), _mat(Color(0.1, 0.1, 0.1)))
	_cyl(panel, 0.035, 0.035, 0.03, Vector3(-0.22, 0.14, 0.0), _mat(Color(0.9, 0.15, 0.15), 0.4))
	for b in range(4):
		_cyl(panel, 0.028, 0.028, 0.03, Vector3(0.05 + 0.075 * float(b), 0.035, -0.04 + 0.05 * float(b % 2)), _mat(Color.from_hsv(float(b) / 4.0, 0.7, 1.0), 0.8))
	_box(n, Vector3(0.84, 0.14, 0.2), Vector3(0.0, 1.78, -0.05), _mat(screen_c.lightened(0.3), 1.2))
	_stool(pos + Vector3(sin(yaw) * 0.85, 0.0, cos(yaw) * 0.85), Color(0.15, 0.15, 0.2))


## 座って遊ぶレースゲーム（ハンドルとシート）
func _racer(pos: Vector3, seed_i: int) -> void:
	var n: Node3D = _node(self, pos)
	_box(n, Vector3(1.0, 1.9, 0.6), Vector3(0.0, 0.95, -0.4), _mat(Color(0.15, 0.15, 0.2)))
	_box(n, Vector3(0.85, 0.55, 0.02), Vector3(0.0, 1.35, -0.09), _mat(Color(0.4, 0.8, 1.0), 1.6))
	_box(n, Vector3(0.5, 0.1, 0.02), Vector3(0.0, 1.2, -0.08), _blink_mat(Color(1.0, 0.3, 0.2), 2.0, 5.0, float(seed_i)))
	var wheel: MeshInstance3D = _cyl(n, 0.16, 0.16, 0.04, Vector3(0.0, 1.0, 0.25), _mat(Color(0.08, 0.08, 0.08)), Vector3(1.2, 0.0, 0.0))
	wheel.scale = Vector3(1.0, 1.0, 1.0)
	_box(n, Vector3(0.6, 0.12, 0.6), Vector3(0.0, 0.45, 0.9), _mat(Color(0.8, 0.1, 0.12), 0.0, 0.5))
	_box(n, Vector3(0.6, 0.7, 0.12), Vector3(0.0, 0.8, 1.2), _mat(Color(0.8, 0.1, 0.12), 0.0, 0.5))
	_label(n, "RACE", Vector3(0.0, 1.78, -0.09), 90, Color(1.0, 0.9, 0.3), 0.003)


func _build_video(rage: bool = false) -> void:
	_env(Color(0.02, 0.02, 0.05), Color(0.45, 0.45, 0.85), 0.45, 1.0)
	_room(Color(0.08, 0.08, 0.14), Color(0.1, 0.08, 0.2), Color(0.05, 0.05, 0.08))
	var screens: Array = [Color(0.2, 0.6, 1.0), Color(1.0, 0.35, 0.5), Color(0.3, 1.0, 0.6), Color(1.0, 0.7, 0.2), Color(0.7, 0.4, 1.0)]
	var i: int = 0
	for z in [-1.2, -2.2, -3.2, -4.2, -5.2]:
		_cabinet(Vector3(-1.2, 0.0, z), PI * 0.5, Color(0.92, 0.92, 0.95), screens[i % screens.size()], i)
		_cabinet(Vector3(1.2, 0.0, z), -PI * 0.5, Color(0.92, 0.92, 0.95), screens[(i + 2) % screens.size()], i + 5)
		_cabinet(Vector3(-3.6, 0.0, z), -PI * 0.5, Color(0.2, 0.2, 0.25), screens[(i + 1) % screens.size()], i + 9)
		_cabinet(Vector3(3.6, 0.0, z), PI * 0.5, Color(0.2, 0.2, 0.25), screens[(i + 3) % screens.size()], i + 13)
		i += 1
	for x in [-1.3, 0.0, 1.3]:
		_racer(Vector3(x, 0.0, -7.2), int(x * 10.0))
	_label(self, "VIDEO GAME", Vector3(0.0, 2.85, -4.0), 120, Color(0.4, 0.9, 1.0))
	for z2 in [-1.5, -3.5, -5.5]:
		_box(self, Vector3(0.12, 0.04, 1.6), Vector3(0.0, 3.13, z2), _mat(Color(0.6, 0.8, 1.0), 2.5))
		_omni(Vector3(0.0, 2.8, z2), Color(0.6, 0.7, 1.0), 0.8, 4.5)
	if rage:
		# 台パンしている人（要件#86, #90: 左だとポスターで見切れたので右の列の席へ）
		var p: Node3D = _person({"body_color": "#5a5f2a", "skin_color": "#e8b890", "hair_color": "#2a2a2a", "hair": "spiky",
			"build": "big", "accessory": "headphones", "height": 1.0}, Vector3(0.45, 0.0, -2.2), PI * 0.5, "slam")
		p.call("set_anger", 1.0)
		_label(self, "バンッ！", Vector3(0.8, 1.75, -1.8), 110, Color(1.0, 0.3, 0.2))
		_rage_label = _label(self, "ドンッ！！", Vector3(1.0, 2.1, -2.6), 90, Color(1.0, 0.85, 0.2))
		_label(self, "台パン禁止", Vector3(4.9, 2.0, -3.2), 80, Color(1.0, 0.2, 0.2), 0.004, -90.0)


# ---------------------------------------------------------------- 音ゲーコーナー（台を増やした。要件#86）

func _taiko(pos: Vector3, yaw_deg: float, c: Color) -> void:
	var t: Node3D = _node(self, pos, yaw_deg)
	_box(t, Vector3(1.6, 0.85, 0.9), Vector3(0.0, 0.425, 0.0), _mat(c, 0.0, 0.5))
	_box(t, Vector3(1.6, 1.3, 0.5), Vector3(0.0, 1.5, -0.2), _mat(Color(0.95, 0.65, 0.15), 0.0, 0.5))
	_box(t, Vector3(1.3, 0.75, 0.02), Vector3(0.0, 1.55, 0.06), _mat(Color(1.0, 0.85, 0.5), 1.4))
	for sx in [-0.4, 0.4]:
		_cyl(t, 0.3, 0.3, 0.32, Vector3(sx, 1.0, 0.45), _mat(c.darkened(0.3), 0.0, 0.5), Vector3(PI * 0.5, 0.0, 0.0))
		_cyl(t, 0.27, 0.27, 0.01, Vector3(sx, 1.0, 0.62), _mat(Color(0.97, 0.94, 0.88), 0.2), Vector3(PI * 0.5, 0.0, 0.0))


func _buttons_machine(pos: Vector3, yaw_deg: float, c: Color, grid: int) -> void:
	var b: Node3D = _node(self, pos, yaw_deg)
	_box(b, Vector3(1.0, 1.0, 0.8), Vector3(0.0, 0.5, 0.0), _mat(c, 0.0, 0.4))
	_box(b, Vector3(1.0, 1.4, 0.4), Vector3(0.0, 1.7, -0.2), _mat(c, 0.0, 0.4))
	var face: MeshInstance3D = _box(b, Vector3(0.8, 0.8, 0.04), Vector3(0.0, 1.35, 0.1), _mat(Color(0.1, 0.1, 0.12)), Vector3(-0.3, 0.0, 0.0))
	var step: float = 0.72 / float(grid)
	for gx in range(grid):
		for gy in range(grid):
			_box(face, Vector3(step * 0.85, step * 0.85, 0.03), Vector3(-0.36 + step * (float(gx) + 0.5), -0.36 + step * (float(gy) + 0.5), 0.03), _blink_mat(Color.from_hsv(float(gx + gy) / float(grid * 2), 0.7, 1.0), 2.2, 4.0 + float(gx), float(gy) * 0.7))
	_box(b, Vector3(0.8, 0.5, 0.02), Vector3(0.0, 2.05, 0.01), _mat(c.lightened(0.3), 1.3))


func _guitar_machine(pos: Vector3, yaw_deg: float) -> void:
	var g: Node3D = _node(self, pos, yaw_deg)
	_box(g, Vector3(1.1, 2.2, 0.6), Vector3(0.0, 1.1, -0.3), _mat(Color(0.1, 0.1, 0.15)))
	_box(g, Vector3(0.9, 0.6, 0.02), Vector3(0.0, 1.6, 0.01), _mat(Color(1.0, 0.4, 0.2), 1.5))
	for sx in [-0.28, 0.28]:
		var body: MeshInstance3D = _cyl(g, 0.16, 0.16, 0.05, Vector3(sx, 1.05, 0.15), _mat(Color(0.85, 0.1, 0.15) if sx < 0 else Color(0.1, 0.3, 0.9), 0.0, 0.4), Vector3(PI * 0.5, 0.0, 0.0))
		body.scale = Vector3(1.0, 1.0, 0.8)
		var neck: MeshInstance3D = _box(g, Vector3(0.05, 0.4, 0.03), Vector3(sx, 1.35, 0.15), _mat(Color(0.3, 0.2, 0.1)))
		neck.rotation.z = 0.0
		for k in range(5):
			_box(g, Vector3(0.04, 0.03, 0.01), Vector3(sx, 1.2 + 0.05 * float(k), 0.17), _blink_mat(Color.from_hsv(float(k) / 5.0, 0.8, 1.0), 1.8, 5.0, float(k)))


func _dj_machine(pos: Vector3, yaw_deg: float) -> void:
	var d: Node3D = _node(self, pos, yaw_deg)
	_box(d, Vector3(1.4, 1.0, 0.7), Vector3(0.0, 0.5, 0.0), _mat(Color(0.08, 0.08, 0.1)))
	_box(d, Vector3(1.4, 1.2, 0.4), Vector3(0.0, 1.6, -0.25), _mat(Color(0.08, 0.08, 0.1)))
	_box(d, Vector3(1.2, 0.7, 0.02), Vector3(0.0, 1.65, -0.04), _mat(Color(0.3, 1.0, 0.6), 1.5))
	for sx in [-0.4, 0.4]:
		var tt: MeshInstance3D = _cyl(d, 0.18, 0.18, 0.03, Vector3(sx, 1.02, 0.05), _mat(Color(0.15, 0.15, 0.18), 0.0, 0.3, 0.6))
		_spin_nodes.append(tt)
		_cyl(d, 0.05, 0.05, 0.035, Vector3(sx, 1.03, 0.05), _blink_mat(Color(1.0, 0.3, 0.8), 2.0, 6.0, sx))
	for k in range(7):
		_box(d, Vector3(0.06, 0.02, 0.12), Vector3(-0.18 + 0.06 * float(k), 1.02, 0.1), _mat(Color(0.95, 0.95, 0.95) if k % 2 == 0 else Color(0.1, 0.1, 0.1)))


func _build_rhythm() -> void:
	_env(Color(0.03, 0.01, 0.05), Color(0.7, 0.45, 0.9), 0.4, 1.1)
	_room(Color(0.06, 0.04, 0.1), Color(0.12, 0.05, 0.18), Color(0.05, 0.03, 0.07))
	_taiko(Vector3(-2.6, 0.0, -2.2), 35.0, Color(0.85, 0.2, 0.15))
	_taiko(Vector3(-3.4, 0.0, -4.4), 50.0, Color(0.2, 0.45, 0.85))
	# ダンスの台（まん中の奥）
	var d: Node3D = _node(self, Vector3(0.0, 0.0, -5.0))
	_box(d, Vector3(1.8, 2.4, 0.7), Vector3(0.0, 1.2, -0.6), _mat(Color(0.12, 0.12, 0.2), 0.0, 0.4))
	_box(d, Vector3(1.4, 0.9, 0.02), Vector3(0.0, 1.7, -0.24), _mat(Color(0.3, 0.6, 1.0), 1.5))
	_box(d, Vector3(2.0, 0.12, 1.8), Vector3(0.0, 0.06, 0.6), _mat(Color(0.75, 0.75, 0.8), 0.0, 0.3, 0.7))
	var arrows: Array = [Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1)]
	for k in range(4):
		var a2: Vector2 = arrows[k]
		_box(d, Vector3(0.48, 0.03, 0.48), Vector3(a2.x * 0.55, 0.135, 0.6 + a2.y * 0.55), _blink_mat(Color(1.0, 0.3, 0.7) if k % 2 == 0 else Color(0.3, 0.8, 1.0), 2.5, 3.5, float(k) * 1.3))
	_box(d, Vector3(1.9, 0.05, 0.05), Vector3(0.0, 1.1, 1.4), _mat(Color(0.7, 0.7, 0.75), 0.0, 0.3, 0.8))
	for sx2 in [-0.95, 0.95]:
		_box(d, Vector3(0.05, 1.05, 0.05), Vector3(sx2, 0.6, 1.4), _mat(Color(0.7, 0.7, 0.75), 0.0, 0.3, 0.8))
	_buttons_machine(Vector3(2.5, 0.0, -2.2), -35.0, Color(0.9, 0.9, 0.95), 4)
	_buttons_machine(Vector3(3.4, 0.0, -4.2), -55.0, Color(0.95, 0.6, 0.8), 3)
	_guitar_machine(Vector3(-1.6, 0.0, -6.2), 15.0)
	_dj_machine(Vector3(1.8, 0.0, -6.3), -15.0)
	_label(self, "音ゲーコーナー", Vector3(0.0, 2.9, -3.0), 110, Color(1.0, 0.5, 0.9))
	_label(self, "♪", Vector3(-4.2, 2.4, -5.5), 200, Color(0.4, 0.9, 1.0), 0.004, 60.0)
	_label(self, "♫", Vector3(4.2, 2.4, -5.5), 200, Color(1.0, 0.8, 0.3), 0.004, -60.0)
	_omni(Vector3(0.0, 2.8, -3.0), Color(0.9, 0.5, 1.0), 1.5, 7.0)
	_omni(Vector3(-2.6, 2.5, -2.5), Color(1.0, 0.6, 0.3), 0.9, 4.0)
	_omni(Vector3(2.6, 2.5, -2.5), Color(0.3, 0.8, 1.0), 0.9, 4.0)
	_omni(Vector3(0.0, 2.5, -6.0), Color(0.5, 1.0, 0.7), 0.8, 5.0)


# ---------------------------------------------------------------- 事務所（人生に疲れた店長。散らかした。要件#86）

func _build_office() -> void:
	_env(Color(0.02, 0.03, 0.06), Color(0.72, 0.75, 0.66), 0.5, 0.2)
	_room(Color(0.45, 0.47, 0.44), Color(0.78, 0.76, 0.68), Color(0.85, 0.85, 0.82), 7.0, 6.0, 2.8)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var paper: StandardMaterial3D = _mat(Color(0.95, 0.95, 0.92))
	# 机・パソコン
	var desk: Node3D = _node(self, Vector3(0.0, 0.0, -1.5))
	var wood: StandardMaterial3D = _mat(Color(0.55, 0.5, 0.45), 0.0, 0.6)
	_box(desk, Vector3(1.9, 0.05, 0.85), Vector3(0.0, 0.74, 0.0), wood)
	_box(desk, Vector3(1.9, 0.7, 0.04), Vector3(0.0, 0.37, 0.4), _mat(Color(0.5, 0.5, 0.52)))
	_box(desk, Vector3(0.62, 0.42, 0.04), Vector3(0.55, 1.05, -0.2), _mat(Color(0.1, 0.1, 0.12)))
	_box(desk, Vector3(0.05, 0.25, 0.05), Vector3(0.55, 0.85, -0.2), _mat(Color(0.1, 0.1, 0.12)))
	for k in range(5):
		_box(desk, Vector3(0.07, 0.07, 0.005), Vector3(0.32 + 0.11 * float(k), 1.29 - 0.03 * float(k % 2), -0.175), _mat(Color(1.0, 0.92, 0.3) if k % 2 == 0 else Color(1.0, 0.6, 0.7)))
	# 書類の山（左に寄せる）
	for i in range(3):
		var h: float = 0.14 + 0.1 * float(i)
		var pile: MeshInstance3D = _box(desk, Vector3(0.22, h, 0.24), Vector3(-0.85 + 0.24 * float(i), 0.77 + h * 0.5, 0.1), paper)
		pile.rotation.y = 0.12 * float(i - 1)
	# カップ麺・エナジードリンクの缶
	for k2 in range(3):
		var cup: MeshInstance3D = _cyl(desk, 0.06, 0.045, 0.1, Vector3(0.05 + 0.15 * float(k2), 0.82, 0.25), _mat(Color(0.97, 0.97, 0.95)))
		_cyl(cup, 0.061, 0.061, 0.02, Vector3(0.0, 0.03, 0.0), _mat(Color(0.85, 0.15, 0.15)))
	for k3 in range(4):
		_cyl(desk, 0.03, 0.03, 0.12, Vector3(0.75 - 0.08 * float(k3), 0.83, 0.28), _mat(Color(0.1, 0.5, 0.9) if k3 % 2 == 0 else Color(0.1, 0.1, 0.1), 0.0, 0.3, 0.7))
	var fallen: MeshInstance3D = _cyl(self, 0.03, 0.03, 0.12, Vector3(0.9, 0.03, -0.6), _mat(Color(0.1, 0.5, 0.9), 0.0, 0.3, 0.7))
	fallen.rotation.z = PI * 0.5
	# 床に散らばった書類
	for k4 in range(14):
		_box(self, Vector3(0.21, 0.004, 0.3), Vector3(rng.randf_range(-2.8, 2.8), 0.003, rng.randf_range(-3.6, 0.6)), paper, Vector3(0.0, rng.randf_range(-1.5, 1.5), 0.0))
	# あふれたゴミ箱
	_cyl(self, 0.18, 0.15, 0.4, Vector3(-1.4, 0.2, -1.2), _mat(Color(0.3, 0.3, 0.32)))
	for k5 in range(5):
		var ball: MeshInstance3D = MeshInstance3D.new()
		var sm: SphereMesh = SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		ball.mesh = sm
		ball.material_override = paper
		ball.position = Vector3(-1.4 + rng.randf_range(-0.3, 0.3), 0.06 + (0.4 if k5 < 2 else 0.0), -1.2 + rng.randf_range(-0.3, 0.3))
		add_child(ball)
	# 椅子と店長（疲れた顔・ネクタイ・うなだれ）
	_box(self, Vector3(0.55, 0.08, 0.55), Vector3(0.0, 0.48, -2.2), _mat(Color(0.15, 0.15, 0.18)))
	_box(self, Vector3(0.55, 0.7, 0.08), Vector3(0.0, 0.9, -2.5), _mat(Color(0.15, 0.15, 0.18)))
	var manager: Node3D = _person({"body_color": "#2e3550", "skin_color": "#d9b89a", "hair_color": "#55524f", "hair": "bald",
		"build": "normal", "accessory": "necktie", "height": 0.86, "tired": true}, Vector3(0.0, 0.0, -2.15), 0.0, "slump")
	manager.set("hold_pose", "slump")
	_label(self, "はぁ……", Vector3(0.45, 1.55, -1.9), 70, Color(0.35, 0.4, 0.55), 0.004)
	# 壁: 売上目標・シフト表（穴だらけ）・時計・カレンダー
	_box(self, Vector3(1.8, 1.0, 0.03), Vector3(-1.4, 1.75, -3.93), _mat(Color(0.97, 0.97, 0.97)))
	_label(self, "今月の売上目標", Vector3(-1.4, 2.1, -3.9), 60, Color(0.15, 0.15, 0.2), 0.004)
	_label(self, "未達", Vector3(-1.4, 1.65, -3.9), 150, Color(0.85, 0.1, 0.1), 0.004)
	_box(self, Vector3(1.2, 0.8, 0.03), Vector3(1.0, 1.6, -3.93), _mat(Color(0.96, 0.96, 0.94)))
	_label(self, "シフト表\n月 店長\n火 店長\n水 店長", Vector3(1.0, 1.6, -3.9), 42, Color(0.15, 0.15, 0.2), 0.004)
	_box(self, Vector3(0.35, 0.35, 0.04), Vector3(2.4, 2.3, -3.93), _mat(Color(0.98, 0.98, 0.95)))
	_label(self, "23:47", Vector3(2.4, 2.3, -3.9), 70, Color(0.1, 0.1, 0.1), 0.0035)
	_box(self, Vector3(0.6, 0.6, 0.02), Vector3(2.4, 1.55, -3.93), _mat(Color(0.95, 0.92, 0.85)))
	_label(self, "休日\n0日", Vector3(2.4, 1.55, -3.9), 56, Color(0.8, 0.1, 0.1), 0.004)
	# 棚と景品の段ボール（積みすぎ）
	for j in range(7):
		_box(self, Vector3(0.6, 0.45, 0.5), Vector3(-2.9 + 0.1 * float(j % 2), 0.23 + 0.46 * float(j % 3), -3.0 + 0.6 * floorf(float(j) / 3.0)), _mat(Color(0.7, 0.55, 0.35)), Vector3(0.0, 0.1 * float(j % 3 - 1), 0.0))
	# しおれた観葉植物と、床の毛布
	_cyl(self, 0.16, 0.12, 0.3, Vector3(2.7, 0.15, -2.8), _mat(Color(0.6, 0.3, 0.2)))
	for k6 in range(5):
		_box(self, Vector3(0.06, 0.4, 0.02), Vector3(2.7 + 0.05 * float(k6 - 2), 0.45, -2.8), _mat(Color(0.45, 0.45, 0.2)), Vector3(0.0, 0.0, 1.2 * float(k6 - 2) / 2.0))
	_box(self, Vector3(1.2, 0.08, 0.7), Vector3(2.0, 0.04, -1.2), _mat(Color(0.45, 0.5, 0.7), 0.0, 0.95), Vector3(0.0, 0.3, 0.05))
	# 蛍光灯（たまにふっと暗くなるだけ。要件#86: チカチカしすぎて目に悪かった）
	_box(self, Vector3(1.4, 0.04, 0.15), Vector3(0.0, 2.75, -1.8), _mat(Color(0.95, 0.98, 1.0), 2.2))
	_flicker = _omni(Vector3(0.0, 2.6, -1.6), Color(0.92, 0.97, 1.0), 1.1, 6.0)
	_omni(Vector3(0.0, 1.8, 0.8), Color(1.0, 0.95, 0.85), 0.5, 4.0)


# ---------------------------------------------------------------- プリクラコーナー（あやしいおじさん）

func _booth(pos: Vector3, body_c: Color, poster_c: Color, text: String) -> void:
	var n: Node3D = _node(self, pos)
	_box(n, Vector3(1.9, 2.3, 1.7), Vector3(0.0, 1.15, 0.0), _mat(body_c, 0.0, 0.5))
	_box(n, Vector3(1.7, 1.3, 0.03), Vector3(0.0, 1.35, 0.86), _mat(poster_c, 0.5))
	_label(n, text, Vector3(0.0, 1.55, 0.9), 110, Color(1.0, 1.0, 1.0), 0.004)
	_label(n, "美肌モード", Vector3(0.0, 1.0, 0.9), 60, Color(1.0, 0.95, 0.6), 0.004)
	var curtain: StandardMaterial3D = _mat(body_c.lightened(0.35), 0.0, 0.9)
	for i in range(5):
		_box(n, Vector3(0.02, 1.5, 0.22), Vector3(0.96, 0.95, -0.55 + 0.23 * float(i)), curtain)
	_box(n, Vector3(1.9, 0.16, 1.7), Vector3(0.0, 2.38, 0.0), _blink_mat(poster_c.lightened(0.3), 1.8, 2.0, pos.x))


func _build_purikura() -> void:
	_env(Color(0.08, 0.05, 0.1), Color(1.0, 0.85, 0.95), 0.7, 0.6)
	_room(Color(0.95, 0.85, 0.9), Color(0.98, 0.9, 0.95), Color(0.95, 0.9, 0.95))
	_booth(Vector3(-2.6, 0.0, -3.4), Color(0.98, 0.6, 0.8), Color(0.95, 0.35, 0.6), "盛れる！")
	_booth(Vector3(0.3, 0.0, -4.6), Color(0.75, 0.65, 0.98), Color(0.5, 0.4, 0.95), "最新機種")
	_booth(Vector3(3.6, 0.0, -3.0), Color(0.6, 0.9, 0.95), Color(0.2, 0.7, 0.85), "デカ目")
	_label(self, "プリクラ", Vector3(0.0, 2.9, -2.6), 130, Color(1.0, 0.4, 0.7))
	# 若い女性のお客さん（大人。私服）。2〜3人ずつでおしゃべり
	var looks: Array = [
		{"body_color": "#f2a0c0", "hair_color": "#5a3a2a", "hair": "long"}, {"body_color": "#a0c8f2", "hair_color": "#2a2a2a", "hair": "bob"},
		{"body_color": "#f5e6a0", "hair_color": "#8a5a3a", "hair": "ponytail"}, {"body_color": "#c0a0f2", "hair_color": "#3a2a2a", "hair": "twintail"},
		{"body_color": "#ffffff", "hair_color": "#c08a50", "hair": "long"}, {"body_color": "#a0e0c0", "hair_color": "#2a2a2a", "hair": "bob"}]
	var spots: Array = [[Vector3(-2.0, 0.0, -1.7), 0.5], [Vector3(-1.3, 0.0, -1.9), -0.6], [Vector3(-0.6, 0.0, -2.9), 0.3],
		[Vector3(0.1, 0.0, -2.7), -0.4], [Vector3(-3.1, 0.0, -1.3), 0.9], [Vector3(1.0, 0.0, -2.0), -0.2]]
	for i in range(looks.size()):
		var lk: Dictionary = (looks[i] as Dictionary).duplicate()
		lk.merge({"skin_color": "#f5d3b5", "build": "slim", "accessory": "bag" if i % 3 == 0 else "none", "height": 0.93 + 0.02 * float(i % 3), "gender": "f"})
		_person(lk, spots[i][0], float(spots[i][1]), "")
	# 天井から下がった注意書き
	_box(self, Vector3(1.5, 0.5, 0.03), Vector3(-0.9, 2.55, -2.2), _mat(Color(1.0, 1.0, 1.0)))
	_label(self, "男性のみのご入場は\nご遠慮ください", Vector3(-0.9, 2.55, -2.17), 46, Color(0.85, 0.1, 0.3), 0.004)
	_box(self, Vector3(1.3, 0.45, 0.03), Vector3(0.9, 2.5, -3.4), _mat(Color(1.0, 0.95, 0.3)))
	_label(self, "盗撮は犯罪です", Vector3(0.9, 2.5, -3.37), 64, Color(0.1, 0.1, 0.1), 0.004)
	# あやしいおじさん: 右の手前（タイトルのポスター・社員証に隠れない所）から、まん中のプリクラ機をスマホでのぞいている（要件#90）
	var uncle: Node3D = _person({"body_color": "#a89a78", "skin_color": "#e9c19b", "hair_color": "#3d3a36", "hair": "bald",
		"build": "big", "accessory": "glasses", "height": 0.98}, Vector3(1.9, 0.0, -2.0), -2.6, "peek")
	var arm: Node3D = uncle.get("_arm_r")
	if arm != null:
		var phone: MeshInstance3D = _box(arm, Vector3(0.08, 0.15, 0.02), Vector3(0.0, -0.62, 0.03), _mat(Color(0.1, 0.1, 0.12)))
		phone.rotation.x = PI * 0.5
		_box(phone, Vector3(0.07, 0.13, 0.005), Vector3(0.0, 0.0, -0.012), _mat(Color(0.6, 0.85, 1.0), 1.2))
	_label(self, "！？", Vector3(1.9, 1.95, -2.0), 110, Color(1.0, 0.25, 0.2), 0.004)
	_omni(Vector3(0.0, 2.8, -2.0), Color(1.0, 0.85, 0.95), 1.6, 8.0)
	_omni(Vector3(-2.5, 2.5, -1.6), Color(1.0, 0.6, 0.85), 0.9, 5.0)
	_omni(Vector3(2.8, 2.5, -1.6), Color(0.6, 0.85, 1.0), 0.9, 5.0)


# ---------------------------------------------------------------- スタッフ更衣室（要件#86）

func _build_locker() -> void:
	_env(Color(0.03, 0.03, 0.04), Color(0.8, 0.82, 0.8), 0.55, 0.15)
	_room(Color(0.5, 0.5, 0.48), Color(0.82, 0.83, 0.8), Color(0.9, 0.9, 0.9), 6.0, 5.0, 2.7)
	var steel: StandardMaterial3D = _mat(Color(0.62, 0.66, 0.7), 0.0, 0.4, 0.6)
	for i in range(8):
		var x: float = -2.6 + 0.62 * float(i)
		_box(self, Vector3(0.6, 1.9, 0.5), Vector3(x, 0.95, -2.7), steel)
		for k in range(3):
			_box(self, Vector3(0.4, 0.02, 0.01), Vector3(x, 1.65 + 0.04 * float(k), -2.445), _mat(Color(0.35, 0.38, 0.42)))
		_box(self, Vector3(0.03, 0.12, 0.02), Vector3(x + 0.22, 1.0, -2.44), _mat(Color(0.25, 0.25, 0.28)))
		_box(self, Vector3(0.22, 0.07, 0.005), Vector3(x, 1.45, -2.443), _mat(Color(0.97, 0.97, 0.95)))
	# 開いたロッカーと、かかった制服
	var door: MeshInstance3D = _box(self, Vector3(0.58, 1.85, 0.03), Vector3(1.95, 0.95, -2.2), steel)
	door.rotation.y = -1.2
	_box(self, Vector3(0.45, 0.7, 0.08), Vector3(1.74, 1.3, -2.6), _mat(Color(0.18, 0.43, 0.82), 0.0, 0.8))
	# ベンチ・カバン・鏡・貼り紙
	_box(self, Vector3(2.6, 0.08, 0.4), Vector3(-0.4, 0.45, -1.4), _mat(Color(0.6, 0.45, 0.3)))
	for sx in [-1.5, 0.7]:
		_box(self, Vector3(0.08, 0.45, 0.35), Vector3(sx, 0.22, -1.4), _mat(Color(0.3, 0.3, 0.32)))
	_box(self, Vector3(0.4, 0.3, 0.2), Vector3(-1.0, 0.64, -1.4), _mat(Color(0.2, 0.25, 0.4)))
	_box(self, Vector3(0.6, 1.4, 0.03), Vector3(-2.97, 1.4, -1.0), _mat(Color(0.75, 0.85, 0.9), 0.3, 0.05, 0.9), Vector3(0.0, PI * 0.5, 0.0))
	_box(self, Vector3(0.8, 0.5, 0.02), Vector3(0.0, 2.25, -2.95), _mat(Color(1.0, 0.95, 0.6)))
	_label(self, "笑顔は無料", Vector3(0.0, 2.3, -2.93), 60, Color(0.8, 0.1, 0.1), 0.004)
	_box(self, Vector3(0.9, 0.6, 0.02), Vector3(2.4, 1.6, -0.6), _mat(Color(0.97, 0.97, 0.97)), Vector3(0.0, -PI * 0.5, 0.0))
	_label(self, "身だしなみ\nチェック", Vector3(2.38, 1.65, -0.6), 50, Color(0.15, 0.15, 0.2), 0.004, -90.0)
	_box(self, Vector3(1.2, 0.04, 0.15), Vector3(0.0, 2.65, -1.6), _mat(Color(0.95, 0.98, 1.0), 2.0))
	_omni(Vector3(0.0, 2.4, -1.4), Color(0.95, 0.97, 1.0), 1.1, 6.0)


# ---------------------------------------------------------------- トイレ（要件#86）

func _build_toilet() -> void:
	_env(Color(0.03, 0.03, 0.04), Color(0.85, 0.88, 0.9), 0.6, 0.15)
	_room(Color(0.75, 0.78, 0.8), Color(0.88, 0.92, 0.94), Color(0.95, 0.95, 0.95), 6.0, 6.0, 2.7)
	# タイルの目地
	for i in range(12):
		_box(self, Vector3(5.9, 0.01, 0.01), Vector3(0.0, 0.2 * float(i + 1), -3.94), _mat(Color(0.75, 0.8, 0.82)))
	# 個室の並び（右）
	for i in range(3):
		var x: float = 0.3 + 0.95 * float(i)
		_box(self, Vector3(0.05, 2.0, 1.4), Vector3(x - 0.45, 1.05, -3.2), _mat(Color(0.55, 0.75, 0.85)))
		_box(self, Vector3(0.85, 1.9, 0.05), Vector3(x + 0.02, 1.0, -2.5), _mat(Color(0.6, 0.8, 0.9)))
		var used: bool = i == 1
		_box(self, Vector3(0.1, 0.05, 0.01), Vector3(x + 0.3, 1.1, -2.47), _mat(Color(0.9, 0.15, 0.15) if used else Color(0.15, 0.7, 0.3), 1.2))
		if used:
			_label(self, "使用中", Vector3(x + 0.02, 1.6, -2.46), 56, Color(0.85, 0.1, 0.1), 0.004)
	_box(self, Vector3(0.05, 2.0, 1.4), Vector3(3.15, 1.05, -3.2), _mat(Color(0.55, 0.75, 0.85)))
	# 洗面台と鏡（左）
	for k in range(2):
		var z: float = -1.0 - 1.1 * float(k)
		_box(self, Vector3(0.5, 0.15, 0.7), Vector3(-2.7, 0.85, z), _mat(Color(0.97, 0.97, 0.97), 0.0, 0.2))
		_cyl(self, 0.02, 0.02, 0.2, Vector3(-2.85, 1.0, z), _mat(Color(0.8, 0.8, 0.85), 0.0, 0.2, 0.9))
		_box(self, Vector3(0.03, 0.8, 0.6), Vector3(-2.97, 1.6, z), _mat(Color(0.75, 0.85, 0.9), 0.25, 0.05, 0.9))
	_box(self, Vector3(0.15, 0.35, 0.3), Vector3(-2.9, 1.3, -3.1), _mat(Color(0.95, 0.95, 0.95)))
	_label(self, "HAND DRY", Vector3(-2.82, 1.3, -3.1), 30, Color(0.2, 0.4, 0.8), 0.004, 90.0)
	# 清掃中の黄色い看板とチェック表
	var sign_n: Node3D = _node(self, Vector3(-0.8, 0.0, -1.2), 20.0)
	for sd in [-1.0, 1.0]:
		var pl: MeshInstance3D = _box(sign_n, Vector3(0.4, 0.7, 0.02), Vector3(0.0, 0.33, sd * 0.1), _mat(Color(1.0, 0.85, 0.1)))
		pl.rotation.x = sd * 0.15
	_label(sign_n, "清掃中", Vector3(0.0, 0.42, 0.13), 60, Color(0.1, 0.1, 0.1), 0.004)
	_box(self, Vector3(0.5, 0.7, 0.02), Vector3(-1.4, 1.6, -3.93), _mat(Color(0.97, 0.97, 0.97)))
	_label(self, "清掃チェック表\n10:00 済\n14:00 済\n18:00 済\n22:00", Vector3(-1.4, 1.6, -3.9), 32, Color(0.15, 0.15, 0.2), 0.004)
	_label(self, "いつもきれいにご利用いただき\nありがとうございます", Vector3(0.0, 2.35, -3.9), 50, Color(0.2, 0.4, 0.7), 0.004)
	_box(self, Vector3(1.2, 0.04, 0.15), Vector3(0.0, 2.65, -1.8), _mat(Color(0.95, 0.98, 1.0), 2.0))
	_omni(Vector3(0.0, 2.4, -1.6), Color(0.95, 0.98, 1.0), 1.2, 6.0)


# ---------------------------------------------------------------- 景品倉庫（要件#86）

func _build_warehouse() -> void:
	_env(Color(0.02, 0.02, 0.03), Color(0.7, 0.65, 0.55), 0.4, 0.3)
	_room(Color(0.42, 0.42, 0.4), Color(0.55, 0.55, 0.52), Color(0.35, 0.35, 0.35), 8.0, 8.0, 3.2)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 21
	var steel: StandardMaterial3D = _mat(Color(0.3, 0.4, 0.55), 0.0, 0.4, 0.5)
	for sx in [-2.2, 2.2]:
		for z in [-1.6, -3.6, -5.6]:
			var n: Node3D = _node(self, Vector3(sx, 0.0, z))
			for lv in range(4):
				_box(n, Vector3(0.9, 0.04, 1.8), Vector3(0.0, 0.1 + 0.75 * float(lv), 0.0), _mat(Color(0.8, 0.55, 0.2)))
				for b in range(3):
					if rng.randf() < 0.8:
						var bx: Vector3 = Vector3(rng.randf_range(0.5, 0.8), rng.randf_range(0.35, 0.6), 0.5)
						_box(n, bx, Vector3(0.0, 0.12 + 0.75 * float(lv) + bx.y * 0.5, -0.6 + 0.6 * float(b)), _mat(Color(0.72, 0.56, 0.36)), Vector3(0.0, rng.randf_range(-0.1, 0.1), 0.0))
			for c in [Vector3(-0.42, 0, -0.88), Vector3(0.42, 0, -0.88), Vector3(-0.42, 0, 0.88), Vector3(0.42, 0, 0.88)]:
				_box(n, Vector3(0.05, 3.0, 0.05), Vector3(c.x, 1.5, c.z), steel)
	# ぬいぐるみの山（まん中）
	var cols: Array = [Color(1.0, 0.85, 0.3), Color(1.0, 0.6, 0.75), Color(0.6, 0.85, 1.0), Color(0.8, 0.7, 0.55), Color(0.7, 0.95, 0.7)]
	for i in range(40):
		var r: float = rng.randf_range(0.12, 0.2)
		var ang: float = rng.randf() * TAU
		var dist: float = rng.randf_range(0.0, 0.9)
		var y: float = r + maxf(0.0, 0.9 - dist) * 0.8 + rng.randf_range(0.0, 0.2)
		var m: MeshInstance3D = MeshInstance3D.new()
		var sm: SphereMesh = SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		m.mesh = sm
		m.material_override = _mat(cols[i % cols.size()], 0.0, 0.95)
		m.position = Vector3(cos(ang) * dist, y, -3.4 + sin(ang) * dist)
		add_child(m)
	# 台車と、ひとつだけの電球
	var cart: Node3D = _node(self, Vector3(0.9, 0.0, -1.2), -25.0)
	_box(cart, Vector3(0.6, 0.04, 0.9), Vector3(0.0, 0.12, 0.0), _mat(Color(0.2, 0.5, 0.25)))
	_box(cart, Vector3(0.6, 0.9, 0.04), Vector3(0.0, 0.55, -0.45), _mat(Color(0.2, 0.5, 0.25)))
	_box(cart, Vector3(0.5, 0.4, 0.5), Vector3(0.0, 0.34, 0.05), _mat(Color(0.72, 0.56, 0.36)))
	_label(self, "景品在庫", Vector3(0.0, 2.6, -7.85), 120, Color(1.0, 0.9, 0.5))
	_label(self, "※ 在庫は数えないこと（店長）", Vector3(0.0, 2.15, -7.85), 50, Color(1.0, 1.0, 1.0))
	_cyl(self, 0.01, 0.01, 0.6, Vector3(0.0, 2.9, -3.4), _mat(Color(0.1, 0.1, 0.1)))
	_cyl(self, 0.08, 0.08, 0.12, Vector3(0.0, 2.55, -3.4), _mat(Color(1.0, 0.85, 0.5), 3.0))
	_omni(Vector3(0.0, 2.4, -3.4), Color(1.0, 0.85, 0.6), 2.0, 7.0)


# ---------------------------------------------------------------- 店長の家（要件#86）

func _build_manager_home() -> void:
	_env(Color(0.02, 0.02, 0.04), Color(0.55, 0.55, 0.7), 0.35, 0.6)
	_room(Color(0.6, 0.5, 0.38), Color(0.85, 0.82, 0.75), Color(0.9, 0.9, 0.88), 6.0, 5.0, 2.5)
	# 低いテーブルとコンビニの弁当、テレビ、布団、洗濯物
	var tb: Node3D = _node(self, Vector3(0.0, 0.0, -1.6))
	_box(tb, Vector3(1.1, 0.04, 0.7), Vector3(0.0, 0.36, 0.0), _mat(Color(0.55, 0.38, 0.22)))
	for sx in [-0.5, 0.5]:
		for sz in [-0.3, 0.3]:
			_box(tb, Vector3(0.05, 0.34, 0.05), Vector3(sx, 0.17, sz), _mat(Color(0.45, 0.3, 0.18)))
	_box(tb, Vector3(0.24, 0.05, 0.18), Vector3(-0.2, 0.41, 0.05), _mat(Color(0.15, 0.15, 0.15)))
	_box(tb, Vector3(0.22, 0.02, 0.16), Vector3(-0.2, 0.44, 0.05), _mat(Color(0.9, 0.75, 0.4)))
	for k in range(3):
		var can: MeshInstance3D = _cyl(tb, 0.03, 0.03, 0.12, Vector3(0.25 + 0.08 * float(k), 0.44, -0.1), _mat(Color(0.75, 0.75, 0.8), 0.0, 0.3, 0.8))
		if k == 2:
			can.rotation.z = PI * 0.5
			can.position.y = 0.41
	# スマホに「着信: 店」
	var ph: MeshInstance3D = _box(tb, Vector3(0.08, 0.01, 0.15), Vector3(0.1, 0.39, 0.2), _mat(Color(0.1, 0.1, 0.12)))
	_box(ph, Vector3(0.07, 0.005, 0.13), Vector3(0.0, 0.006, 0.0), _blink_mat(Color(0.6, 0.9, 1.0), 2.0, 8.0, 0.0))
	_label(self, "着信: 店", Vector3(0.55, 0.62, -1.15), 60, Color(1.0, 0.3, 0.3), 0.004)
	# 散らかった部屋: コンビニの袋・ゴミ袋・積んだ弁当のから・脱いだ服
	for k3 in range(4):
		_box(self, Vector3(0.3, 0.32, 0.22), Vector3(-2.5 + 0.35 * float(k3 % 2), 0.16, -1.2 + 0.4 * floorf(float(k3) / 2.0)), _mat(Color(0.95, 0.95, 0.95), 0.0, 0.9), Vector3(0.0, 0.3 * float(k3), 0.0))
	for k4 in range(2):
		var bag: MeshInstance3D = MeshInstance3D.new()
		var sm: SphereMesh = SphereMesh.new()
		sm.radius = 0.28
		sm.height = 0.5
		bag.mesh = sm
		bag.material_override = _mat(Color(0.25, 0.3, 0.45), 0.0, 0.4)
		bag.position = Vector3(2.4 - 0.5 * float(k4), 0.25, -3.1)
		add_child(bag)
	for k5 in range(5):
		_box(self, Vector3(0.2, 0.04 * float(k5 + 1), 0.15), Vector3(0.7, 0.02 * float(k5 + 1), -0.8), _mat(Color(0.15, 0.15, 0.15)))
	_box(self, Vector3(0.6, 0.03, 0.45), Vector3(-0.9, 0.015, -0.6), _mat(Color(0.18, 0.43, 0.82), 0.0, 0.95), Vector3(0.0, 0.5, 0.0))
	# 店長（テーブルの向こうに座っている。コンビニ弁当を前にぐったり）
	var mg: Node3D = _person({"body_color": "#8a8f99", "skin_color": "#d9b89a", "hair_color": "#55524f", "hair": "bald",
		"build": "normal", "accessory": "glasses", "height": 0.9, "tired": true}, Vector3(0.0, -0.5, -2.2), 0.0, "slump")
	mg.set("hold_pose", "slump")
	_box(self, Vector3(0.9, 0.55, 0.35), Vector3(-1.8, 0.28, -3.0), _mat(Color(0.2, 0.2, 0.22)))
	_box(self, Vector3(0.8, 0.5, 0.05), Vector3(-1.8, 0.85, -3.05), _mat(Color(0.08, 0.08, 0.1)))
	_box(self, Vector3(0.72, 0.42, 0.01), Vector3(-1.8, 0.85, -3.02), _blink_mat(Color(0.4, 0.6, 0.9), 1.4, 1.5, 0.0))
	_box(self, Vector3(1.0, 0.12, 2.0), Vector3(1.8, 0.06, -2.0), _mat(Color(0.85, 0.85, 0.95), 0.0, 0.95))
	_box(self, Vector3(0.5, 0.12, 0.35), Vector3(1.8, 0.16, -2.8), _mat(Color(0.95, 0.95, 0.98), 0.0, 0.95))
	_cyl(self, 0.01, 0.01, 2.4, Vector3(0.0, 2.1, -3.5), _mat(Color(0.6, 0.6, 0.6)), Vector3(0.0, 0.0, PI * 0.5))
	for k2 in range(4):
		_box(self, Vector3(0.35, 0.5, 0.02), Vector3(-0.9 + 0.6 * float(k2), 1.82, -3.5), _mat([Color(0.18, 0.43, 0.82), Color(0.95, 0.95, 0.95), Color(0.3, 0.3, 0.35), Color(0.18, 0.43, 0.82)][k2]))
	_label(self, "店の制服", Vector3(-0.9, 1.45, -3.48), 36, Color(0.15, 0.15, 0.2), 0.004)
	_cyl(self, 0.18, 0.18, 0.02, Vector3(0.0, 2.48, -1.6), _mat(Color(1.0, 0.95, 0.8), 1.5))
	_omni(Vector3(0.0, 2.3, -1.6), Color(1.0, 0.9, 0.75), 0.8, 5.0)
	_omni(Vector3(-1.8, 1.0, -2.6), Color(0.5, 0.7, 1.0), 0.6, 3.0)


# ---------------------------------------------------------------- 店長の実家（要件#86）

func _build_parents_home() -> void:
	_env(Color(0.04, 0.03, 0.02), Color(0.95, 0.85, 0.7), 0.55, 0.3)
	_room(Color(0.72, 0.7, 0.45), Color(0.9, 0.86, 0.76), Color(0.75, 0.6, 0.42), 6.0, 5.0, 2.6)
	# 畳のへり
	for i in range(4):
		_box(self, Vector3(5.9, 0.005, 0.04), Vector3(0.0, 0.003, 0.5 - 1.0 * float(i)), _mat(Color(0.2, 0.25, 0.2)))
	# 障子
	for k in range(4):
		var x: float = -2.25 + 1.5 * float(k)
		_box(self, Vector3(1.45, 1.9, 0.03), Vector3(x, 1.05, -2.95), _mat(Color(0.97, 0.95, 0.88), 0.2))
		for gx in range(3):
			_box(self, Vector3(0.02, 1.9, 0.035), Vector3(x - 0.48 + 0.48 * float(gx), 1.05, -2.94), _mat(Color(0.55, 0.4, 0.25)))
		for gy in range(5):
			_box(self, Vector3(1.45, 0.02, 0.035), Vector3(x, 0.2 + 0.4 * float(gy), -2.94), _mat(Color(0.55, 0.4, 0.25)))
	# こたつとみかん
	var kt: Node3D = _node(self, Vector3(0.0, 0.0, -1.6))
	_box(kt, Vector3(1.3, 0.3, 1.3), Vector3(0.0, 0.15, 0.0), _mat(Color(0.8, 0.35, 0.3), 0.0, 0.95))
	_box(kt, Vector3(1.0, 0.04, 1.0), Vector3(0.0, 0.34, 0.0), _mat(Color(0.6, 0.4, 0.22)))
	for k2 in range(5):
		var a: float = TAU * float(k2) / 5.0
		_cyl(kt, 0.045, 0.045, 0.07, Vector3(cos(a) * 0.08, 0.39 + (0.05 if k2 == 0 else 0.0), sin(a) * 0.08), _mat(Color(1.0, 0.55, 0.1)))
	_cyl(kt, 0.13, 0.13, 0.03, Vector3(0.0, 0.37, 0.0), _mat(Color(0.3, 0.45, 0.6)))
	# 店長（ほっとした顔で、こたつに入っている）と母
	_person({"body_color": "#7a5a8a", "skin_color": "#e6c0a0", "hair_color": "#55524f", "hair": "bald",
		"build": "normal", "accessory": "glasses", "height": 0.92}, Vector3(-0.35, -0.48, -2.35), 0.0, "sit")
	_person({"body_color": "#8a6a4a", "skin_color": "#ecc9a8", "hair_color": "#b8b4ae", "hair": "perm",
		"build": "normal", "accessory": "none", "height": 0.86, "gender": "f"}, Vector3(0.6, -0.48, -2.1), -0.35, "sit")
	_label(self, "ちゃんと食べてる？", Vector3(-0.35, 1.6, -2.0), 50, Color(0.4, 0.25, 0.1), 0.004)
	# 掛け軸・ちゃぶ台の上の写真・古いテレビ
	_box(self, Vector3(0.5, 1.1, 0.02), Vector3(2.3, 1.45, -2.9), _mat(Color(0.95, 0.93, 0.85)))
	_label(self, "忍耐", Vector3(2.3, 1.55, -2.87), 110, Color(0.1, 0.1, 0.1), 0.004)
	_box(self, Vector3(0.3, 0.22, 0.02), Vector3(-2.2, 2.2, -2.9), _mat(Color(0.4, 0.25, 0.12)))
	_box(self, Vector3(0.26, 0.18, 0.01), Vector3(-2.2, 2.2, -2.88), _mat(Color(0.75, 0.8, 0.9), 0.2))
	_label(self, "入社式", Vector3(-2.2, 2.03, -2.87), 32, Color(0.2, 0.15, 0.1), 0.004)
	_box(self, Vector3(0.7, 0.55, 0.5), Vector3(-2.3, 0.28, -2.4), _mat(Color(0.35, 0.25, 0.18)))
	_box(self, Vector3(0.55, 0.42, 0.02), Vector3(-2.3, 0.3, -2.14), _mat(Color(0.3, 0.45, 0.35), 0.8))
	_omni(Vector3(0.0, 2.3, -1.6), Color(1.0, 0.85, 0.6), 1.3, 6.0)
