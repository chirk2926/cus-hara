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
## 配る版のゲームサーバー（本番。要件#119）
const DEFAULT_SERVER_URL: String = "https://game.mgc-sv.com"
## 開発（エディタ・CI）とテスト版の exe は、同じPCのテスト用サーバー（start_server.bat）につなぐ
const LOCAL_SERVER_URL: String = "http://127.0.0.1:8787"
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

## 表示言語。"ja" | "en" | "zh"（簡体字中国語。要件#71） | "ko"（韓国語。要件#102）。初回は OS の言語から決める
const LANGS: Array = [["ja", "日本語"], ["en", "English"], ["zh", "简体中文"], ["ko", "한국어"]]
## 言語ごとのお金の単位（要件#71）。中身の計算はすべて円で、表示するときだけ換える。1プレイ = 100円 = 1ドル = 8元
const CURRENCY: Dictionary = {
	"ja": {"rate": 1.0, "prefix": "", "suffix": "円"},
	"en": {"rate": 0.01, "prefix": "$", "suffix": ""},
	"zh": {"rate": 0.08, "prefix": "", "suffix": "元"},
	"ko": {"rate": 10.0, "prefix": "", "suffix": "원"},   # 1プレイ = 1,000원（要件#102）
}
var language: String = ""
var server_url: String = DEFAULT_SERVER_URL
var token: String = ""
var player_name: String = ""
var solo_source: String = "server"
var api_key: String = ""
var _migrate_key: bool = false   # 古い版の平文のキーを、暗号化ファイルへ移す
var model: String = "claude-haiku-5-5"
var volume: float = 0.8
var bgm_volume: float = 0.5
## 返事の時間（要件#35）。怒りの上がる速さにかける倍率: ゆっくり 0.6 / ふつう 1.0 / はやい 1.4
const ANSWER_TIMES: Array = [["slow", "かめ（イージー）"], ["normal", "うさぎ（ノーマル）"], ["fast", "チーター（ハード）"]]
const ANSWER_RATE: Dictionary = {"slow": 0.6, "normal": 1.0, "fast": 1.4}
var answer_time: String = "normal"
var fullscreen: bool = true   # 既定はフルスクリーン（要件#69）
## 解像度（ウィンドウの大きさ）。"auto" = 画面に収まる一番大きいもの。どれを選んでも、画面（タスクバーを除く）より大きくはしない
const RESOLUTIONS: Array = [
	["auto", "自動（画面に合わせる）"],
	["1280x720", "1280 × 720"],
	["1366x768", "1366 × 768"],
	["1600x900", "1600 × 900"],
	["1920x1080", "1920 × 1080"],
	["1440x900", "1440 × 900（16:10）"],
	["1920x1200", "1920 × 1200（16:10）"],
	["2560x1080", "2560 × 1080（21:9）"],
	["2560x1440", "2560 × 1440"],
	["3440x1440", "3440 × 1440（21:9）"],
	["3840x2160", "3840 × 2160（4K）"],
]
## 描画の解像度（3D の部分を何割の大きさで描くか。文字や UI はいつもくっきり。要件#95）。下げると軽くなる
const RENDER_SCALES: Array = [["1.0", "100%（きれい）"], ["0.85", "85%"], ["0.75", "75%"], ["0.5", "50%（軽い）"]]
var render_scale: String = "1.0"
## 垂直同期（要件#95）。on = ずれ（ティアリング）なし / adaptive = フレームが落ちたときだけ同期を外す / off = 遅れが最小
const VSYNC_MODES: Array = [["on", "オン"], ["adaptive", "アダプティブ"], ["off", "オフ"]]
var vsync: String = "on"
## フレームレートの上限（0 = 上限なし）
const FPS_LIMITS: Array = [["0", "上限なし"], ["30", "30"], ["60", "60"], ["120", "120"], ["144", "144"], ["165", "165"], ["240", "240"]]
var max_fps: String = "0"
## 可変リフレッシュレート（G-SYNC / FreeSync。要件#95）。オンにすると、フルスクリーン（排他）・垂直同期オン・
## 上限をリフレッシュレートより少し下にする（可変リフレッシュレートの範囲から外れないようにする、よくあるやり方）
var vrr: bool = false
## これより小さいウィンドウにはしない（画面の部品が入りきらなくなるため）
const MIN_WINDOW: Vector2i = Vector2i(960, 540)
var resolution: String = "auto"
## クレーンゲームの店の設定（要件#55）。"power"（パワー設定。既定）| "prob"（確率設定）と、ペイアウト率 10〜80%
var crane_mode: String = "power"
var crane_payout: int = 30
## メンタルランク（要件#72）。1〜20。
## A（通常モード）: シフトをこなすと経験値がたまって上がる。B（素材型・対戦）: レーティングから決まる（最初の 1000 で 10）
const MENTAL_A: Array = ["崩壊寸前", "限界ギリギリ", "ボロボロ", "絶不調", "ぐらつき", "ビクビク", "動揺", "ざわつき", "ぎこちない", "まずまず",
	"平常心", "落ち着き", "安定", "しなやか", "堅実", "動じない", "不屈", "鋼の心", "明鏡止水", "悟り"]
