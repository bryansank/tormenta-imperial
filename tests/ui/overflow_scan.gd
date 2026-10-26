extends RefCounted
## Busca desbordes de la interfaz: cada Control visible (dentro de un
## CanvasLayer, no los del mundo) cuyo rectangulo se sale del lienzo, o del
## padre que lo recorta (clip_contents, o un ScrollContainer sin barra
## horizontal: lo que pasa de su ancho se corta a la derecha).
##
## Un nodo con la meta "overflow_ok" (y lo que cuelga de el) no se mira: es
## para lo que se sale a proposito, como la ilustracion del menu principal.
##
## No es una suite: la usan tests/ui/test_desbordes.gd y la sonda
## tools/desborde_probe_runner.gd.
##
##     var hits := OverflowScan.scan(get_tree().root)
##     for line in OverflowScan.report(hits): print(line)
##
## Cada hallazgo es un Dictionary: path, side ("right", "left", "bottom",
## "top"), over (px que se sale), against ("viewport" o la ruta del padre que
## recorta), rect y leaves (las hojas que se salen dentro de el: lo que lo
## empuja, normalmente una etiqueta o una fila demasiado larga).

const TOL := 1.5
## Controles mirados en el ultimo scan() (para ver que la sonda mira algo).
static var last_checked := 0

## Todo lo que se sale. `only_right` deja solo lo que se sale por la derecha.
static func scan(root: Node, only_right: bool = false) -> Array:
	var vp_rect := Rect2(Vector2.ZERO, root.get_viewport().get_visible_rect().size)
	var raw: Array = []
	last_checked = 0
	_walk(root, true, vp_rect, "viewport", false, raw)
	if only_right:
		raw = raw.filter(func(h): return h["side"] == "right")
	return _collapse(raw)

