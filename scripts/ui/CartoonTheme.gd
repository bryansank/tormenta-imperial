class_name CartoonTheme
## Estilo "maqueta" de la interfaz (rediseno 2026-10, docs/28-guia-ui.md):
## caricatura limpia, paneles redondeados con borde grueso y sombra suave,
## colores vivos, botones pastilla con icono + 1-2 palabras y letra redonda.
##
## Es una VARIANTE de UITheme, no un tema aparte: `UITheme.use_style("cartoon")`
## la activa (y reescribe los tokens de siempre para que los paneles viejos la
## sigan a grandes rasgos); `UITheme.use_style("classic")` vuelve a la de serie.
## Las pantallas nuevas piden sus piezas aqui (pill_button, window, chip...).
##
## Tres decisiones abiertas, seleccionables para las maquetas:
##   * `combo`: la pareja de fuentes (COMBOS).
##   * `surface`: el fondo de los paneles (SURFACES): claro, oscuro o mixto
##     (HUD oscuro fino + ventanas grandes claras).
##   * la paleta de daltonismo y el alto contraste, que vienen de UITheme.
##
## Sin animaciones (decision de Bryan): todo aparece al instante; los estados
## (encima, pulsado) cambian el estilo, nunca con un Tween.

# ══════════════════════════════════════
# FUENTES
# ══════════════════════════════════════

## Tres parejas, todas OFL (assets/fonts/<familia>/OFL.txt). `wght` es el peso
## del eje variable (0 = la fuente no es variable).
const COMBOS := {
	"lilita_nunito": {
		"name": "Lilita One + Nunito",
		"title": "res://assets/fonts/lilita_one/LilitaOne-Regular.ttf", "title_wght": 0,
		"body": "res://assets/fonts/nunito/Nunito-Variable.ttf", "body_wght": 700, "bold_wght": 900,
	},
	"baloo_nunitosans": {
		"name": "Baloo 2 + Nunito Sans",
		"title": "res://assets/fonts/baloo_2/Baloo2-Variable.ttf", "title_wght": 800,
		"body": "res://assets/fonts/nunito_sans/NunitoSans-Variable.ttf", "body_wght": 650, "bold_wght": 850,
	},
	"fredoka_inter": {
		"name": "Fredoka + Inter",
		"title": "res://assets/fonts/fredoka/Fredoka-Variable.ttf", "title_wght": 600,
		"body": "res://assets/fonts/inter/Inter-Variable.ttf", "body_wght": 550, "bold_wght": 750,
	},
}
const Icon := preload("res://scripts/ui/CartoonIcon.gd")
const COMBO_ORDER := ["lilita_nunito", "baloo_nunitosans", "fredoka_inter"]
## La elegida por Bryan (2026-10-18, docs/28 §3).
const DEFAULT_COMBO := "baloo_nunitosans"

## Fondos de panel en estudio: claro (crema), oscuro (pizarra con borde de
## color) y mixto (HUD oscuro fino, ventanas claras).
const SURFACES := ["light", "dark", "mixed"]

static var combo := DEFAULT_COMBO
## Elegido por Bryan (2026-10-18): mixto.
static var surface := "mixed"

static var _font_cache := {}

static func _variation(path: String, wght: int) -> Font:
	var key := "%s|%d" % [path, wght]
	if _font_cache.has(key):
		return _font_cache[key]
	var base: FontFile = UITheme._load_font(path)
	var out: Font = base
	if base != null and wght > 0:
		var fv := FontVariation.new()
		fv.base_font = base
		var ts := TextServerManager.get_primary_interface()
		fv.variation_opentype = {ts.name_to_tag("wght"): wght}
		out = fv
	if out == null:
		out = UITheme.bold_font()
	_font_cache[key] = out
	return out

static func _combo() -> Dictionary:
	return COMBOS.get(combo, COMBOS[DEFAULT_COMBO])

## Titulos, botones y cifras.
static func title_font() -> Font:
	var c := _combo()
	return _variation(c["title"], int(c["title_wght"]))

## Texto de cuerpo.
static func body_font() -> Font:
	var c := _combo()
	return _variation(c["body"], int(c["body_wght"]))

## Cuerpo en negrita: rotulos pequenos bajo los iconos, etiquetas de fila.
static func bold_font() -> Font:
	var c := _combo()
	return _variation(c["body"], int(c["bold_wght"]))

