extends CanvasLayer
## Las ayudas en pantalla: los globos que apuntan a un control del HUD, las
## tarjetas de consejo (TutorialManager.TIPS) y la guia de edificios. Tambien
## crea el indice de AYUDA (HelpIndexPanel).
##
## Reglas (docs/07 bug 6, docs/23-onboarding.md):
##   - UNA ayuda a la vez. Las demas esperan en una cola por prioridad
##     (HelpCatalog.priority): los consejos de algo que acaba de pasar van
##     delante, los globos basicos detras. Nunca seis a la vez.
##   - Cada una tiene ✕ y se cierra sola (6-12 s segun el texto, con barra). El
##     reloj se para con el dedo o el raton encima.
##   - Cerrada o agotada, queda vista (TutorialManager.helps_seen) y no vuelve a
##     salir sola. El indice de AYUDA la vuelve a abrir cuando se pida.
##   - Contextual: los globos basicos salen al terminar (o saltar) el tutorial;
##     el de ESCARAMUZAS cuando aparece su boton; los consejos, cuando pasa lo
##     que explican. Mientras el tutorial guiado esta en marcha no sale ninguna
##     sola: el tutorial ya dice que hacer.
##   - El interruptor global (GameConfig.ui_helper_visible, Ajustes > Interfaz
##     y el indice de AYUDA) apaga las que salen solas. Las pedidas desde el
##     indice salen igual.
##   - Se callan (y vuelven luego, sin contar como vistas) con una ventana
##     abierta, en pausa, al colocar un edificio en tactil y, los globos, con la
##     Tormenta encima. Los consejos no se callan por la Tormenta: la explican.
##
## Los globos los coloca UILayoutManager (slots tip_*), bajo el panel del que
## hablan. Las tarjetas de consejo van abajo al centro en su propia capa (19),
## por encima de las ventanas, porque a veces explican una ventana (mercado).

const HelpCallout := preload("res://scripts/ui/HelpCallout.gd")
const HelpCatalog := preload("res://scripts/ui/HelpCatalog.gd")
const HelpTargets := preload("res://scripts/ui/HelpTargets.gd")
const HelpIndexScene := preload("res://scenes/ui/HelpIndexPanel.tscn")

## Node name of the Skirmish callout, so tests and tools can find it.
const SKIRMISH_CALLOUT_NAME := "SkirmishCallout"
## Width of the Skirmish callout and the gap it keeps from the sidebar button.
const SKIRMISH_CALLOUT_WIDTH := 260
const SKIRMISH_CALLOUT_GAP := 12
## Sidebar buttons hang from the right edge at offset_left = -176 (see
## SkirmishPanel/ArmyPanel); the callout sits to their left.
const SIDEBAR_BTN_LEFT := 176
## Capa de las tarjetas de consejo y del marco que senala: encima de las
## ventanas (12+) y del tablero (18), debajo de la victoria (20).
const TIP_LAYER := 19
const TIP_WIDTH := 480.0
## Hueco bajo la tarjeta de consejo: el boton CONSTRUIR vive abajo al centro.
const TIP_BOTTOM_GAP := 96.0
const EDGE := 16.0
## Respiro entre dos ayudas que salen solas: una detras de otra sin pausa se
## siente como un muro aunque sea de una en una.
const GAP_SECONDS := 1.2

## Ayuda -> panel_id de su hueco en UILayoutConfig.
const CALLOUT_SLOTS := {
	"callout_resources": "HelperPanel.tip_resources",
	"callout_menus": "HelperPanel.tip_menus",
	"callout_objective": "HelperPanel.tip_objective",
	"callout_build": "HelperPanel.tip_build",
	"callout_zoom": "HelperPanel.tip_zoom",
}
## Los globos que salen al terminar o saltar el tutorial, por orden.
const BASICS_AFTER_GUIDE := ["callout_objective", "callout_resources", "callout_camera", "callout_zoom", "callout_menus"]
## Tips that only make sense with the touch buttons on screen, and the one that
## replaces them on a desktop.
const TOUCH_TIPS := ["HelperPanel.tip_camera_touch", "HelperPanel.tip_zoom"]
const DESKTOP_TIPS := ["HelperPanel.tip_camera"]

