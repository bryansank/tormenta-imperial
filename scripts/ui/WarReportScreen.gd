extends CanvasLayer
## Los partes de guerra que no tienen tablero propio:
##
##   * **Parte de defensa** (`defense_auto_resolved`): el Diezmo cayo con la
##     columna fuera y la guarnicion peleo sola, resuelta a ciegas. Bajas de los
##     dos lados, rondas y resultado. Antes solo quedaba un aviso en la esquina.
##   * **Parte del Diezmo** (`tithe_resolved`): lo que se llevaron los Tasadores,
##     con su sello — COBRADO o REPELIDO. Lee el diccionario `taken` tal cual:
##     recursos por nombre, `buildings` embargados, `workers` reclutados.
##
##   * **Parte del Impuesto de prueba** (`trial_tithe_resolved`, 2026-10-17): la
##     tormenta de prueba de la era 1 trae unos Cobradores de juguete. Echados, o
##     lo poco que se llevaron, y por que: sin soldados en casa no hay quien pelee.
##
## Los partes esperan en cola y salen de uno en uno: una defensa perdida trae su
## Diezmo detras, y dos tarjetas a la vez no se leen ninguna. Tampoco salen con
## un tablero abierto (`CombatManager.is_board_open()`): un parte no interrumpe
## una pelea; espera a que se cierre.
##
## No sale el parte del Diezmo cuando el Diezmo es parte de otra cosa: durante
## el asedio (los Tasadores no cobran, ya lo dice un aviso) y cuando es el Diezmo
## maximo de un asedio perdido, que ya cuenta AuditDefeatScreen.
##
## El Sargento Mayor Bombarda (feat/instructores) comenta cada parte con una
## frase, debajo de las cifras: tres variantes por caso (QUOTE_CASES), que se
## turnan. Su fila se oculta con Ajustes > Interfaz > Instructores.
##
## Rediseno fase 2 (feat/ui2-ejercito, docs/28): ventana crema con cinta PARTE
## (verde si salio bien, roja si no), el sello, lo perdido en iconos (discos de
## unidad, recursos en rojo) y las lineas cortas debajo; ¡ENTENDIDO! verde.

const ColonyByline := preload("res://scripts/ui/ColonyByline.gd")
const TextKit := preload("res://scripts/ui/TextKit.gd")
const InstructorBust := preload("res://scripts/ui/InstructorBust.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")

## Los casos que el Sargento comenta, y cuantas frases tiene cada uno
## (INSTR_QUOTE_<CASO>_<n> en Tr.gd).
const QUOTE_CASES := ["DEFENSE_WON", "DEFENSE_LOST", "TITHE_REPELLED", "TITHE_TAKEN", "TRIAL_REPELLED", "TRIAL_TAKEN"]
const QUOTE_VARIANTS := 3
const BUST_SIZE := Vector2(84, 105)

const LAYER := 19
const CARD_WIDTH := 500.0

enum Kind { DEFENSE, TITHE, TRIAL }

var _root: Control
var _win: Dictionary = {}
var _card: PanelContainer
## Lo perdido o lo ganado en iconos, encima de las lineas.
var _icons: HFlowContainer
var _relayout_queued := false
var _kicker: Label
var _title: Label
var _stamp_slot: VBoxContainer
var _body: Label
var _scroll: ScrollContainer
var _scroll_body: VBoxContainer
var _voice_row: HBoxContainer
var _voice_bust: Control
var _quote: Label
var _signed: Label
var _quote_case := ""
## Turno de frases: empieza en un sitio al azar para que dos partidas no
## arranquen igual, y luego se turnan.
var _quote_seq := randi() % QUOTE_VARIANTS

## Cola de partes: {"kind": Kind, ...datos}.
var _queue: Array = []
var _current: Dictionary = {}
var _audit_lost_frame: int = -1

func _ready() -> void:
	layer = LAYER
	# Mientras se ve, los avisos esperan (NotificationPanel.is_busy).
	add_to_group("modal_screen")
	_setup_ui()
	visible = false
	EventBus.defense_auto_resolved.connect(_on_defense_auto_resolved)
	EventBus.tithe_resolved.connect(_on_tithe_resolved)
	EventBus.trial_tithe_resolved.connect(_on_trial_tithe_resolved)
	EventBus.final_audit_lost.connect(func(_w): _audit_lost_frame = Engine.get_process_frames())
	get_viewport().size_changed.connect(_relayout)

