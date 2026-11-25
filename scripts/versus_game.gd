extends Node
## 対戦モード（客役 vs 店員役）のクライアント側。進行・判定・時間・レーティングはすべてサーバーが決める。
## ここはサーバーからのメッセージ（docs/SERVER.md）を画面に映し、入力（文字・声）を送るだけ。
##
## 遊び方の種類:
##   ランクマッチ: レーティングが近い人と組む（待つほど範囲が広がる）。レーティングが動く
##   フレンド対戦: 部屋コードを共有した相手とだけ遊ぶ。レーティングは動かない
## 形式: "text"（文字で返す）/ "voice"（押して話す。相手に声が届き、サーバーが文字起こしして判定）

const UI = preload("res://scripts/ui_kit.gd")
const VoiceScript = preload("res://scripts/voice.gd")
const Scenarios = preload("res://scripts/scenarios.gd")
const ShopActions = preload("res://scripts/shop_actions.gd")
const EosScript = preload("res://scripts/eos_matchmaker.gd")
const Titles = preload("res://scripts/titles.gd")
const Shop = preload("res://scripts/shop.gd")

## サーバーのエラーコード → 画面の言葉（サーバーの文は日本語だけなので、ここで訳す）
const ERROR_TEXT: Dictionary = {
	"maintenance": "メンテナンス中のため、対戦はお休みしています。1人用は遊べます",
	"consent_required": "対戦の前に、発言の取り扱いへの同意が必要です",
	"versus_banned": "対戦の利用を停止されています",
	"banned": "このアカウントは利用停止中です",
	"bad_format": "対戦の形式（文字・音声）が正しくありません",
	"voice_unavailable": "このサーバーは音声対戦に対応していません",
	"busy": "もう相手を探しているか、部屋で待っています。先に「探すのをやめる」を押してください",
	"ranked_rooms_disabled": "このサーバーでは、部屋でのランクマッチは使えません",
	"room_not_found": "その部屋コードは見つかりません。コードを確かめるか、相手に作り直してもらってください",
	"own_room": "自分の部屋には参加できません",
	"same_network": "同じ回線のプレイヤーどうしでは、ランクマッチはできません",
	"rating_gap": "レーティングの差が大きすぎるため、このランクマッチには入れません",
	"unauthorized": "ログイン情報が無効です",
	"server_closed": "そのサーバーは今お休み中です。別のサーバーを選んでください",
}

signal lobby_event(kind: String, data: Dictionary)   # ロビー画面向け: queued / queue_status / room_created / error / cancelled
signal finished(summary: Dictionary)

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
var api = null
var voice = null
var eos = null           # Epic Online Services のマッチング（入っていなければ使わない）
var _eos_flow: String = ""   # "" | "ranked" | "invite": EOS 経由で部屋を作ろうとしている
var paused: bool = false

var state: String = "idle"   # idle | connecting | queued | room | match
var _pending: Dictionary = {}
var _match: Dictionary = {}
var _role: String = ""
var _card: Dictionary = {}
var _anger: float = 0.0
var _resolve: float = 0.0
var _rate: float = 0.0
var _phase: String = ""
var _grace_left: float = 0.0   # 音声の店員の番で、怒りが上がりはじめるまでの秒
var _my_turn: bool = false
var _seconds_left: float = -1.0
var _totals: Dictionary = {"you": 0, "opponent": 0}
var _round: int = 0
var _rounds: int = 2
var _smoke_n: int = 0


## 通報する相手と試合（要件#87）
func report_target() -> Dictionary:
	var op: Dictionary = _match.get("opponent", {}) if typeof(_match.get("opponent", null)) == TYPE_DICTIONARY else {}
	return {"player_id": str(op.get("id", "")), "name": str(op.get("name", "")), "match_id": str(_match.get("match_id", ""))}


