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
##   kind  "build" | "upgrade" | "train" | "repair" | "sell" | "buy" | "research" | "siege" | "resummon"
##         | "rebuild" | "sandbox" | "sortie" | "contract" | "campaign"
##         | "core" (subir el Nucleo a `level`; id "nucleo". 1.2, feat/nucleo-y-planos:
##           sale cuando un tope frena un paso y el Nucleo mas alto lo levanta)
##         ("sortie_offer" solo sale de sortie_step(), la segunda linea del panel)
##   id    edificio o unidad
##   level nivel al que sube una mejora
##   why   clave de Tr con el porque (una frase)

const Rules := preload("res://scripts/buildings/PlacementRules.gd")
const CoreLevel := preload("res://scripts/services/CoreLevel.gd")

## El camino recomendado, en orden. Cada entrada se da por hecha cuando hay al
## menos `count` en pie (o en obras). Es el mismo orden que la guia
## (docs/14-guia-de-juego.md, seccion 11).
const LINE := [
	{"kind": "build", "id": "sawmill", "count": 1, "why": "OBJ_WHY_SAWMILL"},
	# Cuartel temprano (2026-10-17, feat/cuartel-temprano; decision de Bryan:
	# "prioridad despues de la madera"). Va justo detras del aserradero, del que
	# salen sus tablones, y ANTES de la Granja: la comida de salida (80) da para
	# unos 16 minutos con 5 personas en las fases tempranas, y el Cuartel solo
	# pide 1 trabajador, asi que aserradero (2) + Cuartel (1) + Granja (2) caben
	# en los 5 del Nucleo sin esperar a una Casa. Solo donde hay Impuesto
	# (`needs: tithe`): en Constructor el Cuartel llega por el Cuartel General.
	# `eager`: si se puede pagar ya (con los tablones hechos), va antes que
	# cualquier paso de apoyo. Sin esto la Granja (comida en negativo), una Casa
	# (gente al tope) y la Mina se le colaban delante y el Cuartel salia el
	# sexto (ronda de pruebas de la 1.0, 2026-10-17).
	{"kind": "build", "id": "barracks", "count": 1, "needs": "tithe", "eager": true, "why": "OBJ_WHY_BARRACKS"},
	# La gente come comida (2026-10-04): la Granja va justo despues del primer
	# aserradero (y del Cuartel), antes de que se acabe la comida de salida.
	{"kind": "build", "id": "farm", "count": 1, "why": "OBJ_WHY_FARM"},
	# Un soldado antes de la tormenta de prueba (minuto 5): sale a la primera
	# mision (first_sortie_step, un solo nodo facil con botin), vuelve, y echa a
	# los Cobradores de juguete. Cuenta cualquier tropa ("any"); en la era 1 solo
	# hay Infanteria. La fila de la primera mision va DETRAS de esta en EL CAMINO
	# (`sortie_row`: sin soldado no hay mision).
	{"kind": "train", "id": "infantry", "count": 1, "any": true, "needs": "tithe",
		"sortie_row": "after", "why": "OBJ_WHY_FIRST_SOLDIERS"},
	{"kind": "build", "id": "gold_mine", "count": 1, "why": "OBJ_WHY_GOLD_MINE"},
	{"kind": "build", "id": "house", "count": 1, "why": "OBJ_WHY_HOUSE"},
	# Antes un segundo aserradero "porque la gente come madera". Desde que come
	# comida (2026-10-04) la madera sobra y atasca la bolsa: lo que hace falta es
	# el Mercado, para vender lo que sobra y comprar comida si falta.
	{"kind": "build", "id": "market", "count": 1, "why": "OBJ_WHY_MARKET"},
	{"kind": "build", "id": "warehouse", "count": 1, "why": "OBJ_WHY_WAREHOUSE"},
	{"kind": "build", "id": "foundry", "count": 1, "why": "OBJ_WHY_FOUNDRY"},
	# El Cuartel ya esta desde la era 1 donde hay Impuesto; esta entrada queda
	# para los modos sin el (`no_tithe`), y asi EL CAMINO no lo lista dos veces.
	{"kind": "build", "id": "barracks", "count": 1, "needs": "no_tithe", "why": "OBJ_WHY_BARRACKS"},
	# Guarnicion: cinco unidades en casa, de lo que sea, con dos canones. Tres
	# infantes solos pierden el Diezmo YA en severidad 1 (2 infantes y 1 canon de
	# escolta); tres infantes y dos canones lo ganan hasta severidad 3 sin torres y
	# hasta la 5 con dos torres en pie (tabla en docs/22-linea-jugable.md). Cuenta
	# cualquier tropa: los blindados del final tambien son guarnicion.
	{"kind": "train", "id": "infantry", "count": GARRISON_UNITS, "any": true, "needs": "tithe", "why": "OBJ_WHY_GARRISON"},
	{"kind": "build", "id": "refinery", "count": 1, "why": "OBJ_WHY_REFINERY"},
	{"kind": "build", "id": "tower", "count": 2, "needs": "storm", "why": "OBJ_WHY_TOWERS"},
	{"kind": "build", "id": "headquarters", "count": 1, "why": "OBJ_WHY_HQ"},
	{"kind": "upgrade", "id": "headquarters", "level": 2, "why": "OBJ_WHY_HQ_2"},
	{"kind": "train", "id": "vehicle", "count": 6, "needs": "audit", "why": "OBJ_WHY_ARMOUR"},
	# Las torres que el asedio aprovecha: cada una manda una dotacion de
	# artilleria, y con la guarnicion mermada caben mas en el tablero
	# (GameConfig.storm_tower_garrison_max). Es la preparacion del final
	# (docs/17-balance-asedio.md, 2026-10-12): con dos torres el asedio se gana
	# siete de cada diez; con las que pide aqui, casi siempre.
	{"kind": "build", "id": "tower", "count_from": "audit_towers", "needs": "audit", "why": "OBJ_WHY_TOWERS_AUDIT"},
	{"kind": "upgrade", "id": "headquarters", "level": 3, "why": "OBJ_WHY_HQ_3"},
]

## La guarnicion de referencia para bajar a la Regencia: el tope de despliegue en
## blindados, que es la que gana la mayoria de asedios (docs/17-balance-asedio.md).
const SIEGE_VEHICLES := 6
## Guarnicion minima para el Diezmo, y cuantos canones lleva dentro.
const GARRISON_UNITS := 5
const GARRISON_GUNS := 2

## Las tecnologias que agrandan la bolsa, con sus requisitos delante: Logistica 1
## y 2 (+300) e Industria 1 y 2 (+200).
const STORAGE_TECH_PATH := ["log_1", "log_2", "ind_1", "ind_2"]
## Lo que se investiga con lo que sobra mientras se ahorra (2026-10-14).
const SURPLUS_TECH_PATH := ["ind_1", "mil_1", "log_1", "ind_2", "mil_2", "log_2",
	"ind_3", "mil_3", "log_3", "ind_4", "mil_4", "log_4", "ind_5", "mil_5", "log_5"]

## Por debajo de esta fraccion de la bolsa se puede pedir un productor mas.
const ROOMY_BAG := 0.75
## Por encima de esta fraccion, si al paso le falta oro o madera, se vende.
const CROWDED_BAG := 0.9
## Lo que se vende de una vez con la bolsa clavada (_unclog_step): el oro que
## entra paga la compra de lo que falta (_sell_step compra lotes de MIN_SALE).
const PINNED_SALE := 300
## Lo minimo que merece la pena vender, y lo que no se vende nunca de madera
## (varios ciclos de comida).
const MIN_SALE := 20

## Por debajo de este saldo por segundo el paso siguiente es otro productor.
const MIN_NET_PER_SECOND := 0.05
## Si lo que falta para el paso tarda mas que esto en llegar, un productor mas
## del recurso que frena es mejor inversion que esperar.
## 240 desde 2026-10-14 (antes 360): pide otro productor antes de que la espera
## pase de 4 min. Con 360 quedaban 4-23 huecos de mas de 3 min sin decidir por
## partida; con 240, 2-9 (docs/22 §11).
const SLOW_RESOURCE_SECONDS := 240.0
## Bolsa casi llena: por encima de esta fraccion se pide otro almacen.
const FULL_BAG := 0.9
## Si lo que falta para el paso tarda mas que esto, el panel ofrece algo util
## pagado con lo que sobra (_while_saving_step) en vez de "espera" (2026-10-16).
const WAIT_FILL_SECONDS := 90.0
## Por debajo de esta moral, mientras se ahorra, se pide una decoracion.
const DECORATE_BELOW_MORALE := 80

const PRODUCER_OF := {
	"food": "farm",
	"gold": "gold_mine",
	"wood": "sawmill",
	"steel": "foundry",
	"oil": "refinery",
}
## El apoyo de comida cuando no cabe otra Granja (feat/muelle-pesca).
const FISHING_DOCK_ID := "fishing_dock"

# ══════════════════════════════════════════════════════════════════════
# El paso
# ══════════════════════════════════════════════════════════════════════

