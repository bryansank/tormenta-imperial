extends GdUnitTestSuite
## La ficha de unidad (docs/15 §3 "Ensenar el combate"): los numeros salen de
## GameConfig, la ventaja por tipo del circulo, la artilleria dice su alcance
## minimo, y la ficha se monta sin romper con o sin unidad viva.

const UnitCardScript := preload("res://scripts/ui/UnitCard.gd")
const TypeCircleScript := preload("res://scripts/ui/TypeCircle.gd")
const CombatUnitScript := preload("res://scripts/combat/CombatUnit.gd")
const HelpCatalog := preload("res://scripts/ui/HelpCatalog.gd")

func test_strong_and_weak_follow_the_circle() -> void:
	assert_array(UnitCardScript.strong_against("infantry")).contains_exactly(["artillery"])
	assert_array(UnitCardScript.weak_against("infantry")).contains_exactly(["vehicle"])
	assert_array(UnitCardScript.strong_against("artillery")).contains_exactly(["vehicle"])
	assert_array(UnitCardScript.weak_against("artillery")).contains_exactly(["infantry"])

func test_numbers_come_from_the_config() -> void:
	for id in GameConfig.combat_unit_stats:
		var v: Dictionary = UnitCardScript.stat_values(id)
		var s: Dictionary = GameConfig.get_combat_stats(id)
		assert_int(int(v["max_hp"])).is_equal(int(s["hp"]))
		assert_int(int(v["atk"])).is_equal(int(s["atk"]))
		assert_int(int(v["move"])).is_equal(int(s["move"]))

func test_a_live_unit_shows_its_own_health() -> void:
	var u := CombatUnitScript.create(1, "infantry", 0, 1.0)
	u.hp = 40
	var v: Dictionary = UnitCardScript.stat_values("infantry", u)
	assert_int(int(v["hp"])).is_equal(40)

func test_artillery_says_its_minimum_range() -> void:
	var lines: Array = UnitCardScript.summary_lines("artillery")
	assert_bool(lines.has(Tr.t("LBL_CARD_TOO_CLOSE"))).is_true()
	assert_bool(UnitCardScript.summary_lines("infantry").has(Tr.t("LBL_CARD_TOO_CLOSE"))).is_false()

func test_the_card_builds_and_closes() -> void:
	var card = auto_free(UnitCardScript.new())
	add_child(card)
	var u := CombatUnitScript.create(1, "vehicle", 1, 1.0)
	card.setup("vehicle", u, true)
	await await_idle_frame()
	assert_object(card.find_child("CardClose", true, false)).is_not_null()
	assert_object(card.find_child("Matchup_good", true, false)).is_not_null()
	assert_object(card.find_child("Matchup_bad", true, false)).is_not_null()

func test_mult_text_uses_a_comma_in_spanish() -> void:
	var locale := Tr.get_locale()
	Tr.set_locale("es")
	assert_str(UnitCardScript.mult_text(1.5)).is_equal("×1,5")
	Tr.set_locale("en")
	assert_str(UnitCardScript.mult_text(1.5)).is_equal("×1.5")
	Tr.set_locale(locale)

func test_the_circle_has_one_arrow_per_win() -> void:
	assert_int(TypeCircleScript.arrows().size()).is_equal(3)
	assert_int(TypeCircleScript.circle_ids().size()).is_equal(3)

func test_combat_help_is_in_the_index_from_the_start() -> void:
	for id in ["guide_combat_units", "guide_combat_move", "guide_type_advantage",
			"guide_artillery_range", "guide_combat_previews", "guide_combat_defend"]:
		assert_bool(HelpCatalog.has(id)).is_true()
		assert_bool(HelpCatalog.is_basic(id)).is_true()
		assert_str(HelpCatalog.category(id)).is_equal(HelpCatalog.CAT_ARMY)
		assert_str(HelpCatalog.body(id)).is_not_empty()
