class_name StageWorld
extends Node3D
## Procedurally built shop interiors made only from primitive meshes.
## "konbini" is built here; "arcade" is delegated to res://scripts/arcade_stage.gd.
## Conventions: metres, Y up, floor y = 0, camera (made by main) near (0, 1.55, 1.9) looking -Z.

## Font for every Label3D (Label3D ignores the theme). Set this before build().
var label_font: Font = null

const STAND_POS: Vector3 = Vector3(0.0, 0.0, -0.35)
const ENTRANCE_POS: Vector3 = Vector3(3.6, 0.0, -3.0)
const TENSION_COLOR: Color = Color(1.0, 0.16, 0.1)
const ARCADE_SCRIPT: String = "res://scripts/arcade_stage.gd"
const BACKDROP_SCRIPT: String = "res://scripts/backdrop_stage.gd"
const SignFit = preload("res://scripts/sign_fit.gd")

var _stage_id: String = ""
var _built: bool = false
var _arcade: Node3D = null
var _env: Environment = null
var _base_ambient: Color = Color(1.0, 1.0, 1.0)
var _lit_tension: float = 0.0
var _lights: Array[Light3D] = []
var _light_colors: Array[Color] = []
var _light_energy: Array[float] = []
var _alarm: OmniLight3D = null
var _tension: float = 0.0
var _time: float = 0.0
var _anim_mats: Array[StandardMaterial3D] = []
var _anim_base: Array[float] = []
var _anim_speed: Array[float] = []
var _anim_phase: Array[float] = []
var _mat_cache: Dictionary = {}
var _mesh_cache: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


# ---------------------------------------------------------------- public API

## variant: "day"（ふつう）か "night"（コンビニは深夜、ゲームセンターは閉店後。タイトルの背景用。要件#82）
func build(stage_id: String, variant: String = "day") -> void:
	_clear()
	_rng.seed = 7741
	if stage_id.begins_with("bg_"):
		# タイトルの背景だけの場面（要件#84）
		_stage_id = stage_id
		var bd: Node3D = (load(BACKDROP_SCRIPT) as GDScript).new()
		bd.set("label_font", label_font)
		add_child(bd)
		bd.call("build", stage_id)
		_built = true
		SignFit.fit_all(self)
		return
	if stage_id == "arcade":
		_stage_id = "arcade"
		_build_arcade_delegate()
	else:
		_stage_id = "konbini"
		_build_konbini()
	if variant == "night" or variant == "hard":
		_apply_night()
	if variant == "hard":
		_apply_hard()
	if _stage_id == "konbini":
		_apply_lighting()
	_built = true
	# 看板の文字を板に収める（要件#91）
	SignFit.fit_all(self)


## 夜にする: 外を暗くし、日の光を消す。ゲームセンターは閉店後なので照明もほとんど落とす
func _apply_night() -> void:
	var closed: bool = _stage_id == "arcade"
	var stack: Array = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is WorldEnvironment and (n as WorldEnvironment).environment != null:
			var env: Environment = (n as WorldEnvironment).environment
			env.background_color = Color(0.02, 0.03, 0.07)
			env.ambient_light_energy *= 0.25 if closed else 0.45
			env.ambient_light_color = env.ambient_light_color.lerp(Color(0.35, 0.4, 0.75), 0.5)
			env.tonemap_exposure *= 0.8 if closed else 0.92
			if n == _find_env_owner():
				_base_ambient = env.ambient_light_color
		elif n is Light3D:
			var l: Light3D = n
			var k: float = 0.08 if l is DirectionalLight3D else (0.3 if closed else 1.0)
			l.light_energy *= k
			if not closed and l is OmniLight3D:
				l.light_color = l.light_color.lerp(Color(0.85, 0.92, 1.0), 0.3)
	# コンビニの明るさは毎フレーム _light_energy から戻すので、元の値も変える
	for i in range(_lights.size()):
		if is_instance_valid(_lights[i]):
			_light_energy[i] = _lights[i].light_energy
			_light_colors[i] = _lights[i].light_color


## ハードコアの画面（要件#90）: 閉店後の店を赤い照明で
func _apply_hard() -> void:
	var red: OmniLight3D = OmniLight3D.new()
	red.light_color = Color(1.0, 0.12, 0.08)
	red.light_energy = 2.2
	red.omni_range = 9.0
	red.position = Vector3(0.0, 2.6, -1.5)
	add_child(red)
	var stack: Array = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is WorldEnvironment and (n as WorldEnvironment).environment != null:
			var env: Environment = (n as WorldEnvironment).environment
			env.ambient_light_color = Color(0.6, 0.1, 0.08)
			env.background_color = Color(0.06, 0.0, 0.0)
			# 毎フレームの照明（_apply_lighting）がこの色から計算するように（要件#109: コンビニでは赤みがすぐ消えていた）
			if env == _env:
				_base_ambient = env.ambient_light_color


func _find_env_owner() -> Node:
	for c in get_children():
		if c is WorldEnvironment:
			return c
	return null


## 対戦の客役のカメラ（カウンターの外から店員を見る。要件#84）のための、店員のうしろの壁と棚。1回だけ作る
var _staff_side: Node3D = null


