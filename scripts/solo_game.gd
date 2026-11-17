extends Node
## 1人用モードの進行。1シフト = お客さん CUSTOMERS_PER_SHIFT 人。
## 画面・3Dの操作は main（main.gd）と hud（hud.gd）に依頼し、ここはルールだけを持つ。

const Scenarios = preload("res://scripts/scenarios.gd")
const Judge = preload("res://scripts/offline_judge.gd")
const UI = preload("res://scripts/ui_kit.gd")

signal finished(stage_id: String, results: Array, total: int)
signal _reply(text: String)

const CUSTOMERS_PER_SHIFT: int = 4
const BASE_ANGER_RATE: float = 1.25     # 返事を考えている間、1秒あたりに上がる怒り
const RATE_STEP: float = 0.15           # お客さん1人ごとの上昇率
const SCORE_RESOLVED: int = 1000
const SCORE_EXPLODED: int = -300
const SCORE_YIELDED: int = -600

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
var _cust_is_llm: bool = false
var _anger: float = 0.0
var _resolve: float = 0.0
var _rate: float = 1.0
var _turns: int = 0
var _history: Array = []
var _used: Array = []
var _player_turn: bool = false


func setup(main_node: Node, hud_node: Control) -> void:
	main = main_node
	hud = hud_node
	hud.reply_submitted.connect(_on_reply)


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
	_pool = Scenarios.customers(stage_id).duplicate()
	_pool.shuffle()
	for i in range(CUSTOMERS_PER_SHIFT):
		_index = i
		await _play_customer(my_run)
		if my_run != _run:
			return
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


func _on_reply(text: String) -> void:
	if _active and _player_turn:
		_player_turn = false
		_reply.emit(text)


func _refresh(show_countdown: bool) -> void:
	var left: float = -1.0
	if show_countdown and _rate > 0.0:
		left = (100.0 - _anger) / _rate
	hud.set_gauges(_anger, _resolve, left)
	main.display_anger = _anger


func _update_top() -> void:
	hud.set_top(_stage_name, "お客さん %d / %d 人目" % [_index + 1, CUSTOMERS_PER_SHIFT], "スコア %d" % _total)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _next_offline() -> Dictionary:
	if _pool.is_empty():
		_pool = Scenarios.customers(_stage_id).duplicate()
		_pool.shuffle()
	return (_pool.pop_back() as Dictionary).duplicate(true)


