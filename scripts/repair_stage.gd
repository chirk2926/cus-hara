extends "res://scripts/backdrop_stage.gd"
## 筐体の前の場面（要件#99）。メダルゲームの筐体1台とそのまわり／ビデオゲームコーナー（背景の場面を流用）。
## repair_scene.gd が自分だけの 3D の世界（SubViewport）に置いて使う。カメラの位置は cam_pos / cam_look。
## 動き（扉を開ける・レールを叩く・分解する・補充・抽選機の修理・パネルを開ける・コネクタを差し直す）は、
## ここの関数が Tween で動かす。どれも await できる（終わるまで待つ）。

var parts: Dictionary = {}
var cam_pos: Vector3 = Vector3(0.0, 1.35, 1.55)
var cam_look: Vector3 = Vector3(0.0, 1.05, 0.0)
var _pusher: Node3D = null
var _drum: Node3D = null
var _drum_speed: float = 0.0
var _medal_mat: StandardMaterial3D = null


func build_repair(kind: String, problem: String) -> void:
	match kind:
		"medal":
			_build_medal_repair(problem)
		"video_talk":
			_build_video_talk(problem)
		_:
			_build_video_repair()


func _process(delta: float) -> void:
	super(delta)
	if _pusher != null:
		_pusher.position.z = 0.05 + 0.07 * sin(_time * 1.6)
	if _drum != null:
		_drum.rotation.x += delta * _drum_speed


# ---------------------------------------------------------------- メダルゲームの筐体（プッシャー）