func setup(main_node, hud_node, api_node) -> void:
	main = main_node
	hud = hud_node
	api = api_node
	voice = VoiceScript.new()
	add_child(voice)
	voice.level_changed.connect(func(v: float) -> void:
		if hud != null and is_instance_valid(hud):
			hud.set_voice_level(v))
	voice.auto_stopped.connect(_on_voice_stop)
	api.message.connect(_on_message)
	eos = EosScript.new()
	add_child(eos)
	eos.status.connect(func(t: String) -> void: lobby_event.emit("status", {"text": t}))
	eos.need_room.connect(_on_eos_need_room)
	eos.room_found.connect(func(code: String) -> void:
		_eos_flow = ""
		request("room_join", _eos_format, code))
	eos.failed.connect(_on_eos_failed)
	attach_hud(hud_node)


## 画面（HUD）を作り直したときに付け替える
func attach_hud(hud_node) -> void:
	hud = hud_node
	hud.reply_submitted.connect(_on_text)
	hud.action_pressed.connect(_on_action)
	hud.voice_start.connect(_on_voice_start)
	hud.voice_stop.connect(_on_voice_stop)


func is_active() -> bool:
	return state == "match"


func is_busy() -> bool:
	return state != "idle"


# ---------------------------------------------------------------- ロビーからの操作

var _eos_format: String = "text"


## EOS（Epic のロビー・フレンド招待）が使えるか
func eos_available() -> bool:
	return eos != null and eos.available()


## Epic のロビーで相手を探す（ランク）。だめならゲームサーバーのマッチングに切り替える
func request_eos(kind: String, format: String) -> void:
	if not eos_available():
		request("queue" if kind == "ranked" else "room_create", format)
		return
	_eos_format = format
	_eos_flow = kind
	state = "connecting"
	var me: Dictionary = await api.ensure_login()
	if me.has("error"):
		state = "idle"
		_eos_flow = ""
		lobby_event.emit("error", {"message": str(me["error"])})
		return
	var p: Dictionary = GameSettings.last_profile
	var rating: int = int(p.get("rating", 1000))
	var pname: String = str(p.get("name", GameSettings.player_name))
	if kind == "ranked":
		eos.find_match(GameSettings.language, format, rating, pname)
	else:
		eos.invite_friend(GameSettings.language, format, rating, pname)


func _on_eos_need_room(ranked: bool) -> void:
	_pending = {"t": "room_create", "format": _eos_format, "code": "", "ranked": ranked, "eos_lobby": eos.lobby_id()}
	if api.is_open():
		_send_pending()
	else:
		api.open_socket()


func _on_eos_failed(message: String) -> void:
	lobby_event.emit("status", {"text": message})
	var flow: String = _eos_flow
	_eos_flow = ""
	eos.leave()
	if state == "match":
		return
	state = "idle"
	# ランクはゲームサーバーのマッチングで続ける。招待は部屋コードで
	if flow == "ranked":
		request("queue", _eos_format)
	elif flow == "invite":
		request("room_create", _eos_format)

## 対戦の接続サーバー（要件#132）。空なら自分の言語のサーバー
static func vs_server() -> String:
	var s: String = GameSettings.vs_server
	return s if s in ["ja", "en", "zh", "ko", "global"] else GameSettings.language


## 翻訳モード（グローバルサーバーのときだけ）
static func vs_translate() -> bool:
	return vs_server() == "global" and GameSettings.vs_translate


## kind: "queue" | "room_create" | "room_join"
func request(kind: String, format: String, code: String = "") -> void:
	_pending = {"t": kind, "format": format, "code": code}
	state = "connecting"
	lobby_event.emit("status", {"text": tr("サーバーに接続しています…")})
	var me: Dictionary = await api.ensure_login()
	if me.has("error"):
		state = "idle"
		lobby_event.emit("error", {"message": str(me["error"])})
		return
	if api.is_open():
		_send_pending()
	else:
		api.open_socket()


func cancel() -> void:
	# 状態に関係なく、試合中でなければサーバーに「やめる」を送る（サーバー側の待ちが残らないように）
	if state != "match" and api.is_open():
		api.send({"t": "cancel"})
	if eos != null:
		eos.cancel()
	_eos_flow = ""
	state = "idle"
	_pending = {}


func leave_match() -> void:
	voice.release_mic()
	if state == "match":
		api.send({"t": "leave"})


