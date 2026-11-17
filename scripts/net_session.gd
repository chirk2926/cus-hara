extends Node
## 対戦モードの接続層。つながった後は Godot 標準の multiplayer（RPC）を使うので、
## ゲーム側（versus_game.gd）は接続方法を気にしなくてよい。
##
## 接続方法は2つ:
##  - "steam": Steamのロビー（フレンド招待／ランダムマッチ）。GodotSteam（GDExtension）が入っているときだけ使える。
##             ★ GodotSteam を入れた実機での動作確認はまだ行っていない（docs/HANDOVER.md 参照）。
##  - "enet":  IPアドレス直結。開発・自動テスト・LAN用。
##
## ホストは常に peer id 1。相手は1人だけ（2人対戦）。

signal connected                 # 相手とつながった（ホスト・ゲスト両方で発行）
signal closed(reason: String)    # 切断・失敗
signal status(text: String)      # 画面に出す進行メッセージ

const DEFAULT_PORT: int = 24545
const LOBBY_TAG: String = "cushara_versus_v1"
# Steamworks の定数（GodotSteam の列挙と同じ値）
const LOBBY_TYPE_FRIENDS_ONLY: int = 1
const LOBBY_TYPE_PUBLIC: int = 2
const LOBBY_COMPARISON_EQUAL: int = 0
const LOBBY_DISTANCE_WORLDWIDE: int = 3

var mode: String = ""
var is_host: bool = false
var peer_id: int = 0          # 相手の peer id

var _steam = null             # GodotSteam の Steam シングルトン（無ければ null）
var _steam_ready: bool = false
var _lobby_id: int = 0
var _searching: bool = false
var _invite_on_create: bool = false
var _open: bool = false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(_delta: float) -> void:
	if _steam_ready and _steam != null:
		_steam.run_callbacks()


func is_open() -> bool:
	return _open


# ---------------------------------------------------------------- IP直結（ENet）

func host_enet(port: int = DEFAULT_PORT) -> bool:
	close("")
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: int = peer.create_server(port, 1)
	if err != OK:
		closed.emit("部屋を作れませんでした（ポート %d が使用中かもしれません）" % port)
		return false
	multiplayer.multiplayer_peer = peer
	mode = "enet"
	is_host = true
	_open = true
	status.emit("部屋を作りました。相手の参加を待っています…（ポート %d）" % port)
	return true


func join_enet(address: String, port: int = DEFAULT_PORT) -> bool:
	close("")
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: int = peer.create_client(address, port)
	if err != OK:
		closed.emit("接続を開始できませんでした")
		return false
	multiplayer.multiplayer_peer = peer
	mode = "enet"
	is_host = false
	_open = true
	status.emit("%s に接続しています…" % address)
	return true


# ---------------------------------------------------------------- Steam（GodotSteam）

func steam_available() -> bool:
	return Engine.has_singleton("Steam") and ClassDB.class_exists("SteamMultiplayerPeer")


## Steam を初期化する。成功なら空文字、失敗なら理由を返す。
func steam_init() -> String:
	if _steam_ready:
		return ""
	if not steam_available():
		return "このビルドにはSteam連携（GodotSteam）が入っていません"
	_steam = Engine.get_singleton("Steam")
	var res: Variant = _steam.steamInitEx()
	if typeof(res) == TYPE_DICTIONARY and int((res as Dictionary).get("status", 1)) != 0:
		return "Steamを初期化できませんでした: " + str((res as Dictionary).get("verbal", ""))
	_steam.lobby_created.connect(_on_lobby_created)
	_steam.lobby_joined.connect(_on_lobby_joined)
	_steam.lobby_match_list.connect(_on_lobby_match_list)
	_steam.join_requested.connect(_on_join_requested)
	_steam_ready = true
	return ""


func steam_name() -> String:
	if _steam_ready and _steam != null:
		return str(_steam.getPersonaName())
	return ""


## フレンドだけが入れる部屋を作り、招待画面を開く
func steam_host_friends() -> void:
	var err: String = steam_init()
	if err != "":
		closed.emit(err)
		return
	close("")
	_searching = false
	_invite_on_create = true
	status.emit("部屋を作っています…")
	_steam.createLobby(LOBBY_TYPE_FRIENDS_ONLY, 2)


