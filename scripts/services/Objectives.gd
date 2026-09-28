extends RefCounted
## El siguiente paso de la campana, calculado desde la partida tal como esta.
##
## Es la unica respuesta del juego a "¿y ahora que hago?". La lee el panel
## ¿QUE HACER? y la lee `tools/line_probe.gd`, que juega la campana entera
## siguiendola al pie de la letra: si la sonda llega a la victoria obedeciendo
## esto, el panel nunca le dice al jugador algo falso ni algo que no puede hacer.
## Ver docs/22-linea-jugable.md.
##
## Sin estado y sin senales: solo pregunta a los servicios. No es un modelo puro
## del combate (lee autoloads), es una consulta, como `PlacementRules`.
##
## Un paso es un Dictionary:
##   kind  "build" | "upgrade" | "train" | "repair" | "siege" | "resummon" | "rebuild" | "sandbox"
##   id    edificio o unidad
##   level nivel al que sube una mejora
##   why   clave de Tr con el porque (una frase)

const Rules := preload("res://scripts/buildings/PlacementRules.gd")

## El camino recomendado, en orden. Cada entrada se da por hecha cuando hay al
## menos `count` en pie (o en obras). Es el mismo orden que la guia
## (docs/14-guia-de-juego.md, seccion 10) y que la intro del tutorial.
const LINE := [
	{"kind": "build", "id": "sawmill", "count": 1, "why": "OBJ_WHY_SAWMILL"},
	{"kind": "build", "id": "gold_mine", "count": 1, "why": "OBJ_WHY_GOLD_MINE"},
	{"kind": "build", "id": "house", "count": 1, "why": "OBJ_WHY_HOUSE"},
	{"kind": "build", "id": "sawmill", "count": 2, "why": "OBJ_WHY_SAWMILL_2"},
	{"kind": "build", "id": "warehouse", "count": 1, "why": "OBJ_WHY_WAREHOUSE"},
	{"kind": "build", "id": "foundry", "count": 1, "why": "OBJ_WHY_FOUNDRY"},
	{"kind": "build", "id": "barracks", "count": 1, "why": "OBJ_WHY_BARRACKS"},
	# Guarnicion: cinco unidades en casa, de lo que sea, con dos canones. Tres
	# infantes solos pierden el Diezmo YA en severidad 1 (2 infantes y 1 canon de
	# escolta); tres infantes y dos canones lo ganan hasta severidad 3 sin torres y
	# hasta la 5 con dos torres en pie (tabla en docs/22-linea-jugable.md). Cuenta
	# cualquier tropa: los blindados del final tambien son guarnicion.
	{"kind": "train", "id": "infantry", "count": GARRISON_UNITS, "any": true, "why": "OBJ_WHY_GARRISON"},
	{"kind": "build", "id": "refinery", "count": 1, "why": "OBJ_WHY_REFINERY"},
	{"kind": "build", "id": "tower", "count": 2, "why": "OBJ_WHY_TOWERS"},
	{"kind": "build", "id": "headquarters", "count": 1, "why": "OBJ_WHY_HQ"},
	{"kind": "upgrade", "id": "headquarters", "level": 2, "why": "OBJ_WHY_HQ_2"},
	{"kind": "train", "id": "vehicle", "count": 6, "why": "OBJ_WHY_ARMOUR"},
	{"kind": "upgrade", "id": "headquarters", "level": 3, "why": "OBJ_WHY_HQ_3"},
]

## La guarnicion de referencia para bajar a la Regencia: el tope de despliegue en
## blindados, que es la que gana la mayoria de asedios (docs/17-balance-asedio.md).
const SIEGE_VEHICLES := 6
## Guarnicion minima para el Diezmo, y cuantos canones lleva dentro.
const GARRISON_UNITS := 5
const GARRISON_GUNS := 2

## Por debajo de este saldo por segundo el paso siguiente es otro productor.
const MIN_NET_PER_SECOND := 0.05
## Si lo que falta para el paso tarda mas que esto en llegar, un productor mas
## del recurso que frena es mejor inversion que esperar.
const SLOW_RESOURCE_SECONDS := 360.0
## Bolsa casi llena: por encima de esta fraccion se pide otro almacen.
const FULL_BAG := 0.9

const PRODUCER_OF := {
	"gold": "gold_mine",
	"wood": "sawmill",
	"steel": "foundry",
	"oil": "refinery",
}

