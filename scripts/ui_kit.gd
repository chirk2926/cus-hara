extends RefCounted
## 画面部品の共通関数。色・書体・形の決まりは docs/UI_GUIDE.md。
## 画面のスクリプトでは色の数値を直接書かず、ここの定数と関数を使う。
## 使い方: const UI = preload("res://scripts/ui_kit.gd") → UI.text("…", UI.S_BODY)

# ---------------------------------------------------------------- 色（UI_GUIDE 3節）
const PAPER: Color = Color("#f3eee3")
const PAPER_DIM: Color = Color("#d9d1c0")
const PAPER_LINE: Color = Color("#c9d6e3")      # 罫線（薄い青）
const INK: Color = Color("#24212b")
const INK_SOFT: Color = Color("#6b6574")
const SHU: Color = Color("#d23f2f")
const POP: Color = Color("#ffd23f")
const LCD_BG: Color = Color("#1f2b22")
const LCD_OFF: Color = Color("#2c3d30")
const LCD_ON: Color = Color("#b8f28a")
const OK: Color = Color("#2f8f5b")
const SHADE: Color = Color(0.141, 0.129, 0.169, 0.6)   # 画面を暗くする幕（INK の60%）
const SHADOW: Color = Color(0.141, 0.129, 0.169, 0.25) # 紙の影（INK の25%）

# ---------------------------------------------------------------- 文字の大きさ（5段階）
const S_SMALL: int = 14
const S_BODY: int = 18
const S_LEAD: int = 22
const S_HEAD: int = 30
const S_HUGE: int = 48
const S_DIGIT: int = 56

# ---------------------------------------------------------------- 書体（役割ごと）
const F_BODY: String = "res://assets/fonts/NotoSansJP_500Medium.ttf"
const F_BOLD: String = "res://assets/fonts/NotoSansJP_800ExtraBold.ttf"
const F_HAND: String = "res://assets/fonts/YuseiMagic.ttf"        # 手書きの物（メモ・付箋・POP）
const F_DOT: String = "res://assets/fonts/DotGothic16.ttf"         # 機械の表示（レジ・レシート）
const F_SIGN: String = "res://assets/fonts/DelaGothicOne.ttf"
## 簡体字中国語の文字（日本語のフォントに無い字）を補う。すべてのフォントの予備にする（要件#71）
const F_SC: String = "res://assets/fonts/NotoSansSC_500Medium.ttf"      # 看板・ポスター・大きな判定

static var _fonts: Dictionary = {}


static func font(path: String) -> Font:
	if not _fonts.has(path):
		var f: Font = load(path) as Font
		if f != null and path != F_SC:
			var sc: Font = load(F_SC) as Font
			if sc != null and not f.fallbacks.has(sc):
				var fb: Array[Font] = f.fallbacks.duplicate()
				fb.append(sc)
				f.fallbacks = fb
		_fonts[path] = f
	return _fonts[path]


static func bold_font() -> Font:
	return font(F_BOLD)


## 文字。face は F_BODY / F_BOLD / F_HAND / F_DOT / F_SIGN
static func text(t: String, size: int, color: Color = INK, face: String = F_BODY) -> Label:
	var l: Label = Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if face != F_BODY:
		l.add_theme_font_override("font", font(face))
	return l


## 折り返す文字。英語は単語の途中で切らない（日本語は文字の間で自然に折り返される）
static func para(t: String, size: int, color: Color = INK, face: String = F_BODY) -> Label:
	var l: Label = text(t, size, color, face)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


# ---------------------------------------------------------------- 面

## 紙。右下にずらしただけの影（ぼかさない）。radius は 0〜2
static func paper_style(bg: Color = PAPER, pad: int = 16, radius: int = 1, shadow: int = 4) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad + shadow
	s.content_margin_top = pad
	s.content_margin_bottom = pad + shadow
	if shadow > 0:
		s.border_width_right = shadow
		s.border_width_bottom = shadow
		s.border_color = SHADOW
	return s


static func paper(bg: Color = PAPER, pad: int = 16, shadow: int = 4) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", paper_style(bg, pad, 1, shadow))
	return p


static func flat_style(bg: Color, pad: int = 8, radius: int = 0) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	return s


static func empty_style(pad_h: int = 0, pad_v: int = 0) -> StyleBoxEmpty:
	var s: StyleBoxEmpty = StyleBoxEmpty.new()
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	return s


