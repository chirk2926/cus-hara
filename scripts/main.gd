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
const Titles = preload("res://scripts/titles.gd")
const Shop = preload("res://scripts/shop.gd")
const DebugPanelScript = preload("res://scripts/debug_panel.gd")
const ShopActionsScript = preload("res://scripts/shop_actions.gd")
const Moderation = preload("res://scripts/moderation.gd")
const RepairSceneScript = preload("res://scripts/repair_scene.gd")
const Markdown = preload("res://scripts/markdown.gd")
const RepairStageScript = preload("res://scripts/repair_stage.gd")

const CAMERA_POS: Vector3 = Vector3(0.0, 1.55, 1.9)
const CAMERA_TARGET: Vector3 = Vector3(0.0, 1.28, -0.35)
## 対戦の店員役のキャラクターの位置と、客役のときのカメラ（要件#84）
const STAFF_POS: Vector3 = Vector3(0.0, 0.0, 1.2)
const CUSTOMER_VIEW_POS: Vector3 = Vector3(1.15, 1.8, -1.75)
const CUSTOMER_VIEW_TARGET: Vector3 = Vector3(-0.3, 1.35, 1.2)
const STAGE_ORDER: Array = ["arcade", "konbini"]   # 勤務先はゲームセンターが上（要件#82）
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
var _server_label: Label = null
var _notice_box: PanelContainer = null   # 運営からのお知らせ（要件#100）
var _notice_text: Label = null
var _notice_list: VBoxContainer = null   # お知らせの見出し（押すと本文。要件#100）
var _warning_shown: bool = false
var _player_card: Control = null
var _version_label: Label = null
var _stage_links: Dictionary = {}


## その店で働けるか（要件#102）。コンビニは、ゲームサーバーが「開いている」と言ったときだけ（サーバーにつながらないときは閉じたまま）
func stage_open(sid: String) -> bool:
	if sid != "konbini" or smoke:
		return true
	var open: Variant = _server_info.get("open_stages", null)
	return typeof(open) == TYPE_ARRAY and (open as Array).has(sid)
var _bg_label: Label = null
var _current_variant: String = "day"
## テスト版のデバッグパネルで切り替える1人用のイベント（要件#85）: wild / manager / age / police / anger_stop
var debug: Dictionary = {}
var _last_hard: bool = false
var _hard_on: bool = false
var _hard_toggle: Button = null   # 直前のシフトがハードコアだったか（「もう一度」用）
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
	# すべての字体に中国語（簡体字）の予備を付ける（テーマ既定の字体も同じリソース）
	for f in [UI.F_BODY, UI.F_BOLD, UI.F_HAND, UI.F_DOT, UI.F_SIGN]:
		UI.font(f)
	# Godot の既定のまま残っていた部品を店の見た目にそろえる（要件#96）
	UI.install_theme()
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
	# テスト版だけ: デバッグパネル（F12 か右上の「TEST」）
	if GameSettings.is_test:
		var dp: CanvasLayer = DebugPanelScript.new()
		add_child(dp)
		dp.call("setup", self)

	if args.has("--smoke"):
		_run_smoke()
	elif _arg("--vs-smoke=") != "":
		_run_versus_smoke(_arg("--vs-smoke="))
	elif args.has("--shots"):
		_run_shots()
	elif args.has("--qa"):
		# 自動の動作確認（ボタンを実際に押す。scripts/qa_runner.gd）
		var qa: Node = (load("res://scripts/qa_runner.gd") as GDScript).new()
		add_child(qa)
		qa.call("run", self)
	else:
		_check_server()
		# 初めて起動したときは、難しさを選んでから研修（チュートリアル）を勧める（要件#53, #91）
		_offer_first_run()


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
	_hud.tool_pressed.connect(func(id: String) -> void:
		if id == "report" and mode == "versus":
			show_report(_versus.report_target()))
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
			# ハードコアの画面などタイトルを隠していた画面を閉じたら、タイトルに戻す
			if not _in_game and not _title.visible:
				_show_title()
		elif _in_game:
			_show_pause()


# ---------------------------------------------------------------- ゲームモード向けの関数

func set_stage(stage_id: String, variant: String = "day") -> void:
	if stage_id == _current_stage and variant == _current_variant:
		return
	_abort_crane()
	_current_stage = stage_id
	_current_variant = variant
	_world.call("build", stage_id, variant)


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


## 臭い客（要件#92）: お客さんのまわりに緑のもやもや
var _stink: CPUParticles3D = null


func set_stink(on: bool) -> void:
	if _stink != null and is_instance_valid(_stink):
		_stink.queue_free()
	_stink = null
	if not on or _customer == null or not is_instance_valid(_customer):
		return
	var p: CPUParticles3D = CPUParticles3D.new()
	var m: SphereMesh = SphereMesh.new()
	m.radius = 0.05
	m.height = 0.1
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.75, 0.2, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material = mat
	p.mesh = m
	p.amount = 24
	p.lifetime = 2.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.45
	p.direction = Vector3(0, 1, 0)
	p.spread = 30.0
	p.gravity = Vector3(0, 0.15, 0)
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.2
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	p.position = Vector3(0.0, 1.1, 0.0)
	_customer.add_child(p)
	_stink = p


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
	free_staff()
	_hud.set_tools([])
	set_stage(stage_id)
	bgm.play("versus")


## カメラを指定の位置へ動かす（台の調整のミニゲームなど）
var _cam_tween: Tween = null


func camera_to(pos: Vector3, target: Vector3, dur: float) -> void:
	var from_pos: Vector3 = _camera.position
	var from_target: Vector3 = _cam_override_target if _cam_override else CAMERA_TARGET
	_cam_override = true
	_cam_override_pos = from_pos
	_cam_override_target = from_target
	# 前のカメラの動き（戻る途中など）は止める。止めないと、終わりに「いつもの位置」に戻されてしまう
	if _cam_tween != null and _cam_tween.is_valid():
		_cam_tween.kill()
	var tw: Tween = create_tween()
	_cam_tween = tw
	tw.set_parallel(true)
	tw.tween_property(self, "_cam_override_pos", pos, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "_cam_override_target", target, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## カメラをいつもの位置（カウンター）に戻す
func camera_release(dur: float) -> void:
	if not _cam_override:
		return
	if _cam_tween != null and _cam_tween.is_valid():
		_cam_tween.kill()
	var tw: Tween = create_tween()
	_cam_tween = tw
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


## 筐体の前で対応する（要件#99）。メダルゲーム・ビデオゲームの台の問題があるお客さん。
## 結果: {"actions": [した対応], "seconds": かかった時間, "opened": bool}
var _repair: Control = null


func run_repair_scene(cust: Dictionary) -> Dictionary:
	close_machine_data()
	var sc: Control = RepairSceneScript.new()
	_repair = sc
	_ui.add_child(sc)
	sc.call("setup", self, cust)
	_hud.visible = false
	var res: Dictionary = await sc.call("run")
	if is_instance_valid(sc):
		sc.queue_free()
	_repair = null
	if _in_game:
		_hud.visible = true
	return res


## 迷惑なお客さん（台パン・大声）と話す間の背景（要件#99）。HUD の下に、ビデオゲームコーナーの場面を出す
var _talk_bg: Control = null
var _talk_stage: Node3D = null


func show_talk_backdrop(problem: String) -> void:
	hide_talk_backdrop()
	var svc: SubViewportContainer = SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp: SubViewport = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(vp)
	var st: Node3D = RepairStageScript.new()
	vp.add_child(st)
	st.call("build_repair", "video_talk", problem)
	var cam: Camera3D = Camera3D.new()
	cam.fov = 50.0
	vp.add_child(cam)
	cam.transform = Transform3D.IDENTITY.translated(st.get("cam_pos")).looking_at(st.get("cam_look"), Vector3.UP)
	_ui.add_child(svc)
	_ui.move_child(svc, 0)   # HUD（会話の吹き出し・入力欄）の下
	_talk_bg = svc
	_talk_stage = st


func calm_talk_backdrop() -> void:
	if _talk_stage != null and is_instance_valid(_talk_stage):
		_talk_stage.call("calm_offender")


func hide_talk_backdrop() -> void:
	if _talk_bg != null and is_instance_valid(_talk_bg):
		_talk_bg.queue_free()
	_talk_bg = null
	_talk_stage = null


## 筐体のデータ（要件#57）。「〇〇円使っても取れない」と言うお客さんの、本当の投入額を見せる。
## 嘘なら記録を示して話せばよく、本当で目安に近いなら景品を取りやすい位置に直すとよい。
var _machine_panel: Control = null
## 筐体のデータを見に、台の前まで行っている（1人用の怒りは止まる。要件#66）
var machine_view_open: bool = false
var _md_token: int = 0


## 筐体のデータ（要件#57, #59, #66）。台の前まで行き（台の調整と同じカメラ）、台のサービス画面として記録を見せる。
## walk = false（対戦）のときは、カウンターのまま画面だけ出す
func show_machine_data(cust: Dictionary, walk: bool = true) -> void:
	close_machine_data()
	var sp: Variant = cust.get("spend", null)
	if typeof(sp) != TYPE_DICTIONARY:
		return
	_md_token += 1
	var token: int = _md_token
	var arcade = _world.call("get_arcade")
	if walk and arcade != null:
		var cr: Dictionary = arcade.get_service_crane()
		if not cr.is_empty():
			var front: Vector3 = (cr["root"] as Node3D).to_global(Vector3.ZERO)
			machine_view_open = true
			_hud.visible = false
			sfx.play("door", 1.3)
			camera_to(front + Vector3(0.55, 1.45, 1.05), front + Vector3(0.1, 0.95, 0.0), 0.7)
			await get_tree().create_timer(0.7).timeout
			if token != _md_token:
				return
	_build_service_screen(sp as Dictionary)


## 台のサービス画面（黒い液晶・緑のドット文字・走査線）と、お客さんの話のメモ
func _build_service_screen(d: Dictionary) -> void:
	sfx.play("click", 1.2)
	var claimed: int = int(d.get("claimed", 0))
	var actual: int = int(d.get("actual", 0))
	var expected: int = int(d.get("expected", 0))
	var payout: int = int(d.get("payout", 30))
	var holder: Control = Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_machine_panel = holder
	_ui.add_child(holder)
	# 液晶のまわりの黒い枠（台の筐体）
	var bezel: PanelContainer = PanelContainer.new()
	var bst: StyleBoxFlat = UI.flat_style(Color("#232328"), 14, 10)
	bst.border_color = Color("#3c3c44")
	bst.set_border_width_all(3)
	bezel.add_theme_stylebox_override("panel", bst)
	bezel.anchor_left = 0.5
	bezel.anchor_right = 0.5
	bezel.offset_left = -270
	bezel.offset_right = 270
	bezel.offset_top = 70
	holder.add_child(bezel)
	var screen: PanelContainer = PanelContainer.new()
	screen.add_theme_stylebox_override("panel", UI.flat_style(Color("#07140b"), 16, 2))
	bezel.add_child(screen)
	var col: VBoxContainer = UI.vbox(4)
	screen.add_child(col)
	var on: Color = Color("#7dff8a")
	var dim: Color = Color("#3f8f4a")
	col.add_child(UI.text("SERVICE MODE  ::  BOOKKEEPING", UI.S_SMALL, dim, UI.F_DOT))
	col.add_child(UI.text("UNIT #05  CRANE-B   PRIZE COST %s" % GameSettings.money(CraneScript.PRIZE_COST), UI.S_SMALL, dim, UI.F_DOT))
	col.add_child(UI.text("--------------------------------------", UI.S_SMALL, dim, UI.F_DOT))
	var rows: Array = [
		["01", "CREDIT IN", GameSettings.money(actual)],
		["02", "PLAY COUNT", str(actual / 100)],
		["03", "PAYOUT SET", "%d%%" % payout],
		["04", "PAYOUT GOAL", GameSettings.money(expected)],
		["05", "TO GOAL", "REACHED" if actual >= expected else GameSettings.money(expected - actual)],
	]
	for r in rows:
		var row: HBoxContainer = UI.hbox(10)
		col.add_child(row)
		row.add_child(UI.text(str(r[0]), UI.S_BODY, dim, UI.F_DOT))
		var l: Label = UI.text(str(r[1]), UI.S_BODY, on, UI.F_DOT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UI.text(str(r[2]), UI.S_LEAD, on if str(r[0]) != "05" or actual < expected else UI.POP, UI.F_DOT))
	col.add_child(UI.text("--------------------------------------", UI.S_SMALL, dim, UI.F_DOT))
	var bar = Paper.DotBar.new()
	bar.segments = 24
	bar.custom_minimum_size = Vector2(470, 14)
	bar.value = 100.0 * float(actual) / float(maxi(expected, 1))
	bar.color = UI.POP if actual >= expected else on
	col.add_child(bar)
	col.add_child(UI.text("GOAL %3d%%" % int(round(minf(999.0, 100.0 * float(actual) / float(maxi(expected, 1))))), UI.S_SMALL, dim, UI.F_DOT))
	var close: Button = UI.link("▶ EXIT  " + tr("カウンターに戻る"), UI.S_SMALL, on)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_machine_data)
	col.add_child(close)
	# 走査線
	var scan: Control = Paper.Scanlines.new()
	screen.add_child(scan)
	# お客さんの話と見立て（手書きのメモ）
	var note: PanelContainer = UI.paper(UI.POP, 12, 3)
	note.anchor_left = 0.5
	note.anchor_right = 0.5
	note.offset_left = 290
	note.offset_right = 290 + 250
	note.offset_top = 90
	note.rotation_degrees = 2.0
	holder.add_child(note)
	var nb: VBoxContainer = UI.vbox(4)
	note.add_child(nb)
	nb.add_child(UI.text(tr("お客さんの話"), UI.S_SMALL, UI.INK_SOFT, UI.F_HAND))
	nb.add_child(UI.text(GameSettings.money(claimed), UI.S_HEAD, UI.INK, UI.F_HAND))
	var verdict: String = ""
	if actual < int(float(claimed) * 0.6):
		verdict = tr("→ 話の金額より、記録がかなり少ない。記録をもとに落ち着いて伝えよう。")
	elif actual >= int(float(expected) * 0.8):
		verdict = tr("→ 記録どおり。目安に近いので、景品を取りやすい位置に直してもいい頃。")
	else:
		verdict = tr("→ 記録どおり。ただ、まだ目安には届いていない。")
	var vl: Label = UI.para(verdict, UI.S_SMALL, UI.INK, UI.F_HAND)
	vl.custom_minimum_size = Vector2(220, 0)
	nb.add_child(vl)


## 年齢確認の身分証（要件#61）。お客さんが差し出した身分証を、カードの形で見せる。
## プレイヤーは「使える身分証か・顔写真があるか・顔が同じか・生年月日から何歳か」を自分で確かめる
const AgeCheck = preload("res://scripts/age_check.gd")


func show_id_card(cust: Dictionary) -> void:
	close_machine_data()
	var ag: Variant = cust.get("age", null)
	if typeof(ag) != TYPE_DICTIONARY:
		return
	var a: Dictionary = ag
	sfx.play("click", 1.1)
	var en: bool = GameSettings.language == "en"
	var panel: PanelContainer = UI.paper(UI.PAPER, 16, 5)
	panel.custom_minimum_size = Vector2(460, 0)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -230
	panel.offset_right = 230
	panel.offset_top = 88
	panel.rotation_degrees = 0.6
	_machine_panel = panel
	_ui.add_child(panel)
	var col: VBoxContainer = UI.vbox(8)
	panel.add_child(col)
	var today: Dictionary = a.get("today", Time.get_date_dict_from_system())
	var date_text: String = ("%04d-%02d-%02d" % [int(today["year"]), int(today["month"]), int(today["day"])]) if en else (("%d년 %d월 %d일" if GameSettings.language == "ko" else "%d年%d月%d日") % [int(today["year"]), int(today["month"]), int(today["day"])])
	col.add_child(UI.text(tr("本日 %s  現在 %s") % [date_text, AgeCheck.clock_text(int(a.get("clock", 0)))], UI.S_SMALL, UI.INK_SOFT, UI.F_DOT))
	# カード
	var card: PanelContainer = PanelContainer.new()
	var t: String = str(a.get("type", ""))
	var tint: Color = {"license": Color("#d8ecd0"), "mynumber": Color("#f3e3ef"), "passport": Color("#d6dcef"),
		"student": Color("#fff3c8"), "commuter": Color("#dff2ff"), "insurance": Color("#f0f0e6")}.get(t, UI.PAPER)
	var st: StyleBoxFlat = UI.flat_style(tint, 12, 8)
	st.border_color = UI.INK_SOFT
	st.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", st)
	col.add_child(card)
	var row: HBoxContainer = UI.hbox(14)
	card.add_child(row)
	if bool(a.get("has_photo", false)):
		var photo = Paper.IdPhoto.new()
		photo.look = a.get("photo", {})
		row.add_child(photo)
	else:
		var none: Label = UI.text(tr("写真なし"), UI.S_SMALL, UI.INK_SOFT, UI.F_DOT)
		none.custom_minimum_size = Vector2(84, 104)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(none)
	var info: VBoxContainer = UI.vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	info.add_child(UI.text(tr(AgeCheck.type_label(t)), UI.S_LEAD, UI.INK, UI.F_BOLD))
	info.add_child(UI.text(str(a.get("name", "")), UI.S_BODY, UI.INK))
	if bool(a.get("has_dob", false)):
		info.add_child(UI.text(AgeCheck.dob_text(a.get("dob", {}), GameSettings.language), UI.S_BODY, UI.INK, UI.F_DOT))
	match t:
		"commuter":
			info.add_child(UI.text(tr("通学 ハッピー駅 ⇔ パラダイス駅"), UI.S_SMALL, UI.INK_SOFT))
		"student":
			info.add_child(UI.text(tr("私立パラダイス学園 高等部"), UI.S_SMALL, UI.INK_SOFT))
		"insurance":
			info.add_child(UI.text(tr("被保険者証"), UI.S_SMALL, UI.INK_SOFT))
	if str(a.get("mode", "arcade")) == "konbini":
		col.add_child(UI.para(tr("確かめること: 使える身分証か（免許証・マイナンバーカード・パスポート・学生証）・顔写真と生年月日があるか・写真の顔が本人か・何歳か（お酒・たばこは20歳未満に販売不可）"), UI.S_SMALL, UI.INK_SOFT))
	else:
		col.add_child(UI.para(tr("確かめること: 使える身分証か（免許証・マイナンバーカード・パスポート・学生証）・顔写真と生年月日があるか・写真の顔が本人か・何歳か（%d歳未満は入店不可）") % int(a.get("limit", 18)), UI.S_SMALL, UI.INK_SOFT))
	var close: Button = UI.link(tr("閉じる"), UI.S_SMALL)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(close_machine_data)
	col.add_child(close)


## 警察（要件#61）。年齢確認をしないで入店不可の客を遊ばせていると来る
const POLICE_LOOK: Dictionary = {"body_color": "#1d2a5a", "skin_color": "#eec39c", "hair_color": "#1d2a5a",
	"hair": "cap", "build": "big", "accessory": "none", "height": 1.1}


## 対戦の店員役のキャラクター（要件#84）。カウンターの中に立ち、お客さんのほうを向く
var _staff = null


func spawn_staff(look: Dictionary) -> void:
	free_staff()
	_world.call("ensure_staff_side")
	_staff = CustomerScript.new()
	add_child(_staff)
	_staff.call("setup", look)
	_staff.position = STAFF_POS
	_staff.rotation.y = PI


func staff_talk(duration: float) -> void:
	if _staff != null and is_instance_valid(_staff):
		_staff.call("talk", duration)


