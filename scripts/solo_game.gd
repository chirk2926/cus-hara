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
const Titles = preload("res://scripts/titles.gd")
const Shop = preload("res://scripts/shop.gd")

signal finished(stage_id: String, results: Array, total: int)
signal _reply(text: String)

const CUSTOMERS_PER_SHIFT: int = 4
const BASE_ANGER_RATE: float = 0.56     # 返事を考えている間、1秒あたりに上がる怒り（要件#49で 1.25→0.8、要件#86で 0.7倍）
## 納得の上がり方の倍率（要件#86: 全体をやさしく）。ハードコアはここからさらに厳しく
const RESOLVE_MUL: float = 1.3
## ハードコアモード（要件#86）: 怒り 1.6倍・納得 0.7倍・店長なし・定型文なし・ヒントなし・点数と給与 1.5倍。メンタルランク 10 で解放
const HARD_ANGER_MUL: float = 1.6
const HARD_RESOLVE_MUL: float = 0.7
const HARD_REWARD_MUL: float = 1.5
const HARD_UNLOCK_RANK: int = 10
## 店長を呼ぶ（要件#86）: 1シフト1回。呼んだお客さんの点数は半分
const CALL_MANAGER_POINTS: float = 0.5
## 社員モードの風営法の確認（要件#91）: お客さんの合間に、この確率で警察が来て質問する（1シフト1回まで）
const FUEI_CHANCE: float = 0.05   # 社員モードで警察が風営法の質問に来る確率（要件#97: 5%くらい）
const FUEI_SECONDS: float = 20.0
## 臭い客のイベント（要件#92）: この確率でお客さんから強烈なにおい。しれっと消臭剤をかける（30% でバレる）か、遠回しに伝える
const SMELL_CHANCE: float = 0.12
const SMELL_CAUGHT: float = 0.3
const RATE_STEP: float = 0.04           # お客さん1人ごとの上昇率（要件#49で 0.15→0.08、要件#90で 0.04）
## お客さんが言い終わってから、怒りが上がり始めるまでの読む時間（秒。要件#90）
const READ_GRACE: float = 5.0
## 同じお客さんに2回すると規定違反になる行動（要件#90）。「景品を取りやすい位置へ」は取れるまで何回でもよい
const ONCE_ONLY: Array = ["maintenance", "credit", "medal_return", "crane_stuck", "discount"]
const VIOLATION_COST: int = 300
const VIOLATION_REVIEW: float = -0.2
const SCORE_RESOLVED: int = 1000
const SCORE_EXPLODED: int = -300
const SCORE_YIELDED: int = -600
const SCORE_BREAKDOWN: int = -500
## 行動ボタンの店の負担（点数から引く）。台の調整で規定外の強さにしたら CHEAT
## 話がまとまったとみなす納得・怒りの目安（要件#106）
const SETTLE_AT: float = 70.0
const SETTLE_ANGER: float = 40.0
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
## 入店できない客を遊ばせていた・売ってしまったとき、警察が来る確率と営業停止の点数（要件#97: 年齢確認のミスは必ず来る）
const POLICE_CHANCE: float = 1.0
## 退店・販売のお断りをお願いしたとき、ちょっとだけ粘る確率（要件#97）。もう一度お願いすれば従う
const LEAVE_RESIST_CHANCE: float = 0.3
const SCORE_SUSPENDED: int = -2000
const REVIEW_SUSPENDED: float = -1.5
const CHEAT_COST: int = 150
## 筐体の前の対応（要件#99）。かかった時間 1 秒あたりの怒りの上がり方（ゆるやかに）と、レールを叩いたときの減点
const REPAIR_ANGER_RATE: float = 0.45
const HIT_COST: int = 150
const HIT_REVIEW: float = -0.05
## 店員のメンタル（要件#38）
const MENTAL_MAX: float = 100.0
const ACTION_PREFIX: String = "\u0001action:"
## たまに起きるイベント（要件#52）
## 要注意人物: 2人目以降のお客さんが、この確率でとびきり突飛な人になる（1シフト1回まで）。納得させると点数 ×1.5
const WILD_CHANCE: float = 0.07   # 要件#106: 多すぎたので半分以下（0.18 → 0.07）
const WILD_BONUS: float = 1.5
## 店長のアドバイス: 返事の番が来るとき、怒りが高い（または話が長引いている）と、この確率で店長が来る（1シフト1回まで）
const MANAGER_CHANCE: float = 0.15    # 要件#86: 怒りが 80 以上のときだけ、この確率
const MANAGER_ANGER: float = 80.0
const MANAGER_CALM: float = 10.0    # 店長の顔を見てお客さんが落ち着く分
const MANAGER_MENTAL: float = 10.0  # 店員のメンタルの回復

var main = null
var hud = null
var paused: bool = false
## ハードコアで遊んでいる（要件#86）
var hardcore: bool = false
var _manager_called: bool = false     # このシフトで店長を呼んだ
var _called_here: bool = false        # このお客さんで店長を呼んだ（点数が半分）
## 会話ログ（今のお客さんだけ。要件#86）: {"role": "customer"|"staff"|"manager", "text"}
var log_lines: Array = []
var log_open: bool = false
var _grace: float = 0.0              # 読む時間の残り（秒）
var _act_counts: Dictionary = {}     # このお客さんに使った行動の回数
var _id_views: int = 0               # 身分証を見た回数
var _alt_resisted: bool = false      # 別の身分証を頼んで、一度しぶられた
var _smelly: bool = false            # このお客さんは強烈なにおい（要件#92）
var _smell_done: bool = false        # 消臭剤をかけた・遠回しに伝えた
var _alt_id_asked: bool = false
var _leave_resisted: bool = false   # 退店のお願いに一度粘ったか（要件#97）

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
var _queued: Array = []            # 筐体の前でした対応（要件#99）。会話の番を待たずに順に判定する
var _repaired: bool = false        # 筐体の前に行ったか
var _nuisance_done: bool = false   # 迷惑なお客さんの様子を見に行ったか
var _in_nuisance: bool = false     # 迷惑なお客さん本人と話している
var _data_seen: bool = false
var _sales: int = 0              # このシフトの売上（円）
var _review: float = REVIEW_START # このシフトの店舗レビュー（★1〜5）
var _payout: int = 30            # このシフトのペイアウト率（ゲームセンター）
## シフトの終わりにまとめた売上・レビュー（main のレシートが読む）
var summary: Dictionary = {}
var _age_count: int = 0          # このシフトの年齢確認のお客さんの数
var _suspended: bool = false     # 営業停止になった
var _crane_wins: int = 0         # 台の調整で取れた回数（レビュー用）
var _offline_used: bool = false  # このシフトで台本・キーワード判定（オフライン）のお客さんがいた（経験値なし。要件#74）
var _id_seen: bool = false       # このお客さんの身分証を見た
## 称号の記録（要件#79）: このシフトとこのお客さんの様子
var _t_shift: Dictionary = {}
var _t_peak: float = 0.0         # このお客さんの怒りの最高
var _t_firm: bool = false        # このお客さんに、はっきり断る言葉を使った
var _t_last_action: String = ""
var _t_move_mode: bool = false   # 最後の台の調整が「景品を取りやすい位置へ」だった
var _t_data_views: int = 0       # このお客さんで筐体のデータを見た回数
var _t_manager_here: bool = false  # このお客さんの間に店長が来た
var _t_crane_lost: bool = false  # 台の調整で取らせられなかった（その後まだ取れていない）
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
	hud.tool_pressed.connect(_on_tool)


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
	_offline_used = false
	_suspended = false
	_crane_wins = 0
	_payout = GameSettings.effective_payout()
	_manager_called = false
	log_lines = []
	_update_tools()
	summary = {}
	_t_shift = {"impolite": false, "discount": 0, "age_total": 0, "age_ok": 0, "manager": false, "mental_min": MENTAL_MAX,
		"freebies": 0, "wild": false, "spend": false, "mental_lost": false, "calm_n": 0, "oneturn_n": 0, "age_refused": 0}
	_mental = MENTAL_MAX
	hud.set_mental(_mental)
	hud.set_voice_mode(false)
	hud.set_quick_phrases([] if hardcore else hud.DEFAULT_PHRASES)
	var fuei_done: bool = false
	for i in range(CUSTOMERS_PER_SHIFT):
		_index = i
		# 社員モード: 警察が風営法について聞きに来ることがある（要件#91）
		if hardcore and not fuei_done and i >= 1 and (randf() < FUEI_CHANCE or main.debug_flag("fuei")):
			fuei_done = true
			await _fuei_check(my_run)
			if my_run != _run:
				return
			if _suspended:
				break
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
		"suspended": _suspended, "reviews": _make_reviews(), "offline": _offline_used or GameSettings.solo_source == "offline",
		"clock_in": int(CLOCK.get(_stage_id, CLOCK["konbini"])[0]) - 30, "clock_out": _clock() + (20 if _suspended else 30)}
	_track_shift(review)
	# 給与（要件#82）: オフラインは HP、オンラインは CUS。売上がマイナスでも減らない
	# ペイアウト率 60% 以上は、景品代にスタッフの時給・電気代が乗って赤字になるので、給与は少なめ（要件#106）
	var pay_mul: float = Shop.payout_pay_mul(_payout) if _stage_id == "arcade" else 1.0
	summary["pay_cut"] = pay_mul < 1.0
	summary["pay"] = Shop.pay_shift(int(float(_sales) * (HARD_REWARD_MUL if hardcore else 1.0) * pay_mul), not bool(summary["offline"]))
	summary["hardcore"] = hardcore
	if hardcore:
		_track_hardcore()
	# レビューログ（要件#86）
	var d: Dictionary = Time.get_datetime_dict_from_system()
	GameSettings.add_review_log({"date": "%04d-%02d-%02d %02d:%02d" % [int(d["year"]), int(d["month"]), int(d["day"]), int(d["hour"]), int(d["minute"])],
		"stage": _stage_id, "review": review, "reviews": summary["reviews"], "sales": _sales, "total": _total, "hard": hardcore,
		"results": _results.map(func(r: Dictionary) -> Dictionary: return {"title": str(r.get("title", "")), "outcome": str(r.get("outcome", ""))})})
	summary["new_titles"] = Titles.check()
	GameSettings.save_settings()


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
			var agd: Dictionary = _cust.get("age", {})
			if not hardcore and (bool(agd.get("hat", false)) or bool(agd.get("mask", false))):
				hud.set_comment(tr("使える身分証で、年齢も足りていた。正しい判断だ。") + "\n" + tr("（帽子・マスクは外してもらうと、本人か確実に分かる）"))
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
			hud.set_comment(tr("顔写真と生年月日のある身分証で、年齢も足りていた。帰す必要はなかった。") if _age_mode() != "konbini" else tr("顔写真と生年月日のある身分証で、20歳以上だった。売ってよかった。"))
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
	GameSettings.stat_add("suspended")
	_total += SCORE_SUSPENDED
	_review += REVIEW_SUSPENDED
	_results.append({"title": tr("営業停止"), "outcome": "suspended", "points": SCORE_SUSPENDED, "turns": 0, "clock": _clock() + 20})
	_update_top()
	await _wait(2.6)
	if my_run != _run:
		return
	hud.hide_bubble()
	main.manager_leave()
	await main.dismiss_customer("smug")


