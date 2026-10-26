class_name ProcessActionsPanel
## La seccion FABRICAR de la ficha (feat/recetas-tarjetas, 2026-10-25): las
## recetas de un edificio (o el minado a mano de un yacimiento) como TARJETAS
## GRANDES (scripts/ui/ProcessCard.gd) en una rejilla:
##
##   [icono] FABRICAR
##   (Nucleo) [Nucleo] [Aserradero] [Mina] [Fundicion] [Refineria] [A mano]
##   ┌ tarjeta ┐ ┌ tarjeta ┐        tablet y PC: dos columnas si caben
##   ┌ tarjeta ┐ ┌ tarjeta ┐        telefono: una por fila, a todo el ancho
##
## Se ven TODAS las recetas del edificio: las cerradas, apagadas con su
## candado y el porque ("Falta acero: llega con la Fundición"), para que se
## sepa lo que viene. El Nucleo, que hace de todo, separa sus talleres en
## pestanas (lo suyo, uno por taller y lo que se saca a mano).
##
## Un edificio hace una receta a la vez: la que trabaja ensena su cola, su
## barra y cancelar; las demas dicen "Ocupado: ...". Las tarjetas se ponen al
## dia con cuentagotas (REFRESH_MS); la barra, cada fotograma.

const CT := preload("res://scripts/ui/CartoonTheme.gd")
const TextKit := preload("res://scripts/ui/TextKit.gd")
const ProcessCard := preload("res://scripts/ui/ProcessCard.gd")
const MapGeneratorScript := preload("res://scripts/map/MapGenerator.gd")

## Cada cuanto se recalcula lo que alcanza (MAX, bloqueos) mientras el panel
## esta abierto. No cada fotograma: rendimiento es prioridad.
const REFRESH_MS := 300

## Pestanas del Nucleo: lo suyo, un taller por pestana (en este orden; los que
## no esten aqui van detras) y lo que se saca a mano.
const CORE_TAB_OWN := "own"
const CORE_TAB_HAND := "hand"
const CORE_WORKSHOP_ORDER := ["sawmill", "gold_mine", "foundry", "refinery"]

## La ultima pestana del Nucleo que se eligio (se recuerda mientras dure la
## sesion: al volver a tocar el Nucleo se abre donde se dejo).
static var _core_tab_memory := ""

var _host: VBoxContainer
var _header: HBoxContainer
var _header_label: Label
var _tabs: HFlowContainer
var _grid: GridContainer
var _cards: Array = []
var _count := 0
var _node: Node = null
var _is_deposit := false
var _data: BuildingData = null
## Pestanas del Nucleo: id -> Array de procesos.
var _groups: Dictionary = {}
var _group_order: Array = []
var _tab := ""
var _busy_token := ""
var _forced_busy := false
var _last_refresh_ms := 0

## `host` es la caja de la ficha donde vive la seccion (la ficha la ensena u
## oculta segun action_count()).
func _init(host: VBoxContainer) -> void:
	_host = host
	_host.name = "RecipeSection"
	_host.add_theme_constant_override("separation", 8 if CT.is_phone() else 10)
	_header = CT.recipe_header(Tr.t("RCP_SECTION"), "build")
	_header.name = "RecipeHeader"
	_header_label = _header.find_child("RecipeTitle", true, false)
	_host.add_child(_header)
	_tabs = HFlowContainer.new()
	_tabs.name = "RecipeTabs"
	_tabs.add_theme_constant_override("h_separation", 6)
	_tabs.add_theme_constant_override("v_separation", 6)
	_tabs.visible = false
	_host.add_child(_tabs)
	_grid = GridContainer.new()
	_grid.name = "RecipeGrid"
	_grid.columns = 1
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", CT.recipe_gap())
	_grid.add_theme_constant_override("v_separation", CT.recipe_gap())
	_grid.resized.connect(_fit_columns)
	_host.add_child(_grid)

func clear() -> void:
	_count = 0
	_cards.clear()
	_forced_busy = false
	_busy_token = ""
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.free()
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_tabs.visible = false
	_groups.clear()
	_group_order.clear()

