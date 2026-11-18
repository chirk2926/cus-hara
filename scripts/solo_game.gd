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
const AgeCheck = preload("res://scripts/age_check.gd")

signal finished(stage_id: String, results: Array, total: int)
signal _reply(text: String)

const CUSTOMERS_PER_SHIFT: int = 4
const BASE_ANGER_RATE: float = 0.8      # 返事を考えている間、1秒あたりに上がる怒り（要件#49で 1.25 から下げた）
const RATE_STEP: float = 0.08           # お客さん1人ごとの上昇率（要件#49で 0.15 から下げた）
const SCORE_RESOLVED: int = 1000
const SCORE_EXPLODED: int = -300
const SCORE_YIELDED: int = -600
const SCORE_BREAKDOWN: int = -500
## 行動ボタンの店の負担（点数から引く）。台の調整で規定外の強さにしたら CHEAT
const ACTION_COST: Dictionary = {"discount": 100, "dogeza": 0, "medal_return": 100, "credit": 50, "maintenance": 0, "crane_stuck": 0}
## 売上と店舗レビュー（要件#56）。売上は1人を接客するごとに入る（円）
const SALES_PER_CUSTOMER: Dictionary = {"konbini": 2500, "arcade": 2000}
const CRANE_SALES: float = 3000.0      # ゲームセンターのクレーンの売上（ペイアウト率 30% のとき、1人あたり）
const SALES_COST: Dictionary = {"discount": 300, "medal_return": 200, "credit": 300}   # 行動で減る売上（円）
const SALES_YIELD: int = 1000          # 要求に屈したとき減る売上（円）
const REVIEW_START: float = 3.0
const REVIEW_DELTA: Dictionary = {"resolved": 0.3, "explode": -0.4, "yield": -0.2, "breakdown": -0.3,
	"age_ok": 0.1, "age_refused": 0.1, "age_wrong": -0.2, "age_left": -0.1, "age_lax": 0.0}
## シフトの時刻（要件#61）。i 人目のお客さんが来る時刻（0:00 からの分）
const CLOCK: Dictionary = {"konbini": [1080, 1200, 1320, 1410], "arcade": [1050, 1155, 1260, 1350]}
## 年齢確認（要件#61）。18:00 以降のゲームセンターで、この確率で年齢の怪しいお客さんが来る（1シフト2人まで）
const AGE_CHANCE: float = 0.3
## コンビニのお酒・たばこの年齢確認（要件#63）。時間に関係なく、この確率
const AGE_CHANCE_KONBINI: float = 0.25
const AGE_MAX: int = 2
## 年齢確認の点数（減りは少なめ）
const SCORE_AGE: Dictionary = {"age_ok": 700, "age_refused": 600, "age_wrong": -150, "age_lax": -200, "age_left_ok": 300, "age_left_ng": -150}
## 入店できない客を遊ばせていたとき、警察が来る確率と営業停止の点数
const POLICE_CHANCE: float = 0.7
const SCORE_SUSPENDED: int = -2000
const REVIEW_SUSPENDED: float = -1.5
const CHEAT_COST: int = 150
## 店員のメンタル（要件#38）
const MENTAL_MAX: float = 100.0
const ACTION_PREFIX: String = "\u0001action:"
## たまに起きるイベント（要件#52）
## 要注意人物: 2人目以降のお客さんが、この確率でとびきり突飛な人になる（1シフト1回まで）。納得させると点数 ×1.5
const WILD_CHANCE: float = 0.18
const WILD_BONUS: float = 1.5
## 店長のアドバイス: 返事の番が来るとき、怒りが高い（または話が長引いている）と、この確率で店長が来る（1シフト1回まで）
const MANAGER_CHANCE: float = 0.4
const MANAGER_CALM: float = 10.0    # 店長の顔を見てお客さんが落ち着く分
const MANAGER_MENTAL: float = 10.0  # 店員のメンタルの回復

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
var _sales_cost: int = 0      # このお客さんでの行動で減った売上（円）
var _crane_used: bool = false
var _data_seen: bool = false
var _sales: int = 0              # このシフトの売上（円）
var _review: float = REVIEW_START # このシフトの店舗レビュー（★1〜5）
var _payout: int = 30            # このシフトのペイアウト率（ゲームセンター）
## シフトの終わりにまとめた売上・レビュー（main のレシートが読む）
var summary: Dictionary = {}
var _age_count: int = 0          # このシフトの年齢確認のお客さんの数
var _suspended: bool = false     # 営業停止になった
var _crane_wins: int = 0         # 台の調整で取れた回数（レビュー用）
var _id_seen: bool = false       # このお客さんの身分証を見た
var _wild: bool = false          # このお客さんは要注意人物
var _wild_used: bool = false     # このシフトで要注意人物が来たか
var _manager_used: bool = false  # このシフトで店長が来たか


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
	_wild_used = false
	_manager_used = false
	_sales = 0
	_review = REVIEW_START
	_age_count = 0
	_suspended = false
	_crane_wins = 0
	_payout = GameSettings.effective_payout()
	summary = {}
	_mental = MENTAL_MAX
	hud.set_mental(_mental)
	hud.set_voice_mode(false)
	hud.set_quick_phrases(hud.DEFAULT_PHRASES)
	for i in range(CUSTOMERS_PER_SHIFT):
		_index = i
		await _play_customer(my_run)
		if my_run != _run:
			return
		if _suspended:
			break
		if _mental <= 0.0:
			# 心が折れたので早退（要件#38）
			hud.show_banner(tr("心が折れた…早退します"), Color("#ff8a6a"))
			await _wait(2.0)
			if my_run != _run:
				return
			break
	_active = false
	_finish_summary()
	finished.emit(_stage_id, _results, _total)


