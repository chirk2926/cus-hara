extends Node
## クレーンゲームの「台の調整」ミニゲーム（要件#37）。1人用のゲームセンターで、クレーンゲームのお客さんのときに使える。
##
## 流れ:
##   1. カメラが台の前へ移動する
##   2. 景品をクリックしてつかみ、ケースの中でドラッグして動かす（取り出し口に近いほど取りやすい）
##      アームの強さを変える（店の規定は 6 まで。それより上は「しれっと」の規定外）
##   3. 「この台で遊んでもらう」→ お客さんが遊ぶ。アームが動いて景品をつかみ、取れるか落とすか
##   4. 結果 {"result": "won" | "lost" | "cancelled", "cheat": bool, "moved": bool} を返し、カメラを戻す
##
## 取れる確率: 取り出し口からの距離と、アームの強さ（パワー設定）またはペイアウト率（確率設定）で決まる（_win_chance）。
## main.smoke（自動テスト）のときは、自動で景品を寄せて遊ぶ。
##
## 要件#55, #57 で足したこと:
##   - mode "adjust"（難易度を調整）: パワー設定 / 確率設定 を切り替えられる。確率設定のときはパワーは触れない。
##     確率設定: 景品原価 1,100円 / ペイアウト率 [10〜80]% = 1個あたりの目安。店全体の設定として保存され、
##     「取れない」クレームの出やすさ・お客さんが言う金額・売上・店舗レビューに効く（docs/SPEC.md 14節）。
##     テストプレイ（2回まで）: 今の設定で自分で遊んでみる。取れても景品はすぐ補充される。
##   - mode "move"（景品を取りやすい位置へ）: 景品を動かすだけ。設定は今の店の設定のまま。

const UI = preload("res://scripts/ui_kit.gd")
const Arcade = preload("res://scripts/arcade_stage.gd")

signal _done(result: Dictionary)

const POWER_LIMIT: int = 6       # 店の規定
const POWER_DEFAULT: int = 4
const TIME_LIMIT: float = 40.0   # 調整にかけられる時間（秒。テストプレイの間は止まる）
const TEST_PLAYS: int = 2        # テストプレイの回数
## 確率設定（要件#55）。サーバーの server/src/scenarios.ts と同じ値
const PRIZE_COST: int = 1100
const PAYOUT_MIN: int = 10
const PAYOUT_MAX: int = 80
const PAYOUT_DEFAULT: int = 30

var main = null
var arcade = null

var _cr: Dictionary = {}
var _root: Node3D = null
var _prizes: Array = []
var _held: Node3D = null
var _hover: Node3D = null
var _target: Node3D = null       # お客さんが狙う景品（最後に動かした景品。なければ取り出し口に一番近い景品）
var _power: int = POWER_DEFAULT
var _moved: bool = false
var _phase: String = ""          # "adjust" | "test" | "play" | ""
var _mode: String = "adjust"     # "adjust"（難易度を調整）| "move"（景品を取りやすい位置へ）
var _customer: Dictionary = {}
var _prob: bool = false          # 確率設定が有効
var _payout: int = PAYOUT_DEFAULT
var _tests_left: int = TEST_PLAYS
var _tested: bool = false
var _power_box: Control = null
var _prob_box: Control = null
var _slider: HSlider = null
var _cost_label: Label = null
var _test_btn: Button = null
var _test_label: Label = null
var _time_left: float = 0.0
var _ui: Control = null
var _time_label: Label = null
var _power_label: Label = null
var _chance_label: Label = null
var _hint: Label = null
var _play_btn: Button = null
var _marker: MeshInstance3D = null
var _bob: float = 0.0


## opts: {"mode": "adjust" | "move", "customer": お客さんのデータ}
func setup(main_node, arcade_node, opts: Dictionary = {}) -> void:
	main = main_node
	arcade = arcade_node
	_mode = str(opts.get("mode", "adjust"))
	_customer = opts.get("customer", {}) if typeof(opts.get("customer", null)) == TYPE_DICTIONARY else {}
	_prob = GameSettings.crane_mode == "prob"
	_payout = GameSettings.crane_payout


