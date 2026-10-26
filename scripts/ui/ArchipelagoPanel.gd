extends CanvasLayer
## Volverse el Imperio (feat/volverse-imperio, docs/06): el mapa del archipielago.
##
## Tu isla en el centro y las seis vecinas alrededor, cada una con su escudo
## (o tu bandera, si ya es tuya), su dificultad, su cadena de misiones, su
## tributo y su premio unico. Arriba, el Sargento cuenta de que va la fase y
## cual es el siguiente objetivo. PREPARAR EL ASALTO abre MISIONES en la
## pestana IMPERIO con esa isla elegida (alli se elige la tropa).
##
## Lo monta VictoryScreen como hermano (NODE_NAME) en las dos vistas; ☰ MENU lo
## abre por nombre (entrada ARCHIPIELAGO, solo con la fase activa). Solo lee
## EmpireManager y llama a SkirmishPanel: no guarda estado de partida.
##
## Rendimiento: se construye la primera vez que se abre; el mapa es un _draw
## que solo se repinta al cambiar algo (empire_changed, eleccion, tamano); un
## Timer de 1 s cuenta el proximo cobro solo mientras esta abierto.
##
## v1.2 (integracion): ventana de CartoonTheme (cinta azul, X con dodge del menu,
## velo), el mapa a la izquierda y la ficha de la isla a la derecha con su
## propio scroll (cabe en 640x360), y la cara del Sargento quieta (sin
## animacion de hablar, docs/28 §0.6).

const NODE_NAME := "ArchipelagoPanel"
const InstructorBust := preload("res://scripts/ui/InstructorBust.gd")
const Face := preload("res://scripts/ui/InstructorFace.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")
## Tope de la ventana en PC/tablet.
const WINDOW_MAX := Vector2(1080, 640)
const ColonyFlag := preload("res://scripts/ui/ColonyFlag.gd")
const ConquestGen := preload("res://scripts/empire/ConquestGenerator.gd")
const ArchipelagoScript := preload("res://scripts/empire/Archipelago.gd")
const DragScroll := preload("res://scripts/ui/DragScroll.gd")

var _built := false
var _root: Control
var _backdrop: ColorRect
var _card: Control
var _scroll: ScrollContainer
var _voice_row: HBoxContainer
var _bust: Control
var _quote: Label
var _summary: Label
var _tribute: Label
var _countdown: Label
var _map: ArchipelagoMap
var _island_box: VBoxContainer
var _timer: Timer
var _selected: String = ""

func _ready() -> void:
	layer = 17
	visible = false
	EventBus.empire_changed.connect(_on_changed)
	EventBus.colony_identity_changed.connect(func(_n, _s): _on_changed())
	EventBus.locale_changed.connect(func(_l): _rebuild_if_open())

## Esta abierto.
func is_open() -> bool:
	return visible

func open() -> void:
	if not _built:
		_build()
	if _selected == "" or not EmpireManager.island_ids().has(_selected):
		_selected = EmpireManager.next_target()
	visible = true
	_relayout()
	_refresh()
	_timer.start()
	# La primera vez, el Sargento cuenta de que va (y ya no se repite).
	if not EmpireManager.intro_seen() and EmpireManager.is_active():
		EmpireManager.mark_intro_seen()

func close() -> void:
	visible = false
	if _timer != null:
		_timer.stop()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

## La isla elegida en el mapa ("" ninguna). Publico para pruebas.
func selected_island() -> String:
	return _selected

func select_island(island_id: String) -> void:
	_selected = island_id
	if visible:
		_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# ── Construccion ─────────────────────────────────────────────────────

