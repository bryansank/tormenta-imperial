extends CanvasLayer
## CONSTRUIR (rediseno fase 2, docs/28-guia-ui.md; maqueta en
## tools/ui_mockup/mock_screens.gd, build_construction).
##
## Ventana crema con la cinta verde. A la izquierda, un carril de pestanas de
## categoria (icono; con su palabra en PC). En medio, una lista de filas de UNA
## linea: miniatura, nombre, coste en iconos (en rojo lo que falta) y el martillo
## verde, que construye directamente. Lo que no se puede, con su porque corto en
## vez del coste: candado + "Rango 4", "Era 2", "Falta Almacén"; lleno, "Al
## máximo" y el atajo MEJORAR UNO. El detalle de cada fila, al mantener pulsado
## (TouchTooltip) o al pasar el raton.
##
## En PC y tablet, a la derecha, la ficha del elegido: miniatura, una frase, lo
## que da, por que no se puede, el coste y CONSTRUIR. En telefono (lienzo de
## menos de 450 de alto) la ficha no cabe: el elegido sale en una franja debajo
## de la lista (nombre, porque, coste y CONSTRUIR / MEJORAR). La ventana va a
## pantalla completa en todos los perfiles, dentro de la zona segura, con la X
## a la izquierda del boton ☰ (que se dibuja encima de todo).
##
## Los nombres, siempre enteros (dos lineas antes que "…"), en Baloo 2 de 16 dp
## como poco en telefono (CartoonTheme.name_label); el globo de cada fila
## empieza por el nombre.
##
## Sin animaciones (decision de Bryan): ni la maqueta 3D que giraba ni nada que
## se mueva; la miniatura es la foto que se hace al arrancar.
##
## Tocar una fila la ELIGE (al soltar dentro: arrastrar la lista empieza encima
## de una fila y no debe elegirla); el martillo elige y construye. El tutorial
## busca las filas por id (card_for) y el CONSTRUIR de la ficha
## (detail_build_button).

const CT := preload("res://scripts/ui/CartoonTheme.gd")
const PlacementAssistScript := preload("res://scripts/buildings/PlacementAssist.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const TextKit := preload("res://scripts/ui/TextKit.gd")
const HelpText := preload("res://scripts/ui/BuildingHelpText.gd")

var _root: Control
var _backdrop: ColorRect
## La ventana entera (cinta + panel + X). La coloca UILayoutManager en PC y
## CartoonTheme.fit_fullscreen en telefono.
var _modal: Control
var _win: Dictionary = {}
var _build_btn: Button
## Tamano del boton CONSTRUIR del HUD (el primario del juego).
const BUILD_BTN_W := 240.0
const BUILD_BTN_H := 64.0
var _is_open := false
## Telefono: la disposicion con la que se monto la lista (cambia al girar o al
## cambiar de perfil, y entonces se rehace).
var _phone := false

# Category state
var _all_buildings: Array = []
var _current_category := "all"
## Ya no hay buscador (menos interfaz, docs/28 §0); se conserva por si algo lo
## pone a mano.
var _search_text := ""
var _cat_buttons: Dictionary = {}
var _rail: VBoxContainer

# La lista (una fila por edificio)
var _grid_container: VBoxContainer
var _grid_scroll: ScrollContainer

# Ficha del elegido (PC)
var _detail_column: VBoxContainer
var _detail_panel: VBoxContainer
var _detail_name: Label
var _detail_desc: Label
## El coste en fila de iconos con su cifra; en rojo lo que falta.
var _detail_cost: HBoxContainer
## Lo que produce: "+6 [madera] cada 12 s".
var _detail_production: HBoxContainer
## Trabajadores que pide, alojamiento y moral que da, en fichas de cifra.
var _detail_extras: HBoxContainer
## "[edificio] 3/6": cuantos hay y el tope de la era.
var _detail_limit: HBoxContainer
## "Necesita bosque al lado": la regla del yacimiento, antes de colocar.
var _detail_rule: Label
## Por que no se puede construir ahora ("Te falta: 20 Madera"), junto al boton.
var _detail_block: Label
## La frase del tope lleno y lo que trae una era aun no alcanzada.
var _detail_explain: Label
var _detail_upgrade_one: Button
var _detail_build_btn: Button
var _detail_thumb: TextureRect
var _selected_data: BuildingData = null

# Thumbnail cache
var _thumb_cache: Dictionary = {}  # building_id -> ImageTexture

# Vista 2D (docs/18-vista-2d.md): miniaturas con el dibujo plano del mapa en vez
# de fotos de los modelos 3D. Se decide al arrancar: sin Camera3D es la 2D.
const BuildingIcon2D := preload("res://scripts/view2d/BuildingIcon2D.gd")
var _is_2d := false
var _preview_icon: Control = null
var _thumb_rects: Dictionary = {}  # building_id -> TextureRect

const CATEGORIES := ["all", "production", "support", "military", "decoration"]
## El icono de cada pestana del carril.
const CATEGORY_GLYPHS := {
	"all": "build", "production": "res:wood", "support": "res:workers",
	"military": "army", "decoration": "star",
}

## Ancho de la ficha del elegido (PC) y ancho minimo de lienzo para que quepa.
const DETAIL_W := 300.0
const DETAIL_MIN_VP_W := 760.0
## Lo que se le deja a la lista y al carril antes de dar sitio a la ficha, y el
## ancho de la ficha por debajo del cual ya no se encoge mas.
const LIST_MIN_W := 520.0
const RAIL_W := 180.0
const DETAIL_MIN_W := 250.0
## Por debajo de este ancho de lienzo (tablet), el atajo MEJORAR de la fila va
## solo con su icono: la palabra empujaba la ficha fuera de la pantalla.
const WIDE_ROWS_VP_W := 1200.0
## Filas compactas (tablet): MEJORAR de la fila solo con icono.
var _compact := false

## Capa en reposo (lista cerrada): bajo cualquier ventana de UIManager, que
## apila desde la 12. Con la lista abierta la capa la pone UIManager.
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
	# Los topes suben con la era (GameConfig.building_limits_by_era).
	EventBus.era_advanced.connect(func(_e):
		_request_grid_refresh()
		_refresh_block())
	EventBus.game_load_completed.connect(_request_grid_refresh)
	EventBus.game_new_started.connect(_request_grid_refresh)
	# Con la lista abierta, el coste en rojo o no y el porque siguen a lo que hay.
	EventBus.resource_changed.connect(func(_t, _a, _d): _on_resources_changed())
	EventBus.workers_changed.connect(func(_u, _t): _on_resources_changed())
	# CONSTRUIR es la accion principal: siempre a la vista. Con la barra de
	# abajo (estilo maqueta) el boton es suyo, en su fila: este se esconde y le
	# deja el grupo que busca el tutorial.
	_build_btn.visible = true
	_hand_build_button_to_bar.call_deferred()
	UIManager.register_panel(self, "ConstructionMenu.modal")
	UILayoutManager.layout_changed.connect(_fit_layout)
	get_viewport().size_changed.connect(_fit_layout)

func _load_buildings() -> void:
	_all_buildings.clear()
	for res in BuildingData.load_all():
		if not res.is_core:
			_all_buildings.append(res)
	_all_buildings.sort_custom(func(a, b): return a.get_display_name() < b.get_display_name())

func _get_category(data: BuildingData) -> String:
	if data.is_decoration:
		return "decoration"
	if data.id in ["house", "warehouse", "silo", "fuel_depot", "tavern", "well", "lighthouse"]:
		return "support"
	if data.id in ["barracks", "tower", "shipyard", "aerodrome"]:
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

func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)

