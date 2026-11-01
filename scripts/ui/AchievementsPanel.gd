extends CanvasLayer
## LOGROS Y ESTADISTICAS (feat/logros-estadisticas, docs/29). Se abre desde la
## tarjeta de la colonia (tocar el rango → fila ColonyHub → LOGROS). No esta en
## Main.tscn ni en Main2D.tscn: RankPanel la crea de hermana al arrancar
## (_mount_achievements), como VictoryScreen con el archipielago.
##
## Dos pestanas:
##   Logros        "12 de 31 logros" y una fila por logro, por grupos: icono,
##                 nombre, que hay que hacer y, si falta, cuanto lleva esta
##                 partida (barra y "12/25"). Los secretos son "???" hasta
##                 ganarlos.
##   Estadisticas  los contadores de esta partida (AchievementManager) y los
##                 del dispositivo (partidas terminadas, campanas ganadas).
##
## Solo lee AchievementManager y GameConfig; no guarda nada. Sin _process: se
## construye al abrir y se rehace al cambiar de pestana o al ganar un logro con
## la ventana abierta. Telefono primero (640x360): una columna de logros, dos
## de cifras, pestanas de 48 dp.

const CT := preload("res://scripts/ui/CartoonTheme.gd")

const NODE_NAME := "AchievementsPanel"
## Tope de la ventana en PC (en telefono va a pantalla completa).
const MAX_SIZE := Vector2(980, 600)
const ICON_PX := 34
const ICON_PX_PHONE := 28

enum Tab { ACHIEVEMENTS, STATS }

var _built := false
var _win: Dictionary = {}
var _holder: Control
var _is_open := false
var _tab: int = Tab.ACHIEVEMENTS
var _tabs: HBoxContainer
var _count: Label
var _scroll: ScrollContainer
var _content: VBoxContainer
var _footer: Label
var _refresh_queued := false

func _ready() -> void:
	layer = 11
	# Mientras esta abierta, los avisos esperan (NotificationPanel.is_busy).
	add_to_group("modal_screen")
	UIManager.register_panel(self, "AchievementsPanel.modal")
	EventBus.achievement_unlocked.connect(func(_id): _request_refresh())
	EventBus.game_load_completed.connect(_request_refresh)
	get_viewport().size_changed.connect(_on_viewport_resized)

func _build() -> void:
	_built = true
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_win = CT.modal_window(root, Tr.t("LBL_ACH_TITLE"), CT.sem("ACCENT"))
	_holder = _win["holder"]
	_holder.visible = false
	(_win["veil"] as Control).gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close())
	var panel: PanelContainer = _win["panel"]
	panel.name = "Modal"
	panel.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed: UIManager.focus_window(self))
	(_win["close"] as Button).pressed.connect(close)
	(_win["close"] as Button).tooltip_text = Tr.t("BTN_CLOSE")
	(_win["ribbon"] as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	(_win["ribbon"] as Control).tooltip_text = Tr.t("LBL_ACH_HINT")
	var body: VBoxContainer = _win["body"]

	# Pestanas + "12 de 31 logros".
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	body.add_child(top)
	_tabs = HBoxContainer.new()
	_tabs.name = "Tabs"
	_tabs.add_theme_constant_override("separation", 6)
	top.add_child(_tabs)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gap)
	_count = CT.label("", "number", CT.text("window"))
	_count.name = "Count"
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_count)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	_scroll.add_child(_content)

	_footer = CT.label("", "small", CT.text("window", true))
	_footer.name = "Footer"
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_footer)

func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)

func _fit() -> void:
	if _built:
		CT.fit_window(_win, _vp(), MAX_SIZE)

func _on_viewport_resized() -> void:
	if _is_open:
		_fit()
		refresh()

# ── Abrir y cerrar ───────────────────────────────────────────────────

func is_open() -> bool:
	return _is_open

## Para NotificationPanel.is_busy (grupo "modal_screen").
func is_showing() -> bool:
	return _is_open

func open() -> void:
	if _is_open:
		return
	_set_open(true)

func close() -> void:
	if not _is_open:
		return
	_set_open(false)