func _play_customer(my_run: int) -> void:
	_player_turn = false
	hud.clear_round()
	_update_top()
	hud.set_comment("落ち着いて、まずは話を聞こう。")

	# ---- お客さんを用意する（AI生成 → 失敗したら台本）
	var data: Dictionary = {}
	_cust_is_llm = false
	if GameSettings.llm_ready() and not main.smoke:
		hud.set_status("AIが次のお客さんを考えています…")
		data = await main.llm.generate_customer(_stage_id, _titles)
		if my_run != _run:
			return
		if data.has("error"):
			hud.set_comment("AI接続エラー: %s\n→ 台本のお客さんで続けます。" % str(data["error"]))
			data = {}
		else:
			_cust_is_llm = true
	if data.is_empty():
		data = _next_offline()
	_cust = data
	_titles.append(str(_cust.get("title", "")))
	_anger = float(_cust.get("start_anger", 40))
	_resolve = 0.0
	_turns = 0
	_history = []
	_used = []
	_rate = BASE_ANGER_RATE * float(_cust.get("patience", 1.0)) * (1.0 + RATE_STEP * float(_index))
	_refresh(false)

	# ---- 来店
	hud.set_status("お客さんが来店…")
	main.sfx.play("door")
	var look: Dictionary = {}
	if typeof(_cust.get("look", null)) == TYPE_DICTIONARY:
		look = _cust["look"]
	await main.spawn_customer(look)
	if my_run != _run:
		return
	var speaker: String = "%s（%s）" % [str(_cust.get("title", "お客さん")), str(_cust.get("name", ""))]
	hud.set_memo(str(_cust.get("title", "")), str(_cust.get("memo", "")), str(_cust.get("demand", "")))
	var opening: String = str(_cust.get("opening", "おい！ちょっと！"))
	_history.append({"role": "customer", "text": opening})
	await main.customer_say(speaker, opening)
	if my_run != _run:
		return

	# ---- 会話ループ
	var outcome: String = ""
	while outcome == "":
		_player_turn = true
		hud.set_status("お客さんがキレる前に返事を入力しよう（Enterで送信）")
		hud.set_input_enabled(true, "ここに返事を入力…")
		if main.smoke:
			_smoke_autoplay(my_run)
		var reply: String = await _reply
		if my_run != _run:
			return
		_player_turn = false
		hud.set_input_enabled(false, "")
		if reply == "":
			# 時間切れ
			outcome = "explode"
			_anger = 100.0
			_refresh(false)
			await _customer_line(speaker, Judge.line(_cust, "explode"), "explode")
			if my_run != _run:
				return
			break

		_turns += 1
		hud.show_echo("あなた: ", reply)
		_history.append({"role": "staff", "text": reply})
		hud.set_status("お客さんの反応を待っています…")
		_refresh(false)
		var res: Dictionary = await _judge(reply)
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
	if outcome == "resolved":
		points = SCORE_RESOLVED + int((100.0 - _anger) * 6.0) + maxi(0, 300 - _turns * 50)
		hud.show_banner("納得して帰った！  +%d" % points, UI.C_GREEN.lightened(0.35))
		main.sfx.play("win")
	elif outcome == "yield":
		points = SCORE_YIELDED
		mood = "smug"
		hud.show_banner("不当な要求に屈した…  %d" % points, UI.C_PURPLE.lightened(0.35))
		hud.set_comment("あれを認めたら、次はもっと要求されるぞ。")
		main.sfx.play("lose")
	else:
		points = SCORE_EXPLODED
		mood = "angry"
		hud.show_banner("ブチギレ！  %d" % points, UI.C_RED.lightened(0.3))
		main.sfx.play("explode")
		main.shake(0.25)
	_total += points
	_results.append({"title": str(_cust.get("title", "")), "outcome": outcome, "points": points, "turns": _turns})
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
	await main.customer_say(speaker, text)
	await _wait(0.25)


## 採点。AIのお客さんはAIで、失敗時と台本のお客さんはキーワード判定で採点する。
func _judge(reply: String) -> Dictionary:
	if _cust_is_llm:
		var res: Dictionary = await main.llm.judge_turn(_stage_id, _cust, _history, _anger, _resolve)
		if not res.has("error"):
			return res
		var fallback: Dictionary = Judge.judge(_cust, reply, _used, _anger, _resolve)
		fallback["comment"] = "（AI接続エラーのため簡易判定）" + str(fallback.get("comment", ""))
		return fallback
	await _wait(0.6)
	return Judge.judge(_cust, reply, _used, _anger, _resolve)


## 自動テスト（--smoke）用: 人によって違う展開になるよう自動で返事する
func _smoke_autoplay(my_run: int) -> void:
	await _wait(0.5)
	if my_run != _run or not _player_turn:
		return
	var text: String = ""
	var mode: int = _index % 4
	if mode == 0:
		var words: Array = _cust.get("solution_keywords", [])
		var w: String = str(words[_turns % words.size()]) if not words.is_empty() else "確認"
		text = "申し訳ございません。お気持ちお察しいたします。すぐに%sの対応をいたします。（%d）" % [w, _turns]
	elif mode == 1:
		text = "うるさい、帰れ"
	elif mode == 2:
		return   # 何もしない → 時間切れでブチギレ
	else:
		var ys: Array = _cust.get("yield_keywords", [])
		text = "分かりました、%sです。" % (str(ys[0]) if not ys.is_empty() else "無料")
	_on_reply(text)
