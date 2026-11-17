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