# ══════════════════════════════════════════════════════════════════════
# El paso
# ══════════════════════════════════════════════════════════════════════

static func next_step() -> Dictionary:
	# ── Despues del final ──
	if StormManager.is_halted():
		return {"kind": "sandbox", "why": "OBJ_WHY_SANDBOX"}

	# ── El asedio ──
	# Reconvocar se puede con 3 unidades, pero 3 unidades no ganan nunca
	# (docs/17-balance-asedio.md): el paso honesto es rehacer la guarnicion que si
	# gana, y solo entonces volver a llamarlos.
	if ProgressionManager.is_final_audit_active():
		return {"kind": "siege", "why": "OBJ_WHY_SIEGE"}
	if ProgressionManager.is_final_audit_lost():
		var rebuild: Dictionary = _siege_army_step("OBJ_WHY_REBUILD", "rebuild")
		if not rebuild.is_empty():
			return _support_or(rebuild)
		if ProgressionManager.can_resummon_final_audit():
			return {"kind": "resummon", "why": "OBJ_WHY_RESUMMON"}
		return _support_or(_army_step("infantry", GameConfig.final_audit_resummon_min_units, "OBJ_WHY_REBUILD", "rebuild"))
	if ProgressionManager.is_final_audit_pending():
		var fill: Dictionary = _siege_army_step("OBJ_WHY_ARMOUR_BEFORE_SIEGE", "train")
		if not fill.is_empty():
			return _support_or(fill)
		return {"kind": "siege", "why": "OBJ_WHY_SIEGE"}

	# ── La linea ──
	var target: Dictionary = _first_open_line_step()
	if target.is_empty():
		return {"kind": "sandbox", "why": "OBJ_WHY_SANDBOX"}

	# Antes del paso, lo que lo haria imposible o absurdo: comer, obreros, bolsa.
	return _support_or(target)

static func _support_or(target: Dictionary) -> Dictionary:
	var support: Dictionary = _support_step(target)
	if support.is_empty():
		return target
	# El paso de apoyo tiene que poder darse el tambien: otro aserradero sin
	# obreros para atenderlo es un consejo que el juego rechaza al hacer clic.
	var hands: Dictionary = _workers_step(support)
	return hands if not hands.is_empty() else support

## Una casa, si `step` pide obreros que no hay ni van a nacer. {} si no hace falta.
static func _workers_step(step: Dictionary) -> Dictionary:
	var workers_needed: int = _workers_for(step)
	if workers_needed <= PopulationManager.get_free_workers() or not _houses_would_help(workers_needed):
		return {}
	return _build_step("house", "OBJ_WHY_MORE_WORKERS")

## Blindados que faltan en casa para la guarnicion de referencia del asedio, o {}
## si ya estan (contando los que se entrenan).
static func _siege_army_step(why: String, kind: String) -> Dictionary:
	var wanted: int = SIEGE_VEHICLES
	if _army_count("vehicle") - int(CombatManager.get_units_away().get("vehicle", 0)) >= wanted:
		return {}
	return _army_step("vehicle", wanted, why, kind)

## El primer paso de la linea que no esta hecho.
static func _first_open_line_step() -> Dictionary:
	for entry in LINE:
		match String(entry["kind"]):
			"build":
				if Rules.count_building(String(entry["id"])) < int(entry["count"]):
					return entry.duplicate()
			"upgrade":
				var node: Node = _first_building(String(entry["id"]))
				if node == null:
					return {"kind": "build", "id": String(entry["id"]), "count": 1, "why": "OBJ_WHY_HQ"}
				var level: int = int(node.get_meta("level", 1))
				var target_level: int = ProductionManager.get_upgrade_target(node)
				if maxi(level, target_level) < int(entry["level"]):
					return entry.duplicate()
			"train":
				if _train_progress(entry) < int(entry["count"]):
					var step := _army_step(_garrison_unit(entry), int(entry["count"]), String(entry["why"]), "train")
					step["any"] = bool(entry.get("any", false))
					return step
	return {}

## Que se entrena para un paso de guarnicion: canones hasta tener los que pide,
## luego infanteria. Un paso de un solo tipo entrena ese tipo.
static func _garrison_unit(entry: Dictionary) -> String:
	if not bool(entry.get("any", false)):
		return String(entry["id"])
	if ArmyManager.is_unlocked("artillery") and _army_count("artillery") < GARRISON_GUNS:
		return "artillery"
	return String(entry["id"])