func _setup_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_win = CT.modal_window(_root, Tr.t("ARMY2_REPORT"), CT.sem("ACCENT"))
	var veil: ColorRect = _win["veil"]
	veil.color = Color(veil.color, 0.55)
	(_win["close"] as Button).pressed.connect(close_current)
	(_win["close"] as Button).tooltip_text = Tr.t("BTN_CLOSE")
	_card = _win["panel"]
	_card.minimum_size_changed.connect(_queue_relayout)
	var outer: VBoxContainer = _win["body"]
	outer.add_theme_constant_override("separation", 6)
	# Lo del medio (pais, titulo, bajas, el Sargento) se arrastra si no cabe: en
	# un telefono de 360 de alto el parte entero no cabe y se quedaba en blanco.
	_scroll = ScrollContainer.new()
	_scroll.name = "ReportScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_scroll)
	var column := VBoxContainer.new()
	column.name = "ReportBody"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	_scroll.add_child(column)
	_scroll_body = column
	column.minimum_size_changed.connect(_queue_relayout)

	# El pais que firma el parte: bandera y nombre, encima (no alarga el titulo).
	column.add_child(ColonyByline.new("small", CT.text("window", true)))
	_kicker = _centered(CT.label("", "small", CT.text("window", true)))
	column.add_child(_kicker)
	_title = _centered(CT.label("", "title", CT.text("window")))
	column.add_child(_title)
	_stamp_slot = VBoxContainer.new()
	column.add_child(_stamp_slot)
	_icons = HFlowContainer.new()
	_icons.name = "ReportIcons"
	_icons.alignment = FlowContainer.ALIGNMENT_CENTER
	_icons.add_theme_constant_override("h_separation", 10)
	_icons.add_theme_constant_override("v_separation", 4)
	column.add_child(_icons)
	_body = _centered(CT.label("", "body", CT.text("window")))
	column.add_child(_body)
	# El Sargento y su frase.
	_voice_row = HBoxContainer.new()
	_voice_row.name = "InstructorRow"
	_voice_row.add_theme_constant_override("separation", 10)
	_voice_row.visible = false
	column.add_child(_voice_row)
	_voice_bust = InstructorBust.new()
	_voice_bust.name = "Instructor"
	_voice_bust.custom_minimum_size = BUST_SIZE
	_voice_bust.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_voice_bust.show_as(InstructorBust.COMBAT, "point", 1)
	_voice_row.add_child(_voice_bust)
	var said := VBoxContainer.new()
	said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	said.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_voice_row.add_child(said)
	_quote = CT.label("", "body", CT.text("window"))
	_quote.name = "Quote"
	_quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	said.add_child(_quote)
	_signed = CT.label("", "small", CT.text("window", true))
	_signed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_signed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	said.add_child(_signed)
	EventBus.instructors_visibility_changed.connect(func(on: bool):
		_voice_row.visible = on and _quote_case != "")
	var ok := CT.pill_button(Tr.t("BTN_UNDERSTOOD"), "check", "primary", CT.h("big"))
	ok.name = "Understood"
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(close_current)
	outer.add_child(ok)
	_relayout()

static func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

## La tarjeta mide lo que su contenido; se recoloca cuando este cambia.
func _relayout() -> void:
	_relayout_queued = false
	if not is_inside_tree():
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if _scroll != null:
		# El medio mide lo que pida, sin pasarse de lo que deja la pantalla.
		var panel: Control = _win["panel"]
		var base: float = panel.get_combined_minimum_size().y + panel.offset_top - _scroll.custom_minimum_size.y
		var room: float = vp.y - (4.0 if CT.is_phone() else 24.0) - base
		var want := clampf(_scroll_body.get_combined_minimum_size().y, 40.0, maxf(40.0, room))
		if absf(want - _scroll.custom_minimum_size.y) > 0.5:
			_scroll.custom_minimum_size.y = want
	CT.fit_card(_win, vp, CARD_WIDTH)

func _queue_relayout() -> void:
	if _relayout_queued:
		return
	_relayout_queued = true
	_relayout.call_deferred()

# ── Entradas ─────────────────────────────────────────────────────────

func _on_defense_auto_resolved(victory: bool, rounds: int, summary: Dictionary) -> void:
	_queue.append({"kind": Kind.DEFENSE, "victory": victory, "rounds": rounds, "summary": summary.duplicate(true)})