## Lineas legibles para la consola.
static func report(hits: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for h in hits:
		out.append("DESBORDE %s %+.0f px contra %s: %s %s" % [h["side"], h["over"],
			h["against"], h["path"], _r(h["rect"])])
		if String(h.get("culprit", "")) != "":
			out.append("    causa: %s" % h["culprit"])
		for leaf in h["leaves"]:
			out.append("    hoja: %s %s %s" % [leaf["path"], _r(leaf["rect"]), leaf.get("what", "")])
	return out

static func _r(r: Rect2) -> String:
	return "[x %.0f..%.0f, y %.0f..%.0f]" % [r.position.x, r.end.x, r.position.y, r.end.y]

static func _walk(n: Node, parent_visible: bool, clip: Rect2, clip_name: String,
		clip_x_only: bool, out: Array) -> void:
	if not parent_visible:
		return
	if n is Window and n != n.get_tree().root:
		return
	if n is SubViewport or n is VisualInstance3D:
		return
	# Lo que se sale a proposito (una ilustracion que cubre y se recorta).
	if n.has_meta("overflow_ok"):
		return
	if n is CanvasLayer:
		if not (n as CanvasLayer).visible:
			return
	elif n is CanvasItem:
		var ci := n as CanvasItem
		if not ci.visible or ci.modulate.a < 0.02:
			return
	var next_clip := clip
	var next_name := clip_name
	var next_x_only := clip_x_only
	if n is Control and (n as Control).get_canvas_layer_node() != null:
		var c := n as Control
		var rect := _rect(c)
		if rect.size.x > 0.5 and rect.size.y > 0.5:
			last_checked += 1
			_check(c, rect, clip, clip_name, clip_x_only, out)
		if c is ScrollContainer:
			var sc := c as ScrollContainer
			if sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
				# Lo de dentro se corta por los lados (el alto se arrastra).
				next_clip = rect
				next_name = _path(c)
				next_x_only = true
			else:
				# Barra horizontal a proposito (una tira que se arrastra): dentro
				# no hay borde que mirar.
				next_clip = Rect2(Vector2(-1e7, -1e7), Vector2(2e7, 2e7))
				next_name = _path(c)
				next_x_only = true
		elif c.clip_contents:
			next_clip = rect.intersection(clip) if not clip_x_only else rect
			next_name = _path(c)
			next_x_only = false
	for child in n.get_children():
		_walk(child, true, next_clip, next_name, next_x_only, out)

static func _rect(c: Control) -> Rect2:
	var xf := c.get_global_transform_with_canvas()
	return xf * Rect2(Vector2.ZERO, c.size)

static func _check(c: Control, r: Rect2, clip: Rect2, clip_name: String, x_only: bool, out: Array) -> void:
	var sides := {
		"right": r.end.x - clip.end.x,
		"left": clip.position.x - r.position.x,
	}
	if not x_only:
		sides["bottom"] = r.end.y - clip.end.y
		sides["top"] = clip.position.y - r.position.y
	for side in sides:
		var over: float = sides[side]
		if over > TOL:
			out.append({"node": c, "path": _path(c), "side": side, "over": over,
				"against": clip_name, "rect": r, "leaves": []})

static func _path(n: Node) -> String:
	var tree := n.get_tree()
	if tree != null and tree.current_scene != null and tree.current_scene.is_ancestor_of(n):
		return String(tree.current_scene.get_path_to(n))
	return String(n.get_path())

## Un hallazgo por cadena: el mas de fuera (su padre no se sale por el mismo
## lado contra lo mismo) con sus hojas (los de dentro que se salen y no
## tienen hijos que se salgan).
static func _collapse(raw: Array) -> Array:
	var keyed := {}
	for h in raw:
		keyed["%s|%s|%s" % [h["node"].get_instance_id(), h["side"], h["against"]]] = h
	var tops: Array = []
	for h in raw:
		var parent: Node = (h["node"] as Node).get_parent()
		var nested := false
		while parent != null:
			if keyed.has("%s|%s|%s" % [parent.get_instance_id(), h["side"], h["against"]]):
				nested = true
				break
			parent = parent.get_parent()
		if not nested:
			tops.append(h)
	for top in tops:
		var top_node: Node = top["node"]
		for h in raw:
			if h == top or h["side"] != top["side"] or h["against"] != top["against"]:
				continue
			var n: Node = h["node"]
			if not top_node.is_ancestor_of(n):
				continue
			var has_inner := false
			for other in raw:
				if other != h and other["side"] == h["side"] and n.is_ancestor_of(other["node"]):
					has_inner = true
					break
			if not has_inner and top["leaves"].size() < 4:
				top["leaves"].append({"path": h["path"], "rect": h["rect"], "what": _what(n)})
	for top in tops:
		top["what"] = _what(top["node"])
		top["culprit"] = _culprit(top["node"])
		top.erase("node")
	return tops

static func _what(n: Node) -> String:
	var t := n.get_class()
	if n is Label:
		return "%s \"%s\"" % [t, (n as Label).text.left(40)]
	if n is Button:
		return "%s \"%s\"" % [t, (n as Button).text.left(40)]
	if n is RichTextLabel:
		return "%s \"%s\"" % [t, (n as RichTextLabel).get_parsed_text().left(40)]
	return t

## Lo que fija el ancho minimo: baja por el hijo de minimo mas ancho mientras
## pida al menos el 60 % del ancho de su padre.
static func _culprit(n: Node) -> String:
	if not (n is Control):
		return ""
	var c := n as Control
	var want := c.get_combined_minimum_size().x
	var last := c
	while true:
		var best: Control = null
		var best_w := 0.0
		for ch in last.get_children():
			if ch is Control and (ch as Control).visible and not (ch as Control).top_level:
				var w := (ch as Control).get_combined_minimum_size().x
				if w > best_w:
					best_w = w
					best = ch
		if best == null or best_w < want * 0.6:
			break
		last = best
		want = best_w
	return "%s min %.0f (%s)" % [_path(last), last.get_combined_minimum_size().x, _what(last)]