# ---------------------------------------------------------------- ボタン（主役は1画面に1つ）

static func _button_base(label: String, size: int, face: String) -> Button:
	var b: Button = Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_font_override("font", font(face))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.focus_mode = Control.FOCUS_ALL
	return b


static func _colors(b: Button, normal: Color, hover: Color, disabled: Color) -> void:
	b.add_theme_color_override("font_color", normal)
	b.add_theme_color_override("font_focus_color", normal)
	b.add_theme_color_override("font_hover_color", hover)
	b.add_theme_color_override("font_pressed_color", hover)
	b.add_theme_color_override("font_hover_pressed_color", hover)
	b.add_theme_color_override("font_disabled_color", disabled)


## 主役のボタン: 朱赤のべた塗り。紙の影つき
static func primary(label: String, size: int = S_LEAD) -> Button:
	var b: Button = _button_base(label, size, F_BOLD)
	_colors(b, PAPER, PAPER, Color(PAPER.r, PAPER.g, PAPER.b, 0.6))
	b.add_theme_stylebox_override("normal", paper_style(SHU, 12, 0, 4))
	b.add_theme_stylebox_override("hover", paper_style(SHU.lightened(0.08), 12, 0, 4))
	b.add_theme_stylebox_override("pressed", paper_style(SHU.darkened(0.12), 12, 0, 1))
	b.add_theme_stylebox_override("disabled", paper_style(INK_SOFT, 12, 0, 0))
	b.add_theme_stylebox_override("focus", _focus_style())
	return b


## 紙のタグ: 薄い紙に細い線。定型文や二番手の操作
static func tag(label: String, size: int = S_BODY) -> Button:
	var b: Button = _button_base(label, size, F_BODY)
	_colors(b, INK, INK, INK_SOFT.lerp(PAPER, 0.4))
	var n: StyleBoxFlat = flat_style(PAPER, 0, 4)
	n.content_margin_left = 12
	n.content_margin_right = 12
	n.content_margin_top = 6
	n.content_margin_bottom = 6
	n.set_border_width_all(1)
	n.border_color = PAPER_DIM.darkened(0.15)
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = POP.lerp(PAPER, 0.55)
	h.border_color = INK
	var d: StyleBoxFlat = n.duplicate()
	d.bg_color = PAPER_DIM
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_stylebox_override("focus", _focus_style())
	return b


## ハンコの形のボタン: 店の「行動」（割引・土下座・補填など）。朱色の枠と文字、塗りは無し
static func stamp(label: String, size: int = S_SMALL) -> Button:
	var b: Button = _button_base(label, size, F_BOLD)
	_colors(b, SHU, PAPER, Color(SHU.r, SHU.g, SHU.b, 0.35))
	var n: StyleBoxFlat = flat_style(Color(PAPER.r, PAPER.g, PAPER.b, 0.0), 0, 6)
	n.content_margin_left = 12
	n.content_margin_right = 12
	n.content_margin_top = 6
	n.content_margin_bottom = 6
	n.set_border_width_all(2)
	n.border_color = SHU
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = SHU
	var d: StyleBoxFlat = n.duplicate()
	d.border_color = Color(SHU.r, SHU.g, SHU.b, 0.35)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_stylebox_override("focus", _focus_style())
	return b


## 文字だけのボタン（下線の代わりに、マウスを乗せると朱色になる）
static func link(label: String, size: int = S_BODY, color: Color = INK) -> Button:
	var b: Button = _button_base(label, size, F_BOLD)
	_colors(b, color, SHU, INK_SOFT)
	for st in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, empty_style(4, 4))
	b.add_theme_stylebox_override("focus", _focus_style())
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b


static func _focus_style() -> StyleBoxFlat:
	var f: StyleBoxFlat = StyleBoxFlat.new()
	f.draw_center = false
	f.set_border_width_all(2)
	f.border_color = SHU
	f.set_expand_margin_all(3)
	return f


# ---------------------------------------------------------------- 入力欄（枠で囲まず、下線だけ）

