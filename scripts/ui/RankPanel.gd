extends CanvasLayer
## El rango del gobernador en pantalla. Tres piezas, ninguna con estado propio
## (todo se lee de RankManager):
##
##   Insignia   arriba a la derecha, junto al ☰ MENU: la bandera del pais, el
##              numero de rango, el nombre del pais y una barra fina de XP (el
##              titulo del rango, en el tooltip y en la tarjeta). Tocarla abre
##              la tarjeta. Slot propio "rank_badge" en UILayoutConfig y
##              registrada en HudRegistry (se oculta y se mueve).
##   Aviso      al subir de rango: "▲ 5 · Alcalde" y lo desbloqueado, corto, bajo
##              la insignia. Suena "rank_up" (AudioManager, no aqui).
##   Tarjeta    ☰ MENU > COLONIA: el pais (bandera y nombre), rango y XP, y el
##              boton BANDERA Y NOMBRE, que abre el editor (ColonyIdentityPanel)
##              con las piezas del rango (lo bloqueado, con candado y "Rango N").

const LAYER := 11
const BADGE_W := 196.0
const BADGE_W_NARROW := 118.0
const FLAG_SMALL := Vector2(36, 24)
const FLAG_BIG := Vector2(84, 56)
const CARD_W := 520.0

const ColonyFlag := preload("res://scripts/ui/ColonyFlag.gd")
const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const IdentityPanel := preload("res://scripts/ui/ColonyIdentityPanel.gd")

var _root: Control
var _dock: Control
var _badge: Button
var _badge_flag: TextureRect
var _badge_rank: Label
var _badge_title: Label
var _badge_bar: ProgressBar

var _backdrop: ColorRect
var _card: PanelContainer
var _card_flag: TextureRect
var _card_rank: Label
var _card_bar: ProgressBar
var _card_xp: Label
var _card_next: Label
var _card_name: Label
var _editor: CanvasLayer = null
var _is_open := false

## La fila de la colonia en la tarjeta (rediseno 2026-10, docs/28 §12): lo que
## salio del menu ☰ y no esta en la barra de abajo. [id, clave Tr, panel
## hermano, glifo].
const HUB_ENTRIES := [
	["progress", "BTN_PROGRESS", "ProgressPanel", "star"],
	["contracts", "BTN_CONTRACTS", "ContractPanel", "check"],
	["log", "BTN_LOG_MENU", "NotificationPanel", "clock"],
	["sandbox", "BTN_SANDBOX", "SandboxPanel", "wrench"],
]
var _hub: HFlowContainer
var _hub_buttons: Dictionary = {}
## Insignia en telefono: bandera, estrella, cifra y barra (sin el nombre).
const BADGE_W_PHONE := 128.0
const FLAG_PHONE := Vector2(33, 22)

static func _cartoon() -> bool:
	return UITheme.is_cartoon()

func _ready() -> void:
	layer = LAYER
	_setup_ui()
	UIManager.register_panel(self, "RankPanel.modal")
	EventBus.governor_xp_changed.connect(_on_xp_changed)
	EventBus.governor_rank_up.connect(_on_rank_up)
	EventBus.colony_identity_changed.connect(func(_n, _s): refresh())
	EventBus.game_load_completed.connect(refresh)
	EventBus.game_new_started.connect(refresh)
	get_viewport().size_changed.connect(_relayout)
	refresh()

# ── Montaje ──

