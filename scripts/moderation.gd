extends RefCounted
## 不適切な発言・名前を送る前に止める（要件#94）。語は data/moderation_words.json（サーバーの server/src/moderation.ts と共通）。
## ここで止めるのは「送らせない」ための先回り。対戦ではサーバーでも同じ語と AI で確かめる（すり抜けてもサーバーで伏せ字になる）。

const WORDS_PATH: String = "res://data/moderation_words.json"

static var _words: Dictionary = {}
static var _ascii: Dictionary = {}   # 英語の語 → 単語の区切りで見る RegEx（cocktail で cock を拾わない）
static var _phone: RegEx = null
static var _email: RegEx = null


static func _load() -> void:
	if not _words.is_empty():
		return
	var f: FileAccess = FileAccess.open(WORDS_PATH, FileAccess.READ)
	if f != null:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_DICTIONARY:
			for k in ["sexual", "hate"]:
				var norm: PackedStringArray = PackedStringArray()
				var res: Array = []
				for w in (d as Dictionary).get(k, []):
					var lw: String = str(w).to_lower()
					if _is_ascii_word(lw):
						res.append(RegEx.create_from_string("(?:^|[^a-z])" + lw.replace(" ", "[\\s._*-]*") + "(?:$|[^a-z])"))
						continue
					var n: String = normalize(lw)
					if n != "":
						norm.append(n)
				_words[k] = norm
				_ascii[k] = res
	if _words.is_empty():
		_words = {"sexual": PackedStringArray(), "hate": PackedStringArray()}
		_ascii = {"sexual": [], "hate": []}
	_phone = RegEx.create_from_string("(?<!\\d)0\\d{1,4}[-ー－ ]\\d{1,4}[-ー－ ]\\d{3,4}(?!\\d)|(?<!\\d)0[5789]0\\d{8}(?!\\d)|(?<!\\d)01[016789]\\d{7,8}(?!\\d)|\\+\\d{1,3}[- ]?\\d{2,4}[- ]?\\d{3,4}[- ]?\\d{3,4}")
	_email = RegEx.create_from_string("[\\w.+-]+@[\\w-]+\\.[\\w.]+")


static func _is_ascii_word(w: String) -> bool:
	if w == "":
		return false
	for i in w.length():
		var c: int = w.unicode_at(i)
		if not ((c >= 97 and c <= 122) or c == 32):
			return false
	return true


## 全角英数を半角・小文字にし、空白や区切りの記号をのぞく（「え ろ」「e.r.o」も拾う。サーバーの normalize と同じ）
static func normalize(text: String) -> String:
	var out: String = _half(strip_invisible(text)).to_lower()
	for ch in [" ", "　", ".", "_", "・", "*", "＊", "-", "~", "〜", "\t", "\n"]:
		out = out.replace(ch, "")
	return out


## 見えない字（ゼロ幅の文字・ソフトハイフンなど）を消す（要件#108）
static func strip_invisible(text: String) -> String:
	var out: String = ""
	for i in text.length():
		var c: int = text.unicode_at(i)
		if c == 0xAD or c == 0x34F or c == 0x61C or (c >= 0x180B and c <= 0x180E) or (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) or (c >= 0x2060 and c <= 0x206F) or c == 0x3164 or (c >= 0xFE00 and c <= 0xFE0F) or c == 0xFEFF or c == 0xFFA0:
			continue
		out += text[i]
	return out


## 全角の英数・記号を半角にする
static func _half(text: String) -> String:
	var out: String = ""
	for i in text.length():
		var c: int = text.unicode_at(i)
		if c >= 0xFF01 and c <= 0xFF5E:   # 全角の英数・記号 → 半角
			c -= 0xFEE0
		elif c == 0x3000:
			c = 0x20
		out += String.chr(c)
	return out


## 不適切なら種類（"sexual" / "hate" / "personal_info"）、問題なければ ""
static func check(text: String) -> String:
	_load()
	var t: String = normalize(text)
	if t == "":
		return ""
	# 見えない文字をはさんで、英語の禁止語・電話番号・メールをすり抜けられないように（レビュー2-8）
	var raw: String = _half(strip_invisible(text)).to_lower()
	for k in ["sexual", "hate"]:
		for w in _words[k]:
			if t.contains(str(w)):
				return k
		for re in _ascii[k]:
			if (re as RegEx).search(raw) != null:
				return k
	if _phone.search(raw) != null or _email.search(raw) != null:
		return "personal_info"
	return ""


## 止めたときに出す文
static func message(kind: String) -> String:
	match kind:
		"personal_info":
			return TranslationServer.translate("電話番号やメールアドレスなどの個人情報は送れません。")
		_:
			return TranslationServer.translate("不適切な言葉が含まれているため送れません。言い方を変えてください。")
