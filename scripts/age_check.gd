extends RefCounted
## 年齢確認のお客さん（要件#61）。ゲームセンターの夜のシフトで、年齢の怪しいお客さんが来る。
##
## 決まり（依頼者の指定）:
##   18:00 以降は 16 歳未満は入店不可。22:00 以降は 18 歳未満は入店不可。
##   年齢は「公的な身分証」で、顔写真と生年月日が書いてあるものだけで確かめられる。
##     使える: 運転免許証・マイナンバーカード・パスポート（顔が本人と違えば不可）
##     使えない: 定期券・学生証（公的でない）、健康保険証（顔写真がない）
##   確かめられない・入店できない年齢なら、退店してもらう。
## コンビニ（要件#63）: お酒・たばこは時間に関係なく 20 歳未満には売れない。身分証の決まりは同じ。
## お客さんのデータは make() が作る（台本・AIは使わない。サーバーも通さない）。
## 店員の判断が正しいかは must_leave で決まる: 使える身分証で、顔が同じで、見せた生年月日の年齢が条件を満たすときだけ OK。

const UI = preload("res://scripts/ui_kit.gd")

const TYPES: Dictionary = {
	"license": {"public": true, "photo": true, "dob": true},
	"mynumber": {"public": true, "photo": true, "dob": true},
	"passport": {"public": true, "photo": true, "dob": true},
	"student": {"public": false, "photo": true, "dob": true},
	"commuter": {"public": false, "photo": false, "dob": false},
	"insurance": {"public": true, "photo": false, "dob": true},
}

const NAMES_JA: Array = ["若葉 蓮", "中野 陽太", "春川 みゆ", "大森 颯", "早瀬 ひなた", "石田 光", "三好 奏", "北村 莉子"]
const NAMES_EN: Array = ["Ren Wakaba", "Yota Nakano", "Miyu Harukawa", "Hayate Omori", "Hinata Hayase", "Hikaru Ishida", "Kanade Miyoshi", "Riko Kitamura"]


static func type_label(t: String) -> String:
	match t:
		"license":
			return "運転免許証"
		"mynumber":
			return "マイナンバーカード"
		"passport":
			return "パスポート"
		"student":
			return "学生証"
		"commuter":
			return "通学定期券"
		"insurance":
			return "健康保険証"
	return t


## 何歳から入れるか（時刻は 0:00 からの分）。0 なら制限なし
static func limit_for(clock_min: int) -> int:
	if clock_min >= 22 * 60:
		return 18
	if clock_min >= 18 * 60:
		return 16
	return 0


static func clock_text(clock_min: int) -> String:
	return "%02d:%02d" % [int(clock_min / 60) % 24, clock_min % 60]


## 今日の日付から age 歳になる生年月日（誕生日はまだ来ていない日もある）
static func _dob_for_age(age: int, today: Dictionary) -> Dictionary:
	var y: int = int(today["year"]) - age
	var m: int = randi_range(1, 12)
	var d: int = randi_range(1, 28)
	# 今年の誕生日がまだなら 1 年早く生まれている
	if m > int(today["month"]) or (m == int(today["month"]) and d > int(today["day"])):
		y -= 1
	return {"year": y, "month": m, "day": d}


static func age_on(dob: Dictionary, today: Dictionary) -> int:
	var age: int = int(today["year"]) - int(dob["year"])
	if int(today["month"]) < int(dob["month"]) or (int(today["month"]) == int(dob["month"]) and int(today["day"]) < int(dob["day"])):
		age -= 1
	return age


static func dob_text(dob: Dictionary, lang: String) -> String:
	if lang == "ja":
		return "%d年%d月%d日生" % [int(dob["year"]), int(dob["month"]), int(dob["day"])]
	if lang == "zh":
		return "%d年%d月%d日出生" % [int(dob["year"]), int(dob["month"]), int(dob["day"])]
	return "Born %04d-%02d-%02d" % [int(dob["year"]), int(dob["month"]), int(dob["day"])]


## 言語ごとの文言を選ぶ（en / zh 以外は日本語）
static func _tr(lang: String, ja: Variant, en: Variant, zh: Variant) -> Variant:
	if lang == "en":
		return en
	if lang == "zh":
		return zh
	return ja