func _send_pending() -> void:
	if _pending.is_empty():
		return
	api.send({"t": "lang", "lang": GameSettings.language})
	var p: Dictionary = _pending
	_pending = {}
	match str(p["t"]):
		"queue":
			api.send({"t": "queue", "format": p["format"], "server": vs_server(), "translate": vs_translate()})
		"room_create":
			var m: Dictionary = {"t": "room_create", "format": p["format"], "answer_time": GameSettings.answer_time,
				"server": vs_server(), "translate": vs_translate()}
			if bool(p.get("ranked", false)):
				m["ranked"] = true
			if str(p.get("eos_lobby", "")) != "":
				m["eos_lobby"] = str(p["eos_lobby"])
			api.send(m)
		"room_join":
			api.send({"t": "room_join", "code": p["code"], "translate": vs_translate()})


# ---------------------------------------------------------------- サーバーからのメッセージ

func _on_message(msg: Dictionary) -> void:
	var t: String = str(msg.get("t", ""))
	match t:
		"hello":
			if bool(msg.get("resumed", false)):
				hud.set_status(tr("つなぎ直しました"))
			elif state == "match":
				# 待ち時間を過ぎてから戻った: サーバーではもう試合が終わっている
				_on_match_end({"result": "lose", "reason": "disconnected", "kind": str(_match.get("kind", "")),
					"you_points": int(_totals.get("you", 0)), "opponent_points": int(_totals.get("opponent", 0))})
			elif _pending.is_empty() and (state == "queued" or state == "room"):
				# 待っている間に切れた: サーバーの待ちは消えているので、やり直してもらう
				state = "idle"
				lobby_event.emit("error", {"message": tr("接続が切れたため、待つのをやめました。もう一度押してください")})
			else:
				_send_pending()
		"queued":
			state = "queued"
			lobby_event.emit("queued", msg)
		"queue_status":
			lobby_event.emit("queue_status", msg)
		"room_created":
			state = "room"
			if _eos_flow != "":
				eos.set_room_code(str(msg.get("code", "")))
			lobby_event.emit("room_created", msg)
		"room_expired":
			state = "idle"
			lobby_event.emit("error", {"message": tr("部屋の期限が切れました。作り直してください")})
		"cancelled":
			lobby_event.emit("cancelled", msg)
		"error":
			var code: String = str(msg.get("code", ""))
			# busy は「もう待っている」なので、状態は変えない（やめるボタンで cancel が届くように）
			if state != "match" and code != "busy":
				state = "idle"
			var shown: Dictionary = msg.duplicate()
			if ERROR_TEXT.has(code):
				shown["message"] = tr(str(ERROR_TEXT[code]))
				# 運営が書いた理由・お知らせは、どの言語でも添える（要件#109: 日本語のときだけだと、予定や理由が伝わらなかった）
				if code in ["maintenance", "versus_banned", "banned"] and str(msg.get("message", "")) != "":
					var own: String = str(msg.get("message", ""))
					shown["message"] = own if GameSettings.language == "ja" else (str(shown["message"]) + "\n" + tr("運営より: ") + own)
			lobby_event.emit("error", shown)
			# 同意がない（取り消した・別のPCで遊んだなど）: 同意の画面を出す（要件#101）
			if code == "consent_required" and not main.smoke:
				GameSettings.vs_consent = 0
				main.call("show_vs_consent", Callable(main, "_show_versus_lobby"))
			if _eos_flow != "" and state != "match":
				_on_eos_failed(shown.get("message", ""))
		"match_found":
			_eos_voice_joined = false
			_on_match_found(msg)
		"round_start":
			_on_round_start(msg)
		"phase":
			_on_phase(msg)
		"line":
			_on_line(msg)
		"line_tr", "judged_tr", "card_tr":
			_on_translated(t, msg)
		"eos_voice":
			_join_eos_voice(str(msg.get("lobby_id", "")))
		"voice_mode":
			_voice_mode = str(msg.get("mode", "relay"))
			if _voice_mode == "eos":
				hud.set_comment(tr("声は Epic のボイスで相手に届きます。"))
		"voice":
			var secs: float = voice.play_base64(str(msg.get("audio", "")))
			if secs > 0.0:
				hud.set_status(tr("相手の声: %.1f 秒") % secs)
				# 相手の声が聞こえる間は BGM を小さく（要件#109）
				main.bgm.duck(0.25)
				get_tree().create_timer(secs + 0.2).timeout.connect(func() -> void: main.bgm.duck(1.0))
		"judged":
			_on_judged(msg)
		"round_end":
			_on_round_end(msg)
		"match_end":
			_on_match_end(msg)
		"opponent_status":
			if bool(msg.get("connected", true)):
				hud.set_comment(tr("相手がつなぎ直しました。"))
			else:
				hud.set_comment(tr("相手の接続が切れました。%d 秒待って戻らなければ、あなたの勝ちです。") % int(msg.get("grace_seconds", 20)))
		"notice":
			hud.set_comment(str(msg.get("text", "")))
		"warning":
			# 不適切な発言の警告（要件#88）
			hud.show_banner(tr("警告"), UI.SHU)
			hud.set_comment(str(msg.get("text", "")))
			main.sfx.play("warn", 0.8)
			main.shake(0.15)
		_:
			pass


