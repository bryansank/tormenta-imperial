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
## Los partes esperan en cola y salen de uno en uno: una defensa perdida trae su
## Diezmo detras, y dos tarjetas a la vez no se leen ninguna. Tampoco salen con
## un tablero abierto (`CombatManager.is_board_open()`): un parte no interrumpe
## una pelea; espera a que se cierre.
##
## No sale el parte del Diezmo cuando el Diezmo es parte de otra cosa: durante
## el asedio (los Tasadores no cobran, ya lo dice un aviso) y cuando es el Diezmo
## maximo de un asedio perdido, que ya cuenta AuditDefeatScreen.

const LAYER := 19
const CARD_WIDTH := 500.0

enum Kind { DEFENSE, TITHE }

var _root: Control
var _card: PanelContainer
var _kicker: Label
var _title: Label
var _stamp_slot: VBoxContainer
var _body: Label

## Cola de partes: {"kind": Kind, ...datos}.
var _queue: Array = []
var _current: Dictionary = {}
var _audit_lost_frame: int = -1

func _ready() -> void:
	layer = LAYER
	_setup_ui()
	visible = false
	EventBus.defense_auto_resolved.connect(_on_defense_auto_resolved)
	EventBus.tithe_resolved.connect(_on_tithe_resolved)
	EventBus.final_audit_lost.connect(func(_w): _audit_lost_frame = Engine.get_process_frames())
	get_viewport().size_changed.connect(_relayout)

func _setup_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.add_child(ModalKit.make_backdrop(0.55))

	_card = ModalKit.make_card(8)
	_root.add_child(_card)
	var column: VBoxContainer = _card.get_child(0)

	_kicker = ModalKit.make_text("", "small", UITheme.TEXT_DIM)
	column.add_child(_kicker)
	_title = ModalKit.make_text("", "title", UITheme.ACCENT)
	column.add_child(_title)
	_stamp_slot = VBoxContainer.new()
	column.add_child(_stamp_slot)
	column.add_child(UITheme.make_separator())
	_body = ModalKit.make_text("", "body", UITheme.TEXT)
	column.add_child(_body)
	column.add_child(ModalKit.make_menu_button(Tr.t("BTN_UNDERSTOOD"), UITheme.BTN, close_current))
	_relayout()

func _relayout() -> void:
	ModalKit.fit_center(_card, CARD_WIDTH, get_viewport().get_visible_rect().size)

# ── Entradas ─────────────────────────────────────────────────────────

func _on_defense_auto_resolved(victory: bool, rounds: int, summary: Dictionary) -> void:
	_queue.append({"kind": Kind.DEFENSE, "victory": victory, "rounds": rounds, "summary": summary.duplicate(true)})

func _on_tithe_resolved(repelled: bool, taken: Dictionary) -> void:
	# Con el asedio en marcha no hay Diezmo: el aviso STORM_TITHE_DURING_AUDIT
	# ya lo explica, y un sello de "repelido" mentiria.
	if ProgressionManager.is_final_audit_active():
		return
	_enqueue_tithe.call_deferred(repelled, taken.duplicate(), Engine.get_process_frames())

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
		_:
			_paint_tithe(_current)
	_relayout()
	visible = true
	return true

func close_current() -> void:
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
		_stamp_slot.add_child(ModalKit.make_stamp(text, color))

func _paint_defense(report: Dictionary) -> void:
	var victory: bool = bool(report.get("victory", false))
	_kicker.text = Tr.t("LBL_REPORT_DEFENSE_KICKER")
	_title.text = Tr.t("LBL_REPORT_DEFENSE_WON") if victory else Tr.t("LBL_REPORT_DEFENSE_LOST")
	UITheme.set_label_color(_title, UITheme.POSITIVE if victory else UITheme.DANGER)
	_set_stamp("", Color.WHITE)
	_body.text = "\n".join(defense_lines(victory, int(report.get("rounds", 0)), report.get("summary", {})))

func _paint_tithe(report: Dictionary) -> void:
	var repelled: bool = bool(report.get("repelled", false))
	_kicker.text = Tr.t("STORM_TITHE_DEFENDING")
	_title.text = Tr.t("LBL_REPORT_TITHE_REPELLED") if repelled else Tr.t("LBL_REPORT_TITHE_TAKEN")
	UITheme.set_label_color(_title, UITheme.POSITIVE if repelled else UITheme.DANGER)
	_set_stamp(
		Tr.t("LBL_STAMP_REPELLED") if repelled else Tr.t("LBL_STAMP_COLLECTED"),
		UITheme.POSITIVE.lightened(0.2) if repelled else UITheme.DANGER.lightened(0.25)
	)
	_body.text = "\n".join(tithe_lines(repelled, report.get("taken", {})))

## Las lineas del parte de una defensa a ciegas. Sin estado, para las pruebas.
static func defense_lines(victory: bool, rounds: int, summary: Dictionary) -> Array:
	var lines: Array = []
	lines.append(Tr.t("LBL_REPORT_ROUNDS") % rounds)
	lines.append("%s: %s" % [Tr.t("LBL_REPORT_OUR_LOSSES"), _unit_list(summary.get("casualties", {}))])
	lines.append("%s: %s" % [Tr.t("LBL_REPORT_THEIR_LOSSES"), _unit_list(summary.get("enemy_casualties", {}))])
	var crews: int = int(summary.get("tower_crews", 0))
	if crews > 0:
		lines.append(Tr.t("LBL_REPORT_TOWER_CREWS") % [crews, int(summary.get("tower_crews_lost", 0))])
	var morale: int = int(summary.get("morale_delta", 0))
	if morale != 0:
		lines.append(Tr.t("LBL_MORALE_DELTA") % morale)
	lines.append(Tr.t("STORM_TITHE_REPELLED") if victory else Tr.t("STORM_TITHE_PAID"))
	return lines

## Las lineas del parte del Diezmo, leyendo `taken` tal y como lo deja
## StormManager: recursos por nombre, `buildings` y `workers`.
static func tithe_lines(repelled: bool, taken: Dictionary) -> Array:
	if repelled:
		return [Tr.t("STORM_TITHE_REPELLED")]
	var lines: Array = []
	var resources: Dictionary = {}
	for key in taken:
		if key in ["gold", "wood", "steel", "oil"] and int(taken[key]) > 0:
			resources[key] = int(taken[key])
	if not resources.is_empty():
		lines.append(Tr.t("LBL_TITHE_TOOK") % Tr.amount_list(resources))
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