func free_staff() -> void:
	if _staff != null and is_instance_valid(_staff):
		_staff.queue_free()
	_staff = null


## 客役のときは、カウンターの外（お客さんの斜めうしろ）から店員を見る
func set_customer_view(on: bool) -> void:
	if on:
		camera_to(CUSTOMER_VIEW_POS, CUSTOMER_VIEW_TARGET, 0.8)
	else:
		camera_release(0.5)


## 対戦の相手の名札を右上に少しの間出す（要件#82）
func show_opponent_tag(op: Dictionary) -> void:
	var t: Dictionary = Titles.by_id(str(op.get("title", "")))
	var tag: Variant = op.get("tag", {})
	var box: VBoxContainer = UI.vbox(4)
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -360
	box.offset_right = -20
	box.offset_top = 70
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(box)
	box.add_child(UI.text("VS", UI.S_HEAD, UI.POP, UI.F_SIGN))
	box.add_child(Shop.name_tag(str(op.get("name", "")), Titles.title_name(t) if not t.is_empty() else "", tag if typeof(tag) == TYPE_DICTIONARY else {}, UI.S_LEAD))
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(box):
		var tw: Tween = create_tween()
		tw.tween_property(box, "modulate:a", 0.0, 0.5)
		await tw.finished
		if is_instance_valid(box):
			box.queue_free()


func police_visit() -> void:
	manager_leave_now()
	_manager = CustomerScript.new()
	add_child(_manager)
	_manager.call("setup", POLICE_LOOK)
	var from: Vector3 = _world.call("get_customer_entrance")
	var stand: Vector3 = _world.call("get_customer_stand")
	_manager.position = from
	_manager.call("enter", from, stand + Vector3(0.8, 0.0, -0.2))
	await _manager.arrived
	if _manager != null and is_instance_valid(_manager):
		_manager.call("react", "angry")


func close_machine_data() -> void:
	_md_token += 1
	if _machine_panel != null and is_instance_valid(_machine_panel):
		_machine_panel.queue_free()
	_machine_panel = null
	if machine_view_open:
		# 台の前からカウンターに戻る
		machine_view_open = false
		camera_release(0.6)
		if _in_game:
			_hud.visible = true


func _on_talk_started(duration: float) -> void:
	if _customer != null and is_instance_valid(_customer):
		_customer.call("talk", duration)


func _free_customer() -> void:
	set_stink(false)
	if _customer != null and is_instance_valid(_customer):
		_customer.queue_free()
	_customer = null
	manager_leave_now()
	close_machine_data()


# ---------------------------------------------------------------- 画面遷移

func _start_solo(stage_id: String, hard: bool = false) -> void:
	sfx.play("click")
	_solo.hardcore = hard
	_last_hard = hard
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
	_hud.set_tools([])
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


## 称号を手に入れたお知らせ（要件#79）。画面の上に札を出して少しずつ消す。EOS の実績にも記録する
var _toast_queue: Array = []
var _toast_busy: bool = false


func show_new_titles(list: Array) -> void:
	if list.is_empty():
		return
	var ids: Array = []
	for t in list:
		ids.append(str((t as Dictionary).get("id", "")))
		_toast_queue.append(t)
	if _versus != null and _versus.eos != null:
		_versus.eos.unlock_achievements(ids)
	if not _toast_busy:
		_run_toasts()


func _run_toasts() -> void:
	_toast_busy = true
	while not _toast_queue.is_empty():
		var t: Dictionary = _toast_queue.pop_front()
		var card: PanelContainer = UI.paper(UI.POP, 14, 4)
		card.anchor_left = 0.5
		card.anchor_right = 0.5
		card.offset_left = -220
		card.offset_right = 220
		card.offset_top = 16
		card.rotation_degrees = -1.0
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ui.add_child(card)
		var col: VBoxContainer = UI.vbox(2)
		card.add_child(col)
		col.add_child(UI.text(tr("称号を手に入れた！") + "  " + "★".repeat(clampi(int(t.get("rarity", 1)), 1, 5)), UI.S_SMALL, UI.INK_SOFT, UI.F_HAND))
		col.add_child(UI.text(tr("「%s」") % Titles.title_name(t), UI.S_LEAD, UI.INK, UI.F_BOLD))
		col.add_child(UI.para(Titles.title_desc(t), UI.S_SMALL, UI.INK_SOFT))
		sfx.play("win", 1.4)
		await get_tree().create_timer(2.6 if _toast_queue.size() < 3 else 0.9).timeout
		var tw: Tween = create_tween()
		tw.tween_property(card, "modulate:a", 0.0, 0.4)
		await tw.finished
		card.queue_free()
	_toast_busy = false


## 称号の一覧（要件#79, #91）。分類のタブ・分類ごとの進み具合・「手に入れたものだけ」・★の数で並べ替え。手に入れたものは押すと名札につける
const TITLE_CATS: Array = [["all", "すべて", 1, 155], ["basic", "接客の基本", 1, 20], ["fail", "失敗", 21, 35], ["konbini", "コンビニ", 36, 45],
	["arcade", "ゲームセンター", 46, 65], ["age", "年齢確認・警察", 66, 81], ["rank", "メンタル・対戦", 82, 100], ["fun", "面白い", 101, 125],
	["hard", "やりこみ", 126, 150], ["staff", "社員モード", 151, 155]]
var _titles_cat: String = "all"
var _titles_owned_only: bool = false
var _titles_sort_stars: bool = false


func _title_num(t: Dictionary) -> int:
	return int(str(t.get("id", "t0")).substr(1))


func _show_titles() -> void:
	sfx.play("click")
	var col: VBoxContainer = _open_sheet(860, "center")
	var all_t: Array = Titles.all()
	var head: HBoxContainer = UI.hbox(14)
	col.add_child(head)
	head.add_child(UI.text(tr("称号"), UI.S_HEAD, UI.INK, UI.F_SIGN))
	head.add_child(UI.text("%d / %d" % [GameSettings.unlocked_titles.size(), all_t.size()], UI.S_LEAD, UI.SHU, UI.F_DOT))
	head.add_child(UI.spacer())
	head.add_child(UI.text(tr("いまの称号: %s") % (Titles.equipped_name() if Titles.equipped_name() != "" else tr("なし")), UI.S_BODY, UI.INK, UI.F_BOLD))
	# 分類のタブ（進み具合つき）。書類のインデックスの形（要件#96）
	var tab_items: Array = []
	for c in TITLE_CATS:
		var lo: int = int(c[2])
		var hi: int = int(c[3])
		var have: int = 0
		var total: int = 0
		for t in all_t:
			var n: int = _title_num(t)
			if n >= lo and n <= hi:
				total += 1
				if GameSettings.unlocked_titles.has(str((t as Dictionary).get("id", ""))):
					have += 1
		tab_items.append([str(c[0]), tr(str(c[1])) + " %d/%d" % [have, total]])
	col.add_child(UI.index_tabs(tab_items, _titles_cat, func(id: String) -> void:
		sfx.play("click")
		_titles_cat = id
		_show_titles()))
	var opts: HBoxContainer = UI.hbox(16)
	col.add_child(opts)
	var own: CheckBox = UI.check(tr("手に入れたものだけ"), _titles_owned_only)
	own.toggled.connect(func(on: bool) -> void:
		_titles_owned_only = on
		_show_titles())
	opts.add_child(own)
	var sort: CheckBox = UI.check(tr("★の多い順"), _titles_sort_stars)
	sort.toggled.connect(func(on: bool) -> void:
		_titles_sort_stars = on
		_show_titles())
	opts.add_child(sort)
	# 一覧
	var cat: Array = TITLE_CATS[0]
	for c2 in TITLE_CATS:
		if str(c2[0]) == _titles_cat:
			cat = c2
	var list: Array = []
	for t in all_t:
		var n2: int = _title_num(t)
		if n2 < int(cat[2]) or n2 > int(cat[3]):
			continue
		if _titles_owned_only and not GameSettings.unlocked_titles.has(str((t as Dictionary).get("id", ""))):
			continue
		list.append(t)
	if _titles_sort_stars:
		list.sort_custom(func(a: Dictionary, b2: Dictionary) -> bool: return int(a.get("rarity", 1)) > int(b2.get("rarity", 1)))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(820, 380)
	col.add_child(scroll)
	# 一覧は「表彰の台帳」: カードを並べず、罫線で区切った行にする（要件#96）
	var ledger: VBoxContainer = UI.vbox(0)
	ledger.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(ledger)
	if list.is_empty():
		ledger.add_child(UI.text(tr("まだありません。"), UI.S_BODY, UI.INK_SOFT))
	for t in list:
		ledger.add_child(_title_row(t))
	var row: HBoxContainer = UI.hbox(24)
	col.add_child(row)
	var off: Button = UI.link(tr("称号をはずす"), UI.S_BODY, UI.INK_SOFT)
	off.pressed.connect(func() -> void:
		_equip_title("")
		_show_titles())
	row.add_child(off)
	var close: Button = UI.link(tr("閉じる"), UI.S_BODY)
	close.pressed.connect(func() -> void:
		_close_sheet()
		_refresh_title())
	row.add_child(close)


## 称号の台帳の1行: ★ ｜ 名前と条件 ｜ 右はし（つける・つけている・進み具合）
func _title_row(t: Dictionary) -> Control:
	var id: String = str(t.get("id", ""))
	var have: bool = GameSettings.unlocked_titles.has(id)
	var wearing: bool = GameSettings.equipped_title == id
	var wrap: VBoxContainer = UI.vbox(0)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row: PanelContainer = PanelContainer.new()
	# つけている行だけ、蛍光ペンを引いたように黄色くする（影や枠はつけない）
	row.add_theme_stylebox_override("panel", UI.flat_style(UI.POP.lerp(UI.PAPER, 0.45) if wearing else Color(0, 0, 0, 0), 0, 0))
	wrap.add_child(row)
	var line: HBoxContainer = UI.hbox(12)
	row.add_child(line)
	var m: MarginContainer = MarginContainer.new()
	m.add_theme_constant_override("margin_left", 6)
	m.add_theme_constant_override("margin_right", 6)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 10)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(m)
	var cols: HBoxContainer = UI.hbox(16)
	m.add_child(cols)
	var r: int = clampi(int(t.get("rarity", 1)), 1, 5)
	var stars: Label = UI.text("★".repeat(r) + "☆".repeat(5 - r), UI.S_SMALL, UI.SHU if have else UI.PAPER_DIM.darkened(0.25), UI.F_DOT)
	stars.custom_minimum_size = Vector2(84, 0)
	stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cols.add_child(stars)
	var mid: VBoxContainer = UI.vbox(2)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(mid)
	mid.add_child(UI.text(Titles.title_name(t) if have else tr("？？？"), UI.S_BODY, UI.INK if have else UI.INK_SOFT, UI.F_BOLD))
	mid.add_child(UI.para(Titles.title_desc(t), UI.S_SMALL, UI.INK_SOFT))
	var right: VBoxContainer = UI.vbox(4)
	right.custom_minimum_size = Vector2(150, 0)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cols.add_child(right)
	if wearing:
		var on: Label = UI.text(tr("つけている"), UI.S_SMALL, UI.SHU, UI.F_BOLD)
		on.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(on)
	elif have:
		var use: Button = UI.link(tr("つける →"), UI.S_SMALL)
		use.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		use.pressed.connect(func() -> void:
			_equip_title(id)
			_show_titles())
		right.add_child(use)
	else:
		# 進み具合（数で数える条件だけ）。細い鉛筆の線のゲージと数
		var cur: int = Titles.value(str(t.get("stat", "")))
		var mn: int = int(t.get("min", 1))
		if mn > 1:
			var num: Label = UI.text("%s / %s" % [_num(mini(cur, mn)), _num(mn)], UI.S_SMALL, UI.INK_SOFT, UI.F_DOT)
			num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			right.add_child(num)
			var bar: ProgressBar = ProgressBar.new()
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(150, 4)
			bar.value = 100.0 * float(mini(cur, mn)) / float(mn)
			bar.add_theme_stylebox_override("background", UI.flat_style(UI.PAPER_DIM, 0, 0))
			bar.add_theme_stylebox_override("fill", UI.flat_style(UI.INK_SOFT, 0, 0))
			right.add_child(bar)
	wrap.add_child(UI.rule(UI.PAPER_DIM, 1))
	return wrap


func _equip_title(id: String) -> void:
	sfx.play("click")
	if GameSettings.equipped_title != id:
		GameSettings.stat_add("title_changes")
	GameSettings.equipped_title = id
	GameSettings.save_settings()
	# 対戦の相手にも見えるように、サーバーに送る（見た目だけ）
	if GameSettings.token != "":
		api.request("POST", "/api/v1/me", {"title": id})


func _offer_first_run() -> void:
	if not GameSettings.difficulty_asked:
		_offer_difficulty()
	elif not GameSettings.tutorial_seen:
		_offer_tutorial()


## 初めて起動したとき: タイピングに合わせて難しさを選ぶ（要件#91）
func _offer_difficulty() -> void:
	var col: VBoxContainer = _open_sheet(720, "center")
	_sheet_title(col, tr("難しさを選んでください"))
	col.add_child(UI.para(tr("このゲームはキーボードでの迅速な入力が必要です。自身のタイピング能力に合わせて難易度を設定してください。（難易度はいつでも設定で変更できます）"), UI.S_BODY, UI.INK))
	var row: HBoxContainer = UI.hbox(14)
	col.add_child(row)
	for d in [["slow", "かめ", "イージー", "返事の時間が長い"], ["normal", "うさぎ", "ノーマル", "返事の時間はふつう"], ["fast", "チーター", "ハード", "返事の時間が短い"]]:
		var did: String = str(d[0])
		var b: Button = Button.new()
		b.text = tr(str(d[1])) + "\n" + tr(str(d[2])) + "\n" + tr(str(d[3]))
		b.custom_minimum_size = Vector2(210, 120)
		b.add_theme_font_size_override("font_size", UI.S_LEAD)
		b.add_theme_color_override("font_color", UI.INK)
		b.add_theme_color_override("font_hover_color", UI.INK)
		var bg: Color = {"slow": Color("#cfe8c4"), "normal": UI.POP, "fast": Color("#f5c3b8")}[did]
		b.add_theme_stylebox_override("normal", UI.paper_style(bg, 14, 2, 3))
		b.add_theme_stylebox_override("hover", UI.paper_style(bg.lightened(0.2), 14, 2, 3))
		b.add_theme_stylebox_override("pressed", UI.paper_style(bg, 14, 2, 1))
		b.pressed.connect(func() -> void:
			sfx.play("click")
			GameSettings.answer_time = did
			GameSettings.difficulty_asked = true
			GameSettings.save_settings()
			_close_sheet()
			if not GameSettings.tutorial_seen:
				_offer_tutorial())
		row.add_child(b)


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


## 会話ログ（今のお客さんだけ。要件#86）。開いている間は怒りが止まる（紙の画面が開くと一時停止）
func show_talk_log(lines: Array, title: String) -> void:
	sfx.play("click")
	var col: VBoxContainer = _open_sheet(640, "center")
	_sheet_title(col, tr("会話ログ") + ("  " + title if title != "" else ""))
	col.add_child(UI.text(tr("見ている間、怒りは止まっています。"), UI.S_SMALL, UI.INK_SOFT))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(600, 380)
	col.add_child(scroll)
	var list: VBoxContainer = UI.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	if lines.is_empty():
		list.add_child(UI.text(tr("まだ会話がありません。"), UI.S_BODY, UI.INK_SOFT))
	for l in lines:
		var d: Dictionary = l
		var role: String = str(d.get("role", ""))
		var who: String = tr("お客さん") if role == "customer" else (tr("店長") if role == "manager" else tr("あなた"))
		var color: Color = UI.SHU if role == "customer" else (Color("#8a6d00") if role == "manager" else UI.INK)
		var row: VBoxContainer = UI.vbox(0)
		row.add_child(UI.text(who, UI.S_SMALL, color, UI.F_BOLD))
		var t: Label = UI.para(str(d.get("text", "")), UI.S_BODY, UI.INK, UI.F_HAND if role == "manager" else UI.F_BODY)
		t.custom_minimum_size = Vector2(560, 0)
		row.add_child(t)
		list.add_child(row)
	scroll.ready.connect(func() -> void: scroll.set_deferred("scroll_vertical", 100000))
	var close: Button = UI.link(tr("閉じる"), UI.S_BODY)
	close.pressed.connect(_close_sheet)
	col.add_child(close)


## ペイアウト率を変える（ゲームセンターのシフト中ならいつでも。要件#86）。開いている間は怒りが止まる
func show_payout_panel() -> void:
	sfx.play("click")
	var col: VBoxContainer = _open_sheet(560, "center")
	_sheet_title(col, tr("台の設定（ペイアウト率）"))
	var mode_row: HBoxContainer = UI.hbox(8)
	col.add_child(mode_row)
	var group: ButtonGroup = ButtonGroup.new()
	for m in [["power", "パワー設定"], ["prob", "確率設定"]]:
		var mid: String = str(m[0])
		var t: Button = UI.tag(tr(str(m[1])), UI.S_BODY)
		t.toggle_mode = true
		t.button_group = group
		t.button_pressed = GameSettings.crane_mode == mid
		t.pressed.connect(func() -> void:
			GameSettings.crane_mode = mid
			GameSettings.save_settings()
			_solo.refresh_payout()
			show_payout_panel())
		mode_row.add_child(t)
	var row: HBoxContainer = UI.hbox(8)
	col.add_child(row)
	row.add_child(UI.text(tr("ペイアウト率"), UI.S_BODY, UI.INK))
	var cost: Label = UI.text("", UI.S_BODY, UI.INK, UI.F_DOT)
	var upd: Callable = func(v: int) -> void:
		GameSettings.crane_payout = clampi(v, 10, 80)
		cost.text = "%d%%  " % GameSettings.crane_payout + tr("＝ 1個あたり %s") % GameSettings.money(CraneScript.cost_per_prize(GameSettings.crane_payout))
	row.add_child(UI.number_box(10, 80, GameSettings.crane_payout, 5, upd))
	upd.call(GameSettings.crane_payout)
	col.add_child(cost)
	if GameSettings.crane_mode != "prob":
		col.add_child(UI.para(tr("いまはパワー設定です。ペイアウト率は「確率設定」にしたときに使われます。"), UI.S_SMALL, UI.SHU))
	col.add_child(UI.para(tr("上げると「取れない」クレームが減り、店舗レビューが少し上がりやすい。下げると「取れない」クレームが増えるが、売上は上がる。（%d〜%d%%）") % [10, 80], UI.S_SMALL, UI.INK_SOFT))
	var close: Button = UI.primary(tr("決める"), UI.S_BODY)
	close.pressed.connect(func() -> void:
		GameSettings.save_settings()
		_solo.refresh_payout()
		_close_sheet())
	col.add_child(close)


## プレイヤーの通報（要件#87）。理由を選んで送る。ブロックの機能はない。対戦中に開いても時間は止まらない
const REPORT_REASONS: Array = [["abuse", "暴言・差別・脅し"], ["sexual", "性的な発言"], ["personal_info", "個人情報をさらした"], ["cheating", "ズル・不正"], ["afk", "放置・わざと負ける"], ["other", "その他"]]