## Recetas (o avisos) que ofrece la seccion. Sin ninguna, la ficha la esconde.
func action_count() -> int:
	return _count

## Las tarjetas que hay ahora (ProcessCard), para las pruebas.
func cards() -> Array:
	return _cards.duplicate()

## La pestana del Nucleo elegida ("" fuera del Nucleo) y las que hay.
func current_tab() -> String:
	return _tab

func tab_ids() -> Array:
	return _group_order.duplicate()

func populate_building(node: Node, data: BuildingData, is_constructing: bool) -> void:
	clear()
	_node = node
	_data = data
	_is_deposit = false
	_set_title(_section_title(data.id))
	var processes: Array = ProcessManager.get_processes_for(data.id)
	if data.id == "nucleo":
		_build_core_tabs(processes)
	else:
		_tab = ""
		_fill_grid(processes)
	if is_constructing:
		set_buttons_disabled(true)
	update_progress(node, false, data)

## "FABRICAR" o el verbo propio del edificio (RCP_SECTION_<ID>), si lo tiene.
func _section_title(building_id: String) -> String:
	var key := "RCP_SECTION_" + building_id.to_upper()
	return Tr.t(key) if Tr.t(key) != key else Tr.t("RCP_SECTION")

func _set_title(text: String) -> void:
	if _header_label != null:
		_header_label.text = text

## Las tarjetas de `processes` en la rejilla: primero las abiertas, luego las
## cerradas (en su orden de siempre dentro de cada grupo).
func _fill_grid(processes: Array) -> void:
	var open: Array = []
	var locked: Array = []
	for proc in processes:
		if ProcessCard.locked_resource(proc) == "":
			open.append(proc)
		else:
			locked.append(proc)
	for proc in open + locked:
		_add_process_card(proc, _node, _from_tip(proc))
	_fit_columns.call_deferred()

# ── El Nucleo: pestanas por taller ──

func _build_core_tabs(processes: Array) -> void:
	_groups.clear()
	_group_order.clear()
	for proc in processes:
		var gid := _core_group_of(proc)
		if not _groups.has(gid):
			_groups[gid] = []
		(_groups[gid] as Array).append(proc)
	var order: Array = [CORE_TAB_OWN]
	order.append_array(CORE_WORKSHOP_ORDER)
	for gid in _groups:
		if not (gid in order) and gid != CORE_TAB_HAND:
			order.append(gid)
	order.append(CORE_TAB_HAND)
	for gid in order:
		if _groups.has(gid):
			_group_order.append(gid)
	# Se abre donde se dejo; si no, en la primera con algo que hacer.
	var pick := _core_tab_memory if _groups.has(_core_tab_memory) else ""
	if pick == "":
		for gid in _group_order:
			if _group_open_count(gid) > 0:
				pick = gid
				break
	if pick == "" and not _group_order.is_empty():
		pick = _group_order[0]
	_show_core_tab(pick)

## La pestana de un proceso del Nucleo: lo suyo, el taller del que lo copia o
## "a mano".
static func _core_group_of(proc: Dictionary) -> String:
	var group := String(proc.get("core_group", CORE_TAB_OWN))
	if group == "workshop":
		return String(proc.get("from", "workshop"))
	return group

func _group_open_count(gid: String) -> int:
	var n := 0
	for proc in _groups.get(gid, []):
		if ProcessCard.locked_resource(proc) == "":
			n += 1
	return n

func _show_core_tab(gid: String) -> void:
	_tab = gid
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	for g in _group_order:
		_tabs.add_child(_make_tab(String(g), String(g) == gid))
	_tabs.visible = _group_order.size() > 1
	var head := _section_title("nucleo")
	_set_title("%s · %s" % [head, _tab_title(gid)] if CT.is_phone() and gid != "" else head)
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.free()
	_cards.clear()
	_count = 0
	_fill_grid(_groups.get(gid, []))
	_last_refresh_ms = 0
	if _node != null:
		update_progress(_node, false, _data)

