extends Node3D
## タイトルの背景だけに使う場面（要件#84。ショップの背景ガチャで手に入る）。
## メダルコーナー・ビデオゲームコーナー・音ゲーコーナー・事務所（人生に疲れた店長）・プリクラコーナー（あやしいおじさん）。
## カメラはタイトルのいつもの位置（main.gd の CAMERA_POS あたり。奥の -z を見る）から見る前提で並べる。

const CustomerScript = preload("res://scripts/customer_character.gd")

var label_font: Font = null
var _blink: Array = []      # {mat, base, speed, phase}
var _time: float = 0.0
var _flicker: OmniLight3D = null


func build(kind: String) -> void:
	match kind:
		"bg_medal":
			_build_medal()
		"bg_video":
			_build_video()
		"bg_rhythm":
			_build_rhythm()
		"bg_office":
			_build_office()
		"bg_purikura":
			_build_purikura()
		_:
			_build_video()


func set_tension(_t: float) -> void:
	pass


func _process(delta: float) -> void:
	_time += delta
	for b in _blink:
		var d: Dictionary = b
		var m: StandardMaterial3D = d["mat"]
		m.emission_energy_multiplier = float(d["base"]) * (0.35 + 0.65 * (0.5 + 0.5 * sin(_time * float(d["speed"]) + float(d["phase"]))))
	# 事務所の蛍光灯は、ときどきチカチカする
	if _flicker != null:
		var f: float = fmod(_time, 5.3)
		_flicker.light_energy = 0.15 if (f > 4.6 and fmod(_time * 23.0, 1.0) > 0.5) else 1.1


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


# ---------------------------------------------------------------- メダルコーナー

