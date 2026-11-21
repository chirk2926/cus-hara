extends Node
## ゲームサーバー（server/）との通信。HTTP の API と、対戦用の WebSocket（/ws）。
## APIの一覧は docs/SERVER.md。main.gd が1つだけ作り、1人用と対戦の両方が使う。
##
## HTTP: `var res: Dictionary = await api.request("POST", "/api/v1/solo/start", {...})`
##   成功 → {"ok": true, "body": {...}} / 失敗 → {"ok": false, "status": 401, "message": "日本語の説明"}
## WebSocket: open_socket() で接続し、届いたメッセージは message(msg) で受け取る。

signal message(msg: Dictionary)
signal socket_state(state: String)   # "connecting" | "open" | "closed"

const TIMEOUT_SEC: float = 35.0   # サーバーの AI 待ち（最大25秒）より長く（レビュー1-6）

var _ws: WebSocketPeer = null
var _ws_state: String = "closed"
var _want_socket: bool = false
var _reconnect_wait: float = 0.0
var _reconnect_tries: int = 0
var _authed: bool = false


# ---------------------------------------------------------------- HTTP

func base_url() -> String:
	return GameSettings.server_url.strip_edges().trim_suffix("/")


func request(method: String, path: String, body: Variant = null, auth: bool = true) -> Dictionary:
	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = TIMEOUT_SEC
	add_child(http)
	var headers: PackedStringArray = PackedStringArray(["content-type: application/json"])
	if auth and GameSettings.token != "":
		headers.append("authorization: Bearer " + GameSettings.token)
	var m: int = HTTPClient.METHOD_GET
	if method == "POST":
		m = HTTPClient.METHOD_POST
	var payload: String = "" if body == null else JSON.stringify(body)
	var err: int = http.request(base_url() + path, headers, m, payload)
	if err != OK:
		http.queue_free()
		return {"ok": false, "status": 0, "message": tr("サーバーへの接続を始められませんでした（接続先: %s）") % base_url()}
	var res: Array = await http.request_completed
	http.queue_free()
	var result: int = int(res[0])
	var code: int = int(res[1])
	var raw: PackedByteArray = res[3]
	if result == HTTPRequest.RESULT_TIMEOUT:
		return {"ok": false, "status": 0, "message": tr("サーバーの応答が時間切れになりました")}
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status": 0, "message": tr("ゲームサーバーにつながりません。ネット接続を確かめてください")}
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	var data: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	if code != 200:
		var msg: String = tr("サーバーのエラー（%d）") % code
		var e: Variant = data.get("error", null)
		if typeof(e) == TYPE_DICTIONARY:
			msg = str((e as Dictionary).get("message", msg))
		return {"ok": false, "status": code, "message": msg, "code": str((e as Dictionary).get("code", "")) if typeof(e) == TYPE_DICTIONARY else ""}
	return {"ok": true, "status": code, "body": data}


## ログインする（初回はゲストのアカウントを作る）。成功なら自分の情報、失敗なら {"error": "..."}
## 運営からの警告（要件#100）。タイトル画面で見せて、既読を送る
var pending_warning: String = ""


func ensure_login() -> Dictionary:
	if GameSettings.token != "":
		var me: Dictionary = await request("GET", "/api/v1/me")
		if bool(me.get("ok", false)):
			var p: Dictionary = (me["body"] as Dictionary).get("player", {})
			pending_warning = str((me["body"] as Dictionary).get("warning", ""))
			# 対戦の同意（要件#101）はサーバーの記録に合わせる
			if (me["body"] as Dictionary).has("vs_consent"):
				GameSettings.vs_consent = int((me["body"] as Dictionary).get("vs_consent", 0))
			_remember(p)
			return p
		if int(me.get("status", 0)) == 403:
			return {"error": str(me.get("message", "")), "code": "banned"}
		if int(me.get("status", 0)) != 401:
			return {"error": str(me.get("message", ""))}
		GameSettings.token = ""
	# 名前が無いときは空で送り、サーバーの既定の名前（名無しのスタッフ）にする。
	# パソコンのユーザー名（本名のことがある）は送らない（要件#108）
	var name_to_use: String = GameSettings.player_name
	var res: Dictionary = await request("POST", "/api/v1/guest", {"name": name_to_use}, false)
	if not bool(res.get("ok", false)):
		return {"error": str(res.get("message", ""))}
	var body: Dictionary = res["body"]
	GameSettings.token = str(body.get("token", ""))
	var player: Dictionary = body.get("player", {})
	_remember(player)
	return player