## 1個あたりの目安（円）= 景品原価 / ペイアウト率
static func cost_per_prize(payout: int) -> int:
	return int(floor(float(PRIZE_COST) / (float(clampi(payout, PAYOUT_MIN, PAYOUT_MAX)) / 100.0)))


static func yen(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func is_running() -> bool:
	return _phase != ""


## 途中でやめる（タイトルへ戻る・店を変えるとき）。台を元に戻し、cancelled で終わる
func abort() -> void:
	if _phase == "":
		return
	_phase = ""
	if _ui != null:
		_ui.queue_free()
		_ui = null
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null
	_held = null
	if is_instance_valid(arcade):
		arcade.set_crane_manual(_cr, false)
	main.camera_release(0.0)
	_done.emit({"result": "cancelled", "cheat": false, "moved": _moved})


## ミニゲームを最後まで行い、結果を返す
func run() -> Dictionary:
	_cr = arcade.get_service_crane()
	if _cr.is_empty():
		return {"result": "cancelled", "cheat": false, "moved": false}
	_root = _cr["root"]
	_prizes = (_cr["prizes"] as Array).duplicate()
	_held = null
	_hover = null
	_target = null
	_power = POWER_DEFAULT
	_moved = false
	arcade.set_crane_manual(_cr, true)
	arcade.set_claw(_cr, 0.3, -0.25, 0.0, 30.0)   # アームを奥の右に止めておく
	_make_marker()

	# 1. 台の前へ
	var front: Vector3 = _root.to_global(Vector3(0.0, 0.0, 0.0))
	main.camera_to(front + Vector3(0.12, 1.78, 1.55), front + Vector3(-0.05, 0.95, -0.05), 0.9)
	main.sfx.play("door", 1.3)
	await get_tree().create_timer(0.9).timeout

	# 2. 調整
	_phase = "adjust"
	_time_left = TIME_LIMIT if _mode == "adjust" else TIME_LIMIT * 0.75
	_build_ui()
	_refresh_ui()
	if main.smoke:
		_auto_adjust()
	var res: Dictionary = await _done
	return res


# ---------------------------------------------------------------- 画面（作業メモ）

func _build_ui() -> void:
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_overlay(_ui)
	var memo: PanelContainer = UI.paper(UI.PAPER, 16, 4)
	memo.position = Vector2(24, 24)
	memo.custom_minimum_size = Vector2(380, 0)
	memo.rotation_degrees = -0.8
	_ui.add_child(memo)
	var col: VBoxContainer = UI.vbox(8)
	memo.add_child(col)
	var adjust: bool = _mode == "adjust"
	col.add_child(UI.text(tr("難易度の調整") if adjust else tr("景品を取りやすい位置へ"), UI.S_HEAD, UI.INK, UI.F_SIGN))
	_hint = UI.para(tr("景品をクリックしてつかみ、動かしたい場所まで引っぱって離す。取り出し口（左手前の穴）に近いほど取りやすい。"), UI.S_SMALL, UI.INK, UI.F_HAND)
	col.add_child(_hint)
	if adjust:
		col.add_child(UI.rule(UI.PAPER_DIM, 1))
		# パワー設定 / 確率設定（要件#55）
		var mode_row: HBoxContainer = UI.hbox(6)
		col.add_child(mode_row)
		var group: ButtonGroup = ButtonGroup.new()
		for m in [["power", "パワー設定"], ["prob", "確率設定"]]:
			var t: Button = UI.tag(tr(str(m[1])), UI.S_SMALL)
			t.toggle_mode = true
			t.button_group = group
			t.focus_mode = Control.FOCUS_NONE
			t.button_pressed = (str(m[0]) == "prob") == _prob
			var mid: String = str(m[0])
			t.toggled.connect(func(on: bool) -> void:
				if on:
					_prob = mid == "prob"
					main.sfx.play("click")
					_refresh_ui())
			mode_row.add_child(t)
		# パワー設定
		var pb: VBoxContainer = UI.vbox(4)
		_power_box = pb
		col.add_child(pb)
		_power_label = UI.text("", UI.S_BODY, UI.INK, UI.F_BOLD)
		pb.add_child(_power_label)
		_slider = HSlider.new()
		_slider.min_value = 1
		_slider.max_value = 10
		_slider.step = 1
		_slider.value = _power
		_slider.custom_minimum_size = Vector2(300, 24)
		_slider.focus_mode = Control.FOCUS_NONE
		_slider.value_changed.connect(func(v: float) -> void:
			_power = int(v)
			main.sfx.play("click", 0.8 + 0.05 * v)
			_refresh_ui())
		pb.add_child(_slider)
		pb.add_child(UI.text(tr("店の規定: 6 まで"), UI.S_SMALL, UI.INK_SOFT))
		# 確率設定: 景品原価 1,100円 / ペイアウト率 [30]% = 1個あたり 3,666円
		var qb: VBoxContainer = UI.vbox(4)
		_prob_box = qb
		col.add_child(qb)
		var row: HBoxContainer = UI.hbox(4)
		qb.add_child(row)
		row.add_child(UI.text(tr("景品原価 %s / ペイアウト率") % GameSettings.money(PRIZE_COST), UI.S_SMALL, UI.INK, UI.F_DOT))
		var spin: SpinBox = SpinBox.new()
		spin.min_value = PAYOUT_MIN
		spin.max_value = PAYOUT_MAX
		spin.step = 1
		spin.value = _payout
		spin.custom_minimum_size = Vector2(72, 0)
		spin.get_line_edit().add_theme_font_size_override("font_size", UI.S_BODY)
		spin.value_changed.connect(func(v: float) -> void:
			_payout = clampi(int(v), PAYOUT_MIN, PAYOUT_MAX)
			_refresh_ui())
		row.add_child(spin)
		row.add_child(UI.text("%", UI.S_SMALL, UI.INK, UI.F_DOT))
		_cost_label = UI.text("", UI.S_BODY, UI.INK, UI.F_DOT)
		qb.add_child(_cost_label)
		qb.add_child(UI.para(tr("上げると「取れない」クレームが減り、店舗レビューが少し上がりやすい。下げると「取れない」クレームが増えるが、売上は上がる。（%d〜%d%%）") % [PAYOUT_MIN, PAYOUT_MAX], UI.S_SMALL, UI.INK_SOFT))
	_chance_label = UI.text("", UI.S_SMALL, UI.INK_SOFT, UI.F_DOT)
	col.add_child(_chance_label)
	_time_label = UI.text("", UI.S_BODY, UI.SHU, UI.F_DOT)
	col.add_child(_time_label)
	if adjust:
		# テストプレイ（要件#55）
		var trow: HBoxContainer = UI.hbox(10)
		col.add_child(trow)
		_test_btn = UI.link(tr("テストプレイ"), UI.S_BODY)
		_test_btn.focus_mode = Control.FOCUS_NONE
		_test_btn.pressed.connect(_test_play)
		trow.add_child(_test_btn)
		_test_label = UI.text("", UI.S_SMALL, UI.INK_SOFT, UI.F_DOT)
		trow.add_child(_test_label)
	_play_btn = UI.primary(tr("この台で遊んでもらう"), UI.S_BODY)
	_play_btn.focus_mode = Control.FOCUS_NONE
	_play_btn.pressed.connect(_start_play)
	col.add_child(_play_btn)
	var cancel: Button = UI.link(tr("やめてカウンターに戻る"), UI.S_SMALL, UI.INK_SOFT)
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(func() -> void: _finish(_result("cancelled")))
	col.add_child(cancel)


func _refresh_ui() -> void:
	if _chance_label == null:
		return
	if _power_box != null:
		# 確率設定が有効なときは、パワーは触れない（要件#55）
		_slider.editable = not _prob
		_power_box.modulate = Color(1, 1, 1, 0.35 if _prob else 1.0)
		_prob_box.modulate = Color(1, 1, 1, 1.0 if _prob else 0.35)
		var over: bool = _power > POWER_LIMIT and not _prob
		_power_label.text = tr("アームの強さ: %d") % _power + ("  " + tr("（規定外…）") if over else "")
		_power_label.add_theme_color_override("font_color", UI.SHU if over else UI.INK)
		_cost_label.text = tr("＝ 1個あたり %s") % GameSettings.money(cost_per_prize(_payout))
	if _test_btn != null:
		_test_btn.disabled = _tests_left <= 0 or _phase != "adjust"
		if _test_label.text == "" or _tests_left == TEST_PLAYS:
			_test_label.text = tr("あと %d 回") % _tests_left
	var t: Node3D = _pick_target()
	var pct: int = int(round(_win_chance(t) * 100.0)) if t != null else 0
	# 正確な確率は見せず、目安だけ
	var guess: String = tr("まず無理") if pct < 20 else (tr("五分五分") if pct < 55 else (tr("いけそう") if pct < 80 else tr("ほぼ確実")))
	_chance_label.text = tr("取れそうか: %s") % guess


func _result(kind: String) -> Dictionary:
	return {"result": kind, "cheat": _is_cheat(), "moved": _moved, "mode": "prob" if _prob else "power",
		"payout": _payout, "tested": _tested, "tests": TEST_PLAYS - _tests_left}


func _is_cheat() -> bool:
	return not _prob and _power > POWER_LIMIT


## そろそろ払い出してもいい台か（筐体の記録の投入額が、1個あたりの目安の 8 割を超えている）。要件#57
func _near_payout() -> bool:
	var sp: Variant = _customer.get("spend", null)
	if typeof(sp) != TYPE_DICTIONARY:
		return false
	return float((sp as Dictionary).get("actual", 0)) >= 0.8 * float(cost_per_prize(_payout))


func _process(delta: float) -> void:
	if _phase != "adjust":
		return
	_time_left -= delta
	if _time_label != null:
		_time_label.text = tr("お客さんが待っている: あと %d 秒") % int(ceil(maxf(_time_left, 0.0)))
	if _time_left <= 0.0:
		_start_play()
		return
	# つかんでいる景品・カーソルの下の景品を少し浮かせて見せる
	_bob += delta * 6.0
	for p in _prizes:
		var n: Node3D = p
		if not is_instance_valid(n):
			continue
		var lift: float = 0.0
		if n == _held:
			lift = 0.06 + 0.01 * sin(_bob)
		elif n == _hover:
			lift = 0.015
		var base_y: float = _rest_y(n)
		n.position.y = lerpf(n.position.y, base_y + lift, minf(1.0, delta * 14.0))
	_update_marker()


# ---------------------------------------------------------------- マウス操作

func _unhandled_input(event: InputEvent) -> void:
	if _phase != "adjust":
		return
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _held != null:
			_drag_to(mm.position)
		else:
			_hover = _prize_at(mm.position)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb: InputEventMouseButton = event
		if mb.pressed:
			_held = _prize_at(mb.position)
			if _held != null:
				main.sfx.play("click", 1.3)
		elif _held != null:
			_drop_held()
		get_viewport().set_input_as_handled()


func _camera() -> Camera3D:
	return main.get_camera()


## 画面の点の下にある景品（ぶつかり判定の代わりに、視線と景品の中心の近さで選ぶ）
func _prize_at(screen_pos: Vector2) -> Node3D:
	var cam: Camera3D = _camera()
	var origin: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	var best: Node3D = null
	var best_d: float = 0.09
	for p in _prizes:
		var n: Node3D = p
		if not is_instance_valid(n) or not n.visible:
			continue
		var center: Vector3 = n.global_position + Vector3(0.0, 0.12, 0.0)
		var t: float = (center - origin).dot(dir)
		if t <= 0.0:
			continue
		var d: float = (origin + dir * t).distance_to(center)
		if d < best_d:
			best_d = d
			best = n
	return best


## 視線とケースの床（水平な面）の交点を、台のローカル座標で返す
func _floor_point(screen_pos: Vector2) -> Variant:
	var cam: Camera3D = _camera()
	var origin: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	var floor_y: float = _root.to_global(Vector3(0.0, Arcade.CASE_FLOOR_Y + 0.06, 0.0)).y
	if absf(dir.y) < 0.0001:
		return null
	var t: float = (floor_y - origin.y) / dir.y
	if t <= 0.0:
		return null
	return _root.to_local(origin + dir * t)


func _drag_to(screen_pos: Vector2) -> void:
	var hit: Variant = _floor_point(screen_pos)
	if hit == null:
		return
	var p: Vector3 = hit
	var x: float = clampf(p.x, Arcade.CASE_MIN.x, Arcade.CASE_MAX.x)
	var z: float = clampf(p.z, Arcade.CASE_MIN.y, Arcade.CASE_MAX.y)
	# 取り出し口の穴の上には置けない（ふちの柵の外側に押し出す）
	var hole_x: float = Arcade.CHUTE.x + Arcade.CHUTE_HALF
	var hole_z: float = Arcade.CHUTE.y - Arcade.CHUTE_HALF
	if x < hole_x + 0.02 and z > hole_z - 0.02:
		if (hole_x + 0.02 - x) < (z - (hole_z - 0.02)):
			x = hole_x + 0.02
		else:
			z = hole_z - 0.02
	_held.position.x = x
	_held.position.z = z
	_held.set_meta("dropped", true)


func _drop_held() -> void:
	main.sfx.play("click", 0.9)
	_target = _held
	_held = null
	_moved = true
	_refresh_ui()


# ---------------------------------------------------------------- 取れる確率

func _pick_target() -> Node3D:
	if _target != null and is_instance_valid(_target):
		return _target
	var best: Node3D = null
	var best_d: float = INF
	for p in _prizes:
		var n: Node3D = p
		if not is_instance_valid(n) or not n.visible:
			continue
		var d: float = Vector2(n.position.x, n.position.z).distance_to(Arcade.CHUTE)
		if d < best_d:
			best_d = d
			best = n
	return best


func _win_chance(prize: Node3D) -> float:
	if prize == null:
		return 0.0
	var dist: float = Vector2(prize.position.x, prize.position.z).distance_to(Arcade.CHUTE)
	var base: float = clampf(1.05 - dist / 0.65, 0.05, 0.95)
	if _prob:
		# 確率設定: ペイアウト率 30% → 1.0 倍、10% → 0.6、80% → 2.0。そろそろ払い出す台なら +0.25（要件#55, #57）
		var pf: float = 0.4 + float(_payout) / 50.0
		var bonus: float = 0.25 if _near_payout() else 0.0
		return clampf(base * pf + 0.04 + bonus, 0.03, 0.96)
	var factor: float = 0.3 + 0.1 * float(_power)          # 強さ 4 → 0.7、6 → 0.9、10 → 1.3
	return clampf(base * factor + 0.04, 0.03, 0.96)


## 取り出し口の上に、狙いの目印（薄い輪）を出す
func _make_marker() -> void:
	_marker = MeshInstance3D.new()
	var tm: TorusMesh = TorusMesh.new()
	tm.inner_radius = 0.07
	tm.outer_radius = 0.085
	_marker.mesh = tm
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.82, 0.25)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.82, 0.25)
	m.emission_energy_multiplier = 2.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker.material_override = m
	_root.add_child(_marker)
	_marker.visible = false


