extends GdUnitTestSuite
## Logros y estadisticas (AchievementManager, docs/29): las definiciones estan
## bien formadas y traducidas, un logro sale al llegar a su meta (una vez), en
## Sandbox no sale ninguno, el Impuesto se cuenta bien, el guardado "stats" es
## idempotente, el reset tira la partida y no el perfil, y el perfil viaja en
## settings.cfg [perfil].
##
## Toca settings.cfg (cada logro ganado lo guarda): se aparta con
## settings_parking y se salta en la carpeta del jugador. Los contadores se
## mueven llamando al servicio, no emitiendo senales del EventBus, para no
## despertar a los demas autoloads (Mercado, rango, musica).

const SettingsParking := preload("res://tests/save/settings_parking.gd")
const SaveParking := preload("res://tests/save/save_parking.gd")
const CartoonIcon := preload("res://scripts/ui/CartoonIcon.gd")

var _settings: Dictionary = {}
var _stats_saved: Dictionary = {}
var _mode_saved: Dictionary = {}
var _unlocked: Array = []

func before(do_skip := SaveParking.in_player_dir(), skip_reason := "Carpeta de usuario del jugador: lanza los tests con tools/run_tests.sh") -> void:
	pass

func before_test() -> void:
	_settings = SettingsParking.park()
	_stats_saved = AchievementManager.get_save_data()
	_mode_saved = GameMode.get_save_data()
	GameConfig.profile_achievements = {}
	AchievementManager.reset()
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.COLONIST)
	_unlocked.clear()
	EventBus.achievement_unlocked.connect(_on_unlocked)

func after_test() -> void:
	EventBus.achievement_unlocked.disconnect(_on_unlocked)
	GameMode.load_save_data(_mode_saved)
	AchievementManager.load_save_data(_stats_saved)
	SettingsParking.restore(_settings)

func _on_unlocked(id: String) -> void:
	_unlocked.append(id)

# ── Definiciones ─────────────────────────────────────────────────────

func test_definitions_are_well_formed() -> void:
	var ids := {}
	var groups := []
	for g in GameConfig.achievement_groups:
		groups.append(String(g[0]))
	for def in GameConfig.achievement_definitions:
		var id := String(def.get("id", ""))
		assert_bool(id.is_empty()).override_failure_message("logro sin id").is_false()
		assert_bool(ids.has(id)).override_failure_message("id repetido: " + id).is_false()
		ids[id] = true
		assert_bool(String(def.get("stat", "")) in AchievementManager.STAT_KEYS) \
			.override_failure_message("contador desconocido en " + id).is_true()
		assert_int(int(def.get("goal", 0))).override_failure_message(id).is_greater(0)
		assert_bool(String(def.get("group", "")) in groups).override_failure_message(id).is_true()
		assert_bool(String(def.get("glyph", "")) in CartoonIcon.GLYPHS).override_failure_message(id).is_true()
	# Entre 25 y 35 logros, alguno secreto.
	assert_int(ids.size()).is_between(25, 35)
	var secrets := GameConfig.achievement_definitions.filter(func(d): return bool(d.get("secret", false)))
	assert_int(secrets.size()).is_greater(0)

func test_every_text_exists_in_both_languages() -> void:
	var keys: Array = ["BTN_ACHIEVEMENTS", "LBL_ACH_TITLE", "FMT_ACHIEVEMENT_UNLOCKED", "FMT_ACH_COUNT"]
	for def in GameConfig.achievement_definitions:
		var id := String(def["id"])
		keys.append(AchievementManager.name_key(id))
		keys.append(AchievementManager.desc_key(id))
	for g in GameConfig.achievement_groups:
		keys.append("ACH_GROUP_" + String(g[0]).to_upper())
	for row in GameConfig.achievement_stat_rows:
		keys.append("STAT_" + String(row[0]).to_upper())
	var saved := Tr.get_locale()
	for locale in Tr.LOCALES:
		Tr.set_locale(locale)
		for key in keys:
			assert_str(Tr.t(key)).override_failure_message("%s sin texto en %s" % [key, locale]).is_not_equal(key)
	Tr.set_locale(saved)