const MENTAL_B: Array = ["豆腐", "綿あめ", "プリン", "薄氷", "ガラス", "紙", "粘土", "ゴム", "竹", "木",
	"石", "レンガ", "銅", "鉄", "鋼鉄", "チタン", "ミスリル", "オリハルコン", "ダイヤモンド", "アダマンタイト"]
## 【仮の値】A の各ランクに必要な経験値の合計（ランク n になるのに MENTAL_XP[n-1] 以上）。後で調整する
## 要件#91: 11 からは上がりにくく（必要な経験値を多めに）
const MENTAL_XP: Array = [0, 800, 1800, 3000, 4400, 6000, 7800, 9800, 12000, 14400,
	18800, 24000, 30000, 37000, 45000, 54000, 64000, 75000, 87000, 100000]
## 【仮の値】1シフトでもらえる経験値 = 最後まで出た分 + 合計点（マイナスは 0）
const MENTAL_XP_SHIFT: int = 200
## 【仮の値】B: レート 1000 で 10、レート 60 ごとに 1 つ上下
const MENTAL_B_BASE_RATING: int = 1000
const MENTAL_B_STEP: int = 60
var mental_xp: int = 0
## 称号（要件#79）: 記録・手に入れた称号・つけている称号
var stats: Dictionary = {}
var unlocked_titles: Array = []
var equipped_title: String = ""
## ショップ（要件#82）: HP（ハラスメントポイント・オフラインの給与）と CUS（カスポイント・オンラインの給与）、
## 持っているもの（"カテゴリ:ID"）、使っているもの（カテゴリ → ID）
var hp_points: int = 0
var kas_points: int = 0
var owned_items: Array = []
var equipped_items: Dictionary = {}
## 対戦のキャラクター（要件#84）: 性別・身長・体型・肌の色（髪型などはショップの equipped_items）。created は作ったか
var avatar: Dictionary = {}
## レビューログ（要件#86）: シフトごとの記録。新しい順に最大 200 件。このPCに保存
var review_log: Array = []
const REVIEW_LOG_MAX: int = 200
## チュートリアル（要件#53）を一度でも終えた／断ったか
var tutorial_seen: bool = false
## 初めて起動したときに難しさ（かめ・うさぎ・チーター）を選んだか（要件#91）
var difficulty_asked: bool = false
## 対戦の発言の取り扱いに同意した版（要件#101。0 = していない）。サーバーの記録が正で、ログインのたびに合わせる
var vs_consent: int = 0
## 起動引数 --resolution で大きさを決めたとき（テスト・スクリーンショット）は、保存した解像度で上書きしない
var _resolution_from_cmdline: bool = false
var push_to_talk_key: int = KEY_SPACE
var high_scores: Dictionary = {}
## サーバーから最後に受け取った自分の情報（表示用。正しい値は常にサーバーにある）
var last_profile: Dictionary = {}


## テスト版（要件#85）: テスト用の書き出し（機能タグ testbuild）か、起動引数 `-- --test`。デバッグパネルが出て、セーブは別のファイル
var is_test: bool = false


## セーブの置き場所を「CusHara」に決めた（ゲームの名前を英語にしたので、名前で決まる置き場所だと変わってしまう）。
## 前の置き場所（%APPDATA%/Godot/app_userdata/カスハラ防衛線）にセーブがあれば、初回だけ写す
func _migrate_old_saves() -> void:
	# Windows・macOS は「Godot」、Linux は「godot」
	var old_dir: String = ""
	for g in ["Godot", "godot"]:
		var cand: String = OS.get_data_dir().path_join(g).path_join("app_userdata").path_join("カスハラ防衛線")
		if DirAccess.dir_exists_absolute(cand):
			old_dir = cand
			break
	var new_dir: String = OS.get_user_data_dir()
	if old_dir == "" or old_dir == new_dir:
		return
	if FileAccess.file_exists("user://.migrated") or FileAccess.file_exists(PATH):
		return
	_copy_dir(old_dir, new_dir)
	var f: FileAccess = FileAccess.open("user://.migrated", FileAccess.WRITE)
	if f != null:
		f.store_string("1")


