extends RefCounted
## ショップ（要件#82）。品物は data/shop.json。持ち物・使っているもの・HP/KAS は GameSettings に保存する。
##
## お金（給与）:
##   HP（ハラスメントポイント）: オフライン（台本・キーワード判定）のシフトの売上の一部
##   KAS（カスポイント）: オンライン（サーバー・自分のAIキー）のシフトの売上の一部と、対戦の給与。HP より価値が高い
##   売上がマイナスでも減らない。
## 品物: 背景（タイトルの背景の店と時間帯）・名札の枠・名前の色・スタンプ。
##   値段は hp と kas の2つ（0 はその通貨では買えない）。KAS でしか買えないものもある。
## 名札の飾り（枠・名前の色・スタンプ）はサーバーに送り、対戦の相手にも見える（見た目だけ）。
## 要件#84: 背景はガチャ（KAS か HP。HP は高め。1回と10連=11回）。KAS は HP に両替できる（1 KAS = 3 HP、逆はできない）。
## 対戦のキャラクター（客役は私服、店員役は制服）。髪型・髪の色・私服・制服・小物はショップの品物。

const UI = preload("res://scripts/ui_kit.gd")

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f: FileAccess = FileAccess.open("res://data/shop.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
	return _data


static func categories() -> Array:
	return data().get("categories", [])


static func items(cat: String) -> Array:
	var out: Array = []
	for it in data().get("items", []):
		if str((it as Dictionary).get("cat", "")) == cat:
			out.append(it)
	return out


static func item(cat: String, id: String) -> Dictionary:
	for it in items(cat):
		if str((it as Dictionary).get("id", "")) == id:
			return it
	return {}


static func text(d: Variant) -> String:
	if typeof(d) != TYPE_DICTIONARY:
		return str(d)
	var dict: Dictionary = d
	return str(dict.get(GameSettings.language, dict.get("ja", "")))


static func item_name(it: Dictionary) -> String:
	return text(it.get("name", {}))


static func _key(cat: String, id: String) -> String:
	return cat + ":" + id


static func owns(cat: String, id: String) -> bool:
	var it: Dictionary = item(cat, id)
	if it.is_empty():
		return false
	return bool(it.get("default", false)) or GameSettings.owned_items.has(_key(cat, id))


static func default_id(cat: String) -> String:
	for it in items(cat):
		if bool((it as Dictionary).get("default", false)):
			return str((it as Dictionary).get("id", ""))
	return ""


## 使っているもの（持っていなければ最初からあるもの）
static func equipped(cat: String) -> String:
	var id: String = str(GameSettings.equipped_items.get(cat, ""))
	return id if owns(cat, id) else default_id(cat)


static func equipped_item(cat: String) -> Dictionary:
	return item(cat, equipped(cat))


## 買う。currency は "hp" か "kas"。買えたら true（保存もする）
static func buy(cat: String, id: String, currency: String) -> bool:
	var it: Dictionary = item(cat, id)
	if it.is_empty() or owns(cat, id):
		return false
	var price: int = int(it.get(currency, 0))
	if price <= 0:
		return false
	if currency == "kas":
		if GameSettings.kas_points < price:
			return false
		GameSettings.kas_points -= price
	else:
		if GameSettings.hp_points < price:
			return false
		GameSettings.hp_points -= price
	GameSettings.owned_items.append(_key(cat, id))
	GameSettings.stat_add("shop_buys")
	GameSettings.save_settings()
	return true


static func equip(cat: String, id: String) -> void:
	if not owns(cat, id):
		return
	GameSettings.equipped_items[cat] = id
	GameSettings.save_settings()


## サーバーに送る名札の飾り
static func tag_dict() -> Dictionary:
	return {"frame": equipped("frame"), "color": equipped("color"), "stamp": equipped("stamp")}


## タイトルの背景（店と時間帯）
static func backdrop() -> Dictionary:
	var it: Dictionary = equipped_item("bg")
	return {"stage": str(it.get("stage", "arcade")), "variant": str(it.get("variant", "day"))}


## シフトの給与。オンラインなら KAS、オフラインなら HP。売上がマイナスでも減らない。もらった分を返す
static func pay_shift(sales: int, online: bool) -> Dictionary:
	var pay: Dictionary = data().get("pay", {})
	var s: float = float(maxi(0, sales))
	if online:
		var k: int = int(floor(s * float(pay.get("kas_per_sales", 0.005))))
		GameSettings.kas_points += k
		return {"hp": 0, "kas": k}
	var h: int = int(floor(s * float(pay.get("hp_per_sales", 0.01))))
	GameSettings.hp_points += h
	return {"hp": h, "kas": 0}


## 対戦の給与（KAS）
static func pay_versus(won: bool) -> int:
	var pay: Dictionary = data().get("pay", {})
	var k: int = int(pay.get("kas_versus_win" if won else "kas_versus_lose", 0))
	GameSettings.kas_points += k
	return k


static func pay_text(paid: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if int(paid.get("kas", 0)) > 0:
		parts.append("+%d KAS" % int(paid["kas"]))
	if int(paid.get("hp", 0)) > 0:
		parts.append("+%d HP" % int(paid["hp"]))
	return " ".join(parts) if not parts.is_empty() else "+0"


# ---------------------------------------------------------------- 名札

## 名札を作る。tag は {frame, color, stamp}（空なら最初からあるもの）。big は文字の大きさ
static func name_tag(player_name: String, title: String, tag: Dictionary, big: int = UI.S_LEAD) -> PanelContainer:
	var fr: Dictionary = item("frame", str(tag.get("frame", "")))
	if fr.is_empty():
		fr = item("frame", default_id("frame"))
	var co: Dictionary = item("color", str(tag.get("color", "")))
	var st: Dictionary = item("stamp", str(tag.get("stamp", "")))
	var panel: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(str(fr.get("bg", "#f3eee3")))
	sb.border_color = Color(str(fr.get("border", "#6b6574")))
	sb.set_border_width_all(int(fr.get("width", 2)))
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	if str(fr.get("glow", "")) != "":
		sb.shadow_color = Color(str(fr["glow"]), 0.7)
		sb.shadow_size = 10
	else:
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 3
		sb.shadow_offset = Vector2(2, 3)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var text_c: Color = Color(str(fr.get("text", "#24212b")))
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	if title != "":
		col.add_child(UI.text("「%s」" % title, maxi(UI.S_SMALL - 2, int(big * 0.55)), Color(text_c, 0.8), UI.F_BOLD))
	var name_c: Color = text_c
	if str(co.get("value", "")) != "":
		name_c = Color(str(co["value"]))
	var nl: Label = UI.text(player_name, big, name_c, UI.F_SIGN)
	col.add_child(nl)
	var ch: String = str(st.get("char", ""))
	if ch != "":
		row.add_child(hanko(ch, int(big * 1.7)))
	return panel


## 判子（丸い朱色の枠に1文字）
static func hanko(ch: String, size: int) -> Control:
	var box: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(UI.SHU, 0.08)
	sb.border_color = UI.SHU
	sb.set_border_width_all(maxi(2, int(size / 16)))
	sb.set_corner_radius_all(size)
	box.add_theme_stylebox_override("panel", sb)
	box.custom_minimum_size = Vector2(size, size)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.rotation_degrees = -10.0
	box.pivot_offset = Vector2(size, size) * 0.5
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l: Label = UI.text(ch, int(size * 0.55), UI.SHU, UI.F_SIGN)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(l)
	return box


# ---------------------------------------------------------------- 両替（要件#84）

static func hp_per_kas() -> int:
	return int((data().get("exchange", {}) as Dictionary).get("hp_per_kas", 3))


## KAS を HP にする（逆はできない）。できたら true
static func exchange(kas: int) -> bool:
	if kas <= 0 or kas > GameSettings.kas_points:
		return false
	GameSettings.kas_points -= kas
	GameSettings.hp_points += kas * hp_per_kas()
	GameSettings.save_settings()
	return true


# ---------------------------------------------------------------- 背景ガチャ（要件#84）

static func gacha_conf() -> Dictionary:
	return data().get("gacha", {})


static func gacha_pool() -> Array:
	var out: Array = []
	for it in items("bg"):
		if bool((it as Dictionary).get("gacha", false)):
			out.append(it)
	return out


## まだ持っていない背景があるか（全部持っていたら回せない）
static func gacha_has_new() -> bool:
	for it in gacha_pool():
		if not owns("bg", str((it as Dictionary).get("id", ""))):
			return true
	return false


## 1回分の値段。currency は "kas" か "hp"
static func gacha_price(currency: String, ten: bool) -> int:
	var c: Dictionary = gacha_conf()
	var one: int = int(c.get("price_kas", 100)) if currency == "kas" else int(c.get("price_hp", 400))
	return one * int(c.get("ten_price_mul", 10)) if ten else one


## 回す。結果は [{item, new, refund}]。払えない・全部持っているときは []
static func gacha_pull(currency: String, ten: bool) -> Array:
	if not gacha_has_new():
		return []
	var c: Dictionary = gacha_conf()
	var price: int = gacha_price(currency, ten)
	var wallet: int = GameSettings.kas_points if currency == "kas" else GameSettings.hp_points
	if wallet < price:
		return []
	if currency == "kas":
		GameSettings.kas_points -= price
	else:
		GameSettings.hp_points -= price
	var count: int = int(c.get("ten_pulls", 11)) if ten else 1
	var one_price: int = gacha_price(currency, false)
	var refund_one: int = int(floor(float(one_price) * float(c.get("refund_rate", 0.3))))
	var weights: Dictionary = c.get("weights", {})
	var pool: Array = gacha_pool()
	var total_w: float = 0.0
	for it in pool:
		total_w += float(weights.get(str(int((it as Dictionary).get("rarity", 1))), 10))
	var out: Array = []
	for i in range(count):
		var r: float = randf() * total_w
		var pick: Dictionary = pool[pool.size() - 1]
		for it in pool:
			r -= float(weights.get(str(int((it as Dictionary).get("rarity", 1))), 10))
			if r <= 0.0:
				pick = it
				break
		var id: String = str(pick.get("id", ""))
		var is_new: bool = not owns("bg", id)
		if is_new:
			GameSettings.owned_items.append(_key("bg", id))
		else:
			if currency == "kas":
				GameSettings.kas_points += refund_one
			else:
				GameSettings.hp_points += refund_one
		out.append({"item": pick, "new": is_new, "refund": 0 if is_new else refund_one})
	GameSettings.stat_add("gacha_pulls", count)
	GameSettings.save_settings()
	return out


# ---------------------------------------------------------------- 対戦のキャラクター（要件#84）

const AVATAR_CATS: Array = ["hair", "hair_color", "casual", "uniform", "acc", "head", "face", "hand", "body"]


static func avatar_created() -> bool:
	return bool(GameSettings.avatar.get("created", false))


static func skins() -> Array:
	return data().get("skins", [])


static func skin_hex(id: String) -> String:
	for sk in skins():
		if str((sk as Dictionary).get("id", "")) == id:
			return str((sk as Dictionary).get("value", "#f1c9a5"))
	return "#f1c9a5"


## サーバーに送る・相手から届くキャラクター（IDだけ。色はこのゲームの表から引く）
static func avatar_dict() -> Dictionary:
	var a: Dictionary = GameSettings.avatar
	var out: Dictionary = {"gender": str(a.get("gender", "x")), "height": snappedf(float(a.get("height", 1.0)), 0.01),
		"build": str(a.get("build", "normal")), "skin": str(a.get("skin", "s2"))}
	for c in AVATAR_CATS:
		out[c] = equipped(c)
	return out


## キャラクターの見た目（customer_character.gd の look）。role は "casual"（客役）か "uniform"（店員役）
static func avatar_look(av: Dictionary, role: String) -> Dictionary:
	var hair: Dictionary = item("hair", str(av.get("hair", "")))
	var hc: Dictionary = item("hair_color", str(av.get("hair_color", "")))
	var cloth: Dictionary = item(role, str(av.get(role, "")))
	if cloth.is_empty():
		cloth = item(role, default_id(role))
	var acc: Dictionary = item("acc", str(av.get("acc", "")))
	return {
		"body_color": str(cloth.get("value", "#2f3b63")),
		"skin_color": skin_hex(str(av.get("skin", "s2"))),
		"hair_color": str(hc.get("value", "#262326")),
		"hair": str(hair.get("id", "short")),
		"build": str(av.get("build", "normal")) if str(av.get("build", "")) in ["slim", "normal", "big"] else "normal",
		"accessory": str(acc.get("id", "none")),
		"height": clampf(float(av.get("height", 1.0)), 0.85, 1.15),
		"gender": str(av.get("gender", "x")),
		"outfit": "uniform" if role == "uniform" else "casual",
		"head": str(av.get("head", "")), "face": str(av.get("face", "")), "hand": str(av.get("hand", "")), "body": str(av.get("body", "")),
	}

