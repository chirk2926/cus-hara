extends RefCounted
## 店の行動ボタンと、台の調整の結果。要件#34, #37, #54
## ゲームセンターは、お客さんの台の種類（machine: crane / medal / rhythm / video / none）でボタンが変わる。
## 表は data/actions.json（サーバーの server/src/actions.ts と共通）。お客さんごとの効果は台本の actions。

const Judge = preload("res://scripts/offline_judge.gd")
const Scenarios = preload("res://scripts/scenarios.gd")

## 台の調整（ボタンの id。押すとミニゲームを開く）
const CRANE_ADJUST: String = "crane_adjust"   # 難易度を調整（パワー・確率設定・テストプレイ・景品の移動）
const CRANE_MOVE: String = "crane_move"       # 景品を取りやすい位置へ（景品の移動だけ）
## 判定しないボタン: 筐体のデータを見る（要件#57）
const MACHINE_DATA: String = "machine_data"

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
	return GameSettings.language if GameSettings.language in ["en", "zh", "ko"] else "ja"


## そのお客さんに出すボタン: [[id, 表示名], ...]。with_crane: ミニゲームのボタン（難易度の調整・景品の移動）を出すか（1人用のみ）
static func buttons(stage_id: String, customer: Dictionary, with_crane: bool) -> Array:
	var out: Array = []
	var t: Dictionary = table()
	var ids: Array = []
	if stage_id == "arcade":
		ids = (t.get("machines", {}) as Dictionary).get(Scenarios.machine_of(customer), [])
	else:
		ids = (t.get("stages", {}) as Dictionary).get(stage_id, [])
	var minigame: Array = t.get("minigame", [])
	var repair: Array = t.get("repair", [])
	var scene: Array = t.get("scene", [])
	var solo_only: Array = t.get("solo_only", [])
	var pr_acts: Dictionary = problem_actions(customer)
	for id in ids:
		if minigame.has(str(id)) and not with_crane:
			continue
		# 台の問題の行動（要件#99）: そのお客さんの問題の表にあるものだけ。
		# 1人用（with_crane）では、筐体の前の場面の中でする行動はボタンに出さず「筐体を見に行く」から行う。対戦では1人用だけの行動を出さない
		if repair.has(str(id)):
			if not pr_acts.has(str(id)):
				continue
			if with_crane and scene.has(str(id)):
				continue
			if not with_crane and solo_only.has(str(id)):
				continue
		# 「引っかかった景品をとる」は、本当に景品が引っかかっているお客さんだけ（要件#91）
		if str(id) == "crane_stuck" and not is_stuck(customer):
			continue
		out.append([str(id), label(str(id))])
	# 「〇〇円使っても取れない」のお客さんには、筐体のデータを見るボタン
	if stage_id == "arcade" and typeof(customer.get("spend", null)) == TYPE_DICTIONARY:
		out.append([MACHINE_DATA, label(MACHINE_DATA)])
	return out


## 景品が本当に引っかかっているお客さん（台本で「引っかかった景品をとる」が正解の人）
static func is_stuck(customer: Dictionary) -> bool:
	if bool(customer.get("stuck", false)):
		return true
	# 「お金を使ったのに取れない」お客さんは引っかかっていない（要件#106: AI が crane_stuck を good にしても出さない）
	var sp: Variant = customer.get("spend", null)
	if typeof(sp) == TYPE_DICTIONARY or (typeof(sp) == TYPE_BOOL and sp) or customer.has("spend_data"):
		return false
	var acts: Variant = customer.get("actions", {})
	return typeof(acts) == TYPE_DICTIONARY and str((acts as Dictionary).get("crane_stuck", "")) == "good"


## 台の問題（要件#99）: jam / empty / lottery / button / button_lie / slam / loud。なければ ""
static func problem_of(customer: Dictionary) -> String:
	var p: String = str(customer.get("problem", ""))
	return p if (table().get("problems", {}) as Dictionary).has(p) else ""


static func problem_actions(customer: Dictionary) -> Dictionary:
	var p: String = problem_of(customer)
	if p == "":
		return {}
	return ((table()["problems"] as Dictionary)[p] as Dictionary).get("actions", {})


## 台の問題をお客さんに当てはめる（サーバーの applyProblem と同じ）。台の種類と行動の効果を表から入れ、
## 「ボタンが反応しない」は lie_chance の確率でうそ（button_lie）にする
static func apply_problem(customer: Dictionary) -> Dictionary:
	var p: String = problem_of(customer)
	if p == "":
		customer.erase("problem")
		return customer
	if p == "button" and randf() < float(table().get("lie_chance", 0.4)):
		p = "button_lie"
		customer["problem"] = p
	var pr: Dictionary = (table()["problems"] as Dictionary)[p]
	customer["machine"] = str(pr.get("machine", "none"))
	customer["crane"] = false
	var acts: Dictionary = (customer.get("actions", {}) as Dictionary).duplicate() if typeof(customer.get("actions", null)) == TYPE_DICTIONARY else {}
	for k in (pr.get("actions", {}) as Dictionary):
		acts[k] = pr["actions"][k]
	customer["actions"] = acts
	return customer


## 筐体の前の場面の中でする行動か（1人用）
static func is_scene_action(id: String) -> bool:
	return (table().get("scene", []) as Array).has(id)


static func is_minigame(id: String) -> bool:
	return (table().get("minigame", []) as Array).has(id)


static func effect_kind(customer: Dictionary, id: String) -> String:
	if id == "crane_won" or id == "crane_lost" or id == "crane_moved":
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