func _setup_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_dock = Control.new()
	_dock.name = "RankDock"
	_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock.custom_minimum_size = Vector2(BADGE_W, UITheme.MIN_BTN_H)
	UILayoutManager.apply_layout("RankPanel", _dock)
	_root.add_child(_dock)

	_badge = Button.new()
	_badge.name = "RankBadge"
	_badge.focus_mode = Control.FOCUS_NONE
	_badge.tooltip_text = Tr.t("LBL_RANK_BADGE_TIP")
	_badge.set_anchors_preset(Control.PRESET_FULL_RECT)
	for state in ["normal", "hover", "pressed", "focus"]:
		var st := UITheme.make_hud_card_style(UITheme.ACCENT, 2)
		if _cartoon():
			# Ficha del HUD oscuro fino (docs/28 §12), mismo alto que el ☰.
			st = CartoonTheme.hud_style()
		st.content_margin_top = 4
		st.content_margin_bottom = 4
		st.content_margin_left = 6
		st.content_margin_right = 8
		if state == "hover":
			st.bg_color = st.bg_color.lightened(0.08)
		_badge.add_theme_stylebox_override(state, st)
	_badge.pressed.connect(open)
	_dock.add_child(_badge)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6
	row.offset_right = -8
	row.offset_top = 4
	row.offset_bottom = -4
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_child(row)

	_badge_flag = _make_flag_rect(FLAG_SMALL)
	_badge_flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_badge_flag)
	if _cartoon():
		# La estrella del rango delante de la cifra (docs/28 §12).
		var star := CartoonTheme.make_glyph("star", 20 if CartoonTheme.phone else 24, Color(0, 0, 0, 0), "hud")
		star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(star)
	_badge_rank = UITheme.make_label("1", "section", UITheme.ACCENT)
	if _cartoon():
		_badge_rank = CartoonTheme.label("1", "button", CartoonTheme.text("hud"))
	_badge_rank.name = "RankNumber"
	_badge_rank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_rank.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_badge_rank)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)
	_badge_title = UITheme.make_label("", "small", UITheme.TEXT)
	if _cartoon():
		_badge_title = CartoonTheme.label("", "small", CartoonTheme.text("hud", true))
	_badge_title.name = "ColonyName"
	_badge_title.clip_text = true
	_badge_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_badge_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_badge_title)
	_badge_bar = _make_thin_bar(5)
	if _cartoon():
		_badge_bar = CartoonTheme.progress(0.0, CartoonTheme.sem("INFO"), "hud", 8)
	_badge_bar.name = "RankXpBar"
	column.add_child(_badge_bar)

	HudRegistry.register("RankPanel", _dock)

	# ── Tarjeta de COLONIA ──
	_backdrop = UITheme.make_backdrop()
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _close())
	_root.add_child(_backdrop)

	_card = ModalKit.make_card(UITheme.SEPARATION)
	_card.name = "ColonyCard"
	_card.visible = false
	_root.add_child(_card)
	var col: VBoxContainer = _card.get_child(0)
	col.add_child(UITheme.make_panel_header(Tr.t("LBL_COLONY_TITLE"), _close))

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	_card_flag = _make_flag_rect(FLAG_BIG)
	head.add_child(_card_flag)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(info)
	_card_name = UITheme.make_label("", "section", UITheme.TEXT_BRIGHT)
	_card_name.name = "ColonyName"
	_card_name.clip_text = true
	_card_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(_card_name)
	_card_rank = UITheme.make_label("", "body", UITheme.ACCENT)
	info.add_child(_card_rank)
	_card_bar = _make_thin_bar(8)
	info.add_child(_card_bar)
	_card_xp = UITheme.make_label("", "small", UITheme.TEXT_DIM)
	info.add_child(_card_xp)

	_card_next = UITheme.make_label("", "small", UITheme.INFO)
	_card_next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_card_next)

	var edit := ModalKit.make_menu_button(Tr.t("BTN_COLONY_EDIT"), UITheme.ACCENT_DIM, open_editor)
	edit.name = "EditColony"
	col.add_child(edit)

	# ── La colonia, en una fila (rediseno 2026-10): lo que salio del menu ☰ y no
	# va en la barra de abajo. Progreso, Encargos, Registro y, en su modo,
	# Sandbox. Cada uno cierra esta tarjeta y abre su panel.
	_hub = HFlowContainer.new()
	_hub.name = "ColonyHub"
	_hub.add_theme_constant_override("h_separation", 8)
	_hub.add_theme_constant_override("v_separation", 8)
	col.add_child(_hub)
	for entry in HUB_ENTRIES:
		var id: String = entry[0]
		var b: Button
		if _cartoon():
			b = CartoonTheme.pill_button(Tr.t(String(entry[1])), String(entry[3]), "open",
				CartoonTheme.h("small"), "window", "body")
			b.pressed.connect(open_hub_entry.bind(id))
		else:
			b = ModalKit.make_menu_button(Tr.t(String(entry[1])), UITheme.BTN, open_hub_entry.bind(id))
		b.name = "Hub_" + id
		_hub.add_child(b)
		_hub_buttons[id] = b
	_relayout()