func _build_medal() -> void:
	_env(Color(0.04, 0.02, 0.03), Color(0.75, 0.55, 0.45), 0.55, 0.8)
	_room(Color(0.42, 0.08, 0.1), Color(0.2, 0.08, 0.12), Color(0.1, 0.06, 0.08))
	var gold: StandardMaterial3D = _mat(Color(0.95, 0.75, 0.25), 0.25, 0.25, 0.9)
	# 真ん中の大きなプッシャー機
	var big: Node3D = _node(self, Vector3(0.0, 0.0, -4.2))
	_box(big, Vector3(3.4, 1.0, 1.8), Vector3(0.0, 0.5, 0.0), _mat(Color(0.75, 0.12, 0.15), 0.0, 0.4))
	_box(big, Vector3(3.4, 0.9, 1.8), Vector3(0.0, 1.45, 0.0), _glass())
	for step in range(3):
		_box(big, Vector3(3.0, 0.08, 0.5), Vector3(0.0, 1.05 + 0.18 * float(step), -0.45 + 0.35 * float(step) * -1.0 + 0.35), _mat(Color(0.85, 0.85, 0.9), 0.0, 0.3, 0.6))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	for i in range(140):
		var c: MeshInstance3D = _cyl(big, 0.045, 0.045, 0.012, Vector3(rng.randf_range(-1.45, 1.45), 1.1 + rng.randf_range(0.0, 0.35), rng.randf_range(-0.7, 0.6)), gold)
		c.rotation = Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4))
	# てっぺんのルーレット
	var wheel: Node3D = _node(big, Vector3(0.0, 2.55, -0.3))
	_cyl(wheel, 0.75, 0.75, 0.12, Vector3.ZERO, _mat(Color(0.98, 0.85, 0.3), 0.6, 0.4, 0.6), Vector3(PI * 0.5, 0.0, 0.0))
	for k in range(12):
		var a: float = TAU * float(k) / 12.0
		var col: Color = Color.from_hsv(float(k) / 12.0, 0.8, 1.0)
		_cyl(wheel, 0.07, 0.07, 0.05, Vector3(cos(a) * 0.62, sin(a) * 0.62, 0.08), _blink_mat(col, 2.5, 5.0, float(k) * 0.5), Vector3(PI * 0.5, 0.0, 0.0))
	_label(wheel, "JACKPOT", Vector3(0.0, 0.0, 0.1), 120, Color(1.0, 0.2, 0.25), 0.004)
	for x in [-1.1, 0.0, 1.1]:
		_stool(Vector3(x, 0.0, -2.9), Color(0.85, 0.15, 0.2))
	# 両側の小さいメダル機
	for sx in [-1.0, 1.0]:
		for j in range(2):
			var m: Node3D = _node(self, Vector3(sx * 3.4, 0.0, -1.6 - 2.2 * float(j)), -90.0 * sx)
			_box(m, Vector3(1.6, 1.0, 1.0), Vector3(0.0, 0.5, 0.0), _mat(Color(0.2, 0.25, 0.55), 0.0, 0.4))
			_box(m, Vector3(1.6, 0.7, 1.0), Vector3(0.0, 1.35, 0.0), _glass())
			for i2 in range(30):
				_cyl(m, 0.04, 0.04, 0.012, Vector3(rng.randf_range(-0.7, 0.7), 1.03, rng.randf_range(-0.4, 0.4)), gold)
			_box(m, Vector3(1.6, 0.12, 0.1), Vector3(0.0, 1.75, 0.5), _blink_mat(Color(0.3, 0.9, 1.0), 2.0, 3.0, float(j) + sx))
			_stool(m.position + Vector3(-sx * 0.95, 0.0, 0.0), Color(0.2, 0.3, 0.75))
	# メダルのカップ
	_cyl(self, 0.09, 0.07, 0.14, Vector3(-1.1, 0.73, -2.9), _mat(Color(1.0, 0.55, 0.15, 0.85), 0.2))
	_label(self, "メダルコーナー", Vector3(2.9, 2.55, -7.85), 120, Color(1.0, 0.85, 0.3))
	_label(self, "メダル貸機 →", Vector3(-3.6, 2.4, -6.0), 70, Color(1.0, 1.0, 1.0), 0.004, 30.0)
	_omni(Vector3(0.0, 2.8, -2.5), Color(1.0, 0.8, 0.55), 1.6, 7.0)
	_omni(Vector3(-3.0, 2.6, -2.0), Color(1.0, 0.4, 0.5), 1.0, 5.0)
	_omni(Vector3(3.0, 2.6, -2.0), Color(0.4, 0.7, 1.0), 1.0, 5.0)


# ---------------------------------------------------------------- ビデオゲームコーナー

func _cabinet(pos: Vector3, yaw: float, body_c: Color, screen_c: Color, seed_i: int) -> void:
	var n: Node3D = _node(self, pos)
	n.rotation.y = yaw   # yaw はラジアン
	_box(n, Vector3(0.8, 1.15, 0.9), Vector3(0.0, 0.575, 0.0), _mat(body_c, 0.0, 0.5))
	_box(n, Vector3(0.8, 0.5, 0.6), Vector3(0.0, 1.45, -0.15), _mat(body_c.darkened(0.2), 0.0, 0.5))
	var scr: MeshInstance3D = _box(n, Vector3(0.66, 0.42, 0.02), Vector3(0.0, 1.42, 0.16), _mat(screen_c, 1.6), Vector3(-0.35, 0.0, 0.0))
	# 画面の中の「キャラクター」
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