## Una pestana: [icono] Nombre. En telefono las no elegidas solo con icono
## (el nombre al mantener). Con todo cerrado, el candado.
func _make_tab(gid: String, selected: bool) -> Button:
	var title := _tab_title(gid)
	var glyph := _tab_glyph(gid)
	var locked := _group_open_count(gid) == 0
	if locked:
		glyph = "lock"
	# En telefono, todas solo con icono: el nombre de la elegida va en el titulo
	# de la seccion ("FABRICAR · Refineria") y el de cada una, al mantener.
	var text := "" if CT.is_phone() else title
	var b := CT.recipe_tab(text, glyph, selected)
	b.name = "Tab_" + gid
	b.tooltip_text = title
	b.set_meta("tab_id", gid)
	b.pressed.connect(func():
		_core_tab_memory = gid
		_show_core_tab(gid))
	return b

func _tab_title(gid: String) -> String:
	match gid:
		CORE_TAB_OWN:
			return Tr.t("RCP_TAB_OWN")
		CORE_TAB_HAND:
			return Tr.t("RCP_TAB_HAND")
	var key := "BLD_%s_NAME" % gid.to_upper()
	return Tr.t(key) if Tr.t(key) != key else gid

func _tab_glyph(gid: String) -> String:
	match gid:
		CORE_TAB_OWN:
			return "build"
		CORE_TAB_HAND:
			return "res:workers"
	var mat := GameConfig.get_material_of(gid)
	var g := CT.res_glyph_id(mat) if mat != "" else ""
	return g if g != "" else "wrench"

## "Lo mismo que en: Aserradero. Aqui tarda mas." para lo que el Nucleo copia.
func _from_tip(proc: Dictionary) -> String:
	var from := String(proc.get("from", ""))
	if from == "":
		return ""
	var where := ""
	if MapGeneratorScript.DEPOSIT_TYPES.has(from):
		where = Tr.t(String(MapGeneratorScript.DEPOSIT_TYPES[from]["display_name"]))
	else:
		where = Tr.t("BLD_%s_NAME" % from.to_upper())
	return Tr.t("LBL_CORE_FROM") % where

# ── Yacimientos ──

func populate_deposit(node: Node, deposit_id: String) -> void:
	clear()
	_node = node
	_data = null
	_is_deposit = true
	_tab = ""
	_set_title(Tr.t("RCP_SECTION_DEPOSIT"))
	var mining := ProcessManager.get_mining_info(deposit_id)
	if not mining.is_empty():
		_add_mining_card(mining, node, deposit_id)
	_fit_columns.call_deferred()
	update_progress(node, true, null)

# ── Rejilla ──

## Una columna en telefono; en tablet y PC, dos si caben dos tarjetas.
func _fit_columns() -> void:
	if _grid == null or not is_instance_valid(_grid):
		return
	var card_min := 0.0
	for card in _cards:
		if is_instance_valid(card):
			card_min = maxf(card_min, (card as Control).get_combined_minimum_size().x)
	var cols := CT.recipe_columns(_grid.size.x, card_min)
	cols = mini(cols, maxi(1, _cards.size()))
	if _grid.columns != cols:
		_grid.columns = cols

# ── Progreso y estado ──

func update_progress(node: Node, is_deposit: bool, data: BuildingData) -> void:
	if not node:
		return
	var active := ProcessManager.get_active(node)
	var constructing: bool = not is_deposit and data != null and ProductionManager.is_constructing(node)
	var token := ""
	if constructing or _forced_busy:
		token = ProcessCard.BUSY_BUILDING
	elif not active.is_empty():
		token = String(active.get("id", "*"))
	_refresh_cards(token != _busy_token, token)
	if active.is_empty():
		return
	# La barra de la tanda en marcha, en su tarjeta.
	var own := String(active.get("id", ""))
	var total: int = ProcessManager.get_batch_total(node)
	var current: int = total - ProcessManager.get_batch_left(node) + 1
	var text := Tr.t("RCP_PROGRESS") % [current, total, TextKit.short_time(float(active.get("remaining", 0.0)))]
	for card in _cards:
		if is_instance_valid(card) and String(card._proc.get("id", "")) == own:
			card.set_progress(ProcessManager.get_progress(node), text)

