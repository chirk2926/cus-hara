extends Control
## 筐体の前で対応する場面（要件#99）。1人用のゲームセンターで、台の問題（problem）があるお客さんのとき。
##
## 流れ:
##   1. 筐体の前へ移動（カメラが寄る）
##   2. 「筐体を開ける」（メダル）／「操作パネルを開ける」（ビデオ）→ 中を見て、何が起きているかがわかる
##   3. 対応のボタン → 簡単なミニゲーム → 店員の手の動き（扉・レール・補充口・抽選機・コネクタが動く）
##   4. 「カウンターに戻る」で終わり。{"actions": [した対応の id], "seconds": かかった時間, "opened": bool} を返す
## かかった時間（WORK_SECONDS）の分だけ、お客さんの怒りがゆるやかに上がる（solo_game.gd が REPAIR_ANGER_RATE をかける）。
## main.smoke（自動テスト）のときは、ミニゲームを飛ばして正しい対応を自動でする。

const UI = preload("res://scripts/ui_kit.gd")
const Paper = preload("res://scripts/ui_paper.gd")
const ShopActions = preload("res://scripts/shop_actions.gd")
const RepairStage = preload("res://scripts/repair_stage.gd")

signal _done(result: Dictionary)
signal _mini_done(ok: bool)

## 対応にかかる時間（秒）。叩くのは早いが、分解は時間がかかる（要件#99）
const WORK_SECONDS: Dictionary = {"cab_open": 3.0, "medal_hit": 3.0, "medal_rail": 14.0, "medal_refill": 8.0, "medal_repair": 10.0,
	"video_check": 5.0, "video_connector": 6.0}

var main = null
var _kind: String = "medal"      # "medal" | "video"
var _problem: String = ""
var _customer: Dictionary = {}
var _stage: Node3D = null
var _cam: Camera3D = null
var _vp: SubViewport = null
var _panel: VBoxContainer = null
var _status: Label = null
var _buttons: VBoxContainer = null
var _mini: Control = null
var _opened: bool = false
var _busy: bool = false
var _done_ids: Array = []
var _seconds: float = 0.0
var _dead_button: int = 2


func setup(m, customer: Dictionary) -> void:
	main = m
	_customer = customer
	_problem = ShopActions.problem_of(customer)
	_kind = "medal" if str(customer.get("machine", "")) == "medal" else "video"
	_dead_button = absi(str(customer.get("title", "")).hash()) % 4
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 3D: 自分だけの世界に筐体のまわりを作る（店のカウンターの場面とは別）
	var svc: SubViewportContainer = SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(_vp)
	_stage = RepairStage.new()
	_vp.add_child(_stage)
	_stage.call("build_repair", _kind, _problem)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_vp.add_child(_cam)
	var cp: Vector3 = _stage.get("cam_pos")
	var cl: Vector3 = _stage.get("cam_look")
	_cam.transform = Transform3D.IDENTITY.translated(cp + Vector3(0.0, 0.25, 1.6)).looking_at(cl, Vector3.UP)
	var tw: Tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(k: float) -> void:
		var p: Vector3 = (cp + Vector3(0.0, 0.25, 1.6)).lerp(cp, k)
		_cam.transform = Transform3D.IDENTITY.translated(p).looking_at(cl, Vector3.UP), 0.0, 1.0, 0.9)
	_build_ui()


func _build_ui() -> void:
	# 右はしに「作業メモ」（クリップボードの紙）。左はしの3Dの筐体を見ながら押す
	var holder: MarginContainer = MarginContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	holder.offset_left = -380
	for s in ["margin_top", "margin_bottom", "margin_right"]:
		holder.add_theme_constant_override(s, 24)
	add_child(holder)
	var paper: PanelContainer = UI.paper(UI.PAPER, 20, 5)
	paper.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	holder.add_child(paper)
	_panel = UI.vbox(10)
	paper.add_child(_panel)
	_panel.add_child(UI.text(tr("メダルゲームの筐体") if _kind == "medal" else tr("ビデオゲームの台"), UI.S_LEAD, UI.INK, UI.F_SIGN))
	_status = UI.para("", UI.S_BODY, UI.INK, UI.F_HAND)
	_status.custom_minimum_size = Vector2(320, 0)
	_panel.add_child(_status)
	_mini = UI.vbox(6)
	_panel.add_child(_mini)
	_buttons = UI.vbox(6)
	_panel.add_child(_buttons)
	_status.text = _first_look()
	_refresh_buttons()


func _first_look() -> String:
	if _kind == "medal":
		return tr("お客さんの台の前に来た。中を見るには、まず筐体を開ける。")
	return tr("お客さんの台の前に来た。ボタンを確かめるか、操作パネルを開けて中を見る。")


func _inside_look() -> String:
	match _problem:
		"jam":
			return tr("払い出しのレールの途中で、メダルが斜めに重なって詰まっている。")
		"empty":
			return tr("ホッパー（メダルの箱）が空っぽだ。払い出すメダルがない。")
		"lottery":
			return tr("抽選機のランプが赤く点いて、ドラムが止まっている。")
		"button", "button_lie":
			return tr("パネルの裏に、ボタンの配線とコネクタがある。")
	return ""