func _build_video() -> void:
	_env(Color(0.02, 0.02, 0.05), Color(0.45, 0.45, 0.85), 0.45, 1.0)
	_room(Color(0.08, 0.08, 0.14), Color(0.1, 0.08, 0.2), Color(0.05, 0.05, 0.08))
	var screens: Array = [Color(0.2, 0.6, 1.0), Color(1.0, 0.35, 0.5), Color(0.3, 1.0, 0.6), Color(1.0, 0.7, 0.2), Color(0.7, 0.4, 1.0)]
	var i: int = 0
	for z in [-1.4, -2.5, -3.6, -4.7, -5.8]:
		_cabinet(Vector3(-1.5, 0.0, z), PI * 0.5, Color(0.92, 0.92, 0.95), screens[i % screens.size()], i)
		_cabinet(Vector3(1.5, 0.0, z), -PI * 0.5, Color(0.92, 0.92, 0.95), screens[(i + 2) % screens.size()], i + 5)
		i += 1
	# 奥の壁: 格闘ゲームの大きなポスター
	_box(self, Vector3(3.2, 1.6, 0.04), Vector3(0.0, 1.7, -7.9), _mat(Color(0.85, 0.2, 0.25), 0.6))
	_label(self, "VS", Vector3(0.0, 1.75, -7.85), 260, Color(1.0, 0.95, 0.4), 0.004)
	_label(self, "VIDEO GAME", Vector3(0.0, 2.85, -4.0), 120, Color(0.4, 0.9, 1.0))
	for z2 in [-1.5, -3.5, -5.5]:
		_box(self, Vector3(0.12, 0.04, 1.6), Vector3(0.0, 3.13, z2), _mat(Color(0.6, 0.8, 1.0), 2.5))
		_omni(Vector3(0.0, 2.8, z2), Color(0.6, 0.7, 1.0), 0.8, 4.5)


# ---------------------------------------------------------------- 音ゲーコーナー

func _build_rhythm() -> void:
	_env(Color(0.03, 0.01, 0.05), Color(0.7, 0.45, 0.9), 0.4, 1.1)
	_room(Color(0.06, 0.04, 0.1), Color(0.12, 0.05, 0.18), Color(0.05, 0.03, 0.07))
	# 太鼓の台（左）
	var t: Node3D = _node(self, Vector3(-2.2, 0.0, -3.0), 25.0)
	_box(t, Vector3(1.6, 0.85, 0.9), Vector3(0.0, 0.425, 0.0), _mat(Color(0.85, 0.2, 0.15), 0.0, 0.5))
	_box(t, Vector3(1.6, 1.3, 0.5), Vector3(0.0, 1.5, -0.2), _mat(Color(0.95, 0.65, 0.15), 0.0, 0.5))
	_box(t, Vector3(1.3, 0.75, 0.02), Vector3(0.0, 1.55, 0.06), _mat(Color(1.0, 0.85, 0.5), 1.4))
	for sx in [-0.4, 0.4]:
		_cyl(t, 0.3, 0.3, 0.32, Vector3(sx, 1.0, 0.45), _mat(Color(0.6, 0.15, 0.1), 0.0, 0.5), Vector3(PI * 0.5, 0.0, 0.0))
		_cyl(t, 0.27, 0.27, 0.01, Vector3(sx, 1.0, 0.62), _mat(Color(0.97, 0.94, 0.88), 0.2), Vector3(PI * 0.5, 0.0, 0.0))
		_cyl(t, 0.015, 0.015, 0.35, Vector3(sx + 0.15, 1.25, 0.6), _mat(Color(0.95, 0.85, 0.6)), Vector3(0.6, 0.0, 0.4))
	# ダンスの台（まん中）
	var d: Node3D = _node(self, Vector3(0.0, 0.0, -4.6))
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
		_box(d, Vector3(0.45, 0.7, 0.4), Vector3(sx2 * 1.25, 2.1, -0.6), _mat(Color(0.08, 0.08, 0.1)))
		_cyl(d, 0.15, 0.15, 0.02, Vector3(sx2 * 1.25, 2.1, -0.39), _blink_mat(Color(0.9, 0.3, 1.0), 1.6, 8.0, sx2), Vector3(PI * 0.5, 0.0, 0.0))
	# ボタンの台（右）
	var b: Node3D = _node(self, Vector3(2.3, 0.0, -3.0), -25.0)
	_box(b, Vector3(1.0, 1.0, 0.8), Vector3(0.0, 0.5, 0.0), _mat(Color(0.9, 0.9, 0.95), 0.0, 0.4))
	_box(b, Vector3(1.0, 1.4, 0.4), Vector3(0.0, 1.7, -0.2), _mat(Color(0.9, 0.9, 0.95), 0.0, 0.4))
	var face: MeshInstance3D = _box(b, Vector3(0.8, 0.8, 0.04), Vector3(0.0, 1.35, 0.1), _mat(Color(0.1, 0.1, 0.12)), Vector3(-0.3, 0.0, 0.0))
	for gx in range(4):
		for gy in range(4):
			_box(face, Vector3(0.16, 0.16, 0.03), Vector3(-0.27 + 0.18 * float(gx), -0.27 + 0.18 * float(gy), 0.03), _blink_mat(Color.from_hsv(float(gx + gy) / 8.0, 0.7, 1.0), 2.2, 4.0 + float(gx), float(gy) * 0.7))
	_box(b, Vector3(0.8, 0.5, 0.02), Vector3(0.0, 2.05, 0.01), _mat(Color(1.0, 0.5, 0.8), 1.3))
	_label(self, "音ゲーコーナー", Vector3(0.0, 2.9, -3.0), 110, Color(1.0, 0.5, 0.9))
	_label(self, "♪", Vector3(-3.4, 2.3, -4.5), 200, Color(0.4, 0.9, 1.0))
	_omni(Vector3(0.0, 2.8, -3.0), Color(0.9, 0.5, 1.0), 1.5, 7.0)
	_omni(Vector3(-2.0, 2.5, -2.0), Color(1.0, 0.6, 0.3), 0.9, 4.0)
	_omni(Vector3(2.0, 2.5, -2.0), Color(0.3, 0.8, 1.0), 0.9, 4.0)


