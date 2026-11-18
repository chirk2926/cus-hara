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

## 表示言語。"ja" | "en" | "zh"（簡体字中国語。要件#71）。初回は OS の言語から決める
const LANGS: Array = [["ja", "日本語"], ["en", "English"], ["zh", "简体中文"]]
## 言語ごとのお金の単位（要件#71）。中身の計算はすべて円で、表示するときだけ換える。1プレイ = 100円 = 1ドル = 8元
const CURRENCY: Dictionary = {
	"ja": {"rate": 1.0, "prefix": "", "suffix": "円"},
	"en": {"rate": 0.01, "prefix": "$", "suffix": ""},
	"zh": {"rate": 0.08, "prefix": "", "suffix": "元"},
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
const ANSWER_TIMES: Array = [["slow", "ゆっくり（タイピングが苦手な人向け）"], ["normal", "ふつう"], ["fast", "はやい"]]
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
	["2560x1440", "2560 × 1440"],
]
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
const MENTAL_XP: Array = [0, 800, 1800, 3000, 4400, 6000, 7800, 9800, 12000, 14400,
	17000, 19800, 22800, 26000, 29400, 33000, 36800, 40800, 45000, 49400]
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
## ショップ（要件#82）: HP（ハラスメントポイント・オフラインの給与）と KAS（カスポイント・オンラインの給与）、
## 持っているもの（"カテゴリ:ID"）、使っているもの（カテゴリ → ID）
var hp_points: int = 0
var kas_points: int = 0
var owned_items: Array = []
var equipped_items: Dictionary = {}
## 対戦のキャラクター（要件#84）: 性別・身長・体型・肌の色（髪型などはショップの equipped_items）。created は作ったか
var avatar: Dictionary = {}
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
		var os_lang: String = OS.get_locale_language()
		language = os_lang if os_lang in ["ja", "zh"] else "en"
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


var _translations: Array = []
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
	if not ["ja", "en", "zh"].has(language):
		language = ""
	token = str(cfg.get_value("server", "token", ""))
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
	crane_mode = str(cfg.get_value("play", "crane_mode", "power"))
	if crane_mode != "prob":
		crane_mode = "power"
	crane_payout = clampi(int(cfg.get_value("play", "crane_payout", 30)), 10, 80)
	tutorial_seen = bool(cfg.get_value("play", "tutorial_seen", false))
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
	_save_secret_key(api_key)
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
	cfg.set_value("play", "mental_xp", mental_xp)
	cfg.set_value("play", "stats", stats)
	cfg.set_value("play", "titles", unlocked_titles)
	cfg.set_value("play", "title", equipped_title)
	cfg.set_value("shop", "hp", hp_points)
	cfg.set_value("shop", "kas", kas_points)
	cfg.set_value("shop", "owned", owned_items)
	cfg.set_value("shop", "equipped", equipped_items)
	cfg.set_value("shop", "avatar", avatar)
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
		return
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


## 自分の API キーの保存先（暗号化。鍵はこのPCの固有ID。別のPCにコピーしても開けない）
func _secret_path() -> String:
	return _path().get_basename() + "_secret.cfg"


func _load_secret_key() -> String:
	var c: ConfigFile = ConfigFile.new()
	if c.load_encrypted_pass(_secret_path(), OS.get_unique_id() + "cushara") != OK:
		return ""
	return str(c.get_value("ai", "api_key", ""))


func _save_secret_key(key: String) -> void:
	var c: ConfigFile = ConfigFile.new()
	c.set_value("ai", "api_key", key)
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
