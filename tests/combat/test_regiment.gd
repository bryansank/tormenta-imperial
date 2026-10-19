extends GdUnitTestSuite
## El regimiento (feat/regimiento, doc 21 §5.1): nombre, color, emblema,
## pintura por rango y estrellas por combates ganados. SOLO COSMETICO.
##
## Escrito sin correr (regla de Bryan: un solo pase de pruebas al final).

const SaveParking := preload("res://tests/save/save_parking.gd")
const RegimentLook := preload("res://scripts/ui/RegimentLook.gd")
const RegimentCard := preload("res://scripts/ui/RegimentCard.gd")
const Models := preload("res://scripts/combat_view/UnitModels3D.gd")
const UnitToy := preload("res://scripts/combat_view/UnitToy3D.gd")
const BACKUP_PATH := "user://save_game.regiment.bak"

func before(do_skip := SaveParking.in_player_dir(), skip_reason := "Carpeta de usuario del jugador: lanza los tests con tools/run_tests.sh") -> void:
	pass

var _army_saved: Dictionary = {}
var _rank_saved: Dictionary = {}
var _mode_saved: Dictionary = {}

func before_test() -> void:
	SaveParking.park(BACKUP_PATH)
	_army_saved = ArmyManager.get_save_data()
	_rank_saved = RankManager.get_save_data()
	_mode_saved = GameMode.get_save_data()
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	RankManager.reset()
	ArmyManager.reset()

func after_test() -> void:
	GameMode.load_save_data(_mode_saved)
	RankManager.reset()
	RankManager.load_save_data(_rank_saved)
	ArmyManager.reset()
	ArmyManager.load_save_data(_army_saved)
	SaveParking.restore(BACKUP_PATH)

func _reach_rank(rank: int) -> void:
	RankManager.add_xp(RankManager.xp_for_rank(rank) - RankManager.get_xp())

# ── Lo de serie ──

func test_a_new_regiment_wears_the_colony_flag() -> void:
	var look := ArmyManager.get_regiment_look()
	var flag := RankManager.get_flag_spec()
	assert_str(String(look["color_id"])).is_equal(RankManager.get_color_id())
	assert_str(String(look["emblem"])).is_equal(String(flag["emblem"]))
	assert_str(String(look["paint"])).is_equal("plain")
	assert_int(int(look["stars"])).is_equal(0)
	assert_str(String(look["name"])).is_equal(Tr.t("REGIMENT_DEFAULT_NAME"))

func test_the_default_regiment_follows_a_new_flag_colour() -> void:
	var spec := RankManager.get_flag_spec()
	spec["colors"][0] = "crimson"
	RankManager.set_colony(RankManager.get_colony_name(), spec)
	assert_str(String(ArmyManager.get_regiment_look()["color_id"])).is_equal("crimson")

# ── Piezas por rango ──

func test_every_paint_opens_at_its_rank() -> void:
	var want := {"plain": 1, "stripes": 3, "spots": 6, "desert": 9, "snow": 12, "parade": 15}
	for paint in GameConfig.REGIMENT_PAINTS:
		assert_int(RegimentLook.paint_rank(paint)).is_equal(int(want[paint]))

func test_a_locked_paint_is_refused_until_the_rank_opens_it() -> void:
	assert_bool(ArmyManager.set_regiment("", "", "", "stripes")).is_false()
	assert_str(String(ArmyManager.get_regiment()["paint"])).is_equal("plain")
	_reach_rank(3)
	assert_bool(ArmyManager.set_regiment("", "", "", "stripes")).is_true()
	assert_str(String(ArmyManager.get_regiment_look()["paint"])).is_equal("stripes")

func test_a_locked_colour_or_emblem_is_refused() -> void:
	# "gold" abre en el rango 14 y "airship" en el 18.
	assert_bool(ArmyManager.set_regiment("", "gold", "", "plain")).is_false()
	assert_bool(ArmyManager.set_regiment("", "", "airship", "plain")).is_false()
	assert_bool(ArmyManager.set_regiment("", "steel", "anchor", "plain")).is_true()
	var look := ArmyManager.get_regiment_look()
	assert_str(String(look["color_id"])).is_equal("steel")
	assert_str(String(look["emblem"])).is_equal("anchor")

