extends RefCounted
## Las cinco pantallas clave del rediseno (fase 1, docs/28-guia-ui.md) montadas
## con CartoonTheme y datos de ejemplo: HUD, CONSTRUIR, FICHA de edificio,
## MISIONES y AJUSTES. Son MAQUETAS para aprobar el estilo: no estan cableadas
## a los servicios (eso es la fase 2), pero usan los nombres, iconos, costes y
## miniaturas reales del juego.
##
## Disenadas primero para telefono pequeno (lienzo 640x360 y 800x360,
## CartoonTheme.phone) y luego escaladas a PC (1280x720).
##
## Cada build_* devuelve un Control a pantalla completa para meter en un
## CanvasLayer. `ctx`: {"vp": Vector2 (lienzo), "thumbs": {id: Texture2D}}.
## Los textos son los recortados (una frase como mucho): los definitivos iran a
## Tr.gd en la fase 2.

const CT := preload("res://scripts/ui/CartoonTheme.gd")
const Bust := preload("res://scripts/ui/InstructorBust.gd")
const Flag := preload("res://scripts/ui/ColonyFlag.gd")

const SCREENS := ["hud", "construir", "ficha", "misiones", "ajustes"]

static func _root() -> Control:
	var r := Control.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## La raiz de una pantalla, ya dentro del arbol (en ctx["host"]).
static func _attach(ctx: Dictionary) -> Control:
	var r := _root()
	(ctx["host"] as Control).add_child(r)
	return r

static func _sub(ctx: Dictionary, host: Control) -> Dictionary:
	var c := ctx.duplicate()
	c["host"] = host
	return c

static func _put(parent: Control, child: Control, pos: Vector2, size: Vector2 = Vector2.ZERO) -> Control:
	parent.add_child(child)
	child.position = pos
	child.size = size if size != Vector2.ZERO else child.get_combined_minimum_size()
	return child

static func _hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h

static func _vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v

static func _panel(style: StyleBox) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

static func _spacer(vertical: bool = false) -> Control:
	var s := Control.new()
	if vertical:
		s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

static func _center(c: Control) -> Control:
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c

static func _name(id: String) -> String:
	var d: BuildingData = load("res://data/buildings/%s.tres" % id)
	return d.get_display_name() if d != null else id

static func _thumb(ctx: Dictionary, id: String, px: Vector2) -> PanelContainer:
	var p := _panel(CT.well_style("window", 12, 3))
	var t := TextureRect.new()
	t.texture = (ctx.get("thumbs", {}) as Dictionary).get(id, null)
	t.custom_minimum_size = px
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(t)
	return p

