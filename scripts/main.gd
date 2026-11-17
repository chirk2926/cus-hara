extends Node
## アプリ全体の司令塔。3Dステージ・カメラ・お客さんキャラ・各画面（タイトル/設定/遊び方/結果/メニュー）を管理し、
## ゲームモード（solo_game.gd）に「見た目を動かす」ための関数を提供する。
##
## 起動引数 `-- --smoke` を付けると、台本モードで全ステージを自動プレイして終了する（CIの動作確認用）。

const StageWorldScript = preload("res://scripts/stage_world.gd")
const CustomerScript = preload("res://scripts/customer_character.gd")
const HudScript = preload("res://scripts/hud.gd")
const SoloScript = preload("res://scripts/solo_game.gd")
const LlmScript = preload("res://scripts/llm_client.gd")
const SfxScript = preload("res://scripts/sfx.gd")
const UI = preload("res://scripts/ui_kit.gd")
const ScenariosScript = preload("res://scripts/scenarios.gd")

const GAME_TITLE: String = "カスハラ防衛線"
const CAMERA_POS: Vector3 = Vector3(0.0, 1.55, 1.9)
const CAMERA_TARGET: Vector3 = Vector3(0.0, 1.28, -0.35)
const STAGE_ORDER: Array = ["konbini", "arcade"]
const STAGES: Dictionary = {
	"konbini": {
		"name": "コンビニ「ハッピーマート」",
		"short": "コンビニ",
		"desc": "24時間営業。弁当、レジ袋、年齢確認…火種は無限大。",
	},
	"arcade": {
		"name": "ゲームセンター「ゲームパラダイス」",
		"short": "ゲームセンター",
		"desc": "クレーンゲームだらけの店。「取れない」は全部こちらのせい。",
	},
}
const RANKS: Array = [
	[5600, "S", "伝説のクレーム処理班"],
	[4000, "A", "頼れるバイトリーダー"],
	[2400, "B", "一人前のスタッフ"],
	[800, "C", "研修中スタッフ"],
	[-999999, "D", "店長に呼び出されるスタッフ"],
]

# ゲームモードから参照される公開メンバー
var sfx = null
var llm = null
var smoke: bool = false
var display_anger: float = 0.0   # 0〜100。3Dの表情・照明に反映される

var _world = null
var _camera: Camera3D = null
var _customer = null
var _hud = null
var _solo = null
var _ui: CanvasLayer = null
var _title: Control = null
var _overlay: Control = null
var _mode_label: Label = null
var _score_label: Label = null
var _current_stage: String = ""
var _shake: float = 0.0
var _time: float = 0.0
var _in_game: bool = false
var _cam_override: bool = false
var _cam_override_pos: Vector3 = Vector3.ZERO
var _cam_override_target: Vector3 = Vector3.ZERO


func _ready() -> void:
	randomize()
	smoke = OS.get_cmdline_user_args().has("--smoke")

	sfx = SfxScript.new()
	add_child(sfx)
	llm = LlmScript.new()
	add_child(llm)

	_world = StageWorldScript.new()
	_world.set("label_font", UI.bold_font())
	add_child(_world)
	_camera = Camera3D.new()
	_camera.fov = 60.0
	add_child(_camera)
	_camera.position = CAMERA_POS
	_camera.look_at(CAMERA_TARGET, Vector3.UP)
	_camera.current = true

	_ui = CanvasLayer.new()
	add_child(_ui)
	_hud = HudScript.new()
	_hud.sfx = sfx
	_ui.add_child(_hud)
	_hud.visible = false
	_hud.pause_pressed.connect(_show_pause)
	_hud.talk_started.connect(_on_talk_started)

	_solo = SoloScript.new()
	add_child(_solo)
	_solo.setup(self, _hud)
	_solo.finished.connect(_on_solo_finished)

	_build_title()
	_show_title()

	if smoke:
		_run_smoke()
	elif OS.get_cmdline_user_args().has("--shots"):
		_run_shots()


func _process(delta: float) -> void:
	_time += delta
	# カメラ: タイトルではゆっくり揺れ、プレイ中は固定＋ブチギレ時の揺れ
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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _overlay != null:
			_close_overlay()
		elif _in_game:
			_show_pause()


# ---------------------------------------------------------------- ゲームモード向けAPI

