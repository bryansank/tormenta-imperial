extends GdUnitTestSuite
## El contador de puntos de investigacion era vestigial y se quito. Un guardado
## viejo que todavia lo trae tiene que cargar igual, y el nuevo ya no lo escribe.

var _saved: Dictionary = {}

func before_test() -> void:
	_saved = TechTreeManager.get_save_data()
	TechTreeManager.reset()

func after_test() -> void:
	TechTreeManager.reset()
	TechTreeManager.load_save_data(_saved)

func test_the_save_no_longer_carries_research_points() -> void:
	assert_bool(TechTreeManager.get_save_data().has("research_points")).is_false()

func test_an_old_save_with_research_points_still_loads() -> void:
	TechTreeManager.load_save_data({
		"researched": {"log_1": true}, "researching": {}, "research_points": 42})
	assert_bool(TechTreeManager.is_researched("log_1")).is_true()
	assert_bool(TechTreeManager.get_save_data().has("research_points")).is_false()

func test_a_first_tier_tech_needs_no_hq() -> void:
	var saved_res := {}
	for type in ResourceManager.get_all():
		saved_res[ResourceManager.get_type_name(type)] = ResourceManager.get_amount(type)
	ResourceManager.set_amounts({"gold": 300, "wood": 200, "steel": 0, "oil": 0})
	assert_bool(TechTreeManager.can_research("log_1")).is_true()
	ResourceManager.set_amounts(saved_res)
