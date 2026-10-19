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

## true con el perfil Movil o un lienzo de telefono; lo fija DeviceProfile. Leelo con is_phone().
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

## Tema de las ventanas, a eleccion del jugador (Ajustes > Pantalla > Tema;
## settings.cfg [interfaz] ui_theme): "light" = ventanas crema (de serie),
## "dark" = ventanas gris azulado con borde de color. El HUD es oscuro en los
## dos. Lo pone DeviceProfile.apply_theme() antes de UITheme.configure().
const WINDOW_THEMES := ["light", "dark"]
static var window_theme := "light"

## Las ventanas del tema oscuro (Bryan, 2026-10-19): fondo #243241, tarjetas
## #2e3f51, borde #4fa3e0, texto #f3f7fb y tenue #a9bccd.
const _SURF_NIGHT := {
	"BG": Color("243241"), "CARD": Color("2e3f51"), "CARD_ALT": Color("37495d"),
	"WELL": Color("1b2733"), "BORDER": Color("4fa3e0"), "CARD_BORDER": Color("4b6b89"),
	"TEXT": Color("f3f7fb"), "TEXT_DIM": Color("a9bccd"), "NEUTRAL": Color("3d546c"),
	"SHADOW": Color(0, 0, 0, 0.45),
}

## "hud" (fichas sobre el mapa, barra de abajo) o "window" (ventanas grandes).
static func kind(role: String) -> String:
	if role == "hud":
		return "light" if surface == "light" else "dark"
	return "dark" if (surface == "dark" or window_theme == "dark") else "light"

## Un color de la superficie de `role` (BG, CARD, TEXT...) o un semantico.
static func c(role: String, key: String) -> Color:
	if _SEMANTIC.has(key):
		return sem(key)
	var k := kind(role)
	if UITheme.high_contrast and _SURF_HC[k].has(key):
		return _SURF_HC[k][key]
	if k == "dark" and role != "hud" and window_theme == "dark" and _SURF_NIGHT.has(key):
		return _SURF_NIGHT[key]
	return _SURF[k][key]

