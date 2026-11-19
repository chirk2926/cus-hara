extends RefCounted
## 自前で描く画面部品（docs/UI_GUIDE.md 2節の「店の物」）。
## 使い方: const Paper = preload("res://scripts/ui_paper.gd") → Paper.Bubble.new()

const UI = preload("res://scripts/ui_kit.gd")


## マンガのフキダシ。子（Label など）を1つ入れる。しっぽは上（お客さんの顔の方）を向く。
## jagged = true で怒りのギザギザ。
class Bubble extends Container:
	const PAD_X: float = 26.0
	const PAD_Y: float = 18.0
	const TAIL: float = 22.0
	var jagged: bool = false:
		set(v):
			jagged = v
			queue_redraw()
	var tail_x: float = 0.5:
		set(v):
			tail_x = v
			queue_redraw()

	func _get_minimum_size() -> Vector2:
		var m: Vector2 = Vector2.ZERO
		for c in get_children():
			if c is Control and (c as Control).visible:
				m = m.max((c as Control).get_combined_minimum_size())
		return m + Vector2(PAD_X * 2.0, PAD_Y * 2.0 + TAIL)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			for c in get_children():
				if c is Control:
					fit_child_in_rect(c as Control, Rect2(Vector2(PAD_X, PAD_Y + TAIL), size - Vector2(PAD_X * 2.0, PAD_Y * 2.0 + TAIL)))

	func _draw() -> void:
		var body: Rect2 = Rect2(Vector2(0, TAIL), size - Vector2(0, TAIL))
		var ink: Color = UI.INK
		var fill: Color = UI.PAPER.lightened(0.6)
		var tx: float = clampf(size.x * tail_x, 40.0, size.x - 40.0)
		if jagged:
			var pts: PackedVector2Array = _burst(body)
			draw_colored_polygon(pts, fill)
			pts.append(pts[0])
			draw_polyline(pts, ink, 3.0, true)
		else:
			var s: StyleBoxFlat = StyleBoxFlat.new()
			s.bg_color = fill
			s.set_corner_radius_all(int(minf(body.size.y * 0.5, 40.0)))
			s.corner_detail = 12
			s.set_border_width_all(3)
			s.border_color = ink
			s.anti_aliasing = true
			draw_style_box(s, body)
		# しっぽ（線の重なりを消すため、塗ってから2辺だけ線を引く）
		var a: Vector2 = Vector2(tx - 14.0, TAIL + 4.0)
		var b: Vector2 = Vector2(tx + 10.0, TAIL + 4.0)
		var tip: Vector2 = Vector2(tx + 6.0, 0.0)
		draw_colored_polygon(PackedVector2Array([a, tip, b]), fill)
		draw_line(a, tip, ink, 3.0, true)
		draw_line(tip, b, ink, 3.0, true)

	## 四角の周りをたどり、外向きのトゲを交互に出した多角形
	func _burst(r: Rect2) -> PackedVector2Array:
		var pts: PackedVector2Array = PackedVector2Array()
		var spike: float = 12.0
		var step: float = 26.0
		var corners: Array = [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		var normals: Array = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
		for side in range(4):
			var a: Vector2 = corners[side]
			var b: Vector2 = corners[(side + 1) % 4]
			var nrm: Vector2 = normals[side]
			var length: float = a.distance_to(b)
			var count: int = maxi(2, int(length / step))
			for i in range(count):
				var t0: float = float(i) / float(count)
				var tm: float = (float(i) + 0.5) / float(count)
				pts.append(a.lerp(b, t0))
				pts.append(a.lerp(b, tm) + nrm * spike)
		return pts


## 引き継ぎメモ: 罫線の入った紙と、上辺のマスキングテープ
class Memo extends PanelContainer:
	const LINE_GAP: float = 30.0

	func _init() -> void:
		var s: StyleBoxFlat = UI.paper_style(UI.PAPER, 18, 0, 4)
		s.content_margin_top = 26
		add_theme_stylebox_override("panel", s)

	func _draw() -> void:
		var y: float = 54.0
		while y < size.y - 12.0:
			draw_line(Vector2(14, y), Vector2(size.x - 18, y), UI.PAPER_LINE, 1.0)
			y += LINE_GAP
		# 左の赤い縦線（ノートの余白線）
		draw_line(Vector2(10, 8), Vector2(10, size.y - 10), Color(UI.SHU.r, UI.SHU.g, UI.SHU.b, 0.35), 1.0)
		# テープ
		var tape: Color = Color(UI.POP.r, UI.POP.g, UI.POP.b, 0.7)
		var w: float = 86.0
		var c: Vector2 = Vector2(size.x * 0.5, 2.0)
		var pts: PackedVector2Array = PackedVector2Array([
			c + Vector2(-w * 0.5, -6), c + Vector2(w * 0.5, -10), c + Vector2(w * 0.5 + 2, 10), c + Vector2(-w * 0.5 + 2, 14)])
		draw_colored_polygon(pts, tape)


## お客様用のレジ表示器（液晶）。怒りと納得のメーター。
class Lcd extends Control:
	var anger: float = 0.0
	var resolve: float = 0.0
	var seconds_left: float = -1.0
	var caption: String = "お客様表示"
	var _blink: float = 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(300, 196)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_values(a: float, r: float, left: float) -> void:
		anger = clampf(a, 0.0, 100.0)
		resolve = clampf(r, 0.0, 100.0)
		seconds_left = left
		queue_redraw()

	func _process(delta: float) -> void:
		if seconds_left >= 0.0 and seconds_left < 10.0:
			_blink += delta
			queue_redraw()

	func _draw() -> void:
		var dot: Font = UI.font(UI.F_DOT)
		# 本体（樹脂の枠）と液晶
		draw_rect(Rect2(Vector2(4, 4), size), UI.SHADOW)
		draw_rect(Rect2(Vector2.ZERO, size), Color("#3a3640"))
		var lcd: Rect2 = Rect2(Vector2(10, 22), size - Vector2(20, 32))
		draw_rect(lcd, UI.LCD_BG)
		draw_string(dot, Vector2(12, 16), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#b9b3c2"))
		var x0: float = lcd.position.x + 12.0
		var w: float = lcd.size.x - 24.0
		_meter(dot, Vector2(x0, lcd.position.y + 10.0), w, tr("イカリ"), anger, UI.LCD_ON if anger < 70.0 else Color("#ff8a6a"))
		_meter(dot, Vector2(x0, lcd.position.y + 74.0), w, tr("ナットク"), resolve, UI.LCD_ON)
		if seconds_left >= 0.0:
			var on: bool = seconds_left >= 10.0 or fmod(_blink, 0.6) < 0.4
			if on:
				var t: String = tr("キレるまで %02d秒") % int(ceil(seconds_left))
				draw_string(dot, Vector2(x0, lcd.end.y - 10.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UI.LCD_ON if seconds_left >= 10.0 else Color("#ff8a6a"))

	func _meter(dot: Font, pos: Vector2, w: float, label: String, v: float, on: Color) -> void:
		draw_string(dot, pos + Vector2(0, 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, on)
		draw_string(dot, pos + Vector2(w - 70.0, 22), "%3d" % int(v), HORIZONTAL_ALIGNMENT_RIGHT, 70.0, 28, on)
		var n: int = 20
		var gap: float = 3.0
		var seg: float = (w - gap * float(n - 1)) / float(n)
		var lit: int = int(round(v / 100.0 * float(n)))
		for i in range(n):
			var r: Rect2 = Rect2(pos + Vector2(float(i) * (seg + gap), 30.0), Vector2(seg, 18.0))
			draw_rect(r, on if i < lit else UI.LCD_OFF)


## レシート: 白い細長い紙。下の端がギザギザ（切り取った跡）
class Receipt extends PanelContainer:
	const COLOR: Color = Color("#fbfaf6")

	func _init() -> void:
		var s: StyleBoxEmpty = StyleBoxEmpty.new()
		s.content_margin_left = 24
		s.content_margin_right = 24
		s.content_margin_top = 22
		s.content_margin_bottom = 34
		add_theme_stylebox_override("panel", s)

	func _draw() -> void:
		var y: float = size.y - 8.0
		# 紙の影（右にずらした同じ形）と紙
		draw_rect(Rect2(Vector2(5, 5), Vector2(size.x, y)), UI.SHADOW)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, y)), COLOR)
		# 下端のギザギザ（切り取った跡）
		var step: float = 12.0
		var x: float = 0.0
		while x < size.x:
			var w: float = minf(step, size.x - x)
			draw_colored_polygon(PackedVector2Array([Vector2(x, y - 1), Vector2(x + w, y - 1), Vector2(x + w * 0.5, y + 8)]), COLOR)
			x += step


## ドットの並んだ小さなメーター（店員のメンタルなど）
class DotBar extends Control:
	var value: float = 100.0:
		set(v):
			value = clampf(v, 0.0, 100.0)
			queue_redraw()
	var color: Color = UI.LCD_ON:
		set(v):
			color = v
			queue_redraw()
	var segments: int = 10

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var gap: float = 3.0
		var w: float = (size.x - gap * float(segments - 1)) / float(segments)
		var lit: int = int(ceil(value / 100.0 * float(segments)))
		for i in range(segments):
			var r: Rect2 = Rect2(Vector2(float(i) * (w + gap), 0.0), Vector2(w, size.y))
			draw_rect(r, color if i < lit else Color(1, 1, 1, 0.15))


## 身分証の顔写真（要件#61）。お客さんの見た目（肌・髪の色と形・めがね）を2Dで描く。借り物の身分証は別人の顔になる
class IdPhoto extends Control:
	var look: Dictionary = {}:
		set(v):
			look = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(84, 104)

	func _col(key: String, fallback: Color) -> Color:
		return Color.from_string(str(look.get(key, "")), fallback)

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		draw_rect(Rect2(0, 0, w, h), Color("#cfe3f0"))
		var skin: Color = _col("skin_color", Color("#f1c9a5"))
		var hair: Color = _col("hair_color", Color("#333333"))
		var body: Color = _col("body_color", Color("#3a5a8a"))
		var cx: float = w * 0.5
		# 肩（写真の枠の中に収める。要件#86: 円が枠の外にはみ出していた）
		draw_rect(Rect2(cx - w * 0.36, h * 0.8, w * 0.72, h * 0.2), body)
		draw_circle(Vector2(cx - w * 0.26, h * 0.86), w * 0.12, body)
		draw_circle(Vector2(cx + w * 0.26, h * 0.86), w * 0.12, body)
		draw_rect(Rect2(cx - w * 0.38, h * 0.86, w * 0.76, h * 0.14), body)
		# 首と顔
		draw_rect(Rect2(cx - w * 0.08, h * 0.55, w * 0.16, h * 0.16), skin)
		var face_c: Vector2 = Vector2(cx, h * 0.45)
		var r: float = w * 0.27
		var style: String = str(look.get("hair", "short"))
		if style == "long":
			draw_rect(Rect2(cx - r * 1.15, h * 0.32, r * 2.3, h * 0.42), hair)
		draw_circle(face_c, r, skin)
		match style:
			"bald":
				pass
			"cap":
				draw_rect(Rect2(cx - r * 1.05, face_c.y - r * 1.05, r * 2.1, r * 0.75), hair.darkened(0.2))
				draw_rect(Rect2(cx - r * 0.2, face_c.y - r * 0.35, r * 1.5, r * 0.18), hair.darkened(0.35))
			"perm":
				for i in range(7):
					var a: float = PI + float(i) / 6.0 * PI
					draw_circle(face_c + Vector2(cos(a), sin(a) * 0.9) * r * 0.95, r * 0.32, hair)
			_:
				draw_circle(face_c + Vector2(0, -r * 0.35), r * 0.85, hair)
				draw_rect(Rect2(cx - r * 0.8, face_c.y - r * 0.35, r * 1.6, r * 0.28), skin)
		# 目・口
		var ink: Color = Color("#24212b")
		draw_circle(face_c + Vector2(-r * 0.38, r * 0.05), r * 0.09, ink)
		draw_circle(face_c + Vector2(r * 0.38, r * 0.05), r * 0.09, ink)
		draw_line(face_c + Vector2(-r * 0.25, r * 0.5), face_c + Vector2(r * 0.25, r * 0.5), ink, 2.0)
		if str(look.get("accessory", "")) == "glasses":
			draw_arc(face_c + Vector2(-r * 0.38, r * 0.05), r * 0.24, 0, TAU, 20, ink, 2.0)
			draw_arc(face_c + Vector2(r * 0.38, r * 0.05), r * 0.24, 0, TAU, 20, ink, 2.0)
			draw_line(face_c + Vector2(-r * 0.14, r * 0.05), face_c + Vector2(r * 0.14, r * 0.05), ink, 2.0)


## 液晶の走査線（台のサービス画面。要件#66）
class Scanlines extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var y: float = 0.0
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.22), 1.0)
			y += 3.0