func _who(by: String) -> String:
	return tr("あなた") if by == "you" else Shop.display_name(str((_match.get("opponent", {}) as Dictionary).get("name", tr("相手"))))


func _on_match_found(msg: Dictionary) -> void:
	var resumed: bool = state == "match"
	state = "match"
	_match = msg
	_eos_flow = ""
	if eos != null:
		eos.leave()
	var stage: String = str(msg.get("stage", "konbini"))
	_rounds = int(msg.get("rounds", 2))
	if not resumed:
		main.enter_versus(stage)
		hud.clear_round()
		var op: Dictionary = msg.get("opponent", {})
		var kind_label: String = tr("ランクマッチ") if str(msg.get("kind", "")) == "ranked" else tr("フレンド対戦")
		hud.set_top(tr(str(STAGE_NAMES.get(stage, ""))), kind_label, "")
		var op_title: Dictionary = Titles.by_id(str(op.get("title", "")))
		var op_name: String = Shop.display_name(str(op.get("name", "")))
		if not op_title.is_empty():
			op_name = tr("「%s」") % Titles.title_name(op_title) + op_name
		hud.set_comment(tr("対戦相手: %s（%s・%d）") % [op_name, str(op.get("rank", "")), int(op.get("rating", 0))])
		main.show_opponent_tag(op)
		# 通報ボタン（要件#87。ブロックはない）
		hud.set_tools([["report", tr("通報")]])
		hud.show_banner(tr("対戦開始！"), UI.POP)
		main.sfx.play("door")
	var voice_format: bool = str(msg.get("format", "text")) == "voice"
	hud.set_voice_mode(voice_format)
	if voice_format and not voice.available():
		hud.set_voice_mode(false)
		hud.set_comment(tr("マイクが見つからないので、文字で入力します。"))
	# 声は EOS のボイスで相手に届ける（要件#100）。部屋は席 0 が作る。だめならゲームサーバーの中継のまま
	if voice_format and not resumed and bool(msg.get("voice_host", false)):
		_start_eos_voice_host()


