extends Node
## 1人用モードの進行。1シフト = お客さん CUSTOMERS_PER_SHIFT 人。
## お客さんの用意と採点は、設定（GameSettings.solo_source）で選んだ先に頼む:
##   "server"  … ゲームサーバー（既定）。つながらないときは台本に切り替える
##   "own_key" … 自分の Claude APIキー（llm_client.gd）
##   "offline" … 台本とキーワード判定（offline_judge.gd）
## 画面・3Dの操作は main と hud に頼み、ここはルールだけを持つ。

const Scenarios = preload("res://scripts/scenarios.gd")
const Judge = preload("res://scripts/offline_judge.gd")
const UI = preload("res://scripts/ui_kit.gd")
const ShopActions = preload("res://scripts/shop_actions.gd")

signal finished(stage_id: String, results: Array, total: int)
signal _reply(text: String)

const CUSTOMERS_PER_SHIFT: int = 4
const BASE_ANGER_RATE: float = 1.25     # 返事を考えている間、1秒あたりに上がる怒り
const RATE_STEP: float = 0.15           # お客さん1人ごとの上昇率
const SCORE_RESOLVED: int = 1000
const SCORE_EXPLODED: int = -300
const SCORE_YIELDED: int = -600
const SCORE_BREAKDOWN: int = -500
## 行動ボタンの店の負担（点数から引く）。台の調整で規定外の強さにしたら CHEAT
const ACTION_COST: Dictionary = {"discount": 100, "dogeza": 0, "medal_return": 100, "compensate": 50}
const CHEAT_COST: int = 150
## 店員のメンタル（要件#38）
const MENTAL_MAX: float = 100.0
const ACTION_PREFIX: String = "\u0001action:"

var main = null
var hud = null
var paused: bool = false

var _run: int = 0
var _active: bool = false
var _stage_id: String = ""
var _stage_name: String = ""
var _pool: Array = []
var _titles: Array = []
var _results: Array = []
var _total: int = 0
var _index: int = 0

var _cust: Dictionary = {}
var _source: String = "offline"   # このお客さんの採点先: "server" | "own_key" | "offline"
var _session_id: String = ""
var _anger: float = 0.0
var _resolve: float = 0.0
var _rate: float = 1.0
var _turns: int = 0
var _history: Array = []
var _used: Array = []
var _player_turn: bool = false
var _mental: float = MENTAL_MAX
var _cost: int = 0            # このお客さんでの行動の負担
var _crane_used: bool = false


func setup(main_node, hud_node) -> void:
	main = main_node
	attach_hud(hud_node)


## 画面（HUD）を作り直したときに付け替える
func attach_hud(hud_node) -> void:
	hud = hud_node
	hud.reply_submitted.connect(_on_reply)
	hud.action_pressed.connect(_on_action)


func is_active() -> bool:
	return _active


func abort() -> void:
	_run += 1
	_active = false
	_player_turn = false


func start(stage_id: String, stage_name: String) -> void:
	_run += 1
	var my_run: int = _run
	_active = true
	paused = false
	_stage_id = stage_id
	_stage_name = stage_name
	_results = []
	_titles = []
	_total = 0
	_pool = []
	_mental = MENTAL_MAX
	hud.set_mental(_mental)
	hud.set_voice_mode(false)
	hud.set_quick_phrases(hud.DEFAULT_PHRASES)
	for i in range(CUSTOMERS_PER_SHIFT):
		_index = i
		await _play_customer(my_run)
		if my_run != _run:
			return
		if _mental <= 0.0:
			# 心が折れたので早退（要件#38）
			hud.show_banner(tr("心が折れた…早退します"), Color("#ff8a6a"))
			await _wait(2.0)
			if my_run != _run:
				return
			break
	_active = false
	finished.emit(_stage_id, _results, _total)


func _process(delta: float) -> void:
	if not _active or not _player_turn or paused:
		return
	_anger = minf(100.0, _anger + _rate * delta)
	_refresh(true)
	if _anger >= 100.0:
		_player_turn = false
		hud.set_input_enabled(false, "")
		_reply.emit("")


## 店の行動ボタン
func _on_action(id: String) -> void:
	if _active and _player_turn and main.mode == "solo":
		_player_turn = false
		_reply.emit(ACTION_PREFIX + id)


func _change_mental(delta: float) -> void:
	_mental = clampf(_mental + delta, 0.0, MENTAL_MAX)
	hud.set_mental(_mental)