static func next_step() -> Dictionary:
	# ── El modo manda (docs/20-modos-de-juego.md) ──
	if GameMode.is_run_over():
		return {"kind": "sandbox", "why": "OBJ_WHY_RUN_OVER"}
	if not GameMode.victory_enabled():
		return {"kind": "sandbox", "why": "OBJ_WHY_SANDBOX_MODE"}
	if GameMode.capstone_wins() and ProgressionManager.is_milestone_completed("hq_max"):
		return {"kind": "sandbox", "why": "OBJ_WHY_SANDBOX_BUILT"}

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

	# ── La primera escaramuza ──
	# En cuanto sale del cuartel la primera unidad, a pelear: una salida facil y
	# con botin antes de juntar la guarnicion (docs/15-combat.md §4). No pasa por
	# _support_or: no cuesta nada, y el botin es justo oro y madera.
	var sortie: Dictionary = first_sortie_step()
	if not sortie.is_empty():
		return sortie

	# ── Las tres campanas (feat/tres-campanas) ──
	# El Cuartel General ya esta a nivel 3 y el Ataque Final espera a las
	# campanas que faltan: lo siguiente es una de ellas (su edificio, su tropa o
	# su mision). Antes del nivel 3 las campanas van en la segunda linea
	# (campaign_step) y la linea principal no cambia.
	var gate: Dictionary = campaign_gate_step()
	if not gate.is_empty():
		return _support_or(gate) if String(gate["kind"]) != "campaign" else gate

	# ── La linea ──
	var target: Dictionary = _first_open_line_step()
	if target.is_empty():
		return {"kind": "sandbox", "why": "OBJ_WHY_SANDBOX"}

	# Antes del paso, lo que lo haria imposible o absurdo: comer, obreros, bolsa.
	return _support_or(target)

static func _support_or(target: Dictionary) -> Dictionary:
	# Lo que el edificio pide en pie antes (GameConfig.building_prerequisites)
	# va primero: si no, el panel pedia algo que el juego rechaza al hacer clic
	# y la partida se quedaba ahi para siempre.
	var prereq: Dictionary = prerequisite_step(target)
	if not prereq.is_empty():
		target = prereq
	# La bolsa atascada de lo que el paso no pide: vender eso primero, o lo que
	# espera en los edificios (el acero de la fundicion, el oro de la mina) no
	# entra nunca (2026-10-04: la produccion ya no se tira, se para).
	var unclog: Dictionary = _unclog_step(target)
	if not unclog.is_empty():
		return unclog
	# Lo que da de comer en ruinas, antes que el taller: el taller puede ser
	# justo ese edificio (los tablones del Cuartel temprano salen del Aserradero,
	# y uno en ruinas no los fabrica). Ronda de pruebas de la 1.0, 2026-10-17.
	var repair: Dictionary = _repair_step()
	if not repair.is_empty():
		return repair
	# Lo que el paso pide del taller va antes que cualquier otra cosa: sin
	# fabricarlo, juntar oro no acerca al paso.
	var make: Dictionary = make_step_for(target)
	if not make.is_empty():
		# Al taller le falta su receta (acero para las vigas...) y la bolsa esta
		# llena de otra cosa: comprarla con el oro que sobra. Sin esto la sonda
		# se quedo horas con 3.000 de oro y sin acero para una viga (2026-10-12).
		var trade: Dictionary = _sell_step(make)
		if not trade.is_empty():
			return trade
		# Al taller le falta su receta y tarda en llegar (la madera de los
		# tablones al entrar en la era 2, el petroleo del combustible en la 3):
		# lo mismo que con cualquier paso que espera, otro productor de lo que
		# frena o algo util con lo que sobra (2026-10-16, docs/22 §11). Sin esto
		# el panel repetia "Fabrica tablones" durante 5-9 min sin poder darse.
		if not missing_for(make).is_empty():
			# La espera es la de todas las vueltas que pide el paso (los 100 de
			# combustible del CG nv2 son 300 de petroleo), no la de una sola.
			var whole: Dictionary = make.duplicate()
			whole["runs"] = runs_for(make)
			var help: Dictionary = _support_step(whole, target)
			if not help.is_empty() and String(help.get("kind", "")) != "sell" \
					and _workers_step(help).is_empty() \
					and _workers_for(help) <= PopulationManager.get_free_workers():
				return help
		return make
	# Un paso `eager` de la linea (el Cuartel temprano) que ya se puede pagar y
	# tiene obreros va tal cual: los apoyos son para cuando falta algo.
	# Los tablones que ya salen del taller cuentan como hechos.
	if bool(target.get("eager", false)) and _missing_once_made(target).is_empty() \
			and _workers_for(target) <= PopulationManager.get_free_workers() \
			and _food_market_step("food").is_empty():
		return target
	var support: Dictionary = _support_step(target)
	if support.is_empty():
		return target
	# El paso de apoyo tiene que poder darse el tambien: otro aserradero sin
	# obreros para atenderlo es un consejo que el juego rechaza al hacer clic.
	var hands: Dictionary = _workers_step(support)
	if not hands.is_empty():
		return hands
	# Sin obreros libres ahora y con la gente ya de camino (hay aforo): una casa
	# no ayuda y el aserradero de apoyo se rechazaria con "Sin trabajadores
	# disponibles". Se sigue con el paso de la linea hasta que nazcan.
	if _workers_for(support) > PopulationManager.get_free_workers():
		return target
	return support

## El primer requisito que le falta a un paso de obra, como paso de obra (y el
## requisito del requisito, si tambien falta). {} si no le falta ninguno.
static func prerequisite_step(target: Dictionary, depth: int = 0) -> Dictionary:
	if String(target.get("kind", "")) != "build" or depth > 4:
		return {}
	for req_id in GameConfig.get_prerequisites(String(target["id"])):
		if Rules.count_building(String(req_id)) >= 1:
			continue
		var req := {"kind": "build", "id": String(req_id), "count": 1,
			"why": "OBJ_WHY_PREREQUISITE", "for": String(target["id"])}
		var deeper: Dictionary = prerequisite_step(req, depth + 1)
		return deeper if not deeper.is_empty() else req
	return {}

## Vender lo que sobra cuando la bolsa esta a rebosar y algo espera en los
## edificios para entrar. Sobra lo que ni el paso ni su receta de taller piden,
## y de la comida lo que pasa de ocho ciclos. {} si no hace falta o no hay Mercado.
static func _unclog_step(target: Dictionary) -> Dictionary:
	if Rules.count_building("market") == 0:
		return {}
	var cap: int = ResourceManager.get_storage_cap()
	if ResourceManager.get_total_stored() < int(float(cap) * CROWDED_BAG):
		return {}
	var waiting: Dictionary = ProductionManager.get_all_stock()
	var keep := {}
	var cost: Dictionary = step_cost(target)
	for type in cost:
		keep[ResourceManager.get_type_name(type)] = int(cost[type])
	for res in missing_for(target):
		if not ResourceManager.is_material_name(String(res)):
			continue
		for res_name in material_recipe(String(res)).get("cost", {}):
			keep[res_name] = int(keep.get(res_name, 0)) + 2 * int(material_recipe(String(res))["cost"][res_name])
	keep["food"] = int(keep.get("food", 0)) + PopulationManager.food_due() * 8
	# Solo si lo que espera fuera es justo lo que falta: si no, sobra vender.
	var blocked := false
	for res_name in keep:
		if ResourceManager.get_amount(ResourceManager.name_to_type(String(res_name))) < int(keep[res_name]) \
				and int(waiting.get(res_name, 0)) > 0:
			blocked = true
	if not blocked:
		return {}
	var best := ""
	var best_excess := MIN_SALE - 1
	for res in ["food", "wood", "oil", "steel"]:
		if not ResourceManager.is_unlocked_by_name(res):
			continue
		var excess: int = ResourceManager.get_amount(ResourceManager.name_to_type(res)) - int(keep.get(res, 0))
		if excess > best_excess:
			best = res
			best_excess = excess
	# Lo que se vende vuelve como oro, que tambien ocupa bolsa: con la bolsa a
	# rebosar, vender de golpe un quinto de la bolsa tiraba el oro que no cabia
	# (hasta 8.000 de oro perdidos por partida, tools/line_probe.gd 2026-10-12).
	# Se vende solo lo que cabe; si no cabe ni un poco, no se vende (la gente
	# come y hace sitio en unos ciclos).
	var amount: int = _sale_that_fits(best, mini(best_excess, maxi(MIN_SALE, cap / 5))) if best != "" else 0
	# La bolsa clavada (2026-10-16): ni un hueco libre, al paso no le falta oro
	# y lo que falta espera fuera. Vender sin que quepa el oro es perder parte
	# del precio, pero el oro de mas paga en el siguiente vistazo la compra de
	# lo que falta, y comprar si hace sitio. Sin esto la sonda se quedaba hasta
	# dos horas con la bolsa llena de acero mirando el petroleo del CG nv2.
	var gold_spare: int = ResourceManager.get_amount(ResourceManager.Type.GOLD) \
		- int(cost.get(ResourceManager.Type.GOLD, 0)) - _army_upkeep() * 2
	if amount <= 0 and ResourceManager.get_free_space() < MIN_SALE \
			and not missing_for(target).has("gold") and gold_spare < PINNED_SALE:
		# Lo mas barato que sobre: cada unidad vendida pierde (precio - 1) de oro.
		var cheap := ""
		var cheap_price: int = 1 << 20
		for res in ["food", "wood", "steel", "oil"]:
			if not ResourceManager.is_unlocked_by_name(res):
				continue
			var res_keep: int = int(keep.get(res, 0))
			# La comida de mucha gente es lo que clava la bolsa del final (101
			# personas, 600 de comida y 4.104 de 4.104 ante el CG nv3): con la
			# bolsa clavada se guardan tres ciclos, no ocho.
			if res == "food":
				res_keep = res_keep - PopulationManager.food_due() * 5
			var spare: int = ResourceManager.get_amount(ResourceManager.name_to_type(res)) - res_keep
			var price: int = MarketManager.get_sell_price(res)
			if spare >= MIN_SALE and price < cheap_price:
				cheap = res
				cheap_price = price
				amount = mini(spare, PINNED_SALE)
		if cheap != "":
			best = cheap
	if amount <= 0:
		return {}
	return {"kind": "sell", "id": best, "amount": amount, "why": "OBJ_WHY_SELL"}