func _on_round_start(msg: Dictionary) -> void:
	_round = int(msg.get("round", 0))
	_role = str(msg.get("role", "staff"))
	_card = msg.get("card", {}) if typeof(msg.get("card", null)) == TYPE_DICTIONARY else {}
	_anger = float(msg.get("anger", 40.0))
	_resolve = float(msg.get("resolve", 0.0))
	_rate = 0.0
	_phase = ""
	_my_turn = false
	var tot: Variant = msg.get("totals", {})
	if typeof(tot) == TYPE_DICTIONARY:
		_totals = tot
	hud.clear_round()
	_update_top()
	if _role == "staff":
		hud.set_quick_phrases(hud.DEFAULT_PHRASES)
		hud.set_actions(ShopActions.buttons(str(_match.get("stage", "konbini")), _card, false))
		hud.set_memo(str(_card.get("title", "")), str(_card.get("memo", "")), str(_card.get("demand", "")))
		hud.set_comment(tr("あなたは店員役。怒りを100にせず、納得を100にすれば勝ち。"))
		hud.show_banner(tr("あなたは店員役"), UI.LCD_ON)
	else:
		hud.set_quick_phrases(CUSTOMER_PHRASES)
		hud.set_actions([])
		hud.set_memo(tr("あなたの役: ") + str(_card.get("title", "")), str(_card.get("memo", "")), str(_card.get("demand", "")))
		hud.set_comment(tr("あなたは客役。怒りを100にするか、店員に不当な要求を飲ませれば勝ち。暴言・無言・くり返しは逆効果。"))
		hud.show_banner(tr("あなたは客役"), Color("#ff8a6a"))
	hud.set_gauges(_anger, _resolve, -1.0)
	main.display_anger = _anger
	var look: Dictionary = _card.get("look", {}) if typeof(_card.get("look", null)) == TYPE_DICTIONARY else {}
	# 対戦のキャラクター（要件#84）: 客役は私服、店員役は制服。作っていない人は台本の見た目・ふつうの店員
	var op_av: Variant = (_match.get("opponent", {}) as Dictionary).get("avatar", null)
	if _role == "staff":
		main.free_staff()
		main.set_customer_view(false)
		if typeof(op_av) == TYPE_DICTIONARY:
			look = Shop.avatar_look(op_av, "casual")
		main.spawn_customer(look)
	else:
		if Shop.avatar_created():
			look = Shop.avatar_look(Shop.avatar_dict(), "casual")
		main.spawn_staff(Shop.avatar_look(op_av if typeof(op_av) == TYPE_DICTIONARY else {}, "uniform"))
		main.set_customer_view(true)
		main.spawn_customer(look)


func _update_top() -> void:
	hud.set_top(tr(str(STAGE_NAMES.get(str(_match.get("stage", "")), ""))),
		tr("ラウンド %d / %d") % [_round + 1, _rounds],
		tr("あなた %d ― 相手 %d") % [int(_totals.get("you", 0)), int(_totals.get("opponent", 0))])


func _on_phase(msg: Dictionary) -> void:
	_phase = str(msg.get("phase", ""))
	_my_turn = str(msg.get("turn", "")) == "you"
	_anger = float(msg.get("anger", _anger))
	_resolve = float(msg.get("resolve", _resolve))
	_rate = float(msg.get("rate", 0.0))
	var elapsed: float = float(msg.get("elapsed", 0.0))
	_seconds_left = maxf(0.0, float(msg.get("seconds", 0.0)) - elapsed)
	# 音声の店員の番は、はじめの数秒（grace）は怒りが上がらない（サーバーと同じ。レビュー2-2）
	var grace: float = float(msg.get("grace", 0.0))
	_grace_left = maxf(0.0, grace - elapsed)
	if _phase == "staff_turn":
		_anger = minf(100.0, _anger + _rate * maxf(0.0, elapsed - grace))
	var can_input: bool = _my_turn and (_phase == "customer_turn" or _phase == "staff_turn")
	if can_input:
		if _phase == "staff_turn":
			hud.set_input_enabled(true, tr("ここに返事を書く…"))
		else:
			hud.set_input_enabled(true, tr("お客さんとして言い返す…"))
		main.sfx.play("warn", 1.3)
	else:
		hud.set_input_enabled(false, "")
		if voice.is_recording():
			voice.cancel_recording()
	_update_status()
	_refresh()
	if main.smoke and can_input:
		_smoke_autoplay()


func _update_status() -> void:
	var s: String = ""
	match _phase:
		"customer_turn":
			s = tr("あなたの番（客役）: 店員を追い詰めよう　残り %d 秒") if _my_turn else tr("相手（客役）がセリフを考えています…　残り %d 秒")
			s = s % int(ceil(_seconds_left))
		"staff_turn":
			s = tr("あなたの番（店員役）: キレられる前に返事を") if _my_turn else tr("相手（店員役）が返事を考えています… 怒りが上がっていく")
		"judging":
			s = tr("店長が判定しています…")
		"intro":
			s = tr("まもなく開始…")
		_:
			s = ""
	hud.set_status(s)


