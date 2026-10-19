extends GdUnitTestSuite
## Fase 2 del rediseno, el HUD (feat/ui2-hud, docs/28 §12):
##   - el estilo maqueta de serie;
##   - disposicion de telefono (PHONE_SLOTS) y la linea del siguiente paso por
##     encima de la cruceta en tablet;
##   - recursos: 3 + libres en telefono, barra de almacen fina solo en PC;
##   - la Tormenta como un icono redondo (sol / nube), sin latido;
##   - ¿QUE HACER? como una linea plegable con la cara de la Capitana;
##   - avisos con CartoonTheme.notice() (mismos nombres de nodo);
##   - la tarjeta de la colonia recoge Progreso, Encargos, Registro y Sandbox;
##   - globos de ayuda apagados de serie.
##
## CartoonTheme.phone y el lienzo de UILayoutManager se devuelven como estaban.

var _saved_phone := false
var _saved_vp := Vector2.ZERO
var _saved_touch := "auto"
var _saved_profile := "auto"
var _nodes: Array = []

func before_test() -> void:
	_saved_phone = CartoonTheme.phone
	_saved_vp = UILayoutManager._viewport_size
	_saved_touch = GameConfig.ui_touch_controls
	_saved_profile = GameConfig.ui_device_profile

func after_test() -> void:
	CartoonTheme.phone = _saved_phone
	CartoonTheme.show_caption_never = _saved_phone
	GameConfig.ui_touch_controls = _saved_touch
	GameConfig.ui_device_profile = _saved_profile
	UILayoutManager._viewport_size = _saved_vp
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	UIManager.reset()

func _instance(path: String) -> Node:
	var n: Node = load(path).instantiate()
	add_child(n)
	_nodes.append(n)
	return n

# ── Estilo de serie ──────────────────────────────────────────────────

func test_the_cartoon_style_is_the_default() -> void:
	assert_str(UITheme.STYLE_DEFAULT).is_equal("cartoon")
	assert_bool(UITheme.is_cartoon()).is_true()
	assert_str(CartoonTheme.combo).is_equal("baloo_nunitosans")
	assert_str(CartoonTheme.surface).is_equal("mixed")

func test_floating_help_tips_are_off_by_default() -> void:
	# Un GameConfig recien hecho (sin settings.cfg): el valor de serie.
	var fresh: Node = GameConfig.get_script().new()
	assert_bool(bool(fresh.get("ui_helper_visible"))).is_false()
	fresh.free()

# ── Disposicion ──────────────────────────────────────────────────────

func test_phone_slots_only_name_known_slots() -> void:
	for slot_name in UILayoutConfig.PHONE_SLOTS:
		assert_bool(UILayoutConfig.SLOTS.has(slot_name)).override_failure_message(slot_name).is_true()

func test_a_phone_canvas_pulls_the_hud_to_the_edges() -> void:
	UILayoutManager._viewport_size = Vector2(640, 360)
	CartoonTheme.phone = false
	var pc_build := int(UILayoutManager.get_slot("bottom_center")["margin"]["bottom"])
	CartoonTheme.phone = true
	var phone_build := int(UILayoutManager.get_slot("bottom_center")["margin"]["bottom"])
	var phone_bar := int(UILayoutManager.get_slot("bottom_bar")["margin"]["bottom"])
	var phone_line := int(UILayoutManager.get_slot("next_step")["margin"]["bottom"])
	assert_int(phone_build).is_less(pc_build)
	assert_int(phone_bar).is_equal(phone_build)
	# La linea va encima de la barra (CONSTRUIR de 52 en telefono).
	assert_int(phone_line).is_greater_equal(phone_build + CartoonTheme.bar_build_h())

func test_the_next_step_line_climbs_over_the_dpad_on_a_tablet() -> void:
	UILayoutManager._viewport_size = Vector2(1113, 696)
	CartoonTheme.phone = false
	GameConfig.ui_touch_controls = "never"
	var plain := float(UILayoutManager.get_slot("next_step")["margin"]["bottom"])
	GameConfig.ui_touch_controls = "always"
	var over := float(UILayoutManager.get_slot("next_step")["margin"]["bottom"])
	assert_float(over).is_greater_equal(plain + UILayoutConfig.TOUCH_DPAD_SIDE)

func test_the_storm_is_an_icon_under_the_menu() -> void:
	assert_str(String(UILayoutConfig.PANEL_SLOTS["StormHUD"])).is_equal("storm_icon")
	var slot: Dictionary = UILayoutConfig.SLOTS["storm_icon"]
	assert_float((slot["anchor"] as Rect2).position.x).is_equal(1.0)
	# Debajo del ☰ (14 de margen + 54) y de la insignia del rango, a su altura.
	assert_float(float(slot["margin"]["top"])).is_greater_equal(14.0 + 54.0)

func test_new_hud_entries_are_registered() -> void:
	for id in ["BottomBar", "ObjectivePanel.line"]:
		assert_bool(HudRegistry.ELEMENTS.has(id)).is_true()
		assert_bool(UILayoutConfig.PANEL_SLOTS.has(id)).is_true()
		assert_str(Tr.t(HudRegistry.label_key(id))).is_not_equal(HudRegistry.label_key(id))

# ── Recursos ─────────────────────────────────────────────────────────