func set_stage(stage_id: String) -> void:
	if stage_id == _current_stage:
		return
	_current_stage = stage_id
	_world.call("build", stage_id)


## お客さんを入口から歩かせ、カウンター前に着くまで待つ
func spawn_customer(look: Dictionary) -> void:
	_free_customer()
	_customer = CustomerScript.new()
	add_child(_customer)
	_customer.call("setup", look)
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


func customer_say(speaker: String, text: String) -> void:
	await _hud.say(speaker, text)


func customer_react(kind: String) -> void:
	if _customer != null and is_instance_valid(_customer):
		_customer.call("react", kind)


func shake(strength: float) -> void:
	_shake = maxf(_shake, strength)


func _on_talk_started(duration: float) -> void:
	if _customer != null and is_instance_valid(_customer):
		_customer.call("talk", duration)


func _free_customer() -> void:
	if _customer != null and is_instance_valid(_customer):
		_customer.queue_free()
	_customer = null


# ---------------------------------------------------------------- 画面遷移

func _start_solo(stage_id: String) -> void:
	sfx.play("click")
	_close_overlay()
	_title.visible = false
	_hud.visible = true
	_in_game = true
	display_anger = 0.0
	set_stage(stage_id)
	_solo.start(stage_id, str(STAGES[stage_id]["name"]))


func _quit_to_title() -> void:
	_solo.abort()
	_free_customer()
	_close_overlay()
	_show_title()


func _show_title() -> void:
	_in_game = false
	display_anger = 0.0
	_hud.visible = false
	_title.visible = true
	if _current_stage == "":
		set_stage("konbini")
	_refresh_title()


func _refresh_title() -> void:
	if GameSettings.llm_ready():
		_mode_label.text = "AIお客さんモード: ON（毎回ちがうお客さんをAIが生成）"
		_mode_label.add_theme_color_override("font_color", UI.C_GREEN.lightened(0.3))
	else:
		_mode_label.text = "台本モード（設定でAPIキーを入れるとAIがお客さんを生成）"
		_mode_label.add_theme_color_override("font_color", UI.C_MUTED)
	var parts: PackedStringArray = PackedStringArray()
	for sid in STAGE_ORDER:
		parts.append("%s %d" % [str(STAGES[sid]["short"]), GameSettings.get_high_score(str(sid))])
	_score_label.text = "ハイスコア  " + "  /  ".join(parts)


func _build_title() -> void:
	_title = Control.new()
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_title)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.06, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.add_child(shade)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 48)
	_title.add_child(margin)
	var row: HBoxContainer = HBoxContainer.new()
	margin.add_child(row)
	var card: PanelContainer = UI.panel(Color(0.06, 0.07, 0.12, 0.88), 22, 28)
	card.custom_minimum_size = Vector2(520, 0)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(card)
	row.add_child(UI.spacer())
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)

	var title: Label = UI.label(GAME_TITLE, 60, UI.C_ACCENT, true)
	title.add_theme_color_override("font_outline_color", Color(0.5, 0.1, 0.1))
	title.add_theme_constant_override("outline_size", 10)
	col.add_child(title)
	col.add_child(UI.label("〜お客様は神様…ですか？〜", 20, UI.C_TEXT))
	col.add_child(UI.wrap_label("理不尽なお客さんがキレる前に、言葉だけで切り抜けろ。", 16, UI.C_MUTED))
	col.add_child(UI.spacer(false, Vector2(0, 8)))

	for sid in STAGE_ORDER:
		var info: Dictionary = STAGES[sid]
		var b: Button = UI.button("%sで働く" % str(info["short"]), 26, UI.C_RED if str(sid) == "konbini" else UI.C_PURPLE)
		b.tooltip_text = str(info["desc"])
		b.pressed.connect(_start_solo.bind(str(sid)))
		col.add_child(b)
		col.add_child(UI.wrap_label(str(info["desc"]), 14, UI.C_MUTED))

	var versus: Button = UI.button("対戦（客 vs 店員）― 準備中", 20, UI.C_GRAY)
	versus.disabled = true
	col.add_child(versus)

	var sub: HBoxContainer = HBoxContainer.new()
	sub.add_theme_constant_override("separation", 10)
	col.add_child(sub)
	var how: Button = UI.button("遊び方", 20, UI.C_BLUE)
	how.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	how.pressed.connect(_show_howto)
	sub.add_child(how)
	var opt: Button = UI.button("設定", 20, UI.C_GRAY)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.pressed.connect(_show_settings)
	sub.add_child(opt)
	var quit: Button = UI.button("終了", 20, Color(0.2, 0.2, 0.25))
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit.pressed.connect(func() -> void: get_tree().quit())
	sub.add_child(quit)

	_mode_label = UI.wrap_label("", 14, UI.C_MUTED)
	col.add_child(_mode_label)
	_score_label = UI.wrap_label("", 14, UI.C_TEXT)
	col.add_child(_score_label)