# ══════════════════════════════════════
# TAMANOS (docs/28 §4)
# ══════════════════════════════════════

## Pixeles del lienzo a 1280x720 (PC). En tablet y movil el lienzo ya se
## agranda con DeviceProfile (x1,15 / x1,3), asi que los numeros son los mismos.
const SIZES := {"display": 34, "title": 26, "button": 22, "number": 22, "body": 18, "small": 15}
## Nunca por debajo de esto, ni con el texto "pequeno" de Ajustes.
const SIZE_FLOOR := {"display": 26, "title": 20, "button": 18, "number": 18, "body": 16, "small": 14}

const RADIUS_WINDOW := 22
const RADIUS_CARD := 18
const BORDER_WINDOW := 4
const BORDER := 3
## El "labio" de los botones de juguete: el borde inferior mas grueso.
const LIP := 5
const PAD := 18
const GAP := 12
## Alto de boton: pastilla grande, normal y pequena.
const BTN_BIG := 64
const BTN := 52
const BTN_SMALL := 44
## Diametro de los botones redondos de la barra de abajo.
const ROUND := 66

## Altos segun el lienzo: "big" (accion principal), "btn", "small". En
## telefono nada baja de TOUCH_MIN (48 dp).
static func h(size_s: String) -> int:
	match size_s:
		"big":
			return 52 if phone else BTN_BIG
		"small":
			return 48 if phone else BTN_SMALL
	return 48 if phone else BTN

## Telefono pequeno (lienzo de 360 de alto, docs/28 §4): se disena PRIMERO
## para el y luego se escala. Pixeles logicos = dp.
const SIZES_PHONE := {"display": 22, "title": 19, "button": 17, "number": 17, "body": 15, "small": 13}
const SIZE_FLOOR_PHONE := {"display": 20, "title": 17, "button": 16, "number": 16, "body": 14, "small": 12}
## Lado tactil minimo en telefono (dp).
const TOUCH_MIN := 48

## true en lienzos de telefono (alto < 450): letra y piezas de telefono.
static var phone := false

static func fs(level: String) -> int:
	if phone:
		var pb: int = SIZES_PHONE.get(level, SIZES_PHONE["body"])
		return maxi(int(SIZE_FLOOR_PHONE.get(level, 12)), roundi(float(pb) * UITheme.text_scale))
	var base: int = SIZES.get(level, SIZES["body"])
	return maxi(int(SIZE_FLOOR.get(level, 14)), roundi(float(base) * UITheme.text_scale))

# ══════════════════════════════════════
# COLORES (docs/28 §2)
# ══════════════════════════════════════

## Tinta de contornos y del texto blanco sobre color (la de los instructores).
const INK := Color(0.12, 0.09, 0.06)
const WHITE := Color(1.0, 0.99, 0.96)

## Los semanticos: los cinco de docs/24 (laton, positivo, peligro, advertencia,
## informacion) subidos de luz y de saturacion. Mismo significado.
const _SEMANTIC := {
	"ACCENT": Color("f5b31c"),
	"POSITIVE": Color("37a847"),
	"DANGER": Color("e0453a"),
	"WARNING": Color("ff8c1a"),
	"INFO": Color("2a88d8"),
}
## Daltonismo: los mismos cambios que UITheme._PALETTE_TOKENS, con su luz.
const _SEMANTIC_PALETTES := {
	"red_green": {"POSITIVE": Color("0072b2"), "DANGER": Color("d55e00"), "WARNING": Color("f0e442"), "INFO": Color("cc79a7")},
	"tritan": {"POSITIVE": Color("009e99"), "DANGER": Color("dc264d"), "WARNING": Color("f78c9e"), "INFO": Color("8c8c99")},
}