## Si las ventanas son oscuras (tema oscuro o superficie oscura).
static func dark_windows() -> bool:
	return kind("window") == "dark"

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
	var s := box(Color(c("hud", "BG"), (0.92 if not UITheme.high_contrast else 1.0) * UITheme.panel_opacity),
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
## Las X de ventana van en el grupo "window_close": PauseMenu las aparta de
## debajo del ☰ (dodge_menu_button) cada vez que se abre o cierra una ventana.
static func close_button(d: int = 0) -> Button:
	var b := round_button("close", "danger", d if d > 0 else (48 if phone else 50)) as Button
	b.add_to_group("window_close")
	return b

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
		col = danger_text(role)
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
	return {"root": root, "body": body, "close": close, "panel": panel, "ribbon": ribbon, "top_pad": top_pad}

## La cinta mide lo que mida su titulo (una palabra larga, letra grande): el
## hueco de arriba del cuerpo la sigue, para que nada quede tapado bajo ella.
## Llamalo despues de cambiar el titulo (diferido: la etiqueta se mide en el arbol).
static func sync_ribbon_pad(w: Dictionary) -> void:
	var ribbon: Control = w.get("ribbon")
	var pad: Control = w.get("top_pad")
	var panel: Control = w.get("panel")
	if ribbon == null or pad == null or panel == null:
		return
	var rh := maxf(ribbon.get_combined_minimum_size().y, ribbon.offset_bottom - ribbon.offset_top)
	ribbon.offset_bottom = ribbon.offset_top + rh
	var need := rh - panel.offset_top - float(panel.get_theme_stylebox("panel").content_margin_top) + 6.0
	pad.custom_minimum_size.y = maxf(roundf(need), 0.0)

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
		row.add_child(badge("×%d" % count, col))
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
	d["HUD_BG"] = Color(c("hud", "BG"), 0.92 * UITheme.panel_opacity)
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

# --- HUD (feat/ui2-hud) ---
# Piezas del HUD de la fase 2 (docs/28 §12): barra de recursos, rango compacto,
# icono de la Tormenta, la linea del siguiente paso con la cara de la Capitana,
# la barra de abajo y el estilo de los avisos. Solo se anaden; lo de arriba no
# se toca.

## Margen del HUD con el borde de la pantalla (telefono / PC y tablet).
static func hud_edge() -> float:
	return 8.0 if phone else 14.0

## Diametro de los redondos de la barra de abajo y del ☰ (docs/28 §5).
static func bar_round() -> int:
	return 48 if phone else 64

static func menu_round() -> int:
	return 48 if phone else 54

## Diametro del icono de la Tormenta (un redondo solo, docs/28 §12).
static func storm_round() -> int:
	return 44 if phone else 50

## Alto de CONSTRUIR en la barra (pastilla grande: 52 telefono, 70 PC).
static func bar_build_h() -> int:
	return 52 if phone else 70

## Ficha redonda del HUD oscuro con un aro de color (la Tormenta).
static func hud_round_style(d: int, ring: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := box(Color(c("hud", "BG"), 0.9 if not UITheme.high_contrast else 1.0),
		ring if ring.a > 0.0 else c("hud", "CARD_BORDER"), 3 if ring.a > 0.0 else 2, int(d * 0.5), 0, 0, 0, "hud")
	return s

## El punto rojo de "hay algo nuevo" (Misiones). Se pega a la esquina de arriba
## a la derecha de `host` (un boton redondo).
static func red_dot(host: Control, side: int = 0) -> Panel:
	var px := side if side > 0 else (16 if phone else 20)
	var dot := Panel.new()
	dot.name = "RedDot"
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.add_theme_stylebox_override("panel", box(sem("DANGER"), INK, 2, int(px * 0.5), 0))
	host.add_child(dot)
	dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	dot.offset_left = -px + 4
	dot.offset_right = 4
	dot.offset_top = -4
	dot.offset_bottom = px - 4
	return dot

## Glifo y tono de un aviso segun su categoria (NotificationPanel). Forma propia
## por tipo, no solo color: peligro rayo, advertencia reloj, logro estrella,
## la columna que sale o vuelve banderin, el resto la "?" azul.
static func notice_glyph(category: String) -> String:
	match category:
		"danger":
			return "raid"
		"warning":
			return "clock"
		"achievement", "success":
			return "star"
		"combat":
			return "missions"
	return "help"

static func notice_tone(category: String) -> String:
	match category:
		"danger":
			return "danger"
		"warning":
			return "warning"
		"achievement", "success":
			return "positive"
	return "info"

## Busca en un aviso de notice() su etiqueta, su X y su "×N" (para nombrarlos y
## cablearlos sin rehacer la pieza).
static func notice_parts(p: PanelContainer) -> Dictionary:
	var out := {"label": null, "close": null, "count": null}
	if p == null or p.get_child_count() == 0:
		return out
	var row := p.get_child(0)
	for ch in row.get_children():
		if ch is Label and out["label"] == null:
			out["label"] = ch
		elif ch is Button:
			out["close"] = ch
		elif ch is PanelContainer:
			out["count"] = ch
	return out

## La cara de la Capitana Remache en un circulo (la linea del siguiente paso,
## docs/28 §12): el mismo dibujo de InstructorBust, recortado, sin animacion.
class CaptainFace extends Control:
	var mood := "happy":
		set(v):
			mood = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		resized.connect(queue_redraw)

	func _draw() -> void:
		var sz := minf(size.x, size.y)
		if sz <= 1.0:
			return
		var center := size * 0.5
		draw_circle(center, sz * 0.5, Color("f7e7c4"))
		var h := sz * 2.15
		var w := h * 0.8
		var bust = load("res://scripts/ui/InstructorBust.gd")
		bust._draw_ada(self, Rect2(Vector2(size.x * 0.5 - w * 0.5, -0.1 * h), Vector2(w, h)), mood)
		draw_arc(center, sz * 0.5 - 1.5, 0.0, TAU, 40, CartoonTheme.sem("ACCENT"), 3.0, true)

static func captain_face(px: int) -> Control:
	var f := CaptainFace.new()
	f.custom_minimum_size = Vector2(px, px)
	f.size = Vector2(px, px)
	return f
# --- CONSTRUIR (feat/ui2-construir) ---
# Piezas de CONSTRUIR, la ficha del edificio, el Mercado e Investigar (fase 2,
# docs/28). Solo se anaden aqui: lo de arriba es de la fase 1 y de los otros
# frentes.

## LA pregunta "¿maqueto para telefono?" de todas las pantallas: lee `phone`,
## que fija DeviceProfile (perfil Movil, o lienzo de menos de
## DeviceProfile.PHONE_CANVAS_MAX_SIDE de lado corto). Las ventanas van entonces
## a pantalla completa, una columna. `_vp` se ignora (se acepta por las llamadas
## viejas); no se mira el tamano del lienzo aqui para que nadie discrepe.
static func is_phone(_vp: Vector2 = Vector2.ZERO) -> bool:
	return phone

## Rojo legible de "lo que falta" sobre la superficie de `role`.
static func danger_text(role: String = "window") -> Color:
	return readable(sem("DANGER").darkened(0.25) if kind(role) == "light" else sem("DANGER").lightened(0.35), role)

## Verde legible de "lo que se gana" sobre la superficie de `role`.
static func positive_text(role: String = "window") -> Color:
	return readable(sem("POSITIVE").darkened(0.3) if kind(role) == "light" else sem("POSITIVE").lightened(0.3), role)

## `col` como texto sobre la superficie de `role` (su BG, CARD y CARD_ALT):
## si no llega al contraste minimo (UITheme.MIN_CONTRAST: 4,5, o 7 con alto
## contraste) se oscurece sobre lo claro o se aclara sobre lo oscuro, a pasos,
## hasta llegar. Conserva el tono: rojo sigue rojo, ambar sigue ambar. Asi un
## color con significado se lee igual en Claro, en Oscuro y con daltonismo.
static func readable(col: Color, role: String = "window") -> Color:
	var target := UITheme.MIN_CONTRAST
	var light := kind(role) == "light"
	var out := col
	for i in 24:
		var worst := 99.0
		for key in ["BG", "CARD", "CARD_ALT"]:
			worst = minf(worst, UITheme.contrast_ratio(out, c(role, key)))
		if worst >= target:
			return out
		out = out.darkened(0.06) if light else out.lightened(0.06)
	return out

## Recursos que tienen icono propio (PNG). Los materiales del taller no: se
## escriben con su nombre.
const ICON_RES := ["gold", "wood", "steel", "oil", "food", "workers", "morale"]

## Fila de costes del estilo nuevo: una ficha hundida por recurso ([icono] cifra)
## y en rojo lo que falta (`short`, por nombre de recurso). Compatible con
## TextKit.row_amounts: cada cifra se llama "Amount_<id>" y la fila guarda el
## diccionario en la meta "amounts". `prefix` va delante ("+" en lo que se gana);
## `tone` cambia el color de las cifras que no faltan.
static func cost_strip(amounts: Dictionary, short: Dictionary = {}, role: String = "window",
		prefix: String = "", level: String = "number", tone: Color = Color(0, 0, 0, 0)) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "CostRow"
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	fill_cost_strip(row, amounts, short, role, prefix, level, tone)
	return row

## Rehace una fila de cost_strip con otras cifras. No toca nada si no cambio
## (llega una senal por recurso; docs/26 §6.9).
static func fill_cost_strip(row: Container, amounts: Dictionary, short: Dictionary = {}, role: String = "window",
		prefix: String = "", level: String = "number", tone: Color = Color(0, 0, 0, 0)) -> void:
	var sig := [amounts, short, role, prefix, level, tone, phone, UITheme.palette, UITheme.high_contrast]
	if row.has_meta("strip_sig") and row.get_meta("strip_sig") == sig and row.get_child_count() == amounts.size():
		return
	row.set_meta("strip_sig", sig)
	row.set_meta("amounts", amounts.duplicate())
	for child in row.get_children():
		row.remove_child(child)
		child.free()
	for res_id in amounts:
		var id := String(res_id)
		row.add_child(_strip_chip(id, int(amounts[res_id]), int(short.get(id, 0)), role, prefix, level, tone))

static func _strip_chip(id: String, amount: int, missing: int, role: String, prefix: String,
		level: String, tone: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "Chip_" + id
	var s := well_style(role, 12, 2)
	s.content_margin_left = 4
	s.content_margin_right = 8
	if missing > 0:
		s.bg_color = Color(sem("DANGER"), 0.22)
		s.border_color = sem("DANGER")
		s.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var cap := Tr.res_cap(id) if id != "workers" else Tr.t("UI2C_WORKERS")
	p.tooltip_text = cap if missing <= 0 else "%s · %s" % [cap, Tr.t("OBJ_MISSING") % ("%d" % missing)]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var txt := "%s%d" % [prefix, amount]
	if id in ICON_RES:
		var ic := UITheme.make_icon(id, 20 if phone else 24)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ic)
	else:
		txt += " " + Tr.res_name(id)
	var col := tone if tone.a > 0.0 else text(role)
	if missing > 0:
		col = danger_text(role)
	var l := label(txt, level if id in ICON_RES else "small", col)
	l.name = "Amount_" + id
	h.add_child(l)
	p.add_child(h)
	return p

## Hueco hundido con una imagen dentro (miniatura del edificio). Sobre una
## ventana oscura el hueco es claro (la letra tenue): las miniaturas son de
## tejados y piedra oscuros y en un hueco casi negro no se veian.
static func thumb_frame(content: Control, px: Vector2, role: String = "window") -> PanelContainer:
	var p := PanelContainer.new()
	var st := well_style(role, 12, 3)
	if kind(role) == "dark":
		st.bg_color = c(role, "TEXT_DIM")
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.custom_minimum_size = px
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(content)
	return p

## Cambia el texto de un boton hecho con pill_button / tab (su primera etiqueta).
static func set_pill_text(btn: Control, text_s: String) -> void:
	for n in btn.find_children("*", "Label", true, false):
		(n as Label).text = text_s
		return

## Cambia la clase (verde, azul, ambar, rojo, crema) de un pill_button hecho.
static func set_pill_kind(btn: Button, kind_s: String, height: int, role: String = "window") -> void:
	var fill := kind_fill(kind_s, role)
	_btn_states(btn, fill, int(height * 0.5), 22, role)
	var tc := on_fill(fill)
	if kind_s == "secondary":
		tc = {"color": text(role), "outline": false}
	for n in btn.find_children("*", "Label", true, false):
		var l := n as Label
		l.add_theme_color_override("font_color", tc["color"])
		l.add_theme_constant_override("outline_size", maxi(4, roundi(fs("button") * 0.3)) if tc["outline"] else 0)

## El porque de un boton gris, en 2-3 palabras debajo (docs/28 §5). Oculto si
## no hay porque.
static func why_label(role: String = "window") -> Label:
	var l := label("", "small", danger_text(role))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.visible = false
	return l

## Titulito de seccion: [icono] palabra en tenue (sin mayusculas).
static func section(text_s: String, glyph: String = "", role: String = "window") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	if glyph != "":
		var g := make_glyph(glyph, 20)
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(g)
	row.add_child(label(text_s, "small", text(role, true)))
	return row

## Una ventana de CartoonTheme.window() colocada a pantalla completa con
## `margin` de borde (telefono). La X se mete dentro para que no se corte.
static func fit_fullscreen(w: Dictionary, margin: float = 6.0) -> void:
	dodge_closes_in.call_deferred(w.get("root"))
	var root: Control = w["root"]
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = margin
	root.offset_top = 2.0
	root.offset_right = -margin
	root.offset_bottom = -margin
	root.custom_minimum_size = Vector2.ZERO
	var panel: PanelContainer = w["panel"]
	var s := window_style()
	s.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", s)
	var close: Control = w.get("close")
	if close != null:
		close.offset_left = -close.custom_minimum_size.x - 2
		close.offset_right = -2

## Devuelve la ventana a su sitio de PC (lo pone UILayoutManager con el slot).
static func fit_desktop(w: Dictionary) -> void:
	dodge_closes_in.call_deferred(w.get("root"))
	var panel: PanelContainer = w["panel"]
	panel.add_theme_stylebox_override("panel", window_style())
	var close: Control = w.get("close")
	if close != null:
		close.offset_left = -close.custom_minimum_size.x + 10
		close.offset_right = 10

## Barra de nivel: "Nivel 2 de 3" y una barra de laton con lo hecho.
static func level_bar(level: int, top: int, role: String = "window") -> ProgressBar:
	var bar := progress(float(level) / float(maxi(top, 1)), sem("ACCENT"), role, 10 if phone else 12)
	bar.custom_minimum_size.x = 80
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return bar

## Pastilla con su texto en Button.text (no en una etiqueta hija): para los
## botones cuyo texto cambia a menudo o se lee desde fuera (x1 / x5 / MAX,
## COMPRAR / VENDER, las tarjetas de tecnologia). Mismo labio y colores que
## pill_button; `icon_id` pone un icono de recurso (PNG) delante.
static func text_pill(text_s: String, kind_s: String = "primary", height: int = BTN,
		role: String = "window", level: String = "button", icon_id: String = "") -> Button:
	var b := Button.new()
	b.text = text_s
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(height, height)
	if icon_id != "":
		b.icon = UITheme.icon_texture(icon_id, 24)
		b.expand_icon = false
	style_text_pill(b, kind_s, height, role, level)
	return b

static func style_text_pill(b: Button, kind_s: String, height: int, role: String = "window", level: String = "button") -> void:
	var fill := kind_fill(kind_s, role)
	_btn_states(b, fill, int(height * 0.5), 14, role)
	var tc := on_fill(fill)
	if kind_s == "secondary":
		tc = {"color": text(role), "outline": false}
	var f: Font = title_font() if level in ["display", "title", "button", "number"] else bold_font()
	if f != null:
		b.add_theme_font_override("font", f)
	b.add_theme_font_size_override("font_size", fs(level))
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(st, tc["color"])
	b.add_theme_color_override("font_disabled_color", Color(tc["color"], 0.65))
	b.add_theme_constant_override("outline_size", maxi(4, roundi(fs(level) * 0.3)) if tc["outline"] else 0)
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("h_separation", 8)
	b.set_meta("pill_kind", kind_s)

## Tarjeta-boton (tecnologias): una tarjeta que se toca. `state`: "open",
## "done" (verde claro), "locked" (CARD_ALT). `selected`: borde de laton.
static func style_card_button(b: Button, state: String, selected: bool, edge: Color = Color(0, 0, 0, 0)) -> void:
	var fill := c("window", "CARD")
	if state == "done":
		fill = c("window", "CARD").lerp(sem("POSITIVE"), 0.22)
	elif state == "locked":
		fill = c("window", "CARD_ALT")
	var n := card_style("window", selected, fill)
	if edge.a > 0.0 and not selected:
		n.border_color = edge
	n.content_margin_left = 10
	n.content_margin_right = 10
	n.content_margin_top = 6
	n.content_margin_bottom = 8
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = fill.lightened(0.15)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("disabled", n)
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), sem("ACCENT"), 3, RADIUS_CARD + 2, 0))
	var col := text("window", state == "locked")
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(st, col)
	b.add_theme_constant_override("outline_size", 0)
	var f := bold_font()
	if f != null:
		b.add_theme_font_override("font", f)
	b.add_theme_font_size_override("font_size", fs("small"))