## 売上と店舗レビューをまとめ、ボーナスを点数に足す（要件#56）
func _finish_summary() -> void:
	# ペイアウト率はゲームセンターだけ。高いほどレビューが少し上がりやすい
	if _stage_id == "arcade":
		_review += float(_payout - 30) * 0.01
	var review: float = clampf(snappedf(_review, 0.1), 1.0, 5.0)
	var baseline: int = SALES_PER_CUSTOMER.get(_stage_id, 2500) * CUSTOMERS_PER_SHIFT + (int(CRANE_SALES) * CUSTOMERS_PER_SHIFT if _stage_id == "arcade" else 0)
	var sales_bonus: int = int(float(_sales - baseline) / 20.0)
	var review_bonus: int = int((review - REVIEW_START) * 400.0)
	_total += sales_bonus + review_bonus
	summary = {"sales": _sales, "review": review, "sales_bonus": sales_bonus, "review_bonus": review_bonus,
		"payout": _payout if (_stage_id == "arcade" and GameSettings.crane_mode == "prob") else -1,
		"suspended": _suspended, "reviews": _make_reviews()}


## お客様の声（要件#62）: 高い評価と低い評価を1つずつ。どちらも当てはまらない・出ないこともある
func _make_reviews() -> Array:
	var count: Dictionary = {}
	for r in _results:
		var o: String = str((r as Dictionary).get("outcome", ""))
		count[o] = int(count.get(o, 0)) + 1
	var arcade: bool = _stage_id == "arcade"
	var prob: bool = arcade and GameSettings.crane_mode == "prob"
	var highs: Array = []
	var lows: Array = []
	if int(count.get("resolved", 0)) > 0:
		highs.append(tr("店員さんがちゃんと話を聞いてくれた。また来ます。"))
		highs.append(tr("言い方は丁寧なのに、できないことははっきり。気持ちのいい店。"))
	if int(count.get("resolved", 0)) >= 3:
		highs.append(tr("クレーム対応が神。この店員さん、何者？"))
	if _crane_wins > 0:
		highs.append(tr("店員さんが景品を取りやすくしてくれた！神対応！"))
	if prob and _payout >= 45:
		highs.append(tr("このゲーセン、ちゃんと取れる。良心的！"))
	if int(count.get("age_ok", 0)) + int(count.get("age_refused", 0)) > 0:
		highs.append(tr("夜でも年齢確認がしっかりしていて、安心して遊べる。") if arcade else tr("お酒の年齢確認がきちんとしていて、安心できるコンビニ。"))
	if not arcade and int(count.get("resolved", 0)) > 0:
		highs.append(tr("深夜でも感じのいいコンビニ。おでんもおいしい。"))
	if int(count.get("explode", 0)) > 0:
		lows.append(tr("店員の対応が最悪。二度と来ない。"))
		lows.append(tr("ちょっと文句を言っただけなのに、話にならなかった。"))
	if int(count.get("yield", 0)) > 0:
		lows.append(tr("ゴネた人だけ得してた。まじめに遊んでるのがバカらしい。"))
	if int(count.get("breakdown", 0)) > 0:
		lows.append(tr("店員さんが途中でいなくなった…大丈夫？"))
	if prob and _payout <= 20:
		lows.append(tr("クレーン、全然取れない。お金が溶けただけ。"))
	if int(count.get("age_wrong", 0)) > 0:
		lows.append(tr("ちゃんと免許証を見せたのに追い出された。") if arcade else tr("免許証を見せたのに、お酒を売ってもらえなかった。"))
	if _suspended:
		lows.append(tr("行ったら営業停止になってた。何があったの？"))
	var out: Array = []
	# どちらも、当てはまっても出ないことがある（2割）
	if not highs.is_empty() and randf() < 0.8:
		out.append({"stars": 5 if randf() < 0.6 else 4, "text": str(highs[randi() % highs.size()])})
	if not lows.is_empty() and (randf() < 0.8 or _suspended):
		out.append({"stars": 1 if randf() < 0.6 else 2, "text": str(lows[randi() % lows.size()])})
	return out


