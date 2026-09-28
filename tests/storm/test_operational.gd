extends GdUnitTestSuite
## "En pie" tiene que significar lo mismo en todas partes.
##
## Habia dos definiciones —una en StormManager para la mitigacion, otra en
## CombatManager para las dotaciones— y **ninguna miraba la construccion**. Una
## torre a medio levantar mitigaba daño Y peleaba el Diezmo, asi que colocar
## torres justo antes de una tormenta pagaba sin haberlas terminado.
##
## Ahora la definicion vive en un solo sitio. Estos casos la fijan ahi.

var _node: Node3D = null

func before_test() -> void:
	_node = auto_free(Node3D.new())
	add_child(_node)

# ── La definicion ────────────────────────────────────────────────────

func test_a_building_with_no_marks_is_operational() -> void:
	assert_bool(BuildingHealth.is_operational(_node)).is_true()

func test_a_building_under_construction_is_not() -> void:
	# El exploit que cerraba: plantar torres al ver el aviso y que contaran ya.
	_node.set_meta("under_construction", true)
	assert_bool(BuildingHealth.is_operational(_node)).is_false()

func test_a_finished_building_counts_again() -> void:
	_node.set_meta("under_construction", true)
	_node.remove_meta("under_construction")
	assert_bool(BuildingHealth.is_operational(_node)).is_true()

func test_null_is_never_operational() -> void:
	assert_bool(BuildingHealth.is_operational(null)).is_false()

# ── Y sigue respetando lo que ya hacia ───────────────────────────────

func test_a_ruined_building_is_not_operational() -> void:
	_node.set_meta("health", 0)
	assert_bool(BuildingHealth.is_operational(_node)).is_false()

func test_damaged_but_standing_still_counts() -> void:
	# Media torre rota sigue siendo media torre: protege hasta que cae del todo.
	_node.set_meta("health", 1)
	assert_bool(BuildingHealth.is_operational(_node)).is_true()
	assert_bool(BuildingHealth.is_ruined(_node)).is_false()

func test_under_construction_beats_being_healthy() -> void:
	# Las dos condiciones son independientes: una obra a vida completa no cuenta.
	_node.set_meta("health", 999)
	_node.set_meta("under_construction", true)
	assert_bool(BuildingHealth.is_operational(_node)).is_false()