func _setup_ui() -> void:
	_phone = CT.is_phone()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# El boton CONSTRUIR del HUD (abajo en el centro). La barra de abajo es de
	# otro frente: aqui solo se crea y se registra, como siempre.
	_build_btn = Button.new()
	_build_btn.name = "BuildButton"
	_build_btn.add_to_group("hud_build_button")
	_build_btn.text = Tr.t("BTN_BUILD_BIG")
	_build_btn.tooltip_text = Tr.t("BTN_BUILD_HINT")
	_build_btn.focus_mode = Control.FOCUS_NONE
	_build_btn.custom_minimum_size = Vector2(BUILD_BTN_W, BUILD_BTN_H)
	UILayoutManager.apply_layout("ConstructionMenu.button", _build_btn)
	UITheme.style_button(_build_btn, UITheme.POSITIVE.darkened(0.1), UITheme.FONT_TITLE)
	_build_btn.add_theme_stylebox_override("normal", UITheme._button_style(
		UITheme._metal_tint(UITheme.POSITIVE, 1.35), UITheme.POSITIVE, UITheme.ACCENT, 4))
	_build_btn.pressed.connect(_open)
	_root.add_child(_build_btn)
	HudRegistry.register("ConstructionMenu.button", _build_btn)

	# Velo sobre el mapa: tocarlo cierra.
	_backdrop = CT.veil()
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close()
	)
	_root.add_child(_backdrop)

	# La ventana: cinta verde CONSTRUIR y la X roja.
	_win = CT.window(Tr.t("UI2C_BUILD_TITLE"), CT.sem("POSITIVE"))
	_modal = _win["root"]
	_modal.name = "BuildWindow"
	_modal.visible = false
	(_win["close"] as Button).pressed.connect(_close)
	(_win["close"] as Button).tooltip_text = Tr.t("UI2C_CLOSE")
	(_win["panel"] as Control).gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			UIManager.focus_window(self)
	)
	_root.add_child(_modal)
	# A pantalla completa en todos los perfiles: _fit_layout la coloca (sin slot).

	var body: VBoxContainer = _win["body"]
	var main := HBoxContainer.new()
	main.name = "BuildMain"
	main.add_theme_constant_override("separation", 8 if _phone else CT.GAP + 4)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(main)

	# Carril de pestanas de categoria, a la izquierda.
	_rail = VBoxContainer.new()
	_rail.name = "CategoryRail"
	_rail.add_theme_constant_override("separation", 6)
	main.add_child(_rail)
	_build_rail()

	# La lista: una fila por edificio, en una columna que se arrastra con el dedo.
	_grid_scroll = ScrollContainer.new()
	_grid_scroll.name = "BuildList"
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# La lista y, debajo (solo telefono), la franja del elegido.
	var list_col := VBoxContainer.new()
	list_col.name = "ListColumn"
	list_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_col.add_theme_constant_override("separation", 6)
	main.add_child(list_col)
	list_col.add_child(_grid_scroll)
	_build_strip(list_col)
	_grid_container = VBoxContainer.new()
	_grid_container.add_theme_constant_override("separation", 6)
	_grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_scroll.add_child(_grid_container)

	_build_detail(main)
	_show_no_selection()
	_refresh_grid()
	_fit_layout()

