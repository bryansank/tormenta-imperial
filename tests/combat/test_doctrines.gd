extends GdUnitTestSuite
## Doctrinas de la Herreria militar (feat/edificios-militares, doc 21 §5.2,
## docs/15 §14): datos en GameConfig.combat_doctrines, aplicadas por
## CombatUnit.create() solo al bando del jugador, puras y sin azar.
##
## Escrita sin correr (regla de Bryan: un solo pase de pruebas al final).
## Toca GameConfig.combat_active_doctrine: cada prueba la deja como estaba.

const Doctrines := preload("res://scripts/combat/Doctrines.gd")
const CombatUnitScript := preload("res://scripts/combat/CombatUnit.gd")

var _saved_doctrine := ""

func before_test() -> void:
	_saved_doctrine = GameConfig.combat_active_doctrine
	GameConfig.combat_active_doctrine = ""

func after_test() -> void:
	GameConfig.combat_active_doctrine = _saved_doctrine

func _unit(unit_id: String, side: int = 0) -> CombatUnit:
	return CombatUnitScript.create(1, unit_id, side, 1.0)

# ── La tabla ──

func test_there_are_six_doctrines_in_order() -> void:
	assert_int(GameConfig.combat_doctrines.size()).is_equal(6)
	assert_array(Doctrines.ids()).contains_exactly(["assault", "trench", "heavy_artillery",
		"tuned_engines", "seamanship", "air_aces"])

func test_every_doctrine_gives_and_takes() -> void:
	# Mismo presupuesto, distinto estilo: cada una tiene algo bueno y algo malo.
	for id in Doctrines.ids():
		var good := 0
		var bad := 0
		for row in Doctrines.effect_rows(id):
			if bool(row[2]):
				good += 1
			else:
				bad += 1
		assert_int(good).override_failure_message("%s sin ventaja" % id).is_greater(0)
		# Trinchera: su precio es el movimiento; su ventaja, defender x3.
		assert_int(bad).override_failure_message("%s sin precio" % id).is_greater(0)

func test_every_doctrine_has_texts_in_both_languages() -> void:
	var saved := Tr.get_locale()
	for locale in ["es", "en"]:
		Tr.set_locale(locale)
		for id in Doctrines.ids():
			var def := Doctrines.get_def(id)
			for key in [String(def["name"]), String(def["desc"])]:
				assert_str(Tr.t(key)).is_not_equal(key)
		for key in ["DOC_STAT_ATK", "DOC_STAT_ATK_PCT", "DOC_STAT_DEF", "DOC_STAT_DEFEND_MULT",
				"DOC_STAT_MOVE", "DOC_STAT_RANGE", "DOC_STAT_INITIATIVE", "DOC_STAT_HP_PCT"]:
			assert_str(Tr.t(key)).is_not_equal(key)
	Tr.set_locale(saved)

func test_each_doctrine_reaches_the_right_units() -> void:
	assert_array(Doctrines.affected_units("assault")).contains_exactly(["infantry"])
	assert_array(Doctrines.affected_units("heavy_artillery")).contains_exactly(["artillery"])
	assert_array(Doctrines.affected_units("tuned_engines")).contains_exactly(["vehicle"])
	assert_array(Doctrines.affected_units("seamanship")).contains_exactly_in_any_order(
		["torpedo_boat", "gunboat", "dreadnought"])
	assert_array(Doctrines.affected_units("air_aces")).contains_exactly_in_any_order(
		["fighter", "bomber", "airship"])
	assert_bool(Doctrines.applies_to("assault", "vehicle")).is_false()
	assert_bool(Doctrines.applies_to("nope", "infantry")).is_false()

# ── En la unidad ──

func test_no_doctrine_changes_nothing() -> void:
	var u := _unit("infantry")
	assert_str(u.doctrine).is_equal("")
	assert_int(u.move_range()).is_equal(3)
	assert_int(u.defense()).is_equal(2)

func test_assault_moves_one_more_and_covers_one_less() -> void:
	GameConfig.combat_active_doctrine = "assault"
	var u := _unit("infantry")
	assert_str(u.doctrine).is_equal("assault")
	assert_int(u.move_range()).is_equal(4)
	assert_int(u.defense()).is_equal(1)
	# A otro tipo no le toca.
	var gun := _unit("artillery")
	assert_str(gun.doctrine).is_equal("")
	assert_int(gun.defense()).is_equal(1)

func test_trench_triples_defence_when_defending() -> void:
	GameConfig.combat_active_doctrine = "trench"
	var u := _unit("infantry")
	assert_int(u.move_range()).is_equal(2)
	u.defending = true
	assert_int(u.defense()).is_equal(6)

func test_heavy_artillery_hits_harder_and_acts_later() -> void:
	var plain := _unit("artillery")
	GameConfig.combat_active_doctrine = "heavy_artillery"
	var heavy := _unit("artillery")
	assert_int(heavy.attack_power()).is_equal(plain.attack_power() + 2)
	assert_int(heavy.initiative()).is_equal(plain.initiative() - 1)

func test_hp_doctrines_shrink_max_hp_at_birth_and_stay_full() -> void:
	GameConfig.combat_active_doctrine = "tuned_engines"
	var u := _unit("vehicle")
	assert_int(u.max_hp).is_equal(180)   # 200 - 10 %
	assert_int(u.hp).is_equal(u.max_hp)
	GameConfig.combat_active_doctrine = "air_aces"
	var f := _unit("fighter")
	assert_int(f.max_hp).is_between(76, 77)   # 90 - 15 %
	assert_int(f.hp).is_equal(f.max_hp)

func test_seamanship_cuts_attack_by_a_tenth() -> void:
	var plain := _unit("gunboat")
	GameConfig.combat_active_doctrine = "seamanship"
	var drilled := _unit("gunboat")
	assert_int(drilled.attack_power()).is_equal(roundi(float(plain.attack_power()) * 0.9))
	assert_int(drilled.initiative()).is_equal(plain.initiative() + 1)

func test_the_enemy_never_gets_a_doctrine() -> void:
	GameConfig.combat_active_doctrine = "assault"
	var enemy := _unit("infantry", 1)
	assert_str(enemy.doctrine).is_equal("")
	assert_int(enemy.move_range()).is_equal(3)

# ── Guardado ──

func test_a_saved_unit_keeps_its_doctrine_without_touching_hp() -> void:
	GameConfig.combat_active_doctrine = "tuned_engines"
	var u := _unit("vehicle")
	u.take_damage(50)
	var data := u.to_dict()
	assert_str(String(data["doctrine"])).is_equal("tuned_engines")
	# Al cargar, la doctrina activa ya es otra: la unidad sigue con la suya.
	GameConfig.combat_active_doctrine = "assault"
	var back := CombatUnitScript.from_dict(data)
	assert_str(back.doctrine).is_equal("tuned_engines")
	assert_int(back.max_hp).is_equal(180)
	assert_int(back.hp).is_equal(130)
	assert_int(back.move_range()).is_equal(5)

func test_an_old_save_without_doctrine_loads_plain() -> void:
	var data := _unit("infantry").to_dict()
	data.erase("doctrine")
	var back := CombatUnitScript.from_dict(data)
	assert_str(back.doctrine).is_equal("")
	assert_bool(back.doctrine_mods.is_empty()).is_true()

func test_an_unknown_doctrine_in_a_save_is_forgotten() -> void:
	var data := _unit("infantry").to_dict()
	data["doctrine"] = "ya_no_existe"
	var back := CombatUnitScript.from_dict(data)
	assert_str(back.doctrine).is_equal("")