## 風営法の確認（社員モード。要件#91）: 3つの答えから選ぶ。まちがえる・時間切れは営業停止
func _fuei_check(my_run: int) -> void:
	hud.set_actions([])
	hud.set_input_enabled(false, "")
	hud.show_banner(tr("警察です！"), Color("#5b7bd5"))
	main.sfx.play("warn", 0.7)
	await main.police_visit()
	if my_run != _run:
		return
	var qs: Array = [
		[tr("風営法の許可証は、どこに掲示していますか？"), [tr("店内の見やすい場所に掲示しています"), tr("事務所の金庫にしまってあります"), tr("店長が家に持って帰っています")]],
		[tr("従業員名簿を見せてください。"), [tr("事務所に備えてあります。すぐお持ちします"), tr("名簿は作っていません"), tr("個人情報なのでお見せできません")]],
		[tr("18歳未満の夜間の入場制限は、どこに表示していますか？"), [tr("入口に掲示しています"), tr("表示はしていません"), tr("スタッフが口で伝えています")]],
	]
	var q: Array = qs[randi() % qs.size()]
	await main.customer_say(tr("警察官"), str(q[0]), false)
	if my_run != _run:
		return
	GameSettings.stat_add("fuei_checks")
	var ok: bool = await main.show_quiz(tr("警察官の質問"), str(q[0]), q[1], 0, FUEI_SECONDS)
	if my_run != _run:
		return
	if ok:
		GameSettings.stat_add("fuei_passed")
		main.sfx.play("good", 1.0)
		await main.customer_say(tr("警察官"), tr("よろしい。引き続き、きちんと営業してください。"), false)
		if my_run != _run:
			return
		await _wait(1.0)
		hud.hide_bubble()
		main.manager_leave()
		return
	main.shake(0.3)
	main.sfx.play("explode")
	await main.customer_say(tr("警察官"), tr("答えられないのですか。営業停止です。"), true)
	if my_run != _run:
		return
	hud.show_banner(tr("営業停止…") + "  %d" % SCORE_SUSPENDED, Color("#ff8a6a"))
	_suspended = true
	GameSettings.stat_add("suspended")
	_total += SCORE_SUSPENDED
	_review += REVIEW_SUSPENDED
	_results.append({"title": tr("営業停止（風営法）"), "outcome": "suspended", "points": SCORE_SUSPENDED, "turns": 0, "clock": _clock()})
	_update_top()
	await _wait(2.0)
	if my_run != _run:
		return
	hud.hide_bubble()
	main.manager_leave()


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
	# 台の前に筐体のデータを見に行っている間は、怒りは止まる（要件#66）
	if not _active or not _player_turn or paused or main.machine_view_open or main.debug_flag("anger_stop") or log_open:
		return
	if _grace > 0.0:
		_grace -= delta
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
			_id_views += 1
			# 何度も見せてもらうと、お客さんの印象（店舗レビュー）が下がる（要件#90）
			if _id_views > 2:
				_review -= 0.05
				hud.set_comment(tr("何度も身分証を見せてもらうと、お客さんの印象が悪くなる。"))
			if not _id_seen:
				_id_seen = true
				_history.append({"role": "staff", "text": tr("（身分証を確認した）")})
				hud.set_actions(_age_buttons())
		return
	# 筐体のデータは見るだけ（番は終わらない。要件#57）
	if id == ShopActions.MACHINE_DATA:
		if _active and not paused and main.mode == "solo":
			GameSettings.stat_add("machine_data_views")
			_t_data_views += 1
			if _t_data_views == 3:
				GameSettings.stat_add("data_views_one_customer")
			main.show_machine_data(_cust)
			if not _data_seen:
				_data_seen = true
				_history.append({"role": "staff", "text": tr("（筐体のデータを確認した）")})
		return
	if _active and _player_turn and not paused and main.mode == "solo":
		_player_turn = false
		_reply.emit(ACTION_PREFIX + id)


## 画面の上のボタン（要件#86）: 会話ログ・ペイアウト（ゲームセンター）・店長を呼ぶ（1シフト1回）
func _update_tools() -> void:
	var tools: Array = [["log", tr("会話ログ")]]
	if _stage_id == "arcade":
		tools.append(["payout", tr("ペイアウト")])
	if not hardcore:
		tools.append(["call_manager", tr("店長を呼ぶ（1回）") if not _manager_called else tr("店長は呼んだ")])
	hud.set_tools(tools, {"call_manager": not _manager_called})


func _on_tool(id: String) -> void:
	if not _active or main.mode != "solo":
		return
	match id:
		"log":
			main.show_talk_log(log_lines, str(_cust.get("title", "")))
		"payout":
			main.show_payout_panel()
		"call_manager":
			if _manager_called or hardcore or not _player_turn or paused or _manager_used:
				if _manager_used and not _manager_called:
					hud.set_comment(tr("店長はさっき来たばかりだ。このシフトはもう呼べない。"))
				return
			_manager_called = true
			_called_here = true
			GameSettings.stat_add("manager_called")
			_player_turn = false
			_update_tools()
			var my_run: int = _run
			await _manager_visit(my_run, true)
			if my_run != _run or not _active:
				return
			_player_turn = true
			hud.set_input_enabled(true, tr("ここに返事を書く…"))


## ペイアウトを変えたら、ここからの売上・レビューに効かせる
func refresh_payout() -> void:
	_payout = GameSettings.effective_payout()


## ハードコアの記録（称号用。要件#86）
func _track_hardcore() -> void:
	var count: Dictionary = {}
	for r in _results:
		var o: String = str((r as Dictionary).get("outcome", ""))
		count[o] = int(count.get(o, 0)) + 1
	var completed: bool = not _suspended and _results.size() >= CUSTOMERS_PER_SHIFT and int(count.get("breakdown", 0)) == 0
	if not completed:
		return
	GameSettings.stat_add("hard_shifts")
	var resolved: int = int(count.get("resolved", 0)) + int(count.get("age_ok", 0)) + int(count.get("age_refused", 0))
	if resolved >= CUSTOMERS_PER_SHIFT:
		GameSettings.stat_add("hard_perfect")
	if int(count.get("yield", 0)) == 0:
		GameSettings.stat_add("hard_no_yield")
	GameSettings.stat_max("hard_best", _total)