func _refresh_buttons() -> void:
	for c in _buttons.get_children():
		c.queue_free()
	var acts: Dictionary = ShopActions.problem_actions(_customer)
	var ids: Array = []
	if _kind == "medal":
		if not _opened:
			ids.append("cab_open")
		else:
			for id in ["medal_hit", "medal_rail", "medal_refill", "medal_repair"]:
				if acts.has(id):
					ids.append(id)
	else:
		if acts.has("video_check"):
			ids.append("video_check")
		if not _opened:
			ids.append("cab_open")
		elif acts.has("video_connector"):
			ids.append("video_connector")
	for id in ids:
		var label: String = ShopActions.label(id)
		if id == "cab_open" and _kind == "video":
			label = tr("操作パネルを開ける")
		var b: Button = UI.stamp(label, UI.S_BODY)
		b.disabled = _busy or _done_ids.has(id)
		var aid: String = id
		b.pressed.connect(func() -> void: _do(aid))
		_buttons.add_child(b)
	_buttons.add_child(UI.gap(6))
	var back: Button = UI.link(tr("カウンターに戻る →"), UI.S_BODY)
	back.disabled = _busy
	back.pressed.connect(_finish)
	_buttons.add_child(back)
	if main != null and bool(main.get("smoke")) and not _busy:
		_auto.call_deferred()


func run() -> Dictionary:
	var res: Dictionary = await _done
	return res


func _finish() -> void:
	if _busy:
		return
	_done.emit({"actions": _done_ids.filter(func(i: String) -> bool: return i != "cab_open"), "seconds": _seconds, "opened": _opened})


# ---------------------------------------------------------------- 対応

func _do(id: String) -> void:
	if _busy:
		return
	_busy = true
	_refresh_buttons()
	if main != null and main.get("sfx") != null:
		main.sfx.play("click")
	var acts: Dictionary = ShopActions.problem_actions(_customer)
	var good: bool = str(acts.get(id, "neutral")) in ["good", "hit", "fixed"]
	if not (main != null and bool(main.get("smoke"))):
		await _minigame(id)
	match id:
		"cab_open":
			_opened = true
			if _kind == "medal":
				await _stage.call("open_door")
			else:
				await _stage.call("open_panel")
			_status.text = _inside_look()
		"medal_hit":
			await _stage.call("hit_rail", _problem == "jam")
			_status.text = tr("ガンッ！……詰まりが取れて、メダルが出てきた。（規定では、叩いて直すのは推奨されていない）") if _problem == "jam" else tr("叩いてみたが、何も変わらない。")
		"medal_rail":
			await _stage.call("disassemble_rail", _problem == "jam")
			_status.text = tr("レールを外して、詰まったメダルを取り除いた。元に戻すと、メダルが出てきた。") if _problem == "jam" else tr("レールを分解してみたが、詰まりはなかった。")
		"medal_refill":
			await _stage.call("refill", _problem == "empty")
			_status.text = tr("補充口からメダルを入れた。払い出しが戻った。") if _problem == "empty" else tr("メダルを足してみたが、問題はそこではなかった。")
		"medal_repair":
			await _stage.call("repair_lottery", _problem == "lottery")
			_status.text = tr("抽選機の部品を締め直した。ランプが緑になり、ドラムが回りだした。") if _problem == "lottery" else tr("抽選機はもともと動いていた。")
		"video_check":
			for i in range(4):
				await _stage.call("test_button", i, _problem != "button" or i != _dead_button)
			_status.text = (tr("%d番のボタンだけ反応しない。本当に壊れている。") % (_dead_button + 1)) if _problem == "button" else tr("ボタンはぜんぶ反応する。壊れていないようだ。")
		"video_connector":
			await _stage.call("reseat_connector")
			_status.text = tr("コネクタを差し直した。ボタンがぜんぶ反応するようになった。") if _problem == "button" else tr("コネクタを差し直したが、もともと問題はなかった。")
	_seconds += float(WORK_SECONDS.get(id, 4.0))
	if not _done_ids.has(id):
		_done_ids.append(id)
	if good and main != null and main.get("sfx") != null:
		main.sfx.play("win", 1.4)
	_busy = false
	_refresh_buttons()


## 自動テスト: 開けて、正しい対応をして、戻る
func _auto() -> void:
	await get_tree().create_timer(0.3).timeout
	if _busy or not is_inside_tree():
		return
	var acts: Dictionary = ShopActions.problem_actions(_customer)
	if not _opened and _kind == "medal":
		_do("cab_open")
		return
	for id in ["medal_rail", "medal_refill", "medal_repair", "video_check", "video_connector"]:
		if str(acts.get(id, "")) in ["good", "fixed"] and not _done_ids.has(id):
			if id == "video_connector" and not _opened:
				_do("cab_open")
				return
			_do(id)
			return
	if _kind == "video" and not _done_ids.has("video_check") and acts.has("video_check"):
		_do("video_check")
		return
	_finish()