## ランダムマッチ: 空いている部屋を探し、無ければ自分で公開の部屋を作って待つ
func steam_find_match() -> void:
	var err: String = steam_init()
	if err != "":
		closed.emit(err)
		return
	close("")
	_searching = true
	_invite_on_create = false
	status.emit("対戦相手を探しています…")
	_steam.addRequestLobbyListStringFilter("tag", LOBBY_TAG, LOBBY_COMPARISON_EQUAL)
	_steam.addRequestLobbyListNearValueFilter("rating", GameSettings.rating)
	_steam.addRequestLobbyListDistanceFilter(LOBBY_DISTANCE_WORLDWIDE)
	_steam.requestLobbyList()


func steam_invite() -> void:
	if _steam_ready and _lobby_id != 0:
		_steam.activateGameOverlayInviteDialog(_lobby_id)


func _on_lobby_match_list(lobbies: Array) -> void:
	if not _searching:
		return
	_searching = false
	for l in lobbies:
		var id: int = int(l)
		if int(_steam.getNumLobbyMembers(id)) < 2:
			status.emit("部屋が見つかりました。参加しています…")
			_steam.joinLobby(id)
			return
	status.emit("空いている部屋が無いので、部屋を作って待ちます…")
	_steam.createLobby(LOBBY_TYPE_PUBLIC, 2)


func _on_lobby_created(result: int, lobby_id: int) -> void:
	if result != 1:
		closed.emit("Steamの部屋を作れませんでした")
		return
	_lobby_id = lobby_id
	_steam.setLobbyData(lobby_id, "tag", LOBBY_TAG)
	_steam.setLobbyData(lobby_id, "rating", str(GameSettings.rating))
	_steam.setLobbyJoinable(lobby_id, true)
	var peer: Variant = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: int = OK
	# GodotSteam のバージョンによって関数名が違うため、両方に対応する
	if peer.has_method("host_with_lobby"):
		err = int(peer.host_with_lobby(lobby_id))
	else:
		err = int(peer.create_host(0))
	if err != OK:
		closed.emit("Steamの通信を開始できませんでした")
		return
	multiplayer.multiplayer_peer = peer
	mode = "steam"
	is_host = true
	_open = true
	status.emit("部屋を作りました。相手の参加を待っています…")
	if _invite_on_create:
		_invite_on_create = false
		steam_invite()


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != 1:
		closed.emit("部屋に入れませんでした")
		return
	_lobby_id = lobby_id
	var owner_id: int = int(_steam.getLobbyOwner(lobby_id))
	if owner_id == int(_steam.getSteamID()):
		return   # 自分が作った部屋
	var peer: Variant = ClassDB.instantiate("SteamMultiplayerPeer")
	var err: int = OK
	if peer.has_method("connect_to_lobby"):
		err = int(peer.connect_to_lobby(lobby_id))
	else:
		err = int(peer.create_client(owner_id, 0))
	if err != OK:
		closed.emit("相手に接続できませんでした")
		return
	multiplayer.multiplayer_peer = peer
	mode = "steam"
	is_host = false
	_open = true
	status.emit("相手に接続しています…")


## Steamのフレンド一覧や招待から「参加」を選んだとき
func _on_join_requested(lobby_id: int, _friend_id: int) -> void:
	close("")
	status.emit("招待された部屋に参加しています…")
	_steam.joinLobby(lobby_id)


# ---------------------------------------------------------------- 共通

func close(reason: String) -> void:
	var was_open: bool = _open
	_open = false
	peer_id = 0
	if _steam_ready and _lobby_id != 0:
		_steam.leaveLobby(_lobby_id)
	_lobby_id = 0
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = ""
	if was_open and reason != "":
		closed.emit(reason)


func _on_peer_connected(id: int) -> void:
	if not _open:
		return
	if is_host and peer_id != 0:
		return   # 3人目は無視
	peer_id = id
	if _steam_ready and _lobby_id != 0 and is_host:
		_steam.setLobbyJoinable(_lobby_id, false)
	connected.emit()


func _on_peer_disconnected(id: int) -> void:
	if _open and id == peer_id:
		close("相手との接続が切れました")


func _on_connection_failed() -> void:
	if _open:
		close("接続できませんでした")


func _on_server_disconnected() -> void:
	if _open:
		close("相手との接続が切れました")