## Las dos superficies. Las ventanas y el HUD eligen una segun `surface`.
const _SURF := {
	"light": {
		"BG": Color("fff6e3"), "CARD": Color("fffcf4"), "CARD_ALT": Color("f7e7c4"),
		"WELL": Color("ecd9b2"), "BORDER": Color("7a5634"), "CARD_BORDER": Color("a07a52"),
		"TEXT": Color("2e2218"), "TEXT_DIM": Color("6a543c"), "NEUTRAL": Color("fffaef"),
		"SHADOW": Color(0.22, 0.13, 0.05, 0.34),
	},
	"dark": {
		"BG": Color("1a2531"), "CARD": Color("26364a"), "CARD_ALT": Color("34495f"),
		"WELL": Color("152130"), "BORDER": Color("f5b31c"), "CARD_BORDER": Color("5b7898"),
		"TEXT": Color("fff5e1"), "TEXT_DIM": Color("bdd0e2"), "NEUTRAL": Color("44607f"),
		"SHADOW": Color(0, 0, 0, 0.45),
	},
}
## Alto contraste: blanco y negro puros, bordes mas gruesos (ver border_k()).
const _SURF_HC := {
	"light": {"BG": Color("ffffff"), "CARD": Color("ffffff"), "CARD_ALT": Color("f1f1f1"),
		"WELL": Color("dcdcdc"), "BORDER": Color("000000"), "CARD_BORDER": Color("000000"),
		"TEXT": Color("000000"), "TEXT_DIM": Color("1c1c1c")},
	"dark": {"BG": Color("070b10"), "CARD": Color("101820"), "CARD_ALT": Color("1c2a38"),
		"WELL": Color("000000"), "BORDER": Color("ffd34d"), "CARD_BORDER": Color("ffffff"),
		"TEXT": Color("ffffff"), "TEXT_DIM": Color("f2f2f2")},
}

## "hud" (fichas sobre el mapa, barra de abajo) o "window" (ventanas grandes).
static func kind(role: String) -> String:
	if role == "hud":
		return "light" if surface == "light" else "dark"
	return "dark" if surface == "dark" else "light"

## Un color de la superficie de `role` (BG, CARD, TEXT...) o un semantico.
static func c(role: String, key: String) -> Color:
	if _SEMANTIC.has(key):
		return sem(key)
	var k := kind(role)
	if UITheme.high_contrast and _SURF_HC[k].has(key):
		return _SURF_HC[k][key]
	return _SURF[k][key]

static func sem(key: String) -> Color:
	var pal: Dictionary = _SEMANTIC_PALETTES.get(UITheme.palette, {})
	return pal.get(key, _SEMANTIC[key])

static func border_k() -> int:
	return 1 if UITheme.high_contrast else 0

## Color de texto que se lee sobre `fill`: tinta sobre lo claro, blanco con
## contorno de tinta sobre lo saturado. `outline` dice si lleva contorno.
static func on_fill(fill: Color) -> Dictionary:
	if UITheme._relative_luminance(fill) > 0.42:
		return {"color": INK, "outline": false}
	return {"color": WHITE, "outline": true}

# ══════════════════════════════════════
# CAJAS
# ══════════════════════════════════════

static func box(bg: Color, border: Color, bw: int, radius: int, pad: int = PAD, shadow: int = 0,
		lip: int = 0, role: String = "window") -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.corner_detail = 10
	s.anti_aliasing = true
	s.set_content_margin_all(pad)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw + border_k())
		s.border_width_bottom = bw + border_k() + lip
	if shadow > 0:
		s.shadow_color = c(role, "SHADOW")
		s.shadow_size = shadow
		s.shadow_offset = Vector2(0, roundf(shadow * 0.45))
	return s

## La ventana grande (CONSTRUIR, MISIONES, AJUSTES...).
static func window_style(role: String = "window") -> StyleBoxFlat:
	var s := box(c(role, "BG"), c(role, "BORDER"), BORDER_WINDOW, RADIUS_WINDOW, PAD, 0, 0, role)
	s.bg_color.a = UITheme.panel_opacity if kind(role) == "dark" else 1.0
	# Sombra dura (0 4px 0, sin desenfoque): la ventana es una pieza de juguete.
	s.shadow_color = Color(c(role, "BORDER").darkened(0.45), 0.75)
	s.shadow_size = 1
	s.shadow_offset = Vector2(0, 5)
	return s