# ---------------------------------------------------------------- オーバーレイ（設定・遊び方・結果・メニュー）

## 画面中央にパネルを出す。戻り値は中身を入れる VBoxContainer。
func _open_overlay(title_text: String, width: int = 640) -> VBoxContainer:
	_close_overlay()
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_overlay)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.62)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(shade)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var card: PanelContainer = UI.panel(Color(0.08, 0.09, 0.15, 0.98), 20, 26, Color(1, 1, 1, 0.15), 2)
	card.custom_minimum_size = Vector2(width, 0)
	center.add_child(card)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	card.add_child(col)
	col.add_child(UI.label(title_text, 30, UI.C_ACCENT, true))
	_solo.paused = true
	return col


func _close_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	_solo.paused = false


func _show_pause() -> void:
	if not _in_game or _overlay != null:
		return
	var col: VBoxContainer = _open_overlay("メニュー", 420)
	col.add_child(UI.wrap_label("一時停止中。怒りゲージは止まっています。", 16, UI.C_MUTED))
	var resume: Button = UI.button("つづける", 24, UI.C_GREEN)
	resume.pressed.connect(_close_overlay)
	col.add_child(resume)
	var back: Button = UI.button("タイトルへ戻る", 20, UI.C_GRAY)
	back.pressed.connect(_quit_to_title)
	col.add_child(back)


func _show_howto() -> void:
	sfx.play("click")
	var col: VBoxContainer = _open_overlay("遊び方", 760)
	var lines: Array = [
		"① お客さんが来店し、理不尽なクレームをつけてきます。",
		"② 返事を考えている間、怒りゲージがじわじわ上がります。100になるとブチギレて失敗。",
		"③ 入力欄に返事を書いて Enter。定型文ボタンを押すと文章に追加できます。",
		"④ 謝罪・共感・聞く姿勢で怒りが下がり、「状況メモ」に沿った正しい解決策で納得ゲージが上がります。",
		"⑤ 納得ゲージが100になれば成功。お客さんは帰ってくれます。",
		"⑥ ただし「不当な要求」（土下座・全部タダなど）を飲むと大きく減点。丁寧に、でも毅然と断りましょう。",
		"⑦ 1シフト4人。合計スコアでランク（S〜D）が決まります。",
	]
	for l in lines:
		col.add_child(UI.wrap_label(str(l), 18, UI.C_TEXT))
	var ok: Button = UI.button("とじる", 22, UI.C_BLUE)
	ok.pressed.connect(_close_overlay)
	col.add_child(ok)