## Cuantas unidades cuentan para un paso de tropa: las de su tipo, o todas si el
## paso es de guarnicion ("any"). Incluye las que se estan entrenando.
static func _train_progress(entry: Dictionary) -> int:
	if bool(entry.get("any", false)):
		var total: int = ArmyManager.get_training().size()
		for unit_id in GameConfig.get_unit_ids():
			total += ArmyManager.get_count(unit_id)
		return total
	return _army_count(String(entry["id"]))

## Lo que tiene que ir antes del paso de la linea, en este orden:
##   1. el oro o la madera no dan para comer: otra mina / otro aserradero;
##   2. el paso pide obreros que no hay y no va a haber: una casa;
##   3. el paso no cabe en la bolsa, o la bolsa esta a rebosar: un almacen;
##   4. lo que falta tarda demasiado en llegar: otro productor de ese recurso.
static func _support_step(target: Dictionary) -> Dictionary:
	# 0. Lo que da de comer esta en ruinas: repararlo antes que levantar otro.
	var ruined: Node = _ruined_producer()
	if ruined != null:
		return {"kind": "repair", "id": (GridManager.get_building_info(ruined)["data"] as BuildingData).id,
			"why": "OBJ_WHY_REPAIR"}
	var net: Dictionary = net_rates()
	# Mientras la gente no come (Fundacion) no hay saldo que vigilar: la linea
	# empieza por el aserradero, no por una mina que nadie necesita todavia.
	var eating: bool = ProgressionManager.current_phase >= GameConfig.Phase.SETTLEMENT
	for res in ["gold", "wood"]:
		if eating and float(net[res]) < MIN_NET_PER_SECOND:
			var fix: Dictionary = _producer_step(res, "OBJ_WHY_FEED_%s" % res.to_upper())
			if not fix.is_empty() and String(fix["id"]) != String(target.get("id", "")):
				return fix

	var house: Dictionary = _workers_step(target)
	if not house.is_empty():
		return house

	var cost_total: int = _cost_total(step_cost(target))
	var cap: int = ResourceManager.get_storage_cap()
	# La bolsa llena solo pide almacen cuando la linea ya paso por el primero: el
	# primer Almacen es el interruptor de la fase Supervivencia (consumo al doble,
	# castigo de moral y eventos), y adelantarlo por 60 de oro que sobran es la
	# trampa que la guia avisa de no pisar. Antes de eso, lo que sobra se gasta.
	var full: bool = Rules.count_building("warehouse") > 0 \
		and ResourceManager.get_total_stored() >= int(float(cap) * FULL_BAG)
	if (cost_total > cap or full) and String(target.get("id", "")) != "warehouse":
		var wh := _build_step("warehouse", "OBJ_WHY_BAG_TOO_SMALL" if cost_total > cap else "OBJ_WHY_BAG_FULL")
		if not wh.is_empty():
			return wh

	var slow: String = _slowest_missing(target, net)
	if slow != "":
		var more: Dictionary = _producer_step(slow, "OBJ_WHY_SLOW_%s" % slow.to_upper())
		if not more.is_empty() and String(more["id"]) != String(target.get("id", "")):
			return more
	return {}

# ══════════════════════════════════════════════════════════════════════
# Cuentas
# ══════════════════════════════════════════════════════════════════════

