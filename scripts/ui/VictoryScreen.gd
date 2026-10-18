extends CanvasLayer
## Full-screen victory overlay shown when the Final Audit is won (or, in
## Constructor, when HQ reaches max level).
##
## Volverse el Imperio (feat/volverse-imperio): donde el modo tiene la fase
## (GameMode.empire_enabled) el titulo es "Ahora el Imperio eres tu" y un boton
## abre el archipielago. Esta pantalla tambien monta ArchipelagoPanel como
## hermano (lo crea al arrancar, en las dos vistas): asi ☰ MENU lo encuentra
## por nombre como al resto de paneles sin tocar Main.tscn ni Main2D.tscn.

const ColonyByline := preload("res://scripts/ui/ColonyByline.gd")
const ArchipelagoPanelScript := preload("res://scripts/ui/ArchipelagoPanel.gd")

var _backdrop: ColorRect
var _panel_node: PanelContainer

func _ready() -> void:
	layer = 20
	EventBus.victory_achieved.connect(_on_victory_achieved)
	_mount_archipelago.call_deferred()

## Pone el ArchipelagoPanel de hermano (una vez). Oculto y sin _process hasta
## que se abre: no cuesta nada mientras no se usa.
func _mount_archipelago() -> void:
	var parent: Node = get_parent()
	if parent == null or parent.get_node_or_null(ArchipelagoPanelScript.NODE_NAME) != null:
		return
	var archipelago: CanvasLayer = ArchipelagoPanelScript.new()
	archipelago.name = ArchipelagoPanelScript.NODE_NAME
	parent.add_child(archipelago)

## Cierra la pantalla (CONTINUAR o VER EL ARCHIPIELAGO).
func dismiss() -> void:
	if _backdrop != null and is_instance_valid(_backdrop):
		_backdrop.queue_free()
	if _panel_node != null and is_instance_valid(_panel_node):
		_panel_node.queue_free()

func _on_victory_achieved(stats: Dictionary) -> void:
	_show_victory(stats)

## Esta la pantalla en pantalla. Para pruebas y para quien tenga que esperarla.
func is_showing() -> bool:
	return _backdrop != null and is_instance_valid(_backdrop) and not _backdrop.is_queued_for_deletion()

