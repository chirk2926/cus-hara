extends Node
## 設定・ログイン情報・ハイスコアの保存（オートロード: GameSettings）
##
## AIの使い方（solo_source）:
##   "server"  … ゲームサーバーに問い合わせる（既定。APIキーはサーバーにある）
##   "own_key" … プレイヤー自身の Claude APIキーで直接呼ぶ（サーバーが無いとき用）
##   "offline" … AIを使わず台本とキーワード判定だけ
## 対戦は常にサーバー経由。

const PATH: String = "user://settings.cfg"
## 接続するゲームサーバー（1つだけ。要件#31）。運営するサーバーのURLが決まったらここを書き換える（docs/SERVER.md）。
## 設定画面からは変えられない。テストのときだけ起動引数 `-- --server=URL` で変える。
const DEFAULT_SERVER_URL: String = "http://127.0.0.1:8787"
## 「自分のAPIキー」を選んだときだけ選べるモデル（要件#33。サーバーは Haiku だけを使う）
const MODELS: Array = [
	["claude-haiku-5-5", "Claude Haiku 5.5（高速・低コスト）"],
	["claude-sonnet-5-5", "Claude Sonnet 5.5（バランス）"],
	["claude-opus-5-5", "Claude Opus 5.5（高品質）"],
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
var model: String = "claude-haiku-5-5"
var volume: float = 0.8
var bgm_volume: float = 0.5
## 返事の時間（要件#35）。怒りの上がる速さにかける倍率: ゆっくり 0.6 / ふつう 1.0 / はやい 1.4
const ANSWER_TIMES: Array = [["slow", "ゆっくり（タイピングが苦手な人向け）"], ["normal", "ふつう"], ["fast", "はやい"]]
const ANSWER_RATE: Dictionary = {"slow": 0.6, "normal": 1.0, "fast": 1.4}
var answer_time: String = "normal"
var fullscreen: bool = false
## 解像度（ウィンドウの大きさ）。"auto" = 画面に収まる一番大きいもの。どれを選んでも、画面（タスクバーを除く）より大きくはしない
const RESOLUTIONS: Array = [
	["auto", "自動（画面に合わせる）"],
	["1280x720", "1280 × 720"],
	["1366x768", "1366 × 768"],
	["1600x900", "1600 × 900"],
	["1920x1080", "1920 × 1080"],
	["2560x1440", "2560 × 1440"],
]
## これより小さいウィンドウにはしない（画面の部品が入りきらなくなるため）
const MIN_WINDOW: Vector2i = Vector2i(960, 540)
var resolution: String = "auto"
## クレーンゲームの店の設定（要件#55）。"power"（パワー設定。既定）| "prob"（確率設定）と、ペイアウト率 10〜80%
var crane_mode: String = "power"
var crane_payout: int = 30
## チュートリアル（要件#53）を一度でも終えた／断ったか
var tutorial_seen: bool = false
## 起動引数 --resolution で大きさを決めたとき（テスト・スクリーンショット）は、保存した解像度で上書きしない
var _resolution_from_cmdline: bool = false
var push_to_talk_key: int = KEY_SPACE
var high_scores: Dictionary = {}
## サーバーから最後に受け取った自分の情報（表示用。正しい値は常にサーバーにある）
var last_profile: Dictionary = {}


func _ready() -> void:
	load_settings()
	# 起動引数 `-- --server=http://...` で接続先を一時的に変えられる（テスト用。保存はしない）
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--profile="):
			# 同じPCで2つ起動して対戦を試すとき、ログイン情報を分ける
			_profile = a.substr(10)
			load_settings()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--server="):
			server_url = a.substr(9)
	if language == "":
		language = "ja" if OS.get_locale_language() == "ja" else "en"
	_resolution_from_cmdline = OS.get_cmdline_args().has("--resolution")
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
	bgm_volume = float(cfg.get_value("audio", "bgm_volume", 0.5))
	answer_time = str(cfg.get_value("play", "answer_time", "normal"))
	if not ANSWER_RATE.has(answer_time):
		answer_time = "normal"
	push_to_talk_key = int(cfg.get_value("audio", "push_to_talk_key", KEY_SPACE))
	fullscreen = bool(cfg.get_value("video", "fullscreen", false))
	resolution = str(cfg.get_value("video", "resolution", "auto"))
	crane_mode = str(cfg.get_value("play", "crane_mode", "power"))
	if crane_mode != "prob":
		crane_mode = "power"
	crane_payout = clampi(int(cfg.get_value("play", "crane_payout", 30)), 10, 80)
	tutorial_seen = bool(cfg.get_value("play", "tutorial_seen", false))
	if not RESOLUTIONS.any(func(r: Array) -> bool: return str(r[0]) == resolution):
		resolution = "auto"
	var hs: Variant = cfg.get_value("score", "high_scores", {})
	if typeof(hs) == TYPE_DICTIONARY:
		high_scores = hs


func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("ui", "language", language)
	cfg.set_value("server", "token", token)
	cfg.set_value("server", "name", player_name)
	cfg.set_value("server", "profile", last_profile)
	cfg.set_value("ai", "source", solo_source)
	cfg.set_value("ai", "api_key", api_key)
	cfg.set_value("ai", "model", model)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "bgm_volume", bgm_volume)
	cfg.set_value("play", "answer_time", answer_time)
	cfg.set_value("audio", "push_to_talk_key", push_to_talk_key)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "resolution", resolution)
	cfg.set_value("play", "crane_mode", crane_mode)
	cfg.set_value("play", "crane_payout", crane_payout)
	cfg.set_value("play", "tutorial_seen", tutorial_seen)
	cfg.set_value("score", "high_scores", high_scores)
	cfg.save(_path())