func test_sandbox_opens_every_piece() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX)
	assert_bool(ArmyManager.set_regiment("", "gold", "airship", "parade")).is_true()

func test_a_name_that_fails_the_filter_is_refused() -> void:
	assert_bool(ArmyManager.set_regiment("puta", "", "", "plain")).is_false()
	assert_bool(ArmyManager.set_regiment("  Guardia   del Faro ", "", "", "plain")).is_true()
	assert_str(String(ArmyManager.get_regiment()["name"])).is_equal("Guardia del Faro")
	assert_str(String(ArmyManager.get_regiment_look()["name"])).is_equal("Guardia del Faro")

func test_random_names_are_stable_and_pass_the_filter() -> void:
	for seed_value in 20:
		for locale in ["es", "en"]:
			var a := RegimentLook.random_name(seed_value, locale)
			assert_str(a).is_equal(RegimentLook.random_name(seed_value, locale))
			assert_bool(a.length() <= GameConfig.COLONY_NAME_MAX).is_true()

# ── Guardado ──

func test_the_regiment_travels_in_the_army_save_and_loads_twice_the_same() -> void:
	_reach_rank(6)
	ArmyManager.set_regiment("Brigada del Yunque", "moss", "hammer", "spots")
	ArmyManager._record_regiment_win()
	var data := ArmyManager.get_save_data()
	assert_bool(data.has("regiment")).is_true()
	var want := ArmyManager.get_regiment()
	ArmyManager.reset()
	ArmyManager.load_save_data(data)
	ArmyManager.load_save_data(data)
	assert_dict(ArmyManager.get_regiment()).is_equal(want)
	assert_int(int(ArmyManager.get_regiment()["wins"])).is_equal(1)

func test_an_old_save_without_regiment_gets_the_default() -> void:
	ArmyManager.set_regiment("Columna de Hierro", "", "", "plain")
	ArmyManager.load_save_data({"units": {"infantry": 2}})
	assert_dict(ArmyManager.get_regiment()).is_equal(RegimentLook.defaults())

func test_unknown_pieces_in_a_save_fall_back_to_the_default() -> void:
	ArmyManager.load_save_data({"regiment": {"name": 7, "color": "plaid", "emblem": "dragon", "paint": "chrome", "wins": -4}})
	var r := ArmyManager.get_regiment()
	assert_str(String(r["color"])).is_equal("")
	assert_str(String(r["emblem"])).is_equal("")
	assert_str(String(r["paint"])).is_equal("plain")
	assert_int(int(r["wins"])).is_equal(0)

func test_a_saved_piece_above_the_rank_is_kept_but_drawn_as_the_flag_one() -> void:
	# El ejercito carga antes que el rango: no se recorta al cargar.
	ArmyManager.load_save_data({"regiment": {"paint": "snow", "color": "gold"}})
	assert_str(String(ArmyManager.get_regiment()["paint"])).is_equal("snow")
	var look := ArmyManager.get_regiment_look()
	assert_str(String(look["paint"])).is_equal("plain")
	assert_str(String(look["color_id"])).is_equal(RankManager.get_color_id())

func test_reset_throws_the_regiment_away() -> void:
	ArmyManager.set_regiment("Guardia del Faro", "steel", "", "plain")
	ArmyManager._record_regiment_win()
	ArmyManager.reset()
	assert_dict(ArmyManager.get_regiment()).is_equal(RegimentLook.defaults())

# ── Estrellas ──

func test_stars_come_from_fights_won() -> void:
	var t: Array = GameConfig.regiment_star_wins
	assert_int(RegimentLook.stars_for(int(t[0]) - 1)).is_equal(0)
	assert_int(RegimentLook.stars_for(int(t[0]))).is_equal(1)
	assert_int(RegimentLook.stars_for(int(t[1]))).is_equal(2)
	assert_int(RegimentLook.stars_for(int(t[2]))).is_equal(3)
	assert_int(RegimentLook.stars_for(int(t[2]) * 10)).is_equal(3)
	assert_int(RegimentLook.wins_to_next_star(0)).is_equal(int(t[0]))

