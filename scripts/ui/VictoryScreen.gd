extends CanvasLayer
## Full-screen victory overlay shown when HQ reaches max level.

var _backdrop: ColorRect

func _ready() -> void:
	layer = 20
	EventBus.victory_achieved.connect(_on_victory_achieved)

## La victoria y el parte de progreso offline comparten la capa 20. Si el parte
## sigue en pantalla, la victoria espera a que se cierre: dos modales en la misma
## capa se tapan el uno al otro y el jugador no sabe cual esta pulsando.
func _on_victory_achieved(stats: Dictionary) -> void:
	if GameManager.is_offline_report_open():
		GameManager.offline_report_closed.connect(func(): _show_victory(stats), CONNECT_ONE_SHOT)
		return
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
	panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	UILayoutManager.apply_layout("VictoryScreen", panel)
	panel.modulate.a = 0.0

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	# Title. Constructor gana sin asedio: su victoria no habla de la Tormenta.
	var builder: bool = GameMode.capstone_wins()
	var title := UITheme.make_label(Tr.t("LBL_VICTORY_TITLE_BUILDER" if builder else "LBL_VICTORY_TITLE"), "title", UITheme.ACCENT)
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Subtitle
	var subtitle := UITheme.make_label(Tr.t("LBL_VICTORY_SUBTITLE_BUILDER" if builder else "LBL_VICTORY_SUBTITLE_AUDIT"), "body", UITheme.TEXT_DIM)
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
	# se les echo, y a la cuantas se gano el asedio.
	_add_stat(vbox, Tr.t("LBL_STAT_STORMS"), "%d" % int(stats.get("storms_survived", 0)))
	_add_stat(vbox, Tr.t("LBL_STAT_TITHES_REPELLED"), "%d" % int(stats.get("tithes_repelled", 0)))
	_add_stat(vbox, Tr.t("LBL_STAT_SUMMONS"), "%d" % int(stats.get("audit_summons", 1)))

	var coda := UITheme.make_label(Tr.t("LBL_VICTORY_CODA"), "small", UITheme.ACCENT)
	coda.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coda.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(coda)

	vbox.add_child(UITheme.make_separator())

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)

	var continue_btn := Button.new()
	continue_btn.text = Tr.t("BTN_CONTINUE")
	continue_btn.custom_minimum_size = Vector2(150, 44)
	UITheme.style_button(continue_btn, UITheme.POSITIVE)
	continue_btn.pressed.connect(func():
		_backdrop.queue_free()
		panel.queue_free()
	)
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
