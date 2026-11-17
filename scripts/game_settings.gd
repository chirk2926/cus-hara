extends Node
## 設定・ログイン情報・ハイスコアの保存（オートロード: GameSettings）
##
## AIの使い方（solo_source）:
##   "server"  … ゲームサーバーに問い合わせる（既定。APIキーはサーバーにある）
##   "own_key" … プレイヤー自身の Claude APIキーで直接呼ぶ（サーバーが無いとき用）
##   "offline" … AIを使わず台本とキーワード判定だけ
## 対戦は常にサーバー経由。

const PATH: String = "user://settings.cfg"
## 配布版が最初に使うサーバー。運営するサーバーのURLが決まったらここを書き換える（docs/SERVER.md）。
const DEFAULT_SERVER_URL: String = "http://127.0.0.1:8787"
const MODELS: Array = [
	["claude-opus-5-5", "Claude Opus 5.5（高品質）"],
	["claude-sonnet-5-5", "Claude Sonnet 5.5（バランス）"],
	["claude-haiku-5-5", "Claude Haiku 5.5（高速・低コスト）"],
]
const SOURCES: Array = [
	["server", "ゲームサーバー（おすすめ）"],
	["own_key", "自分のAPIキー"],
	["offline", "AIを使わない（台本）"],
]

## 表示言語。"ja" | "en"。初回は OS の言語から決める
const LANGS: Array = [["ja", "日本語"], ["en", "English"]]
var language: String = ""
var server_url: String = DEFAULT_SERVER_URL
var token: String = ""
var player_name: String = ""
var solo_source: String = "server"
var api_key: String = ""
var model: String = "claude-opus-5-5"
var volume: float = 0.8
var fullscreen: bool = false
var push_to_talk_key: int = KEY_SPACE
var high_scores: Dictionary = {}
## サーバーから最後に受け取った自分の情報（表示用。正しい値は常にサーバーにある）
var last_profile: Dictionary = {}


func _ready() -> void:
	load_settings()
	# 起動引数 `-- --server=http://...` で接続先を一時的に変えられる（テスト用。保存はしない）
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server="):
			server_url = a.substr(9)
		elif a.begins_with("--profile="):
			# 同じPCで2つ起動して対戦を試すとき、ログイン情報を分ける
			_profile = a.substr(10)
			load_settings()
	if language == "":
		language = "ja" if OS.get_locale_language() == "ja" else "en"
	apply_language()
	apply_window()


## 画面の文言を切り替える。日本語の文をキーにして data/i18n/<言語>.json の訳を引く（docs/MAINTENANCE.md「翻訳」）
func apply_language() -> void:
	for t in _translations:
		TranslationServer.remove_translation(t)
	_translations.clear()
	if language != "ja":
		var f: FileAccess = FileAccess.open("res://data/i18n/%s.json" % language, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				var tr_res: Translation = Translation.new()
				tr_res.locale = language
				var dict: Dictionary = parsed
				for k in dict:
					tr_res.add_message(StringName(str(k)), StringName(str(dict[k])))
				TranslationServer.add_translation(tr_res)
				_translations.append(tr_res)
	TranslationServer.set_locale(language)


var _translations: Array = []
var _profile: String = ""


func _path() -> String:
	if _profile == "":
		return PATH
	return "user://settings_%s.cfg" % _profile.validate_filename()


func load_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(_path()) != OK:
		return
	language = str(cfg.get_value("ui", "language", language))
	if not ["ja", "en"].has(language):
		language = ""
	server_url = str(cfg.get_value("server", "url", server_url))
	token = str(cfg.get_value("server", "token", ""))
	player_name = str(cfg.get_value("server", "name", ""))
	var lp: Variant = cfg.get_value("server", "profile", {})
	if typeof(lp) == TYPE_DICTIONARY:
		last_profile = lp
	solo_source = str(cfg.get_value("ai", "source", solo_source))
	if not ["server", "own_key", "offline"].has(solo_source):
		solo_source = "server"
	api_key = str(cfg.get_value("ai", "api_key", ""))
	model = str(cfg.get_value("ai", "model", model))
	volume = float(cfg.get_value("audio", "volume", 0.8))
	push_to_talk_key = int(cfg.get_value("audio", "push_to_talk_key", KEY_SPACE))
	fullscreen = bool(cfg.get_value("video", "fullscreen", false))
	var hs: Variant = cfg.get_value("score", "high_scores", {})
	if typeof(hs) == TYPE_DICTIONARY:
		high_scores = hs


func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("ui", "language", language)
	cfg.set_value("server", "url", server_url)
	cfg.set_value("server", "token", token)
	cfg.set_value("server", "name", player_name)
	cfg.set_value("server", "profile", last_profile)
	cfg.set_value("ai", "source", solo_source)
	cfg.set_value("ai", "api_key", api_key)
	cfg.set_value("ai", "model", model)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "push_to_talk_key", push_to_talk_key)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("score", "high_scores", high_scores)
	cfg.save(_path())


func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


## 設定画面のキーが空なら環境変数 ANTHROPIC_API_KEY を使う（開発用）
func get_api_key() -> String:
	var k: String = api_key.strip_edges()
	if k == "":
		k = OS.get_environment("ANTHROPIC_API_KEY").strip_edges()
	return k


func own_key_ready() -> bool:
	return get_api_key() != ""


func get_high_score(stage_id: String) -> int:
	return int(high_scores.get(stage_id, 0))


func submit_score(stage_id: String, value: int) -> bool:
	if value > get_high_score(stage_id):
		high_scores[stage_id] = value
		save_settings()
		return true
	return false