func show_report(target: Dictionary, back_to_result: Dictionary = {}) -> void:
	sfx.play("click")
	var col: VBoxContainer = _open_sheet(560, "center")
	_sheet_title(col, tr("通報する"))
	col.add_child(UI.para(tr("相手: %s") % str(target.get("name", "")), UI.S_BODY, UI.INK))
	col.add_child(UI.para(tr("運営が内容を確かめます。うその通報はしないでください。"), UI.S_SMALL, UI.INK_SOFT))
	var group: ButtonGroup = ButtonGroup.new()
	var chosen: Array = [""]
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)
	for r in REPORT_REASONS:
		var rid: String = str(r[0])
		var t: Button = UI.tag(tr(str(r[1])), UI.S_SMALL)
		t.toggle_mode = true
		t.button_group = group
		t.pressed.connect(func() -> void: chosen[0] = rid)
		grid.add_child(t)
	var note: LineEdit = UI.field(tr("くわしく（なくてもよい・200文字まで）"), UI.S_BODY)
	note.max_length = 200
	col.add_child(note)
	var status: Label = UI.text("", UI.S_SMALL, UI.SHU)
	col.add_child(status)
	var row: HBoxContainer = UI.hbox(20)
	col.add_child(row)
	var send: Button = UI.primary(tr("送る"), UI.S_BODY)
	row.add_child(send)
	var cancel: Button = UI.link(tr("やめる"), UI.S_BODY)
	row.add_child(cancel)
	var go_back: Callable = func() -> void:
		if not back_to_result.is_empty():
			var again: Dictionary = back_to_result.duplicate()
			again["new_titles"] = []
			_on_versus_finished(again)
		else:
			_close_sheet()
	cancel.pressed.connect(go_back)
	send.pressed.connect(func() -> void:
		if str(chosen[0]) == "":
			status.text = tr("理由を選んでください。")
			return
		send.disabled = true
		var res: Dictionary = await api.request("POST", "/api/v1/report", {"player_id": str(target.get("player_id", "")), "match_id": str(target.get("match_id", "")), "reason": str(chosen[0]), "note": note.text})
		if not is_instance_valid(status):
			return
		if bool(res.get("ok", false)):
			GameSettings.stat_add("reports_sent")
			status.add_theme_color_override("font_color", UI.OK)
			status.text = tr("通報しました。ご協力ありがとうございます。")
			await get_tree().create_timer(1.2).timeout
			go_back.call()
		else:
			send.disabled = false
			status.text = tr("送れませんでした: %s") % str(res.get("message", "")))


## 選んで答える問題（社員モードの風営法の確認など。要件#91）。correct 番目が正解。時間切れはまちがい
signal _quiz_answered(ok: bool)


func show_quiz(title: String, question: String, choices: Array, correct: int, seconds: float) -> bool:
	var col: VBoxContainer = _open_sheet(620, "center")
	_sheet_title(col, title)
	col.add_child(UI.para(question, UI.S_LEAD, UI.INK, UI.F_BOLD))
	var timer_label: Label = UI.text("", UI.S_BODY, UI.SHU, UI.F_DOT)
	col.add_child(timer_label)
	var order: Array = range(choices.size())
	order.shuffle()
	var done: Array = [false]
	for i in order:
		var idx: int = int(i)
		var b: Button = UI.tag(str(choices[idx]), UI.S_BODY)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void:
			if done[0]:
				return
			done[0] = true
			_close_sheet()
			_quiz_answered.emit(idx == correct))
		col.add_child(b)
	if smoke:
		# 自動テストは正解を選ぶ
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if not done[0]:
				done[0] = true
				_close_sheet()
				_quiz_answered.emit(true))
	var left: float = seconds
	var t: Timer = Timer.new()
	t.wait_time = 0.25
	add_child(t)
	t.timeout.connect(func() -> void:
		left -= 0.25
		if is_instance_valid(timer_label):
			timer_label.text = tr("のこり %d 秒") % int(ceil(left))
		if left <= 0.0 and not done[0]:
			done[0] = true
			_close_sheet()
			_quiz_answered.emit(false))
	t.start()
	var ok: bool = await _quiz_answered
	t.queue_free()
	return ok


func debug_flag(key: String) -> bool:
	return bool(debug.get(key, false))


## テスト版: 客役の対戦画面を見る（相手の店員役のキャラクターをカウンターの外から）
func debug_preview_customer_view(op_avatar: Dictionary) -> void:
	_close_sheet()
	_title.visible = false
	_hud.visible = false
	_in_game = true
	mode = ""
	set_stage("arcade")
	free_staff()
	spawn_staff(Shop.avatar_look(op_avatar, "uniform"))
	set_customer_view(true)
	await spawn_customer(Shop.avatar_look(Shop.avatar_dict(), "casual"))


## テスト版: タイムカード（結果）の見本
func debug_preview_result() -> void:
	_close_sheet()
	_title.visible = false
	_hud.visible = true
	_in_game = true
	var cs: Array = ScenariosScript.customers("arcade")
	_solo.summary = {"sales": 21400, "review": 3.6, "sales_bonus": 70, "review_bonus": 240, "payout": 25, "clock_in": 1020, "clock_out": 1380,
		"pay": {"hp": 0, "kas": 107}, "reviews": [{"stars": 5, "text": tr("店員さんが景品を取りやすくしてくれた！神対応！")}, {"stars": 2, "text": tr("クレーン、全然取れない。お金が溶けただけ。")}]}
	_on_solo_finished("arcade", [
		{"title": str(cs[0]["title"]).replace("{spent}", GameSettings.money(3500)), "outcome": "resolved", "points": 1520, "turns": 3, "clock": 1050},
		{"title": cs[1]["title"], "outcome": "explode", "points": -300, "turns": 2, "clock": 1155},
		{"title": cs[5]["title"], "outcome": "resolved", "points": 1430, "turns": 4, "clock": 1260},
		{"title": cs[4]["title"], "outcome": "age_refused", "points": 600, "turns": 1, "clock": 1350},
	], 3250)


func _quit_to_title() -> void:
	_tutorial.abort()
	_abort_crane()
	hide_talk_backdrop()
	if _repair != null and is_instance_valid(_repair):
		_repair.queue_free()
		_repair = null
	_solo.abort()
	if _versus.is_active():
		_versus.leave_match()
	_versus.cancel()
	_free_customer()
	free_staff()
	_cam_override = false
	_close_sheet()
	_show_title()


func _show_title() -> void:
	_in_game = false
	mode = ""
	display_anger = 0.0
	_hud.visible = false
	_title.visible = true
	bgm.play("title")
	# タイトルの背景はショップで選んだ店と時間帯（最初はゲームセンター。要件#82）
	var bd: Dictionary = Shop.backdrop()
	set_stage(str(bd["stage"]), str(bd["variant"]))
	_refresh_title()


## サーバーの状態を確かめ、ログインしておく（タイトルに表示）
func _check_server() -> void:
	var res: Dictionary = await api.request("GET", "/api/v1/info", null, false)
	if bool(res.get("ok", false)):
		_server_info = res["body"]
		var me: Dictionary = await api.ensure_login()
		_sync_look()
		# 利用停止・運営からの警告（要件#100）
		if str(me.get("code", "")) == "banned":
			_show_admin_message(tr("このアカウントは利用停止中です"), str(me.get("error", "")), false)
		elif str(api.pending_warning) != "" and not _warning_shown:
			_warning_shown = true
			_show_admin_message(tr("運営からの警告"), str(api.pending_warning), true)
	else:
		_server_info = {"error": str(res.get("message", ""))}
	_refresh_title()
	_sync_eos_achievements()


## EOS の実績（要件#100: Microsoft Store 版の実績）。起動したら EOS に（Epic アカウントが無ければ、この PC の ID で）ログインし、
## 手に入れた称号をまとめて実績に記録する（オフラインで手に入れた分も、ここで追いつく。同じ実績を何度記録しても問題ない）
var _eos_synced: bool = false


func _sync_eos_achievements() -> void:
	if _eos_synced or smoke or _versus == null or _versus.eos == null or not _versus.eos.available():
		return
	_eos_synced = true
	if not await _versus.eos.ensure_ready(GameSettings.player_name):
		_eos_synced = false
		return
	_versus.eos.unlock_achievements(GameSettings.unlocked_titles.duplicate())


## 対戦の発言の取り扱いへの同意（要件#101）。総務省の考え方に合わせ、利用規約にまとめた同意ではなく、
## 対戦の前に、何に使い・どこに送り・どれだけ保存するかを具体的に見せて、チェックと「同意して進む」で明確に同意してもらう。
## 文を大きく変えたら VS_CONSENT_VERSION とサーバーの VS_CONSENT_VERSION を上げる（もう一度同意してもらう）
const VS_CONSENT_VERSION: int = 1
const VS_CONSENT_POINTS: Array = [
	["発言のチェックと判定", "対戦での発言（文字・声）は、不適切な内容（性的な内容・差別・脅し・個人情報）のチェックと、AIによる採点に使います。"],
	["外部のAIへの送信", "チェックと採点のため、発言の文字（声は文字に起こしたもの）を、ゲームサーバーからAIの事業者（Anthropic など、運営が設定した事業者）に送ります。声の対戦では、文字に起こすために声を文字起こしのサービスに送ります。"],
	["相手への中継", "発言は対戦相手に届けます。声は Epic Online Services（Epic Games）のボイスチャット、またはゲームサーバーを通して届けます。"],
	["保存", "発言は、試合中と試合の終わりから1時間だけ、サーバーのメモリに置きます。通報（相手からの通報、または自動の不適切発言の検出）があった試合だけ、会話の文字を30日保存し、運営が通報の確認に使います。声そのものは保存しません。"],
	["不適切な発言", "見つかった発言は相手に見せず、あなたに警告します。3回で負けになり、自動で通報されます。"],
]


func show_vs_consent(next: Callable) -> void:
	_close_sheet()
	var col: VBoxContainer = _open_sheet(820, "center")
	_sheet_title(col, tr("対戦の前に確認してください"))
	col.add_child(UI.para(tr("オンライン対戦での、あなたの発言（文字・声）の取り扱いです。同意すると対戦できます。同意しなくても、1人用は遊べます。"), UI.S_BODY, UI.INK))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(770, 300)
	col.add_child(scroll)
	var list: VBoxContainer = UI.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for i in VS_CONSENT_POINTS.size():
		var p: Array = VS_CONSENT_POINTS[i]
		list.add_child(UI.text("%d. %s" % [i + 1, tr(str(p[0]))], UI.S_BODY, UI.SHU, UI.F_BOLD))
		list.add_child(UI.para(tr(str(p[1])), UI.S_BODY, UI.INK))
	list.add_child(UI.para(tr("同意はいつでも「設定」から取り消せます（取り消すと対戦できなくなります）。くわしくはプライバシーポリシーをご覧ください。"), UI.S_SMALL, UI.INK_SOFT))
	var check: CheckBox = UI.check(tr("上の内容を読み、同意します"), false)
	col.add_child(check)
	var row: HBoxContainer = UI.hbox(24)
	col.add_child(row)
	var agree: Button = UI.primary(tr("同意して対戦へ進む"), UI.S_LEAD)
	agree.disabled = true
	check.toggled.connect(func(on: bool) -> void: agree.disabled = not on)
	row.add_child(agree)
	var no: Button = UI.link(tr("同意しない（1人用で遊ぶ）"), UI.S_BODY, UI.INK_SOFT)
	row.add_child(no)
	var policy: Button = UI.link(tr("プライバシーポリシーを読む →"), UI.S_BODY)
	policy.pressed.connect(func() -> void: OS.shell_open(api.base_url() + "/privacy?lang=" + GameSettings.language))
	row.add_child(policy)
	var msg: Label = UI.para("", UI.S_SMALL, UI.SHU)
	col.add_child(msg)
	no.pressed.connect(func() -> void:
		_close_sheet()
		_refresh_title())
	agree.pressed.connect(func() -> void:
		agree.disabled = true
		msg.text = tr("同意を記録しています…")
		var me: Dictionary = await api.ensure_login()
		var r: Dictionary = {} if me.has("error") else await api.request("POST", "/api/v1/me/consent", {"agree": true, "version": VS_CONSENT_VERSION})
		if not is_instance_valid(msg):
			return
		if not bool(r.get("ok", false)):
			agree.disabled = false
			msg.text = tr("サーバーにつながらないため、同意を記録できませんでした。つながってから、もう一度押してください。")
			return
		GameSettings.vs_consent = VS_CONSENT_VERSION
		GameSettings.save_settings()
		_close_sheet()
		if next.is_valid():
			next.call())


## 運営からの警告・利用停止の知らせ（要件#100）。警告は「わかりました」で既読にする
func _show_admin_message(title: String, text: String, ack: bool) -> void:
	if _sheet != null:
		return
	var col: VBoxContainer = _open_sheet(560, "center")
	_sheet_title(col, title)
	col.add_child(UI.para(text, UI.S_BODY, UI.INK))
	if not ack:
		col.add_child(UI.para(tr("対戦などオンラインの機能は使えません。1人用（AIを使わない台本）は遊べます。"), UI.S_SMALL, UI.INK_SOFT))
	var ok: Button = UI.primary(tr("わかりました"), UI.S_BODY)
	ok.pressed.connect(func() -> void:
		_close_sheet()
		if ack:
			api.pending_warning = ""
			api.request("POST", "/api/v1/me/ack_warning", {}))
	col.add_child(ok)


func _refresh_title() -> void:
	if _server_label == null:
		return
	# 準備中の店（要件#102: コンビニはサーバーの管理画面で開けるまで閉じる）
	for sid in _stage_links:
		var link: Button = _stage_links[sid]
		var open: bool = stage_open(str(sid))
		link.disabled = not open
		link.text = tr(str(STAGES[sid]["name"])) + ("　→" if open else "　" + tr("（準備中）"))
	_build_player_card()
	if _bg_label != null:
		_bg_label.text = tr("背景: %s") % Shop.item_name(Shop.equipped_item("bg"))
	if _hard_toggle != null:
		var unlocked: bool = GameSettings.mental_rank() >= SoloScript.HARD_UNLOCK_RANK or GameSettings.is_test
		_hard_toggle.disabled = not unlocked
		_hard_toggle.text = tr("社員モード") + "  →"
		if not unlocked:
			_hard_toggle.icon = _lock_icon()
			_hard_toggle.text = tr("社員モード（メンタル %d で解放）") % SoloScript.HARD_UNLOCK_RANK
		else:
			_hard_toggle.icon = null
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
		_server_label.add_theme_color_override("font_color", UI.LCD_ON)
	_refresh_notices()


## 運営からのお知らせ・メンテナンス（要件#100）。付箋に見出しを並べ、押すと本文（Markdown）・画像を出す
func _refresh_notices() -> void:
	if _notice_box == null or not is_instance_valid(_notice_box):
		return
	for c in _notice_list.get_children():
		c.queue_free()
	var head: PackedStringArray = PackedStringArray([tr("運営からのお知らせ")])
	if bool(_server_info.get("maintenance", false)):
		var mm: String = str(_server_info.get("maintenance_message", ""))
		head.append(tr("【メンテナンス中】対戦はお休みしています。1人用は遊べます。") + ("\n" + mm if mm != "" and GameSettings.language == "ja" else ""))
	var notices: Array = _server_info.get("notices", [])
	for n in notices:
		var d: Dictionary = n
		var title: String = _notice_lang(d.get("title", {}))
		if title == "":
			title = _notice_lang(d.get("body", {})).split("\n")[0].left(30)
		var b: Button = UI.link("・" + title + " →", UI.S_SMALL)
		b.add_theme_font_override("font", UI.font(UI.F_HAND))
		b.pressed.connect(func() -> void: show_notice(d))
		_notice_list.add_child(b)
	_notice_text.text = "\n".join(head)
	_notice_box.visible = head.size() > 1 or not notices.is_empty()


func _notice_lang(v: Variant) -> String:
	if typeof(v) != TYPE_DICTIONARY:
		return str(v)
	var lang: String = GameSettings.language if GameSettings.language in ["en", "zh", "ko"] else "ja"
	var d: Dictionary = v
	return str(d.get(lang, d.get("ja", "")))


const NOTICE_FONTS: Dictionary = {"body": ["res://assets/fonts/NotoSansJP_500Medium.ttf", "res://assets/fonts/NotoSansJP_800ExtraBold.ttf"],
	"hand": ["res://assets/fonts/YuseiMagic.ttf", "res://assets/fonts/YuseiMagic.ttf"],
	"dot": ["res://assets/fonts/DotGothic16.ttf", "res://assets/fonts/DotGothic16.ttf"],
	"sign": ["res://assets/fonts/DelaGothicOne.ttf", "res://assets/fonts/DelaGothicOne.ttf"]}
var _notice_tex: Dictionary = {}


## お知らせを1つ開く（見出し・画像・本文）。本文は Markdown を BBCode にして出す。リンクは http/https だけ開く
func show_notice(n: Dictionary) -> void:
	sfx.play("click")
	var fonts: Array = NOTICE_FONTS.get(str(n.get("font", "body")), NOTICE_FONTS["body"])
	var col: VBoxContainer = _open_sheet(760, "center")
	col.add_child(UI.para(_notice_lang(n.get("title", {})), UI.S_HEAD, UI.INK, str(fonts[1])))
	var img_holder: VBoxContainer = UI.vbox(0)
	col.add_child(img_holder)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(700, 200)
	col.add_child(scroll)
	var rt: RichTextLabel = RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_override("normal_font", UI.font(str(fonts[0])))
	rt.add_theme_font_override("bold_font", UI.font(str(fonts[1])))
	rt.add_theme_font_override("italics_font", UI.font(str(fonts[0])))
	rt.add_theme_font_size_override("normal_font_size", UI.S_BODY)
	rt.add_theme_font_size_override("bold_font_size", UI.S_BODY)
	rt.add_theme_color_override("default_color", UI.INK)
	rt.text = Markdown.to_bbcode(_notice_lang(n.get("body", {})))
	rt.meta_clicked.connect(func(meta: Variant) -> void:
		var url: String = str(meta)
		if url.begins_with("https://") or url.begins_with("http://"):
			OS.shell_open(url))
	scroll.add_child(rt)
	var close: Button = UI.link(tr("閉じる"), UI.S_BODY)
	close.pressed.connect(_close_sheet)
	col.add_child(close)
	var path: String = str(n.get("image", ""))
	if path != "":
		var tex: Texture2D = await _load_notice_image(path)
		if tex != null and is_instance_valid(img_holder):
			var tr_img: TextureRect = TextureRect.new()
			tr_img.texture = tex
			tr_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
			var w: float = 700.0
			tr_img.custom_minimum_size = Vector2(w, minf(300.0, w * float(tex.get_height()) / maxf(1.0, float(tex.get_width()))))
			img_holder.add_child(tr_img)


