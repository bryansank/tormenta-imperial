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
## La pestana la coloca UILayoutManager (slot "sandbox_tab": al pie de la
## columna izquierda, bajo lo que haya en ella) y se registra en HudRegistry,
## asi que se puede ocultar en Ajustes > Interfaz y mover en "Editar
## disposicion". La tarjeta sigue a la pestana.
## La tarjeta se abre a la derecha de la columna izquierda (UILayoutConfig:
## left_panel mide 354 como mucho), para no tapar los avisos que salen debajo.
const CARD_LEFT := 364.0
const CARD_GAP := 8.0

var _root: Control
## Lo que se coloca, se mueve y se oculta: mide lo que la pestana. La tarjeta
## cuelga de el (fuera de su rectangulo) para ir y ocultarse con la pestana.
var _dock: Control
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

	_dock = Control.new()
	_dock.name = "SandboxDock"
	_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock.custom_minimum_size = Vector2(TAB_W, UITheme.MIN_BTN_H)
	UILayoutManager.apply_layout("SandboxPanel", _dock)
	_root.add_child(_dock)

	_tab = Button.new()
	_tab.text = Tr.t("BTN_SANDBOX")
	_tab.focus_mode = Control.FOCUS_NONE
	_tab.toggle_mode = true
	_tab.custom_minimum_size = Vector2(TAB_W, UITheme.MIN_BTN_H)
	UITheme.style_card_button(_tab, UITheme.BTN, UITheme.INFO)
	_tab.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tab.toggled.connect(_on_tab_toggled)
	_dock.add_child(_tab)

	_card = ModalKit.make_card(8)
	_card.visible = false
	_card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_card.custom_minimum_size = Vector2(CARD_W, 0)
	_dock.add_child(_card)
	HudRegistry.register("SandboxPanel", _dock)
	get_viewport().size_changed.connect(_relayout)
	# La pestana cambia de sitio al apilarse, al moverla en el editor o al
	# restablecer la disposicion; la tarjeta crece con el aviso de ocupado.
	_dock.item_rect_changed.connect(_relayout)
	_card.resized.connect(_relayout)
	# El texto envuelto mide primero a ancho 0 (altisimo) y encoge al conocer su
	# ancho: eso cambia el minimo, no el tamano, y resized no salta.
	_card.minimum_size_changed.connect(_relayout, CONNECT_DEFERRED)
	UILayoutManager.layout_changed.connect(_relayout)
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
	_relayout()

## La tarjeta junto a la pestana, donde este: a su derecha (y fuera de la
## columna izquierda) si cabe, si no a su izquierda (pestana movida al borde
## derecho), y en una pantalla estrecha (movil en vertical) debajo, al ancho que
## quede. Siempre dentro de la pantalla.
func _relayout() -> void:
	if _card == null or _dock == null or not _dock.is_inside_tree():
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var tab := _dock.get_global_rect()
	var margin := ModalKit.EDGE * 0.5
	var width := CARD_W
	var pos: Vector2
	var right_x := tab.end.x + CARD_GAP
	if tab.position.x < CARD_LEFT:
		right_x = maxf(CARD_LEFT, right_x)
	if right_x + width + margin <= vp.x:
		pos = Vector2(right_x, tab.position.y)
	elif tab.position.x - CARD_GAP - width >= margin:
		pos = Vector2(tab.position.x - CARD_GAP - width, tab.position.y)
	else:
		width = minf(CARD_W, vp.x - ModalKit.EDGE * 2.0)
		pos = Vector2(clampf(tab.position.x, margin, maxf(margin, vp.x - width - margin)), tab.end.y + 6.0)
	_card.custom_minimum_size.x = width
	# Su padre no es un contenedor: sin esto la tarjeta se queda con el alto de
	# la primera medida (texto envuelto a ancho 0) y nunca encoge.
	_card.reset_size()
	var card_h: float = _card.size.y
	pos.y = clampf(pos.y, margin, maxf(margin, vp.y - card_h - margin))
	_card.position = pos - tab.position

## Rectangulo de la tarjeta en pantalla (para las pruebas).
func card_rect() -> Rect2:
	return _card.get_global_rect()

func tab_button() -> Button:
	return _tab

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