static func _scroll(child: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(child)
	return sc

## Ventana: en telefono a pantalla completa; en PC centrada con un tope.
static func _window(root: Control, ctx: Dictionary, title: String, fill: Color, max_size: Vector2) -> Dictionary:
	var vp: Vector2 = ctx["vp"]
	var margin := Vector2(6, 2) if CT.phone else Vector2(24, 16)
	var sz := Vector2(minf(max_size.x, vp.x - margin.x * 2.0), minf(max_size.y, vp.y - margin.y * 2.0))
	if CT.phone:
		sz = vp - margin * 2.0
	var w := CT.window(title, fill)
	_put(root, w["root"], (vp - sz) * 0.5, sz)
	var body: VBoxContainer = w["body"]
	body.add_theme_constant_override("separation", 6 if CT.phone else CT.GAP)
	if CT.phone:
		(w["panel"] as PanelContainer).add_theme_stylebox_override("panel", _phone_window_style())
	return w

static func _phone_window_style() -> StyleBoxFlat:
	var s := CT.window_style()
	s.set_content_margin_all(10)
	return s

# ══════════════════════════════════════════════════════════════════════
# 1. HUD
# ══════════════════════════════════════════════════════════════════════
# Minimo: recursos (3-4 en telefono), rango y menu, la Tormenta en un icono,
# la columna de avisos (2 como mucho) y la barra de abajo. El siguiente paso
# (¿QUE HACER?) es UNA linea plegable con la cara de la Capitana.
# Todo va anclado a una esquina y crece hacia dentro: el tamano lo decide el
# contenido, que solo se sabe dentro del arbol.

## Ancla `child` a una esquina de `parent` (o al centro de abajo) con margen.
static func _dock(parent: Control, child: Control, corner: String, off: Vector2) -> Control:
	parent.add_child(child)
	var ax: float = {"tl": 0.0, "tr": 1.0, "bl": 0.0, "br": 1.0, "bc": 0.5}[corner]
	var ay: float = {"tl": 0.0, "tr": 0.0, "bl": 1.0, "br": 1.0, "bc": 1.0}[corner]
	child.anchor_left = ax
	child.anchor_right = ax
	child.anchor_top = ay
	child.anchor_bottom = ay
	var ox := off.x if ax == 0.0 else (-off.x if ax == 1.0 else 0.0)
	var oy := off.y if ay == 0.0 else -off.y
	child.offset_left = ox
	child.offset_right = ox
	child.offset_top = oy
	child.offset_bottom = oy
	child.grow_horizontal = Control.GROW_DIRECTION_END if ax == 0.0 else (
		Control.GROW_DIRECTION_BEGIN if ax == 1.0 else Control.GROW_DIRECTION_BOTH)
	child.grow_vertical = Control.GROW_DIRECTION_END if ay == 0.0 else Control.GROW_DIRECTION_BEGIN
	return child

## `parts`: "full" (todo), "bare" (solo recursos, rango y menu: con un panel
## lateral abierto), "under" (bajo una ventana: sin avisos ni siguiente paso).
static func build_hud(ctx: Dictionary, parts: String = "full") -> Control:
	var vp: Vector2 = ctx["vp"]
	var ph := CT.phone
	var root := _root()
	var host: Control = ctx.get("host", null)
	if host != null:
		host.add_child(root)
	var edge := 8.0 if ph else 14.0

	# ── Arriba a la izquierda: recursos y, debajo, la columna de avisos ──
	var tl := _vbox(6)
	var res_card := _panel(CT.hud_style())
	(res_card.get_theme_stylebox("panel") as StyleBoxFlat).set_content_margin_all(6 if ph else 8)
	res_card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var res_col := _vbox(3)
	var chips := _hbox(10 if ph else 16)
	var data := [["res:gold", "1.240", "Oro"], ["res:wood", "860", "Madera"], ["res:steel", "320", "Acero"]]
	if not ph:
		data.append(["res:oil", "90", "Petróleo"])
	if not ph or vp.x >= 780:
		data.append(["res:food", "140", "Comida"])
	for d in data:
		chips.add_child(CT.stat_chip(d[0], d[1], d[2], "hud"))
	var sep := Panel.new()
	sep.custom_minimum_size = Vector2(2, 26 if ph else 40)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sep.add_theme_stylebox_override("panel", CT.box(CT.c("hud", "CARD_BORDER"), Color(0, 0, 0, 0), 0, 1, 0))
	chips.add_child(sep)
	chips.add_child(CT.stat_chip("res:workers", "4", "Libres", "hud"))
	if not ph:
		chips.add_child(CT.stat_chip("res:morale", "72", "Moral", "hud", CT.sem("POSITIVE").lightened(0.3)))
	res_col.add_child(chips)
	if not ph:
		var bar := CT.progress(0.82, CT.sem("ACCENT"), "hud", 8)
		bar.tooltip_text = "Almacén: 2.650 de 3.200"
		res_col.add_child(bar)
	res_card.add_child(res_col)
	res_card.tooltip_text = "Toca para ver todos los recursos."
	tl.add_child(res_card)
	if parts == "full":
		for n in [CT.notice("Aserradero listo", "check", "positive"),
				CT.notice("Falta comida", "res:food", "warning", 3)]:
			n.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			tl.add_child(n)
	_dock(root, tl, "tl", Vector2(edge, edge))

	# ── Arriba a la derecha: rango y ☰; debajo, la Tormenta (solo icono) ──
	var tr := _vbox(8)
	var top_row := _hbox(8)
	var md := 48 if ph else 54
	var rank := _panel(CT.hud_style())
	(rank.get_theme_stylebox("panel") as StyleBoxFlat).set_content_margin_all(5 if ph else 7)
	var rrow := _hbox(6)
	var flag := TextureRect.new()
	flag.texture = Flag.texture({"pattern": "bands_v"}, 96, 64)
	flag.custom_minimum_size = Vector2(33, 22) if ph else Vector2(45, 30)
	flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rrow.add_child(_center(flag))
	var rcol := _vbox(2)
	var rtitle := _hbox(4)
	rtitle.add_child(_center(CT.make_glyph("star", 20 if ph else 24)))
	rtitle.add_child(CT.label("4" if ph else "4 · Capataz", "button", CT.text("hud")))
	rcol.add_child(rtitle)
	var xp := CT.progress(0.55, CT.sem("INFO"), "hud", 8)
	xp.custom_minimum_size.x = 40 if ph else 120
	rcol.add_child(xp)
	rrow.add_child(_center(rcol))
	rank.add_child(rrow)
	rank.tooltip_text = "Rango 4 · Capataz"
	top_row.add_child(rank)
	top_row.add_child(CT.round_button("menu", "secondary", md, "", "hud"))
	tr.add_child(top_row)
	if parts != "bare":
		var sd := 44 if ph else 50
		var storm := _panel(CT.box(Color(CT.c("hud", "BG"), 0.9), CT.c("hud", "CARD_BORDER"), 2, int(sd * 0.5), 0))
		storm.custom_minimum_size = Vector2(sd, sd)
		storm.size_flags_horizontal = Control.SIZE_SHRINK_END
		var scc := CenterContainer.new()
		scc.add_child(CT.make_glyph("sun", int(sd * 0.62)))
		storm.add_child(scc)
		storm.tooltip_text = "Calma: la Tormenta está lejos."
		var holder := _hbox(0)
		holder.alignment = BoxContainer.ALIGNMENT_END
		holder.add_child(storm)
		var pad := Control.new()
		pad.custom_minimum_size.x = (md - sd) * 0.5
		holder.add_child(pad)
		tr.add_child(holder)
	_dock(root, tr, "tr", Vector2(edge, edge))

	if parts == "bare":
		return root

	# ── Abajo: CONSTRUIR en el centro, redondos a los lados ──
	var d := 48 if ph else 64
	var bh := 52 if ph else 70
	var bar_row := _hbox(8 if ph else 18)
	var captions := not ph
	var items := [["army", "Ejército"], ["missions", "Misiones"], ["BUILD", ""],
		["market", "Mercado"], ["research", "Investigar"], ["help", "Ayuda"]]
	for it in items:
		var c: Control
		if it[0] == "BUILD":
			c = CT.pill_button("CONSTRUIR", "build", "primary", bh, "hud", "button" if ph else "display")
		else:
			c = CT.round_button(it[0], "open", d, it[1] if captions else "", "hud")
			if not captions:
				c.tooltip_text = it[1]
			if captions:
				c.custom_minimum_size.x = d + 14
			if it[0] == "missions":
				var btn: Button = c.get_meta("button") if c.has_meta("button") else c
				var dot := _panel(CT.box(CT.sem("DANGER"), CT.INK, 2, 10, 0))
				btn.add_child(dot)
				dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
				dot.offset_left = -16
				dot.offset_right = 4
				dot.offset_top = -4
				dot.offset_bottom = 16
		c.size_flags_vertical = Control.SIZE_SHRINK_END
		bar_row.add_child(c)
	_dock(root, bar_row, "bc", Vector2(0, edge))

	if parts == "under":
		return root

	# ── Siguiente paso: una linea plegable con la cara de la Capitana ──
	var coach := _panel(CT.hud_style(CT.sem("ACCENT")))
	var cst := coach.get_theme_stylebox("panel") as StyleBoxFlat
	cst.set_content_margin_all(3)
	cst.content_margin_right = 12
	cst.set_corner_radius_all(30)
	var crow := _hbox(6)
	var face := Face.new()
	face.custom_minimum_size = Vector2(40, 40) if ph else Vector2(50, 50)
	face.clip_contents = true
	crow.add_child(face)
	crow.add_child(_center(CT.label("Haz una Casa", "button", CT.text("hud"))))
	crow.add_child(_center(CT.make_glyph("next", 18, CT.sem("ACCENT"))))
	coach.add_child(crow)
	coach.tooltip_text = "Tu siguiente paso. Tócalo para verlo en el mapa."
	_dock(root, coach, "bl", Vector2(edge, edge + (bh + 10.0 if ph else 0.0)))
	return root

# ══════════════════════════════════════════════════════════════════════
# 2. CONSTRUIR
# ══════════════════════════════════════════════════════════════════════

const BUILD_LIST := [
	# id, costes, bloqueo ("" = se puede)
	["sawmill", {"gold": 80, "wood": 50}, ""],
	["gold_mine", {"gold": 120, "wood": 80}, ""],
	["farm", {"gold": 60, "wood": 40}, ""],
	["fishing_dock", {"gold": 70, "wood": 60}, ""],
	["house", {"gold": 50, "wood": 30}, ""],
	["warehouse", {"gold": 60, "wood": 40}, ""],
	["foundry", {"gold": 200, "wood": 120}, "Falta Almacén"],
	["refinery", {"gold": 300, "steel": 150}, "Era 3"],
]
const BUILD_TABS := [["Producir", "res:wood"], ["Casas", "res:workers"], ["Ejército", "army"], ["Adornos", "star"]]

static func _cost_row(entry: Array, id: String) -> HBoxContainer:
	var costs := _hbox(4)
	var locked: String = entry[2]
	if locked != "":
		costs.add_child(_center(CT.make_glyph("lock", 20)))
		costs.add_child(_center(CT.label(locked, "small", CT.text("window", true))))
		return costs
	for res in entry[1]:
		costs.add_child(CT.cost_chip(res, int(entry[1][res]), not (id == "gold_mine" and res == "gold")))
	return costs

static func build_construction(ctx: Dictionary) -> Control:
	var root := _attach(ctx)
	build_hud(_sub(ctx, root), "under")
	root.add_child(CT.veil())
	var w := _window(root, ctx, "CONSTRUIR", CT.sem("POSITIVE"), Vector2(1180, 650))
	var body: VBoxContainer = w["body"]
	var tip_anchor: Control = null

	if CT.phone:
		# Telefono: carril de pestanas solo icono + UNA columna de filas. Cada
		# fila construye directamente; el detalle, al mantener pulsado.
		var main := _hbox(8)
		main.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(main)
		var rail := _vbox(6)
		for i in BUILD_TABS.size():
			var t := CT.tab("", BUILD_TABS[i][1], i == 0, "window", Color(0, 0, 0, 0), 48)
			t.custom_minimum_size = Vector2(52, 48)
			t.tooltip_text = BUILD_TABS[i][0]
			rail.add_child(t)
		main.add_child(rail)
		var list := _vbox(6)
		for entry in BUILD_LIST:
			var id: String = entry[0]
			var locked := String(entry[2]) != ""
			var card := _panel(CT.card_style("window", id == "sawmill",
				CT.c("window", "CARD_ALT") if locked else Color(0, 0, 0, 0)))
			(card.get_theme_stylebox("panel") as StyleBoxFlat).set_content_margin_all(3)
			# Una fila de una linea: [miniatura] Nombre ... coste [martillo].
			var row := _hbox(8)
			var th := _thumb(ctx, id, Vector2(52, 40))
			if locked:
				th.modulate = Color(1, 1, 1, 0.45)
			row.add_child(th)
			var nm := CT.label(_name(id), "button", CT.text("window", locked))
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nm.clip_text = true
			row.add_child(nm)
			var cr := _cost_row(entry, id)
			row.add_child(_center(cr))
			if id == "sawmill":
				tip_anchor = cr.get_child(1)
			if not locked:
				row.add_child(_center(CT.pill_button("", "build", "primary", 48)))
			card.add_child(row)
			card.tooltip_text = "Mantén pulsado para ver qué hace."
			list.add_child(card)
		main.add_child(_scroll(list))
	else:
		var tabs := _hbox(8)
		for i in BUILD_TABS.size():
			tabs.add_child(CT.tab(BUILD_TABS[i][0], BUILD_TABS[i][1], i == 0))
		body.add_child(tabs)
		var main := _hbox(CT.GAP + 4)
		main.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_child(main)
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		for entry in BUILD_LIST:
			var id: String = entry[0]
			var locked := String(entry[2]) != ""
			var card := _panel(CT.card_style("window", id == "sawmill",
				CT.c("window", "CARD_ALT") if locked else Color(0, 0, 0, 0)))
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var col := _vbox(4)
			var th := _thumb(ctx, id, Vector2(0, 84))
			if locked:
				th.modulate = Color(1, 1, 1, 0.45)
			col.add_child(th)
			var nm := CT.label(_name(id), "button", CT.text("window", locked))
			nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			nm.clip_text = true
			col.add_child(nm)
			var cr := _cost_row(entry, id)
			cr.alignment = BoxContainer.ALIGNMENT_CENTER
			col.add_child(cr)
			if id == "sawmill":
				tip_anchor = cr.get_child(1)
			card.add_child(col)
			grid.add_child(card)
		main.add_child(_scroll(grid))
		# Detalle del elegido: miniatura, una frase, cifras, coste y CONSTRUIR.
		var det := _panel(CT.card_style("window"))
		det.custom_minimum_size.x = 330
		var dcol := _vbox(10)
		dcol.add_child(_thumb(ctx, "sawmill", Vector2(0, 150)))
		dcol.add_child(CT.label(_name("sawmill"), "title", CT.text("window")))
		dcol.add_child(CT.para("Corta madera del bosque de al lado.", "window", true))
		var stats := _hbox(18)
		stats.add_child(CT.stat_chip("res:wood", "+6", "cada 12 s", "window"))
		stats.add_child(CT.stat_chip("res:workers", "2", "trabajan", "window"))
		dcol.add_child(stats)
		dcol.add_child(_spacer(true))
		var cost := _hbox(6)
		cost.add_child(CT.cost_chip("gold", 80))
		cost.add_child(CT.cost_chip("wood", 50))
		dcol.add_child(cost)
		var go := CT.pill_button("CONSTRUIR", "build", "primary", CT.h("big"))
		go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dcol.add_child(go)
		det.add_child(dcol)
		main.add_child(det)

	if tip_anchor != null:
		root.set_meta("tip_anchor", tip_anchor)
		root.set_meta("tip_text", "Madera: la usan casi todos los edificios.")
	return root

## Se llama cuando la pantalla ya tiene tamano: el globo de "mantener pulsado"
## sobre su ancla, con su piquito.
static func place_tooltip(root: Control) -> void:
	if not root.has_meta("tip_anchor"):
		return
	var a: Control = root.get_meta("tip_anchor")
	var bubble := CT.tooltip_bubble(String(root.get_meta("tip_text")), 190 if CT.phone else 230)
	root.add_child(bubble)
	var bs := bubble.get_combined_minimum_size()
	var r := a.get_global_rect()
	var vp := root.get_viewport_rect().size
	bubble.size = bs
	bubble.position = Vector2(clampf(r.position.x + r.size.x * 0.5 - 30, 4, vp.x - bs.x - 4), r.end.y + 9)
	var beak := Panel.new()
	beak.add_theme_stylebox_override("panel", CT.box(Color("2e2218"), CT.sem("ACCENT"), 2, 2, 0))
	beak.size = Vector2(14, 14)
	beak.pivot_offset = Vector2(7, 7)
	beak.rotation = PI / 4.0
	beak.position = Vector2(r.position.x + r.size.x * 0.5 - 7, r.end.y + 3)
	root.add_child(beak)
	root.move_child(beak, bubble.get_index())

# ══════════════════════════════════════════════════════════════════════
# 3. FICHA DE EDIFICIO (panel lateral: el edificio sigue a la vista)
# ══════════════════════════════════════════════════════════════════════

static func build_building_sheet(ctx: Dictionary) -> Control:
	var vp: Vector2 = ctx["vp"]
	var ph := CT.phone
	var root := _attach(ctx)
	build_hud(_sub(ctx, root), "bare")
	var edge := 6.0 if ph else 14.0
	var width := minf(330.0, vp.x * 0.52) if ph else 440.0
	var top := 4.0 if ph else 84.0
	var bottom_reserve := 4.0 if ph else 100.0
	var w := CT.window(_name("sawmill"), CT.sem("ACCENT"))
	_put(root, w["root"], Vector2(vp.x - edge - width, top), Vector2(width, vp.y - top - bottom_reserve))
	if ph:
		(w["panel"] as PanelContainer).add_theme_stylebox_override("panel", _phone_window_style())
	var body: VBoxContainer = w["body"]
	body.add_theme_constant_override("separation", 6 if ph else CT.GAP)

	var inner := _vbox(6 if ph else CT.GAP)
	var head := _hbox(10)
	head.add_child(_thumb(ctx, "sawmill", Vector2(74, 54) if ph else Vector2(120, 96)))
	var hcol := _vbox(4)
	var stars := _hbox(1)
	for i in 3:
		stars.add_child(CT.make_glyph("star", 20 if ph else 26, Color(0, 0, 0, 0) if i < 2 else Color(0.75, 0.7, 0.62)))
	stars.tooltip_text = "Nivel 2 de 3"
	hcol.add_child(stars)
	hcol.add_child(CT.badge("Trabajando", CT.sem("POSITIVE"), "check"))
	(hcol.get_child(1) as Control).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var bar := CT.progress(0.7, CT.sem("POSITIVE"), "window", 10 if ph else 14)
	bar.tooltip_text = "Salud 70 %"
	hcol.add_child(bar)
	hcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hcol)
	inner.add_child(head)

	var stats := _hbox(18)
	stats.add_child(CT.stat_chip("res:wood", "+6", "cada 12 s", "window"))
	stats.add_child(CT.stat_chip("res:workers", "2/2", "trabajan", "window"))
	inner.add_child(stats)

	# El proceso del taller: entra -> sale, y un boton.
	var proc := _panel(CT.card_style("window"))
	(proc.get_theme_stylebox("panel") as StyleBoxFlat).set_content_margin_all(6 if ph else 10)
	var prow := _hbox(6)
	prow.add_child(_center(CT.cost_chip("wood", 20)))
	prow.add_child(_center(CT.make_glyph("next", 18, CT.c("window", "TEXT_DIM"))))
	prow.add_child(_center(CT.label("5 tablones", "button", CT.text("window"))))
	prow.add_child(_spacer())
	prow.add_child(CT.pill_button("HACER", "", "primary", CT.h("small"), "window", "button"))
	proc.add_child(prow)
	inner.add_child(proc)
	body.add_child(_scroll(inner))

	# Mejorar: la accion principal, con su coste al lado.
	var up := _hbox(6)
	up.add_child(CT.pill_button("MEJORAR", "upgrade", "primary", CT.h("btn")))
	up.add_child(_center(CT.cost_chip("gold", 130)))
	up.add_child(_center(CT.cost_chip("wood", 80)))
	body.add_child(up)
	# Reparar (ambar), mover y derribar (rojo, solo icono: el nombre al mantener).
	var row := _hbox(6)
	if ph:
		for b in [["wrench", "warn", "Reparar"], ["move", "secondary", "Mover"], ["workers_off", "secondary", "Retirar"]]:
			var ib := CT.pill_button("", b[0], b[1], 48)
			ib.tooltip_text = b[2]
			row.add_child(ib)
	else:
		row.add_child(CT.pill_button("REPARAR", "wrench", "warn", CT.h("small")))
		row.add_child(CT.pill_button("MOVER", "move", "secondary", CT.h("small")))
	row.add_child(_spacer())
	var demolish := CT.pill_button("", "demolish", "danger", CT.h("small"))
	demolish.tooltip_text = "Derribar"
	row.add_child(demolish)
	body.add_child(row)
	return root

