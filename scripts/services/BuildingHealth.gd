extends Node
## Salud de los edificios: daño, ruina y reparación.
##
## Hasta ahora `BuildingData.max_health` existía y estaba poblado en los 14
## `.tres`, pero **ningún script lo leía**. Estaba el dato y faltaba el sistema.
## Aquí está el sistema.
##
## Un edificio dañado **no se destruye**: se queda en ruinas y deja de producir
## hasta que se paga la reparación. Es una decisión de diseño, no una limitación —
## en un city builder sin deshacer, borrarle a alguien una fundición que le costó
## media partida es como se pierde a un jugador.
##
## El estado vive en el propio nodo (`health`), igual que `level` y
## `under_construction`, y viaja en el guardado con el resto del edificio.

func get_max_health(node: Node) -> int:
	var info := GridManager.get_building_info(node)
	if info.is_empty():
		return 1
	var data: BuildingData = info["data"]
	return maxi(1, data.max_health)

func get_health(node: Node) -> int:
	if node == null or not is_instance_valid(node):
		return 0
	return int(node.get_meta("health", get_max_health(node)))

func get_health_ratio(node: Node) -> float:
	return clampf(float(get_health(node)) / float(maxi(1, get_max_health(node))), 0.0, 1.0)

## En ruinas: sigue ocupando su sitio, pero no produce nada hasta repararlo.
func is_ruined(node: Node) -> bool:
	return get_health(node) <= 0

