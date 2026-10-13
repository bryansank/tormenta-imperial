extends GdUnitTestSuite
## El pais del jugador: nombre y bandera por piezas (RankManager, ColonyIdentity,
## ColonyFlag y el editor ColonyIdentityPanel). Guardar y cargar, idempotencia,
## partidas viejas, desbloqueo por rango, filtro de palabras, "al azar" estable
## con semilla y que la bandera siempre se lea.
##
## RankManager y GameMode son autoloads compartidos: se aparta su estado antes de
## cada test y se devuelve despues. La semilla de la isla tambien.

const ColonyFlag := preload("res://scripts/ui/ColonyFlag.gd")
const ColonyIdentity := preload("res://scripts/services/ColonyIdentity.gd")
const IdentityPanel := preload("res://scripts/ui/ColonyIdentityPanel.gd")

var _rank_saved: Dictionary = {}
var _mode_saved: Dictionary = {}
var _island_seed := -1
var _events: Array = []

func before_test() -> void:
	_rank_saved = RankManager.get_save_data()
	_mode_saved = GameMode.get_save_data()
	_island_seed = GridManager.island_seed
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	RankManager.reset()
	_events.clear()
	EventBus.colony_identity_changed.connect(_on_identity)

func after_test() -> void:
	EventBus.colony_identity_changed.disconnect(_on_identity)
	GridManager.island_seed = _island_seed
	GameMode.load_save_data(_mode_saved)
	RankManager.reset()
	RankManager.load_save_data(_rank_saved)

func _on_identity(colony_name: String, spec: Dictionary) -> void:
	_events.append([colony_name, spec])

func _spec(pattern: String, emblem: String, colors: Array) -> Dictionary:
	return {"pattern": pattern, "emblem": emblem, "colors": colors}

# ── Guardar y cargar ─────────────────────────────────────────────────

func test_the_country_travels_in_the_save_and_loads_back() -> void:
	assert_bool(RankManager.set_colony("Liga de Vaporia", _spec("bands_v", "anchor", ["steel", "ivory", "soot"]))).is_true()
	var saved := RankManager.get_save_data()
	assert_dict(saved["colony"]).contains_keys(["name", "flag"])
	assert_dict(saved["colony"]["flag"]).contains_keys(["pattern", "emblem", "colors"])
	RankManager.reset()
	assert_str(RankManager.get_colony_name()).is_not_equal("Liga de Vaporia")
	RankManager.load_save_data(saved)
	assert_str(RankManager.get_colony_name()).is_equal("Liga de Vaporia")
	assert_str(ColonyFlag.spec_key(RankManager.get_flag_spec())).is_equal(ColonyFlag.spec_key(saved["colony"]["flag"]))
	# La carga lo anuncia (los mastiles y la insignia se repintan).
	assert_str(String(_events.back()[0])).is_equal("Liga de Vaporia")

func test_loading_twice_gives_the_same_country() -> void:
	var data := {"xp": 300, "colony": {"name": "Ducado de Pistonia",
		"flag": _spec("cross", "wheat", ["moss", "ivory", "brass"])}}
	RankManager.load_save_data(data.duplicate(true))
	var once := RankManager.get_save_data()
	RankManager.load_save_data(data.duplicate(true))
	assert_dict(RankManager.get_save_data()).is_equal(once)

func test_an_old_save_with_the_old_flag_translates_it_to_pieces() -> void:
	GridManager.island_seed = 4242
	RankManager.load_save_data({"xp": 0, "flag": "gear", "color": "steel"})
	var spec := RankManager.get_flag_spec()
	assert_str(String(spec["pattern"])).is_equal("plain")
	assert_str(String(spec["emblem"])).is_equal("gear")
	assert_str(String(spec["colors"][0])).is_equal("steel")
	assert_str(RankManager.get_colony_name()).is_not_empty()
	# Todas las banderas de antes tienen traduccion, abierta en el rango en que
	# se abria la de antes (o antes).
	var old_rank := {"plain": 1, "band": 1, "cross": 3, "diagonal": 6, "gear": 9, "chevron": 12}
	for old in GameConfig.COLONY_LEGACY_FLAGS:
		var translated := ColonyIdentity.legacy_spec(old, "crimson")
		assert_str(String(translated["pattern"])).is_equal(GameConfig.COLONY_LEGACY_FLAGS[old][0])
		assert_bool(ColonyIdentity.is_spec_open(translated, old_rank[old])).override_failure_message(old).is_true()

