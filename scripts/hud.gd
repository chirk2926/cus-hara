extends Control
## プレイ中の画面表示（HUD）。1人用・対戦の両方で使う。
## 上: ステージ名/進行/スコア  左: 状況メモ・店長の一言  中央: お客さんの吹き出し
## 右: 怒り/納得ゲージ  下: 定型文ボタン・入力欄

const UI = preload("res://scripts/ui_kit.gd")

signal reply_submitted(text: String)
signal pause_pressed
signal talk_started(duration: float)

const DEFAULT_PHRASES: Array = [
	"申し訳ございません。",
	"お気持ちお察しいたします。",
	"詳しくお聞かせいただけますか。",
	"すぐに確認いたします。",
	"恐れ入りますが、それはいたしかねます。",
]

var sfx = null

var _stage_label: Label
var _progress_label: Label
var _score_label: Label
var _memo_title: Label
var _memo_body: Label
var _memo_demand: Label
var _comment_label: Label
var _bubble: PanelContainer
var _bubble_name: Label
var _bubble_text: Label
var _echo: PanelContainer
var _echo_text: Label
var _banner: Label
var _anger_gauge: ProgressBar
var _anger_value: Label
var _countdown: Label
var _resolve_gauge: ProgressBar
var _resolve_value: Label
var _delta_label: Label
var _status: Label
var _quick_row: HFlowContainer
var _input: LineEdit
var _send: Button
var _input_enabled: bool = false
var _say_tween: Tween = null
var _banner_tween: Tween = null
var _delta_tween: Tween = null
var _typing: bool = false
var _blip_timer: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	set_quick_phrases(DEFAULT_PHRASES)
	set_input_enabled(false, "")


