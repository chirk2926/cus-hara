extends RefCounted
## 3D の看板の文字を、うしろの板に収める（要件#91: 掲示の文字が板からはみ出していた）。
## 場面を作り終えたあとに呼ぶ。文字（Label3D）のすぐうしろにある板（BoxMesh）を探し、
## 文字の幅・高さが板の 92% を超えていたら、文字を縮める。


static func fit_all(root: Node) -> void:
	var labels: Array = []
	var boxes: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Label3D:
			labels.append(n)
		elif n is MeshInstance3D and (n as MeshInstance3D).mesh is BoxMesh:
			boxes.append(n)
	for l in labels:
		_fit(l as Label3D, boxes)


static func _fit(l: Label3D, boxes: Array) -> void:
	if not l.is_inside_tree() or l.text.strip_edges() == "":
		return
	var p: Vector3 = l.global_transform.origin
	var best: MeshInstance3D = null
	var best_area: float = INF
	for b in boxes:
		var mi: MeshInstance3D = b
		if not mi.is_inside_tree():
			continue
		# 共通の 1×1×1 の箱を scale で大きさを決めているものもあるので、実際の大きさで見る（バグチェック B-03）
		var sc: Vector3 = mi.global_transform.basis.get_scale().abs()
		var size: Vector3 = (mi.mesh as BoxMesh).size * sc
		# 薄い板だけ（看板・ポスター）。文字はその板の表のすぐ前にある
		if size.z > 0.12 or size.x < 0.15 or size.y < 0.1:
			continue
		var local: Vector3 = (mi.global_transform.affine_inverse() * p) * sc
		if absf(local.x) <= size.x * 0.5 + 0.02 and absf(local.y) <= size.y * 0.5 + 0.02 and absf(local.z) <= size.z * 0.5 + 0.08:
			var area: float = size.x * size.y
			if area < best_area:
				best_area = area
				best = mi
	if best == null:
		return
	var font: Font = l.font if l.font != null else ThemeDB.fallback_font
	var sz: Vector2 = font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, -1, l.font_size)
	var lsc: Vector3 = l.global_transform.basis.get_scale().abs()
	var w: float = (sz.x * l.pixel_size + float(l.outline_size) * l.pixel_size * 2.0) * lsc.x
	var h: float = sz.y * l.pixel_size * lsc.y
	var bsize: Vector3 = (best.mesh as BoxMesh).size * best.global_transform.basis.get_scale().abs()
	var k: float = minf(bsize.x * 0.92 / maxf(w, 0.001), bsize.y * 0.92 / maxf(h, 0.001))
	if k < 1.0:
		l.pixel_size *= k