## Icono de girar (flecha en arco con punta), dibujado: CartoonIcon no lo trae.
static func rotate_glyph(px: int, tint: Color = Color(0, 0, 0, 0)) -> Control:
	var ctl := Control.new()
	ctl.custom_minimum_size = Vector2(px, px)
	ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctl.draw.connect(func():
		var s := minf(ctl.size.x, ctl.size.y)
		var cen := ctl.size * 0.5
		var r := s * 0.32
		var col := tint if tint.a > 0.0 else sem("INFO")
		var w := maxf(3.0, s * 0.14)
		ctl.draw_arc(cen, r, deg_to_rad(-60), deg_to_rad(220), 24, INK, w + 3.0, true)
		ctl.draw_arc(cen, r, deg_to_rad(-60), deg_to_rad(220), 24, col, w, true)
		var tip := cen + Vector2(cos(deg_to_rad(-60)), sin(deg_to_rad(-60))) * r
		var head := PackedVector2Array([tip + Vector2(-s * 0.2, -s * 0.05), tip + Vector2(s * 0.12, -s * 0.16),
			tip + Vector2(s * 0.06, s * 0.2)])
		ctl.draw_colored_polygon(head, col)
		ctl.draw_polyline(PackedVector2Array([head[0], head[1], head[2], head[0]]), INK, 2.0, true))
	return ctl

## Coloca una ventana de window() centrada en el lienzo (PC y tablet): ancho y
## alto como mucho `want` (alto 0 = lo que pida su contenido), con margen, y
## bajada lo justo para no quedar bajo el boton ☰ (UILayoutManager).
static func place_center(w: Dictionary, vp: Vector2, want: Vector2) -> void:
	fit_desktop(w)
	var root: Control = w["root"]
	var panel: PanelContainer = w["panel"]
	var h := want.y
	if h <= 0.0:
		h = panel.get_combined_minimum_size().y + panel.offset_top
	var sz := Vector2(minf(want.x, vp.x - 48.0), minf(h, vp.y - 32.0))
	if UILayoutManager != null and UILayoutManager.has_method("clear_menu_button"):
		sz = UILayoutManager.clear_menu_button(sz)
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.custom_minimum_size = Vector2.ZERO
	root.position = ((vp - sz) * 0.5).round()
	root.size = sz


# ══════════════════════════════════════
# --- EJÉRCITO (feat/ui2-ejercito)
# ══════════════════════════════════════
# Piezas de las pantallas de Ejercito, Misiones, combate y partes de guerra
# (fase 2, docs/28 §14). Solo se AÑADE aqui: lo de arriba es de la fase 1.

const _ArmyTextKit := preload("res://scripts/ui/TextKit.gd")

## Ventana grande con su velo detras, dentro de `parent` (un Control a pantalla
## completa). Devuelve lo de window() mas "holder" (velo + ventana, lo que se
## enciende y se apaga), "veil" y "ribbon".
static func modal_window(parent: Control, title: String, fill: Color, with_close: bool = true) -> Dictionary:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	var v := veil()
	holder.add_child(v)
	var w := window(title, fill, with_close)
	holder.add_child(w["root"])
	w["holder"] = holder
	w["veil"] = v
	w["ribbon"] = (w["root"] as Control).get_child(1)
	return w