## El carril: en telefono solo iconos (el nombre al mantener); en PC icono y
## palabra. La elegida, verde y con labio.
func _build_rail() -> void:
	for child in _rail.get_children():
		_rail.remove_child(child)
		child.queue_free()
	_cat_buttons.clear()
	var names := {
		"all": Tr.t("LBL_CAT_ALL"),
		"production": Tr.t("LBL_CAT_PRODUCTION"),
		"support": Tr.t("LBL_CAT_SUPPORT"),
		"military": Tr.t("LBL_CAT_MILITARY"),
		"decoration": Tr.t("LBL_CAT_DECORATION"),
	}
	for cat_id in CATEGORIES:
		var sel: bool = cat_id == _current_category
		var t := CT.tab("" if _phone else String(names[cat_id]), String(CATEGORY_GLYPHS[cat_id]), sel, "window",
			CT.sem("POSITIVE") if sel else Color(0, 0, 0, 0), 48 if _phone else CT.BTN)
		t.name = "Cat_" + cat_id
		t.tooltip_text = String(names[cat_id])
		t.focus_mode = Control.FOCUS_NONE
		if _phone:
			t.custom_minimum_size = Vector2(52, 48)
		else:
			t.set_meta("min_w", 180.0)
			t.custom_minimum_size.x = maxf(t.custom_minimum_size.x, 180.0)
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cid: String = cat_id
		t.pressed.connect(func(): _select_category(cid))
		_rail.add_child(t)
		_cat_buttons[cat_id] = t

## La ficha de la derecha (PC). CONSTRUIR, MEJORAR UNO, el coste y el porque
## van fuera del scroll: en tablet la ficha es mas alta que la ventana y el
## boton quedaba fuera (QA flujo 04).
func _build_detail(main: HBoxContainer) -> void:
	_detail_column = VBoxContainer.new()
	_detail_column.name = "DetailColumn"
	_detail_column.custom_minimum_size = Vector2(DETAIL_W, 0)
	_detail_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_column.add_theme_constant_override("separation", 8)
	main.add_child(_detail_column)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_column.add_child(detail_scroll)

	_detail_panel = VBoxContainer.new()
	_detail_panel.add_theme_constant_override("separation", 8)
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_detail_panel)

	# Miniatura: la foto del modelo (3D) o el dibujo del mapa (2D). Quieta.
	var thumb_box := Control.new()
	thumb_box.custom_minimum_size = Vector2(0, 120)
	if _is_2d:
		_preview_icon = BuildingIcon2D.new()
		_preview_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		thumb_box.add_child(_preview_icon)
	else:
		_detail_thumb = TextureRect.new()
		_detail_thumb.name = "DetailThumb"
		_detail_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_detail_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_detail_thumb.set_anchors_preset(Control.PRESET_FULL_RECT)
		thumb_box.add_child(_detail_thumb)
	_detail_panel.add_child(CT.thumb_frame(thumb_box, Vector2(0, 120)))

	# El nombre; la descripcion entera y el tamano, en su tooltip.
	_detail_name = CT.label("", "title", CT.text("window"))
	_detail_name.name = "DetailName"
	_detail_name.mouse_filter = Control.MOUSE_FILTER_PASS
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_panel.add_child(_detail_name)
	# Una frase como mucho (docs/28 §9).
	_detail_desc = CT.para("", "window", true)
	_detail_desc.name = "DetailDesc"
	_detail_panel.add_child(_detail_desc)

	_detail_production = HBoxContainer.new()
	_detail_production.name = "DetailProduction"
	_detail_production.add_theme_constant_override("separation", 6)
	_detail_production.mouse_filter = Control.MOUSE_FILTER_PASS
	_detail_panel.add_child(_detail_production)

	_detail_extras = HBoxContainer.new()
	_detail_extras.name = "DetailExtras"
	_detail_extras.add_theme_constant_override("separation", 14)
	_detail_panel.add_child(_detail_extras)

	_detail_rule = CT.para("", "window", true, "small")
	_detail_rule.name = "DepositRule"
	_detail_rule.mouse_filter = Control.MOUSE_FILTER_PASS
	_detail_panel.add_child(_detail_rule)

	_detail_limit = HBoxContainer.new()
	_detail_limit.name = "DetailLimit"
	_detail_limit.visible = false
	_detail_panel.add_child(_detail_limit)

	# Lo que decide, fuera del scroll y junto al boton.
	_detail_explain = CT.para("", "window", false, "small")
	_detail_explain.name = "DetailExplain"
	_detail_explain.add_theme_color_override("font_color", CT.tone_color("warning"))
	_detail_explain.mouse_filter = Control.MOUSE_FILTER_PASS
	_detail_explain.visible = false
	_detail_column.add_child(_detail_explain)

	_detail_block = CT.why_label()
	_detail_block.name = "DetailBlock"
	_detail_block.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_detail_column.add_child(_detail_block)

	_detail_cost = CT.cost_strip({})
	_detail_cost.name = "DetailCost"
	_detail_column.add_child(_detail_cost)

	# Con el tope lleno: lleva al de nivel mas bajo y abre su ficha para mejorarlo.
	_detail_upgrade_one = CT.pill_button(Tr.t("TOPE_BTN_UPGRADE_ONE"), "upgrade", "open", CT.h("btn"))
	_detail_upgrade_one.name = "DetailUpgradeOne"
	_detail_upgrade_one.tooltip_text = Tr.t("TOPE_BTN_UPGRADE_ONE_TIP")
	_detail_upgrade_one.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_upgrade_one.pressed.connect(_on_upgrade_one)
	_detail_upgrade_one.visible = false
	_detail_column.add_child(_detail_upgrade_one)

	_detail_build_btn = CT.pill_button(Tr.t("BTN_BUILD"), "build", "primary", CT.h("big"))
	_detail_build_btn.name = "DetailBuildButton"
	_detail_build_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_build_btn.pressed.connect(_on_build_pressed)
	_detail_column.add_child(_detail_build_btn)

## Telefono: la franja del elegido, debajo de la lista (la ficha de la derecha
## no cabe): Nombre entero / porque · coste · CONSTRUIR o MEJORAR.
var _strip: PanelContainer
var _strip_name: Label
var _strip_why: Label
var _strip_cost: HBoxContainer
var _strip_build: Button
var _strip_upgrade: Button