static func _copy_dir(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	var d: DirAccess = DirAccess.open(from)
	if d == null:
		return
	for name in d.get_files():
		if not FileAccess.file_exists(to.path_join(name)):
			DirAccess.copy_absolute(from.path_join(name), to.path_join(name))
	# フォルダ（ログ・シェーダーのキャッシュなど）は写さない。セーブはどれも直下のファイル


func _ready() -> void:
	_migrate_old_saves()
	# `--test` はデバッグ用のビルド（エディタ・CI）でだけ効く。リリース版の exe では引数をつけてもデバッグパネルは出ない（要件#93）
	is_test = OS.has_feature("testbuild") or (OS.is_debug_build() and OS.get_cmdline_user_args().has("--test"))
	if is_test:
		_profile = "test"
	load_settings()
	# 起動引数 `-- --server=http://...` で接続先を一時的に変えられる（テスト用。保存はしない）
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--profile="):
			# 同じPCで2つ起動して対戦を試すとき、ログイン情報を分ける
			_profile = a.substr(10) if not is_test else "test_" + a.substr(10)
			load_settings()
	# 接続先を変える引数は、開発・テスト版だけ（要件#108: 配る版では、保存したログイン情報をほかのサーバーへ送らない）
	if dev_args_allowed():
		server_url = LOCAL_SERVER_URL
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--server="):
				server_url = a.substr(9)
	if language == "":
		var os_lang: String = OS.get_locale_language()
		language = os_lang if os_lang in ["ja", "zh", "ko"] else "en"
	_resolution_from_cmdline = OS.get_cmdline_args().has("--resolution")
	_finish_migration()
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
	# ウィンドウの名前も表示の言語で（要件#102）
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title(short_app_name())


var _translations: Array = []


## ウィンドウ・タスクバーに出す短いゲームの名前（言語ごと。知らない言語は英語）
const SHORT_NAMES: Dictionary = {"ja": "カスハラ防衛線", "en": "Kasuhara Defense Line", "zh": "顾客骚扰防线", "ko": "카스하라 방어선"}   # no-tr


func short_app_name() -> String:
	return str(SHORT_NAMES.get(language, SHORT_NAMES["en"]))
var _profile: String = ""


## 古い版の設定ファイルに平文のキーがあれば、暗号化ファイルへ移して消す
func _finish_migration() -> void:
	if _migrate_key:
		_migrate_key = false
		save_settings()


func _path() -> String:
	if _profile == "":
		return PATH
	return "user://settings_%s.cfg" % _profile.validate_filename()


func load_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(_path()) != OK:
		return
	language = str(cfg.get_value("ui", "language", language))
	if not ["ja", "en", "zh", "ko"].has(language):
		language = ""
	# ログインの合言葉も暗号化ファイルへ（要件#108）。古い版の平文の値があれば読んで移す
	token = _load_secret("server", "token")
	if token == "" and str(cfg.get_value("server", "token", "")) != "":
		token = str(cfg.get_value("server", "token", ""))
		_migrate_key = true
	player_name = str(cfg.get_value("server", "name", ""))
	var lp: Variant = cfg.get_value("server", "profile", {})
	if typeof(lp) == TYPE_DICTIONARY:
		last_profile = lp
	solo_source = str(cfg.get_value("ai", "source", solo_source))
	if not ["server", "own_key", "offline"].has(solo_source):
		solo_source = "server"
	# 自分の API キーは、このPCだけで開ける暗号化ファイルに置く（要件#77）。古い版の平文の値があれば移す
	api_key = _load_secret_key()
	var old_plain: String = str(cfg.get_value("ai", "api_key", ""))
	if old_plain != "":
		if api_key == "":
			api_key = old_plain
		_migrate_key = true
	model = str(cfg.get_value("ai", "model", model))
	volume = float(cfg.get_value("audio", "volume", 0.8))
	bgm_volume = float(cfg.get_value("audio", "bgm_volume", 0.5))
	answer_time = str(cfg.get_value("play", "answer_time", "normal"))
	if not ANSWER_RATE.has(answer_time):
		answer_time = "normal"
	push_to_talk_key = int(cfg.get_value("audio", "push_to_talk_key", KEY_SPACE))
	fullscreen = bool(cfg.get_value("video", "fullscreen", true))
	resolution = str(cfg.get_value("video", "resolution", "auto"))
	render_scale = _pick(RENDER_SCALES, str(cfg.get_value("video", "render_scale", "1.0")), "1.0")
	vsync = _pick(VSYNC_MODES, str(cfg.get_value("video", "vsync", "on")), "on")
	max_fps = _pick(FPS_LIMITS, str(cfg.get_value("video", "max_fps", "0")), "0")
	vrr = bool(cfg.get_value("video", "vrr", false))
	crane_mode = str(cfg.get_value("play", "crane_mode", "power"))
	if crane_mode != "prob":
		crane_mode = "power"
	crane_payout = clampi(int(cfg.get_value("play", "crane_payout", 30)), 10, 80)
	tutorial_seen = bool(cfg.get_value("play", "tutorial_seen", false))
	difficulty_asked = bool(cfg.get_value("play", "difficulty_asked", false))
	vs_consent = int(cfg.get_value("play", "vs_consent", 0))
	mental_xp = maxi(0, int(cfg.get_value("play", "mental_xp", 0)))
	var st: Variant = cfg.get_value("play", "stats", {})
	stats = st if typeof(st) == TYPE_DICTIONARY else {}
	var ut: Variant = cfg.get_value("play", "titles", [])
	unlocked_titles = ut if typeof(ut) == TYPE_ARRAY else []
	equipped_title = str(cfg.get_value("play", "title", ""))
	hp_points = maxi(0, int(cfg.get_value("shop", "hp", 0)))
	kas_points = maxi(0, int(cfg.get_value("shop", "kas", 0)))
	var oi: Variant = cfg.get_value("shop", "owned", [])
	owned_items = oi if typeof(oi) == TYPE_ARRAY else []
	var ei: Variant = cfg.get_value("shop", "equipped", {})
	equipped_items = ei if typeof(ei) == TYPE_DICTIONARY else {}
	var av: Variant = cfg.get_value("shop", "avatar", {})
	avatar = av if typeof(av) == TYPE_DICTIONARY else {}
	var rl: Variant = cfg.get_value("play", "review_log", [])
	review_log = rl if typeof(rl) == TYPE_ARRAY else []
	if not RESOLUTIONS.any(func(r: Array) -> bool: return str(r[0]) == resolution):
		resolution = "auto"
	var hs: Variant = cfg.get_value("score", "high_scores", {})
	if typeof(hs) == TYPE_DICTIONARY:
		high_scores = hs


func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("ui", "language", language)
	cfg.set_value("server", "name", player_name)
	cfg.set_value("server", "profile", last_profile)
	cfg.set_value("ai", "source", solo_source)
	_save_secret_key(api_key)
	cfg.set_value("ai", "model", model)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "bgm_volume", bgm_volume)
	cfg.set_value("play", "answer_time", answer_time)
	cfg.set_value("audio", "push_to_talk_key", push_to_talk_key)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "render_scale", render_scale)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "max_fps", max_fps)
	cfg.set_value("video", "vrr", vrr)
	cfg.set_value("video", "resolution", resolution)
	cfg.set_value("play", "crane_mode", crane_mode)
	cfg.set_value("play", "crane_payout", crane_payout)
	cfg.set_value("play", "tutorial_seen", tutorial_seen)
	cfg.set_value("play", "difficulty_asked", difficulty_asked)
	cfg.set_value("play", "vs_consent", vs_consent)
	cfg.set_value("play", "mental_xp", mental_xp)
	cfg.set_value("play", "stats", stats)
	cfg.set_value("play", "titles", unlocked_titles)
	cfg.set_value("play", "title", equipped_title)
	cfg.set_value("shop", "hp", hp_points)
	cfg.set_value("shop", "kas", kas_points)
	cfg.set_value("shop", "owned", owned_items)
	cfg.set_value("shop", "equipped", equipped_items)
	cfg.set_value("shop", "avatar", avatar)
	cfg.set_value("play", "review_log", review_log)
	cfg.set_value("score", "high_scores", high_scores)
	cfg.save(_path())