func _build() -> void:
	_built = true
	var small := CT.is_phone()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_backdrop = CT.veil()
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close())
	_root.add_child(_backdrop)

	var w := CT.menu_window(Tr.t("LBL_ARCHIPELAGO_TITLE"), CT.sem("INFO"), small, true)
	_card = w["root"]
	_card.name = "ArchipelagoCard"
	_root.add_child(_card)
	(w["close"] as Button).pressed.connect(close)
	var column: VBoxContainer = w["body"]

	# El Sargento (cara quieta) y su frase.
	_voice_row = HBoxContainer.new()
	_voice_row.name = "InstructorRow"
	_voice_row.add_theme_constant_override("separation", 8)
	_voice_row.visible = GameConfig.ui_instructors_visible
	column.add_child(_voice_row)
	_bust = Face.make(InstructorBust.COMBAT, "salute", 36 if small else 48)
	_bust.name = "Instructor"
	_bust.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_voice_row.add_child(_bust)
	_quote = CT.para("", "window", false, "small" if small else "body")
	_quote.name = "Quote"
	_quote.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quote.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_voice_row.add_child(_quote)
	EventBus.instructors_visibility_changed.connect(func(on: bool): _voice_row.visible = on)

	var main := HBoxContainer.new()
	main.name = "Main"
	main.add_theme_constant_override("separation", 8 if small else 14)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(main)

	# Izquierda: el mapa y, debajo, cuantas islas, el tributo y el proximo cobro.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.4
	left.add_theme_constant_override("separation", 2)
	main.add_child(left)
	_map = ArchipelagoMap.new()
	_map.name = "ArchipelagoMap"
	_map.custom_minimum_size = Vector2(0, 120)
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.island_pressed.connect(select_island)
	left.add_child(_map)
	_summary = CT.label("", "small", CT.text("window"))
	_summary.name = "Summary"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_summary)
	_tribute = CT.label("", "small", CT.positive_text())
	_tribute.name = "TributeLine"
	_tribute.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_tribute)
	_countdown = CT.label("", "small", CT.text("window", true))
	_countdown.name = "TributeCountdown"
	left.add_child(_countdown)

	# Derecha: la ficha de la isla elegida, con su propio scroll.
	var right := PanelContainer.new()
	right.name = "IslandPanel"
	var st := CT.card_style("window")
	st.set_content_margin_all(6 if small else 12)
	right.add_theme_stylebox_override("panel", st)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(right)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_scroll)
	DragScroll.attach.call_deferred(_scroll)
	_island_box = VBoxContainer.new()
	_island_box.name = "IslandCard"
	_island_box.add_theme_constant_override("separation", 4 if small else 6)
	_island_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_island_box)

	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(_refresh_countdown)
	add_child(_timer)

	get_viewport().size_changed.connect(_relayout)

func _relayout() -> void:
	if _card == null or not visible:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	CT.place_window(_card, vp, WINDOW_MAX, CT.is_phone())

func _rebuild_if_open() -> void:
	if not _built:
		return
	var was_open: bool = visible
	close()
	for child in get_children():
		child.queue_free()
	_built = false
	if was_open:
		open.call_deferred()

# ── Refresco ─────────────────────────────────────────────────────────

func _on_changed() -> void:
	if visible:
		_refresh()

func _refresh() -> void:
	if not _built:
		return
	var count: int = EmpireManager.conquered_count()
	var total: int = EmpireManager.island_count()
	var summary: String = Tr.t("LBL_ARCH_CONQUERED") % [count, total]
	var title: String = EmpireManager.title_key()
	if title != "":
		summary += "  ·  " + Tr.t("LBL_ARCH_TITLE_NOW") % Tr.t(title)
	_summary.text = summary
	var minutes: int = maxi(1, roundi(GameConfig.get_duration(GameConfig.empire_tribute_interval) / 60.0))
	var per: Dictionary = EmpireManager.tribute_per_cycle()
	_tribute.text = Tr.t("LBL_ARCH_TRIBUTE_NONE") % minutes if per.is_empty() \
		else Tr.t("LBL_ARCH_TRIBUTE") % [minutes, EmpireManager.amounts_text(per)]
	_refresh_countdown()
	_quote.text = quote_text()
	_map.selected = _selected
	_map.queue_redraw()
	_rebuild_island_card()