var _callouts: Control
var _help_btn: Button
var _guide_panel: PanelContainer
var _backdrop: ColorRect
var _guide_open := false
var _skirmish_callout: PanelContainer
var _sidebar_visible := false
var _storm_silenced := false
## While a building is being placed the touch camera tips step aside: the right
## column grows with rotate-building + CANCEL and the zoom tip would cover them.
var _placing := false
## Every layout-placed tip: panel_id -> its HelpCallout.
var _tips: Dictionary = {}
var _tip_layer: CanvasLayer
var _tip_card: PanelContainer
var _pointer: Panel
var _index: CanvasLayer

## Cola: {id, prio, seq, forced}. `_current` es la que esta en pantalla.
var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _seq := 0
var _gap := 0.0
var _pulse := 0.0

func _ready() -> void:
	# Above the HUD (10-11). UIManager stacks open windows from layer 12 up, so
	# at 14 a callout would draw OVER an open window: that is why the callouts
	# go quiet while any window is open, instead of relying on layer order.
	layer = 14
	_setup_ui()
	UIManager.register_panel(self, "HelperPanel.modal")
	UIManager.window_opened.connect(func(_w): _refresh_callouts())
	UIManager.window_closed.connect(func(_w): _refresh_callouts())
	EventBus.storm_incoming.connect(func(_s): _set_storm_silenced(true))
	EventBus.tithe_resolved.connect(func(_paid, _taken): _set_storm_silenced(false))
	EventBus.storm_false_alarm.connect(func(_deferred): _set_storm_silenced(false))
	EventBus.touch_controls_changed.connect(func(_enabled): _refresh_tips())
	EventBus.helper_visibility_changed.connect(func(_vis): _refresh_callouts())
	# La pausa y el menu principal no estan en la pila de UIManager: un vigia que
	# corre en pausa mira get_tree().paused y avisa al cambiar.
	var watcher := Node.new()
	watcher.name = "PauseWatcher"
	watcher.process_mode = Node.PROCESS_MODE_ALWAYS
	watcher.set_script(_PauseWatcher)
	watcher.set("owner_panel", self)
	add_child(watcher)
	UILayoutManager.layout_changed.connect(_refresh_tips)
	EventBus.building_selected_for_placement.connect(func(_d): _set_placing(true))
	EventBus.request_move_building.connect(func(_b): _set_placing(true))
	EventBus.building_placement_cancelled.connect(func(): _set_placing(false))
	EventBus.building_moved.connect(func(_from, _to): _set_placing(false))
	EventBus.building_placed.connect(func(_d, _c): _set_placing(false))
	EventBus.building_deselected.connect(func(): _set_placing(false))
	EventBus.sidebar_toggled.connect(_on_sidebar_toggled)
	EventBus.building_placed.connect(func(_d, _c): _update_skirmish_callout())
	EventBus.building_demolished.connect(func(_n, _c): _update_skirmish_callout())
	EventBus.army_changed.connect(func(_a = null): _update_skirmish_callout())
	EventBus.game_new_started.connect(_on_game_started)
	EventBus.game_load_completed.connect(_on_game_started)
	# Las ayudas nuevas.
	EventBus.tutorial_tip_requested.connect(_on_tip_requested)
	EventBus.help_reopen_requested.connect(show_help)
	EventBus.tutorial_guide_finished.connect(_on_guide_finished)
	_update_skirmish_callout()
	_refresh_tips()
	_refresh_callouts()