# ══════════════════════════════════════════════════════════════════════
# 4. MISIONES
# ══════════════════════════════════════════════════════════════════════

static func _unit_disc(unit_id: String, fill: Color, d: int, count: int = -1) -> Control:
	var p := _panel(CT.box(fill, CT.INK, 3, int(d * 0.5), 3))
	p.custom_minimum_size = Vector2(d, d)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(CT.make_glyph("unit:" + unit_id, int(d * 0.66)))
	p.add_child(cc)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if count < 0:
		return p
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(d + 10, d + 4)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(p)
	p.size = Vector2(d, d)
	var n := _panel(CT.box(CT.WHITE, CT.INK, 2, 10, 0))
	var nl := CT.label("x%d" % count, "small", CT.INK)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_child(nl)
	holder.add_child(n)
	n.size = n.get_combined_minimum_size() + Vector2(8, 0)
	n.position = Vector2(d + 10 - n.size.x, d + 4 - n.size.y)
	return holder

static func _track(ph: bool) -> HBoxContainer:
	var track := _hbox(0)
	track.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in 6:
		var state := "done" if i < 2 else ("now" if i == 2 else ("boss" if i == 5 else "next"))
		var dd := 46 if state in ["now", "boss"] else 36
		if ph:
			dd = 34 if state in ["now", "boss"] else 26
		var fill: Color = CT.sem("POSITIVE") if state == "done" else (CT.sem("ACCENT") if state == "now"
			else (CT.sem("DANGER") if state == "boss" else CT.c("window", "WELL")))
		var node := _panel(CT.box(fill, CT.INK, 3, int(dd * 0.5), 0))
		node.custom_minimum_size = Vector2(dd, dd)
		node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var cc := CenterContainer.new()
		var g: String = {"done": "check", "now": "star", "boss": "demolish"}.get(state, "")
		if g != "":
			cc.add_child(CT.make_glyph(g, int(dd * 0.6), CT.WHITE if state == "done" else Color(0, 0, 0, 0)))
		else:
			cc.add_child(CT.label(str(i + 1), "small", CT.text("window", true)))
		node.add_child(cc)
		if state == "boss":
			node.tooltip_text = "Jefe: el Coronel de Hierro"
		track.add_child(node)
		if i < 5:
			var line := Panel.new()
			line.custom_minimum_size = Vector2(16 if ph else 34, 7)
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_theme_stylebox_override("panel", CT.box(CT.sem("POSITIVE") if i < 2 else CT.c("window", "WELL"), CT.INK, 2, 3, 0))
			track.add_child(line)
	return track