## タイムカード（シフトの結果。要件#70）。厚紙の色・上のパンチ穴・時刻の欄の赤い線
class TimeCard extends PanelContainer:
	const CARD: Color = Color("#f1e8cf")
	const EDGE: Color = Color("#b9ab86")
	const RED: Color = Color("#c8463c")
	var line_end: float = 0.0:
		set(v):
			line_end = v
			queue_redraw()

	func _init() -> void:
		var st: StyleBoxFlat = StyleBoxFlat.new()
		st.bg_color = CARD
		st.border_color = EDGE
		st.set_border_width_all(2)
		st.content_margin_left = 30
		st.content_margin_right = 30
		st.content_margin_top = 42
		st.content_margin_bottom = 22
		st.shadow_color = Color(0, 0, 0, 0.35)
		st.shadow_size = 0
		st.shadow_offset = Vector2(6, 6)
		add_theme_stylebox_override("panel", st)

	func _draw() -> void:
		# 打刻機に差し込むためのパンチ穴と、上の切り欠き
		draw_circle(Vector2(size.x * 0.5, 20), 8.0, Color(0, 0, 0, 0.55))
		draw_rect(Rect2(size.x * 0.5 - 30, 0, 60, 6), Color(0, 0, 0, 0.25))
		# 時刻の欄の赤い縦線（打刻の行の範囲だけ。line_end は main が行を並べた後に入れる）
		if line_end > 0.0:
			draw_line(Vector2(30 + 78, 120), Vector2(30 + 78, line_end), Color(RED.r, RED.g, RED.b, 0.55), 1.5)



