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