## Saldo por segundo de cada recurso con lo que hay en pie ahora mismo: produccion
## (con moral, nivel y tecnologia) menos lo que come la gente y cobra la tropa.
## Sin la Tormenta: es la cuenta de un dia normal, no la del peor.
static func net_rates() -> Dictionary:
	var rates := {"gold": 0.0, "wood": 0.0, "steel": 0.0, "oil": 0.0}
	var morale_mult: float = PopulationManager.get_morale_multiplier()
	for info in GridManager.get_all_buildings():
		var data: BuildingData = info["data"]
		var node: Node = info["node"]
		if not data.is_producer() or data.production_interval <= 0.0:
			continue
		if BuildingHealth.is_ruined(node):
			continue
		# Lo que esta en obras cuenta como si ya produjera: va a hacerlo en
		# segundos, y sin esto el paso pediria una segunda mina mientras la
		# primera aun se esta levantando.
		var building: bool = node.has_meta("under_construction")
		if not building and data.workers_required > 0 and not PopulationManager.is_building_staffed(node):
			continue
		var level: int = int(node.get_meta("level", 1))
		var mult: float = (GameConfig.get_production_multiplier(level) + GameConfig.tech_production_bonus) * morale_mult
		var interval: float = data.production_interval
		rates["gold"] += float(data.produces_gold) * mult / interval
		rates["wood"] += float(data.produces_wood) * mult / interval
		rates["steel"] += float(data.produces_steel) * mult / interval
		rates["oil"] += float(data.produces_oil) * mult / interval
	if ProgressionManager.current_phase >= GameConfig.Phase.SETTLEMENT:
		var early: bool = ProgressionManager.current_phase < GameConfig.Phase.SURVIVAL
		var interval: float = GameConfig.early_consumption_interval if early else GameConfig.consumption_interval
		var eat: float = float(PopulationManager.get_population()) \
			* maxf(0.1, 1.0 - GameConfig.tech_consumption_reduction) / interval
		rates["gold"] -= eat
		rates["wood"] -= eat
	var upkeep := 0
	for unit_id in GameConfig.get_unit_ids():
		upkeep += ArmyManager.get_count(unit_id) * int(GameConfig.get_unit_def(unit_id).get("upkeep_gold", 0))
	rates["gold"] -= float(upkeep) / GameConfig.army_upkeep_interval
	return rates

## Lo que cuesta el paso, indexado por ResourceManager.Type. Vacio si no cuesta.
static func step_cost(step: Dictionary) -> Dictionary:
	match String(step.get("kind", "")):
		"build":
			var data: BuildingData = Rules.load_building_data(String(step["id"]))
			return data.get_cost() if data != null else {}
		"upgrade":
			var data: BuildingData = Rules.load_building_data(String(step["id"]))
			return GameConfig.get_upgrade_cost(data, int(step["level"])) if data != null else {}
		"train", "rebuild":
			var cost: Dictionary = {}
			var raw: Dictionary = GameConfig.get_unit_def(String(step["id"])).get("cost", {})
			for res_name in raw:
				cost[ResourceManager.name_to_type(res_name)] = int(raw[res_name])
			return cost
	return {}

## Lo que falta para pagar el paso, por nombre de recurso. Vacio si alcanza.
static func missing_for(step: Dictionary) -> Dictionary:
	var missing := {}
	var cost: Dictionary = step_cost(step)
	for type in cost:
		var short: int = int(cost[type]) - ResourceManager.get_amount(type)
		if short > 0:
			missing[ResourceManager.get_type_name(type)] = short
	return missing

## El recurso cuya falta mas tarda en cubrirse, si tarda demasiado. "" si nada.
static func _slowest_missing(step: Dictionary, net: Dictionary) -> String:
	var worst := ""
	var worst_eta := SLOW_RESOURCE_SECONDS
	var missing: Dictionary = missing_for(step)
	for res in missing:
		var rate: float = float(net.get(res, 0.0))
		var eta: float = INF if rate <= 0.0 else float(missing[res]) / rate
		if eta > worst_eta:
			worst = res
			worst_eta = eta
	return worst

static func _cost_total(cost: Dictionary) -> int:
	var total := 0
	for type in cost:
		total += int(cost[type])
	return total

static func _workers_for(step: Dictionary) -> int:
	if String(step.get("kind", "")) != "build":
		return 0
	var data: BuildingData = Rules.load_building_data(String(step["id"]))
	return data.workers_required if data != null else 0

## Una casa solo ayuda si la gente que falta no esta ya de camino: si hay aforo
## libre, la poblacion crece sola y basta con esperar.
static func _houses_would_help(workers_needed: int) -> bool:
	var room: int = PopulationManager.get_max_population() - PopulationManager.get_population()
	return PopulationManager.get_free_workers() + room < workers_needed

## Construir `building_id` si el tope, los requisitos y el mapa lo permiten.
## Vacio si no: un paso que el jugador no puede dar no se le propone.
static func _build_step(building_id: String, why: String) -> Dictionary:
	if not Rules.check_building_limit(building_id) or not Rules.check_prerequisites(building_id):
		return {}
	if not ResourceManager.is_unlocked_by_name(_needs_unlocked(building_id)):
		return {}
	if not has_site(building_id):
		return {}
	return {"kind": "build", "id": building_id, "count": Rules.count_building(building_id) + 1, "why": why}

