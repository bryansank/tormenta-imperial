extends CanvasLayer
## Construction menu: full-screen modal with category tabs, search bar,
## building grid with thumbnails, and a 3D preview panel for the selected building.

const PlacementAssistScript := preload("res://scripts/buildings/PlacementAssist.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const TextKit := preload("res://scripts/ui/TextKit.gd")

var _root: Control
var _backdrop: ColorRect
var _modal: PanelContainer
var _build_btn: Button
## Tamano del boton CONSTRUIR del HUD (el primario del juego).
const BUILD_BTN_W := 240.0
const BUILD_BTN_H := 64.0
var _is_open := false

# Category state
var _all_buildings: Array = []
var _current_category := "all"
var _search_text := ""
var _cat_buttons: Dictionary = {}

# Building grid
var _grid_container: GridContainer
var _grid_scroll: ScrollContainer

# Detail panel (right side)
var _detail_panel: VBoxContainer
var _detail_name: Label
## El coste en fila de iconos con su cifra; en rojo lo que falta (2026-10-04).
var _detail_cost: HFlowContainer
## Lo que produce: "+6 [madera] cada 12 s".
var _detail_production: HBoxContainer
var _detail_extras: Label
## "[edificio] 3/6 · era 2: 9": cuantos hay, el tope de la era y el siguiente.
var _detail_limit: HBoxContainer
## "Necesita bosque adyacente": la regla del yacimiento, antes de colocar (bug 10).
var _detail_rule: Label
## Por que no se puede construir ahora ("Te falta: 20 Madera"), junto al boton.
var _detail_block: Label
var _detail_build_btn: Button
var _selected_data: BuildingData = null

# 3D Preview
var _preview_viewport: SubViewport
var _preview_container: SubViewportContainer
var _preview_camera: Camera3D
var _preview_model: Node3D = null
var _preview_spin := 0.0

# Thumbnail cache
var _thumb_cache: Dictionary = {}  # building_id -> ImageTexture

# Vista 2D (docs/18-vista-2d.md): miniaturas y vista previa con el dibujo plano
# del mapa en vez de modelos 3D. Se decide al arrancar: sin Camera3D es la 2D.
const BuildingIcon2D := preload("res://scripts/view2d/BuildingIcon2D.gd")
var _is_2d := false
var _preview_icon: Control = null
var _thumb_rects: Dictionary = {}  # building_id -> TextureRect

const CATEGORIES := ["all", "production", "support", "military", "decoration"]

## Capa en reposo (lista cerrada): bajo cualquier ventana de UIManager, que
## apila desde la 12. Antes era 12 fija y empataba con la primera ventana
## abierta (AYUDA, Ejercito...): el boton CONSTRUIR se pintaba encima de ella.
## Con la lista abierta la capa la pone UIManager, como a las demas.
const REST_LAYER := 11

func _ready() -> void:
	layer = REST_LAYER
	_is_2d = get_viewport().get_camera_3d() == null and get_viewport().get_camera_2d() != null
	_load_buildings()
	_setup_ui()
	_generate_thumbnails()
	EventBus.resource_unlocked.connect(func(_r): _request_grid_refresh())
	# Subir de rango quita candados; cargar otra partida puede ponerlos.
	EventBus.governor_rank_up.connect(func(_r, _w):
		_request_grid_refresh()
		_refresh_block())
	# Los topes suben con la era (GameConfig.building_limits_by_era): al cambiar
	# de era, las tarjetas y el detalle dicen el tope nuevo.
	EventBus.era_advanced.connect(func(_e):
		_request_grid_refresh()
		_refresh_block())
	EventBus.game_load_completed.connect(_request_grid_refresh)
	EventBus.game_new_started.connect(_request_grid_refresh)
	# Con la lista abierta, el coste en rojo o no y el aviso siguen a lo que hay.
	EventBus.resource_changed.connect(func(_t, _a, _d): _on_resources_changed())
	# CONSTRUIR es la accion principal: siempre a la vista, no escondida tras el
	# menu (bug 9/11: solo salia al desplegar el antiguo ☰).
	_build_btn.visible = true
	UIManager.register_panel(self, "ConstructionMenu.modal")
	# El giro de la maqueta solo hace falta con la lista abierta.
	set_process(false)

func _process(delta: float) -> void:
	if _preview_model and _is_open and _selected_data:
		_preview_spin += delta * 0.5
		_preview_model.rotation.y = _preview_spin

func _load_buildings() -> void:
	_all_buildings.clear()
	for res in BuildingData.load_all():
		if not res.is_core:
			_all_buildings.append(res)
	_all_buildings.sort_custom(func(a, b): return a.get_display_name() < b.get_display_name())

func _get_category(data: BuildingData) -> String:
	if data.is_decoration:
		return "decoration"
	if data.id in ["house", "warehouse"]:
		return "support"
	if data.id in ["barracks", "tower"]:
		return "military"
	return "production"

func _get_filtered_buildings() -> Array:
	var result: Array = []
	for data in _all_buildings:
		if _current_category != "all" and _get_category(data) != _current_category:
			continue
		if _search_text != "" and data.get_display_name().to_lower().find(_search_text.to_lower()) == -1:
			continue
		result.append(data)
	return result

# ══════════════════════════════════════════════════════════════════════
# ── UI Setup ──
# ══════════════════════════════════════════════════════════════════════

func _setup_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Build button (bottom center)
	_build_btn = Button.new()
	_build_btn.name = "BuildButton"
	# Gancho del tutorial guiado (frente de ayudas): resalta este boton.
	_build_btn.add_to_group("hud_build_button")
	_build_btn.text = Tr.t("BTN_BUILD_BIG")
	_build_btn.tooltip_text = Tr.t("BTN_BUILD_HINT")
	_build_btn.focus_mode = Control.FOCUS_NONE
	# Grande y abajo en el centro: el pulgar llega en una tablet apaisada.
	_build_btn.custom_minimum_size = Vector2(BUILD_BTN_W, BUILD_BTN_H)
	UILayoutManager.apply_layout("ConstructionMenu.button", _build_btn)
	UITheme.style_button(_build_btn, UITheme.POSITIVE.darkened(0.1), UITheme.FONT_TITLE)
	# El primario del juego se distingue en reposo: metal mas claro y borde de
	# laton, no el mismo verde apagado que cualquier boton.
	_build_btn.add_theme_stylebox_override("normal", UITheme._button_style(
		UITheme._metal_tint(UITheme.POSITIVE, 1.35), UITheme.POSITIVE, UITheme.ACCENT, 4))
	_build_btn.pressed.connect(_open)
	_root.add_child(_build_btn)
	HudRegistry.register("ConstructionMenu.button", _build_btn)

	# Backdrop
	_backdrop = UITheme.make_backdrop()
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close()
	)
	_root.add_child(_backdrop)

	# Main modal panel
	_modal = PanelContainer.new()
	UILayoutManager.apply_layout("ConstructionMenu.modal", _modal)
	_modal.visible = false
	_modal.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	_modal.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			UIManager.focus_window(self)
	)
	_root.add_child(_modal)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	_modal.add_child(main_vbox)

	# ── Header: title + search + close ──
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	main_vbox.add_child(header)

	var title := UITheme.make_label(Tr.t("LBL_BUILDINGS_TITLE"), "title", UITheme.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var search := LineEdit.new()
	search.placeholder_text = Tr.t("LBL_SEARCH")
	search.custom_minimum_size = Vector2(180, 32)
	search.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	UITheme.set_label_color(search, UITheme.TEXT)
	search.add_theme_color_override("font_placeholder_color", UITheme.readable(UITheme.TEXT_DIM, UITheme.UI_BG_REFERENCE, 3.0))
	var search_style := StyleBoxFlat.new()
	search_style.bg_color = UITheme.BG_DARK
	search_style.set_corner_radius_all(UITheme.CORNER)
	search_style.set_content_margin_all(6)
	search_style.border_color = UITheme.ACCENT_DIM
	search_style.set_border_width_all(1)
	search.add_theme_stylebox_override("normal", search_style)
	var search_focus := search_style.duplicate()
	search_focus.border_color = UITheme.ACCENT
	search_focus.set_border_width_all(2)
	search.add_theme_stylebox_override("focus", search_focus)
	search.text_changed.connect(func(text):
		_search_text = text
		_refresh_grid()
	)
	header.add_child(search)

	header.add_child(UITheme.make_close_button(_close))

	# ── Category tabs ──
	var cat_bar := HBoxContainer.new()
	cat_bar.add_theme_constant_override("separation", 4)
	main_vbox.add_child(cat_bar)

	var cat_labels := {
		"all": Tr.t("LBL_CAT_ALL"),
		"production": Tr.t("LBL_CAT_PRODUCTION"),
		"support": Tr.t("LBL_CAT_SUPPORT"),
		"military": Tr.t("LBL_CAT_MILITARY"),
		"decoration": Tr.t("LBL_CAT_DECORATION"),
	}
	for cat_id in CATEGORIES:
		var btn := Button.new()
		btn.text = cat_labels.get(cat_id, cat_id)
		btn.custom_minimum_size = Vector2(0, 32)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var is_active: bool = cat_id == _current_category
		UITheme.style_button(btn, filter_color(is_active), UITheme.FONT_SMALL)
		var cid: String = cat_id  # capture
		btn.pressed.connect(func(): _select_category(cid))
		cat_bar.add_child(btn)
		_cat_buttons[cat_id] = btn

	main_vbox.add_child(UITheme.make_separator())

	# ── Content: grid (left) + detail (right) ──
	var content := HSplitContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.split_offset = 420
	main_vbox.add_child(content)

	# Left side: scrollable grid of building cards
	_grid_scroll = ScrollContainer.new()
	_grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(_grid_scroll)

	_grid_container = GridContainer.new()
	_grid_container.columns = 3
	# Tantas columnas como quepan: con tres fijas quedaba media lista vacia y
	# habia que desplazar para ver edificios que cabian de sobra.
	_grid_scroll.resized.connect(_fit_columns)
	_grid_container.add_theme_constant_override("h_separation", 6)
	_grid_container.add_theme_constant_override("v_separation", 6)
	_grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_scroll.add_child(_grid_container)

	# Right side: detail panel with 3D preview. The CONSTRUIR button sits below
	# the scroll, always in sight: on a tablet the detail is taller than the
	# window and the button used to end up scrolled off the bottom (QA flow 04).
	var detail_column := VBoxContainer.new()
	detail_column.name = "DetailColumn"
	detail_column.custom_minimum_size = Vector2(320, 0)
	detail_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_column.add_theme_constant_override("separation", 8)
	content.add_child(detail_column)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_column.add_child(detail_scroll)

	_detail_panel = VBoxContainer.new()
	_detail_panel.add_theme_constant_override("separation", 8)
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_detail_panel)

	# 3D preview SubViewport
	_preview_viewport = SubViewport.new()
	_preview_viewport.size = Vector2i(300, 220)
	_preview_viewport.transparent_bg = true
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_viewport.world_3d = World3D.new()

	_preview_camera = Camera3D.new()
	_preview_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_preview_camera.size = 6.0
	# look_at_from_position works before the node is in the tree (plain look_at errors).
	_preview_camera.look_at_from_position(Vector3(4.0, 4.5, 4.0), Vector3(0, 0.5, 0))
	_preview_viewport.add_child(_preview_camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	light.light_energy = 1.3
	_preview_viewport.add_child(light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-30, -150, 0)
	fill_light.light_energy = 0.5
	_preview_viewport.add_child(fill_light)

	_preview_container = SubViewportContainer.new()
	_preview_container.custom_minimum_size = Vector2(300, 220)
	_preview_container.stretch = true
	_preview_container.add_child(_preview_viewport)
	# Border around preview
	var preview_style := StyleBoxFlat.new()
	preview_style.bg_color = UITheme.BG_DARK.darkened(0.4)
	preview_style.set_corner_radius_all(UITheme.CORNER)
	preview_style.border_color = UITheme.ACCENT_DIM
	preview_style.set_border_width_all(1)
	var preview_wrapper := PanelContainer.new()
	preview_wrapper.add_theme_stylebox_override("panel", preview_style)
	preview_wrapper.add_child(_preview_container)
	if _is_2d:
		_preview_container.visible = false
		_preview_icon = BuildingIcon2D.new()
		_preview_icon.custom_minimum_size = Vector2(300, 220)
		preview_wrapper.add_child(_preview_icon)
	_detail_panel.add_child(preview_wrapper)

	# Detail labels
	# El nombre; el tamano (todos 2x2 salvo la carretera) va en su tooltip.
	_detail_name = UITheme.make_label("", "title", UITheme.TEXT_BRIGHT)
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_name.mouse_filter = Control.MOUSE_FILTER_PASS
	_detail_panel.add_child(_detail_name)

	# El coste, lo primero tras el nombre: es lo que decide si se puede. Iconos
	# con su cifra y en rojo lo que falta, sin repetir "Costo:" ni los nombres.
	_detail_cost = TextKit.cost_row({}, {}, "section", UITheme.WARNING)
	_detail_cost.name = "DetailCost"
	_detail_cost.alignment = FlowContainer.ALIGNMENT_CENTER
	_detail_panel.add_child(_detail_cost)

	_detail_panel.add_child(UITheme.make_separator())
	# Nombre y coste arriba del todo; la vista previa, detras. En tableta la
	# vista previa empujaba el coste fuera de la pantalla.
	_detail_panel.move_child(preview_wrapper, _detail_panel.get_child_count() - 1)

	_detail_production = HBoxContainer.new()
	_detail_production.name = "DetailProduction"
	_detail_production.add_theme_constant_override("separation", 6)
	_detail_panel.add_child(_detail_production)

	_detail_rule = UITheme.make_label("", "small", UITheme.INFO)
	_detail_rule.name = "DepositRule"
	_detail_rule.autowrap_mode = TextServer.AUTOWRAP_WORD
	# La regla de la carretera, entera, en el tooltip (y en la guia rapida).
	_detail_rule.mouse_filter = Control.MOUSE_FILTER_PASS
	_detail_panel.add_child(_detail_rule)

	_detail_extras = UITheme.make_label("", "small", UITheme.TEXT_DIM)
	_detail_extras.autowrap_mode = TextServer.AUTOWRAP_WORD
	_detail_panel.add_child(_detail_extras)

	_detail_limit = HBoxContainer.new()
	_detail_limit.name = "DetailLimit"
	_detail_limit.visible = false
	_detail_panel.add_child(_detail_limit)

	# Lo que impide construir, a la vista junto al boton (fuera del scroll).
	_detail_block = UITheme.make_label("", "body", UITheme.DANGER)
	_detail_block.name = "DetailBlock"
	_detail_block.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_block.autowrap_mode = TextServer.AUTOWRAP_WORD
	_detail_block.mouse_filter = Control.MOUSE_FILTER_PASS
	_detail_block.visible = false
	detail_column.add_child(_detail_block)

	# Build button (outside the scroll, see DetailColumn above)
	_detail_build_btn = Button.new()
	_detail_build_btn.text = Tr.t("BTN_BUILD")
	_detail_build_btn.custom_minimum_size = Vector2(0, 48)
	_detail_build_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_button(_detail_build_btn, UITheme.POSITIVE.darkened(0.1), UITheme.FONT_TITLE)
	_detail_build_btn.name = "DetailBuildButton"
	_detail_build_btn.pressed.connect(_on_build_pressed)
	detail_column.add_child(_detail_build_btn)

	# Initial state: show placeholder
	_show_no_selection()
	_refresh_grid()

# ══════════════════════════════════════════════════════════════════════
# ── Open / Close ──
# ══════════════════════════════════════════════════════════════════════

func _open() -> void:
	_is_open = true
	_modal.visible = true
	_backdrop.visible = true
	_refresh_grid()
	_refresh_block()
	set_process(true)
	UIManager.open_panel(self)

func _close() -> void:
	_is_open = false
	set_process(false)
	_modal.visible = false
	_backdrop.visible = false
	UIManager.close_panel(self)
	layer = REST_LAYER

func _toggle_panel() -> void:
	if _is_open:
		_close()
	else:
		_open()

# ══════════════════════════════════════════════════════════════════════
# ── Category Selection ──
# ══════════════════════════════════════════════════════════════════════

## Color de categoria: solo la franja inferior de cada tarjeta (docs/24-paleta.md).
var _cat_colors := {
	"all": UITheme.ACCENT,
	"production": UITheme.CAT_PRODUCTION,
	"support": UITheme.CAT_SUPPORT,
	"military": UITheme.CAT_MILITARY,
	"decoration": UITheme.CAT_DECORATION,
}

## Fondo de un boton del filtro: todos iguales, el activo en laton. Antes cada
## categoria tenia su color de boton y la barra parecia un arcoiris.
static func filter_color(active: bool) -> Color:
	return UITheme.ACCENT.darkened(0.55) if active else UITheme.BTN

func _select_category(cat_id: String) -> void:
	_current_category = cat_id
	# Update button styles
	for cid in _cat_buttons:
		var btn: Button = _cat_buttons[cid]
		var is_active: bool = cid == _current_category
		UITheme.style_button(btn, filter_color(is_active), UITheme.FONT_SMALL)
	_refresh_grid()

# ══════════════════════════════════════════════════════════════════════
# ── Grid (building cards) ──
# ══════════════════════════════════════════════════════════════════════

## Estilos de las tarjetas desbloqueadas: id -> {"style": StyleBoxFlat, "cat": Color}.
## Hace falta para marcar la seleccionada sin recrear la rejilla.
var _card_styles: Dictionary = {}

const CARD_W := 125.0
const CARD_GAP := 6.0

## Columnas de la rejilla para el ancho de la lista.
static func columns_for(width: float) -> int:
	return maxi(1, floori((width - 14.0 + CARD_GAP) / (CARD_W + CARD_GAP)))

func _fit_columns() -> void:
	if _grid_scroll != null and _grid_container != null:
		_grid_container.columns = columns_for(_grid_scroll.size.x)

## Tarjetas de la rejilla por id de edificio (HelpTargets las busca asi).
var _cards: Dictionary = {}
## Lo que decide como es cada tarjeta: [id, bloqueada, bloqueada por rango, con
## miniatura]. Si no cambia, la rejilla no se recrea: solo se repintan costes.
var _grid_sig: Array = []

## La tarjeta de `building_id` en la rejilla, o null. Para el tutorial.
func card_for(building_id: String) -> Control:
	var card: Control = _cards.get(building_id)
	return card if card != null and is_instance_valid(card) else null

## Una senal pide rehacer la rejilla: con la lista cerrada no se hace nada
## (_open la pone al dia), abierta se hace una vez al final del fotograma.
var _grid_refresh_queued := false
func _request_grid_refresh() -> void:
	if not _is_open or _grid_refresh_queued:
		return
	_grid_refresh_queued = true
	_flush_grid_refresh.call_deferred()

func _flush_grid_refresh() -> void:
	_grid_refresh_queued = false
	if _is_open:
		_refresh_grid()

func _grid_signature(filtered: Array) -> Array:
	var sig: Array = []
	for data in filtered:
		var rank_locked := not Rules.check_rank(data.id)
		sig.append([data.id, rank_locked or _has_locked_resource_cost(data), rank_locked,
			_thumb_cache.has(data.id)])
	return sig

## Rehace las tarjetas solo si cambia cuales hay o si alguna se bloquea o se
## desbloquea; si no, deja las que hay y pone al dia su coste (docs/26 §6.9).
func _refresh_grid() -> void:
	var filtered := _get_filtered_buildings()
	var sig := _grid_signature(filtered)
	if sig == _grid_sig and _cards.size() == filtered.size() and _grid_container.get_child_count() == filtered.size():
		_update_card_costs()
		_mark_selected_card()
		return
	_grid_sig = sig
	for child in _grid_container.get_children():
		child.queue_free()
	_card_styles.clear()
	_cards.clear()

	for data in filtered:
		var card := _create_grid_card(data)
		_grid_container.add_child(card)
		_cards[data.id] = card
	_mark_selected_card()

func _create_grid_card(data: BuildingData) -> PanelContainer:
	# Bloqueado por rango del gobernador: candado y "Rango N" en vez del coste.
	var rank_locked := not Rules.check_rank(data.id)
	var locked := rank_locked or _has_locked_resource_cost(data)
	var cat_color: Color = _cat_colors.get(_get_category(data), UITheme.ACCENT)

	var card := PanelContainer.new()
	# El tutorial guiado busca la tarjeta por id, no por el nombre traducido.
	card.set_meta("building_id", data.id)
	card.custom_minimum_size = Vector2(125, 110)
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.CARD_BG if not locked else UITheme.BTN_DISABLED
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	style.border_width_bottom = 3
	style.border_color = cat_color if not locked else UITheme.TEXT_DIM
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	# Thumbnail
	if _is_2d:
		var icon: Control = BuildingIcon2D.new()
		icon.custom_minimum_size = Vector2(64, 64)
		icon.data = data
		if locked:
			icon.modulate = Color(0.4, 0.4, 0.4, 0.7)
		vbox.add_child(icon)
	elif _thumb_cache.has(data.id):
		var tex_rect := TextureRect.new()
		tex_rect.custom_minimum_size = Vector2(64, 64)
		tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.texture = _thumb_cache[data.id]
		if locked:
			tex_rect.modulate = Color(0.4, 0.4, 0.4, 0.7)
		_thumb_rects[data.id] = tex_rect
		vbox.add_child(tex_rect)
	else:
		var placeholder := ColorRect.new()
		placeholder.custom_minimum_size = Vector2(64, 64)
		placeholder.color = data.mesh_color if not locked else data.mesh_color.darkened(0.5)
		vbox.add_child(placeholder)

	# Name
	var name_label := UITheme.make_label(data.get_display_name(), "small", UITheme.TEXT if not locked else UITheme.TEXT_DIM)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.custom_minimum_size.x = 110
	vbox.add_child(name_label)

	if rank_locked:
		vbox.add_child(make_rank_lock_row(RankManager.building_rank(data.id)))

	# El coste en la propia tarjeta: se ve sin elegir. Icono y cifra por recurso,
	# y en rojo solo lo que falta (antes la linea entera en rojo, con nombres).
	# Bloqueado por rango, la tarjeta ensena el candado en su lugar.
	var cost := {} if rank_locked else Rules.cost_by_name(data)
	if not cost.is_empty():
		var cost_row := TextKit.cost_row(cost, {} if locked else Rules.missing_cost(data), "small",
			UITheme.TEXT_DIM if locked else UITheme.WARNING)
		cost_row.name = "CardCost"
		cost_row.alignment = FlowContainer.ALIGNMENT_CENTER
		cost_row.add_theme_constant_override("h_separation", 6)
		cost_row.custom_minimum_size.x = 110
		vbox.add_child(cost_row)

	# Lo que da una vivienda, en la propia tarjeta: "+6 trabajadores".
	if data.population_capacity > 0 and not data.is_core:
		var gain := UITheme.make_label(Tr.t("LBL_CARD_WORKERS") % data.population_capacity, "small", UITheme.POSITIVE)
		gain.name = "CardGain"
		gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(gain)

	# Cuantos hay y el tope de la era: "3/6 · era 2: 9". Sin tope, nada.
	var limit_row := HBoxContainer.new()
	limit_row.name = "CardLimit"
	limit_row.alignment = BoxContainer.ALIGNMENT_CENTER
	fill_limit_row(limit_row, data.id, "small")
	vbox.add_child(limit_row)

	# Interaction (A14): el hover solo RESALTA; la seleccion cambia solo con
	# clic y queda bloqueada hasta el siguiente. Antes pasar el raton por otra
	# tarjeta cambiaba la seleccion y el detalle saltaba de edificio en edificio.
	#
	# Se elige al SOLTAR dentro de la tarjeta: arrastrar la lista (DragScroll)
	# empieza encima de una tarjeta y no puede elegirla. Las bloqueadas tambien
	# se pueden tocar: el detalle dice que les falta (antes no pasaba nada, y el
	# Cuartel General parecia roto).
	_card_styles[data.id] = {"style": style, "cat": cat_color if not locked else UITheme.TEXT_DIM, "locked": locked}
	card.gui_input.connect(func(event):
		if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
				and Rect2(Vector2.ZERO, card.size.max(card.custom_minimum_size)).has_point(event.position):
			_select_building(data)
	)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var base_bg: Color = UITheme.CARD_BG if not locked else UITheme.BTN_DISABLED
	card.mouse_entered.connect(func():
		if not _is_selected(data):
			style.bg_color = base_bg.lightened(0.12)
	)
	card.mouse_exited.connect(func():
		if not _is_selected(data):
			style.bg_color = base_bg
	)

	return card

## Candado dibujado + "Rango N". El candado se pinta (no es un emoji): la
## tipografia del juego no lo tiene y el respaldo del sistema no esta en todos.
static func make_rank_lock_row(rank: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "RankLock"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lock := Control.new()
	lock.custom_minimum_size = Vector2(14, 16)
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.draw.connect(func(): draw_lock(lock, Rect2(Vector2.ZERO, lock.custom_minimum_size), UITheme.WARNING))
	row.add_child(lock)
	var label := UITheme.make_label(Tr.t("LBL_RANK_LOCK") % rank, "small", UITheme.WARNING)
	label.name = "RankLockLabel"
	row.add_child(label)
	return row

## Lo que dice CONSTRUIR del tope de `building_id`: {} si no tiene (decoraciones,
## Sandbox). Si no, count / limit (de la era en curso, rango incluido), full, y
## next_era / next_limit si una era posterior lo sube. Estatica para las pruebas.
static func limit_info(building_id: String) -> Dictionary:
	var limit := GameConfig.get_building_limit(building_id)
	if building_id == "" or limit < 0:
		return {}
	var count := _count_of(building_id)
	var info := {"count": count, "limit": limit, "full": count >= limit}
	var next := GameConfig.next_building_limit(building_id)
	if not next.is_empty():
		info["next_era"] = int(next["era"])
		info["next_limit"] = int(next["limit"])
	return info

## Cuantos hay de `building_id`, recordado mientras no cambie el mapa
## (GridManager.map_version()): el refresco de costes llega con cada recurso que
## cambia y contar recorre todos los edificios, carreteras incluidas.
static var _count_version := -1
static var _counts: Dictionary = {}
static func _count_of(building_id: String) -> int:
	var v: int = GridManager.map_version()
	if v != _count_version:
		_count_version = v
		_counts.clear()
	if not _counts.has(building_id):
		_counts[building_id] = Rules.count_building(building_id)
	return int(_counts[building_id])

## "3/6 · era 2: 9", o "3/6" si ya no sube. "" sin tope.
static func limit_text(building_id: String) -> String:
	return _limit_text_of(limit_info(building_id))

static func _limit_text_of(info: Dictionary) -> String:
	if info.is_empty():
		return ""
	var text: String = Tr.t("FMT_LIMIT_COUNT") % [int(info["count"]), int(info["limit"])]
	if info.has("next_era"):
		text += " · " + Tr.t("FMT_LIMIT_NEXT_ERA") % [int(info["next_era"]), int(info["next_limit"])]
	return text

## El tooltip: lo mismo en frase ("Tienes 3. Tope en esta era: 6. En la era 2...").
static func limit_tooltip(building_id: String) -> String:
	return _limit_tooltip_of(limit_info(building_id))

static func _limit_tooltip_of(info: Dictionary) -> String:
	if info.is_empty():
		return ""
	var lines: Array = [Tr.t("FMT_LIMIT_TIP") % [int(info["count"]), int(info["limit"])]]
	if info.has("next_era"):
		lines.append(Tr.t("FMT_LIMIT_TIP_NEXT") % [int(info["next_era"]), int(info["next_limit"])])
	elif int(info["limit"]) == 1:
		lines.append(Tr.t("LBL_LIMIT_UNIQUE"))
	else:
		lines.append(Tr.t("LBL_LIMIT_TIP_MAX"))
	return " ".join(lines)

## Rellena `row` con el icono de edificio y limit_text(); la esconde sin tope.
## No rehace nada si el texto no cambio (se llama en cada refresco de costes).
static func fill_limit_row(row: HBoxContainer, building_id: String, font_size: String) -> void:
	var info := limit_info(building_id)
	var text := _limit_text_of(info)
	var full := bool(info.get("full", false))
	row.visible = text != ""
	var same: bool = row.get_meta("limit_text", "") == text and row.get_meta("limit_full", false) == full
	if same and row.get_child_count() > 0:
		return
	row.set_meta("limit_text", text)
	row.set_meta("limit_full", full)
	for child in row.get_children():
		row.remove_child(child)
		child.free()
	if text == "":
		return
	row.add_theme_constant_override("separation", 4)
	row.tooltip_text = _limit_tooltip_of(info)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var color: Color = UITheme.WARNING if full else UITheme.TEXT_DIM
	var icon := Control.new()
	icon.name = "LimitIcon"
	icon.custom_minimum_size = Vector2(14, 14)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(func(): draw_building_glyph(icon, Rect2(Vector2.ZERO, icon.custom_minimum_size), color))
	row.add_child(icon)
	var label := UITheme.make_label(text, font_size, color)
	label.name = "LimitLabel"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)

## Una casita: tejado a dos aguas y cuerpo con puerta. Se pinta (como el
## candado): la tipografia no trae un icono de edificio.
static func draw_building_glyph(ci: CanvasItem, r: Rect2, color: Color) -> void:
	var roof_h := r.size.y * 0.42
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(r.position.x, r.position.y + roof_h),
		Vector2(r.get_center().x, r.position.y),
		Vector2(r.end.x, r.position.y + roof_h)]), color)
	var body := Rect2(r.position.x + r.size.x * 0.12, r.position.y + roof_h,
		r.size.x * 0.76, r.size.y - roof_h)
	ci.draw_rect(body, color)
	var door := Rect2(body.get_center().x - r.size.x * 0.1, body.end.y - body.size.y * 0.6,
		r.size.x * 0.2, body.size.y * 0.6)
	ci.draw_rect(door, UITheme.BG_DARK)