func _update_marker() -> void:
	if _marker == null or not is_instance_valid(_marker):
		return
	var t: Node3D = _pick_target()
	_marker.visible = t != null and _phase == "adjust"
	if t != null:
		_marker.position = Vector3(t.position.x, Arcade.CASE_FLOOR_Y + 0.01, t.position.z)
		_marker.rotation.y += 0.02


# ---------------------------------------------------------------- お客さんが遊ぶ

func _start_play() -> void:
	if _phase != "adjust":
		return
	if _held != null:
		_drop_held()
	_phase = "play"
	if _ui != null:
		_ui.queue_free()
		_ui = null
	_marker.visible = false
	_save_settings()
	var prize: Node3D = _pick_target()
	if prize == null:
		_finish(_result("lost"))
		return
	var won: bool = randf() < _win_chance(prize)
	if main.smoke:
		won = true
	await _play_claw(prize, won)
	_finish(_result("won" if won else "lost"))


## 確率設定とペイアウト率は店全体の設定として保存する（パワーはこのお客さんだけ）
func _save_settings() -> void:
	if _mode != "adjust":
		return
	GameSettings.crane_mode = "prob" if _prob else "power"
	GameSettings.crane_payout = _payout
	GameSettings.save_settings()


## テストプレイ（要件#55）: 今の設定で自分で1回遊ぶ。取れても景品はすぐ補充される。調整の時間は止まる
func _test_play() -> void:
	if _phase != "adjust" or _tests_left <= 0:
		return
	if _held != null:
		_drop_held()
	var prize: Node3D = _pick_target()
	if prize == null:
		return
	_tests_left -= 1
	_tested = true
	_phase = "test"
	_marker.visible = false
	_play_btn.disabled = true
	_test_btn.disabled = true
	_test_label.text = tr("テスト中…")
	var keep_pos: Vector3 = prize.position
	var won: bool = randf() < _win_chance(prize)
	await _play_claw(prize, won)
	if _phase != "test":
		return   # 途中でやめた
	if won:
		# 取れた景品は元の場所に戻しておく（補充した体）
		prize.reparent(_root, true)
		prize.position = keep_pos
		prize.rotation = Vector3.ZERO
		prize.visible = true
		if not _prizes.has(prize):
			_prizes.append(prize)
	_test_label.text = (tr("テスト: 取れた") if won else tr("テスト: 取れなかった")) + "  " + tr("あと %d 回") % _tests_left
	_phase = "adjust"
	_play_btn.disabled = false
	_refresh_ui()


