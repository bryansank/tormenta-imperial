extends GdUnitTestSuite
## A quién muerde la Tormenta primero, y a quién no puede morder nunca.
##
## Antes esto era `targets.shuffle()`: un impuesto plano repartido a suertes. El
## reparto por prioridad es lo que convierte el daño en una conversación —la
## Tormenta te quita el colchón de moral antes que el pan— y lo que impide que
## una mala racha temprana cierre la partida sin decirlo.
##
## Las decoraciones estaban excluidas y ahora encabezan la lista: romper una
## estatua es el golpe más legible que tiene la Tormenta.

const SPOTS: Array[Vector2i] = [
	Vector2i(2, 2), Vector2i(6, 2), Vector2i(10, 2), Vector2i(14, 2), Vector2i(18, 2),
	Vector2i(2, 8), Vector2i(6, 8), Vector2i(10, 8), Vector2i(14, 8), Vector2i(18, 8),
	Vector2i(2, 14), Vector2i(6, 14), Vector2i(10, 14), Vector2i(14, 14), Vector2i(18, 14),
]

var _placed: Array = []
var _next: int = 0

func before_test() -> void:
	_placed = []
	_next = 0

func after_test() -> void:
	# La rejilla es un autoload compartido: lo que una suite planta, la misma
	# suite lo levanta, o la siguiente hereda una base fantasma.
	for node in _placed:
		if is_instance_valid(node):
			GridManager.remove_building(node)
	_placed.clear()

# ── Utillería ────────────────────────────────────────────────────────

func _build(id: String) -> Node3D:
	var data: BuildingData = load("res://data/buildings/%s.tres" % id)
	var node: Node3D = auto_free(Node3D.new())
	node.name = "%s_%d" % [id, _next]
	assert_bool(GridManager.place_building(SPOTS[_next], data, node)).is_true()
	_next += 1
	_placed.append(node)
	return node

func _ruin(node: Node3D) -> void:
	BuildingHealth.damage_building(node, BuildingHealth.get_max_health(node))

func _tier(severity: int, index: int) -> Array:
	var tiers: Array = StormManager.damage_priority(severity)
	return tiers[index] if index < tiers.size() else []

func _every_target(severity: int) -> Array:
	var all: Array = []
	for tier in StormManager.damage_priority(severity):
		all.append_array(tier)
	return all

func _worst() -> int:
	return GameConfig.storm_severity_max

## La pertenencia se afirma a mano y no con el matcher de arrays de gdUnit: ese
## compara por valor y se enreda con listas de nodos. Lo que se mide aquí es la
## identidad del edificio, no su contenido.
func _hits(list: Array, node: Node3D) -> bool:
	return list.has(node)

# ── Escalón 1: la defensa y la moral ─────────────────────────────────

func test_decorations_are_no_longer_spared() -> void:
	# La decisión que revierte el comportamiento anterior: la estatua era
	# intocable y ahora es lo primero que cae.
	var statue := _build("statue")
	assert_bool(_hits(_tier(1, 0), statue)).is_true()

func test_towers_and_barracks_share_the_first_tier() -> void:
	var tower := _build("tower")
	var barracks := _build("barracks")
	assert_bool(_hits(_tier(1, 0), tower)).is_true()
	assert_bool(_hits(_tier(1, 0), barracks)).is_true()

func test_the_cushion_falls_before_the_roof() -> void:
	var fountain := _build("fountain")
	var house := _build("house")
	assert_bool(_hits(_tier(1, 0), fountain)).is_true()
	assert_bool(_hits(_tier(1, 0), house)).is_false()
	assert_bool(_hits(_tier(1, 1), house)).is_true()

# ── Escalón 3: la economía solo con severidad alta ───────────────────

func test_a_minor_storm_cannot_touch_production() -> void:
	# Sin esta regla, la primera mala racha deja al jugador sin fundición y sin
	# ventana para rehacerse: el ciclo dejaría de ser presión y pasaría a ser
	# una cuenta atrás.
	var foundry := _build("foundry")
	_build("warehouse")
	assert_bool(_hits(_every_target(1), foundry)).is_false()

func test_a_harsh_storm_puts_production_on_the_ledger() -> void:
	var foundry := _build("foundry")
	assert_bool(_hits(_every_target(GameConfig.storm_production_target_severity), foundry)).is_true()

func test_production_is_always_the_last_tier() -> void:
	var statue := _build("statue")
	var house := _build("house")
	var foundry := _build("foundry")
	var tiers: Array = StormManager.damage_priority(_worst())
	assert_int(tiers.size()).is_equal(3)
	assert_bool(_hits(tiers[0], statue)).is_true()
	assert_bool(_hits(tiers[1], house)).is_true()
	assert_bool(_hits(tiers[2], foundry)).is_true()