func _build_medal_repair(problem: String) -> void:
	_env(Color(0.05, 0.02, 0.03), Color(0.9, 0.7, 0.55), 0.6, 0.8)
	_room(Color(0.45, 0.06, 0.08), Color(0.2, 0.06, 0.09), Color(0.08, 0.04, 0.05), 7.0, 5.0)
	_medal_mat = _mat(Color(0.95, 0.75, 0.25), 0.2, 0.25, 0.9)
	# まわり: 左右にスロット、奥に看板（ぼんやり見える程度）
	_slot(Vector3(-1.5, 0.0, -0.4), 0.15, 1)
	_slot(Vector3(1.5, 0.0, -0.4), -0.15, 4)
	_label(self, "MEDAL GAME", Vector3(0.0, 2.6, -2.9), 150, Color(1.0, 0.85, 0.3))
	_omni(Vector3(0.0, 2.4, 1.2), Color(1.0, 0.85, 0.7), 1.6, 5.0)
	_omni(Vector3(-1.2, 2.0, -0.5), Color(1.0, 0.4, 0.45), 0.8, 4.0)
	var m: Node3D = _node(self, Vector3.ZERO)
	parts["machine"] = m
	var body: StandardMaterial3D = _mat(Color(0.78, 0.12, 0.15), 0.0, 0.4)
	# 下の箱（前の扉の中に払い出しのレールとホッパー）。中が見えるように、板で組んだ空の箱にする
	_box(m, Vector3(0.05, 0.95, 0.9), Vector3(-0.575, 0.475, 0.0), body)
	_box(m, Vector3(0.05, 0.95, 0.9), Vector3(0.575, 0.475, 0.0), body)
	_box(m, Vector3(1.2, 0.95, 0.05), Vector3(0.0, 0.475, -0.425), body)
	_box(m, Vector3(1.2, 0.05, 0.9), Vector3(0.0, 0.025, 0.0), body)
	_box(m, Vector3(1.2, 0.05, 0.9), Vector3(0.0, 0.93, 0.0), body)
	_omni(Vector3(0.0, 0.6, 0.3), Color(1.0, 0.95, 0.85), 0.6, 1.2)   # 中を照らす小さな明かり
	# 上のケース（ガラス）と遊ぶ面
	_box(m, Vector3(1.2, 0.08, 0.9), Vector3(0.0, 0.99, 0.0), _mat(Color(0.25, 0.08, 0.1)))
	_box(m, Vector3(1.2, 0.75, 0.9), Vector3(0.0, 1.41, 0.0), _glass())
	_box(m, Vector3(1.24, 0.12, 0.94), Vector3(0.0, 1.84, 0.0), _mat(Color(0.95, 0.75, 0.25), 0.6, 0.3, 0.8))
	_label(m, "MEDAL PUSHER", Vector3(0.0, 1.84, 0.475), 70, Color(0.3, 0.05, 0.05), 0.0035)
	var field: MeshInstance3D = _box(m, Vector3(1.1, 0.02, 0.8), Vector3(0.0, 1.06, 0.0), _mat(Color(0.15, 0.35, 0.55), 0.2))
	field.rotation.x = 0.06
	_pusher = _node(m, Vector3(0.0, 1.1, 0.05))
	_box(_pusher, Vector3(1.0, 0.06, 0.35), Vector3(0.0, 0.0, -0.2), _mat(Color(0.85, 0.85, 0.9), 0.1, 0.3, 0.7))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(55):
		_cyl(m, 0.035, 0.035, 0.01, Vector3(rng.randf_range(-0.48, 0.48), 1.08 + rng.randf_range(0.0, 0.03), rng.randf_range(-0.1, 0.35)), _medal_mat)
	# 抽選機（ケースの上の左。球の入ったドラム）
	var lot: Node3D = _node(m, Vector3(-0.35, 1.5, -0.25))
	parts["lottery"] = lot
	_cyl(lot, 0.14, 0.14, 0.04, Vector3(0.0, -0.12, 0.0), _mat(Color(0.3, 0.3, 0.35), 0.0, 0.3, 0.8))
	_drum = _node(lot, Vector3.ZERO)
	_cyl(_drum, 0.12, 0.12, 0.16, Vector3.ZERO, _glass(), Vector3(0.0, 0.0, PI * 0.5))
	for k in range(6):
		var a: float = TAU * float(k) / 6.0
		_sph_ball(_drum, Vector3(rng.randf_range(-0.05, 0.05), cos(a) * 0.06, sin(a) * 0.06), Color.from_hsv(float(k) / 6.0, 0.8, 1.0))
	_drum_speed = 0.0 if problem == "lottery" else 3.0
	var lamp: MeshInstance3D = _box(lot, Vector3(0.18, 0.05, 0.02), Vector3(0.0, 0.18, 0.12), _mat(Color(1.0, 0.2, 0.15), 2.0) if problem == "lottery" else _mat(Color(0.3, 1.0, 0.4), 1.5))
	parts["lot_lamp"] = lamp
	# 前の扉（左の辺でひらく）。中: ホッパー（メダルの箱）と、払い出しのレール（3つの部品）
	var hinge: Node3D = _node(m, Vector3(-0.55, 0.0, 0.451))
	parts["door"] = hinge
	var door: MeshInstance3D = _box(hinge, Vector3(1.1, 0.8, 0.03), Vector3(0.55, 0.47, 0.0), _mat(Color(0.65, 0.1, 0.12), 0.0, 0.35))
	_box(door, Vector3(0.08, 0.05, 0.03), Vector3(0.45, 0.0, 0.03), _mat(Color(0.8, 0.8, 0.85), 0.0, 0.3, 0.9))   # 取っ手
	_box(door, Vector3(0.12, 0.12, 0.012), Vector3(-0.38, 0.22, 0.02), _mat(Color(0.9, 0.85, 0.3), 0.3))       # 鍵穴の板
	var inside: StandardMaterial3D = _mat(Color(0.12, 0.1, 0.1))
	_box(m, Vector3(1.1, 0.8, 0.02), Vector3(0.0, 0.47, -0.38), inside)
	var hopper: Node3D = _node(m, Vector3(0.25, 0.72, 0.2))
	parts["hopper"] = hopper
	_box(hopper, Vector3(0.36, 0.22, 0.3), Vector3.ZERO, _mat(Color(0.55, 0.55, 0.6), 0.0, 0.3, 0.8))
	var fill: Node3D = _node(hopper, Vector3(0.0, 0.0, 0.0))
	parts["hopper_fill"] = fill
	for i2 in range(0 if problem == "empty" else 14):
		_cyl(fill, 0.032, 0.032, 0.01, Vector3(rng.randf_range(-0.12, 0.12), 0.08 + rng.randf_range(0.0, 0.04), rng.randf_range(-0.1, 0.1)), _medal_mat)
	var rail: Array = []
	for j in range(3):
		var seg: Node3D = _node(m, Vector3(0.05 - 0.2 * float(j), 0.55 - 0.12 * float(j), 0.25))
		var sm: MeshInstance3D = _box(seg, Vector3(0.22, 0.04, 0.12), Vector3.ZERO, _mat(Color(0.75, 0.75, 0.8), 0.0, 0.25, 0.85))
		sm.rotation.z = 0.5
		_box(seg, Vector3(0.03, 0.03, 0.03), Vector3(0.08, 0.05, 0.05), _mat(Color(0.3, 0.3, 0.35), 0.0, 0.3, 0.9))   # ネジ
		rail.append(seg)
	parts["rail"] = rail
	var jam: Node3D = _node(rail[1], Vector3(0.0, 0.04, 0.0))
	parts["jam"] = jam
	if problem == "jam":
		for k2 in range(5):
			var md: MeshInstance3D = _cyl(jam, 0.032, 0.032, 0.01, Vector3(-0.04 + 0.02 * float(k2), 0.01 * float(k2), 0.0), _medal_mat)
			md.rotation = Vector3(0.6 * float(k2), 0.0, 1.0)
	# 受け皿（払い出し口）
	_box(m, Vector3(0.5, 0.06, 0.18), Vector3(-0.25, 0.12, 0.54), _mat(Color(0.2, 0.2, 0.22), 0.0, 0.4, 0.6))
	parts["tray"] = Vector3(-0.25, 0.2, 0.54)
	# 右の横の補充口（小さい扉）
	var side: Node3D = _node(m, Vector3(0.601, 0.75, 0.15))
	parts["hatch"] = side
	_box(side, Vector3(0.02, 0.16, 0.22), Vector3(0.0, 0.0, -0.11), _mat(Color(0.95, 0.75, 0.25), 0.3, 0.3, 0.8))
	_label(m, "補充口" if GameSettings.language == "ja" else ("补充口" if GameSettings.language == "zh" else ("보충구" if GameSettings.language == "ko" else "REFILL")), Vector3(0.62, 0.9, 0.05), 40, Color(1.0, 0.95, 0.8), 0.003, 90.0)
	cam_pos = Vector3(0.35, 1.25, 1.6)
	cam_look = Vector3(0.0, 0.8, 0.0)