func _make_flag_rect(px: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	rect.custom_minimum_size = px
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

func _make_thin_bar(height: int) -> ProgressBar:
	var bar := UITheme.make_progress_bar(UITheme.ACCENT, height)
	var bg := StyleBoxFlat.new()
	bg.bg_color = UITheme.BG_DARK
	bg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar

## Insignia mas estrecha (sin titulo) en pantalla estrecha; la tarjeta centrada.
func _relayout() -> void:
	if _dock == null or not is_inside_tree():
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var narrow: bool = vp.x < UILayoutConfig.NARROW_WIDTH
	_dock.custom_minimum_size.x = BADGE_W_NARROW if narrow else BADGE_W
	_badge_title.visible = not narrow
	if _cartoon():
		# Mismo alto que el ☰ redondo; en telefono, bandera + cifra + barra.
		_dock.custom_minimum_size.y = CartoonTheme.menu_round()
		if CartoonTheme.phone:
			_dock.custom_minimum_size.x = BADGE_W_PHONE
			_badge_title.visible = false
			_badge_flag.custom_minimum_size = FLAG_PHONE
	ModalKit.fit_center(_card, CARD_W, vp)
	_card.reset_size()
	_card.offset_top = -_card.size.y * 0.5
	_card.offset_bottom = _card.size.y * 0.5

# ── Refresco ──

## Cada ciclo de produccion da 1 XP: con muchos edificios llegan varias en el
## mismo fotograma. Si el rango no cambia, se repinta una vez al final del
## fotograma; si cambia, ya.
var _refresh_queued := false
func _on_xp_changed(_xp: int, rank: int, _gained: int) -> void:
	if _badge_rank != null and _badge_rank.text != str(rank):
		refresh()
		return
	if _refresh_queued:
		return
	_refresh_queued = true
	_flush_refresh.call_deferred()

func _flush_refresh() -> void:
	_refresh_queued = false
	refresh()

func refresh() -> void:
	var rank: int = RankManager.get_rank()
	var flag_tex := ColonyFlag.current_texture()
	var title := Tr.t(RankManager.get_title_key())
	_badge_flag.texture = flag_tex
	_badge_rank.text = str(rank)
	_badge_title.text = RankManager.get_colony_name()
	_badge.tooltip_text = "%s · %s
%s" % [RankManager.get_colony_name(), title, Tr.t("LBL_RANK_BADGE_TIP")]
	_badge_bar.value = RankManager.get_rank_progress()
	if _is_open:
		_refresh_card()

func _refresh_card() -> void:
	var rank: int = RankManager.get_rank()
	_card_flag.texture = ColonyFlag.current_texture()
	_card_name.text = RankManager.get_colony_name()
	_card_rank.text = Tr.t("FMT_RANK_TITLE") % [rank, Tr.t(RankManager.get_title_key())]
	_card_bar.value = RankManager.get_rank_progress()
	if RankManager.is_max_rank():
		_card_xp.text = Tr.t("LBL_RANK_MAX")
		_card_next.text = ""
	else:
		_card_xp.text = Tr.t("FMT_RANK_XP") % [RankManager.get_xp(), RankManager.xp_for_rank(rank + 1)]
		var lines := reward_lines(RankManager.rewards_between(rank, rank + 1))
		_card_next.text = Tr.t("FMT_RANK_NEXT") % [rank + 1, ", ".join(lines)] if not lines.is_empty() else ""
	_card_next.visible = _card_next.text != ""
	_relayout.call_deferred()

# ── El editor del pais (ColonyIdentityPanel, modo "edit") ──

## Abre el editor sobre la tarjeta. LISTO aplica en RankManager.set_colony().
func open_editor() -> void:
	if _editor != null and is_instance_valid(_editor):
		return
	_editor = IdentityPanel.new()
	add_child(_editor)
	_editor.confirmed.connect(func(colony_name: String, spec: Dictionary):
		RankManager.set_colony(colony_name, spec))
	_editor.open("edit")

func editor() -> CanvasLayer:
	return _editor if _editor != null and is_instance_valid(_editor) else null

# ── Lo ganado, en pocas palabras ──

## "Fuente", "+1 % producción", "+2 Casa", "Bandera nueva"... una cosa por entrada.
static func reward_lines(rewards: Dictionary) -> Array:
	var out: Array = []
	for id in rewards.get("buildings", []):
		var data := Rules.load_building_data(String(id))
		out.append(data.get_display_name() if data != null else String(id))
	var limits: Dictionary = rewards.get("limit", {})
	for id in limits:
		# Huecos de algo sin tope (las decoraciones desde los topes por era) no
		# dan nada: no se anuncian.
		if GameConfig.is_uncapped_building(String(id)):
			continue
		var data := Rules.load_building_data(String(id))
		out.append(Tr.t("FMT_RANK_REWARD_SLOTS") % [int(limits[id]), data.get_display_name() if data != null else String(id)])
	if float(rewards.get("production", 0.0)) > 0.0:
		out.append(Tr.t("FMT_RANK_REWARD_PRODUCTION") % roundi(float(rewards["production"]) * 100.0))
	if float(rewards.get("storage", 0.0)) > 0.0:
		out.append(Tr.t("FMT_RANK_REWARD_STORAGE") % roundi(float(rewards["storage"]) * 100.0))
	if not rewards.get("patterns", []).is_empty():
		out.append(Tr.t("LBL_RANK_REWARD_PATTERN"))
	if not rewards.get("emblems", []).is_empty():
		out.append(Tr.t("LBL_RANK_REWARD_EMBLEM"))
	if not rewards.get("colors", []).is_empty():
		out.append(Tr.t("LBL_RANK_REWARD_COLOR"))
	if not rewards.get("paints", []).is_empty():
		out.append(Tr.t("LBL_RANK_REWARD_PAINT"))
	return out

# ── Aviso de ascenso ──

## El ascenso va a la columna de avisos (NotificationPanel, "achievement",
## 2026-10-18) en una frase: "▲ 3 · Maestro de obras: + Jardin, + Bandera
## nueva". Alli espera si hay una ventana o el tablero abiertos.
func _on_rank_up(rank: int, rewards: Dictionary) -> void:
	refresh()
	show_rank_toast(rank, rewards)

func show_rank_toast(rank: int, rewards: Dictionary) -> void:
	EventBus.notification_posted.emit(rank_up_text(rank, rewards), "achievement", UITheme.ACCENT)
	show_rank_stamp()

## Cuanto se queda el sello ASCENDIDO sobre la insignia.
const RANK_STAMP_SECONDS := 4.0

## El sello oficial (CartoonTheme.stamp) sobre la insignia, unos segundos: el
## momento del ascenso. Un PanelContainer y un temporizador; nada mas.
func show_rank_stamp() -> void:
	if not _cartoon() or _dock == null:
		return
	var old := _dock.get_node_or_null("RankStamp")
	if old != null:
		old.free()
	var st := CartoonTheme.stamp(Tr.t("STAMP_RANK_UP"), CartoonTheme.sem("ACCENT"), true)
	st.name = "RankStamp"
	st.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dock.add_child(st)
	if is_inside_tree():
		get_tree().create_timer(RANK_STAMP_SECONDS).timeout.connect(func():
			if is_instance_valid(st):
				st.queue_free())

## El sello del ascenso, si se ve (pruebas).
func rank_stamp() -> Control:
	return _dock.get_node_or_null("RankStamp") if _dock != null else null

static func rank_up_text(rank: int, rewards: Dictionary) -> String:
	var text := Tr.t("FMT_RANK_UP") % [rank, Tr.t(GameConfig.rank_title_key(rank))]
	var lines := reward_lines(rewards)
	if not lines.is_empty():
		text += ": " + ", ".join(lines.map(func(l): return "+ " + String(l)))
	return text

# ── Abrir y cerrar (☰ MENU > COLONIA, o tocar la insignia) ──

func is_open() -> bool:
	return _is_open

func open() -> void:
	if _is_open:
		return
	_is_open = true
	_card.visible = true
	_backdrop.visible = true
	_refresh_card()
	_refresh_hub()
	UIManager.open_panel(self)

## Que entradas de la colonia se ven: solo lo que existe en la escena y ya
## esta disponible (Encargos no en Sandbox; Sandbox solo en su modo).
func _refresh_hub() -> void:
	for entry in HUB_ENTRIES:
		var id: String = entry[0]
		var b: Button = _hub_buttons.get(id)
		if b == null:
			continue
		b.visible = _sibling(String(entry[2])) != null and hub_entry_available(id)

static func hub_entry_available(id: String) -> bool:
	match id:
		"sandbox":
			return GameMode.sandbox_tools()
		"contracts":
			return GameMode.contracts_enabled()
	return true

## Cierra la tarjeta y abre el panel de esa entrada (si ya estaba abierto, lo
## deja asi).
func open_hub_entry(id: String) -> void:
	var sibling := ""
	for entry in HUB_ENTRIES:
		if String(entry[0]) == id:
			sibling = String(entry[2])
	var panel := _sibling(sibling)
	_close()
	if panel == null:
		return
	if panel.has_method("is_open") and panel.is_open():
		return
	if panel.has_method("open_log"):
		panel.open_log()
	elif panel.has_method("open"):
		panel.open()
	elif panel.has_method("toggle"):
		panel.toggle()
	elif panel.has_method("_toggle_panel"):
		panel._toggle_panel()

func hub_button(id: String) -> Button:
	return _hub_buttons.get(id) as Button

func _sibling(node_name: String) -> Node:
	if node_name == "" or get_parent() == null:
		return null
	return get_parent().get_node_or_null(node_name)

func _close() -> void:
	if not _is_open:
		return
	_is_open = false
	_card.visible = false
	_backdrop.visible = false
	UIManager.close_panel(self)
	layer = LAYER

func _toggle_panel() -> void:
	if _is_open:
		_close()
	else:
		open()

func badge() -> Button:
	return _badge

func card() -> PanelContainer:
	return _card