func test_an_old_save_without_a_country_gets_a_stable_one_from_the_island_seed() -> void:
	GridManager.island_seed = 777
	RankManager.load_save_data({"xp": 50})
	var first_name := RankManager.get_colony_name()
	var first_flag := ColonyFlag.spec_key(RankManager.get_flag_spec())
	RankManager.reset()
	RankManager.load_save_data({"xp": 50})
	assert_str(RankManager.get_colony_name()).is_equal(first_name)
	assert_str(ColonyFlag.spec_key(RankManager.get_flag_spec())).is_equal(first_flag)
	assert_bool(RankManager.is_spec_unlocked(RankManager.get_flag_spec())).is_true()
	# Otra isla, otro pais (en alguna de unas cuantas semillas).
	var differs := false
	for s in [1, 2, 3, 4, 5]:
		GridManager.island_seed = s
		RankManager.load_save_data({})
		if RankManager.get_colony_name() != first_name or ColonyFlag.spec_key(RankManager.get_flag_spec()) != first_flag:
			differs = true
	assert_bool(differs).is_true()

func test_a_saved_name_that_does_not_pass_is_replaced() -> void:
	GridManager.island_seed = 9
	RankManager.load_save_data({"colony": {"name": "Puerto Mierda", "flag": GameConfig.COLONY_DEFAULT_SPEC}})
	assert_str(RankManager.get_colony_name()).is_not_equal("Puerto Mierda")
	assert_bool(ColonyIdentity.is_name_allowed(RankManager.get_colony_name())).is_true()

func test_reset_uses_the_country_queued_by_the_new_game_step() -> void:
	var spec := _spec("halves_h", "hammer", ["crimson", "soot", "ivory"])
	assert_bool(RankManager.queue_colony_for_new_game("Comuna de Hollinar", spec)).is_true()
	assert_bool(RankManager.has_queued_colony()).is_true()
	RankManager.reset()
	assert_str(RankManager.get_colony_name()).is_equal("Comuna de Hollinar")
	assert_str(String(RankManager.get_flag_spec()["pattern"])).is_equal("halves_h")
	assert_bool(RankManager.has_queued_colony()).is_false()
	# Lo encolado se usa una vez: la siguiente partida vuelve a ser al azar.
	RankManager.reset()
	assert_str(RankManager.get_colony_name()).is_not_equal("Comuna de Hollinar")

func test_the_queue_only_takes_rank_one_pieces_and_clean_names() -> void:
	assert_bool(RankManager.queue_colony_for_new_game("Liga de Vaporia", _spec("checks", "gear", ["brass", "ivory", "soot"]))).is_false()
	assert_bool(RankManager.queue_colony_for_new_game("puta", GameConfig.COLONY_DEFAULT_SPEC)).is_false()
	assert_bool(RankManager.has_queued_colony()).is_false()

# ── Desbloqueo por rango ─────────────────────────────────────────────

func test_rank_one_opens_the_basics_and_the_showy_pieces_come_later() -> void:
	for kind in ["patterns", "emblems", "colors"]:
		var basics := ColonyIdentity.open_pieces(kind, 1)
		assert_int(basics.size()).override_failure_message(kind).is_greater_equal(5)
		assert_int(basics.size()).override_failure_message(kind).is_less(ColonyIdentity.catalog(kind).size())
		assert_array(ColonyIdentity.open_pieces(kind, RankManager.max_rank())).is_equal(ColonyIdentity.catalog(kind))
	assert_int(ColonyIdentity.piece_rank("patterns", "checks")).is_equal(18)
	assert_int(ColonyIdentity.piece_rank("emblems", "airship")).is_equal(18)
	assert_int(ColonyIdentity.piece_rank("emblems", "nonsense")).is_equal(0)