func _on_reply(text: String) -> void:
	if _active and _player_turn and main.mode == "solo":
		_player_turn = false
		_reply.emit(text)


func _refresh(show_countdown: bool) -> void:
	var left: float = -1.0
	if show_countdown and _rate > 0.0:
		left = (100.0 - _anger) / _rate
	hud.set_gauges(_anger, _resolve, left)
	main.display_anger = _anger


func _update_top() -> void:
	hud.set_top(_stage_name, tr("お客さん %d / %d") % [_index + 1, CUSTOMERS_PER_SHIFT], tr("%d 点") % _total)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _next_offline() -> Dictionary:
	if _pool.is_empty():
		_pool = Scenarios.customers(_stage_id).duplicate()
		_pool.shuffle()
	return (_pool.pop_back() as Dictionary).duplicate(true)


## お客さんを用意する。戻り値: お客さんデータ（_source と _session_id も決まる）
func _prepare_customer() -> Dictionary:
	_session_id = ""
	var src: String = GameSettings.solo_source
	if src == "server":
		hud.set_status(tr("お客さんが来ます…"))
		var res: Dictionary = await main.api.request("POST", "/api/v1/solo/start", {"stage": _stage_id, "avoid": _titles, "lang": GameSettings.language})
		if bool(res.get("ok", false)):
			var body: Dictionary = res["body"]
			_source = "server"
			_session_id = str(body.get("session_id", ""))
			var notice: String = str(body.get("notice", ""))
			if notice != "":
				hud.set_comment(notice)
			return body.get("customer", {})
		hud.set_comment(tr("サーバーにつながりません。台本のお客さんで続けます。") + "\n" + str(res.get("message", "")))
	elif src == "own_key" and GameSettings.own_key_ready():
		hud.set_status(tr("AIが次のお客さんを考えています…"))
		var data: Dictionary = await main.llm.generate_customer(_stage_id, _titles)
		if not data.has("error"):
			_source = "own_key"
			return data
		hud.set_comment(tr("AI接続エラー: %s\n台本のお客さんで続けます。") % str(data["error"]))
	_source = "offline"
	return _next_offline()