func test_only_a_won_fight_counts() -> void:
	ArmyManager._on_encounter_ended(false, 4)
	assert_int(int(ArmyManager.get_regiment()["wins"])).is_equal(0)
	ArmyManager._on_encounter_ended(true, 4)
	assert_int(int(ArmyManager.get_regiment()["wins"])).is_equal(1)

func test_combat_never_reads_the_regiment() -> void:
	# Solo cosmetico: ni el modelo del combate ni sus reglas lo miran.
	for file in ["CombatUnit", "CombatRules", "Encounter", "CombatAI", "AutoResolver", "FinalAudit"]:
		var src := FileAccess.get_file_as_string("res://scripts/combat/%s.gd" % file)
		assert_bool(src.to_lower().contains("regiment")).is_false()

# ── Lo que se ve ──

func test_the_badge_is_one_texture_per_look() -> void:
	var look := ArmyManager.get_regiment_look()
	assert_object(RegimentLook.badge_texture(look)).is_same(RegimentLook.badge_texture(look))
	var starred := look.duplicate()
	starred["stars"] = 2
	assert_object(RegimentLook.badge_texture(starred)).is_not_same(RegimentLook.badge_texture(look))
	var img := RegimentLook.make_badge_image("brass", "gear", 3)
	assert_int(img.get_width()).is_equal(RegimentLook.BADGE)
	# Las esquinas, transparentes (es un disco).
	assert_float(img.get_pixel(0, 0).a).is_equal(0.0)

func test_a_paint_is_one_shared_material_per_colour_and_paint() -> void:
	var c := Color(0.3, 0.45, 0.62)
	var striped := Models.team_material(c, "stripes")
	assert_object(striped).is_same(Models.team_material(c, "stripes"))
	assert_bool(striped is ShaderMaterial).is_true()
	assert_int(int((striped as ShaderMaterial).get_shader_parameter("paint"))).is_equal(GameConfig.REGIMENT_PAINTS.find("stripes"))
	# Liso: el material de siempre, sin shader propio.
	assert_bool(Models.team_material(c) is StandardMaterial3D).is_true()
	assert_object(Models.team_material(c, "plain")).is_same(Models.team_material(c))

func test_only_our_toys_wear_the_badge() -> void:
	var look := ArmyManager.get_regiment_look()
	var ours: Node3D = auto_free(UnitToy.new())
	add_child(ours)
	ours.setup({"uid": 1, "unit_id": "infantry", "side": 0, "hp": 10, "max_hp": 10, "team_color": look["color"], "regiment": look})
	assert_bool(ours.has_regiment_badge()).is_true()
	var theirs: Node3D = auto_free(UnitToy.new())
	add_child(theirs)
	theirs.setup({"uid": 2, "unit_id": "infantry", "side": 1, "hp": 10, "max_hp": 10, "regiment": look})
	assert_bool(theirs.has_regiment_badge()).is_false()

func test_the_card_shows_the_regiment_and_locks_paints_by_rank() -> void:
	var card: PanelContainer = auto_free(RegimentCard.new())
	add_child(card)
	await await_idle_frame()
	var name_label: Label = card.find_child("RegimentName", true, false)
	assert_str(name_label.text).is_equal(Tr.t("REGIMENT_DEFAULT_NAME"))
	card.toggle_editor()
	var stripes: Button = card.find_child("Paint_stripes", true, false)
	assert_bool(stripes.disabled).is_true()
	var plain: Button = card.find_child("Paint_plain", true, false)
	assert_bool(plain.disabled).is_false()
	assert_bool(card.pick("color", "steel")).is_true()
	assert_str(String(ArmyManager.get_regiment()["color"])).is_equal("steel")

func test_the_army_panel_carries_the_card() -> void:
	var panel: CanvasLayer = auto_free(load("res://scenes/ui/ArmyPanel.tscn").instantiate())
	add_child(panel)
	await await_idle_frame()
	assert_object(panel.find_child("RegimentCard", true, false)).is_not_null()

func test_rank_ups_name_the_new_paint() -> void:
	var lines: Array = load("res://scripts/ui/RankPanel.gd").reward_lines(RankManager.rewards_between(2, 3))
	assert_bool(Tr.t("LBL_RANK_REWARD_PAINT") in lines).is_true()
