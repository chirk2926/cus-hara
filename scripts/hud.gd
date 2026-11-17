extends Control
## プレイ中の画面（1人用・対戦で共通）。見た目の決まりは docs/UI_GUIDE.md。
##   左上: 名札（店名・何人目・点数）
##   左:   引き継ぎメモ（状況）と付箋（店長の一言）
##   右:   お客様用のレジ表示器（怒り・納得・残り秒数）
##   中央: お客さんの顔（何も重ねない）→ 大きな判定の文字 → フキダシ
##   下:   伝言の記入欄（定型文タグ・入力・返事ボタン。音声モードでは「押して話す」）
## ゲームのルールは持たない。

const UI = preload("res://scripts/ui_kit.gd")
const Paper = preload("res://scripts/ui_paper.gd")

signal reply_submitted(text: String)
signal pause_pressed
signal talk_started(duration: float)
signal voice_start
signal voice_stop
signal action_pressed(id: String)

## 定型文（日本語の文がキー。英語は翻訳ファイルで差し替わる）
const DEFAULT_PHRASES: Array = [
	"申し訳ございません。",
	"お気持ちお察しいたします。",
	"詳しくお聞かせいただけますか。",
	"すぐに確認いたします。",
	"恐れ入りますが、それはいたしかねます。",
]

var sfx = null

var _shop: Label
var _progress: Label
var _score: Label
var _memo_title: Label
var _memo_body: Label
var _memo_demand: Label
var _note: Label
var _lcd
var _bubble
var _bubble_name: Label
var _bubble_text: RichTextLabel
var _banner: Label
var _delta: Label
var _echo: Label
var _status: Label
var _tags: HBoxContainer
var _actions: HBoxContainer
var _desk: PanelContainer
var _upper: MarginContainer
var _mental
var _mental_row: HBoxContainer
var _field: LineEdit
var _send: Button
var _talk: Button
var _level: ProgressBar
var _text_row: HBoxContainer
var _voice_row: HBoxContainer
var _voice_mode: bool = false
var _input_on: bool = false
var _say_tween: Tween = null
var _banner_tween: Tween = null
var _delta_tween: Tween = null
var _typing: bool = false
var _blip: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	set_quick_phrases(DEFAULT_PHRASES)
	set_input_enabled(false, "")


