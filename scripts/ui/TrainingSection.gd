extends VBoxContainer
## ENTRENAR en la ficha de un edificio militar (decision de Bryan, 2026-10-19:
## "los soldados se entrenan en los CUARTELES, no en un menu"). Al tocar un
## Cuartel, un Astillero o un Aerodromo, su ficha trae esta seccion:
##
##   ENTRENAR                                   [tropa] 5/43  [reloj] 1/2
##   (disco) Infanteria  ×4      [oro]40 [madera]20   [+ ENTRENAR]
##   (disco) Artilleria          candado "Llega en la era 2"
##   (disco) ▬▬▬▬▬▬▬░░░░  ✕                    (la cola de ESTE edificio)
##   [Ver ejercito]
##
## Las filas y la cola son las mismas piezas que usa ArmyPanel (las funciones
## estaticas de aqui): una sola logica, la de ArmyManager. La seccion no lleva
## estado del ejercito: lo lee cada vez que se rehace.

const TextKit := preload("res://scripts/ui/TextKit.gd")
const UnitCardScript := preload("res://scripts/ui/UnitCard.gd")
const CT := preload("res://scripts/ui/CartoonTheme.gd")

signal open_army_requested

var _building_id := ""
var _rows: VBoxContainer
var _queue: VBoxContainer
var _troops_label: Label
var _slots_label: Label
var _bars: Array = []
var _cards_open: Dictionary = {}
var _queued := false

func _init() -> void:
	name = "TrainingSection"
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _ready() -> void:
	EventBus.army_changed.connect(_request_rebuild)
	EventBus.resource_changed.connect(func(_t, _a, _d): _request_rebuild())
	EventBus.era_advanced.connect(func(_e): _request_rebuild())

## Monta la seccion para `building_id` (barracks / shipyard / aerodrome).
func setup(building_id: String) -> void:
	_building_id = building_id
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	add_child(head)
	var title := CT.section(Tr.t("UI2F_TRAIN_TITLE"), "army")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_troops_label = _chip(head, "res:workers", Tr.t("ARMY2_TROOPS"))
	_slots_label = _chip(head, "clock", Tr.t("ARMY2_QUEUE"))
	_rows = VBoxContainer.new()
	_rows.name = "TrainRows"
	_rows.add_theme_constant_override("separation", 6)
	add_child(_rows)
	_queue = VBoxContainer.new()
	_queue.name = "TrainQueue"
	_queue.add_theme_constant_override("separation", 4)
	add_child(_queue)
	var army_btn := CT.text_button(Tr.t("UI2F_SEE_ARMY"), "army", "secondary", CT.h("small"))
	army_btn.name = "SeeArmy"
	army_btn.tooltip_text = Tr.t("UI2F_SEE_ARMY_TIP")
	army_btn.pressed.connect(func(): open_army_requested.emit())
	add_child(army_btn)
	rebuild()

func building_id() -> String:
	return _building_id

func _chip(parent: Container, glyph: String, caption: String) -> Label:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 4)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.tooltip_text = caption
	var ic := CT.make_glyph(glyph, 20 if CT.is_phone() else 24)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_child(ic)
	var l := CT.label("", "number", CT.text("window"))
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.add_child(l)
	parent.add_child(chip)
	return l

func _request_rebuild() -> void:
	if _queued or not is_visible_in_tree():
		return
	_queued = true
	(func():
		_queued = false
		if is_instance_valid(self) and is_inside_tree():
			rebuild()).call_deferred()

## Rehace filas, cola y cifras con lo que diga ArmyManager ahora.
func rebuild() -> void:
	if _rows == null:
		return
	_troops_label.text = "%d/%d" % [ArmyManager.get_used_capacity(), ArmyManager.get_capacity()]
	_slots_label.text = "%d/%d" % [ArmyManager.training_in(_building_id), ArmyManager.max_slots(_building_id)]
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	for unit_id in GameConfig.get_unit_ids():
		if GameConfig.get_unit_building(String(unit_id)) == _building_id:
			_rows.add_child(make_unit_row(String(unit_id), _cards_open.has(unit_id), true,
				_toggle_card.bind(String(unit_id)), rebuild))
	_bars = fill_queue(_queue, _building_id, rebuild)

## Las barras de la cola, sin rehacer nada (cada fotograma con la ficha abierta).
func update_progress() -> void:
	update_bars(_bars, _building_id)

func _toggle_card(unit_id: String) -> void:
	if _cards_open.has(unit_id):
		_cards_open.erase(unit_id)
	else:
		_cards_open[unit_id] = true
	rebuild()