## 画面の設定を反映する。ゲームの画面は 1280×720 を基準に、ウィンドウの大きさに合わせて拡大・縮小される
## （project.godot の stretch: canvas_items / expand）。なので、ウィンドウが画面に収まっていれば部品も必ず収まる。
func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_min_size(MIN_WINDOW)
	# テスト・スクリーンショットで大きさを指定したときは、ウィンドウのまま
	if _resolution_from_cmdline:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		apply_video()
		return
	if fullscreen or vrr:
		# 可変リフレッシュレートは、Windows では排他のフルスクリーンがいちばん確実に効く
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if vrr else DisplayServer.WINDOW_MODE_FULLSCREEN)
		apply_video()
		return
	apply_video()
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
## 描画の解像度・垂直同期・フレームレートの上限を反映する（要件#95）
func apply_video() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var sc: float = clampf(float(render_scale), 0.5, 1.0)
		tree.root.scaling_3d_scale = sc
		# 下げたときは FSR で拡大する（Forward+ のとき。ぼやけにくい）
		tree.root.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if sc < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	if DisplayServer.get_name() == "headless":
		return
	var mode: int = DisplayServer.VSYNC_ENABLED
	if not vrr:
		mode = {"on": DisplayServer.VSYNC_ENABLED, "adaptive": DisplayServer.VSYNC_ADAPTIVE, "off": DisplayServer.VSYNC_DISABLED}.get(vsync, DisplayServer.VSYNC_ENABLED)
	DisplayServer.window_set_vsync_mode(mode)
	Engine.max_fps = fps_cap()


