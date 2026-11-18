extends Node
## アプリ全体の司令塔。3Dステージ・カメラ・お客さんキャラと、各画面（タイトル／設定／遊び方／休憩／結果／対戦ロビー）を持ち、
## ゲームモード（solo_game.gd / versus_game.gd）に「見た目を動かす」関数を提供する。
## 画面の見た目の決まりは docs/UI_GUIDE.md、全体の作りは docs/DESIGN.md。
##
## 起動引数（`godot -- <引数>`）:
##   --smoke            1人用を全ステージ自動プレイして終了（CI）。--source=server|offline で採点先を指定
##   --vs-smoke=text|voice  ランクマッチに並んで対戦を自動プレイして終了（CI。2つ同時に起動する）
##   --shots            主な画面を docs/screenshots/ に保存して終了
##   --server=URL       接続先サーバー（保存しない） / --profile=名前  ログイン情報を分ける / --lang=ja|en

const StageWorldScript = preload("res://scripts/stage_world.gd")
const CustomerScript = preload("res://scripts/customer_character.gd")
const HudScript = preload("res://scripts/hud.gd")
const SoloScript = preload("res://scripts/solo_game.gd")
const VersusScript = preload("res://scripts/versus_game.gd")
const LlmScript = preload("res://scripts/llm_client.gd")
const ApiScript = preload("res://scripts/server_api.gd")
const SfxScript = preload("res://scripts/sfx.gd")
const BgmScript = preload("res://scripts/bgm.gd")
const UI = preload("res://scripts/ui_kit.gd")
const Paper = preload("res://scripts/ui_paper.gd")
const ScenariosScript = preload("res://scripts/scenarios.gd")
const CraneScript = preload("res://scripts/crane_minigame.gd")
const TutorialScript = preload("res://scripts/tutorial.gd")
const ShopActionsScript = preload("res://scripts/shop_actions.gd")

const CAMERA_POS: Vector3 = Vector3(0.0, 1.55, 1.9)
const CAMERA_TARGET: Vector3 = Vector3(0.0, 1.28, -0.35)
const STAGE_ORDER: Array = ["konbini", "arcade"]
## 名前・説明は日本語の文をキーにして tr() で訳す
const STAGES: Dictionary = {
	"konbini": {"name": "コンビニ「ハッピーマート」", "desc": "24時間営業。弁当、レジ袋、年齢確認…火種はどこにでもある。"},
	"arcade": {"name": "ゲームセンター「ゲームパラダイス」", "desc": "クレーンゲームだらけの店。「取れない」は全部こちらのせい。"},
}
const RANKS: Array = [
	[5600, "S", "伝説のクレーム処理班"],
	[4000, "A", "頼れるバイトリーダー"],
	[2400, "B", "一人前のスタッフ"],
	[800, "C", "研修中スタッフ"],
	[-999999, "D", "店長に呼び出されるスタッフ"],
]

# ゲームモードから使う公開メンバー
var sfx = null
var bgm = null
var llm = null
var api = null
var smoke: bool = false
var mode: String = ""             # "" | "solo" | "versus"
var display_anger: float = 0.0    # 0〜100。3Dの表情・照明に反映される

var _world = null
var _camera: Camera3D = null
var _customer = null
var _hud = null
var _solo = null
var _versus = null
var _tutorial = null
var _ui: CanvasLayer = null
var _title: Control = null
var _sheet: Control = null
var _profile_label: Label = null
var _server_label: Label = null
var _lobby_status: Label = null
var _lobby_code: Label = null
var _current_stage: String = ""
var _shake: float = 0.0
var _time: float = 0.0
var _in_game: bool = false
var _cam_override: bool = false
var _cam_override_pos: Vector3 = Vector3.ZERO
var _cam_override_target: Vector3 = Vector3.ZERO
var _server_info: Dictionary = {}
var _vs_format: String = "text"
var _crane_mg = null
var _sheet_is_receipt: bool = false
var _sheet_is_lobby: bool = false


func _ready() -> void:
	randomize()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--lang="):
			GameSettings.language = a.substr(7)
			GameSettings.apply_language()
		elif a.begins_with("--source="):
			GameSettings.solo_source = a.substr(9)
	smoke = args.has("--smoke") or _arg("--vs-smoke=") != ""

	sfx = SfxScript.new()
	add_child(sfx)
	bgm = BgmScript.new()
	add_child(bgm)
	llm = LlmScript.new()
	add_child(llm)
	api = ApiScript.new()
	add_child(api)

	_world = StageWorldScript.new()
	_world.set("label_font", UI.font(UI.F_SIGN))
	add_child(_world)
	_camera = Camera3D.new()
	_camera.fov = 60.0
	add_child(_camera)
	_camera.position = CAMERA_POS
	_camera.look_at(CAMERA_TARGET, Vector3.UP)
	_camera.current = true

	_ui = CanvasLayer.new()
	add_child(_ui)
	_solo = SoloScript.new()
	add_child(_solo)
	_versus = VersusScript.new()
	add_child(_versus)
	_make_hud()
	_solo.setup(self, _hud)
	_solo.finished.connect(_on_solo_finished)
	_versus.setup(self, _hud, api)
	_versus.finished.connect(_on_versus_finished)
	_versus.lobby_event.connect(_on_lobby_event)
	_tutorial = TutorialScript.new()
	add_child(_tutorial)
	_tutorial.setup(self, _hud)
	_tutorial.finished.connect(_quit_to_title)

	_build_title()
	_show_title()

	if args.has("--smoke"):
		_run_smoke()
	elif _arg("--vs-smoke=") != "":
		_run_versus_smoke(_arg("--vs-smoke="))
	elif args.has("--shots"):
		_run_shots()
	else:
		_check_server()
		# 初めて起動したときは研修（チュートリアル）を勧める（要件#53）
		if not GameSettings.tutorial_seen:
			_offer_tutorial()