## Un candado: arco del grillete y cuerpo con ojo de cerradura.
static func draw_lock(ci: CanvasItem, r: Rect2, color: Color) -> void:
	var body := Rect2(r.position.x, r.position.y + r.size.y * 0.45, r.size.x, r.size.y * 0.55)
	var shackle_c := Vector2(r.get_center().x, r.position.y + r.size.y * 0.45)
	ci.draw_arc(shackle_c, r.size.x * 0.32, PI, TAU, 12, color, 2.0)
	ci.draw_rect(body, color)
	ci.draw_circle(body.get_center(), maxf(1.0, r.size.x * 0.1), UITheme.BG_DARK)

## "50 Oro · 30 Madera", o "" si es gratis.
static func card_cost_text(data: BuildingData) -> String:
	var parts: Array = []
	var cost := Rules.cost_by_name(data)
	for res_id in cost:
		parts.append("%d %s" % [int(cost[res_id]), Tr.res_name(res_id)])
	return " · ".join(parts)

func _is_selected(data: BuildingData) -> bool:
	return _selected_data != null and _selected_data.id == data.id

## Pinta la tarjeta elegida con marco de laton y fondo claro, y devuelve las
## demas a su estado normal. Se llama al seleccionar y al reconstruir la rejilla.
func _mark_selected_card() -> void:
	for id in _card_styles:
		var entry: Dictionary = _card_styles[id]
		var style: StyleBoxFlat = entry["style"]
		var selected: bool = _selected_data != null and _selected_data.id == id
		var base_bg: Color = UITheme.BTN_DISABLED if bool(entry.get("locked", false)) else UITheme.CARD_BG
		style.bg_color = base_bg.lightened(0.25) if selected else base_bg
		style.set_border_width_all(2 if selected else 0)
		style.border_width_bottom = 3
		style.border_color = UITheme.ACCENT if selected else entry["cat"]