func _sph_ball(parent: Node3D, pos: Vector3, c: Color) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var sm: SphereMesh = SphereMesh.new()
	sm.radius = 0.025
	sm.height = 0.05
	mi.mesh = sm
	mi.material_override = _mat(c, 0.5)
	mi.position = pos
	parent.add_child(mi)


# ---------------------------------------------------------------- ビデオゲームの台（背景のコーナーを流用）

func _build_video_repair() -> void:
	_build_video(false)
	# 手前の通路に、対応する台を1台。操作パネルは手前の辺でひらく
	var n: Node3D = _node(self, Vector3(0.0, 0.0, 0.2))
	parts["cab"] = n
	_box(n, Vector3(0.8, 1.15, 0.9), Vector3(0.0, 0.575, 0.0), _mat(Color(0.92, 0.92, 0.95), 0.0, 0.5))
	_box(n, Vector3(0.8, 0.5, 0.6), Vector3(0.0, 1.45, -0.15), _mat(Color(0.75, 0.75, 0.8), 0.0, 0.5))
	var scr: MeshInstance3D = _box(n, Vector3(0.66, 0.42, 0.02), Vector3(0.0, 1.42, 0.16), _mat(Color(0.2, 0.6, 1.0), 1.4), Vector3(-0.35, 0.0, 0.0))
	_label(scr, "INSERT COIN", Vector3(0.0, 0.0, 0.015), 32, Color(1.0, 1.0, 0.6), 0.0016)
	# 操作パネル（ヒンジは奥の辺）
	var hinge: Node3D = _node(n, Vector3(0.0, 1.15, 0.24))
	hinge.rotation.x = 0.25
	parts["panel"] = hinge
	var panel: MeshInstance3D = _box(hinge, Vector3(0.8, 0.05, 0.38), Vector3(0.0, 0.0, 0.19), _mat(Color(0.12, 0.12, 0.15)))
	_cyl(panel, 0.012, 0.012, 0.12, Vector3(-0.22, 0.07, 0.0), _mat(Color(0.1, 0.1, 0.1)))
	_cyl(panel, 0.035, 0.035, 0.03, Vector3(-0.22, 0.14, 0.0), _mat(Color(0.9, 0.15, 0.15), 0.4))
	var btns: Array = []
	for b in range(4):
		var bm: MeshInstance3D = _cyl(panel, 0.03, 0.03, 0.03, Vector3(0.02 + 0.08 * float(b), 0.035, -0.04 + 0.05 * float(b % 2)), _mat(Color.from_hsv(float(b) / 4.0, 0.7, 1.0), 0.6))
		btns.append(bm)
	parts["buttons"] = btns
	# パネルの裏の配線とコネクタ（パネルを開けると見える）
	var conn: Node3D = _node(n, Vector3(0.12, 1.07, 0.3))
	parts["connector"] = conn
	_box(conn, Vector3(0.06, 0.03, 0.04), Vector3.ZERO, _mat(Color(0.95, 0.95, 0.9)))
	_box(n, Vector3(0.4, 0.01, 0.01), Vector3(-0.1, 1.06, 0.3), _mat(Color(0.9, 0.2, 0.2)))
	_box(n, Vector3(0.4, 0.01, 0.01), Vector3(-0.1, 1.05, 0.31), _mat(Color(0.2, 0.3, 0.9)))
	_stool(Vector3(0.0, 0.0, 1.0), Color(0.15, 0.15, 0.2))
	_omni(Vector3(0.0, 2.3, 1.2), Color(0.8, 0.85, 1.0), 1.2, 4.0)
	cam_pos = Vector3(0.45, 1.6, 1.25)
	cam_look = Vector3(0.0, 1.1, 0.25)