## "Fabrica vigas en la Fundicion" si `target` pide un material que falta y su
## edificio esta en pie. {} si no pide materiales, ya los hay, o aun no hay donde
## fabricarlos (entonces manda el requisito del propio paso).
static func make_step_for(target: Dictionary) -> Dictionary:
	# Si el paso ni cabe en la bolsa, lo primero es el almacen: fabricar para
	# algo que no se puede pagar no acerca a nada.
	if _cost_total(step_cost(target)) > ResourceManager.get_storage_cap():
		return {}
	var missing: Dictionary = missing_for(target)
	for res in missing:
		if not ResourceManager.is_material_name(String(res)):
			continue
		var source: String = GameConfig.get_material_source(String(res))
		if source == "" or Rules.count_building(source) < 1:
			continue
		# Lo que ya se esta fabricando cuenta: sin esto el panel seguia diciendo
		# "Fabrica tablones" con el lote en marcha y se pagaba dos veces (la
		# sonda de linea gastaba 80 de madera en 20 tablones, ronda 1.0).
		var still: int = int(missing[res]) - in_production(String(res))
		if still <= 0:
			continue
		return {"kind": "make", "id": String(res), "building": source,
			"amount": still, "why": "OBJ_WHY_MAKE"}
	return {}

## Lo que le falta a `step` contando lo que el taller ya esta fabricando.
static func _missing_once_made(step: Dictionary) -> Dictionary:
	var out: Dictionary = missing_for(step)
	for res in out.keys():
		if ResourceManager.is_material_name(String(res)) \
				and int(out[res]) - in_production(String(res)) <= 0:
			out.erase(res)
	return out

## Cuanto de `res` sale de los procesos en marcha (todas las vueltas que quedan).
static func in_production(res: String) -> int:
	var total := 0
	for info in GridManager.buildings_view():
		var node: Node = info.get("node")
		if node == null or not is_instance_valid(node):
			continue
		var active: Dictionary = ProcessManager.get_active(node)
		if active.is_empty():
			continue
		total += int((active.get("produces", {}) as Dictionary).get(res, 0)) * maxi(1, int(active.get("count", 1)))
	return total

## La receta del taller que da `material` en su edificio, o {}.
static func material_recipe(material: String) -> Dictionary:
	var source: String = GameConfig.get_material_source(material)
	for proc in GameConfig.get_processes_for(source):
		if (proc.get("produces", {}) as Dictionary).has(material):
			return proc
	return {}

## Cuantas vueltas del taller hacen falta para el `amount` de un paso "make".
static func runs_for(step: Dictionary) -> int:
	var per_run: int = int((material_recipe(String(step["id"])).get("produces", {}) as Dictionary).get(String(step["id"]), 1))
	return maxi(1, int(ceil(float(int(step.get("amount", 1))) / float(maxi(1, per_run)))))

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

## "Lanza tu primera escaramuza", o {} si no toca: ya se gano una, hay columna
## fuera, la Regencia esta convocada o no queda nadie en casa que mandar.
static func first_sortie_step() -> Dictionary:
	if TutorialManager.is_first_sortie_done():
		return {}
	if CombatManager.has_active_expedition():
		return {}
	if ProgressionManager.is_final_audit_pending() or ProgressionManager.is_final_audit_active():
		return {}
	var party: Dictionary = first_sortie_party()
	if party.is_empty():
		return {}
	return {"kind": "sortie", "id": String(party.keys()[0]), "why": "OBJ_WHY_FIRST_SORTIE"}

## "Sal de escaramuza" (doc 21 §3.6, 2026-10-14): la segunda linea de ¿QUE
## HACER?, aparte del paso de la linea (next_step no la devuelve, asi la sonda de
## linea sigue igual). {} si no hay motivo; si lo hay, el porque viene de
## CombatManager.sortie_reason(), la misma respuesta que el punto rojo del boton.
## La primera escaramuza ya tiene su paso propio (first_sortie_step).
static func sortie_step() -> Dictionary:
	var reason: String = CombatManager.sortie_reason()
	if reason == "" or reason == "SORTIE_WHY_FIRST":
		return {}
	return {"kind": "sortie_offer", "why": reason}

## ── Las tres campanas (feat/tres-campanas) ──

## El paso de las campanas cuando el Ataque Final solo espera por ellas (el
## Cuartel General ya esta a nivel 3). {} si no toca. Elige la campana que se
## puede jugar ya (si no, la primera que falte) y pide, por orden, su edificio,
## tropa de su medio o la mision.
static func campaign_gate_step() -> Dictionary:
	if not GameMode.audit_needs_campaigns() or ProgressionManager.final_audit != null:
		return {}
	if not ProgressionManager.is_milestone_completed("hq_max"):
		return {}
	if CombatManager.campaigns_all_complete():
		return {}
	var domain: String = ""
	for d in GameConfig.CAMPAIGN_DOMAINS:
		if CombatManager.is_campaign_complete(String(d)):
			continue
		if domain == "":
			domain = String(d)
		if CombatManager.campaign_lock_reason(String(d)) == "" and not CombatManager.campaign_units_home(String(d)).is_empty():
			domain = String(d)
			break
	if domain == "":
		return {}
	return campaign_need_step(domain, "OBJ_WHY_CAMPAIGN_FOR_AUDIT")

## Lo que pide una campana para poder jugar su mision: su edificio, tropa de su
## medio, o la mision misma ({"kind": "campaign", "id": medio}).
static func campaign_need_step(domain: String, why: String) -> Dictionary:
	var building: String = CombatManager.campaign_building(domain)
	if CombatManager.campaign_lock_reason(domain) == "CAMP_LOCK_BUILDING":
		return {"kind": "build", "id": building, "count": 1, "why": "OBJ_WHY_CAMPAIGN_BUILDING"}
	var home: int = CombatManager.roster_size(CombatManager.campaign_units_home(domain))
	var wanted: int = maxi(1, GameConfig.campaign_suggested_party)
	if home < wanted:
		var unit_id: String = String(GameConfig.campaign_suggested_unit.get(domain, "infantry"))
		if ArmyManager.is_unlocked(unit_id):
			var away: int = int(CombatManager.get_units_away().get(unit_id, 0))
			return _army_step(unit_id, _army_count(unit_id) - away + (wanted - home), "OBJ_WHY_CAMPAIGN_UNITS", "train")
	return {"kind": "campaign", "id": domain, "why": why}

## La segunda linea de ¿QUE HACER? (como sortie_step): la siguiente mision de
## alguna campana que ya se puede jugar con la tropa que hay en casa. {} si no
## hay ninguna, si la linea principal ya la pide o si hay columna fuera.
static func campaign_step() -> Dictionary:
	if not campaign_gate_step().is_empty():
		return {}
	for d in GameConfig.CAMPAIGN_DOMAINS:
		var domain: String = String(d)
		if CombatManager.campaign_lock_reason(domain) != "":
			continue
		if CombatManager.campaign_units_home(domain).is_empty():
			continue
		return {"kind": "campaign", "id": domain, "why": "OBJ_WHY_CAMPAIGN_NEXT"}
	return {}

## "Para llamar al Ataque Final: ...", o "" si no falta nada (o no hay asedio).
static func final_gate_text() -> String:
	return ProgressionManager.final_audit_gate_text()

## El candado de una campana en palabras, con su cifra (lo mismo que dice el
## panel de MISIONES): "Construye un Astillero", "Llega a la era 3",
## "La tropa descansa: 1:20". "" si se puede salir.
static func campaign_lock_text(domain: String) -> String:
	var lock: String = CombatManager.campaign_lock_reason(domain)
	match lock:
		"":
			return ""
		"CAMP_DONE":
			return Tr.t("CAMP_DONE") % Tr.t("CAMP_NAME_" + domain.to_upper())
		"CAMP_LOCK_BUILDING":
			var data: BuildingData = Rules.load_building_data(CombatManager.campaign_building(domain))
			return Tr.t("CAMP_LOCK_BUILDING") % (data.get_display_name() if data != null else CombatManager.campaign_building(domain))
		"CAMP_LOCK_ERA":
			return Tr.t("CAMP_LOCK_ERA") % ExpeditionGenerator.campaign_mission_era(domain, CombatManager.campaign_won(domain))
		"CAMP_LOCK_REST":
			var left: int = ceili(CombatManager.campaign_rest_left(domain))
			return Tr.t("CAMP_LOCK_REST") % [left / 60, left % 60]
	return Tr.t(lock)

## Paso aparte, que no entra en next_step() (la linea y su sonda no cambian):
## "Entrega el encargo de los vecinos" cuando uno del tablon ya se puede
## entregar. {} si no hay ninguno o el modo no tiene encargos. ¿QUE HACER? lo
## ensena debajo del paso principal.
static func contract_step() -> Dictionary:
	if not GameMode.contracts_enabled():
		return {}
	var source: String = ContractManager.first_deliverable()
	if source.is_empty():
		return {}
	return {"kind": "contract", "id": source, "why": "OBJ_WHY_CONTRACT"}

## Paso aparte, como contract_step() (aire y mar, 2026-10-17): "Construye un
## Astillero" en la era 2 y "Construye un Aerodromo" en la era 3, cuando la linea
## ya tiene en pie lo que pide cada uno y un Cuartel. No entra en next_step(): la
## linea principal (y tools/line_probe.gd) no cambia; ¿QUE HACER? lo ensena
## debajo, como una idea mas. {} si no toca: modo sin combate, asedio en marcha,
## ya lo hay, falta su requisito o el tope no deja.
static func fleet_step() -> Dictionary:
	if not GameMode.tithe_enabled() and not GameMode.audit_enabled():
		return {}
	if ProgressionManager.is_final_audit_active():
		return {}
	if Rules.count_building("barracks") < 1:
		return {}
	for building_id in ["shipyard", "aerodrome"]:
		if Rules.count_building(building_id) >= 1:
			continue
		var ready := true
		for req_id in GameConfig.get_prerequisites(building_id):
			if Rules.count_building(String(req_id)) < 1:
				ready = false
		if not ready or GameConfig.get_building_limit(building_id) == 0:
			continue
		return {"kind": "build", "id": building_id, "count": 1,
			"why": "OBJ_WHY_SHIPYARD" if building_id == "shipyard" else "OBJ_WHY_AERODROME"}
	return {}

