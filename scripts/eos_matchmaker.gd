extends Node
## Epic Online Services（EOS）で対戦相手を探す（要件#32, #48）。
## プラグイン「Epic Online Services Godot（EOSG）」の高レベルAPI（HPlatform / HAuth / HLobbies）を使う。
##
## 役割の分け方:
##   - EOS: 相手を探す（ロビー）・Epic のフレンド招待
##   - ゲームサーバー: 対戦の進行・AIの判定・レーティング（改ざんできないようにサーバーに置く）
## 流れ:
##   ランダムマッチ: 同じ言語・形式で待っているロビーを探す → あればレートの近いものに入る / なければ作って待つ
##     作った側（ホスト）: ゲームサーバーに部屋を作り（ranked）、部屋コードをロビーの属性 room に書く
##     入った側: ロビーの属性 room を読んで、ゲームサーバーの部屋に入る
##   フレンド招待: 招待専用のロビーを作り、Epic のフレンド画面（オーバーレイ）を開く。招待を受けた側は自動で入る
##
## ★ プラグインが入っていない・ID が設定されていないときは available() が false になり、
##    versus_game.gd はゲームサーバーのマッチングを使う（今までどおり）。
## ★ このファイルはプラグインが無くてもコンパイルできるよう、プラグインの名前（HLobbies, EOS など）を直接書かず、
##    実行時に探して使う。
## ★ 作業環境ではプラグインを動かせないため、実機での確認はまだ（docs/EOS.md）。

signal status(text: String)
## ゲームサーバーの部屋を作ってほしい（ホスト側）。versus_game.gd が room_create を送り、set_room_code() で返す
signal need_room(ranked: bool)
## ゲームサーバーの部屋コードが分かった（参加側）。versus_game.gd が room_join を送る
signal room_found(code: String)
signal failed(message: String)

const PLUGIN_DIR: String = "res://addons/epic-online-services-godot"
const CREDENTIALS_PATH: String = "res://config/eos.cfg"
## 本物の ID はこちらに書く（.gitignore 済み。リポジトリには入らない）。あれば eos.cfg より優先（要件#76）
const CREDENTIALS_LOCAL_PATH: String = "res://config/eos.local.cfg"
const GAME_TAG: String = "cushara"
const WAIT_FOR_ROOM_SEC: float = 20.0
const RATING_WINDOW: int = 300

var _eos = null          # eos.gd（クラス EOS）を load したもの
var _ready_eos: bool = false
var _setting_up: bool = false
var _lobby = null        # 今入っている HLobby
var _is_host: bool = false
var _cancelled: bool = false


# ---------------------------------------------------------------- 準備

func _node(n: String) -> Node:
	return get_node_or_null("/root/" + n)


## プラグインが入っていて、ID が設定されているか
func available() -> bool:
	if not FileAccess.file_exists(PLUGIN_DIR + "/eos.gd") or not Engine.has_singleton("IEOS"):
		return false
	if _node("HPlatform") == null or _node("HAuth") == null or _node("HLobbies") == null:
		return false
	return _credentials().get("product_id", "") != ""


func _credentials() -> Dictionary:
	var out: Dictionary = {}
	for path in [CREDENTIALS_PATH, CREDENTIALS_LOCAL_PATH]:
		var cfg: ConfigFile = ConfigFile.new()
		if cfg.load(path) != OK:
			continue
		for k in ["product_name", "product_version", "product_id", "sandbox_id", "deployment_id", "client_id", "client_secret", "encryption_key"]:
			var v: String = str(cfg.get_value("eos", k, ""))
			if v != "" or not out.has(k):
				out[k] = v
	return out


## EOS を初期化してログインする（初回だけ）。成功で true
func ensure_ready(display_name: String) -> bool:
	if _ready_eos:
		return true
	if _setting_up:
		while _setting_up:
			await get_tree().process_frame
		return _ready_eos
	if not available():
		return false
	_setting_up = true
	status.emit(tr("Epic のサービスに接続しています…"))
	_eos = load(PLUGIN_DIR + "/eos.gd")
	var creds_script: Script = load(PLUGIN_DIR + "/heos/hcredentials.gd")
	var creds = creds_script.new()
	var c: Dictionary = _credentials()
	for k in c:
		if str(c[k]) != "":
			creds.set(k, str(c[k]))
	if str(c.get("product_name", "")) == "":
		creds.set("product_name", "CusHara")
	if str(c.get("product_version", "")) == "":
		creds.set("product_version", str(ProjectSettings.get_setting("application/config/version", "0.1.0")))
	var ok: bool = await _node("HPlatform").setup_eos_async(creds)
	if ok:
		var auth: Node = _node("HAuth")
		# Epic アカウントで前回ログインしていればそれを使い（フレンド招待ができる）、無ければ端末のIDでログイン
		ok = await auth.login_persistent_auth_async()
		if not ok:
			ok = await auth.login_anonymous_async(display_name if display_name != "" else "Player")
	if ok:
		var ieos: Object = Engine.get_singleton("IEOS")
		ieos.connect("lobby_interface_lobby_invite_accepted_callback", _on_invite_accepted)
	_ready_eos = ok
	_setting_up = false
	if not ok:
		failed.emit(tr("Epic のサービスに接続できませんでした。ゲームサーバーのマッチングを使います"))
	return ok