func _load_notice_image(path: String) -> Texture2D:
	if _notice_tex.has(path):
		return _notice_tex[path]
	var req: HTTPRequest = HTTPRequest.new()
	req.timeout = 10.0
	req.body_size_limit = 3 * 1024 * 1024
	add_child(req)
	if req.request(api.base_url() + path) != OK:
		req.queue_free()
		return null
	var r: Array = await req.request_completed
	req.queue_free()
	if int(r[0]) != HTTPRequest.RESULT_SUCCESS or int(r[1]) != 200:
		return null
	var bytes: PackedByteArray = r[3]
	var img: Image = Image.new()
	var err: int = img.load_png_from_buffer(bytes) if path.ends_with(".png") else img.load_jpg_from_buffer(bytes)
	if err != OK:
		return null
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_notice_tex[path] = tex
	return tex


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
	poster.set_meta("leave_bottom", true)   # 左下のサーバーの表示と重ならないように
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
	# 英語・中国語・韓国語の名前は「名前 – 副題」。副題は下に小さく（要件#102）
	var title_parts: PackedStringArray = tr("カスハラ防衛線").split(" – ", false, 1)
	var game_title: String = title_parts[0]
	b.add_child(UI.para(game_title, UI.S_HUGE if game_title.length() <= 12 else UI.S_HEAD, UI.INK, UI.F_SIGN))
	if title_parts.size() > 1:
		b.add_child(UI.para(title_parts[1], UI.S_LEAD, UI.SHU, UI.F_SIGN))
	b.add_child(UI.text(tr("時給：お客様の笑顔（たぶん）"), UI.S_BODY, UI.INK_SOFT, UI.F_HAND))
	b.add_child(UI.gap(12))
	var pick_row: HBoxContainer = UI.hbox(8)
	b.add_child(pick_row)
	pick_row.add_child(UI.text(tr("勤務先を選んでください"), UI.S_SMALL, UI.INK_SOFT))
	pick_row.add_child(UI.spacer())
	# ハードコア（要件#86, #90）: メンタルランク 10 までは鍵でふさぎ、解放後は専用の画面へ
	_hard_toggle = UI.tag(tr("社員モード"), UI.S_SMALL)
	_hard_toggle.add_theme_stylebox_override("normal", UI.paper_style(Color("#2a1215"), 8, 2, 3))
	_hard_toggle.add_theme_stylebox_override("hover", UI.paper_style(Color("#4a1a1e"), 8, 2, 3))
	_hard_toggle.add_theme_stylebox_override("disabled", UI.paper_style(Color("#55525a"), 8, 2, 1))
	_hard_toggle.add_theme_color_override("font_color", Color("#ff5a4a"))
	_hard_toggle.add_theme_color_override("font_hover_color", Color("#ff8a7a"))
	_hard_toggle.add_theme_color_override("font_disabled_color", Color("#d0ccd6"))
	_hard_toggle.pressed.connect(_show_hardcore)
	pick_row.add_child(_hard_toggle)
	b.add_child(UI.rule(UI.INK, 2))
	_stage_links.clear()
	for sid in STAGE_ORDER:
		var info: Dictionary = STAGES[sid]
		var row: Button = UI.link(tr(str(info["name"])) + "　→", UI.S_LEAD)
		var sid_s: String = str(sid)
		row.pressed.connect(func() -> void:
			if stage_open(sid_s):
				_start_solo(sid_s, _hard_on))
		b.add_child(row)
		_stage_links[sid_s] = row
		b.add_child(UI.para(tr(str(info["desc"])), UI.S_SMALL, UI.INK_SOFT))
		b.add_child(UI.rule(UI.PAPER_DIM, 1))
	b.add_child(UI.gap(8))
	var versus: Button = UI.primary(tr("対戦する（客 vs 店員）"), UI.S_LEAD)
	versus.pressed.connect(_ask_versus_format)
	b.add_child(versus)
	var links: HBoxContainer = UI.hbox(24)
	b.add_child(links)
	var tut: Button = UI.link(tr("新人研修（チュートリアル） →"), UI.S_BODY)
	tut.pressed.connect(start_tutorial)
	links.add_child(tut)
	var ttl: Button = UI.link(tr("称号 →"), UI.S_BODY)
	ttl.pressed.connect(_show_titles)
	links.add_child(ttl)
	var rec: Button = UI.link(tr("記録 →"), UI.S_BODY)
	rec.pressed.connect(_show_records)
	links.add_child(rec)
	# ショップは大きなボタンで（要件#86: 開くボタンがわかりにくかった）
	var shop: Button = UI.tag(tr("ショップ（背景ガチャ・名札・キャラクター・両替）"), UI.S_BODY)
	shop.add_theme_stylebox_override("normal", UI.paper_style(UI.POP, 10, 2, 3))
	shop.add_theme_stylebox_override("hover", UI.paper_style(UI.POP.lightened(0.2), 10, 2, 3))
	shop.add_theme_stylebox_override("pressed", UI.paper_style(UI.POP.darkened(0.1), 10, 2, 1))
	shop.add_theme_color_override("font_color", UI.INK)
	shop.add_theme_color_override("font_hover_color", UI.INK)
	shop.pressed.connect(_show_shop)
	b.add_child(shop)
	b.add_child(UI.gap(8))

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

	# 左下: サーバーの接続状況（要件#82）
	var srv: PanelContainer = PanelContainer.new()
	srv.add_theme_stylebox_override("panel", UI.flat_style(Color(0.08, 0.07, 0.12, 0.82), 8, 6))
	srv.anchor_top = 1.0
	srv.anchor_bottom = 1.0
	srv.offset_left = 16
	srv.offset_top = -44
	srv.offset_bottom = -12
	srv.grow_vertical = Control.GROW_DIRECTION_BEGIN
	srv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_child(srv)
	_server_label = UI.text("", UI.S_SMALL, UI.PAPER, UI.F_DOT)
	srv.add_child(_server_label)
	# 右下: 運営からのお知らせ・メンテナンス（要件#100。管理画面から出す）。付箋を少し傾けて貼る
	_notice_box = PanelContainer.new()
	_notice_box.add_theme_stylebox_override("panel", UI.paper_style(UI.POP, 12, 0, 3))
	_notice_box.anchor_left = 1.0
	_notice_box.anchor_right = 1.0
	_notice_box.anchor_top = 1.0
	_notice_box.anchor_bottom = 1.0
	_notice_box.offset_left = -380
	_notice_box.offset_right = -24
	_notice_box.offset_bottom = -44
	_notice_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_notice_box.rotation_degrees = -1.2
	_notice_box.visible = false
	_title.add_child(_notice_box)
	var nb_col: VBoxContainer = UI.vbox(2)
	_notice_box.add_child(nb_col)
	_notice_text = UI.para("", UI.S_SMALL, UI.INK, UI.F_HAND)
	nb_col.add_child(_notice_text)
	_notice_list = UI.vbox(0)
	nb_col.add_child(_notice_list)
	# 下の真ん中: いまの背景の名前（要件#86）
	_bg_label = UI.text("", UI.S_SMALL, UI.PAPER, UI.F_BOLD)
	_bg_label.anchor_left = 0.5
	_bg_label.anchor_right = 0.5
	_bg_label.anchor_top = 1.0
	_bg_label.anchor_bottom = 1.0
	_bg_label.offset_left = -260
	_bg_label.offset_right = 260
	_bg_label.offset_top = -38
	_bg_label.offset_bottom = -12
	_bg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bg_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_bg_label.add_theme_constant_override("outline_size", 6)
	_title.add_child(_bg_label)
	# 右下: ゲームのバージョン
	_version_label = UI.text("ver " + str(ProjectSettings.get_setting("application/config/version", "0.1.0")), UI.S_SMALL, Color(UI.PAPER, 0.85), UI.F_DOT)
	_version_label.anchor_left = 1.0
	_version_label.anchor_right = 1.0
	_version_label.anchor_top = 1.0
	_version_label.anchor_bottom = 1.0
	_version_label.offset_left = -200
	_version_label.offset_right = -16
	_version_label.offset_top = -36
	_version_label.offset_bottom = -12
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_version_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_version_label.add_theme_constant_override("outline_size", 4)
	_title.add_child(_version_label)


## 右上: 首から下げる社員証（要件#82, #86）。名前・称号・レート・メンタルランク・HP/CUS を、印刷の文字とハンコと手書きで
func _build_player_card() -> void:
	if _player_card != null and is_instance_valid(_player_card):
		_player_card.queue_free()
	var p: Dictionary = GameSettings.last_profile
	var root: Control = Control.new()
	root.anchor_left = 1.0
	root.anchor_right = 1.0
	root.offset_left = -372
	root.offset_right = -28
	root.offset_top = 0
	root.offset_bottom = 420
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_child(root)
	_player_card = root
	# ストラップ（画面の上から下がっている）
	for side in [-1.0, 1.0]:
		var strap: ColorRect = ColorRect.new()
		strap.color = Color("#c23b33")
		strap.size = Vector2(14, 70)
		strap.position = Vector2(172 + side * 46 - 7, -8)
		strap.rotation_degrees = -side * 14.0
		strap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(strap)
	var clip: ColorRect = ColorRect.new()
	clip.color = Color("#9aa0a8")
	clip.size = Vector2(34, 14)
	clip.position = Vector2(155, 52)
	root.add_child(clip)
	# カード本体（白いプラスチック）
	var card: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = UI.flat_style(Color("#fbfbf8"), 0, 12)
	sb.border_color = Color("#d6d3cc")
	sb.set_border_width_all(1)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(3, 5)
	card.add_theme_stylebox_override("panel", sb)
	card.position = Vector2(0, 62)
	card.custom_minimum_size = Vector2(344, 0)
	card.rotation_degrees = 1.5
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(card)
	var col: VBoxContainer = UI.vbox(0)
	card.add_child(col)
	# 上の帯: 店の名前
	var band: PanelContainer = PanelContainer.new()
	var bsb: StyleBoxFlat = UI.flat_style(UI.SHU, 8, 0)
	bsb.corner_radius_top_left = 12
	bsb.corner_radius_top_right = 12
	band.add_theme_stylebox_override("panel", bsb)
	col.add_child(band)
	var brow: HBoxContainer = UI.hbox(8)
	band.add_child(brow)
	brow.add_child(UI.text(tr("従業員証"), UI.S_BODY, UI.PAPER, UI.F_SIGN))
	brow.add_child(UI.spacer())
	brow.add_child(UI.text("No.%06d" % (absi(str(p.get("id", GameSettings.player_name)).hash()) % 1000000), UI.S_SMALL, Color(UI.PAPER, 0.85), UI.F_DOT))
	var body: MarginContainer = MarginContainer.new()
	for side2 in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		body.add_theme_constant_override(side2, 12)
	col.add_child(body)
	var bc: VBoxContainer = UI.vbox(8)
	body.add_child(bc)
	var top: HBoxContainer = UI.hbox(12)
	bc.add_child(top)
	# 顔写真（自分のキャラクター。作っていなければふつうの店員）
	var photo_frame: PanelContainer = PanelContainer.new()
	var pf: StyleBoxFlat = UI.flat_style(Color("#d8e4ee"), 0, 2)
	pf.border_color = Color("#9aa7b4")
	pf.set_border_width_all(1)
	photo_frame.add_theme_stylebox_override("panel", pf)
	top.add_child(photo_frame)
	var look: Dictionary = Shop.avatar_look(Shop.avatar_dict(), "uniform")
	photo_frame.add_child(avatar_preview(look, Vector2(92, 116), true))
	var info: VBoxContainer = UI.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	var tname: String = Titles.equipped_name()
	if tname != "":
		info.add_child(UI.text("「%s」" % tname, UI.S_SMALL, UI.INK_SOFT, UI.F_BOLD))
	var pname: String = str(p.get("name", GameSettings.player_name)) if not p.is_empty() else (GameSettings.player_name if GameSettings.player_name != "" else tr("新人"))
	# 名前（ショップの名札の飾りを使う）
	info.add_child(Shop.name_tag(pname, "", Shop.tag_dict(), UI.S_BODY))
	info.add_child(UI.gap(4))
	info.add_child(UI.text(tr("役職") + "  " + (tr(str(p.get("rank", ""))) if not p.is_empty() else tr("見習い")), UI.S_SMALL, UI.INK, UI.F_DOT))
	info.add_child(UI.text(tr("レート") + "  " + (str(int(p.get("rating", 1000))) if not p.is_empty() else "----"), UI.S_SMALL, UI.INK, UI.F_DOT))
	bc.add_child(UI.rule(Color("#d6d3cc"), 1))
	# メンタル（手書きの「正」の字で数える）と対戦メンタル（ハンコ）
	var ra: int = GameSettings.mental_rank()
	var mrow: HBoxContainer = UI.hbox(10)
	bc.add_child(mrow)
	var mcol: VBoxContainer = UI.vbox(0)
	mcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mrow.add_child(mcol)
	# メンタルランクをわかりやすく（要件#91）: 「ランク 4 / 20」と名前、次のランクまでの手書きのゲージ、一覧へのリンク
	var rrow: HBoxContainer = UI.hbox(8)
	mcol.add_child(rrow)
	rrow.add_child(UI.text(tr("メンタルランク"), UI.S_SMALL, UI.INK_SOFT, UI.F_BOLD))
	rrow.add_child(UI.text("%d" % ra, UI.S_HEAD, Color("#2a4fa8"), UI.F_SIGN))
	rrow.add_child(UI.text("/ 20", UI.S_SMALL, UI.INK_SOFT, UI.F_DOT))
	mcol.add_child(UI.text("「%s」" % GameSettings.mental_name_a(ra), UI.S_BODY, UI.INK, UI.F_BOLD))
	var nxt: int = GameSettings.mental_xp_to_next()
	var gauge: ProgressBar = ProgressBar.new()
	gauge.show_percentage = false
	gauge.custom_minimum_size = Vector2(150, 8)
	gauge.add_theme_stylebox_override("background", UI.flat_style(Color("#e4e0d8"), 0, 2))
	gauge.add_theme_stylebox_override("fill", UI.flat_style(Color("#2a4fa8"), 0, 2))
	if nxt < 0:
		gauge.value = 100.0
	else:
		var lo: int = int(GameSettings.MENTAL_XP[ra - 1])
		var hi: int = int(GameSettings.MENTAL_XP[ra])
		gauge.value = 100.0 * float(GameSettings.mental_xp - lo) / float(maxi(1, hi - lo))
	mcol.add_child(gauge)
	var nrow: HBoxContainer = UI.hbox(8)
	mcol.add_child(nrow)
	nrow.add_child(UI.text((tr("次まで %d EXP") % nxt) if nxt >= 0 else "MAX", UI.S_SMALL, UI.INK_SOFT, UI.F_HAND))
	var list_btn: Button = UI.link(tr("一覧 →"), UI.S_SMALL, Color("#2a4fa8"))
	list_btn.pressed.connect(_show_mental_list)
	nrow.add_child(list_btn)
	var mb: int = GameSettings.mental_rank_b(int(p.get("rating", 1000)))
	var bcol: VBoxContainer = UI.vbox(2)
	mrow.add_child(bcol)
	var stamp: Control = Shop.hanko(GameSettings.mental_name_b(mb).left(1), 46)
	bcol.add_child(stamp)
	bcol.add_child(UI.text(tr("対戦") + " %d %s" % [mb, GameSettings.mental_name_b(mb)], UI.S_SMALL - 2, UI.SHU, UI.F_BOLD))
	bc.add_child(UI.rule(Color("#d6d3cc"), 1))
	# 手持ちのポイントとバーコード
	var wrow: HBoxContainer = UI.hbox(10)
	bc.add_child(wrow)
	wrow.add_child(UI.text("%s HP" % _num(GameSettings.hp_points), UI.S_BODY, Color("#b0611b"), UI.F_DOT))
	wrow.add_child(UI.text("%s CUS" % _num(GameSettings.kas_points), UI.S_BODY, Color("#a0257e"), UI.F_DOT))
	wrow.add_child(UI.spacer())
	var bars: HBoxContainer = UI.hbox(1)
	bars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var seed_v: int = absi(pname.hash())
	for i in range(22):
		var bar: ColorRect = ColorRect.new()
		bar.color = UI.INK
		bar.custom_minimum_size = Vector2(1 + ((seed_v >> (i % 16)) & 1) * 2, 22)
		bars.add_child(bar)
	wrow.add_child(bars)


## メンタルランクの一覧（要件#91）。まだ届いていないランクは「？？？」
func _show_mental_list() -> void:
	sfx.play("click")
	var col: VBoxContainer = _open_sheet(820, "center")
	_sheet_title(col, tr("メンタルランク一覧"))
	var ra: int = GameSettings.mental_rank()
	var rb: int = GameSettings.mental_rank_b(int(GameSettings.last_profile.get("rating", 1000)))
	var row: HBoxContainer = UI.hbox(30)
	col.add_child(row)
	for side in ["a", "b"]:
		var c: VBoxContainer = UI.vbox(3)
		c.custom_minimum_size = Vector2(370, 0)
		row.add_child(c)
		c.add_child(UI.text(tr("1人用（経験値で上がる）") if side == "a" else tr("対戦（レートで決まる・素材）"), UI.S_BODY, UI.INK, UI.F_BOLD))
		var cur: int = ra if side == "a" else rb
		for r in range(1, 21):
			# 対戦（レートで決まる）は全部見せる。1人用はまだ届いていないランクを「？？？」に（要件#93）
			var reached: bool = r <= cur or side == "b"
			var name: String = (GameSettings.mental_name_a(r) if side == "a" else GameSettings.mental_name_b(r)) if reached else tr("？？？")
			var need: String = ""
			if side == "a":
				need = "%s EXP" % _num(int(GameSettings.MENTAL_XP[r - 1]))
			else:
				need = tr("レート %d〜") % (GameSettings.MENTAL_B_BASE_RATING + (r - 10) * GameSettings.MENTAL_B_STEP) if r > 1 else tr("レート 〜%d") % (GameSettings.MENTAL_B_BASE_RATING - 9 * GameSettings.MENTAL_B_STEP)
			var line: HBoxContainer = UI.hbox(8)
			c.add_child(line)
			var mark: String = "▶" if r == cur else "  "
			line.add_child(UI.text("%s %2d" % [mark, r], UI.S_SMALL, UI.SHU if r == cur else UI.INK_SOFT, UI.F_DOT))
			line.add_child(UI.text(name, UI.S_SMALL, UI.INK if r <= cur else UI.INK_SOFT, UI.F_BOLD if r == cur else UI.F_BODY))
			line.add_child(UI.spacer())
			line.add_child(UI.text(need, UI.S_SMALL - 2, UI.INK_SOFT, UI.F_DOT))
	var close: Button = UI.link(tr("閉じる"), UI.S_BODY)
	close.pressed.connect(_close_sheet)
	col.add_child(close)


## 「正」の字で数える（5で1つ。端数は書きかけ）
func _tally(n: int) -> String:
	var parts: Array = ["", "一", "丅", "下", "止"]
	return "正".repeat(int(n / 5.0)) + str(parts[n % 5])


func _badge(label: String, value: String, accent: Color) -> Control:
	var box: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = UI.flat_style(Color(1, 1, 1, 0.06), 8, 6)
	sb.border_color = Color(accent, 0.7)
	sb.border_width_left = 4
	box.add_theme_stylebox_override("panel", sb)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c: VBoxContainer = UI.vbox(0)
	box.add_child(c)
	c.add_child(UI.text(label, UI.S_SMALL - 2, accent, UI.F_BOLD))
	c.add_child(UI.text(value, UI.S_BODY, UI.PAPER, UI.F_DOT))
	return box