## Coloca una ventana de modal_window(): en telefono a pantalla completa (6 px
## de margen); en PC centrada, con `max_size` de tope.
static func fit_window(w: Dictionary, vp: Vector2, max_size: Vector2) -> void:
	dodge_closes_in.call_deferred(w.get("root"))
	var root: Control = w["root"]
	var ph := is_phone()
	var margin := Vector2(6, 2) if ph else Vector2(24, 16)
	var sz := vp - margin * 2.0
	if not ph:
		sz = Vector2(minf(max_size.x, sz.x), minf(max_size.y, sz.y))
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = ((vp - sz) * 0.5).floor()
	root.size = sz
	var st := window_style()
	if ph:
		st.set_content_margin_all(10)
	(w["panel"] as PanelContainer).add_theme_stylebox_override("panel", st)
	(w["body"] as VBoxContainer).add_theme_constant_override("separation", 6 if ph else GAP)

## Como fit_window, pero el alto lo pone el contenido (partes, carteles): ancho
## `width` como mucho, centrada. Se llama otra vez cuando cambia el contenido.
static func fit_card(w: Dictionary, vp: Vector2, width: float) -> void:
	dodge_closes_in.call_deferred(w.get("root"))
	var root: Control = w["root"]
	var panel: PanelContainer = w["panel"]
	var ph := is_phone()
	var wd := minf(width, vp.x - (12.0 if ph else 32.0))
	var st := window_style()
	if ph:
		st.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", st)
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.size = Vector2(wd, maxf(root.size.y, 10.0))
	var hh := panel.get_combined_minimum_size().y + panel.offset_top
	var h := minf(hh, vp.y - (4.0 if ph else 24.0))
	root.size = Vector2(wd, h)
	root.position = ((vp - root.size) * 0.5).floor()

## Cambia el titulo y el color de la cinta de una ventana.
static func set_ribbon(w: Dictionary, title: String, fill: Color) -> void:
	var ribbon: PanelContainer = w["ribbon"] if w.has("ribbon") else (w["root"] as Control).get_child(1)
	ribbon.add_theme_stylebox_override("panel", ribbon_style(fill))
	var l := ribbon.get_child(0) as Label
	if l == null:
		return
	var tc := on_fill(fill)
	l.text = title
	style_label(l, "display", tc["color"], tc["outline"])
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

## Color de texto con significado sobre la superficie de `role` ("" = tenue):
## sobre crema se oscurece para leerse, sobre pizarra se aclara.
static func tone_color(tone: String, role: String = "window") -> Color:
	if tone == "":
		return text(role, true)
	var key: String = {"positive": "POSITIVE", "warning": "WARNING", "danger": "DANGER", "info": "INFO", "accent": "ACCENT"}.get(tone, "INFO")
	var col := sem(key)
	return readable(col.darkened(0.38) if kind(role) == "light" else col.lightened(0.28), role)

## Una linea con icono: [icono] frase corta. La frase envuelve.
static func icon_line(glyph: String, text_s: String, tone: String = "", role: String = "window",
		level: String = "small") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	if glyph != "":
		var ic := make_glyph(glyph, 22 if phone else 24)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	var l := label(text_s, level, tone_color(tone, role))
	l.name = "Text"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row

## Un Button de siempre (su `text` sigue siendo su texto: las pantallas lo
## cambian y las pruebas lo leen) con la piel de pastilla de pill_button y, si
## se pide, un icono a la izquierda. Se puede volver a llamar para cambiarla.
static func style_pill(btn: Button, kind_s: String = "secondary", height: int = BTN, role: String = "window",
		glyph: String = "", level: String = "button") -> Button:
	var fill := kind_fill(kind_s, role)
	var pad := 16 if btn.text != "" else 6
	_btn_states(btn, fill, int(height * 0.5), pad, role)
	var tc := on_fill(fill)
	if kind_s == "secondary":
		tc = {"color": text(role), "outline": false}
	var size := fs(level)
	btn.add_theme_font_override("font", title_font())
	btn.add_theme_font_size_override("font_size", size)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		btn.add_theme_color_override(st, tc["color"])
	btn.add_theme_color_override("font_disabled_color", Color(tc["color"], 0.65))
	btn.add_theme_constant_override("outline_size", maxi(3, roundi(size * 0.25)) if tc["outline"] else 0)
	btn.add_theme_color_override("font_outline_color", INK)
	btn.custom_minimum_size.y = height
	var old := btn.get_node_or_null("PillGlyph")
	if old != null:
		btn.remove_child(old)
		old.queue_free()
	if glyph != "":
		var px := roundi(height * 0.52)
		var ic := make_glyph(glyph, px)
		ic.name = "PillGlyph"
		btn.add_child(ic)
		if btn.text == "":
			ic.set_anchors_preset(Control.PRESET_CENTER)
			ic.offset_left = -px * 0.5
			ic.offset_right = px * 0.5
			btn.custom_minimum_size.x = maxf(btn.custom_minimum_size.x, height)
		else:
			ic.set_anchors_preset(Control.PRESET_CENTER_LEFT)
			ic.offset_left = pad
			ic.offset_right = pad + px
			for st in ["normal", "hover", "pressed", "disabled"]:
				var sb := btn.get_theme_stylebox(st)
				if sb != null:
					sb.content_margin_left = pad + px + 6
		ic.offset_top = -px * 0.5 - LIP * 0.5
		ic.offset_bottom = px * 0.5 - LIP * 0.5
	return btn

static func _army_first_label(n: Node) -> Label:
	for child in n.get_children():
		if child is Label:
			return child
		var found := _army_first_label(child)
		if found != null:
			return found
	return null

## Disco de unidad: la silueta en blanco sobre el color de su bando, con "×N"
## en una pastilla abajo a la derecha si `count` >= 0.
static func unit_disc(unit_id: String, fill: Color, d: int, count: int = -1) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(fill, INK, 3, int(d * 0.5), 3))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size = Vector2(d, d)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(make_glyph("unit:" + unit_id, int(d * 0.66)))
	p.add_child(cc)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if count < 0:
		return p
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(d + 12, d + 4)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	holder.add_child(p)
	p.size = Vector2(d, d)
	var n := PanelContainer.new()
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ns := box(WHITE, INK, 2, 10, 0)
	ns.content_margin_left = 4
	ns.content_margin_right = 4
	n.add_theme_stylebox_override("panel", ns)
	var nl := label("×%d" % count, "small", INK)
	nl.name = "Count"
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_child(nl)
	holder.add_child(n)
	n.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	n.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	n.grow_vertical = Control.GROW_DIRECTION_BEGIN
	return holder

## Una fila de discos por unidad de `roster` ({unit_id: n}), en el orden de
## GameConfig. `fill`: el color del bando.
static func roster_discs(roster: Dictionary, fill: Color, d: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	for unit_id in GameConfig.get_unit_ids():
		var n: int = int(roster.get(unit_id, 0))
		if n <= 0:
			continue
		var disc := unit_disc(String(unit_id), fill, d, n)
		disc.tooltip_text = "%d %s" % [n, Tr.t(String(GameConfig.get_unit_def(String(unit_id)).get("name", unit_id)))]
		row.add_child(disc)
	return row

## Fila de costes: [icono] cifra en huecos redondos, en rojo lo que falta. Cada
## cifra es una etiqueta "Amount_<recurso>" (como TextKit.cost_row) y la fila
## guarda "amounts" en meta. Los materiales sin icono llevan su nombre detras.
static func cost_row(amounts: Dictionary, short: Dictionary = {}, prefix: String = "", role: String = "window") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "CostRow"
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.set_meta("amounts", amounts.duplicate())
	for res_id in amounts:
		var id := String(res_id)
		var missing: int = int(short.get(id, 0))
		var chip := PanelContainer.new()
		chip.name = "Cost_" + id
		var s := well_style(role, 12, 2)
		s.content_margin_left = 4
		s.content_margin_right = 8
		if missing > 0:
			s.bg_color = Color(sem("DANGER"), 0.22)
			s.border_color = sem("DANGER")
			s.set_border_width_all(2)
		chip.add_theme_stylebox_override("panel", s)
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.tooltip_text = Tr.res_cap(id) if missing <= 0 else "%s · %s" % [Tr.res_cap(id), Tr.t("OBJ_MISSING") % ("%d" % missing)]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 3)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tex := _ArmyTextKit.res_icon(id)
		var txt := "%s%d" % [prefix, int(amounts[id])]
		if tex != null:
			var r := TextureRect.new()
			r.texture = tex
			r.custom_minimum_size = Vector2(22, 22)
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(r)
		else:
			txt += " " + Tr.res_name(id)
		var col := text(role)
		if missing > 0:
			col = tone_color("danger", role)
		var l := label(txt, "small" if phone else "number", col)
		l.name = "Amount_" + id
		h.add_child(l)
		chip.add_child(h)
		row.add_child(chip)
	return row