func _build_strip(parent: Control) -> void:
	_strip = PanelContainer.new()
	_strip.name = "PhoneStrip"
	var st := CT.card_style("window", true)
	st.set_content_margin_all(4)
	st.content_margin_left = 8
	_strip.add_theme_stylebox_override("panel", st)
	_strip.visible = false
	parent.add_child(_strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_strip.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	_strip_name = CT.name_label("", "button")
	_strip_name.name = "StripName"
	col.add_child(_strip_name)
	_strip_why = CT.label("", "small", CT.danger_text())
	_strip_why.name = "StripWhy"
	_strip_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_strip_why)
	_strip_cost = CT.cost_strip({})
	_strip_cost.name = "StripCost"
	_strip_cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_strip_cost)
	_strip_upgrade = CT.pill_button("", "upgrade", "open", 48)
	_strip_upgrade.name = "StripUpgradeOne"
	_strip_upgrade.tooltip_text = Tr.t("TOPE_BTN_UPGRADE_ONE_TIP")
	_strip_upgrade.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_strip_upgrade.pressed.connect(_on_upgrade_one)
	row.add_child(_strip_upgrade)
	_strip_build = CT.pill_button(Tr.t("BTN_BUILD"), "build", "primary", 48)
	_strip_build.name = "StripBuildButton"
	_strip_build.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_strip_build.pressed.connect(_on_build_pressed)
	row.add_child(_strip_build)

## Pone la franja del telefono al dia con el elegido (oculta en PC y tablet, o
## sin elegido).
func _refresh_strip() -> void:
	if _strip == null:
		return
	_strip.visible = _phone and _selected_data != null and _is_open
	if not _strip.visible:
		return
	var data := _selected_data
	_strip_name.text = data.get_display_name()
	var block := Rules.purchase_block_detail(data)
	var full := HelpText.is_full(data.id)
	var why := lock_reason(data)
	if why == "" and full:
		why = Tr.t("TOPE_CARD_FULL")
	elif why == "" and block != "":
		var short: Array = Rules.block_reasons_short(data)
		why = String(short[0]) if not short.is_empty() else ""
	_strip_why.text = why
	_strip_why.visible = why != ""
	# Lleno no es un error: ambar, como la etiqueta "Al máximo" de la fila.
	_strip_why.add_theme_color_override("font_color", CT.sem("WARNING").darkened(0.35) \
		if (full and lock_reason(data) == "") else CT.danger_text())
	_strip_why.tooltip_text = block
	_strip.tooltip_text = _row_tooltip_of(data, block)
	CT.fill_cost_strip(_strip_cost, Rules.cost_by_name(data), Rules.missing_cost(data))
	_strip_cost.visible = not full and lock_reason(data) == ""
	_strip_upgrade.visible = full and Rules.upgrade_does_something(data) \
		and HelpText.lowest_upgradable(data.id) != null
	_strip_build.visible = not full
	_strip_build.disabled = block != ""

## Coloca la ventana a pantalla completa (todos los perfiles, zona segura).
## Si cambia de telefono a PC (o al reves) se rehacen el carril y las filas.
func _fit_layout() -> void:
	if _modal == null or not is_inside_tree():
		return
	var vp := _vp()
	var ph := CT.is_phone()
	# A pantalla completa en todos los perfiles (Bryan, 2026-10-19: "es mas
	# facil"), con margen al borde: en PC y tablet la ficha va a la derecha.
	CT.fit_fullscreen(_win, 8.0 if ph else 16.0)
	var root := _win["root"] as Control
	if not ph:
		root.offset_top = 10.0
		var close: Control = _win.get("close")
		if close != null:
			close.offset_left = -close.custom_minimum_size.x - 6
			close.offset_right = -6
	# Zona segura del telefono (muesca, barra de gestos): fuera de ella.
	var safe := CT.safe_insets(get_viewport())
	root.offset_left += float(safe["left"])
	root.offset_top += float(safe["top"])
	root.offset_right -= float(safe["right"])
	root.offset_bottom -= float(safe["bottom"])
	_detail_column.visible = not ph and vp.x >= DETAIL_MIN_VP_W
	# La ficha nunca empuja la lista fuera de la ventana (tablet 1280x800: los
	# botones de la ficha salian cortados por la derecha).
	var room := vp.x - 32.0 - float(safe["left"]) - float(safe["right"]) - 60.0 - RAIL_W - LIST_MIN_W
	_detail_column.custom_minimum_size.x = clampf(minf(vp.x * 0.30, room), DETAIL_MIN_W, 460.0)
	var compact := not ph and vp.x < WIDE_ROWS_VP_W
	if ph != _phone or compact != _compact:
		_phone = ph
		_compact = compact
		_build_rail()
		_grid_sig = []
		_refresh_grid()
	_refresh_strip()
	# El ☰ (capa 30) tapaba la X en todos los perfiles: la X va a su izquierda.
	CT.dodge_menu_button.call_deferred(_win.get("close"))

# ══════════════════════════════════════════════════════════════════════
# ── Open / Close ──
# ══════════════════════════════════════════════════════════════════════

## Abre la lista (para la barra de abajo y el tutorial).
func open() -> void:
	if not _is_open:
		_open()

## Abre la lista con `building_id` ya elegido (los pasos de ¿QUE HACER?, 2026-10-19).
func open_on(building_id: String) -> void:
	open()
	var data := _data_by_id(building_id)
	if data != null:
		_select_building(data)

func _open() -> void:
	_is_open = true
	_fit_layout()
	_modal.visible = true
	_backdrop.visible = true
	_refresh_grid()
	_refresh_block()
	UIManager.open_panel(self)

func _close() -> void:
	_is_open = false
	_modal.visible = false
	if _strip != null:
		_strip.visible = false
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