## Compatibilidad: apaga (o enciende) todas las tarjetas, p. ej. en obras.
func set_buttons_disabled(disabled: bool) -> void:
	_forced_busy = disabled
	_refresh_cards(true, ProcessCard.BUSY_BUILDING if disabled else _busy_token)

## Pone las tarjetas al dia: siempre si `force`, si no como mucho cada REFRESH_MS.
func _refresh_cards(force: bool, token: String = "") -> void:
	var now := Time.get_ticks_msec()
	if not force and now - _last_refresh_ms < REFRESH_MS:
		return
	_last_refresh_ms = now
	_busy_token = token
	for card in _cards:
		if is_instance_valid(card):
			card.refresh(token)

func _add_process_card(proc: Dictionary, node: Node, from_tip: String = "") -> void:
	var card: PanelContainer = ProcessCard.new()
	card.setup(proc, ProcessCard.Kind.PROCESS, node, Color(0, 0, 0, 0), from_tip)
	card.batch_requested.connect(func(n: int): _start_process(node, proc, n))
	card.dequeue_requested.connect(func(n: int): _dequeue(node, n))
	card.cancel_requested.connect(func(): _cancel(node))
	_grid.add_child(card)
	_cards.append(card)
	_count += 1

func _add_mining_card(mining: Dictionary, node: Node, deposit_id: String) -> void:
	var card: PanelContainer = ProcessCard.new()
	card.setup(mining, ProcessCard.Kind.DEPOSIT, node)
	card.batch_requested.connect(func(n: int): _start_mining(node, deposit_id, n))
	card.dequeue_requested.connect(func(n: int): _dequeue(node, n))
	card.cancel_requested.connect(func(): _cancel(node))
	_grid.add_child(card)
	_cards.append(card)
	_count += 1

## "Madera refinada\n15 madera → 25 madera · 5 oro · 30 s". Estatica para las
## pruebas: coste, producto y tiempo, sin "Costo:", "Produce:" ni "Duracion:".
static func process_card_text(proc: Dictionary) -> String:
	return ProcessCard.card_text(proc, int(proc.get("workers", 0)))

## "Talar\n+10 madera · 30 s · 2 trabajadores" y, si no se puede, "✖ motivo".
static func mining_card_text(mining: Dictionary, block: String = "") -> String:
	var line := "%s · %s · %s" % [
		TextKit.cost_text(mining["produces"], "+"),
		TextKit.short_time(float(mining["duration"])),
		Tr.t("LBL_WORKERS_SHORT") % GameConfig.mining_workers,
	]
	var text := "%s\n%s" % [Tr.t(mining["name"]), line]
	if block != "":
		text += "\n✖ " + Tr.t(block)
	return text

## Un proceso esta cerrado mientras alguno de sus recursos o materiales no
## exista (por era o por el primer edificio de su material). Ya no se esconde:
## su tarjeta sale apagada con el porque (ProcessCard.locked_resource).
static func _process_has_locked_resource(proc: Dictionary) -> bool:
	return ProcessCard.locked_resource(proc) != ""

# ── Acciones ──

## Cada toque del verbo SUMA a la cola de ese proceso (o la empieza).
func _start_process(node: Node, proc: Dictionary, count: int = 1) -> void:
	if node and ProcessManager.enqueue_process(node, proc, count):
		_after_change(node)

func _start_mining(node: Node, deposit_id: String, count: int = 1) -> void:
	if node and ProcessManager.enqueue_mining(node, deposit_id, count):
		_after_change(node)

## Quita tandas sin empezar (n = -1: todas) y devuelve lo pagado por ellas.
func _dequeue(node: Node, n: int) -> void:
	if node == null:
		return
	ProcessManager.dequeue(node, ProcessManager.queued_not_started(node) if n < 0 else n)
	_after_change(node)

func _cancel(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	ProcessManager.cancel(node)
	_after_change(node)

func _after_change(node: Node) -> void:
	_busy_token = "?"
	update_progress(node, _is_deposit, _data)