# ---------------------------------------------------------------- 事務所（人生に疲れた店長）

func _build_office() -> void:
	_env(Color(0.02, 0.03, 0.06), Color(0.75, 0.78, 0.7), 0.5, 0.2)
	_room(Color(0.45, 0.47, 0.44), Color(0.8, 0.78, 0.7), Color(0.85, 0.85, 0.82), 7.0, 6.0, 2.8)
	# 机・椅子・パソコン
	var desk: Node3D = _node(self, Vector3(0.0, 0.0, -1.5))
	var wood: StandardMaterial3D = _mat(Color(0.55, 0.5, 0.45), 0.0, 0.6)
	_box(desk, Vector3(1.9, 0.05, 0.85), Vector3(0.0, 0.74, 0.0), wood)
	_box(desk, Vector3(1.9, 0.7, 0.04), Vector3(0.0, 0.37, 0.4), _mat(Color(0.5, 0.5, 0.52)))
	_box(desk, Vector3(0.62, 0.42, 0.04), Vector3(0.35, 1.05, -0.2), _mat(Color(0.1, 0.1, 0.12)), Vector3(0.0, PI, 0.0))
	_box(desk, Vector3(0.56, 0.36, 0.01), Vector3(0.35, 1.05, -0.225), _mat(Color(0.3, 0.55, 0.9), 1.0))
	_box(desk, Vector3(0.05, 0.25, 0.05), Vector3(0.35, 0.85, -0.2), _mat(Color(0.1, 0.1, 0.12)))
	# 書類の山
	var paper: StandardMaterial3D = _mat(Color(0.95, 0.95, 0.92))
	for i in range(3):
		var h: float = 0.12 + 0.1 * float(i)
		var pile: MeshInstance3D = _box(desk, Vector3(0.2, h, 0.22), Vector3(-0.85 + 0.22 * float(i), 0.77 + h * 0.5, 0.15), paper)
		pile.rotation.y = 0.1 * float(i - 1)
	# 冷めたコーヒー
	_cyl(desk, 0.045, 0.04, 0.1, Vector3(-0.15, 0.82, 0.25), _mat(Color(0.95, 0.95, 0.95)))
	_cyl(desk, 0.04, 0.04, 0.01, Vector3(-0.15, 0.865, 0.25), _mat(Color(0.25, 0.15, 0.08)))
	# 椅子（店長が座っている）
	_box(self, Vector3(0.55, 0.08, 0.55), Vector3(0.0, 0.48, -2.2), _mat(Color(0.15, 0.15, 0.18)))
	_box(self, Vector3(0.55, 0.7, 0.08), Vector3(0.0, 0.9, -2.5), _mat(Color(0.15, 0.15, 0.18)))
	var manager: Node3D = _person({"body_color": "#2e3550", "skin_color": "#e6bf9c", "hair_color": "#55524f", "hair": "bald",
		"build": "normal", "accessory": "glasses", "height": 0.86}, Vector3(0.0, 0.0, -2.15), 0.0, "slump")
	manager.set("hold_pose", "slump")
	# 壁: 売上目標・時計・カレンダー
	_box(self, Vector3(1.8, 1.0, 0.03), Vector3(-1.4, 1.75, -3.93), _mat(Color(0.97, 0.97, 0.97)))
	_label(self, "今月の売上目標", Vector3(-1.4, 2.1, -3.9), 60, Color(0.15, 0.15, 0.2), 0.004)
	_label(self, "未達", Vector3(-1.4, 1.65, -3.9), 150, Color(0.85, 0.1, 0.1), 0.004)
	_box(self, Vector3(0.35, 0.35, 0.04), Vector3(1.2, 2.25, -3.93), _mat(Color(0.98, 0.98, 0.95)))
	_label(self, "23:47", Vector3(1.2, 2.25, -3.9), 70, Color(0.1, 0.1, 0.1), 0.0035)
	_box(self, Vector3(0.6, 0.8, 0.02), Vector3(2.3, 1.6, -3.93), _mat(Color(0.95, 0.92, 0.85)))
	_label(self, "休日\n0日", Vector3(2.3, 1.6, -3.9), 60, Color(0.8, 0.1, 0.1), 0.004)
	# 棚と景品の段ボール
	for j in range(4):
		_box(self, Vector3(0.6, 0.45, 0.5), Vector3(-2.9, 0.23 + 0.46 * float(j % 2), -3.0 + 0.6 * floorf(float(j) / 2.0)), _mat(Color(0.7, 0.55, 0.35)))
	# しおれた観葉植物
	_cyl(self, 0.16, 0.12, 0.3, Vector3(2.7, 0.15, -2.8), _mat(Color(0.6, 0.3, 0.2)))
	for k in range(5):
		var leaf: MeshInstance3D = _box(self, Vector3(0.06, 0.4, 0.02), Vector3(2.7 + 0.05 * float(k - 2), 0.45, -2.8), _mat(Color(0.45, 0.45, 0.2)))
		leaf.rotation.z = 1.2 * float(k - 2) / 2.0
	# 蛍光灯（ときどきチカチカ）
	_box(self, Vector3(1.4, 0.04, 0.15), Vector3(0.0, 2.75, -1.8), _mat(Color(0.95, 0.98, 1.0), 2.5))
	_flicker = _omni(Vector3(0.0, 2.6, -1.6), Color(0.92, 0.97, 1.0), 1.1, 6.0)
	_omni(Vector3(0.0, 1.8, 0.8), Color(1.0, 0.95, 0.85), 0.5, 4.0)