## En pie y funcionando: ni en ruinas ni a medio construir.
##
## Es la definicion unica de "cuenta" para todo el que mire edificios. Habia dos
## copias —una en StormManager para la mitigacion y otra en CombatManager para
## las dotaciones— y ninguna miraba la construccion, asi que una torre a medio
## levantar mitigaba daño Y peleaba el Diezmo: colocar torres justo antes de una
## tormenta pagaba sin haberlas terminado.
func is_operational(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node.has_meta("under_construction"):
		return false
	return not is_ruined(node)

func is_damaged(node: Node) -> bool:
	return get_health(node) < get_max_health(node)

## El Núcleo es el suelo de la partida: se puede caer hasta el fondo, pero
## siempre queda un hilo del que tirar. El guard vive aquí y no en quien golpea
## para que ninguna fuente de daño futura —torres enemigas, eventos, el Diezmo—
## tenga que acordarse de filtrarlo.
func is_core(node: Node) -> bool:
	var info := GridManager.get_building_info(node)
	if info.is_empty():
		return false
	var data: BuildingData = info["data"]
	return data.is_core

## Lo que ningun dano toca: el Nucleo y las carreteras (2026-09-28). La red une
## cada edificio al Nucleo; una calle en ruinas no dejaria nada que reparar y
## la tormenta se gastaba en la acera en vez de en la base.
func is_immune(node: Node) -> bool:
	if is_core(node):
		return true
	var info := GridManager.get_building_info(node)
	return not info.is_empty() and (info["data"] as BuildingData).id == "road"

# ── Daño ─────────────────────────────────────────────────────────────

## Devuelve true si este golpe lo dejó en ruinas.
func damage_building(node: Node, amount: int) -> bool:
	if node == null or not is_instance_valid(node) or amount <= 0:
		return false
	if is_immune(node):
		return false
	if is_ruined(node):
		return false
	var health: int = maxi(0, get_health(node) - amount)
	node.set_meta("health", health)
	_apply_visual(node)
	EventBus.building_damaged.emit(node, health, get_max_health(node))
	if health <= 0:
		EventBus.building_ruined.emit(node)
		return true
	return false

# ── Reparación ───────────────────────────────────────────────────────

## Cuesta en proporción a lo que falta: un rasguño es barato, una ruina casi
## cuesta construirla de nuevo.
##
## Indexado por `ResourceManager.Type`, como `BuildingData.get_cost()` y como todo
## lo que se paga en este juego. Antes devolvia nombres de texto, y como
## `can_afford()` espera el enum, `has_enough()` reventaba con un error de tipos
## en cada comprobacion: `can_repair()` contestaba que no habia recursos siempre,
## asi que el boton REPARAR estaba muerto aunque el panel pintara el precio
## correcto justo encima. Media Tormenta era irreversible.
func repair_cost(node: Node) -> Dictionary:
	var info := GridManager.get_building_info(node)
	if info.is_empty():
		return {}
	var data: BuildingData = info["data"]
	var missing: float = 1.0 - get_health_ratio(node)
	if missing <= 0.0:
		return {}
	var factor: float = missing * GameConfig.storm_repair_cost_ratio
	var cost: Dictionary = {}
	var full: Dictionary = data.get_base_cost()
	for type in full:
		var amount: int = roundi(float(full[type]) * factor)
		if amount > 0:
			cost[type] = amount
	return cost

func can_repair(node: Node) -> Dictionary:
	if not is_damaged(node):
		return {"ok": false, "reason": "MSG_REPAIR_NOT_NEEDED"}
	var cost := repair_cost(node)
	if not ResourceManager.can_afford(cost):
		return {"ok": false, "reason": "MSG_REPAIR_NO_RESOURCES"}
	return {"ok": true, "reason": ""}

func repair(node: Node) -> bool:
	var check := can_repair(node)
	if not check["ok"]:
		return false
	if not ResourceManager.spend_cost(repair_cost(node)):
		return false
	node.set_meta("health", get_max_health(node))
	_apply_visual(node)
	EventBus.building_repaired.emit(node)
	return true

## Cura `amount` sin cobrar (el Pozo tras la Tormenta, 1.1). No levanta una
## ruina: eso es la reparacion pagada. Devuelve lo curado de verdad. No emite
## building_damaged (el parte del asedio lo cuenta como golpe); solo
## building_repaired si queda entero.
func heal(node: Node, amount: int) -> int:
	if node == null or not is_instance_valid(node) or amount <= 0 or is_ruined(node):
		return 0
	var before := get_health(node)
	var after: int = mini(get_max_health(node), before + amount)
	if after == before:
		return 0
	node.set_meta("health", after)
	_apply_visual(node)
	if after >= get_max_health(node):
		EventBus.building_repaired.emit(node)
	return after - before

# ── Aspecto ──────────────────────────────────────────────────────────

## Un edificio herido se cubre de ceniza; en ruinas queda casi negro. Sin esto el
## jugador no sabe qué reparar sin ir clicando uno por uno.
##
## Se hace con `material_overlay` en vez de tocar el albedo: los edificios son
## modelos GLB con sus propios materiales, y sobrescribirlos les borraría la
## textura. La capa se pinta encima y se quita poniéndola a null.
##
## La capa es compartida (docs/26 §6 punto 8): antes cada golpe creaba un
## `StandardMaterial3D` nuevo, y tras una Tormenta habia un material unico por
## edificio herido (el motor no puede agruparlos). Ahora la ceniza va en
## `ASH_LEVELS` escalones, cada uno un solo material para toda la isla. El
## escalon se redondea hacia arriba: un rasguño sigue viendose, y la ruina es el
## mismo casi negro (0,75 de opacidad) de siempre.
const ASH_LEVELS := 8
const ASH_MAX_ALPHA := 0.75
static var _ash_materials: Array = []

func _apply_visual(node: Node) -> void:
	var ratio: float = get_health_ratio(node)
	var overlay: StandardMaterial3D = null
	if ratio < 1.0:
		overlay = ash_material(ratio)
	for mesh in _meshes_of(node):
		if mesh.material_overlay != overlay:
			mesh.material_overlay = overlay

## La capa de ceniza para una proporcion de vida (< 1), de la cache.
static func ash_material(ratio: float) -> StandardMaterial3D:
	if _ash_materials.is_empty():
		for i in range(ASH_LEVELS + 1):
			_ash_materials.append(null)
	var level: int = clampi(ceili((1.0 - clampf(ratio, 0.0, 1.0)) * ASH_LEVELS - 0.0001), 1, ASH_LEVELS)
	var mat: StandardMaterial3D = _ash_materials[level]
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Cuanto menos vida, más ceniza encima.
		mat.albedo_color = Color(0.10, 0.09, 0.08, float(level) / ASH_LEVELS * ASH_MAX_ALPHA)
		_ash_materials[level] = mat
	return mat

func _meshes_of(node: Node) -> Array:
	var found: Array = []
	for child in node.get_children():
		# La obra, los escombros y el humo (BuildingLookVisual) llevan su propio
		# color: con la capa de ceniza encima, el humo seria un cuadro negro.
		if child.is_in_group("building_fx"):
			continue
		if child is MeshInstance3D:
			found.append(child)
		if child.get_child_count() > 0:
			found.append_array(_meshes_of(child))
	return found

## Reaplica el aspecto tras cargar partida, cuando la malla ya existe.
func refresh_visual(node: Node) -> void:
	_apply_visual(node)