## 実際のフレームレートの上限（0 = 上限なし）。可変リフレッシュレートのときはリフレッシュレート − 3
func fps_cap() -> int:
	var cap: int = int(max_fps)
	if vrr:
		var hz: float = DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen()) if DisplayServer.get_name() != "headless" else -1.0
		if hz > 0.0:
			var v: int = int(floor(hz)) - 3
			cap = v if cap <= 0 else mini(cap, v)
	return maxi(cap, 0)


var _screen_seen: int = -1
var _screen_timer: float = 0.0


## 可変リフレッシュレートのとき、ウィンドウが別のモニターに移ったら上限をそのモニターに合わせ直す
func _process(delta: float) -> void:
	if not vrr:
		return
	_screen_timer += delta
	if _screen_timer < 1.0:
		return
	_screen_timer = 0.0
	if DisplayServer.get_name() == "headless":
		return
	var sc: int = DisplayServer.window_get_current_screen()
	if sc != _screen_seen:
		_screen_seen = sc
		Engine.max_fps = fps_cap()


static func _pick(list: Array, v: String, fallback: String) -> String:
	for r in list:
		if str(r[0]) == v:
			return v
	return fallback


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


## 自分の API キーの保存先（暗号化。鍵はこのPCの固有ID。別のPCにコピーしても開けない）
func _secret_path() -> String:
	return _path().get_basename() + "_secret.cfg"


func _load_secret_key() -> String:
	return _load_secret("ai", "api_key")


func _load_secret(section: String, key: String) -> String:
	var c: ConfigFile = ConfigFile.new()
	if c.load_encrypted_pass(_secret_path(), OS.get_unique_id() + "cushara") != OK:
		return ""
	return str(c.get_value(section, key, ""))


## API キーとログインの合言葉（要件#108）を、このPCだけで開ける暗号化ファイルに書く
func _save_secret_key(key: String) -> void:
	var c: ConfigFile = ConfigFile.new()
	c.set_value("ai", "api_key", key)
	c.set_value("server", "token", token)
	c.save_encrypted_pass(_secret_path(), OS.get_unique_id() + "cushara")


func get_api_key() -> String:
	var k: String = api_key.strip_edges()
	if k == "":
		k = OS.get_environment("ANTHROPIC_API_KEY").strip_edges()
	return k


func own_key_ready() -> bool:
	return get_api_key() != ""


## 怒りの上がる速さにかける倍率（1人用とフレンド対戦）
## 称号の記録（要件#79）
func stat(key: String) -> int:
	return int(stats.get(key, 0))


func stat_add(key: String, n: int = 1) -> void:
	stats[key] = stat(key) + n


func stat_max(key: String, v: int) -> void:
	if v > stat(key):
		stats[key] = v


## 遊んだ言語（「三か国語の店員」用）
func stat_lang(lang: String) -> void:
	stat_list_add("langs", lang)


## 記録の「集めたものの一覧」に足す（同じものは1回だけ）
func stat_list_add(key: String, v: String) -> void:
	var list: Array = stats.get(key, []) if typeof(stats.get(key, null)) == TYPE_ARRAY else []
	if not list.has(v):
		list.append(v)
	stats[key] = list