# ══════════════════════════════════════════════════════════════════════
# ── Detail Panel (right side) ──
# ══════════════════════════════════════════════════════════════════════

func _show_no_selection() -> void:
	_selected_data = null
	_detail_name.text = Tr.t("LBL_SELECT_BUILDING")
	_detail_name.tooltip_text = ""
	TextKit.fill_cost_row(_detail_cost, {})
	_fill_production({}, 0)
	_detail_extras.text = ""
	fill_limit_row(_detail_limit, "", "small")
	_detail_rule.text = ""
	_detail_block.visible = false
	_detail_build_btn.visible = false
	_clear_preview_model()

func _select_building(data: BuildingData) -> void:
	if _selected_data == data:
		return
	_selected_data = data
	_preview_spin = 0.0
	_mark_selected_card()

	# Nombre; el tamano y la descripcion, en su tooltip.
	_detail_name.text = data.get_display_name()
	_detail_name.tooltip_text = "%dx%d · %s" % [data.grid_size.x, data.grid_size.y, data.get_description()]

	# Coste: fila de iconos (el rojo de lo que falta lo pone _refresh_block).
	_refresh_cost()

	# Produccion: "+6 [madera] cada 12 s".
	var prod := {}
	for pair in [["gold", data.produces_gold], ["steel", data.produces_steel], ["oil", data.produces_oil], ["wood", data.produces_wood], ["food", data.produces_food]]:
		if int(pair[1]) > 0:
			prod[pair[0]] = int(pair[1])
	_fill_production(prod, data.production_interval)

	# Regla del yacimiento (PlacementAssist.rule_text): se dice aqui, no al
	# fallar. La de la carretera, en corto; entera en el tooltip.
	var rule := PlacementAssistScript.rule_text(data.id)
	var rules: Array = []
	if rule != "":
		rules.append("▲ " + rule)
	if not data.is_core and data.id != "road":
		rules.append("▲ " + Tr.t("LBL_RULE_ROAD_SHORT"))
	_detail_rule.text = "\n".join(rules)
	_detail_rule.tooltip_text = Tr.t("LBL_RULE_ROAD") if not data.is_core and data.id != "road" else ""
	_detail_rule.visible = not rules.is_empty()

	# Extras, en una linea: trabajadores, alojamiento, moral y requisitos.
	_detail_extras.text = " · ".join(extras_parts(data))

	# Build button, y lo que lo impide si algo lo impide
	_detail_build_btn.visible = true
	_refresh_block()

	# 3D preview
	_load_preview_model(data)

