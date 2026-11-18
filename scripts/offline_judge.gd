extends RefCounted
## キーワードによる採点（AIを使わないとき・サーバーにつながらないときの予備）。
## サーバーの server/src/keyword_judge.ts と同じ規則・同じ語（data/judge_words.json）。規則を変えるときは両方を直す。
## judge() は AI の採点と同じ形の Dictionary を返す。

const COMMENTS: Dictionary = {
	"ja": {
		"solution": "具体的な解決策、いいね！", "cushion": "断る時こそクッション言葉を。", "firm": "毅然とした対応、その調子。",
		"only_sorry": "謝るだけじゃ解決しないぞ。", "excuse": "言い訳に聞こえてるぞ。", "casual": "タメ口は火に油だ。",
		"short": "短すぎる。ちゃんと話そう。", "repeat": "同じ返事の繰り返しはNG。", "rude": "お客さんに暴言はダメ！",
		"yielded": "不当な要求を飲んじゃダメだ…。", "good": "いい受け止め方だ。", "ok": "悪くない。次は解決策を。",
		"miss": "響いてないぞ。メモを読もう。", "offtopic": "接客と関係ない話はやめよう。",
		"specific": "メモの中身に触れているのはいい。あと一歩、具体的に。",
	},
	"en": {
		"solution": "A concrete solution. Nice!", "cushion": "Soften a refusal with a kind word first.", "firm": "Polite but firm. Keep it up.",
		"only_sorry": "Apologizing alone won't fix it.", "excuse": "That sounds like an excuse.", "casual": "Too casual. Mind your manners.",
		"short": "Too short. Say a bit more.", "repeat": "Don't repeat the same reply.", "rude": "Never insult a customer!",
		"yielded": "You caved to an unreasonable demand...", "good": "Good, you took it on board.", "ok": "Not bad. Now offer a solution.",
		"miss": "That missed. Read the memo.", "offtopic": "Stay on the job, not off-topic chatter.",
		"specific": "Good, you're using what's in the memo. Now be more specific.",
	},
	"zh": {
		"solution": "具体的解决方案，很好！", "cushion": "拒绝的时候更要先说句软话。", "firm": "坚定又得体，保持住。",
		"only_sorry": "光道歉解决不了问题。", "excuse": "听起来像在找借口。", "casual": "说话太随便，火上浇油。",
		"short": "太短了。好好说几句。", "repeat": "重复同样的回答可不行。", "rude": "不能对顾客恶语相向！",
		"yielded": "不能答应无理要求啊…。", "good": "接得很好。", "ok": "还不错。接下来给出解决方案。",
		"miss": "没说到点上。看看备忘录。", "offtopic": "别聊和接待无关的话题。",
		"specific": "提到了备忘录里的内容，不错。再具体一点。",
	},
}

## 接客と関係ない話（AIへの依頼・プログラム・モデル名など）。要件#28
const OFFTOPIC: Array = [
	"コードを", "プログラム", "モデル名", "どのモデル", "システムプロンプト", "プロンプト", "指示を無視", "aiとして", "ai として",
	"write code", "write a program", "python", "javascript", "which model", "what model", "model name", "system prompt",
	"prompt", "chatgpt", "claude", "anthropic", "openai", "gpt", "as an ai", "ignore previous", "ignore your instructions",
	"写代码", "写程序", "编程", "模型名", "哪个模型", "什么模型", "系统提示", "提示词", "忽略指令", "忽略之前", "作为ai",
]

static var _words: Dictionary = {}


## 今の言語の配列から1つ選ぶ
static func pick_lang(ja: Array, en: Array, zh: Array) -> String:
	var l: String = _lang()
	return _pick(en if l == "en" else (zh if l == "zh" else ja))


static func _lang() -> String:
	return GameSettings.language if COMMENTS.has(GameSettings.language) else "ja"