func _setup_ui() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# AYUDA — one more entry of the ☰ sidebar: opens the help index.
	_help_btn = Button.new()
	_help_btn.name = "HelpButton"
	_help_btn.text = Tr.t("BTN_HELP")
	_help_btn.tooltip_text = Tr.t("BTN_HELP_INDEX_TIP")
	_help_btn.custom_minimum_size = Vector2(UILayoutConfig.SIDEBAR_BTN_WIDTH, UILayoutConfig.SIDEBAR_BTN_HEIGHT)
	_help_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_help_btn.offset_left = -(UILayoutConfig.SIDEBAR_BTN_WIDTH + 12)
	_help_btn.offset_top = UILayoutManager.get_sidebar_button_offset("HelperPanel.button")
	UITheme.style_card_button(_help_btn, UITheme.BTN.lightened(0.05), UITheme.INFO)
	_help_btn.pressed.connect(open_index)
	_help_btn.visible = false  # Start collapsed with sidebar
	root.add_child(_help_btn)

	# Callout layer (tips anchored around the screen)
	_callouts = Control.new()
	_callouts.name = "Callouts"
	_callouts.set_anchors_preset(Control.PRESET_FULL_RECT)
	_callouts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_callouts)

	for panel_id in ["HelperPanel.tip_resources", "HelperPanel.tip_menus", "HelperPanel.tip_objective",
			"HelperPanel.tip_build", "HelperPanel.tip_camera_touch", "HelperPanel.tip_zoom", "HelperPanel.tip_camera"]:
		_add_tip(panel_id)

	# Right, beside the Skirmish sidebar button.
	var skirmish_x := -(SIDEBAR_BTN_LEFT + SKIRMISH_CALLOUT_GAP + SKIRMISH_CALLOUT_WIDTH)
	var skirmish_y := UILayoutManager.get_sidebar_button_offset("SkirmishPanel.button")
	_skirmish_callout = _make_callout()
	_skirmish_callout.name = SKIRMISH_CALLOUT_NAME
	_skirmish_callout.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skirmish_callout.offset_left = skirmish_x
	_skirmish_callout.offset_top = skirmish_y
	_skirmish_callout.offset_right = skirmish_x + SKIRMISH_CALLOUT_WIDTH
	_skirmish_callout.offset_bottom = skirmish_y + 10
	_skirmish_callout.grow_vertical = Control.GROW_DIRECTION_END
	_skirmish_callout.custom_minimum_size = Vector2(SKIRMISH_CALLOUT_WIDTH, 0)
	_skirmish_callout.setup("callout_skirmish", HelpCatalog.title("callout_skirmish"), HelpCatalog.body("callout_skirmish"))
	_callouts.add_child(_skirmish_callout)

	# ── Building guide modal ──
	_backdrop = UITheme.make_backdrop()
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_toggle_guide()
	)
	root.add_child(_backdrop)

	_guide_panel = PanelContainer.new()
	_guide_panel.visible = false
	UILayoutManager.apply_layout("HelperPanel.modal", _guide_panel)
	_guide_panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	root.add_child(_guide_panel)

	var margin := MarginContainer.new()
	for side in ["top", "left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	_guide_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	vbox.add_child(UITheme.make_panel_header(Tr.t("LBL_GUIDE_TITLE"), _toggle_guide))
	vbox.add_child(UITheme.make_separator())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 14)
	scroll.add_child(list)

	for data in _load_buildings():
		list.add_child(_make_building_entry(data))

	# ── Capa de consejos: la tarjeta de abajo y el marco que senala ──
	_tip_layer = CanvasLayer.new()
	_tip_layer.name = "TipLayer"
	_tip_layer.layer = TIP_LAYER
	add_child(_tip_layer)
	var tip_root := Control.new()
	tip_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	tip_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_layer.add_child(tip_root)

	_pointer = Panel.new()
	_pointer.name = "HelpPointer"
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0, 0, 0, 0)
	ps.border_color = UITheme.INFO.lightened(0.35)
	ps.set_border_width_all(3)
	ps.set_corner_radius_all(6)
	ps.shadow_color = Color(UITheme.INFO, 0.5)
	ps.shadow_size = 6
	_pointer.add_theme_stylebox_override("panel", ps)
	_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer.visible = false
	tip_root.add_child(_pointer)

	_tip_card = _make_callout()
	_tip_card.name = "TipCard"
	_tip_card.anchor_left = 0.5
	_tip_card.anchor_right = 0.5
	_tip_card.anchor_top = 1.0
	_tip_card.anchor_bottom = 1.0
	_tip_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tip_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tip_root.add_child(_tip_card)

	# El indice de AYUDA, en su propia capa (la pone UIManager al abrirse).
	_index = HelpIndexScene.instantiate()
	_index.name = "HelpIndexPanel"
	add_child(_index)
	_index.set("helper", self)

func _make_callout() -> PanelContainer:
	var c: PanelContainer = HelpCallout.new()
	c.visible = false
	c.closed.connect(_on_help_closed)
	return c