static func _num(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# ---------------------------------------------------------------- ショップ（要件#82）

var _shop_tab: String = "gacha"   # gacha / tag / chara / exchange


func _show_shop() -> void:
	sfx.play("click")
	var col: VBoxContainer = _open_sheet(980, "center")
	# 見出しと手持ち（HP はコイン、CUS はお札。要件#86: お金の違いがわかるように）
	var head: HBoxContainer = UI.hbox(14)
	col.add_child(head)
	head.add_child(UI.text(tr("ショップ"), UI.S_HEAD, UI.INK, UI.F_SIGN))
	head.add_child(UI.spacer())
	head.add_child(_money_chip("HP", GameSettings.hp_points, tr("ハラスメントポイント"), true))
	head.add_child(_money_chip("CUS", GameSettings.kas_points, tr("カスポイント"), false))
	var body: HBoxContainer = UI.hbox(16)
	col.add_child(body)
	# 左: 売り場の案内（大きなボタン）
	var nav: VBoxContainer = UI.vbox(8)
	nav.custom_minimum_size = Vector2(210, 0)
	body.add_child(nav)
	for tb in [["gacha", "背景ガチャ", "タイトルの背景が出る"], ["tag", "名札", "枠・名前の色・スタンプ"], ["chara", "キャラクター", "対戦で見える自分の姿"], ["exchange", "両替機", "CUS を HP に替える"]]:
		var tid: String = str(tb[0])
		var on: bool = tid == _shop_tab
		var btn: Button = Button.new()
		btn.text = tr(str(tb[1])) + "\n" + tr(str(tb[2]))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(210, 64)
		btn.add_theme_font_size_override("font_size", UI.S_BODY)
		btn.add_theme_color_override("font_color", UI.INK)
		btn.add_theme_color_override("font_hover_color", UI.INK)
		btn.add_theme_stylebox_override("normal", UI.paper_style(UI.POP if on else UI.PAPER_DIM.lerp(UI.PAPER, 0.5), 12, 2, 3 if not on else 1))
		btn.add_theme_stylebox_override("hover", UI.paper_style(UI.POP.lerp(UI.PAPER, 0.4), 12, 2, 3))
		btn.add_theme_stylebox_override("pressed", UI.paper_style(UI.POP, 12, 2, 1))
		btn.pressed.connect(func() -> void:
			_shop_tab = tid
			_show_shop())
		nav.add_child(btn)
	nav.add_child(UI.spacer())
	var close: Button = UI.link(tr("閉じる"), UI.S_BODY)
	close.pressed.connect(func() -> void:
		_close_sheet()
		_refresh_title())
	nav.add_child(close)
	# 右: 売り場
	var area: VBoxContainer = UI.vbox(10)
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.custom_minimum_size = Vector2(720, 520)
	body.add_child(area)
	match _shop_tab:
		"gacha":
			_shop_gacha(area)
		"exchange":
			_shop_exchange(area)
		_:
			_shop_items(area, _shop_tab)


## 手持ちのお金（HP はコイン、CUS はお札の形。要件#90: 「<アイコン>16,300 HP（ハラスメントポイント）」の形）
var _wallet_labels: Dictionary = {}


func _money_chip(label: String, value: int, note: String, coin: bool) -> Control:
	var col: VBoxContainer = UI.vbox(0)
	var row: HBoxContainer = UI.hbox(6)
	col.add_child(row)
	var icon: PanelContainer = PanelContainer.new()
	var st: StyleBoxFlat = UI.flat_style(Color("#e9b949") if coin else Color("#bfe0b4"), 0, 14 if coin else 2)
	st.border_color = Color("#a8791d") if coin else Color("#4f7a45")
	st.set_border_width_all(2)
	icon.add_theme_stylebox_override("panel", st)
	icon.custom_minimum_size = Vector2(26, 26) if coin else Vector2(40, 22)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mark: Label = UI.text("HP" if coin else "CUS", 10, Color("#6b4a0a") if coin else Color("#24402a"), UI.F_BOLD)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_child(mark)
	row.add_child(icon)
	var num: Label = UI.text("%s %s" % [_num(value), label], UI.S_LEAD, Color("#b0611b") if coin else Color("#a0257e"), UI.F_DOT)
	row.add_child(num)
	_wallet_labels[label] = num
	var n: Label = UI.text("（%s）" % note, UI.S_SMALL - 2, UI.INK_SOFT)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(n)
	return col


## 手持ちの表示をすぐ新しくする（両替・買い物のたび。要件#90）
func _refresh_wallet() -> void:
	for k in _wallet_labels:
		var l = _wallet_labels[k]
		if is_instance_valid(l):
			(l as Label).text = "%s %s" % [_num(GameSettings.hp_points if k == "HP" else GameSettings.kas_points), k]
	_refresh_title()


## 名札・キャラクターの品物（カテゴリごとに見出し）
func _shop_items(col: VBoxContainer, group_id: String) -> void:
	var top: HBoxContainer = UI.hbox(16)
	col.add_child(top)
	var pname: String = str(GameSettings.last_profile.get("name", GameSettings.player_name))
	if group_id == "tag":
		top.add_child(UI.text(tr("いまの名札:"), UI.S_SMALL, UI.INK_SOFT))
		top.add_child(Shop.name_tag(pname if pname != "" else tr("新人"), Titles.equipped_name(), Shop.tag_dict(), UI.S_BODY))
	else:
		var av: Dictionary = Shop.avatar_dict()
		top.add_child(avatar_preview(Shop.avatar_look(av, "casual"), Vector2(150, 190)))
		top.add_child(avatar_preview(Shop.avatar_look(av, "uniform"), Vector2(150, 190)))
		var side: VBoxContainer = UI.vbox(8)
		top.add_child(side)
		side.add_child(UI.para(tr("左が客役（私服）、右が店員役（制服）。対戦の相手の画面に出ます。"), UI.S_SMALL, UI.INK_SOFT))
		var edit: Button = UI.stamp(tr("性別・身長・体型・肌の色を変える"), UI.S_SMALL)
		edit.pressed.connect(func() -> void: show_avatar_maker(Callable()))
		side.add_child(edit)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(710, 300 if group_id == "chara" else 400)
	col.add_child(scroll)
	var list: VBoxContainer = UI.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for c in Shop.categories():
		var cd: Dictionary = c
		if str(cd.get("group", "")) != group_id:
			continue
		var cat: String = str(cd.get("id", ""))
		list.add_child(UI.text(Shop.text(cd.get("name", {})), UI.S_LEAD, UI.INK, UI.F_SIGN))
		var grid: GridContainer = GridContainer.new()
		grid.columns = 3 if group_id == "chara" else 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		list.add_child(grid)
		for it in Shop.items(cat):
			grid.add_child(_shop_item(it))


func _shop_item(it: Dictionary) -> Control:
	var cat: String = str(it.get("cat", ""))
	var id: String = str(it.get("id", ""))
	var have: bool = Shop.owns(cat, id)
	var using: bool = Shop.equipped(cat) == id
	var chara: bool = cat in Shop.AVATAR_CATS
	var box: PanelContainer = UI.paper(UI.PAPER if not using else UI.POP.lerp(UI.PAPER, 0.6), 10, 2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(222 if chara else 340, 0)
	var c: VBoxContainer = UI.vbox(6)
	box.add_child(c)
	var top: HBoxContainer = UI.hbox(8)
	c.add_child(top)
	top.add_child(UI.text(Shop.item_name(it), UI.S_BODY, UI.INK, UI.F_BOLD))
	top.add_child(UI.spacer())
	if int(it.get("hp", 0)) <= 0 and int(it.get("kas", 0)) > 0:
		top.add_child(UI.text(tr("CUS限定"), UI.S_SMALL, Color("#b0258a"), UI.F_BOLD))
	var pname: String = str(GameSettings.last_profile.get("name", GameSettings.player_name))
	if pname == "":
		pname = tr("新人")
	# 見本
	match cat:
		"frame", "color", "stamp":
			var tg: Dictionary = Shop.tag_dict()
			tg[cat] = id
			c.add_child(Shop.name_tag(pname, "", tg, UI.S_BODY))
		"hair_color", "casual", "uniform":
			var sw: ColorRect = ColorRect.new()
			sw.color = Color(str(it.get("value", "#888888")))
			sw.custom_minimum_size = Vector2(0, 22)
			c.add_child(sw)
	var row: HBoxContainer = UI.hbox(8)
	c.add_child(row)
	if using:
		row.add_child(UI.text(tr("使用中"), UI.S_SMALL, UI.SHU, UI.F_BOLD))
	elif have:
		row.add_child(UI.text(tr("持っている"), UI.S_SMALL, UI.OK, UI.F_BOLD))
		var use: Button = UI.link(tr("使う →"), UI.S_SMALL)
		use.pressed.connect(func() -> void:
			sfx.play("click")
			Shop.equip(cat, id)
			_after_equip(cat)
			_show_shop())
		row.add_child(use)
	else:
		for cur in ["hp", "kas"]:
			var price: int = int(it.get(cur, 0))
			if price <= 0:
				continue
			var cur_name: String = "HP" if cur == "hp" else "CUS"
			var wallet: int = GameSettings.hp_points if cur == "hp" else GameSettings.kas_points
			# 値札の形のボタン（要件#96）。枠つきの角丸ボタンを並べない
			var tag: Paper.PriceTag = Paper.PriceTag.new(tr("%s %s で買う") % [_num(price), cur_name], UI.S_SMALL)
			tag.disabled = wallet < price
			var buy: Button = tag.button
			var cur_id: String = cur
			buy.pressed.connect(func() -> void:
				if Shop.buy(cat, id, cur_id):
					sfx.play("win", 1.3)
					Shop.equip(cat, id)
					_after_equip(cat)
					show_new_titles(Titles.check())
				_show_shop())
			row.add_child(tag)
	return box


## 背景ガチャ（要件#84）
func _shop_gacha(col: VBoxContainer) -> void:
	var pool: Array = Shop.gacha_pool()
	var have_n: int = 0
	for it in pool:
		if Shop.owns("bg", str((it as Dictionary).get("id", ""))):
			have_n += 1
	col.add_child(UI.para(tr("背景はガチャで出ます。持っている背景が出たら、1回分の3割を返します。10連は10回分の値段で11回。") + "  " + tr("集めた背景: %d / %d") % [have_n, pool.size()], UI.S_SMALL, UI.INK_SOFT))
	var row: HBoxContainer = UI.hbox(10)
	col.add_child(row)
	var can: bool = Shop.gacha_has_new()
	for spec in [["kas", false], ["kas", true], ["hp", false], ["hp", true]]:
		var cur: String = str(spec[0])
		var ten: bool = bool(spec[1])
		var price: int = Shop.gacha_price(cur, ten)
		var wallet: int = GameSettings.kas_points if cur == "kas" else GameSettings.hp_points
		var label: String = (tr("10連") if ten else tr("1回")) + "  %s %s" % [_num(price), "CUS" if cur == "kas" else "HP"]
		# 主役は「CUS の10連」だけ（1画面に主役は1つ。要件#96）。ほかは値札
		var holder: Control = null
		var b: Button = null
		if cur == "kas" and ten:
			b = UI.primary(label, UI.S_BODY)
			holder = b
		else:
			var tg: Paper.PriceTag = Paper.PriceTag.new(label, UI.S_BODY)
			b = tg.button
			holder = tg
		b.disabled = not can or wallet < price
		if holder is Paper.PriceTag:
			(holder as Paper.PriceTag).disabled = b.disabled
		b.pressed.connect(func() -> void:
			var res: Array = Shop.gacha_pull(cur, ten)
			if not res.is_empty():
				_show_gacha_result(res))
		row.add_child(holder)
	if not can:
		col.add_child(UI.text(tr("背景を全部集めました！"), UI.S_BODY, UI.SHU, UI.F_BOLD))
	# 持っている背景（使うものを選ぶ）
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(710, 330)
	col.add_child(scroll)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for it in Shop.items("bg"):
		grid.add_child(_bg_card(it))


func _bg_card(it: Dictionary) -> Control:
	var id: String = str(it.get("id", ""))
	var have: bool = Shop.owns("bg", id)
	var using: bool = Shop.equipped("bg") == id
	var rar: int = int(it.get("rarity", 0))
	var box: PanelContainer = UI.paper(UI.POP.lerp(UI.PAPER, 0.6) if using else UI.PAPER, 10, 2)
	box.custom_minimum_size = Vector2(222, 0)
	var c: VBoxContainer = UI.vbox(4)
	box.add_child(c)
	var sw: ColorRect = ColorRect.new()
	sw.color = _bg_swatch(it) if have else Color(0.2, 0.2, 0.22)
	sw.custom_minimum_size = Vector2(0, 40)
	c.add_child(sw)
	var star: Label = UI.text("★".repeat(rar) if rar > 0 else tr("最初から"), UI.S_SMALL, _rarity_color(rar), UI.F_BOLD)
	star.position = Vector2(8, 8)
	sw.add_child(star)
	c.add_child(UI.text(Shop.item_name(it) if have else tr("？？？"), UI.S_SMALL, UI.INK if have else UI.INK_SOFT, UI.F_BOLD))
	if using:
		c.add_child(UI.text(tr("使用中"), UI.S_SMALL, UI.SHU, UI.F_BOLD))
	elif have:
		var use: Button = UI.link(tr("使う →"), UI.S_SMALL)
		use.pressed.connect(func() -> void:
			sfx.play("click")
			Shop.equip("bg", id)
			_after_equip("bg")
			_show_shop())
		c.add_child(use)
	return box


func _bg_swatch(it: Dictionary) -> Color:
	var night: bool = str(it.get("variant", "")) == "night"
	match str(it.get("stage", "")):
		"arcade":
			return Color("#0b0a18") if night else Color("#2a1846")
		"konbini":
			return Color("#1a2340") if night else Color("#cfe3f2")
		"bg_medal":
			return Color("#6b1420")
		"bg_video":
			return Color("#1a1a40")
		"bg_rhythm":
			return Color("#3a1050")
		"bg_office":
			return Color("#8a8778")
		"bg_purikura":
			return Color("#f2b8d6")
		"bg_video_rage":
			return Color("#3a1a2a")
		"bg_locker":
			return Color("#9aa2aa")
		"bg_toilet":
			return Color("#cfe2ea")
		"bg_warehouse":
			return Color("#6b5a40")
		"bg_manager_home":
			return Color("#4a4a62")
		"bg_parents_home":
			return Color("#c9b98a")
	return Color("#444444")


static func _rarity_color(r: int) -> Color:
	match r:
		3:
			return Color("#ffcc33")
		2:
			return Color("#9ad0ff")
		1:
			return Color("#e6e6e6")
	return Color("#c8c8c8")


## ガチャの結果。カプセルを1つずつ開ける
func _show_gacha_result(res: Array) -> void:
	sfx.play("click")
	var col: VBoxContainer = _open_sheet(820, "center")
	col.add_child(UI.text(tr("ガチャの結果"), UI.S_HEAD, UI.INK, UI.F_SIGN))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4 if res.size() > 1 else 1
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	var cards: Array = []
	for r in res:
		var d: Dictionary = r
		var it: Dictionary = d["item"]
		var rar: int = int(it.get("rarity", 1))
		var card: PanelContainer = PanelContainer.new()
		var sb: StyleBoxFlat = UI.flat_style(Color(0.1, 0.08, 0.16), 10, 8)
		sb.border_color = _rarity_color(rar)
		sb.set_border_width_all(3 if rar >= 3 else 2)
		if rar >= 3:
			sb.shadow_color = Color(1.0, 0.8, 0.2, 0.6)
			sb.shadow_size = 10
		card.add_theme_stylebox_override("panel", sb)
		card.custom_minimum_size = Vector2(185, 96)
		card.modulate.a = 0.0
		var cc: VBoxContainer = UI.vbox(2)
		card.add_child(cc)
		cc.add_child(UI.text("★".repeat(rar), UI.S_BODY, _rarity_color(rar), UI.F_BOLD))
		var nm: Label = UI.para(Shop.item_name(it), UI.S_SMALL, UI.PAPER, UI.F_BOLD)
		nm.custom_minimum_size = Vector2(165, 0)
		cc.add_child(nm)
		if bool(d.get("new", false)):
			cc.add_child(UI.text("NEW!", UI.S_SMALL, UI.POP, UI.F_SIGN))
		else:
			cc.add_child(UI.text(tr("持っている（+%d 返却）") % int(d.get("refund", 0)), UI.S_SMALL - 2, UI.PAPER_DIM))
		grid.add_child(card)
		cards.append([card, rar])
	var again: Button = UI.link(tr("ショップへ戻る"), UI.S_BODY)
	again.pressed.connect(func() -> void:
		_shop_tab = "gacha"
		_show_shop())
	col.add_child(again)
	show_new_titles(Titles.check())
	for pair in cards:
		# 途中でショップを閉じたら止める（消えたカードを触らない）
		if not is_instance_valid(pair[0]):
			return
		var card2: Control = pair[0]
		var tw: Tween = card2.create_tween()
		tw.tween_property(card2, "modulate:a", 1.0, 0.18)
		sfx.play("win" if int(pair[1]) >= 3 else "good", 1.0 + 0.1 * float(int(pair[1])))
		await get_tree().create_timer(0.22 if res.size() > 1 else 0.4).timeout


## CUS → HP の両替機（要件#84）。お札（CUS）を入れるとコイン（HP）が出てくる。逆はできない
func _shop_exchange(col: VBoxContainer) -> void:
	var rate: int = Shop.hp_per_kas()
	var wrap: Control = Control.new()
	wrap.custom_minimum_size = Vector2(720, 400)
	col.add_child(wrap)
	# 機械の本体
	var body: PanelContainer = PanelContainer.new()
	var bs: StyleBoxFlat = UI.flat_style(Color("#3b3f48"), 16, 10)
	bs.border_color = Color("#22252b")
	bs.set_border_width_all(4)
	bs.shadow_color = Color(0, 0, 0, 0.4)
	bs.shadow_size = 8
	body.add_theme_stylebox_override("panel", bs)
	body.position = Vector2(170, 0)
	body.size = Vector2(380, 400)
	wrap.add_child(body)
	var mc: VBoxContainer = UI.vbox(10)
	body.add_child(mc)
	# 看板
	var plate: PanelContainer = PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UI.flat_style(UI.POP, 6, 4))
	mc.add_child(plate)
	var pt: Label = UI.text(tr("両替機") + "  CHANGE", UI.S_LEAD, UI.INK, UI.F_SIGN)
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.add_child(pt)
	# 表示
	var lcd: PanelContainer = PanelContainer.new()
	lcd.add_theme_stylebox_override("panel", UI.flat_style(Color("#1d2b1d"), 8, 4))
	mc.add_child(lcd)
	var lcd_t: Label = UI.text("CUS 1 → HP %d   CUS %s" % [rate, _num(GameSettings.kas_points)], UI.S_BODY, UI.LCD_ON, UI.F_DOT)
	lcd.add_child(lcd_t)
	# お札の入れ口
	mc.add_child(UI.text(tr("お札（CUS）を入れてください"), UI.S_SMALL, UI.PAPER_DIM))
	var slot: ColorRect = ColorRect.new()
	slot.color = Color("#111215")
	slot.custom_minimum_size = Vector2(0, 10)
	mc.add_child(slot)
	var bills: HBoxContainer = UI.hbox(8)
	mc.add_child(bills)
	# コインの受け皿
	mc.add_child(UI.text(tr("コイン（HP）の受け皿"), UI.S_SMALL, UI.PAPER_DIM))
	var tray: PanelContainer = PanelContainer.new()
	var ts: StyleBoxFlat = UI.flat_style(Color("#16171b"), 8, 10)
	ts.border_color = Color("#8a8f99")
	ts.border_width_top = 3
	tray.add_theme_stylebox_override("panel", ts)
	tray.custom_minimum_size = Vector2(0, 74)
	tray.clip_contents = true
	mc.add_child(tray)
	var coins: Control = Control.new()
	tray.add_child(coins)
	var out: Label = UI.text("", UI.S_LEAD, Color("#ffc94a"), UI.F_DOT)
	out.position = Vector2(250, 14)
	coins.add_child(out)
	var amounts: Array = [10, 50, 100, GameSettings.kas_points]
	for i in range(amounts.size()):
		var kas: int = int(amounts[i])
		var label: String = (tr("全部") + " " if i == amounts.size() - 1 else "") + "CUS %s" % _num(kas)
		var bill: Button = Button.new()
		bill.text = label
		bill.add_theme_font_override("font", UI.font(UI.F_DOT))
		bill.add_theme_font_size_override("font_size", UI.S_SMALL)
		var bst: StyleBoxFlat = UI.flat_style(Color("#cfe6c4"), 8, 3)
		bst.border_color = Color("#4f7a45")
		bst.set_border_width_all(2)
		bill.add_theme_stylebox_override("normal", bst)
		var bh: StyleBoxFlat = bst.duplicate()
		bh.bg_color = Color("#e4f5da")
		bill.add_theme_stylebox_override("hover", bh)
		bill.add_theme_stylebox_override("pressed", bh)
		bill.add_theme_color_override("font_color", Color("#24402a"))
		bill.disabled = kas <= 0 or kas > GameSettings.kas_points
		bill.pressed.connect(func() -> void:
			if not Shop.exchange(kas):
				return
			sfx.play("good", 1.3)
			lcd_t.text = "CUS 1 → HP %d   CUS %s" % [rate, _num(GameSettings.kas_points)]
			out.text = "+%s HP" % _num(kas * rate)
			_refresh_wallet()
			_exchange_manager_check()
			_drop_coins(coins, mini(14, 3 + int(kas / 10.0)))
			for b2 in bills.get_children():
				var idx: int = b2.get_index()
				(b2 as Button).disabled = int(amounts[idx]) <= 0 or int(amounts[idx]) > GameSettings.kas_points)
		bills.add_child(bill)
	# POP（貼り紙）
	var pop1: PanelContainer = UI.paper(UI.POP, 10, 3)
	pop1.position = Vector2(-6, 30)
	pop1.rotation_degrees = -6.0
	wrap.add_child(pop1)
	var p1: VBoxContainer = UI.vbox(2)
	pop1.add_child(p1)
	p1.add_child(UI.text(tr("業務両替禁止！"), UI.S_LEAD, UI.SHU, UI.F_HAND))
	var p1t: Label = UI.para(tr("お店のつり銭用の両替はお断りします"), UI.S_SMALL, UI.INK, UI.F_HAND)
	p1t.custom_minimum_size = Vector2(130, 0)
	p1.add_child(p1t)
	var pop2: PanelContainer = UI.paper(Color("#ffd1e3"), 10, 3)
	pop2.position = Vector2(562, 120)
	pop2.rotation_degrees = 5.0
	wrap.add_child(pop2)
	var p2: VBoxContainer = UI.vbox(2)
	pop2.add_child(p2)
	p2.add_child(UI.text(tr("お札→コインのみ"), UI.S_BODY, UI.SHU, UI.F_HAND))
	var p2t: Label = UI.para(tr("HP を CUS には戻せません"), UI.S_SMALL, UI.INK, UI.F_HAND)
	p2t.custom_minimum_size = Vector2(130, 0)
	p2.add_child(p2t)


## 両替機を続けて押すと、5% で店長が怒る（要件#90。ポイントはそのまま）
var _last_exchange_ms: int = -100000


func _exchange_manager_check() -> void:
	var now: int = Time.get_ticks_msec()
	var rapid: bool = now - _last_exchange_ms <= 2000
	_last_exchange_ms = now
	if not rapid or randf() >= 0.05 or _sheet == null:
		return
	GameSettings.stat_add("exchange_scolded")
	sfx.play("warn", 0.8)
	shake(0.15)
	var note: PanelContainer = UI.paper(UI.POP, 14, 4)
	note.anchor_left = 0.5
	note.anchor_right = 0.5
	note.offset_left = -230
	note.offset_right = 230
	note.offset_top = 90
	note.rotation_degrees = -2.0
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.add_child(note)
	var c: VBoxContainer = UI.vbox(2)
	note.add_child(c)
	c.add_child(UI.text(tr("店長より"), UI.S_SMALL, UI.INK_SOFT, UI.F_HAND))
	c.add_child(UI.para(tr("おい！業務両替じゃないだろうな！？ 貼り紙を読め！"), UI.S_LEAD, UI.SHU, UI.F_HAND))
	await get_tree().create_timer(2.4).timeout
	if is_instance_valid(note):
		var tw: Tween = note.create_tween()
		tw.tween_property(note, "modulate:a", 0.0, 0.4)
		tw.tween_callback(note.queue_free)


## コインが受け皿に落ちてくる
func _drop_coins(parent: Control, n: int) -> void:
	for i in range(n):
		if not is_instance_valid(parent):
			return
		var c: Label = UI.text("●", UI.S_LEAD, Color("#ffc94a"), UI.F_BODY)
		c.position = Vector2(randf_range(10.0, 220.0), -30.0)
		parent.add_child(c)
		var tw: Tween = c.create_tween()
		tw.tween_property(c, "position:y", randf_range(18.0, 34.0), 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		sfx.play("click", 1.6 + randf() * 0.4)
		await get_tree().create_timer(0.05).timeout


## 使うものを変えた後: 背景はすぐ変え、名札の飾り・キャラクターはサーバーに送る（対戦の相手に見える）
func _after_equip(cat: String) -> void:
	_refresh_title()   # 後ろの STAFF CARD（HP/CUS・名札）もすぐ新しくする
	if cat == "bg":
		var bd: Dictionary = Shop.backdrop()
		set_stage(str(bd["stage"]), str(bd["variant"]))
	else:
		_sync_look()


## 名札の飾りとキャラクターをサーバーに送る
func _sync_look() -> void:
	if GameSettings.token == "":
		return
	var body: Dictionary = {"tag": Shop.tag_dict()}
	if Shop.avatar_created():
		body["avatar"] = Shop.avatar_dict()
	api.request("POST", "/api/v1/me", body)


# ---------------------------------------------------------------- 対戦のキャラクター（要件#84）

## キャラクターを小さな画面で回して見せる
func avatar_preview(look: Dictionary, size: Vector2, id_photo: bool = false) -> Control:
	var svc: SubViewportContainer = SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = size
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp: SubViewport = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)
	var cam: Camera3D = Camera3D.new()
	cam.fov = 32.0
	vp.add_child(cam)
	# まだ画面に置かれていないので look_at は使えない（"Node not inside tree"）。向きは計算で決める
	cam.transform = Transform3D.IDENTITY.translated(Vector3(0.0, 1.15, 3.9)).looking_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	sun.light_energy = 1.2
	vp.add_child(sun)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.9, 0.9, 1.0)
	e.ambient_light_energy = 0.7
	env.environment = e
	vp.add_child(env)
	var ch: Node3D = CustomerScript.new()
	vp.add_child(ch)
	ch.call("setup", look)
	if id_photo:
		# 証明写真: 正面の胸から上
		cam.fov = 22.0
		var hh: float = float(look.get("height", 1.0))
		cam.transform = Transform3D.IDENTITY.translated(Vector3(0.0, 1.42 * hh, 3.2)).looking_at(Vector3(0.0, 1.38 * hh, 0.0), Vector3.UP)
		return svc
	ch.rotation.y = -0.5
	var tw: Tween = ch.create_tween().set_loops()
	tw.tween_property(ch, "rotation:y", 0.5, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(ch, "rotation:y", -0.5, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return svc


## キャラクターを作る・直す（初めての対戦の前に出る）。done は作り終えたら呼ぶ
func show_avatar_maker(done: Callable) -> void:
	sfx.play("click")
	var a: Dictionary = GameSettings.avatar
	if not a.has("gender"):
		a = {"gender": "x", "height": 1.0, "build": "normal", "skin": "s2"}
		GameSettings.avatar = a
	var col: VBoxContainer = _open_sheet(820, "center")
	col.add_child(UI.text(tr("対戦のキャラクター"), UI.S_HEAD, UI.INK, UI.F_SIGN))
	col.add_child(UI.para(tr("対戦では、客役のときは私服、店員役のときは制服で相手の画面に出ます。髪型や服はショップで増やせます。"), UI.S_SMALL, UI.INK_SOFT))
	var row: HBoxContainer = UI.hbox(18)
	col.add_child(row)
	var previews: HBoxContainer = UI.hbox(4)
	row.add_child(previews)
	var form: GridContainer = GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 12)
	form.add_theme_constant_override("v_separation", 10)
	row.add_child(form)
	var refresh: Callable = func() -> void:
		for ch in previews.get_children():
			ch.queue_free()
		var av: Dictionary = Shop.avatar_dict()
		previews.add_child(avatar_preview(Shop.avatar_look(av, "casual"), Vector2(170, 260)))
		previews.add_child(avatar_preview(Shop.avatar_look(av, "uniform"), Vector2(170, 260)))
	# 性別
	var g_row: HBoxContainer = UI.hbox(6)
	var g_group: ButtonGroup = ButtonGroup.new()
	for g in [["m", "男性"], ["f", "女性"], ["x", "そのほか"]]:
		var gid: String = str(g[0])
		var b: Button = UI.tag(tr(str(g[1])), UI.S_SMALL)
		b.toggle_mode = true
		b.button_group = g_group
		b.button_pressed = str(a.get("gender", "x")) == gid
		b.pressed.connect(func() -> void:
			GameSettings.avatar["gender"] = gid
			refresh.call())
		g_row.add_child(b)
	_form_row(form, tr("性別"), g_row)
	# 身長
	var h: HSlider = HSlider.new()
	h.min_value = 0.85
	h.max_value = 1.15
	h.step = 0.01
	h.value = float(a.get("height", 1.0))
	h.custom_minimum_size = Vector2(220, 0)
	h.drag_ended.connect(func(_c: bool) -> void:
		GameSettings.avatar["height"] = h.value
		refresh.call())
	_form_row(form, tr("身長"), h)
	# 体型
	var b_row: HBoxContainer = UI.hbox(6)
	var b_group: ButtonGroup = ButtonGroup.new()
	for bb in [["slim", "細め"], ["normal", "ふつう"], ["big", "がっしり"]]:
		var bid: String = str(bb[0])
		var b2: Button = UI.tag(tr(str(bb[1])), UI.S_SMALL)
		b2.toggle_mode = true
		b2.button_group = b_group
		b2.button_pressed = str(a.get("build", "normal")) == bid
		b2.pressed.connect(func() -> void:
			GameSettings.avatar["build"] = bid
			refresh.call())
		b_row.add_child(b2)
	_form_row(form, tr("体型"), b_row)
	# 肌の色
	var s_row: HBoxContainer = UI.hbox(6)
	for sk in Shop.skins():
		var sid: String = str((sk as Dictionary).get("id", ""))
		var sw: Button = Button.new()
		sw.custom_minimum_size = Vector2(34, 34)
		var st: StyleBoxFlat = UI.flat_style(Color(str((sk as Dictionary).get("value", "#f1c9a5"))), 0, 17)
		st.border_color = UI.SHU if str(a.get("skin", "s2")) == sid else UI.INK_SOFT
		st.set_border_width_all(3 if str(a.get("skin", "s2")) == sid else 1)
		sw.add_theme_stylebox_override("normal", st)
		sw.add_theme_stylebox_override("hover", st)
		sw.add_theme_stylebox_override("pressed", st)
		sw.pressed.connect(func() -> void:
			GameSettings.avatar["skin"] = sid
			GameSettings.save_settings()
			show_avatar_maker(done))
		s_row.add_child(sw)
	_form_row(form, tr("肌の色"), s_row)
	# 髪型・髪の色（持っているもの）
	for cat in ["hair", "hair_color"]:
		var opt: OptionButton = UI.option()
		var ids: Array = []
		for it in Shop.items(cat):
			var iid: String = str((it as Dictionary).get("id", ""))
			if Shop.owns(cat, iid):
				opt.add_item(Shop.item_name(it))
				ids.append(iid)
				if Shop.equipped(cat) == iid:
					opt.select(ids.size() - 1)
		var cat_id: String = cat
		opt.item_selected.connect(func(i: int) -> void:
			Shop.equip(cat_id, str(ids[i]))
			refresh.call())
		_form_row(form, tr("髪型") if cat == "hair" else tr("髪の色"), opt)
	refresh.call()
	var btns: HBoxContainer = UI.hbox(20)
	col.add_child(btns)
	var ok: Button = UI.primary(tr("このキャラクターにする"), UI.S_LEAD)
	ok.pressed.connect(func() -> void:
		GameSettings.avatar["created"] = true
		GameSettings.save_settings()
		_sync_look()
		_close_sheet()
		if done.is_valid():
			done.call()
		else:
			_shop_tab = "chara"
			_show_shop())
	btns.add_child(ok)


# ---------------------------------------------------------------- 記録: レビューログと統計（要件#86）

var _records_tab: String = "reviews"


func _show_records() -> void:
	sfx.play("click")
	var col: VBoxContainer = _open_sheet(820, "center")
	_sheet_title(col, tr("記録"))
	col.add_child(UI.index_tabs([["reviews", tr("レビューログ")], ["stats", tr("統計")]], _records_tab, func(id: String) -> void:
		sfx.play("click")
		_records_tab = id
		_show_records(), UI.S_BODY))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(780, 440)
	col.add_child(scroll)
	var list: VBoxContainer = UI.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	if _records_tab == "reviews":
		_fill_review_log(list)
	else:
		_fill_stats(list)
	var close: Button = UI.link(tr("閉じる"), UI.S_BODY)
	close.pressed.connect(_close_sheet)
	col.add_child(close)


func _fill_review_log(list: VBoxContainer) -> void:
	if GameSettings.review_log.is_empty():
		list.add_child(UI.text(tr("まだ記録がありません。シフトを最後まで勤めると、ここに残ります。"), UI.S_BODY, UI.INK_SOFT))
		return
	for e in GameSettings.review_log:
		var d: Dictionary = e
		var card: PanelContainer = UI.paper(UI.PAPER, 12, 2)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(card)
		var c: VBoxContainer = UI.vbox(4)
		card.add_child(c)
		var head: HBoxContainer = UI.hbox(12)
		c.add_child(head)
		var st: String = str(d.get("stage", ""))
		head.add_child(UI.text(str(d.get("date", "")), UI.S_SMALL, UI.INK_SOFT, UI.F_DOT))
		head.add_child(UI.text(tr(str((STAGES.get(st, {}) as Dictionary).get("name", st))) + ("  " + tr("社員モード") if bool(d.get("hard", false)) else ""), UI.S_BODY, UI.INK, UI.F_BOLD))
		head.add_child(UI.spacer())
		var rv: float = float(d.get("review", 3.0))
		head.add_child(UI.text("★".repeat(int(round(rv))) + "☆".repeat(5 - int(round(rv))) + " %.1f" % rv, UI.S_BODY, UI.SHU, UI.F_DOT))
		c.add_child(UI.text(tr("売上 %s　合計 %d 点") % [GameSettings.money(int(d.get("sales", 0))), int(d.get("total", 0))], UI.S_SMALL, UI.INK, UI.F_DOT))
		for r in (d.get("reviews", []) as Array):
			var rd: Dictionary = r
			var n: int = int(rd.get("stars", 3))
			var t: Label = UI.para("★".repeat(n) + "☆".repeat(5 - n) + "  " + tr("「%s」") % str(rd.get("text", "")), UI.S_SMALL, UI.INK, UI.F_HAND)
			t.custom_minimum_size = Vector2(700, 0)
			c.add_child(t)


## 統計は「業務日報」: 分けた見出しの下に、点線のリーダーでつないだ行（要件#96）。0 の行は薄く、数のある行を目立たせる
func _fill_stats(list: VBoxContainer) -> void:
	var groups: Array = [
		["シフト", [
			["勤めたシフト", GameSettings.stat("shifts")],
			["パーフェクトシフト", GameSettings.stat("perfect_shift")],
			["最高の売上（1シフト）", GameSettings.money(GameSettings.stat("max_sales"))],
			["ハイスコア: ゲームセンター", GameSettings.get_high_score("arcade")],
			["ハイスコア: コンビニ", GameSettings.get_high_score("konbini")],
			["ハイスコア: ゲームセンター（社員モード）", GameSettings.get_high_score("arcade_hard")],
			["ハイスコア: コンビニ（社員モード）", GameSettings.get_high_score("konbini_hard")],
			["メンタルランク", "%d「%s」" % [GameSettings.mental_rank(), GameSettings.mental_name_a(GameSettings.mental_rank())]],
		]],
		["お客さん", [
			["納得させたお客さん", GameSettings.stat("resolved")],
			["1回目の返事で納得", GameSettings.stat("one_turn_resolve")],
			["要注意人物を納得させた", GameSettings.stat("wild_resolved")],
			["「〇〇円使った」の嘘を見破った", GameSettings.stat("lie_caught")],
			["台の調整で取らせた", GameSettings.stat("crane_won")],
			["ブチギレさせた", GameSettings.stat("explode")],
			["要求に屈した", GameSettings.stat("yield")],
			["時間切れ", GameSettings.stat("timeout")],
			["土下座", GameSettings.stat("dogeza")],
		]],
		["事件", [
			["年齢確認の正しい判断", GameSettings.stat("age_correct")],
			["営業停止", GameSettings.stat("suspended")],
			["店長が来た", GameSettings.stat("manager_visits")],
			["店長を呼んだ", GameSettings.stat("manager_called")],
			["心が折れて早退", GameSettings.stat("breakdown")],
			["休憩した回数", GameSettings.stat("pauses")],
		]],
		["対戦・ショップ", [
			["対戦の回数", GameSettings.stat("vs_matches")],
			["対戦の勝ち", GameSettings.stat("vs_wins")],
			["対戦の最高連勝", GameSettings.stat("vs_streak_max")],
			["称号", "%d / %d" % [GameSettings.unlocked_titles.size(), Titles.all().size()]],
			["ガチャを回した回数", GameSettings.stat("gacha_pulls")],
			["ショップで買った回数", GameSettings.stat("shop_buys")],
		]],
	]
	for g in groups:
		var head: Label = UI.text(tr(str(g[0])), UI.S_BODY, UI.SHU, UI.F_BOLD)
		list.add_child(head)
		var rows: VBoxContainer = UI.vbox(2)
		list.add_child(rows)
		for r in (g[1] as Array):
			var v: Variant = r[1]
			var zero: bool = (typeof(v) == TYPE_INT and int(v) == 0)
			var line: HBoxContainer = UI.hbox(6)
			rows.add_child(line)
			line.add_child(UI.text(tr(str(r[0])), UI.S_BODY, UI.INK_SOFT if zero else UI.INK))
			line.add_child(Paper.DotLeader.new())
			var num: Label = UI.text(_num(int(v)) if typeof(v) == TYPE_INT else str(v), UI.S_LEAD if not zero else UI.S_BODY, UI.INK_SOFT.lerp(UI.PAPER, 0.3) if zero else UI.INK, UI.F_DOT)
			num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			num.custom_minimum_size = Vector2(120, 0)
			line.add_child(num)
			line.add_child(UI.gap(0))
			(line.get_child(line.get_child_count() - 1) as Control).custom_minimum_size = Vector2(16, 0)   # スクロールバーと重ならないように
		list.add_child(UI.gap(8))


## 鍵マーク（ハードコアが解放されていないとき）
var _lock_tex: Texture2D = null


func _lock_icon() -> Texture2D:
	if _lock_tex != null:
		return _lock_tex
	var img: Image = Image.create(18, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c: Color = Color("#e8e4ee")
	# つる（U字）
	for y in range(1, 10):
		for x in range(3, 15):
			var dx: float = float(x) - 8.5
			var dy: float = float(y) - 8.0
			var r: float = sqrt(dx * dx + dy * dy)
			if (r >= 4.0 and r <= 6.2 and y <= 8) or ((x == 3 or x == 4 or x == 13 or x == 14) and y >= 7):
				img.set_pixel(x, y, c)
	# 本体
	for y in range(9, 19):
		for x in range(1, 17):
			img.set_pixel(x, y, c)
	for y in range(12, 16):
		img.set_pixel(8, y, Color("#2a1215"))
		img.set_pixel(9, y, Color("#2a1215"))
	_lock_tex = ImageTexture.create_from_image(img)
	return _lock_tex


## ハードコア専用の画面（要件#90）: 勤務先の選択・ハードコアのハイスコアと称号。背景は赤い照明の閉店後の店
func _show_hardcore() -> void:
	sfx.play("warn", 0.7)
	_close_sheet()
	set_stage("arcade", "hard")
	bgm.play("versus")
	_title.visible = false
	_sheet = Control.new()
	_sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_sheet)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.05, 0.0, 0.0, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sheet.add_child(shade)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 48)
	_sheet.add_child(margin)
	var root: VBoxContainer = UI.vbox(14)
	margin.add_child(root)
	root.add_child(UI.text("HARDCORE" + tr("（社員モード）"), UI.S_HUGE, Color("#ff3b2f"), UI.F_SIGN))
	root.add_child(UI.text(tr("怒りは速く、納得は遅い。店長は来ない。そのかわり点数と給与は 1.5倍。"), UI.S_BODY, Color("#ffd6d0")))
	var row: HBoxContainer = UI.hbox(24)
	root.add_child(row)
	# 勤務先
	var left: VBoxContainer = UI.vbox(10)
	left.custom_minimum_size = Vector2(420, 0)
	row.add_child(left)
	left.add_child(UI.text(tr("勤務先を選んでください"), UI.S_LEAD, Color("#ffffff"), UI.F_BOLD))
	for sid in STAGE_ORDER:
		var sid_s: String = str(sid)
		var b: Button = Button.new()
		b.text = tr(str(STAGES[sid_s]["name"])) + "\n" + tr("ハイスコア: %d 点") % GameSettings.get_high_score(sid_s + "_hard")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(420, 84)
		b.add_theme_font_size_override("font_size", UI.S_LEAD)
		b.add_theme_color_override("font_color", Color("#ffffff"))
		b.add_theme_color_override("font_hover_color", Color("#ffffff"))
		var st: StyleBoxFlat = UI.flat_style(Color("#5a0f12"), 16, 4)
		st.border_color = Color("#ff3b2f")
		st.set_border_width_all(2)
		b.add_theme_stylebox_override("normal", st)
		var sh: StyleBoxFlat = st.duplicate()
		sh.bg_color = Color("#7a1418")
		b.add_theme_stylebox_override("hover", sh)
		b.add_theme_stylebox_override("pressed", sh)
		b.pressed.connect(func() -> void: _start_solo(sid_s, true))
		if not stage_open(sid_s):
			b.disabled = true
			b.text = tr(str(STAGES[sid_s]["name"])) + "\n" + tr("（準備中）")
		left.add_child(b)
	# ハードコアの称号
	var right: VBoxContainer = UI.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	right.add_child(UI.text(tr("社員モードの称号"), UI.S_LEAD, Color("#ffffff"), UI.F_BOLD))
	for id in ["t151", "t152", "t153", "t154", "t155"]:
		var t: Dictionary = Titles.by_id(id)
		if t.is_empty():
			continue
		var have: bool = GameSettings.unlocked_titles.has(id)
		var cur: int = Titles.value(str(t.get("stat", "")))
		var line: String = ("★".repeat(int(t.get("rarity", 1))) + "  ") + (Titles.title_name(t) if have else tr("？？？")) + "\n" + Titles.title_desc(t) + ("" if have else "  (%s / %s)" % [_num(mini(cur, int(t.get("min", 1)))), _num(int(t.get("min", 1)))])
		var l: Label = UI.para(line, UI.S_SMALL, Color("#ffd24a") if have else Color("#d0c8c8"), UI.F_BOLD if have else UI.F_BODY)
		right.add_child(l)
	root.add_child(UI.spacer())
	var back: Button = UI.link(tr("戻る"), UI.S_BODY, Color("#ffffff"))
	back.pressed.connect(func() -> void:
		_close_sheet()
		_show_title())
	root.add_child(back)


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
	body.add_child(UI.text(tr("カスハラ防衛線") + "  © 2026 medal", UI.S_LEAD, UI.INK, UI.F_BOLD))
	body.add_child(UI.text("Godot Engine", UI.S_LEAD, UI.INK, UI.F_BOLD))
	body.add_child(UI.para(tr("このゲームは Godot Engine で作られています。") + " https://godotengine.org/license", UI.S_SMALL, UI.INK_SOFT))
	body.add_child(UI.para(Engine.get_license_text(), UI.S_SMALL, UI.INK))
	body.add_child(UI.text(tr("フォント"), UI.S_LEAD, UI.INK, UI.F_BOLD))
	body.add_child(UI.para("Noto Sans JP, Noto Sans SC, Noto Sans KR (c) Google / Adobe, Yusei Magic (c) The Yusei Magic Project Authors, DotGothic16 (c) The DotGothic16 Project Authors, Dela Gothic One (c) The Dela Gothic Project Authors — SIL Open Font License 1.1", UI.S_SMALL, UI.INK))
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
func _open_sheet(width: int, align: String = "center", receipt: bool = false, timecard: bool = false) -> VBoxContainer:
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
	var panel: PanelContainer = Paper.Receipt.new() if receipt else (Paper.TimeCard.new() if timecard else UI.paper(UI.PAPER, 28, 6))
	panel.resized.connect(_fit_to_screen.bind(panel, true))
	# コンテナは並べ直すたびに子の scale を 1 に戻すので、並べ直した後にもう一度縮める（レシートが画面からはみ出していた）
	row.sort_children.connect(func() -> void:
		if is_instance_valid(panel):
			_fit_to_screen(panel, true))
	panel.custom_minimum_size = Vector2(width, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(panel)
	if align != "right":
		row.add_child(UI.spacer())
	var col: VBoxContainer = UI.vbox(12)
	panel.add_child(col)
	if not receipt and not timecard:
		# 紙をマスキングテープで留めた感じにする（要件#96）。位置と傾きは幅から決めて、シートごとに少しずつ変える
		var tape: Paper.Tape = Paper.Tape.new()
		tape.at = 0.44 + float(width % 5) * 0.09   # 見出しは左にあるので、テープは右寄りに貼る
		tape.angle = -5.0 + float(width % 5) * 2.2
		panel.add_child(tape, false, Node.INTERNAL_MODE_FRONT)
	_solo.paused = true
	_sheet_is_receipt = receipt or timecard
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
	var room_y: float = vp.y - (56.0 if c.get_meta("leave_bottom", false) else 16.0) - maxf(c.global_position.y, 0.0)
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
	if mode == "solo":
		GameSettings.stat_add("pauses")
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

	var name_edit: LineEdit = UI.field(tr("フロアネーム（16文字まで）"), UI.S_BODY)
	name_edit.text = GameSettings.player_name
	name_edit.max_length = 16
	# 名前の下に、使えない名前のときの注意を出す（表の並びを崩さないよう、欄と同じ列に入れる）
	var name_box: VBoxContainer = UI.vbox(2)
	name_box.add_child(name_edit)
	var name_err: Label = UI.text("", UI.S_SMALL, UI.SHU)
	name_err.visible = false
	name_box.add_child(name_err)
	_form_row(grid, tr("フロアネーム"), name_box)

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
	# 描画の解像度・垂直同期・フレームレート・可変リフレッシュレート（要件#95）
	var scale_opt: OptionButton = _option(_translated(GameSettings.RENDER_SCALES), GameSettings.render_scale)
	_form_row(grid, tr("描画の解像度"), scale_opt)
	var vrr_chk: CheckBox = UI.check(tr("可変リフレッシュレート（G-SYNC / FreeSync）"), GameSettings.vrr)
	_form_row(grid, tr("リフレッシュレート"), vrr_chk)
	var vsync_opt: OptionButton = _option(_translated(GameSettings.VSYNC_MODES), GameSettings.vsync)
	_form_row(grid, tr("垂直同期"), vsync_opt)
	var fps_opt: OptionButton = _option(_translated(GameSettings.FPS_LIMITS), GameSettings.max_fps)
	_form_row(grid, tr("フレームレートの上限"), fps_opt)
	# 可変リフレッシュレートのときは、フルスクリーン・垂直同期オンに決まる
	var sync_vrr: Callable = func(on: bool) -> void:
		vsync_opt.disabled = on
		full.disabled = on
		if on:
			full.button_pressed = true
	vrr_chk.toggled.connect(sync_vrr)
	sync_vrr.call(GameSettings.vrr)

	col.add_child(UI.para(tr("「ゲームサーバー」では、AIの判定はサーバーで行います（APIキーは不要）。「自分のAPIキー」はサーバーが使えないときの予備で、料金はキーの持ち主にかかります。キーはこのPCの設定ファイルにだけ保存されます。「返事の時間」は1人用と、自分が作ったフレンド対戦の部屋に効きます（ランクマッチは全員同じ）。"), UI.S_SMALL, UI.INK_SOFT))
	var test_label: Label = UI.para("", UI.S_SMALL, UI.INK_SOFT)
	col.add_child(test_label)

	var row: HBoxContainer = UI.hbox(24)
	col.add_child(row)
	var save: Button = UI.primary(tr("保存する"), UI.S_LEAD)
	row.add_child(save)
	var test_btn: Button = UI.link(tr("接続を確かめる"), UI.S_BODY)
	row.add_child(test_btn)
	# 対戦の同意を取り消す（要件#101）
	if GameSettings.vs_consent >= VS_CONSENT_VERSION:
		var withdraw: Button = UI.link(tr("対戦の発言の取り扱いへの同意を取り消す（対戦できなくなります）"), UI.S_SMALL, UI.INK_SOFT)
		withdraw.pressed.connect(func() -> void:
			var r: Dictionary = await api.request("POST", "/api/v1/me/consent", {"agree": false})
			if bool(r.get("ok", false)):
				GameSettings.vs_consent = 0
				GameSettings.save_settings()
				withdraw.text = tr("同意を取り消しました。対戦するときに、もう一度確かめます。")
				withdraw.disabled = true
			else:
				withdraw.text = tr("サーバーにつながらないため、取り消せませんでした。") + " " + str(r.get("message", "")))
		col.add_child(withdraw)
	# 退職（データ削除。要件#91）: 2回確かめる
	var resign: Button = UI.link(tr("退職する（データ削除）"), UI.S_SMALL, UI.SHU)
	resign.pressed.connect(_confirm_resign.bind(1))
	col.add_child(resign)
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
		GameSettings.render_scale = str(GameSettings.RENDER_SCALES[maxi(scale_opt.selected, 0)][0])
		GameSettings.vsync = str(GameSettings.VSYNC_MODES[maxi(vsync_opt.selected, 0)][0])
		GameSettings.max_fps = str(GameSettings.FPS_LIMITS[maxi(fps_opt.selected, 0)][0])
		GameSettings.vrr = vrr_chk.button_pressed
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
		# 不適切な名前は使えない（要件#94。サーバーでも同じように確かめる）
		if new_name != "" and Moderation.check(new_name) != "":
			sfx.play("warn", 0.8)
			name_err.text = tr("その名前は使えません")
			name_err.visible = true
			return
		if new_name != "" and new_name != GameSettings.player_name and GameSettings.token != "":
			var rn: Dictionary = await api.rename(new_name)
			if rn.has("error"):
				sfx.play("warn", 0.8)
				name_err.text = tr("その名前は使えません") if str(rn.get("code", "")) == "name_not_allowed" else str(rn["error"])
				name_err.visible = true
				return
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


## 退職（データ削除）の確認。step 1 → 2 → 消す
func _confirm_resign(step: int) -> void:
	sfx.play("warn", 0.8)
	var col: VBoxContainer = _open_sheet(520, "center")
	_sheet_title(col, tr("退職届") if step == 1 else tr("本当に退職しますか？"))
	if step == 1:
		col.add_child(UI.para(tr("退職すると、このパソコンに保存した記録・称号・HP/CUS・持ち物・キャラクター・設定がすべて消えます。元には戻せません。"), UI.S_BODY, UI.INK))
		col.add_child(UI.para(tr("ゲームサーバーにあるあなたのアカウント（名前・レート・同意の記録・通報の記録・保存された会話）も消します。"), UI.S_SMALL, UI.INK_SOFT))
	else:
		col.add_child(UI.para(tr("最後の確認です。すべてのデータを消して、新人からやり直します。"), UI.S_BODY, UI.SHU))
	var row: HBoxContainer = UI.hbox(20)
	col.add_child(row)
	var yes: Button = UI.primary(tr("退職する") if step == 1 else tr("すべて消して退職する"), UI.S_BODY)
	yes.pressed.connect(func() -> void:
		if step == 1:
			_confirm_resign(2)
			return
		# サーバーのアカウントも消す（要件#101）。つながらないときは、このPCのデータだけ消して、そのことを伝える
		var server_note: String = ""
		if GameSettings.token != "":
			var del: Dictionary = await api.request("POST", "/api/v1/me/delete", {})
			if not bool(del.get("ok", false)):
				server_note = tr("サーバーにつながらなかったため、サーバーのアカウントは消せませんでした。プライバシーポリシーの連絡先から、削除をお申し込みください。")
		GameSettings.wipe_all()
		GameSettings.save_settings()
		_close_sheet()
		if server_note != "":
			_show_admin_message(tr("退職しました"), server_note, false)
		_server_info = {}
		_rebuild_ui()
		_check_server()
		_offer_first_run())
	row.add_child(yes)
	var no: Button = UI.link(tr("やめる"), UI.S_BODY)
	no.pressed.connect(_show_settings)
	row.add_child(no)


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


## シフトの結果（要件#70: レシートではなくタイムカード）。お客様の声は右の空いた所に付箋で
const STAMP_INK: Color = Color("#4a3a8c")   # 打刻のインク（紫）


func _outcome_mark(outcome: String) -> String:
	match outcome:
		"resolved":
			return tr("納得")
		"explode":
			return tr("激怒")
		"yield":
			return tr("屈服")
		"breakdown":
			return tr("早退")
		"age_ok":
			return tr("年齢OK")
		"age_refused", "age_left":
			return tr("お断り")
		"age_wrong":
			return tr("確認ミス")
		"age_lax":
			return tr("確認不足")
		"suspended":
			return tr("営業停止")
	return ""


## タイムカードの1行: [打刻の時刻][お客さん][結果のハンコ][点]
func _card_row(col: VBoxContainer, clock: String, title: String, mark: String, points: String, mark_color: Color) -> void:
	var row: HBoxContainer = UI.hbox(10)
	col.add_child(row)
	var t: Label = UI.text(clock, UI.S_BODY, STAMP_INK, UI.F_DOT)
	t.custom_minimum_size = Vector2(70, 0)
	row.add_child(t)
	var n: Label = UI.text(title, UI.S_BODY, UI.INK, UI.F_BODY)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(n)
	if mark != "":
		var m: Label = UI.text(mark, UI.S_SMALL, mark_color, UI.F_BOLD)
		m.custom_minimum_size = Vector2(76, 0)
		m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var st: StyleBoxFlat = StyleBoxFlat.new()
		st.bg_color = Color(0, 0, 0, 0)
		st.border_color = mark_color
		st.set_border_width_all(2)
		st.set_corner_radius_all(3)
		st.content_margin_left = 4
		st.content_margin_right = 4
		m.add_theme_stylebox_override("normal", st)
		m.rotation_degrees = -3.0
		row.add_child(m)
	var p: Label = UI.text(points, UI.S_BODY, UI.INK, UI.F_DOT)
	p.custom_minimum_size = Vector2(70, 0)
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(p)


func _on_solo_finished(stage_id: String, results: Array, total: int) -> void:
	var hard: bool = bool(_solo.summary.get("hardcore", false))
	var is_best: bool = GameSettings.submit_score(stage_id + ("_hard" if hard else ""), total)
	var rank: Array = rank_for(total)
	# メンタルランク A の経験値（要件#72）
	# オフライン（台本・キーワード判定）で遊んだシフトは経験値なし（要件#74）
	var offline: bool = bool(_solo.summary.get("offline", false))
	var mr: Dictionary = {"before": GameSettings.mental_rank(), "after": GameSettings.mental_rank(), "gain": 0}
	if not offline:
		mr = GameSettings.add_mental_xp(total)
	sfx.play("win" if total >= 2400 else "lose")
	var col: VBoxContainer = _open_sheet(580, "center", false, true)
	col.add_theme_constant_override("separation", 6)
	var sm: Dictionary = _solo.summary
	# 見出し: TIME CARD ／ 店・氏名・日付
	var head: HBoxContainer = UI.hbox(12)
	col.add_child(head)
	head.add_child(UI.text("TIME CARD", UI.S_HEAD, UI.INK, UI.F_SIGN))
	head.add_child(UI.spacer())
	var today: Dictionary = Time.get_date_dict_from_system()
	head.add_child(UI.text("%04d.%02d.%02d" % [int(today["year"]), int(today["month"]), int(today["day"])], UI.S_BODY, STAMP_INK, UI.F_DOT))
	var info: HBoxContainer = UI.hbox(16)
	col.add_child(info)
	info.add_child(UI.text(tr("店舗") + "  " + tr(str(STAGES[stage_id]["name"])), UI.S_SMALL, UI.INK_SOFT))
	info.add_child(UI.spacer())
	var pname: String = str(GameSettings.last_profile.get("name", GameSettings.player_name))
	info.add_child(UI.text(tr("氏名") + "  " + (pname if pname != "" else tr("新人")), UI.S_SMALL, UI.INK_SOFT))
	col.add_child(UI.rule(Paper.TimeCard.EDGE, 1))
	# 出勤 → お客さんごとの打刻 → 退勤
	var clock_in: int = int(sm.get("clock_in", 17 * 60))
	var clock_out: int = int(sm.get("clock_out", 23 * 60))
	_card_row(col, AgeCheck.clock_text(clock_in), tr("出勤"), "", "", UI.INK)
	for r in results:
		var res: Dictionary = r
		var outcome: String = str(res.get("outcome", ""))
		var good: bool = outcome in ["resolved", "age_ok", "age_refused"]
		var color: Color = Color("#2f7a4a") if good else (Paper.TimeCard.RED if outcome in ["explode", "yield", "suspended", "age_lax", "breakdown"] else UI.INK_SOFT)
		var clock: String = AgeCheck.clock_text(int(res.get("clock", clock_in))) if res.has("clock") else "--:--"
		_card_row(col, clock, str(res.get("title", "")), _outcome_mark(outcome), "%+d" % int(res.get("points", 0)), color)
	var suspended: bool = bool(sm.get("suspended", false))
	_card_row(col, AgeCheck.clock_text(clock_out), tr("退勤"), tr("営業停止") if suspended else "", "", Paper.TimeCard.RED)
	var rows_end: Control = UI.rule(Paper.TimeCard.EDGE, 1)
	col.add_child(rows_end)
	# 赤い縦線は打刻の行の下まで
	var card_panel: Node = col.get_parent()
	rows_end.resized.connect(func() -> void:
		if is_instance_valid(card_panel) and is_instance_valid(rows_end) and "line_end" in card_panel:
			card_panel.set("line_end", rows_end.position.y + col.position.y))
	# 売上・店舗レビュー（要件#56）
	if not sm.is_empty():
		if int(sm.get("payout", -1)) > 0:
			_receipt_line(col, tr("クレーンのペイアウト率"), "%d%%" % int(sm["payout"]), UI.S_SMALL, UI.INK_SOFT)
		_receipt_line(col, tr("売上"), "%s   %+d" % [GameSettings.money(int(sm.get("sales", 0))), int(sm.get("sales_bonus", 0))], UI.S_BODY)
		var stars: float = float(sm.get("review", 3.0))
		_receipt_line(col, tr("店舗レビュー"), "%s %.1f   %+d" % ["★".repeat(int(round(stars))) + "☆".repeat(5 - int(round(stars))), stars, int(sm.get("review_bonus", 0))])
		# 給与（要件#82）: オフラインは HP、オンラインは CUS
		if sm.has("pay"):
			_receipt_line(col, tr("給与"), Shop.pay_text(sm["pay"]), UI.S_BODY, STAMP_INK)
	col.add_child(UI.rule(Paper.TimeCard.EDGE, 1))
	var tot: HBoxContainer = UI.hbox(12)
	col.add_child(tot)
	tot.add_child(UI.text(tr("合計"), UI.S_LEAD, UI.INK, UI.F_BOLD))
	tot.add_child(UI.spacer())
	tot.add_child(UI.text(tr("%d 点") % total, UI.S_HEAD, STAMP_INK, UI.F_DOT))
	var rk: HBoxContainer = UI.hbox(12)
	col.add_child(rk)
	rk.add_child(UI.text(tr("ランク") + "  %s  %s" % [str(rank[1]), tr(str(rank[2]))], UI.S_BODY, UI.INK))
	rk.add_child(UI.spacer())
	if is_best:
		rk.add_child(UI.text(tr("★ ハイスコア更新"), UI.S_BODY, UI.SHU, UI.F_BOLD))
	var mrow: HBoxContainer = UI.hbox(12)
	col.add_child(mrow)
	var ra: int = int(mr["after"])
	var rb0: int = int(mr["before"])
	mrow.add_child(UI.text(tr("メンタル %d「%s」") % [ra, GameSettings.mental_name_a(ra)], UI.S_BODY, STAMP_INK, UI.F_DOT))
	if offline:
		mrow.add_child(UI.text(tr("オフラインのため経験値なし"), UI.S_SMALL, UI.INK_SOFT))
	else:
		mrow.add_child(UI.text("+%d EXP" % int(mr["gain"]), UI.S_SMALL, UI.INK_SOFT, UI.F_DOT))
	mrow.add_child(UI.spacer())
	if ra > rb0:
		mrow.add_child(UI.text(tr("メンタルランクアップ！"), UI.S_BODY, UI.SHU, UI.F_BOLD))
	col.add_child(UI.gap(6))
	var btns: HBoxContainer = UI.hbox(20)
	col.add_child(btns)
	var again: Button = UI.primary(tr("もう一度シフトに入る"), UI.S_LEAD)
	again.pressed.connect(_start_solo.bind(stage_id, hard))
	btns.add_child(again)
	var back: Button = UI.link(tr("タイトルへ戻る"), UI.S_BODY)
	back.pressed.connect(_quit_to_title)
	btns.add_child(back)
	show_new_titles(sm.get("new_titles", []))
	# メンタルランクの称号は、経験値を足した後で見る
	show_new_titles(Titles.check())
	# お客様の声（要件#62）は右の空いた所に付箋で
	var reviews: Array = sm.get("reviews", [])
	if not reviews.is_empty() and _sheet != null:
		var side: VBoxContainer = UI.vbox(14)
		side.anchor_left = 1.0
		side.anchor_right = 1.0
		side.offset_left = -300
		side.offset_right = -28
		side.offset_top = 240
		_sheet.add_child(side)
		side.add_child(UI.text(tr("お客様の声"), UI.S_LEAD, UI.PAPER, UI.F_SIGN))
		var i: int = 0
		for rv in reviews:
			var d: Dictionary = rv
			var n: int = int(d.get("stars", 3))
			var note: PanelContainer = UI.paper(UI.POP if n >= 4 else UI.PAPER, 14, 4)
			note.rotation_degrees = -2.0 if i % 2 == 0 else 1.5
			side.add_child(note)
			var nb: VBoxContainer = UI.vbox(4)
			note.add_child(nb)
			nb.add_child(UI.text("★".repeat(n) + "☆".repeat(5 - n), UI.S_BODY, UI.SHU if n >= 4 else UI.INK_SOFT, UI.F_DOT))
			var tl: Label = UI.para(tr("「%s」") % str(d.get("text", "")), UI.S_SMALL, UI.INK, UI.F_HAND)
			tl.custom_minimum_size = Vector2(230, 0)
			nb.add_child(tl)
			i += 1


# ---------------------------------------------------------------- 対戦ロビー（バックヤードの掲示板）

## 対戦: まず「文字で言い合う」か「声で言い合う」かを選んでから掲示板へ（要件#90）
func _ask_versus_format() -> void:
	# 初めての対戦の前に、発言の取り扱いへの同意をもらう（要件#101）。同意しないと対戦できない（1人用は遊べる）
	if GameSettings.vs_consent < VS_CONSENT_VERSION and not smoke:
		show_vs_consent(_ask_versus_format)
		return
	sfx.play("click")
	var col: VBoxContainer = _open_sheet(620, "center")
	_sheet_title(col, tr("対戦の形式を選んでください"))
	var row: HBoxContainer = UI.hbox(16)
	col.add_child(row)
	var no_voice: bool = _server_info.has("voice") and not bool(_server_info.get("voice", false))
	for f in [["text", "文字で言い合う", "キーボードで返事を打つ"], ["voice", "声で言い合う", "マイクで話す（ボイスチャット）"]]:
		var fid: String = str(f[0])
		var b: Button = Button.new()
		b.text = tr(str(f[1])) + "\n" + tr(str(f[2]))
		b.custom_minimum_size = Vector2(270, 110)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", UI.S_LEAD)
		b.add_theme_color_override("font_color", UI.INK)
		b.add_theme_color_override("font_hover_color", UI.INK)
		b.add_theme_stylebox_override("normal", UI.paper_style(UI.POP if fid == "text" else Color("#bfe0f2"), 14, 2, 3))
		b.add_theme_stylebox_override("hover", UI.paper_style(UI.POP.lightened(0.25) if fid == "text" else Color("#d6ecf8"), 14, 2, 3))
		b.add_theme_stylebox_override("pressed", UI.paper_style(UI.POP, 14, 2, 1))
		b.add_theme_stylebox_override("disabled", UI.paper_style(UI.PAPER_DIM, 14, 2, 1))
		if fid == "voice" and no_voice:
			b.disabled = true
			b.tooltip_text = tr("このサーバーは音声対戦に対応していません")
		b.pressed.connect(func() -> void:
			_vs_format = fid
			_show_versus_lobby())
		row.add_child(b)
	var back: Button = UI.link(tr("戻る"), UI.S_BODY)
	back.pressed.connect(_close_sheet)
	col.add_child(back)


func _show_versus_lobby() -> void:
	# 初めての対戦の前に、キャラクターを作る（要件#84）
	if not Shop.avatar_created() and not smoke:
		show_avatar_maker(_show_versus_lobby)
		return
	sfx.play("click")
	_close_sheet()
	_sheet = Control.new()
	_sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_sheet)
	_sheet_is_lobby = true
	_hud.set_blocked(true)
	var use_eos: bool = _versus.eos_available()
	# コルクの掲示板（要件#96）: 紙を押しピンで留め、大きさ・高さ・傾きをそろえない
	var board: Paper.Cork = Paper.Cork.new()
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
	head.add_child(Shop.name_tag(str(p.get("name", GameSettings.player_name)), Titles.equipped_name(), Shop.tag_dict(), UI.S_BODY))
	head.add_child(UI.text(tr("レート %d（%s）") % [int(p.get("rating", 1000)), tr(str(p.get("rank", "")))], UI.S_BODY, UI.POP, UI.F_DOT))
	# メンタルランク B（素材型。要件#72）
	var mb: int = GameSettings.mental_rank_b(int(p.get("rating", 1000)))
	head.add_child(UI.text(tr("メンタル %d「%s」") % [mb, GameSettings.mental_name_b(mb)], UI.S_BODY, UI.PAPER, UI.F_DOT))
	var chara: Button = UI.link(tr("キャラクター →"), UI.S_BODY, UI.POP)
	chara.pressed.connect(func() -> void:
		_sheet_is_lobby = false
		show_avatar_maker(_show_versus_lobby))
	head.add_child(chara)

	# 形式（文字・音声）は先に選んである（要件#90）。ここでは表示と「変える」だけ
	var fmt_row: HBoxContainer = UI.hbox(12)
	root.add_child(fmt_row)
	fmt_row.add_child(UI.text(tr("対戦の形式:") + " " + (tr("文字で言い合う") if _vs_format == "text" else tr("声で言い合う")), UI.S_BODY, UI.PAPER))
	var change: Button = UI.link(tr("形式を変える"), UI.S_SMALL, UI.POP)
	change.pressed.connect(func() -> void:
		_versus.cancel()
		_ask_versus_format())
	fmt_row.add_child(change)

	var notes: HBoxContainer = UI.hbox(32)
	notes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(notes)

	# ランクマッチ（いちばん大きいポスター。少し左に傾ける）
	var ranked: PanelContainer = UI.paper(UI.PAPER, 24, 5)
	var ranked_pin: Paper.PinnedNote = _pin_note(ranked, -1.2, UI.SHU, 0)
	ranked_pin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ranked_pin.size_flags_stretch_ratio = 1.5
	notes.add_child(ranked_pin)
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
	# フレンド対戦（黄色い付箋。少し下げて、右に傾ける）
	var friend: PanelContainer = UI.paper(UI.POP, 18, 3)
	var friend_pin: Paper.PinnedNote = _pin_note(friend, 1.6, Color("#2f6fb0"), 36)
	friend_pin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friend_pin.size_flags_stretch_ratio = 1.0
	notes.add_child(friend_pin)
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
	var board_note: PanelContainer = UI.paper(Color("#f7f3e8"), 18, 4)
	board_note.custom_minimum_size = Vector2(300, 0)
	notes.add_child(_pin_note(board_note, -0.6, UI.OK, 12))
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


