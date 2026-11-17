extends Node
## 設定とハイスコアの保存（オートロード: GameSettings）

const PATH: String = "user://settings.cfg"
const MODELS: Array = [
	["claude-opus-5-5", "Claude Opus 5.5（高品質）"],
	["claude-sonnet-5-5", "Claude Sonnet 5.5（バランス）"],
	["claude-haiku-5-5", "Claude Haiku 5.5（高速・低コスト）"],
]

var api_key: String = ""
var model: String = "claude-opus-5-5"
var use_llm: bool = true
var volume: float = 0.8
var fullscreen: bool = false
var high_scores: Dictionary = {}

# 対戦モードのレーティング（このPCに保存）
const RATING_START: int = 1000
const RATING_K: float = 32.0
const VERSUS_RANKS: Array = [
	[1700, "伝説のクレーム処理班"],
	[1500, "エリアマネージャー"],
	[1350, "店長"],
	[1200, "副店長"],
	[1050, "バイトリーダー"],
	[900, "アルバイト"],
	[-999999, "研修生"],
]
var rating: int = RATING_START
var versus_wins: int = 0
var versus_losses: int = 0
var versus_draws: int = 0


func _ready() -> void:
	load_settings()
	apply_window()


func load_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	api_key = str(cfg.get_value("llm", "api_key", ""))
	model = str(cfg.get_value("llm", "model", model))
	use_llm = bool(cfg.get_value("llm", "enabled", true))
	volume = float(cfg.get_value("audio", "volume", 0.8))
	fullscreen = bool(cfg.get_value("video", "fullscreen", false))
	rating = int(cfg.get_value("versus", "rating", RATING_START))
	versus_wins = int(cfg.get_value("versus", "wins", 0))
	versus_losses = int(cfg.get_value("versus", "losses", 0))
	versus_draws = int(cfg.get_value("versus", "draws", 0))
	var hs: Variant = cfg.get_value("score", "high_scores", {})
	if typeof(hs) == TYPE_DICTIONARY:
		high_scores = hs


func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("llm", "api_key", api_key)
	cfg.set_value("llm", "model", model)
	cfg.set_value("llm", "enabled", use_llm)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("score", "high_scores", high_scores)
	cfg.set_value("versus", "rating", rating)
	cfg.set_value("versus", "wins", versus_wins)
	cfg.set_value("versus", "losses", versus_losses)
	cfg.set_value("versus", "draws", versus_draws)
	cfg.save(PATH)


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


func llm_ready() -> bool:
	return use_llm and get_api_key() != ""


func get_high_score(stage_id: String) -> int:
	return int(high_scores.get(stage_id, 0))


func submit_score(stage_id: String, value: int) -> bool:
	if value > get_high_score(stage_id):
		high_scores[stage_id] = value
		save_settings()
		return true
	return false


# ---------------------------------------------------------------- 対戦レーティング

static func rank_name(value: int) -> String:
	for r in VERSUS_RANKS:
		if value >= int(r[0]):
			return str(r[1])
	return "研修生"


## Elo方式の増減。score: 勝ち=1.0 / 引き分け=0.5 / 負け=0.0
static func elo_delta(mine: int, theirs: int, score: float) -> int:
	var expected: float = 1.0 / (1.0 + pow(10.0, float(theirs - mine) / 400.0))
	return int(round(RATING_K * (score - expected)))


## 対戦結果を記録して、レーティングの増減を返す
func record_versus(opponent_rating: int, score: float) -> int:
	var d: int = elo_delta(rating, opponent_rating, score)
	rating = maxi(0, rating + d)
	if score > 0.75:
		versus_wins += 1
	elif score < 0.25:
		versus_losses += 1
	else:
		versus_draws += 1
	save_settings()
	return d