func ensure_staff_side() -> void:
	if _staff_side != null and is_instance_valid(_staff_side):
		return
	_staff_side = Node3D.new()
	add_child(_staff_side)
	var arcade: bool = _stage_id == "arcade"
	var wall_c: Color = Color(0.16, 0.12, 0.24) if arcade else Color(0.9, 0.92, 0.94)
	var parts: Array = []
	parts.append(_box(_staff_side, Vector3(8.0, 3.2, 0.1), Vector3(0.0, 1.6, 2.7), _mat(wall_c), false))
	for row in range(4):
		var y: float = 0.9 + 0.42 * float(row)
		parts.append(_box(_staff_side, Vector3(3.2, 0.04, 0.32), Vector3(0.0, y, 2.5), _mat(Color(0.75, 0.75, 0.78), 0.3, 0.5), false))
		for k in range(12):
			var c: Color = Color.from_hsv(fmod(float(k * 7 + row * 3) / 12.0, 1.0), 0.55 if not arcade else 0.7, 0.9)
			var sz: Vector3 = Vector3(0.2, 0.3, 0.2) if arcade else Vector3(0.18, 0.08, 0.05)
			parts.append(_box(_staff_side, sz, Vector3(-1.45 + 0.265 * float(k), y + sz.y * 0.5 + 0.02, 2.48), _mat(c, 0.6), false))
	if arcade:
		_label(_staff_side, "今投入中の景品！", Vector3(0.0, 2.75, 2.64), 90, Color(1.0, 0.85, 0.3)).rotation_degrees.y = 180.0
	else:
		_label(_staff_side, "TOBACCO", Vector3(0.0, 2.75, 2.64), 80, Color(0.2, 0.3, 0.5), 0.003, Color(1, 1, 1, 0.0), 0).rotation_degrees.y = 180.0
	for p in parts:
		(p as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func get_customer_stand() -> Vector3:
	return STAND_POS


func get_customer_entrance() -> Vector3:
	return ENTRANCE_POS


## ゲームセンターのときだけ、arcade_stage.gd のノード（台の調整のミニゲーム用）
func get_arcade() -> Node3D:
	if _arcade != null and is_instance_valid(_arcade):
		return _arcade
	return null


func get_stage_id() -> String:
	return _stage_id


func set_tension(t: float) -> void:
	_tension = clampf(t, 0.0, 1.0)
	if _arcade != null and is_instance_valid(_arcade):
		_arcade.call("set_tension", _tension)


# ---------------------------------------------------------------- frame update

func _process(delta: float) -> void:
	if not _built or _stage_id != "konbini":
		return
	_time += delta
	for i in range(_anim_mats.size()):
		var wave: float = 0.5 + 0.5 * sin(_time * _anim_speed[i] + _anim_phase[i])
		_anim_mats[i].emission_energy_multiplier = _anim_base[i] * (0.35 + 0.65 * wave)
	# 照明は、緊張しているときと、緊張が解けた直後の1回だけ計算する（要件#109: ふだんは毎フレーム全部の明かりを触らない）
	if _tension > 0.0 or _lit_tension > 0.0:
		_apply_lighting()
		_lit_tension = _tension


func _apply_lighting() -> void:
	var t: float = _tension
	var pulse: float = 0.5 + 0.5 * sin(_time * (2.0 + 7.0 * t))
	var red: float = clampf(t * (0.65 + 0.35 * pulse), 0.0, 1.0)
	for i in range(_lights.size()):
		var l: Light3D = _lights[i]
		if l == null or not is_instance_valid(l):
			continue
		l.light_color = _light_colors[i].lerp(TENSION_COLOR, red * 0.7)
		l.light_energy = _light_energy[i] * (1.0 - 0.2 * red)
	if _env != null:
		_env.ambient_light_color = _base_ambient.lerp(Color(0.6, 0.1, 0.07), red * 0.6)
	if _alarm != null and is_instance_valid(_alarm):
		_alarm.light_energy = t * t * (0.4 + 1.6 * pulse) * 2.5


# ---------------------------------------------------------------- arcade (delegated)

func _build_arcade_delegate() -> void:
	var scr: GDScript = load(ARCADE_SCRIPT) as GDScript
	if scr == null:
		push_error("StageWorld: could not load " + ARCADE_SCRIPT)
		return
	var arcade: Node3D = scr.new() as Node3D
	if arcade == null:
		push_error("StageWorld: arcade_stage.gd is not a Node3D script")
		return
	arcade.set("label_font", label_font)
	add_child(arcade)
	arcade.call("build")
	_arcade = arcade


# ---------------------------------------------------------------- housekeeping

func _clear() -> void:
	_built = false
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_arcade = null
	_staff_side = null
	_env = null
	_alarm = null
	_lights.clear()
	_light_colors.clear()
	_light_energy.clear()
	_anim_mats.clear()
	_anim_base.clear()
	_anim_speed.clear()
	_anim_phase.clear()
	_mat_cache.clear()
	_mesh_cache.clear()
	_tension = 0.0
	_time = 0.0


# ---------------------------------------------------------------- helpers

func _node(parent: Node3D, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> Node3D:
	var n: Node3D = Node3D.new()
	n.position = pos
	n.rotation_degrees = rot_deg
	parent.add_child(n)
	return n


func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, shadow: bool) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material, shadow: bool = true) -> MeshInstance3D:
	var key: String = "b%.3f_%.3f_%.3f" % [sz.x, sz.y, sz.z]
	var bm: BoxMesh = null
	if _mesh_cache.has(key):
		bm = _mesh_cache[key] as BoxMesh
	else:
		bm = BoxMesh.new()
		bm.size = sz
		_mesh_cache[key] = bm
	return _add_mesh(parent, bm, pos, mat, shadow)


## 円柱・球も、同じ大きさならメッシュを使い回す（要件#109: 棚の商品などで同じ形を何百個も作っていた）
func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material, shadow: bool = true, seg: int = 16) -> MeshInstance3D:
	var key: String = "c%.3f_%.3f_%.3f_%d" % [r_top, r_bot, h, seg]
	var cm: CylinderMesh = _mesh_cache.get(key, null) as CylinderMesh
	if cm == null:
		cm = CylinderMesh.new()
		cm.top_radius = r_top
		cm.bottom_radius = r_bot
		cm.height = h
		cm.radial_segments = seg
		cm.rings = 1
		_mesh_cache[key] = cm
	return _add_mesh(parent, cm, pos, mat, shadow)


func _sphere(parent: Node3D, r: float, pos: Vector3, mat: Material, shadow: bool = true, seg: int = 16) -> MeshInstance3D:
	var key: String = "s%.3f_%d" % [r, seg]
	var sm: SphereMesh = _mesh_cache.get(key, null) as SphereMesh
	if sm == null:
		sm = SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = seg
		sm.rings = maxi(int(float(seg) * 0.5), 4)
		_mesh_cache[key] = sm
	return _add_mesh(parent, sm, pos, mat, shadow)


func _mat(c: Color, rough: float = 0.7, metal: float = 0.0) -> StandardMaterial3D:
	var key: String = "m%s_%.2f_%.2f" % [c.to_html(true), rough, metal]
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_mat_cache[key] = m
	return m


func _emat(c: Color, energy: float = 2.0) -> StandardMaterial3D:
	var key: String = "e%s_%.2f" % [c.to_html(true), energy]
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	_mat_cache[key] = m
	return m