## Fondo de un boton del filtro del estilo viejo (se conserva para quien lo use).
static func filter_color(active: bool) -> Color:
	return UITheme.ACCENT.darkened(0.55) if active else UITheme.BTN

func _select_category(cat_id: String) -> void:
	if cat_id == _current_category:
		return
	_current_category = cat_id
	_build_rail()
	_refresh_grid()
	_grid_scroll.scroll_vertical = 0

# ══════════════════════════════════════════════════════════════════════
# ── La lista (una fila por edificio) ──
# ══════════════════════════════════════════════════════════════════════

## Filas por id de edificio (HelpTargets las busca asi) y lo que se repinta de
## cada una sin rehacerla: {"cost", "full", "up", "hammer", "locked"}.
var _cards: Dictionary = {}
var _row_parts: Dictionary = {}
## Lo que decide como es cada fila: [id, porque del candado, con miniatura].
## Si no cambia, la lista no se rehace: solo se repintan costes y topes.
var _grid_sig: Array = []

## La fila de `building_id`, o null. Para el tutorial.
func card_for(building_id: String) -> Control:
	var card: Control = _cards.get(building_id)
	return card if card != null and is_instance_valid(card) else null

## Una senal pide rehacer la lista: cerrada no se hace nada (_open la pone al
## dia), abierta se hace una vez al final del fotograma.
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
	var sig: Array = [_phone, _compact]
	for data in filtered:
		sig.append([data.id, lock_reason(data), _thumb_cache.has(data.id)])
	return sig

## Rehace las filas solo si cambia cuales hay o si alguna se bloquea o se
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
		_grid_container.remove_child(child)
		child.queue_free()
	_cards.clear()
	_row_parts.clear()
	_thumb_rects.clear()
	for data in filtered:
		var card := _create_grid_card(data)
		_grid_container.add_child(card)
		_cards[data.id] = card
	_update_card_costs()
	_mark_selected_card()

## Una fila: [miniatura] Nombre ........ [coste] [martillo]. Bloqueada, el
## candado y su porque en el sitio del coste, y sin martillo.
func _create_grid_card(data: BuildingData) -> PanelContainer:
	var reason := lock_reason(data)
	var locked := reason != ""
	var card := PanelContainer.new()
	# El tutorial busca la fila por id, no por el nombre traducido.
	card.set_meta("building_id", data.id)
	card.set_meta("locked", locked)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Alto de dedo; el ancho minimo solo hace que la fila se pueda tocar antes
	# de que la lista tenga tamano (al abrir, y en las pruebas).
	card.custom_minimum_size = Vector2(160, 48 if _phone else 60)
	_style_row(card, false, locked, false)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)

	row.add_child(_make_thumb(data, Vector2(52, 40) if _phone else Vector2(64, 48), locked))

	# El nombre siempre entero: si no cabe, la fila crece a dos lineas.
	# El nombre siempre entero (crece a dos lineas antes que cortar), en Baloo 2
	# de 16 dp como poco en telefono y en el color normal tambien bloqueado: lo
	# apagado ya lo dicen la miniatura y el fondo (contraste).
	var name_label := CT.name_label(data.get_display_name(), "button")
	name_label.name = "RowName"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.custom_minimum_size.x = 96.0 if _phone else 150.0
	row.add_child(name_label)

	if locked:
		var lock := HBoxContainer.new()
		lock.name = "RankLock" if not Rules.check_rank(data.id) else "LockReason"
		lock.add_theme_constant_override("separation", 4)
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var g := CT.make_glyph("lock", 20 if _phone else 24)
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lock.add_child(g)
		# "Falta Almacén" lleva un nombre: el mismo minimo que los nombres.
		var why := CT.name_label(reason, "small")
		why.autowrap_mode = TextServer.AUTOWRAP_OFF
		why.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		why.name = "RankLockLabel" if lock.name == "RankLock" else "LockLabel"
		lock.add_child(why)
		row.add_child(lock)
	else:
		# El coste, con lo que falta en rojo (y los trabajadores, si faltan).
		var cost := CT.cost_strip({}, {}, "window", "", "number")
		cost.name = "CardCost"
		cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cost)
		# La primera a mitad de precio (GameConfig.first_building_discount, 2026-10-19).
		var deal := CT.badge(Tr.t("LBL_FIRST_HALF_PRICE"), CT.sem("POSITIVE"))
		deal.name = "CardDeal"
		deal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		deal.visible = data.first_discount_factor() < 1.0
		row.add_child(deal)
		# Lleno: una palabra en vez del coste, y el atajo para mejorar uno.
		var full := CT.badge(Tr.t("TOPE_CARD_FULL"), CT.sem("WARNING"))
		full.name = "CardFull"
		full.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		full.visible = false
		row.add_child(full)
		var up := CT.pill_button("" if (_phone or _compact) else Tr.t("UI2C_BTN_UPGRADE_ONE_SHORT"), "upgrade", "open", 48 if _phone else CT.BTN_SMALL)
		up.name = "RowUpgradeOne"
		up.tooltip_text = Tr.t("TOPE_BTN_UPGRADE_ONE_TIP")
		up.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		up.visible = false
		up.pressed.connect(func():
			_select_building(data)
			_on_upgrade_one())
		row.add_child(up)
		# El martillo: elige y empieza a colocar.
		var hammer := CT.pill_button("", "build", "primary", 48 if _phone else CT.BTN_SMALL)
		hammer.name = "RowBuild"
		hammer.tooltip_text = Tr.t("UI2C_BTN_BUILD_TIP")
		hammer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hammer.pressed.connect(func():
			_select_building(data)
			_on_build_pressed())
		row.add_child(hammer)
		_row_parts[data.id] = {"cost": cost, "full": full, "up": up, "hammer": hammer, "deal": deal}

	card.tooltip_text = row_tooltip(data)

	# Se elige al SOLTAR dentro de la fila: arrastrar la lista (DragScroll)
	# empieza encima de una fila y no puede elegirla. Las bloqueadas tambien se
	# eligen: la ficha dice que les falta. El raton encima solo resalta (A14).
	card.gui_input.connect(func(event):
		if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
				and Rect2(Vector2.ZERO, card.size.max(card.custom_minimum_size)).has_point(event.position):
			_select_building(data)
	)
	if not locked:
		card.mouse_entered.connect(func():
			if not _is_selected(data):
				_style_row(card, false, false, true)
		)
		card.mouse_exited.connect(func():
			if not _is_selected(data):
				_style_row(card, false, false, false)
		)
	return card