func _play_customer(my_run: int) -> void:
	_player_turn = false
	hud.clear_round()
	_update_top()
	hud.set_comment(tr("落ち着いて、まずは話を聞こう。"))

	var data: Dictionary = await _prepare_customer()
	if my_run != _run:
		return
	_cust = data
	_titles.append(str(_cust.get("title", "")))
	_anger = float(_cust.get("start_anger", 40))
	_resolve = 0.0
	_turns = 0
	_history = []
	_used = []
	_rate = BASE_ANGER_RATE * float(_cust.get("patience", 1.0)) * (1.0 + RATE_STEP * float(_index)) * GameSettings.answer_rate()
	_cost = 0
	_crane_used = false
	_refresh(false)

	# ---- 来店
	hud.set_status(tr("いらっしゃいませ…"))
	main.sfx.play("door")
	var look: Dictionary = {}
	if typeof(_cust.get("look", null)) == TYPE_DICTIONARY:
		look = _cust["look"]
	await main.spawn_customer(look)
	if my_run != _run:
		return
	hud.set_actions(ShopActions.buttons(_stage_id, _cust, true))
	var speaker: String = tr("%s（%s）") % [str(_cust.get("title", tr("お客さん"))), str(_cust.get("name", ""))]
	hud.set_memo(str(_cust.get("title", "")), str(_cust.get("memo", "")), str(_cust.get("demand", "")))
	var opening: String = str(_cust.get("opening", "……"))
	_history.append({"role": "customer", "text": opening})
	await main.customer_say(speaker, opening, true)
	if my_run != _run:
		return

	# ---- 会話
	var outcome: String = ""
	while outcome == "":
		_player_turn = true
		hud.set_status(tr("キレられる前に返事を書こう（Enterで渡す）"))
		hud.set_input_enabled(true, tr("ここに返事を書く…"))
		if main.smoke:
			_smoke_autoplay(my_run)
		var reply: String = await _reply
		if my_run != _run:
			return
		_player_turn = false
		hud.set_input_enabled(false, "")
		if reply == "":
			outcome = "explode"
			_anger = 100.0
			_refresh(false)
			await _customer_line(speaker, Judge.line(_cust, "explode"), "explode")
			if my_run != _run:
				return
			break

		var res: Dictionary = {}
		if reply.begins_with(ACTION_PREFIX):
			# ---- 店の行動ボタン（要件#34）・台の調整（要件#37）
			var id: String = reply.substr(ACTION_PREFIX.length())
			if id == ShopActions.CRANE_ADJUST:
				hud.set_status(tr("台を調整しています…"))
				var cr: Dictionary = await main.run_crane_minigame()
				if my_run != _run:
					return
				if str(cr.get("result", "cancelled")) == "cancelled":
					continue
				_crane_used = true
				hud.set_actions(ShopActions.buttons(_stage_id, _cust, false))
				id = "crane_won" if str(cr["result"]) == "won" else "crane_lost"
				if bool(cr.get("cheat", false)):
					_cost += CHEAT_COST
			_turns += 1
			hud.show_echo(tr("あなた: "), tr("（行動: %s）") % ShopActions.label(id))
			_history.append({"role": "staff", "text": tr("（行動: %s）") % ShopActions.label(id)})
			hud.set_status(tr("お客さんの反応を待っています…"))
			_refresh(false)
			res = await _judge_action(id)
			if my_run != _run:
				return
			_cost += int(ACTION_COST.get(id, 0))
			if id == "dogeza":
				_change_mental(-20.0)
			if id.begins_with("crane_") and _cost >= CHEAT_COST:
				res["comment"] = str(res.get("comment", "")) + "\n" + tr("（アームは規定外の強さ…店長には内緒だ）")
		else:
			_turns += 1
			hud.show_echo(tr("あなた: "), reply)
			_history.append({"role": "staff", "text": reply})
			hud.set_status(tr("お客さんの反応を待っています…"))
			_refresh(false)
			res = await _judge(reply)
			if my_run != _run:
				return
			_used.append(reply)

		var a_delta: int = int(res.get("anger_delta", 0))
		var r_delta: int = int(res.get("resolve_delta", 0))
		_anger = clampf(_anger + float(a_delta), 0.0, 100.0)
		_resolve = clampf(_resolve + float(r_delta), 0.0, 100.0)
		_refresh(false)
		hud.show_delta(a_delta, r_delta)
		hud.set_comment(str(res.get("comment", "")))

		# 店員のメンタル: 怒られるほど減り、落ち着かせると少し戻る
		if a_delta > 0:
			_change_mental(-float(a_delta) * 0.6)
		elif a_delta < 0:
			_change_mental(1.0)
		var kind: String = "calm" if a_delta < 0 else ("angry" if a_delta > 0 else "")
		if bool(res.get("yielded", false)):
			outcome = "yield"
			kind = "smug"
		elif _anger >= 100.0:
			outcome = "explode"
			kind = "explode"
		elif _resolve >= 100.0:
			outcome = "resolved"
			kind = "happy"
		elif _mental <= 0.0:
			outcome = "breakdown"
		if kind == "calm":
			main.sfx.play("good", 1.2)
		elif kind == "angry":
			main.sfx.play("bad")
		var line: String = str(res.get("customer_reply", "……"))
		_history.append({"role": "customer", "text": line})
		await _customer_line(speaker, line, kind)
		if my_run != _run:
			return

	# ---- 結果
	var points: int = 0
	var mood: String = "happy"
	if outcome == "breakdown":
		points = SCORE_BREAKDOWN
		mood = "smug"
		hud.show_banner(tr("心が折れた…") + "  %d" % points, Color("#ff8a6a"))
		hud.set_comment(tr("今日はもう休もう。店長が代わってくれた。"))
		main.sfx.play("lose")
	elif outcome == "resolved":
		points = SCORE_RESOLVED + int((100.0 - _anger) * 6.0) + maxi(0, 300 - _turns * 50)
		hud.show_banner(tr("納得して帰った！") + "  +%d" % points, UI.LCD_ON)
		main.sfx.play("win")
	elif outcome == "yield":
		points = SCORE_YIELDED
		mood = "smug"
		hud.show_banner(tr("要求に屈した…") + "  %d" % points, UI.POP)
		hud.set_comment(tr("あれを認めたら、次はもっと要求されるぞ。"))
		main.sfx.play("lose")
	else:
		points = SCORE_EXPLODED
		mood = "angry"
		hud.show_banner(tr("ブチギレ！") + "  %d" % points, Color("#ff8a6a"))
		main.sfx.play("explode")
		main.shake(0.25)
	# 店員のメンタル（要件#38）
	match outcome:
		"resolved":
			_change_mental(8.0)
		"yield":
			_change_mental(-10.0)
		"explode":
			_change_mental(-15.0)
	# 行動ボタンの店の負担
	if _cost > 0:
		points -= _cost
		hud.set_comment(tr("行動の負担: -%d 点") % _cost)
	_total += points
	_results.append({"title": str(_cust.get("title", "")), "outcome": outcome, "points": points, "turns": _turns})
	hud.set_actions([])
	_update_top()
	hud.set_status("")
	await _wait(1.4)
	if my_run != _run:
		return
	hud.hide_bubble()
	await main.dismiss_customer(mood)
	if my_run != _run:
		return
	main.display_anger = 0.0
	await _wait(0.5)