## 画面の設定を反映する。ゲームの画面は 1280×720 を基準に、ウィンドウの大きさに合わせて拡大・縮小される
## （project.godot の stretch: canvas_items / expand）。なので、ウィンドウが画面に収まっていれば部品も必ず収まる。
func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_min_size(MIN_WINDOW)
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if _resolution_from_cmdline:
		return
	var screen: int = DisplayServer.window_get_current_screen()
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen)
	# タイトルバーや枠の分を少し残す
	var room: Vector2i = Vector2i(maxi(usable.size.x - 16, MIN_WINDOW.x), maxi(usable.size.y - 48, MIN_WINDOW.y))
	var want: Vector2i = window_size_for(resolution, room)
	DisplayServer.window_set_size(want)
	DisplayServer.window_set_position(usable.position + (usable.size - want) / 2)


## 解像度の設定から、実際のウィンドウの大きさを決める。room = 使える画面の大きさ
static func window_size_for(res: String, room: Vector2i) -> Vector2i:
	var want: Vector2i = Vector2i(1280, 720)
	if res == "auto":
		# 16:9 で、使える画面に収まる一番大きい候補
		want = Vector2i(1280, 720)
		for r in RESOLUTIONS:
			var v: Vector2i = parse_resolution(str(r[0]))
			if v.x > 0 and v.x <= room.x and v.y <= room.y and v.x > want.x:
				want = v
	else:
		want = parse_resolution(res)
	# 画面より大きければ、縦横の比を保って縮める
	if want.x > room.x or want.y > room.y:
		var k: float = minf(float(room.x) / float(want.x), float(room.y) / float(want.y))
		want = Vector2i(int(want.x * k), int(want.y * k))
	return Vector2i(maxi(want.x, MIN_WINDOW.x), maxi(want.y, MIN_WINDOW.y))


static func parse_resolution(res: String) -> Vector2i:
	var parts: PackedStringArray = res.split("x")
	if parts.size() != 2:
		return Vector2i(1280, 720)
	return Vector2i(int(parts[0]), int(parts[1]))


func get_api_key() -> String:
	var k: String = api_key.strip_edges()
	if k == "":
		k = OS.get_environment("ANTHROPIC_API_KEY").strip_edges()
	return k


func own_key_ready() -> bool:
	return get_api_key() != ""


## 怒りの上がる速さにかける倍率（1人用とフレンド対戦）
## 店の売上・レビュー・「取れない」クレームの出やすさに効くペイアウト率。確率設定でないときは既定の 30%
func effective_payout() -> int:
	return crane_payout if crane_mode == "prob" else 30


func answer_rate() -> float:
	return float(ANSWER_RATE.get(answer_time, 1.0))


func get_high_score(stage_id: String) -> int:
	return int(high_scores.get(stage_id, 0))


func submit_score(stage_id: String, value: int) -> bool:
	if value > get_high_score(stage_id):
		high_scores[stage_id] = value
		save_settings()
		return true
	return false