## 迷惑なお客さん（台パン・大声）と話す場面。本人は立ち上がってこちらを向く
func _build_video_talk(problem: String) -> void:
	_build_video(false)
	var look: Dictionary = {"body_color": "#5a5f2a", "skin_color": "#e8b890", "hair_color": "#2a2a2a", "hair": "spiky",
		"build": "big", "accessory": "headphones", "height": 1.0} if problem == "slam" else {"body_color": "#a5463a", "skin_color": "#f2cba8",
		"hair_color": "#c08040", "hair": "mohawk", "build": "normal", "accessory": "sunglasses", "height": 1.02}
	var p: Node3D = _person(look, Vector3(0.0, 0.0, -1.5), 0.0, "")
	p.call("set_anger", 0.7)
	parts["offender"] = p
	if problem == "slam":
		_rage_label = _label(self, "ドンッ！" if GameSettings.language == "ja" else ("咚！" if GameSettings.language == "zh" else ("쾅!" if GameSettings.language == "ko" else "BANG!")), Vector3(0.8, 2.0, -1.9), 90, Color(1.0, 0.85, 0.2))
	else:
		_rage_label = _label(self, "うおおおっ！" if GameSettings.language == "ja" else ("哇啊啊！" if GameSettings.language == "zh" else ("우오오오!" if GameSettings.language == "ko" else "WOOOO!")), Vector3(0.7, 2.05, -1.8), 90, Color(1.0, 0.45, 0.3))
	cam_pos = Vector3(0.0, 1.55, 0.6)
	cam_look = Vector3(0.0, 1.35, -1.5)


## 迷惑なお客さんが落ち着いた（「ドンッ！」を消す）
func calm_offender() -> void:
	if _rage_label != null:
		_rage_label.queue_free()
		_rage_label = null
	var p: Variant = parts.get("offender", null)
	if p != null and is_instance_valid(p):
		(p as Node3D).call("set_anger", 0.1)


# ---------------------------------------------------------------- 動き（Tween。await できる）

func _tw() -> Tween:
	return create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func open_door() -> void:
	var d: Node3D = parts.get("door", null)
	if d == null:
		return
	var t: Tween = _tw()
	t.tween_property(d, "rotation:y", deg_to_rad(-105.0), 0.8)
	await t.finished


func open_panel() -> void:
	var p: Node3D = parts.get("panel", null)
	if p == null:
		return
	var t: Tween = _tw()
	t.tween_property(p, "rotation:x", -1.1, 0.7)
	await t.finished


## レールを叩く: 小刻みにゆれて、詰まったメダルが落ちる
func hit_rail(fixes: bool) -> void:
	var rail: Array = parts.get("rail", [])
	if rail.is_empty():
		return
	var seg: Node3D = rail[1]
	var base: Vector3 = seg.position
	for i in range(3):
		var t: Tween = create_tween()
		t.tween_property(seg, "position", base + Vector3(0.0, -0.015, 0.0), 0.05)
		t.tween_property(seg, "position", base, 0.08)
		await t.finished
	if fixes:
		await _drop_jam()