## Las cifras de una fila de cost_row(), {recurso: texto}: lo que ve el jugador.
static func row_amounts(row: Node) -> Dictionary:
	var out := {}
	if row == null:
		return out
	for child in row.get_children():
		if child is Label and String(child.name).begins_with("Amount_"):
			out[String(child.name).substr(7)] = (child as Label).text
		else:
			out.merge(row_amounts(child))
	return out

## El recorrido de una campana: hechas (✓ verde), la que toca (★ laton), las que
## faltan (su numero) y el jefe al final (bomba roja). `compact`: telefono.
static func campaign_track(won: int, total: int, compact: bool, boss_tip: String = "") -> HBoxContainer:
	var track := HBoxContainer.new()
	track.name = "CampaignTrack"
	track.add_theme_constant_override("separation", 0)
	track.alignment = BoxContainer.ALIGNMENT_CENTER
	track.mouse_filter = Control.MOUSE_FILTER_PASS
	for i in total:
		var state := "next"
		if i < won:
			state = "done"
		elif i == total - 1:
			state = "boss"
		elif i == won:
			state = "now"
		var big := state in ["now", "boss"]
		var dd := (34 if big else 26) if compact else (46 if big else 36)
		var fill: Color = c("window", "WELL")
		match state:
			"done":
				fill = sem("POSITIVE")
			"now":
				fill = sem("ACCENT")
			"boss":
				fill = sem("DANGER")
		var node := PanelContainer.new()
		node.name = "Mission_%d" % i
		var st := box(fill, INK, 3, int(dd * 0.5), 0)
		if state == "boss" and i == won:
			st.border_color = sem("ACCENT")
			st.set_border_width_all(4)
		node.add_theme_stylebox_override("panel", st)
		node.custom_minimum_size = Vector2(dd, dd)
		node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		node.mouse_filter = Control.MOUSE_FILTER_PASS
		node.set_meta("state", state)
		var cc := CenterContainer.new()
		cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var g: String = {"done": "check", "now": "star", "boss": "demolish"}.get(state, "")
		if g != "":
			cc.add_child(make_glyph(g, int(dd * 0.6), WHITE if state == "done" else Color(0, 0, 0, 0)))
		else:
			cc.add_child(label(str(i + 1), "small", text("window", true)))
		node.add_child(cc)
		if state == "boss" and boss_tip != "":
			node.tooltip_text = boss_tip
		track.add_child(node)
		if i < total - 1:
			var line := Panel.new()
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.custom_minimum_size = Vector2(12 if compact else 30, 7)
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_theme_stylebox_override("panel", box(sem("POSITIVE") if i < won else c("window", "WELL"), INK, 2, 3, 0))
			track.add_child(line)
	return track

## Etiqueta de pronostico: Favorable (verde), Igualada (ambar), Dificil (rojo);
## "" = sin tropa elegida todavia (gris).
static func odds_badge(odds: String, text_s: String) -> PanelContainer:
	var fill: Color = kind_fill("disabled")
	match odds:
		"favorable":
			fill = sem("POSITIVE")
		"even":
			fill = sem("WARNING")
		"hard":
			fill = sem("DANGER")
	var b := badge(text_s, fill)
	b.name = "OddsLabel"
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	return b

## El sello de los partes (COBRADO / REPELIDO): pastilla de color algo girada,
## sin animacion. Guarda su texto en meta "stamp_text".
static func stamp(text_s: String, fill: Color) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(0, 50 if phone else 60)
	var p := PanelContainer.new()
	var s := box(fill, INK, BORDER + 1, 14, 0, 0, 3)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 2
	s.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tc := on_fill(fill)
	var l := label(text_s, "title", tc["color"], tc["outline"])
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	holder.add_child(p)
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.rotation = deg_to_rad(-6.0)
	p.resized.connect(func(): p.pivot_offset = p.size * 0.5)
	holder.set_meta("stamp_text", text_s)
	return holder

## Tarjeta-boton (las mejoras del draft): un Button de texto con piel de
## tarjeta; encima, borde de laton.
static func army_card_button(btn: Button, role: String = "window") -> Button:
	var n := card_style(role)
	var h := card_style(role, true)
	var p := card_style(role, true, c(role, "CARD_ALT"))
	for sb in [n, h, p]:
		sb.set_content_margin_all(12)
	btn.add_theme_stylebox_override("normal", n)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", p)
	btn.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), sem("ACCENT"), 3, RADIUS_CARD + 2, 0))
	btn.add_theme_font_override("font", title_font())
	btn.add_theme_font_size_override("font_size", fs("button"))
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(st, text(role))
	btn.add_theme_constant_override("outline_size", 0)
	return btn


# --- MENÚS (feat/ui2-menus) ---------------------------------------------
# Piezas de las pantallas de menu de la fase 2 (Ajustes, Ayuda, tutorial,
# menu principal, partidas, victoria, prologo, registro). Solo se anaden:
# las de arriba son de la fase 1 y de los otros frentes.

## Coloca la raiz de una ventana (`window()["root"]`): en telefono a pantalla
## completa con un margen corto; si no, centrada con un tope `max_size`. Con
## anclas, para que siga al lienzo si cambia de tamano.
static func place_window(root: Control, vp: Vector2, max_size: Vector2, small: bool = false) -> void:
	dodge_closes_in.call_deferred(root)
	var margin := Vector2(6, 4) if small else Vector2(24, 16)
	var sz := Vector2(minf(max_size.x, vp.x - margin.x * 2.0), minf(max_size.y, vp.y - margin.y * 2.0))
	if small:
		sz = vp - margin * 2.0
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.offset_left = -roundf(sz.x * 0.5)
	root.offset_right = roundf(sz.x * 0.5)
	root.offset_top = -roundf(sz.y * 0.5)
	root.offset_bottom = roundf(sz.y * 0.5)

## La ventana de menu entera: `window()` + el margen corto del telefono.
## Devuelve lo mismo que window() ({"root", "body", "close", "panel"}).
static func menu_window(title: String, fill: Color, small: bool, with_close: bool = true) -> Dictionary:
	var w := window(title, fill, with_close)
	var body: VBoxContainer = w["body"]
	body.add_theme_constant_override("separation", 6 if small else GAP)
	if small:
		var s := window_style()
		s.set_content_margin_all(10)
		(w["panel"] as PanelContainer).add_theme_stylebox_override("panel", s)
	return w