func _on_tithe_resolved(repelled: bool, taken: Dictionary) -> void:
	# Con el asedio en marcha no hay Diezmo: el aviso STORM_TITHE_DURING_AUDIT
	# ya lo explica, y un sello de "repelido" mentiria.
	if ProgressionManager.is_final_audit_active():
		return
	_enqueue_tithe.call_deferred(repelled, taken.duplicate(), Engine.get_process_frames())

## El Impuesto de juguete de la tormenta de prueba (cuartel temprano).
func _on_trial_tithe_resolved(repelled: bool, taken: Dictionary) -> void:
	_queue.append({"kind": Kind.TRIAL, "repelled": repelled, "taken": taken.duplicate()})

## Diferido: `final_audit_lost` puede llegar despues del Diezmo en la misma
## cadena. Si llego en este frame, el Diezmo es el del asedio y lo cuenta el
## parte de derrota.
func _enqueue_tithe(repelled: bool, taken: Dictionary, frame: int) -> void:
	if _audit_lost_frame == frame:
		return
	_queue.append({"kind": Kind.TITHE, "repelled": repelled, "taken": taken})

# ── Cola ─────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	try_show_next()

## Saca el siguiente parte si no hay uno en pantalla ni tablero abierto.
## Devuelve true si ensena uno. Publico para las pruebas.
func try_show_next() -> bool:
	if visible or _queue.is_empty():
		return false
	if CombatManager.is_board_open():
		return false
	_current = _queue.pop_front()
	match int(_current.get("kind", Kind.TITHE)):
		Kind.DEFENSE:
			_paint_defense(_current)
		Kind.TRIAL:
			_paint_trial(_current)
		_:
			_paint_tithe(_current)
	_relayout()
	visible = true
	_queue_relayout()
	if _voice_row.visible:
		_voice_bust.speak(_quote)
	return true

func close_current() -> void:
	_voice_bust.finish_speaking()
	visible = false
	_current = {}

func pending_count() -> int:
	return _queue.size()

func is_showing() -> bool:
	return visible

func current_kind() -> int:
	return int(_current.get("kind", -1))

func title_text() -> String:
	return _title.text

func body_text() -> String:
	return _body.text

## La frase del Sargento en pantalla, su caso y si se ve (pruebas).
func quote_text() -> String:
	return _quote.text

func quote_case() -> String:
	return _quote_case

func is_instructor_shown() -> bool:
	return _voice_row.visible

func instructor() -> Control:
	return _voice_bust

## La clave de la frase `n` (se turnan) de `quote_case_id`. Pura, para las pruebas.
static func quote_key(quote_case_id: String, n: int) -> String:
	return "INSTR_QUOTE_%s_%d" % [quote_case_id, posmod(n, QUOTE_VARIANTS) + 1]

## El caso que comenta el Sargento para un parte: tipo y si salio bien.
static func quote_case_for(kind: int, good: bool) -> String:
	match kind:
		Kind.DEFENSE:
			return "DEFENSE_WON" if good else "DEFENSE_LOST"
		Kind.TRIAL:
			return "TRIAL_REPELLED" if good else "TRIAL_TAKEN"
	return "TITHE_REPELLED" if good else "TITHE_TAKEN"

## La cara del Sargento: saluda tras una defensa ganada, contento si echa a
## los Cobradores; enfadado si se llevan algo, preocupado en el de prueba.
static func quote_face(kind: int, good: bool) -> String:
	if good:
		return "salute" if kind == Kind.DEFENSE else "happy"
	return "worried" if kind == Kind.TRIAL else "angry"

## Pone la frase del Sargento con su cara.
func _say(kind: int, good: bool) -> void:
	_quote_case = quote_case_for(kind, good)
	_quote_seq += 1
	_quote.text = Tr.t(quote_key(_quote_case, _quote_seq))
	_signed.text = Tr.t("INSTR_SIGNED") % ("%s %s" % [Tr.t(InstructorBust.rank_key(InstructorBust.COMBAT)),
		Tr.t(InstructorBust.name_key(InstructorBust.COMBAT))])
	_voice_bust.show_as(InstructorBust.COMBAT, quote_face(kind, good), 1)
	_voice_row.visible = GameConfig.ui_instructors_visible

