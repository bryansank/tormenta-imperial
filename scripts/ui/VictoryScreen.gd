extends CanvasLayer
## La victoria: una ventana crema con la cinta verde, la bandera y el nombre del
## pais, una frase y las cifras de la partida como icono + numero (el nombre
## debajo, en pequeno). Sin animacion: sale de golpe (docs/28 §0.6).
##
##   [bandera] Monte Biela
##   ( VICTORIA IMPERIAL )
##   La Regencia bajo a cobrar y se fue sin nada...
##   [reloj] 3 h 05   [casa] 30   [mercado] 12   [estrella] 9
##   [tormenta] 11    [check] 9   [misiones] 2
##   [ SEGUIR JUGANDO ]  [ Nueva partida ]

const ColonyByline := preload("res://scripts/ui/ColonyByline.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")

## Tope de la ventana en PC/tablet.
const WINDOW_MAX := Vector2(720, 560)

var _backdrop: ColorRect
var _window: Control

func _ready() -> void:
	layer = 20
	# Mientras se ve, los avisos esperan (NotificationPanel.is_busy).
	add_to_group("modal_screen")
	EventBus.victory_achieved.connect(_on_victory_achieved)

func _on_victory_achieved(stats: Dictionary) -> void:
	_show_victory(stats)

## Esta la pantalla en pantalla. Para pruebas y para quien tenga que esperarla.
func is_showing() -> bool:
	return _backdrop != null and is_instance_valid(_backdrop) and not _backdrop.is_queued_for_deletion()

func _show_victory(stats: Dictionary) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var small := CT.is_phone()
	_backdrop = CT.veil()
	add_child(_backdrop)

	# Constructor gana sin asedio: su victoria no habla de la Tormenta.
	var builder: bool = GameMode.capstone_wins()
	var title := Tr.t("LBL_VICTORY_TITLE_BUILDER" if builder else "LBL_VICTORY_TITLE")
	var w := CT.menu_window(title, CT.sem("POSITIVE"), small, false)
	_window = w["root"]
	_window.name = "VictoryWindow"
	add_child(_window)
	var body: VBoxContainer = w["body"]

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8 if small else 12)
	scroll.add_child(vbox)

	# El pais que gana: su bandera y su nombre.
	var byline := ColonyByline.new("section", CT.text("window"), Vector2(60, 40) if small else Vector2(72, 48))
	byline.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(byline)

	# Una frase.
	var subtitle := CT.para(Tr.t("LBL_VICTORY_SUBTITLE_BUILDER" if builder else "LBL_VICTORY_SUBTITLE_AUDIT"), "window")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	# Las cifras: icono + numero, el nombre debajo.
	var grid := HFlowContainer.new()
	grid.name = "Stats"
	grid.alignment = FlowContainer.ALIGNMENT_CENTER
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)
	var time_played: float = stats.get("time_played", 0.0)
	_add_stat(grid, "game", Tr.t("LBL_STAT_MODE"), GameMode.display_name(GameMode.from_key(String(stats.get("mode", GameMode.current_key())))))
	_add_stat(grid, "clock", Tr.t("LBL_STAT_TIME"), _format_time(time_played))
	_add_stat(grid, "build", Tr.t("LBL_STAT_BUILDINGS"), str(stats.get("buildings_built", 0)))
	_add_stat(grid, "market", Tr.t("LBL_STAT_TRADES"), str(stats.get("trades_completed", 0)))
	_add_stat(grid, "star", Tr.t("LBL_STAT_MILESTONES"), str(stats.get("milestones", 0)))
	# Lo que de verdad cuenta la partida: cuantas veces volvio la Tormenta, cuantas
	# se les echo, y a la cuantas se gano el asedio. Constructor gana sin Tormenta,
	# sin Diezmo y sin asedio: ahi esas tres serian ceros que no dicen nada.
	if not builder:
		_add_stat(grid, "storm", Tr.t("LBL_STAT_STORMS"), "%d" % int(stats.get("storms_survived", 0)))
		_add_stat(grid, "check", Tr.t("LBL_STAT_TITHES_REPELLED"), "%d" % int(stats.get("tithes_repelled", 0)))
		_add_stat(grid, "missions", Tr.t("LBL_STAT_SUMMONS"), "%d" % int(stats.get("audit_summons", 1)))
		var coda := CT.para(Tr.t("LBL_VICTORY_CODA"), "window", true, "small")
		coda.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(coda)

	# Botones: seguir es lo principal (verde); una partida nueva, crema.
	# Uno debajo del otro si no caben (telefono en vertical: salian 33 px por la
	# derecha).
	var btn_row := HFlowContainer.new()
	btn_row.alignment = FlowContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("h_separation", 12)
	btn_row.add_theme_constant_override("v_separation", 8)
	var bh := CT.menu_h("btn")
	var continue_btn := CT.text_button(Tr.t("BTN_CONTINUE"), "next", "primary", bh)
	continue_btn.name = "ContinueButton"
	continue_btn.pressed.connect(_close)
	btn_row.add_child(continue_btn)
	var new_btn := CT.text_button(Tr.t("BTN_NEW_GAME"), "plus", "secondary", bh)
	new_btn.name = "NewGameButton"
	# Ya no borra nada: abre el selector de modo y crea otra partida.
	new_btn.pressed.connect(func(): GameManager.request_new_game())
	btn_row.add_child(new_btn)
	body.add_child(btn_row)

	var max_size := Vector2(WINDOW_MAX.x, minf(WINDOW_MAX.y, vp.y - 32.0))
	CT.place_window(_window, vp, max_size, small)
	_set_menu_button_hidden(true)

func _close() -> void:
	_set_menu_button_hidden(false)
	if _backdrop != null and is_instance_valid(_backdrop):
		_backdrop.queue_free()
	if _window != null and is_instance_valid(_window):
		_window.queue_free()

## El ☰ (capa 30) caia sobre la esquina de la ventana, que no tiene X que
## apartar: mientras se ve la Victoria, el ☰ se esconde. Lo que se escondio aqui
## es lo unico que se vuelve a mostrar.
func _set_menu_button_hidden(hide_it: bool) -> void:
	if not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group("hud_menu_button"):
		var c := n as Control
		if c == null or not is_instance_valid(c):
			continue
		if hide_it and c.visible:
			c.visible = false
			c.set_meta("hidden_by_victory", true)
		elif not hide_it and c.has_meta("hidden_by_victory"):
			c.remove_meta("hidden_by_victory")
			c.visible = true

## Una cifra: [icono] valor, y debajo el nombre (sin los dos puntos del texto
## de siempre). El nombre entero, al mantener pulsado.
func _add_stat(parent: Container, glyph: String, label_text: String, value_text: String) -> void:
	var chip := PanelContainer.new()
	var st := CT.card_style("window")
	st.set_content_margin_all(8)
	st.content_margin_left = 12
	st.content_margin_right = 14
	chip.add_theme_stylebox_override("panel", st)
	chip.tooltip_text = label_text
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	var ic := CT.make_glyph(glyph, 30)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	col.add_child(CT.label(value_text, "number", CT.text("window")))
	col.add_child(CT.label(label_text.trim_suffix(":"), "small", CT.text("window", true)))
	parent.add_child(chip)

func _format_time(seconds: float) -> String:
	var s := int(seconds)
	if s < 60:
		return "%ds" % s
	if s < 3600:
		return "%dm %ds" % [s / 60, s % 60]
	return "%dh %dm" % [s / 3600, (s % 3600) / 60]