## メンタルランク A（通常モード）。1〜20
func mental_rank() -> int:
	return mental_rank_for_xp(mental_xp)


static func mental_rank_for_xp(xp: int) -> int:
	var r: int = 1
	for i in range(MENTAL_XP.size()):
		if xp >= int(MENTAL_XP[i]):
			r = i + 1
	return r


## シフトの結果で経験値を足す。戻り値 {"before", "after", "gain"}
func add_mental_xp(total: int) -> Dictionary:
	var before: int = mental_rank()
	var gain: int = MENTAL_XP_SHIFT + maxi(0, total)
	mental_xp += gain
	save_settings()
	return {"before": before, "after": mental_rank(), "gain": gain}


## 次のランクまでの経験値（MAX なら -1）
func mental_xp_to_next() -> int:
	var r: int = mental_rank()
	if r >= MENTAL_XP.size():
		return -1
	return int(MENTAL_XP[r]) - mental_xp


## メンタルランク B（対戦。素材型）: レーティングから決まる
static func mental_rank_b(rating: int) -> int:
	return clampi(10 + int(floor(float(rating - MENTAL_B_BASE_RATING) / float(MENTAL_B_STEP))), 1, 20)


func mental_name_a(rank: int) -> String:
	return tr(str(MENTAL_A[clampi(rank, 1, 20) - 1]))


func mental_name_b(rank: int) -> String:
	return tr(str(MENTAL_B[clampi(rank, 1, 20) - 1]))


## 店の売上・レビュー・「取れない」クレームの出やすさに効くペイアウト率。確率設定でないときは既定の 30%
func effective_payout() -> int:
	return crane_payout if crane_mode == "prob" else 30


## 円の金額を、今の言語のお金の表記にする（例: 3500 → "3,500円" / "$35" / "280元"）
func money(yen: int) -> String:
	return money_in(yen, language)


static func money_in(yen: int, lang: String) -> String:
	var c: Dictionary = CURRENCY.get(lang, CURRENCY["ja"])
	var v: float = float(yen) * float(c["rate"])
	var neg: bool = v < 0.0
	v = absf(v)
	var whole: int = int(floor(v + 0.0001))
	var cents: int = int(round((v - float(whole)) * 100.0))
	if cents >= 100:
		whole += 1
		cents = 0
	var s: String = str(whole)
	var out: String = ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	var num: String = s + out
	if cents > 0:
		num += ".%02d" % cents
	return ("-" if neg else "") + str(c["prefix"]) + num + str(c["suffix"])


## 開発・テスト用の起動引数を受け付けるか（エディタ・デバッグ版・テスト版の exe）。配る版は false（要件#108）
func dev_args_allowed() -> bool:
	return OS.is_debug_build() or OS.has_feature("testbuild")


func answer_rate() -> float:
	return float(ANSWER_RATE.get(answer_time, 1.0))


## サーバーの管理画面で決めた「キレるまでの秒数」（要件#106）。サーバーにつないでいるときだけ。無ければ 0
var server_snap_seconds: Dictionary = {}


func snap_seconds() -> float:
	return float(server_snap_seconds.get(answer_time, 0.0))


func get_high_score(stage_id: String) -> int:
	return int(high_scores.get(stage_id, 0))


func submit_score(stage_id: String, value: int) -> bool:
	if value > get_high_score(stage_id):
		high_scores[stage_id] = value
		save_settings()
		return true
	return false


## シフトの記録をレビューログに足す（新しいものが先頭）
func add_review_log(entry: Dictionary) -> void:
	review_log.push_front(entry)
	while review_log.size() > REVIEW_LOG_MAX:
		review_log.pop_back()


## 返事の入力欄の最大文字数（要件#91）: 日本語・中国語 128、英語 256
func reply_max_length() -> int:
	return 256 if language == "en" else 128


## 退職（データ削除。要件#91）: このPCの設定・記録・持ち物を全部消す。サーバーのアカウントは残る（ログインし直すと新しい名札になる）
func wipe_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path()))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_secret_path()))
	token = ""
	player_name = ""
	last_profile = {}
	stats = {}
	unlocked_titles = []
	equipped_title = ""
	hp_points = 0
	kas_points = 0
	owned_items = []
	equipped_items = {}
	avatar = {}
	review_log = []
	mental_xp = 0
	tutorial_seen = false
	difficulty_asked = false
	vs_consent = 0
	high_scores = {}
	api_key = ""

