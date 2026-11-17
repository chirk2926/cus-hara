extends Node
## 対戦モード（客役 vs 店員役）。1試合 = 2ラウンドで役を交代する。
##
## 進行はホスト（peer id 1）がすべて決める。ゲストは入力を送り、ホストから届く結果を表示するだけ。
##  - ホスト → 全員: @rpc("authority", "call_local") の show_* 関数
##  - 入力 → ホスト: submit_text()
## このノードは両者で同じパス（/root/Main/Versus）に置くこと。
##
## 採点: 店員の返答は、ホストにAPIキーがあればAI、なければキーワード判定。
##       客役のセリフは常にキーワード判定（offline_judge.gd の judge_customer_line）。

const Scenarios = preload("res://scripts/scenarios.gd")
const Judge = preload("res://scripts/offline_judge.gd")
const UI = preload("res://scripts/ui_kit.gd")

signal finished(summary: Dictionary)
signal _submitted(peer: int, text: String)

const ROUNDS: int = 2
const BASE_ANGER_RATE: float = 1.1      # 店員が考えている間の怒り上昇（毎秒）
const OPENING_TIME: float = 35.0        # 客役が最初のクレームを書く時間
const CUSTOMER_TIME: float = 25.0       # 客役が言い返す時間
const MAX_EXCHANGES: int = 8            # これだけ往復しても決着しなければ判定
const STAGES: Array = ["konbini", "arcade"]
const STAGE_NAMES: Dictionary = {"konbini": "コンビニ「ハッピーマート」", "arcade": "ゲームセンター「ゲームパラダイス」"}
const CUSTOMER_PHRASES: Array = [
	"責任者を出せ！",
	"誠意を見せろ！",
	"こっちは客だぞ！",
	"それで済むと思ってるのか！",
	"納得できない！",
]

var main = null
var hud = null
var net = null
var paused: bool = false   # 対戦中は止まらない（main との互換のために持つ）

var _run: int = 0
var _active: bool = false
var _in_match: bool = false
var _my_name: String = "プレイヤー"
var _names: Dictionary = {}       # peer id -> 名前
var _ratings: Dictionary = {}     # peer id -> レーティング
var _stage_id: String = "konbini"
var _round: int = 0
var _my_role: String = ""         # "staff" | "customer"
var _card: Dictionary = {}
var _anger: float = 0.0
var _resolve: float = 0.0
var _rate: float = 1.0
var _phase: String = ""           # "customer_turn" | "staff_turn" | "judging" | ""
var _turn_peer: int = 0
var _turn_left: float = 0.0
var _score_text: String = ""
# ホストだけが使う
var _expect_peer: int = 0
var _sync_timer: float = 0.0


func setup(main_node, hud_node, net_node) -> void:
	main = main_node
	hud = hud_node
	net = net_node
	hud.reply_submitted.connect(_on_local_reply)


func is_active() -> bool:
	return _active


func my_id() -> int:
	return multiplayer.get_unique_id()


func abort() -> void:
	_run += 1
	_active = false
	_in_match = false
	_phase = ""


## 接続が確立したら両者が呼ぶ。名前とレーティングを交換し、ホストが試合を始める。
func begin(player_name: String) -> void:
	_run += 1
	_active = true
	_in_match = false
	_my_name = player_name if player_name != "" else "プレイヤー"
	_names = {my_id(): _my_name}
	_ratings = {my_id(): GameSettings.rating}
	_phase = ""
	hello.rpc(_my_name, GameSettings.rating)


