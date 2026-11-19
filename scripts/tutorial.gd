extends Node
## チュートリアル（新人研修。要件#53）。店長がカウンターの横に来て、画面の部品を1つずつ指しながら説明する。
## 最後に台本のお客さん1人を、実際に返事を書いて納得させる（怒りは上がらない。何度でもやり直せる）。
##
## 流れ（_run）:
##   1. 店長が来る・あいさつ
##   2. お客さんが来る → フキダシ・引き継ぎメモ・お客様表示・メンタル・店長の付箋を順に指す
##   3. 接客用語のタグ・店の行動ボタン → 記入欄に返事を書いてみる（納得が100になるまで）
##   4. 屈服しないこと・ゲームセンターの対応（台ごとのボタン・筐体のデータ・難易度の調整）を説明して終わり
## 画面の部品は hud.get_part() で受け取り、赤い枠で囲む。説明の紙（店長の研修メモ）は、囲んだ部品と反対側に出す。
## auto = true（自動テスト・スクリーンショット）のときは、ボタンを自動で押し、返事も自動で書く。

const UI = preload("res://scripts/ui_kit.gd")
const Judge = preload("res://scripts/offline_judge.gd")
const ShopActions = preload("res://scripts/shop_actions.gd")
const Scenarios = preload("res://scripts/scenarios.gd")
const Titles = preload("res://scripts/titles.gd")

signal finished
signal _next
## 自動のとき、hold_step の説明で止まったら出す（スクリーンショット用。resume() で続ける）
signal held

var main = null
var hud = null
var auto: bool = false
var hold_step: int = -1
var _run: int = 0
var _active: bool = false
var _overlay: Control = null
var _frame: Panel = null
var _card: PanelContainer = null
var _card_text: Label = null
var _card_next: Button = null
var _step_label: Label = null
var _cust: Dictionary = {}
var _anger: float = 40.0
var _resolve: float = 0.0
var _used: Array = []
var _waiting_reply: bool = false

const STEPS: int = 12


func setup(main_node, hud_node) -> void:
	main = main_node
	hud = hud_node


func is_active() -> bool:
	return _active


func abort() -> void:
	_run += 1
	_active = false
	_waiting_reply = false
	_free_overlay()


func start() -> void:
	_run += 1
	_active = true
	_build_overlay()
	_go(_run)


# ---------------------------------------------------------------- 画面（枠と説明の紙）

func _build_overlay() -> void:
	_free_overlay()
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_overlay(_overlay)
	_frame = Panel.new()
	var st: StyleBoxFlat = StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0)
	st.border_color = UI.SHU
	st.set_border_width_all(5)
	st.set_corner_radius_all(4)
	_frame.add_theme_stylebox_override("panel", st)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.visible = false
	_overlay.add_child(_frame)
	_card = UI.paper(UI.POP, 18, 5)
	_card.custom_minimum_size = Vector2(540, 0)
	_card.rotation_degrees = -0.6
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(_card)
	var col: VBoxContainer = UI.vbox(8)
	_card.add_child(col)
	var head: HBoxContainer = UI.hbox(8)
	col.add_child(head)
	head.add_child(UI.text(tr("店長の研修メモ"), UI.S_SMALL, UI.INK_SOFT, UI.F_HAND))
	head.add_child(UI.spacer())
	_step_label = UI.text("", UI.S_SMALL, UI.INK_SOFT, UI.F_DOT)
	head.add_child(_step_label)
	_card_text = UI.para("", UI.S_LEAD, UI.INK, UI.F_HAND)
	_card_text.custom_minimum_size = Vector2(500, 0)
	col.add_child(_card_text)
	var row: HBoxContainer = UI.hbox(16)
	col.add_child(row)
	_card_next = UI.primary(tr("次へ"), UI.S_BODY)
	_card_next.focus_mode = Control.FOCUS_NONE
	_card_next.pressed.connect(func() -> void:
		main.sfx.play("click")
		_next.emit())
	row.add_child(_card_next)
	row.add_child(UI.spacer())
	var skip: Button = UI.link(tr("研修をやめる"), UI.S_SMALL, UI.INK_SOFT)
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(func() -> void:
		_end(false))
	row.add_child(skip)