## 年齢確認の結果の点数・表示（要件#61。減りは少なめ）
func _age_result(outcome: String) -> Dictionary:
	var must: bool = bool((_cust.get("age", {}) as Dictionary).get("must_leave", true))
	var points: int = 0
	var mood: String = "happy"
	match outcome:
		"age_ok":
			points = SCORE_AGE["age_ok"]
			hud.show_banner(tr("年齢確認OK") + "  +%d" % points, UI.LCD_ON)
			hud.set_comment(tr("使える身分証で、年齢も足りていた。正しい判断だ。"))
			main.sfx.play("win")
		"age_refused":
			points = SCORE_AGE["age_refused"]
			mood = "angry"
			if _age_mode() == "konbini":
				hud.show_banner(tr("販売をお断りした") + "  +%d" % points, UI.LCD_ON)
				hud.set_comment(tr("20歳未満、または確かめられない客だった。売らなくて正解だ。"))
			else:
				hud.show_banner(tr("退店してもらった") + "  +%d" % points, UI.LCD_ON)
				hud.set_comment(tr("入店できない客だった。きちんと帰ってもらえたな。"))
			main.sfx.play("win")
		"age_wrong":
			points = SCORE_AGE["age_wrong"]
			mood = "angry"
			hud.show_banner(tr("大人だったのに…") + "  %d" % points, Color("#ff8a6a"))
			hud.set_comment(tr("顔写真つきの公的な身分証で、年齢も足りていた。帰す必要はなかった。") if _age_mode() != "konbini" else tr("顔写真つきの公的な身分証で、20歳以上だった。売ってよかった。"))
			_change_mental(-5.0)
			main.sfx.play("lose")
		"age_lax":
			points = SCORE_AGE["age_lax"]
			hud.show_banner(tr("年齢確認があまい…") + "  %d" % points, UI.POP)
			hud.set_comment(tr("その身分証では入店させられない。警察に見つかったら営業停止だぞ…") if _age_mode() != "konbini" else tr("20歳未満かもしれない客に売ってしまった。警察に見つかったら営業停止だぞ…"))
			main.sfx.play("lose")
		"age_left":
			points = SCORE_AGE["age_left_ok"] if must else SCORE_AGE["age_left_ng"]
			mood = "angry"
			hud.show_banner(tr("怒って帰った") + "  %+d" % points, Color("#ff8a6a"))
			hud.set_comment(tr("帰ってもらう客ではあったが、もっと落ち着いて伝えよう。") if must else tr("入れる客を怒らせて帰してしまった。"))
			main.sfx.play("bad")
	return {"points": points, "mood": mood}