func _refresh_countdown() -> void:
	if _countdown == null:
		return
	var left: int = ceili(EmpireManager.tribute_left())
	_countdown.visible = left > 0
	_countdown.text = Tr.t("LBL_ARCH_NEXT_TRIBUTE") % [left / 60, left % 60]

## Lo que dice el Sargento: la intro la primera vez, luego el siguiente
## objetivo, y al final la advertencia (el giro del lore: "asi empezo la Regencia").
func quote_text() -> String:
	if not EmpireManager.intro_seen():
		return Tr.t("EMP_QUOTE_INTRO")
	if EmpireManager.all_conquered():
		return Tr.t("EMP_QUOTE_DONE")
	var target: String = EmpireManager.next_target()
	if target == "":
		return Tr.t("EMP_QUOTE_WAIT")
	if EmpireManager.lock_reason(target) == "EMP_LOCK_REST":
		return Tr.t("EMP_QUOTE_WAIT")
	return Tr.t("EMP_QUOTE_NEXT") % Tr.t(ConquestGen.island_name_key(target))

## La ficha de la isla elegida.
func _rebuild_island_card() -> void:
	for child in _island_box.get_children():
		_island_box.remove_child(child)
		child.queue_free()
	var small := CT.is_phone()
	if _selected == "":
		_island_box.add_child(CT.icon_line("anchor", Tr.t("LBL_ARCH_PICK"), "", "window", "body"))
		return
	var island_id: String = _selected
	var def: Dictionary = GameConfig.empire_island(island_id)
	var conquered: bool = EmpireManager.is_conquered(island_id)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_island_box.add_child(head)
	var crest := TextureRect.new()
	crest.name = "Crest"
	crest.texture = ColonyFlag.current_small_texture() if conquered else ColonyFlag.small_texture(def.get("crest", {}))
	crest.custom_minimum_size = Vector2(42, 28) if small else Vector2(48, 32)
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(crest)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 0)
	head.add_child(names)
	var name_label := CT.label(Tr.t(ConquestGen.island_name_key(island_id)), "button" if small else "title", CT.text("window"))
	name_label.name = "IslandName"
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(name_label)
	var stars: String = "★".repeat(ArchipelagoScript.tier(island_id)) + "☆".repeat(3 - ArchipelagoScript.tier(island_id))
	names.add_child(CT.label(Tr.t("LBL_ARCH_TIER") % stars, "small", CT.tone_color("warning")))

	var desc := CT.para(Tr.t("EMP_ISLE_%s_DESC" % island_id.to_upper()), "window", true, "small")
	_island_box.add_child(desc)

	# La cadena de misiones: el recorrido de siempre (hechas, la que toca, jefe)
	# y una linea por mision (medio y combates) en pequeno.
	var won: int = EmpireManager.won(island_id)
	var total: int = EmpireManager.total(island_id)
	var track := CT.campaign_track(won, total, small, Tr.t("EMP_BOSS_WARNING"))
	track.name = "IslandTrack"
	track.alignment = BoxContainer.ALIGNMENT_BEGIN
	_island_box.add_child(track)
	for i in range(total):
		var m: Dictionary = ArchipelagoScript.mission_def(island_id, i)
		var domain: String = String(m.get("domain", "land"))
		var glyph: String = String({"land": "tank", "sea": "anchor", "air": "plane"}.get(domain, "missions"))
		if i < won:
			glyph = "check"
		var line := "%s · %s" % [Tr.t(String(m.get("name", ""))), Tr.t("CAMP_KIND_FIGHTS") % int(m.get("fights", 1))]
		var row := CT.icon_line(glyph, line, "" if i >= won else "positive")
		row.name = "Mission_%d" % i
		row.tooltip_text = Tr.t("LBL_DOMAIN_" + domain.to_upper())
		_island_box.add_child(row)

	var tribute: Dictionary = ArchipelagoScript.tribute_of(island_id)
	var pays := CT.icon_line("market", Tr.t("LBL_ARCH_ISLAND_PAYS" if conquered else "LBL_ARCH_ISLAND_TRIBUTE") % EmpireManager.amounts_text(tribute), "positive")
	pays.name = "IslandPays"
	_island_box.add_child(pays)

	var rewards: Array = EmpireManager.reward_lines(island_id)
	for text in rewards:
		_island_box.add_child(CT.icon_line("star", String(text), "" if conquered else "accent"))

	if conquered:
		var yours := CT.icon_line("check", Tr.t("LBL_ARCH_YOURS"), "positive", "window", "body")
		yours.name = "IslandYours"
		_island_box.add_child(yours)
		return

	var lock: String = EmpireManager.lock_reason(island_id)
	if lock != "":
		var why := CT.icon_line("lock", EmpireManager.lock_text(island_id), "warning")
		why.name = "IslandLock"
		_island_box.add_child(why)
	# Con la tropa descansando o una columna fuera, se puede mirar pero no salir.
	var attack := CT.text_button(Tr.t("BTN_ARCH_ATTACK"), "missions", "primary" if lock == "" else "disabled",
		CT.menu_h("btn"))
	attack.name = "AttackButton"
	attack.disabled = lock != ""
	attack.tooltip_text = EmpireManager.lock_text(island_id)
	attack.pressed.connect(func(): prepare_attack(island_id))
	_island_box.add_child(attack)