func _build() -> void:
	# ---- 下: 伝言の記入欄。画面の下に固定し、上の部品の大きさに左右されない（要件#29）
	_desk = UI.paper(UI.PAPER, 16, 4)
	_desk.anchor_left = 0.0
	_desk.anchor_right = 1.0
	_desk.anchor_top = 1.0
	_desk.anchor_bottom = 1.0
	_desk.offset_left = 24
	_desk.offset_right = -24
	_desk.offset_top = -16
	_desk.offset_bottom = -16
	_desk.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_desk)
	var db: VBoxContainer = UI.vbox(8)
	_desk.add_child(db)
	var head: HBoxContainer = UI.hbox(16)
	db.add_child(head)
	_status = UI.text("", UI.S_SMALL, UI.INK_SOFT)
	head.add_child(_status)
	_echo = UI.text("", UI.S_SMALL, UI.INK)
	_echo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_echo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_echo.clip_text = true
	_echo.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_echo)
	# 接客用語のタグ
	_tags = UI.hbox(8)
	db.add_child(_tags)

	# 入力の行: [店の行動ボタン（ハンコ）][記入欄][返事をする]。記入欄が縮むので、はみ出さない
	_text_row = UI.hbox(16)
	db.add_child(_text_row)
	_actions = UI.hbox(8)
	_actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_text_row.add_child(_actions)
	_field = UI.field("", UI.S_LEAD)
	_field.max_length = 200
	_field.text_submitted.connect(func(_t: String) -> void: _submit())
	_text_row.add_child(_field)
	_send = UI.primary(tr("返事をする"), UI.S_LEAD)
	_send.focus_mode = Control.FOCUS_NONE
	_send.pressed.connect(_submit)
	_text_row.add_child(_send)

	_voice_row = UI.hbox(16)
	db.add_child(_voice_row)
	_talk = UI.primary(tr("押して話す（スペース）"), UI.S_LEAD)
	_talk.focus_mode = Control.FOCUS_NONE
	_talk.custom_minimum_size = Vector2(360, 0)
	_talk.button_down.connect(func() -> void: _voice_press(true))
	_talk.button_up.connect(func() -> void: _voice_press(false))
	_voice_row.add_child(_talk)
	_level = ProgressBar.new()
	_level.show_percentage = false
	_level.max_value = 1.0
	_level.custom_minimum_size = Vector2(160, 12)
	_level.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_level.add_theme_stylebox_override("background", UI.flat_style(UI.PAPER_DIM, 0, 0))
	_level.add_theme_stylebox_override("fill", UI.flat_style(UI.OK, 0, 0))
	_voice_row.add_child(_level)
	var type_instead: Button = UI.link(tr("文字で入力する"), UI.S_SMALL, UI.INK_SOFT)
	type_instead.focus_mode = Control.FOCUS_NONE
	type_instead.pressed.connect(func() -> void:
		_text_row.visible = true
		_focus_field())
	_voice_row.add_child(type_instead)
	_voice_row.visible = false

	# ---- 上: 記入欄より上の残りの場所
	_upper = MarginContainer.new()
	_upper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_upper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_upper.add_theme_constant_override("margin_left", 24)
	_upper.add_theme_constant_override("margin_right", 24)
	_upper.add_theme_constant_override("margin_top", 16)
	_upper.add_theme_constant_override("margin_bottom", 200)
	add_child(_upper)
	move_child(_upper, 0)
	_desk.resized.connect(_fit_upper)

	var mid: HBoxContainer = UI.hbox(24)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_upper.add_child(mid)

	# ---- 左: 名札・引き継ぎメモ・付箋（はみ出す分は切る。記入欄は押し下げない）
	var left: VBoxContainer = UI.vbox(12)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.custom_minimum_size = Vector2(300, 0)
	left.clip_contents = true
	mid.add_child(left)

	var tag_row: HBoxContainer = UI.hbox(0)
	left.add_child(tag_row)
	var nametag: PanelContainer = UI.paper(UI.INK, 8, 3)
	tag_row.add_child(nametag)
	var nt: VBoxContainer = UI.vbox(2)
	nametag.add_child(nt)
	_shop = UI.text("", UI.S_BODY, UI.POP, UI.F_SIGN)
	nt.add_child(_shop)
	var nt2: HBoxContainer = UI.hbox(12)
	nt.add_child(nt2)
	_progress = UI.text("", UI.S_SMALL, UI.PAPER, UI.F_DOT)
	nt2.add_child(_progress)
	_score = UI.text("", UI.S_SMALL, UI.PAPER, UI.F_DOT)
	nt2.add_child(_score)
	# 店員のメンタル（要件#38）
	_mental_row = UI.hbox(8)
	nt.add_child(_mental_row)
	_mental_row.add_child(UI.text(tr("メンタル"), UI.S_SMALL, UI.PAPER, UI.F_DOT))
	_mental = Paper.DotBar.new()
	_mental.custom_minimum_size = Vector2(150, 12)
	_mental.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mental_row.add_child(_mental)
	_mental_row.visible = false
	var menu: Button = UI.link(tr("休憩"), UI.S_SMALL, UI.INK)
	menu.focus_mode = Control.FOCUS_NONE
	menu.tooltip_text = tr("一時停止（Esc）")
	menu.add_theme_stylebox_override("normal", UI.paper_style(UI.PAPER, 8, 0, 3))
	menu.add_theme_stylebox_override("hover", UI.paper_style(UI.POP, 8, 0, 3))
	menu.add_theme_stylebox_override("pressed", UI.paper_style(UI.POP, 8, 0, 1))
	menu.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	menu.pressed.connect(func() -> void: pause_pressed.emit())
	tag_row.add_child(menu)

	var memo = Paper.Memo.new()
	left.add_child(memo)
	var mb: VBoxContainer = UI.vbox(4)
	memo.add_child(mb)
	mb.add_child(UI.text(tr("引き継ぎメモ"), UI.S_SMALL, UI.INK_SOFT, UI.F_HAND))
	_memo_title = UI.para("", UI.S_LEAD, UI.INK, UI.F_HAND)
	mb.add_child(_memo_title)
	_memo_body = UI.para("", UI.S_BODY, UI.INK, UI.F_HAND)
	_memo_body.max_lines_visible = 6
	mb.add_child(_memo_body)
	_memo_demand = UI.para("", UI.S_SMALL, UI.SHU, UI.F_HAND)
	_memo_demand.max_lines_visible = 3
	mb.add_child(_memo_demand)

	var note: PanelContainer = UI.paper(UI.POP, 12, 3)
	note.custom_minimum_size = Vector2(240, 0)
	note.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(note)
	var nb: VBoxContainer = UI.vbox(2)
	note.add_child(nb)
	nb.add_child(UI.text(tr("店長より"), UI.S_SMALL, UI.INK_SOFT, UI.F_HAND))
	_note = UI.para(tr("落ち着いて、まずは話を聞こう。"), UI.S_BODY, UI.INK, UI.F_HAND)
	_note.custom_minimum_size = Vector2(210, 0)
	_note.max_lines_visible = 3
	nb.add_child(_note)

	# ---- 中央: 顔は空ける → フキダシ（文字の量に合わせて高さが変わる。要件#30）
	var center: VBoxContainer = UI.vbox(8)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(center)
	center.add_child(UI.spacer())
	_bubble = Paper.Bubble.new()
	center.add_child(_bubble)
	var bb: VBoxContainer = UI.vbox(2)
	_bubble.add_child(bb)
	_bubble_name = UI.text("", UI.S_SMALL, UI.SHU, UI.F_BOLD)
	bb.add_child(_bubble_name)
	_bubble_text = RichTextLabel.new()
	_bubble_text.bbcode_enabled = false
	_bubble_text.fit_content = true
	_bubble_text.scroll_active = false
	# 文字を出していく途中で折り返しが変わらないよう、全文で配置してから見せる
	_bubble_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_bubble_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bubble_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_text.add_theme_font_override("normal_font", UI.font(UI.F_BOLD))
	_bubble_text.add_theme_font_size_override("normal_font_size", UI.S_LEAD)
	_bubble_text.add_theme_color_override("default_color", UI.INK)
	bb.add_child(_bubble_text)
	_bubble.visible = false

	# 判定の大きな文字: 画面の上の中央（名札とレジ表示器の間）。お客さんの顔には重ねない
	_banner = UI.text("", UI.S_HUGE, UI.PAPER, UI.F_SIGN)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.add_theme_color_override("font_outline_color", UI.INK)
	_banner.add_theme_constant_override("outline_size", 14)
	_banner.modulate = Color(1, 1, 1, 0)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.anchor_left = 0.27
	_banner.anchor_right = 0.73
	_banner.anchor_top = 0.0
	_banner.anchor_bottom = 0.0
	_banner.offset_top = 24
	_banner.offset_bottom = 160
	add_child(_banner)

	# ---- 右: レジ表示器
	var right: VBoxContainer = UI.vbox(12)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.custom_minimum_size = Vector2(300, 0)
	mid.add_child(right)
	_lcd = Paper.Lcd.new()
	_lcd.caption = tr("お客様表示")
	right.add_child(_lcd)
	_delta = UI.text("", UI.S_HEAD, UI.PAPER, UI.F_SIGN)
	_delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_delta.add_theme_color_override("font_outline_color", UI.INK)
	_delta.add_theme_constant_override("outline_size", 10)
	_delta.modulate = Color(1, 1, 1, 0)
	right.add_child(_delta)