## 警察が来て営業停止（要件#61）。入店できない客を遊ばせていたとき POLICE_CHANCE の確率で
func _police(my_run: int) -> void:
	await _wait(1.2)
	if my_run != _run:
		return
	hud.set_actions([])
	hud.show_banner(tr("警察です！"), Color("#5b7bd5"))
	main.sfx.play("warn", 0.7)
	await main.police_visit()
	if my_run != _run:
		return
	var police_line: String = tr("こちらの店で、入店できない時間に未成年を遊ばせていましたね。営業停止です。")
	if _age_mode() == "konbini":
		police_line = tr("こちらの店で、20歳未満にお酒・たばこを売っていましたね。営業停止です。")
	await main.customer_say(tr("警察官"), police_line, true)
	if my_run != _run:
		return
	main.shake(0.3)
	main.sfx.play("explode")
	hud.show_banner(tr("営業停止…") + "  %d" % SCORE_SUSPENDED, Color("#ff8a6a"))
	hud.set_comment(tr("年齢確認はきちんとやろう…。"))
	_suspended = true
	_total += SCORE_SUSPENDED
	_review += REVIEW_SUSPENDED
	_results.append({"title": tr("営業停止"), "outcome": "suspended", "points": SCORE_SUSPENDED, "turns": 0})
	_update_top()
	await _wait(2.6)
	if my_run != _run:
		return
	hud.hide_bubble()
	main.manager_leave()
	await main.dismiss_customer("smug")


## このお客さんの分の売上（接客した分だけ入る）
func _add_sales(outcome: String) -> void:
	_review += float(REVIEW_DELTA.get(outcome, 0.0))
	# 退店してもらった客の分の売上は入らない
	if outcome in ["age_refused", "age_wrong", "age_left"]:
		return
	var s: float = float(SALES_PER_CUSTOMER.get(_stage_id, 2500))
	if _stage_id == "arcade":
		# ペイアウト率が低いほどクレーンの売上が上がる（30% で 1 倍、10% で 1.29 倍、80% で 0.29 倍）
		s += CRANE_SALES * (1.0 - float(_payout) / 100.0) / 0.7
	s -= float(_sales_cost)
	if outcome == "yield":
		s -= float(SALES_YIELD)
	_sales += int(s)


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
	# 身分証を見せてもらう（番は終わらない。要件#61）
	if id == "id_check":
		if _active and not paused and main.mode == "solo" and _is_age_check():
			main.show_id_card(_cust)
			if not _id_seen:
				_id_seen = true
				_history.append({"role": "staff", "text": tr("（身分証を確認した）")})
		return
	# 筐体のデータは見るだけ（番は終わらない。要件#57）
	if id == ShopActions.MACHINE_DATA:
		if _active and not paused and main.mode == "solo":
			main.show_machine_data(_cust)
			if not _data_seen:
				_data_seen = true
				_history.append({"role": "staff", "text": tr("（筐体のデータを確認した）")})
		return
	if _active and _player_turn and not paused and main.mode == "solo":
		_player_turn = false
		_reply.emit(ACTION_PREFIX + id)