func _arg(prefix: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return ""


func _make_hud() -> void:
	_hud = HudScript.new()
	_hud.sfx = sfx
	_ui.add_child(_hud)
	_ui.move_child(_hud, 0)
	_hud.visible = false
	_hud.pause_pressed.connect(_show_pause)
	_hud.talk_started.connect(_on_talk_started)


func _process(delta: float) -> void:
	_time += delta
	var pos: Vector3 = CAMERA_POS
	if not _in_game:
		pos += Vector3(sin(_time * 0.25) * 0.5, 0.25 + sin(_time * 0.18) * 0.08, 0.6)
	if _shake > 0.001:
		pos += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * _shake
		_shake = lerpf(_shake, 0.0, minf(1.0, delta * 5.0))
	var target: Vector3 = CAMERA_TARGET
	if _cam_override:
		pos = _cam_override_pos
		target = _cam_override_target
	_camera.position = pos
	_camera.look_at(target, Vector3.UP)
	if _customer != null and is_instance_valid(_customer):
		_customer.call("set_anger", clampf(display_anger / 100.0, 0.0, 1.0))
	if _world != null:
		_world.call("set_tension", clampf((display_anger - 60.0) / 40.0, 0.0, 1.0) if _in_game else 0.0)
	bgm.set_tension(clampf((display_anger - 60.0) / 40.0, 0.0, 1.0) if _in_game else 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# 台の調整中は止めない（お客さんを待たせている設定）。結果のレシートは Esc で閉じない（閉じると空の画面が残る）
		if _crane_mg != null and is_instance_valid(_crane_mg) and _crane_mg.is_running():
			return
		if _sheet != null:
			if _sheet_is_receipt:
				return
			if _sheet_is_lobby:
				_versus.cancel()
			_close_sheet()
		elif _in_game:
			_show_pause()


# ---------------------------------------------------------------- ゲームモード向けの関数

func set_stage(stage_id: String) -> void:
	if stage_id == _current_stage:
		return
	_abort_crane()
	_current_stage = stage_id
	_world.call("build", stage_id)


## お客さんを入口から歩かせ、カウンター前に着くまで待つ
func spawn_customer(look: Dictionary) -> void:
	_free_customer()
	_customer = CustomerScript.new()
	add_child(_customer)
	_customer.call("setup", look)
	_customer.tripped.connect(func() -> void:
		sfx.play("explode", 1.6)
		shake(0.12))
	var from: Vector3 = _world.call("get_customer_entrance")
	var to: Vector3 = _world.call("get_customer_stand")
	_customer.position = from
	_customer.call("enter", from, to)
	await _customer.arrived


## お客さんを退店させ、出ていくまで待つ。mood: "happy" | "angry" | "smug"
func dismiss_customer(mood: String) -> void:
	if _customer == null or not is_instance_valid(_customer):
		return
	var c = _customer
	var to: Vector3 = _world.call("get_customer_entrance")
	c.call("leave", to, mood)
	await c.left
	if is_instance_valid(c):
		c.queue_free()
	if _customer == c:
		_customer = null


## 店長（要件#52）。紺のスーツ・めがね・七三。お客さんの右うしろまで来て、プレイヤーにアドバイスする
const MANAGER_LOOK: Dictionary = {"body_color": "#2e3550", "skin_color": "#efc7a0", "hair_color": "#3a3a3a",
	"hair": "short", "build": "normal", "accessory": "glasses", "height": 1.05}
var _manager = null


## 店長を売り場の奥から歩かせ、お客さんの横に着くまで待つ
func manager_enter() -> void:
	manager_leave_now()
	_manager = CustomerScript.new()
	add_child(_manager)
	_manager.call("setup", MANAGER_LOOK)
	var from: Vector3 = _world.call("get_customer_entrance")
	var stand: Vector3 = _world.call("get_customer_stand")
	# お客さんのすぐ右うしろ（左はメモの紙で隠れるため。フキダシより上に頭が見える）
	var to: Vector3 = stand + Vector3(0.8, 0.0, -0.2)
	_manager.position = from
	_manager.call("enter", from, to)
	await _manager.arrived


func manager_talk(duration: float) -> void:
	if _manager != null and is_instance_valid(_manager):
		_manager.call("talk", duration)
		_manager.call("react", "calm")


## 店長が戻っていく（待たない）
func manager_leave() -> void:
	if _manager == null or not is_instance_valid(_manager):
		return
	var m = _manager
	_manager = null
	m.call("leave", _world.call("get_customer_entrance"), "happy")
	await m.left
	if is_instance_valid(m):
		m.queue_free()


## すぐ消す（店を変える・タイトルへ戻るとき）
func manager_leave_now() -> void:
	if _manager != null and is_instance_valid(_manager):
		_manager.queue_free()
	_manager = null


func customer_say(speaker: String, text: String, angry: bool = false) -> void:
	await _hud.say(speaker, text, angry)


func customer_react(kind: String) -> void:
	if _customer != null and is_instance_valid(_customer):
		_customer.call("react", kind)


func shake(strength: float) -> void:
	_shake = maxf(_shake, strength)


## 対戦が始まったとき（versus_game.gd から）
func enter_versus(stage_id: String) -> void:
	_abort_crane()
	_solo.abort()
	_close_sheet()
	_hud.set_mental(-1)
	_title.visible = false
	_hud.visible = true
	_in_game = true
	mode = "versus"
	display_anger = 0.0
	_free_customer()
	set_stage(stage_id)
	bgm.play("versus")


## カメラを指定の位置へ動かす（台の調整のミニゲームなど）
func camera_to(pos: Vector3, target: Vector3, dur: float) -> void:
	var from_pos: Vector3 = _camera.position
	var from_target: Vector3 = _cam_override_target if _cam_override else CAMERA_TARGET
	_cam_override = true
	_cam_override_pos = from_pos
	_cam_override_target = from_target
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "_cam_override_pos", pos, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "_cam_override_target", target, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## カメラをいつもの位置（カウンター）に戻す
func camera_release(dur: float) -> void:
	if not _cam_override:
		return
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "_cam_override_pos", CAMERA_POS, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "_cam_override_target", CAMERA_TARGET, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.chain().tween_callback(func() -> void: _cam_override = false)


func get_camera() -> Camera3D:
	return _camera


## 画面の一番上に部品を足す（ミニゲームの作業メモなど）
func add_overlay(c: Control) -> void:
	_ui.add_child(c)


## 台の調整のミニゲーム（要件#37）。ゲームセンターでないときは {"result": "cancelled"}
func run_crane_minigame(opts: Dictionary = {}) -> Dictionary:
	var arcade = _world.call("get_arcade")
	if arcade == null:
		return {"result": "cancelled", "cheat": false, "moved": false}
	close_machine_data()
	var mg = CraneScript.new()
	_crane_mg = mg
	add_child(mg)
	mg.setup(self, arcade, opts)
	_hud.visible = false
	var res: Dictionary = await mg.run()
	mg.queue_free()
	if _in_game:
		_hud.visible = true
	return res


## 筐体のデータ（要件#57）。「〇〇円使っても取れない」と言うお客さんの、本当の投入額を見せる。
## 嘘なら記録を示して話せばよく、本当で目安に近いなら景品を取りやすい位置に直すとよい。
var _machine_panel: Control = null


func show_machine_data(cust: Dictionary) -> void:
	close_machine_data()
	var sp: Variant = cust.get("spend", null)
	if typeof(sp) != TYPE_DICTIONARY:
		return
	var d: Dictionary = sp
	sfx.play("click", 1.2)
	var claimed: int = int(d.get("claimed", 0))
	var actual: int = int(d.get("actual", 0))
	var expected: int = int(d.get("expected", 0))
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.flat_style(UI.LCD_BG, 14, 2))
	panel.custom_minimum_size = Vector2(400, 0)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -200
	panel.offset_right = 200
	panel.offset_top = 96
	_machine_panel = panel
	_ui.add_child(panel)
	var col: VBoxContainer = UI.vbox(6)
	panel.add_child(col)
	col.add_child(UI.text(tr("筐体のデータ  サービス台 #5"), UI.S_SMALL, UI.LCD_ON, UI.F_DOT))
	col.add_child(UI.rule(Color(UI.LCD_ON.r, UI.LCD_ON.g, UI.LCD_ON.b, 0.4), 1))
	var rows: Array = [
		[tr("お客さんの話"), tr("%s円") % CraneScript.yen(claimed)],
		[tr("記録された投入額"), tr("%s円（%d プレイ）") % [CraneScript.yen(actual), actual / 100]],
		[tr("1個あたりの目安"), tr("%s円（ペイアウト率 %d%%）") % [CraneScript.yen(expected), int(d.get("payout", 30))]],
	]
	for r in rows:
		var row: HBoxContainer = UI.hbox(12)
		col.add_child(row)
		var l: Label = UI.text(str(r[0]), UI.S_BODY, UI.LCD_ON, UI.F_DOT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UI.text(str(r[1]), UI.S_BODY, UI.LCD_ON, UI.F_DOT))
	var verdict: String = ""
	if actual < int(float(claimed) * 0.6):
		verdict = tr("→ 話の金額より、記録がかなり少ない。記録をもとに落ち着いて伝えよう。")
	elif actual >= int(float(expected) * 0.8):
		verdict = tr("→ 記録どおり。目安に近いので、景品を取りやすい位置に直してもいい頃。")
	else:
		verdict = tr("→ 記録どおり。ただ、まだ目安には届いていない。")
	col.add_child(UI.para(verdict, UI.S_SMALL, UI.POP, UI.F_DOT))
	var close: Button = UI.link(tr("閉じる"), UI.S_SMALL, UI.LCD_ON)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_machine_data)
	col.add_child(close)


func close_machine_data() -> void:
	if _machine_panel != null and is_instance_valid(_machine_panel):
		_machine_panel.queue_free()
	_machine_panel = null


func _on_talk_started(duration: float) -> void:
	if _customer != null and is_instance_valid(_customer):
		_customer.call("talk", duration)


