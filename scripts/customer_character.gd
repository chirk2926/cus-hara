class_name CustomerCharacter
extends Node3D
## Stylised toy-like customer built from primitives. Origin at the feet, faces +Z.
## Node layout:  self (walk tween: position / rotation.y)
##               └ _hop (one-shot react tweens: position / rotation / scale)
##                 └ _body_pivot (per-frame: tremble, walk bob, lean, sway)
##                   └ _figure (uniform height scale) → legs, torso, arms, head

signal arrived
signal left

const WALK_SPEED: float = 1.35
const ANGRY_SKIN: Color = Color(0.95, 0.28, 0.22)
const BROW_Y: float = 0.105
const MASK_SCALE: Vector3 = Vector3(1.05, 0.72, 0.65)

var _built: bool = false
var _height: float = 1.0
var _bw: float = 1.0
var _hair: String = "short"
var _accessory: String = "none"
var _skin: Color = Color(0.95, 0.79, 0.65)
var _body_color: Color = Color(0.54, 0.35, 0.24)
var _hair_color: Color = Color(0.2, 0.2, 0.2)

# nodes
var _hop: Node3D = null
var _body_pivot: Node3D = null
var _figure: Node3D = null
var _torso: Node3D = null
var _torso_base_scale: Vector3 = Vector3.ONE
var _head_pivot: Node3D = null
var _head: Node3D = null
var _arm_l: Node3D = null
var _arm_r: Node3D = null
var _leg_l: Node3D = null
var _leg_r: Node3D = null
var _eye_l: Node3D = null
var _eye_r: Node3D = null
var _pupil_l: Node3D = null
var _pupil_r: Node3D = null
var _brow_l: Node3D = null
var _brow_r: Node3D = null
var _mouth: Node3D = null
var _mouth_center: MeshInstance3D = null
var _mouth_cl: Node3D = null
var _mouth_cr: Node3D = null
var _nose: MeshInstance3D = null
var _mask: MeshInstance3D = null
var _vein: Node3D = null
var _steam: Array[CPUParticles3D] = []
var _skin_mat: StandardMaterial3D = null

# state
var _anger: float = 0.0
var _anger_smooth: float = 0.0
var _time: float = 0.0
var _walking: bool = false
var _walk_phase: float = 0.0
var _walk_rate: float = 1.0
var _mood_walk: String = ""
var _talk_time: float = 0.0
var _expr: String = "neutral"
var _expr_time: float = 0.0
var _arm_override: String = ""
var _arm_override_time: float = 0.0
var _shake: float = 0.0
var _flash: float = 0.0
var _steam_boost: float = 0.0
var _lean: float = 0.0

var _walk_tween: Tween = null
var _react_tween: Tween = null
var _nod_tween: Tween = null


# ---------------------------------------------------------------- public API

func setup(look: Dictionary) -> void:
	_kill_tween(_react_tween)
	_kill_tween(_nod_tween)
	_built = false
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_steam.clear()
	_mask = null
	_nose = null
	_body_color = Color.from_string(str(look.get("body_color", "#8a5a3c")), Color(0.54, 0.35, 0.24))
	_skin = Color.from_string(str(look.get("skin_color", "#f1c9a5")), Color(0.95, 0.79, 0.65))
	_hair_color = Color.from_string(str(look.get("hair_color", "#333333")), Color(0.2, 0.2, 0.2))
	_height = clampf(float(look.get("height", 1.0)), 0.8, 1.2)
	var build_s: String = str(look.get("build", "normal"))
	_bw = 1.0
	if build_s == "slim":
		_bw = 0.82
	elif build_s == "big":
		_bw = 1.3
	_hair = str(look.get("hair", "short"))
	_accessory = str(look.get("accessory", "none"))
	_expr = "neutral"
	_expr_time = 0.0
	_arm_override = ""
	_arm_override_time = 0.0
	_shake = 0.0
	_flash = 0.0
	_lean = 0.0
	_build_body()
	_built = true


func set_anger(ratio: float) -> void:
	_anger = clampf(ratio, 0.0, 1.0)