## La columna que se propone para la primera escaramuza: una unidad de casa, la
## del primer tipo que haya (infanteria antes que canones). Vacio si no hay nadie.
static func first_sortie_party() -> Dictionary:
	var home: Dictionary = CombatManager.get_deployable_units()
	for unit_id in GameConfig.get_unit_ids():
		# La primera escaramuza es en tierra: un barco no puede ir (aire y mar).
		if GameConfig.get_unit_domain(String(unit_id)) == "sea":
			continue
		if int(home.get(unit_id, 0)) > 0:
			return {String(unit_id): 1}
	return {}

## El primer paso de la linea que no esta hecho.
static func _first_open_line_step() -> Dictionary:
	for entry in LINE:
		if not _entry_applies(entry):
			continue
		match String(entry["kind"]):
			"build":
				if Rules.count_building(String(entry["id"])) < entry_count(entry):
					# El tope lo frena y el Nucleo mas alto lo levanta: subir el
					# Nucleo es el paso (1.2).
					var core: Dictionary = core_step_for_limit(String(entry["id"]))
					if not core.is_empty():
						return core
					var open_step: Dictionary = entry.duplicate()
					open_step["count"] = entry_count(entry)
					return open_step
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

## Cuantos pide una entrada de la linea. Las torres del asedio salen de
## GameConfig: tantas como dotaciones caben a la vez (storm_tower_garrison_max).
static func entry_count(entry: Dictionary) -> int:
	match String(entry.get("count_from", "")):
		"audit_towers":
			var per: int = maxi(1, GameConfig.storm_tower_garrison_per_tower)
			return int(ceil(float(GameConfig.storm_tower_garrison_max) / float(per)))
	return int(entry.get("count", 1))

## Que se entrena para un paso de guarnicion: canones hasta tener los que pide,
## luego infanteria. Un paso de un solo tipo entrena ese tipo.
static func _garrison_unit(entry: Dictionary) -> String:
	if not bool(entry.get("any", false)):
		return String(entry["id"])
	if ArmyManager.is_unlocked("artillery") and _army_count("artillery") < GARRISON_GUNS:
		return "artillery"
	return String(entry["id"])

## Un paso de tropa solo tiene sentido si el modo trae aquello contra lo que se
## entrena: la guarnicion es para el Diezmo, los blindados para la Auditoria. En
## Constructor no hay ni lo uno ni lo otro. Las torres son contra la Tormenta:
## sin Tormenta no son un paso (el Cuartel General no las pide).
static func _entry_applies(entry: Dictionary) -> bool:
	match String(entry.get("needs", "")):
		"storm":
			return GameMode.storm_enabled()
		"tithe":
			return GameMode.tithe_enabled()
		"no_tithe":
			return not GameMode.tithe_enabled()
		"audit":
			return GameMode.audit_enabled()
	return true

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
static func _support_step(target: Dictionary, outer: Dictionary = {}) -> Dictionary:
	# 0. Lo que da de comer esta en ruinas: repararlo antes que levantar otro.
	var repair: Dictionary = _repair_step()
	if not repair.is_empty():
		return repair
	var net: Dictionary = net_rates()
	# Mientras la gente no come (Fundacion) no hay saldo que vigilar: la linea
	# empieza por el aserradero, no por una mina que nadie necesita todavia.
	var eating: bool = ProgressionManager.current_phase >= GameConfig.Phase.SETTLEMENT
	# La gente come comida; el oro solo hace falta para el sueldo de la tropa.
	for res in ["food", "gold"]:
		if not eating:
			continue
		if res == "gold" and _army_upkeep() <= 0:
			continue
		# Hambre ya: lo que hay no llega a dos ciclos de comida. Un aserradero nuevo
		# tarda en rendir (y puede no tener obreros: con la moral bajo 30 no nace
		# nadie); el Mercado es inmediato.
		var hungry: Dictionary = _food_market_step(res)
		if not hungry.is_empty():
			return hungry
		if float(net[res]) < MIN_NET_PER_SECOND:
			var fix: Dictionary = _producer_step(res, "OBJ_WHY_FEED_%s" % res.to_upper())
			if not fix.is_empty() and String(fix["id"]) != String(target.get("id", "")):
				return fix

	var house: Dictionary = _workers_step(target)
	if not house.is_empty():
		return house
	# La gente al tope y comida de sobra: otra vivienda, pagada con lo que el
	# paso no pide. Va antes que esperar, este como este la bolsa: si no, las
	# casas solo salian cuando un paso pedia obreros y ninguna partida pasaba
	# de 13 de las 20 que deja la era 3 (2026-10-16, docs/22 §11).
	var more_room: Dictionary = house_room_step(target, outer)
	if not more_room.is_empty() and String(target.get("id", "")) != "house":
		return more_room

	var cost_total: int = _cost_total(step_cost(target))
	var cap: int = ResourceManager.get_storage_cap()
	# La bolsa llena solo pide almacen cuando la linea ya paso por el primero: el
	# primer Almacen es el interruptor de la fase Supervivencia (consumo al doble,
	# castigo de moral y eventos), y adelantarlo por 60 de oro que sobran es la
	# trampa que la guia avisa de no pisar. Antes de eso, lo que sobra se gasta.
	var full: bool = Rules.count_building("warehouse") > 0 \
		and ResourceManager.get_total_stored() >= int(float(cap) * FULL_BAG)
	# "No cabe" es tambien "cabe tan justo que no se puede pagar": con la gente
	# comiendo y las fabricas produciendo, juntar el 95% de la bolsa en la mezcla
	# exacta es un rompecabezas. Por encima del 90% se pide sitio.
	var tight: bool = cost_total > int(float(cap) * FULL_BAG)
	if (tight or full) and String(target.get("id", "")) != "warehouse":
		var wh := _build_step("warehouse", "OBJ_WHY_BAG_TOO_SMALL" if tight else "OBJ_WHY_BAG_FULL")
		if not wh.is_empty():
			return wh
	# Con los cinco almacenes en pie la bolsa ya no crece con edificios: crece con
	# la rama de Logistica e Industria del arbol. La mejora final del Cuartel
	# General cuesta EXACTAMENTE la bolsa maxima sin tecnologia (3.500), asi que
	# pagarla exige tener los cuatro recursos justos a la vez mientras la gente
	# come y las fabricas producen: un rompecabezas, no una decision. Con +500 de
	# las dos tecnologias de almacen cabe con holgura.
	if tight:
		var tech: Dictionary = _storage_tech_step()
		if not tech.is_empty():
			return tech

	# 5. La bolsa a rebosar y al paso le falta oro o madera: lo que sobra se vende.
	# Con la bolsa llena lo que entra se pierde, el oro de la comida incluido, y
	# lo que se llena solo es el acero y el petroleo que nadie come.
	var sell: Dictionary = _sell_step(target)
	if not sell.is_empty():
		return sell
	# La bolsa a rebosar, al paso le falta algo y ni vender cabe (el oro de la
	# venta no entra): lo que sobra se pasa al taller, que no ocupa bolsa. Sin
	# esto una partida se quedo dos horas ante el CG nv3 con la bolsa llena de
	# madera y petroleo y sin sitio para el oro que faltaba (2026-10-16).
	var room: Dictionary = _make_room_step(target, outer)
	if not room.is_empty():
		return room

	# Un productor mas solo si hay sitio para lo que va a producir: con la bolsa
	# casi llena, otra fundicion es mas acero que se tira.
	# La receta del taller (outer no vacio) espera un recurso que el paso gasta
	# entero: otro productor no se tira aunque la bolsa vaya llena (el petroleo
	# de los 400 de combustible del CG nv3, 2026-10-16).
	var slow: String = _slowest_missing(target, net) \
		if not outer.is_empty() or ResourceManager.get_total_stored() < int(float(cap) * ROOMY_BAG) else ""
	if slow != "":
		var more: Dictionary = _producer_step(slow, "OBJ_WHY_SLOW_%s" % slow.to_upper())
		if not more.is_empty() and String(more["id"]) != String(target.get("id", "")):
			return more
	# La bolsa casi llena y el paso esperando un recurso lento: la espera muerta
	# de la era 3 (4-15 huecos de mas de 3 min por partida ahorrando para el CG
	# nv2/nv3 y los blindados, tools/line_probe.gd 2026-10-12). Lo que sobra
	# (lo que el paso no pide) se gasta en subir de nivel el productor de lo que
	# frena: rinde mas, hace sitio en la bolsa y no retrasa el paso ni una unidad.
	if slow == "":
		var surplus: Dictionary = _surplus_upgrade_step(target, net, false, outer)
		if not surplus.is_empty():
			return surplus
		var study: Dictionary = _surplus_research_step(target, false, outer)
		if not study.is_empty():
			return study
	# Mientras se ahorra, este como este la bolsa (2026-10-16): si lo que falta
	# tarda, el panel no dice "espera" sino algo util pagado solo con lo que
	# sobra. Era la mayoria de los huecos de mas de 3 min sin decidir nada: el
	# blindado, los tablones del Cuartel y el combustible (docs/22 §11).
	return _while_saving_step(target, net, outer)