func _process(delta: float) -> void:
	if state != "match":
		return
	if _phase == "staff_turn":
		var d: float = delta
		if _grace_left > 0.0:
			d = maxf(0.0, delta - _grace_left)
			_grace_left = maxf(0.0, _grace_left - delta)
		_anger = minf(100.0, _anger + _rate * d)
		_refresh()
	elif _phase == "customer_turn" and _seconds_left > 0.0:
		var before: int = int(ceil(_seconds_left))
		_seconds_left = maxf(0.0, _seconds_left - delta)
		if int(ceil(_seconds_left)) != before:
			_update_status()


func _refresh() -> void:
	var left: float = -1.0
	if _phase == "staff_turn" and _rate > 0.0:
		left = (100.0 - _anger) / _rate + _grace_left
	hud.set_gauges(_anger, _resolve, left)
	main.display_anger = _anger


## 訳を待っているセリフ（seq → line のメッセージ。グローバルの翻訳モード。要件#132）
var _lines_by_seq: Dictionary = {}


func _on_translated(t: String, msg: Dictionary) -> void:
	var seq: int = int(msg.get("seq", -1))
	match t:
		"line_tr":
			if not _lines_by_seq.has(seq):
				return
			var orig: Dictionary = _lines_by_seq[seq]
			_lines_by_seq.erase(seq)
			var m: Dictionary = orig.duplicate()
			m["text"] = str(msg.get("text", ""))
			m["translated"] = true
			_on_line(m)
		"judged_tr":
			var c: String = str(msg.get("comment", msg.get("text", "")))
			if c != "":
				hud.set_comment(c)
		"card_tr":
			if seq != _round:
				return
			for k in ["title", "memo", "demand", "opening"]:
				var v: String = str(msg.get(k, ""))
				if v != "":
					_card[k] = v
			if _role == "staff":
				hud.set_memo(str(_card.get("title", "")), str(_card.get("memo", "")), str(_card.get("demand", "")))
			else:
				hud.set_memo(tr("あなたの役: ") + str(_card.get("title", "")), str(_card.get("memo", "")), str(_card.get("demand", "")))


func _on_line(msg: Dictionary) -> void:
	var role: String = str(msg.get("role", ""))
	var text: String = str(msg.get("text", ""))
	var by: String = str(msg.get("by", ""))
	var mark: String = tr("（声）") if str(msg.get("via", "")) == "voice" else ""
	if bool(msg.get("translated", false)):
		mark += tr("（訳）")
	elif by != "you" and vs_translate() and msg.has("seq"):
		_lines_by_seq[int(msg["seq"])] = msg
		if _lines_by_seq.size() > 40:
			_lines_by_seq.erase(_lines_by_seq.keys()[0])
	if role == "customer":
		var speaker: String = "%s（%s）%s" % [str(_card.get("title", tr("お客さん"))), _who(by), mark]
		# お客さん役のプレイヤーの吹き出し（ショップで買ったもの。要件#107）
		var bub: String = str(Shop.tag_dict().get("bubble", ""))
		if by != "you":
			var op_tag: Variant = (_match.get("opponent", {}) as Dictionary).get("tag", null)
			bub = str((op_tag as Dictionary).get("bubble", "")) if typeof(op_tag) == TYPE_DICTIONARY else ""
		main.customer_say(speaker, text, _anger >= 70.0, Shop.bubble_skin(bub))
	else:
		hud.show_echo(tr("店員（%s）: ") % _who(by), text)
		main.staff_talk(clampf(float(text.length()) * 0.08, 0.8, 3.0))