func test_a_phone_shows_three_resources_and_the_free_workers() -> void:
	var state := ResourceManager.get_unlock_state()
	ResourceManager.set_unlock_state({"gold": true, "wood": true, "steel": true, "oil": true, "food": true})
	CartoonTheme.phone = true
	var hud = _instance("res://scenes/ui/ResourceHUD.tscn")
	hud._refresh()
	var shown: Array = hud.shown_resource_ids()
	var workers_on: bool = hud.workers_chip().visible
	var storage_on: bool = hud._storage_row.visible
	ResourceManager.set_unlock_state(state)
	assert_int(shown.size()).is_less_equal(ResourceHUDScript.PHONE_RESOURCES_WIDE)
	assert_array(shown).contains(["gold", "wood"])
	assert_bool(workers_on).is_true()
	# La barra del almacen sale de la pantalla del telefono.
	assert_bool(storage_on).is_false()

const ResourceHUDScript := preload("res://scripts/ui/ResourceHUD.gd")

func test_a_pc_shows_every_unlocked_resource_and_a_thin_storage_bar() -> void:
	var state := ResourceManager.get_unlock_state()
	ResourceManager.set_unlock_state({"gold": true, "wood": true, "steel": true, "oil": true})
	CartoonTheme.phone = false
	var hud = _instance("res://scenes/ui/ResourceHUD.tscn")
	hud._refresh()
	var shown: Array = hud.shown_resource_ids()
	var storage_on: bool = hud._storage_row.visible
	var value_on: bool = hud._storage_value.visible
	var tip: String = hud._storage_row.tooltip_text
	ResourceManager.set_unlock_state(state)
	assert_array(shown).contains(["gold", "wood", "steel", "oil"])
	assert_bool(storage_on).is_true()
	# La cifra del almacen va al mantener pulsado, no a la vista.
	assert_bool(value_on).is_false()
	assert_str(tip).contains(Tr.t("HUD_STORAGE_TIP").split(":")[0])

# ── La Tormenta ──────────────────────────────────────────────────────

func test_the_storm_hud_draws_a_single_round_icon() -> void:
	var storm = _instance("res://scenes/ui/StormHUD.tscn")
	assert_bool(storm.shown_glyph() in ["sun", "storm"]).is_true()
	# El nombre de la fase no se ve: va al mantener pulsado.
	assert_bool(storm._label.visible).is_false()
	assert_vector(storm._panel.custom_minimum_size).is_equal(
		Vector2(CartoonTheme.storm_round(), CartoonTheme.storm_round()))

# ── El siguiente paso ────────────────────────────────────────────────

func test_the_next_step_is_a_foldable_line_with_the_captain() -> void:
	var obj = _instance("res://scenes/ui/ObjectivePanel.tscn")
	obj.refresh_line()
	var line: Control = obj.line()
	assert_object(line).is_not_null()
	assert_object(line.find_child("Face", true, false)).is_not_null()
	assert_str(obj.line_text()).is_equal(String(Objectives.describe(Objectives.next_step())["title"]))
	obj.set_line_folded(true)
	var text_hidden: bool = not (line.find_child("StepText", true, false) as Control).visible
	obj.set_line_folded(false)
	assert_bool(text_hidden).is_true()
	assert_bool(obj.is_line_folded()).is_false()

const Objectives := preload("res://scripts/services/Objectives.gd")

func test_the_line_lives_under_the_windows() -> void:
	var obj = _instance("res://scenes/ui/ObjectivePanel.tscn")
	var layer: CanvasLayer = obj.find_child("NextStepLayer", false, false)
	assert_int(layer.layer).is_less(12)  # UIManager apila ventanas desde la 12

# ── Avisos ───────────────────────────────────────────────────────────

func test_alerts_use_the_cartoon_notice_and_keep_their_node_names() -> void:
	var panel = _instance("res://scenes/ui/NotificationPanel.tscn")
	await await_idle_frame()
	EventBus.notification_posted.emit("Falta madera. Construye un Aserradero.", "warning", UITheme.WARNING)
	var toasts: Array = panel.shown_toasts()
	assert_int(toasts.size()).is_greater_equal(1)
	var toast: Control = toasts[0]
	assert_object(toast.find_child("Text", true, false)).is_not_null()
	assert_object(toast.find_child("Close", true, false)).is_not_null()
	# Una frase: hasta el primer punto.
	assert_str((toast.find_child("Text", true, false) as Label).text).is_equal("Falta madera.")

func test_each_alert_kind_has_its_own_glyph() -> void:
	var glyphs := {}
	for cat in ["danger", "warning", "achievement", "combat", "notice"]:
		glyphs[CartoonTheme.notice_glyph(cat)] = true
	assert_int(glyphs.size()).is_equal(5)

# ── La colonia ───────────────────────────────────────────────────────

func test_the_colony_card_gathers_what_left_the_menu() -> void:
	var rank = _instance("res://scenes/ui/RankPanel.tscn")
	for id in ["progress", "contracts", "log", "sandbox"]:
		assert_object(rank.hub_button(id)).override_failure_message(id).is_not_null()
	var saved_mode := GameMode.current
	GameMode.current = GameMode.Mode.CAMPAIGN
	var sandbox_campaign: bool = rank.hub_entry_available("sandbox")
	GameMode.current = GameMode.Mode.SANDBOX
	var sandbox_mode: bool = rank.hub_entry_available("sandbox")
	GameMode.current = saved_mode
	assert_bool(sandbox_campaign).is_false()
	assert_bool(sandbox_mode).is_true()
