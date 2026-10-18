extends CanvasLayer
## El boton ESCARAMUZAS del HUD (doc 21 §3.6, 2026-10-14): junto a CONSTRUIR, en
## cuanto hay un Cuartel, con un punto rojo cuando hay motivo para salir. Antes
## las escaramuzas vivian solo en ☰ MENU > COLONIA y nada invitaba a salir.
##
## El motivo es uno solo y lo decide CombatManager.sortie_reason() (la primera
## escaramuza, la avanzadilla antes del Diezmo, repuestos que faltan, una oferta
## nueva sin mirar); la linea de ¿QUE HACER? lee lo mismo. El tooltip lo dice.
##
## Registrado en HudRegistry: se oculta en Ajustes > Interfaz y se mueve en
## Editar disposicion (slot "skirmish_button"). No hace nada por fotograma: se
## repinta con senales.

const LAYER := 10
const BTN_W := 176.0
const DOT := 16.0

var _dock: Control
var _button: Button
var _dot: Panel

func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_setup_ui()
	EventBus.army_changed.connect(func(_a = null): refresh())
	EventBus.building_placed.connect(func(_d, _c): refresh())
	EventBus.building_demolished.connect(func(_n, _c): refresh())
	EventBus.building_upgrade_completed.connect(func(_n, _l): refresh())
	EventBus.game_load_completed.connect(refresh)
	EventBus.sortie_offers_changed.connect(refresh)
	# Tres campanas: mision nueva, ganada o lista tras el descanso; era nueva.
	EventBus.campaign_changed.connect(refresh)
	EventBus.era_advanced.connect(func(_e): refresh())
	EventBus.expedition_started.connect(func(_id, _n): refresh())
	EventBus.expedition_ended.connect(func(_r, _rw, _c): refresh())
	EventBus.encounter_started.connect(func(_i, _b): refresh())
	EventBus.encounter_closed.connect(refresh)
	EventBus.final_audit_summoned.connect(func(_w, _s): refresh())
	EventBus.final_audit_started.connect(func(_w): refresh())
	EventBus.storm_phase_changed.connect(func(_p, _s): refresh())
	# Los repuestos cambian el motivo; el resto de recursos, no.
	EventBus.resource_changed.connect(func(res, _amount, _delta): if String(res) == "parts": refresh())
	refresh.call_deferred()

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_dock = Control.new()
	_dock.name = "SkirmishDock"
	_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock.custom_minimum_size = Vector2(UITheme.touch_px(BTN_W), UITheme.MIN_BTN_H + 12)
	UILayoutManager.apply_layout("SkirmishButton", _dock)
	root.add_child(_dock)

	_button = Button.new()
	_button.name = "SkirmishHudButton"
	_button.focus_mode = Control.FOCUS_NONE
	_button.text = Tr.t("BTN_SKIRMISH")
	_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	UITheme.style_button(_button, UITheme.CAT_MILITARY.darkened(0.15), UITheme.FONT_BUTTON)
	_button.pressed.connect(_on_pressed)
	_dock.add_child(_button)

	# El punto rojo, en la esquina de arriba a la derecha del boton.
	_dot = Panel.new()
	_dot.name = "ReasonDot"
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.DANGER
	style.set_corner_radius_all(int(DOT))
	style.border_color = UITheme.TEXT_BRIGHT
	style.set_border_width_all(2)
	_dot.add_theme_stylebox_override("panel", style)
	_dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_dot.offset_left = -DOT * 0.75
	_dot.offset_right = DOT * 0.25
	_dot.offset_top = -DOT * 0.25
	_dot.offset_bottom = DOT * 0.75
	_dot.visible = false
	_dock.add_child(_dot)

	HudRegistry.register("SkirmishButton", _dock)

## Se ve con un Cuartel en pie; el punto, cuando hay motivo para salir.
func refresh() -> void:
	if _dock == null:
		return
	var shown: bool = ArmyManager.has_military_building()
	_dock.visible = shown
	if not shown:
		_dot.visible = false
		return
	var reason: String = CombatManager.sortie_reason()
	_dot.visible = reason != ""
	_button.tooltip_text = Tr.t(reason) if reason != "" else Tr.t("HINT_SKIRMISH_BUTTON")

func _on_pressed() -> void:
	var panel: Node = _skirmish_panel()
	if panel == null:
		return
	if panel.has_method("open"):
		panel.open()

## SkirmishPanel es hermano en las dos escenas (Main y Main2D).
func _skirmish_panel() -> Node:
	var parent: Node = get_parent()
	if parent != null:
		var sibling: Node = parent.get_node_or_null("SkirmishPanel")
		if sibling != null:
			return sibling
	return get_tree().root.find_child("SkirmishPanel", true, false)

## Para pruebas y capturas.
func button() -> Button:
	return _button

func has_reason_dot() -> bool:
	return _dot != null and _dot.visible