## ¿Queda en el mapa algun sitio legal para un extractor de este tipo? Los que
## construyen donde quieran siempre lo tienen (la isla cubre la rejilla entera).
## Sin mapa (un test sin escena) no se puede saber y se da por bueno.
static func has_site(building_id: String) -> bool:
	var rule: Dictionary = GameConfig.get_deposit_rule(building_id)
	if rule.is_empty():
		return true
	var map_gen: Node = GameManager._map_gen
	if map_gen == null or not is_instance_valid(map_gen):
		return true
	var data: BuildingData = Rules.load_building_data(building_id)
	if data == null:
		return false
	if int(rule["reach"]) > 0:
		return map_gen.has_buildable_spot_near(String(rule["deposit"]), data.grid_size, int(rule["reach"]))
	# Encima del yacimiento (la Refineria): basta con que haya uno donde quepa.
	for dep in map_gen.get_all_deposits():
		if String(dep["id"]) != String(rule["deposit"]):
			continue
		for ox in range(int(dep["cell_x"]), int(dep["cell_x"]) + int(dep["size_x"])):
			for oy in range(int(dep["cell_y"]), int(dep["cell_y"]) + int(dep["size_y"])):
				if bool(Rules.evaluate_placement(building_id, Vector2i(ox, oy), data.grid_size, map_gen)["ok"]):
					return true
	return false

## El productor de `res`, si se puede levantar otro (tope, era, yacimiento).
static func _producer_step(res: String, why: String) -> Dictionary:
	var building_id: String = PRODUCER_OF.get(res, "")
	if building_id == "":
		return {}
	if not ResourceManager.is_unlocked_by_name(res):
		return {}
	# La Fundicion y la Refineria abren su propio recurso: hasta tener la primera
	# no hay "otra", hay la de la linea.
	if Rules.count_building(building_id) == 0 and building_id in ["foundry", "refinery"]:
		return {}
	return _build_step(building_id, why)

## Recurso que un edificio necesita desbloqueado para que tenga sentido pedirlo.
static func _needs_unlocked(building_id: String) -> String:
	match building_id:
		"barracks":
			return "steel"
		"tower", "headquarters":
			return "oil"
	return "gold"

static func _army_step(unit_id: String, count: int, why: String, kind: String) -> Dictionary:
	return {"kind": kind, "id": unit_id, "count": count, "why": why}

## Unidades de ese tipo en el ejercito, mas las que se estan entrenando.
static func _army_count(unit_id: String) -> int:
	var total: int = ArmyManager.get_count(unit_id)
	for entry in ArmyManager.get_training():
		if String(entry.get("id", "")) == unit_id:
			total += 1
	return total

## El primer productor en ruinas, o null. Con la Tormenta encima no se propone:
## repararlo ahora es tirar el dinero, la tormenta lo vuelve a romper.
static func _ruined_producer() -> Node:
	if StormManager.is_storming():
		return null
	for info in GridManager.get_all_buildings():
		var data: BuildingData = info["data"]
		if data.is_producer() and BuildingHealth.is_ruined(info["node"]):
			return info["node"]
	return null

static func _first_building(building_id: String) -> Node:
	for info in GridManager.get_all_buildings():
		if (info["data"] as BuildingData).id == building_id:
			return info["node"]
	return null

# ══════════════════════════════════════════════════════════════════════
# Texto para el panel
# ══════════════════════════════════════════════════════════════════════

## La linea entera para pintarla: una fila por paso con su texto, si esta hecho y
## si es el primero que falta. Cierra con el asedio, que no es un edificio.
static func route() -> Array:
	var rows: Array = []
	var current_found := false
	for entry in LINE:
		var done: bool = _line_entry_done(entry)
		var row := {"text": describe(entry)["title"], "done": done, "current": false}
		if String(entry["kind"]) == "train":
			var as_step := _army_step(String(entry["id"]), int(entry["count"]), "", "train")
			as_step["any"] = bool(entry.get("any", false))
			row["text"] = describe(as_step)["title"]
		if not done and not current_found:
			row["current"] = true
			current_found = true
		rows.append(row)
	var won: bool = StormManager.is_halted()
	rows.append({"text": Tr.t("OBJ_ROUTE_FINAL"), "done": won, "current": not current_found and not won})
	rows.append({"text": Tr.t("OBJ_ROUTE_MARKET"), "current": false,
		"done": ProgressionManager.is_milestone_completed("market_10_trades")})
	return rows