## Estilo de una fila: normal, elegida (borde de laton), bloqueada (CARD_ALT) o
## con el raton encima (un poco mas clara).
func _style_row(card: PanelContainer, selected: bool, locked: bool, hover: bool) -> void:
	var fill := CT.c("window", "CARD_ALT") if locked else Color(0, 0, 0, 0)
	if hover and not locked:
		fill = CT.c("window", "CARD_ALT") if CT.dark_windows() else CT.c("window", "CARD").lightened(0.5)
	var s := CT.card_style("window", selected, fill)
	s.set_content_margin_all(3 if _phone else 6)
	s.content_margin_right = 6 if _phone else 8
	card.add_theme_stylebox_override("panel", s)

## La miniatura de una fila: la foto del modelo (3D) o el dibujo del mapa (2D).
func _make_thumb(data: BuildingData, px: Vector2, locked: bool) -> PanelContainer:
	var content: Control
	if _is_2d:
		var icon: Control = BuildingIcon2D.new()
		icon.data = data
		content = icon
	else:
		var tex_rect := TextureRect.new()
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.texture = _thumb_cache.get(data.id, null)
		_thumb_rects[data.id] = tex_rect
		content = tex_rect
	var frame := CT.thumb_frame(content, px)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if locked:
		frame.modulate = Color(1, 1, 1, 0.45)
	return frame

## El porque corto de una fila que no se puede construir, o "" si se puede (con
## o sin recursos): "Rango 4", "Era 2", "Falta Almacén", "Aún no". El tope lleno
## no cuenta aqui: lo dice la etiqueta "Al máximo". Estatica para las pruebas.
static func lock_reason(data: BuildingData) -> String:
	if data == null:
		return ""
	if not Rules.check_rank(data.id):
		return Tr.t("LBL_RANK_LOCK") % RankManager.building_rank(data.id)
	if has_locked_resource_cost(data):
		var era := HelpText.build_era(data)
		if era > ProgressionManager.current_era:
			return Tr.t("UI2C_BLD_ERA") % era
		return Tr.t("UI2C_BLD_LOCKED")
	if not Rules.check_prerequisites(data.id):
		var names := Rules.missing_prerequisite_names(data.id).split(" + ")
		return Tr.t("UI2C_BLD_NEEDS") % names[0]
	return ""

## Lo que se lee al mantener pulsada una fila: que es, su regla, su tope y, si
## no se puede, por que (entero). Estatica para las pruebas.
static func row_tooltip(data: BuildingData) -> String:
	return _row_tooltip_of(data, Rules.purchase_block_detail(data))

static func _row_tooltip_of(data: BuildingData, block: String) -> String:
	# El nombre entero primero: el globo se lee sin mirar la fila.
	var lines: Array = [data.get_display_name(), data.get_description()]
	var rule := PlacementAssistScript.rule_text(data.id)
	if rule != "":
		lines.append(rule)
	var lim := limit_tooltip(data.id)
	if lim != "":
		lines.append(lim)
	if block != "":
		lines.append(block)
	return "\n".join(lines)

## Candado dibujado + "Rango N" (estilo viejo). Lo usan la Colonia y los
## Regimientos; las filas de CONSTRUIR llevan el candado de CartoonIcon.
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
## (GridManager.map_version()).
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
## No rehace nada si el texto no cambio.
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
	row.add_theme_constant_override("separation", 6)
	row.tooltip_text = _limit_tooltip_of(info)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var color: Color = CT.tone_color("warning") if full else CT.text("window", true)
	var icon := CT.make_glyph("build", 20)
	icon.name = "LimitIcon"
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var level := "small" if font_size == "small" else "body"
	var label := CT.label(text, level, color)
	label.name = "LimitLabel"
	row.add_child(label)

## Una casita: tejado a dos aguas y cuerpo con puerta (estilo viejo).
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

## Un candado: arco del grillete y cuerpo con ojo de cerradura (estilo viejo).
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

## La fila elegida con borde de laton; las demas, normales.
func _mark_selected_card() -> void:
	for id in _cards:
		var card: PanelContainer = _cards[id]
		if not is_instance_valid(card):
			continue
		var selected: bool = _selected_data != null and _selected_data.id == id
		_style_row(card, selected, bool(card.get_meta("locked", false)), false)

# ══════════════════════════════════════════════════════════════════════
# ── Ficha del elegido ──
# ══════════════════════════════════════════════════════════════════════

func _show_no_selection() -> void:
	_selected_data = null
	_detail_name.text = Tr.t("LBL_SELECT_BUILDING")
	_detail_name.tooltip_text = ""
	_detail_desc.text = ""
	_detail_desc.visible = false
	CT.fill_cost_strip(_detail_cost, {})
	_fill_production({}, 0)
	_fill_extras(null)
	fill_limit_row(_detail_limit, "", "small")
	_detail_rule.text = ""
	_detail_rule.visible = false
	_detail_block.visible = false
	_detail_explain.visible = false
	_detail_upgrade_one.visible = false
	_detail_build_btn.visible = false
	_clear_preview_model()
	_refresh_strip()