static func _pick(weights: Dictionary) -> String:
	var sum: float = 0.0
	for k in weights:
		sum += float(weights[k])
	var r: float = randf() * sum
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return str(k)
	return str(weights.keys()[0])


## お客さんを1人作る。clock_min: 来店した時刻（0:00 からの分）
## mode: "arcade"（夜の入店制限）| "konbini"（お酒・たばこの販売。20歳未満は不可）
static func make(clock_min: int, lang: String, mode: String = "arcade") -> Dictionary:
	var en: bool = lang == "en"
	var zh: bool = lang == "zh"
	var konbini: bool = mode == "konbini"
	var today: Dictionary = Time.get_date_dict_from_system()
	var limit: int = 20 if konbini else maxi(limit_for(clock_min), 16)
	var under: bool = randf() < 0.6
	var age: int = randi_range(limit - 4, limit - 1) if under else randi_range(limit, limit + 6)
	var id_type: String = ""
	var face_match: bool = true
	if under:
		id_type = _pick({"commuter": 25, "insurance": 20, "borrowed": 20, "student": 10, "mynumber": 15, "license": 10})
	else:
		id_type = _pick({"license": 30, "mynumber": 25, "passport": 10, "insurance": 15, "commuter": 10, "borrowed": 10})
	if id_type == "borrowed":
		# 年上の家族・友だちの運転免許証。顔が違う
		id_type = "license"
		face_match = false
	if id_type == "license" and age < 16:
		id_type = "mynumber"   # 16 歳未満は免許を持てない
	var real_dob: Dictionary = _dob_for_age(age, today)
	var shown_dob: Dictionary = real_dob if face_match else _dob_for_age(randi_range(21, 34), today)
	var t: Dictionary = TYPES[id_type]
	var shown_age: int = age_on(shown_dob, today)
	var verifiable: bool = bool(t["public"]) and bool(t["photo"]) and bool(t["dob"]) and face_match
	var must_leave: bool = not (verifiable and shown_age >= limit)
	# 見た目: 若く見える（背が低め・キャップ・ヘッドホン）
	var hair_colors: Array = ["#2a2a2a", "#4a3020", "#7a4a2a", "#c08040", "#2a2a3a"]
	var look: Dictionary = {
		"body_color": ["#3a6ea5", "#a5463a", "#3aa57a", "#7a3aa5", "#d08a2a"][randi() % 5],
		"skin_color": ["#f2cba8", "#e8b890", "#f5d3b5"][randi() % 3],
		"hair_color": hair_colors[randi() % hair_colors.size()],
		"hair": ["short", "cap", "long", "perm"][randi() % 4],
		"build": "slim",
		"accessory": ["none", "headphones", "bag", "glasses"][randi() % 4],
		"height": randf_range(0.86, 0.95),
	}
	# 身分証の写真: 本人なら同じ見た目、借り物なら別人
	var photo: Dictionary = look.duplicate()
	if not face_match:
		var other: Array = hair_colors.filter(func(c: String) -> bool: return c != str(look["hair_color"]))
		photo["hair_color"] = other[randi() % other.size()]
		photo["hair"] = "perm" if str(look["hair"]) != "perm" else "short"
		photo["accessory"] = "none" if str(look["accessory"]) == "glasses" else "glasses"
		photo["skin_color"] = "#d9a57e" if str(look["skin_color"]) != "#d9a57e" else "#f5d3b5"
	var names: Array = NAMES_EN if en else NAMES_JA
	var who: String = str(names[randi() % names.size()])
	# 借り物の身分証は、同じ名字の年上の家族のもの
	var shown_name: String = who
	if not face_match:
		shown_name = ("Kenji " + who.split(" ")[1]) if en else (who.split(" ")[0] + " 健二")
	var clock: String = clock_text(clock_min)
	var rule: String = ""
	if zh:
		rule = "现在是 %s。未满%d岁的顾客不能入店（18:00以后未满16岁、22:00以后未满18岁不可入店）。年龄只能用带有照片和出生日期的官方证件（驾照、个人编号卡、护照）来确认。月票和学生证不是官方证件，健康保险证没有照片，都不能用。照片与本人不符的证件也不行。" % [clock, limit]
	elif en:
		rule = "It's %s. Under-%d customers may not stay (after 18:00 under-16, after 22:00 under-18). Check age only with a public ID showing a face photo and date of birth (driver's license, My Number card, passport). Commuter passes and student IDs aren't public; health insurance cards have no photo. An ID whose photo doesn't match the face doesn't count either." % [clock, limit]
	else:
		rule = "現在 %s。%d歳未満は入店できない（18:00以降は16歳未満、22:00以降は18歳未満）。年齢は、顔写真と生年月日のある公的な身分証（運転免許証・マイナンバーカード・パスポート）で確かめる。定期券・学生証は公的でなく、健康保険証は顔写真がないので使えない。顔が本人と違う身分証も不可。" % [clock, limit]
	var openings_ja: Array = ["え、まだ遊べますよね？あと1回だけ！", "なんで出なきゃいけないの？オレもう大人だし！", "年齢確認？ほら、これ見せればいいんでしょ？", "友だち待ってるんで、あと10分だけお願いします！"]
	var openings_en: Array = ["I can still play, right? Just one more round!", "Why do I have to leave? I'm basically an adult!", "Age check? Here, this should do, right?", "My friends are waiting, just ten more minutes, please!"]
	var titles_ja: Array = ["年齢があやしい常連", "大人っぽい学生", "自称ハタチ", "あと1回だけの客"]
	var titles_en: Array = ["The Suspiciously Young Regular", "The Grown-Up-Looking Student", "The \"Totally 20\" Kid", "The Just-One-More Kid"]
	var openings_zh: Array = ["诶，还能玩吧？就再玩一次！", "为什么要我走？我已经是大人了！", "年龄确认？喏，给你看这个就行了吧？", "朋友在等我，就再给我10分钟吧，拜托了！"]
	var titles_zh: Array = ["年龄可疑的常客", "长得成熟的学生", "自称二十岁", "再玩一次的客人"]
	var demand: String = str(_tr(lang, "身分証をきちんと見せずに遊び続けること", "Keep playing without showing a proper ID", "不出示正规证件就继续玩"))
	var item: String = ""
	if konbini:
		# お酒・たばこ（実在の銘柄は出さない）
		var items_ja: Array = ["缶ビール", "缶チューハイ", "たばこ", "ワンカップの日本酒"]
		var items_en: Array = ["a can of beer", "a can of chu-hi", "a pack of cigarettes", "a cup of sake"]
		var items_zh: Array = ["一罐啤酒", "一罐烧酒苏打", "一包香烟", "一杯日本酒"]
		var k: int = randi() % 4
		item = str(_tr(lang, items_ja[k], items_en[k], items_zh[k]))
		if zh:
			rule = "想买%s。无论什么时间，酒和烟都不能卖给未满20岁的人。年龄只能用带有照片和出生日期的官方证件（驾照、个人编号卡、护照）来确认。月票和学生证不是官方证件，健康保险证没有照片，都不能用。照片与本人不符的证件也不行。只在收银台屏幕上按“已满20岁”不算确认。" % item
		elif en:
			rule = "Wants to buy %s. Alcohol and tobacco can't be sold to anyone under 20, at any hour. Check age only with a public ID showing a face photo and date of birth (driver's license, My Number card, passport). Commuter passes and student IDs aren't public; health insurance cards have no photo. An ID whose photo doesn't match the face doesn't count either. Pressing \"I'm 20 or older\" on the register screen alone isn't proof." % item
		else:
			rule = "%sを買おうとしている。お酒・たばこは、時間に関係なく20歳未満には売れない。年齢は、顔写真と生年月日のある公的な身分証（運転免許証・マイナンバーカード・パスポート）で確かめる。定期券・学生証は公的でなく、健康保険証は顔写真がないので使えない。顔が本人と違う身分証も不可。レジの画面の「20歳以上」を押しただけでは確認にならない。" % item
		openings_ja = ["%sください。……え、年齢確認？見ればわかるでしょ。" % item, "画面の「20歳以上です」押したんだから、それでいいでしょ？", "%sと、あと袋もお願いします。急いでるんで。" % item, "年齢確認とか、いつもされないんだけど？"]
		openings_en = ["%s, please. ...Huh, an age check? Isn't it obvious?" % (item.left(1).to_upper() + item.substr(1)), "I pressed \"I'm 20 or older\" on the screen, so we're good, right?", "%s, and a bag too. I'm in a hurry." % (item.left(1).to_upper() + item.substr(1)), "Age check? Nobody ever asks me that."]
		titles_ja = ["若く見えるお客さん", "急いでいる若者", "自称社会人", "年齢確認されたことがない客"]
		titles_en = ["The Young-Looking Customer", "The Kid in a Hurry", "The \"Totally Employed\" Guy", "The Never-Been-Carded Customer"]
		openings_zh = ["请给我%s。……诶，年龄确认？看不出来吗？" % item, "我都在屏幕上按了“已满20岁”，这样就行了吧？", "%s，再要个袋子。我赶时间。" % item, "年龄确认？平时从来没人查过我啊？"]
		titles_zh = ["看着很年轻的顾客", "赶时间的年轻人", "自称上班族", "从没被查过年龄的客人"]
		demand = str(_tr(lang, "身分証をきちんと見せずに%sを買うこと" % item, "Buy %s without showing a proper ID" % item, "不出示正规证件就买%s" % item))
	var opening: String = str((_tr(lang, openings_ja, openings_en, openings_zh) as Array)[randi() % 4])
	return {
		"kind": "age_check",
		"title": str((_tr(lang, titles_ja, titles_en, titles_zh) as Array)[randi() % 4]),
		"name": who,
		"look": look,
		"memo": rule,
		"opening": opening,
		"demand": demand,
		"patience": 1.0,
		"start_anger": 30,
		"machine": "none",
		"solution_keywords": _tr(lang, ["身分証", "年齢", "確認", "顔写真", "規則", "条例"], ["ID", "identification", "age", "check", "photo", "rules"], ["证件", "身份证", "年龄", "确认", "照片", "规定"]),
		"yield_keywords": _tr(lang, ["今回だけ", "大丈夫です", "どうぞ遊んで"], ["no problem, go ahead", "just this once", "it's fine"], ["就这一次", "没问题", "请便", "通融"]),
		"lines": {
			"calm": _tr(lang, ["……わかったよ。", "はいはい、見せればいいんでしょ。", "決まりなら、しょうがないか。"], ["...Okay, okay. I get it.", "Fine, I'll show you.", "Rules are rules, huh."], ["……知道了。", "好啦好啦，给你看就是了。", "既然是规定，那也没办法。"]),
			"angry": _tr(lang, ["ちょっとくらいいいじゃん！", "ほかの店はいけたのに！", "厳しすぎでしょ！"], ["Come on, just let it slide!", "Everyone else lets me in!", "You're so strict!"], ["通融一下又怎么了！", "别的店都让了！", "也太严了吧！"]),
			"neutral": _tr(lang, ["……で、遊んでいいの？", "え？"], ["...So can I play or not?", "Huh?"], ["……所以，能玩吗？", "诶？"]),
			"demand": (_tr(lang, ["いいから売ってよ！", "買うまで帰らないからね！"], ["Just sell it to me!", "I'm not leaving without it!"], ["别废话，卖给我！", "不买到我就不走！"]) if konbini else _tr(lang, ["遊ばせてよ！", "帰らないからね！"], ["Just let me play!", "I'm not leaving!"], ["让我玩嘛！", "我不走！"])),
			"resolved": _tr(lang, "……わかった、帰るよ。ごめんなさい。", "Okay... I'll go home. Sorry.", "……知道了，我回去。对不起。"),
			"explode": _tr(lang, "もういい！帰る！", "Ugh, fine! I'm out!", "算了！我走了！"),
			"yielded": _tr(lang, "やった、ラッキー！", "Yes! Lucky!", "太好了，运气真好！"),
		},
		"age": {"mode": mode, "item": item, "limit": limit, "clock": clock_min, "type": id_type, "public": bool(t["public"]), "has_photo": bool(t["photo"]),
			"has_dob": bool(t["dob"]), "face_match": face_match, "dob": shown_dob, "shown_age": shown_age,
			"name": shown_name, "photo": photo, "must_leave": must_leave, "real_age": age, "today": today},
	}