# ── Piezas compartidas con ArmyPanel ─────────────────────────────────

## Una fila de unidad: disco, nombre y cuantas hay, coste en iconos (en rojo lo
## que falta), poder y sueldo, el porque si no se puede y, a la derecha, la
## ficha (?) y ENTRENAR (verde; con la palabra si `with_word`).
static func make_unit_row(unit_id: String, card_open: bool, with_word: bool,
		on_card: Callable, on_changed: Callable) -> PanelContainer:
	var def := GameConfig.get_unit_def(unit_id)
	var unlocked := ArmyManager.is_unlocked(unit_id) \
		and ArmyManager.building_count(GameConfig.get_unit_building(unit_id)) > 0
	var ph := CT.is_phone()

	var card := PanelContainer.new()
	card.name = "Unit_" + unit_id
	var style := CT.card_style("window", false, CT.c("window", "CARD_ALT") if not unlocked else Color(0, 0, 0, 0))
	style.set_content_margin_all(6 if ph else 10)
	card.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	var disc := CT.unit_disc(unit_id, CT.sem("POSITIVE") if unlocked else CT.kind_fill("disabled"), 38 if ph else 48)
	disc.mouse_filter = Control.MOUSE_FILTER_PASS
	disc.tooltip_text = "\n".join(UnitCardScript.summary_lines(unit_id))
	row.add_child(disc)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)

	# Nombre y "×3" (cuantas tienes); "fuera: 2" si hay columna fuera.
	var title_row := HFlowContainer.new()
	title_row.add_theme_constant_override("h_separation", 8)
	var name_label := CT.label(Tr.t(def.get("name", unit_id)), "button", CT.text("window", not unlocked))
	name_label.name = "UnitName"
	title_row.add_child(name_label)
	var owned_label := CT.label(Tr.t("LBL_ARMY_OWNED") % ArmyManager.get_count(unit_id), "number", CT.tone_color("positive"))
	owned_label.name = "Owned"
	title_row.add_child(owned_label)
	var on_campaign: int = int(CombatManager.get_units_on_expedition().get(unit_id, 0))
	if on_campaign > 0:
		var away := CT.badge(Tr.t("ARMY2_AWAY_N") % on_campaign, CT.sem("WARNING"))
		away.tooltip_text = Tr.t("LBL_ON_CAMPAIGN") % on_campaign
		away.mouse_filter = Control.MOUSE_FILTER_PASS
		away.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title_row.add_child(away)
	info.add_child(title_row)

	var stats := HFlowContainer.new()
	stats.name = "Stats"
	stats.add_theme_constant_override("h_separation", 8)
	stats.add_theme_constant_override("v_separation", 2)
	var cost: Dictionary = def.get("cost", {})
	stats.add_child(CT.cost_row(cost, missing(cost)))
	var power := CT.label(Tr.t("LBL_ARMY_POWER_EACH") % int(def.get("power", 0)), "small", CT.text("window", true))
	power.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stats.add_child(power)
	var upkeep := HBoxContainer.new()
	upkeep.name = "Upkeep"
	upkeep.add_theme_constant_override("separation", 2)
	upkeep.mouse_filter = Control.MOUSE_FILTER_PASS
	upkeep.tooltip_text = "%s · %s" % [Tr.t("LBL_ARMY_UPKEEP_SHORT"), Tr.t("LBL_ARMY_UPKEEP_HINT") % int(GameConfig.army_upkeep_interval)]
	var clock := CT.make_glyph("clock", 20)
	clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	upkeep.add_child(clock)
	upkeep.add_child(CT.cost_row({"gold": int(def.get("upkeep_gold", 0))}))
	stats.add_child(upkeep)
	info.add_child(stats)

	var check := ArmyManager.can_train(unit_id)
	if not check["ok"] and check["reason"] != "":
		var why := CT.icon_line("lock", blocked_text(unit_id, String(check["reason"])), "warning")
		why.get_node("Text").name = "BlockedReason"
		info.add_child(why)

	if card_open:
		var unit_card = UnitCardScript.new()
		unit_card.setup(unit_id, null, false)
		info.add_child(unit_card)

	var btn_h := 48 if ph else CT.BTN_SMALL
	var card_btn := CT.pill_button("", "help", "secondary" if not card_open else "open", btn_h)
	card_btn.name = "CardButton"
	card_btn.tooltip_text = Tr.t("ARMY2_CARD_TIP")
	card_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card_btn.pressed.connect(on_card)
	row.add_child(card_btn)
	var word := Tr.t("UI2F_TRAIN_BTN") if (with_word and not ph) else ""
	var train_btn := CT.pill_button(word, "plus", "primary", 52 if not ph else 48)
	train_btn.name = "TrainButton"
	train_btn.add_to_group("hud_train_button")
	train_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	train_btn.disabled = not check["ok"]
	train_btn.tooltip_text = "%s · %s" % [Tr.t("ARMY2_TRAIN_TIP"), TextKit.cost_text(cost)]
	if not check["ok"] and check["reason"] != "":
		train_btn.tooltip_text = blocked_text(unit_id, String(check["reason"]))
	train_btn.pressed.connect(func():
		if ArmyManager.train(unit_id):
			on_changed.call()
	)
	row.add_child(train_btn)
	return card