func _free_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	_frame = null
	_card = null


## 部品を赤い枠で囲み、説明の紙を反対側に出す。part が "" なら枠なしで真ん中に
func _point(part_name: String, text: String, step: int, show_next: bool = true) -> void:
	if _card == null:
		return
	_card_text.text = text
	_step_label.text = "%d / %d" % [step, STEPS]
	_card_next.visible = show_next
	var vp: Vector2 = main.get_viewport().get_visible_rect().size
	var target: Control = hud.get_part(part_name) if part_name != "" else null
	var card_w: float = _card.custom_minimum_size.x
	await main.get_tree().process_frame
	if _card == null:
		return
	var card_h: float = _card.size.y
	var pos: Vector2 = Vector2((vp.x - card_w) * 0.5, vp.y * 0.30 - card_h * 0.5)
	if target != null and is_instance_valid(target) and target.is_visible_in_tree():
		var r: Rect2 = target.get_global_rect().grow(8.0)
		_frame.position = r.position
		_frame.size = r.size
		_frame.visible = true
		main.sfx.play("warn", 1.6)
		# 部品が画面の上半分なら紙は下、下半分なら紙は上。左右も部品の反対側に寄せる
		var cy: float = r.get_center().y
		var cx: float = r.get_center().x
		pos.y = (vp.y * 0.08) if cy > vp.y * 0.5 else clampf(r.end.y + 16.0, vp.y * 0.08, vp.y - card_h - 16.0)
		if r.size.x < vp.x * 0.5:
			pos.x = (vp.x - card_w - 32.0) if cx < vp.x * 0.5 else 32.0
	else:
		_frame.visible = false
	_card.position = Vector2(clampf(pos.x, 16.0, maxf(16.0, vp.x - card_w - 16.0)), clampf(pos.y, 16.0, maxf(16.0, vp.y - card_h - 16.0)))


## 説明を出して「次へ」を待つ
func _say(part_name: String, text: String, step: int) -> bool:
	var my_run: int = _run
	await _point(part_name, text, step, true)
	if auto and step == hold_step:
		await main.get_tree().create_timer(0.6).timeout
		held.emit()
		await _next
	elif auto:
		await main.get_tree().create_timer(0.45).timeout
	else:
		await _next
	return my_run == _run


func resume() -> void:
	_next.emit()


# ---------------------------------------------------------------- 流れ

