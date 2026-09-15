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

func get_max_health(node: Node3D) -> int:
	var info := GridManager.get_building_info(node)
	if info.is_empty():
		return 1
	var data: BuildingData = info["data"]
	return maxi(1, data.max_health)

func get_health(node: Node3D) -> int:
	if node == null or not is_instance_valid(node):
		return 0
	return int(node.get_meta("health", get_max_health(node)))

func get_health_ratio(node: Node3D) -> float:
	return clampf(float(get_health(node)) / float(maxi(1, get_max_health(node))), 0.0, 1.0)

## En ruinas: sigue ocupando su sitio, pero no produce nada hasta repararlo.
func is_ruined(node: Node3D) -> bool:
	return get_health(node) <= 0

## En pie y funcionando: ni en ruinas ni a medio construir.
##
## Es la definicion unica de "cuenta" para todo el que mire edificios. Habia dos
## copias —una en StormManager para la mitigacion y otra en CombatManager para
## las dotaciones— y ninguna miraba la construccion, asi que una torre a medio
## levantar mitigaba daño Y peleaba el Diezmo: colocar torres justo antes de una
## tormenta pagaba sin haberlas terminado.
func is_operational(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node.has_meta("under_construction"):
		return false
	return not is_ruined(node)

func is_damaged(node: Node3D) -> bool:
	return get_health(node) < get_max_health(node)

## El Núcleo es el suelo de la partida: se puede caer hasta el fondo, pero
## siempre queda un hilo del que tirar. El guard vive aquí y no en quien golpea
## para que ninguna fuente de daño futura —torres enemigas, eventos, el Diezmo—
## tenga que acordarse de filtrarlo.
func is_core(node: Node3D) -> bool:
	var info := GridManager.get_building_info(node)
	if info.is_empty():
		return false
	var data: BuildingData = info["data"]
	return data.is_core

# ── Daño ─────────────────────────────────────────────────────────────

## Devuelve true si este golpe lo dejó en ruinas.
func damage_building(node: Node3D, amount: int) -> bool:
	if node == null or not is_instance_valid(node) or amount <= 0:
		return false
	if is_core(node):
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
func repair_cost(node: Node3D) -> Dictionary:
	var info := GridManager.get_building_info(node)
	if info.is_empty():
		return {}
	var data: BuildingData = info["data"]
	var missing: float = 1.0 - get_health_ratio(node)
	if missing <= 0.0:
		return {}
	var factor: float = missing * GameConfig.storm_repair_cost_ratio
	var cost: Dictionary = {}
	for pair in [["gold", data.cost_gold], ["steel", data.cost_steel],
			["oil", data.cost_oil], ["wood", data.cost_wood]]:
		var amount: int = roundi(float(pair[1]) * factor)
		if amount > 0:
			cost[pair[0]] = amount
	return cost

func can_repair(node: Node3D) -> Dictionary:
	if not is_damaged(node):
		return {"ok": false, "reason": "MSG_REPAIR_NOT_NEEDED"}
	var cost := repair_cost(node)
	if not ResourceManager.can_afford(cost):
		return {"ok": false, "reason": "MSG_REPAIR_NO_RESOURCES"}
	return {"ok": true, "reason": ""}

func repair(node: Node3D) -> bool:
	var check := can_repair(node)
	if not check["ok"]:
		return false
	if not ResourceManager.spend_cost(repair_cost(node)):
		return false
	node.set_meta("health", get_max_health(node))
	_apply_visual(node)
	EventBus.building_repaired.emit(node)
	return true

# ── Aspecto ──────────────────────────────────────────────────────────

## Un edificio herido se cubre de ceniza; en ruinas queda casi negro. Sin esto el
## jugador no sabe qué reparar sin ir clicando uno por uno.
##
## Se hace con `material_overlay` en vez de tocar el albedo: los edificios son
## modelos GLB con sus propios materiales, y sobrescribirlos les borraría la
## textura. La capa se pinta encima y se quita poniéndola a null.
func _apply_visual(node: Node3D) -> void:
	var ratio: float = get_health_ratio(node)
	var overlay: StandardMaterial3D = null
	if ratio < 1.0:
		overlay = StandardMaterial3D.new()
		overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Cuanto menos vida, más ceniza encima.
		overlay.albedo_color = Color(0.10, 0.09, 0.08, (1.0 - ratio) * 0.75)
	for mesh in _meshes_of(node):
		mesh.material_overlay = overlay

func _meshes_of(node: Node) -> Array:
	var found: Array = []
	for child in node.get_children():
		if child is MeshInstance3D:
			found.append(child)
		if child.get_child_count() > 0:
			found.append_array(_meshes_of(child))
	return found

## Reaplica el aspecto tras cargar partida, cuando la malla ya existe.
func refresh_visual(node: Node3D) -> void:
	_apply_visual(node)