func _free_customer() -> void:
	if _customer != null and is_instance_valid(_customer):
		_customer.queue_free()
	_customer = null
	manager_leave_now()
	close_machine_data()


# ---------------------------------------------------------------- 画面遷移

func _start_solo(stage_id: String) -> void:
	sfx.play("click")
	_close_sheet()
	_title.visible = false
	_hud.visible = true
	_in_game = true
	mode = "solo"
	display_anger = 0.0
	set_stage(stage_id)
	bgm.play(stage_id)
	_solo.start(stage_id, tr(str(STAGES[stage_id]["name"])))


func _abort_crane() -> void:
	if _crane_mg != null and is_instance_valid(_crane_mg):
		_crane_mg.abort()


## チュートリアル（新人研修。要件#53）
func start_tutorial() -> void:
	sfx.play("click")
	_abort_crane()
	_solo.abort()
	_close_sheet()
	_title.visible = false
	_hud.visible = true
	_in_game = true
	mode = "tutorial"
	display_anger = 0.0
	_free_customer()
	set_stage("konbini")
	bgm.play("konbini")
	_tutorial.start()


func _offer_tutorial() -> void:
	var col: VBoxContainer = _open_sheet(520, "center")
	_sheet_title(col, tr("新人研修"))
	col.add_child(UI.para(tr("はじめまして！まずは店長の研修（チュートリアル）を受けますか？画面の見かたと、返事のコツを3分ほどで説明します。あとからタイトルの「新人研修」でも受けられます。"), UI.S_BODY, UI.INK))
	var row: HBoxContainer = UI.hbox(24)
	col.add_child(row)
	var yes: Button = UI.primary(tr("研修を受ける"), UI.S_LEAD)
	yes.pressed.connect(start_tutorial)
	row.add_child(yes)
	var later: Button = UI.link(tr("あとで"), UI.S_BODY, UI.INK_SOFT)
	later.pressed.connect(func() -> void:
		GameSettings.tutorial_seen = true
		GameSettings.save_settings()
		_close_sheet())
	row.add_child(later)


func _quit_to_title() -> void:
	_tutorial.abort()
	_abort_crane()
	_solo.abort()
	if _versus.is_active():
		_versus.leave_match()
	_versus.cancel()
	_free_customer()
	_close_sheet()
	_show_title()


func _show_title() -> void:
	_in_game = false
	mode = ""
	display_anger = 0.0
	_hud.visible = false
	_title.visible = true
	bgm.play("title")
	if _current_stage == "":
		set_stage("konbini")
	_refresh_title()


## サーバーの状態を確かめ、ログインしておく（タイトルに表示）
func _check_server() -> void:
	var res: Dictionary = await api.request("GET", "/api/v1/info", null, false)
	if bool(res.get("ok", false)):
		_server_info = res["body"]
		await api.ensure_login()
	else:
		_server_info = {"error": str(res.get("message", ""))}
	_refresh_title()


func _refresh_title() -> void:
	if _profile_label == null:
		return
	var p: Dictionary = GameSettings.last_profile
	if p.is_empty():
		_profile_label.text = tr("名札: まだ登録されていません")
	else:
		_profile_label.text = tr("名札: %s　レート %d（%s）") % [str(p.get("name", "")), int(p.get("rating", 1000)), tr(str(p.get("rank", "")))]
	if _server_info.has("error"):
		_server_label.text = tr("サーバーにつながりません（1人用は台本で遊べます）")
		_server_label.add_theme_color_override("font_color", UI.SHU)
	elif _server_info.is_empty():
		_server_label.text = tr("サーバーを確認しています…")
		_server_label.add_theme_color_override("font_color", UI.INK_SOFT)
	else:
		var parts: PackedStringArray = PackedStringArray([tr("サーバー接続中")])
		parts.append(tr("AI判定あり") if bool(_server_info.get("ai", false)) else tr("AIなし（簡易判定）"))
		if bool(_server_info.get("voice", false)):
			parts.append(tr("音声対戦あり"))
		_server_label.text = "・".join(parts)
		_server_label.add_theme_color_override("font_color", UI.OK)


## タイトル: 店頭に貼られた求人ポスター
func _build_title() -> void:
	_title = Control.new()
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_title)

	var poster: PanelContainer = UI.paper(UI.PAPER, 0, 6)
	poster.position = Vector2(56, 28)
	poster.custom_minimum_size = Vector2(500, 0)
	poster.rotation_degrees = -1.2
	# 画面に入りきらないときは縮める（英語でボタンが画面外に出て操作できなくなっていた。要件#45）
	poster.resized.connect(_fit_to_screen.bind(poster, false))
	get_viewport().size_changed.connect(func() -> void:
		if is_instance_valid(poster):
			_fit_to_screen(poster, false))
	_title.add_child(poster)
	var col: VBoxContainer = UI.vbox(0)
	poster.add_child(col)

	var band: PanelContainer = PanelContainer.new()
	band.add_theme_stylebox_override("panel", UI.flat_style(UI.SHU, 12, 0))
	col.add_child(band)
	var band_row: HBoxContainer = UI.hbox(12)
	band.add_child(band_row)
	band_row.add_child(UI.text(tr("スタッフ大募集"), UI.S_HEAD, UI.PAPER, UI.F_SIGN))
	band_row.add_child(UI.spacer())
	band_row.add_child(UI.text(tr("急募"), UI.S_BODY, UI.POP, UI.F_SIGN))

	var body: MarginContainer = MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		body.add_theme_constant_override(side, 24)
	body.add_theme_constant_override("margin_top", 16)
	body.add_theme_constant_override("margin_bottom", 8)
	col.add_child(body)
	var b: VBoxContainer = UI.vbox(4)
	body.add_child(b)
	var game_title: String = tr("カスハラ防衛線")
	b.add_child(UI.para(game_title, UI.S_HUGE if game_title.length() <= 12 else UI.S_HEAD, UI.INK, UI.F_SIGN))
	b.add_child(UI.text(tr("時給：お客様の笑顔（たぶん）"), UI.S_BODY, UI.INK_SOFT, UI.F_HAND))
	b.add_child(UI.gap(12))
	b.add_child(UI.text(tr("勤務先を選んでください"), UI.S_SMALL, UI.INK_SOFT))
	b.add_child(UI.rule(UI.INK, 2))
	for sid in STAGE_ORDER:
		var info: Dictionary = STAGES[sid]
		var row: Button = UI.link(tr(str(info["name"])) + "　→", UI.S_LEAD)
		row.pressed.connect(_start_solo.bind(str(sid)))
		b.add_child(row)
		b.add_child(UI.para(tr(str(info["desc"])), UI.S_SMALL, UI.INK_SOFT))
		b.add_child(UI.rule(UI.PAPER_DIM, 1))
	b.add_child(UI.gap(8))
	var versus: Button = UI.primary(tr("対戦する（客 vs 店員）"), UI.S_LEAD)
	versus.pressed.connect(_show_versus_lobby)
	b.add_child(versus)
	var tut: Button = UI.link(tr("新人研修（チュートリアル） →"), UI.S_BODY)
	tut.pressed.connect(start_tutorial)
	b.add_child(tut)
	b.add_child(UI.gap(8))
	_profile_label = UI.text("", UI.S_SMALL, UI.INK, UI.F_DOT)
	b.add_child(_profile_label)
	_server_label = UI.text("", UI.S_SMALL, UI.INK_SOFT)
	b.add_child(_server_label)

	# 下の「切り取りタブ」（求人ポスターの電話番号の短冊）
	var tabs: HBoxContainer = UI.hbox(0)
	col.add_child(tabs)
	for item in [["遊び方", "_show_howto"], ["設定", "_show_settings"], ["ライセンス", "_show_licenses"], ["終了", "_quit_game"]]:
		var t: Button = UI.link(tr(str(item[0])), UI.S_BODY)
		t.alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var st: StyleBoxFlat = UI.flat_style(UI.PAPER, 10, 0)
		st.border_width_top = 2
		st.border_width_left = 1
		st.border_color = UI.PAPER_DIM.darkened(0.1)
		t.add_theme_stylebox_override("normal", st)
		var sth: StyleBoxFlat = st.duplicate()
		sth.bg_color = UI.POP.lerp(UI.PAPER, 0.5)
		t.add_theme_stylebox_override("hover", sth)
		t.add_theme_stylebox_override("pressed", sth)
		t.pressed.connect(Callable(self, str(item[1])))
		tabs.add_child(t)