# ---------------------------------------------------------------- プリクラコーナー（あやしいおじさん）

func _booth(pos: Vector3, body_c: Color, poster_c: Color, text: String) -> void:
	var n: Node3D = _node(self, pos)
	_box(n, Vector3(1.9, 2.3, 1.7), Vector3(0.0, 1.15, 0.0), _mat(body_c, 0.0, 0.5))
	_box(n, Vector3(1.7, 1.3, 0.03), Vector3(0.0, 1.35, 0.86), _mat(poster_c, 0.5))
	_label(n, text, Vector3(0.0, 1.55, 0.9), 110, Color(1.0, 1.0, 1.0), 0.004)
	_label(n, "美肌モード", Vector3(0.0, 1.0, 0.9), 60, Color(1.0, 0.95, 0.6), 0.004)
	# 横の入口のカーテン
	var curtain: StandardMaterial3D = _mat(body_c.lightened(0.35), 0.0, 0.9)
	for i in range(5):
		_box(n, Vector3(0.02, 1.5, 0.22), Vector3(0.96, 0.95, -0.55 + 0.23 * float(i)), curtain)
	_box(n, Vector3(1.9, 0.16, 1.7), Vector3(0.0, 2.38, 0.0), _blink_mat(poster_c.lightened(0.3), 1.8, 2.0, pos.x))


