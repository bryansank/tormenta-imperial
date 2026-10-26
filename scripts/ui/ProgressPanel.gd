extends CanvasLayer
## Shows era progression, milestones checklist, and overall completion.

var _panel: PanelContainer
var _backdrop: ColorRect
var _progress_btn: Button
var _is_open := false
var _milestone_labels: Dictionary = {}
var _era_label: Label
var _bar: ProgressBar
## Los hitos van en un scroll: en un telefono de 360 de alto la lista entera
## sacaba la ventana por arriba y por abajo (fix/desbordes-derecha).
var _list_scroll: ScrollContainer
var _list: VBoxContainer

func _ready() -> void:
	layer = 11
	_setup_ui()
	UIManager.register_panel(self, "ProgressPanel.modal")
	EventBus.milestone_completed.connect(_on_milestone_completed)
	EventBus.era_advanced.connect(_on_era_advanced)

func _setup_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_progress_btn = Button.new()
	_progress_btn.text = Tr.t("BTN_PROGRESS")
	_progress_btn.custom_minimum_size = Vector2(164, UILayoutConfig.SIDEBAR_BTN_HEIGHT)
	_progress_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_progress_btn.offset_left = -176
	_progress_btn.offset_top = UILayoutManager.get_sidebar_button_offset("ProgressPanel.button")
	UITheme.style_card_button(_progress_btn, UITheme.BTN.lightened(0.05), UITheme.WARNING)
	_progress_btn.pressed.connect(_toggle_panel)
	_progress_btn.visible = false  # Start collapsed with sidebar
	root.add_child(_progress_btn)
	EventBus.sidebar_toggled.connect(func(vis: bool): _progress_btn.visible = vis)

	_backdrop = UITheme.make_backdrop()
	_backdrop.visible = false
	_backdrop.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _toggle_panel())
	root.add_child(_backdrop)

	_panel = PanelContainer.new()
	UILayoutManager.apply_layout("ProgressPanel.modal", _panel)
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel", UITheme.make_war_table_style())
	_panel.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed: UIManager.focus_window(self))
	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.SEPARATION)
	_panel.add_child(vbox)

	vbox.add_child(UITheme.make_panel_header(Tr.t("LBL_PROGRESS_TITLE"), _toggle_panel))

	# Era display
	_era_label = UITheme.make_label(
		"%s: %s" % [Tr.t("LBL_CURRENT_ERA"), Tr.t(ProgressionManager.get_era_name())],
		"section", UITheme.INFO
	)
	_era_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_era_label)

	# Progress bar
	_bar = UITheme.make_progress_bar(UITheme.ACCENT)
	_bar.value = ProgressionManager.get_completion_percent()
	_bar.show_percentage = true
	vbox.add_child(_bar)

	vbox.add_child(UITheme.make_separator())

	# Milestones
	_list_scroll = ScrollContainer.new()
	_list_scroll.name = "MilestoneScroll"
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", UITheme.SEPARATION)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_scroll.add_child(_list)
	for milestone in ProgressionManager.get_milestone_list():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var is_done := ProgressionManager.is_milestone_completed(milestone["id"])

		var check := UITheme.make_label(
			"[X]" if is_done else "[ ]", "body",
			UITheme.POSITIVE if is_done else UITheme.TEXT_DIM
		)
		check.custom_minimum_size.x = 30
		row.add_child(check)

		var name_label := UITheme.make_label(
			Tr.t(milestone["name"]), "body",
			UITheme.TEXT if is_done else UITheme.TEXT_DIM
		)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(name_label)

		_milestone_labels[milestone["id"]] = {"check": check, "name": name_label}
		_list.add_child(row)

func _on_milestone_completed(milestone_id: String) -> void:
	if _milestone_labels.has(milestone_id):
		var labels: Dictionary = _milestone_labels[milestone_id]
		labels["check"].text = "[X]"
		UITheme.set_label_color(labels["check"], UITheme.POSITIVE)
		UITheme.set_label_color(labels["name"], UITheme.TEXT)
	_bar.value = ProgressionManager.get_completion_percent()
	_show_milestone_toast(milestone_id)

func _on_era_advanced(new_era: int) -> void:
	_era_label.text = "%s: %s" % [Tr.t("LBL_CURRENT_ERA"), Tr.t(ProgressionManager.get_era_name())]
	_show_era_toast(new_era)

func _show_milestone_toast(milestone_id: String) -> void:
	var milestone_name := milestone_id
	for m in ProgressionManager.get_milestone_list():
		if m["id"] == milestone_id:
			milestone_name = Tr.t(m["name"])
			break
	_show_toast(Tr.t("FMT_MILESTONE_COMPLETE") % milestone_name, UITheme.ACCENT)

func _show_era_toast(era: int) -> void:
	var era_name := Tr.t(GameConfig.era_names.get(era, ""))
	_show_toast(Tr.t("FMT_ERA_UNLOCKED") % era_name, UITheme.INFO)

## Hitos y eras van a la columna de avisos (NotificationPanel, categoria
## "achievement", 2026-10-18): antes eran una placa propia a un tercio de
## pantalla que se ponia encima de todo. Alli esperan si hay una ventana o el
## tablero abiertos, se agrupan y salen de dos en dos como mucho.
func _show_toast(text: String, color: Color) -> void:
	EventBus.notification_posted.emit(text, "achievement", color)

func _toggle_panel() -> void:
	_is_open = not _is_open
	_panel.visible = _is_open
	_backdrop.visible = _is_open
	if _is_open:
		_fit_list()
		UIManager.open_panel(self)
	else:
		UIManager.close_panel(self)

## El alto del scroll de hitos: la lista entera si cabe; si no, lo que deja el
## lienzo bajo la cabecera, la era y la barra (el resto se arrastra).
func _fit_list() -> void:
	if _list_scroll == null or not is_inside_tree():
		return
	var vp_h: float = get_viewport().get_visible_rect().size.y
	var need: float = _list.get_combined_minimum_size().y
	_list_scroll.custom_minimum_size.y = clampf(need, 80.0, maxf(80.0, vp_h - 190.0))