func _show_settings() -> void:
	sfx.play("click")
	var col: VBoxContainer = _open_overlay("設定", 720)

	col.add_child(UI.label("AIお客さん（Claude API）", 20, UI.C_TEXT, true))
	col.add_child(UI.wrap_label("AnthropicのAPIキーを入れると、AIがお客さんを毎回生成し、返事を採点します。キーはこのPCの設定ファイルにだけ保存されます。利用料金はキーの持ち主にかかります。", 14, UI.C_MUTED))
	var use_llm: CheckButton = CheckButton.new()
	use_llm.text = "AIお客さんを使う"
	use_llm.button_pressed = GameSettings.use_llm
	use_llm.add_theme_font_size_override("font_size", 18)
	col.add_child(use_llm)
	var key_edit: LineEdit = UI.line_edit("sk-ant-...", 18)
	key_edit.secret = true
	key_edit.text = GameSettings.api_key
	col.add_child(key_edit)
	var model_opt: OptionButton = OptionButton.new()
	model_opt.add_theme_font_size_override("font_size", 18)
	for i in range(GameSettings.MODELS.size()):
		model_opt.add_item(str(GameSettings.MODELS[i][1]), i)
		if str(GameSettings.MODELS[i][0]) == GameSettings.model:
			model_opt.select(i)
	col.add_child(model_opt)
	var test_row: HBoxContainer = HBoxContainer.new()
	test_row.add_theme_constant_override("separation", 10)
	col.add_child(test_row)
	var test_btn: Button = UI.button("接続テスト", 18, UI.C_BLUE)
	test_row.add_child(test_btn)
	var test_label: Label = UI.wrap_label("", 16, UI.C_MUTED)
	test_row.add_child(test_label)

	col.add_child(UI.label("音量", 20, UI.C_TEXT, true))
	var vol: HSlider = HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.05
	vol.value = GameSettings.volume
	col.add_child(vol)
	var full: CheckButton = CheckButton.new()
	full.text = "フルスクリーン"
	full.button_pressed = GameSettings.fullscreen
	full.add_theme_font_size_override("font_size", 18)
	col.add_child(full)

	var apply: Callable = func() -> void:
		GameSettings.use_llm = use_llm.button_pressed
		GameSettings.api_key = key_edit.text.strip_edges()
		GameSettings.model = str(GameSettings.MODELS[maxi(model_opt.selected, 0)][0])
		GameSettings.volume = vol.value
		GameSettings.fullscreen = full.button_pressed
		GameSettings.save_settings()
		GameSettings.apply_window()

	vol.value_changed.connect(func(v: float) -> void:
		GameSettings.volume = v
		sfx.play("click"))
	test_btn.pressed.connect(func() -> void:
		apply.call()
		test_label.text = "接続中…"
		var res: Dictionary = await llm.test_connection()
		if not is_instance_valid(test_label):
			return
		if res.has("error"):
			test_label.text = "失敗: " + str(res["error"])
			test_label.add_theme_color_override("font_color", UI.C_RED.lightened(0.3))
		else:
			test_label.text = "接続OK！"
			test_label.add_theme_color_override("font_color", UI.C_GREEN.lightened(0.3)))
	var ok: Button = UI.button("保存してとじる", 22, UI.C_GREEN)
	ok.pressed.connect(func() -> void:
		apply.call()
		_close_overlay()
		_refresh_title())
	col.add_child(ok)


static func rank_for(total: int) -> Array:
	for r in RANKS:
		if total >= int(r[0]):
			return r
	return RANKS[RANKS.size() - 1]


func _on_solo_finished(stage_id: String, results: Array, total: int) -> void:
	var is_best: bool = GameSettings.submit_score(stage_id, total)
	var rank: Array = rank_for(total)
	sfx.play("win" if total >= 2400 else "lose")
	var col: VBoxContainer = _open_overlay("シフト終了！", 680)
	col.add_child(UI.label(str(STAGES[stage_id]["name"]), 18, UI.C_MUTED))
	for r in results:
		var res: Dictionary = r
		var outcome: String = str(res.get("outcome", ""))
		var mark: String = "○ 納得"
		var c: Color = UI.C_GREEN.lightened(0.3)
		if outcome == "explode":
			mark = "× ブチギレ"
			c = UI.C_RED.lightened(0.3)
		elif outcome == "yield":
			mark = "△ 屈した"
			c = UI.C_PURPLE.lightened(0.35)
		var line: HBoxContainer = HBoxContainer.new()
		col.add_child(line)
		var name_label: Label = UI.label(str(res.get("title", "")), 20, UI.C_TEXT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var mark_label: Label = UI.label(mark, 20, c, true)
		mark_label.custom_minimum_size = Vector2(150, 0)
		line.add_child(mark_label)
		var pts: Label = UI.label("%+d" % int(res.get("points", 0)), 20, UI.C_TEXT, true)
		pts.custom_minimum_size = Vector2(90, 0)
		pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(pts)
	col.add_child(UI.label("合計 %d 点%s" % [total, "  ★ハイスコア更新！" if is_best else ""], 28, UI.C_ACCENT, true))
	col.add_child(UI.label("ランク %s ― %s" % [str(rank[1]), str(rank[2])], 26, UI.C_TEXT, true))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var again: Button = UI.button("もう一度", 22, UI.C_RED)
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.pressed.connect(_start_solo.bind(stage_id))
	row.add_child(again)
	var back: Button = UI.button("タイトルへ", 22, UI.C_GRAY)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_quit_to_title)
	row.add_child(back)