func _change_mental(delta: float) -> void:
	_mental = clampf(_mental + delta, 0.0, MENTAL_MAX)
	hud.set_mental(_mental)


func _on_reply(text: String) -> void:
	if _active and _player_turn and not paused and main.mode == "solo":
		_player_turn = false
		_reply.emit(text)


func _refresh(show_countdown: bool) -> void:
	var left: float = -1.0
	if show_countdown and _rate > 0.0:
		left = (100.0 - _anger) / _rate
	hud.set_gauges(_anger, _resolve, left)
	main.display_anger = _anger


func _update_top() -> void:
	hud.set_top(_stage_name, tr("お客さん %d / %d") % [_index + 1, CUSTOMERS_PER_SHIFT] + "  " + AgeCheck.clock_text(_clock()), tr("%d 点") % _total)


## 今のお客さんが来た時刻（0:00 からの分）
func _clock() -> int:
	var list: Array = CLOCK.get(_stage_id, CLOCK["konbini"])
	return int(list[clampi(_index, 0, list.size() - 1)])


func _is_age_check() -> bool:
	return str(_cust.get("kind", "")) == "age_check"


func _age_buttons() -> Array:
	if _age_mode() == "konbini":
		return [["id_check", ShopActions.label("id_check")], ["age_allow", ShopActions.label("sell_ok")], ["age_refuse", ShopActions.label("sell_refuse")]]
	return [["id_check", ShopActions.label("id_check")], ["age_allow", ShopActions.label("age_allow")], ["age_refuse", ShopActions.label("age_refuse")]]


## 年齢確認の種類: "arcade"（夜の入店）| "konbini"（お酒・たばこ。要件#63）
func _age_mode() -> String:
	return str((_cust.get("age", {}) as Dictionary).get("mode", "arcade"))


## 年齢確認の判断（要件#61）: 入店OK か 退店をお願いするか。正しいかは must_leave で決まる
func _age_outcome(allow: bool) -> String:
	var must: bool = bool((_cust.get("age", {}) as Dictionary).get("must_leave", true))
	if allow:
		return "age_lax" if must else "age_ok"
	return "age_refused" if must else "age_wrong"


## 要注意人物の見た目: 背が高く、派手な色、ヘッドホンかマスク
func _make_wild_look() -> void:
	var look: Dictionary = {}
	if typeof(_cust.get("look", null)) == TYPE_DICTIONARY:
		look = (_cust["look"] as Dictionary).duplicate()
	var loud: Array = ["#ff3fa4", "#38e05a", "#ffb000", "#7a3cff", "#00c2d4"]
	look["body_color"] = loud[randi() % loud.size()]
	look["hair_color"] = loud[randi() % loud.size()]
	look["hair"] = ["perm", "long", "cap"][randi() % 3]
	look["accessory"] = ["headphones", "glasses", "mask"][randi() % 3]
	look["height"] = 1.15
	_cust["look"] = look
	_cust["title"] = tr("【要注意】") + str(_cust.get("title", ""))