func _go(my_run: int) -> void:
	_cust = (Scenarios.customers("konbini")[0] as Dictionary).duplicate(true)
	_anger = 40.0
	_resolve = 0.0
	_used = []
	hud.clear_round()
	hud.set_top(tr("コンビニ「ハッピーマート」"), tr("新人研修"), "")
	hud.set_mental(80.0)
	hud.set_gauges(_anger, _resolve, -1.0)
	hud.set_actions([])
	hud.set_comment(tr("落ち着いて、まずは話を聞こう。"))
	hud.set_input_enabled(false, "")

	# 1. 店長が来る
	_point("", tr("（店長が来ます…）"), 1, false)
	await main.manager_enter()
	if my_run != _run:
		return
	main.manager_talk(2.5)
	await _say("", tr("新人さん、ようこそ！店長だ。\n今日はクレーム対応の基本を教える。お客さんを怒らせずに、納得して帰ってもらうのが仕事だ。"), 1)
	if my_run != _run:
		return

	# 2. お客さんが来る
	_point("", tr("（お客さんが来ます…）"), 2, false)
	main.sfx.play("door")
	await main.spawn_customer(_cust.get("look", {}))
	if my_run != _run:
		return
	hud.set_memo(str(_cust.get("title", "")), str(_cust.get("memo", "")), str(_cust.get("demand", "")))
	hud.set_actions(ShopActions.buttons("konbini", _cust, false))
	await main.customer_say(tr("%s（%s）") % [str(_cust.get("title", "")), str(_cust.get("name", ""))], str(_cust.get("opening", "")), true)
	if my_run != _run:
		return
	await _say("bubble", tr("お客さんの言ったことは、このフキダシに出る。まずはよく読もう。"), 2)
	if my_run != _run:
		return
	await _say("memo", tr("左の「引き継ぎメモ」には、本当は何が起きたのか、店の規定で何ができて何ができないか、お客さんの不当な要求が書いてある。正しい対応のヒントはここだ。"), 3)
	if my_run != _run:
		return
	await _say("lcd", tr("右上は「お客様表示」。イカリが100になるとブチギレ、ナットクが100になると納得して帰る。本番では、返事を考えている間にイカリが少しずつ上がる（研修中は止めてある）。"), 4)
	if my_run != _run:
		return
	await _say("mental", tr("ここは、あなたのメンタル。怒られると減って、0になると早退だ。"), 5)
	if my_run != _run:
		return
	await _say("note", tr("黄色い付箋は、わたし（店長）からのひとこと。返事のよかったところ・まずかったところをここで教える。"), 6)
	if my_run != _run:
		return
	await _say("phrases", tr("接客用語のタグ。押すと記入欄に入る。そのまま送るより、続けて具体的な対応を書き足すといい。"), 7)
	if my_run != _run:
		return
	await _say("actions", tr("店の行動ボタン。コンビニは「割引する」「土下座する」。土下座はほぼ逆効果だぞ。\nゲームセンターでは、台の種類ごとに「メンテナンス」「クレジットを補填」「難易度を調整」などが出る。"), 8)
	if my_run != _run:
		return

	# 3. 実際に返事を書く
	# ヒントは単語だけにせず「何に触れて、何を伝えるか」まで書く（要件#65）
	var hint: String = ""
	for k in (_cust.get("solution_keywords", []) as Array).slice(0, 2):
		hint += tr("『%s』") % str(k)
	_point("input", tr("では、やってみよう。記入欄に返事を書いて Enter（または「返事をする」）。\nコツ: おわび＋気持ちを受け止める＋メモにある「できること」を具体的に。") + "\n" + tr("ヒント: %sに触れて、できることを伝えよう。") % hint, 9, false)
	var ok: bool = await _practice(my_run)
	if not ok:
		return

	# 4. まとめ
	await _say("", tr("よくできた！ナットクが100になった。\n不当な要求（メモの赤い字）を飲むと「屈服」で大きく減点だ。できないことは、言い方に気をつけて、はっきり断ろう。"), 10)
	if my_run != _run:
		return
	main.dismiss_customer("happy")
	await _say("", tr("ゲームセンターでは、ほかにもこんな対応がある。\n・「〇〇円使っても取れない」と言われたら「筐体のデータを見る」。嘘なら記録をもとに話し、本当なら景品を取りやすい位置へ。\n・「難易度を調整」では、アームの強さ（パワー設定）か、ペイアウト率（確率設定）を決めて、テストプレイもできる。"), 11)
	if my_run != _run:
		return
	await _say("", tr("研修はこれで終わりだ。あとはシフトに入って慣れていこう。\nたまに、とんでもないお客さん（要注意人物）が来ることもある。困ったら、わたしが様子を見に来るかもしれない。"), 12)
	if my_run != _run:
		return
	_end(true)