func test_set_colony_follows_the_rank() -> void:
	var spec := _spec("quartered", "wrench", ["steel", "ivory", "soot"])
	assert_bool(RankManager.set_colony("Cantón de Valvulia", spec)).is_false()
	RankManager.add_xp(RankManager.xp_for_rank(9))
	assert_bool(RankManager.set_colony("Cantón de Valvulia", spec)).is_true()
	assert_str(String(RankManager.get_flag_spec()["pattern"])).is_equal("quartered")
	# Sandbox: todo abierto desde el rango 1.
	RankManager.reset()
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	assert_bool(RankManager.set_colony("Liga de Vaporia", _spec("checks", "airship", ["gold", "soot", "ivory"]))).is_true()

func test_set_colony_rejects_bad_or_empty_names_and_announces_only_changes() -> void:
	var name_before := RankManager.get_colony_name()
	assert_bool(RankManager.set_colony("", GameConfig.COLONY_DEFAULT_SPEC)).is_false()
	assert_bool(RankManager.set_colony("   ", GameConfig.COLONY_DEFAULT_SPEC)).is_false()
	assert_bool(RankManager.set_colony("F u c k land", GameConfig.COLONY_DEFAULT_SPEC)).is_false()
	assert_str(RankManager.get_colony_name()).is_equal(name_before)
	assert_array(_events).is_empty()
	assert_bool(RankManager.set_colony("Bahía Tuerca", GameConfig.COLONY_DEFAULT_SPEC)).is_true()
	assert_int(_events.size()).is_equal(1)
	assert_bool(RankManager.set_colony("Bahía Tuerca", GameConfig.COLONY_DEFAULT_SPEC)).is_true()
	assert_int(_events.size()).is_equal(1)
	# Largo: se recorta a COLONY_NAME_MAX.
	assert_bool(RankManager.set_colony("Una Republica Con Un Nombre Larguisimo", GameConfig.COLONY_DEFAULT_SPEC)).is_true()
	assert_int(RankManager.get_colony_name().length()).is_less_equal(GameConfig.COLONY_NAME_MAX)

# ── Filtro ───────────────────────────────────────────────────────────

func test_the_word_filter_blocks_rude_names_in_both_languages() -> void:
	for bad in ["Puta Isla", "PUTO", "República de la Mierda", "M1erd4 Land", "Shitland", "s h i t",
			"Fuuuck", "Isla Culo", "Cabrón", "Ass Bay", "Dick Island", "Nazi Port", "Coño"]:
		assert_bool(ColonyIdentity.is_name_allowed(bad)).override_failure_message("deja pasar: " + bad).is_false()

func test_the_word_filter_lets_normal_names_through() -> void:
	for good in ["Puerto Hierro", "Liga de Vaporia", "Calculo", "Disputa Vieja", "Vehículo",
			"Assembly Bay", "Peacock Point", "Sussex", "Penélope", "Ciudad Cocodrilo", "Pollensa"]:
		assert_bool(ColonyIdentity.is_name_allowed(good)).override_failure_message("bloquea: " + good).is_true()
	assert_bool(ColonyIdentity.is_name_allowed("a")).is_false()

func test_clean_name_trims_spaces_and_control_characters() -> void:
	assert_str(ColonyIdentity.clean_name("  Liga   de \tVaporia  ")).is_equal("Liga de Vaporia")
	assert_str(ColonyIdentity.clean_name("Vapo\nria")).is_equal("Vaporia")

# ── Al azar ──────────────────────────────────────────────────────────

func test_random_names_are_stable_short_clean_and_in_both_languages() -> void:
	for s in range(40):
		for lang in ["es", "en"]:
			var n := ColonyIdentity.random_name(s, lang)
			assert_str(ColonyIdentity.random_name(s, lang)).is_equal(n)
			assert_int(n.length()).is_less_equal(GameConfig.COLONY_NAME_MAX)
			assert_bool(ColonyIdentity.is_name_allowed(n)).override_failure_message(n).is_true()
	assert_bool(ColonyIdentity.PLACES["es"].any(func(p): return ColonyIdentity.random_name(3, "es").contains(p))).is_true()
	assert_bool(ColonyIdentity.PLACES["en"].any(func(p): return ColonyIdentity.random_name(3, "en").contains(p))).is_true()
	# El ejemplo del dueno cabe.
	assert_int("República de Puerto Hierro".length()).is_less_equal(GameConfig.COLONY_NAME_MAX)