## 店長がアドバイスに来るイベント（要件#52）。来ている間は怒りが止まる（_player_turn が false のため）
func _maybe_manager_visit(my_run: int) -> void:
	if _manager_used or _turns < 1:
		return
	var tense: bool = _anger >= 60.0 or _turns >= 3
	if not tense and not main.smoke:
		return
	if not (randf() < MANAGER_CHANCE or main.smoke):
		return
	_manager_used = true
	hud.set_input_enabled(false, "")
	hud.set_status(tr("店長が来た！"))
	hud.show_banner(tr("店長が来た！"), UI.POP)
	main.sfx.play("door", 0.9)
	await main.manager_enter()
	if my_run != _run:
		return
	var advice: Dictionary = await _manager_advice()
	if my_run != _run:
		return
	var lines: PackedStringArray = PackedStringArray()
	var kw: String = str(advice.get("keyword", ""))
	var act: String = str(advice.get("action", ""))
	if kw != "":
		lines.append(tr("「%s」の方向で話してみろ。") % kw)
	if act != "":
		lines.append(tr("「%s」も効くかもしれない。") % ShopActions.label(act))
	if lines.is_empty():
		lines.append(tr("メモの規定を確かめて、できることを具体的に伝えろ。"))
	lines.append(tr("要求は飲むなよ。"))
	hud.set_comment(tr("店長: ") + " ".join(lines))
	main.manager_talk(3.0)
	_anger = maxf(0.0, _anger - MANAGER_CALM)
	_change_mental(MANAGER_MENTAL)
	hud.show_delta(-int(MANAGER_CALM), 0)
	main.customer_react("calm")
	main.sfx.play("good", 0.9)
	_refresh(false)
	await _wait(2.8)
	if my_run != _run:
		return
	main.manager_leave()


## 店長のアドバイスの中身: 正しい方向の言葉1つと、効く行動ボタン1つ
func _manager_advice() -> Dictionary:
	if _source == "server" and _session_id != "":
		var res: Dictionary = await main.api.request("POST", "/api/v1/solo/hint", {"session_id": _session_id})
		if bool(res.get("ok", false)):
			return res["body"]
		return {}
	var out: Dictionary = {"keyword": "", "action": ""}
	var words: Variant = _cust.get("solution_keywords", [])
	if typeof(words) == TYPE_ARRAY and not (words as Array).is_empty():
		out["keyword"] = str((words as Array)[randi() % (words as Array).size()])
	for b in ShopActions.buttons(_stage_id, _cust, false):
		var id: String = str((b as Array)[0])
		if ShopActions.effect_kind(_cust, id) == "good":
			out["action"] = id
			break
	return out


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _next_offline() -> Dictionary:
	if _wild:
		var rares: Array = Scenarios.customers(_stage_id).filter(func(c: Variant) -> bool:
			return bool((c as Dictionary).get("rare", false)) and not _titles.has(str((c as Dictionary).get("title", ""))))
		if not rares.is_empty():
			return Scenarios.materialize_spend((rares[randi() % rares.size()] as Dictionary).duplicate(true), _payout)
	if _pool.is_empty():
		_pool = Scenarios.customers(_stage_id).duplicate()
		_pool.shuffle()
	# 「取れない」クレームはペイアウト率で出やすさが変わる（要件#55）: 重みつきで1人選ぶ
	var weights: Array = []
	var sum: float = 0.0
	for c in _pool:
		var w: float = Scenarios.spend_weight(_payout) if (_stage_id == "arcade" and bool((c as Dictionary).get("spend", false))) else 1.0
		weights.append(w)
		sum += w
	var r: float = randf() * sum
	var idx: int = _pool.size() - 1
	for i in range(_pool.size()):
		r -= float(weights[i])
		if r <= 0.0:
			idx = i
			break
	var picked: Dictionary = (_pool[idx] as Dictionary).duplicate(true)
	_pool.remove_at(idx)
	return Scenarios.materialize_spend(picked, _payout)


## お客さんを用意する。戻り値: お客さんデータ（_source と _session_id も決まる）
func _prepare_customer() -> Dictionary:
	_session_id = ""
	var src: String = GameSettings.solo_source
	if src == "server":
		hud.set_status(tr("お客さんが来ます…"))
		var req: Dictionary = {"stage": _stage_id, "avoid": _titles, "lang": GameSettings.language, "payout": _payout}
		if _wild:
			req["event"] = "wild"
		var res: Dictionary = await main.api.request("POST", "/api/v1/solo/start", req)
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
		# 「〇〇円使っても取れない」のお客さんにするか（ペイアウト率が低いほど多い。要件#55）
		var spend: bool = _stage_id == "arcade" and not _wild and randf() < minf(0.8, 0.3 * Scenarios.spend_weight(_payout))
		var data: Dictionary = await main.llm.generate_customer(_stage_id, _titles, _wild, spend)
		if not data.has("error"):
			_source = "own_key"
			return Scenarios.materialize_spend(data, _payout)
		hud.set_comment(tr("AI接続エラー: %s\n台本のお客さんで続けます。") % str(data["error"]))
	_source = "offline"
	return _next_offline()