## Tarjeta dentro de una ventana. `selected`: borde de laton grueso.
static func card_style(role: String = "window", selected: bool = false, fill: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var bg := fill if fill.a > 0.0 else c(role, "CARD")
	var s := box(bg, sem("ACCENT") if selected else c(role, "CARD_BORDER"),
		BORDER + (1 if selected else 0), RADIUS_CARD, 12, 0, 2, role)
	if selected:
		s.shadow_color = Color(sem("ACCENT"), 0.55)
		s.shadow_size = 6
	return s

## Hueco hundido (barras, fondo de cifras, carril del deslizador).
static func well_style(role: String, radius: int = 12, pad: int = 6) -> StyleBoxFlat:
	return box(c(role, "WELL"), Color(0, 0, 0, 0), 0, radius, pad, 0, 0, role)

## Ficha del HUD sobre el mapa. Clara: crema con tinta gruesa. Oscura: pizarra
## translucida con un borde fino de color (el "HUD oscuro fino").
static func hud_style(accent: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	if kind("hud") == "light":
		return box(c("hud", "CARD"), c("hud", "BORDER"), BORDER, 18, 8, 6, 2, "hud")
	var s := box(Color(c("hud", "BG"), 0.9 if not UITheme.high_contrast else 1.0),
		accent if accent.a > 0.0 else c("hud", "CARD_BORDER"), 2, 16, 8, 6, 0, "hud")
	return s

## Cinta del titulo de una ventana: color vivo, tinta gruesa y labio.
static func ribbon_style(fill: Color) -> StyleBoxFlat:
	var s := box(fill, INK, BORDER + 1, 16, 0, 0, 4)
	s.content_margin_left = 30
	s.content_margin_right = 30
	s.content_margin_top = 4
	s.content_margin_bottom = 6
	return s

# ══════════════════════════════════════
# TEXTO
# ══════════════════════════════════════

## Etiqueta en el nivel pedido (display, title, button, number, body, small).
## `outline`: contorno de tinta (texto blanco sobre color o sobre el mapa).
static func label(text: String, level: String, color: Color, outline: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	style_label(l, level, color, outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func style_label(l: Label, level: String, color: Color, outline: bool = false) -> void:
	var size := fs(level)
	var f: Font
	match level:
		"display", "title", "button", "number":
			f = title_font()
		"small":
			f = bold_font()
		_:
			f = body_font()
	if f != null:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.add_theme_constant_override("outline_size", maxi(4, roundi(size * 0.3)))
		l.add_theme_color_override("font_outline_color", INK)
	else:
		l.add_theme_constant_override("outline_size", 0)
	l.add_theme_constant_override("line_spacing", -2 if level in ["display", "title", "button", "number"] else 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

## Texto de la superficie de `role`, normal o tenue.
static func text(role: String, dim: bool = false) -> Color:
	return c(role, "TEXT_DIM" if dim else "TEXT")

## Texto que envuelve (una frase como mucho, docs/28 §9).
static func para(text_s: String, role: String, dim: bool = false, level: String = "body") -> Label:
	var l := label(text_s, level, text(role, dim))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

# ══════════════════════════════════════
# BOTONES
# ══════════════════════════════════════

## Relleno de cada clase de boton.
static func kind_fill(kind_s: String, role: String = "window") -> Color:
	# Por intencion (docs/28 §5): verde = la accion principal, azul = abrir /
	# ver, ambar = avisar / reparar / mejorar, rojo = derribar / cerrar, gris =
	# no se puede (con el porque escrito debajo).
	match kind_s:
		"primary":
			return sem("POSITIVE")
		"accent":
			return sem("ACCENT")
		"danger":
			return sem("DANGER")
		"info", "open":
			return sem("INFO")
		"warning", "warn":
			return sem("WARNING")
		"disabled":
			return Color("9a958c") if kind(role) == "light" else Color("55606c")
	return c(role, "NEUTRAL")

static func _btn_states(btn: Button, fill: Color, radius: int, pad_h: int, role: String) -> void:
	var border := INK if kind(role) == "light" or fill != c(role, "NEUTRAL") else c(role, "CARD_BORDER")
	var n := box(fill, border, BORDER, radius, 0, 0, LIP, role)
	var h := box(fill.lightened(0.12), border, BORDER, radius, 0, 0, LIP, role)
	var p := box(fill.darkened(0.08), border, BORDER, radius, 0, 0, 1, role)
	var d := box(Color(fill.lerp(Color(0.6, 0.6, 0.6), 0.65), 0.75), Color(border, 0.5), BORDER, radius, 0, 0, 2, role)
	for sb in [n, h, p, d]:
		sb.content_margin_left = pad_h
		sb.content_margin_right = pad_h
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
	# Pulsado: el contenido baja lo que pierde el labio (sin animacion).
	p.content_margin_top = 2 + LIP - 1
	var f := box(Color(0, 0, 0, 0), Color(sem("ACCENT"), 0.9), 3, radius + 3, 0)
	btn.add_theme_stylebox_override("normal", n)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", p)
	btn.add_theme_stylebox_override("disabled", d)
	btn.add_theme_stylebox_override("focus", f)

## Boton pastilla: [icono] PALABRA. `kind_s`: primary (verde, la accion
## principal), accent (laton, mejorar/comprar), danger (rojo, derribar),
## info (azul, ayuda/ver), secondary (crema, lo demas). `glyph` es un id de
## CartoonIcon o "res:<id>" para un icono de recurso.
static func pill_button(text_s: String, glyph: String = "", kind_s: String = "primary",
		height: int = BTN, role: String = "window", level: String = "button") -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var fill := kind_fill(kind_s, role)
	_btn_states(btn, fill, int(height * 0.5), 22 if text_s != "" else 8, role)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if glyph != "":
		row.add_child(make_glyph(glyph, roundi(height * 0.56)))
	if text_s != "":
		var tc := on_fill(fill)
		if kind_s == "secondary":
			tc = {"color": text(role), "outline": false}
		row.add_child(label(text_s, level, tc["color"], tc["outline"]))
	_fill_button(btn, row, height, 22 if text_s != "" else 8)
	return btn

## Mete `content` centrado en el boton y le da el tamano minimo del contenido.
static func _fill_button(btn: Button, content: Control, height: int, pad_h: int) -> void:
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_top = 0
	content.offset_bottom = -LIP
	btn.add_child(content)
	# El contenido solo sabe lo que mide dentro del arbol (la letra se resuelve
	# con el tema): el boton se reajusta cada vez que cambia.
	var fit := func():
		if not is_instance_valid(btn) or not is_instance_valid(content):
			return
		var m := content.get_combined_minimum_size()
		btn.custom_minimum_size = Vector2(maxf(m.x + pad_h * 2 + BORDER * 2, maxf(height, btn.get_meta("min_w", 0.0))), height)
	content.minimum_size_changed.connect(fit)
	fit.call()

## Boton redondo con icono (barra de abajo, cerrar). `caption` va debajo.
static func round_button(glyph: String, kind_s: String = "secondary", d: int = ROUND,
		caption: String = "", role: String = "hud", glyph_tint: Color = Color(0, 0, 0, 0)) -> Control:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_ALL
	var fill := kind_fill(kind_s, role)
	_btn_states(btn, fill, int(d * 0.5), 0, role)
	var icon := make_glyph(glyph, roundi(d * 0.58), glyph_tint)
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(icon)
	_fill_button(btn, holder, d, 0)
	btn.custom_minimum_size = Vector2(d, d)
	if caption == "":
		return btn
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var wrap := CenterContainer.new()
	wrap.add_child(btn)
	col.add_child(wrap)
	var cap := label(caption, "small", WHITE, true)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cap)
	col.set_meta("button", btn)
	return col

## Cerrar: redondo rojo con la X, siempre arriba a la derecha de la ventana.
static func close_button(d: int = 0) -> Button:
	return round_button("close", "danger", d if d > 0 else (48 if phone else 50)) as Button

## Un icono: id de CartoonIcon, "res:<id>" (recurso, PNG) o "unit:<id>"
## (silueta de unidad, PNG en blanco).
static func make_glyph(glyph: String, px: int, tint: Color = Color(0, 0, 0, 0)) -> Control:
	if glyph.begins_with("res:"):
		return UITheme.make_icon(glyph.substr(4), px)
	if glyph.begins_with("unit:"):
		var r := TextureRect.new()
		r.texture = UITheme.unit_icon(glyph.substr(5), px)
		r.custom_minimum_size = Vector2(px, px)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.modulate = tint if tint.a > 0.0 else WHITE
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return r
	return Icon.make(glyph, px, tint)

# ══════════════════════════════════════
# PIEZAS
# ══════════════════════════════════════

## Con true, las fichas de cifra no llevan nombre debajo (telefono: el
## nombre sale al mantener pulsado).
static var show_caption_never := false

## Ficha de cifra: [icono] 1.240 con el nombre debajo en pequeno.
static func stat_chip(glyph: String, value: String, caption: String, role: String = "hud",
		value_color: Color = Color(0, 0, 0, 0)) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.tooltip_text = caption
	var ic := make_glyph(glyph, 26 if phone else 34)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(label(value, "number", value_color if value_color.a > 0.0 else text(role)))
	if caption != "" and not show_caption_never:
		col.add_child(label(caption, "small", text(role, true)))
	row.add_child(col)
	return row

## Coste en pequeno: [icono] 80, en rojo si no llega.
static func cost_chip(res_id: String, amount: int, enough: bool = true, role: String = "window") -> PanelContainer:
	var p := PanelContainer.new()
	var s := well_style(role, 14, 4)
	s.content_margin_left = 6
	s.content_margin_right = 10
	if not enough:
		s.bg_color = Color(sem("DANGER"), 0.22)
		s.border_color = sem("DANGER")
		s.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", s)
	p.tooltip_text = Tr.res_cap(res_id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(UITheme.make_icon(res_id, 24))
	var col := text(role)
	if not enough:
		col = sem("DANGER").darkened(0.25) if kind(role) == "light" else sem("DANGER").lightened(0.35)
	row.add_child(label(_thousands(amount), "number", col))
	p.add_child(row)
	return p

## Etiqueta de estado: pastilla de color con 1-2 palabras ("Trabajando").
static func badge(text_s: String, fill: Color, glyph: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(fill, INK, 2, 14, 0)
	s.content_margin_left = 10
	s.content_margin_right = 12
	s.content_margin_top = 1
	s.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	if glyph != "":
		row.add_child(make_glyph(glyph, 20))
	var tc := on_fill(fill)
	row.add_child(label(text_s, "small", tc["color"], tc["outline"]))
	p.add_child(row)
	return p

## Barra de progreso redonda.
static func progress(value: float, fill: Color, role: String = "window", h: int = 16) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.value = value
	bar.custom_minimum_size = Vector2(0, h)
	var border := INK if kind(role) == "light" else c(role, "CARD_BORDER")
	var bg := box(c(role, "WELL"), border, 2, int(h * 0.5), 0, 0, 0, role)
	var fg := box(fill, border, 2, int(h * 0.5), 0, 0, 0, role)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar

## Interruptor grande: carril pastilla y bolita blanca (verde = encendido).
static func switch(on: bool, role: String = "window") -> Control:
	var track := PanelContainer.new()
	var border := INK if kind(role) == "light" else c(role, "CARD_BORDER")
	var s := box(sem("POSITIVE") if on else c(role, "WELL"), border, BORDER, 20, 4, 0, 0, role)
	track.add_theme_stylebox_override("panel", s)
	track.custom_minimum_size = Vector2(76, 40)
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END if on else BoxContainer.ALIGNMENT_BEGIN
	var knob := Panel.new()
	knob.custom_minimum_size = Vector2(28, 28)
	knob.add_theme_stylebox_override("panel", box(WHITE, INK, 2, 14, 0))
	row.add_child(knob)
	track.add_child(row)
	return track

## Deslizador de dedo: carril grueso, relleno de laton y bolita blanca.
static func slider(value: float, role: String = "window") -> HSlider:
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.01
	sl.value = value
	sl.custom_minimum_size = Vector2(0, 40)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var border := INK if kind(role) == "light" else c(role, "CARD_BORDER")
	var rail := box(c(role, "WELL"), border, 2, 9, 0, 0, 0, role)
	rail.content_margin_top = 7
	rail.content_margin_bottom = 7
	var area := box(sem("ACCENT"), border, 2, 9, 0, 0, 0, role)
	area.content_margin_top = 7
	area.content_margin_bottom = 7
	sl.add_theme_stylebox_override("slider", rail)
	sl.add_theme_stylebox_override("grabber_area", area)
	sl.add_theme_stylebox_override("grabber_area_highlight", area)
	sl.add_theme_icon_override("grabber", knob_icon(34))
	sl.add_theme_icon_override("grabber_highlight", knob_icon(34))
	return sl

static var _knob := {}
static func knob_icon(side: int) -> Texture2D:
	if _knob.has(side):
		return _knob[side]
	var img := Image.create(side, side, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := side * 0.5
	for y in side:
		for x in side:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			if d <= r - 4.0:
				img.set_pixel(x, y, WHITE)
			elif d <= r - 0.6:
				img.set_pixel(x, y, INK)
			elif d <= r:
				img.set_pixel(x, y, Color(INK, r - d))
	var t := ImageTexture.create_from_image(img)
	_knob[side] = t
	return t

## Selector de 2-4 opciones en fila (sustituye a los desplegables).
static func segmented(options: Array, selected: int, role: String = "window", height: int = BTN_SMALL) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for i in options.size():
		var b := pill_button(String(options[i]), "", "info" if i == selected else "secondary", height, role, "body")
		row.add_child(b)
	return row

## Pestana: [icono] Palabra. La elegida, en color y con labio; las demas, planas.
static func tab(text_s: String, glyph: String, selected: bool, role: String = "window",
		fill: Color = Color(0, 0, 0, 0), height: int = BTN) -> Button:
	if selected:
		var f := fill if fill.a > 0.0 else sem("ACCENT")
		var b := Button.new()
		_btn_states(b, f, 18, 18, role)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if glyph != "":
			row.add_child(make_glyph(glyph, roundi(height * 0.58)))
		var tc := on_fill(f)
		row.add_child(label(text_s, "button", tc["color"], tc["outline"]))
		_fill_button(b, row, height, 18)
		return b
	var btn := Button.new()
	var border := c(role, "CARD_BORDER")
	var n := box(c(role, "CARD_ALT"), Color(border, 0.55), 2, 18, 0, 0, 0, role)
	var h := box(c(role, "CARD_ALT").lightened(0.08), border, 2, 18, 0, 0, 0, role)
	for sb in [n, h]:
		sb.content_margin_left = 18
		sb.content_margin_right = 18
	btn.add_theme_stylebox_override("normal", n)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", h)
	btn.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), sem("ACCENT"), 3, 20, 0))
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 8)
	row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if glyph != "":
		row2.add_child(make_glyph(glyph, roundi(height * 0.5)))
	row2.add_child(label(text_s, "button", text(role, true)))
	_fill_button(btn, row2, height, 18)
	return btn

## Globo de ayuda (lo que sale al pasar el raton o mantener el dedo): tinta
## oscura, texto claro, una o dos frases. Igual en las tres superficies.
static func tooltip_bubble(text_s: String, max_w: float = 300.0) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(Color("2e2218") if not UITheme.high_contrast else Color.BLACK, sem("ACCENT"), 2, 14, 12, 8, 0)
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text_s, "body", Color("fff5e1"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(max_w, 0)
	p.add_child(l)
	return p

## Estilo para el TooltipPanel global (Theme): el mismo globo.
static func tooltip_style() -> StyleBoxFlat:
	return box(Color("2e2218"), sem("ACCENT"), 2, 14, 10, 8, 0)

## Ventana con su cinta de titulo encima del borde y la X redonda. Devuelve
## {"root": Control, "body": VBoxContainer, "close": Button}. El llamador
## coloca `root` (anclas/tamano); el cuerpo se llena con su contenido.
static func window(title: String, ribbon_fill: Color = Color(0, 0, 0, 0), with_close: bool = true,
		role: String = "window") -> Dictionary:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ribbon_fill if ribbon_fill.a > 0.0 else sem("ACCENT")
	var ribbon := PanelContainer.new()
	ribbon.add_theme_stylebox_override("panel", ribbon_style(fill))
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tc := on_fill(fill)
	var t := label(title, "display", tc["color"], tc["outline"])
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ribbon.add_child(t)
	# Alto de la cinta calculado (fuera del arbol las etiquetas no se miden).
	var rh := roundf(fs("display") * 1.3) + 4 + 6 + (BORDER + 1 + border_k()) * 2 + 4
	var rs := Vector2(0, rh)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", window_style(role))
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_top = roundf(rs.y * 0.5)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", GAP)
	var top_pad := Control.new()
	top_pad.custom_minimum_size = Vector2(0, roundf(rs.y * 0.5) - 6)
	body.add_child(top_pad)
	panel.add_child(body)
	ribbon.set_anchors_preset(Control.PRESET_CENTER_TOP)
	ribbon.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ribbon.offset_left = 0
	ribbon.offset_right = 0
	ribbon.offset_top = 0
	ribbon.offset_bottom = rs.y
	root.add_child(ribbon)
	var close: Button = null
	if with_close:
		close = close_button()
		close.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		close.offset_left = -close.custom_minimum_size.x + 10
		close.offset_right = 10
		close.offset_top = rs.y * 0.5 - close.custom_minimum_size.y * 0.5 + 2
		close.offset_bottom = close.offset_top + close.custom_minimum_size.y
		root.add_child(close)
	return {"root": root, "body": body, "close": close, "panel": panel}

## Aviso (docs/28 §10): icono + una frase + X, en la columna de avisos. El
## repetido se agrupa con "x3". `tone`: positive, warning, danger, info.
## Solo el ESTILO: la cola y la colocacion son de NotificationPanel.
static func notice(text_s: String, glyph: String, tone: String = "info", count: int = 1) -> PanelContainer:
	var col: Color = sem({"positive": "POSITIVE", "warning": "WARNING", "danger": "DANGER"}.get(tone, "INFO"))
	var s := hud_style(col)
	s.border_width_left = 7
	s.content_margin_top = 1 if phone else 4
	s.content_margin_bottom = 1 if phone else 4
	s.content_margin_right = 2 if phone else 4
	s.content_margin_left = 8
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", s)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := make_glyph(glyph, 20 if phone else 28)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var l := label(text_s, "small" if phone else "body", text("hud"))
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	if count > 1:
		row.add_child(badge("x%d" % count, col))
		(row.get_child(row.get_child_count() - 1) as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# La X: dibujo pequeno, zona de toque de dedo (el boton entero mide 40-48).
	var x := Button.new()
	x.flat = true
	# En telefono la X dibujada es pequena; el aviso entero tambien se cierra
	# de un toque (docs/28 §10), asi que el dedo no tiene que acertarle.
	x.custom_minimum_size = Vector2(40, 40) if not phone else Vector2(30, 30)
	x.tooltip_text = "Cerrar"
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		x.add_theme_stylebox_override(st, empty)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(make_glyph("close", 13 if phone else 16, text("hud", true)))
	x.add_child(cc)
	row.add_child(x)
	p.add_child(row)
	return p

## Velo detras de una ventana: oscurece el mapa sin taparlo del todo.
static func veil() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.05, 0.04, 0.03, 0.6 if UITheme.high_contrast else 0.42)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r

## 12480 -> "12.480" (punto de miles, como se escribe en espanol).
static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

static func thousands(n: int) -> String:
	return _thousands(n)

# ══════════════════════════════════════
# PUENTE CON UITheme (los paneles viejos)
# ══════════════════════════════════════

## Los tokens de UITheme reescritos con la superficie de las ventanas, para
## que los paneles que aun no se rehicieron sigan el estilo a grandes rasgos.
## `base` son los de resolve_tokens() de siempre (recursos, tablero, ramas).
static func legacy_tokens(base: Dictionary) -> Dictionary:
	var d := base.duplicate()
	var r := "window"
	var light := kind(r) == "light"
	d["SURFACE"] = c(r, "BG")
	d["NEUTRAL"] = c(r, "NEUTRAL")
	d["BG_DARK"] = c(r, "WELL")
	d["PANEL_BG"] = c(r, "BG")
	d["PANEL_BG_LIGHT"] = c(r, "CARD")
	d["CARD_BG"] = c(r, "CARD")
	d["HUD_BG"] = Color(c("hud", "BG"), 0.92)
	d["ACCENT"] = sem("ACCENT").darkened(0.25) if light else sem("ACCENT")
	d["ACCENT_DIM"] = Color(c(r, "CARD_BORDER"), 0.7)
	d["TEXT"] = c(r, "TEXT")
	d["TEXT_DIM"] = c(r, "TEXT_DIM")
	d["TEXT_BRIGHT"] = INK if light else WHITE
	# El contorno de las etiquetas viejas: del color del fondo, se funde.
	d["OUTLINE_COLOR"] = c(r, "BG")
	for k in ["POSITIVE", "DANGER", "WARNING", "INFO"]:
		d[k] = sem(k)
	d["BTN"] = c(r, "NEUTRAL")
	d["BTN_HOVER"] = c(r, "CARD_ALT")
	d["BTN_PRESSED"] = c(r, "CARD_ALT").darkened(0.08)
	d["BTN_DISABLED"] = Color(c(r, "WELL"), 0.7)
	return d