func _quit_game() -> void:
	get_tree().quit()


## ライセンス表記（要件#39）。Godot（MIT）と、エンジンが含むライブラリ、フォント、サーバーの依存を表示する
func _show_licenses() -> void:
	sfx.play("click")
	var col: VBoxContainer = _open_sheet(900, "left")
	_sheet_title(col, tr("ライセンス"))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var body: VBoxContainer = UI.vbox(8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	body.add_child(UI.text("Godot Engine", UI.S_LEAD, UI.INK, UI.F_BOLD))
	body.add_child(UI.para(tr("このゲームは Godot Engine で作られています。") + " https://godotengine.org/license", UI.S_SMALL, UI.INK_SOFT))
	body.add_child(UI.para(Engine.get_license_text(), UI.S_SMALL, UI.INK))
	body.add_child(UI.text(tr("フォント"), UI.S_LEAD, UI.INK, UI.F_BOLD))
	body.add_child(UI.para("Noto Sans JP (c) Google / Adobe, Yusei Magic (c) The Yusei Magic Project Authors, DotGothic16 (c) The DotGothic16 Project Authors, Dela Gothic One (c) The Dela Gothic Project Authors — SIL Open Font License 1.1", UI.S_SMALL, UI.INK))
	body.add_child(UI.text(tr("エンジンに含まれるライブラリ"), UI.S_LEAD, UI.INK, UI.F_BOLD))
	var parts: PackedStringArray = PackedStringArray()
	for info in Engine.get_copyright_info():
		var d: Dictionary = info
		var names: PackedStringArray = PackedStringArray()
		for p in (d.get("parts", []) as Array):
			var pd: Dictionary = p
			names.append("%s (%s)" % [", ".join(PackedStringArray(pd.get("copyright", []))), str(pd.get("license", ""))])
		parts.append("%s: %s" % [str(d.get("name", "")), "; ".join(names)])
	body.add_child(UI.para("\n".join(parts), UI.S_SMALL, UI.INK_SOFT))
	var ok: Button = UI.link(tr("閉じる"), UI.S_BODY)
	ok.pressed.connect(_close_sheet)
	col.add_child(ok)


# ---------------------------------------------------------------- 紙の画面（設定・遊び方・休憩・結果・ロビー）

## 暗幕の上に紙を1枚置く。align: "left" | "center" | "right"。戻り値は中身を入れる箱
func _open_sheet(width: int, align: String = "center", receipt: bool = false) -> VBoxContainer:
	_close_sheet()
	_sheet = Control.new()
	_sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_sheet)
	var shade: ColorRect = ColorRect.new()
	shade.color = UI.SHADE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet.add_child(shade)
	var holder: MarginContainer = MarginContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_theme_constant_override("margin_left", 72)
	holder.add_theme_constant_override("margin_right", 72)
	holder.add_theme_constant_override("margin_top", 32)
	holder.add_theme_constant_override("margin_bottom", 32)
	_sheet.add_child(holder)
	var row: HBoxContainer = UI.hbox(0)
	holder.add_child(row)
	if align != "left":
		row.add_child(UI.spacer())
	var panel: PanelContainer = Paper.Receipt.new() if receipt else UI.paper(UI.PAPER, 28, 6)
	panel.resized.connect(_fit_to_screen.bind(panel, true))
	panel.custom_minimum_size = Vector2(width, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(panel)
	if align != "right":
		row.add_child(UI.spacer())
	var col: VBoxContainer = UI.vbox(12)
	panel.add_child(col)
	_solo.paused = true
	_sheet_is_receipt = receipt
	_sheet_is_lobby = false
	if _hud != null:
		_hud.set_blocked(true)
	return col


## 部品が画面に入りきらないとき、全体を縮めて収める（要件#45）。centered: 真ん中を基準に縮める
func _fit_to_screen(c: Control, centered: bool) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var need: Vector2 = c.size
	if need.x <= 0.0 or need.y <= 0.0:
		return
	# 上の端は動かさずに縮める（下にはみ出した分が収まる）
	var room_y: float = vp.y - 16.0 - maxf(c.global_position.y, 0.0)
	var room_x: float = vp.x - 32.0
	var k: float = clampf(minf(room_y / need.y, room_x / need.x), 0.5, 1.0)
	c.pivot_offset = Vector2(need.x * 0.5, 0.0) if centered else Vector2.ZERO
	c.scale = Vector2(k, k)


func _close_sheet() -> void:
	if _sheet != null and is_instance_valid(_sheet):
		_sheet.queue_free()
	_sheet = null
	_lobby_status = null
	_lobby_code = null
	_solo.paused = false
	_sheet_is_receipt = false
	_sheet_is_lobby = false
	if _hud != null and is_instance_valid(_hud):
		_hud.set_blocked(false)


func _sheet_title(col: VBoxContainer, t: String) -> void:
	col.add_child(UI.text(t, UI.S_HEAD, UI.INK, UI.F_SIGN))


## 休憩中の札
func _show_pause() -> void:
	if not _in_game or _sheet != null:
		return
	var col: VBoxContainer = _open_sheet(420, "center")
	_sheet_title(col, tr("休憩中"))
	var in_versus: bool = mode == "versus"
	col.add_child(UI.para(tr("対戦中は時間が止まりません。やめると相手の勝ちになります。") if in_versus else tr("一時停止中。怒りゲージは止まっています。"), UI.S_BODY, UI.INK_SOFT))
	var resume: Button = UI.primary(tr("仕事に戻る"), UI.S_LEAD)
	resume.pressed.connect(_close_sheet)
	col.add_child(resume)
	var back: Button = UI.link(tr("対戦をやめてタイトルへ") if in_versus else tr("シフトを抜けてタイトルへ"), UI.S_BODY)
	back.pressed.connect(_quit_to_title)
	col.add_child(back)


## 遊び方: 新人向けマニュアル
func _show_howto() -> void:
	sfx.play("click")
	var col: VBoxContainer = _open_sheet(760, "left")
	_sheet_title(col, tr("新人スタッフ向けマニュアル"))
	var lines: Array = [
		"1. お客さんが来て、理不尽なクレームをつけてきます。",
		"2. 返事を考えている間、レジ表示器の「イカリ」が上がります。100になるとブチギレて失敗。",
		"3. 下の記入欄に返事を書いて Enter。接客用語のタグを押すと文に足せます。",
		"4. 謝る・気持ちをくむ・話を聞くで怒りが下がり、引き継ぎメモに沿った正しい解決策で「ナットク」が上がります。",
		"5. ナットクが100になれば成功。お客さんは帰ってくれます。",
		"6. ただし不当な要求（土下座・全部タダなど）を飲むと大きく減点。丁寧に、でもきっぱり断りましょう。",
		"7. 対戦では、客役と店員役を1ラウンドずつ交代します。客役は店員を追い詰めるセリフを言います（暴言・無言・くり返しは逆効果）。",
		"8. 音声対戦では「押して話す」ボタン（またはスペースキー）を押している間だけ声が相手に届きます。",
	]
	for l in lines:
		col.add_child(UI.para(tr(str(l)), UI.S_BODY, UI.INK))
	var ok: Button = UI.link(tr("閉じる"), UI.S_BODY)
	ok.pressed.connect(_close_sheet)
	col.add_child(ok)


## 設定: 書類の形
func _show_settings() -> void:
	sfx.play("click")
	var col: VBoxContainer = _open_sheet(720, "left")
	_sheet_title(col, tr("設定"))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 12)
	col.add_child(grid)

	var name_edit: LineEdit = UI.field(tr("名前（16文字まで）"), UI.S_BODY)
	name_edit.text = GameSettings.player_name
	name_edit.max_length = 16
	_form_row(grid, tr("名前"), name_edit)

	var lang_opt: OptionButton = _option(GameSettings.LANGS, GameSettings.language)
	_form_row(grid, tr("言語 / Language"), lang_opt)

	var src_opt: OptionButton = _option(_translated(GameSettings.SOURCES), GameSettings.solo_source)
	_form_row(grid, tr("1人用のAI"), src_opt)

	# 自分のAPIキーとモデルは「自分のAPIキー」を選んだときだけ出す（要件#33）
	var key_edit: LineEdit = UI.field("sk-ant-...", UI.S_BODY)
	key_edit.secret = true
	key_edit.text = GameSettings.api_key
	var key_label: Label = _form_row(grid, tr("自分のAPIキー"), key_edit)

	var model_opt: OptionButton = _option(_translated(GameSettings.MODELS), GameSettings.model)
	var model_label: Label = _form_row(grid, tr("自分のキーのモデル"), model_opt)
	var show_key: Callable = func(idx: int) -> void:
		var own: bool = str(GameSettings.SOURCES[maxi(idx, 0)][0]) == "own_key"
		for c in [key_edit, key_label, model_opt, model_label]:
			(c as Control).visible = own
	show_key.call(src_opt.selected)
	src_opt.item_selected.connect(show_key)

	var time_opt: OptionButton = _option(_translated(GameSettings.ANSWER_TIMES), GameSettings.answer_time)
	_form_row(grid, tr("返事の時間"), time_opt)

	var vol: HSlider = HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = GameSettings.volume
	vol.custom_minimum_size = Vector2(240, 24)
	vol.value_changed.connect(func(v: float) -> void:
		GameSettings.volume = v
		sfx.play("click"))
	_form_row(grid, tr("効果音の音量"), vol)

	var bgm_vol: HSlider = HSlider.new()
	bgm_vol.min_value = 0.0
	bgm_vol.max_value = 1.0
	bgm_vol.step = 0.05
	bgm_vol.value = GameSettings.bgm_volume
	bgm_vol.custom_minimum_size = Vector2(240, 24)
	bgm_vol.value_changed.connect(func(v: float) -> void:
		GameSettings.bgm_volume = v
		bgm.refresh_volume())
	_form_row(grid, tr("BGMの音量"), bgm_vol)

	var full: CheckBox = UI.check(tr("フルスクリーンにする"), GameSettings.fullscreen)
	_form_row(grid, tr("画面"), full)
	var res_opt: OptionButton = _option(_translated(GameSettings.RESOLUTIONS), GameSettings.resolution)
	_form_row(grid, tr("解像度"), res_opt)
	full.toggled.connect(func(on: bool) -> void: res_opt.disabled = on)
	res_opt.disabled = GameSettings.fullscreen

	col.add_child(UI.para(tr("「ゲームサーバー」では、AIの判定はサーバーで行います（APIキーは不要）。「自分のAPIキー」はサーバーが使えないときの予備で、料金はキーの持ち主にかかります。キーはこのPCの設定ファイルにだけ保存されます。「返事の時間」は1人用と、自分が作ったフレンド対戦の部屋に効きます（ランクマッチは全員同じ）。"), UI.S_SMALL, UI.INK_SOFT))
	var test_label: Label = UI.para("", UI.S_SMALL, UI.INK_SOFT)
	col.add_child(test_label)

	var row: HBoxContainer = UI.hbox(24)
	col.add_child(row)
	var save: Button = UI.primary(tr("保存する"), UI.S_LEAD)
	row.add_child(save)
	var test_btn: Button = UI.link(tr("接続を確かめる"), UI.S_BODY)
	row.add_child(test_btn)
	var close_btn: Button = UI.link(tr("保存しないで閉じる"), UI.S_BODY, UI.INK_SOFT)
	close_btn.pressed.connect(_close_sheet)
	row.add_child(close_btn)

	var apply: Callable = func() -> bool:
		var lang_before: String = GameSettings.language
		GameSettings.language = str(GameSettings.LANGS[maxi(lang_opt.selected, 0)][0])
		GameSettings.solo_source = str(GameSettings.SOURCES[maxi(src_opt.selected, 0)][0])
		GameSettings.answer_time = str(GameSettings.ANSWER_TIMES[maxi(time_opt.selected, 0)][0])
		GameSettings.api_key = key_edit.text.strip_edges()
		GameSettings.model = str(GameSettings.MODELS[maxi(model_opt.selected, 0)][0])
		GameSettings.volume = vol.value
		GameSettings.bgm_volume = bgm_vol.value
		GameSettings.fullscreen = full.button_pressed
		GameSettings.resolution = str(GameSettings.RESOLUTIONS[maxi(res_opt.selected, 0)][0])
		GameSettings.save_settings()
		GameSettings.apply_window()
		return lang_before != GameSettings.language

	test_btn.pressed.connect(func() -> void:
		apply.call()
		test_label.text = tr("確かめています…")
		var lines: PackedStringArray = PackedStringArray()
		var res: Dictionary = await api.request("GET", "/api/v1/info", null, false)
		if not is_instance_valid(test_label):
			return
		if bool(res.get("ok", false)):
			lines.append(tr("サーバー: つながりました"))
		else:
			lines.append(tr("サーバー: ") + str(res.get("message", "")))
		if GameSettings.own_key_ready():
			var t: Dictionary = await llm.test_connection()
			if not is_instance_valid(test_label):
				return
			lines.append(tr("自分のキー: ") + (tr("使えます") if not t.has("error") else str(t["error"])))
		test_label.text = "\n".join(lines))

	save.pressed.connect(func() -> void:
		var lang_changed: bool = apply.call()
		var new_name: String = name_edit.text.strip_edges()
		if new_name != "" and new_name != GameSettings.player_name and GameSettings.token != "":
			await api.rename(new_name)
		elif new_name != "":
			GameSettings.player_name = new_name
			GameSettings.save_settings()
		if lang_changed:
			GameSettings.apply_language()
			_rebuild_ui()
		_close_sheet()
		_server_info = {}
		_refresh_title()
		_check_server())