func _build_purikura() -> void:
	_env(Color(0.08, 0.05, 0.1), Color(1.0, 0.85, 0.95), 0.7, 0.6)
	_room(Color(0.95, 0.85, 0.9), Color(0.98, 0.9, 0.95), Color(0.95, 0.9, 0.95))
	_booth(Vector3(-2.3, 0.0, -3.3), Color(0.98, 0.6, 0.8), Color(0.95, 0.35, 0.6), "盛れる！")
	_booth(Vector3(0.3, 0.0, -4.4), Color(0.75, 0.65, 0.98), Color(0.5, 0.4, 0.95), "最新機種")
	_booth(Vector3(2.9, 0.0, -3.3), Color(0.6, 0.9, 0.95), Color(0.2, 0.7, 0.85), "デカ目")
	_label(self, "プリクラ", Vector3(0.0, 2.9, -2.6), 130, Color(1.0, 0.4, 0.7))
	# よくある注意書き
	# 天井から下がった注意書き（カメラに見える位置）
	_box(self, Vector3(1.5, 0.5, 0.03), Vector3(-0.9, 2.55, -2.2), _mat(Color(1.0, 1.0, 1.0)))
	_label(self, "男性のみのご入場は\nご遠慮ください", Vector3(-0.9, 2.55, -2.17), 46, Color(0.85, 0.1, 0.3), 0.004)
	_box(self, Vector3(1.3, 0.45, 0.03), Vector3(1.55, 2.0, -2.35), _mat(Color(1.0, 0.95, 0.3)))
	_label(self, "盗撮は犯罪です", Vector3(1.55, 2.0, -2.32), 64, Color(0.1, 0.1, 0.1), 0.004)
	# あやしいおじさん: 左のプリクラ機のカーテンのすき間をスマホでのぞいている
	var uncle: Node3D = _person({"body_color": "#a89a78", "skin_color": "#e9c19b", "hair_color": "#3d3a36", "hair": "bald",
		"build": "big", "accessory": "glasses", "height": 0.98}, Vector3(-0.85, 0.0, -2.9), -PI * 0.5, "peek")
	var arm: Node3D = uncle.get("_arm_r")
	if arm != null:
		var phone: MeshInstance3D = _box(arm, Vector3(0.08, 0.15, 0.02), Vector3(0.0, -0.62, 0.03), _mat(Color(0.1, 0.1, 0.12)))
		phone.rotation.x = PI * 0.5
		_box(phone, Vector3(0.07, 0.13, 0.005), Vector3(0.0, 0.0, -0.012), _mat(Color(0.6, 0.85, 1.0), 1.2))
	# 頭の上の「！？」
	_label(self, "！？", Vector3(-0.6, 1.95, -2.6), 110, Color(1.0, 0.25, 0.2), 0.004)
	_omni(Vector3(0.0, 2.8, -2.0), Color(1.0, 0.85, 0.95), 1.6, 8.0)
	_omni(Vector3(-2.5, 2.5, -1.6), Color(1.0, 0.6, 0.85), 0.9, 5.0)
	_omni(Vector3(2.8, 2.5, -1.6), Color(0.6, 0.85, 1.0), 0.9, 5.0)