## Lo que se puede hacer mientras el paso espera recursos que tardan mas de
## WAIT_FILL_SECONDS: subir el productor de lo que frena, investigar o una
## decoracion si la moral flojea (la vivienda va antes, en _support_step). Todo pagado con lo que sobra: nada de esto retrasa el paso ni una
## unidad (se guarda lo que cuestan el paso y `outer`, y dos sueldos de la tropa).
## {} si el paso no espera, la espera es corta o no sobra para nada.
static func _while_saving_step(target: Dictionary, net: Dictionary, outer: Dictionary = {}) -> Dictionary:
	if _wait_seconds(target, net) < WAIT_FILL_SECONDS:
		return {}
	# Con la bolsa a rebosar el oro que sobra es lo que compra lo que falta
	# (_sell_step): gastarlo aqui dejaba la bolsa clavada, llena de lo que el
	# paso no pide y sin oro para comprar lo que si (2026-10-16).
	if ResourceManager.get_total_stored() >= int(float(ResourceManager.get_storage_cap()) * CROWDED_BAG):
		return {}
	var surplus: Dictionary = _surplus_upgrade_step(target, net, true, outer)
	if not surplus.is_empty():
		return surplus
	var study: Dictionary = _surplus_research_step(target, true, outer)
	if not study.is_empty():
		return study
	return _decoration_step(target, outer)

## Cuanto tarda en llegar lo que le falta al paso (lo mas lento), en segundos.
## 0 si no le falta nada; INF si algo no llega nunca. Los materiales no cuentan:
## los hace el taller (make_step_for).
static func _wait_seconds(step: Dictionary, net: Dictionary) -> float:
	var worst := 0.0
	var missing: Dictionary = missing_for(step)
	for res in missing:
		if ResourceManager.is_material_name(String(res)):
			continue
		var rate: float = float(net.get(res, 0.0))
		worst = maxf(worst, INF if rate <= 0.0 else float(missing[res]) / rate)
	return worst

## "Construye otra vivienda" cuando la gente esta al tope y la comida aguanta a
## los que vendran (2026-10-16): hasta aqui solo se pedian casas cuando faltaban
## obreros para un paso, y ninguna partida pasaba de 11 de las 20 que deja la
## era 3. Pagada con lo que sobra. {} si hay aforo libre, la comida no llega, no
## cabe otra (tope) o no sobra.
static func house_room_step(target: Dictionary = {}, outer: Dictionary = {}) -> Dictionary:
	if ProgressionManager.current_phase < GameConfig.Phase.SURVIVAL:
		return {}
	if PopulationManager.get_population() < PopulationManager.get_max_population():
		return {}
	var data: BuildingData = Rules.load_building_data("house")
	if data == null:
		return {}
	# La comida tiene que dar para los que llegan: el saldo de ahora menos lo que
	# comerian, y cuatro ciclos en el granero.
	var newcomers: float = float(data.population_capacity * GameConfig.food_per_pop) \
		* maxf(0.1, 1.0 - GameConfig.tech_consumption_reduction) / GameConfig.consumption_interval
	if float(net_rates()["food"]) - newcomers < MIN_NET_PER_SECOND:
		return {}
	if ResourceManager.get_amount(ResourceManager.Type.FOOD) < PopulationManager.food_due() * 4:
		return {}
	var step: Dictionary = _build_step("house", "OBJ_WHY_HOUSE_ROOM")
	if step.is_empty():
		# Casas al tope: el Nucleo mas alto deja levantar mas (1.2).
		step = core_step_for_limit("house")
	if step.is_empty() or not _paid_with_surplus(step, target, outer):
		return {}
	return step

## Una decoracion cuando la moral flojea (la moral pesa en la produccion y en el
## asedio, docs/17): la mas barata que el rango abre y se paga con lo que sobra.
static func _decoration_step(target: Dictionary, outer: Dictionary = {}) -> Dictionary:
	if PopulationManager.get_morale() >= DECORATE_BELOW_MORALE:
		return {}
	for deco_id in ["garden", "fountain"]:
		if not Rules.check_rank(deco_id):
			continue
		var step: Dictionary = _build_step(deco_id, "OBJ_WHY_DECORATE")
		if not step.is_empty() and _paid_with_surplus(step, target, outer):
			return step
	return {}

## Lo que hay que guardar para el paso (y para el paso de fuera, si el paso es
## su receta de taller): lo mayor de los dos por recurso, y dos sueldos de tropa.
static func _keep_for(target: Dictionary, outer: Dictionary = {}) -> Dictionary:
	var keep: Dictionary = step_cost(target).duplicate()
	if not outer.is_empty():
		var more: Dictionary = step_cost(outer)
		for type in more:
			keep[type] = maxi(int(keep.get(type, 0)), int(more[type]))
	keep[ResourceManager.Type.GOLD] = int(keep.get(ResourceManager.Type.GOLD, 0)) + _army_upkeep() * 2
	return keep

## Las recetas que sacan de la bolsa lo que sobra: material -> recurso que gasta.
const ROOM_RECIPES := {"fuel": "oil", "planks": "wood", "beams": "steel", "ingots": "gold"}

## "Fabrica combustible con el petroleo que sobra" cuando la bolsa esta a rebosar
## y lo que le falta al paso no puede entrar. {} si hay sitio, al paso no le
## falta nada de la bolsa o no sobra para ninguna receta.
static func _make_room_step(target: Dictionary, outer: Dictionary = {}) -> Dictionary:
	var cap: int = ResourceManager.get_storage_cap()
	if ResourceManager.get_total_stored() < int(float(cap) * CROWDED_BAG):
		return {}
	var short := false
	for res in missing_for(target):
		if not ResourceManager.is_material_name(String(res)):
			short = true
	if not short:
		return {}
	var keep: Dictionary = _keep_for(target, outer)
	var best: Dictionary = {}
	var best_excess := 0
	for material in ROOM_RECIPES:
		var source: String = GameConfig.get_material_source(material)
		if source == "" or Rules.count_building(source) < 1:
			continue
		var recipe: Dictionary = material_recipe(material)
		var cost: Dictionary = recipe.get("cost", {})
		if cost.is_empty():
			continue
		# Cuantas vueltas se pagan enteras con lo que sobra.
		var runs: int = GameConfig.process_batch_max
		for res_name in cost:
			var type: int = ResourceManager.name_to_type(String(res_name))
			var spare: int = ResourceManager.get_amount(type) - int(keep.get(type, 0))
			runs = mini(runs, spare / maxi(1, int(cost[res_name])))
		if runs < 1:
			continue
		var main_type: int = ResourceManager.name_to_type(String(ROOM_RECIPES[material]))
		var excess: int = ResourceManager.get_amount(main_type) - int(keep.get(main_type, 0))
		if excess > best_excess:
			best_excess = excess
			var per_run: int = int((recipe.get("produces", {}) as Dictionary).get(material, 1))
			best = {"kind": "make", "id": material, "building": source, "amount": per_run * runs,
				"why": "OBJ_WHY_MAKE_ROOM"}
	return best

## ¿Se paga `step` sin tocar lo que el paso necesita?
static func _paid_with_surplus(step: Dictionary, target: Dictionary, outer: Dictionary = {}) -> bool:
	var keep: Dictionary = _keep_for(target, outer)
	var cost: Dictionary = step_cost(step)
	for type in cost:
		if ResourceManager.get_amount(type) - int(keep.get(type, 0)) < int(cost[type]):
			return false
	return true

## Mientras se ahorra con la bolsa casi llena: investigar con lo que sobra (lo
## que el paso no pide). Produccion primero, luego moral (pesa en el asedio,
## docs/17) y logistica. {} si no hay Laboratorio, ya se investiga algo, el paso
## no espera nada o no sobra para ninguna.
static func _surplus_research_step(target: Dictionary, any_bag: bool = false, outer: Dictionary = {}) -> Dictionary:
	if Rules.count_building("laboratory") == 0 or TechTreeManager.is_researching():
		return {}
	if not any_bag and ResourceManager.get_total_stored() < int(float(ResourceManager.get_storage_cap()) * ROOMY_BAG):
		return {}
	if missing_for(target).is_empty():
		return {}
	for tech_id in SURPLUS_TECH_PATH:
		if TechTreeManager.is_researched(tech_id):
			continue
		if not TechTreeManager.get_missing_prerequisites(tech_id).is_empty():
			continue
		var step := {"kind": "research", "id": tech_id, "why": "OBJ_WHY_SURPLUS_RESEARCH"}
		if _paid_with_surplus(step, target, outer):
			return step
	return {}

## Subir de nivel el productor del recurso que frena el paso, pagado solo con lo
## que sobra: cada recurso de la mejora sale de lo que hay por encima de lo que
## el paso cuesta. {} si nada frena, no hay productor que subir o no sobra.
static func _surplus_upgrade_step(target: Dictionary, net: Dictionary, any_bag: bool = false, outer: Dictionary = {}) -> Dictionary:
	if not any_bag and ResourceManager.get_total_stored() < int(float(ResourceManager.get_storage_cap()) * ROOMY_BAG):
		return {}
	var slow: String = _slowest_missing(target, net)
	if slow == "":
		return {}
	var building_id: String = PRODUCER_OF.get(slow, "")
	if building_id == "" or String(target.get("id", "")) == building_id:
		return {}
	var lowest: Node = _lowest_level(building_id)
	if lowest == null:
		return {}
	var level: int = int(lowest.get_meta("level", 1))
	if level >= GameConfig.max_building_level or ProductionManager.is_constructing(lowest):
		return {}
	var step := {"kind": "upgrade", "id": building_id, "level": level + 1, "pick": "lowest",
		"why": "OBJ_WHY_SURPLUS_UPGRADE"}
	# Se guarda lo del paso y dos sueldos de la tropa, como en las compras.
	return step if _paid_with_surplus(step, target, outer) else {}

# ══════════════════════════════════════════════════════════════════════
# Cuentas
# ══════════════════════════════════════════════════════════════════════