func test_random_flags_are_stable_open_and_readable() -> void:
	var keys := {}
	for s in range(60):
		var spec := ColonyIdentity.random_spec(s, 1)
		assert_str(ColonyFlag.spec_key(ColonyIdentity.random_spec(s, 1))).is_equal(ColonyFlag.spec_key(spec))
		assert_bool(ColonyIdentity.is_spec_open(spec, 1)).is_true()
		_assert_pretty(spec)
		keys[ColonyFlag.spec_key(spec)] = true
	# Variadas: no siempre la misma.
	assert_int(keys.size()).is_greater(30)
	for s in range(20):
		var spec := ColonyIdentity.random_spec(s, 18)
		assert_bool(ColonyIdentity.is_spec_open(spec, 18)).is_true()
		_assert_pretty(spec)

func _assert_pretty(spec: Dictionary) -> void:
	var colors: Array = spec["colors"]
	if ColonyFlag.fields_of(spec["pattern"]) == 2:
		assert_bool(ColonyFlag.fields_distinct(colors[0], colors[1])).override_failure_message(str(spec)).is_true()
	if spec["emblem"] != "none":
		assert_float(ColonyFlag.emblem_contrast(spec["pattern"], colors, colors[2])).override_failure_message(str(spec)).is_greater_equal(1.5)

# ── Siempre bonita ───────────────────────────────────────────────────

func test_fix_spec_repairs_clashing_colours_and_is_idempotent() -> void:
	var fixed := ColonyFlag.fix_spec(_spec("bands_h", "gear", ["brass", "brass", "brass"]))
	assert_bool(ColonyFlag.fields_distinct(fixed["colors"][0], fixed["colors"][1])).is_true()
	assert_bool(ColonyFlag.emblem_legible("bands_h", fixed["colors"], fixed["colors"][2])).is_true()
	assert_str(ColonyFlag.spec_key(ColonyFlag.fix_spec(fixed))).is_equal(ColonyFlag.spec_key(fixed))
	# Una receta ya buena no cambia.
	var good := _spec("cross", "anchor", ["steel", "ivory", "ivory"])
	assert_str(ColonyFlag.spec_key(ColonyFlag.fix_spec(good))).is_equal(ColonyFlag.spec_key(good))

func test_every_rank_one_background_leaves_a_readable_emblem_colour() -> void:
	var colors := ColonyIdentity.open_pieces("colors", 1)
	for pattern in ColonyIdentity.open_pieces("patterns", 1):
		for c0 in colors:
			for c1 in colors:
				if ColonyFlag.fields_of(pattern) == 2 and not ColonyFlag.fields_distinct(c0, c1):
					continue
				var any := false
				for ce in colors:
					if ColonyFlag.emblem_legible(pattern, [c0, c1, ce], ce):
						any = true
						break
				assert_bool(any).override_failure_message("%s %s/%s sin color de emblema legible" % [pattern, c0, c1]).is_true()

func test_unknown_pieces_fall_back_to_the_default_recipe() -> void:
	var s := ColonyFlag.normalized({"pattern": "skull", "emblem": "x", "colors": ["pink"]})
	assert_str(String(s["pattern"])).is_equal(GameConfig.COLONY_DEFAULT_SPEC["pattern"])
	assert_str(String(s["emblem"])).is_equal(GameConfig.COLONY_DEFAULT_SPEC["emblem"])
	assert_int((s["colors"] as Array).size()).is_equal(3)

# ── Dibujo ───────────────────────────────────────────────────────────

func test_textures_are_cached_per_recipe_and_size() -> void:
	var spec := _spec("border", "ship", ["sky", "soot", "ivory"])
	var a := ColonyFlag.texture(spec)
	assert_object(ColonyFlag.texture(spec)).is_same(a)
	assert_object(ColonyFlag.small_texture(spec)).is_not_same(a)
	assert_int(a.get_width()).is_equal(ColonyFlag.W)
	assert_int(ColonyFlag.small_texture(spec).get_width()).is_equal(ColonyFlag.SMALL_W)

func test_the_emblem_is_actually_drawn_in_its_colour() -> void:
	var img := ColonyFlag.make_image(_spec("plain", "gear", ["soot", "soot", "gold"]), ColonyFlag.W, ColonyFlag.H, 1)
	var center := img.get_pixel(ColonyFlag.W / 2 + 12, ColonyFlag.H / 2)
	var corner := img.get_pixel(6, 6)
	assert_float(UITheme.contrast_ratio(center, corner)).is_greater(3.0)

