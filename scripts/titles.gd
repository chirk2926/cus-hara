extends RefCounted
## 称号（要件#79）。条件と名前は data/titles.json。記録（stats）と手に入れた称号は GameSettings に保存する。
##
## 使い方:
##   GameSettings.stat_add("resolved")            記録を足す
##   var got: Array = Titles.check()              新しく手に入った称号（Dictionary の配列）を返し、保存する
##   Titles.title_name(t) / Titles.title_desc(t)  今の言語の名前・条件
## 条件: titles.json の stat の値が min 以上。stat の特別な名前:
##   res:<日本語の呼び名>  そのお客さんを納得させた回数（台本のお客さん。言語に関係なく日本語の呼び名で数える）
##   all:<店>              その店の台本のお客さん全員を一度ずつ納得させたら 1
##   mental_rank / vs_mental_b / titles_count / langs_count  そのときの値を計算する
## EOS が使えるときは、手に入れた称号を EOS の実績にも記録する（実績のIDは称号の id と同じ。開発者ポータルに登録が要る）。

const Scenarios = preload("res://scripts/scenarios.gd")

static var _list: Array = []


static func all() -> Array:
	if _list.is_empty():
		var f: FileAccess = FileAccess.open("res://data/titles.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_list = (parsed as Dictionary).get("titles", [])
	return _list


static func by_id(id: String) -> Dictionary:
	for t in all():
		if str((t as Dictionary).get("id", "")) == id:
			return t
	return {}


static func _text(d: Variant) -> String:
	if typeof(d) != TYPE_DICTIONARY:
		return str(d)
	var dict: Dictionary = d
	return str(dict.get(GameSettings.language, dict.get("ja", "")))


static func title_name(t: Dictionary) -> String:
	return _text(t.get("name", {}))


static func title_desc(t: Dictionary) -> String:
	return _text(t.get("desc", {}))


## つけている称号の名前（無ければ ""）
static func equipped_name() -> String:
	if GameSettings.equipped_title == "":
		return ""
	var t: Dictionary = by_id(GameSettings.equipped_title)
	return title_name(t) if not t.is_empty() else ""


## 台本のお客さんの日本語の呼び名（どの言語のお客さんでも、同じ順番の日本語の呼び名を返す。台本に無ければ ""）
static func ja_title(stage_id: String, cust: Dictionary) -> String:
	var t: String = str(cust.get("title", ""))
	for lang in ["ja", "en", "zh"]:
		var list: Array = Scenarios.customers(stage_id, lang)
		for i in range(list.size()):
			if str((list[i] as Dictionary).get("title", "")) == t:
				var ja: Array = Scenarios.customers(stage_id, "ja")
				return str((ja[i] as Dictionary).get("title", "")) if i < ja.size() else ""
	return ""


static func value(stat: String) -> int:
	match stat:
		"mental_rank":
			return GameSettings.mental_rank()
		"vs_mental_b":
			return GameSettings.mental_rank_b(int(GameSettings.last_profile.get("rating", 1000))) if not GameSettings.last_profile.is_empty() and GameSettings.stat("vs_matches") > 0 else 0
		"titles_count":
			return GameSettings.unlocked_titles.size()
		"langs_count":
			var langs: Variant = GameSettings.stats.get("langs", [])
			return (langs as Array).size() if typeof(langs) == TYPE_ARRAY else 0
	if stat.begins_with("all:"):
		var stage: String = stat.substr(4)
		for c in Scenarios.customers(stage, "ja"):
			if GameSettings.stat("res:" + str((c as Dictionary).get("title", ""))) <= 0:
				return 0
		return 1
	return GameSettings.stat(stat)


## 条件を満たした称号を手に入れる。新しく手に入ったものを返す
static func check() -> Array:
	var got: Array = []
	# 称号の数の称号（#100）は、ほかを先に数えてから見る
	for pass_i in range(2):
		for t in all():
			var d: Dictionary = t
			var id: String = str(d.get("id", ""))
			if id == "" or GameSettings.unlocked_titles.has(id):
				continue
			if (str(d.get("stat", "")) == "titles_count") != (pass_i == 1):
				continue
			if value(str(d.get("stat", ""))) >= int(d.get("min", 1)):
				GameSettings.unlocked_titles.append(id)
				got.append(d)
	if not got.is_empty():
		GameSettings.save_settings()
	return got
