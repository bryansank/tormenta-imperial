extends PanelContainer
## La ficha de una unidad (docs/15 §3 "Ensenar el combate", doc de diseno 21 §4.2).
## La misma en el tablero (tocar una pieza, en las dos vistas y en el 2D) y en el
## Cuartel (ArmyPanel, boton FICHA). Iconos y numeros primero, frases despues:
##
##   [silueta] INFANTERIA            80/100
##   [corazon] 100  [espada] 8  [escudo] 2
##   [pies] Mueve 3   [diana] Ataca a 1 casilla
##   [✕] No dispara a quien tiene al lado           (solo artilleria)
##   [▲] Fuerte contra: [silueta] Artilleria
##       (pega 1,5 veces más)
##   [▼] Debil contra:  [silueta] Blindado
##       (pega más flojo)
##   "Barata y rapida. Asalta los canones antes de que disparen."
##
## Nada se escribe a mano: los numeros salen de GameConfig.combat_unit_stats y
## combat_type_advantage, o de la unidad viva (con sus mejoras y su moral) si se
## pasa una. Los iconos se dibujan aqui (StatGlyph): no dependen de que la fuente
## tenga emojis, que en Android y en la fuente del juego no esta garantizado.

signal closed()

const ICON_PX := 42
const GLYPH_PX := 22

var _unit_id := ""
var _unit = null      ## CombatUnit o null (la ficha del tipo, sin vida actual)
var _closable := false

## Monta la ficha. `unit`: la pieza del tablero (vida actual, mejoras), o null.
## `closable`: pone una ✕ arriba a la derecha que emite `closed`.
func setup(unit_id: String, unit = null, closable := false) -> void:
	_unit_id = unit_id
	_unit = unit
	_closable = closable
	name = "UnitCard"
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UITheme.make_hud_card_style(UITheme.CAT_MILITARY, 2, true))
	# Fuera del arbol ya: con queue_free solo, la ficha vieja y la nueva sumaban
	# su alto un fotograma y el panel crecia sin encoger (ronda de pruebas 1.0).
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build()

func unit_id() -> String:
	return _unit_id

# ── Datos (estaticos: las pruebas los leen sin montar nada) ──────────

## A quien pega `unit_id` con ventaja (combat_type_advantage.beats).
static func strong_against(unit_id: String) -> Array:
	var beats: Dictionary = GameConfig.combat_type_advantage.get("beats", {})
	return (beats.get(unit_id, []) as Array).duplicate()

## Quien le pega a `unit_id` con ventaja: la desventaja es la ventaja al reves.
static func weak_against(unit_id: String) -> Array:
	var out: Array = []
	var beats: Dictionary = GameConfig.combat_type_advantage.get("beats", {})
	for other in beats:
		if (beats[other] as Array).has(unit_id) and String(other) != unit_id:
			out.append(String(other))
	return out

## Los numeros de la ficha. Con `unit`, los de esa pieza (ataque con moral y
## mejoras, defensa sin la guardia de este turno); sin ella, los de la tabla.
static func stat_values(unit_id: String, unit = null) -> Dictionary:
	var s: Dictionary = GameConfig.get_combat_stats(unit_id)
	var out := {
		"hp": int(s.get("hp", 0)),
		"max_hp": int(s.get("hp", 0)),
		"atk": int(s.get("atk", 0)),
		"def": int(s.get("def", 0)),
		"move": int(s.get("move", 0)),
		"range": maxi(1, int(s.get("range", 1))),
		"min_range": maxi(1, int(s.get("min_range", 1))),
	}
	if unit != null:
		out["hp"] = unit.hp
		out["max_hp"] = unit.max_hp
		out["atk"] = unit.attack_power()
		# La guardia de este turno no es de la unidad: la ficha da su defensa normal.
		out["def"] = int(unit.defense() / 2) if unit.defending else unit.defense()
		out["move"] = unit.move_range()
		out["range"] = unit.attack_range()
		out["min_range"] = unit.min_range()
	return out

## "Ataca a 1 casilla" / "Ataca hasta 3 casillas" / "Dispara de 2 a 3 casillas".
static func range_text(lo: int, hi: int) -> String:
	if lo > 1:
		return Tr.t("LBL_CARD_RANGE_MIN") % [lo, hi]
	if hi <= 1:
		return Tr.t("LBL_CARD_RANGE_ONE")
	return Tr.t("LBL_CARD_RANGE") % hi

## "×1,5" en espanol, "×1.5" en ingles.
static func mult_text(mult: float) -> String:
	var m := String.num(mult, 2)
	if Tr.get_locale() == "es":
		m = m.replace(".", ",")
	return "×" + m

static func _names(ids: Array) -> String:
	var parts: PackedStringArray = []
	for id in ids:
		parts.append(unit_name(String(id)))
	return ", ".join(parts)

static func unit_name(unit_id: String) -> String:
	return Tr.t(String(GameConfig.get_unit_def(unit_id).get("name", unit_id)))