func _load_preview_model(data: BuildingData) -> void:
	_clear_preview_model()
	if _is_2d:
		_preview_icon.data = data
		return
	if data.model_scene:
		_preview_model = data.instantiate_model()
	else:
		_preview_model = DieselpunkBuildingFactory.create(data.id, GridManager.cell_size, data.grid_size)
	if not _preview_model:
		return
	_preview_viewport.add_child(_preview_model)
	# Adjust camera to fit building
	var max_dim := maxf(data.grid_size.x, data.grid_size.y) * GridManager.cell_size
	_preview_camera.size = max_dim * 2.8
	_preview_spin = 0.0

func _clear_preview_model() -> void:
	if _preview_icon:
		_preview_icon.data = null
	if _preview_model and is_instance_valid(_preview_model):
		_preview_model.queue_free()
		_preview_model = null

## Lo que impide construir el elegido: se dice y el boton no deja empezar a
## colocar algo que luego no se puede pagar.
func _refresh_block() -> void:
	if _selected_data == null:
		_detail_block.visible = false
		return
	# En corto junto al boton; entero (como se desbloquea cada cosa) en el tooltip.
	var block := Rules.purchase_block_detail(_selected_data)
	_detail_block.text = "\n".join(Rules.block_reasons_short(_selected_data))
	_detail_block.tooltip_text = block
	_detail_block.visible = block != ""
	_detail_build_btn.disabled = block != ""
	fill_limit_row(_detail_limit, _selected_data.id, "body")
	_refresh_cost()