func enter(from: Vector3, to: Vector3) -> void:
	_kill_tween(_walk_tween)
	position = from
	var dir: Vector3 = to - from
	dir.y = 0.0
	var face: float = 0.0
	if dir.length() > 0.001:
		face = atan2(dir.x, dir.z)
	rotation.y = face
	_mood_walk = ""
	_walk_rate = 1.0
	_start_walk()
	var dur: float = maxf(dir.length() / WALK_SPEED, 0.2)
	_walk_tween = create_tween()
	_walk_tween.tween_property(self, "position", to, dur)
	_walk_tween.tween_callback(_stop_walk)
	_walk_tween.tween_property(self, "rotation:y", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_walk_tween.tween_callback(_emit_arrived)


func leave(to: Vector3, mood: String) -> void:
	_kill_tween(_walk_tween)
	var m: String = mood
	if m != "happy" and m != "angry" and m != "smug":
		m = "angry"
	if _built:
		react(m)
	_set_expr(m, 10000.0)
	_mood_walk = m
	var from: Vector3 = position
	var dir: Vector3 = to - from
	dir.y = 0.0
	var face: float = rotation.y
	if dir.length() > 0.001:
		face = atan2(dir.x, dir.z)
	var target_rot: float = rotation.y + wrapf(face - rotation.y, -PI, PI)
	var speed: float = WALK_SPEED * 1.1
	_walk_rate = 1.1
	if m == "angry":
		speed = WALK_SPEED * 1.3
		_walk_rate = 1.35
	elif m == "smug":
		speed = WALK_SPEED * 0.8
		_walk_rate = 0.8
	var dur: float = maxf(dir.length() / speed, 0.2)
	_walk_tween = create_tween()
	_walk_tween.tween_interval(0.35)
	_walk_tween.tween_property(self, "rotation:y", target_rot, 0.35).set_trans(Tween.TRANS_SINE)
	_walk_tween.tween_callback(_start_walk)
	_walk_tween.tween_property(self, "position", to, dur)
	_walk_tween.tween_callback(_finish_leave)


func talk(duration: float) -> void:
	_talk_time = maxf(duration, 0.0)


func react(kind: String) -> void:
	if not _built:
		return
	match kind:
		"explode":
			_set_expr("explode", 1.8)
			_arm_override = "up"
			_arm_override_time = 1.6
			_flash = 1.0
			_shake = 1.0
			_steam_boost = 2.0
			var tw: Tween = _new_react_tween()
			tw.tween_property(_hop, "scale", Vector3(1.15, 0.8, 1.15), 0.12)
			tw.tween_property(_hop, "position:y", 0.45, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(_hop, "scale", Vector3(0.9, 1.15, 0.9), 0.18)
			tw.tween_property(_hop, "position:y", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(_hop, "scale", Vector3.ONE, 0.2)
			tw.tween_property(_hop, "scale", Vector3(1.12, 0.88, 1.12), 0.06)
			_finish_rest(tw)
		"happy":
			_set_expr("happy", 2.0)
			_arm_override = "cheer"
			_arm_override_time = 0.9
			var tw2: Tween = _new_react_tween()
			tw2.tween_property(_hop, "position:y", 0.12, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw2.tween_property(_hop, "position:y", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw2.tween_property(_hop, "position:y", 0.07, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw2.tween_property(_hop, "position:y", 0.0, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			_finish_rest(tw2)
		"calm":
			_set_expr("calm", 1.5)
			_arm_override = "drop"
			_arm_override_time = 1.2
			var tw3: Tween = _new_react_tween()
			tw3.tween_property(_hop, "position:y", -0.035, 0.25).set_trans(Tween.TRANS_SINE)
			tw3.tween_property(_hop, "position:y", 0.0, 0.45).set_trans(Tween.TRANS_SINE)
			_finish_rest(tw3)
			_nod(0.3, 0.2, 0.0)
		"angry":
			_set_expr("angry", 1.6)
			_arm_override = "point"
			_arm_override_time = 1.4
			_shake = maxf(_shake, 0.5)
			var tw4: Tween = _new_react_tween()
			tw4.tween_property(_hop, "position:y", 0.08, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw4.parallel().tween_property(_hop, "rotation:x", 0.2, 0.15)
			tw4.tween_property(_hop, "position:y", 0.0, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw4.tween_property(_hop, "scale", Vector3(1.08, 0.92, 1.08), 0.05)
			tw4.tween_interval(0.35)
			tw4.tween_property(_hop, "rotation:x", 0.0, 0.4).set_trans(Tween.TRANS_SINE)
			_finish_rest(tw4)
		"smug":
			_set_expr("smug", 2.2)
			_arm_override = "crossed"
			_arm_override_time = 1.8
			var tw5: Tween = _new_react_tween()
			tw5.tween_property(_hop, "rotation:x", -0.12, 0.3).set_trans(Tween.TRANS_SINE)
			tw5.tween_interval(1.2)
			tw5.tween_property(_hop, "rotation:x", 0.0, 0.4).set_trans(Tween.TRANS_SINE)
			_finish_rest(tw5)
			_nod(-0.15, 0.3, 1.2)
		_:
			pass


func get_head_position() -> Vector3:
	if _head_pivot != null and is_instance_valid(_head_pivot) and _head_pivot.is_inside_tree():
		return _head_pivot.global_position + Vector3(0.0, 0.62 * _height, 0.0)
	if is_inside_tree():
		return global_position + Vector3(0.0, 1.95 * _height, 0.0)
	return position + Vector3(0.0, 1.95 * _height, 0.0)


# ---------------------------------------------------------------- tween helpers

func _kill_tween(tw: Tween) -> void:
	if tw != null and tw.is_valid():
		tw.kill()


func _new_react_tween() -> Tween:
	_kill_tween(_react_tween)
	_react_tween = create_tween()
	return _react_tween


func _finish_rest(tw: Tween) -> void:
	tw.tween_property(_hop, "scale", Vector3.ONE, 0.12)
	tw.parallel().tween_property(_hop, "position", Vector3.ZERO, 0.12)
	tw.parallel().tween_property(_hop, "rotation", Vector3.ZERO, 0.12)


func _nod(amount: float, down_time: float, hold: float) -> void:
	_kill_tween(_nod_tween)
	_nod_tween = create_tween()
	_nod_tween.tween_property(_head_pivot, "rotation:x", amount, down_time).set_trans(Tween.TRANS_SINE)
	if hold > 0.0:
		_nod_tween.tween_interval(hold)
	_nod_tween.tween_property(_head_pivot, "rotation:x", 0.0, 0.3).set_trans(Tween.TRANS_SINE)


func _set_expr(e: String, duration: float) -> void:
	_expr = e
	_expr_time = duration


func _start_walk() -> void:
	_walking = true


func _stop_walk() -> void:
	_walking = false


func _emit_arrived() -> void:
	arrived.emit()


func _finish_leave() -> void:
	_walking = false
	left.emit()


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if not _built:
		return
	_time += delta
	_expr_time = maxf(_expr_time - delta, 0.0)
	_arm_override_time = maxf(_arm_override_time - delta, 0.0)
	_shake = maxf(_shake - delta * 1.5, 0.0)
	_flash = maxf(_flash - delta * 2.0, 0.0)
	_steam_boost = maxf(_steam_boost - delta, 0.0)
	_anger_smooth = lerpf(_anger_smooth, _anger, clampf(delta * 6.0, 0.0, 1.0))
	var a: float = _anger_smooth
	var k: float = clampf(delta * 10.0, 0.0, 1.0)
	var expr: String = _expr if _expr_time > 0.0 else "neutral"

	# --- body: breathing, tremble, walk bob, lean, sway
	var breath: float = sin(_time * 2.2)
	_torso.scale = _torso_base_scale * Vector3(1.0 + 0.012 * breath, 1.0 + 0.018 * breath, 1.0 + 0.012 * breath)
	var trem: float = clampf((a - 0.6) / 0.4, 0.0, 1.0) * 0.012 + _shake * 0.05
	var off: Vector3 = Vector3.ZERO
	if trem > 0.0:
		off = Vector3(randf_range(-trem, trem), randf_range(-trem, trem) * 0.4, randf_range(-trem, trem))
	if _walking:
		_walk_phase += delta * 8.5 * _walk_rate
		var bob: float = 0.07 if _mood_walk == "happy" else 0.045
		off.y += absf(sin(_walk_phase)) * bob
	_body_pivot.position = off
	var lean_target: float = a * 0.14
	if expr == "smug":
		lean_target = -0.08
	elif expr == "explode":
		lean_target = 0.05
	_lean = lerpf(_lean, lean_target, k * 0.5)
	_body_pivot.rotation.x = _lean
	_body_pivot.rotation.z = sin(_time * 0.9) * 0.025 * (1.0 - a * 0.5)
	_head_pivot.rotation.z = sin(_time * 0.7 + 1.0) * 0.04
	_head_pivot.rotation.y = sin(_time * 0.45) * 0.06 * (1.0 - a)

	# --- legs
	if _walking:
		var swing: float = sin(_walk_phase) * 0.55
		_leg_l.rotation.x = swing
		_leg_r.rotation.x = -swing
	else:
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 0.0, k)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 0.0, k)

	# --- arms
	var pose: String = _arm_override if _arm_override_time > 0.0 else _default_pose(a, expr)
	var arm_k: float = clampf(delta * 14.0, 0.0, 1.0)
	_arm_l.rotation = _arm_l.rotation.lerp(_arm_target(pose, true), arm_k)
	_arm_r.rotation = _arm_r.rotation.lerp(_arm_target(pose, false), arm_k)

	# --- face
	_update_face(a, expr, delta, k)

	# --- skin colour / flash
	var redness: float = clampf(a * 0.6 + _flash * 0.5, 0.0, 1.0)
	_skin_mat.albedo_color = _skin.lerp(ANGRY_SKIN, redness)
	_skin_mat.emission = Color(1.0, 0.1, 0.05) * (_flash * 0.6)

	# --- anger mark + steam
	var show_vein: bool = a > 0.8 or expr == "explode" or expr == "angry"
	_vein.visible = show_vein
	if show_vein:
		var vs: float = 1.0 + 0.25 * absf(sin(_time * 9.0))
		_vein.scale = Vector3(vs, vs, vs)
	var want_steam: bool = a > 0.8 or _steam_boost > 0.0
	for p in _steam:
		if p.emitting != want_steam:
			p.emitting = want_steam


func _update_face(a: float, expr: String, delta: float, k: float) -> void:
	var fa: float = a
	if expr == "angry":
		fa = maxf(fa, 0.9)
	elif expr == "calm":
		fa = fa * 0.5
	var brow_ang_l: float = lerpf(-0.08, 0.55, fa)
	var brow_ang_r: float = brow_ang_l
	var brow_y_l: float = lerpf(0.0, -0.022, fa)
	var brow_y_r: float = brow_y_l
	var eye_sy: float = lerpf(1.0, 0.72, fa)
	var pupil_s: float = lerpf(1.0, 0.82, fa)
	var curve_l: float = lerpf(-0.2, -0.75, fa)
	var curve_r: float = curve_l
	var mouth_w: float = lerpf(0.9, 1.25, fa)
	var mouth_open: float = 0.0
	if fa > 0.8:
		mouth_open = (fa - 0.8) * 2.0
	match expr:
		"happy":
			brow_ang_l = -0.25
			brow_ang_r = -0.25
			brow_y_l = 0.02
			brow_y_r = 0.02
			eye_sy = 0.35
			pupil_s = 1.0
			curve_l = 0.85
			curve_r = 0.85
			mouth_w = 1.15
			mouth_open = 0.9
		"smug":
			brow_ang_l = -0.35
			brow_y_l = 0.03
			brow_ang_r = 0.35
			brow_y_r = -0.012
			eye_sy = 0.62
			pupil_s = 1.0
			curve_l = 0.75
			curve_r = -0.05
			mouth_w = 1.0
			mouth_open = 0.0
		"explode":
			brow_ang_l = 0.75
			brow_ang_r = 0.75
			brow_y_l = -0.03
			brow_y_r = -0.03
			eye_sy = 1.25
			pupil_s = 0.55
			curve_l = -0.9
			curve_r = -0.9
			mouth_w = 1.5
			mouth_open = 2.8
		_:
			pass
	if _talk_time > 0.0:
		_talk_time = maxf(_talk_time - delta, 0.0)
		var flap: float = absf(sin(_time * 17.0)) * (0.8 + 0.4 * sin(_time * 5.3))
		mouth_open += 0.4 + flap * 1.6

	_brow_l.rotation.z = lerpf(_brow_l.rotation.z, brow_ang_l, k)
	_brow_r.rotation.z = lerpf(_brow_r.rotation.z, -brow_ang_r, k)
	_brow_l.position.y = lerpf(_brow_l.position.y, BROW_Y + brow_y_l, k)
	_brow_r.position.y = lerpf(_brow_r.position.y, BROW_Y + brow_y_r, k)
	var es: float = lerpf(_eye_l.scale.y, eye_sy, k)
	_eye_l.scale = Vector3(1.0, es, 1.0)
	_eye_r.scale = Vector3(1.0, es, 1.0)
	var ps: float = lerpf(_pupil_l.scale.x, pupil_s, k)
	_pupil_l.scale = Vector3(ps, ps, 1.0)
	_pupil_r.scale = Vector3(ps, ps, 1.0)
	var mo: float = 1.0 + mouth_open * 1.2
	var mk: float = clampf(delta * 20.0, 0.0, 1.0)
	var my: float = lerpf(_mouth_center.scale.y, mo, mk)
	var mw: float = lerpf(_mouth_center.scale.x, mouth_w, k)
	_mouth_center.scale = Vector3(mw, my, 1.0)
	_mouth_cl.position.x = 0.05 * mw
	_mouth_cr.position.x = -0.05 * mw
	_mouth_cl.rotation.z = lerpf(_mouth_cl.rotation.z, curve_l * 0.7, k)
	_mouth_cr.rotation.z = lerpf(_mouth_cr.rotation.z, -curve_r * 0.7, k)
	if _mask != null:
		_mask.scale = MASK_SCALE * Vector3(1.0, 1.0 + (my - 1.0) * 0.03, 1.0)


func _default_pose(a: float, expr: String) -> String:
	if _walking:
		if _mood_walk == "angry":
			return "walk_angry"
		return "walk"
	if expr == "happy" or expr == "calm":
		return "rest"
	if expr == "smug":
		return "crossed"
	if a > 0.78:
		return "fists"
	if a > 0.4:
		return "crossed"
	return "rest"


## Returns the Euler rotation of an arm. Values are authored for the +X (left) arm
## and mirrored (y, z negated) for the -X arm unless returned early.
func _arm_target(pose: String, is_left: bool) -> Vector3:
	var s: float = 1.0 if is_left else -1.0
	var v: Vector3 = Vector3(0.0, 0.0, 0.08)
	match pose:
		"walk":
			v = Vector3(-sin(_walk_phase) * 0.45 * s, 0.0, 0.1)
		"walk_angry":
			v = Vector3(-sin(_walk_phase) * 0.7 * s, 0.0, 0.3)
		"fists":
			v = Vector3(-0.25, 0.0, 0.38 + 0.05 * sin(_time * 8.0 + s))
		"crossed":
			if is_left:
				return Vector3(-1.2, -1.0, 0.0)
			return Vector3(-1.35, 1.0, 0.0)
		"up":
			v = Vector3(0.0, 0.0, 2.6 + 0.18 * sin(_time * 22.0 + s))
		"point":
			if is_left:
				return Vector3(-1.45, -0.12, 0.0)
			v = Vector3(-0.2, 0.0, 0.35)
		"cheer":
			v = Vector3(0.0, 0.0, 1.0 + 0.2 * sin(_time * 10.0))
		"drop":
			v = Vector3(0.05, 0.0, 0.02)
		_:
			v = Vector3(0.0, 0.0, 0.08)
	return Vector3(v.x, v.y * s, v.z * s)


# ---------------------------------------------------------------- construction helpers

func _node(parent: Node3D, pos: Vector3) -> Node3D:
	var n: Node3D = Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _mat(c: Color, rough: float = 0.7) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var bm: BoxMesh = BoxMesh.new()
	bm.size = sz
	return _mesh(parent, bm, pos, mat)


func _sphere(parent: Node3D, r: float, pos: Vector3, mat: Material, seg: int = 16) -> MeshInstance3D:
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = seg
	sm.rings = maxi(int(float(seg) * 0.5), 4)
	return _mesh(parent, sm, pos, mat)


func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var cm: CylinderMesh = CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = 16
	cm.rings = 1
	return _mesh(parent, cm, pos, mat)


func _capsule(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var cp: CapsuleMesh = CapsuleMesh.new()
	cp.radius = r
	cp.height = maxf(h, r * 2.0)
	cp.radial_segments = 16
	cp.rings = 6
	return _mesh(parent, cp, pos, mat)


func _torus(parent: Node3D, inner: float, outer: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var tm: TorusMesh = TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 24
	tm.ring_segments = 8
	return _mesh(parent, tm, pos, mat)


# ---------------------------------------------------------------- body construction

func _build_body() -> void:
	_skin_mat = _mat(_skin, 0.6)
	_skin_mat.emission_enabled = true
	_skin_mat.emission = Color(0.0, 0.0, 0.0)
	var cloth: StandardMaterial3D = _mat(_body_color, 0.75)
	var pants_c: Color = _body_color.darkened(0.55).lerp(Color(0.18, 0.2, 0.28), 0.5)
	var pants: StandardMaterial3D = _mat(pants_c, 0.8)
	var shoe: StandardMaterial3D = _mat(Color(0.12, 0.1, 0.1), 0.5)
	var hair_m: StandardMaterial3D = _mat(_hair_color, 0.65)
	var trim: StandardMaterial3D = _mat(_body_color.lightened(0.45), 0.7)

	_hop = _node(self, Vector3.ZERO)
	_body_pivot = _node(_hop, Vector3.ZERO)
	_figure = _node(_body_pivot, Vector3.ZERO)
	_figure.scale = Vector3(_height, _height, _height)

	# legs (pivot at the hip)
	var hip_y: float = 0.64
	var leg_x: float = 0.095 * _bw
	_leg_l = _node(_figure, Vector3(leg_x, hip_y, 0.0))
	_leg_r = _node(_figure, Vector3(-leg_x, hip_y, 0.0))
	var legs: Array[Node3D] = [_leg_l, _leg_r]
	for lg in legs:
		_capsule(lg, 0.08, 0.62, Vector3(0.0, -0.3, 0.0), pants)
		_box(lg, Vector3(0.14, 0.08, 0.24), Vector3(0.0, -0.6, 0.04), shoe)

	# pelvis + belt
	var pelvis: MeshInstance3D = _cyl(_figure, 0.19, 0.17, 0.22, Vector3(0.0, 0.7, 0.0), pants)
	pelvis.scale = Vector3(_bw, 1.0, _bw * 0.85)
	var belt: MeshInstance3D = _cyl(_figure, 0.195, 0.195, 0.05, Vector3(0.0, 0.8, 0.0), _mat(Color(0.12, 0.1, 0.08), 0.4))
	belt.scale = Vector3(_bw, 1.0, _bw * 0.85)

	# torso
	_torso = _node(_figure, Vector3(0.0, 0.99, 0.0))
	_torso_base_scale = Vector3(1.0, 1.0, 0.85)
	_torso.scale = _torso_base_scale
	_capsule(_torso, 0.2 * _bw, 0.64, Vector3.ZERO, cloth)
	if _bw > 1.1:
		_sphere(_torso, 0.2 * _bw * 0.85, Vector3(0.0, -0.08, 0.07), cloth, 20)
	var collar: MeshInstance3D = _torus(_torso, 0.055, 0.1, Vector3(0.0, 0.29, 0.0), trim)
	collar.scale = Vector3(1.0, 1.4, 1.0)
	for b in range(3):
		_sphere(_torso, 0.015, Vector3(0.0, 0.12 - float(b) * 0.11, 0.2 * _bw + 0.005), trim, 8)

	# arms (pivot at the shoulder, hanging along -Y)
	var sh_x: float = 0.2 * _bw + 0.06
	_arm_l = _node(_figure, Vector3(sh_x, 1.2, 0.0))
	_arm_r = _node(_figure, Vector3(-sh_x, 1.2, 0.0))
	var arms: Array[Node3D] = [_arm_l, _arm_r]
	for am in arms:
		_sphere(am, 0.075, Vector3.ZERO, cloth, 12)
		_capsule(am, 0.065, 0.52, Vector3(0.0, -0.25, 0.0), cloth)
		_cyl(am, 0.068, 0.068, 0.05, Vector3(0.0, -0.46, 0.0), trim)
		_sphere(am, 0.075, Vector3(0.0, -0.55, 0.0), _skin_mat, 12)

	# neck + head
	_cyl(_figure, 0.065, 0.07, 0.12, Vector3(0.0, 1.31, 0.0), _skin_mat)
	_head_pivot = _node(_figure, Vector3(0.0, 1.3, 0.0))
	_head = _node(_head_pivot, Vector3(0.0, 0.21, 0.0))
	_sphere(_head, 0.22, Vector3.ZERO, _skin_mat, 32)
	if _hair != "long":
		for i in range(2):
			var sx: float = 1.0 if i == 0 else -1.0
			var ear: MeshInstance3D = _sphere(_head, 0.05, Vector3(sx * 0.215, -0.01, 0.0), _skin_mat, 12)
			ear.scale = Vector3(0.6, 1.0, 1.0)
	_nose = _sphere(_head, 0.035, Vector3(0.0, -0.02, 0.215), _skin_mat, 12)

	_build_face()
	_build_hair(hair_m)
	_build_accessory()
	_build_anger_fx()


func _build_face() -> void:
	var white: StandardMaterial3D = _mat(Color(1.0, 1.0, 1.0), 0.3)
	white.emission_enabled = true
	white.emission = Color(1.0, 1.0, 1.0)
	white.emission_energy_multiplier = 0.25
	var black: StandardMaterial3D = _mat(Color(0.05, 0.04, 0.04), 0.2)
	var brow_m: StandardMaterial3D = _mat(_hair_color.darkened(0.3), 0.7)
	var mouth_m: StandardMaterial3D = _mat(Color(0.35, 0.06, 0.08), 0.5)

	# eyes
	_eye_l = _node(_head, Vector3(0.085, 0.03, 0.178))
	_eye_r = _node(_head, Vector3(-0.085, 0.03, 0.178))
	var eyes: Array[Node3D] = [_eye_l, _eye_r]
	for en in eyes:
		var w: MeshInstance3D = _sphere(en, 0.058, Vector3.ZERO, white, 16)
		w.scale = Vector3(1.0, 1.1, 0.5)
	_pupil_l = _node(_eye_l, Vector3(-0.008, -0.004, 0.026))
	_pupil_r = _node(_eye_r, Vector3(0.008, -0.004, 0.026))
	var pupils: Array[Node3D] = [_pupil_l, _pupil_r]
	for pn in pupils:
		var pm: MeshInstance3D = _sphere(pn, 0.031, Vector3.ZERO, black, 12)
		pm.scale = Vector3(1.0, 1.1, 0.45)
		_sphere(pn, 0.009, Vector3(0.01, 0.012, 0.013), white, 6)

	# eyebrows (pivot in the middle of each brow)
	_brow_l = _node(_head, Vector3(0.085, BROW_Y, 0.185))
	_brow_r = _node(_head, Vector3(-0.085, BROW_Y, 0.185))
	_box(_brow_l, Vector3(0.12, 0.032, 0.03), Vector3.ZERO, brow_m)
	_box(_brow_r, Vector3(0.12, 0.032, 0.03), Vector3.ZERO, brow_m)
	_brow_l.rotation.y = 0.35
	_brow_r.rotation.y = -0.35

	# mouth: centre bar + two corner pieces that tilt up (smile) or down (frown)
	_mouth = _node(_head, Vector3(0.0, -0.1, 0.195))
	_mouth_center = _box(_mouth, Vector3(0.1, 0.028, 0.03), Vector3.ZERO, mouth_m)
	_mouth_cl = _node(_mouth, Vector3(0.05, 0.0, 0.0))
	_mouth_cr = _node(_mouth, Vector3(-0.05, 0.0, 0.0))
	_box(_mouth_cl, Vector3(0.045, 0.024, 0.03), Vector3(0.018, 0.0, -0.004), mouth_m)
	_box(_mouth_cr, Vector3(0.045, 0.024, 0.03), Vector3(-0.018, 0.0, -0.004), mouth_m)
	_mouth_cl.rotation.y = 0.35
	_mouth_cr.rotation.y = -0.35


func _hair_top(m: Material) -> void:
	var top: MeshInstance3D = _sphere(_head, 0.235, Vector3(0.0, 0.18, -0.025), m, 24)
	top.scale = Vector3(0.85, 0.51, 1.0)


func _hair_back(m: Material) -> void:
	_sphere(_head, 0.225, Vector3(0.0, 0.04, -0.07), m, 24)


func _build_hair(m: StandardMaterial3D) -> void:
	match _hair:
		"bald":
			for i in range(2):
				var sx: float = 1.0 if i == 0 else -1.0
				var tuft: MeshInstance3D = _sphere(_head, 0.075, Vector3(sx * 0.19, 0.03, -0.07), m, 12)
				tuft.scale = Vector3(0.6, 0.9, 1.2)
			var back: MeshInstance3D = _sphere(_head, 0.12, Vector3(0.0, -0.02, -0.16), m, 16)
			back.scale = Vector3(1.6, 0.8, 0.6)
		"long":
			_hair_top(m)
			_hair_back(m)
			_box(_head, Vector3(0.42, 0.5, 0.12), Vector3(0.0, -0.15, -0.14), m)
			for i in range(2):
				var sx2: float = 1.0 if i == 0 else -1.0
				_box(_head, Vector3(0.07, 0.42, 0.16), Vector3(sx2 * 0.2, -0.08, -0.03), m)
		"perm":
			_hair_top(m)
			_hair_back(m)
			for row in range(4):
				var el: float = deg_to_rad(80.0 - float(row) * 25.0)
				var count: int = 1 if row == 0 else 6 + row * 3
				for c in range(count):
					var az: float = TAU * float(c) / float(count)
					if row >= 2 and absf(wrapf(az, -PI, PI)) < deg_to_rad(65.0 + 25.0 * float(row - 2)):
						continue
					var dirv: Vector3 = Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az))
					_sphere(_head, 0.075, dirv * 0.215 + Vector3(0.0, 0.03, -0.01), m, 10)
		"cap":
			_hair_back(m)
			var cap_c: Color = Color.from_hsv(fmod(_body_color.h + 0.5, 1.0), 0.7, 0.8)
			var cm: StandardMaterial3D = _mat(cap_c, 0.6)
			var dome: MeshInstance3D = _sphere(_head, 0.232, Vector3(0.0, 0.17, -0.01), cm, 24)
			dome.scale = Vector3(1.0, 0.55, 1.0)
			var brim: MeshInstance3D = _box(_head, Vector3(0.26, 0.022, 0.15), Vector3(0.0, 0.155, 0.235), cm)
			brim.rotation.x = 0.12
			_sphere(_head, 0.025, Vector3(0.0, 0.3, -0.01), cm, 8)
		_:
			_hair_top(m)
			_hair_back(m)


func _build_accessory() -> void:
	var dark: StandardMaterial3D = _mat(Color(0.08, 0.08, 0.1), 0.3)
	match _accessory:
		"glasses":
			var lens_m: StandardMaterial3D = _mat(Color(0.8, 0.9, 1.0, 0.25), 0.05)
			lens_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			for i in range(2):
				var sx: float = 1.0 if i == 0 else -1.0
				var ring: MeshInstance3D = _torus(_head, 0.05, 0.064, Vector3(sx * 0.085, 0.03, 0.222), dark)
				ring.rotation.x = PI * 0.5
				var lens: MeshInstance3D = _cyl(_head, 0.052, 0.052, 0.004, Vector3(sx * 0.085, 0.03, 0.222), lens_m)
				lens.rotation.x = PI * 0.5
				_box(_head, Vector3(0.01, 0.012, 0.2), Vector3(sx * 0.15, 0.04, 0.12), dark)
			_box(_head, Vector3(0.045, 0.012, 0.012), Vector3(0.0, 0.035, 0.225), dark)
		"mask":
			var mm: StandardMaterial3D = _mat(Color(0.96, 0.97, 1.0), 0.8)
			_mask = _sphere(_head, 0.15, Vector3(0.0, -0.075, 0.13), mm, 20)
			_mask.scale = MASK_SCALE
			_mouth.visible = false
			if _nose != null:
				_nose.visible = false
			for i in range(2):
				var sx3: float = 1.0 if i == 0 else -1.0
				_box(_head, Vector3(0.012, 0.012, 0.14), Vector3(sx3 * 0.19, -0.03, 0.05), mm)
		"headphones":
			var hm: StandardMaterial3D = _mat(Color(0.1, 0.85, 0.9), 0.35)
			for i in range(2):
				var sx4: float = 1.0 if i == 0 else -1.0
				var cup: MeshInstance3D = _cyl(_head, 0.075, 0.075, 0.06, Vector3(sx4 * 0.225, 0.0, -0.01), hm)
				cup.rotation.z = PI * 0.5
				var pad: MeshInstance3D = _cyl(_head, 0.06, 0.06, 0.02, Vector3(sx4 * 0.258, 0.0, -0.01), dark)
				pad.rotation.z = PI * 0.5
			for j in range(7):
				var ang: float = deg_to_rad(15.0 + 150.0 * float(j) / 6.0)
				var seg: MeshInstance3D = _box(_head, Vector3(0.035, 0.1, 0.05), Vector3(cos(ang) * 0.255, 0.03 + sin(ang) * 0.27, -0.01), dark)
				seg.rotation.z = ang
		"bag":
			var bm: StandardMaterial3D = _mat(Color(0.97, 0.97, 0.95), 0.6)
			var bag: Node3D = _node(_arm_r, Vector3(-0.05, -0.6, 0.0))
			_box(bag, Vector3(0.24, 0.26, 0.12), Vector3(0.0, -0.2, 0.0), bm)
			_box(bag, Vector3(0.245, 0.05, 0.125), Vector3(0.0, -0.15, 0.0), _mat(Color(0.1, 0.6, 0.3), 0.6))
			_box(bag, Vector3(0.012, 0.09, 0.012), Vector3(0.06, -0.04, 0.0), bm)
			_box(bag, Vector3(0.012, 0.09, 0.012), Vector3(-0.06, -0.04, 0.0), bm)
			_cyl(bag, 0.03, 0.03, 0.14, Vector3(0.05, -0.05, 0.0), _mat(Color(1.0, 0.55, 0.1), 0.3))
		_:
			pass


func _build_anger_fx() -> void:
	var red: StandardMaterial3D = _mat(Color(0.9, 0.05, 0.05), 0.5)
	red.emission_enabled = true
	red.emission = Color(1.0, 0.1, 0.05)
	red.emission_energy_multiplier = 0.8
	# anime-style anger mark: four corner pieces pointing at the centre
	_vein = _node(_head, Vector3(0.13, 0.17, 0.15))
	_vein.rotation = Vector3(-0.5, 0.7, 0.0)
	for ix in range(2):
		var sx: float = 1.0 if ix == 0 else -1.0
		for iy in range(2):
			var sy: float = 1.0 if iy == 0 else -1.0
			_box(_vein, Vector3(0.04, 0.016, 0.016), Vector3(sx * 0.035, sy * 0.015, 0.0), red)
			_box(_vein, Vector3(0.016, 0.04, 0.016), Vector3(sx * 0.015, sy * 0.035, 0.0), red)
	_vein.visible = false
	# steam puffs from both sides of the head
	for i in range(2):
		var sxs: float = 1.0 if i == 0 else -1.0
		var p: CPUParticles3D = CPUParticles3D.new()
		p.position = Vector3(sxs * 0.16, 0.22, -0.02)
		p.amount = 16
		p.lifetime = 0.9
		p.local_coords = false
		var sm: SphereMesh = SphereMesh.new()
		sm.radius = 0.045
		sm.height = 0.09
		sm.radial_segments = 8
		sm.rings = 4
		var pm: StandardMaterial3D = StandardMaterial3D.new()
		pm.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.vertex_color_use_as_albedo = true
		sm.material = pm
		p.mesh = sm
		p.direction = Vector3(sxs * 0.5, 1.0, 0.0)
		p.spread = 18.0
		p.initial_velocity_min = 0.6
		p.initial_velocity_max = 1.1
		p.gravity = Vector3(0.0, 0.4, 0.0)
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.4
		var grad: Gradient = Gradient.new()
		grad.set_color(0, Color(1.0, 1.0, 1.0, 0.9))
		grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		p.color_ramp = grad
		p.emitting = false
		_head.add_child(p)
		_steam.append(p)