func test_the_mode_rule() -> void:
	assert_bool(GameMode.achievements_enabled()).is_true()
	GameMode.begin_run(GameMode.Mode.SURVIVAL, GameMode.Tier.COLONIST)
	assert_bool(GameMode.achievements_enabled()).is_true()
	GameMode.begin_run(GameMode.Mode.SANDBOX, GameMode.Tier.COLONIST)
	assert_bool(GameMode.achievements_enabled()).is_false()

# ── Ganar un logro ───────────────────────────────────────────────────

func test_an_achievement_unlocks_at_its_goal_once() -> void:
	for i in range(49):
		AchievementManager.count("trades")
	assert_bool(AchievementManager.is_unlocked("trader_50")).is_false()
	assert_that(AchievementManager.progress("trader_50")).is_equal(Vector2i(49, 50))
	AchievementManager.count("trades")
	assert_bool(AchievementManager.is_unlocked("trader_50")).is_true()
	assert_int(AchievementManager.unlocked_at("trader_50")).is_greater(0)
	AchievementManager.count("trades", 10)
	assert_int(_unlocked.count("trader_50")).is_equal(1)
	assert_that(AchievementManager.progress("trader_50")).is_equal(Vector2i(50, 50))

func test_sandbox_counts_stats_but_wins_nothing() -> void:
	GameMode.begin_run(GameMode.Mode.SANDBOX, GameMode.Tier.COLONIST)
	AchievementManager.count("trades", 60)
	assert_int(AchievementManager.get_stat("trades")).is_equal(60)
	assert_bool(AchievementManager.is_unlocked("trader_50")).is_false()
	assert_array(_unlocked).is_empty()

func test_maxima_only_go_up() -> void:
	AchievementManager.raise_max("era", 3)
	AchievementManager.raise_max("era", 2)
	assert_int(AchievementManager.get_stat("era")).is_equal(3)
	assert_bool(AchievementManager.is_unlocked("era_2")).is_true()
	assert_bool(AchievementManager.is_unlocked("era_3")).is_true()

func test_the_tax_is_counted_only_when_it_was_real() -> void:
	AchievementManager._on_tithe_resolved(true, {})
	assert_int(AchievementManager.get_stat("tithes_repelled")).is_equal(1)
	assert_bool(AchievementManager.is_unlocked("tithe_repel_1")).is_true()
	AchievementManager._on_tithe_resolved(false, {"gold": 30})
	assert_int(AchievementManager.get_stat("tithes_paid")).is_equal(1)
	# Constructor no tiene Impuesto: su (true, {}) no es un Impuesto rechazado.
	GameMode.begin_run(GameMode.Mode.BUILDER, GameMode.Tier.COLONIST)
	AchievementManager._on_tithe_resolved(true, {})
	assert_int(AchievementManager.get_stat("tithes_repelled")).is_equal(1)

func test_a_fight_without_losses_is_flawless() -> void:
	AchievementManager._board_losses = 0
	AchievementManager._on_unit_died(7, 1)
	AchievementManager._on_encounter_ended(true, 4)
	assert_int(AchievementManager.get_stat("flawless_wins")).is_equal(1)
	assert_bool(AchievementManager.is_unlocked("flawless")).is_true()
	AchievementManager._on_unit_died(3, 0)
	AchievementManager._on_encounter_ended(true, 6)
	assert_int(AchievementManager.get_stat("flawless_wins")).is_equal(1)
	assert_int(AchievementManager.get_stat("fights_won")).is_equal(2)
	assert_int(AchievementManager.get_stat("units_lost")).is_equal(1)
	assert_int(AchievementManager.get_stat("enemies_defeated")).is_equal(1)
	AchievementManager._on_encounter_ended(false, 9)
	assert_int(AchievementManager.get_stat("fights_lost")).is_equal(1)