func _on_judged(msg: Dictionary) -> void:
	_anger = float(msg.get("anger", _anger))
	_resolve = float(msg.get("resolve", _resolve))
	_phase = ""
	_refresh()
	var a: int = int(msg.get("anger_delta", 0))
	var r: int = int(msg.get("resolve_delta", 0))
	hud.show_delta(a, r)
	hud.set_comment(str(msg.get("comment", "")))
	if a < 0:
		main.customer_react("calm")
		main.sfx.play("good", 1.2)
	elif a > 0:
		main.customer_react("angry")
		main.sfx.play("bad")


func _on_round_end(msg: Dictionary) -> void:
	_phase = ""
	hud.set_input_enabled(false, "")
	hud.set_status("")
	var tot: Variant = msg.get("totals", {})
	if typeof(tot) == TYPE_DICTIONARY:
		_totals = tot
	_update_top()
	var outcome: String = str(msg.get("outcome", ""))
	var won: bool = str(msg.get("winner", "")) == "you"
	# 称号の記録（要件#79）: 役ごとのラウンドの勝ち
	if won:
		GameSettings.stat_add("vs_staff_rounds" if _role == "staff" else "vs_customer_rounds")
		if _role != "staff" and bool(msg.get("timeout", false)):
			GameSettings.stat_add("vs_silent_wins")
	var what: String = tr("納得して帰った")
	var mood: String = "happy"
	if outcome == "explode":
		what = tr("ブチギレた")
		mood = "angry"
		main.customer_react("explode")
		main.shake(0.25)
	elif outcome == "yield":
		what = tr("店員が要求を飲んだ")
		mood = "smug"
		main.customer_react("smug")
	else:
		main.customer_react("happy")
	hud.show_banner("%s\n%s +%d" % [what, tr("あなたの勝ち") if won else tr("相手の勝ち"), int(msg.get("points", 0))], UI.LCD_ON if won else Color("#ff8a6a"))
	main.sfx.play("win" if won else "lose")
	_leave_later(mood)


func _leave_later(mood: String) -> void:
	await get_tree().create_timer(2.6).timeout
	if state != "match":
		return
	hud.hide_bubble()
	main.dismiss_customer(mood)
	main.display_anger = 0.0


func _on_match_end(msg: Dictionary) -> void:
	voice.release_mic()
	_voice_mode = "relay"
	_eos_voice_joined = false
	if eos != null:
		eos.voice_leave()
	main.free_staff()
	main.set_customer_view(false)
	# 称号の記録（要件#79）
	GameSettings.stat_add("vs_matches")
	if str(_match.get("format", "")) == "voice":
		GameSettings.stat_add("vs_voice")
	if str(msg.get("result", "")) == "win":
		GameSettings.stat_add("vs_wins")
		GameSettings.stat_add("vs_streak")
		GameSettings.stat_max("vs_streak_max", GameSettings.stat("vs_streak"))
	else:
		GameSettings.stats["vs_streak"] = 0
	var pl: Variant = msg.get("player", null)
	if typeof(pl) == TYPE_DICTIONARY:
		GameSettings.last_profile = pl
	# 給与（要件#82）: 対戦は CUS
	msg["pay_kas"] = Shop.pay_versus(str(msg.get("result", "")) == "win")
	msg["new_titles"] = Titles.check()
	GameSettings.save_settings()
	state = "idle"
	_phase = ""
	hud.set_input_enabled(false, "")
	if voice.is_recording():
		voice.cancel_recording()
	finished.emit(msg)


# ---------------------------------------------------------------- 入力

## 店員役が店の行動ボタンを押した（効果はサーバーが表どおりに決める）
func _on_action(id: String) -> void:
	# 筐体のデータは見るだけ（要件#57）
	if id == ShopActions.MACHINE_DATA:
		if state == "match" and main.mode == "versus":
			main.show_machine_data(_card, false)
		return
	if state != "match" or not _my_turn or _phase != "staff_turn" or main.mode != "versus":
		return
	_my_turn = false
	api.send({"t": "act", "id": id})
	hud.set_status(tr("送りました…"))


func _on_text(text: String) -> void:
	if state != "match" or not _my_turn or main.mode != "versus":
		return
	_my_turn = false
	api.send({"t": "say", "text": text})
	hud.set_status(tr("送りました…"))