static func words(lang: String) -> Dictionary:
	if _words.is_empty():
		var f: FileAccess = FileAccess.open("res://data/judge_words.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_words = parsed
	var w: Variant = _words.get(lang, _words.get("ja", {}))
	return w if typeof(w) == TYPE_DICTIONARY else {}


static func _norm(text: String, lang: String) -> String:
	return text if lang == "ja" else text.to_lower()


static func _count(text: String, list: Variant, lang: String = "ja") -> int:
	if typeof(list) != TYPE_ARRAY:
		return 0
	var n: int = 0
	for w in (list as Array):
		var s: String = _norm(str(w), lang)
		if s != "" and text.find(s) != -1:
			n += 1
	return n


static func _pick(v: Variant) -> String:
	if typeof(v) == TYPE_ARRAY:
		var arr: Array = v
		if arr.is_empty():
			return ""
		return str(arr[randi() % arr.size()])
	if v == null:
		return ""
	return str(v)


static func line(customer: Dictionary, key: String) -> String:
	var lines: Variant = customer.get("lines", {})
	var s: String = ""
	if typeof(lines) == TYPE_DICTIONARY:
		s = _pick((lines as Dictionary).get(key, null))
	if s == "":
		var g: Variant = words(_lang()).get("generic_lines", {})
		if typeof(g) == TYPE_DICTIONARY:
			s = _pick((g as Dictionary).get(key, null))
	return s if s != "" else "……"


static func is_off_topic(text: String) -> bool:
	var t: String = text.to_lower()
	if _count(t, OFFTOPIC, "en") > 0:
		return true
	return t.find("```") != -1 or t.find("<script") != -1


# ---------------------------------------------------------------- 精度を上げるための道具（要件#73）

## 文を節に分ける（「、」「。」や「but」で区切る）。否定が同じ節にあるかを見るため
static func _clauses(text: String, lang: String) -> PackedStringArray:
	var re: RegEx = RegEx.new()
	if lang == "en":
		re.compile("[.,!?;\\n]|\\bbut\\b")
	else:
		re.compile("[。、！？!?，,．\\n]")
	return PackedStringArray(re.sub(text, "|", true).split("|", false))


## 中身のある語のかたまり: 日本語は漢字・カタカナの2文字の並び、中国語は漢字の2文字の並び、英語は4文字以上の単語
static func _tokens(text: String, lang: String) -> Dictionary:
	var out: Dictionary = {}
	var re: RegEx = RegEx.new()
	if lang == "en":
		re.compile("[a-z]{4,}")
		for m in re.search_all(text.to_lower()):
			out[m.get_string()] = true
		return out
	if lang == "zh":
		re.compile("[\\x{4E00}-\\x{9FFF}]{2,}")
	else:
		re.compile("[\\x{4E00}-\\x{9FFF}\\x{30A0}-\\x{30FF}]{2,}")
	for m in re.search_all(text):
		var run: String = m.get_string()
		for i in range(run.length() - 1):
			out[run.substr(i, 2)] = true
	return out


## 2つの文の似ている度合い（0〜1）。日本語・中国語は2文字ずつ、英語は単語で比べる
static func similarity(a: String, b: String, lang: String) -> float:
	var ta: Dictionary = {}
	var tb: Dictionary = {}
	if lang == "en":
		for wd in a.to_lower().split(" ", false):
			ta[wd] = true
		for wd in b.to_lower().split(" ", false):
			tb[wd] = true
	else:
		for i in range(a.length() - 1):
			ta[a.substr(i, 2)] = true
		for i in range(b.length() - 1):
			tb[b.substr(i, 2)] = true
	if ta.is_empty() or tb.is_empty():
		return 1.0 if a == b else 0.0
	var inter: int = 0
	for k in ta:
		if tb.has(k):
			inter += 1
	return float(inter) / float(ta.size() + tb.size() - inter)


## 返事が、メモの中身（何が起きたか・規定・できること）にいくつ触れているか
static func memo_overlap(customer: Dictionary, text: String, lang: String, stop: Array) -> int:
	var mt: Dictionary = _tokens(str(customer.get("memo", "")), lang)
	var n: int = 0
	for k in _tokens(text, lang):
		if mt.has(k) and not stop.has(k):
			n += 1
	return n


## 返事の特徴（称号の記録用。要件#79）。AIで判定したときも、同じ決まりで数える
static func flags(customer: Dictionary, reply: String, used: Array) -> Dictionary:
	var lang: String = _lang()
	var w: Dictionary = words(lang)
	var raw: String = reply.strip_edges()
	var text: String = _norm(raw, lang)
	var re: RegEx = RegEx.new()
	re.compile(str(w.get("polite_pattern", "です|ます")))
	var polite: bool = re.search(text) != null or _count(text, w.get("polite", []), lang) > 0
	var ex_text: String = text
	for e in (w.get("excuse_exempt", []) as Array):
		ex_text = ex_text.replace(_norm(str(e), lang), "")
	var near: bool = used.has(raw)
	for u in used:
		if similarity(raw, str(u), lang) >= 0.8:
			near = true
	return {
		"apology": _count(text, w.get("apology", []), lang) > 0,
		"empathy": _count(text, w.get("empathy", []), lang) > 0,
		"question": (text.find("？") != -1 or text.find("?") != -1) and polite,
		"memo": memo_overlap(customer, text, lang, w.get("stop_tokens", [])) >= 2,
		"firm": _count(text, w.get("firm", []), lang) > 0,
		"casual": not polite,
		"rude": _count(text, w.get("rude", []), lang) > 0,
		"repeat": near,
		"excuse": _count(ex_text, w.get("excuse", []), lang) > 0,
		"offtopic": is_off_topic(raw),
		"short": (raw.split(" ", false).size() < 3) if lang == "en" else raw.length() <= 3,
	}


## customer: お客さんデータ / reply: プレイヤーの返答 / used: これまでの返答 / anger, resolve: 現在値(0-100)
static func judge(customer: Dictionary, reply: String, used: Array, anger: float, resolve: float) -> Dictionary:
	var lang: String = _lang()
	var w: Dictionary = words(lang)
	var cm: Dictionary = COMMENTS[lang]
	var raw: String = reply.strip_edges()
	var text: String = _norm(raw, lang)
	var a: float = 0.0
	var r: float = 0.0
	var comment: String = ""
	var yielded: bool = false

	var apology: int = _count(text, w.get("apology", []), lang)
	var empathy: int = _count(text, w.get("empathy", []), lang)
	var listen: int = _count(text, w.get("listen", []), lang)
	var firm: int = _count(text, w.get("firm", []), lang)
	var polite: int = _count(text, w.get("polite", []), lang)
	var rude: int = _count(text, w.get("rude", []), lang)
	var solution: int = mini(_count(text, customer.get("solution_keywords", []), lang), 2)
	# 言い訳: 「いつでも」「何でも」の「でも」は言い訳ではない。「でも／but」は、続けて解決策や断りがあれば言い訳にしない（要件#73）
	var ex_text: String = text
	for e in (w.get("excuse_exempt", []) as Array):
		var es: String = _norm(str(e), lang)
		if es != "":
			ex_text = ex_text.replace(es, "")
	var excuse: int = _count(ex_text, w.get("excuse", []), lang)
	if solution == 0 and firm == 0:
		excuse += _count(ex_text, w.get("excuse_soft", []), lang)
	# 屈服: 不当な要求の語と、否定が「同じ節」にあるかで見る（「無料で交換します、返金はできません」は屈服）
	var stripped: String = text
	for f in (w.get("apology_forms", []) as Array):
		var fs: String = _norm(str(f), lang)
		if fs != "":
			stripped = stripped.replace(fs, "")
	for cl in _clauses(stripped, lang):
		if _count(cl, customer.get("yield_keywords", []), lang) > 0 and _count(cl, w.get("negation", []), lang) == 0:
			yielded = true
	# 同じ謝罪ばかりだと効きが落ちる
	var past_apology: int = 0
	for u in used:
		if _count(_norm(str(u), lang), w.get("apology", []), lang) > 0:
			past_apology += 1
	# ていねいに質問して聞き出すのも「話を聞く」に数える
	if listen == 0 and (text.find("？") != -1 or text.find("?") != -1) and polite > 0:
		listen = 1
	# メモの中身に触れているか（キーワードが無くても、具体的に話していれば少し納得する）
	var overlap: int = memo_overlap(customer, text, lang, w.get("stop_tokens", []))

	if apology > 0:
		a -= 3.0 if past_apology >= 2 else 8.0
	if empathy > 0:
		a -= 7.0
	if listen > 0:
		a -= 5.0
		r += 8.0
	if polite > 0:
		a -= 3.0
	if solution > 0:
		a -= 6.0 * float(solution)
		r += 24.0 * float(solution)
		comment = str(cm["solution"])
	elif overlap >= 2:
		a -= 3.0
		r += 10.0
		comment = str(cm["specific"])
	if firm > 0:
		r += 15.0
		if apology == 0 and empathy == 0:
			a += 6.0
			comment = str(cm["cushion"])
		elif comment == "":
			comment = str(cm["firm"])
	if apology > 0 and empathy == 0 and listen == 0 and solution == 0 and firm == 0 and used.size() >= 2:
		a = -2.0
		comment = str(cm["only_sorry"])
	if excuse > 0:
		a += 8.0
		comment = str(cm["excuse"])
	var re: RegEx = RegEx.new()
	re.compile(str(w.get("polite_pattern", "です|ます")))
	if re.search(text) == null:
		a += 8.0
		comment = str(cm["casual"])
	# 英語は単語数、日本語・中国語は文字数で短さを見る
	var too_short: bool = raw.length() < 6
	if lang == "en":
		too_short = raw.split(" ", false).size() < 3
	if too_short:
		a += 10.0
		comment = str(cm["short"])
	var near_repeat: bool = false
	for u in used:
		if similarity(raw, str(u), lang) >= 0.8:
			near_repeat = true
	if used.has(raw) or near_repeat:
		a = maxf(a, 0.0) + 12.0
		r = 0.0
		comment = str(cm["repeat"])
	if is_off_topic(raw):
		a = maxf(a, 0.0) + 12.0
		r = 0.0
		yielded = false
		comment = str(cm["offtopic"])
	if rude > 0:
		a += 25.0
		r = 0.0
		comment = str(cm["rude"])
	if yielded:
		comment = str(cm["yielded"])
	if comment == "":
		if a < -8.0:
			comment = str(cm["good"])
		elif a < 0.0:
			comment = str(cm["ok"])
		else:
			comment = str(cm["miss"])

	a = clampf(a, -30.0, 30.0)
	r = clampf(r, 0.0, 45.0)
	var key: String = "neutral"
	if yielded:
		key = "yielded"
	elif anger + a >= 100.0:
		key = "explode"
	elif resolve + r >= 100.0:
		key = "resolved"
	elif a >= 5.0:
		key = "angry"
	elif a <= -6.0:
		key = "calm"
		if resolve + r < 60.0 and randf() < 0.4:
			key = "demand"
	return {
		"anger_delta": int(round(a)),
		"resolve_delta": int(round(r)),
		"yielded": yielded,
		"customer_reply": line(customer, key),
		"comment": comment,
	}