# ---------------------------------------------------------------- 自動テスト

## 全ステージを台本モードで自動プレイする。成功で終了コード0、時間切れで1。
func _run_smoke() -> void:
	Engine.time_scale = 8.0
	get_tree().create_timer(150.0, true, false, true).timeout.connect(func() -> void:
		print("SMOKE TIMEOUT")
		get_tree().quit(1))
	for sid in STAGE_ORDER:
		print("SMOKE stage: ", sid)
		_start_solo(str(sid))
		var res: Array = await _solo.finished
		print("SMOKE result: ", res[1], " total=", res[2])
	print("SMOKE OK")
	get_tree().quit(0)


# ---------------------------------------------------------------- スクリーンショット撮影

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(dir: String, id: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_jpg(dir.path_join(id + ".jpg"), 0.88)
	print("SHOT ", id)


## 起動引数 `-- --shots` で、主な画面を docs/screenshots/ に保存して終了する（見た目の確認用）。
func _run_shots() -> void:
	var dir: String = ProjectSettings.globalize_path("res://docs/screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_tree().create_timer(500.0).timeout.connect(func() -> void:
		print("SHOTS TIMEOUT")
		get_tree().quit(1))
	await _wait(1.5)
	await _shot(dir, "01_title")
	for sid in STAGE_ORDER:
		var s: String = str(sid)
		var list: Array = ScenariosScript.customers(s)
		var cust: Dictionary = list[0]
		_title.visible = false
		_hud.visible = true
		_in_game = true
		display_anger = 38.0
		set_stage(s)
		_hud.clear_round()
		_hud.set_top(str(STAGES[s]["name"]), "お客さん 1 / 4 人目", "スコア 0")
		await spawn_customer(cust["look"])
		_hud.set_memo(str(cust["title"]), str(cust["memo"]), str(cust["demand"]))
		_hud.set_gauges(38.0, 20.0, 42.0)
		await customer_say("%s（%s）" % [str(cust["title"]), str(cust["name"])], str(cust["opening"]))
		_hud.set_input_enabled(true, "ここに返事を入力…")
		_hud.set_status("お客さんがキレる前に返事を入力しよう（Enterで送信）")
		await _wait(0.6)
		await _shot(dir, s + "_1_play")
		display_anger = 96.0
		_hud.set_gauges(96.0, 20.0, 3.0)
		_hud.show_delta(18, 0)
		customer_react("angry")
		await _wait(1.5)
		await _shot(dir, s + "_2_angry")
		_hud.visible = false
		display_anger = 20.0
		await _wait(1.0)
		await _shot(dir, s + "_3_scene")
		_cam_override = true
		_cam_override_pos = Vector3(3.9, 2.5, 1.6)
		_cam_override_target = Vector3(-1.5, 0.9, -4.5)
		await _wait(0.4)
		await _shot(dir, s + "_4_wide")
		_cam_override_pos = Vector3(-1.9, 1.5, -1.5)
		_cam_override_target = Vector3(-1.9, 1.35, -3.7)
		await _wait(0.4)
		await _shot(dir, s + "_5_back")
		_cam_override_pos = Vector3(0.9, 1.5, -0.2)
		_cam_override_target = Vector3(0.0, 1.35, -0.35)
		display_anger = 90.0
		await _wait(1.2)
		await _shot(dir, s + "_6_face")
		_cam_override = false
		_free_customer()
	display_anger = 0.0
	_hud.visible = true
	_on_solo_finished("arcade", [
		{"title": "クレーン三千円男", "outcome": "resolved", "points": 1520, "turns": 3},
		{"title": "メダル沼の主婦", "outcome": "explode", "points": -300, "turns": 2},
		{"title": "割り込み親子", "outcome": "resolved", "points": 1430, "turns": 4},
		{"title": "音ゲー判定おじさん", "outcome": "yield", "points": -600, "turns": 1},
	], 2050)
	await _wait(0.6)
	await _shot(dir, "08_result")
	_close_overlay()
	_show_title()
	_show_settings()
	await _wait(0.6)
	await _shot(dir, "09_settings")
	_close_overlay()
	_show_howto()
	await _wait(0.6)
	await _shot(dir, "10_howto")
	print("SHOTS OK")
	get_tree().quit(0)