## La fila del coste del elegido, con lo que falta en rojo. Gratis lo dice.
func _refresh_cost() -> void:
	if _selected_data == null:
		TextKit.fill_cost_row(_detail_cost, {})
		return
	var cost := Rules.cost_by_name(_selected_data)
	TextKit.fill_cost_row(_detail_cost, cost, Rules.missing_cost(_selected_data), "section", UITheme.WARNING)
	if cost.is_empty():
		_detail_cost.add_child(UITheme.make_label(Tr.t("LBL_FREE"), "section", UITheme.POSITIVE))

## "+6 [madera] cada 12 s", o nada si no produce.
func _fill_production(prod: Dictionary, interval: float) -> void:
	for child in _detail_production.get_children():
		_detail_production.remove_child(child)
		child.free()
	_detail_production.visible = not prod.is_empty()
	if prod.is_empty():
		return
	_detail_production.add_child(TextKit.cost_inline(prod, {}, "body", UITheme.POSITIVE, "+"))
	if interval > 0:
		_detail_production.add_child(UITheme.make_label(Tr.t("FMT_EVERY") % TextKit.short_time(interval), "body", UITheme.POSITIVE))

## Lo que pide y lo que da, en piezas cortas: "2 trabajadores", "+6 trabajadores",
## "+5 moral", "Requiere: Fundicion". Estatica y publica para las pruebas.
static func extras_parts(data: BuildingData) -> Array:
	var extras: Array = []
	if data.workers_required > 0:
		extras.append(Tr.t("LBL_WORKERS_SHORT") % data.workers_required)
	if data.population_capacity > 0:
		extras.append(Tr.t("LBL_CARD_WORKERS") % data.population_capacity)
	if data.morale_bonus > 0:
		extras.append(Tr.t("LBL_MORALE_BONUS") % data.morale_bonus)
	if not GameConfig.get_prerequisites(data.id).is_empty():
		extras.append(Tr.t("LBL_REQUIRES") % Rules.prerequisite_names(data.id))
	return extras