func _tween_claw(from: Dictionary, to: Dictionary, dur: float) -> void:
	var tw: Tween = create_tween()
	tw.tween_method(_apply_claw.bind(from, to), 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


func _apply_claw(t: float, from: Dictionary, to: Dictionary) -> void:
	var x: float = lerpf(float(from["x"]), float(to["x"]), t)
	var z: float = lerpf(float(from["z"]), float(to["z"]), t)
	var d: float = lerpf(float(from["d"]), float(to["d"]), t)
	var o: float = lerpf(float(from["o"]), float(to["o"]), t)
	arcade.set_claw(_cr, x, z, d, o)


func _play_claw(prize: Node3D, won: bool) -> void:
	var px: float = prize.position.x
	var pz: float = prize.position.z
	var top_y: float = prize.position.y + 0.14
	var grab_drop: float = clampf(Arcade.CARRIAGE_Y - 0.36 - top_y, 0.1, 0.75)
	var s: Dictionary = {"x": 0.3, "z": -0.25, "d": 0.0, "o": 30.0}
	main.sfx.play("send", 1.2)
	# 横 → 奥（お客さんのボタン操作）
	var a: Dictionary = {"x": px, "z": -0.25, "d": 0.0, "o": 30.0}
	await _tween_claw(s, a, 1.0)
	var b: Dictionary = {"x": px, "z": pz, "d": 0.0, "o": 34.0}
	await _tween_claw(a, b, 0.8)
	await get_tree().create_timer(0.25).timeout
	# 下りる → つかむ
	var c: Dictionary = {"x": px, "z": pz, "d": grab_drop, "o": 34.0}
	await _tween_claw(b, c, 0.9)
	var grip: float = 8.0 if (won or (_power >= 8 and not _prob)) else 16.0   # 弱いと爪が閉じきらない
	var d: Dictionary = {"x": px, "z": pz, "d": grab_drop, "o": grip}
	await _tween_claw(c, d, 0.35)
	# 景品を爪にくっつける
	var claw: Node3D = _cr["claw"]
	prize.reparent(claw, true)
	main.sfx.play("click", 0.7)
	# 上がる
	var e: Dictionary = {"x": px, "z": pz, "d": 0.0, "o": grip}
	if not won and randf() < 0.5:
		# 持ち上げる途中でずり落ちる
		await _tween_claw(d, {"x": px, "z": pz, "d": grab_drop * 0.45, "o": grip}, 0.6)
		await _drop_prize(prize, Vector3(px, Arcade.CASE_FLOOR_Y, pz) + Vector3(randf_range(-0.06, 0.06), 0.0, randf_range(-0.06, 0.06)), false)
		await _tween_claw({"x": px, "z": pz, "d": grab_drop * 0.45, "o": 30.0}, {"x": 0.3, "z": -0.25, "d": 0.0, "o": 30.0}, 1.2)
		return
	await _tween_claw(d, e, 0.8)
	# 取り出し口へ運ぶ
	var cx: float = Arcade.CHUTE.x
	var cz: float = Arcade.CHUTE.y
	var fail_at: float = randf_range(0.35, 0.8)
	if not won:
		# 運ぶ途中で落とす
		var mid: Dictionary = {"x": lerpf(px, cx, fail_at), "z": lerpf(pz, cz, fail_at), "d": 0.0, "o": grip}
		await _tween_claw(e, mid, 1.1 * fail_at)
		var land: Vector3 = Vector3(float(mid["x"]), Arcade.CASE_FLOOR_Y, float(mid["z"]))
		# 穴のふちに当たったら柵の外へ
		if land.x < cx + Arcade.CHUTE_HALF and land.z > cz - Arcade.CHUTE_HALF:
			land.x = cx + Arcade.CHUTE_HALF + 0.05
		await _drop_prize(prize, land, false)
		await _tween_claw({"x": float(mid["x"]), "z": float(mid["z"]), "d": 0.0, "o": 30.0}, {"x": 0.3, "z": -0.25, "d": 0.0, "o": 30.0}, 1.0)
		return
	var f: Dictionary = {"x": cx, "z": cz, "d": 0.0, "o": grip}
	await _tween_claw(e, f, 1.1)
	await _tween_claw(f, {"x": cx, "z": cz, "d": 0.0, "o": 34.0}, 0.25)
	await _drop_prize(prize, Vector3(cx, Arcade.CASE_FLOOR_Y - 0.55, cz), true)
	main.sfx.play("win")
	await _tween_claw({"x": cx, "z": cz, "d": 0.0, "o": 34.0}, {"x": 0.3, "z": -0.25, "d": 0.0, "o": 30.0}, 1.0)


## 景品を落とす。into_chute なら取り出し口に吸い込まれて消える
func _drop_prize(prize: Node3D, land_local: Vector3, into_chute: bool) -> void:
	prize.reparent(_root, true)
	var tw: Tween = create_tween()
	tw.tween_property(prize, "position", land_local, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(prize, "rotation:z", prize.rotation.z + randf_range(-0.6, 0.6), 0.35)
	if not into_chute:
		# 床で一度はねる
		tw.tween_property(prize, "position:y", land_local.y + 0.04, 0.1).set_ease(Tween.EASE_OUT)
		tw.tween_property(prize, "position:y", land_local.y, 0.1).set_ease(Tween.EASE_IN)
	await tw.finished
	main.sfx.play("bad" if not into_chute else "good", 1.4)
	if into_chute:
		prize.visible = false
		_prizes.erase(prize)
		# 少し後に補充された体で戻しておく（次のお客さんのため）
		prize.position = Vector3(randf_range(0.0, 0.4), Arcade.CASE_FLOOR_Y, randf_range(-0.3, 0.0))
		prize.rotation = Vector3.ZERO
		_prizes.append(prize)
		# ミニゲームの節は終わるとすぐ消えるので、木（SceneTree）の tween で戻す
		var back: Tween = get_tree().create_tween()
		back.tween_interval(3.0)
		back.tween_callback(func() -> void:
			if is_instance_valid(prize):
				prize.visible = true)
	prize.set_meta("dropped", true)


## 景品が床に置かれたときの高さ。積まれていた景品も、一度動かしたら床に置く
func _rest_y(n: Node3D) -> float:
	if not n.has_meta("y0"):
		n.set_meta("y0", n.position.y)
	var off: float = float(n.get_meta("y0")) - Arcade.CASE_FLOOR_Y
	if bool(n.get_meta("dropped", false)) and off >= 0.1:
		off -= 0.11
	return Arcade.CASE_FLOOR_Y + off


func _finish(res: Dictionary) -> void:
	if _phase == "":
		return
	_phase = ""
	if _ui != null:
		_ui.queue_free()
		_ui = null
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null
	_held = null
	if not is_instance_valid(arcade):
		return
	arcade.set_crane_manual(_cr, false)
	main.camera_release(0.8)
	await get_tree().create_timer(0.8).timeout
	_done.emit(res)


## 自動テスト用: 取り出し口に一番近い景品をさらに寄せて、強さ 5 で遊ぶ
func _auto_adjust() -> void:
	await get_tree().create_timer(0.5).timeout
	var t: Node3D = _pick_target()
	if t != null:
		t.position.x = Arcade.CHUTE.x + Arcade.CHUTE_HALF + 0.05
		t.position.z = Arcade.CHUTE.y - 0.05
		_target = t
		_moved = true
	_power = 5
	_start_play()