## Un globo en su hueco de UILayoutConfig. Empieza oculto: sale por la cola.
func _add_tip(panel_id: String) -> PanelContainer:
	var box := _make_callout()
	box.name = "Tip_" + panel_id.get_slice(".", 1)
	UILayoutManager.apply_layout(panel_id, box)
	_callouts.add_child(box)
	_tips[panel_id] = box
	return box

# ══════════════════════════════════════════════════════════════════════
# ── La cola ──
# ══════════════════════════════════════════════════════════════════════

## Pone una ayuda en la cola si no se habia visto ni esta ya esperando.
func enqueue(help_id: String, forced: bool = false) -> void:
	if not HelpCatalog.has(help_id) or not HelpCatalog.allowed(help_id):
		return
	if not forced and TutorialManager.has_seen_help(help_id) and HelpCatalog.kind(help_id) != "tip":
		return
	if String(_current.get("id", "")) == help_id:
		return
	for q in _queue:
		if String(q["id"]) == help_id:
			q["forced"] = bool(q["forced"]) or forced
			return
	_seq += 1
	_queue.append({"id": help_id, "prio": HelpCatalog.priority(help_id), "seq": _seq, "forced": forced})
	_pump()

## La pide el jugador (indice de AYUDA): sale ya, aunque haya otra en pantalla
## y aunque las ayudas automaticas esten apagadas.
func show_help(help_id: String) -> void:
	if not HelpCatalog.has(help_id):
		return
	if not _current.is_empty():
		var cur: Dictionary = _current
		_suspend_current()
		if String(cur["id"]) != help_id:
			_queue.push_front(cur)
	for i in range(_queue.size() - 1, -1, -1):
		if String(_queue[i]["id"]) == help_id:
			_queue.remove_at(i)
	_seq += 1
	_gap = 0.0
	_queue.push_front({"id": help_id, "prio": 1000, "seq": -_seq, "forced": true})
	_pump()

func _on_tip_requested(tip_id: String, _title: String, _body: String) -> void:
	# El consejo llega ya marcado en tips_seen (TutorialManager lo marca al
	# ofrecerlo): va a la cola igual, con la prioridad de los consejos.
	if not HelpCatalog.has(tip_id):
		return
	_seq += 1
	for q in _queue:
		if String(q["id"]) == tip_id:
			return
	_queue.append({"id": tip_id, "prio": HelpCatalog.TIP_PRIORITY, "seq": _seq, "forced": false})
	_pump()

func _on_guide_finished(skipped: bool) -> void:
	if skipped:
		enqueue("callout_build")
	for id in BASICS_AFTER_GUIDE:
		enqueue(id)

## Al cargar una partida con el tutorial ya hecho, lo que quedo sin ver de lo
## basico vuelve a la cola (una vez visto, ya no).
func _on_game_started() -> void:
	_update_skirmish_callout()
	if TutorialManager.guide_state in [TutorialManager.GUIDE_DONE, TutorialManager.GUIDE_SKIPPED]:
		for id in BASICS_AFTER_GUIDE:
			enqueue(id)

## ¿Puede salir esta ayuda ahora mismo?
func _can_show(item: Dictionary) -> bool:
	var id := String(item["id"])
	var forced := bool(item["forced"])
	if get_tree().paused or _guide_open:
		return false
	# Con el indice de AYUDA abierto se esta eligiendo que leer: nada encima.
	if _index != null and _index.has_method("is_open") and _index.call("is_open"):
		return false
	if not forced:
		if not GameConfig.ui_helper_visible:
			return false
		if TutorialManager.is_guide_active():
			return false
	var k := HelpCatalog.kind(id)
	if k == "callout":
		if UIManager.is_any_window_open():
			return false
		if _storm_silenced and not forced:
			return false
		if not _callout_relevant(id):
			return false
		# Sin sitio junto a su control (pantalla estrecha, tablet con la columna
		# central bajada): sale en la tarjeta de abajo, con el marco senalandolo.
		return true
	# Consejos y guias: tarjeta de abajo. Solo esperan si se esta colocando con
	# el dedo (taparian la columna de CANCELAR).
	if _placing and GameConfig.touch_controls_enabled() and not forced:
		return false
	return true