## 値札（要件#96）。ショップの「買う」ボタン。左がとがって穴のあいた、店で使う紙の値札の形。
## 中に文字だけのボタンを入れて、形はこの入れ物が描く（ボタンの既定の角丸の枠を使わない）
class PriceTag extends Container:
	var button: Button = null
	var _hover: bool = false
	const NOTCH: float = 14.0

	func _init(label: String, size: int = UI.S_SMALL) -> void:
		button = Button.new()
		button.text = label
		button.focus_mode = Control.FOCUS_ALL
		button.add_theme_font_override("font", UI.font(UI.F_BOLD))
		button.add_theme_font_size_override("font_size", size)
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			button.add_theme_color_override(k, UI.INK)
		button.add_theme_color_override("font_disabled_color", UI.INK_SOFT)
		for st in ["normal", "hover", "pressed", "disabled"]:
			button.add_theme_stylebox_override(st, UI.empty_style(0, 0))
		var f: StyleBoxFlat = StyleBoxFlat.new()
		f.draw_center = false
		f.set_border_width_all(2)
		f.border_color = UI.SHU
		f.set_expand_margin_all(2)
		button.add_theme_stylebox_override("focus", f)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.mouse_entered.connect(func() -> void:
			_hover = true
			queue_redraw())
		button.mouse_exited.connect(func() -> void:
			_hover = false
			queue_redraw())
		add_child(button)

	var disabled: bool:
		get:
			return button.disabled
		set(v):
			button.disabled = v
			queue_redraw()

	func _get_minimum_size() -> Vector2:
		return button.get_combined_minimum_size() + Vector2(NOTCH + 22.0, 10.0)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			fit_child_in_rect(button, Rect2(Vector2(NOTCH + 10.0, 5.0), size - Vector2(NOTCH + 22.0, 10.0)))

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		var pts: PackedVector2Array = PackedVector2Array([
			Vector2(NOTCH, 0), Vector2(w - 2, 0), Vector2(w - 2, h - 2), Vector2(NOTCH, h - 2), Vector2(0, (h - 2) * 0.5)])
		# ずらしただけの影 → 紙 → 線
		var sh: PackedVector2Array = PackedVector2Array()
		for p in pts:
			sh.append(p + Vector2(3, 3))
		draw_colored_polygon(sh, UI.SHADOW)
		var fill: Color = UI.PAPER.lightened(0.45)
		if button.disabled:
			fill = UI.PAPER_DIM
		elif _hover:
			fill = UI.POP.lerp(UI.PAPER, 0.35)
		draw_colored_polygon(pts, fill)
		var loop: PackedVector2Array = pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, UI.INK_SOFT if button.disabled else UI.INK, 1.5, true)
		# ひもを通す穴と、朱色の縁どり
		var hole: Vector2 = Vector2(NOTCH * 0.85, (h - 2) * 0.5)
		draw_circle(hole, 3.5, UI.PAPER_DIM.darkened(0.2))
		draw_arc(hole, 4.5, 0.0, TAU, 16, UI.INK_SOFT if button.disabled else UI.SHU, 1.2, true)