func _select_building(data: BuildingData) -> void:
	if _selected_data == data:
		return
	_selected_data = data
	_mark_selected_card()

	# Nombre; el tamano y la descripcion entera, en su tooltip.
	_detail_name.text = data.get_display_name()
	_detail_name.tooltip_text = "%dx%d · %s" % [data.grid_size.x, data.grid_size.y, data.get_description()]
	_detail_desc.text = first_sentence(data.get_description())
	_detail_desc.tooltip_text = data.get_description()
	_detail_desc.visible = _detail_desc.text != ""

	# Produccion: "+6 [madera] cada 12 s".
	var prod := {}
	for pair in [["gold", data.produces_gold], ["steel", data.produces_steel], ["oil", data.produces_oil], ["wood", data.produces_wood], ["food", data.produces_food]]:
		if int(pair[1]) > 0:
			prod[pair[0]] = int(pair[1])
	_fill_production(prod, data.production_interval)
	_fill_extras(data)

	# Regla del yacimiento y de la carretera, en corto; entera en el tooltip.
	var rule := PlacementAssistScript.rule_text(data.id)
	_detail_rule.text = rule
	_detail_rule.tooltip_text = Tr.t("LBL_RULE_ROAD") if not data.is_core and data.id != "road" else ""
	_detail_rule.visible = rule != ""

	_detail_build_btn.visible = true
	_refresh_block()
	_load_preview_model(data)

## La primera frase de un texto (docs/28 §9: una frase como mucho).
static func first_sentence(text: String) -> String:
	var t := text.strip_edges()
	for i in t.length():
		if t[i] in [".", "!", "?"] and (i == t.length() - 1 or t[i + 1] == " "):
			return t.substr(0, i + 1)
	return t

func _load_preview_model(data: BuildingData) -> void:
	if _is_2d:
		if _preview_icon != null:
			_preview_icon.data = data
		return
	if _detail_thumb != null:
		_detail_thumb.texture = _thumb_cache.get(data.id, null)

func _clear_preview_model() -> void:
	if _preview_icon:
		_preview_icon.data = null
	if _detail_thumb != null:
		_detail_thumb.texture = null

## Lo que impide construir el elegido: se dice y el boton no deja empezar a
## colocar algo que luego no se puede pagar.
func _refresh_block() -> void:
	if _selected_data == null:
		_detail_block.visible = false
		return
	var block := Rules.purchase_block_detail(_selected_data)
	var explain := explain_lines(_selected_data)
	_detail_explain.text = "\n".join(explain)
	_detail_explain.visible = not explain.is_empty()
	var short := block_lines_without_explained(_selected_data, not explain.is_empty())
	_detail_block.text = "\n".join(short)
	_detail_block.tooltip_text = block
	_detail_block.visible = not short.is_empty()
	_detail_build_btn.disabled = block != ""
	_detail_upgrade_one.visible = HelpText.is_full(_selected_data.id) \
		and Rules.upgrade_does_something(_selected_data) \
		and HelpText.lowest_upgradable(_selected_data.id) != null
	fill_limit_row(_detail_limit, _selected_data.id, "body")
	_refresh_cost()
	_refresh_strip()

## Lo que se explica en frase sobre el boton: el tope lleno y que hacer, y lo
## que llega con una era o se fabrica en otro sitio. Estatica para las pruebas.
static func explain_lines(data: BuildingData) -> Array:
	var out: Array = []
	if data == null:
		return out
	var full := HelpText.limit_full_text(data.id)
	if full != "":
		out.append(full)
		var advice := HelpText.limit_full_advice(data.id)
		if advice != "":
			out.append(advice)
	out.append_array(HelpText.locked_lines(data))
	return out

## Las razones cortas de siempre, sin las que ya dice explain_lines() en frase.
static func block_lines_without_explained(data: BuildingData, explained: bool) -> Array:
	var lines: Array = Rules.block_reasons_short(data)
	if not explained:
		return lines
	var limit_line := ""
	if not Rules.check_building_limit(data.id):
		limit_line = Tr.t("LBL_LIMIT_REACHED") % [Rules.count_building(data.id), GameConfig.get_building_limit(data.id)]
	var unlock_head := Tr.t("LBL_NEEDS_UNLOCK").get_slice("%s", 0)
	var era_said := not HelpText.locked_lines(data).is_empty()
	var out: Array = []
	for line in lines:
		var l := String(line)
		if l == limit_line:
			continue
		if era_said and unlock_head != "" and l.begins_with(unlock_head):
			continue
		out.append(l)
	return out

## "Mejorar uno": cierra la lista, lleva la camara al de nivel mas bajo y abre
## su ficha (BuildingInfoPanel), donde esta MEJORAR con lo que da y lo que cuesta.
func _on_upgrade_one() -> void:
	if _selected_data == null:
		return
	var node := HelpText.lowest_upgradable(_selected_data.id)
	if node == null:
		return
	_close()
	HelpText.focus_and_select(get_viewport(), node)

## El coste del elegido, con lo que falta en rojo. Gratis lo dice.
func _refresh_cost() -> void:
	if _selected_data == null:
		CT.fill_cost_strip(_detail_cost, {})
		return
	var cost := Rules.cost_by_name(_selected_data)
	CT.fill_cost_strip(_detail_cost, cost, Rules.missing_cost(_selected_data))
	if cost.is_empty() and _detail_cost.get_child_count() == 0:
		var free := CT.label(Tr.t("LBL_FREE"), "button", CT.positive_text())
		_detail_cost.add_child(free)
		_detail_cost.remove_meta("strip_sig")

