extends VBoxContainer
## La parte propia de la ficha de los edificios militares de la 1.2
## (feat/edificios-militares), dentro de BuildingInfoPanel, como HarvestSection:
##
## - Enfermeria: lo que hace, en tres lineas con sus cifras.
## - Herreria militar: las DOCTRINAS. Un boton por doctrina con lo que cambia;
##   la que esta en uso marcada; adoptar otra cuesta oro y tiempo (barra).
## - Campo de tiro: el -20 % al entrenar y el SIMULACRO, un boton por leccion
##   con su premio de la primera vez o "hecha".
##
## Se oculta sola en cualquier otro edificio y mientras esta en obras.
## BuildingInfoPanel la crea una vez, llama a show_for() al abrir y a refresh()
## cada fotograma; refresh() solo trabaja con una doctrina adoptandose, y como
## mucho cuatro veces por segundo.

const TextKit := preload("res://scripts/ui/TextKit.gd")
const Doctrines := preload("res://scripts/combat/Doctrines.gd")
const Military := preload("res://scripts/buildings/MilitaryBuildings.gd")

const REFRESH_EVERY := 0.25

var _node: Node = null
var _data: BuildingData = null
var _header: Label
var _info: Label
var _body: VBoxContainer
var _status: Label
var _bar: ProgressBar
var _refresh_left := 0.0

func _init() -> void:
	name = "MilitarySection"
	add_theme_constant_override("separation", 4)
	_header = UITheme.section_header("", UITheme.ACCENT)
	add_child(_header)
	_info = UITheme.make_label("", "small", UITheme.TEXT_DIM)
	_info.name = "MilitaryInfo"
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_info)
	_status = UITheme.make_label("", "small", UITheme.WARNING)
	_status.name = "MilitaryStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_bar = UITheme.make_progress_bar(UITheme.ACCENT, 12)
	_bar.name = "DoctrineBar"
	_bar.max_value = 1.0
	_bar.visible = false
	add_child(_bar)
	_body = VBoxContainer.new()
	_body.name = "MilitaryBody"
	_body.add_theme_constant_override("separation", 4)
	add_child(_body)
	visible = false
	EventBus.doctrine_changed.connect(func(_id): _rebuild())
	EventBus.doctrine_switch_started.connect(func(_id, _s): _rebuild())
	EventBus.practice_lesson_completed.connect(func(_id, _f, _r): _rebuild())
	EventBus.encounter_closed.connect(_rebuild)

static func handles(building_id: String) -> bool:
	return building_id in GameConfig.MILITARY_SUPPORT_BUILDINGS

func show_for(node: Node, data: BuildingData) -> void:
	_node = node
	_data = data
	visible = data != null and handles(data.id) and node != null and is_instance_valid(node) \
		and not ProductionManager.is_constructing(node)
	_rebuild()

func refresh() -> void:
	if not visible or _data == null or _data.id != Military.SMITHY:
		return
	if ArmyManager.get_doctrine_pending() == "":
		return
	_refresh_left -= get_process_delta_time()
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH_EVERY
	_paint_switching()

# ── Contenido ──

func _rebuild() -> void:
	if not visible or _data == null:
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.free()
	_bar.visible = false
	_status.visible = false
	match _data.id:
		Military.INFIRMARY:
			_build_infirmary()
		Military.SMITHY:
			_build_smithy()
		Military.FIRING_RANGE:
			_build_firing_range()

func _build_infirmary() -> void:
	_header.text = Tr.t("MIL_INFIRMARY_HEADER")
	_info.text = Tr.t("MIL_INFIRMARY_LINES") % [GameConfig.infirmary_return_every,
		roundi(GameConfig.combat_morale_per_casualty), roundi(GameConfig.infirmary_morale_per_casualty),
		roundi((GameConfig.infirmary_heal_mult - 1.0) * 100.0)]
	_status.visible = not Military.is_working(_node)
	_status.text = Tr.t("MIL_NOT_WORKING")