## Saldo por segundo de cada recurso con lo que hay en pie ahora mismo: produccion
## (con moral, nivel y tecnologia) menos lo que come la gente y cobra la tropa.
## Sin la Tormenta: es la cuenta de un dia normal, no la del peor.
static func net_rates() -> Dictionary:
	var rates := {"gold": 0.0, "wood": 0.0, "steel": 0.0, "oil": 0.0, "food": 0.0}
	var morale_mult: float = PopulationManager.get_morale_multiplier()
	for info in GridManager.buildings_view():
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
		var mult: float = (GameConfig.get_production_multiplier(level) + GameConfig.tech_production_bonus + GameConfig.rank_production_bonus) * morale_mult
		var interval: float = data.production_interval
		if data.id == ProductionManager.FARM_ID:
			# La Granja rinde lo que su cultivo, en lo que dura el cultivo.
			var crop: Dictionary = GameConfig.get_crop(ProductionManager.get_crop(node))
			interval = float(crop.get("duration", interval))
		var base: Dictionary = ProductionManager.base_cycle_production(node, data)
		for res_name in base:
			rates[res_name] = float(rates.get(res_name, 0.0)) + float(base[res_name]) * mult / interval
	if ProgressionManager.current_phase >= GameConfig.Phase.SETTLEMENT:
		var early: bool = ProgressionManager.current_phase < GameConfig.Phase.SURVIVAL
		var interval: float = GameConfig.early_consumption_interval if early else GameConfig.consumption_interval
		var eat: float = float(PopulationManager.get_population() * GameConfig.food_per_pop) \
			* maxf(0.1, 1.0 - GameConfig.tech_consumption_reduction) / interval
		rates["food"] -= eat
	rates["gold"] -= float(_army_upkeep()) / GameConfig.army_upkeep_interval
	return rates

## Lo que cobra la tropa por ciclo de sueldo, en oro.
static func _army_upkeep() -> int:
	var upkeep := 0
	for unit_id in GameConfig.get_unit_ids():
		upkeep += ArmyManager.get_count(unit_id) * int(GameConfig.get_unit_def(unit_id).get("upkeep_gold", 0))
	return upkeep

## Subir el Nucleo cuando su tope frena a `building_id` (1.2): {"kind": "core"}
## si ya esta lleno, un nivel mas alto lo sube y el Nucleo puede apuntar a ese
## nivel (no esta en obras ni al maximo, y se cumple lo que pide); {} si no.
static func core_step_for_limit(building_id: String, why: String = "OBJ_WHY_CORE_LIMIT") -> Dictionary:
	if Rules.check_building_limit(building_id) or not CoreLevel.raises_limit(building_id):
		return {}
	if not CoreLevel.can_aim():
		return {}
	return {"kind": "core", "id": GameConfig.CORE_ID, "level": CoreLevel.next_level(), "why": why,
		"for": building_id}

## Lo que cuesta el paso, indexado por ResourceManager.Type. Vacio si no cuesta.
static func step_cost(step: Dictionary) -> Dictionary:
	match String(step.get("kind", "")):
		"core":
			return CoreLevel.cost(int(step.get("level", CoreLevel.next_level())))
		"build":
			var data: BuildingData = Rules.load_building_data(String(step["id"]))
			return data.get_cost() if data != null else {}
		"upgrade":
			var data: BuildingData = Rules.load_building_data(String(step["id"]))
			return GameConfig.get_upgrade_cost(data, int(step["level"])) if data != null else {}
		"research":
			var cost: Dictionary = {}
			var raw_tech: Dictionary = TechTreeManager.get_tech(String(step["id"])).get("cost", {})
			for res_name in raw_tech:
				cost[ResourceManager.name_to_type(res_name)] = int(raw_tech[res_name])
			return cost
		"make":
			var cost: Dictionary = {}
			var runs: int = maxi(1, int(step.get("runs", 1)))
			for res_name in material_recipe(String(step["id"])).get("cost", {}):
				cost[ResourceManager.name_to_type(res_name)] = int(material_recipe(String(step["id"]))["cost"][res_name]) * runs
			return cost
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

## Comprar comida con el oro que sobre, o vender lo que sobre por oro (para el
## sueldo de la tropa), cuando lo que hay de `res` no llega a dos ciclos. {} si
## no hay hambre o no hay con que. Lo que espera en los edificios cuenta:
## recogerlo es gratis y no pide Mercado.
static func _food_market_step(res: String) -> Dictionary:
	# Sin Mercado no se compra ni se vende (2026-09-28).
	if Rules.count_building("market") == 0:
		return {}
	var upkeep: int = _army_upkeep()
	var due: int = PopulationManager.food_due() if res == "food" else upkeep
	var have: int = ResourceManager.get_amount(ResourceManager.name_to_type(res)) \
		+ int(ProductionManager.get_all_stock().get(res, 0))
	if have >= due * 2:
		return {}
	var wanted: int = maxi(MIN_SALE, due * 4 - have)
	if res == "food":
		var gold_spare: int = ResourceManager.get_amount(ResourceManager.Type.GOLD) - upkeep * 2
		var price: int = maxi(1, MarketManager.get_buy_price("food"))
		var can: int = mini(wanted, gold_spare / price)
		if can >= MIN_SALE and ResourceManager.get_free_space() >= can:
			return {"kind": "buy", "id": "food", "amount": can, "why": "OBJ_WHY_HUNGRY"}
	# Vender lo que no se come: el acero y el petroleo primero.
	for other in ["oil", "steel", "wood"]:
		if other == res or not ResourceManager.is_unlocked_by_name(other):
			continue
		var stock: int = ResourceManager.get_amount(ResourceManager.name_to_type(other))
		var keep: int = 0
		if stock - keep < MIN_SALE:
			continue
		var sell_price: int = maxi(1, MarketManager.get_sell_price(other))
		var units: int = mini(stock - keep, maxi(MIN_SALE, int(ceil(float(wanted) / float(sell_price)))))
		# El oro tiene que caber (el que no cabe se tira). Con hambre de oro para
		# la tropa se vende igual un poco: es eso o que deserte.
		if sell_price > 1:
			units = mini(units, maxi(MIN_SALE, ResourceManager.get_free_space() / (sell_price - 1)))
		return {"kind": "sell", "id": other, "amount": units, "why": "OBJ_WHY_HUNGRY"}
	return {}

## La siguiente tecnologia de almacen que se puede investigar, o {} si no queda
## ninguna o ya se esta investigando algo (una a la vez).
static func _storage_tech_step() -> Dictionary:
	if TechTreeManager.is_researching():
		return {}
	# Se investiga en el Laboratorio: sin el, lo primero es levantarlo.
	if Rules.count_building("laboratory") == 0:
		var lab: Dictionary = _build_step("laboratory", "OBJ_WHY_LABORATORY")
		return lab
	for tech_id in STORAGE_TECH_PATH:
		if TechTreeManager.is_researched(tech_id):
			continue
		if not TechTreeManager.get_missing_prerequisites(tech_id).is_empty():
			continue
		return {"kind": "research", "id": tech_id, "why": "OBJ_WHY_STORAGE_TECH"}
	return {}

## Vender lo que sobra si la bolsa esta a rebosar y al paso le falta oro o madera.
## Solo se vende lo que el paso no pide, y lo justo para que el oro quepa: con la
## bolsa llena, cada unidad vendida vale un oro (el resto no cabe y se pierde).
static func _sell_step(target: Dictionary) -> Dictionary:
	if Rules.count_building("market") == 0:
		return {}
	var cap: int = ResourceManager.get_storage_cap()
	if ResourceManager.get_total_stored() < int(float(cap) * CROWDED_BAG):
		return {}
	var missing: Dictionary = missing_for(target)
	var food_short: bool = ResourceManager.get_amount(ResourceManager.Type.FOOD) < PopulationManager.food_due() * 2
	# Los materiales no se compran: los hace el taller (make_step_for).
	for res in missing.keys():
		if ResourceManager.is_material_name(String(res)):
			missing.erase(res)
	if missing.is_empty() and not food_short:
		return {}
	var cost: Dictionary = step_cost(target)
	# Falta madera, acero o petroleo y sobra oro: se compra. Comprar ademas hace
	# sitio (sale mas oro del que entra de lo comprado), que con la bolsa llena es
	# justo lo que hace falta.
	var gold_spare: int = ResourceManager.get_amount(ResourceManager.Type.GOLD) \
		- int(cost.get(ResourceManager.Type.GOLD, 0)) - _army_upkeep() * 2
	if food_short:
		missing["food"] = PopulationManager.food_due() * 4 - ResourceManager.get_amount(ResourceManager.Type.FOOD)
	for res in ["food", "wood", "steel", "oil"]:
		if not missing.has(res) or not ResourceManager.is_unlocked_by_name(res):
			continue
		var buy_price: int = maxi(1, MarketManager.get_buy_price(res))
		var can: int = mini(int(missing[res]), gold_spare / buy_price)
		# Lo que falta puede ser menos que MIN_SALE (los 16 de acero de una viga).
		if can >= mini(MIN_SALE, int(missing[res])) and can > 0:
			return {"kind": "buy", "id": res, "amount": can, "why": "OBJ_WHY_BUY"}
	var best := ""
	var best_excess := 0
	# La comida va primero: se vende casi a 1 de oro por unidad, asi que con la
	# bolsa llena es lo unico que se convierte en oro sin tirar nada. Sin ella,
	# la sonda se quedo horas ante el CG nivel 3 con la bolsa llena de comida y
	# sin hueco para el oro (2026-10-14). Se guardan ocho ciclos.
	for res in ["food", "oil", "steel", "wood"]:
		var type: int = ResourceManager.name_to_type(res)
		if not ResourceManager.is_unlocked(type) or missing.has(res):
			continue
		var keep: int = int(cost.get(type, 0))
		if res == "food":
			keep += PopulationManager.food_due() * 8
		var excess: int = ResourceManager.get_amount(type) - keep
		# Lo que cabe: el oro de mas se tiraria (hasta 8.000 de oro por partida
		# con el minimo de MIN_SALE de antes, 2026-10-12). Gana la venta mas
		# grande que quepa. Si lo que falta no es oro, el oro de la venta paga la
		# compra del siguiente vistazo.
		var fit: int = _sale_that_fits(res, excess) if excess >= 5 else 0
		if fit > best_excess:
			best = res
			best_excess = fit
	# Una venta de menos de MIN_SALE no saca a nadie de la bolsa llena: la
	# sonda vendia 7 de comida cada 30 s durante minutos sin avanzar
	# (2026-10-16). Entonces manda _make_room_step o lo que se hace mientras se
	# ahorra, que si gastan.
	if best == "" or best_excess < MIN_SALE:
		return {}
	return {"kind": "sell", "id": best, "amount": best_excess, "why": "OBJ_WHY_SELL"}