func _show_victory(stats: Dictionary) -> void:
	# Backdrop
	_backdrop = UITheme.make_backdrop()
	_backdrop.color.a = 0.0
	add_child(_backdrop)

	var panel := PanelContainer.new()
	_panel_node = panel
	panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	UILayoutManager.apply_layout("VictoryScreen", panel)
	panel.modulate.a = 0.0

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	# Title. Constructor gana sin asedio: su victoria no habla de la Tormenta.
	var builder: bool = GameMode.capstone_wins()
	# Volverse el Imperio: ganar no cierra la partida, abre el archipielago.
	var empire: bool = not builder and GameMode.empire_enabled()
	# El pais que gana: su bandera y su nombre encima del titulo.
	vbox.add_child(ColonyByline.new("section", UITheme.TEXT_BRIGHT, Vector2(72, 48)))
	var title_key: String = "LBL_VICTORY_TITLE_BUILDER" if builder else ("LBL_VICTORY_TITLE_EMPIRE" if empire else "LBL_VICTORY_TITLE")
	var title := UITheme.make_label(Tr.t(title_key), "title", UITheme.ACCENT)
	title.name = "VictoryTitle"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title)

	# Subtitle
	var subtitle_key: String = "LBL_VICTORY_SUBTITLE_BUILDER" if builder else ("LBL_VICTORY_SUBTITLE_EMPIRE" if empire else "LBL_VICTORY_SUBTITLE_AUDIT")
	var subtitle := UITheme.make_label(Tr.t(subtitle_key), "body", UITheme.TEXT_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(subtitle)

	vbox.add_child(UITheme.make_separator())

	# Stats
	var time_played: float = stats.get("time_played", 0.0)
	_add_stat(vbox, Tr.t("LBL_STAT_MODE"), GameMode.display_name(GameMode.from_key(String(stats.get("mode", GameMode.current_key())))))
	_add_stat(vbox, Tr.t("LBL_STAT_TIME"), _format_time(time_played))
	_add_stat(vbox, Tr.t("LBL_STAT_BUILDINGS"), str(stats.get("buildings_built", 0)))
	_add_stat(vbox, Tr.t("LBL_STAT_TRADES"), str(stats.get("trades_completed", 0)))
	_add_stat(vbox, Tr.t("LBL_STAT_MILESTONES"), str(stats.get("milestones", 0)))
	# Lo que de verdad cuenta la partida: cuantas veces volvio la Tormenta, cuantas
	# se les echo, y a la cuantas se gano el asedio. Constructor gana sin Tormenta,
	# sin Diezmo y sin asedio: ahi esas tres filas serian ceros que no dicen nada.
	if not builder:
		_add_stat(vbox, Tr.t("LBL_STAT_STORMS"), "%d" % int(stats.get("storms_survived", 0)))
		_add_stat(vbox, Tr.t("LBL_STAT_TITHES_REPELLED"), "%d" % int(stats.get("tithes_repelled", 0)))
		_add_stat(vbox, Tr.t("LBL_STAT_SUMMONS"), "%d" % int(stats.get("audit_summons", 1)))

		var coda := UITheme.make_label(Tr.t("LBL_VICTORY_CODA_EMPIRE" if empire else "LBL_VICTORY_CODA"), "small", UITheme.ACCENT)
		coda.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		coda.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(coda)

	vbox.add_child(UITheme.make_separator())

	# Buttons
	# Volverse el Imperio: el boton grande lleva al archipielago.
	if empire:
		var arch_btn := Button.new()
		arch_btn.name = "ArchipelagoButton"
		arch_btn.text = Tr.t("BTN_VIEW_ARCHIPELAGO")
		arch_btn.custom_minimum_size = Vector2(0, 52)
		UITheme.style_button(arch_btn, UITheme.ACCENT.darkened(0.25), UITheme.FONT_BUTTON)
		arch_btn.pressed.connect(open_archipelago)
		vbox.add_child(arch_btn)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)

	var continue_btn := Button.new()
	continue_btn.text = Tr.t("BTN_CONTINUE")
	continue_btn.custom_minimum_size = Vector2(150, 44)
	UITheme.style_button(continue_btn, UITheme.POSITIVE)
	continue_btn.pressed.connect(dismiss)
	btn_row.add_child(continue_btn)

	var new_btn := Button.new()
	new_btn.text = Tr.t("BTN_NEW_GAME")
	new_btn.custom_minimum_size = Vector2(150, 44)
	UITheme.style_button(new_btn, UITheme.DANGER)
	# Borrar la partida es irreversible: siempre con confirmacion, como en Ajustes.
	new_btn.pressed.connect(func(): GameManager.request_new_game())
	btn_row.add_child(new_btn)

	vbox.add_child(btn_row)
	add_child(panel)

	# Fade in
	var tween := create_tween()
	tween.tween_property(_backdrop, "color:a", 0.45, 0.5)
	tween.parallel().tween_property(panel, "modulate:a", 1.0, 1.0).set_ease(Tween.EASE_OUT)

## VER EL ARCHIPIELAGO: cierra la victoria y abre el mapa de las islas.
func open_archipelago() -> void:
	dismiss()
	_mount_archipelago()
	var archipelago: Node = get_parent().get_node_or_null(ArchipelagoPanelScript.NODE_NAME) if get_parent() != null else null
	if archipelago != null and archipelago.has_method("open"):
		archipelago.open()

func _add_stat(parent: VBoxContainer, label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := UITheme.make_label(label_text, "body", UITheme.TEXT_DIM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := UITheme.make_label(value_text, "body", UITheme.TEXT_BRIGHT)
	row.add_child(value)
	parent.add_child(row)

func _format_time(seconds: float) -> String:
	var s := int(seconds)
	if s < 60:
		return "%ds" % s
	if s < 3600:
		return "%dm %ds" % [s / 60, s % 60]
	return "%dh %dm" % [s / 3600, (s % 3600) / 60]