func _customer_line(speaker: String, text: String, kind: String) -> void:
	if kind != "":
		main.customer_react(kind)
	await main.customer_say(speaker, text, kind == "angry" or kind == "explode" or _anger >= 70.0)
	await _wait(0.25)


## 行動ボタンの判定。点数は表どおり（サーバーでも同じ表）。サーバーのお客さんはサーバーに送る
func _judge_action(id: String) -> Dictionary:
	if _source == "server":
		var res: Dictionary = await main.api.request("POST", "/api/v1/solo/turn", {"session_id": _session_id, "action": id, "anger": _anger, "resolve": _resolve})
		if bool(res.get("ok", false)):
			return res["body"]
	await _wait(0.5)
	return ShopActions.judge(_cust, id, _anger, _resolve)


## 採点。サーバー／自分のキーで失敗したら、そのターンだけキーワード判定にする
func _judge(reply: String) -> Dictionary:
	if _source == "server":
		var res: Dictionary = await main.api.request("POST", "/api/v1/solo/turn", {"session_id": _session_id, "reply": reply, "anger": _anger, "resolve": _resolve})
		if bool(res.get("ok", false)):
			var body: Dictionary = res["body"]
			var notice: String = str(body.get("notice", ""))
			if notice != "":
				body["comment"] = "%s\n（%s）" % [str(body.get("comment", "")), notice]
			return body
		var fb: Dictionary = Judge.judge(_cust, reply, _used, _anger, _resolve)
		fb["comment"] = tr("（サーバーにつながらないので簡易判定）") + str(fb.get("comment", ""))
		return fb
	if _source == "own_key":
		var res2: Dictionary = await main.llm.judge_turn(_stage_id, _cust, _history, _anger, _resolve)
		if not res2.has("error"):
			return res2
		var fb2: Dictionary = Judge.judge(_cust, reply, _used, _anger, _resolve)
		fb2["comment"] = tr("（AI接続エラーのため簡易判定）") + str(fb2.get("comment", ""))
		return fb2
	await _wait(0.6)
	return Judge.judge(_cust, reply, _used, _anger, _resolve)


## 自動テスト（--smoke）用: お客さんごとに違う展開になるよう自動で返事する
func _smoke_autoplay(my_run: int) -> void:
	await _wait(0.5)
	if my_run != _run or not _player_turn:
		return
	# サーバーのお客さんは採点用の語を持たないので、同じ呼び名の台本から借りる
	var keys: Dictionary = _cust
	for c in Scenarios.customers(_stage_id):
		if str((c as Dictionary).get("title", "")) == str(_cust.get("title", "")):
			keys = c
	var text: String = ""
	var en: bool = GameSettings.language == "en"
	# 台の調整（クレーンの客のとき、最初のターン）と、店の行動ボタン（3人目の最初のターン）も自動で試す
	if bool(_cust.get("crane", false)) and not _crane_used and _turns == 0:
		_on_action(ShopActions.CRANE_ADJUST)
		return
	if _index % 4 == 2 and _turns == 0:
		var btns: Array = ShopActions.buttons(_stage_id, _cust, false)
		if not btns.is_empty():
			_on_action(str(btns[0][0]))
			return
	match _index % 4:
		0:
			var words: Array = keys.get("solution_keywords", [])
			var w: String = str(words[_turns % words.size()]) if not words.is_empty() else "check"
			if en:
				text = "I'm so sorry, I understand. Please let me %s for you right away, sir. (%d)" % [w, _turns]
			else:
				text = "申し訳ございません。お気持ちお察しいたします。すぐに%sの対応をいたします。（%d）" % [w, _turns]
		1:
			text = "Shut up and go away" if en else "うるさい、帰れ"
		2:
			return   # 何もしない → 時間切れでブチギレ
		_:
			var ys: Array = keys.get("yield_keywords", [])
			var y: String = str(ys[0]) if not ys.is_empty() else ("for free" if en else "無料")
			text = ("Okay sir, please take %s." % y) if en else ("分かりました、%sです。" % y)
	_on_reply(text)