static func field(placeholder: String, size: int = S_LEAD) -> LineEdit:
	var e: LineEdit = LineEdit.new()
	e.placeholder_text = placeholder
	e.add_theme_font_size_override("font_size", size)
	e.add_theme_color_override("font_color", INK)
	e.add_theme_color_override("font_placeholder_color", INK_SOFT.lerp(PAPER, 0.25))
	e.add_theme_color_override("caret_color", SHU)
	e.add_theme_color_override("selection_color", POP.lerp(PAPER, 0.3))
	var n: StyleBoxFlat = StyleBoxFlat.new()
	n.bg_color = Color(PAPER.r, PAPER.g, PAPER.b, 0.0)
	n.draw_center = false
	n.border_width_bottom = 2
	n.border_color = INK_SOFT
	n.content_margin_left = 4
	n.content_margin_right = 4
	n.content_margin_top = 6
	n.content_margin_bottom = 6
	var f: StyleBoxFlat = n.duplicate()
	f.border_width_bottom = 3
	f.border_color = SHU
	var ro: StyleBoxFlat = n.duplicate()
	ro.border_color = PAPER_DIM
	e.add_theme_stylebox_override("normal", n)
	e.add_theme_stylebox_override("focus", f)
	e.add_theme_stylebox_override("read_only", ro)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return e


## 選択欄（入力欄と同じく、紙の上の下線）
static func option() -> OptionButton:
	var o: OptionButton = OptionButton.new()
	o.add_theme_font_size_override("font_size", S_BODY)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		o.add_theme_color_override(k, INK)
	var n: StyleBoxFlat = StyleBoxFlat.new()
	n.bg_color = PAPER
	n.border_width_bottom = 2
	n.border_color = INK_SOFT
	n.content_margin_left = 6
	n.content_margin_right = 6
	n.content_margin_top = 6
	n.content_margin_bottom = 6
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = POP.lerp(PAPER, 0.6)
	var f: StyleBoxFlat = n.duplicate()
	f.border_color = SHU
	f.border_width_bottom = 3
	o.add_theme_stylebox_override("normal", n)
	o.add_theme_stylebox_override("hover", h)
	o.add_theme_stylebox_override("pressed", h)
	o.add_theme_stylebox_override("focus", f)
	return o


static func check(label: String, on: bool) -> CheckBox:
	var c: CheckBox = CheckBox.new()
	c.text = label
	c.button_pressed = on
	c.add_theme_font_size_override("font_size", S_BODY)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		c.add_theme_color_override(k, INK)
	return c


# ---------------------------------------------------------------- 余白

static func gap(h: int) -> Control:
	var c: Control = Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func spacer() -> Control:
	var c: Control = Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func hbox(sep: int = 8) -> HBoxContainer:
	var b: HBoxContainer = HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func vbox(sep: int = 8) -> VBoxContainer:
	var b: VBoxContainer = VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


## 罫線（区切り）
static func rule(color: Color = PAPER_DIM, thickness: int = 2) -> ColorRect:
	var r: ColorRect = ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, thickness)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## 数を入れる箱（要件#86）: [◀][数][▶]。全角の数字でも入り、矢印のボタン・キーボードの↑↓でも変えられる
static func number_box(min_v: int, max_v: int, value: int, step_big: int, on_change: Callable) -> HBoxContainer:
	var row: HBoxContainer = hbox(4)
	var spin: SpinBox = SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = 1
	spin.value = value
	spin.custom_minimum_size = Vector2(84, 0)
	var le: LineEdit = spin.get_line_edit()
	le.add_theme_font_size_override("font_size", S_BODY)
	# 全角の数字・記号を半角に直す（IME で「３０」と打っても入る）
	le.text_changed.connect(func(t: String) -> void:
		var h: String = to_halfwidth(t)
		if h != t:
			var c: int = le.caret_column
			le.text = h
			le.caret_column = mini(c, h.length()))
	spin.value_changed.connect(func(v: float) -> void: on_change.call(int(v)))
	var down: Button = stamp("◀", S_SMALL)
	down.focus_mode = Control.FOCUS_NONE
	down.pressed.connect(func() -> void: spin.value -= step_big)
	var up: Button = stamp("▶", S_SMALL)
	up.focus_mode = Control.FOCUS_NONE
	up.pressed.connect(func() -> void: spin.value += step_big)
	row.add_child(down)
	row.add_child(spin)
	row.add_child(up)
	return row


static func to_halfwidth(t: String) -> String:
	var out: String = ""
	for i in range(t.length()):
		var c: int = t.unicode_at(i)
		if c >= 0xFF01 and c <= 0xFF5E:
			c -= 0xFEE0
		elif c == 0x3000:
			c = 0x20
		out += String.chr(c)
	return out