## 点線のリーダー（「勤めたシフト ………… 12」）。帳簿・日報の行に使う
class DotLeader extends Control:
	func _init() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(24, 4)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var y: float = size.y * 0.5 + 6.0
		var x: float = 4.0
		while x < size.x - 4.0:
			draw_rect(Rect2(x, y, 2, 2), UI.INK_SOFT.lerp(UI.PAPER, 0.35))
			x += 7.0


## コルクボード（対戦の掲示板の地）。乱数を固定して、毎回同じ粒の模様にする
class Cork extends Control:
	const BASE: Color = Color("#8a6a48")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), BASE)
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 4096
		var n: int = int(size.x * size.y / 900.0)
		for i in n:
			var p: Vector2 = Vector2(rng.randf() * size.x, rng.randf() * size.y)
			var dark: bool = rng.randf() < 0.55
			var c: Color = BASE.darkened(rng.randf_range(0.12, 0.3)) if dark else BASE.lightened(rng.randf_range(0.08, 0.2))
			draw_rect(Rect2(p, Vector2(rng.randi_range(2, 4), rng.randi_range(1, 3))), c)
		# 木の枠
		var frame: Color = Color("#5b3f28")
		draw_rect(Rect2(Vector2.ZERO, size), frame, false, 14.0)


## 押しピンで留めた紙。中身を1つ入れ、上の真ん中にピンを描く。tilt は傾き（度）。
## コンテナは子の傾きを 0 に戻すので、並べた後に傾けなおす
class PinnedNote extends Container:
	var tilt: float = 0.0
	var pin_color: Color = UI.SHU
	var top_gap: float = 0.0   # 紙ごとに高さをずらすための、上の余白
	const TOP: float = 10.0
	var _pin: Control = null

	func _get_minimum_size() -> Vector2:
		var m: Vector2 = Vector2.ZERO
		for c in get_children():
			if c is Control and (c as Control).visible:
				m = m.max((c as Control).get_combined_minimum_size())
		return m + Vector2(0, TOP + top_gap)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			var y: float = TOP + top_gap
			for c in get_children():
				if c is Control:
					var cc: Control = c
					var h: float = cc.get_combined_minimum_size().y
					fit_child_in_rect(cc, Rect2(Vector2(0, y), Vector2(size.x, h)))
					cc.pivot_offset = Vector2(cc.size.x * 0.5, 0)
					cc.rotation_degrees = tilt
			if _pin != null:
				_pin.position = Vector2(size.x * 0.5 - 9, top_gap)

	func _ready() -> void:
		# ピンは紙の上に描く必要があるので、最後に描かれる「後ろ側の内部の子」として足す
		var pin: _Pin = _Pin.new()
		pin.color = pin_color
		add_child(pin, false, Node.INTERNAL_MODE_BACK)
		_pin = pin
		queue_sort()