func toggle() -> void:
	_set_open(not _is_open)

## Lo llama UIManager (ESC, el boton atras, otra ventana en el mismo sitio).
func _close() -> void:
	close()

func _set_open(value: bool) -> void:
	if value and not _built:
		_build()
	_is_open = value
	if _holder != null:
		_holder.visible = value
	if value:
		_fit()
		refresh()
		_scroll.scroll_vertical = 0
		UIManager.open_panel(self)
	else:
		UIManager.close_panel(self)

## Cambia de pestana (publico para los tests).
func show_tab(tab: int) -> void:
	_tab = tab
	if _is_open:
		refresh()
		_scroll.scroll_vertical = 0

func current_tab() -> int:
	return _tab

# ── Repintar ─────────────────────────────────────────────────────────

func _request_refresh() -> void:
	if not _is_open or _refresh_queued:
		return
	_refresh_queued = true
	_flush_refresh.call_deferred()

func _flush_refresh() -> void:
	_refresh_queued = false
	if _is_open:
		refresh()

## Rehace la pestana a la vista. Publico para los tests.
func refresh() -> void:
	if not _built:
		return
	_build_tabs()
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_count.text = Tr.t("FMT_ACH_COUNT") % [AchievementManager.unlocked_count(), AchievementManager.total_count()]
	if _tab == Tab.STATS:
		_fill_stats()
	else:
		_fill_achievements()
	if not GameMode.achievements_enabled():
		_footer.text = Tr.t("LBL_ACH_SANDBOX")
	else:
		_footer.text = Tr.t("LBL_ACH_HINT")
	# En telefono la frase de ayuda va al mantener la cinta; el aviso de
	# Sandbox se ve siempre (explica por que no sube nada).
	_footer.visible = not CT.is_phone() or not GameMode.achievements_enabled()

func _build_tabs() -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	var h := CT.h("small")
	var a := CT.tab(Tr.t("LBL_ACH_TAB_ACH"), "trophy", _tab == Tab.ACHIEVEMENTS, "window", Color(0, 0, 0, 0), h, 14)
	a.name = "TabAchievements"
	a.pressed.connect(show_tab.bind(Tab.ACHIEVEMENTS))
	_tabs.add_child(a)
	var s := CT.tab(Tr.t("LBL_ACH_TAB_STATS"), "clock", _tab == Tab.STATS, "window", Color(0, 0, 0, 0), h, 14)
	s.name = "TabStats"
	s.pressed.connect(show_tab.bind(Tab.STATS))
	_tabs.add_child(s)

# ── Logros ───────────────────────────────────────────────────────────

func _fill_achievements() -> void:
	var columns := 1 if CT.is_phone() else 2
	for group in GameConfig.achievement_groups:
		var gid := String(group[0])
		var defs: Array = []
		for def in GameConfig.achievement_definitions:
			if String(def.get("group", "")) == gid:
				defs.append(def)
		if defs.is_empty():
			continue
		_content.add_child(CT.section(Tr.t("ACH_GROUP_" + gid.to_upper()), String(group[1])))
		var grid := GridContainer.new()
		grid.name = "Group_" + gid
		grid.columns = columns
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		for def in defs:
			grid.add_child(_make_row(def))
		_content.add_child(grid)