## El globo tiene sentido ahora: el de ESCARAMUZAS solo con su boton a la vista,
## el de zoom solo con los botones tactiles, y ninguno de camara colocando con
## el dedo (la columna derecha crece con CANCELAR).
func _callout_relevant(id: String) -> bool:
	match id:
		"callout_skirmish":
			return _skirmish_gate()
		"callout_zoom":
			return GameConfig.touch_controls_enabled() and not _placing
		"callout_camera":
			return not (_placing and GameConfig.touch_controls_enabled())
	return true

## El globo de pantalla que ensena `id`, o null si ahora no cabe junto a su
## control (pantalla estrecha, sin flechas en pantalla, colocando...).
func _callout_for(id: String) -> PanelContainer:
	if id == "callout_skirmish":
		return _skirmish_callout if _skirmish_gate() else null
	var panel_id := ""
	if id == "callout_camera":
		panel_id = "HelperPanel.tip_camera_touch" if GameConfig.touch_controls_enabled() else "HelperPanel.tip_camera"
	else:
		panel_id = String(CALLOUT_SLOTS.get(id, ""))
	if panel_id == "" or not _tips.has(panel_id):
		return null
	return _tips[panel_id] if _slot_allowed(panel_id) else null

func _pump() -> void:
	if not is_inside_tree():
		return
	if not _current.is_empty():
		# La que esta en pantalla sigue si puede; si ya no (se abrio una ventana,
		# llego la Tormenta), se aparta sin contar como vista y vuelve luego.
		if not _can_show(_current):
			var cur: Dictionary = _current
			_suspend_current()
			_queue.push_front(cur)
		return
	if _gap > 0.0 or _queue.is_empty():
		return
	_queue.sort_custom(func(a, b):
		if int(a["prio"]) != int(b["prio"]):
			return int(a["prio"]) > int(b["prio"])
		return int(a["seq"]) < int(b["seq"]))
	for i in _queue.size():
		var item: Dictionary = _queue[i]
		if HelpCatalog.kind(String(item["id"])) != "tip" and not bool(item["forced"]) \
				and TutorialManager.has_seen_help(String(item["id"])):
			_queue.remove_at(i)
			_pump()
			return
		if _can_show(item):
			_queue.remove_at(i)
			_show(item)
			return

func _show(item: Dictionary) -> void:
	var id := String(item["id"])
	var box: PanelContainer = _callout_for(id) if HelpCatalog.kind(id) == "callout" else null
	if box == null:
		box = _tip_card
		_fit_tip_card()
	if box == null:
		return
	box.setup(id, HelpCatalog.title(id), HelpCatalog.body(id))
	box.start()
	# Entra con un fundido corto: llama la vista sin interrumpir.
	box.modulate.a = 0.0
	create_tween().tween_property(box, "modulate:a", 1.0, 0.25)
	_current = item.duplicate()
	_current["box"] = box
	_refresh_callouts()

func _suspend_current() -> void:
	if _current.is_empty():
		return
	var box: Variant = _current.get("box", null)
	_current.erase("box")
	if box is PanelContainer and is_instance_valid(box):
		(box as PanelContainer).call("suspend")
	_current = {}
	_pointer.visible = false

func _on_help_closed(help_id: String, _reason: String) -> void:
	TutorialManager.mark_help_seen(help_id)
	if String(_current.get("id", "")) == help_id:
		_current = {}
	_pointer.visible = false
	_gap = GAP_SECONDS
	_pump()

func _process(delta: float) -> void:
	if _gap > 0.0:
		_gap -= delta
		if _gap <= 0.0:
			_gap = 0.0
			_pump()
	_pulse += delta
	_update_pointer()

## El marco azul alrededor del control del que habla la ayuda en pantalla.
func _update_pointer() -> void:
	if _current.is_empty():
		_pointer.visible = false
		return
	var target := HelpCatalog.target(String(_current["id"]))
	var rect := HelpTargets.rect(get_tree(), target) if target != "" else Rect2()
	if rect.size.x < 1.0:
		_pointer.visible = false
		return
	rect = rect.grow(6.0)
	_pointer.visible = true
	_pointer.position = rect.position
	_pointer.size = rect.size
	_pointer.modulate.a = 0.6 + 0.4 * sin(_pulse * 4.0)