func _translated(items: Array) -> Array:
	var out: Array = []
	for it in items:
		out.append([it[0], tr(str(it[1]))])
	return out


func _option(items: Array, current: String) -> OptionButton:
	var o: OptionButton = UI.option()
	for i in range(items.size()):
		o.add_item(str(items[i][1]), i)
		if str(items[i][0]) == current:
			o.select(i)
	return o


func _form_row(grid: GridContainer, label: String, control: Control) -> Label:
	var l: Label = UI.text(label, UI.S_BODY, UI.INK_SOFT)
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)
	return l


## 言語を変えたとき、文言を作り直す
func _rebuild_ui() -> void:
	if _title != null:
		_title.queue_free()
	var old_hud = _hud
	_make_hud()
	_solo.attach_hud(_hud)
	_versus.attach_hud(_hud)
	_tutorial.hud = _hud
	old_hud.queue_free()
	_build_title()
	_show_title()


# ---------------------------------------------------------------- 1人用の結果（レシート）

static func rank_for(total: int) -> Array:
	for r in RANKS:
		if total >= int(r[0]):
			return r
	return RANKS[RANKS.size() - 1]


func _receipt_line(col: VBoxContainer, left: String, right: String, size: int = UI.S_BODY, color: Color = UI.INK) -> void:
	var row: HBoxContainer = UI.hbox(8)
	col.add_child(row)
	var l: Label = UI.text(left, size, color, UI.F_DOT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	row.add_child(l)
	var r: Label = UI.text(right, size, color, UI.F_DOT)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(r)


func _receipt_rule(col: VBoxContainer) -> void:
	col.add_child(UI.text("- - - - - - - - - - - - - - - - - - - - - -", UI.S_SMALL, UI.INK_SOFT, UI.F_DOT))


func _on_solo_finished(stage_id: String, results: Array, total: int) -> void:
	var is_best: bool = GameSettings.submit_score(stage_id, total)
	var rank: Array = rank_for(total)
	sfx.play("win" if total >= 2400 else "lose")
	var col: VBoxContainer = _open_sheet(440, "center", true)
	col.add_theme_constant_override("separation", 6)
	var shop: Label = UI.text(tr(str(STAGES[stage_id]["name"])), UI.S_LEAD, UI.INK, UI.F_DOT)
	shop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(shop)
	var date: Label = UI.text(Time.get_datetime_string_from_system(false, true) + "  " + tr("シフト明細"), UI.S_SMALL, UI.INK_SOFT, UI.F_DOT)
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(date)
	_receipt_rule(col)
	for r in results:
		var res: Dictionary = r
		var outcome: String = str(res.get("outcome", ""))
		var mark: String = tr("納得")
		if outcome == "explode":
			mark = tr("激怒")
		elif outcome == "yield":
			mark = tr("屈服")
		elif outcome == "breakdown":
			mark = tr("早退")
		_receipt_line(col, "%s  %s" % [str(res.get("title", "")), mark], "%+d" % int(res.get("points", 0)))
	# 売上と店舗レビュー（要件#56）
	var sm: Dictionary = _solo.summary
	if not sm.is_empty():
		_receipt_rule(col)
		if int(sm.get("payout", -1)) > 0:
			_receipt_line(col, tr("クレーンのペイアウト率"), "%d%%" % int(sm["payout"]), UI.S_SMALL, UI.INK_SOFT)
		_receipt_line(col, tr("売上"), tr("%s円") % CraneScript.yen(int(sm.get("sales", 0))))
		_receipt_line(col, "  " + tr("売上ボーナス"), "%+d" % int(sm.get("sales_bonus", 0)), UI.S_SMALL)
		var stars: float = float(sm.get("review", 3.0))
		_receipt_line(col, tr("店舗レビュー"), "%s %.1f" % ["★".repeat(int(round(stars))) + "☆".repeat(5 - int(round(stars))), stars])
		_receipt_line(col, "  " + tr("レビューボーナス"), "%+d" % int(sm.get("review_bonus", 0)), UI.S_SMALL)
	_receipt_rule(col)
	_receipt_line(col, tr("合計"), tr("%d 点") % total, UI.S_HEAD)
	_receipt_line(col, tr("ランク"), "%s  %s" % [str(rank[1]), tr(str(rank[2]))], UI.S_BODY)
	if is_best:
		_receipt_line(col, tr("★ ハイスコア更新"), "", UI.S_BODY, UI.SHU)
	_receipt_rule(col)
	var thanks: Label = UI.text(tr("またのご来店をお待ちしております"), UI.S_SMALL, UI.INK_SOFT, UI.F_DOT)
	thanks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(thanks)
	col.add_child(UI.gap(8))
	var again: Button = UI.primary(tr("もう一度シフトに入る"), UI.S_LEAD)
	again.pressed.connect(_start_solo.bind(stage_id))
	col.add_child(again)
	var back: Button = UI.link(tr("タイトルへ戻る"), UI.S_BODY)
	back.alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.pressed.connect(_quit_to_title)
	col.add_child(back)


# ---------------------------------------------------------------- 対戦ロビー（バックヤードの掲示板）

func _show_versus_lobby() -> void:
	sfx.play("click")
	_close_sheet()
	_sheet = Control.new()
	_sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_sheet)
	_sheet_is_lobby = true
	_hud.set_blocked(true)
	var use_eos: bool = _versus.eos_available()
	var board: Panel = Panel.new()
	board.add_theme_stylebox_override("panel", UI.flat_style(Color("#5b4636"), 0, 0))
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet.add_child(board)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 32)
	_sheet.add_child(margin)
	var root: VBoxContainer = UI.vbox(16)
	margin.add_child(root)

	var head: HBoxContainer = UI.hbox(16)
	root.add_child(head)
	head.add_child(UI.text(tr("バックヤード掲示板"), UI.S_HEAD, UI.PAPER, UI.F_SIGN))
	head.add_child(UI.spacer())
	var p: Dictionary = GameSettings.last_profile
	head.add_child(UI.text(tr("あなた: %s　レート %d（%s）") % [str(p.get("name", GameSettings.player_name)), int(p.get("rating", 1000)), tr(str(p.get("rank", "")))], UI.S_BODY, UI.POP, UI.F_DOT))

	# 形式（文字・音声）
	var fmt_row: HBoxContainer = UI.hbox(8)
	root.add_child(fmt_row)
	fmt_row.add_child(UI.text(tr("対戦の形式:"), UI.S_BODY, UI.PAPER))
	var group: ButtonGroup = ButtonGroup.new()
	for f in [["text", "文字で言い合う"], ["voice", "声で言い合う（ボイスチャット）"]]:
		var t: Button = UI.tag(tr(str(f[1])), UI.S_BODY)
		t.toggle_mode = true
		t.button_group = group
		t.button_pressed = _vs_format == str(f[0])
		var fid: String = str(f[0])
		t.toggled.connect(func(on: bool) -> void:
			if on:
				_vs_format = fid)
		if fid == "voice" and _server_info.has("voice") and not bool(_server_info.get("voice", false)):
			t.disabled = true
			t.tooltip_text = tr("このサーバーは音声対戦に対応していません")
		fmt_row.add_child(t)

	var notes: HBoxContainer = UI.hbox(24)
	notes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(notes)

	# ランクマッチ
	var ranked: PanelContainer = UI.paper(UI.PAPER, 20, 5)
	ranked.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ranked.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	notes.add_child(ranked)
	var rc: VBoxContainer = UI.vbox(10)
	ranked.add_child(rc)
	rc.add_child(UI.text(tr("ランクマッチ"), UI.S_LEAD, UI.INK, UI.F_SIGN))
	rc.add_child(UI.para(tr("レートの近い相手を探します。待つほど範囲が広がります。勝敗でレートが動きます。同じ言語の人どうしで組みます。"), UI.S_SMALL, UI.INK_SOFT))
	var find: Button = UI.primary(tr("相手を探す"), UI.S_LEAD)
	find.pressed.connect(func() -> void:
		sfx.play("click")
		if use_eos:
			_versus.request_eos("ranked", _vs_format)
		else:
			_versus.request("queue", _vs_format))
	rc.add_child(find)
	if use_eos:
		rc.add_child(UI.para(tr("Epic Online Services で相手を探します。見つからなければゲームサーバーで探します。"), UI.S_SMALL, UI.INK_SOFT))

	# フレンド対戦
	var friend: PanelContainer = UI.paper(UI.POP, 20, 5)
	friend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friend.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	notes.add_child(friend)
	var fc: VBoxContainer = UI.vbox(10)
	friend.add_child(fc)
	fc.add_child(UI.text(tr("フレンド対戦"), UI.S_LEAD, UI.INK, UI.F_SIGN))
	fc.add_child(UI.para(tr("部屋コードを友達に教えて、その人とだけ遊びます。レートは動きません。"), UI.S_SMALL, UI.INK))
	var make: Button = UI.link(tr("部屋を作る →"), UI.S_BODY)
	make.pressed.connect(func() -> void:
		sfx.play("click")
		_versus.request("room_create", _vs_format))
	fc.add_child(make)
	if use_eos:
		var invite: Button = UI.link(tr("Epic のフレンドを招待する →"), UI.S_BODY)
		invite.pressed.connect(func() -> void:
			sfx.play("click")
			_versus.request_eos("invite", _vs_format))
		fc.add_child(invite)
	_lobby_code = UI.text("", UI.S_HEAD, UI.INK, UI.F_DOT)
	fc.add_child(_lobby_code)
	var join_row: HBoxContainer = UI.hbox(8)
	fc.add_child(join_row)
	var code_edit: LineEdit = UI.field(tr("部屋コード"), UI.S_BODY)
	code_edit.max_length = 8
	join_row.add_child(code_edit)
	var join: Button = UI.link(tr("参加する →"), UI.S_BODY)
	join.pressed.connect(func() -> void:
		var code: String = code_edit.text.strip_edges()
		if code != "":
			sfx.play("click")
			_versus.request("room_join", _vs_format, code))
	join_row.add_child(join)

	# ランキング（シフト表の形）
	var board_note: PanelContainer = UI.paper(UI.PAPER, 20, 5)
	board_note.custom_minimum_size = Vector2(320, 0)
	board_note.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	notes.add_child(board_note)
	var bc: VBoxContainer = UI.vbox(4)
	board_note.add_child(bc)
	bc.add_child(UI.text(tr("今月の優秀スタッフ"), UI.S_LEAD, UI.INK, UI.F_SIGN))
	var list: VBoxContainer = UI.vbox(2)
	bc.add_child(list)
	list.add_child(UI.text(tr("読み込み中…"), UI.S_SMALL, UI.INK_SOFT, UI.F_DOT))
	_load_leaderboard(list)

	var foot: HBoxContainer = UI.hbox(24)
	root.add_child(foot)
	_lobby_status = UI.para("", UI.S_BODY, UI.PAPER)
	foot.add_child(_lobby_status)
	var stop: Button = UI.link(tr("探すのをやめる"), UI.S_BODY, UI.PAPER)
	stop.pressed.connect(func() -> void:
		_versus.cancel()
		_set_lobby_status(tr("やめました"), false)
		if _lobby_code != null:
			_lobby_code.text = "")
	foot.add_child(stop)
	var back: Button = UI.link(tr("タイトルへ戻る"), UI.S_BODY, UI.PAPER)
	back.pressed.connect(func() -> void:
		_versus.cancel()
		_close_sheet()
		_refresh_title())
	foot.add_child(back)