## "+6 [madera] cada 12 s", o nada si no produce.
func _fill_production(prod: Dictionary, interval: float) -> void:
	for child in _detail_production.get_children():
		_detail_production.remove_child(child)
		child.free()
	_detail_production.visible = not prod.is_empty()
	if prod.is_empty():
		return
	_detail_production.add_child(CT.cost_strip(prod, {}, "window", "+", "number", CT.positive_text()))
	if interval > 0:
		var every := CT.label(Tr.t("FMT_EVERY") % TextKit.short_time(interval), "body", CT.text("window", true))
		_detail_production.add_child(every)

## Trabajadores que pide, alojamiento y moral que da: fichas de cifra con su
## nombre debajo (el requisito va en el porque, no aqui).
func _fill_extras(data: BuildingData) -> void:
	for child in _detail_extras.get_children():
		_detail_extras.remove_child(child)
		child.free()
	if data == null:
		_detail_extras.visible = false
		return
	if data.workers_required > 0:
		_detail_extras.add_child(CT.stat_chip("res:workers", str(data.workers_required), Tr.t("UI2C_CHIP_WORK"), "window"))
	if data.population_capacity > 0:
		_detail_extras.add_child(CT.stat_chip("res:workers", "+%d" % data.population_capacity, Tr.t("UI2C_CHIP_ROOM"), "window"))
	if data.morale_bonus > 0:
		_detail_extras.add_child(CT.stat_chip("res:morale", "+%d" % data.morale_bonus, Tr.t("UI2C_CHIP_MORALE"), "window"))
	_detail_extras.visible = _detail_extras.get_child_count() > 0

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

## El coste de cada fila (con lo que falta en rojo), el tope lleno, el atajo de
## mejorar y el martillo. Cada pieza no se rehace si no cambio.
func _update_card_costs() -> void:
	var free_workers: int = PopulationManager.get_free_workers()
	for id in _row_parts:
		var parts: Dictionary = _row_parts[id]
		var card: Control = _cards.get(id)
		if card == null or not is_instance_valid(card) or card.is_queued_for_deletion():
			continue
		var data: BuildingData = _data_by_id(String(id))
		if data == null:
			continue
		var full := HelpText.is_full(data.id)
		var cost := Rules.cost_by_name(data)
		var short := Rules.missing_cost(data)
		if data.workers_required > 0 and free_workers < data.workers_required:
			cost["workers"] = data.workers_required
			short["workers"] = data.workers_required - free_workers
		CT.fill_cost_strip(parts["cost"], cost, short)
		(parts["cost"] as Control).visible = not full
		(parts["full"] as Control).visible = full
		if parts.has("deal"):
			(parts["deal"] as Control).visible = not full and data.first_discount_factor() < 1.0
		(parts["up"] as Control).visible = full and Rules.upgrade_does_something(data) \
			and HelpText.lowest_upgradable(data.id) != null
		var hammer: Button = parts["hammer"]
		hammer.visible = not full
		var block := Rules.purchase_block_detail(data)
		hammer.disabled = block != ""
		card.tooltip_text = _row_tooltip_of(data, block)

func _data_by_id(id: String) -> BuildingData:
	for data in _all_buildings:
		if data.id == id:
			return data
	return null

func _on_build_pressed() -> void:
	if _selected_data and Rules.purchase_block_detail(_selected_data) == "":
		EventBus.building_selected_for_placement.emit(_selected_data)
		_close()

# ══════════════════════════════════════════════════════════════════════
# ── Helpers ──
# ══════════════════════════════════════════════════════════════════════

## Cualquier recurso o material del coste que aun no este en el juego.
static func has_locked_resource_cost(data: BuildingData) -> bool:
	var cost := data.get_cost()
	for type in cost:
		if not ResourceManager.is_unlocked(type) and ResourceManager.get_amount(type) < int(cost[type]):
			return true
	return false

func _has_locked_resource_cost(data: BuildingData) -> bool:
	return has_locked_resource_cost(data)

# ══════════════════════════════════════════════════════════════════════
# ── Thumbnail Generation (background, for the rows) ──
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
	# Las miniaturas que no llegaron a tiempo a su fila: la firma de la lista
	# cambia y la proxima vez que se abra (o ya, si esta abierta) se rehace.
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
	# Mas cerca que antes (2,5): en la fila el modelo salia diminuto.
	camera.size = max_dim * 1.9

	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw

	var image := viewport.get_texture().get_image()
	var tex := ImageTexture.create_from_image(image)
	_thumb_cache[data.id] = tex

	if _thumb_rects.has(data.id) and is_instance_valid(_thumb_rects[data.id]):
		_thumb_rects[data.id].texture = tex
	if _selected_data != null and _selected_data.id == data.id and _detail_thumb != null:
		_detail_thumb.texture = tex

	model.queue_free()

## Id del edificio elegido en la lista ("" si ninguno). Para el tutorial.
func _bar() -> Node:
	return get_tree().get_first_node_in_group("bottom_bar") if is_inside_tree() else null

func _hand_build_button_to_bar() -> void:
	var bar := _bar()
	if bar == null or not bar.has_method("build_button") or bar.build_button() == null:
		return
	_build_btn.visible = false
	if _build_btn.is_in_group("hud_build_button"):
		_build_btn.remove_from_group("hud_build_button")

func selected_building_id() -> String:
	return String(_selected_data.id) if _selected_data != null and _is_open else ""

## El CONSTRUIR de la ficha (el que empieza a colocar). Para el tutorial.
func detail_build_button() -> Button:
	# En telefono la ficha no sale: el CONSTRUIR es el de la franja de abajo.
	if _phone and _strip_build != null:
		return _strip_build
	return _detail_build_btn

## El boton CONSTRUIR del HUD, para pruebas.
func build_button() -> Button:
	var bar := _bar()
	if bar != null and bar.has_method("build_button") and bar.build_button() != null:
		return bar.build_button()
	return _build_btn
