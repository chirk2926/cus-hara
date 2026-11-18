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
			# 台の種類（machine）からクレーンかどうかを決める（要件#54）
			for k in stages:
				for c in (stages[k] as Array):
					var d: Dictionary = c
					if d.has("machine"):
						d["crane"] = str(d["machine"]) == "crane"
	_cache[lang] = stages
	return stages


static func customers(stage_id: String, lang: String = "") -> Array:
	var l: String = lang if lang != "" else GameSettings.language
	var stages: Dictionary = _load(l)
	var list: Variant = stages.get(stage_id, stages.get("konbini", []))
	if typeof(list) == TYPE_ARRAY:
		return list
	return []


# ---------------------------------------------------------------- 「〇〇円使っても取れない」（要件#55, #57）
# サーバーの server/src/scenarios.ts の materializeSpend と同じ決まり（AIを使わないときにゲームの中で使う）

const PRIZE_COST: int = 1100


static func machine_of(c: Dictionary) -> String:
	if c.has("machine"):
		return str(c["machine"])
	return "crane" if bool(c.get("crane", false)) else "none"


## 「取れない」クレームの出やすさ: ペイアウト率 30% で 1 倍。低いほど出やすい
static func spend_weight(payout: int) -> float:
	return 30.0 / float(clampi(payout, 10, 80))


static func cost_per_prize(payout: int) -> int:
	return int(floor(float(PRIZE_COST) / (float(clampi(payout, 10, 80)) / 100.0)))


static func _round_to(n: float, step: int) -> int:
	return maxi(step, int(round(n / float(step))) * step)


## 言語ごとのお金の表記（要件#71: 円 / ドル / 元）
static func yen_text(n: int, lang: String) -> String:
	return GameSettings.money_in(n, lang)


## 金額を決めて {spent} を置き換える。spend: {claimed, actual, expected, payout} を入れる（lie は内部用に _lie）
static func materialize_spend(c: Dictionary, payout: int, lang: String = "") -> Dictionary:
	var flag: Variant = c.get("spend", false)
	if typeof(flag) != TYPE_BOOL or not flag:
		return c
	var l: String = lang if lang != "" else GameSettings.language
	var p: int = clampi(payout, 10, 80)
	var expected: int = cost_per_prize(p)
	var claimed: int = maxi(1000, _round_to(float(expected) * (0.6 + 0.7 * randf()), 500))
	var lie: bool = randf() < 0.4
	var actual: int = _round_to(float(claimed) * (0.15 + 0.3 * randf()), 100) if lie else _round_to(float(claimed) * (0.9 + 0.1 * randf()), 100)
	var text: String = yen_text(claimed, l)
	for k in ["title", "memo", "opening", "demand"]:
		c[k] = str(c.get(k, "")).replace("{spent}", text)
	var lines: Variant = c.get("lines", {})
	if typeof(lines) == TYPE_DICTIONARY:
		for k in (lines as Dictionary):
			var v: Variant = lines[k]
			if typeof(v) == TYPE_ARRAY:
				var arr: Array = []
				for x in (v as Array):
					arr.append(str(x).replace("{spent}", text))
				lines[k] = arr
			else:
				lines[k] = str(v).replace("{spent}", text)
	c["spend"] = {"claimed": claimed, "actual": actual, "expected": expected, "payout": p}
	c["_lie"] = lie
	var acts: Dictionary = (c.get("actions", {}) as Dictionary).duplicate() if typeof(c.get("actions", null)) == TYPE_DICTIONARY else {}
	if lie:
		acts["credit"] = "yield"
		var kw: Array = (c.get("solution_keywords", []) as Array).duplicate()
		kw.append_array({"ja": ["記録", "データ", "履歴", "実際"], "zh": ["记录", "数据", "实际"]}.get(l, ["record", "data", "log", "actually"]))
		c["solution_keywords"] = kw
	c["actions"] = acts
	return c