static func _line_entry_done(entry: Dictionary) -> bool:
	match String(entry["kind"]):
		"build":
			return Rules.count_building(String(entry["id"])) >= int(entry["count"])
		"upgrade":
			var node: Node = _first_building(String(entry["id"]))
			return node != null and int(node.get_meta("level", 1)) >= int(entry["level"])
		"train":
			return _train_progress(entry) >= int(entry["count"])
	return false

## {"title", "why", "blocker"} ya traducidos. `blocker` vacio si el paso se puede
## dar ahora mismo.
static func describe(step: Dictionary) -> Dictionary:
	var kind: String = String(step.get("kind", ""))
	var title := ""
	match kind:
		"build":
			var data: BuildingData = Rules.load_building_data(String(step["id"]))
			title = Tr.t("OBJ_DO_BUILD") % (data.get_display_name() if data != null else String(step["id"]))
		"upgrade":
			var data: BuildingData = Rules.load_building_data(String(step["id"]))
			title = Tr.t("OBJ_DO_UPGRADE") % [data.get_display_name() if data != null else String(step["id"]), int(step["level"])]
		"train", "rebuild":
			var def: Dictionary = GameConfig.get_unit_def(String(step["id"]))
			title = Tr.t("OBJ_DO_TRAIN") % [Tr.t(String(def.get("name", step["id"]))),
				mini(_train_progress(step), int(step["count"])), int(step["count"])]
		"repair":
			var data: BuildingData = Rules.load_building_data(String(step["id"]))
			title = Tr.t("OBJ_DO_REPAIR") % (data.get_display_name() if data != null else String(step["id"]))
		"siege":
			title = Tr.t("OBJ_DO_SIEGE")
		"resummon":
			title = Tr.t("OBJ_DO_RESUMMON")
		_:
			title = Tr.t("OBJ_DO_SANDBOX")
	return {"title": title, "why": Tr.t(String(step.get("why", ""))), "blocker": blocker(step)}

## Por que no se puede dar el paso ahora, o "" si se puede.
static func blocker(step: Dictionary) -> String:
	var kind: String = String(step.get("kind", ""))
	match kind:
		"build":
			var data: BuildingData = Rules.load_building_data(String(step["id"]))
			if data == null:
				return ""
			var block: String = Rules.purchase_block_message(data)
			if block == Tr.t("LBL_NOT_ENOUGH_RESOURCES"):
				return Tr.t("OBJ_MISSING") % Tr.amount_list(missing_for(step))
			return block
		"upgrade":
			var node: Node = _first_building(String(step["id"]))
			if node != null and ProductionManager.is_constructing(node):
				return Tr.t("OBJ_IN_PROGRESS")
			var total: int = _cost_total(step_cost(step))
			if total > ResourceManager.get_storage_cap():
				return Tr.t("OBJ_BAG_TOO_SMALL") % [total, ResourceManager.get_storage_cap()]
			var missing: Dictionary = missing_for(step)
			return "" if missing.is_empty() else Tr.t("OBJ_MISSING") % Tr.amount_list(missing)
		"train", "rebuild":
			var check: Dictionary = ArmyManager.can_train(String(step["id"]))
			if bool(check["ok"]):
				return ""
			if String(check["reason"]) == "LBL_NOT_ENOUGH_RESOURCES":
				return Tr.t("OBJ_MISSING") % Tr.amount_list(missing_for(step))
			return Tr.t(String(check["reason"]))
		"repair":
			var node: Node = _ruined_producer()
			if node == null:
				return ""
			var check: Dictionary = BuildingHealth.can_repair(node)
			if bool(check["ok"]):
				return ""
			var missing := {}
			var cost: Dictionary = BuildingHealth.repair_cost(node)
			for type in cost:
				var short: int = int(cost[type]) - ResourceManager.get_amount(type)
				if short > 0:
					missing[ResourceManager.get_type_name(type)] = short
			return Tr.t("OBJ_MISSING") % Tr.amount_list(missing) if not missing.is_empty() else Tr.t(String(check["reason"]))
		"siege":
			if ProgressionManager.is_final_audit_active():
				return Tr.t("OBJ_SIEGE_UNDER_WAY")
			var reason: String = CombatManager.final_audit_block_reason()
			return Tr.t(reason) if reason != "" else ""
	return ""