## 記入欄の高さが変わったら、上の場所をその分だけ縮める
func _fit_upper() -> void:
	_upper.add_theme_constant_override("margin_bottom", int(_desk.size.y) + 16 + 12)


func _process(delta: float) -> void:
	if _typing and sfx != null:
		_blip -= delta
		if _blip <= 0.0:
			_blip = 0.07
			sfx.play("talk", randf_range(0.85, 1.15))


## 記入欄に入力を向ける。クリックしなくても打てるように、少し遅らせてからもう一度
func _focus_field() -> void:
	if not is_inside_tree():
		return
	_field.call_deferred("grab_focus")
	_field.call_deferred("set_caret_column", _field.text.length())


## 記入欄の外で文字キーを押しても、記入欄に入るようにする（要件#40）
func _input(event: InputEvent) -> void:
	if not _input_on or _voice_mode or not visible or not _text_row.visible or _field.has_focus():
		return
	if event is InputEventKey and event.is_pressed():
		var k: InputEventKey = event
		if k.unicode >= 32 or k.keycode == KEY_BACKSPACE or k.keycode == KEY_ENTER:
			if get_viewport().gui_get_focus_owner() == null or not (get_viewport().gui_get_focus_owner() is LineEdit):
				_field.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not _voice_mode or not _input_on or not visible:
		return
	if event is InputEventKey and not event.is_echo() and (event as InputEventKey).keycode == GameSettings.push_to_talk_key:
		if _field.has_focus():
			return
		_voice_press(event.is_pressed())
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 表示

func set_top(shop_text: String, progress_text: String, score_text: String) -> void:
	_shop.text = shop_text
	_progress.text = progress_text
	_score.text = score_text


func set_memo(title: String, body: String, demand: String) -> void:
	_memo_title.text = title
	_memo_body.text = body
	_memo_demand.text = (tr("※ 要求: ") + demand) if demand != "" else ""


## 店員のメンタル（0〜100）。負の値を渡すと隠す
func set_mental(v: float) -> void:
	_mental_row.visible = v >= 0.0
	if v >= 0.0:
		_mental.value = v
		_mental.color = UI.LCD_ON if v > 60.0 else (UI.POP if v > 30.0 else Color("#ff8a6a"))


## 店の行動ボタン。items: [[id, 表示名], ...]。空なら消す
func set_actions(items: Array) -> void:
	for c in _actions.get_children():
		c.queue_free()
	for it in items:
		var id: String = str(it[0])
		var b: Button = UI.stamp(tr(str(it[1])), UI.S_SMALL)
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = not _input_on
		b.pressed.connect(func() -> void:
			if _input_on:
				if sfx != null:
					sfx.play("click")
				action_pressed.emit(id))
		_actions.add_child(b)