## 掲示板に紙を留める。drop: 上からの下げ幅（紙ごとに高さをずらす）
func _pin_note(note: Control, tilt: float, pin: Color, drop: int) -> Paper.PinnedNote:
	var pn: Paper.PinnedNote = Paper.PinnedNote.new()
	pn.tilt = tilt
	pn.pin_color = pin
	pn.top_gap = float(drop)
	pn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pn.add_child(note)
	return pn


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
	show_new_titles(summary.get("new_titles", []))
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
	if reason == "moderation":
		col.add_child(UI.para(tr("不適切な発言が続いたため、決着しました。") , UI.S_SMALL, UI.SHU))
	if reason == "disconnected" or reason == "left":
		col.add_child(UI.para(tr("相手が途中で抜けたため、決着しました。") if result == "win" else tr("途中で抜けたため、負けになりました。"), UI.S_SMALL, UI.INK_SOFT))
	_receipt_rule(col)
	_receipt_line(col, tr("あなた"), tr("%d 点") % int(summary.get("you_points", 0)))
	_receipt_line(col, tr("相手"), tr("%d 点") % int(summary.get("opponent_points", 0)))
	_receipt_rule(col)
	if str(summary.get("kind", "")) == "ranked":
		_receipt_line(col, tr("レート"), "%d → %d" % [int(summary.get("rating_before", 0)), int(summary.get("rating_after", 0))], UI.S_LEAD)
		var b0: int = GameSettings.mental_rank_b(int(summary.get("rating_before", 1000)))
		var b1: int = GameSettings.mental_rank_b(int(summary.get("rating_after", 1000)))
		_receipt_line(col, tr("メンタル"), "%s → %s" % [GameSettings.mental_name_b(b0), GameSettings.mental_name_b(b1)], UI.S_BODY, UI.SHU if b1 > b0 else UI.INK)
		_receipt_line(col, "", "%+d" % int(summary.get("rating_delta", 0)), UI.S_LEAD, UI.SHU if int(summary.get("rating_delta", 0)) >= 0 else UI.INK)
		_receipt_line(col, tr("ランク"), tr(str(summary.get("rank", ""))))
		match str(summary.get("rating_note", "")):
			"same_pair":
				col.add_child(UI.para(tr("同じ相手と続けて対戦したため、レートは変わりません。"), UI.S_SMALL, UI.INK_SOFT))
			"early_leave":
				col.add_child(UI.para(tr("始まってすぐに決着したため、勝った側のレートは上がりません。"), UI.S_SMALL, UI.INK_SOFT))
	else:
		_receipt_line(col, tr("フレンド対戦"), tr("レート変動なし"))
	if int(summary.get("pay_kas", 0)) > 0:
		_receipt_line(col, tr("給与"), "+%d CUS" % int(summary["pay_kas"]), UI.S_BODY)
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
	# 相手を通報する（要件#87）
	var target: Dictionary = _versus.report_target()
	if str(target.get("player_id", "")) != "":
		var rep: Button = UI.link(tr("相手を通報する"), UI.S_SMALL, UI.INK_SOFT)
		rep.alignment = HORIZONTAL_ALIGNMENT_CENTER
		rep.pressed.connect(func() -> void: show_report(target, summary))
		col.add_child(rep)


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
	# 自動テストでは同意しておく（要件#101）
	await api.ensure_login()
	await api.request("POST", "/api/v1/me/consent", {"agree": true, "version": VS_CONSENT_VERSION})
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
	get_tree().create_timer(900.0).timeout.connect(func() -> void:
		print("SHOTS TIMEOUT")
		get_tree().quit(1))
	# --shot-tag=xxx で、画面サイズ違いの撮影を別の名前で保存する
	var tag: String = _arg("--shot-tag=")
	var prefix: String = GameSettings.language + ("_" + tag if tag != "" else "") + "_"
	GameSettings.last_profile = {"name": "テスト店員" if GameSettings.language == "ja" else "Test Clerk", "rating": 1084, "rank": "バイトリーダー"}
	GameSettings.avatar = {"created": true, "gender": "f", "height": 1.0, "build": "normal", "skin": "s2"}
	GameSettings.equipped_items = {"hair": "ponytail", "hair_color": "brown", "casual": "red", "uniform": "blue", "acc": "ribbon"}
	GameSettings.owned_items = ["hair:ponytail", "casual:red", "acc:ribbon"]
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
		if s == "konbini":
			# お酒・たばこの年齢確認（要件#63）
			show_id_card(AgeCheck.make(20 * 60, GameSettings.language, "konbini"))
			await _wait(0.4)
			await _shot(dir, prefix + "konbini_3c_id_card")
			close_machine_data()
		# 店長がアドバイスに来るイベント（要件#52）
		_hud.set_input_enabled(false, "")
		_hud.show_banner(tr("店長が来た！"), UI.POP)
		await manager_enter()
		manager_talk(3.0)
		var kws: Array = cust.get("solution_keywords", [])
		_hud.set_comment(tr("店長: ") + (tr("「%s」について具体的に伝えてみろ。") % str(kws[0] if not kws.is_empty() else "")) + " " + tr("要求は飲むなよ。"))
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
			await show_machine_data(cust)
			await _wait(0.4)
			await _shot(dir, prefix + "arcade_4b_machine_data")
			close_machine_data()
			# 年齢確認の身分証（要件#61）
			show_id_card(AgeCheck.make(22 * 60 + 30, GameSettings.language))
			await _wait(0.4)
			await _shot(dir, prefix + "arcade_4c_id_card")
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
	_solo.summary = {"sales": 21400, "review": 3.6, "sales_bonus": 70, "review_bonus": 240, "payout": 25, "clock_in": 1020, "clock_out": 1380,
		"reviews": [{"stars": 5, "text": tr("店員さんが景品を取りやすくしてくれた！神対応！")}, {"stars": 2, "text": tr("クレーン、全然取れない。お金が溶けただけ。")}]}
	_on_solo_finished("arcade", [
		{"title": str(cs[0]["title"]).replace("{spent}", GameSettings.money(3500)), "outcome": "resolved", "points": 1520, "turns": 3, "clock": 1050},
		{"title": cs[1]["title"], "outcome": "explode", "points": -300, "turns": 2, "clock": 1155},
		{"title": cs[5]["title"], "outcome": "resolved", "points": 1430, "turns": 4, "clock": 1260},
		{"title": tr("自称ハタチ") if GameSettings.language == "ja" else cs[4]["title"], "outcome": "age_refused", "points": 600, "turns": 1, "clock": 1350},
	], 3250)
	await _wait(0.6)
	await _shot(dir, prefix + "05_result")
	_close_sheet()
	_show_title()
	_show_settings()
	await _wait(0.6)
	await _shot(dir, prefix + "06_settings")
	# 称号の一覧（要件#79）: いくつか手に入れた状態で
	GameSettings.unlocked_titles = ["t001", "t002", "t003", "t007", "t015", "t021", "t024", "t026", "t039", "t051", "t073", "t082"]
	GameSettings.equipped_title = "t026"
	_show_titles()
	await _wait(0.6)
	await _shot(dir, prefix + "06b_titles")
	# ショップ（要件#82）: 名札の枠
	GameSettings.hp_points = 1250
	GameSettings.kas_points = 480
	GameSettings.owned_items = ["frame:neon", "stamp:oni"]
	GameSettings.equipped_items = {"frame": "neon", "stamp": "oni"}
	_shop_tab = "tag"
	_show_shop()
	await _wait(0.6)
	await _shot(dir, prefix + "06c_shop")
	_close_sheet()
	_refresh_title()
	await _wait(0.4)
	await _shot(dir, prefix + "06d_title_card")
	# 背景ガチャ（要件#84）
	GameSettings.kas_points = 1500
	_show_gacha_result(Shop.gacha_pull("kas", true))
	await _wait(3.4)
	await _shot(dir, prefix + "06e_gacha")
	_shop_tab = "exchange"
	_show_shop()
	await _wait(0.5)
	await _shot(dir, prefix + "06h_exchange")
	GameSettings.owned_items.append_array(["hair:ponytail", "casual:red", "acc:ribbon"])
	GameSettings.equipped_items.merge({"hair": "ponytail", "hair_color": "brown", "casual": "red", "uniform": "blue", "acc": "ribbon"}, true)
	_shop_tab = "chara"
	_show_shop()
	await _wait(0.8)
	await _shot(dir, prefix + "06f_shop_chara")
	_close_sheet()
	show_avatar_maker(Callable())
	await _wait(0.8)
	await _shot(dir, prefix + "06g_avatar_maker")
	_close_sheet()
	# 記録: レビューログと統計（要件#86）
	GameSettings.add_review_log({"date": "2026-11-18 21:30", "stage": "arcade", "review": 3.6, "sales": 21400, "total": 3250, "hard": false,
		"reviews": [{"stars": 5, "text": tr("店員さんが景品を取りやすくしてくれた！神対応！")}, {"stars": 2, "text": tr("クレーン、全然取れない。お金が溶けただけ。")}]})
	_records_tab = "reviews"
	_show_records()
	await _wait(0.5)
	await _shot(dir, prefix + "06i_review_log")
	_records_tab = "stats"
	_show_records()
	await _wait(0.5)
	await _shot(dir, prefix + "06j_stats")
	_close_sheet()
	# 新しい背景（日本語のときだけ撮る）
	if GameSettings.language == "ja" and tag == "":
		for bgid in ["bg_medal", "bg_video", "bg_video_rage", "bg_rhythm", "bg_office", "bg_purikura", "bg_locker", "bg_toilet", "bg_warehouse", "bg_manager_home", "bg_parents_home"]:
			GameSettings.owned_items.append("bg:" + bgid)
			Shop.equip("bg", bgid)
			_show_title()
			_title.visible = false
			await _wait(1.0)
			await _shot(dir, prefix + "bg_" + bgid.trim_prefix("bg_"))
		Shop.equip("bg", "arcade_day")
		_show_title()
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
	# 対戦の客役の画面（要件#84）: 相手（店員役）のキャラクターをカウンターの外から見る
	_close_sheet()
	set_stage("arcade")
	await spawn_customer(Shop.avatar_look(Shop.avatar_dict(), "casual"))
	spawn_staff(Shop.avatar_look({"gender": "m", "height": 1.05, "build": "big", "skin": "s3", "hair": "spiky", "hair_color": "black", "casual": "navy", "uniform": "green", "acc": "sunglasses"}, "uniform"))
	set_customer_view(true)
	_hud.clear_round()
	_hud.visible = false
	await _wait(1.2)
	await _shot(dir, prefix + "10_versus_customer_view")
	set_customer_view(false)
	free_staff()
	print("SHOTS OK")
	get_tree().quit(0)