## Por que no se puede entrenar `unit_id`, en palabras. Una unidad de otra era
## dice cual la abre.
static func blocked_text(unit_id: String, reason: String) -> String:
	if reason == "LBL_ARMY_LOCKED":
		var era: int = int(GameConfig.get_unit_def(unit_id).get("era", 1))
		var key := "LBL_ARMY_LOCKED_ERA_%d" % era
		if Tr.t(key) != key:
			return Tr.t(key)
	return Tr.t(reason)

## La cola en `box`: una linea por recluta (disco, barra, lo que devuelve y ✕).
## Con `building_id`, solo la de ese edificio. Devuelve las barras, en orden,
## con su indice en ArmyManager.get_training() como meta "index".
static func fill_queue(box: VBoxContainer, building_id: String, on_changed: Callable) -> Array:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var bars: Array = []
	var training := ArmyManager.get_training()
	var ph := CT.is_phone()
	for i in range(training.size()):
		var item: Dictionary = training[i]
		if building_id != "" and GameConfig.get_unit_building(String(item["id"])) != building_id:
			continue
		var def := GameConfig.get_unit_def(item["id"])
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var disc := CT.unit_disc(String(item["id"]), CT.sem("INFO"), 30 if ph else 36)
		disc.mouse_filter = Control.MOUSE_FILTER_PASS
		disc.tooltip_text = "%s · %s" % [Tr.t("LBL_ARMY_IN_TRAINING"), Tr.t(def.get("name", item["id"]))]
		line.add_child(disc)
		var bar := CT.progress(training_progress(item), CT.sem("POSITIVE"), "window", 14)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.set_meta("index", i)
		line.add_child(bar)
		line.add_child(make_cancel_button(i, on_changed))
		box.add_child(line)
		bars.append(bar)
	box.visible = not bars.is_empty()
	return bars

static func update_bars(bars: Array, _building_id: String = "") -> void:
	var training := ArmyManager.get_training()
	for bar in bars:
		if not is_instance_valid(bar):
			continue
		var i: int = int(bar.get_meta("index", -1))
		if i >= 0 and i < training.size():
			bar.value = training_progress(training[i])

## Cancelar un entrenamiento: ✕ roja, y lo que vuelve en iconos al lado.
static func make_cancel_button(index: int, on_changed: Callable) -> Control:
	var refund := ArmyManager.get_training_refund(index)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	if not refund.is_empty():
		var back := CT.make_glyph("back", 20)
		back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(back)
		box.add_child(CT.cost_row(refund))
	var btn := CT.pill_button("", "close", "danger", 48 if CT.is_phone() else CT.BTN_SMALL)
	btn.name = "CancelTraining"
	btn.tooltip_text = Tr.t("LBL_CANCEL_NO_REFUND") if refund.is_empty() else Tr.t("FMT_CANCEL_REFUND") % TextKit.cost_text(refund)
	btn.pressed.connect(func():
		ArmyManager.cancel_training(index)
		on_changed.call()
	)
	box.add_child(btn)
	return box

static func training_progress(item: Dictionary) -> float:
	var dur: float = item.get("duration", 1.0)
	if dur <= 0.0:
		return 1.0
	return clampf(1.0 - (item.get("remaining", 0.0) / dur), 0.0, 1.0)

## Lo que falta para pagar `cost` (por nombre de recurso).
static func missing(cost: Dictionary) -> Dictionary:
	var out := {}
	for res_name in cost:
		var type: int = ResourceManager.name_to_type(String(res_name))
		if type < 0:
			continue
		var short: int = int(cost[res_name]) - ResourceManager.get_amount(type)
		if short > 0:
			out[res_name] = short
	return out
