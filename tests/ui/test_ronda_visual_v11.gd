extends GdUnitTestSuite
## Ronda visual de la 1.1 (capturas): las reglas puras de colocacion y dibujo
## que se arreglaron mirando las sondas.

const BattleScreenScript := preload("res://scripts/ui/BattleScreen.gd")
const InstructorBust := preload("res://scripts/ui/InstructorBust.gd")
const TitleMenuScript := preload("res://scripts/ui/TitleMenu.gd")
const StormHUDScript := preload("res://scripts/ui/StormHUD.gd")
const BoardTerrain := preload("res://scripts/combat_view/BoardTerrain3D.gd")
const Rules := preload("res://scripts/combat/CombatRules.gd")

func test_the_mission_map_icon_is_the_unit_the_enemy_brings_most_of() -> void:
	assert_str(BattleScreenScript.node_lead_unit({"enemy_roster": {"gunboat": 1, "torpedo_boat": 3}})).is_equal("torpedo_boat")
	assert_str(BattleScreenScript.node_lead_unit({"enemy_roster": {"fighter": 2}})).is_equal("fighter")
	assert_str(BattleScreenScript.node_lead_unit({})).is_equal("infantry")

func test_an_islet_is_land_touching_water_and_a_coast_is_not() -> void:
	var sea: Dictionary = Rules.open_sea_terrain(Vector2i(8, 8), 777, 3)
	var islets := 0
	for cell in sea:
		if BattleScreenScript.is_islet(sea, cell):
			islets += 1
	assert_int(islets).is_equal(3)
	var coast: Dictionary = Rules.coastal_terrain(Vector2i(8, 8), 4)
	for cell in coast:
		assert_bool(BattleScreenScript.is_islet(coast, cell)).is_false()
	assert_bool(BattleScreenScript.is_islet({}, Vector2i(1, 1))).is_false()

func test_open_sea_is_told_apart_from_a_coast() -> void:
	assert_bool(BoardTerrain.is_open_sea(Rules.open_sea_terrain(Vector2i(8, 8), 5, 3))).is_true()
	assert_bool(BoardTerrain.is_open_sea(Rules.coastal_terrain(Vector2i(8, 8), 5))).is_false()
	assert_bool(BoardTerrain.is_open_sea({})).is_false()

func test_a_centred_card_steps_right_of_the_storm_column() -> void:
	var vp := Vector2(984, 554)
	var storm := Rect2(8, 120, 280, 260)
	var shift := InstructorBust.centered_card_shift(vp, 360.0, storm, 300.0)
	assert_float(vp.x * 0.5 - 180.0 + shift).is_greater_equal(storm.end.x)
	assert_float(vp.x * 0.5 + 180.0 + shift).is_less_equal(vp.x - InstructorBust.EDGE)
	# Arriba en el centro (PC) y la tarjeta por debajo: no se mueve.
	assert_float(InstructorBust.centered_card_shift(Vector2(1280, 720), 460.0, Rect2(450, 8, 380, 280), 400.0)).is_equal(0.0)
	# Sin Tormenta, nada.
	assert_float(InstructorBust.centered_card_shift(vp, 360.0, Rect2(), 300.0)).is_equal(0.0)

func test_the_title_card_never_lifts_past_the_top() -> void:
	assert_float(TitleMenuScript.title_card_lift(720.0, 400.0)).is_equal(60.0)
	var lift := TitleMenuScript.title_card_lift(554.0, 500.0)
	assert_float((554.0 - 500.0) * 0.5 - lift).is_greater_equal(ModalKit.EDGE - 0.01)
	assert_float(TitleMenuScript.title_card_lift(400.0, 600.0)).is_equal(0.0)

func test_the_order_card_stops_at_the_bottom_edge() -> void:
	assert_float(StormHUDScript.order_card_height(200.0, 500.0)).is_equal(200.0)
	assert_float(StormHUDScript.order_card_height(300.0, 180.0)).is_equal(180.0)
	assert_float(StormHUDScript.order_card_height(300.0, 20.0)).is_equal(90.0)