func _load_leaderboard(list: VBoxContainer) -> void:
	var res: Dictionary = await api.request("GET", "/api/v1/leaderboard?limit=10", null, false)
	if not is_instance_valid(list):
		return
	for c in list.get_children():
		c.queue_free()
	if not bool(res.get("ok", false)):
		list.add_child(UI.para(tr("サーバーにつながりません"), UI.S_SMALL, UI.SHU))
		return
	var players: Array = (res["body"] as Dictionary).get("players", [])
	if players.is_empty():
		list.add_child(UI.text(tr("まだ誰もいません"), UI.S_SMALL, UI.INK_SOFT, UI.F_DOT))
	for pl in players:
		var d: Dictionary = pl
		var row: HBoxContainer = UI.hbox(8)
		list.add_child(row)
		var n: Label = UI.text("%2d %s" % [int(d.get("rank", 0)), str(d.get("name", ""))], UI.S_SMALL, UI.INK, UI.F_DOT)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		row.add_child(n)
		row.add_child(UI.text(str(int(d.get("rating", 0))), UI.S_SMALL, UI.INK, UI.F_DOT))


func _set_lobby_status(t: String, is_error: bool) -> void:
	if _lobby_status != null and is_instance_valid(_lobby_status):
		_lobby_status.text = t
		_lobby_status.add_theme_color_override("font_color", Color("#ffb3a3") if is_error else UI.PAPER)


