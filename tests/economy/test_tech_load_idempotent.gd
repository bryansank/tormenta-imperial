extends GdUnitTestSuite
## Cargar el arbol tecnologico dos veces sin reset() de por medio tiene que dejar
## los mismos bonos que cargarlo una vez. Los bonos se derivan de lo investigado,
## no se acumulan: si no, cada recarga que conserva la partida (cambio de idioma,
## cambio de vista, carga desde la nube) los multiplicaria en cuanto un camino se
## olvidara del reset().

var _saved: Dictionary = {}

## Una tecnologia de cada tipo de bono que toca GameConfig.
const DATA := {
	"researched": {
		"ind_1": true, "ind_2": true, "ind_3": true, "ind_4": true, "ind_5": true,
		"mil_1": true, "mil_2": true, "mil_3": true, "mil_4": true, "mil_5": true,
		"log_1": true, "log_2": true, "log_3": true, "log_4": true, "log_5": true,
	},
	"researching": {},
}

func before_test() -> void:
	_saved = TechTreeManager.get_save_data()
	TechTreeManager.reset()

func after_test() -> void:
	TechTreeManager.reset()
	TechTreeManager.load_save_data(_saved)

func _snapshot() -> Dictionary:
	return {
		"production": GameConfig.tech_production_bonus,
		"storage": GameConfig.tech_storage_bonus,
		"consumption": GameConfig.tech_consumption_reduction,
		"build_speed": GameConfig.tech_build_speed_bonus,
		"spread": GameConfig.market_spread,
		"morale": GameConfig.morale_satisfied_recovery,
	}

func test_the_fixture_touches_every_bonus() -> void:
	var before := _snapshot()
	TechTreeManager.load_save_data(DATA.duplicate(true))
	var after := _snapshot()
	for key in before:
		assert_bool(before[key] != after[key]).override_failure_message(
			"el bono %s no cambia con el arbol entero: el test no lo cubre" % key).is_true()

func test_loading_twice_gives_the_same_bonuses_as_loading_once() -> void:
	TechTreeManager.load_save_data(DATA.duplicate(true))
	var once := _snapshot()
	TechTreeManager.load_save_data(DATA.duplicate(true))
	assert_dict(_snapshot()).is_equal(once)

func test_loading_a_smaller_tree_drops_the_bonuses_it_no_longer_has() -> void:
	TechTreeManager.load_save_data(DATA.duplicate(true))
	TechTreeManager.load_save_data({"researched": {}, "researching": {}})
	var loaded_empty := _snapshot()
	TechTreeManager.reset()
	assert_dict(loaded_empty).is_equal(_snapshot())