func _fit_tip_card() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var tw: float = minf(TIP_WIDTH, vp.x - EDGE * 2.0)
	_tip_card.custom_minimum_size = Vector2(tw, 0)
	_tip_card.offset_left = -tw * 0.5
	_tip_card.offset_right = tw * 0.5
	_tip_card.offset_bottom = -TIP_BOTTOM_GAP
	_tip_card.offset_top = -TIP_BOTTOM_GAP

# ── Para pruebas y sondas ────────────────────────────────────────────

func current_help() -> String:
	return String(_current.get("id", ""))

func current_box() -> PanelContainer:
	var b: Variant = _current.get("box", null)
	return b if b is PanelContainer and is_instance_valid(b) else null

func queued_ids() -> Array:
	return _queue.map(func(q): return String(q["id"]))

## Cuantas ayudas hay a la vista ahora mismo (debe ser 0 o 1).
func visible_help_count() -> int:
	var n := 0
	for box in _all_boxes():
		if box.is_visible_in_tree():
			n += 1
	return n

func _all_boxes() -> Array:
	var out: Array = _tips.values()
	out.append(_skirmish_callout)
	out.append(_tip_card)
	return out

## Sin el respiro entre ayudas (pruebas).
func skip_gap() -> void:
	_gap = 0.0
	_pump()

func is_tip_showing() -> bool:
	return _tip_card.visible

func pending_tips() -> int:
	return _queue.filter(func(q): return HelpCatalog.kind(String(q["id"])) == "tip").size()

# ══════════════════════════════════════════════════════════════════════
# ── Indice y guia ──
# ══════════════════════════════════════════════════════════════════════

func open_index() -> void:
	if _index != null and _index.has_method("open"):
		_index.open()

func help_index() -> CanvasLayer:
	return _index

func open_building_guide() -> void:
	if not _guide_open:
		_toggle_guide()

func _load_buildings() -> Array:
	var result: Array = []
	var dir := DirAccess.open("res://data/buildings")
	if not dir:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var res = load("res://data/buildings/" + file_name)
			if res is BuildingData:
				result.append(res)
		file_name = dir.get_next()
	result.sort_custom(func(a, b): return a.get_display_name() < b.get_display_name())
	return result

func _make_building_entry(data: BuildingData) -> VBoxContainer:
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 2)

	var title := UITheme.make_label("%s  (%dx%d)" % [data.get_display_name(), data.grid_size.x, data.grid_size.y], "body", UITheme.ACCENT)
	entry.add_child(title)

	var meta := UITheme.make_label(_meta_line(data), "small", UITheme.TEXT_DIM)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry.add_child(meta)

	if not data.get_description().is_empty():
		var desc := UITheme.make_label(data.get_description(), "small", UITheme.TEXT)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.add_child(desc)
	return entry

## "Costo: 120 oro, 80 madera · Trabajadores: 3 · Produce: 8 oro"
func _meta_line(data: BuildingData) -> String:
	var parts: Array[String] = []

	var costs: Array[String] = []
	for pair in [[data.cost_gold, "gold"], [data.cost_steel, "steel"], [data.cost_oil, "oil"], [data.cost_wood, "wood"]]:
		if pair[0] > 0:
			costs.append("%d %s" % [pair[0], Tr.res_name(pair[1])])
	parts.append("%s: %s" % [Tr.t("LBL_GUIDE_COST"), ", ".join(costs) if not costs.is_empty() else Tr.t("LBL_FREE")])

	if data.workers_required > 0:
		parts.append("%s: %d" % [Tr.t("LBL_GUIDE_WORKERS"), data.workers_required])

	var produces: Array[String] = []
	for pair in [[data.produces_gold, "gold"], [data.produces_steel, "steel"], [data.produces_oil, "oil"], [data.produces_wood, "wood"]]:
		if pair[0] > 0:
			produces.append("%d %s" % [pair[0], Tr.res_name(pair[1])])
	if not produces.is_empty():
		parts.append("%s: %s" % [Tr.t("LBL_GUIDE_PRODUCES"), ", ".join(produces)])
	if data.population_capacity > 0:
		parts.append("%s: +%d" % [Tr.t("LBL_GUIDE_HOUSING"), data.population_capacity])
	if data.morale_bonus > 0:
		parts.append("%s: +%d" % [Tr.t("LBL_GUIDE_MORALE"), data.morale_bonus])

	return " · ".join(parts)