# ---------------------------------------------------------------- EOS のボイス（要件#100）
var _voice_mode: String = "relay"   # "eos" のとき、声は EOS で相手に届き、サーバーは中継しない
var _eos_voice_joined: bool = false


func _eos_ok() -> bool:
	return eos != null and eos.available() and not main.smoke


func _start_eos_voice_host() -> void:
	if not _eos_ok():
		return
	var id: String = await eos.voice_host(GameSettings.player_name)
	if id == "" or state != "match":
		return
	api.send({"t": "eos_voice", "lobby_id": id})
	var ok: bool = await eos.voice_wait_connected(15.0)
	if state == "match":
		api.send({"t": "eos_voice_ready", "ok": ok})


func _join_eos_voice(lobby_id: String) -> void:
	# 1試合に1回だけ（要件#108: 何度も別の部屋に入らせられないように）
	if not _eos_ok() or _eos_voice_joined:
		return
	_eos_voice_joined = true
	var ok: bool = await eos.voice_join(lobby_id, GameSettings.player_name)
	if ok:
		ok = await eos.voice_wait_connected(15.0)
	if state == "match":
		api.send({"t": "eos_voice_ready", "ok": ok})


func _on_voice_start() -> void:
	if state != "match" or not _my_turn:
		return
	if _voice_mode == "eos" and eos != null:
		eos.voice_set_talking(true)
	if not voice.start_recording():
		hud.set_comment(tr("マイクを使えませんでした。文字で入力してください。"))
		hud.set_voice_mode(false)
		hud.set_input_enabled(true, tr("ここに書く…"))


func _on_voice_stop() -> void:
	if _voice_mode == "eos" and eos != null:
		eos.voice_set_talking(false)
	if not voice.is_recording():
		return
	var bytes: PackedByteArray = voice.stop_recording()
	if bytes.is_empty():
		hud.set_comment(tr("声が短すぎました。ボタンを押している間に話してください。"))
		return
	_send_voice(bytes, "")


func _send_voice(bytes: PackedByteArray, debug_text: String) -> void:
	_my_turn = false
	hud.set_input_enabled(false, "")
	var msg: Dictionary = {"t": "voice", "audio": Marshalls.raw_to_base64(bytes)}
	if debug_text != "":
		msg["debug_text"] = debug_text
	api.send(msg)
	hud.set_status(tr("声を送りました。文字にしています…"))


## 自動テスト用: 自分の番が来たら自動で返す（店員はよい返事、客は圧のあるセリフ）
func _smoke_autoplay() -> void:
	_smoke_n += 1
	var n: int = _smoke_n
	await get_tree().create_timer(0.4).timeout
	if not _my_turn or state != "match":
		return
	var en: bool = GameSettings.language == "en"
	var text: String = ""
	if _phase == "staff_turn":
		var words: Array = []
		for c in Scenarios.customers(str(_match.get("stage", "konbini"))):
			if str((c as Dictionary).get("title", "")) == str(_card.get("title", "")):
				words = (c as Dictionary).get("solution_keywords", [])
		var w: String = str(words[n % words.size()]) if not words.is_empty() else ("check" if en else "確認")
		if en:
			text = "I'm so sorry, I understand. Please let me %s right away, sir. (%d)" % [w, n]
		elif GameSettings.language == "ko":
			text = "정말 죄송합니다. 마음 충분히 이해합니다. 바로 %s 대응해 드리겠습니다. (%d)" % [w, n]
		else:
			text = "申し訳ございません。お気持ちお察しいたします。すぐに%sの対応をいたします。（%d）" % [w, n]
	else:
		text = ("Get me the manager! I'm a regular here, this is unacceptable! (%d)" % n) if en else ("책임자 불러! 난 단골이야, 이건 말도 안 돼! (%d)" % n) if GameSettings.language == "ko" else ("責任者を出せ！こっちは客だぞ！どうしてくれるんだ！（%d）" % n)
	if str(_match.get("format", "text")) == "voice":
		_send_voice(VoiceScript.test_tone(1.0), text)
	else:
		_on_text(text)