func _build() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	add_child(margin)
	var root: VBoxContainer = VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	# ---- 上部バー
	var top: PanelContainer = UI.panel(UI.C_PANEL, 12, 8)
	root.add_child(top)
	var top_row: HBoxContainer = HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	top.add_child(top_row)
	_stage_label = UI.label("", 20, UI.C_ACCENT, true)
	_stage_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(_stage_label)
	_progress_label = UI.label("", 20, UI.C_TEXT, true)
	_progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_row.add_child(_progress_label)
	_score_label = UI.label("", 20, UI.C_TEXT, true)
	_score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_row.add_child(_score_label)
	var pause_btn: Button = UI.button("メニュー", 16, UI.C_GRAY)
	pause_btn.focus_mode = Control.FOCUS_NONE
	pause_btn.pressed.connect(func() -> void: pause_pressed.emit())
	top_row.add_child(pause_btn)

	# ---- 中段
	var mid: HBoxContainer = HBoxContainer.new()
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 12)
	root.add_child(mid)

	# 左: 状況メモと店長の一言
	var left: VBoxContainer = VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", 10)
	mid.add_child(left)
	var memo: PanelContainer = UI.panel(Color(1.0, 0.97, 0.78, 0.96), 10, 12)
	left.add_child(memo)
	var memo_box: VBoxContainer = VBoxContainer.new()
	memo_box.add_theme_constant_override("separation", 4)
	memo.add_child(memo_box)
	memo_box.add_child(UI.label("状況メモ", 15, Color(0.55, 0.4, 0.1), true))
	_memo_title = UI.wrap_label("", 20, UI.C_TEXT_DARK, true)
	memo_box.add_child(_memo_title)
	_memo_body = UI.wrap_label("", 16, UI.C_TEXT_DARK)
	memo_box.add_child(_memo_body)
	_memo_demand = UI.wrap_label("", 15, Color(0.7, 0.12, 0.12), true)
	memo_box.add_child(_memo_demand)
	var comment: PanelContainer = UI.panel(UI.C_PANEL, 10, 12)
	left.add_child(comment)
	var comment_box: VBoxContainer = VBoxContainer.new()
	comment.add_child(comment_box)
	comment_box.add_child(UI.label("店長の一言", 15, UI.C_ACCENT, true))
	_comment_label = UI.wrap_label("落ち着いて、まずは話を聞こう。", 16, UI.C_TEXT)
	comment_box.add_child(_comment_label)
	left.add_child(UI.spacer())

	# 中央: 吹き出し・バナー・自分の返答
	var center: VBoxContainer = VBoxContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 8)
	mid.add_child(center)
	center.add_child(UI.spacer())
	_banner = UI.label("", 44, Color.WHITE, true)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner.add_theme_constant_override("outline_size", 12)
	_banner.modulate = Color(1, 1, 1, 0)
	center.add_child(_banner)
	# 吹き出しはお客さんの顔の下（胴体のあたり）に出す。顔と店内を隠さないため。
	_bubble = UI.panel(UI.C_PANEL_LIGHT, 18, 16, Color(0.15, 0.15, 0.2), 3)
	center.add_child(_bubble)
	var bubble_box: VBoxContainer = VBoxContainer.new()
	bubble_box.add_theme_constant_override("separation", 2)
	_bubble.add_child(bubble_box)
	_bubble_name = UI.label("", 16, UI.C_RED, true)
	bubble_box.add_child(_bubble_name)
	_bubble_text = UI.wrap_label("", 22, UI.C_TEXT_DARK, true)
	_bubble_text.custom_minimum_size = Vector2(0, 66)
	bubble_box.add_child(_bubble_text)
	_bubble.visible = false

	# 右: ゲージ
	var right: VBoxContainer = VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.custom_minimum_size = Vector2(270, 0)
	right.add_theme_constant_override("separation", 10)
	mid.add_child(right)
	var anger_panel: PanelContainer = UI.panel(UI.C_PANEL, 10, 12)
	right.add_child(anger_panel)
	var anger_box: VBoxContainer = VBoxContainer.new()
	anger_box.add_theme_constant_override("separation", 4)
	anger_panel.add_child(anger_box)
	var anger_head: HBoxContainer = HBoxContainer.new()
	anger_box.add_child(anger_head)
	var anger_title: Label = UI.label("怒りゲージ", 17, UI.C_RED, true)
	anger_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	anger_head.add_child(anger_title)
	_anger_value = UI.label("0", 17, UI.C_TEXT, true)
	anger_head.add_child(_anger_value)
	_anger_gauge = UI.gauge(UI.C_RED, 30)
	anger_box.add_child(_anger_gauge)
	_countdown = UI.label("", 16, UI.C_ACCENT, true)
	anger_box.add_child(_countdown)
	var resolve_panel: PanelContainer = UI.panel(UI.C_PANEL, 10, 12)
	right.add_child(resolve_panel)
	var resolve_box: VBoxContainer = VBoxContainer.new()
	resolve_box.add_theme_constant_override("separation", 4)
	resolve_panel.add_child(resolve_box)
	var resolve_head: HBoxContainer = HBoxContainer.new()
	resolve_box.add_child(resolve_head)
	var resolve_title: Label = UI.label("納得ゲージ", 17, UI.C_GREEN, true)
	resolve_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resolve_head.add_child(resolve_title)
	_resolve_value = UI.label("0", 17, UI.C_TEXT, true)
	resolve_head.add_child(_resolve_value)
	_resolve_gauge = UI.gauge(UI.C_GREEN, 22)
	resolve_box.add_child(_resolve_gauge)
	resolve_box.add_child(UI.label("100で納得して帰ってくれる", 13, UI.C_MUTED))
	_delta_label = UI.label("", 22, Color.WHITE, true)
	_delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_delta_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_delta_label.add_theme_constant_override("outline_size", 8)
	_delta_label.modulate = Color(1, 1, 1, 0)
	right.add_child(_delta_label)
	right.add_child(UI.spacer())

	# ---- 下段: 入力
	var bottom: PanelContainer = UI.panel(UI.C_PANEL, 14, 12)
	root.add_child(bottom)
	var bottom_box: VBoxContainer = VBoxContainer.new()
	bottom_box.add_theme_constant_override("separation", 8)
	bottom.add_child(bottom_box)
	# 自分（または相手の店員）の直前の返答を1行で表示する
	_echo = UI.panel(Color(0.16, 0.36, 0.72, 0.92), 10, 6)
	bottom_box.add_child(_echo)
	_echo_text = UI.label("", 16, Color.WHITE)
	_echo_text.clip_text = true
	_echo_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_echo.add_child(_echo_text)
	_echo.visible = false
	_status = UI.label("", 16, UI.C_MUTED)
	bottom_box.add_child(_status)
	_quick_row = HFlowContainer.new()
	_quick_row.add_theme_constant_override("h_separation", 8)
	_quick_row.add_theme_constant_override("v_separation", 6)
	bottom_box.add_child(_quick_row)
	var input_row: HBoxContainer = HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 10)
	bottom_box.add_child(input_row)
	_input = UI.line_edit("", 22)
	_input.max_length = 200
	_input.text_submitted.connect(_on_text_submitted)
	input_row.add_child(_input)
	_send = UI.button("  返事する  ", 22, UI.C_BLUE)
	_send.focus_mode = Control.FOCUS_NONE
	_send.pressed.connect(_submit)
	input_row.add_child(_send)


func _process(delta: float) -> void:
	if _typing and sfx != null:
		_blip_timer -= delta
		if _blip_timer <= 0.0:
			_blip_timer = 0.07
			sfx.play("talk", randf_range(0.85, 1.15))


# ---------------------------------------------------------------- 表示の更新