func _play_customer(my_run: int) -> void:
	_player_turn = false
	hud.clear_round()
	_update_top()
	hud.set_comment(tr("落ち着いて、まずは話を聞こう。"))

	# 要注意人物のイベント（要件#52）。自動テストでは2人目で必ず起こす
	_wild = false
	if _index >= 1 and not _wild_used and (randf() < WILD_CHANCE or (main.smoke and _index == 1)):
		_wild = true
		_wild_used = true
	# 年齢確認のお客さん（要件#61）: 18:00 以降のゲームセンター。自動テストでは4人目で必ず
	var data: Dictionary = {}
	var age_ok_here: bool = (_stage_id == "arcade" and AgeCheck.limit_for(_clock()) > 0) or _stage_id == "konbini"
	var age_chance: float = AGE_CHANCE_KONBINI if _stage_id == "konbini" else AGE_CHANCE
	if age_ok_here and not _wild and _age_count < AGE_MAX and (randf() < age_chance or (main.smoke and _index == 3)):
		_age_count += 1
		_source = "offline"
		_session_id = ""
		data = AgeCheck.make(_clock(), GameSettings.language, _stage_id)
	else:
		data = await _prepare_customer()
	if my_run != _run:
		return
	_cust = data
	_id_seen = false
	_titles.append(str(_cust.get("title", "")))
	if _wild:
		_make_wild_look()
	_anger = float(_cust.get("start_anger", 40))
	_resolve = 0.0
	_turns = 0
	_history = []
	_used = []
	_rate = BASE_ANGER_RATE * float(_cust.get("patience", 1.0)) * (1.0 + RATE_STEP * float(_index)) * GameSettings.answer_rate()
	_cost = 0
	_sales_cost = 0
	_crane_used = false
	_data_seen = false
	_refresh(false)

	# ---- 来店
	hud.set_status(tr("いらっしゃいませ…"))
	main.sfx.play("door")
	var look: Dictionary = {}
	if typeof(_cust.get("look", null)) == TYPE_DICTIONARY:
		look = _cust["look"]
	if _wild:
		hud.show_banner(tr("！要注意人物が来店！"), UI.SHU)
		hud.set_comment(tr("要注意人物だ。何を言い出すか分からないぞ。納得させれば点数 ×1.5！"))
		main.sfx.play("warn", 0.8)
		main.shake(0.12)
	await main.spawn_customer(look)
	if my_run != _run:
		return
	if _is_age_check():
		hud.set_actions(_age_buttons())
		hud.show_banner(tr("年齢確認！"), UI.POP)
		if _age_mode() == "konbini":
			hud.set_comment(tr("お酒・たばこは20歳から。身分証で年齢を確かめよう。"))
		else:
			hud.set_comment(tr("今は %s。身分証で年齢を確かめよう。") % AgeCheck.clock_text(_clock()))
	else:
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
		await _maybe_manager_visit(my_run)
		if my_run != _run:
			return
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
			if id == "age_allow" or id == "age_refuse":
				main.close_machine_data()
				outcome = _age_outcome(id == "age_allow")
				var shown_id: String = id
				if _age_mode() == "konbini":
					shown_id = "sell_ok" if id == "age_allow" else "sell_refuse"
				hud.show_echo(tr("あなた: "), tr("（行動: %s）") % ShopActions.label(shown_id))
				var key: String = "yielded" if id == "age_allow" else "calm"
				await _customer_line(speaker, Judge.line(_cust, key), "happy" if id == "age_allow" else "angry")
				if my_run != _run:
					return
				break
			var crane_cheat: bool = false
			if ShopActions.is_minigame(id):
				hud.set_status(tr("台を調整しています…"))
				var cr: Dictionary = await main.run_crane_minigame({"mode": "adjust" if id == ShopActions.CRANE_ADJUST else "move", "customer": _cust})
				if my_run != _run:
					return
				# 確率設定・ペイアウト率を変えたら、ここからの売上・レビューに効かせる
				_payout = GameSettings.effective_payout()
				if str(cr.get("result", "cancelled")) == "cancelled":
					continue
				_crane_used = true
				hud.set_actions(ShopActions.buttons(_stage_id, _cust, false))
				id = "crane_won" if str(cr["result"]) == "won" else "crane_lost"
				if id == "crane_won":
					_crane_wins += 1
				crane_cheat = bool(cr.get("cheat", false))
				if crane_cheat:
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
			_sales_cost += int(SALES_COST.get(id, 0))
			if id == "dogeza":
				_change_mental(-20.0)
			if crane_cheat:
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
	# 怒らせた・屈したときのメンタルの減りで 0 になったら、その場で早退（SPEC 12.4）
	match outcome:
		"yield":
			_change_mental(-10.0)
		"explode":
			_change_mental(-15.0)
	if (outcome == "yield" or outcome == "explode") and _mental <= 0.0:
		outcome = "breakdown"
	# 年齢確認のお客さんは、会話で決着したときも「残った／帰った」に読みかえる
	if _is_age_check():
		var must: bool = bool((_cust.get("age", {}) as Dictionary).get("must_leave", true))
		match outcome:
			"explode", "breakdown":
				outcome = "age_left"
			"yield":
				outcome = "age_lax" if must else "age_ok"
			"resolved":
				outcome = "age_refused" if must else "age_wrong"
	var points: int = 0
	var mood: String = "happy"
	if outcome.begins_with("age_"):
		var res_age: Dictionary = _age_result(outcome)
		points = int(res_age["points"])
		mood = str(res_age["mood"])
	elif outcome == "breakdown":
		points = SCORE_BREAKDOWN
		mood = "smug"
		hud.show_banner(tr("心が折れた…") + "  %d" % points, Color("#ff8a6a"))
		hud.set_comment(tr("今日はもう休もう。店長が代わってくれた。"))
		main.sfx.play("lose")
	elif outcome == "resolved":
		points = SCORE_RESOLVED + int((100.0 - _anger) * 6.0) + maxi(0, 300 - _turns * 50)
		if _wild:
			points = int(float(points) * WILD_BONUS)
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
	if outcome == "resolved":
		_change_mental(8.0)
	# 行動ボタンの店の負担
	if _cost > 0:
		points -= _cost
		hud.set_comment(tr("行動の負担: -%d 点") % _cost)
	_total += points
	_results.append({"title": str(_cust.get("title", "")), "outcome": outcome, "points": points, "turns": _turns})
	_add_sales(outcome)
	if outcome == "age_lax" and (randf() < POLICE_CHANCE) and not main.smoke:
		await _police(my_run)
		return
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
	# 年齢確認（要件#61）: 身分証を見て、正しく判断する
	if _is_age_check():
		_on_action("id_check")
		await _wait(0.8)
		if my_run != _run or not _player_turn:
			return
		var must: bool = bool((_cust.get("age", {}) as Dictionary).get("must_leave", true))
		_on_action("age_refuse" if must else "age_allow")
		return
	# 筐体のデータ（要件#57）を開いて閉じる（番は終わらない）
	if typeof(_cust.get("spend", null)) == TYPE_DICTIONARY and not _data_seen:
		_on_action(ShopActions.MACHINE_DATA)
		await _wait(0.8)
		if my_run != _run or not _player_turn:
			return
		main.close_machine_data()
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