func _anim_emat(c: Color, energy: float, speed: float, phase: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	_anim_mats.append(m)
	_anim_base.append(energy)
	_anim_speed.append(speed)
	_anim_phase.append(phase)
	return m


func _glass_mat(c: Color) -> StandardMaterial3D:
	var key: String = "g%s" % [c.to_html(true)]
	if _mat_cache.has(key):
		return _mat_cache[key] as StandardMaterial3D
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.04
	m.metallic_specular = 0.9
	_mat_cache[key] = m
	return m


func _label(parent: Node3D, text: String, pos: Vector3, font_size: int, color: Color, pix: float = 0.003, outline_color: Color = Color(0.0, 0.0, 0.0, 0.85), outline: int = 8) -> Label3D:
	var lab: Label3D = Label3D.new()
	lab.text = text
	if label_font != null:
		lab.font = label_font
	lab.font_size = font_size
	lab.pixel_size = pix
	lab.modulate = color
	lab.outline_modulate = outline_color
	lab.outline_size = outline
	lab.position = pos
	lab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(lab)
	return lab


func _register_light(l: Light3D) -> void:
	_lights.append(l)
	_light_colors.append(l.light_color)
	_light_energy.append(l.light_energy)


func _add_sun(color: Color, energy: float, rot_deg: Vector3) -> DirectionalLight3D:
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.light_color = color
	sun.light_energy = energy
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 22.0
	sun.rotation_degrees = rot_deg
	add_child(sun)
	_register_light(sun)
	return sun


func _add_omni(pos: Vector3, color: Color, energy: float, light_range: float) -> OmniLight3D:
	var o: OmniLight3D = OmniLight3D.new()
	o.position = pos
	o.light_color = color
	o.light_energy = energy
	o.omni_range = light_range
	o.shadow_enabled = false
	add_child(o)
	_register_light(o)
	return o


func _add_alarm() -> void:
	_alarm = OmniLight3D.new()
	_alarm.position = Vector3(0.0, 2.6, -1.2)
	_alarm.light_color = TENSION_COLOR
	_alarm.light_energy = 0.0
	_alarm.omni_range = 9.0
	add_child(_alarm)


func _make_env(bg: Color, ambient: Color, ambient_energy: float, exposure: float, glow_intensity: float, glow_threshold: float) -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_energy = ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = exposure
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = glow_intensity
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = glow_threshold
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env
	_base_ambient = ambient


func _product_colors() -> Array[Color]:
	var arr: Array[Color] = [
		Color(0.95, 0.25, 0.2), Color(1.0, 0.6, 0.1), Color(1.0, 0.85, 0.2),
		Color(0.3, 0.75, 0.35), Color(0.2, 0.55, 0.95), Color(0.55, 0.3, 0.85),
		Color(0.95, 0.45, 0.65), Color(0.95, 0.95, 0.92), Color(0.55, 0.35, 0.2),
		Color(0.1, 0.75, 0.75), Color(0.9, 0.15, 0.4), Color(0.2, 0.25, 0.45),
	]
	return arr


func _rand_color(pal: Array[Color]) -> Color:
	return pal[_rng.randi_range(0, pal.size() - 1)]


# ---------------------------------------------------------------- shared structure

func _room_shell(floor_mat: Material, back_mat: Material, side_mat: Material, ceil_mat: Material) -> void:
	_box(self, Vector3(10.4, 0.1, 9.9), Vector3(0.0, -0.05, -2.25), floor_mat, false)
	_box(self, Vector3(10.4, 3.4, 0.2), Vector3(0.0, 1.6, -7.1), back_mat, false)
	_box(self, Vector3(0.2, 3.4, 9.9), Vector3(-5.1, 1.6, -2.25), side_mat, false)
	# right wall with a door opening (z -3.9 .. -2.1, height 2.4)
	_box(self, Vector3(0.2, 3.4, 3.3), Vector3(5.1, 1.6, -5.55), side_mat, false)
	_box(self, Vector3(0.2, 3.4, 4.6), Vector3(5.1, 1.6, 0.2), side_mat, false)
	_box(self, Vector3(0.2, 0.9, 1.8), Vector3(5.1, 2.85, -3.0), side_mat, false)
	_box(self, Vector3(10.4, 3.4, 0.2), Vector3(0.0, 1.6, 2.6), side_mat, false)
	_box(self, Vector3(10.4, 0.1, 9.9), Vector3(0.0, 3.25, -2.25), ceil_mat, false)


func _floor_grid(c: Color, step: float) -> void:
	var m: StandardMaterial3D = _mat(c, 0.3)
	var x: float = -5.0 + step
	while x < 5.0:
		_box(self, Vector3(0.012, 0.003, 9.5), Vector3(x, 0.0015, -2.25), m, false)
		x += step
	var z: float = -7.0 + step
	while z < 2.5:
		_box(self, Vector3(10.0, 0.003, 0.012), Vector3(0.0, 0.0015, z), m, false)
		z += step


func _auto_door(frame_c: Color, outside_c: Color) -> void:
	var fm: StandardMaterial3D = _mat(frame_c, 0.3, 0.8)
	var glass: StandardMaterial3D = _glass_mat(Color(0.7, 0.85, 0.95, 0.18))
	# bright "outside" seen through the glass
	_box(self, Vector3(0.05, 3.0, 3.0), Vector3(5.9, 1.5, -3.0), _emat(outside_c, 1.3), false)
	_box(self, Vector3(1.0, 0.1, 2.4), Vector3(5.6, -0.05, -3.0), _mat(Color(0.55, 0.56, 0.58), 0.8), false)
	# fixed frame
	_box(self, Vector3(0.12, 2.4, 0.08), Vector3(4.98, 1.2, -3.88), fm)
	_box(self, Vector3(0.12, 2.4, 0.08), Vector3(4.98, 1.2, -2.12), fm)
	_box(self, Vector3(0.12, 0.1, 1.84), Vector3(4.98, 2.38, -3.0), fm)
	# two sliding panels, parted open
	for i in range(2):
		var sd: float = -1.0 if i == 0 else 1.0
		var zc: float = -3.0 + sd * 0.75
		_box(self, Vector3(0.03, 2.26, 0.86), Vector3(5.02, 1.14, zc), glass, false)
		_box(self, Vector3(0.05, 2.28, 0.04), Vector3(5.02, 1.14, zc - 0.43), fm)
		_box(self, Vector3(0.05, 2.28, 0.04), Vector3(5.02, 1.14, zc + 0.43), fm)
		_box(self, Vector3(0.05, 0.06, 0.86), Vector3(5.02, 0.04, zc), fm)
		_box(self, Vector3(0.05, 0.06, 0.86), Vector3(5.02, 2.25, zc), fm)
	# sensor + floor mat
	_box(self, Vector3(0.15, 0.08, 0.3), Vector3(4.9, 2.5, -3.0), _mat(Color(0.15, 0.15, 0.17), 0.4))
	_box(self, Vector3(0.01, 0.03, 0.1), Vector3(4.82, 2.5, -3.0), _emat(Color(1.0, 0.2, 0.1), 2.0), false)
	_box(self, Vector3(1.3, 0.012, 1.6), Vector3(4.25, 0.006, -3.0), _mat(Color(0.2, 0.22, 0.25), 0.95), false)
	_box(self, Vector3(1.1, 0.014, 0.08), Vector3(4.25, 0.007, -3.6), _mat(Color(0.1, 0.62, 0.32), 0.9), false)
	_box(self, Vector3(1.1, 0.014, 0.08), Vector3(4.25, 0.007, -2.4), _mat(Color(0.1, 0.62, 0.32), 0.9), false)
	var lab: Label3D = _label(self, "自動ドア", Vector3(4.95, 1.35, -3.0), 40, Color(0.1, 0.3, 0.6), 0.0025, Color(1.0, 1.0, 1.0, 0.9), 6)
	lab.rotation_degrees = Vector3(0.0, -90.0, 0.0)


# ================================================================ KONBINI

func _build_konbini() -> void:
	_make_env(Color(0.82, 0.88, 0.95), Color(0.9, 0.92, 0.96), 0.6, 1.0, 0.45, 1.2)
	_add_sun(Color(1.0, 0.97, 0.92), 1.1, Vector3(-58.0, -30.0, 0.0))
	var cool: Color = Color(0.95, 0.97, 1.0)
	_add_omni(Vector3(-2.6, 2.9, -1.6), cool, 0.8, 6.0)
	_add_omni(Vector3(2.6, 2.9, -1.6), cool, 0.8, 6.0)
	_add_omni(Vector3(-2.6, 2.9, -5.0), cool, 0.8, 6.0)
	_add_omni(Vector3(2.6, 2.9, -5.0), cool, 0.8, 6.0)
	_add_omni(Vector3(0.0, 2.4, 1.3), Color(1.0, 0.96, 0.9), 0.7, 4.5)  # face fill for the customer
	_add_alarm()

	var floor_mat: StandardMaterial3D = _mat(Color(0.93, 0.93, 0.9), 0.15)
	var wall_mat: StandardMaterial3D = _mat(Color(0.96, 0.96, 0.93), 0.8)
	var ceil_mat: StandardMaterial3D = _mat(Color(0.97, 0.97, 0.97), 0.9)
	_room_shell(floor_mat, wall_mat, wall_mat, ceil_mat)
	_floor_grid(Color(0.8, 0.81, 0.8), 0.6)
	_konbini_signband()
	_konbini_ceiling_lights()
	_konbini_drink_case()
	_konbini_coffee_corner()
	_konbini_magazines()
	_gondola(Vector3(-2.5, 0.0, -2.2), 2.4, 1.2, 3, "おにぎり・パン")
	_gondola(Vector3(-2.4, 0.0, -4.7), 3.0, 1.75, 5, "お菓子")
	_gondola(Vector3(1.0, 0.0, -5.1), 2.4, 1.6, 4, "日用品")
	_konbini_freezer(Vector3(1.6, 0.0, -3.6))
	_konbini_misc()
	_auto_door(Color(0.75, 0.78, 0.8), Color(0.75, 0.9, 1.0))
	_konbini_counter()
	_konbini_pops()


func _konbini_signband() -> void:
	var green: StandardMaterial3D = _mat(Color(0.1, 0.62, 0.32), 0.5)
	var blue: StandardMaterial3D = _mat(Color(0.12, 0.35, 0.78), 0.5)
	var white: StandardMaterial3D = _emat(Color(0.97, 0.98, 1.0), 0.35)
	var orange: StandardMaterial3D = _mat(Color(1.0, 0.55, 0.1), 0.5)
	# back wall
	_box(self, Vector3(10.0, 0.1, 0.04), Vector3(0.0, 2.57, -6.98), orange, false)
	_box(self, Vector3(10.0, 0.08, 0.04), Vector3(0.0, 2.66, -6.98), green, false)
	_box(self, Vector3(10.0, 0.22, 0.03), Vector3(0.0, 2.81, -6.985), white, false)
	_box(self, Vector3(10.0, 0.08, 0.04), Vector3(0.0, 2.96, -6.98), blue, false)
	# side walls
	for i in range(2):
		var sx: float = -4.98 if i == 0 else 4.98
		_box(self, Vector3(0.04, 0.1, 9.5), Vector3(sx, 2.57, -2.25), orange, false)
		_box(self, Vector3(0.04, 0.08, 9.5), Vector3(sx, 2.66, -2.25), green, false)
		_box(self, Vector3(0.03, 0.22, 9.5), Vector3(sx, 2.81, -2.25), white, false)
		_box(self, Vector3(0.04, 0.08, 9.5), Vector3(sx, 2.96, -2.25), blue, false)
	# main store sign on the back wall
	_box(self, Vector3(3.6, 0.56, 0.06), Vector3(-1.2, 2.76, -6.93), _emat(Color(1.0, 1.0, 1.0), 0.8), false)
	_box(self, Vector3(3.7, 0.62, 0.04), Vector3(-1.2, 2.76, -6.95), green, false)
	_label(self, "ハッピーマート", Vector3(-0.95, 2.76, -6.89), 128, Color(0.05, 0.5, 0.22), 0.0032, Color(1.0, 1.0, 1.0, 1.0), 10)
	# smiley logo
	var logo: MeshInstance3D = _cyl(self, 0.22, 0.22, 0.04, Vector3(-2.65, 2.76, -6.89), _emat(Color(1.0, 0.8, 0.1), 0.9), false, 24)
	logo.rotation.x = PI * 0.5
	var ink: StandardMaterial3D = _mat(Color(0.15, 0.1, 0.05), 0.5)
	_box(self, Vector3(0.04, 0.07, 0.02), Vector3(-2.72, 2.8, -6.86), ink, false)
	_box(self, Vector3(0.04, 0.07, 0.02), Vector3(-2.58, 2.8, -6.86), ink, false)
	_box(self, Vector3(0.16, 0.03, 0.02), Vector3(-2.65, 2.68, -6.86), ink, false)
	# side wall texts
	var l1: Label3D = _label(self, "HAPPY MART", Vector3(-4.95, 2.81, -3.0), 96, Color(0.12, 0.35, 0.78), 0.0022, Color(1.0, 1.0, 1.0, 1.0), 6)
	l1.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	var l2: Label3D = _label(self, "いらっしゃいませ！", Vector3(4.95, 2.81, -5.4), 80, Color(0.9, 0.35, 0.05), 0.0022, Color(1.0, 1.0, 1.0, 1.0), 6)
	l2.rotation_degrees = Vector3(0.0, -90.0, 0.0)


func _konbini_ceiling_lights() -> void:
	var panel: StandardMaterial3D = _emat(Color(1.0, 1.0, 1.0), 4.0)
	var frame: StandardMaterial3D = _mat(Color(0.85, 0.86, 0.88), 0.4, 0.5)
	for ix in range(3):
		for iz in range(4):
			var x: float = -3.2 + float(ix) * 3.2
			var z: float = -0.4 - float(iz) * 1.9
			_box(self, Vector3(1.4, 0.04, 0.36), Vector3(x, 3.185, z), frame, false)
			_box(self, Vector3(1.3, 0.03, 0.26), Vector3(x, 3.16, z), panel, false)
	# security camera dome
	_cyl(self, 0.05, 0.05, 0.05, Vector3(1.5, 3.17, -2.0), _mat(Color(0.95, 0.95, 0.95), 0.4), false)
	_sphere(self, 0.08, Vector3(1.5, 3.12, -2.0), _mat(Color(0.1, 0.1, 0.12), 0.05, 0.3), false)


func _konbini_drink_case() -> void:
	var x0: float = -4.7
	var x1: float = 1.9
	var w: float = x1 - x0
	var cx: float = (x0 + x1) * 0.5
	var doors: int = 8
	var dw: float = w / float(doors)
	var dark: StandardMaterial3D = _mat(Color(0.18, 0.19, 0.21), 0.4, 0.6)
	var silver: StandardMaterial3D = _mat(Color(0.8, 0.82, 0.85), 0.25, 0.8)
	var back: StandardMaterial3D = _emat(Color(0.92, 0.97, 1.0), 1.4)
	var glass: StandardMaterial3D = _glass_mat(Color(0.8, 0.9, 1.0, 0.1))
	var price: StandardMaterial3D = _mat(Color(1.0, 0.9, 0.3), 0.5)
	# housing
	_box(self, Vector3(w + 0.1, 0.32, 0.75), Vector3(cx, 0.16, -6.62), dark)
	_box(self, Vector3(w + 0.1, 0.36, 0.75), Vector3(cx, 2.3, -6.62), dark)
	_box(self, Vector3(0.06, 2.5, 0.75), Vector3(x0 - 0.02, 1.24, -6.62), dark)
	_box(self, Vector3(0.06, 2.5, 0.75), Vector3(x1 + 0.02, 1.24, -6.62), dark)
	_box(self, Vector3(w, 1.8, 0.04), Vector3(cx, 1.22, -6.95), back, false)
	_box(self, Vector3(w, 0.05, 0.02), Vector3(cx, 2.14, -6.24), _emat(Color(0.3, 0.85, 1.0), 3.0), false)
	_label(self, "つめた〜いドリンク", Vector3(cx, 2.31, -6.23), 72, Color(0.75, 0.95, 1.0), 0.003, Color(0.0, 0.15, 0.35, 1.0), 8)
	# shelves with drinks
	var bottle_cols: Array[Color] = [
		Color(0.95, 0.3, 0.2), Color(0.2, 0.6, 0.95), Color(0.3, 0.8, 0.35), Color(1.0, 0.75, 0.15),
		Color(0.95, 0.95, 0.95), Color(0.55, 0.3, 0.15), Color(0.9, 0.4, 0.7), Color(0.15, 0.2, 0.5),
	]
	var cap_mat: StandardMaterial3D = _mat(Color(0.95, 0.95, 0.95), 0.4)
	var white: StandardMaterial3D = _mat(Color(1.0, 1.0, 1.0), 0.6)
	for i in range(5):
		var sy: float = 0.33 + float(i) * 0.36
		_box(self, Vector3(w - 0.06, 0.02, 0.6), Vector3(cx, sy, -6.63), silver, false)
		_box(self, Vector3(w - 0.06, 0.035, 0.008), Vector3(cx, sy - 0.005, -6.33), price, false)
		var base_y: float = sy + 0.01
		for d in range(doors):
			var c: Color = _rand_color(bottle_cols)
			var kind: int = _rng.randi_range(0, 2)
			var dx0: float = x0 + float(d) * dw
			for b in range(4):
				var bx: float = dx0 + 0.15 + float(b) * (dw - 0.3) / 3.0
				var bz: float = -6.47
				if kind == 0:
					var bh: float = 0.24
					_cyl(self, 0.034, 0.036, bh, Vector3(bx, base_y + bh * 0.5, bz), _mat(c.lightened(0.25), 0.15), false, 10)
					_cyl(self, 0.018, 0.018, 0.03, Vector3(bx, base_y + bh + 0.015, bz), cap_mat, false, 8)
				elif kind == 1:
					var ch: float = 0.13
					_cyl(self, 0.034, 0.034, ch, Vector3(bx, base_y + ch * 0.5, bz), _mat(c, 0.25, 0.7), false, 12)
				else:
					var kh: float = 0.2
					_box(self, Vector3(0.07, kh, 0.07), Vector3(bx, base_y + kh * 0.5, bz), _mat(c, 0.6), false)
					_box(self, Vector3(0.072, 0.05, 0.072), Vector3(bx, base_y + kh * 0.72, bz), white, false)
	# doors: glass, mullions, handles
	_box(self, Vector3(w, 1.8, 0.01), Vector3(cx, 1.22, -6.27), glass, false)
	for d in range(doors + 1):
		var mx: float = x0 + float(d) * dw
		_box(self, Vector3(0.045, 1.82, 0.05), Vector3(mx, 1.22, -6.27), silver, false)
	for d in range(doors):
		var hx: float = x0 + float(d) * dw + dw - 0.09
		_box(self, Vector3(0.02, 0.5, 0.03), Vector3(hx, 1.2, -6.22), silver, false)
	_add_omni(Vector3(cx - 1.6, 1.3, -6.5), Color(0.85, 0.95, 1.0), 0.5, 2.2)
	_add_omni(Vector3(cx + 1.6, 1.3, -6.5), Color(0.85, 0.95, 1.0), 0.5, 2.2)


func _konbini_coffee_corner() -> void:
	var wood: StandardMaterial3D = _mat(Color(0.62, 0.44, 0.28), 0.6)
	var black: StandardMaterial3D = _mat(Color(0.08, 0.08, 0.09), 0.25, 0.3)
	_box(self, Vector3(2.2, 0.9, 0.6), Vector3(3.4, 0.45, -6.7), _mat(Color(0.95, 0.95, 0.93), 0.5))
	_box(self, Vector3(2.26, 0.04, 0.64), Vector3(3.4, 0.92, -6.7), wood)
	for i in range(2):
		var mx: float = 2.85 + float(i) * 0.75
		_box(self, Vector3(0.5, 0.78, 0.45), Vector3(mx, 1.33, -6.72), black)
		_box(self, Vector3(0.42, 0.2, 0.02), Vector3(mx, 1.58, -6.49), _emat(Color(0.95, 0.55, 0.15), 1.2), false)
		_box(self, Vector3(0.26, 0.28, 0.1), Vector3(mx, 1.1, -6.47), _mat(Color(0.03, 0.03, 0.03), 0.6))
		_cyl(self, 0.04, 0.03, 0.1, Vector3(mx, 0.99, -6.47), _mat(Color(1.0, 1.0, 1.0), 0.6), false, 12)
		_box(self, Vector3(0.08, 0.05, 0.02), Vector3(mx + 0.15, 1.36, -6.49), _emat(Color(0.3, 1.0, 0.5), 1.5), false)
		_box(self, Vector3(0.08, 0.05, 0.02), Vector3(mx + 0.15, 1.28, -6.49), _emat(Color(1.0, 0.3, 0.3), 1.5), false)
	# cup stacks, lids, sugar
	for k in range(3):
		var cxp: float = 3.95 + float(k) * 0.14
		_cyl(self, 0.045, 0.035, 0.32, Vector3(cxp, 1.1, -6.62), _mat(Color(1.0, 1.0, 1.0), 0.6), false, 12)
	_box(self, Vector3(0.22, 0.1, 0.14), Vector3(4.38, 0.99, -6.6), _mat(Color(0.75, 0.55, 0.3), 0.7), false)
	_box(self, Vector3(1.3, 0.36, 0.04), Vector3(3.4, 2.05, -6.95), _mat(Color(0.35, 0.2, 0.1), 0.6), false)
	_label(self, "COFFEE", Vector3(3.4, 2.05, -6.92), 96, Color(1.0, 0.85, 0.6), 0.003, Color(0.2, 0.1, 0.0, 1.0), 6)


func _konbini_magazines() -> void:
	var z0: float = -5.6
	var z1: float = -1.0
	var len_z: float = z1 - z0
	var cz: float = (z0 + z1) * 0.5
	var base_mat: StandardMaterial3D = _mat(Color(0.85, 0.86, 0.88), 0.5, 0.3)
	var white: StandardMaterial3D = _mat(Color(0.97, 0.97, 0.97), 0.5)
	var pal: Array[Color] = _product_colors()
	_box(self, Vector3(0.45, 0.55, len_z), Vector3(-4.78, 0.275, cz), base_mat)
	_box(self, Vector3(0.06, 1.55, len_z), Vector3(-4.97, 0.78, cz), base_mat)
	for tier in range(3):
		var ty: float = 0.58 + float(tier) * 0.32
		var front: float = -4.58 - float(tier) * 0.09
		var depth: float = front - (-4.94)
		_box(self, Vector3(depth, 0.02, len_z), Vector3(-4.94 + depth * 0.5, ty - 0.01, cz), base_mat, false)
		var z: float = z0 + 0.14
		while z < z1 - 0.12:
			var mag: MeshInstance3D = _box(self, Vector3(0.015, 0.29, 0.21), Vector3(front - 0.05, ty + 0.14, z), _mat(_rand_color(pal), 0.35), false)
			mag.rotation.z = 0.22
			_box(mag, Vector3(0.004, 0.06, 0.2), Vector3(0.01, 0.1, 0.0), white, false)
			z += 0.235
	# window above the rack showing bright outside
	_box(self, Vector3(0.02, 0.9, 4.4), Vector3(-4.985, 2.05, cz), _emat(Color(0.7, 0.85, 1.0), 0.9), false)
	var mull: StandardMaterial3D = _mat(Color(0.75, 0.77, 0.8), 0.3, 0.7)
	for k in range(5):
		var mz: float = cz - 2.2 + float(k) * 1.1
		_box(self, Vector3(0.05, 0.95, 0.05), Vector3(-4.96, 2.05, mz), mull, false)
	_box(self, Vector3(0.08, 0.04, 4.45), Vector3(-4.95, 1.58, cz), mull, false)
	_box(self, Vector3(0.08, 0.04, 4.45), Vector3(-4.95, 2.51, cz), mull, false)
	var lab: Label3D = _label(self, "雑誌", Vector3(-4.93, 1.42, cz), 64, Color(0.1, 0.3, 0.7), 0.0028, Color(1.0, 1.0, 1.0, 1.0), 6)
	lab.rotation_degrees = Vector3(0.0, 90.0, 0.0)


func _gondola(center: Vector3, length: float, height: float, levels: int, sign_text: String) -> void:
	var g: Node3D = _node(self, center)
	var body: StandardMaterial3D = _mat(Color(0.93, 0.94, 0.95), 0.5)
	var dark: StandardMaterial3D = _mat(Color(0.35, 0.37, 0.4), 0.6)
	var accent: StandardMaterial3D = _mat(Color(0.1, 0.62, 0.32), 0.45)
	var price: StandardMaterial3D = _mat(Color(1.0, 0.92, 0.3), 0.5)
	var white: StandardMaterial3D = _mat(Color(0.98, 0.98, 0.96), 0.5)
	_box(g, Vector3(length, 0.14, 0.72), Vector3(0.0, 0.07, 0.0), dark)
	_box(g, Vector3(length, height, 0.06), Vector3(0.0, height * 0.5, 0.0), body)
	_box(g, Vector3(0.06, height + 0.02, 0.74), Vector3(-length * 0.5, height * 0.5, 0.0), accent)
	_box(g, Vector3(0.06, height + 0.02, 0.74), Vector3(length * 0.5, height * 0.5, 0.0), accent)
	var top_y: float = height + 0.14
	_box(g, Vector3(length * 0.6, 0.24, 0.05), Vector3(0.0, top_y, 0.0), _emat(Color(1.0, 0.85, 0.2), 0.6))
	_label(g, sign_text, Vector3(0.0, top_y, 0.03), 64, Color(0.75, 0.1, 0.05), 0.0028, Color(1.0, 1.0, 1.0, 1.0), 6)
	var pal: Array[Color] = _product_colors()
	var step_y: float = (height - 0.25) / float(levels)
	for lv in range(levels):
		var sy: float = 0.16 + float(lv) * step_y
		for i in range(2):
			var sd: float = 1.0 if i == 0 else -1.0
			_box(g, Vector3(length - 0.08, 0.025, 0.32), Vector3(0.0, sy, sd * 0.19), body, false)
			_box(g, Vector3(length - 0.08, 0.045, 0.012), Vector3(0.0, sy - 0.005, sd * 0.355), price, false)
		# products only on the camera-facing (+Z) side
		var max_h: float = step_y - 0.06
		var x: float = -length * 0.5 + 0.08
		while x < length * 0.5 - 0.1:
			var pw: float = _rng.randf_range(0.08, 0.15)
			if x + pw > length * 0.5 - 0.06:
				break
			var ph: float = minf(_rng.randf_range(0.1, 0.24), max_h)
			var pd: float = _rng.randf_range(0.14, 0.24)
			var c: Color = _rand_color(pal)
			var shape: int = _rng.randi_range(0, 5)
			var px: float = x + pw * 0.5
			var py: float = sy + 0.0125 + ph * 0.5
			if shape == 0:
				_cyl(g, pw * 0.5, pw * 0.42, ph, Vector3(px, py, 0.2), _mat(c, 0.4), false, 12)
				_cyl(g, pw * 0.51, pw * 0.51, ph * 0.12, Vector3(px, py + ph * 0.44, 0.2), white, false, 12)
			elif shape == 1:
				var bag: MeshInstance3D = _sphere(g, pw * 0.55, Vector3(px, py, 0.2), _mat(c, 0.25, 0.3), false, 10)
				bag.scale = Vector3(1.0, ph / (pw * 1.1), 0.55)
			else:
				_box(g, Vector3(pw, ph, pd), Vector3(px, py, 0.2), _mat(c, 0.5), false)
				_box(g, Vector3(pw * 0.8, ph * 0.3, 0.005), Vector3(px, py + ph * 0.12, 0.2 + pd * 0.5 + 0.003), white, false)
			x += pw + 0.015


func _konbini_freezer(p: Vector3) -> void:
	var f: Node3D = _node(self, p)
	var body: StandardMaterial3D = _mat(Color(0.95, 0.96, 0.97), 0.35)
	var blue: StandardMaterial3D = _mat(Color(0.12, 0.35, 0.78), 0.5)
	_box(f, Vector3(1.6, 0.6, 0.75), Vector3(0.0, 0.3, 0.0), body)
	_box(f, Vector3(1.6, 0.22, 0.06), Vector3(0.0, 0.71, 0.345), body)
	_box(f, Vector3(1.6, 0.22, 0.06), Vector3(0.0, 0.71, -0.345), body)
	_box(f, Vector3(0.06, 0.22, 0.63), Vector3(0.77, 0.71, 0.0), body)
	_box(f, Vector3(0.06, 0.22, 0.63), Vector3(-0.77, 0.71, 0.0), body)
	_box(f, Vector3(1.6, 0.06, 0.01), Vector3(0.0, 0.5, 0.377), blue, false)
	_box(f, Vector3(1.48, 0.02, 0.63), Vector3(0.0, 0.61, 0.0), _emat(Color(0.8, 0.92, 1.0), 0.8), false)
	var pal: Array[Color] = _product_colors()
	for i in range(22):
		var ix: float = _rng.randf_range(-0.66, 0.66)
		var iz: float = _rng.randf_range(-0.24, 0.24)
		var c: Color = _rand_color(pal)
		if i % 3 == 0:
			_cyl(f, 0.045, 0.045, 0.07, Vector3(ix, 0.655, iz), _mat(c, 0.4), false, 12)
		else:
			var it: MeshInstance3D = _box(f, Vector3(0.14, 0.04, 0.07), Vector3(ix, 0.64, iz), _mat(c, 0.4), false)
			it.rotation.y = _rng.randf_range(-0.5, 0.5)
	_box(f, Vector3(1.56, 0.01, 0.7), Vector3(0.0, 0.82, 0.0), _glass_mat(Color(0.8, 0.9, 1.0, 0.15)), false)
	_label(f, "アイス", Vector3(0.0, 0.3, 0.38), 64, Color(0.12, 0.35, 0.78), 0.003, Color(1.0, 1.0, 1.0, 1.0), 6)


func _konbini_misc() -> void:
	# multi-copy machine against the right wall, facing -X
	var cm: Node3D = _node(self, Vector3(4.6, 0.0, -5.0), Vector3(0.0, -90.0, 0.0))
	_box(cm, Vector3(0.75, 1.0, 0.6), Vector3(0.0, 0.5, 0.0), _mat(Color(0.85, 0.86, 0.88), 0.4))
	_box(cm, Vector3(0.75, 0.05, 0.6), Vector3(0.0, 1.025, 0.0), _mat(Color(0.3, 0.32, 0.35), 0.4))
	var scr: Node3D = _node(cm, Vector3(0.18, 1.1, 0.22), Vector3(-35.0, 0.0, 0.0))
	_box(scr, Vector3(0.3, 0.2, 0.02), Vector3.ZERO, _emat(Color(0.3, 0.7, 1.0), 1.4), false)
	for k in range(3):
		_box(cm, Vector3(0.6, 0.02, 0.02), Vector3(0.0, 0.25 + float(k) * 0.18, 0.305), _mat(Color(0.5, 0.52, 0.55), 0.4), false)
	_label(cm, "マルチコピー", Vector3(0.0, 0.85, 0.305), 40, Color(0.1, 0.3, 0.6), 0.0025, Color(1.0, 1.0, 1.0, 1.0), 4)
	# ATM
	var atm: Node3D = _node(self, Vector3(4.6, 0.0, -6.0), Vector3(0.0, -90.0, 0.0))
	_box(atm, Vector3(0.7, 1.4, 0.6), Vector3(0.0, 0.7, 0.0), _mat(Color(0.3, 0.45, 0.65), 0.4, 0.2))
	var ascr: Node3D = _node(atm, Vector3(0.0, 1.05, 0.29), Vector3(-20.0, 0.0, 0.0))
	_box(ascr, Vector3(0.36, 0.26, 0.02), Vector3.ZERO, _anim_emat(Color(0.3, 0.95, 1.0), 1.4, 1.2, 0.0), false)
	_box(atm, Vector3(0.3, 0.04, 0.2), Vector3(0.0, 0.82, 0.35), _mat(Color(0.15, 0.15, 0.17), 0.4))
	_box(atm, Vector3(0.7, 0.25, 0.62), Vector3(0.0, 1.525, 0.0), _mat(Color(0.95, 0.95, 0.95), 0.4))
	_label(atm, "ATM", Vector3(0.0, 1.525, 0.315), 72, Color(0.12, 0.35, 0.78), 0.003, Color(1.0, 1.0, 1.0, 1.0), 4)
	# shopping baskets near the door
	var basket: StandardMaterial3D = _mat(Color(0.9, 0.15, 0.15), 0.5)
	for k in range(5):
		_box(self, Vector3(0.45, 0.06, 0.32), Vector3(4.35, 0.03 + float(k) * 0.06, -4.2), basket)
	_box(self, Vector3(0.45, 0.2, 0.32), Vector3(4.35, 0.4, -4.2), basket)
	# convex security mirror in the back-left corner
	var mirror: MeshInstance3D = _sphere(self, 0.28, Vector3(-4.75, 2.35, -6.75), _mat(Color(0.9, 0.92, 0.95), 0.03, 1.0), false, 24)
	mirror.scale = Vector3(1.0, 1.0, 0.35)
	mirror.rotation_degrees = Vector3(0.0, 45.0, 0.0)
	# queue footprints in front of the counter (flat)
	var foot: StandardMaterial3D = _mat(Color(1.0, 0.85, 0.15), 0.6)
	_box(self, Vector3(0.1, 0.004, 0.22), Vector3(-0.12, 0.002, -1.6), foot, false)
	_box(self, Vector3(0.1, 0.004, 0.22), Vector3(0.12, 0.002, -1.6), foot, false)


func _konbini_counter() -> void:
	var top: StandardMaterial3D = _mat(Color(0.96, 0.94, 0.9), 0.35)
	var body: StandardMaterial3D = _mat(Color(0.98, 0.98, 0.97), 0.5)
	var green: StandardMaterial3D = _mat(Color(0.1, 0.62, 0.32), 0.45)
	var orange: StandardMaterial3D = _mat(Color(1.0, 0.55, 0.1), 0.5)
	_box(self, Vector3(3.2, 0.95, 0.48), Vector3(0.0, 0.475, 0.8), body)
	_box(self, Vector3(3.3, 0.05, 0.56), Vector3(0.0, 0.975, 0.8), top)
	_box(self, Vector3(3.22, 0.14, 0.02), Vector3(0.0, 0.78, 0.555), green)
	_box(self, Vector3(3.22, 0.05, 0.02), Vector3(0.0, 0.62, 0.555), orange)
	_box(self, Vector3(3.2, 0.08, 0.5), Vector3(0.0, 0.04, 0.8), _mat(Color(0.3, 0.32, 0.35), 0.6))
	_build_register(Vector3(-1.2, 1.0, 0.82))
	_build_hot_case(Vector3(1.18, 1.0, 0.8))
	# flat cash tray (does not block the view)
	_box(self, Vector3(0.24, 0.012, 0.17), Vector3(-0.45, 1.006, 0.72), _mat(Color(0.2, 0.45, 0.85), 0.5), false)
	# donation box
	_cyl(self, 0.06, 0.06, 0.14, Vector3(0.68, 1.07, 0.72), _glass_mat(Color(0.85, 0.95, 1.0, 0.3)), false, 16)
	_cyl(self, 0.062, 0.062, 0.02, Vector3(0.68, 1.15, 0.72), _mat(Color(0.9, 0.15, 0.15), 0.5), false, 16)
	var coin: StandardMaterial3D = _mat(Color(0.85, 0.7, 0.35), 0.3, 0.9)
	for k in range(4):
		_cyl(self, 0.02, 0.02, 0.005, Vector3(0.67 + float(k % 2) * 0.02, 1.005 + float(k) * 0.006, 0.72), coin, false, 10)
	# plastic bag dispenser
	_box(self, Vector3(0.12, 0.12, 0.1), Vector3(-1.52, 1.06, 0.98), _mat(Color(0.97, 0.97, 0.97), 0.7))


func _build_register(p: Vector3) -> void:
	var r: Node3D = _node(self, p)
	var dark: StandardMaterial3D = _mat(Color(0.16, 0.17, 0.19), 0.35, 0.2)
	var grey: StandardMaterial3D = _mat(Color(0.75, 0.76, 0.78), 0.4, 0.3)
	_box(r, Vector3(0.44, 0.1, 0.4), Vector3(0.0, 0.05, 0.0), grey)
	_box(r, Vector3(0.36, 0.012, 0.01), Vector3(0.0, 0.06, 0.205), dark, false)
	_box(r, Vector3(0.06, 0.18, 0.06), Vector3(0.0, 0.19, -0.05), dark)
	# staff touch screen facing the camera
	var scr: Node3D = _node(r, Vector3(0.0, 0.32, -0.02), Vector3(-18.0, 0.0, 0.0))
	_box(scr, Vector3(0.38, 0.28, 0.04), Vector3.ZERO, dark)
	_box(scr, Vector3(0.34, 0.24, 0.005), Vector3(0.0, 0.0, 0.022), _emat(Color(0.35, 0.75, 1.0), 1.3), false)
	var ui_cols: Array[Color] = [Color(1.0, 0.5, 0.2), Color(0.4, 1.0, 0.5), Color(1.0, 0.9, 0.3)]
	for i in range(3):
		_box(scr, Vector3(0.09, 0.05, 0.004), Vector3(-0.1 + float(i) * 0.1, -0.07, 0.026), _emat(ui_cols[i], 1.6), false)
	_box(scr, Vector3(0.28, 0.08, 0.004), Vector3(0.0, 0.05, 0.026), _emat(Color(1.0, 1.0, 1.0), 1.2), false)
	# customer display facing -Z
	_box(r, Vector3(0.03, 0.3, 0.03), Vector3(0.14, 0.25, -0.16), dark)
	_box(r, Vector3(0.2, 0.12, 0.03), Vector3(0.14, 0.43, -0.17), dark)
	_box(r, Vector3(0.17, 0.08, 0.005), Vector3(0.14, 0.43, -0.187), _emat(Color(0.3, 1.0, 0.5), 1.5), false)
	# barcode scanner
	_box(r, Vector3(0.1, 0.06, 0.1), Vector3(0.33, 0.03, 0.0), dark)
	_box(r, Vector3(0.07, 0.006, 0.07), Vector3(0.33, 0.062, 0.0), _emat(Color(1.0, 0.1, 0.05), 2.0), false)
	# card terminal
	_box(r, Vector3(0.08, 0.04, 0.12), Vector3(0.48, 0.02, -0.05), dark)
	_box(r, Vector3(0.06, 0.004, 0.04), Vector3(0.48, 0.042, -0.08), _emat(Color(0.5, 0.9, 1.0), 1.2), false)
	# receipt printer
	_box(r, Vector3(0.12, 0.1, 0.14), Vector3(-0.3, 0.05, 0.05), grey)
	_box(r, Vector3(0.07, 0.002, 0.06), Vector3(-0.3, 0.101, 0.1), _mat(Color(1.0, 1.0, 1.0), 0.8), false)


func _build_hot_case(p: Vector3) -> void:
	var h: Node3D = _node(self, p)
	var red: StandardMaterial3D = _mat(Color(0.85, 0.15, 0.12), 0.4)
	var steel: StandardMaterial3D = _mat(Color(0.8, 0.8, 0.82), 0.3, 0.7)
	var glass: StandardMaterial3D = _glass_mat(Color(1.0, 0.95, 0.85, 0.16))
	_box(h, Vector3(0.8, 0.06, 0.44), Vector3(0.0, 0.03, 0.0), steel)
	_box(h, Vector3(0.78, 0.38, 0.02), Vector3(0.0, 0.25, -0.21), _emat(Color(1.0, 0.75, 0.4), 0.9), false)
	_box(h, Vector3(0.76, 0.012, 0.38), Vector3(0.0, 0.22, 0.0), steel, false)
	for i in range(4):
		var cxp: float = -0.39 if i % 2 == 0 else 0.39
		var czp: float = -0.21 if i < 2 else 0.21
		_box(h, Vector3(0.025, 0.38, 0.025), Vector3(cxp, 0.25, czp), steel)
	_box(h, Vector3(0.82, 0.08, 0.46), Vector3(0.0, 0.48, 0.0), red)
	_label(h, "ホットスナック", Vector3(0.0, 0.48, 0.235), 44, Color(1.0, 1.0, 1.0), 0.0022, Color(0.4, 0.0, 0.0, 1.0), 4)
	# fried chicken + korokke on the lower level
	var fried: StandardMaterial3D = _mat(Color(0.85, 0.55, 0.18), 0.8)
	var korokke: StandardMaterial3D = _mat(Color(0.75, 0.48, 0.2), 0.9)
	for k in range(4):
		var fc: MeshInstance3D = _sphere(h, 0.045, Vector3(-0.28 + float(k) * 0.09, 0.09, 0.02 + float(k % 2) * 0.06), fried, false, 10)
		fc.scale = Vector3(1.2, 0.7, 1.0)
	for k in range(3):
		var kr: MeshInstance3D = _sphere(h, 0.05, Vector3(0.1 + float(k) * 0.1, 0.085, 0.04), korokke, false, 10)
		kr.scale = Vector3(1.3, 0.55, 0.9)
	# frankfurters + nikuman on the upper level
	var sausage: StandardMaterial3D = _mat(Color(0.7, 0.25, 0.15), 0.4)
	for k in range(3):
		var cp: CapsuleMesh = CapsuleMesh.new()
		cp.radius = 0.02
		cp.height = 0.16
		var fs: MeshInstance3D = _add_mesh(h, cp, Vector3(-0.22, 0.25, -0.06 + float(k) * 0.07), sausage, false)
		fs.rotation.z = PI * 0.5
	var bun: StandardMaterial3D = _mat(Color(0.98, 0.96, 0.9), 0.8)
	for k in range(3):
		var nb: MeshInstance3D = _sphere(h, 0.055, Vector3(0.05 + float(k) * 0.11, 0.265, 0.03), bun, false, 12)
		nb.scale = Vector3(1.0, 0.75, 1.0)
	_box(h, Vector3(0.8, 0.38, 0.44), Vector3(0.0, 0.25, 0.0), glass, false)
	_add_omni(Vector3(p.x, p.y + 0.3, p.z), Color(1.0, 0.7, 0.35), 0.25, 0.9)


func _konbini_pops() -> void:
	_hanging_sign(Vector3(-2.5, 2.45, -2.2), "おにぎり100円", Color(1.0, 0.85, 0.15), Color(0.8, 0.05, 0.05))
	_hanging_sign(Vector3(-2.4, 2.55, -4.7), "新商品", Color(1.0, 1.0, 1.0), Color(0.1, 0.5, 0.25))
	_hanging_sign(Vector3(1.0, 2.5, -5.1), "ポイント2倍!", Color(0.95, 0.3, 0.45), Color(1.0, 1.0, 1.0))
	# blinking LED "SALE" board above the freezer
	var s: Node3D = _node(self, Vector3(1.6, 2.2, -3.8))
	_box(s, Vector3(0.7, 0.22, 0.03), Vector3.ZERO, _mat(Color(0.1, 0.1, 0.12), 0.4))
	_box(s, Vector3(0.64, 0.17, 0.005), Vector3(0.0, 0.0, 0.017), _anim_emat(Color(1.0, 0.15, 0.1), 2.5, 4.0, 0.0), false)
	_label(s, "SALE", Vector3(0.0, 0.0, 0.025), 56, Color(1.0, 1.0, 0.85), 0.0028, Color(0.5, 0.0, 0.0, 1.0), 4)
	var wire: StandardMaterial3D = _mat(Color(0.5, 0.5, 0.5), 0.5)
	_box(s, Vector3(0.006, 0.9, 0.006), Vector3(-0.3, 0.56, 0.0), wire, false)
	_box(s, Vector3(0.006, 0.9, 0.006), Vector3(0.3, 0.56, 0.0), wire, false)


func _hanging_sign(p: Vector3, text: String, bg: Color, fg: Color) -> void:
	var s: Node3D = _node(self, p)
	_box(s, Vector3(1.1, 0.34, 0.02), Vector3.ZERO, _mat(bg, 0.5))
	_box(s, Vector3(1.14, 0.38, 0.015), Vector3(0.0, 0.0, -0.006), _mat(fg, 0.5))
	_label(s, text, Vector3(0.0, 0.0, 0.015), 56, fg, 0.0026, Color(1.0, 1.0, 1.0, 1.0), 6)
	var wire_len: float = 3.2 - p.y
	var wire: StandardMaterial3D = _mat(Color(0.5, 0.5, 0.5), 0.5)
	_box(s, Vector3(0.006, wire_len, 0.006), Vector3(-0.45, wire_len * 0.5 + 0.17, 0.0), wire, false)
	_box(s, Vector3(0.006, wire_len, 0.006), Vector3(0.45, wire_len * 0.5 + 0.17, 0.0), wire, false)