@rpc("any_peer", "call_remote", "reliable")
func hello(player_name: String, rating: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	_names[sender] = player_name.left(16)
	_ratings[sender] = clampi(rating, 0, 9999)
	if multiplayer.is_server() and _active and not _in_match:
		_in_match = true
		_host_match(_run, sender)


# ================================================================ ホスト側の進行

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _line_time(text: String) -> float:
	return clampf(float(text.length()) * 0.045, 0.5, 3.6) + 0.6


func _host_match(my_run: int, guest: int) -> void:
	var host: int = 1
	var stage: String = str(STAGES[randi() % STAGES.size()])
	var pool: Array = Scenarios.customers(stage).duplicate()
	pool.shuffle()
	show_match_start.rpc({"stage": stage, "names": _names, "ratings": _ratings})
	await _wait(2.5)
	if my_run != _run:
		return
	var first_staff: int = host if randi() % 2 == 0 else guest
	var totals: Dictionary = {host: 0, guest: 0}
	for r in range(ROUNDS):
		var staff: int = first_staff
		if r % 2 == 1:
			staff = guest if first_staff == host else host
		var customer: int = guest if staff == host else host
		var card: Dictionary = (pool[r % pool.size()] as Dictionary).duplicate(true)
		var res: Dictionary = await _host_round(my_run, r, staff, customer, card, totals)
		if my_run != _run:
			return
		totals[int(res["winner_peer"])] = int(totals[int(res["winner_peer"])]) + int(res["points"])
	var winner: int = 0
	if int(totals[host]) > int(totals[guest]):
		winner = host
	elif int(totals[guest]) > int(totals[host]):
		winner = guest
	show_match_end.rpc({"totals": totals, "winner": winner, "ratings": _ratings, "names": _names})


func _host_round(my_run: int, r: int, staff: int, customer: int, card: Dictionary, totals: Dictionary) -> Dictionary:
	_anger = float(card.get("start_anger", 40))
	_resolve = 0.0
	_rate = BASE_ANGER_RATE * float(card.get("patience", 1.0))
	var public_card: Dictionary = {
		"title": card.get("title", ""), "name": card.get("name", ""), "look": card.get("look", {}),
		"memo": card.get("memo", ""), "opening": card.get("opening", ""), "demand": card.get("demand", ""),
	}
	show_round_start.rpc({"round": r, "staff": staff, "customer": customer, "card": public_card,
		"anger": _anger, "rate": _rate, "totals": totals})
	await _wait(5.0)
	if my_run != _run:
		return {}

	var history: Array = []
	var used_staff: Array = []
	var used_customer: Array = []
	var exchanges: int = 0
	var outcome: String = ""

	# 客役が最初のクレームを書く（時間切れ・空ならカードの文面を使う。ペナルティなし）
	var opening: String = await _host_collect(my_run, customer, "customer_turn", OPENING_TIME)
	if my_run != _run:
		return {}
	if opening == "":
		opening = str(card.get("opening", "おい！ちょっと！"))
	used_customer.append(opening)
	history.append({"role": "customer", "text": opening})
	show_line.rpc("customer", opening)
	await _wait(_line_time(opening))
	if my_run != _run:
		return {}

	while outcome == "":
		# ---- 店員の番（この間だけ怒りが上がる。100になったら時間切れ）
		var reply: String = await _host_collect(my_run, staff, "staff_turn", 0.0)
		if my_run != _run:
			return {}
		if reply == "":
			_anger = 100.0
			outcome = "explode"
			show_judged.rpc({"anger": _anger, "resolve": _resolve, "anger_delta": 0, "resolve_delta": 0,
				"comment": "時間切れ！お客さんがキレた。", "by": "staff"})
			break
		history.append({"role": "staff", "text": reply})
		show_line.rpc("staff", reply)
		show_phase.rpc("judging", 0, 0.0)
		var res: Dictionary = await _judge_staff(card, reply, used_staff, history)
		if my_run != _run:
			return {}
		used_staff.append(reply)
		_anger = clampf(_anger + float(int(res.get("anger_delta", 0))), 0.0, 100.0)
		_resolve = clampf(_resolve + float(int(res.get("resolve_delta", 0))), 0.0, 100.0)
		show_judged.rpc({"anger": _anger, "resolve": _resolve, "anger_delta": int(res.get("anger_delta", 0)),
			"resolve_delta": int(res.get("resolve_delta", 0)), "comment": str(res.get("comment", "")), "by": "staff"})
		if bool(res.get("yielded", false)):
			outcome = "yield"
		elif _anger >= 100.0:
			outcome = "explode"
		elif _resolve >= 100.0:
			outcome = "resolved"
		if outcome != "":
			break
		exchanges += 1
		if exchanges >= MAX_EXCHANGES:
			outcome = "resolved" if _resolve > _anger else "explode"
			break
		await _wait(1.6)
		if my_run != _run:
			return {}

		# ---- 客役の番（言い返す）
		var line: String = await _host_collect(my_run, customer, "customer_turn", CUSTOMER_TIME)
		if my_run != _run:
			return {}
		var cres: Dictionary = Judge.judge_customer_line(card, line, used_customer)
		if line != "":
			used_customer.append(line)
		var shown: String = line if line != "" else "……（言葉に詰まっている）"
		history.append({"role": "customer", "text": shown})
		_anger = clampf(_anger + float(int(cres["anger_delta"])), 0.0, 100.0)
		_resolve = clampf(_resolve + float(int(cres["resolve_delta"])), 0.0, 100.0)
		show_line.rpc("customer", shown)
		show_judged.rpc({"anger": _anger, "resolve": _resolve, "anger_delta": int(cres["anger_delta"]),
			"resolve_delta": int(cres["resolve_delta"]), "comment": str(cres["comment"]), "by": "customer"})
		if _resolve >= 100.0:
			outcome = "resolved"
		elif _anger >= 100.0:
			outcome = "explode"
		await _wait(_line_time(shown))
		if my_run != _run:
			return {}

	var winner_peer: int = staff if outcome == "resolved" else customer
	var points: int = 100 + int(100.0 - _anger) if outcome == "resolved" else 100 + int(100.0 - _resolve)
	show_round_end.rpc({"outcome": outcome, "winner_peer": winner_peer, "points": points, "staff": staff, "customer": customer})
	await _wait(5.5)
	return {"winner_peer": winner_peer, "points": points}


## 指定した相手の入力を待つ。deadline が 0 より大きければ時間切れで空文字を返す。
## 店員の番（deadline = 0）は、_process が怒りを上げて 100 で時間切れにする。
func _host_collect(my_run: int, peer: int, phase: String, deadline: float) -> String:
	_expect_peer = peer
	_sync_timer = 0.0
	show_phase.rpc(phase, peer, deadline)
	while true:
		var got: Array = await _submitted
		if my_run != _run:
			return ""
		if int(got[0]) == peer:
			_expect_peer = 0
			return str(got[1])
	return ""


func _judge_staff(card: Dictionary, reply: String, used: Array, history: Array) -> Dictionary:
	if GameSettings.llm_ready() and not main.smoke:
		var res: Dictionary = await main.llm.judge_turn(_stage_id, card, history, _anger, _resolve)
		if not res.has("error"):
			return res
	await _wait(0.6)
	return Judge.judge(card, reply, used, _anger, _resolve)


## 入力の受け口。ゲストは rpc_id(1, ...) で、ホスト自身は直接呼ぶ。
@rpc("any_peer", "call_remote", "reliable")
func submit_text(text: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if sender != _expect_peer:
		return
	if _phase != "customer_turn" and _phase != "staff_turn":
		return
	_phase = ""
	_submitted.emit(sender, text.strip_edges().left(200))


func _process(delta: float) -> void:
	if not _active or _phase == "":
		return
	# 表示用のカウント（両者）
	if _phase == "staff_turn":
		_anger = minf(100.0, _anger + _rate * delta)
		_refresh(true)
	elif _phase == "customer_turn" and _turn_left > 0.0:
		_turn_left = maxf(0.0, _turn_left - delta)
		_update_status()
	# 時間切れの判定と同期はホストだけが行う
	if not multiplayer.is_server() or _expect_peer == 0:
		return
	if _phase == "staff_turn":
		_sync_timer -= delta
		if _sync_timer <= 0.0:
			_sync_timer = 0.5
			sync_gauges.rpc(_anger, _resolve)
		if _anger >= 100.0:
			var p: int = _expect_peer
			_phase = ""
			_submitted.emit(p, "")
	elif _phase == "customer_turn" and _turn_left <= 0.0:
		var p2: int = _expect_peer
		_phase = ""
		_submitted.emit(p2, "")


# ================================================================ 表示（両者で実行）

func _refresh(countdown: bool) -> void:
	var left: float = -1.0
	if countdown and _rate > 0.0:
		left = (100.0 - _anger) / _rate
	hud.set_gauges(_anger, _resolve, left)
	main.display_anger = _anger


func _update_top() -> void:
	var role: String = "あなたは店員役" if _my_role == "staff" else "あなたは客役"
	hud.set_top(str(STAGE_NAMES.get(_stage_id, "")), "ラウンド %d / %d ― %s" % [_round + 1, ROUNDS, role], _score_text)


func _update_status() -> void:
	var mine: bool = _turn_peer == my_id()
	if _phase == "customer_turn":
		if mine:
			hud.set_status("あなたの番（客役）: 店員を追い詰めるセリフを入力　あと %d 秒" % int(ceil(_turn_left)))
		else:
			hud.set_status("お客さん（相手）がセリフを考えています…　あと %d 秒" % int(ceil(_turn_left)))
	elif _phase == "staff_turn":
		if mine:
			hud.set_status("あなたの番（店員役）: お客さんがキレる前に返事を入力（Enterで送信）")
		else:
			hud.set_status("店員（相手）が返事を考えています… 怒りゲージが上がっていきます")
	elif _phase == "judging":
		hud.set_status("店長が判定しています…")


@rpc("authority", "call_local", "reliable")
func show_match_start(info: Dictionary) -> void:
	_in_match = true
	_stage_id = str(info.get("stage", "konbini"))
	var names: Dictionary = info.get("names", {})
	var ratings: Dictionary = info.get("ratings", {})
	for k in names:
		_names[int(k)] = str(names[k])
	for k in ratings:
		_ratings[int(k)] = int(ratings[k])
	_score_text = ""
	main.enter_versus(_stage_id)
	hud.clear_round()
	hud.set_top(str(STAGE_NAMES.get(_stage_id, "")), "対戦開始！", "")
	hud.set_status("対戦相手: %s（レーティング %d）" % [_opponent_name(), _opponent_rating()])
	hud.show_banner("対戦開始！", UI.C_ACCENT)
	main.sfx.play("door")


func _opponent_id() -> int:
	for k in _names:
		if int(k) != my_id():
			return int(k)
	return 0


func _opponent_name() -> String:
	return str(_names.get(_opponent_id(), "相手"))


func _opponent_rating() -> int:
	return int(_ratings.get(_opponent_id(), GameSettings.RATING_START))


@rpc("authority", "call_local", "reliable")
func show_round_start(info: Dictionary) -> void:
	_round = int(info.get("round", 0))
	_my_role = "staff" if int(info.get("staff", 0)) == my_id() else "customer"
	_card = info.get("card", {})
	_anger = float(info.get("anger", 40.0))
	_resolve = 0.0
	_rate = float(info.get("rate", 1.0))
	_phase = ""
	var totals: Dictionary = info.get("totals", {})
	var mine: int = 0
	var theirs: int = 0
	for k in totals:
		if int(k) == my_id():
			mine = int(totals[k])
		else:
			theirs = int(totals[k])
	_score_text = "あなた %d ― 相手 %d" % [mine, theirs]
	hud.clear_round()
	_update_top()
	if _my_role == "staff":
		hud.set_quick_phrases(hud.DEFAULT_PHRASES)
		hud.set_memo(str(_card.get("title", "")), str(_card.get("memo", "")), str(_card.get("demand", "")))
		hud.set_comment("あなたは店員役。怒りを100にせず、納得を100にすれば勝ち。")
		hud.show_banner("あなたは店員役", UI.C_BLUE.lightened(0.4))
	else:
		hud.set_quick_phrases(CUSTOMER_PHRASES)
		hud.set_memo("あなたの役: " + str(_card.get("title", "")), str(_card.get("memo", "")), str(_card.get("demand", "")))
		hud.set_comment("あなたは客役。怒りが100になるか、店員が不当な要求を飲めば勝ち。暴言・無言・繰り返しは逆効果。")
		hud.show_banner("あなたは客役", UI.C_RED.lightened(0.3))
	_refresh(false)
	main.sfx.play("door")
	var look: Dictionary = {}
	if typeof(_card.get("look", null)) == TYPE_DICTIONARY:
		look = _card["look"]
	main.spawn_customer(look)


@rpc("authority", "call_local", "reliable")
func show_phase(phase: String, peer: int, deadline: float) -> void:
	_phase = phase
	_turn_peer = peer
	_turn_left = deadline
	var mine: bool = peer == my_id()
	if phase == "customer_turn" and mine:
		hud.set_input_enabled(true, "クレームのセリフを入力…（空のままだとカードのセリフになります）" if deadline > CUSTOMER_TIME else "言い返すセリフを入力…")
	elif phase == "staff_turn" and mine:
		hud.set_input_enabled(true, "ここに返事を入力…")
	else:
		hud.set_input_enabled(false, "")
	_update_status()
	_refresh(phase == "staff_turn")
	if main.smoke and mine and phase != "judging":
		_smoke_autoplay(_run, phase)


@rpc("authority", "call_remote", "unreliable_ordered")
func sync_gauges(anger: float, resolve: float) -> void:
	_anger = anger
	_resolve = resolve


@rpc("authority", "call_local", "reliable")
func show_line(role: String, text: String) -> void:
	if _phase == "customer_turn":
		_phase = ""
		hud.set_status("")
	if role == "customer":
		main.customer_say("%s（%s）" % [str(_card.get("title", "お客さん")), "あなた" if _my_role == "customer" else _opponent_name()], text)
	else:
		hud.show_echo("店員（%s）: " % ("あなた" if _my_role == "staff" else _opponent_name()), text)


@rpc("authority", "call_local", "reliable")
func show_judged(info: Dictionary) -> void:
	_anger = float(info.get("anger", _anger))
	_resolve = float(info.get("resolve", _resolve))
	_phase = ""
	_refresh(false)
	var a: int = int(info.get("anger_delta", 0))
	var r: int = int(info.get("resolve_delta", 0))
	hud.show_delta(a, r)
	hud.set_comment(str(info.get("comment", "")))
	if a < 0:
		main.customer_react("calm")
		main.sfx.play("good", 1.2)
	elif a > 0:
		main.customer_react("angry")
		main.sfx.play("bad")


@rpc("authority", "call_local", "reliable")
func show_round_end(info: Dictionary) -> void:
	_phase = ""
	hud.set_input_enabled(false, "")
	hud.set_status("")
	var outcome: String = str(info.get("outcome", ""))
	var won: bool = int(info.get("winner_peer", 0)) == my_id()
	var pts: int = int(info.get("points", 0))
	var what: String = "お客さんは納得して帰った"
	var mood: String = "happy"
	if outcome == "explode":
		what = "お客さんがブチギレた"
		mood = "angry"
		main.customer_react("explode")
		main.shake(0.25)
	elif outcome == "yield":
		what = "店員が不当な要求を飲んだ"
		mood = "smug"
		main.customer_react("smug")
	else:
		main.customer_react("happy")
	hud.show_banner("%s\n%s  +%d" % [what, "あなたの勝ち！" if won else "相手の勝ち…", pts],
		UI.C_GREEN.lightened(0.35) if won else UI.C_RED.lightened(0.3))
	main.sfx.play("win" if won else "lose")
	_leave_later(_run, mood)


func _leave_later(my_run: int, mood: String) -> void:
	await _wait(2.6)
	if my_run != _run:
		return
	hud.hide_bubble()
	main.dismiss_customer(mood)
	main.display_anger = 0.0


@rpc("authority", "call_local", "reliable")
func show_match_end(info: Dictionary) -> void:
	_active = false
	_in_match = false
	_phase = ""
	var totals: Dictionary = info.get("totals", {})
	var mine: int = 0
	var theirs: int = 0
	for k in totals:
		if int(k) == my_id():
			mine = int(totals[k])
		else:
			theirs = int(totals[k])
	var winner: int = int(info.get("winner", 0))
	var score: float = 0.5
	if winner == my_id():
		score = 1.0
	elif winner != 0:
		score = 0.0
	var before: int = GameSettings.rating
	var delta: int = GameSettings.record_versus(_opponent_rating(), score)
	finished.emit({"score": score, "mine": mine, "theirs": theirs, "opponent": _opponent_name(),
		"rating_before": before, "rating_delta": delta, "disconnected": false})


## 相手が切断したとき（main から呼ばれる）。試合が始まっていれば勝ち扱いにする。
func opponent_left() -> void:
	if not _active:
		return
	var was_in_match: bool = _in_match
	abort()
	if not was_in_match:
		return
	var before: int = GameSettings.rating
	var delta: int = GameSettings.record_versus(_opponent_rating(), 1.0)
	finished.emit({"score": 1.0, "mine": 0, "theirs": 0, "opponent": _opponent_name(),
		"rating_before": before, "rating_delta": delta, "disconnected": true})


# ================================================================ 入力

func _on_local_reply(text: String) -> void:
	if not _active or _turn_peer != my_id():
		return
	if _phase != "customer_turn" and _phase != "staff_turn":
		return
	if multiplayer.is_server():
		submit_text(text)
	else:
		_phase = "judging"
		submit_text.rpc_id(1, text)


## 自動テスト（--smoke-host / --smoke-join）用
func _smoke_autoplay(my_run: int, phase: String) -> void:
	await _wait(0.8)
	if my_run != _run or _phase != phase or _turn_peer != my_id():
		return
	var text: String = ""
	if phase == "staff_turn":
		var words: Array = Scenarios.customers(_stage_id)[0].get("solution_keywords", [])
		for c in Scenarios.customers(_stage_id):
			if str((c as Dictionary).get("title", "")) == str(_card.get("title", "")):
				words = (c as Dictionary).get("solution_keywords", [])
		if _round == 0:
			text = "申し訳ございません。お気持ちお察しいたします。%sと%sで対応いたします。（%d）" % [str(words[0]), str(words[1]), randi() % 1000]
		else:
			text = "うるさい"
	else:
		text = "責任者を出せ！こっちは客だぞ！どうしてくれるんだ！（%d）" % (randi() % 1000)
	hud.set_input_enabled(false, "")
	_on_local_reply(text)