# ══════════════════════════════════════════════════════════════════════
# ── Visibilidad ──
# ══════════════════════════════════════════════════════════════════════

## Enciende o apaga las ayudas que salen solas (lo mismo que Ajustes >
## Interfaz). Apagar no borra lo pendiente: al volver a encender, sigue.
func set_auto_help(enabled: bool) -> void:
	HudRegistry.set_hidden("HelperPanel.callouts", not enabled)
	_refresh_callouts()

## Shows the callout layer if help is on and nothing on screen asks for quiet;
## and lets the queue react (the one on screen steps aside, or the next comes).
func _refresh_callouts() -> void:
	if _callouts == null:
		return
	var forced_now := bool(_current.get("forced", false))
	_callouts.visible = (GameConfig.ui_helper_visible or forced_now) and not is_quiet()
	_help_btn.modulate = Color(1, 1, 1, 1.0 if GameConfig.ui_helper_visible else 0.55)
	_pump()

## Something more important is on screen: an open window, the pause or title
## menu (the tree is paused), or the Storm.
func is_quiet() -> bool:
	return _storm_silenced or UIManager.is_any_window_open() or get_tree().paused

func _set_storm_silenced(silenced: bool) -> void:
	_storm_silenced = silenced
	_refresh_callouts()

func is_showing_callouts() -> bool:
	return _callouts.visible

func _set_placing(placing: bool) -> void:
	_placing = placing
	_refresh_tips()

## Si el hueco `panel_id` cabe ahora: pantalla estrecha, perfil movil, flechas
## tactiles en pantalla, colocando, menu ☰ abierto.
func _slot_allowed(panel_id: String) -> bool:
	var touch := GameConfig.touch_controls_enabled()
	var narrow := UILayoutManager.is_narrow() or UILayoutManager.is_column_narrow() \
		or DeviceProfile.layout_variant() == "compact"
	var show := true
	if narrow and not panel_id in UILayoutConfig.NARROW_TIPS:
		show = false
	if DeviceProfile.layout_variant() == "compact":
		show = false
	if panel_id in TOUCH_TIPS:
		show = show and touch and not _placing
	if panel_id in DESKTOP_TIPS:
		show = show and not touch
	if panel_id == "HelperPanel.tip_menus":
		show = show and not _sidebar_visible
	return show

## Un cambio de disposicion puede dejar sin sitio al globo en pantalla.
func _refresh_tips() -> void:
	_update_skirmish_callout()
	_pump()

func _skirmish_gate() -> bool:
	return _sidebar_visible and ArmyManager.barracks_count() > 0 and not UILayoutManager.is_narrow()

## El globo de ESCARAMUZAS sale (una vez) cuando aparece su boton: hay Cuartel y
## la columna ☰ esta abierta.
func _update_skirmish_callout(_arg = null) -> void:
	if _skirmish_callout == null:
		return
	if _skirmish_gate():
		enqueue("callout_skirmish")
	elif String(_current.get("id", "")) == "callout_skirmish":
		var cur: Dictionary = _current
		_suspend_current()
		_queue.push_front(cur)

func _on_sidebar_toggled(is_visible: bool) -> void:
	_sidebar_visible = is_visible
	_help_btn.visible = is_visible
	_refresh_tips()

## True while the Skirmish callout is actually on screen.
func is_skirmish_callout_shown() -> bool:
	return _skirmish_callout != null and _callouts.visible and _skirmish_callout.visible

func _toggle_guide() -> void:
	_guide_open = not _guide_open
	_guide_panel.visible = _guide_open
	_backdrop.visible = _guide_open
	if _guide_open:
		UIManager.open_panel(self)
	else:
		UIManager.close_panel(self)
		# La pila le cambio la capa al abrir: vuelve a la suya.
		layer = 14

## Vigia de la pausa: el arbol en pausa no llama al _process de HelperPanel.
const _PauseWatcher := preload("res://scripts/ui/PauseWatcher.gd")