func set_top(stage_text: String, progress_text: String, score_text: String) -> void:
	_stage_label.text = stage_text
	_progress_label.text = progress_text
	_score_label.text = score_text


func set_memo(title: String, body: String, demand: String) -> void:
	_memo_title.text = title
	_memo_body.text = body
	_memo_demand.text = ("不当な要求: " + demand) if demand != "" else ""


func set_comment(text: String) -> void:
	_comment_label.text = text


func set_status(text: String) -> void:
	_status.text = text


## seconds_left < 0 のときはカウントダウンを隠す
func set_gauges(anger: float, resolve: float, seconds_left: float) -> void:
	_anger_gauge.value = clampf(anger, 0.0, 100.0)
	_resolve_gauge.value = clampf(resolve, 0.0, 100.0)
	_anger_value.text = str(int(clampf(anger, 0.0, 100.0)))
	_resolve_value.text = str(int(clampf(resolve, 0.0, 100.0)))
	var c: Color = Color(1.0, 0.72, 0.2).lerp(UI.C_RED, clampf((anger - 30.0) / 50.0, 0.0, 1.0))
	UI.set_gauge_color(_anger_gauge, c)
	if seconds_left < 0.0:
		_countdown.text = ""
	else:
		_countdown.text = "キレるまで あと %d 秒" % int(ceil(seconds_left))
		_countdown.add_theme_color_override("font_color", UI.C_RED if seconds_left < 10.0 else UI.C_ACCENT)


## 怒り・納得の増減を一瞬表示する
func show_delta(anger_delta: int, resolve_delta: int) -> void:
	var parts: PackedStringArray = PackedStringArray()
	if anger_delta != 0:
		parts.append("怒り %+d" % anger_delta)
	if resolve_delta != 0:
		parts.append("納得 %+d" % resolve_delta)
	if parts.is_empty():
		parts.append("効果なし…")
	_delta_label.text = "\n".join(parts)
	var good: bool = anger_delta < 0 or (anger_delta == 0 and resolve_delta > 0)
	_delta_label.add_theme_color_override("font_color", UI.C_GREEN.lightened(0.3) if good else UI.C_RED.lightened(0.3))
	if _delta_tween != null and _delta_tween.is_valid():
		_delta_tween.kill()
	_delta_label.modulate = Color(1, 1, 1, 1)
	_delta_tween = create_tween()
	_delta_tween.tween_interval(1.6)
	_delta_tween.tween_property(_delta_label, "modulate", Color(1, 1, 1, 0), 0.6)


func show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner.modulate = Color(1, 1, 1, 0)
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate", Color(1, 1, 1, 1), 0.2)
	_banner_tween.tween_interval(1.8)
	_banner_tween.tween_property(_banner, "modulate", Color(1, 1, 1, 0), 0.5)


## 吹き出しに1文字ずつ表示する。表示し終わるまで await できる。
func say(speaker: String, text: String) -> void:
	_bubble.visible = true
	_bubble_name.text = speaker
	_bubble_text.text = text
	_bubble_text.visible_ratio = 0.0
	var dur: float = clampf(float(text.length()) * 0.045, 0.5, 3.6)
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


func show_echo(prefix: String, text: String) -> void:
	_echo.visible = text != ""
	_echo_text.text = prefix + text


func clear_round() -> void:
	hide_bubble()
	show_echo("", "")
	set_memo("", "", "")
	set_gauges(0.0, 0.0, -1.0)
	set_input_enabled(false, "")


# ---------------------------------------------------------------- 入力

func set_quick_phrases(phrases: Array) -> void:
	for c in _quick_row.get_children():
		c.queue_free()
	for p in phrases:
		var phrase: String = str(p)
		var b: Button = UI.button(phrase, 15, Color(0.22, 0.25, 0.36))
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_quick.bind(phrase))
		_quick_row.add_child(b)


func set_input_enabled(on: bool, placeholder: String) -> void:
	_input_enabled = on
	_input.editable = on
	_input.placeholder_text = placeholder
	_send.disabled = not on
	for c in _quick_row.get_children():
		if c is Button:
			(c as Button).disabled = not on
	if on:
		_input.text = ""
		_input.grab_focus()


func _on_quick(phrase: String) -> void:
	if not _input_enabled:
		return
	if sfx != null:
		sfx.play("click")
	_input.text = _input.text + phrase
	_input.caret_column = _input.text.length()
	_input.grab_focus()


func _on_text_submitted(_text: String) -> void:
	_submit()


func _submit() -> void:
	if not _input_enabled:
		return
	var text: String = _input.text.strip_edges()
	if text == "":
		return
	set_input_enabled(false, "")
	_input.text = ""
	if sfx != null:
		sfx.play("send")
	reply_submitted.emit(text)