## La ficha en lineas de texto, en el orden en que se ven. Para las pruebas y
## para el tooltip con raton.
static func summary_lines(unit_id: String, unit = null) -> Array:
	var v := stat_values(unit_id, unit)
	var lines: Array = []
	lines.append(unit_name(unit_id).to_upper())
	lines.append("%s %d · %s %d · %s %d" % [Tr.t("LBL_CARD_HP"), v["max_hp"], Tr.t("LBL_CARD_ATK"), v["atk"], Tr.t("LBL_CARD_DEF"), v["def"]])
	lines.append("%s · %s" % [Tr.t("LBL_CARD_MOVE") % v["move"], range_text(v["min_range"], v["range"])])
	if int(v["min_range"]) > 1:
		lines.append(Tr.t("LBL_CARD_TOO_CLOSE"))
	var strong := strong_against(unit_id)
	if not strong.is_empty():
		lines.append("%s %s" % [Tr.t("LBL_CARD_STRONG"), _names(strong)])
	var weak := weak_against(unit_id)
	if not weak.is_empty():
		lines.append("%s %s" % [Tr.t("LBL_CARD_WEAK"), _names(weak)])
	return lines

# ── Construccion ─────────────────────────────────────────────────────

func _build() -> void:
	var v := stat_values(_unit_id, _unit)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)

	# Cabecera: silueta, nombre, vida actual y la ✕.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var icon := TextureRect.new()
	icon.texture = UITheme.unit_icon(_unit_id, ICON_PX)
	icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var enemy: bool = _unit != null and int(_unit.side) == 1
	icon.modulate = UITheme.unit_icon_tint(not enemy)
	head.add_child(icon)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 0)
	head.add_child(names)
	var title := UITheme.make_label(unit_name(_unit_id).to_upper(), "section", UITheme.TEXT_BRIGHT)
	title.name = "CardTitle"
	names.add_child(title)
	if _unit != null:
		var who := Tr.t("LBL_CARD_ENEMY") if enemy else Tr.t("LBL_CARD_OURS")
		var sub := UITheme.make_label("%s · %d/%d" % [who, v["hp"], v["max_hp"]], "small",
			UITheme.DANGER.lightened(0.3) if enemy else UITheme.POSITIVE.lightened(0.3))
		sub.name = "CardHp"
		names.add_child(sub)
	if _closable:
		var x := Button.new()
		x.name = "CardClose"
		x.text = "✕"
		x.focus_mode = Control.FOCUS_NONE
		x.custom_minimum_size = Vector2(UITheme.MIN_BTN_H, UITheme.MIN_BTN_H)
		UITheme.style_button(x, UITheme.BTN, UITheme.FONT_BUTTON)
		x.pressed.connect(func(): closed.emit())
		head.add_child(x)

	# Numeros: vida, ataque, defensa.
	var nums := HFlowContainer.new()
	nums.name = "CardNumbers"
	nums.add_theme_constant_override("h_separation", 16)
	col.add_child(nums)
	nums.add_child(_stat("hp", str(v["max_hp"]), Tr.t("LBL_CARD_HP_TIP")))
	nums.add_child(_stat("atk", str(v["atk"]), Tr.t("LBL_CARD_ATK_TIP")))
	nums.add_child(_stat("def", str(v["def"]), Tr.t("LBL_CARD_DEF_TIP")))

	# Moverse y alcance.
	var reach := HFlowContainer.new()
	reach.name = "CardReach"
	reach.add_theme_constant_override("h_separation", 16)
	col.add_child(reach)
	var move_box := HBoxContainer.new()
	move_box.add_theme_constant_override("separation", 4)
	move_box.add_child(UITheme.make_icon("move", GLYPH_PX))
	move_box.add_child(UITheme.make_label(Tr.t("LBL_CARD_MOVE") % v["move"], "body", UITheme.TEXT))
	reach.add_child(move_box)
	reach.add_child(_stat("range", range_text(v["min_range"], v["range"]), ""))
	if int(v["min_range"]) > 1:
		col.add_child(_stat("nofire", Tr.t("LBL_CARD_TOO_CLOSE"), "", UITheme.WARNING))

	# Ventaja por tipo.
	var adv := float(GameConfig.combat_type_advantage.get("advantage", 1.0))
	var dis := float(GameConfig.combat_type_advantage.get("disadvantage", 1.0))
	var strong := strong_against(_unit_id)
	if not strong.is_empty():
		col.add_child(_matchup_row("good", Tr.t("LBL_CARD_STRONG"), strong, mult_words(true, adv), UITheme.POSITIVE))
	var weak := weak_against(_unit_id)
	if not weak.is_empty():
		col.add_child(_matchup_row("bad", Tr.t("LBL_CARD_WEAK"), weak, mult_words(false, dis), UITheme.WARNING))

	# Una frase, la ultima.
	var tip_key := "UNIT_%s_CARD_TIP" % _unit_id.to_upper()
	var tip := Tr.t(tip_key)
	if tip != tip_key:
		var phrase := UITheme.make_label(tip, "small", UITheme.TEXT_DIM)
		phrase.name = "CardPhrase"
		phrase.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		phrase.custom_minimum_size.x = 220
		col.add_child(phrase)

	tooltip_text = "\n".join(summary_lines(_unit_id, _unit))

