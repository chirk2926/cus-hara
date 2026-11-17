extends RefCounted
## 店の行動ボタン（割引・土下座・メダル返還・補填）と、台の調整の結果。要件#34, #37
## 表は data/actions.json（サーバーの server/src/actions.ts と共通）。お客さんごとの効果は台本の actions。

const Judge = preload("res://scripts/offline_judge.gd")

## 台の調整（ボタンの id。押すとミニゲームを開く）
const CRANE_ADJUST: String = "crane_adjust"

static var _table: Dictionary = {}


static func table() -> Dictionary:
	if _table.is_empty():
		var f: FileAccess = FileAccess.open("res://data/actions.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_table = parsed
	return _table


static func _lang() -> String:
	return "en" if GameSettings.language == "en" else "ja"


## そのお客さんに出すボタン: [[id, 表示名], ...]。with_crane: 台の調整を出すか（1人用のみ）
static func buttons(stage_id: String, customer: Dictionary, with_crane: bool) -> Array:
	var out: Array = []
	var ids: Array = (table().get("stages", {}) as Dictionary).get(stage_id, [])
	var labels: Dictionary = (table().get("labels", {}) as Dictionary).get(_lang(), {})
	for id in ids:
		out.append([str(id), str(labels.get(str(id), str(id)))])
	if with_crane and stage_id == "arcade" and bool(customer.get("crane", false)):
		out.append([CRANE_ADJUST, "台を調整する"])
	return out


static func effect_kind(customer: Dictionary, id: String) -> String:
	if id == "crane_won" or id == "crane_lost":
		return id
	var a: Variant = customer.get("actions", {})
	if typeof(a) == TYPE_DICTIONARY and (a as Dictionary).has(id):
		return str((a as Dictionary)[id])
	return str((table().get("default", {}) as Dictionary).get(id, "neutral"))


## サーバーを使わないときの判定（表どおり。お客さんの返事は台本）
static func judge(customer: Dictionary, id: String, anger: float, resolve: float) -> Dictionary:
	var kind: String = effect_kind(customer, id)
	var effects: Dictionary = table().get("effects", {})
	var e: Dictionary = effects.get(kind, effects.get("neutral", {}))
	var yielded: bool = bool(e.get("yielded", false))
	var a: int = int(e.get("anger", 0))
	var r: int = int(e.get("resolve", 0))
	var reply: String = str(e.get("reply", "neutral"))
	if not yielded and anger + a >= 100.0:
		reply = "explode"
	elif not yielded and resolve + r >= 100.0:
		reply = "resolved"
	var comments: Dictionary = (table().get("comments", {}) as Dictionary).get(_lang(), {})
	return {
		"anger_delta": a,
		"resolve_delta": r,
		"yielded": yielded,
		"customer_reply": Judge.line(customer, reply),
		"comment": str(comments.get(kind, "")),
		"action": id,
	}


static func label(id: String) -> String:
	var labels: Dictionary = (table().get("labels", {}) as Dictionary).get(_lang(), {})
	return str(labels.get(id, id))
