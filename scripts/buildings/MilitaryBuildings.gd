extends RefCounted
## Edificios militares de la 1.2 (feat/edificios-militares): Enfermeria,
## Herreria militar y Campo de tiro. Consultas estaticas y baratas sobre el
## mapa; se llaman en el momento en que hacen falta (al acabar un combate, al
## empezar a entrenar, al abrir un simulacro), nunca por fotograma.
##
## "En marcha" = terminado, no en ruinas, unido al Nucleo y con su gente
## (las mismas metas que PopulationManager pone a todos: connected, staffed,
## workers_off). "Construido" = terminado, aunque este en ruinas o parado.

const INFIRMARY := "infirmary"
const SMITHY := "smithy"
const FIRING_RANGE := "firing_range"

## Cuantos `building_id` hay en marcha ahora mismo.
static func working_count(building_id: String) -> int:
	var n := 0
	for info in GridManager.buildings_view():
		var data: BuildingData = info.get("data")
		if data == null or data.id != building_id:
			continue
		if is_working(info.get("node")):
			n += 1
	return n

## Cuantos `building_id` hay terminados (en ruinas o sin gente tambien cuentan).
static func built_count(building_id: String) -> int:
	var n := 0
	for info in GridManager.buildings_view():
		var data: BuildingData = info.get("data")
		if data == null or data.id != building_id:
			continue
		var node: Node = info.get("node")
		if node != null and is_instance_valid(node) and not node.has_meta("under_construction"):
			n += 1
	return n

## Un edificio concreto, ¿en marcha?
static func is_working(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if not BuildingHealth.is_operational(node):
		return false
	if not bool(node.get_meta("connected", true)):
		return false
	if bool(node.get_meta("workers_off", false)):
		return false
	return bool(node.get_meta("staffed", true))

static func infirmary_working() -> bool:
	return working_count(INFIRMARY) > 0

static func firing_range_working() -> bool:
	return working_count(FIRING_RANGE) > 0

## La doctrina se aprende: vale mientras haya una Herreria terminada, aunque
## la Tormenta la deje en ruinas. Para CAMBIARLA si hace falta tenerla en marcha.
static func smithy_built() -> bool:
	return built_count(SMITHY) > 0

static func smithy_working() -> bool:
	return working_count(SMITHY) > 0

## Multiplicador del tiempo de entrenar (Campo de tiro en marcha: 0,8).
static func train_time_mult() -> float:
	return GameConfig.firing_range_train_mult if firing_range_working() else 1.0

## Moral por baja: la de la Enfermeria si hay una en marcha; -1 = la de siempre.
static func morale_per_casualty() -> float:
	return GameConfig.infirmary_morale_per_casualty if infirmary_working() else -1.0

## Multiplicador de la cura entre combates de una mision.
static func heal_mult() -> float:
	return GameConfig.infirmary_heal_mult if infirmary_working() else 1.0