func _stat(kind: String, text: String, tip: String, color: Color = UITheme.TEXT) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.name = "Stat_" + kind
	box.add_theme_constant_override("separation", 4)
	var g := StatGlyph.new()
	g.kind = kind
	g.custom_minimum_size = Vector2(GLYPH_PX, GLYPH_PX)
	box.add_child(g)
	var label := UITheme.make_label(text, "body", color)
	box.add_child(label)
	if tip != "":
		box.tooltip_text = tip
		box.mouse_filter = Control.MOUSE_FILTER_PASS
	return box

## Lo que significa la ventaja, en palabras y no "×1,5" suelto en otra linea
## (ronda 1.0, mejora 14): "(pega 1,5 veces más)" / "(pega más flojo)".
static func mult_words(strong: bool, mult: float) -> String:
	if not strong:
		return Tr.t("LBL_CARD_WEAK_MULT")
	return Tr.t("LBL_CARD_STRONG_MULT") % mult_text(mult).trim_prefix("×")

## Fuerte / debil contra: [▲] Fuerte contra: [silueta] Artilleria, y debajo, en
## su propia linea, que significa (mult_words).
func _matchup_row(kind: String, lead: String, ids: Array, mult: String, color: Color) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Matchup_" + kind
	box.add_theme_constant_override("separation", 0)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	box.add_child(row)
	var g := StatGlyph.new()
	g.kind = kind
	g.custom_minimum_size = Vector2(GLYPH_PX, GLYPH_PX)
	row.add_child(g)
	row.add_child(UITheme.make_label(lead, "body", color))
	for id in ids:
		var ic := TextureRect.new()
		ic.texture = UITheme.unit_icon(String(id), GLYPH_PX)
		ic.custom_minimum_size = Vector2(GLYPH_PX, GLYPH_PX)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ic)
		row.add_child(UITheme.make_label(unit_name(String(id)), "body", UITheme.TEXT_BRIGHT))
	var words := UITheme.make_label(mult, "small", color)
	words.name = "MatchupWords"
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.custom_minimum_size.x = 180
	box.add_child(words)
	return box

## Un icono pequeno dibujado: corazon (vida), espada (ataque), escudo (defensa),
## diana (alcance), ✕ (no dispara de cerca), flecha arriba / abajo (fuerte /
## debil). Polígonos simples con contorno: se leen a 22 px y no cuestan nada.
class StatGlyph extends Control:
	var kind := "hp"

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size * 0.5
		var r := s * 0.42
		var line := UITheme.OUTLINE_COLOR
		match kind:
			"hp":
				var col := UITheme.DANGER.lightened(0.15)
				draw_circle(c + Vector2(-r * 0.45, -r * 0.2), r * 0.52, col)
				draw_circle(c + Vector2(r * 0.45, -r * 0.2), r * 0.52, col)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-r * 0.95, -r * 0.05), c + Vector2(r * 0.95, -r * 0.05), c + Vector2(0, r * 0.95)]), col)
			"atk":
				var blade := UITheme.TEXT_BRIGHT
				draw_line(c + Vector2(-r * 0.8, r * 0.8), c + Vector2(r * 0.85, -r * 0.85), line, 5.0)
				draw_line(c + Vector2(-r * 0.8, r * 0.8), c + Vector2(r * 0.85, -r * 0.85), blade, 3.0)
				draw_line(c + Vector2(-r * 0.75, r * 0.15), c + Vector2(-r * 0.15, r * 0.75), UITheme.ACCENT, 3.0)
			"def":
				var pts := PackedVector2Array([
					c + Vector2(-r * 0.8, -r * 0.85), c + Vector2(r * 0.8, -r * 0.85),
					c + Vector2(r * 0.8, r * 0.1), c + Vector2(0, r * 0.95), c + Vector2(-r * 0.8, r * 0.1)])
				draw_colored_polygon(pts, UITheme.INFO.lightened(0.2))
				pts.append(pts[0])
				draw_polyline(pts, line, 1.5)
			"range":
				draw_arc(c, r, 0, TAU, 20, UITheme.DANGER.lightened(0.25), 2.0)
				draw_arc(c, r * 0.55, 0, TAU, 16, UITheme.DANGER.lightened(0.25), 2.0)
				draw_circle(c, r * 0.18, UITheme.DANGER.lightened(0.25))
			"nofire":
				draw_line(c + Vector2(-r, -r), c + Vector2(r, r), UITheme.WARNING, 3.5)
				draw_line(c + Vector2(r, -r), c + Vector2(-r, r), UITheme.WARNING, 3.5)
			"good":
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(0, -r), c + Vector2(r, r * 0.6), c + Vector2(-r, r * 0.6)]), UITheme.POSITIVE)
			"bad":
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(0, r), c + Vector2(r, -r * 0.6), c + Vector2(-r, -r * 0.6)]), UITheme.WARNING)