static func build_missions(ctx: Dictionary) -> Control:
	var ph := CT.phone
	var root := _attach(ctx)
	build_hud(_sub(ctx, root), "under")
	root.add_child(CT.veil())
	var w := _window(root, ctx, "MISIONES", CT.sem("DANGER"), Vector2(1080, 500))
	var body: VBoxContainer = w["body"]

	# Pestanas: la elegida con icono y palabra; en telefono, las demas solo icono.
	var tabs := _hbox(6)
	var defs := [["Tierra", "tank", ""], ["Mar", "anchor", ""], ["Aire", "lock", "Construye un Aeródromo."],
		["Ataques rápidos", "raid", ""]]
	for i in defs.size():
		var sel := i == 0
		var t := CT.tab(defs[i][0] if (sel or not ph) else "", defs[i][1], sel, "window",
			CT.sem("POSITIVE") if sel else Color(0, 0, 0, 0), 48 if ph else CT.BTN)
		if ph and not sel:
			t.custom_minimum_size.x = 56
		t.tooltip_text = defs[i][2] if defs[i][2] != "" else defs[i][0]
		tabs.add_child(t)
	if ph:
		tabs.add_child(_spacer())
		tabs.add_child(_center(CT.label("3 de 6", "button", CT.text("window", true))))
	body.add_child(tabs)

	# La mision de ahora: el recorrido de la campana arriba, enemigos y botin.
	var now := _panel(CT.card_style("window", true))
	(now.get_theme_stylebox("panel") as StyleBoxFlat).set_content_margin_all(8 if ph else 14)
	now.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ncol := _vbox(6 if ph else 10)
	if not ph:
		var thead := _hbox(8)
		thead.add_child(CT.label("Campaña de Tierra", "small", CT.text("window", true)))
		thead.add_child(_spacer())
		thead.add_child(CT.label("3 de 6", "small", CT.text("window", true)))
		ncol.add_child(thead)
	ncol.add_child(_track(ph))
	var nhead := _hbox(8)
	nhead.add_child(_center(CT.label("Misión 3 · El vado", "title", CT.text("window"))))
	nhead.add_child(_spacer())
	nhead.add_child(_center(CT.badge("Favorable", CT.sem("POSITIVE"))))
	ncol.add_child(nhead)
	var enemy := _hbox(6)
	var ud := 36 if ph else 50
	enemy.add_child(_unit_disc("infantry", CT.sem("DANGER"), ud, 3))
	enemy.add_child(_unit_disc("artillery", CT.sem("DANGER"), ud, 1))
	enemy.add_child(_spacer())
	enemy.add_child(_center(CT.cost_chip("gold", 120)))
	enemy.add_child(_center(CT.cost_chip("steel", 40)))
	enemy.get_child(3).tooltip_text = "Botín si ganas"
	ncol.add_child(enemy)
	now.add_child(ncol)

	# Tu tropa: [silueta] nombre  - n +
	var troop := _panel(CT.card_style("window"))
	(troop.get_theme_stylebox("panel") as StyleBoxFlat).set_content_margin_all(6 if ph else 12)
	var rcol := _vbox(2 if ph else 8)
	if not ph:
		rcol.add_child(CT.label("Tu tropa", "title", CT.text("window")))
	var units := [["infantry", "Soldado", 3, 6, ""], ["artillery", "Cañón", 1, 2, ""], ["vehicle", "Tanque", 0, 0, "Era 3"]]
	for u in units:
		var row := _hbox(8)
		row.add_child(_unit_disc(u[0], CT.sem("POSITIVE") if u[4] == "" else CT.kind_fill("disabled"), 38 if ph else 46))
		var ucol := _vbox(-4)
		ucol.add_child(CT.label(u[1], "button", CT.text("window", u[4] != "")))
		ucol.add_child(CT.label(u[4] if u[4] != "" else "en casa: %d" % u[3], "small", CT.text("window", true)))
		ucol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_center(ucol))
		if u[4] == "":
			row.add_child(CT.pill_button("", "minus", "secondary", 48 if ph else 44))
			var n := CT.label(str(u[2]), "number", CT.text("window"))
			n.custom_minimum_size.x = 24
			n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row.add_child(_center(n))
			row.add_child(CT.pill_button("", "plus", "open", 48 if ph else 44))
		rcol.add_child(row)
	troop.add_child(rcol)

	var go := CT.pill_button("¡AL ATAQUE!", "missions", "primary", CT.h("big"))
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var morale := _hbox(6)
	morale.add_child(_center(CT.make_glyph("res:morale", 24)))
	morale.add_child(_center(CT.label("72", "number", CT.text("window"))))
	morale.tooltip_text = "Moral de la tropa: buena."

	# Apaisado siempre (docs/28 §4): mision y tropa lado a lado, el boton abajo.
	var main := _hbox(8 if ph else CT.GAP + 4)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(now)
	troop.custom_minimum_size.x = 290 if ph else 380
	main.add_child(troop)
	body.add_child(main)
	var foot := _hbox(10)
	foot.add_child(morale)
	foot.add_child(go)
	body.add_child(foot)
	return root