## 同じ見た目のお客さんばかりにならないよう、来るたびに少し変える（要件#90）。年齢確認のお客さんと要注意人物はそのまま
func _vary_look(base: Dictionary) -> Dictionary:
	var look: Dictionary = base.duplicate()
	if _is_age_check() or _wild:
		return look
	var bodies: Array = ["#3f6b4f", "#8a3a3a", "#2f3b63", "#7a6a4a", "#5a4a7a", "#2a6a7a", "#9a5a2a", "#4a4a4a", "#a03a6a", "#3a7a3a", "#c0a040", "#6a2a2a"]
	var hairs: Array = ["#262326", "#3a2a20", "#6b4426", "#9a7040", "#b8b4ae", "#555050", "#2a2a3a"]
	if randf() < 0.75:
		look["body_color"] = bodies[randi() % bodies.size()]
	if randf() < 0.5:
		look["hair_color"] = hairs[randi() % hairs.size()]
	if randf() < 0.45 and str(look.get("hair", "")) != "bald":
		look["hair"] = ["short", "long", "perm", "cap", "bob", "ponytail", "spiky"][randi() % 7]
	if randf() < 0.35:
		look["accessory"] = ["none", "glasses", "headphones", "mask", "sunglasses", "beanie", "bag", "necktie"][randi() % 8]
	if randf() < 0.3:
		look["build"] = ["slim", "normal", "big"][randi() % 3]
	look["height"] = clampf(float(look.get("height", 1.0)) + randf_range(-0.06, 0.06), 0.85, 1.15)
	if str(look.get("hair", "")) in ["long", "bob", "ponytail"] and randf() < 0.5:
		look["gender"] = "f"
	return look


## 行動ボタンに「しれっと消臭剤をかける」を足す（臭い客のとき）
func _with_smell(btns: Array) -> Array:
	if _smelly and not _smell_done:
		btns = btns.duplicate()
		btns.append(["deodorize", tr("しれっと消臭剤をかける")])
	return btns


func _with_smell_refresh() -> void:
	hud.set_actions(_with_smell(ShopActions.buttons(_stage_id, _cust, not _crane_used)))


## しれっと消臭剤をかける（要件#92）: 30% でバレて怒られる。バレなければにおいが消えて少し落ち着く
func _deodorize(speaker: String) -> void:
	_smell_done = true
	_turns += 1
	main.sfx.play("click", 1.6)
	log_lines.append({"role": "staff", "text": tr("（しれっと消臭剤をかけた）")})
	hud.show_echo(tr("あなた: "), tr("（しれっと消臭剤をかけた）"))
	if randf() < SMELL_CAUGHT and not main.smoke:
		GameSettings.stat_add("smell_caught")
		_anger = minf(100.0, _anger + 25.0)
		_review -= 0.2
		_refresh(false)
		hud.show_delta(25, 0)
		hud.set_comment(tr("バレた！お客さんが気を悪くした。"))
		main.set_stink(false)
		var line: String = str(Judge.pick_lang(["ちょっと！今、何かけたでしょ！？失礼にもほどがある！", "……今の、消臭剤だよね？"], ["Hey! Did you just spray something at me?! How rude!", "...Was that air freshener?"], ["喂！你刚才喷了什么！？太失礼了吧！", "……刚才那是除臭剂吧？"], ["잠깐! 방금 뭐 뿌렸죠?! 실례도 정도가 있지!", "……방금 그거, 탈취제죠?"]))
		log_lines.append({"role": "customer", "text": line})
		await _customer_line(speaker, line, "angry")
	else:
		GameSettings.stat_add("smell_ok")
		_anger = maxf(0.0, _anger - 5.0)
		_change_mental(5.0)
		_refresh(false)
		hud.show_delta(-5, 0)
		hud.set_comment(tr("バレずに済んだ。においがやわらいだ。"))
		main.set_stink(false)
	_with_smell_refresh()


func _smell_talk(reply: String) -> String:
	var t: String = reply.to_lower()
	for w in ["臭", "くさ", "におう", "におい", "匂う", "smell", "stink", "b.o.", "臭味", "有味", "냄새", "악취", "구린", "구려"]:
		if t.find(w) >= 0:
			# 「においがこもって」「換気」のような言い方は遠回し
			for soft in ["換気", "こもって", "空調", "ventilat", "通风", "환기", "공기", "에어컨"]:
				if t.find(soft) >= 0:
					return "hint"
			return "direct"
	for w2 in ["換気", "空調", "エアコン", "暑い", "汗", "タオル", "シャワー", "ventilat", "air conditioning", "hot today", "towel", "shower", "通风", "空调", "毛巾", "天热", "出汗", "환기", "에어컨", "덥", "땀", "수건", "샤워"]:
		if t.find(w2) >= 0:
			return "hint"
	return ""


## 金額を言ってしまったか（数字＋円・ドル・元、など）
func _says_amount(reply: String) -> bool:
	var re: RegEx = RegEx.new()
	re.compile("[0-9０-９][0-9０-９,，.]*\\s*(円|えん|yen|ドル|dollars?|\\$|元|块|千|万|원|천|만)|[\\$¥￥][0-9０-９]")
	return re.search(reply.to_lower()) != null


## 景品だけが目当てか（土下座・返金・タダなど、ほかのものも求めていない）
func _prize_only() -> bool:
	var d: String = str(_cust.get("demand", "")).to_lower()
	for w in ["土下座", "返金", "返せ", "タダ", "無料", "謝罪", "補償", "お金", "金を", "もう1", "もう一", "kneel", "refund", "free", "money", "compens", "another", "apolog", "下跪", "退款", "免费", "钱", "赔", "再给", "道歉", "무릎", "환불", "공짜", "무료", "돈", "보상", "사과", "한 번 더", "한번 더"]:
		if d.find(w) >= 0:
			return false
	return true


func _change_mental(delta: float) -> void:
	if delta < 0.0 and not _t_shift.is_empty():
		_t_shift["mental_lost"] = true
	_mental = clampf(_mental + delta, 0.0, MENTAL_MAX)
	hud.set_mental(_mental)


func _on_reply(text: String) -> void:
	if _active and _player_turn and not paused and main.mode == "solo":
		_player_turn = false
		_reply.emit(text)


func _refresh(show_countdown: bool) -> void:
	_t_peak = maxf(_t_peak, _anger)
	if not _t_shift.is_empty():
		_t_shift["mental_min"] = minf(float(_t_shift.get("mental_min", MENTAL_MAX)), _mental)
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
	var out: Array = [["id_check", ShopActions.label("id_check")]]
	# 別の身分証は、まず身分証を見せてもらってから（要件#90）
	if not _alt_id_asked and _id_seen:
		out.append(["ask_other_id", ShopActions.label("ask_other_id")])
	# 帽子・マスクで顔が分かりにくいときは、外してもらえる（要件#106）
	var ag: Dictionary = _cust.get("age", {}) if typeof(_cust.get("age", null)) == TYPE_DICTIONARY else {}
	if bool(ag.get("hat", false)):
		out.append(["hat_off", ShopActions.label("hat_off")])
	if bool(ag.get("mask", false)):
		out.append(["mask_off", ShopActions.label("mask_off")])
	if _age_mode() == "konbini":
		out.append_array([["age_allow", ShopActions.label("sell_ok")], ["age_refuse", ShopActions.label("sell_refuse")]])
	else:
		out.append_array([["age_allow", ShopActions.label("age_allow")], ["age_refuse", ShopActions.label("age_refuse")]])
	return out


## 「別の身分証を見せて」と言った・押した（要件#86）。持っていれば本人の使える身分証を出し、なければ「持ってない」
func _wants_other_id(reply: String) -> bool:
	var words: Array = ["別の身分証", "他の身分証", "ほかの身分証", "別のもの", "免許証", "マイナンバー", "パスポート", "another id", "other id", "different id", "license", "passport", "其他证件", "别的证件", "驾照", "护照", "다른 신분증", "다른 거", "면허증", "마이넘버", "여권"]
	var t: String = reply.to_lower()
	for w in words:
		if t.find(str(w)) >= 0:
			return true
	return false


func _ask_other_id(speaker: String) -> void:
	_turns += 1
	# たまに渋る（要件#90）: 1回目は 30% で「なんでよ」。もう一度頼めば出す（または持っていないと言う）
	if not _alt_resisted and randf() < 0.3:
		_alt_resisted = true
		_anger = minf(100.0, _anger + 8.0)
		_refresh(false)
		hud.show_delta(8, 0)
		var no: String = str(Judge.pick_lang(["えー、なんでよ。それでいいでしょ？", "めんどくさいなあ……さっきの見たでしょ。", "は？疑ってるの？"], ["Ugh, why? That one's fine, right?", "What a hassle... you already saw it.", "What, you don't believe me?"], ["诶，为什么啊。那个不就行了？", "真麻烦……刚才不是看过了吗。", "啊？你怀疑我？"], ["에이, 왜요. 그걸로 되잖아요?", "귀찮게…… 아까 봤잖아요.", "네? 의심하는 거예요?"]))
		if not hardcore:
			hud.set_comment(tr("しぶっている。ていねいに、もう一度お願いしてみよう。"))
		log_lines.append({"role": "customer", "text": no})
		await _customer_line(speaker, no, "angry")
		return
	_alt_id_asked = true
	var ag: Dictionary = _cust.get("age", {})
	var alt: Dictionary = ag.get("alt", {}) if typeof(ag.get("alt", null)) == TYPE_DICTIONARY else {}
	var line: String = ""
	if not alt.is_empty():
		for k in alt:
			ag[k] = alt[k]
		ag["must_leave"] = int(ag.get("shown_age", 0)) < int(ag.get("limit", 18))
		line = str(Judge.pick_lang(["……じゃあ、これでいい？", "……はい、これ。", "あ、こっちならあるけど。"], ["...Fine, will this do?", "...Here.", "Oh, I've got this one."], ["……那这个行吧？", "……给。", "啊，这个倒是有。"], ["……그럼 이거면 돼요?", "……자, 여기요.", "아, 이건 있는데."]))
		main.show_id_card(_cust)
		if not hardcore:
			hud.set_comment(tr("別の身分証が出てきた。もう一度、種類・顔写真・生年月日を確かめよう。"))
	else:
		ag["must_leave"] = true
		ag["no_id"] = true
		line = str(Judge.pick_lang(["え、ほかのは持ってないけど……", "そんなの持ち歩いてないよ。", "……それしかない。"], ["Uh, I don't have anything else...", "I don't carry that around.", "...That's all I've got."], ["诶，我没带别的……", "谁随身带那个啊。", "……就只有这个。"], ["어, 다른 건 없는데……", "그런 거 안 들고 다녀요.", "……그것밖에 없어요."]))
		if not hardcore:
			hud.set_comment(tr("顔写真と生年月日のある身分証がないなら、年齢は確かめられない。退店をお願いしよう。"))
	_cust["age"] = ag
	hud.set_actions(_age_buttons())
	log_lines.append({"role": "staff", "text": tr("（行動: %s）") % ShopActions.label("ask_other_id")})
	log_lines.append({"role": "customer", "text": line})
	await _customer_line(speaker, line, "")