func _on_lobby_event(kind: String, data: Dictionary) -> void:
	match kind:
		"status":
			_set_lobby_status(str(data.get("text", "")), false)
		"queued":
			_set_lobby_status(tr("相手を探しています…"), false)
		"queue_status":
			var rng: Variant = data.get("range", null)
			var range_text: String = tr("誰とでも") if rng == null else tr("レート差 %d まで") % int(rng)
			_set_lobby_status(tr("相手を探しています… %d 秒（%s・待っている人 %d）") % [int(data.get("seconds", 0)), range_text, int(data.get("waiting_players", 0))], false)
		"room_created":
			if _lobby_code != null and is_instance_valid(_lobby_code):
				_lobby_code.text = str(data.get("code", ""))
			_set_lobby_status(tr("部屋を作りました。コードを友達に伝えて、参加を待っています…"), false)
		"cancelled":
			_set_lobby_status(tr("やめました"), false)
		"error":
			_set_lobby_status(str(data.get("message", tr("エラーが起きました"))), true)


func _on_versus_finished(summary: Dictionary) -> void:
	if smoke:
		print("VERSUS OK ", summary)
		await get_tree().create_timer(1.0).timeout
		get_tree().quit(0)
		return
	var result: String = str(summary.get("result", "draw"))
	sfx.play("win" if result == "win" else "lose")
	var col: VBoxContainer = _open_sheet(460, "center", true)
	col.add_theme_constant_override("separation", 6)
	var head: Label = UI.text(tr("対戦結果"), UI.S_LEAD, UI.INK, UI.F_DOT)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	var big: Label = UI.text({"win": tr("勝ち"), "lose": tr("負け"), "draw": tr("引き分け")}.get(result, ""), UI.S_HUGE, UI.SHU if result == "win" else UI.INK, UI.F_SIGN)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(big)
	var reason: String = str(summary.get("reason", ""))
	if reason == "disconnected" or reason == "left":
		col.add_child(UI.para(tr("相手が途中で抜けたため、決着しました。") if result == "win" else tr("途中で抜けたため、負けになりました。"), UI.S_SMALL, UI.INK_SOFT))
	_receipt_rule(col)
	_receipt_line(col, tr("あなた"), tr("%d 点") % int(summary.get("you_points", 0)))
	_receipt_line(col, tr("相手"), tr("%d 点") % int(summary.get("opponent_points", 0)))
	_receipt_rule(col)
	if str(summary.get("kind", "")) == "ranked":
		_receipt_line(col, tr("レート"), "%d → %d" % [int(summary.get("rating_before", 0)), int(summary.get("rating_after", 0))], UI.S_LEAD)
		_receipt_line(col, "", "%+d" % int(summary.get("rating_delta", 0)), UI.S_LEAD, UI.SHU if int(summary.get("rating_delta", 0)) >= 0 else UI.INK)
		_receipt_line(col, tr("ランク"), tr(str(summary.get("rank", ""))))
		match str(summary.get("rating_note", "")):
			"same_pair":
				col.add_child(UI.para(tr("同じ相手と続けて対戦したため、レートは変わりません。"), UI.S_SMALL, UI.INK_SOFT))
			"early_leave":
				col.add_child(UI.para(tr("始まってすぐに決着したため、勝った側のレートは上がりません。"), UI.S_SMALL, UI.INK_SOFT))
	else:
		_receipt_line(col, tr("フレンド対戦"), tr("レート変動なし"))
	_receipt_rule(col)
	col.add_child(UI.gap(8))
	var again: Button = UI.primary(tr("もう一戦"), UI.S_LEAD)
	again.pressed.connect(func() -> void:
		_free_customer()
		_in_game = false
		_hud.visible = false
		_show_title()
		_show_versus_lobby())
	col.add_child(again)
	var back: Button = UI.link(tr("タイトルへ戻る"), UI.S_BODY)
	back.alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.pressed.connect(_quit_to_title)
	col.add_child(back)


# ---------------------------------------------------------------- 自動テスト

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


## 1人用を全ステージ自動プレイする。成功で終了コード0
func _run_smoke() -> void:
	Engine.time_scale = 8.0
	get_tree().create_timer(200.0, true, false, true).timeout.connect(func() -> void:
		print("SMOKE TIMEOUT")
		get_tree().quit(1))
	print("SMOKE source=", GameSettings.solo_source, " lang=", GameSettings.language)
	if GameSettings.solo_source == "server":
		var me: Dictionary = await api.ensure_login()
		print("SMOKE login: ", me)
		if me.has("error"):
			get_tree().quit(1)
			return
	# チュートリアル（要件#53）を自動で最後まで
	print("SMOKE tutorial")
	_tutorial.auto = true
	start_tutorial()
	await _tutorial.finished
	_tutorial.auto = false
	print("SMOKE tutorial done")
	for sid in STAGE_ORDER:
		print("SMOKE stage: ", sid)
		_start_solo(str(sid))
		var res: Array = await _solo.finished
		print("SMOKE result: ", res[1], " total=", res[2])
	print("SMOKE OK")
	get_tree().quit(0)