func set_comment(t: String) -> void:
	_note.text = t


func set_status(t: String) -> void:
	_status.text = t


## seconds_left < 0 なら残り秒数を出さない
func set_gauges(anger: float, resolve: float, seconds_left: float) -> void:
	_lcd.set_values(anger, resolve, seconds_left)


func show_delta(anger_delta: int, resolve_delta: int) -> void:
	var parts: PackedStringArray = PackedStringArray()
	if anger_delta != 0:
		parts.append(tr("怒り %+d") % anger_delta)
	if resolve_delta != 0:
		parts.append(tr("納得 %+d") % resolve_delta)
	if parts.is_empty():
		parts.append(tr("効果なし"))
	_delta.text = "\n".join(parts)
	var good: bool = anger_delta < 0 or (anger_delta == 0 and resolve_delta > 0)
	_delta.add_theme_color_override("font_color", UI.LCD_ON if good else Color("#ff8a6a"))
	if _delta_tween != null and _delta_tween.is_valid():
		_delta_tween.kill()
	_delta.modulate = Color(1, 1, 1, 1)
	_delta_tween = create_tween()
	_delta_tween.tween_interval(1.6)
	_delta_tween.tween_property(_delta, "modulate", Color(1, 1, 1, 0), 0.5).set_ease(Tween.EASE_OUT)


func show_banner(t: String, color: Color) -> void:
	_banner.text = t
	_banner.add_theme_color_override("font_color", color)
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner.modulate = Color(1, 1, 1, 0)
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate", Color(1, 1, 1, 1), 0.15).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(1.8)
	_banner_tween.tween_property(_banner, "modulate", Color(1, 1, 1, 0), 0.4)


## フキダシに1文字ずつ出す。出し終わるまで await できる。angry でギザギザ
func say(speaker: String, t: String, angry: bool = false) -> void:
	_bubble.visible = true
	_bubble.jagged = angry
	_bubble_name.text = speaker
	_bubble_text.text = t
	_bubble_text.visible_ratio = 0.0
	var dur: float = clampf(float(t.length()) * 0.045, 0.5, 3.6)
	if _say_tween != null and _say_tween.is_valid():
		_say_tween.kill()
	_typing = true
	talk_started.emit(dur)
	_say_tween = create_tween()
	_say_tween.tween_property(_bubble_text, "visible_ratio", 1.0, dur)
	await _say_tween.finished
	_typing = false


func hide_bubble() -> void:
	_bubble.visible = false
	_typing = false


func show_echo(prefix: String, t: String) -> void:
	_echo.text = (prefix + t) if t != "" else ""


func clear_round() -> void:
	hide_bubble()
	show_echo("", "")
	set_memo("", "", "")
	set_gauges(0.0, 0.0, -1.0)
	set_input_enabled(false, "")


# ---------------------------------------------------------------- 入力

func set_quick_phrases(phrases: Array) -> void:
	for c in _tags.get_children():
		c.queue_free()
	for p in phrases:
		var phrase: String = tr(str(p))
		var b: Button = UI.tag(phrase, UI.S_SMALL)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_tag.bind(phrase))
		_tags.add_child(b)


## 音声モード: 入力欄の代わりに「押して話す」ボタンを出す
func set_voice_mode(on: bool) -> void:
	_voice_mode = on
	_voice_row.visible = on
	_text_row.visible = not on
	_tags.visible = not on


func set_voice_level(v: float) -> void:
	_level.value = v


func set_input_enabled(on: bool, placeholder: String) -> void:
	_input_on = on
	_field.editable = on
	_field.placeholder_text = placeholder
	_send.disabled = not on
	_talk.disabled = not on
	for c in _tags.get_children():
		if c is Button:
			(c as Button).disabled = not on
	if on and _text_row.visible:
		_field.text = ""
		_focus_field()
	for c in _actions.get_children():
		if c is Button:
			(c as Button).disabled = not on


func _voice_press(down: bool) -> void:
	if not _input_on and down:
		return
	if down:
		_talk.text = tr("話しています…（離すと送信）")
		voice_start.emit()
	else:
		_talk.text = tr("押して話す（スペース）")
		voice_stop.emit()


func _on_tag(phrase: String) -> void:
	if not _input_on:
		return
	if sfx != null:
		sfx.play("click")
	_field.text = _field.text + phrase
	_field.caret_column = _field.text.length()
	_focus_field()


func _submit() -> void:
	if not _input_on:
		return
	var t: String = _field.text.strip_edges()
	if t == "":
		return
	set_input_enabled(false, "")
	_field.text = ""
	if sfx != null:
		sfx.play("send")
	reply_submitted.emit(t)