class _Pin extends Control:
	var color: Color = UI.SHU

	func _init() -> void:
		custom_minimum_size = Vector2(18, 22)
		size = Vector2(18, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_circle(Vector2(11, 13), 7.0, UI.SHADOW)
		draw_circle(Vector2(9, 11), 7.0, color)
		draw_circle(Vector2(7, 8), 2.2, color.lightened(0.45))


## マスキングテープ（シートの上の辺に貼る）。at: 横の位置（0〜1）、angle: 傾き（度）
class Tape extends Control:
	var at: float = 0.5
	var angle: float = -3.0
	var width: float = 96.0
	var color: Color = Color(UI.POP.r, UI.POP.g, UI.POP.b, 0.7)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_TOP_WIDE)

	func _draw() -> void:
		var c: Vector2 = Vector2(size.x * at, 0)
		var r: float = deg_to_rad(angle)
		var hw: Vector2 = Vector2(width * 0.5, 0).rotated(r)
		var hh: Vector2 = Vector2(0, 11).rotated(r)
		var pts: PackedVector2Array = PackedVector2Array([c - hw - hh, c + hw - hh, c + hw + hh, c - hw + hh])
		draw_colored_polygon(pts, color)
		# 切り口のギザギザ（左右の短い辺）
		for e in [-1.0, 1.0]:
			var base: Vector2 = c + hw * e
			for k in range(-2, 3):
				var p: Vector2 = base + hh * (float(k) / 2.0)
				draw_line(p, p + Vector2(2.0 * e, 0).rotated(r), color.darkened(0.15), 1.0)