## ランクマッチに並んで対戦を自動プレイする（2つ同時に起動して使う）
func _run_versus_smoke(format: String) -> void:
	Engine.time_scale = 4.0
	get_tree().create_timer(240.0, true, false, true).timeout.connect(func() -> void:
		print("VERSUS TIMEOUT")
		get_tree().quit(1))
	_show_versus_lobby()
	_versus.request("queue", format)


# ---------------------------------------------------------------- スクリーンショット撮影

func _shot(dir: String, id: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_jpg(dir.path_join(id + ".jpg"), 0.88)
	print("SHOT ", id)


## 主な画面を docs/screenshots/ に保存して終了する（見た目の確認用。サーバーにはつながない）
func _run_shots() -> void:
	var dir: String = ProjectSettings.globalize_path("res://docs/screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_tree().create_timer(500.0).timeout.connect(func() -> void:
		print("SHOTS TIMEOUT")
		get_tree().quit(1))
	# --shot-tag=xxx で、画面サイズ違いの撮影を別の名前で保存する
	var tag: String = _arg("--shot-tag=")
	var prefix: String = GameSettings.language + ("_" + tag if tag != "" else "") + "_"
	GameSettings.last_profile = {"name": "テスト店員" if GameSettings.language == "ja" else "Test Clerk", "rating": 1084, "rank": "バイトリーダー"}
	_server_info = {"ai": true, "voice": true}
	_refresh_title()
	await _wait(1.5)
	await _shot(dir, prefix + "01_title")
	# チュートリアル（要件#53）: 引き継ぎメモを指しているところ
	_tutorial.auto = true
	_tutorial.hold_step = 3
	start_tutorial()
	await _tutorial.held
	await _shot(dir, prefix + "02_tutorial")
	_tutorial.hold_step = -1
	_tutorial.resume()
	await _tutorial.finished
	_tutorial.auto = false
	_free_customer()
	for sid in STAGE_ORDER:
		var s: String = str(sid)
		# ゲームセンターは、メモが一番長いお客さん（重なりのバグの再現用。要件#44）
		var list: Array = ScenariosScript.customers(s)
		var cust: Dictionary = list[0]
		if s == "arcade":
			for c in list:
				if str((c as Dictionary).get("memo", "")).length() + str((c as Dictionary).get("demand", "")).length() > str(cust.get("memo", "")).length() + str(cust.get("demand", "")).length():
					cust = c
			# 「〇〇円使っても取れない」のお客さん（要件#57）で撮る
			for c in list:
				if bool((c as Dictionary).get("spend", false)):
					cust = c
					break
		cust = ScenariosScript.materialize_spend(cust.duplicate(true), 20)
		_title.visible = false
		_hud.visible = true
		_in_game = true
		display_anger = 38.0
		set_stage(s)
		_hud.clear_round()
		_hud.set_top(tr(str(STAGES[s]["name"])), tr("お客さん %d / %d") % [1, 4], tr("%d 点") % 0)
		await spawn_customer(cust["look"])
		_hud.set_memo(str(cust["title"]), str(cust["memo"]), str(cust["demand"]))
		_hud.set_gauges(38.0, 20.0, 42.0)
		_hud.set_mental(72.0)
		_hud.set_actions(ShopActionsScript.buttons(s, cust, true))
		_hud.set_input_enabled(true, "")
		await customer_say(tr("%s（%s）") % [str(cust["title"]), str(cust["name"])], str(cust["opening"]))
		_hud.set_input_enabled(true, tr("ここに返事を書く…"))
		_hud.set_status(tr("キレられる前に返事を書こう（Enterで渡す）"))
		await _wait(0.6)
		await _shot(dir, prefix + s + "_1_play")
		display_anger = 92.0
		_hud.set_gauges(92.0, 20.0, 6.0)
		_hud.show_delta(18, 0)
		_hud.show_banner(tr("ブチギレ！") + "  -300", Color("#ff8a6a"))
		await customer_say(tr("%s（%s）") % [str(cust["title"]), str(cust["name"])], str((cust["lines"] as Dictionary)["angry"][0]), true)
		customer_react("angry")
		await _wait(0.8)
		await _shot(dir, prefix + s + "_2_angry")
		_hud.set_voice_mode(true)
		_hud.set_input_enabled(true, "")
		await _wait(0.3)
		await _shot(dir, prefix + s + "_3_voice")
		_hud.set_voice_mode(false)
		# 店長がアドバイスに来るイベント（要件#52）
		_hud.set_input_enabled(false, "")
		_hud.show_banner(tr("店長が来た！"), UI.POP)
		await manager_enter()
		manager_talk(3.0)
		var kws: Array = cust.get("solution_keywords", [])
		_hud.set_comment(tr("店長: ") + (tr("「%s」の方向で話してみろ。") % str(kws[0] if not kws.is_empty() else "")) + " " + tr("要求は飲むなよ。"))
		await _wait(0.5)
		await _shot(dir, prefix + s + "_3b_manager")
		manager_leave_now()
		_hud.visible = false
		_cam_override = true
		_cam_override_pos = Vector3(3.9, 2.5, 1.6)
		_cam_override_target = Vector3(-1.5, 0.9, -4.5)
		await _wait(0.4)
		await _shot(dir, prefix + s + "_4_wide")
		_cam_override = false
		if s == "arcade":
			# 台の調整のミニゲーム（要件#37）
			_hud.visible = true
			# 筐体のデータ（要件#57）
			show_machine_data(cust)
			await _wait(0.4)
			await _shot(dir, prefix + "arcade_4b_machine_data")
			close_machine_data()
			# 確率設定で開く（要件#55）
			GameSettings.crane_mode = "prob"
			GameSettings.crane_payout = 20
			run_crane_minigame({"mode": "adjust", "customer": cust})
			await _wait(1.8)
			await _shot(dir, prefix + "arcade_5_crane_adjust")
			GameSettings.crane_mode = "power"
			GameSettings.crane_payout = 30
			_crane_mg._auto_adjust()
			await _wait(4.2)
			await _shot(dir, prefix + "arcade_6_crane_play")
			await _wait(6.0)
			_hud.visible = false
		_free_customer()
	display_anger = 0.0
	_hud.visible = true
	var cs: Array = ScenariosScript.customers("arcade")
	_solo.summary = {"sales": 21400, "review": 3.6, "sales_bonus": 70, "review_bonus": 240, "payout": 25}
	_on_solo_finished("arcade", [
		{"title": cs[0]["title"], "outcome": "resolved", "points": 1520, "turns": 3},
		{"title": cs[1]["title"], "outcome": "explode", "points": -300, "turns": 2},
		{"title": cs[5]["title"], "outcome": "resolved", "points": 1430, "turns": 4},
		{"title": cs[4]["title"], "outcome": "yield", "points": -600, "turns": 1},
	], 2050)
	await _wait(0.6)
	await _shot(dir, prefix + "05_result")
	_close_sheet()
	_show_title()
	_show_settings()
	await _wait(0.6)
	await _shot(dir, prefix + "06_settings")
	_show_howto()
	await _wait(0.6)
	await _shot(dir, prefix + "07_howto")
	_show_versus_lobby()
	_on_lobby_event("room_created", {"code": "K7QX2M"})
	await _wait(1.0)
	await _shot(dir, prefix + "08_lobby")
	_close_sheet()
	_in_game = true
	_title.visible = false
	_hud.visible = true
	_on_versus_finished({"result": "win", "reason": "completed", "kind": "ranked", "you_points": 312, "opponent_points": 184,
		"rating_before": 1068, "rating_after": 1084, "rating_delta": 16, "rank": "バイトリーダー"})
	await _wait(0.6)
	await _shot(dir, prefix + "09_versus_result")
	print("SHOTS OK")
	get_tree().quit(0)