## Epic アカウントでログインしているか（フレンド招待に必要）
func has_epic_account() -> bool:
	var auth: Node = _node("HAuth")
	return auth != null and str(auth.get("epic_account_id")) != ""


func _cmp_equal() -> int:
	return int(_eos.ComparisonOp["Equal"])


# ---------------------------------------------------------------- ランダムマッチ

func find_match(lang: String, format: String, rating: int, display_name: String) -> void:
	_cancelled = false
	if not await ensure_ready(display_name):
		return
	var hl: Node = _node("HLobbies")
	status.emit(tr("Epic のロビーで相手を探しています…"))
	var found = await hl.search_by_attribute_async([
		{"key": "game", "value": GAME_TAG, "comparison": _cmp_equal()},
		{"key": "lang", "value": lang, "comparison": _cmp_equal()},
		{"key": "format", "value": format, "comparison": _cmp_equal()},
		{"key": "state", "value": "waiting", "comparison": _cmp_equal()},
	])
	if _cancelled:
		return
	# 空きがあり、レートが近い順
	var best = null
	var best_gap: int = 1 << 30
	if found != null:
		for l in (found as Array):
			if int(l.get("available_slots")) <= 0:
				continue
			var attr: Dictionary = l.get_attribute("rating")
			var gap: int = absi(int(str(attr.get("value", "0"))) - rating)
			if gap <= RATING_WINDOW and gap < best_gap:
				best = l
				best_gap = gap
	if best != null:
		var joined = await hl.join_async(best)
		if _cancelled:
			return
		if joined != null:
			_lobby = joined
			_is_host = false
			await _wait_room_code()
			return
	# 見つからなければ自分でロビーを作って待つ
	await _host_lobby(lang, format, rating, true)


func _host_lobby(lang: String, format: String, rating: int, public: bool) -> void:
	var hl: Node = _node("HLobbies")
	var opts = _eos.Lobby.CreateLobbyOptions.new()
	opts.bucket_id = "%s:%s:%s" % [GAME_TAG, lang, format]
	opts.max_lobby_members = 2
	opts.presence_enabled = true
	opts.allow_invites = true
	opts.enable_rtc_room = false
	var level: Dictionary = _eos.Lobby.LobbyPermissionLevel
	opts.permission_level = level["PublicAdvertised"] if public else level["InviteOnly"]
	var lobby = await hl.create_lobby_async(opts)
	if _cancelled:
		if lobby != null:
			lobby.destroy_async()
		return
	if lobby == null:
		failed.emit(tr("Epic のロビーを作れませんでした。ゲームサーバーのマッチングを使います"))
		return
	_lobby = lobby
	_is_host = true
	lobby.add_attribute("game", GAME_TAG)
	lobby.add_attribute("lang", lang)
	lobby.add_attribute("format", format)
	lobby.add_attribute("rating", str(rating))
	lobby.add_attribute("state", "waiting")
	await lobby.update_async()
	status.emit(tr("Epic のロビーで相手を待っています…"))
	# ゲームサーバーの部屋を作ってもらう（versus_game.gd → set_room_code）
	need_room.emit(public)


## ホスト: ゲームサーバーの部屋コードをロビーに書く（相手が読む）
func set_room_code(code: String) -> void:
	if _lobby == null or not _is_host:
		return
	_lobby.add_attribute("room", code)
	await _lobby.update_async()


## 参加側: ホストが部屋コードを書くまで待つ
func _wait_room_code() -> void:
	var waited: float = 0.0
	while waited < WAIT_FOR_ROOM_SEC and not _cancelled and _lobby != null:
		var attr: Dictionary = _lobby.get_attribute("room")
		var code: String = str(attr.get("value", ""))
		if code != "":
			room_found.emit(code)
			return
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if not _cancelled:
		failed.emit(tr("相手の準備が間に合いませんでした。もう一度探してください"))
		leave()


# ---------------------------------------------------------------- フレンド招待

## 招待専用のロビーを作り、Epic のフレンド画面を開く（Epic アカウントでのログインが必要）
func invite_friend(lang: String, format: String, rating: int, display_name: String) -> void:
	_cancelled = false
	if not await ensure_ready(display_name):
		return
	if not has_epic_account():
		var ok: bool = await _node("HAuth").login_account_portal_async()
		if not ok:
			failed.emit(tr("フレンド招待には Epic アカウントでのログインが必要です。部屋コードを友達に伝えてください"))
			return
	await _host_lobby(lang, format, rating, false)
	if _lobby == null:
		return
	var opts = _eos.UI.ShowFriendsOptions.new()
	_eos.UI.UIInterface.show_friends(opts)
	status.emit(tr("Epic のフレンド画面から招待してください"))


