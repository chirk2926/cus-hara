extends RefCounted
## 台本モード用の採点ロジック（LLMを使わないキーワード判定）
## judge() は LLM の judge_turn() と同じ形の Dictionary を返す。

const APOLOGY: Array = ["申し訳", "すみません", "すいません", "失礼いたしました", "失礼しました", "お詫び", "ごめんなさい"]
const EMPATHY: Array = ["お気持ち", "ご不便", "ご迷惑", "ご不快", "お察し", "おっしゃる通り", "おっしゃるとおり", "ごもっとも", "お怒り", "ご心配"]
const LISTEN: Array = ["お聞かせ", "詳しく", "確認いたし", "確認させ", "お伺い", "状況を", "教えていただ"]
const FIRM: Array = ["いたしかねます", "できかねます", "お受けできません", "応じかねます", "お断り", "致しかねます", "出来かねます", "お応えできません"]
const POLITE: Array = ["ございます", "いたします", "でしょうか", "くださいませ", "恐れ入ります", "おります", "いただけます"]
const RUDE: Array = ["うるさい", "うるせ", "黙れ", "だまれ", "帰れ", "バカ", "ばか", "馬鹿", "アホ", "あほ", "知らん", "知らねえ", "うざ", "クレーマー", "ふざけ", "めんどくさ", "はぁ？", "は？"]
const EXCUSE: Array = ["でも", "だって", "仕方ない", "しょうがない", "ルールなので", "決まりなので", "私のせいじゃ", "私は悪く"]
const NEGATION: Array = ["かねます", "できません", "出来ません", "お断り", "いたしません", "しません", "ません"]

const GENERIC_LINES: Dictionary = {
	"calm": ["……まあ、話は聞いてやる。", "ふん。少しは分かってるじゃないか。", "それで？どうしてくれるんだ？"],
	"angry": ["なんだその態度は！", "こっちは客だぞ！！", "話にならん！責任者を出せ！"],
	"neutral": ["で？それがどうした。", "だから何なんだって聞いてるんだ。"],
	"demand": ["いいから誠意を見せろ、誠意を！", "タダにすれば済む話だろうが！"],
	"resolved": "……分かった。今回はそれでいい。次は気をつけろよ。",
	"explode": "もういい！！話にならん！店長を呼べ！！！",
	"yielded": "最初からそうすればいいんだよ。また来るからな。",
}


static func _count(text: String, words: Array) -> int:
	var n: int = 0
	for w in words:
		if text.find(str(w)) != -1:
			n += 1
	return n


static func _pick(lines: Dictionary, key: String) -> String:
	var v: Variant = lines.get(key, null)
	if v == null:
		v = GENERIC_LINES.get(key, "……")
	if typeof(v) == TYPE_ARRAY:
		var arr: Array = v
		if arr.is_empty():
			return _pick(GENERIC_LINES, key)
		return str(arr[randi() % arr.size()])
	return str(v)


static func line(customer: Dictionary, key: String) -> String:
	var lines: Dictionary = {}
	var raw: Variant = customer.get("lines", {})
	if typeof(raw) == TYPE_DICTIONARY:
		lines = raw
	return _pick(lines, key)


## customer: お客さんデータ / reply: プレイヤーの返答 / used: これまでの返答一覧
## anger, resolve: 現在値(0-100)
static func judge(customer: Dictionary, reply: String, used: Array, anger: float, resolve: float) -> Dictionary:
	var text: String = reply.strip_edges()
	var anger_delta: float = 0.0
	var resolve_delta: float = 0.0
	var comment: String = ""
	var yielded: bool = false

	var apology: int = _count(text, APOLOGY)
	var empathy: int = _count(text, EMPATHY)
	var listen: int = _count(text, LISTEN)
	var firm: int = _count(text, FIRM)
	var polite: int = _count(text, POLITE)
	var rude: int = _count(text, RUDE)
	var excuse: int = _count(text, EXCUSE)
	var sol_words: Array = customer.get("solution_keywords", [])
	var yield_words: Array = customer.get("yield_keywords", [])
	var solution: int = mini(_count(text, sol_words), 2)
	var negated: bool = _count(text, NEGATION) > 0

	if _count(text, yield_words) > 0 and not negated:
		yielded = true

	if apology > 0:
		anger_delta -= 8.0
	if empathy > 0:
		anger_delta -= 7.0
	if listen > 0:
		anger_delta -= 5.0
		resolve_delta += 8.0
	if polite > 0:
		anger_delta -= 3.0
	if solution > 0:
		anger_delta -= 6.0 * solution
		resolve_delta += 24.0 * solution
		comment = "具体的な解決策、いいね！"
	if firm > 0:
		resolve_delta += 15.0
		if apology == 0 and empathy == 0:
			anger_delta += 6.0
			comment = "断る時こそクッション言葉を。"
		elif comment == "":
			comment = "毅然とした対応、その調子。"

	# 謝るだけの繰り返しは効かなくなる
	if apology > 0 and empathy == 0 and listen == 0 and solution == 0 and firm == 0 and used.size() >= 2:
		anger_delta = -2.0
		comment = "謝るだけじゃ解決しないぞ。"

	if excuse > 0:
		anger_delta += 8.0
		comment = "言い訳に聞こえてるぞ。"
	var has_desu: bool = text.find("です") != -1 or text.find("ます") != -1 or text.find("ません") != -1 or text.find("ございま") != -1
	if not has_desu:
		anger_delta += 8.0
		comment = "タメ口は火に油だ。"
	if text.length() < 6:
		anger_delta += 10.0
		comment = "短すぎる。ちゃんと話そう。"
	if used.has(text):
		anger_delta = maxf(anger_delta, 0.0) + 12.0
		resolve_delta = 0.0
		comment = "同じ返事の繰り返しはNG。"
	if rude > 0:
		anger_delta += 25.0
		resolve_delta = 0.0
		comment = "お客さんに暴言はダメ！"
	if yielded:
		comment = "不当な要求を飲んじゃダメだ…。"
	if comment == "":
		if anger_delta < -8.0:
			comment = "いい受け止め方だ。"
		elif anger_delta < 0.0:
			comment = "悪くない。次は解決策を。"
		else:
			comment = "響いてないぞ。メモを読もう。"

	anger_delta = clampf(anger_delta, -30.0, 30.0)
	resolve_delta = clampf(resolve_delta, 0.0, 45.0)

	var new_anger: float = anger + anger_delta
	var new_resolve: float = resolve + resolve_delta
	var key: String = "neutral"
	if yielded:
		key = "yielded"
	elif new_anger >= 100.0:
		key = "explode"
	elif new_resolve >= 100.0:
		key = "resolved"
	elif anger_delta >= 5.0:
		key = "angry"
	elif anger_delta <= -6.0:
		key = "calm"
		if new_resolve < 60.0 and randf() < 0.4:
			key = "demand"

	return {
		"anger_delta": int(round(anger_delta)),
		"resolve_delta": int(round(resolve_delta)),
		"yielded": yielded,
		"customer_reply": line(customer, key),
		"comment": comment,
	}