func stamp_text() -> String:
	for child in _stamp_slot.get_children():
		return String(child.get_meta("stamp_text", ""))
	return ""

# ── Pintado ──────────────────────────────────────────────────────────

func _set_stamp(text: String, color: Color) -> void:
	for child in _stamp_slot.get_children():
		_stamp_slot.remove_child(child)
		child.queue_free()
	if text != "":
		_stamp_slot.add_child(CT.stamp(text, color))

func _paint_defense(report: Dictionary) -> void:
	var victory: bool = bool(report.get("victory", false))
	_kicker.text = Tr.t("LBL_REPORT_DEFENSE_KICKER")
	_title.text = Tr.t("LBL_REPORT_DEFENSE_WON") if victory else Tr.t("LBL_REPORT_DEFENSE_LOST")
	_tone(victory, "danger")
	_set_stamp("", Color.WHITE)
	# Bajas en discos: las nuestras en verde, las suyas en rojo.
	var summary: Dictionary = report.get("summary", {})
	_set_icons([CT.roster_discs(summary.get("casualties", {}), CT.sem("POSITIVE"), 40),
		CT.roster_discs(summary.get("enemy_casualties", {}), CT.sem("DANGER"), 40)])
	_body.text = "\n".join(defense_lines(victory, int(report.get("rounds", 0)), report.get("summary", {})))
	_say(Kind.DEFENSE, victory)

func _paint_tithe(report: Dictionary) -> void:
	var repelled: bool = bool(report.get("repelled", false))
	_kicker.text = Tr.t("STORM_TITHE_DEFENDING")
	_title.text = Tr.t("LBL_REPORT_TITHE_REPELLED") if repelled else Tr.t("LBL_REPORT_TITHE_TAKEN")
	_tone(repelled, "danger")
	_set_stamp(
		Tr.t("LBL_STAMP_REPELLED") if repelled else Tr.t("LBL_STAMP_COLLECTED"),
		CT.sem("POSITIVE") if repelled else CT.sem("DANGER")
	)
	_set_icons([_taken_chips(report.get("taken", {}))])
	_body.text = "\n".join(tithe_lines(repelled, report.get("taken", {})))
	_say(Kind.TITHE, repelled)

## El parte del Impuesto de prueba: echados o lo poco que se llevaron, y la
## leccion (soldados en casa = nadie se lleva nada).
func _paint_trial(report: Dictionary) -> void:
	var repelled: bool = bool(report.get("repelled", false))
	_kicker.text = Tr.t("LBL_REPORT_TRIAL_KICKER")
	_title.text = Tr.t("LBL_REPORT_TITHE_REPELLED") if repelled else Tr.t("LBL_REPORT_TITHE_TAKEN")
	_tone(repelled, "warning")
	_set_stamp(
		Tr.t("LBL_STAMP_REPELLED") if repelled else Tr.t("LBL_STAMP_COLLECTED"),
		CT.sem("POSITIVE") if repelled else CT.sem("WARNING")
	)
	_set_icons([_taken_chips(report.get("taken", {}))])
	_body.text = "\n".join(trial_lines(repelled, report.get("taken", {})))
	_say(Kind.TRIAL, repelled)

## La cinta (PARTE) y el titulo en verde si salio bien; si no, en `bad_tone`.
func _tone(good: bool, bad_tone: String) -> void:
	CT.set_ribbon(_win, Tr.t("ARMY2_REPORT"), CT.sem("POSITIVE") if good else CT.sem(bad_tone.to_upper()))
	CT.style_label(_title, "title", CT.tone_color("positive" if good else bad_tone))

## Cambia la fila de iconos (vacia = se esconde).
func _set_icons(parts: Array) -> void:
	for child in _icons.get_children():
		_icons.remove_child(child)
		child.queue_free()
	for part in parts:
		if part != null and (part as Control).get_child_count() > 0:
			_icons.add_child(part)
		elif part != null:
			(part as Control).queue_free()
	_icons.visible = _icons.get_child_count() > 0

