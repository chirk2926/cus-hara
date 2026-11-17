extends RefCounted
## UI部品の共通ヘルパー（色・角丸パネル・ボタン・ゲージ）。
## 使い方: const UI = preload("res://scripts/ui_kit.gd") → UI.label(...)

const C_PANEL: Color = Color(0.07, 0.08, 0.13, 0.9)
const C_PANEL_LIGHT: Color = Color(0.98, 0.97, 0.94, 0.97)
const C_TEXT: Color = Color(0.96, 0.96, 0.98)
const C_TEXT_DARK: Color = Color(0.12, 0.12, 0.16)
const C_MUTED: Color = Color(0.68, 0.7, 0.78)
const C_ACCENT: Color = Color(1.0, 0.78, 0.2)
const C_RED: Color = Color(0.93, 0.26, 0.26)
const C_GREEN: Color = Color(0.2, 0.78, 0.47)
const C_BLUE: Color = Color(0.25, 0.52, 0.96)
const C_PURPLE: Color = Color(0.58, 0.36, 0.9)
const C_GRAY: Color = Color(0.3, 0.32, 0.4)

const BOLD_FONT_PATH: String = "res://assets/fonts/NotoSansJP_800ExtraBold.ttf"

static var _bold: Font = null


static func bold_font() -> Font:
	if _bold == null and ResourceLoader.exists(BOLD_FONT_PATH):
		_bold = load(BOLD_FONT_PATH) as Font
	return _bold


static func style(bg: Color, radius: int = 14, pad: int = 12, border: Color = Color(0, 0, 0, 0), border_w: int = 0) -> StyleBoxFlat:
	var s: StyleBoxFlat = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	if border_w > 0:
		s.set_border_width_all(border_w)
		s.border_color = border
	return s


static func label(text: String, size: int, color: Color = C_TEXT, bold: bool = false) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold and bold_font() != null:
		l.add_theme_font_override("font", bold_font())
	return l


## 折り返すラベル（日本語は単語区切りがないので任意位置で折り返す）
static func wrap_label(text: String, size: int, color: Color = C_TEXT, bold: bool = false) -> Label:
	var l: Label = label(text, size, color, bold)
	l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func panel(bg: Color = C_PANEL, radius: int = 14, pad: int = 14, border: Color = Color(0, 0, 0, 0), border_w: int = 0) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", style(bg, radius, pad, border, border_w))
	return p


static func button(text: String, size: int, bg: Color, fg: Color = Color.WHITE) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	if bold_font() != null:
		b.add_theme_font_override("font", bold_font())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, fg)
	b.add_theme_color_override("font_disabled_color", Color(fg.r, fg.g, fg.b, 0.45))
	b.add_theme_stylebox_override("normal", style(bg, 12, 10))
	b.add_theme_stylebox_override("hover", style(bg.lightened(0.18), 12, 10))
	b.add_theme_stylebox_override("pressed", style(bg.darkened(0.2), 12, 10))
	b.add_theme_stylebox_override("disabled", style(Color(bg.r, bg.g, bg.b, 0.35), 12, 10))
	b.add_theme_stylebox_override("focus", style(Color(0, 0, 0, 0), 12, 10, Color(1, 1, 1, 0.7), 2))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


static func gauge(fill: Color, height: int = 26) -> ProgressBar:
	var g: ProgressBar = ProgressBar.new()
	g.min_value = 0.0
	g.max_value = 100.0
	g.show_percentage = false
	g.custom_minimum_size = Vector2(0, height)
	g.add_theme_stylebox_override("background", style(Color(0, 0, 0, 0.55), 8, 0))
	g.add_theme_stylebox_override("fill", style(fill, 8, 0))
	return g


static func set_gauge_color(g: ProgressBar, fill: Color) -> void:
	var s: StyleBox = g.get_theme_stylebox("fill")
	if s is StyleBoxFlat:
		(s as StyleBoxFlat).bg_color = fill


static func line_edit(placeholder: String, size: int = 20) -> LineEdit:
	var e: LineEdit = LineEdit.new()
	e.placeholder_text = placeholder
	e.add_theme_font_size_override("font_size", size)
	e.add_theme_color_override("font_color", C_TEXT_DARK)
	e.add_theme_color_override("font_placeholder_color", Color(0.45, 0.45, 0.5))
	e.add_theme_color_override("caret_color", C_TEXT_DARK)
	e.add_theme_stylebox_override("normal", style(Color(1, 1, 1), 10, 10, Color(0.6, 0.62, 0.7), 2))
	e.add_theme_stylebox_override("focus", style(Color(1, 1, 1), 10, 10, C_ACCENT, 3))
	e.add_theme_stylebox_override("read_only", style(Color(0.8, 0.8, 0.84), 10, 10, Color(0.6, 0.62, 0.7), 2))
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return e


static func spacer(expand: bool = true, min_size: Vector2 = Vector2.ZERO) -> Control:
	var c: Control = Control.new()
	c.custom_minimum_size = min_size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c