## Fila grande de Ajustes: [icono] Nombre ······ control [valor]. La tarjeta
## lleva el nombre de la fila (las pruebas la buscan por el).
static func setting_row(row_name: String, glyph: String, text_s: String, control: Control,
		small: bool = false, value: Label = null, tip: String = "") -> PanelContainer:
	var card := PanelContainer.new()
	card.name = row_name
	var st := card_style("window")
	st.set_content_margin_all(4 if small else 10)
	st.content_margin_left = 8 if small else 14
	card.add_theme_stylebox_override("panel", st)
	card.tooltip_text = tip
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8 if small else 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Telefono en vertical: el selector baja bajo su nombre (en 400 px de ancho
	# no cabian los dos en una fila y se salian por la derecha).
	var stacked := portrait() and not (control is CheckButton)
	var outer: VBoxContainer = null
	if stacked:
		outer = VBoxContainer.new()
		outer.add_theme_constant_override("separation", 4)
		outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outer.add_child(row)
	if glyph != "":
		var ic := make_glyph(glyph, 26 if small else 34, sem("INFO"))
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	var l := label(text_s, "button", text("window"))
	l.custom_minimum_size.x = 96 if small else 190
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not (control is HSlider):
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if control is HSlider:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var holder: BoxContainer = row
	if stacked:
		holder = HBoxContainer.new()
		holder.alignment = BoxContainer.ALIGNMENT_END
		holder.add_theme_constant_override("separation", 8)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outer.add_child(holder)
	holder.add_child(control)
	if value != null:
		value.custom_minimum_size.x = 44 if small else 58
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		holder.add_child(value)
	card.add_child(outer if stacked else row)
	return card

## Telefono en vertical (lienzo estrecho y alto): las piezas que van en fila en
## apaisado se apilan.
static func portrait() -> bool:
	return phone and UILayoutManager != null and UILayoutManager.is_narrow()

## Interruptor que se pulsa de verdad (CheckButton con el carril dibujado:
## verde encendido, bolita blanca). Sin texto: el nombre va en la fila.
static func live_switch(on: bool, on_toggled: Callable = Callable(), node_name: String = "") -> CheckButton:
	var b := CheckButton.new()
	if node_name != "":
		b.name = node_name
	b.text = ""
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_icon_override("checked", switch_texture(true, false))
	b.add_theme_icon_override("unchecked", switch_texture(false, false))
	b.add_theme_icon_override("checked_disabled", switch_texture(true, true))
	b.add_theme_icon_override("unchecked_disabled", switch_texture(false, true))
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(st, empty)
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), sem("ACCENT"), 3, 24, 0))
	b.custom_minimum_size = Vector2(84, TOUCH_MIN)
	if on_toggled.is_valid():
		b.toggled.connect(on_toggled)
	return b

static var _switch_tex := {}
## El carril del interruptor (76x40) con su bolita, en textura: CheckButton
## pinta iconos. Se dibuja una vez por estado.
static func switch_texture(on: bool, disabled: bool) -> Texture2D:
	var key := "%s|%s|%s|%s|%s|%s" % [on, disabled, UITheme.palette, UITheme.high_contrast, surface, window_theme]
	if _switch_tex.has(key):
		return _switch_tex[key]
	var w := 76
	var hh := 40
	var img := Image.create(w, hh, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var fill: Color = sem("POSITIVE") if on else c("window", "WELL")
	if disabled:
		fill = fill.lerp(Color(0.6, 0.6, 0.6), 0.6)
	var ink := INK if not disabled else Color(INK, 0.5)
	var r := hh * 0.5
	var bw := 3.0
	var knob_c := Vector2(w - r, r) if on else Vector2(r, r)
	var knob_r := r - 6.0
	for y in hh:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			# Distancia a la capsula (segmento entre los dos centros).
			var cx := clampf(p.x, r, w - r)
			var d := p.distance_to(Vector2(cx, r))
			var col := Color(0, 0, 0, 0)
			if d <= r - bw:
				col = fill
			elif d <= r - 0.5:
				col = ink
			elif d <= r:
				col = Color(ink, r - d)
			var dk := p.distance_to(knob_c)
			if dk <= knob_r - 2.0:
				col = WHITE
			elif dk <= knob_r:
				col = ink
			img.set_pixel(x, y, col)
	var t := ImageTexture.create_from_image(img)
	_switch_tex[key] = t
	return t

## Deslizador de Ajustes con su nombre de nodo, paso y rango.
static func menu_slider(node_name: String, value: float, min_v: float = 0.0, max_v: float = 1.0,
		step: float = 0.05) -> HSlider:
	var sl := slider(value)
	sl.name = node_name
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step
	sl.value = value
	sl.custom_minimum_size = Vector2(120, TOUCH_MIN)
	# La rueda desplaza la pestana, nunca mueve el regulador.
	sl.scrollable = false
	return sl

## Un selector (CartoonPicker): pastillas o paso a paso segun quepan.
static func picker(options: Array, selected: int, on_selected: Callable = Callable(),
		height: int = 48, tips: Array = []) -> HBoxContainer:
	var p: HBoxContainer = load("res://scripts/ui/CartoonPicker.gd").new()
	p.name = "Picker"
	p.call("setup", options, selected, height, "window", false, tips)
	if on_selected.is_valid():
		p.connect("item_selected", on_selected)
	return p

## Titulo pequeno de un grupo dentro de una ventana ("Avanzado").
static func group_title(text_s: String) -> Label:
	var l := label(text_s, "small", text("window", true))
	l.uppercase = true
	return l

## Tarjeta-boton de una lista (indice de ayuda, partidas, menu principal):
## [icono] Texto  ······  [marca]. `mark`: id de icono a la derecha ("" nada).
static func list_button(glyph: String, text_s: String, small: bool = false, mark: String = "",
		dim: bool = false) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	var hgt := 48 if small else 56
	var n := card_style("window")
	var hv := card_style("window")
	hv.bg_color = c("window", "CARD").darkened(0.04)
	hv.border_color = sem("INFO")
	var pr := card_style("window")
	pr.bg_color = c("window", "CARD_ALT")
	for sb in [n, hv, pr]:
		sb.set_content_margin_all(4)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), sem("ACCENT"), 3, RADIUS_CARD + 2, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if glyph != "":
		var ic := make_glyph(glyph, 26 if small else 32, sem("INFO"))
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
	var l := label(text_s, "button", text("window", dim))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	row.add_child(l)
	if mark != "":
		var m := make_glyph(mark, 22 if small else 26)
		m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(m)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -12
	b.add_child(row)
	b.custom_minimum_size = Vector2(0, hgt)
	b.set_meta("label", l)
	return b

## El contorno grueso de lo que se dibuja sobre la superficie de `role`
## (bocadillo, piquito): tinta sobre lo claro, el borde de color sobre lo oscuro.
static func edge(role: String = "window") -> Color:
	return INK if kind(role) == "light" else c(role, "BORDER")

## El bocadillo del instructor (tutorial, consejos): el fondo de las ventanas
## con su contorno (tinta en Claro, el borde azul en Oscuro).
static func bubble_style(small: bool = false) -> StyleBoxFlat:
	var s := box(c("window", "BG"), edge("window"), BORDER, RADIUS_CARD, 10 if small else 14, 0, 2)
	s.shadow_color = Color(INK, 0.35)
	s.shadow_size = 1
	s.shadow_offset = Vector2(0, 4)
	return s

## Pastilla del "Paso 3 de 9" del tutorial.
static func step_pill(text_s: String) -> PanelContainer:
	return badge(text_s, sem("ACCENT"))

## El piquito del bocadillo hacia el instructor. `side`: -1 sale por la
## izquierda de la tarjeta, 1 por la derecha, 0 oculto. Se coloca a mano.
class Tail extends Control:
	var side := -1:
		set(v):
			side = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(18, 26)
		size = custom_minimum_size

	func _draw() -> void:
		if side == 0:
			return
		var w := size.x
		var hh := size.y
		var pts: PackedVector2Array
		if side < 0:
			pts = PackedVector2Array([Vector2(w + 3, 0), Vector2(0, hh * 0.5), Vector2(w + 3, hh)])
		else:
			pts = PackedVector2Array([Vector2(-3, 0), Vector2(w, hh * 0.5), Vector2(-3, hh)])
		draw_colored_polygon(pts, CartoonTheme.c("window", "BG"))
		draw_polyline(pts, CartoonTheme.edge("window"), 3.0, true)