## Cuanto de `res` (hasta `wanted`) se puede vender sin que el oro que trae se
## salga de la bolsa: vender X deja X de sitio y mete precio*X de oro. 0 si no
## llega a un lote que merezca la pena (5).
static func _sale_that_fits(res: String, wanted: int) -> int:
	var price: int = maxi(1, MarketManager.get_sell_price(res))
	var fits: int = wanted if price <= 1 else ResourceManager.get_free_space() / (price - 1)
	var amount: int = mini(wanted, fits)
	return amount if amount >= 5 else 0

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

## Lo que el coste ocupa de la bolsa: los materiales van al taller y no cuentan.
static func _cost_total(cost: Dictionary) -> int:
	var total := 0
	for type in cost:
		if ResourceManager.is_material(int(type)):
			continue
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
	var room: int = PopulationManager.get_max_population() - PopulationManager.get_population() + _room_on_the_way()
	return PopulationManager.get_free_workers() + room < workers_needed

## El sitio de las casas que aun se estan levantando: la gente ya viene de camino.
## Sin esto, con la primera Casa en obra el panel pedia otra igual (dos casas de
## golpe en el minuto 4, y sin oro para la Mina: ronda de pruebas 1.0, line_probe).
static func _room_on_the_way() -> int:
	var room := 0
	for info in GridManager.buildings_view():
		var data: BuildingData = info["data"]
		if data.population_capacity <= 0 or data.is_core:
			continue
		var node: Node = info.get("node")
		if node != null and ProductionManager.is_constructing(node):
			room += data.population_capacity
	return room

## Construir `building_id` si el tope, los requisitos y el mapa lo permiten.
## Vacio si no: un paso que el jugador no puede dar no se le propone.
static func _build_step(building_id: String, why: String) -> Dictionary:
	if not Rules.check_building_limit(building_id) or not Rules.check_prerequisites(building_id):
		return {}
	# Cerrado por el Nucleo o sin plano (1.2): no se propone.
	if not Rules.check_core_level(building_id) or not Rules.check_blueprint(building_id):
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
	var more: Dictionary = _build_step(building_id, why)
	if not more.is_empty():
		return more
	# Sin hueco por el tope y el Nucleo mas alto lo sube: subir el Nucleo (1.2).
	var core: Dictionary = core_step_for_limit(building_id)
	if not core.is_empty():
		return core
	# Comida sin hueco para otra Granja (tope de la era): un Muelle de pesca en
	# la orilla, si queda un banco de peces con sitio (feat/muelle-pesca). Solo
	# como apoyo: la linea nunca lo pide.
	if res == "food":
		var dock: Dictionary = _build_step(FISHING_DOCK_ID, "OBJ_WHY_FISHING_DOCK")
		if not dock.is_empty():
			return dock
	# Sin sitio o sin tope para otro: subir de nivel el que menos rinde. Un nivel 2
	# rinde un 60% mas, y hasta aqui nada en el juego lo sugeria.
	var lowest: Node = _lowest_level(building_id)
	if lowest == null:
		return {}
	var level: int = int(lowest.get_meta("level", 1))
	if level >= GameConfig.max_building_level or ProductionManager.is_constructing(lowest):
		return {}
	# Una mejora que pide repuestos (solo salen de las escaramuzas) no se propone
	# como apoyo sin tenerlos: el motivo de salir lo da sortie_step().
	if ResourceManager.get_amount(ResourceManager.Type.PARTS) < GameConfig.upgrade_parts_needed(building_id, level + 1):
		return {}
	return {"kind": "upgrade", "id": building_id, "level": level + 1, "pick": "lowest", "why": why}

## El edificio de ese tipo con el nivel mas bajo que no este en obras, o null.
static func _lowest_level(building_id: String) -> Node:
	var best: Node = null
	for info in GridManager.buildings_view():
		if (info["data"] as BuildingData).id != building_id:
			continue
		var node: Node = info["node"]
		if ProductionManager.is_constructing(node) or BuildingHealth.is_ruined(node):
			continue
		if best == null or int(node.get_meta("level", 1)) < int(best.get_meta("level", 1)):
			best = node
	return best

## El edificio al que se refiere un paso de mejora: el de nivel mas bajo si el
## paso lo pide ("pick": "lowest"), o el primero (el Cuartel General es uno solo).
static func upgrade_node(step: Dictionary) -> Node:
	if String(step.get("pick", "")) == "lowest":
		return _lowest_level(String(step["id"]))
	return _first_building(String(step["id"]))

## Recurso que un edificio necesita desbloqueado para que tenga sentido pedirlo.
static func _needs_unlocked(building_id: String) -> String:
	# El Cuartel ya no pide acero (cuartel temprano, 2026-10-17): solo oro.
	match building_id:
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
	for info in GridManager.buildings_view():
		var data: BuildingData = info["data"]
		if data.is_producer() and BuildingHealth.is_ruined(info["node"]):
			return info["node"]
	return null

## "Repara el ..." si hay un productor en ruinas (fuera de la tormenta), o {}.
static func _repair_step() -> Dictionary:
	var ruined: Node = _ruined_producer()
	if ruined == null:
		return {}
	return {"kind": "repair", "id": (GridManager.get_building_info(ruined)["data"] as BuildingData).id,
		"why": "OBJ_WHY_REPAIR"}

static func _first_building(building_id: String) -> Node:
	for info in GridManager.buildings_view():
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
	var sortie_placed := false
	for entry in LINE:
		# La primera escaramuza va justo antes de la guarnicion: es lo primero que
		# se hace con la tropa. Tambien sin Diezmo (Constructor), donde la
		# guarnicion no es un paso pero pelear si. Con el Cuartel temprano
		# (2026-10-17) va detras del primer soldado (`sortie_row: after`), y una
		# sola vez.
		var sortie_before: bool = String(entry["kind"]) == "train" and bool(entry.get("any", false)) \
			and String(entry.get("sortie_row", "")) != "after"
		if not sortie_placed and sortie_before:
			sortie_placed = true
			var sortie_done: bool = TutorialManager.is_first_sortie_done()
			var sortie_row := {"text": Tr.t("OBJ_ROUTE_FIRST_SORTIE"), "done": sortie_done, "current": false}
			if not sortie_done and not current_found:
				sortie_row["current"] = true
				current_found = true
			rows.append(sortie_row)
		if not _entry_applies(entry):
			continue
		var sortie_after: bool = not sortie_placed and String(entry.get("sortie_row", "")) == "after"
		var done: bool = _line_entry_done(entry)
		var row := {"text": describe(entry)["title"], "done": done, "current": false}
		# En EL CAMINO cada fila es un paso: "Construye:" delante de cada
		# edificio sobraba (2026-10-04). Basta el nombre.
		if String(entry["kind"]) == "build":
			var bdata: BuildingData = Rules.load_building_data(String(entry["id"]))
			if bdata != null:
				row["text"] = bdata.get_display_name()
		if String(entry["kind"]) == "train":
			var as_step := _army_step(String(entry["id"]), int(entry["count"]), "", "train")
			as_step["any"] = bool(entry.get("any", false))
			row["text"] = describe(as_step)["title"]
		if not done and not current_found:
			row["current"] = true
			current_found = true
		rows.append(row)
		if sortie_after:
			sortie_placed = true
			var first_done: bool = TutorialManager.is_first_sortie_done()
			var first_row := {"text": Tr.t("OBJ_ROUTE_FIRST_SORTIE"), "done": first_done, "current": false}
			if not first_done and not current_found:
				first_row["current"] = true
				current_found = true
			rows.append(first_row)
	# Tres campanas: la otra llave del Ataque Final, en una fila.
	if GameMode.audit_needs_campaigns():
		var camps_done: bool = CombatManager.campaigns_all_complete() or ProgressionManager.final_audit != null
		var camp_row := {"text": Tr.t("OBJ_ROUTE_CAMPAIGNS") % CombatManager.campaigns_completed_count(),
			"done": camps_done, "current": false}
		if not camps_done and not current_found and ProgressionManager.is_milestone_completed("hq_max"):
			camp_row["current"] = true
			current_found = true
		rows.append(camp_row)
	if GameMode.audit_enabled():
		var won: bool = StormManager.is_halted()
		rows.append({"text": Tr.t("OBJ_ROUTE_FINAL"), "done": won, "current": not current_found and not won})
	rows.append({"text": Tr.t("OBJ_ROUTE_MARKET"), "current": false,
		"done": ProgressionManager.is_milestone_completed("market_10_trades")})
	return rows

static func _line_entry_done(entry: Dictionary) -> bool:
	match String(entry["kind"]):
		"build":
			return Rules.count_building(String(entry["id"])) >= entry_count(entry)
		"upgrade":
			var node: Node = _first_building(String(entry["id"]))
			return node != null and int(node.get_meta("level", 1)) >= int(entry["level"])
		"train":
			return _train_progress(entry) >= int(entry["count"])
	return false