## PREPARAR EL ASALTO: MISIONES, pestana IMPERIO, con la isla elegida.
func prepare_attack(island_id: String) -> void:
	var skirmish: Node = _sibling("SkirmishPanel")
	if skirmish == null or not skirmish.has_method("open_conquest"):
		return
	close()
	skirmish.open_conquest(island_id)

func _sibling(node_name: String) -> Node:
	var parent: Node = get_parent()
	if parent != null and parent.get_node_or_null(node_name) != null:
		return parent.get_node(node_name)
	return get_tree().root.find_child(node_name, true, false)


## El mapa: mar, rutas punteadas desde tu isla, las islas con su escudo o tu
## bandera, el nombre y la marca de la elegida. Todo en un _draw; las banderas
## son texturas cacheadas de ColonyFlag. Se repinta solo cuando se le pide.
class ArchipelagoMap extends Control:
	signal island_pressed(island_id: String)

	const HOME := Vector2(0.5, 0.5)
	const Flag := preload("res://scripts/ui/ColonyFlag.gd")
	const Gen := preload("res://scripts/empire/ConquestGenerator.gd")
	const FLAG_SIZE := Vector2(36, 24)
	var selected: String = ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		resized.connect(queue_redraw)

	## Donde cae una isla (0..1) en pixeles, con margen para el nombre.
	func to_px(p: Vector2) -> Vector2:
		var pad := Vector2(44.0, 30.0)
		return pad + Vector2(p.x * (size.x - pad.x * 2.0), p.y * (size.y - pad.y * 2.0))

	func island_radius() -> float:
		return clampf(minf(size.x, size.y) * 0.075, 16.0, 40.0)

	## La isla bajo `pos` ("" si ninguna).
	func island_at(pos: Vector2) -> String:
		var best: String = ""
		var best_d: float = island_radius() * 1.6
		for island in GameConfig.empire_islands:
			var d: float = pos.distance_to(to_px(island.get("pos", HOME)))
			if d < best_d:
				best_d = d
				best = String(island.get("id", ""))
		return best

	func _gui_input(event: InputEvent) -> void:
		var pressed: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and event.pressed)
		if not pressed:
			return
		var id: String = island_at(event.position)
		if id != "":
			island_pressed.emit(id)
			accept_event()

	func _draw() -> void:
		var area := Rect2(Vector2.ZERO, size)
		draw_rect(area, UITheme.BOARD_WATER)
		# Olas: unas lineas cortas fijas (sin azar: salen del tamano).
		var wave: Color = Color(UITheme.TEXT_BRIGHT, 0.10)
		for i in range(14):
			var u: float = fposmod(float(i) * 0.37, 1.0)
			var v: float = fposmod(float(i) * 0.61 + 0.13, 1.0)
			var p := Vector2(u * size.x, v * size.y)
			draw_line(p, p + Vector2(14, 0), wave, 2.0)
		var home: Vector2 = to_px(HOME)
		var r: float = island_radius()
		var font: Font = get_theme_default_font()
		var font_size: int = UITheme.FONT_SMALL
		# Rutas.
		for island in GameConfig.empire_islands:
			var p: Vector2 = to_px(island.get("pos", HOME))
			var id: String = String(island.get("id", ""))
			var col: Color = UITheme.POSITIVE if EmpireManager.is_conquered(id) else Color(UITheme.TEXT_BRIGHT, 0.35)
			draw_dashed_line(home, p, col, 2.0, 8.0)
		# Tu isla.
		_draw_island(home, r * 1.35, 0)
		_draw_flag(home + Vector2(0, -r * 1.35 - 4.0), Flag.current_small_texture())
		_draw_name(font, font_size, home + Vector2(0, r * 1.35 + 16.0), Tr.t("LBL_ARCH_HOME"), UITheme.TEXT_BRIGHT)
		# Las vecinas.
		var index: int = 1
		for island in GameConfig.empire_islands:
			var id: String = String(island.get("id", ""))
			var p: Vector2 = to_px(island.get("pos", HOME))
			var conquered: bool = EmpireManager.is_conquered(id)
			var open: bool = EmpireManager.get_book().needs_met(id)
			if id == selected:
				draw_arc(p, r + 8.0, 0.0, TAU, 40, UITheme.ACCENT, 3.0)
			_draw_island(p, r, index, not open and not conquered)
			var tex: Texture2D = Flag.current_small_texture() if conquered else Flag.small_texture(island.get("crest", {}))
			_draw_flag(p + Vector2(0, -r - 4.0), tex)
			var label: String = Tr.t(Gen.island_name_key(id))
			var won: int = EmpireManager.won(id)
			var total: int = EmpireManager.total(id)
			if not conquered:
				label += "  %d/%d" % [won, total]
			_draw_name(font, font_size, p + Vector2(0, r + 16.0), label,
				UITheme.POSITIVE if conquered else (UITheme.TEXT_BRIGHT if open else UITheme.TEXT_DIM))
			index += 1

	## Una isla: un borron de costa y tierra con forma propia por indice (sin azar).
	func _draw_island(c: Vector2, r: float, index: int, dim: bool = false) -> void:
		var shore := PackedVector2Array()
		var land := PackedVector2Array()
		var n := 18
		for k in range(n):
			var a: float = TAU * float(k) / float(n)
			var wobble: float = 1.0 + 0.16 * sin(a * 3.0 + float(index) * 1.7) + 0.08 * cos(a * 5.0 + float(index))
			var dir := Vector2(cos(a), sin(a) * 0.78)
			shore.append(c + dir * r * wobble * 1.12)
			land.append(c + dir * r * wobble)
		var sand: Color = UITheme.BOARD_SHORE
		var grass: Color = UITheme.CAT_DECORATION.darkened(0.15)
		if dim:
			sand = sand.darkened(0.35)
			grass = grass.darkened(0.45)
		draw_colored_polygon(shore, sand)
		draw_colored_polygon(land, grass)

	func _draw_flag(bottom_center: Vector2, tex: Texture2D) -> void:
		var top_left := bottom_center - Vector2(FLAG_SIZE.x * 0.5 - 4.0, FLAG_SIZE.y + 10.0)
		draw_line(bottom_center + Vector2(-FLAG_SIZE.x * 0.5 + 4.0, 0), top_left, UITheme.TEXT_BRIGHT, 2.0)
		draw_texture_rect(tex, Rect2(top_left, FLAG_SIZE), false)

	func _draw_name(font: Font, font_size: int, center: Vector2, text: String, color: Color) -> void:
		if font == null:
			return
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var pos := Vector2(center.x - w * 0.5, center.y)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, UITheme.OUTLINE_COLOR)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