## Cambian los recursos (llega una senal por recurso, a veces varias en el mismo
## fotograma): se repinta una sola vez, al final del fotograma.
var _costs_queued := false
func _on_resources_changed() -> void:
	if not _is_open or _costs_queued:
		return
	_costs_queued = true
	_flush_costs.call_deferred()

func _flush_costs() -> void:
	_costs_queued = false
	if _is_open:
		_refresh_block()
		_update_card_costs()

## El coste de cada tarjeta desbloqueada, con lo que falta en rojo. TextKit no
## rehace la fila si no cambio nada.
func _update_card_costs() -> void:
	for card in _grid_container.get_children():
		if card.is_queued_for_deletion():
			continue
		var row := card.find_child("CardCost", true, false) as HFlowContainer
		var id := String(card.get_meta("building_id", ""))
		# El tope cambia con lo construido y con la era, este o no bloqueada.
		var limit_row := card.find_child("CardLimit", true, false) as HBoxContainer
		if limit_row != null:
			fill_limit_row(limit_row, id, "small")
		if row == null or not _card_styles.has(id) or bool(_card_styles[id].get("locked", false)):
			continue
		var data: BuildingData = _data_by_id(id)
		if data != null:
			TextKit.fill_cost_row(row, Rules.cost_by_name(data), Rules.missing_cost(data), "small", UITheme.WARNING)

