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
var _my_turn: bool = false
var _seconds_left: float = -1.0
var _totals: Dictionary = {"you": 0, "opponent": 0}
var _round: int = 0
var _rounds: int = 2
var _smoke_n: int = 0


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
	attach_hud(hud_node)


## 画面（HUD）を作り直したときに付け替える
func attach_hud(hud_node) -> void:
	hud = hud_node
	hud.reply_submitted.connect(_on_text)
	hud.voice_start.connect(_on_voice_start)
	hud.voice_stop.connect(_on_voice_stop)


func is_active() -> bool:
	return state == "match"


func is_busy() -> bool:
	return state != "idle"


# ---------------------------------------------------------------- ロビーからの操作

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
	if state == "queued" or state == "room" or state == "connecting":
		api.send({"t": "cancel"})
	state = "idle"
	_pending = {}


func leave_match() -> void:
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
			api.send({"t": "queue", "format": p["format"]})
		"room_create":
			api.send({"t": "room_create", "format": p["format"]})
		"room_join":
			api.send({"t": "room_join", "code": p["code"]})


# ---------------------------------------------------------------- サーバーからのメッセージ

func _on_message(msg: Dictionary) -> void:
	var t: String = str(msg.get("t", ""))
	match t:
		"hello":
			if bool(msg.get("resumed", false)):
				hud.set_status(tr("つなぎ直しました"))
			else:
				_send_pending()
		"queued":
			state = "queued"
			lobby_event.emit("queued", msg)
		"queue_status":
			lobby_event.emit("queue_status", msg)
		"room_created":
			state = "room"
			lobby_event.emit("room_created", msg)
		"room_expired":
			state = "idle"
			lobby_event.emit("error", {"message": tr("部屋の期限が切れました。作り直してください")})
		"cancelled":
			lobby_event.emit("cancelled", msg)
		"error":
			if state != "match":
				state = "idle"
			lobby_event.emit("error", msg)
		"match_found":
			_on_match_found(msg)
		"round_start":
			_on_round_start(msg)
		"phase":
			_on_phase(msg)
		"line":
			_on_line(msg)
		"voice":
			var secs: float = voice.play_base64(str(msg.get("audio", "")))
			if secs > 0.0:
				hud.set_status(tr("相手の声: %.1f 秒") % secs)
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
		_:
			pass


func _who(by: String) -> String:
	return tr("あなた") if by == "you" else str((_match.get("opponent", {}) as Dictionary).get("name", tr("相手")))


func _on_match_found(msg: Dictionary) -> void:
	var resumed: bool = state == "match"
	state = "match"
	_match = msg
	var stage: String = str(msg.get("stage", "konbini"))
	_rounds = int(msg.get("rounds", 2))
	if not resumed:
		main.enter_versus(stage)
		hud.clear_round()
		var op: Dictionary = msg.get("opponent", {})
		var kind_label: String = tr("ランクマッチ") if str(msg.get("kind", "")) == "ranked" else tr("フレンド対戦")
		hud.set_top(tr(str(STAGE_NAMES.get(stage, ""))), kind_label, "")
		hud.set_comment(tr("対戦相手: %s（%s・%d）") % [str(op.get("name", "")), str(op.get("rank", "")), int(op.get("rating", 0))])
		hud.show_banner(tr("対戦開始！"), UI.POP)
		main.sfx.play("door")
	var voice_format: bool = str(msg.get("format", "text")) == "voice"
	hud.set_voice_mode(voice_format)
	if voice_format and not voice.available():
		hud.set_voice_mode(false)
		hud.set_comment(tr("マイクが見つからないので、文字で入力します。"))


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
		hud.set_memo(str(_card.get("title", "")), str(_card.get("memo", "")), str(_card.get("demand", "")))
		hud.set_comment(tr("あなたは店員役。怒りを100にせず、納得を100にすれば勝ち。"))
		hud.show_banner(tr("あなたは店員役"), UI.LCD_ON)
	else:
		hud.set_quick_phrases(CUSTOMER_PHRASES)
		hud.set_memo(tr("あなたの役: ") + str(_card.get("title", "")), str(_card.get("memo", "")), str(_card.get("demand", "")))
		hud.set_comment(tr("あなたは客役。怒りを100にするか、店員に不当な要求を飲ませれば勝ち。暴言・無言・くり返しは逆効果。"))
		hud.show_banner(tr("あなたは客役"), Color("#ff8a6a"))
	hud.set_gauges(_anger, _resolve, -1.0)
	main.display_anger = _anger
	var look: Dictionary = _card.get("look", {}) if typeof(_card.get("look", null)) == TYPE_DICTIONARY else {}
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
	if _phase == "staff_turn":
		_anger = minf(100.0, _anger + _rate * elapsed)
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
		_anger = minf(100.0, _anger + _rate * delta)
		_refresh()
	elif _phase == "customer_turn" and _seconds_left > 0.0:
		var before: int = int(ceil(_seconds_left))
		_seconds_left = maxf(0.0, _seconds_left - delta)
		if int(ceil(_seconds_left)) != before:
			_update_status()


func _refresh() -> void:
	var left: float = -1.0
	if _phase == "staff_turn" and _rate > 0.0:
		left = (100.0 - _anger) / _rate
	hud.set_gauges(_anger, _resolve, left)
	main.display_anger = _anger


func _on_line(msg: Dictionary) -> void:
	var role: String = str(msg.get("role", ""))
	var text: String = str(msg.get("text", ""))
	var by: String = str(msg.get("by", ""))
	var mark: String = tr("（声）") if str(msg.get("via", "")) == "voice" else ""
	if role == "customer":
		var speaker: String = "%s（%s）%s" % [str(_card.get("title", tr("お客さん"))), _who(by), mark]
		main.customer_say(speaker, text, _anger >= 70.0)
	else:
		hud.show_echo(tr("店員（%s）: ") % _who(by), text)


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
	state = "idle"
	_phase = ""
	hud.set_input_enabled(false, "")
	if voice.is_recording():
		voice.cancel_recording()
	finished.emit(msg)


# ---------------------------------------------------------------- 入力

func _on_text(text: String) -> void:
	if state != "match" or not _my_turn or main.mode != "versus":
		return
	_my_turn = false
	api.send({"t": "say", "text": text})
	hud.set_status(tr("送りました…"))


func _on_voice_start() -> void:
	if state != "match" or not _my_turn:
		return
	if not voice.start_recording():
		hud.set_comment(tr("マイクを使えませんでした。文字で入力してください。"))
		hud.set_voice_mode(false)
		hud.set_input_enabled(true, tr("ここに書く…"))


func _on_voice_stop() -> void:
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
		else:
			text = "申し訳ございません。お気持ちお察しいたします。すぐに%sの対応をいたします。（%d）" % [w, n]
	else:
		text = ("Get me the manager! I'm a regular here, this is unacceptable! (%d)" % n) if en else ("責任者を出せ！こっちは客だぞ！どうしてくれるんだ！（%d）" % n)
	if str(_match.get("format", "text")) == "voice":
		_send_voice(VoiceScript.test_tone(1.0), text)
	else:
		_on_text(text)