## 迷惑なお客さん（台パン・大声）のデータ（data/offenders.json）
static var _offenders: Dictionary = {}


func _offender(problem: String) -> Dictionary:
	if _offenders.is_empty():
		var f: FileAccess = FileAccess.open("res://data/offenders.json", FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY:
				_offenders = d
	var lang: String = GameSettings.language if GameSettings.language in ["en", "zh", "ko"] else "ja"
	var byp: Dictionary = _offenders.get(problem, {})
	return (byp.get(lang, byp.get("ja", {})) as Dictionary).duplicate(true)


## 台パン・大声を知らせに来たお客さん（要件#99）: 様子を見に行って、迷惑なお客さん本人と話す。
## 本人との会話はキーワード判定。終わったらカウンターに戻り、知らせてくれたお客さんの結果にする
func _nuisance(reporter_speaker: String, my_run: int) -> String:
	var prob: String = ShopActions.problem_of(_cust)
	var off: Dictionary = _offender(prob)
	_nuisance_done = true
	if off.is_empty():
		return "resolved"
	var reporter: Dictionary = _cust
	var keep_anger: float = _anger
	var keep_used: Array = _used.duplicate()
	main.show_talk_backdrop(prob)
	_cust = off
	_in_nuisance = true
	_anger = float(off.get("start_anger", 50))
	_resolve = 0.0
	_used = []
	hud.set_actions([])
	hud.set_memo(str(off.get("title", "")), str(off.get("memo", "")), str(off.get("demand", "")))
	var sp: String = str(off.get("title", ""))
	_refresh(false)
	await main.customer_say(sp, str(off.get("opening", "")), true)
	log_lines.append({"role": "customer", "text": str(off.get("opening", ""))})
	var res_out: String = ""
	for turn in range(8):
		if my_run != _run:
			return ""
		_player_turn = true
		_grace = READ_GRACE
		hud.set_status(tr("迷惑なお客さんに、落ち着いて声をかけよう（Enterで渡す）"))
		hud.set_input_enabled(true, tr("ここに返事を書く…"))
		if main.smoke:
			_smoke_autoplay(my_run)
		var reply: String = await _reply
		if my_run != _run:
			return ""
		_player_turn = false
		hud.set_input_enabled(false, "")
		if reply == "":
			res_out = "explode"
			_anger = 100.0
			_refresh(false)
			break
		if reply.begins_with(ACTION_PREFIX):
			continue
		_turns += 1
		hud.show_echo(tr("あなた: "), reply)
		log_lines.append({"role": "staff", "text": reply})
		var j: Dictionary = Judge.judge(_cust, reply, _used, _anger, _resolve)
		_used.append(reply)
		var a: int = int(j.get("anger_delta", 0))
		var r: int = int(j.get("resolve_delta", 0))
		if r > 0:
			r = int(round(float(r) * RESOLVE_MUL * (HARD_RESOLVE_MUL if hardcore else 1.0)))
		_anger = clampf(_anger + float(a), 0.0, 100.0)
		_resolve = clampf(_resolve + float(r), 0.0, 100.0)
		_refresh(false)
		hud.show_delta(a, r)
		if not hardcore:
			hud.set_comment(str(j.get("comment", "")))
		var kind: String = "calm" if a < 0 else ("angry" if a > 0 else "")
		var line: String = str(j.get("customer_reply", ""))
		if bool(j.get("yielded", false)):
			res_out = "yield"
			line = Judge.line(_cust, "yielded")
		elif _anger >= 100.0:
			res_out = "explode"
			line = Judge.line(_cust, "explode")
		elif _resolve >= 100.0:
			res_out = "resolved"
			line = Judge.line(_cust, "resolved")
		if line == "":
			line = Judge.line(_cust, "calm" if a < 0 else ("angry" if a > 0 else "neutral"))
		log_lines.append({"role": "customer", "text": line})
		await _customer_line(sp, line, kind)
		if my_run != _run:
			return ""
		if res_out != "":
			break
	if res_out == "":
		res_out = "resolved" if _resolve >= _anger else "explode"
	if res_out == "resolved":
		main.calm_talk_backdrop()
		await _wait(0.8)
		if my_run != _run:
			return ""
	main.hide_talk_backdrop()
	# カウンターに戻る: 知らせてくれたお客さんの反応で終わる
	_cust = reporter
	_in_nuisance = false
	_anger = keep_anger
	_resolve = 100.0 if res_out == "resolved" else _resolve
	_used = keep_used
	hud.set_memo(str(reporter.get("title", "")), str(reporter.get("memo", "")), str(reporter.get("demand", "")))
	_refresh(false)
	var rl: String = Judge.line(reporter, "resolved" if res_out == "resolved" else ("yielded" if res_out == "yield" else "explode"))
	log_lines.append({"role": "customer", "text": rl})
	await _customer_line(reporter_speaker, rl, "happy" if res_out == "resolved" else "angry")
	if res_out == "resolved":
		GameSettings.stat_add("nuisance_calmed")
	return res_out


## 帽子を取ってもらう・マスクを外してもらう（要件#106）。顔が見えて、身分証の写真と比べやすくなる。返事は台本
func _uncover(speaker: String, id: String) -> void:
	_turns += 1
	var ag: Dictionary = _cust.get("age", {})
	var look: Dictionary = (_cust.get("look", {}) as Dictionary).duplicate()
	var line: String = ""
	if id == "hat_off":
		ag["hat"] = false
		look["hair"] = str(ag.get("under_hair", "short"))
		line = str(Judge.pick_lang(["え、帽子？……はい。", "髪ぺちゃんこなんだけど……はい。"], ["My cap? ...Fine.", "Ugh, hat hair... okay."], ["帽子？……好吧。", "头发都压扁了……给。"], ["모자요? ……네.", "머리 눌렸는데…… 네."]))
	else:
		ag["mask"] = false
		look["accessory"] = str(ag.get("under_acc", "none"))
		line = str(Judge.pick_lang(["マスク？……ちょっとだけね。", "……はい、これでいい？"], ["My mask? ...Just for a sec.", "...There. Happy?"], ["口罩？……就一下哦。", "……这样行了吧？"], ["마스크요? ……잠깐만요.", "……됐죠?"]))
	_cust["age"] = ag
	_cust["look"] = look
	main.update_customer_look(look)
	if not hardcore:
		hud.set_comment(tr("顔が見えた。身分証の写真と見比べよう。"))
	hud.set_actions(_age_buttons())
	log_lines.append({"role": "staff", "text": tr("（行動: %s）") % ShopActions.label(id)})
	log_lines.append({"role": "customer", "text": line})
	_history.append({"role": "customer", "text": line})
	await _customer_line(speaker, line, "")


## 退店・販売のお断りに、ちょっとだけ粘るときのセリフ（要件#97）
func _resist_line() -> String:
	if _age_mode() == "konbini":
		return str(Judge.pick_lang(
			["えー、1本だけでいいんだけど……ダメ？", "いや、ほんとに大人なんだって。ちょっとだけ見逃してよ。", "……マジで？ほかの店じゃ普通に買えたけど。"],
			["Aw, just one... Really, no?", "Come on, I really am an adult. Just let it slide this once.", "...Seriously? Other stores sell it to me."],
			["诶，就买一个……不行吗？", "我真的是大人啦。就通融一下嘛。", "……真的假的？别的店都能买的。"],
			["에이, 하나만인데…… 안 돼요?", "진짜 어른이라니까요. 한 번만 봐줘요.", "……진짜요? 다른 가게에선 그냥 샀는데."]))
	return str(Judge.pick_lang(
		["えー、あと1回だけ！ほんとに1回だけだから！", "ちょっと待って、今いいとこなんだって……", "……え、もう？友だちまだ来てないんだけど。"],
		["Aw, just one more round! Really, just one!", "Wait, I'm right in the middle of something good...", "...Already? My friends aren't even here yet."],
		["诶，再玩一次！真的就一次！", "等一下，现在正玩到关键时候……", "……啊，这就要走？我朋友还没来呢。"],
		["에이, 한 판만 더! 진짜 딱 한 판!", "잠깐만요, 지금 좋은 데란 말이에요……", "……네, 벌써요? 친구 아직 안 왔는데."]))


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
	if _manager_used or _turns < 1 or (hardcore and not main.smoke):
		return
	# 困っているとき（怒り 80 以上）だけ、低い確率で来る（要件#86）
	var tense: bool = _anger >= MANAGER_ANGER
	if not tense and not main.smoke and not main.debug_flag("manager"):
		return
	if not (randf() < MANAGER_CHANCE or main.smoke or main.debug_flag("manager")):
		return
	await _manager_visit(my_run, false)


## 店長が来てアドバイスする。called は「店長を呼ぶ」ボタンで呼んだとき
func _manager_visit(my_run: int, called: bool) -> void:
	_manager_used = true
	GameSettings.stat_add("manager_visits")
	_t_shift["manager"] = true
	_t_manager_here = true
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
		lines.append(tr("「%s」について具体的に伝えてみろ。") % kw)
	if act != "":
		lines.append(tr("「%s」ボタンも効くかもしれない。") % ShopActions.label(act))
	if lines.is_empty():
		lines.append(tr("メモの規定を確かめて、できることを具体的に伝えろ。"))
	lines.append(tr("要求は飲むなよ。"))
	if called:
		lines.append(tr("（呼んだので、このお客さんの点数は半分になる）"))
	hud.set_comment(tr("店長: ") + " ".join(lines))
	log_lines.append({"role": "manager", "text": " ".join(lines)})
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


## テスト版（要件#106）: デバッグパネルで選んだ種類のお客さんを、台本から作る。選んでいなければ {}
func _debug_customer() -> Dictionary:
	var kind: String = str(main.debug_kind)
	if kind == "":
		return {}
	if kind == "hatmask":
		var ac: Dictionary = AgeCheck.make(maxi(_clock(), 22 * 60 + 10), GameSettings.language, _stage_id, true)
		return ac
	if _stage_id != "arcade":
		return {}
	var list: Array = Scenarios.customers("arcade")
	for _try in 40:
		var c: Dictionary = (list[randi() % list.size()] as Dictionary).duplicate(true)
		match kind:
			"stuck":
				if not ShopActions.is_stuck(c):
					continue
				return ShopActions.apply_problem(c)
			"spend_true", "spend_lie":
				if not bool(c.get("spend", false)):
					continue
				var m: Dictionary = Scenarios.materialize_spend(c, _payout)
				if bool(m.get("_lie", false)) != (kind == "spend_lie"):
					continue
				return ShopActions.apply_problem(m)
			_:
				var want: String = "button" if kind == "button_lie" else kind
				if str(c.get("problem", "")) != want:
					continue
				var p: Dictionary = ShopActions.apply_problem(c)
				if str(p.get("problem", "")) != kind:
					continue
				return p
	return {}


func _next_offline() -> Dictionary:
	if _wild:
		var rares: Array = Scenarios.customers(_stage_id).filter(func(c: Variant) -> bool:
			return bool((c as Dictionary).get("rare", false)) and not _titles.has(str((c as Dictionary).get("title", ""))))
		if not rares.is_empty():
			return ShopActions.apply_problem(Scenarios.materialize_spend((rares[randi() % rares.size()] as Dictionary).duplicate(true), _payout))
	if _pool.is_empty():
		_pool = Scenarios.customers(_stage_id).duplicate()
		_pool.shuffle()
	# 「取れない」クレームはペイアウト率で出やすさが変わる（要件#55）: 重みつきで1人選ぶ
	var weights: Array = []
	var sum: float = 0.0
	for c in _pool:
		var w: float = Scenarios.spend_weight(_payout) if (_stage_id == "arcade" and bool((c as Dictionary).get("spend", false))) else 1.0
		if bool((c as Dictionary).get("rare", false)):
			w *= 0.1   # 要注意人物はめったに来ない（要件#106: 多すぎた）
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
	# 台の問題（要件#99）: 台の種類と行動の効果を表から入れる（「ボタンが反応しない」は 4割でうそ）
	return ShopActions.apply_problem(Scenarios.materialize_spend(picked, _payout))


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
			return ShopActions.apply_problem(Scenarios.materialize_spend(data, _payout))
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
	if main.debug_flag("wild") or (_index >= 1 and not _wild_used and (randf() < WILD_CHANCE or (main.smoke and _index == 1))):
		_wild = true
		_wild_used = true
	# 年齢確認のお客さん（要件#61）: 18:00 以降のゲームセンター。自動テストでは4人目で必ず
	var data: Dictionary = {}
	var age_ok_here: bool = (_stage_id == "arcade" and AgeCheck.limit_for(_clock()) > 0) or _stage_id == "konbini"
	var age_chance: float = AGE_CHANCE_KONBINI if _stage_id == "konbini" else AGE_CHANCE
	var forced: Dictionary = _debug_customer()
	if not forced.is_empty():
		_source = "offline"
		_session_id = ""
		data = forced
	elif age_ok_here and not main.debug_flag("no_age") and (main.debug_flag("age") or (not _wild and _age_count < AGE_MAX and (randf() < age_chance or (main.smoke and _index == 3)))):
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
	_t_peak = float(_cust.get("start_anger", 40))
	_t_firm = false
	_t_last_action = ""
	_t_move_mode = false
	_t_data_views = 0
	_t_manager_here = false
	_t_crane_lost = false
	if _wild:
		_t_shift["wild"] = true
	if typeof(_cust.get("spend", null)) == TYPE_DICTIONARY:
		_t_shift["spend"] = true
	# 年齢確認のお客さんはもともとゲームの中だけで判定するので数えない
	if _source == "offline" and not _is_age_check():
		_offline_used = true
	_titles.append(str(_cust.get("title", "")))
	if _wild:
		GameSettings.stat_add("wild_met")
		_make_wild_look()
	_anger = float(_cust.get("start_anger", 40))
	_resolve = 0.0
	_turns = 0
	_history = []
	_used = []
	# 1秒あたりの怒り。サーバーの管理画面で秒数が決まっていればそれを使う（要件#106）
	var base_rate: float = (100.0 / GameSettings.snap_seconds()) if GameSettings.snap_seconds() > 0.0 else BASE_ANGER_RATE * GameSettings.answer_rate()
	_rate = base_rate * float(_cust.get("patience", 1.0)) * (1.0 + RATE_STEP * float(_index)) * (HARD_ANGER_MUL if hardcore else 1.0)
	_cost = 0
	_sales_cost = 0
	_crane_used = false
	_queued = []
	_repaired = false
	_nuisance_done = false
	_in_nuisance = false
	_data_seen = false
	_called_here = false
	log_lines = []
	_alt_id_asked = false
	_leave_resisted = false
	_act_counts = {}
	_id_views = 0
	_alt_resisted = false
	_smelly = (not _is_age_check()) and (randf() < SMELL_CHANCE or main.debug_flag("smell"))
	_smell_done = false
	_refresh(false)
	_update_tools()

	# ---- 来店
	hud.set_status(tr("いらっしゃいませ…"))
	main.sfx.play("door")
	var look: Dictionary = {}
	if typeof(_cust.get("look", null)) == TYPE_DICTIONARY:
		look = _vary_look(_cust["look"])
	if _wild:
		hud.show_banner(tr("！要注意人物が来店！"), UI.SHU)
		hud.set_comment(tr("要注意人物だ。何を言い出すか分からないぞ。納得させれば点数 ×1.5！"))
		main.sfx.play("warn", 0.8)
		main.shake(0.12)
	elif ShopActions.is_stuck(_cust) and _stage_id == "arcade":
		# 景品が本当に引っかかっている（要件#91: しっかり表示）
		hud.show_banner(tr("景品が引っかかっている！"), UI.POP)
		hud.set_comment(tr("この台は景品が引っかかっている。「引っかかった景品をとる」が使える。"))
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
		hud.set_actions(_with_smell(ShopActions.buttons(_stage_id, _cust, true)))
	if _smelly:
		main.set_stink(true)
		hud.show_banner(tr("強烈なにおい…！"), Color("#8fbf3a"))
		if not hardcore:
			hud.set_comment(tr("お客さんから強烈なにおいがする。しれっと消臭剤をかけるか、遠回しに伝えるか…。"))
	var speaker: String = tr("%s（%s）") % [str(_cust.get("title", tr("お客さん"))), str(_cust.get("name", ""))]
	var memo_text: String = str(_cust.get("memo", ""))
	if ShopActions.is_stuck(_cust) and _stage_id == "arcade":
		memo_text = tr("【景品が引っかかっています】") + "\n" + memo_text
	hud.set_memo(str(_cust.get("title", "")), memo_text, str(_cust.get("demand", "")))
	var opening: String = str(_cust.get("opening", "……"))
	_history.append({"role": "customer", "text": opening})
	log_lines.append({"role": "customer", "text": opening})
	await main.customer_say(speaker, opening, true)
	if my_run != _run:
		return

	# ---- 会話
	var outcome: String = ""
	while outcome == "":
		await _maybe_manager_visit(my_run)
		if my_run != _run:
			return
		var reply: String = ""
		if not _queued.is_empty():
			# 筐体の前でした対応を、ひとつずつ判定する（要件#99）
			reply = ACTION_PREFIX + str(_queued.pop_front())
		else:
			_player_turn = true
			_grace = READ_GRACE
			hud.set_status(tr("キレられる前に返事を書こう（Enterで渡す）"))
			hud.set_input_enabled(true, tr("ここに返事を書く…"))
			if main.smoke:
				_smoke_autoplay(my_run)
			reply = await _reply
		if my_run != _run:
			return
		_player_turn = false
		hud.set_input_enabled(false, "")
		if reply == "":
			GameSettings.stat_add("timeout")
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
			if id == "deodorize":
				if _smelly and not _smell_done:
					await _deodorize(speaker)
					if my_run != _run:
						return
				continue
			if id == "hat_off" or id == "mask_off":
				if _is_age_check():
					hud.show_echo(tr("あなた: "), tr("（行動: %s）") % ShopActions.label(id))
					await _uncover(speaker, id)
					if my_run != _run:
						return
				continue
			if id == "ask_other_id":
				if _is_age_check() and not _alt_id_asked:
					hud.show_echo(tr("あなた: "), tr("（行動: %s）") % ShopActions.label(id))
					await _ask_other_id(speaker)
					if my_run != _run:
						return
				continue
			if id == "age_refuse" and not _leave_resisted and not main.smoke and (randf() < LEAVE_RESIST_CHANCE or main.debug_flag("resist")):
				# ちょっとだけ粘る（要件#97）: 少し怒って言い返す。決着はせず、もう一度お願いすれば従う
				_leave_resisted = true
				main.close_machine_data()
				var shown_r: String = "sell_refuse" if _age_mode() == "konbini" else id
				hud.show_echo(tr("あなた: "), tr("（行動: %s）") % ShopActions.label(shown_r))
				log_lines.append({"role": "staff", "text": tr("（行動: %s）") % ShopActions.label(shown_r)})
				_history.append({"role": "staff", "text": tr("（行動: %s）") % ShopActions.label(shown_r)})
				_anger = clampf(_anger + 8.0, 0.0, 100.0)
				_refresh(false)
				var rl: String = _resist_line()
				log_lines.append({"role": "customer", "text": rl})
				_history.append({"role": "customer", "text": rl})
				await _customer_line(speaker, rl, "angry")
				if my_run != _run:
					return
				if not hardcore:
					hud.set_comment(tr("少し粘られた。落ち着いて、もう一度はっきりお願いしよう。"))
				continue
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
			# 筐体の前へ行って対応する（要件#99）。した対応はあとで順に判定する。時間の分だけ怒りがゆるやかに上がる
			if id == "repair_visit":
				hud.show_echo(tr("あなた: "), tr("（行動: %s）") % ShopActions.label(id))
				hud.set_status(tr("筐体の前へ行きます…"))
				var rr: Dictionary = await main.run_repair_scene(_cust)
				if my_run != _run:
					return
				_repaired = true
				var secs: float = float(rr.get("seconds", 0.0))
				_anger = clampf(_anger + secs * REPAIR_ANGER_RATE * (HARD_ANGER_MUL if hardcore else 1.0), 0.0, 99.0)
				_refresh(false)
				_queued = (rr.get("actions", []) as Array).duplicate()
				var did: String = ", ".join(PackedStringArray(_queued.map(func(a: String) -> String: return ShopActions.label(a))))
				_history.append({"role": "staff", "text": tr("（筐体の前で対応した: %s）") % (did if did != "" else tr("何もしなかった"))})
				log_lines.append({"role": "staff", "text": tr("（筐体の前で対応した: %s）") % (did if did != "" else tr("何もしなかった"))})
				if _queued.is_empty():
					hud.set_comment(tr("筐体を見に行ったが、何もしないで戻ってきた。"))
				continue
			# 台パン・大声の本人の様子を見に行って、話す（要件#99）
			if id == "go_check":
				hud.show_echo(tr("あなた: "), tr("（行動: %s）") % ShopActions.label(id))
				var nres: String = await _nuisance(speaker, my_run)
				if my_run != _run:
					return
				outcome = nres
				break
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
				# 取れるまでは「景品を取りやすい位置へ」を何回でも押せる（要件#90）。台の調整は1回まで
				var after: Array = ShopActions.buttons(_stage_id, _cust, str(cr.get("result", "")) != "won")
				hud.set_actions(_with_smell(after.filter(func(b: Array) -> bool: return str(b[0]) != ShopActions.CRANE_ADJUST)))
				_t_move_mode = str(cr.get("mode_kind", "")) == "move" or id == ShopActions.CRANE_MOVE
				# 景品を近づけたときは、お客さんはその場では遊ばない（要件#106）: 「近づけたので、もう少し頑張ってみてください」で対応を終える
				id = "crane_moved" if str(cr["result"]) == "moved" else ("crane_won" if str(cr["result"]) == "won" else "crane_lost")
				GameSettings.stat_add("crane_tests", int(cr.get("tests", 0)))
				if int(cr.get("power", 0)) >= 10 and str(cr.get("mode", "")) == "power":
					GameSettings.stat_add("crane_max_power")
				_t_crane_lost = id == "crane_lost"
				if id == "crane_moved":
					GameSettings.stat_add("crane_move_won")   # 称号「景品配置のプロ」は、近づけて対応を終えた回数（要件#106）
				if id == "crane_won":
					_crane_wins += 1
					GameSettings.stat_add("crane_won")
					if GameSettings.crane_mode == "prob" and _payout <= 10:
						GameSettings.stat_add("crane_won_p10")
					if _t_move_mode:
						GameSettings.stat_add("crane_move_won")
					var sp: Variant = _cust.get("spend", null)
					if typeof(sp) == TYPE_DICTIONARY and int((sp as Dictionary).get("actual", 0)) >= int((sp as Dictionary).get("expected", 1)):
						GameSettings.stat_add("payout_reached_won")
				if bool(cr.get("cheat", false)):
					GameSettings.stat_add("crane_cheat")
				crane_cheat = bool(cr.get("cheat", false))
				if crane_cheat:
					_cost += CHEAT_COST
			_turns += 1
			hud.show_echo(tr("あなた: "), tr("（行動: %s）") % ShopActions.label(id))
			_history.append({"role": "staff", "text": tr("（行動: %s）") % ShopActions.label(id)})
			log_lines.append({"role": "staff", "text": tr("（行動: %s）") % ShopActions.label(id)})
			hud.set_status(tr("お客さんの反応を待っています…"))
			_refresh(false)
			res = await _judge_action(id)
			if my_run != _run:
				return
			_cost += int(ACTION_COST.get(id, 0))
			_sales_cost += int(SALES_COST.get(id, 0))
			_t_last_action = id
			_act_counts[id] = int(_act_counts.get(id, 0)) + 1
			# 「景品を取りやすい位置へ」は、お客さんが本当に使った金額が目標金額の半分以上のときだけ（要件#91）
			if id in ["crane_won", "crane_lost", "crane_moved"] and _t_move_mode:
				var spd: Variant = _cust.get("spend", null)
				if typeof(spd) == TYPE_DICTIONARY and float((spd as Dictionary).get("actual", 0)) < 0.5 * float((spd as Dictionary).get("expected", 1)):
					_cost += 200
					_review -= 0.1
					GameSettings.stat_add("early_move")
					res["comment"] = tr("まだ目標金額の半分にも届いていない台を動かすのは規定外（-200 点）。")
			# 引っかかった景品を取ってあげた後の補填は要らない（そこまでに使ったお金は返さない。要件#90）
			if id == "credit" and int(_act_counts.get("crane_stuck", 0)) > 0:
				res["anger_delta"] = maxi(int(res.get("anger_delta", 0)), 8)
				res["resolve_delta"] = 0
				res["comment"] = tr("景品は取ってあげた。そこまでに使ったお金まで返す必要はない。")
			# 払い出しのレールを叩く（要件#99）: 早く直るが規定では推奨されていない。少し減点・レビューが下がる
			if id == "medal_hit":
				_cost += HIT_COST
				_review += HIT_REVIEW
				GameSettings.stat_add("rail_hit")
			# 同じ対応を2回は規定違反（要件#90）: 減点・店長の注意・レビューが下がる・お客さんは味をしめる
			if id in ONCE_ONLY and int(_act_counts[id]) >= 2:
				_cost += VIOLATION_COST
				_review += VIOLATION_REVIEW
				res["anger_delta"] = int(res.get("anger_delta", 0)) + 10
				res["resolve_delta"] = 0
				res["comment"] = tr("店長: 同じ対応を2回するのは規定違反だ！（%d 点）") % -VIOLATION_COST
				GameSettings.stat_add("violations")
				hud.show_banner(tr("規定違反"), UI.SHU)
				main.sfx.play("warn", 0.9)
			if id == "dogeza":
				GameSettings.stat_add("dogeza")
			if id == "discount":
				_t_shift["discount"] = int(_t_shift.get("discount", 0)) + 1
			if id in ["discount", "credit", "medal_return"]:
				_t_shift["freebies"] = int(_t_shift.get("freebies", 0)) + 1
			if id == "dogeza" and ShopActions.effect_kind(_cust, id) == "good":
				GameSettings.stat_add("dogeza_good")
			if id == "dogeza":
				_change_mental(-20.0)
			if crane_cheat:
				res["comment"] = str(res.get("comment", "")) + "\n" + tr("（アームは規定外の強さ…店長には内緒だ）")
		elif _is_age_check() and not _alt_id_asked and _id_seen and _wants_other_id(reply):
			# 話して別の身分証を頼んだ（要件#86）
			hud.show_echo(tr("あなた: "), reply)
			log_lines.append({"role": "staff", "text": reply})
			await _ask_other_id(speaker)
			if my_run != _run:
				return
			continue
		else:
			_turns += 1
			hud.show_echo(tr("あなた: "), reply)
			_history.append({"role": "staff", "text": reply})
			log_lines.append({"role": "staff", "text": reply})
			hud.set_status(tr("お客さんの反応を待っています…"))
			_refresh(false)
			res = await _judge(reply)
			if my_run != _run:
				return
			_track_reply(reply, int(res.get("anger_delta", 0)))
			# 臭い客に、においのことを直接言うと失礼。遠回し（換気・空調・暑さ・汗など）ならよい（要件#92）
			if _smelly and not _smell_done:
				var sm: String = _smell_talk(reply)
				if sm == "direct":
					res["anger_delta"] = maxi(int(res.get("anger_delta", 0)), 0) + 20
					res["resolve_delta"] = 0
					res["comment"] = tr("においのことを直接言うのは失礼だ。")
					GameSettings.stat_add("smell_direct")
				elif sm == "hint":
					_smell_done = true
					main.set_stink(false)
					res["anger_delta"] = int(res.get("anger_delta", 0)) - 6
					res["comment"] = tr("遠回しに伝えられた。お客さんも気づいたようだ。")
					GameSettings.stat_add("smell_hint")
					_with_smell_refresh()
			# 筐体の記録の金額や「あといくらで取れる」を言うのはダメ（要件#91）。「もう少しかもしれません」などはよい
			if typeof(_cust.get("spend", null)) == TYPE_DICTIONARY and _says_amount(reply):
				res["anger_delta"] = maxi(int(res.get("anger_delta", 0)), 0) + 10
				res["resolve_delta"] = 0
				res["comment"] = tr("記録の金額や「あといくらで取れる」は、お客さんに言わない。「もう少しかもしれません」くらいに。")
				GameSettings.stat_add("said_amount")
			_used.append(reply)

		var a_delta: int = int(res.get("anger_delta", 0))
		var r_delta: int = int(res.get("resolve_delta", 0))
		# 納得の上がり方（要件#86: 全体をやさしく。ハードコアは厳しく）
		if r_delta > 0:
			r_delta = int(round(float(r_delta) * RESOLVE_MUL * (HARD_RESOLVE_MUL if hardcore else 1.0)))
		# 景品を渡したら（引っかかった景品を取った・台の調整で取れた）、景品が目当てのお客さんはそれで納得。
		# 景品のほかにも求めている（土下座・返金など）お客さんは、大きく納得して話は続く（要件#86）
		var last_act: String = str(res.get("action", ""))
		if last_act in ["crane_stuck", "crane_won", "crane_moved"] and ShopActions.effect_kind(_cust, last_act) in ["good", "crane_won", "crane_moved"] and int(_act_counts.get(last_act, 0)) <= 1:
			if _prize_only():
				r_delta = maxi(r_delta, int(ceil(100.0 - _resolve)))
				res["customer_reply"] = Judge.line(_cust, "resolved")
			else:
				r_delta = maxi(r_delta, 60)
		# 話はほぼまとまっているのに、納得の数字だけが足りなくて終わらない（要件#106）:
		# 納得 70 以上・怒り 40 以下で、また正しい対応をしたら、そこで納得したことにする
		if r_delta > 0 and a_delta <= 0 and not bool(res.get("yielded", false)) and _resolve + float(r_delta) >= SETTLE_AT and _anger + float(a_delta) <= SETTLE_ANGER:
			r_delta = maxi(r_delta, int(ceil(100.0 - _resolve)))
		var forced_close: bool = _resolve < 100.0 and _resolve + float(r_delta) >= 100.0
		_anger = clampf(_anger + float(a_delta), 0.0, 100.0)
		_resolve = clampf(_resolve + float(r_delta), 0.0, 100.0)
		_refresh(false)
		hud.show_delta(a_delta, r_delta)
		var cm: String = str(res.get("comment", "")).strip_edges()
		if hardcore:
			cm = ""
		hud.set_comment(cm if cm != "" else (tr("（社員モード: ヒントはありません）") if hardcore else tr("落ち着いて、メモの規定どおりに。")))

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
		var line: String = str(res.get("customer_reply", "")).strip_edges()
		# AIのセリフが空のときは台本のセリフ（要件#86: お客さんの言葉が出ないことがあった）
		if line == "":
			line = Judge.line(_cust, "resolved" if outcome == "resolved" else ("explode" if outcome == "explode" else ("yielded" if outcome == "yield" else ("calm" if a_delta < 0 else ("angry" if a_delta > 0 else "neutral")))))
		# 納得で終わるのに、セリフがまだ食い下がっている（問いかけ・怒り）ときは、少しだけ強引に締めの一言を足す（要件#106）
		if outcome == "resolved" and forced_close and (a_delta > 0 or line.ends_with(char(0xFF1F)) or line.ends_with("?")):
			line += "\n" + Judge.line(_cust, "resolved")
		_history.append({"role": "customer", "text": line})
		log_lines.append({"role": "customer", "text": line})
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
		# 要注意人物はブチギレても減点なし（要件#86）
		points = 0 if _wild else SCORE_EXPLODED
		mood = "angry"
		hud.show_banner(tr("ブチギレ！") + "  %d" % points, Color("#ff8a6a"))
		main.sfx.play("explode")
		main.shake(0.25)
	# 店長を呼んだお客さんは点数半分（要件#86）。ハードコアは 1.5倍
	if _called_here and points > 0:
		points = int(float(points) * CALL_MANAGER_POINTS)
		hud.set_comment(tr("店長を呼んだので、点数は半分。"))
	if hardcore and points > 0:
		points = int(float(points) * HARD_REWARD_MUL)
	# 店員のメンタル（要件#38）
	if outcome == "resolved":
		_change_mental(8.0)
	# 行動ボタンの店の負担
	if _cost > 0:
		points -= _cost
		hud.set_comment(tr("行動の負担: -%d 点") % _cost)
	_total += points
	_track_customer(outcome)
	_results.append({"title": str(_cust.get("title", "")), "outcome": outcome, "points": points, "turns": _turns, "clock": _clock()})
	_add_sales(outcome)
	if outcome == "age_lax" and (randf() < POLICE_CHANCE or main.debug_flag("police")) and not main.smoke:
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
	# 台の問題（要件#99）: 筐体の前へ行く・迷惑なお客さんの様子を見に行く
	var pacts: Dictionary = ShopActions.problem_actions(_cust)
	if not _in_nuisance and pacts.has("go_check") and not _nuisance_done:
		_on_action("go_check")
		return
	if pacts.has("repair_visit") and not _repaired:
		_on_action("repair_visit")
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
			if GameSettings.language == "zh":
				text = "非常抱歉，我理解您的心情。请让我马上为您处理%s。（%d）" % [w, _turns]
			elif GameSettings.language == "ko":
				text = "정말 죄송합니다. 마음 충분히 이해합니다. 바로 %s 대응해 드리겠습니다. (%d)" % [w, _turns]
			elif en:
				text = "I'm so sorry, I understand. Please let me %s for you right away, sir. (%d)" % [w, _turns]
			else:
				text = "申し訳ございません。お気持ちお察しいたします。すぐに%sの対応をいたします。（%d）" % [w, _turns]
		1:
			text = "Shut up and go away" if en else ("闭嘴，快走" if GameSettings.language == "zh" else ("닥치고 꺼져" if GameSettings.language == "ko" else "うるさい、帰れ"))
		2:
			return   # 何もしない → 時間切れでブチギレ
		_:
			var ys: Array = keys.get("yield_keywords", [])
			var y: String = str(ys[0]) if not ys.is_empty() else ("for free" if en else "無料")
			text = ("Okay sir, please take %s." % y) if en else (("알겠습니다, %s 해 드릴게요." % y) if GameSettings.language == "ko" else ("分かりました、%sです。" % y))
	_on_reply(text)

# ---------------------------------------------------------------- 称号の記録（要件#79）

## 返事ひとつごとの記録（謝罪・共感・質問・メモ・くり返し・言い訳・暴言・関係ない話・タメ口）
func _track_reply(reply: String, anger_delta: int = 0) -> void:
	var f: Dictionary = Judge.flags(_cust, reply, _used)
	if reply.strip_edges().length() <= 3:
		GameSettings.stat_add("short_replies")
	var any: bool = false
	for k in ["apology", "empathy", "question", "memo", "firm", "repeat", "excuse", "rude", "offtopic"]:
		any = any or bool(f.get(k, false))
	if not any and anger_delta > 0:
		GameSettings.stat_add("miss_replies")
	# 謝るだけ（共感・質問・メモの中身・はっきり断るが無い）で、怒りが下がらなかった
	if bool(f.get("apology", false)) and anger_delta >= 0 and not (bool(f.get("empathy", false)) or bool(f.get("question", false)) or bool(f.get("memo", false)) or bool(f.get("firm", false))):
		GameSettings.stat_add("only_sorry_replies")
	for k in [["apology", "apology_replies"], ["empathy", "empathy_replies"], ["question", "question_replies"], ["memo", "memo_replies"],
			["repeat", "repeat_replies"], ["excuse", "excuse_replies"], ["rude", "rude_replies"], ["offtopic", "offtopic_replies"]]:
		if bool(f.get(k[0], false)):
			GameSettings.stat_add(str(k[1]))
	if bool(f.get("firm", false)):
		_t_firm = true
	if bool(f.get("casual", false)) or bool(f.get("rude", false)):
		_t_shift["impolite"] = true


## お客さん1人の結果の記録
func _track_customer(outcome: String) -> void:
	match outcome:
		"resolved":
			GameSettings.stat_add("resolved")
			GameSettings.stat_add("resolved_" + _stage_id)
			var ja: String = Titles.ja_title(_stage_id, _cust)
			if ja != "":
				GameSettings.stat_add("res:" + ja)
			if _turns <= 1:
				GameSettings.stat_add("one_turn_resolve")
			if _t_peak <= 20.0:
				GameSettings.stat_add("calm_resolve")
			if _t_peak >= 90.0:
				GameSettings.stat_add("clutch_resolve")
			if _t_firm:
				GameSettings.stat_add("firm_resolve")
			var m: String = Scenarios.machine_of(_cust)
			if m in ["medal", "rhythm", "video"]:
				GameSettings.stat_add("resolved_" + m)
			if _t_last_action == "crane_stuck":
				GameSettings.stat_add("stuck_resolved")
			if _wild:
				GameSettings.stat_add("wild_resolved")
			if bool(_cust.get("rare", false)):
				GameSettings.stat_add("rare_resolved")
			if bool(_cust.get("_lie", false)) and _data_seen:
				GameSettings.stat_add("lie_caught")
				GameSettings.stat_list_add("lie_langs", GameSettings.language)
			if _clock() >= 23 * 60:
				GameSettings.stat_add("late_resolved")
		"explode":
			GameSettings.stat_add("explode")
			var jx: String = Titles.ja_title(_stage_id, _cust)
			if jx != "":
				GameSettings.stat_add("exp:" + jx)
			if _t_crane_lost:
				GameSettings.stat_add("crane_lost_explode")
			if _t_manager_here:
				GameSettings.stat_add("manager_then_explode")
		"yield":
			GameSettings.stat_add("yield")
			var jy: String = Titles.ja_title(_stage_id, _cust)
			if jy != "":
				GameSettings.stat_add("yld:" + jy)
		"breakdown":
			GameSettings.stat_add("breakdown")
		"age_ok", "age_refused":
			var ag: Dictionary = _cust.get("age", {})
			GameSettings.stat_add("age_correct")
			_t_shift["age_ok"] = int(_t_shift.get("age_ok", 0)) + 1
			if str(ag.get("mode", "")) == "konbini":
				GameSettings.stat_add("age_konbini_correct")
			if int(ag.get("clock", 0)) >= 22 * 60:
				GameSettings.stat_add("age_night_correct")
			if outcome == "age_refused" and str(ag.get("type", "")) == "commuter":
				GameSettings.stat_add("age_commuter_refused")
			if outcome == "age_refused" and not bool(ag.get("face_match", true)):
				GameSettings.stat_add("age_borrowed_caught")
		"age_wrong":
			GameSettings.stat_add("age_wrong")
	# 年齢確認の連続正解（間違い・ゆるい確認で途切れる）
	if outcome in ["age_ok", "age_refused"]:
		GameSettings.stat_add("age_streak")
		GameSettings.stat_max("age_streak_max", GameSettings.stat("age_streak"))
	elif outcome in ["age_wrong", "age_lax"]:
		GameSettings.stats["age_streak"] = 0
	if outcome == "age_refused":
		_t_shift["age_refused"] = int(_t_shift.get("age_refused", 0)) + 1
	# 1シフトの全員が「怒り20以下」「1回目の返事」で納得（パーフェクトのときに見る）
	if outcome in ["resolved", "age_ok", "age_refused"]:
		if _t_peak <= 20.0:
			_t_shift["calm_n"] = int(_t_shift.get("calm_n", 0)) + 1
		if _turns <= 1:
			_t_shift["oneturn_n"] = int(_t_shift.get("oneturn_n", 0)) + 1
	# 22時以降のお客さんの連続（屈服・ブチギレ・早退・帰ってしまう で途切れる）
	if _clock() >= 22 * 60:
		if outcome in ["resolved", "age_ok", "age_refused"]:
			GameSettings.stat_add("night_streak")
			GameSettings.stat_max("night_streak_max", GameSettings.stat("night_streak"))
		else:
			GameSettings.stats["night_streak"] = 0
	if _is_age_check():
		_t_shift["age_total"] = int(_t_shift.get("age_total", 0)) + 1


## シフト1回の記録（最後まで勤めたときだけ数えるものもある）
func _track_shift(review: float) -> void:
	var count: Dictionary = {}
	for r in _results:
		var o: String = str((r as Dictionary).get("outcome", ""))
		count[o] = int(count.get(o, 0)) + 1
	var completed: bool = not _suspended and _results.size() >= CUSTOMERS_PER_SHIFT and int(count.get("breakdown", 0)) == 0
	var resolved: int = int(count.get("resolved", 0)) + int(count.get("age_ok", 0)) + int(count.get("age_refused", 0))
	if completed:
		GameSettings.stat_add("shifts")
		GameSettings.stat_add("shifts_" + _stage_id)
		GameSettings.stat_lang(GameSettings.language)
		if GameSettings.language != "ja":
			GameSettings.stat_add("shift_foreign")
		if int(count.get("yield", 0)) == 0:
			GameSettings.stat_add("no_yield_shift")
		if not bool(_t_shift.get("impolite", false)):
			GameSettings.stat_add("polite_shift")
		if float(_t_shift.get("mental_min", MENTAL_MAX)) <= 10.0:
			GameSettings.stat_add("low_mental_finish")
		if _stage_id == "arcade" and GameSettings.crane_mode == "prob":
			GameSettings.stat_add("prob_shifts")
			if _payout >= 60:
				GameSettings.stat_add("payout60_shift")
			if _payout <= 10:
				GameSettings.stat_add("payout10_shift")
		if int(_t_shift.get("age_total", 0)) >= 2 and int(_t_shift.get("age_ok", 0)) >= int(_t_shift.get("age_total", 0)):
			GameSettings.stat_add("age_double_clean")
			if int(_t_shift.get("age_refused", 0)) >= 2:
				GameSettings.stat_add("age_double_refused")
		if bool(_t_shift.get("wild", false)) and bool(_t_shift.get("spend", false)):
			GameSettings.stat_add("wild_and_spend_shift")
		if not bool(_t_shift.get("mental_lost", false)):
			GameSettings.stat_add("no_mental_loss_shift")
		if GameSettings.mental_rank() >= 20:
			GameSettings.stat_add("shifts_after_r20")
		if int(count.get("yield", 0)) == 0:
			GameSettings.stat_add("no_yield_streak")
			GameSettings.stat_max("no_yield_streak_max", GameSettings.stat("no_yield_streak"))
		else:
			GameSettings.stats["no_yield_streak"] = 0
		if _stage_id == "arcade" and GameSettings.crane_mode == "prob" and _payout % 10 == 0:
			GameSettings.stat_list_add("payouts", str(_payout))
	var perfect: bool = completed and resolved >= CUSTOMERS_PER_SHIFT
	if perfect:
		GameSettings.stat_add("perfect_shift")
		GameSettings.stat_add("perfect_streak")
		GameSettings.stat_max("perfect_streak_max", GameSettings.stat("perfect_streak"))
		if not bool(_t_shift.get("manager", false)):
			GameSettings.stat_add("perfect_no_manager")
		if int(_t_shift.get("calm_n", 0)) >= CUSTOMERS_PER_SHIFT:
			GameSettings.stat_add("calm_perfect_shift")
		if int(_t_shift.get("oneturn_n", 0)) >= CUSTOMERS_PER_SHIFT:
			GameSettings.stat_add("oneturn_perfect_shift")
		if int(_t_shift.get("age_total", 0)) >= 2:
			GameSettings.stat_add("perfect_night")
	else:
		GameSettings.stats["perfect_streak"] = 0
	if int(count.get("explode", 0)) >= CUSTOMERS_PER_SHIFT:
		GameSettings.stat_add("all_explode_shift")
	if int(_t_shift.get("discount", 0)) >= 3:
		GameSettings.stat_add("discount3_shift")
	if int(_t_shift.get("freebies", 0)) >= 4:
		GameSettings.stat_add("freebies4_shift")
	if review <= 1.0:
		GameSettings.stat_add("review1_shift")
	if review >= 5.0:
		GameSettings.stat_add("review5_shift")
	GameSettings.stat_max("max_sales", _sales)

