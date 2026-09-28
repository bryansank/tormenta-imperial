extends CanvasLayer
## El parte de un asedio perdido. Sale con `final_audit_lost` y dice tres cosas:
## que se perdio (el Diezmo maximo que se llevaron, los edificios que rompieron,
## la guarnicion que cayo), en que oleada, y que NO es el final: la Regencia se
## puede volver a convocar en cuanto haya `final_audit_resummon_min_units`
## unidades en pie.
##
## Lo que se llevaron no viaja en `final_audit_lost`: StormManager lo cobra al
## oirla y lo publica por `tithe_resolved` y `building_damaged/ruined`, en la
## misma cadena de llamadas. Quien conecte primero es cuestion de orden de
## `_ready`, asi que aqui no se supone nada: se apunta todo lo que llega en el
## mismo frame y el parte se monta diferido, cuando ya ha llegado todo.

const LAYER := 20
const CARD_WIDTH := 540.0

var _root: Control
var _card: PanelContainer
var _wave_label: Label
var _lost_label: Label
var _resummon_label: Label

## Lo ultimo que se apunto, con el frame en que llego.
var _tithe_frame: int = -1
var _tithe_taken: Dictionary = {}
var _hit_frame: int = -1
var _damaged: Dictionary = {}       ## instance_id -> true
var _ruined: Dictionary = {}        ## instance_id -> true
var _lost_frame: int = -1

func _ready() -> void:
	layer = LAYER
	_setup_ui()
	visible = false
	EventBus.final_audit_lost.connect(_on_final_audit_lost)
	EventBus.tithe_resolved.connect(_on_tithe_resolved)
	EventBus.building_damaged.connect(_on_building_damaged)
	EventBus.building_ruined.connect(_on_building_ruined)
	get_viewport().size_changed.connect(_relayout)

func _setup_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.add_child(ModalKit.make_backdrop(0.7))

	_card = ModalKit.make_card(10)
	_root.add_child(_card)
	var column: VBoxContainer = _card.get_child(0)

	column.add_child(ModalKit.make_text(Tr.t("AUDIT_TITLE"), "section", UITheme.TEXT_DIM))
	var title := ModalKit.make_text(Tr.t("LBL_AUDIT_DEFEAT_TITLE"), "title", UITheme.DANGER)
	title.add_theme_font_size_override("font_size", 32)
	column.add_child(title)
	_wave_label = ModalKit.make_text("", "section", UITheme.ACCENT)
	column.add_child(_wave_label)
	column.add_child(ModalKit.make_text(Tr.t("AUDIT_LOST"), "body", UITheme.TEXT))
	column.add_child(UITheme.make_separator())

	column.add_child(UITheme.section_header(Tr.t("LBL_AUDIT_WHAT_WAS_LOST"), UITheme.DANGER))
	_lost_label = ModalKit.make_text("", "body", UITheme.TEXT)
	column.add_child(_lost_label)
	column.add_child(UITheme.make_separator())

	# Lo que mas importa, lo ultimo y en otro color: no se ha perdido la partida.
	column.add_child(ModalKit.make_text(Tr.t("AUDIT_LOST_DESC"), "section", UITheme.POSITIVE))
	_resummon_label = ModalKit.make_text("", "small", UITheme.WARNING)
	column.add_child(_resummon_label)

	column.add_child(ModalKit.make_menu_button(Tr.t("BTN_AUDIT_REBUILD"), UITheme.POSITIVE, close))
	_relayout()

func _relayout() -> void:
	ModalKit.fit_center(_card, CARD_WIDTH, get_viewport().get_visible_rect().size)

# ── Apuntes ──────────────────────────────────────────────────────────

func _frame() -> int:
	return Engine.get_process_frames()

func _on_tithe_resolved(repelled: bool, taken: Dictionary) -> void:
	if repelled:
		return
	_tithe_frame = _frame()
	_tithe_taken = taken.duplicate()

func _roll_hits() -> void:
	if _hit_frame != _frame():
		_hit_frame = _frame()
		_damaged.clear()
		_ruined.clear()

func _on_building_damaged(node: Node3D, _health: int, _max_health: int) -> void:
	_roll_hits()
	if node != null:
		_damaged[node.get_instance_id()] = true

func _on_building_ruined(node: Node3D) -> void:
	_roll_hits()
	if node != null:
		_ruined[node.get_instance_id()] = true

func _on_final_audit_lost(wave: int) -> void:
	_lost_frame = _frame()
	_show.call_deferred(wave, _lost_frame)

# ── Parte ────────────────────────────────────────────────────────────

## Monta y ensena el parte. `frame` es el del asedio perdido: solo cuenta lo que
## llego en ese mismo frame, para no mezclar un Diezmo viejo con esta derrota.
func _show(wave: int, frame: int) -> void:
	var taken: Dictionary = _tithe_taken if _tithe_frame == frame else {}
	var damaged: int = _damaged.size() if _hit_frame == frame else 0
	var ruined: int = _ruined.size() if _hit_frame == frame else 0
	var casualties: Dictionary = {}
	var total_waves: int = 0
	var audit = ProgressionManager.final_audit
	if audit != null:
		casualties = audit.result_summary().get("casualties", {})
		total_waves = audit.wave_count()
	_wave_label.text = Tr.t("LBL_AUDIT_FELL_AT") % (Tr.t("AUDIT_WAVE") % [wave + 1, maxi(total_waves, wave + 1)])
	_lost_label.text = "\n".join(loss_lines(taken, damaged, ruined, casualties))
	_resummon_label.text = resummon_text()
	_relayout()
	visible = true

func close() -> void:
	visible = false

func is_showing() -> bool:
	return visible

## Las lineas de "lo que se perdio". Publico y sin estado para las pruebas.
static func loss_lines(taken: Dictionary, damaged: int, ruined: int, casualties: Dictionary) -> Array:
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
	if damaged > 0 or ruined > 0:
		lines.append(Tr.t("LBL_AUDIT_DAMAGE") % [damaged, ruined])
	var dead: Array = []
	for unit_id in casualties:
		if int(casualties[unit_id]) > 0:
			dead.append("%d %s" % [int(casualties[unit_id]), Tr.t(GameConfig.get_unit_def(unit_id).get("name", unit_id))])
	if not dead.is_empty():
		lines.append("%s: %s" % [Tr.t("LBL_CASUALTIES"), "   ".join(dead)])
	if lines.is_empty():
		lines.append(Tr.t("LBL_AUDIT_NOTHING_LOST"))
	return lines

## Cuanto falta para volver a llamarlos, o que ya se puede. Las cifras son del
## manager y de GameConfig.
static func resummon_text() -> String:
	var need: int = GameConfig.final_audit_resummon_min_units
	var standing: int = CombatManager.roster_size(CombatManager.get_garrison())
	if ProgressionManager.can_resummon_final_audit():
		return Tr.t("LBL_AUDIT_RESUMMON_READY")
	return "%s %s" % [Tr.t("AUDIT_RESUMMON_LOCKED") % need, Tr.t("LBL_AUDIT_STANDING") % standing]