## レールを分解して直す: 部品を外して並べ、戻す
func disassemble_rail(fixes: bool) -> void:
	var rail: Array = parts.get("rail", [])
	var bases: Array = []
	for seg in rail:
		bases.append((seg as Node3D).position)
	var t: Tween = _tw().set_parallel(true)
	for i in rail.size():
		t.tween_property(rail[i], "position", (bases[i] as Vector3) + Vector3(0.0, 0.0, 0.28 + 0.06 * float(i)), 0.6)
	await t.finished
	if fixes:
		await _drop_jam()
	var t2: Tween = _tw().set_parallel(true)
	for i in rail.size():
		t2.tween_property(rail[i], "position", bases[i], 0.6)
	await t2.finished


func _drop_jam() -> void:
	var jam: Node3D = parts.get("jam", null)
	if jam == null:
		return
	var t: Tween = _tw()
	t.tween_property(jam, "position:y", -0.5, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished
	jam.visible = false
	await payout()


## メダルを補充する: 横の補充口を開けて、メダルがホッパーに入る
func refill(fixes: bool) -> void:
	var h: Node3D = parts.get("hatch", null)
	if h != null:
		var t: Tween = _tw()
		t.tween_property(h, "rotation:y", deg_to_rad(80.0), 0.4)
		await t.finished
	var fill: Node3D = parts.get("hopper_fill", null)
	if fill != null:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		for i in range(12):
			var md: MeshInstance3D = _cyl(fill, 0.032, 0.032, 0.01, Vector3(rng.randf_range(-0.12, 0.12), 0.35, rng.randf_range(-0.1, 0.1)), _medal_mat)
			var t2: Tween = create_tween()
			t2.tween_property(md, "position:y", 0.08 + rng.randf_range(0.0, 0.05), 0.25)
			await get_tree().create_timer(0.05).timeout
	if h != null:
		var t3: Tween = _tw()
		t3.tween_property(h, "rotation:y", 0.0, 0.3)
		await t3.finished
	if fixes:
		await payout()


## 抽選機を修理する: ランプが緑になり、ドラムが回りだす
func repair_lottery(fixes: bool) -> void:
	var lot: Node3D = parts.get("lottery", null)
	if lot == null:
		return
	var t: Tween = create_tween()
	t.tween_property(lot, "position:y", lot.position.y + 0.02, 0.1)
	t.tween_property(lot, "position:y", lot.position.y, 0.1)
	await t.finished
	if fixes:
		var lamp: MeshInstance3D = parts.get("lot_lamp", null)
		if lamp != null:
			lamp.material_override = _mat(Color(0.3, 1.0, 0.4), 1.5)
		_drum_speed = 3.0


## 受け皿にメダルが出てくる
func payout() -> void:
	var m: Node3D = parts.get("machine", null)
	if m == null:
		return
	var at: Vector3 = parts.get("tray", Vector3.ZERO)
	for i in range(8):
		var md: MeshInstance3D = _cyl(m, 0.032, 0.032, 0.01, at + Vector3(randf_range(-0.15, 0.15), 0.25, 0.0), _medal_mat)
		var t: Tween = create_tween()
		t.tween_property(md, "position:y", at.y - 0.05 + 0.01 * float(i % 3), 0.2)
		await get_tree().create_timer(0.04).timeout


## ボタンを確かめる: 1つずつ光らせる。dead は反応しないボタンの番号（-1 ならぜんぶ反応）
func test_button(i: int, works: bool) -> void:
	var btns: Array = parts.get("buttons", [])
	if i < 0 or i >= btns.size():
		return
	var b: MeshInstance3D = btns[i]
	var keep: Material = b.material_override
	b.material_override = _mat(Color(1.0, 1.0, 0.8), 3.0) if works else _mat(Color(0.2, 0.2, 0.2))
	var t: Tween = create_tween()
	t.tween_property(b, "position:y", b.position.y - 0.01, 0.06)
	t.tween_property(b, "position:y", b.position.y, 0.08)
	await t.finished
	await get_tree().create_timer(0.15).timeout
	b.material_override = keep


func reseat_connector() -> void:
	var c: Node3D = parts.get("connector", null)
	if c == null:
		return
	var base: Vector3 = c.position
	var t: Tween = _tw()
	t.tween_property(c, "position", base + Vector3(0.08, 0.04, 0.0), 0.3)
	t.tween_property(c, "position", base, 0.35)
	await t.finished