# ── El editor ────────────────────────────────────────────────────────

func _editor() -> CanvasLayer:
	var panel: CanvasLayer = IdentityPanel.new()
	panel.auto_free = false
	add_child(panel)
	auto_free(panel)
	return panel

func test_the_new_game_step_comes_preset_and_skip_accepts_it() -> void:
	var panel := _editor()
	await await_idle_frame()
	var got: Array = []
	panel.confirmed.connect(func(n, s): got.append([n, s]))
	panel.open("new")
	var preset_name: String = panel.get_name_text()
	var preset_key := ColonyFlag.spec_key(panel.get_spec())
	assert_str(preset_name).is_not_empty()
	assert_bool(ColonyIdentity.is_spec_open(panel.get_spec(), 1)).is_true()
	# Tocar algo y luego Saltar: vale lo que habia al abrir.
	panel.pick("patterns", "plain")
	panel.secondary()
	assert_int(got.size()).is_equal(1)
	assert_str(String(got[0][0])).is_equal(preset_name)
	assert_str(ColonyFlag.spec_key(got[0][1])).is_equal(preset_key)
	assert_bool(panel.is_open()).is_false()

func test_the_new_game_step_only_offers_rank_one_pieces() -> void:
	RankManager.add_xp(RankManager.xp_for_rank(18))
	var panel := _editor()
	await await_idle_frame()
	panel.open("new")
	assert_bool(panel.pick("patterns", "checks")).is_false()
	assert_bool(panel.pick("patterns", "cross")).is_true()
	# En "edit" el rango 18 lo abre.
	panel.cancel()
	panel.open("edit")
	assert_bool(panel.pick("patterns", "checks")).is_true()

func test_the_editor_refuses_a_bad_name_without_closing() -> void:
	var panel := _editor()
	await await_idle_frame()
	var got: Array = []
	panel.confirmed.connect(func(n, s): got.append(n))
	panel.open("edit")
	var edit: LineEdit = panel.find_child("NameEdit", true, false)
	edit.text = "culo"
	assert_bool(panel.confirm()).is_false()
	assert_bool(panel.is_open()).is_true()
	assert_bool((panel.find_child("NameError", true, false) as Label).visible).is_true()
	edit.text = "Monte Biela"
	assert_bool(panel.confirm()).is_true()
	assert_array(got).is_equal(["Monte Biela"])

func test_the_editor_greys_out_colours_that_would_not_read() -> void:
	var panel := _editor()
	await await_idle_frame()
	panel.open("edit", "Monte Biela", _spec("bands_h", "gear", ["brass", "ivory", "crimson"]))
	panel.select_tab("colors")
	# Fondo 2 igual al fondo 1: no.
	assert_bool((panel.find_child("Color_1_brass", true, false) as Button).disabled).is_true()
	assert_bool(panel.pick("colors", "brass", 1)).is_false()
	# Emblema marfil sobre la franja marfil: no.
	assert_bool((panel.find_child("Color_2_ivory", true, false) as Button).disabled).is_true()
	assert_bool((panel.find_child("Color_2_soot", true, false) as Button).disabled).is_false()
	# Cambiar el fondo arregla lo demas solo.
	assert_bool(panel.pick("colors", "ivory", 0)).is_true()
	var spec: Dictionary = panel.get_spec()
	assert_bool(ColonyFlag.fields_distinct(spec["colors"][0], spec["colors"][1])).is_true()
	assert_bool(ColonyFlag.emblem_legible(spec["pattern"], spec["colors"], spec["colors"][2])).is_true()

func test_random_buttons_change_name_and_flag() -> void:
	var panel := _editor()
	await await_idle_frame()
	panel.open("edit")
	var names := {}
	var flags := {}
	for i in 6:
		panel.randomize_name()
		panel.randomize_flag()
		names[panel.get_name_text()] = true
		flags[ColonyFlag.spec_key(panel.get_spec())] = true
		assert_bool(ColonyIdentity.is_spec_open(panel.get_spec(), RankManager.get_rank())).is_true()
	assert_int(names.size()).is_greater(1)
	assert_int(flags.size()).is_greater(1)