func test_the_threshold_is_the_only_thing_that_opens_the_third_tier() -> void:
	_build("foundry")
	assert_int(StormManager.damage_priority(
		GameConfig.storm_production_target_severity - 1).size()).is_equal(2)
	assert_int(StormManager.damage_priority(
		GameConfig.storm_production_target_severity).size()).is_equal(3)

# ── Lo intocable ─────────────────────────────────────────────────────

func test_the_core_is_never_a_target() -> void:
	# `BuildingHealth` ya lo blinda, pero un objetivo invulnerable en la lista
	# gastaría un mordisco del tic en no hacer nada.
	var core := _build("nucleo")
	assert_bool(_hits(_every_target(_worst()), core)).is_false()

func test_a_ruin_is_not_broken_twice() -> void:
	var statue := _build("statue")
	var other := _build("statue")
	_ruin(statue)
	assert_bool(_hits(_every_target(_worst()), statue)).is_false()
	assert_bool(_hits(_every_target(_worst()), other)).is_true()

# ── La regla anti-softlock ───────────────────────────────────────────

func test_the_last_sawmill_standing_is_untouchable() -> void:
	var sawmill := _build("sawmill")
	assert_bool(_hits(_every_target(_worst()), sawmill)).is_false()

func test_the_last_gold_mine_standing_is_untouchable() -> void:
	var mine := _build("gold_mine")
	assert_bool(_hits(_every_target(_worst()), mine)).is_false()

func test_with_two_sawmills_both_are_fair_game() -> void:
	# La regla protege la capacidad de rehacerse, no cada edificio: con dos,
	# perder uno no cierra ninguna puerta.
	var first := _build("sawmill")
	var second := _build("sawmill")
	assert_bool(_hits(_every_target(_worst()), first)).is_true()
	assert_bool(_hits(_every_target(_worst()), second)).is_true()

func test_a_ruined_sawmill_does_not_cover_for_the_one_still_standing() -> void:
	# El caso que se escapa si se cuenta por existencia en vez de por estar en
	# pie: un aserradero en ruinas sigue en la rejilla pero no produce nada.
	# Contarlo dejaría al jugador con dos serrerías muertas y sin madera con la
	# que reparar ninguna — el softlock exacto que la regla existe para evitar.
	var ruined := _build("sawmill")
	var standing := _build("sawmill")
	_ruin(ruined)
	assert_bool(_hits(_every_target(_worst()), standing)).is_false()

func test_the_rule_protects_each_trade_on_its_own() -> void:
	# Madera y oro son los dos recursos de la era 1: sin cualquiera de los dos
	# no hay forma de rehacerse, así que cada oficio cuenta sus propios pies.
	var spare := _build("sawmill")
	var last := _build("sawmill")
	var mine := _build("gold_mine")
	var targets: Array = _every_target(_worst())
	assert_bool(_hits(targets, spare)).is_true()
	assert_bool(_hits(targets, last)).is_true()
	assert_bool(_hits(targets, mine)).is_false()

# ── El reparto en marcha ─────────────────────────────────────────────

func test_the_storm_spends_every_bite_on_the_top_tier() -> void:
	var statues: Array = [_build("statue"), _build("statue"), _build("statue")]
	var house := _build("house")
	var sawmill := _build("sawmill")

	StormManager._damage_buildings(_worst())

	var bitten: int = 0
	for statue in statues:
		if BuildingHealth.is_damaged(statue):
			bitten += 1
	assert_int(bitten).is_equal(GameConfig.storm_buildings_hit_per_tick)
	assert_bool(BuildingHealth.is_damaged(house)).is_false()
	assert_bool(BuildingHealth.is_damaged(sawmill)).is_false()

func test_the_storm_drops_a_tier_when_the_one_above_runs_out() -> void:
	var statue := _build("statue")
	var house := _build("house")
	StormManager._damage_buildings(1)
	assert_bool(BuildingHealth.is_damaged(statue)).is_true()
	assert_bool(BuildingHealth.is_damaged(house)).is_true()

func test_a_base_of_nothing_but_lifelines_survives_the_worst_storm() -> void:
	# Un aserradero y una mina, ambos protegidos: la Tormenta no tiene a quién
	# morder y no puede inventarse una víctima.
	var sawmill := _build("sawmill")
	var mine := _build("gold_mine")
	StormManager._damage_buildings(_worst())
	assert_bool(BuildingHealth.is_damaged(sawmill)).is_false()
	assert_bool(BuildingHealth.is_damaged(mine)).is_false()
