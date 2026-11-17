class_name Scenarios
extends RefCounted
## 台本のお客さんデータ。日本語は data/scenarios.json、英語は data/scenarios.en.json（サーバーと共通のファイル）。
## データの形は docs/SPEC.md の「お客さんデータ」を参照。

static var _cache: Dictionary = {}


static func _load(lang: String) -> Dictionary:
	if _cache.has(lang):
		return _cache[lang]
	var path: String = "res://data/scenarios.json" if lang == "ja" else "res://data/scenarios.%s.json" % lang
	if not FileAccess.file_exists(path):
		path = "res://data/scenarios.json"
	var stages: Dictionary = {}
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("台本を開けません: %s" % path)
	else:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY and typeof((parsed as Dictionary).get("stages", null)) == TYPE_DICTIONARY:
			stages = (parsed as Dictionary)["stages"]
	_cache[lang] = stages
	return stages


static func customers(stage_id: String, lang: String = "") -> Array:
	var l: String = lang if lang != "" else GameSettings.language
	var stages: Dictionary = _load(l)
	var list: Variant = stages.get(stage_id, stages.get("konbini", []))
	if typeof(list) == TYPE_ARRAY:
		return list
	return []
