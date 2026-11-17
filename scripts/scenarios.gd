class_name Scenarios
extends RefCounted
## 台本のお客さんデータ。中身は data/scenarios.json（サーバーと共通のファイル）。
## データの形は docs/SPEC.md の「お客さんデータ」を参照。

const PATH: String = "res://data/scenarios.json"

static var _cache: Dictionary = {}


static func _load() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var f: FileAccess = FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("scenarios.json を開けません: %s" % PATH)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		var stages: Variant = (parsed as Dictionary).get("stages", {})
		if typeof(stages) == TYPE_DICTIONARY:
			_cache = stages
	return _cache


static func customers(stage_id: String) -> Array:
	var stages: Dictionary = _load()
	var list: Variant = stages.get(stage_id, stages.get("konbini", []))
	if typeof(list) == TYPE_ARRAY:
		return list
	return []