func _data_by_id(id: String) -> BuildingData:
	for data in _all_buildings:
		if data.id == id:
			return data
	return null

func _on_build_pressed() -> void:
	if _selected_data and not _detail_build_btn.disabled:
		EventBus.building_selected_for_placement.emit(_selected_data)
		_close()

# ══════════════════════════════════════════════════════════════════════
# ── Helpers ──
# ══════════════════════════════════════════════════════════════════════

func _has_locked_resource_cost(data: BuildingData) -> bool:
	# Cualquier recurso o material del coste que aun no este en el juego.
	var cost := data.get_cost()
	for type in cost:
		if not ResourceManager.is_unlocked(type) and ResourceManager.get_amount(type) < int(cost[type]):
			return true
	return false

# ══════════════════════════════════════════════════════════════════════
# ── Thumbnail Generation (background, for grid cards) ──
# ══════════════════════════════════════════════════════════════════════

func _generate_thumbnails() -> void:
	# En 2D las miniaturas se dibujan al vuelo (BuildingIcon2D): nada que renderizar.
	if _is_2d:
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.world_3d = World3D.new()

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.0
	camera.look_at_from_position(Vector3(3.5, 4.0, 3.5), Vector3(0, 0.3, 0))
	viewport.add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	light.light_energy = 1.2
	viewport.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, -150, 0)
	fill.light_energy = 0.4
	viewport.add_child(fill)

	add_child(viewport)

	for data in _all_buildings:
		await _render_thumbnail(viewport, camera, data)

	viewport.queue_free()
	# Las miniaturas que no llegaron a tiempo a su tarjeta: la firma de la
	# rejilla cambia y la proxima vez que se abra (o ya, si esta abierta) se
	# rehace con ellas.
	_request_grid_refresh()

func _render_thumbnail(viewport: SubViewport, camera: Camera3D, data: BuildingData) -> void:
	var model: Node3D = null
	if data.model_scene:
		model = data.instantiate_model()
	else:
		model = DieselpunkBuildingFactory.create(data.id, GridManager.cell_size, data.grid_size)
	if not model:
		return

	viewport.add_child(model)
	var max_dim := maxf(data.grid_size.x, data.grid_size.y) * GridManager.cell_size
	camera.size = max_dim * 2.5

	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw

	var image := viewport.get_texture().get_image()
	var tex := ImageTexture.create_from_image(image)
	_thumb_cache[data.id] = tex

	if _thumb_rects.has(data.id) and is_instance_valid(_thumb_rects[data.id]):
		_thumb_rects[data.id].texture = tex

	model.queue_free()

## El boton CONSTRUIR del HUD, para pruebas.
## Id del edificio elegido en la lista ("" si ninguno). Para el tutorial.
func selected_building_id() -> String:
	return String(_selected_data.id) if _selected_data != null and _is_open else ""

## El CONSTRUIR del detalle (el que empieza a colocar). Para el tutorial.
func detail_build_button() -> Button:
	return _detail_build_btn

func build_button() -> Button:
	return _build_btn