func _on_invite_accepted(data: Dictionary) -> void:
	var lobby_id: String = str(data.get("lobby_id", ""))
	if lobby_id == "":
		return
	_cancelled = false
	var hl: Node = _node("HLobbies")
	status.emit(tr("招待された部屋に入っています…"))
	var found = await hl.search_by_lobby_id_async(lobby_id)
	if found == null or (found as Array).is_empty():
		failed.emit(tr("招待された部屋が見つかりませんでした"))
		return
	var joined = await hl.join_async((found as Array)[0])
	if joined == null:
		failed.emit(tr("招待された部屋に入れませんでした"))
		return
	_lobby = joined
	_is_host = false
	await _wait_room_code()


## 今入っている EOS ロビーの ID（サーバーの記録用。無ければ ""）
func lobby_id() -> String:
	if _lobby == null:
		return ""
	return str(_lobby.get("lobby_id"))


## 称号を EOS の実績にも記録する（要件#78, #79）。EOS につながっているときだけ。実績のIDは称号の id（開発者ポータルに同じIDで登録が要る）
func unlock_achievements(ids: Array) -> void:
	if ids.is_empty() or not _ready_eos:
		return
	var ha: Node = _node("HAchievements")
	if ha == null:
		return
	ha.unlock_achievements_async(ids)


# ---------------------------------------------------------------- 声の対戦のボイス（要件#100）
## 声の対戦では、EOS のロビーのボイス（RTC）で相手に声を直接届ける。部屋は席 0 の人が作り、ID はゲームサーバーが相手に渡す。
## 自分の番でボタンを押している間だけマイクを開ける（update_sending）。だめなら、ゲームサーバーが中継する（今までどおり）。

var _voice_lobby = null


## ボイスの部屋を作る。ID を返す（だめなら ""）
func voice_host(display_name: String) -> String:
	if not await ensure_ready(display_name):
		return ""
	_prepare_rtc()
	var opts = _eos.Lobby.CreateLobbyOptions.new()
	opts.bucket_id = "%s:voice" % GAME_TAG
	opts.max_lobby_members = 2
	opts.presence_enabled = false
	opts.allow_invites = false
	opts.enable_rtc_room = true
	opts.enable_join_by_id = true
	opts.permission_level = _eos.Lobby.LobbyPermissionLevel["JoinViaPresence"]
	var lobby = await _node("HLobbies").create_lobby_async(opts)
	if lobby == null:
		return ""
	_voice_lobby = lobby
	return str(lobby.get("lobby_id"))


## 相手が作ったボイスの部屋に入る
func voice_join(lobby_id: String, display_name: String) -> bool:
	if lobby_id == "" or not await ensure_ready(display_name):
		return false
	_prepare_rtc()
	var lobby = await _node("HLobbies").join_by_id_async(lobby_id)
	if lobby == null:
		return false
	_voice_lobby = lobby
	return true


## マイクは最初は閉じておく（自分の番でボタンを押したときだけ開ける）
func _prepare_rtc() -> void:
	var hl: Node = _node("HLobbies")
	if hl != null:
		hl.set("local_rtc_options", {"flags": int(_eos.RTC.JoinRoomFlags["EnableDataChannel"]), "local_audio_device_input_starts_muted": true})


## ボイスの部屋につながって、相手もいるか
func voice_connected() -> bool:
	if _voice_lobby == null or not is_instance_valid(_voice_lobby):
		return false
	return bool(_voice_lobby.get("rtc_room_connected")) and (_voice_lobby.get("members") as Array).size() >= 2


## 何秒か待って、つながったら true
func voice_wait_connected(seconds: float) -> bool:
	var t: float = 0.0
	while t < seconds:
		if voice_connected():
			return true
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	return voice_connected()


## マイクを開ける・閉じる（押して話す）
func voice_set_talking(on: bool) -> void:
	if _voice_lobby == null or not is_instance_valid(_voice_lobby):
		return
	var room: String = str(_voice_lobby.get("rtc_room_name"))
	if room == "":
		return
	var opts = _eos.RTCAudio.UpdateSendingOptions.new()
	opts.room_name = room
	opts.audio_status = _eos.RTCAudio.AudioStatus["Enabled"] if on else _eos.RTCAudio.AudioStatus["Disabled"]
	_eos.RTCAudio.RTCAudioInterface.update_sending(opts)


func voice_leave() -> void:
	if _voice_lobby == null:
		return
	var l = _voice_lobby
	_voice_lobby = null
	if not is_instance_valid(l):
		return
	voice_set_talking(false)
	if bool(l.call("is_owner")):
		l.destroy_async()
	else:
		l.leave_async()


# ---------------------------------------------------------------- 後片付け

## 試合が始まったら（または、やめたら）ロビーを抜ける
func leave() -> void:
	if _lobby == null:
		return
	var l = _lobby
	_lobby = null
	if _is_host:
		l.destroy_async()
	else:
		l.leave_async()


func cancel() -> void:
	_cancelled = true
	leave()