## 練習: 納得が100になるまで返事を書いてもらう（怒りは時間では上がらない）
func _practice(my_run: int) -> bool:
	var tries: int = 0
	while _resolve < 100.0:
		hud.set_input_enabled(true, tr("ここに返事を書く…"))
		_waiting_reply = true
		var reply: String = ""
		if auto:
			await main.get_tree().create_timer(0.4).timeout
			reply = _auto_reply(tries)
		else:
			reply = await hud.reply_submitted
		_waiting_reply = false
		if my_run != _run:
			return false
		hud.set_input_enabled(false, "")
		tries += 1
		hud.show_echo(tr("あなた: "), reply)
		var res: Dictionary = Judge.judge(_cust, reply, _used, _anger, _resolve)
		# 自動テストで終わらなくならないように（判定の語が合わない言語でも、8回で納得したことにする）
		if auto and tries >= 8:
			res["resolve_delta"] = 100
			res["anger_delta"] = -10
		_used.append(reply)
		var a: int = int(res.get("anger_delta", 0))
		var r: int = int(res.get("resolve_delta", 0))
		_anger = clampf(_anger + float(a), 0.0, 100.0)
		_resolve = clampf(_resolve + float(r), 0.0, 100.0)
		hud.show_delta(a, r)
		hud.set_gauges(_anger, _resolve, -1.0)
		hud.set_comment(str(res.get("comment", "")))
		main.display_anger = _anger
		main.customer_react("calm" if a < 0 else ("angry" if a > 0 else "calm"))
		main.sfx.play("good" if a < 0 else "bad", 1.2)
		var line: String = str(res.get("customer_reply", ""))
		if line == "":
			var key: String = "resolved" if _resolve >= 100.0 else ("calm" if a < 0 else "angry")
			line = Judge.line(_cust, key)
		await main.customer_say(tr("%s（%s）") % [str(_cust.get("title", "")), str(_cust.get("name", ""))], line, a > 0)
		if my_run != _run:
			return false
		if bool(res.get("yielded", false)):
			_resolve = 0.0
			hud.set_gauges(_anger, _resolve, -1.0)
			await _say("note", tr("おっと、それは不当な要求を飲んでしまっている（屈服）。本番なら大きな減点だ。もう一度！"), 9)
			if my_run != _run:
				return false
			_point("input", tr("もう一度、記入欄に返事を書いてみよう。"), 9, false)
		elif _anger >= 100.0:
			_anger = 50.0
			hud.set_gauges(_anger, _resolve, -1.0)
			await _say("lcd", tr("ブチギレさせてしまった…。本番ならここで終わりだが、研修なのでもう一回。言い訳や乱暴な言い方は逆効果だ。"), 9)
			if my_run != _run:
				return false
			_point("input", tr("もう一度、記入欄に返事を書いてみよう。"), 9, false)
		elif _resolve < 100.0:
			var more: String = tr("いい調子。ナットクが100になるまで続けよう。") if r > 0 else tr("ナットクが上がらなかった。メモの「できること」を、具体的に伝えてみよう。")
			_point("input", more, 9, false)
	return true


## 自動テスト用の返事（おわび＋共感＋解決の言葉2つ）
func _auto_reply(tries: int) -> String:
	var kws: Array = _cust.get("solution_keywords", [])
	var w1: String = str(kws[tries % kws.size()]) if not kws.is_empty() else ""
	var w2: String = str(kws[(tries + 1) % kws.size()]) if not kws.is_empty() else ""
	if GameSettings.language == "en":
		return "I'm very sorry, I understand how you feel. Let me %s and %s for you right away, sir. (%d)" % [w1, w2, tries]
	if GameSettings.language == "ko":
		return "정말 죄송합니다. 마음 충분히 이해합니다. 바로 %s와 %s 대응해 드리겠습니다. (%d)" % [w1, w2, tries]
	if GameSettings.language == "zh":
		return "非常抱歉，我很理解您的心情。请让我马上为您处理%s和%s的事。（%d）" % [w1, w2, tries]
	return "大変申し訳ございません。お気持ちお察しいたします。すぐに%sと%sの対応をいたします。（%d）" % [w1, w2, tries]


func _end(completed: bool) -> void:
	if not _active:
		return
	_active = false
	_run += 1
	GameSettings.tutorial_seen = true
	if completed:
		GameSettings.stat_add("tutorial_done")
	GameSettings.save_settings()
	_free_overlay()
	if completed:
		main.sfx.play("win")
		main.show_new_titles(Titles.check())
	finished.emit()