## Pastilla con su texto guardado en la meta "text" (Button.text va vacio: lo
## pinta una etiqueta). Las pruebas y las sondas buscan los botones por ella.
static func text_button(text_s: String, glyph: String = "", kind_s: String = "secondary",
		height: int = BTN, level: String = "button") -> Button:
	var b := pill_button(text_s, glyph, kind_s, height, "window", level)
	b.set_meta("text", text_s)
	b.tooltip_text = text_s if glyph != "" and text_s == "" else b.tooltip_text
	return b

## Alto de boton de las pantallas de menu: el de h(), sin bajar del alto de
## dedo que pidan Ajustes (UITheme.MIN_BTN_H, que sube en tablet y movil).
static func menu_h(size_s: String) -> int:
	return maxi(h(size_s), UITheme.MIN_BTN_H)

## El texto de un boton: su meta "text" (pastillas) o Button.text.
static func button_text(b: Button) -> String:
	if b == null:
		return ""
	if b.has_meta("text"):
		return String(b.get_meta("text"))
	if b.text != "":
		return b.text
	# pill_button: el texto vive en una etiqueta hija.
	for n in b.find_children("*", "Label", true, false):
		return (n as Label).text
	return ""

## Coloca el piquito (`Tail`) del bocadillo `card` hacia el instructor `bust`
## (los dos en el mismo lienzo). Sin busto a la vista, o con el busto encima o
## debajo de la tarjeta, el piquito se esconde.
static func place_tail(tail: Control, card: Rect2, bust: Control) -> void:
	if tail == null:
		return
	if bust == null or not bust.visible or card.size.x < 1.0:
		tail.visible = false
		return
	var b := Rect2(bust.position, bust.size)
	var side := 0
	if b.end.x <= card.position.x + 4.0:
		side = -1
	elif b.position.x >= card.end.x - 4.0:
		side = 1
	if side == 0:
		tail.visible = false
		return
	tail.visible = true
	tail.set("side", side)
	var ty := clampf(b.get_center().y - tail.size.y * 0.5, card.position.y + 10.0, card.end.y - tail.size.y - 10.0)
	var tx := card.position.x - tail.size.x + 1.0 if side < 0 else card.end.x - 1.0
	tail.position = Vector2(tx, ty)

# --- REJILLAS DE PIEZAS (integracion/ui-v2, 2026-10-19) -------------------
# Las muestras de color, fondos, emblemas y pinturas: la pieza arriba, entera y
# sin nada pintado encima; si esta cerrada, debajo una placa clara con el
# candado y el rango. El boton mide lo que su contenido (nunca se corta).

## Placa pequena "candado + N" (rango que abre la pieza), clara y legible.
static func rank_plate(rank: int) -> PanelContainer:
	var plate := PanelContainer.new()
	plate.name = "RankLock"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := box(c("window", "CARD"), c("window", "CARD_BORDER"), 2, 8, 2)
	st.content_margin_left = 6
	st.content_margin_right = 6
	plate.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(row)
	var lock := make_glyph("lock", 14 if phone else 16, text("window"))
	lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lock)
	var l := label(str(rank), "small", text("window"))
	l.name = "RankLockLabel"
	row.add_child(l)
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return plate

## Mete `content` en el boton con `pad` de margen y hace que el boton mida lo
## que el contenido pida (y lo siga si cambia).
static func fit_button_content(btn: Button, content: Control, pad: float = 5.0) -> void:
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = pad
	content.offset_top = pad
	content.offset_right = -pad
	content.offset_bottom = -pad
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(content)
	var fit := func():
		if is_instance_valid(btn) and is_instance_valid(content):
			btn.custom_minimum_size = content.get_combined_minimum_size() + Vector2(pad, pad) * 2.0
	content.minimum_size_changed.connect(fit)
	fit.call()

## Relleno de una tarjeta de pieza. La cerrada va hundida: en Claro el hueco
## (WELL); en Oscuro CARD_ALT, porque el hueco casi negro se comia las muestras
## a media luz.
static func pick_fill(enabled: bool) -> Color:
	if enabled:
		return c("window", "CARD")
	return c("window", "WELL") if kind("window") == "light" else c("window", "CARD_ALT")

## Estilo de una tarjeta de pieza: elegida con borde grueso de laton; cerrada,
## apagada (relleno hundido).
static func pick_style(selected: bool, enabled: bool) -> StyleBoxFlat:
	var fill := pick_fill(enabled)
	var st := box(fill, sem("ACCENT") if selected else c("window", "CARD_BORDER"),
		5 if selected else 2, 12, 4, 0, 0, "window")
	if selected:
		st.shadow_color = Color(sem("ACCENT"), 0.5)
		st.shadow_size = 4
	return st

# --- BANDERA (feat/ui3-bandera) -------------------------------------------
# Las fichas de las rejillas de PAIS Y BANDERA y de REGIMIENTO, todas del mismo
# tamano en una rejilla: la pieza arriba (entera, sin nada pintado encima) y
# debajo la placa del rango (cerrada) o la de "no se leeria"
# (abierta pero no vale aqui); la abierta llena la ficha. Del mismo ancho, para que
# abiertas y cerradas midan igual y ninguna fila salga desigual o cortada.

const PIECE_PAD := 4.0

## Ficha de pieza. `content` es la muestra / miniatura (crece hasta llenar).
## `lock_rank` > 0: cerrada hasta ese rango. `unreadable`: abierta pero no se
## leeria en esa casilla. El boton lleva "selected" y "lock_rank" en meta, y
## su caja (VBox "Box") la pieza y, si hace falta, la placa ("RankLock" o
## "Unreadable").
static func piece_tile(content: Control, selected: bool, enabled: bool, lock_rank: int = 0,
		unreadable: bool = false) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.disabled = not enabled
	var st := pick_style(selected, enabled)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(state, st)
	btn.set_meta("selected", selected)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 3)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(content)
	var strip: PanelContainer
	if lock_rank > 0:
		strip = piece_plate("lock", str(lock_rank))
		strip.name = "RankLock"
		btn.set_meta("lock_rank", lock_rank)
	elif unreadable:
		strip = piece_plate("ban", "")
		strip.name = "Unreadable"
	if strip != null:
		box.add_child(strip)
	else:
		# Abierta: la pieza llena la ficha (la fila de HFlow le da el alto de
		# las cerradas); de ancho, al menos el de una placa, para que casen.
		# Se mide una placa invisible ya en el arbol (fuera de el no mide bien).
		var probe := piece_plate("lock", "")
		probe.name = "PlateWidth"
		probe.modulate.a = 0.0
		btn.add_child(probe)
		var sync := func():
			if is_instance_valid(probe) and is_instance_valid(box):
				box.custom_minimum_size.x = probe.get_combined_minimum_size().x
		probe.minimum_size_changed.connect(sync)
		sync.call()
	fit_button_content(btn, box, PIECE_PAD)
	return btn

## La placa pequena de debajo: [candado] N, o el simbolo de prohibido. Todas
## del mismo ancho (el de "88") y alto, para que las fichas casen.
static func piece_plate(icon: String, text_s: String) -> PanelContainer:
	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var st := box(c("window", "CARD"), c("window", "CARD_BORDER"), 1, 7, 1)
	st.content_margin_left = 4
	st.content_margin_right = 4
	plate.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(row)
	var px := 12 if phone else 14
	var ic: Control = make_glyph("lock", px, text("window")) if icon == "lock" else none_icon(px, sem("DANGER"))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var l := label(text_s, "small", text("window"))
	l.name = "RankLockLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var f := l.get_theme_font("font")
	if f != null:
		# Ancho de "88" y alto de una linea aunque no lleve texto.
		l.custom_minimum_size = Vector2(ceilf(f.get_string_size("88", HORIZONTAL_ALIGNMENT_LEFT, -1, fs("small")).x),
			ceilf(f.get_height(fs("small"))))
	row.add_child(l)
	if icon != "lock":
		# Solo el simbolo, centrado en el mismo hueco que "[candado] N".
		l.visible = false
		ic.custom_minimum_size = Vector2(px + 2 + l.custom_minimum_size.x, l.custom_minimum_size.y)
	return plate

