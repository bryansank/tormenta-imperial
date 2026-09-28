extends CanvasLayer
## Las herramientas del modo Sandbox: una pestana "SANDBOX" siempre a la vista
## en el borde izquierdo (es tambien la marca de que esta partida es de pruebas)
## y, al pulsarla, una tarjeta con lo que en Sandbox no llega solo:
##
##   Invocar tormenta   el ciclo entero, aviso -> ceniza -> tormenta -> Diezmo,
##                      sin falsa alarma; al volver la calma se para
##   Invocar Auditoria  la convoca PENDIENTE; se entra con QUE BAJEN
##
## Fuera de Sandbox no existe: se oculta entera. No sabe nada de reglas; pide a
## StormManager y a ProgressionManager, que son quienes deciden si se puede.

const LAYER := 11
const TAB_W := 120.0
const CARD_W := 300.0
## Debajo de la barra de recursos (ranura top_left) y de su boton de pausa.
const TOP := 150.0

var _root: Control
var _tab: Button
var _card: PanelContainer
var _storm_btn: Button
var _audit_btn: Button
var _status: Label

func _ready() -> void:
	layer = LAYER
	_setup_ui()
	EventBus.game_load_completed.connect(refresh)
	EventBus.game_new_started.connect(refresh)
	EventBus.storm_phase_changed.connect(func(_p, _s): refresh())
	EventBus.final_audit_summoned.connect(func(_w, _s): refresh())
	EventBus.final_audit_lost.connect(func(_w): refresh())
	EventBus.final_audit_started.connect(func(_w): refresh())
	EventBus.final_audit_wave_cleared.connect(func(_w, _r): refresh())
	refresh()

func _setup_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_tab = Button.new()
	_tab.text = Tr.t("BTN_SANDBOX")
	_tab.focus_mode = Control.FOCUS_NONE
	_tab.toggle_mode = true
	_tab.custom_minimum_size = Vector2(TAB_W, UITheme.MIN_BTN_H)
	UITheme.style_card_button(_tab, UITheme.BTN, UITheme.INFO)
	_tab.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_tab.position = Vector2(ModalKit.EDGE * 0.5, TOP)
	_tab.toggled.connect(_on_tab_toggled)
	_root.add_child(_tab)

	_card = ModalKit.make_card(8)
	_card.visible = false
	_card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_card.position = Vector2(ModalKit.EDGE * 0.5, TOP + UITheme.MIN_BTN_H + 6.0)
	_card.custom_minimum_size = Vector2(CARD_W, 0)
	_root.add_child(_card)
	var column: VBoxContainer = _card.get_child(0)
	column.add_child(ModalKit.make_text(Tr.t("LBL_SANDBOX_TOOLS"), "section", UITheme.INFO.lightened(0.3)))
	_storm_btn = ModalKit.make_menu_button(Tr.t("BTN_SANDBOX_STORM"), UITheme.WARNING, _on_storm)
	column.add_child(_storm_btn)
	_audit_btn = ModalKit.make_menu_button(Tr.t("BTN_SANDBOX_AUDIT"), UITheme.DANGER, _on_audit)
	column.add_child(_audit_btn)
	_status = ModalKit.make_text("", "small", UITheme.WARNING)
	column.add_child(_status)
	var hint := ModalKit.make_text(Tr.t("LBL_SANDBOX_HINT"), "small", UITheme.TEXT_DIM)
	column.add_child(hint)

## Visible solo en Sandbox; los botones, apagados cuando no pueden hacer nada.
func refresh() -> void:
	visible = GameMode.sandbox_tools()
	if not visible:
		return
	var storm_busy: bool = StormManager.get_phase() != StormCycle.Phase.CALM
	var audit = ProgressionManager.final_audit
	var audit_busy: bool = audit != null and (audit.is_active() or audit.is_pending())
	_storm_btn.disabled = storm_busy or StormManager.is_halted()
	_audit_btn.disabled = audit_busy
	var notes: Array = []
	if storm_busy:
		notes.append(Tr.t("LBL_SANDBOX_STORM_BUSY"))
	if audit_busy:
		notes.append(Tr.t("LBL_SANDBOX_AUDIT_BUSY"))
	_status.text = "\n".join(notes)
	_status.visible = not notes.is_empty()

func is_open() -> bool:
	return visible and _card.visible

func open() -> void:
	_tab.button_pressed = true

func _on_tab_toggled(on: bool) -> void:
	_card.visible = on
	refresh()

func _on_storm() -> void:
	StormManager.invoke_storm()
	refresh()

func _on_audit() -> void:
	ProgressionManager.invoke_final_audit()
	refresh()