func rename(new_name: String) -> Dictionary:
	var res: Dictionary = await request("POST", "/api/v1/me", {"name": new_name})
	if bool(res.get("ok", false)):
		var p: Dictionary = (res["body"] as Dictionary).get("player", {})
		_remember(p)
		return p
	return {"error": str(res.get("message", "")), "code": str(res.get("code", ""))}


func _remember(player: Dictionary) -> void:
	GameSettings.last_profile = player
	GameSettings.player_name = str(player.get("name", GameSettings.player_name))
	GameSettings.save_settings()


# ---------------------------------------------------------------- WebSocket

func socket_url() -> String:
	var u: String = base_url()
	if u.begins_with("https://"):
		return "wss://" + u.substr(8) + "/ws"
	if u.begins_with("http://"):
		return "ws://" + u.substr(7) + "/ws"
	return u + "/ws"


func is_open() -> bool:
	return _ws_state == "open" and _authed


func open_socket() -> void:
	_want_socket = true
	_reconnect_tries = 0
	if _ws_state == "closed":
		_connect()


func close_socket() -> void:
	_want_socket = false
	if _ws != null:
		_ws.close(1000, "bye")
	_ws = null
	_authed = false
	_set_state("closed")


func send(msg: Dictionary) -> bool:
	if _ws == null or _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	return _ws.send_text(JSON.stringify(msg)) == OK


func _connect() -> void:
	_ws = WebSocketPeer.new()
	# 音声（最大20秒 ≒ base64 で430KB）を送受信できる大きさにする
	_ws.outbound_buffer_size = 1 << 20
	_ws.inbound_buffer_size = 1 << 20
	_ws.max_queued_packets = 256
	_authed = false
	var err: int = _ws.connect_to_url(socket_url())
	if err != OK:
		_ws = null
		_set_state("closed")
		_schedule_reconnect()
		return
	_set_state("connecting")


func _set_state(s: String) -> void:
	if s == _ws_state:
		return
	_ws_state = s
	socket_state.emit(s)


func _schedule_reconnect() -> void:
	if not _want_socket:
		return
	_reconnect_tries += 1
	_reconnect_wait = minf(1.0 * float(_reconnect_tries), 5.0)


func _process(delta: float) -> void:
	if _ws == null:
		if _want_socket and _reconnect_wait > 0.0:
			_reconnect_wait -= delta
			if _reconnect_wait <= 0.0:
				_connect()
		return
	_ws.poll()
	var st: int = _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if _ws_state != "open":
			_set_state("open")
			send({"t": "auth", "token": GameSettings.token})
		while _ws != null and _ws.get_available_packet_count() > 0:
			var pkt: PackedByteArray = _ws.get_packet()
			var parsed: Variant = JSON.parse_string(pkt.get_string_from_utf8())
			if typeof(parsed) == TYPE_DICTIONARY:
				var msg: Dictionary = parsed
				# 利用停止・ほかの場所でつながった: つなぎ直さない（2つの窓が互いに切り合わないように。レビュー2-3）
				if str(msg.get("t", "")) == "error" and str(msg.get("code", "")) in ["replaced", "banned", "unauthorized"]:
					_want_socket = false
				if str(msg.get("t", "")) == "hello":
					_authed = true
					_reconnect_tries = 0
					var p: Variant = msg.get("player", {})
					if typeof(p) == TYPE_DICTIONARY:
						_remember(p)
				message.emit(msg)
	elif st == WebSocketPeer.STATE_CLOSED:
		# 4001 = ログインできない・ほかの場所でつながった、4003 = 利用停止。つなぎ直しても同じなのでやめる
		if _ws.get_close_code() in [4001, 4003]:
			_want_socket = false
		_ws = null
		_authed = false
		_set_state("closed")
		_schedule_reconnect()