# ---------------------------------------------------------------- 簡単なミニゲーム（要件#99）

func _minigame(id: String) -> void:
	for c in _mini.get_children():
		c.queue_free()
	match id:
		"medal_hit":
			await _mini_tap(tr("レールを3回叩く！"), 3)
		"medal_rail":
			await _mini_order(tr("ネジを1→4の順に外す"), 4)
		"medal_refill", "medal_repair":
			await _mini_hold(tr("ボタンを押したままにして、メダルを流し込む") if id == "medal_refill" else tr("押したままにして、部品を締める"), 1.6)
		"video_check":
			await _mini_tap(tr("ボタンを順番に押して確かめる（4回）"), 4)
		"video_connector", "cab_open":
			await _mini_timing(tr("鍵を回す：緑のところで止める") if id == "cab_open" else tr("コネクタを差し込む：緑のところで止める"))
	for c in _mini.get_children():
		c.queue_free()


## 何回か押す
func _mini_tap(title: String, n: int) -> void:
	_mini.add_child(UI.text(title, UI.S_SMALL, UI.SHU, UI.F_BOLD))
	var left: Array = [n]
	var b: Button = UI.tag(tr("あと %d 回") % n, UI.S_LEAD)
	b.pressed.connect(func() -> void:
		left[0] -= 1
		if main != null and main.get("sfx") != null:
			main.sfx.play("click", 0.8 + 0.1 * float(left[0]))
		b.text = tr("あと %d 回") % left[0]
		if left[0] <= 0:
			_mini_done.emit(true))
	_mini.add_child(b)
	await _mini_done


## 番号の順に押す（ネジ）
func _mini_order(title: String, n: int) -> void:
	_mini.add_child(UI.text(title, UI.S_SMALL, UI.SHU, UI.F_BOLD))
	var row: HFlowContainer = HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	_mini.add_child(row)
	var order: Array = range(1, n + 1)
	order.shuffle()
	var next: Array = [1]
	for k in order:
		var num: int = int(k)
		var b: Button = UI.tag("⊕ %d" % num, UI.S_LEAD)
		b.pressed.connect(func() -> void:
			if num == next[0]:
				b.disabled = true
				next[0] += 1
				if main != null and main.get("sfx") != null:
					main.sfx.play("click", 1.2)
				if next[0] > n:
					_mini_done.emit(true)
			elif main != null and main.get("sfx") != null:
				main.sfx.play("bad", 1.0))
		row.add_child(b)
	await _mini_done


## 押したままにしてゲージをためる
func _mini_hold(title: String, need: float) -> void:
	_mini.add_child(UI.text(title, UI.S_SMALL, UI.SHU, UI.F_BOLD))
	var bar: ProgressBar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(300, 10)
	bar.add_theme_stylebox_override("background", UI.flat_style(UI.PAPER_DIM, 0, 0))
	bar.add_theme_stylebox_override("fill", UI.flat_style(UI.OK, 0, 0))
	_mini.add_child(bar)
	var b: Button = UI.tag(tr("押したまま"), UI.S_LEAD)
	_mini.add_child(b)
	var held: Array = [0.0]
	while held[0] < need:
		await get_tree().process_frame
		if not is_inside_tree():
			return
		if b.button_pressed or Input.is_action_pressed("ui_accept"):
			held[0] += get_process_delta_time()
			bar.value = 100.0 * held[0] / need


## 動く印を緑のところで止める（外れたらやり直し）
func _mini_timing(title: String) -> void:
	_mini.add_child(UI.text(title, UI.S_SMALL, UI.SHU, UI.F_BOLD))
	var track: Control = Control.new()
	track.custom_minimum_size = Vector2(300, 22)
	_mini.add_child(track)
	var bg: ColorRect = ColorRect.new()
	bg.color = UI.PAPER_DIM
	bg.size = Vector2(300, 22)
	track.add_child(bg)
	var zone: ColorRect = ColorRect.new()
	zone.color = UI.OK
	zone.position = Vector2(randf_range(90.0, 200.0), 0)
	zone.size = Vector2(52, 22)
	track.add_child(zone)
	var mark: ColorRect = ColorRect.new()
	mark.color = UI.INK
	mark.size = Vector2(4, 22)
	track.add_child(mark)
	var stop: Button = UI.tag(tr("止める"), UI.S_LEAD)
	_mini.add_child(stop)
	var t: Array = [0.0]
	var ok: Array = [false]
	stop.pressed.connect(func() -> void:
		var x: float = mark.position.x + 2.0
		if x >= zone.position.x and x <= zone.position.x + zone.size.x:
			ok[0] = true
		elif main != null and main.get("sfx") != null:
			main.sfx.play("bad", 1.0))
	while not ok[0]:
		await get_tree().process_frame
		if not is_inside_tree():
			return
		t[0] += get_process_delta_time()
		mark.position.x = 148.0 + 146.0 * sin(t[0] * 2.4)