## Lo que se llevaron en iconos: recursos con "-", edificios y trabajadores.
func _taken_chips(taken: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var resources: Dictionary = {}
	for key in taken:
		if key in ["gold", "wood", "steel", "oil", "food"] and int(taken[key]) > 0:
			resources[key] = int(taken[key])
	if not resources.is_empty():
		row.add_child(CT.cost_row(resources, resources, "-"))
	if int(taken.get("workers", 0)) > 0:
		var people := HBoxContainer.new()
		people.add_theme_constant_override("separation", 3)
		people.add_child(UITheme.make_icon("workers", 24))
		people.add_child(CT.label("-%d" % int(taken["workers"]), "number", CT.tone_color("danger")))
		row.add_child(people)
	return row

## Las lineas del parte del Impuesto de prueba. Sin estado, para las pruebas.
static func trial_lines(repelled: bool, taken: Dictionary) -> Array:
	var lines: Array = []
	if repelled:
		lines.append(Tr.t("LBL_TITHE_NOTHING_TAKEN"))
		lines.append(Tr.t("LBL_REPORT_TRIAL_WON"))
	else:
		var resources: Dictionary = {}
		for key in taken:
			if key in ["gold", "wood", "steel", "oil", "food"] and int(taken[key]) > 0:
				resources[key] = int(taken[key])
		if resources.is_empty():
			lines.append(Tr.t("LBL_TITHE_NOTHING"))
		else:
			lines.append(Tr.t("LBL_TITHE_TOOK") % TextKit.cost_text(resources))
		lines.append(Tr.t("LBL_REPORT_TRIAL_LOST"))
	lines.append(Tr.t("LBL_REPORT_TRIAL_NEXT"))
	return lines

## Las lineas del parte de una defensa a ciegas. Sin estado, para las pruebas.
static func defense_lines(_victory: bool, rounds: int, summary: Dictionary) -> Array:
	var lines: Array = []
	lines.append(Tr.t("LBL_REPORT_ROUNDS") % rounds)
	lines.append("%s: %s" % [Tr.t("LBL_REPORT_OUR_LOSSES"), _unit_list(summary.get("casualties", {}))])
	lines.append("%s: %s" % [Tr.t("LBL_REPORT_THEIR_LOSSES"), _unit_list(summary.get("enemy_casualties", {}))])
	var wounded: Dictionary = summary.get("wounded", {})
	if not wounded.is_empty():
		lines.append("%s: %s" % [Tr.t("LBL_REPORT_WOUNDED"), _unit_list(wounded)])
	var crews: int = int(summary.get("tower_crews", 0))
	if crews > 0:
		lines.append(Tr.t("LBL_REPORT_TOWER_CREWS") % [crews, int(summary.get("tower_crews_lost", 0))])
	var towers: int = int(summary.get("towers_damaged", 0))
	if towers > 0:
		lines.append(Tr.t("LBL_REPORT_TOWERS_DAMAGED") % towers)
	var morale: int = int(summary.get("morale_delta", 0))
	if morale != 0:
		lines.append(Tr.t("LBL_MORALE_DELTA") % morale)
	# "Los Tasadores se retiran / han cobrado" ya no va aqui (2026-10-04): lo
	# dice el titulo, y el parte del Diezmo sale detras con su sello.
	return lines

## Las lineas del parte del Diezmo, leyendo `taken` tal y como lo deja
## StormManager: recursos por nombre, `buildings` y `workers`.
static func tithe_lines(repelled: bool, taken: Dictionary) -> Array:
	if repelled:
		return [Tr.t("LBL_TITHE_NOTHING_TAKEN")]
	var lines: Array = []
	var resources: Dictionary = {}
	for key in taken:
		if key in ["gold", "wood", "steel", "oil"] and int(taken[key]) > 0:
			resources[key] = int(taken[key])
	if not resources.is_empty():
		lines.append(Tr.t("LBL_TITHE_TOOK") % TextKit.cost_text(resources))
	if int(taken.get("buildings", 0)) > 0:
		lines.append(Tr.t("LBL_TITHE_SEIZED_N") % int(taken["buildings"]))
	if int(taken.get("workers", 0)) > 0:
		lines.append(Tr.t("LBL_TITHE_WORKERS_N") % int(taken["workers"]))
	if lines.is_empty():
		lines.append(Tr.t("LBL_TITHE_NOTHING"))
	return lines

static func _unit_list(counts: Dictionary) -> String:
	var parts: Array = []
	for unit_id in counts:
		if int(counts[unit_id]) > 0:
			parts.append("%d %s" % [int(counts[unit_id]), Tr.t(GameConfig.get_unit_def(unit_id).get("name", unit_id))])
	return Tr.t("LBL_REPORT_NONE") if parts.is_empty() else "   ".join(parts)
