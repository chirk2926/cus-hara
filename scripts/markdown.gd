extends RefCounted
## お知らせの本文（Markdown）を、RichTextLabel の BBCode にする（要件#100）。管理画面のプレビューと同じ範囲だけ:
##   # 見出し / ## / ###、**太字**、*斜体*、`コード`、- 箇条書き、[リンク](https://...)、空の行
## 本文にある「[」は先に [lb] にしておくので、BBCode として悪さはできない（リンクは http/https だけ）。

const SIZES: Array = [30, 24, 20]


static func to_bbcode(md: String) -> String:
	var out: PackedStringArray = PackedStringArray()
	for raw in md.split("\n"):
		var line: String = raw.strip_edges(false, true)
		var hm: RegExMatch = _re("^(#{1,3})\\s+(.*)$").search(line)
		var lm: RegExMatch = _re("^\\s*[-*]\\s+(.*)$").search(line)
		if hm != null:
			var lv: int = hm.get_string(1).length()
			out.append("[font_size=%d][b]%s[/b][/font_size]" % [int(SIZES[lv - 1]), _inline(hm.get_string(2))])
		elif lm != null:
			out.append("  •  " + _inline(lm.get_string(1)))
		elif line == "":
			out.append("")
		else:
			out.append(_inline(line))
	return "\n".join(out)


static func _inline(text: String) -> String:
	# リンクを先に取り出し（URL は http/https だけ）、残りの「[」を無害にしてから太字などを変える
	var links: Array = []
	var link_re: RegEx = _re("\\[([^\\]]+)\\]\\((https?://[^)\\s]+)\\)")
	var t: String = text
	var m: RegExMatch = link_re.search(t)
	while m != null:
		var key: String = "\u0001%d\u0001" % links.size()
		links.append([m.get_string(1), m.get_string(2)])
		t = t.substr(0, m.get_start()) + key + t.substr(m.get_end())
		m = link_re.search(t)
	t = t.replace("[", "[lb]")
	t = _re("\\*\\*([^*]+)\\*\\*").sub(t, "[b]$1[/b]", true)
	t = _re("\\*([^*]+)\\*").sub(t, "[i]$1[/i]", true)
	t = _re("`([^`]+)`").sub(t, "[code]$1[/code]", true)
	for i in links.size():
		var label: String = str(links[i][0]).replace("[", "[lb]")
		var url: String = str(links[i][1]).replace("[", "").replace("]", "")
		t = t.replace("\u0001%d\u0001" % i, "[url=%s][u]%s[/u][/url]" % [url, label])
	return t


static var _cache: Dictionary = {}


static func _re(p: String) -> RegEx:
	if not _cache.has(p):
		_cache[p] = RegEx.create_from_string(p)
	return _cache[p]