## Una fila: [icono] Nombre / que hay que hacer / barra o "Conseguido".
func _make_row(def: Dictionary) -> PanelContainer:
	var id := String(def["id"])
	var done: bool = AchievementManager.is_unlocked(id)
	var hidden: bool = bool(def.get("secret", false)) and not done
	var phone := CT.is_phone()
	var row := PanelContainer.new()
	row.name = "Ach_" + id
	var style := CT.card_style("window", done, Color(0, 0, 0, 0) if done else CT.c("window", "CARD_ALT"))
	style.set_content_margin_all(6 if phone else 10)
	row.add_theme_stylebox_override("panel", style)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	var glyph := String(def.get("glyph", "star")) if not hidden else "lock"
	var icon := CT.make_glyph(glyph, ICON_PX_PHONE if phone else ICON_PX,
		Color(0, 0, 0, 0) if done else CT.text("window", true))
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(icon)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(col)
	var title := CT.label(Tr.t("LBL_ACH_SECRET_NAME") if hidden else Tr.t(AchievementManager.name_key(id)),
		"title", CT.text("window", not done))
	title.name = "Name"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	var desc := CT.para(Tr.t("LBL_ACH_SECRET_DESC") if hidden else Tr.t(AchievementManager.desc_key(id)),
		"window", true, "small")
	desc.name = "Desc"
	col.add_child(desc)

	if done:
		var badge := CT.badge(Tr.t("LBL_ACH_DONE"), CT.sem("POSITIVE"), "check")
		badge.name = "Done"
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(badge)
	elif not hidden:
		var prog: Vector2i = AchievementManager.progress(id)
		if prog.y > 1:
			var bar_row := HBoxContainer.new()
			bar_row.name = "Progress"
			bar_row.add_theme_constant_override("separation", 6)
			bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var bar := CT.progress(float(prog.x) / float(prog.y), CT.sem("ACCENT"), "window", 10)
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar_row.add_child(bar)
			bar_row.add_child(CT.label("%s/%s" % [CT.thousands(prog.x), CT.thousands(prog.y)],
				"small", CT.text("window", true)))
			col.add_child(bar_row)
	return row

# ── Estadisticas ─────────────────────────────────────────────────────

func _fill_stats() -> void:
	var columns := 2 if CT.is_phone() else 3
	_content.add_child(CT.section(Tr.t("LBL_STATS_RUN"), "game"))
	var run := GridContainer.new()
	run.name = "RunStats"
	run.columns = columns
	run.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run.add_theme_constant_override("h_separation", 8)
	run.add_theme_constant_override("v_separation", 6)
	for entry in GameConfig.achievement_stat_rows:
		var stat := String(entry[0])
		var value := AchievementManager.get_stat(stat)
		var shown := format_played(value) if stat == "played" else CT.thousands(value)
		run.add_child(_stat_cell(stat, String(entry[1]), Tr.t("STAT_" + stat.to_upper()), shown))
	_content.add_child(run)

	_content.add_child(CT.section(Tr.t("LBL_STATS_PROFILE"), "star"))
	var prof := GridContainer.new()
	prof.name = "ProfileStats"
	prof.columns = columns
	prof.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prof.add_theme_constant_override("h_separation", 8)
	prof.add_theme_constant_override("v_separation", 6)
	prof.add_child(_stat_cell("achievements", "trophy", Tr.t("STAT_ACHIEVEMENTS"),
		"%d/%d" % [AchievementManager.unlocked_count(), AchievementManager.total_count()]))
	prof.add_child(_stat_cell("runs_finished", "check", Tr.t("STAT_RUNS_FINISHED"),
		CT.thousands(GameConfig.profile_runs_finished)))
	prof.add_child(_stat_cell("campaigns_won", "sun", Tr.t("STAT_CAMPAIGNS_WON"),
		CT.thousands(GameConfig.profile_campaigns_won)))
	_content.add_child(prof)

## Una cifra: [icono] nombre ... valor, en una ficha.
func _stat_cell(stat: String, glyph: String, caption: String, value: String) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.name = "Stat_" + stat
	var style := CT.card_style("window", false, CT.c("window", "CARD_ALT"))
	style.set_content_margin_all(6)
	style.content_margin_left = 8
	style.content_margin_right = 10
	cell.add_theme_stylebox_override("panel", style)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	cell.tooltip_text = caption
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(line)
	var icon := CT.make_glyph(glyph, 22)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(icon)
	var name_label := CT.label(caption, "small", CT.text("window", true))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(name_label)
	var value_label := CT.label(value, "number", CT.text("window"))
	value_label.name = "Value"
	line.add_child(value_label)
	return cell

## "3 h 05 min" o "12 min".
static func format_played(seconds: int) -> String:
	var minutes := floori(maxi(0, seconds) / 60.0)
	if minutes < 60:
		return "%d min" % minutes
	return "%d h %02d min" % [floori(minutes / 60.0), minutes % 60]