func test_the_ending_choice_is_an_achievement() -> void:
	AchievementManager._on_ending_chosen("burn")
	assert_bool(AchievementManager.is_unlocked("ending_burn")).is_true()
	assert_bool(AchievementManager.is_unlocked("ending_sign")).is_false()
	AchievementManager._on_ending_chosen("nonsense")
	assert_int(AchievementManager.get_stat("ending_nonsense")).is_equal(0)

func test_the_governor_win_needs_the_governor_tier() -> void:
	AchievementManager._on_victory({})
	assert_bool(AchievementManager.is_unlocked("governor_win")).is_false()
	GameMode.begin_run(GameMode.Mode.CAMPAIGN, GameMode.Tier.GOVERNOR)
	AchievementManager._on_victory({})
	assert_bool(AchievementManager.is_unlocked("governor_win")).is_true()

func test_campaigns_by_domain() -> void:
	AchievementManager._on_campaign_completed("sea")
	assert_bool(AchievementManager.is_unlocked("campaign_sea")).is_true()
	assert_bool(AchievementManager.is_unlocked("campaign_land")).is_false()
	AchievementManager._on_campaign_completed("space")
	assert_int(AchievementManager.get_stat("campaign_space")).is_equal(0)

func test_technologies_come_as_tech_milestones() -> void:
	AchievementManager._on_milestone("pioneer")
	AchievementManager._on_milestone("tech_ind_1")
	assert_int(AchievementManager.get_stat("techs_researched")).is_equal(1)

func test_collected_resources_add_up() -> void:
	AchievementManager._on_collected(null, {"wood": 40, "gold": 60})
	assert_int(AchievementManager.get_stat("resources_collected")).is_equal(100)

# ── Guardado y perfil ────────────────────────────────────────────────

func test_load_is_idempotent_and_ignores_unknown_keys() -> void:
	var data := {"trades": 7, "storms": 2, "bogus": 99, "fights_won": -3}
	AchievementManager.load_save_data(data)
	AchievementManager.load_save_data(data)
	assert_int(AchievementManager.get_stat("trades")).is_equal(7)
	assert_int(AchievementManager.get_stat("storms")).is_equal(2)
	assert_bool(AchievementManager.get_save_data().has("bogus")).is_false()
	assert_int(AchievementManager.get_stat("fights_won")).is_equal(0)
	# Una partida sin clave "stats" empieza en cero.
	AchievementManager.load_save_data({})
	assert_dict(AchievementManager.get_save_data()).is_empty()

func test_reset_drops_the_run_and_keeps_the_profile() -> void:
	AchievementManager.count("buildings_built")
	assert_bool(AchievementManager.is_unlocked("first_stone")).is_true()
	AchievementManager.reset()
	assert_int(AchievementManager.get_stat("buildings_built")).is_equal(0)
	assert_bool(AchievementManager.is_unlocked("first_stone")).is_true()

func test_the_profile_lives_in_settings_cfg() -> void:
	AchievementManager.count("storms")
	var cf := ConfigFile.new()
	assert_int(cf.load(GameConfig.USER_SETTINGS_PATH)).is_equal(OK)
	var saved: Variant = cf.get_value("perfil", "achievements", {})
	assert_bool(saved is Dictionary and (saved as Dictionary).has("storm_1")).is_true()
	# Al leerlo, un id que no existe se tira.
	var clean: Dictionary = GameConfig._clean_achievements({"storm_1": 5, "made_up": 9, 3: "x"})
	assert_dict(clean).is_equal({"storm_1": 5})
	assert_dict(GameConfig._clean_achievements("basura")).is_empty()

func test_record_achievement_is_once() -> void:
	assert_bool(GameConfig.record_achievement("win_1", 100)).is_true()
	assert_bool(GameConfig.record_achievement("win_1", 200)).is_false()
	assert_bool(GameConfig.record_achievement("no_such_thing", 200)).is_false()
	assert_int(int(GameConfig.profile_achievements["win_1"])).is_equal(100)