# ══════════════════════════════════════════════════════════════════════
# 5. AJUSTES
# ══════════════════════════════════════════════════════════════════════

static func _setting_row(glyph: String, text_s: String, control: Control, value: String = "") -> PanelContainer:
	var card := _panel(CT.card_style("window"))
	(card.get_theme_stylebox("panel") as StyleBoxFlat).set_content_margin_all(3 if CT.phone else 10)
	var row := _hbox(10)
	row.add_child(_center(CT.make_glyph(glyph, 28 if CT.phone else 34, CT.sem("INFO"))))
	var l := CT.label(text_s, "button", CT.text("window"))
	l.custom_minimum_size.x = 92 if CT.phone else 170
	row.add_child(_center(l))
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if control is HSlider:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		row.add_child(_spacer())
	row.add_child(control)
	if value != "":
		var v := CT.label(value, "number", CT.text("window"))
		v.custom_minimum_size.x = 34 if CT.phone else 46
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(_center(v))
	card.add_child(row)
	return card

static func build_settings(ctx: Dictionary) -> Control:
	var ph := CT.phone
	var root := _attach(ctx)
	build_hud(_sub(ctx, root), "under")
	root.add_child(CT.veil())
	var w := _window(root, ctx, "AJUSTES", CT.sem("INFO"), Vector2(980, 470))
	var body: VBoxContainer = w["body"]
	var main := _hbox(10 if ph else CT.GAP + 6)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(main)

	var tabs := _vbox(6 if ph else 8)
	tabs.custom_minimum_size.x = 56 if ph else 240
	var names := [["sound", "Sonido"], ["screen", "Pantalla"], ["controls", "Controles"], ["access", "Accesibilidad"], ["game", "Partida"]]
	for i in names.size():
		var t := CT.tab("" if ph else names[i][1], names[i][0], i == 0, "window", CT.sem("INFO"), 48 if ph else CT.BTN)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.tooltip_text = names[i][1]
		tabs.add_child(t)
	main.add_child(tabs)

	var col := _vbox(6 if ph else 10)
	col.add_child(_setting_row("sound", "General", CT.slider(0.8), "80"))
	col.add_child(_setting_row("music", "Música", CT.switch(true)))
	col.add_child(_setting_row("music", "Volumen" if ph else "Volumen de música", CT.slider(0.35), "35"))
	col.add_child(_setting_row("sound", "Efectos", CT.slider(0.6), "60"))
	col.add_child(_setting_row("game", "Idioma", CT.segmented(["ES", "EN"] if ph else ["Español", "English"], 0, "window", 48 if ph else CT.BTN_SMALL)))
	main.add_child(_scroll(col))
	return root

static func build(screen: String, ctx: Dictionary) -> Control:
	match screen:
		"hud":
			return build_hud(ctx)
		"construir":
			return build_construction(ctx)
		"ficha":
			return build_building_sheet(ctx)
		"misiones":
			return build_missions(ctx)
		"ajustes":
			return build_settings(ctx)
	return _root()


## La cara de la Capitana en un medallon (la linea del siguiente paso): el
## mismo dibujo de InstructorBust, encuadrado en la cabeza.
class Face extends Control:
	func _draw() -> void:
		var sz := size.y
		draw_circle(size * 0.5, sz * 0.5, Color("f7e7c4"))
		var h := sz * 2.15
		var w := h * 0.8
		load("res://scripts/ui/InstructorBust.gd")._draw_ada(self, Rect2(Vector2(size.x * 0.5 - w * 0.5, -0.1 * h), Vector2(w, h)), "happy")
		draw_arc(size * 0.5, sz * 0.5 - 1.5, 0.0, TAU, 40, CartoonTheme.sem("ACCENT"), 3.0, true)