## Como conseguir `res` (un recurso o un material del taller), en una linea
## para el jugador, o "". La usan el tutorial (TutorialManager.step_how) y
## ¿QUE HACER? (describe), para que nunca se diga "te falta" sin decir como
## (2026-10-17, fix/tutorial-materiales).
static func how_to_get(res: String) -> String:
	if ResourceManager.is_material_name(res):
		var source: String = GameConfig.get_material_source(res)
		var src: BuildingData = Rules.load_building_data(source) if source != "" else null
		var src_name: String = src.get_display_name() if src != null else source
		if source != "" and Rules.count_building(source) > 0:
			var proc_name: String = Tr.t(String(material_recipe(res).get("name", "")))
			return Tr.ti("GUIDE_HOW_MAKE") % [Tr.res_cap(res), src_name, proc_name]
		if source != "":
			return Tr.t("GUIDE_HOW_MAKE_FIRST") % [Tr.res_cap(res), src_name]
		return ""
	if not ResourceManager.is_unlocked_by_name(res):
		return Tr.t("LBL_NEEDS_UNLOCK_ONE") % [Tr.res_cap(res), Tr.t("UNLOCK_HINT_" + res.to_upper())]
	if res == "wood":
		return Tr.ti("GUIDE_HOW_WOOD") if Rules.count_building("sawmill") > 0 else Tr.ti("GUIDE_HOW_WOOD_HAND")
	if res == "gold":
		return Tr.ti("GUIDE_HOW_GOLD_MINE") if Rules.count_building("gold_mine") > 0 else Tr.ti("GUIDE_HOW_GOLD_HAND")
	var producer: String = String(PRODUCER_OF.get(res, ""))
	if producer == "":
		return ""
	var pdata: BuildingData = Rules.load_building_data(producer)
	var pname: String = pdata.get_display_name() if pdata != null else producer
	if Rules.count_building(producer) > 0:
		return Tr.ti("GUIDE_HOW_COLLECT") % [Tr.res_name(res), pname]
	return Tr.t("GUIDE_HOW_BUILD_PRODUCER") % [Tr.res_name(res), pname]

## Una linea de how_to_get() por cada cosa de `missing` (nombre -> cantidad),
## sin repetir.
static func how_lines(missing: Dictionary) -> Array:
	var out: Array = []
	for res in missing:
		var line: String = how_to_get(String(res))
		if line != "" and not line in out:
			out.append(line)
	return out

## {"title", "why", "blocker"} ya traducidos. `blocker` vacio si el paso se puede
## dar ahora mismo; si no, lo que falta y como conseguirlo.
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
		"sell":
			title = Tr.t("OBJ_DO_SELL") % [int(step["amount"]), Tr.res_name(String(step["id"]))]
		"buy":
			title = Tr.t("OBJ_DO_BUY") % [int(step["amount"]), Tr.res_name(String(step["id"]))]
		"research":
			var tech: Dictionary = TechTreeManager.get_tech(String(step["id"]))
			title = Tr.t("OBJ_DO_RESEARCH") % Tr.t(String(tech.get("name", step["id"])))
		"make":
			var src: BuildingData = Rules.load_building_data(String(step.get("building", "")))
			title = Tr.t("OBJ_DO_MAKE") % [int(step.get("amount", 0)), Tr.res_name(String(step["id"])),
				src.get_display_name() if src != null else String(step.get("building", ""))]
		"siege":
			title = Tr.t("OBJ_DO_SIEGE")
		"sortie":
			title = Tr.t("OBJ_DO_FIRST_SORTIE")
		"sortie_offer":
			title = Tr.t("OBJ_DO_SORTIE")
		"campaign":
			var domain: String = String(step.get("id", "land"))
			title = Tr.t("OBJ_DO_CAMPAIGN") % [Tr.t(ExpeditionGenerator.campaign_mission_name_key(domain,
				maxi(0, CombatManager.campaign_won(domain)))), Tr.t("CAMP_NAME_" + domain.to_upper())]
		"contract":
			title = Tr.t("OBJ_DO_CONTRACT") % Tr.t("CONTRACT_SRC_" + String(step.get("id", "")).to_upper())
		"resummon":
			title = Tr.t("OBJ_DO_RESUMMON")
		"core":
			title = Tr.t("OBJ_DO_CORE") % int(step.get("level", CoreLevel.next_level()))
		_:
			match String(step.get("why", "")):
				"OBJ_WHY_SANDBOX_BUILT":
					title = Tr.t("OBJ_DO_SANDBOX_BUILT")
				"OBJ_WHY_SANDBOX_MODE":
					title = Tr.t("OBJ_DO_SANDBOX_MODE")
				"OBJ_WHY_RUN_OVER":
					title = Tr.t("LBL_RUN_OVER_TITLE")
				_:
					title = Tr.t("OBJ_DO_SANDBOX")
	var why: String = String(step.get("why", ""))
	# En Constructor el nivel 3 del Cuartel General es la meta, no una convocatoria.
	if why == "OBJ_WHY_HQ_3" and GameMode.capstone_wins():
		why = "OBJ_WHY_HQ_3_BUILDER"
	# Sin Diezmo el cuartel no es para la guarnicion: es lo que pide el Cuartel General.
	elif why == "OBJ_WHY_BARRACKS" and not GameMode.tithe_enabled():
		why = "OBJ_WHY_BARRACKS_BUILDER"
	# Lo que falta y COMO conseguirlo (2026-10-17, fix/tutorial-materiales): no
	# basta con "Te falta: 6 tablones"; debajo, una linea por cosa que falta.
	var block_text: String = blocker(step)
	if kind == "build" and block_text != "":
		var data: BuildingData = Rules.load_building_data(String(step["id"]))
		if data != null:
			var how: Array = how_lines(Rules.missing_cost(data))
			if not how.is_empty():
				block_text += "\n" + "\n".join(how)
	return {"title": title, "why": Tr.t(why), "blocker": block_text}

## Por que no se puede dar el paso ahora, o "" si se puede.
static func blocker(step: Dictionary) -> String:
	var kind: String = String(step.get("kind", ""))
	match kind:
		"build":
			var data: BuildingData = Rules.load_building_data(String(step["id"]))
			if data == null:
				return ""
			# Todo lo que lo impide, una cosa por linea (2026-10-17): antes salia
			# solo lo primero ("Sin trabajadores disponibles") y lo que faltaba de
			# recursos o del taller quedaba escondido detras.
			return "\n".join(Rules.block_reasons(data))
		"upgrade":
			var node: Node = upgrade_node(step)
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
		"research":
			var reason: String = TechTreeManager.get_research_blocker(String(step["id"]))
			if reason == "":
				return ""
			if reason == "TECH_BLOCK_COST":
				var short: Dictionary = TechTreeManager.get_missing_cost(String(step["id"]))
				return Tr.t("OBJ_MISSING") % Tr.amount_list(short)
			return Tr.t(reason)
		"make":
			var recipe: Dictionary = material_recipe(String(step["id"]))
			var need := {}
			for res_name in recipe.get("cost", {}):
				var short: int = int(recipe["cost"][res_name]) - ResourceManager.get_amount(ResourceManager.name_to_type(res_name))
				if short > 0:
					need[res_name] = short
			return "" if need.is_empty() else Tr.t("OBJ_MISSING") % Tr.amount_list(need)
		"sortie":
			var party: Dictionary = first_sortie_party()
			if party.is_empty():
				return Tr.t("MSG_NO_UNITS")
			var check: Dictionary = CombatManager.can_launch(party)
			return "" if bool(check["ok"]) else Tr.t(String(check["reason"]))
		"campaign":
			var domain: String = String(step.get("id", "land"))
			var lock_text: String = campaign_lock_text(domain)
			if lock_text != "":
				return lock_text
			if CombatManager.campaign_units_home(domain).is_empty():
				return Tr.t("CAMP_NO_UNITS_" + domain.to_upper())
			return ""
		"core":
			if ProgressionManager.is_core_upgrading():
				return Tr.t("OBJ_IN_PROGRESS")
			return "\n".join(CoreLevel.block_lines())
		"siege":
			if ProgressionManager.is_final_audit_active():
				return Tr.t("OBJ_SIEGE_UNDER_WAY")
			var reason: String = CombatManager.final_audit_block_reason()
			return Tr.t(reason) if reason != "" else ""
	return ""

# ══════════════════════════════════════════════════════════════════════
# La meta de la calma (doc 21 §2.4)
# ══════════════════════════════════════════════════════════════════════

## La segunda linea de ¿QUE HACER?: lo que pide la Orden de la Regencia antes de
## la proxima Tormenta, o {} si no toca (sin reloj, sin Diezmo en el modo, ya
## entregado o con los Tasadores en la puerta). Va aparte de next_step() a
## proposito: no es un paso de la linea, y la sonda de la linea no la sigue.
##   {"kind": "order", "id": recurso, "amount": n, "pct": rebaja en %, "text": traducido}
static func calm_goal() -> Dictionary:
	if not StormManager.order_visible():
		return {}
	if StormManager.get_phase() == StormCycle.Phase.TITHE:
		return {}
	var order: Dictionary = StormManager.get_order()
	if order.is_empty() or bool(order.get("done", false)):
		return {}
	var res: String = String(order["res"])
	var amount: int = int(order["amount"])
	var pct: int = roundi(GameConfig.storm_order_delivery_pct * 100.0)
	return {
		"kind": "order", "id": res, "amount": amount, "pct": pct,
		"text": Tr.t("OBJ_CALM_GOAL") % [amount, Tr.res_name(res), pct],
	}