## "Ninguno" / "no vale": un aro con su barra (el simbolo de prohibido), dibujado.
static func none_icon(px: int, tint: Color = Color(0, 0, 0, 0)) -> Control:
	var ic := Control.new()
	ic.name = "NoneIcon"
	ic.custom_minimum_size = Vector2(px, px)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := tint if tint.a > 0.0 else text("window", true)
	ic.draw.connect(func():
		var s := minf(ic.size.x, ic.size.y)
		var ctr := ic.size * 0.5
		var r := s * 0.4
		var w := maxf(2.0, s * 0.13)
		ic.draw_arc(ctr, r, 0.0, TAU, 28, col, w, true)
		var d := Vector2(r, -r).normalized() * r
		ic.draw_line(ctr - d, ctr + d, col, w, true))
	return ic

## La pieza "ninguno" (sin emblema): un hueco hundido con el simbolo, en vez
## de una muestra vacia o una raya.
static func none_piece(min_size: Vector2) -> Control:
	var well := PanelContainer.new()
	well.name = "NonePiece"
	well.custom_minimum_size = min_size
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_theme_stylebox_override("panel", well_style("window", 8, 2))
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(center)
	center.add_child(none_icon(int(minf(min_size.x, min_size.y) * 0.7)))
	return well

## Una muestra de color para una ficha; apagada se ve su color, mas gris, opaca.
static func piece_swatch(col: Color, min_size: Vector2, dim: bool) -> ColorRect:
	var sw := ColorRect.new()
	sw.name = "Swatch"
	sw.custom_minimum_size = min_size
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sw.color = col.lerp(Color(0.6, 0.58, 0.55), 0.45) if dim else col
	# Un color que se funde con la tarjeta (negro o azul marino en el tema
	# oscuro, crema en el claro) lleva un borde fino del color del texto.
	if UITheme.contrast_ratio(sw.color, c("window", "CARD")) < 1.6:
		var edge_box := Panel.new()
		edge_box.name = "SwatchEdge"
		edge_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		edge_box.set_anchors_preset(Control.PRESET_FULL_RECT)
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0, 0, 0, 0)
		st.border_color = Color(text("window", true), 0.85)
		st.set_border_width_all(2)
		edge_box.add_theme_stylebox_override("panel", st)
		sw.add_child(edge_box)
	return sw

# --- CONSTRUIR3 (feat/ui3-construir) ---
# Nombres de edificio siempre enteros y legibles, la zona segura del telefono
# y la X de las ventanas grandes fuera de debajo del boton ☰ (capa 30).

## Tamano minimo de un nombre de edificio: 16 dp en telefono (docs/28 §3.1,
## Bryan 2026-10-19: "no se ven bien los nombres"), 18 en tablet y PC.
const NAME_MIN_PHONE := 16
const NAME_MIN := 18

## Tamano de letra de un nombre en `level` (nunca por debajo del minimo).
static func name_size(level: String = "button") -> int:
	return maxi(fs(level), NAME_MIN_PHONE if phone else NAME_MIN)

## Un nombre de edificio (o un porque que lleva uno: "Falta Almacén"): Baloo 2,
## en el color normal del texto (nunca el tenue: contraste), y que pasa a la
## linea siguiente antes que cortarse con "…".
static func name_label(text_s: String, level: String = "button", role: String = "window",
		color: Color = Color(0, 0, 0, 0)) -> Label:
	var l := label(text_s, level, color if color.a > 0.0 else text(role))
	l.add_theme_font_override("font", title_font())
	l.add_theme_font_size_override("font_size", name_size(level))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.clip_text = false
	l.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	return l

## La zona segura (muesca, esquinas, barra de gestos) en pixeles del lienzo:
## {"left", "top", "right", "bottom"}. Cero fuera del movil.
static func safe_insets(vp: Viewport) -> Dictionary:
	var out := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	if vp == null or not OS.has_feature("mobile"):
		return out
	var win := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if win.x <= 0.0 or win.y <= 0.0 or safe.size.x <= 0.0:
		return out
	var k := vp.get_visible_rect().size / win
	out["left"] = maxf(0.0, safe.position.x * k.x)
	out["top"] = maxf(0.0, safe.position.y * k.y)
	out["right"] = maxf(0.0, (win.x - safe.end.x) * k.x)
	out["bottom"] = maxf(0.0, (win.y - safe.end.y) * k.y)
	return out

## El boton ☰ (capa 30, arriba a la derecha) se dibuja encima de cualquier
## ventana: si tapa la X de `close`, la X se corre a su izquierda. Se puede
## llamar cada vez que se recoloca la ventana: deshace el corrimiento anterior.
## Diferido por quien lo llame si la ventana se acaba de colocar.
static func dodge_menu_button(close: Control, gap: float = 8.0) -> void:
	if close == null or not is_instance_valid(close) or not close.is_inside_tree():
		return
	# Se deshace el corrimiento anterior solo si nadie ha recolocado la X desde
	# entonces (fit_desktop / fit_fullscreen ponen sus offsets de nuevo).
	var prev: float = float(close.get_meta("dodge_shift", 0.0))
	if prev != 0.0 and is_equal_approx(close.offset_left, float(close.get_meta("dodge_at", INF))):
		close.offset_left += prev
		close.offset_right += prev
	close.set_meta("dodge_shift", 0.0)
	var btn: Control = null
	for n in close.get_tree().get_nodes_in_group("hud_menu_button"):
		if n is Control and is_instance_valid(n) and (n as Control).is_visible_in_tree():
			btn = n
			break
	var r := close.get_global_rect()
	var shift := 0.0
	# Nunca fuera de la pantalla por la derecha (la X sobresale de su ventana).
	var vp_w: float = close.get_viewport().get_visible_rect().size.x
	if r.end.x > vp_w - 4.0:
		shift = r.end.x - (vp_w - 4.0)
	# Y nunca debajo del ☰ (si la ventana esta por debajo de su capa).
	if btn != null:
		var b := btn.get_global_rect().grow(gap)
		var layer_ok := true
		var btn_layer := btn.get_parent()
		while btn_layer != null and not (btn_layer is CanvasLayer):
			btn_layer = btn_layer.get_parent()
		var close_layer: Node = close.get_parent()
		while close_layer != null and not (close_layer is CanvasLayer):
			close_layer = close_layer.get_parent()
		if btn_layer is CanvasLayer and close_layer is CanvasLayer:
			layer_ok = (close_layer as CanvasLayer).layer <= (btn_layer as CanvasLayer).layer
		if layer_ok and r.intersects(b):
			shift = maxf(shift, r.end.x - b.position.x)
	if shift <= 0.0:
		return
	close.offset_left -= shift
	close.offset_right -= shift
	close.set_meta("dodge_shift", shift)
	close.set_meta("dodge_at", close.offset_left)

## Aparta del ☰ (y del borde) las X de ventana que cuelgan de `root`. Lo llaman
## en diferido las funciones que colocan ventanas (fit_*, place_window).
static func dodge_closes_in(root: Variant) -> void:
	if not is_instance_valid(root) or not (root is Control) or not (root as Control).is_inside_tree():
		return
	for n in (root as Control).get_tree().get_nodes_in_group("window_close"):
		if n is Control and (root as Control).is_ancestor_of(n) and (n as Control).is_visible_in_tree():
			dodge_menu_button(n as Control)