func _build_smithy() -> void:
	_header.text = Tr.t("DOC_HEADER")
	var cost: Dictionary = GameConfig.smithy_doctrine_cost
	_info.text = Tr.t("DOC_INFO") % [TextKit.cost_text(cost),
		TextKit.short_time(GameConfig.get_duration(GameConfig.smithy_doctrine_seconds))]
	var active := ArmyManager.get_doctrine()
	var pending := ArmyManager.get_doctrine_pending()
	for doctrine_id in Doctrines.ids():
		var def := Doctrines.get_def(doctrine_id)
		var btn := Button.new()
		btn.name = "Doctrine_" + doctrine_id
		btn.custom_minimum_size.y = 44
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var who: Array = []
		for unit_id in Doctrines.affected_units(doctrine_id):
			who.append(Tr.t(String(GameConfig.get_unit_def(unit_id).get("name", unit_id))))
		var effects: Array = []
		for row in Doctrines.effect_rows(doctrine_id):
			effects.append("%s %s" % [Tr.t(String(row[0])), String(row[1])])
		var mark := ""
		if doctrine_id == active:
			mark = Tr.t("DOC_IN_USE") + " · "
		elif doctrine_id == pending:
			mark = Tr.t("DOC_LEARNING") + " · "
		btn.text = "%s%s\n%s" % [mark, Tr.t(String(def.get("name", doctrine_id))), ", ".join(effects)]
		btn.tooltip_text = "%s\n%s" % [Tr.t(String(def.get("desc", ""))), Tr.t("DOC_AFFECTS") % ", ".join(who)]
		var check: Dictionary = ArmyManager.can_choose_doctrine(doctrine_id)
		btn.disabled = not bool(check["ok"])
		if not bool(check["ok"]) and String(check["reason"]) != "DOC_WHY_ACTIVE":
			btn.tooltip_text += "\n" + Tr.t(String(check["reason"]))
		var color: Color = UITheme.POSITIVE.darkened(0.25) if doctrine_id == active else UITheme.BTN
		UITheme.style_button(btn, color, UITheme.FONT_BODY)
		var id: String = String(doctrine_id)
		btn.pressed.connect(func(): _on_doctrine(id))
		_body.add_child(btn)
	if active == "" and pending == "":
		_status.text = Tr.t("DOC_NONE_YET")
		_status.visible = true
	elif active != "" and ArmyManager.effective_doctrine() == "":
		_status.text = Tr.t("DOC_NO_SMITHY_OFF")
		_status.visible = true
	if pending != "":
		_paint_switching()

func _paint_switching() -> void:
	var pending := ArmyManager.get_doctrine_pending()
	if pending == "":
		_bar.visible = false
		return
	var def := Doctrines.get_def(pending)
	_status.text = Tr.t("DOC_SWITCHING") % [Tr.t(String(def.get("name", pending))),
		TextKit.short_time(ArmyManager.get_doctrine_left())]
	_status.visible = true
	_bar.value = ArmyManager.get_doctrine_progress()
	_bar.visible = true

func _on_doctrine(doctrine_id: String) -> void:
	if ArmyManager.choose_doctrine(doctrine_id):
		_rebuild()

func _build_firing_range() -> void:
	_header.text = Tr.t("PRACTICE_HEADER")
	_info.text = Tr.t("PRACTICE_INFO") % roundi((1.0 - GameConfig.firing_range_train_mult) * 100.0)
	var block: String = CombatManager.practice_block_reason()
	if block != "":
		_status.text = Tr.t(block)
		_status.visible = true
	var n := 0
	for lesson in GameConfig.firing_range_lessons:
		n += 1
		var lesson_id := String(lesson.get("id", ""))
		var btn := Button.new()
		btn.name = "Practice_" + lesson_id
		btn.custom_minimum_size.y = 44
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var tail := ""
		if ArmyManager.is_practice_done(lesson_id):
			tail = Tr.t("PRACTICE_DONE")
		else:
			tail = Tr.t("PRACTICE_PRIZE") % TextKit.cost_text(lesson.get("reward", {}))
		btn.text = "%d · %s   %s" % [n, Tr.t(String(lesson.get("name", lesson_id))), tail]
		btn.tooltip_text = Tr.t(String(lesson.get("desc", "")))
		btn.disabled = block != ""
		UITheme.style_button(btn, UITheme.INFO.darkened(0.25), UITheme.FONT_BODY)
		btn.pressed.connect(func(): _on_practice(lesson_id))
		_body.add_child(btn)

func _on_practice(lesson_id: String) -> void:
	if CombatManager.start_practice(lesson_id):
		# El tablero se abre encima (BattleScreen); la ficha se cierra.
		var panel := get_parent()
		while panel != null and not panel.has_method("_hide_panel"):
			panel = panel.get_parent()
		if panel != null:
			panel._hide_panel()
