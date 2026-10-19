extends Node
## Central configuration table for all tunable game values.
## dev_mode (fast timings) is on in the editor and off in exports; see below.

# ── Master Controls ──

## dev_mode comprime todas las duraciones (dev_time_scale) y enseña los botones de
## desarrollo (borrar partida en ResourceHUD, combate de prueba en SkirmishPanel).
## No se decide a mano: vale true cuando el juego corre desde el editor (F5, tests,
## sondas) y false en cualquier exportado, sea release o debug. Así un .exe que se
## reparte nunca sale con tiempos de prueba por un commit despistado.
## Para forzarlo, argumentos de usuario tras `--`:
##   TormentaImperial.exe -- --dev      exportado con tiempos de prueba
##   godot --path . -- --no-dev         editor con tiempos reales
var dev_mode := _resolve_dev_mode()
var time_multiplier := 1.0
## Cuanto se acelera todo en dev_mode. Estaba a 1/10 y Bryan, jugando, no llegaba a
## leer que pasaba: construir en 1 s y una tormenta cada 30 s convierten el ciclo en
## un borron. A 1/5 sigue siendo una partida de minutos, pero se entiende.
var dev_time_scale := 0.2

# ── Population & Morale Constants ──

var morale_start := 75
var morale_min := 0
var morale_max := 100
var morale_growth_threshold := 30
var morale_danger_threshold := 20
var morale_satisfied_recovery := 3
var morale_unsatisfied_penalty := -8
var population_start := 5
var consumption_interval := 30.0
var growth_interval := 20.0

# ── Random Event Timing ──

var event_interval_min := 120.0
var event_interval_max := 300.0
var event_interval_min_dev := 30.0
var event_interval_max_dev := 60.0

# ── Starting Resources ──

## 2026-10-12 (docs/22 §11): 30 de oro mas y 20 de madera menos. La madera
## sobraba (la sonda la vendia en el minuto 5) y el oro era lo que frenaba la
## Fundicion. 330 + 180 + 80 = 590 deja hueco en la bolsa de 600 de la era 1, y
## Supervivencia (x0.75: 135 de madera) sigue pagando aserradero + mina (130).
var starting_resources := {
	"gold": 330,
	"wood": 180,
	# Comida para los primeros minutos, hasta que la primera Granja rinda
	# (2026-10-04). 580 en total: cabe en la bolsa de 600 de la era 1.
	"food": 80,
}

# ── Upgrade System ──

var max_building_level := 3

## Cost multiplier per level: level 1 = base cost, level 2 = 1.8x, level 3 = 3.0x
var upgrade_cost_multiplier := [1.0, 1.8, 3.0]

## Production multiplier per level
var upgrade_production_multiplier := [1.0, 1.6, 2.5]

## Lo que da subir de nivel lo que no produce (2026-09-28). Antes una vivienda,
## un almacen o una fuente subian de nivel sin cambiar nada.
## Vivienda: sitio para trabajadores por nivel (6 -> 9 -> 12).
var upgrade_capacity_multiplier := [1.0, 1.5, 2.0]
## Decoraciones: moral por nivel.
var upgrade_morale_multiplier := [1.0, 1.5, 2.0]
## Almacen: almacen extra por cada nivel por encima del 1.
var warehouse_level_bonus := 250

## Multiplicador de una tabla por nivel (1..max), 1.0 fuera de rango.
func level_mult(table: Array, level: int) -> float:
	if level < 1 or level > table.size():
		return 1.0
	return float(table[level - 1])

## Upgrade duration base (seconds), scaled by time_multiplier
var upgrade_base_duration := 15.0

# ── HQ Upgrade Override (capstone building, much more expensive) ──

## 2026-10-12 (docs/22 §11, Campaña de 4-6 h): el nivel 2 pide 3.000 de bolsa
## (antes 2.000) y los dos piden muchos mas materiales del taller (antes 15/10/15
## y 25/20/25). Los materiales van fuera de la bolsa, asi que alargan la era 3 con
## trabajo (vigas, lingotes y combustible que fabricar cada 25-30 s, y fundiciones
## y refinerias de mas que levantar) sin tocar el invariante 3.500 = bolsa maxima
## del nivel 3.
var hq_upgrade_costs := {
	# 2026-10-14: el doble de materiales otra vez (antes 100/70/100 y
	# 200/140/200). Con los lotes y el Nucleo haciendo las recetas de todos, el
	# taller va mucho mas rapido y la campana habia bajado a ~3 h 35 (docs/22 §11).
	# 2026-10-16: vigas 350 y 700 (antes 200 y 400). Con ¿QUE HACER? llenando las
	# esperas y las casas que ahora pide, la campana bajaba a ~4 h 10 y cuatro
	# partidas de diez se quedaban por debajo de las 4 h. Las vigas, y no el
	# combustible ni los lingotes, porque eran las que menos esperas dejaban
	# (hay hasta 6 fundiciones y el acero sobra en la era 3) (docs/22 §11).
	2: {"gold": 1300, "steel": 900, "oil": 500, "wood": 300, "beams": 350, "ingots": 140, "fuel": 200},
	3: {"gold": 1500, "steel": 800, "oil": 500, "wood": 700, "beams": 700, "ingots": 280, "fuel": 400},
}

# ── Building Limits (max per type, -1 = unlimited) ──
# Topes de la ERA 1 y de lo que no sube con la era. Los que suben estan en
# `building_limits_by_era` (seccion "Building Limit Helpers"); las decoraciones
# (BuildingData.is_decoration) no tienen tope aunque salgan aqui. Se lee siempre
# con get_building_limit(id), nunca a mano.

var building_limits := {
	"sawmill": 5,
	"gold_mine": 4,
	"foundry": 3,
	"refinery": 2,
	"warehouse": 5,
	# El Mercado y el Laboratorio abren el comercio y el arbol tecnologico
	# (2026-09-28): uno de cada basta.
	"market": 1,
	"laboratory": 1,
	# El Cuartel no tiene tope (Bryan, 18-10-2026): el freno es el del ejercito,
	# no el del mapa (army_capacity_max, army_training_slots_max y el sueldo).
	"barracks": -1,
	"tower": 6,
	"headquarters": 1,
	"house": 10,
	"garden": -1,
	"statue": 5,
	"fountain": 5,
	"road": -1,
	"farm": 6,
	# Edificios utiles de la 1.1: el tope de era 1 (lo que sube con la era esta
	# en building_limits_by_era, y la prueba exige que la era 1 coincida).
	"windmill": 2,
	"silo": 2,
	"tavern": 1,
	"carpentry": 1,
	"well": 3,
	"lighthouse": 1,
	"fuel_depot": 2,
	# Aire y mar (feat/aire-mar-reglas): el Astillero y el Aerodromo. SIN TOPE
	# desde 2026-10-18 (decision de Bryan, ronda final de la 1.1). Cada uno da un
	# hueco de entrenamiento y +4 de capacidad (army_capacity_per_building); los
	# frenan su precio (planchas, vigas, combustible), sus 3 / 4 trabajadores, el
	# sueldo de la tropa que permiten y el tope de despliegue del tablero (6).
	"shipyard": -1,
	"aerodrome": -1,
}

# ── Building Prerequisites (must have at least 1 of each listed) ──

## La Fundicion abre la era 2 y la Refineria la 3: no se sube de era sin la base
## de la anterior en pie (2026-09-28). Era 1 completa = madera, oro, gente y
## almacen; era 2 completa = acero y un Cuartel que la defienda.
var building_prerequisites := {
	"foundry": ["sawmill", "gold_mine", "house", "warehouse"],
	"market": ["gold_mine"],
	"laboratory": ["house"],
	# Y el Laboratorio (2026-10-12): la era 2 trae una obra mas y el arbol abierto
	# antes del petroleo, que es cuando se piden las tecnologias de almacen.
	"refinery": ["foundry", "barracks", "laboratory"],
	# Cuartel temprano (2026-10-17, feat/cuartel-temprano): de la era 1, sin
	# acero (120 oro + 80 madera + 10 tablones). Solo pide el Aserradero, de donde
	# salen los tablones: es la prioridad "despues de la madera" de Bryan. Entrena
	# infanteria ya; artilleria y tanques siguen con su era (ArmyManager.is_unlocked).
	"barracks": ["sawmill"],
	# La Torre pide acero y vigas, que llegan con la Fundicion; antes el Cuartel
	# ya implicaba la Fundicion. Ahora se dice: sin Fundicion no hay Torre.
	"tower": ["barracks", "foundry"],
	"headquarters": ["barracks", "refinery"],
	# Edificios utiles de la 1.1: cada uno pide lo que mejora o de lo que vive.
	"windmill": ["farm"],
	"silo": ["farm"],
	"tavern": ["house", "farm"],
	"carpentry": ["sawmill"],
	"well": ["house"],
	"lighthouse": ["warehouse"],
	"fuel_depot": ["refinery"],
	# Aire y mar (feat/aire-mar-reglas): barcos con acero (era 2), aviones con
	# combustible (era 3). El Astillero ademas tiene que tocar la costa
	# (PlacementRules.SHORE_ONLY).
	"shipyard": ["foundry"],
	"aerodrome": ["refinery"],
}

# ── Deposit Placement Rules (extractor next to its deposit) ──
#
# Decision del dueno (P1, 2026-09-14): cada extractor se levanta junto al
# yacimiento que explota, y sigue produciendo pasivamente como siempre. La
# produccion se lee como "cosechar ese bosque / esa veta", no como madera que
# aparece de la nada. Nada se agota por producir: el minado a mano en el
# yacimiento sigue igual.
#
# - `deposit`:  id del yacimiento (MapGenerator.DEPOSIT_TYPES).
# - `reach`:    0 = el edificio debe SOLAPAR el yacimiento (la Refineria se
#               planta sobre el pozo); 1 = alguna celda del edificio toca alguna
#               del yacimiento, diagonal incluida, sin pisarlo (nadie construye
#               encima de los arboles).
# - `consumes`: si al colocarlo el yacimiento desaparece (solo la Refineria,
#               como hasta ahora). Con alcance 1 nunca se consume.
# - `message`:  clave de Tr con el aviso al jugador cuando no se cumple.
#
# La misma regla vale para colocar y para MOVER: si no, se colocaba bien y luego
# se arrastraba a cualquier sitio.

var building_deposit_rules := {
	"refinery":  {"deposit": "oil_well",     "reach": 0, "consumes": true,  "message": "LBL_REQUIRES_DEPOSIT"},
	"sawmill":   {"deposit": "forest",       "reach": 1, "consumes": false, "message": "LBL_NEEDS_FOREST_NEAR"},
	"gold_mine": {"deposit": "gold_vein",    "reach": 1, "consumes": false, "message": "LBL_NEEDS_GOLD_VEIN_NEAR"},
	"foundry":   {"deposit": "iron_deposit", "reach": 1, "consumes": false, "message": "LBL_NEEDS_IRON_NEAR"},
}

## Regla de yacimiento de un edificio, o {} si construye donde quiera.
func get_deposit_rule(building_id: String) -> Dictionary:
	return building_deposit_rules.get(building_id, {})

# ── Storage ──
#
# El almacen es UNA bolsa compartida por los cuatro recursos, no un tope por
# recurso. Guardar oro tiene que significar no guardar acero: es lo que hace que
# el mercado sirva, que gastar antes de la Tormenta sea la jugada correcta y que
# llegar lleno al Diezmo sea una decision y no un descuido.
#
# Los dos extremos de la tabla estan fijados por razones distintas:
#
# - **Era 1 = 600 porque la apertura tiene que poder jugarse.** Se empieza con 500
#   (300 oro + 200 madera) y los dos primeros edificios que el juego pide, serreria
#   (80/50) y mina de oro (120/80), suman 330. Con un tope de 300 el jugador
#   arrancaba 200 por encima del limite y perdia recursos antes de tomar su primera
#   decision: el juego le quitaba cosas por existir, no por elegir mal. 600 sigue
#   siendo asfixiante frente a los 800 POR RECURSO de antes (1600 utiles en Era 1),
#   pero deja jugar la apertura y obliga a elegir a partir de ahi.
# - **Era 3 = 1000 porque cuadra con el precio de la victoria.** 1000 + 5x500 = 3500,
#   exactamente lo que cuesta la mejora del Cuartel General a Nv.3 (1500 oro + 800
#   acero + 500 petroleo + 700 madera). Para ganar hay que llegar con la bolsa llena
#   y los cinco almacenes en pie, que es justo cuando mas tienes que perder. Este
#   numero no se mueve sin mover tambien `hq_upgrade_costs`.

## Tope base de la bolsa, por era.
var base_storage_cap_by_era := {
	1: 600,
	2: 800,
	3: 1000,
}

var warehouse_storage_bonus := 500

## Bonificacion permanente de almacenamiento del arbol tecnologico (runtime).
var tech_storage_bonus := 0

# ── Building Processes (margins ~1.5x) ──

var building_processes := {
	"nucleo": [
		{"id": "wood_planks", "name": "PROC_WOOD_PLANKS", "duration": 30.0,
		 "cost": {"wood": 20}, "produces": {"wood": 35}},
		{"id": "iron_sheets", "name": "PROC_IRON_SHEETS", "duration": 45.0,
		 "cost": {"steel": 20}, "produces": {"steel": 30}},
		{"id": "water_pipes", "name": "PROC_WATER_PIPES", "duration": 60.0,
		 "cost": {"steel": 15, "wood": 10}, "produces": {"gold": 60}},
	],
	"sawmill": [
		{"id": "make_planks", "name": "PROC_MAKE_PLANKS", "duration": 20.0,
		 "cost": {"wood": 20}, "produces": {"planks": 5}},
		{"id": "refined_lumber", "name": "PROC_REFINED_LUMBER", "duration": 30.0,
		 "cost": {"wood": 15}, "produces": {"wood": 25, "gold": 5}},
		{"id": "charcoal", "name": "PROC_CHARCOAL", "duration": 25.0,
		 "cost": {"wood": 25}, "produces": {"steel": 12}},
	],
	"gold_mine": [
		{"id": "make_ingots", "name": "PROC_MAKE_INGOTS", "duration": 30.0,
		 "cost": {"gold": 30}, "produces": {"ingots": 3}},
		{"id": "deep_mining", "name": "PROC_DEEP_MINING", "duration": 35.0,
		 "cost": {"steel": 10}, "produces": {"gold": 35}},
		{"id": "gem_extraction", "name": "PROC_GEM_EXTRACTION", "duration": 60.0,
		 "cost": {"gold": 20, "steel": 5}, "produces": {"gold": 60}},
	],
	"foundry": [
		{"id": "make_beams", "name": "PROC_MAKE_BEAMS", "duration": 30.0,
		 "cost": {"steel": 20, "wood": 10}, "produces": {"beams": 4}},
		{"id": "alloy_smelting", "name": "PROC_ALLOY_SMELTING", "duration": 40.0,
		 "cost": {"steel": 20, "wood": 10}, "produces": {"steel": 45}},
		{"id": "armor_plates", "name": "PROC_ARMOR_PLATES", "duration": 45.0,
		 "cost": {"steel": 30}, "produces": {"steel": 15, "gold": 20}},
	],
	"refinery": [
		{"id": "make_fuel", "name": "PROC_MAKE_FUEL", "duration": 25.0,
		 "cost": {"oil": 15}, "produces": {"fuel": 5}},
		{"id": "fuel_distillation", "name": "PROC_FUEL_DISTILLATION", "duration": 30.0,
		 "cost": {"oil": 15}, "produces": {"oil": 25}},
		{"id": "chemical_processing", "name": "PROC_CHEMICAL_PROCESSING", "duration": 50.0,
		 "cost": {"oil": 20, "steel": 10}, "produces": {"oil": 18, "gold": 25}},
	],
	# Carpinteria (1.1): tablones sin ocupar el Aserradero, algo mas deprisa, y
	# muebles que se venden por oro. El Nucleo no los repite (core_skip_workshops).
	"carpentry": [
		{"id": "carpentry_planks", "name": "PROC_CARPENTRY_PLANKS", "duration": 15.0,
		 "cost": {"wood": 20}, "produces": {"planks": 5}},
		{"id": "carpentry_furniture", "name": "PROC_CARPENTRY_FURNITURE", "duration": 35.0,
		 "cost": {"wood": 15, "planks": 2}, "produces": {"gold": 30}},
	],
}

# ── Materiales (2026-09-28) ──
#
# Cada edificio especializado fabrica, con su recurso, un material para los
# edificios avanzados (el primer proceso de su lista en building_processes). El
# material aparece en el juego cuando se termina el primero de su edificio.
# Viven fuera de la bolsa compartida (ResourceManager: el taller del Nucleo).
var material_sources := {
	"planks": "sawmill",
	"ingots": "gold_mine",
	"beams": "foundry",
	"fuel": "refinery",
}

## El edificio que fabrica un material ("" si no es un material).
func get_material_source(res_name: String) -> String:
	return String(material_sources.get(res_name, ""))

## El material que fabrica un edificio ("" si ninguno).
func get_material_of(building_id: String) -> String:
	for m in material_sources:
		if material_sources[m] == building_id:
			return m
	return ""

# ══════════════════════════════════════════════════════════════════════
# ── Comida, Granja y produccion que se recoge (2026-10-04) ──
# ══════════════════════════════════════════════════════════════════════
# Decisiones de Bryan (tormenta-imperial-contexto/17): la gente come COMIDA en
# vez de madera y oro; la Granja la cultiva eligiendo cultivo por duracion; y
# TODO lo que producen los edificios se queda en el edificio hasta que el
# jugador lo recoge con un toque. Lleno, el edificio se para. Detalle y cifras
# en docs/02-economy.md y docs/03-buildings.md.

## Comida que come cada habitante en cada tic de consumo (30 s; 60 s en las
## fases tempranas). La tecnologia de consumo la rebaja como antes.
var food_per_pop := 1

## Cultivos de la Granja, del mas corto al mas largo. El corto rinde poco y da
## comida enseguida; el largo rinde mas por minuto pero hay que esperarlo. El
## cultivo elegido se repite solo mientras quepa en la Granja. Duracion en
## segundos de juego (dev_mode la acorta con get_duration). Por minuto, a moral
## 50 y nivel 1: 20 / 25 / 30 de comida.
var farm_crops := [
	{"id": "crop_short", "name": "CROP_SHORT", "duration": 60.0, "food": 20},
	{"id": "crop_medium", "name": "CROP_MEDIUM", "duration": 300.0, "food": 125},
	{"id": "crop_long", "name": "CROP_LONG", "duration": 1200.0, "food": 600},
]
## El que se planta solo al terminar la obra: el corto, para que una Granja nueva
## de de comer en el primer minuto.
var farm_default_crop := "crop_short"

## Lo que cabe en cada edificio antes de pararse, a nivel 1 (se multiplica por
## el de produccion del nivel: un nivel 2 llena igual de rapido, no antes).
## Unos 6 minutos de su produccion: algo que recoger cada pocos minutos. La
## Granja guarda una cosecha larga entera (600) con margen para la moral alta.
var building_stock_caps := {
	"sawmill": 180,
	"gold_mine": 240,
	"foundry": 120,
	"refinery": 80,
	"headquarters": 180,
	"farm": 800,
}
var building_stock_cap_default := 150

## Lo acumulado sin recoger aguanta esto (segundos de juego); pasado, se echa a
## perder la mitad (`spoil_ratio`) y vuelve a contar. Solo en Gobernador
## (GameMode.spoilage_enabled(), regla `spoilage` de game_tier_rules).
var spoil_after_seconds := 7200.0
var spoil_ratio := 0.5

## Comida con la que carga un guardado de antes de la comida: sin ella la gente
## pasaria hambre nada mas abrir la partida.
var legacy_save_food := 120

## Tope de lo acumulado en un edificio de este tipo a este nivel.
func get_stock_cap(building_id: String, level: int = 1) -> int:
	var base: int = int(building_stock_caps.get(building_id, building_stock_cap_default))
	return int(round(float(base) * get_production_multiplier(level)))

## El cultivo por id, o {} si no existe.
func get_crop(crop_id: String) -> Dictionary:
	for crop in farm_crops:
		if String(crop["id"]) == crop_id:
			return crop
	return {}

## Duracion de un cultivo ya escalada (dev_mode la acorta).
func get_crop_duration(crop_id: String) -> float:
	var crop := get_crop(crop_id)
	return get_duration(float(crop.get("duration", 60.0))) if not crop.is_empty() else 0.0

# ── Mining Data ──

## Era 1 de 8-12 minutos (decision de Bryan, 2026-10-04). Con 20 de oro cada
## 12 s y 20 de madera cada 8 s, dos obreros minando a mano sacaban 2,5 veces lo
## que una Mina de oro con tres, y el jugador que minaba llegaba a la Fundicion
## en el minuto 3,8 (tools/line_probe.gd --active=1, docs/22-linea-jugable.md).
## Ahora la veta y el bosque rinden por obrero lo mismo que su extractor (oro
## 12/30 s = 12 por obrero y minuto, la Mina 13,3; madera 10/20 s = 15, el
## Aserradero 15): minar sirve para arrancar o para un apuro, no es la via rapida.
## Hierro y petroleo (eras 2-3) no cambian.
var mining_data := {
	"gold_vein": {"id": "mine_gold", "name": "PROC_MINE_GOLD", "duration": 30.0, "produces": {"gold": 12}},
	"iron_deposit": {"id": "mine_iron", "name": "PROC_MINE_IRON", "duration": 18.0, "produces": {"steel": 15}},
	"oil_well": {"id": "mine_oil", "name": "PROC_MINE_OIL", "duration": 22.0, "produces": {"oil": 10}},
	"forest": {"id": "mine_wood", "name": "PROC_MINE_WOOD", "duration": 20.0, "produces": {"wood": 10}},
}

## Trabajadores que ocupa sacar una veta a mano mientras dura (2026-09-28):
## minar no es gratis, se quitan a un edificio o se esperan.
var mining_workers := 2

# ── Lotes y el Nucleo como taller de todo (2026-10-14, partidas de Bryan) ──
#
# Lotes: un proceso o un minado se puede pedir varias veces de un toque (x1, x5
# o MAX). Se paga todo al arrancar y se hacen una vuelta tras otra en el mismo
# sitio; cada vuelta entrega lo suyo al terminar. Cancelar devuelve la tasa de
# siempre sobre todo lo pagado que aun no se entrego, y la Tormenta se lleva el
# lote entero, como se llevaba una sola vuelta.

## Botones fijos de lote ademas de MAX.
var process_batch_sizes := [1, 5]
## Techo de MAX: aun con el almacen lleno de madera, un lote no pasa de aqui
## (20 vueltas de 30 s son 10 minutos: mas ya es dejarlo olvidado).
var process_batch_max := 20

## El Nucleo hace lo de todos los talleres y saca a mano lo de cada yacimiento,
## en cuanto el recurso o material de ese proceso esta desbloqueado. Rinde lo
## mismo pero tarda esto mas: asi el Nucleo saca de un apuro y el edificio
## propio sigue valiendo la pena (y deja el Nucleo libre para otra cosa).
var core_process_time_mult := 1.5
## El minado a mano desde el Nucleo lleva este prefijo en su id ("core_mine_gold"),
## para no confundirlo con el de una veta (MapGenerator gasta un uso por cada
## "mine_*" que termina en un yacimiento; el Nucleo no tiene usos).
const CORE_MINING_PREFIX := "core_"

## Lo que el Nucleo ofrece ademas de sus procesos propios: los de cada taller
## (grupo "workshop") y el minado a mano de cada yacimiento (grupo "hand"), con
## la duracion ya escalada y multiplicada por `core_process_time_mult`. Sin
## filtrar por desbloqueo: eso lo decide quien lo ensena (ProcessActionsPanel).
func get_core_extra_processes() -> Array:
	var result: Array = []
	for building_id in building_processes:
		if building_id == "nucleo" or building_id in core_skip_workshops:
			continue
		for proc in building_processes[building_id]:
			var copy: Dictionary = proc.duplicate(true)
			copy["duration"] = get_duration(float(proc["duration"]) * core_process_time_mult)
			copy["core_group"] = "workshop"
			copy["from"] = building_id
			result.append(copy)
	for deposit_id in mining_data:
		var mine: Dictionary = mining_data[deposit_id]
		result.append({
			"id": CORE_MINING_PREFIX + String(mine["id"]),
			"name": mine["name"],
			"duration": get_duration(float(mine["duration"]) * core_process_time_mult),
			"cost": {},
			"produces": (mine["produces"] as Dictionary).duplicate(),
			"workers": mining_workers,
			"core_group": "hand",
			"from": deposit_id,
		})
	return result

# ── Deposit Config ──

var deposit_max_uses := {
	"gold_vein": 8,
	"iron_deposit": 7,
	"oil_well": 10,
	"forest": 8,
}

## Cuantos yacimientos de CADA tipo (bosque, oro, hierro, petroleo) trae una isla
## nueva: se sortea un numero en [min, max] para cada tipo por separado, asi que
## ninguna partida sale sin pozo (sin era 3) ni sin bosque (sin apertura), y dos
## partidas no se parecen. Tres como minimo porque la Refineria se come su pozo
## y el tope es de dos.
var deposit_per_type_min := 3
var deposit_per_type_max := 6
## Distancia minima (Manhattan, en celdas) del centro de un yacimiento al centro
## de la rejilla.
var deposit_center_exclusion := 6
## Celdas libres que se dejan entre un yacimiento y la acera del Nucleo (la
## corona de carreteras): la red tiene por donde crecer hacia los cuatro lados.
var deposit_core_gap := 2
## Franja exterior de la rejilla (en celdas) que se reserva para la costa: ahi no
## caen yacimientos de tierra. Es donde iran los futuros recursos del mar y la
## orilla (MapGenerator.shore_cells()). Se puede construir en ella.
var map_shore_band := 1

# ── Map Size ──
## Ancho y alto de la rejilla, en celdas, que sortea cada partida nueva (por
## separado, siempre pares para que el Nucleo quede en el centro del mundo; la
## isla no sale siempre cuadrada). Se guardan con la partida (clave "grid"); un
## guardado sin ella es de 40x40. Con la isla irregular (2026-10-12) la rejilla
## es mas grande que la de antes (40-48) porque el mar entra en ella: la tierra
## la fija island_coast (land_min..land_max), no el tamano de la rejilla.
var grid_width_min := 60
var grid_width_max := 74
var grid_height_min := 60
var grid_height_max := 74

## La costa de la isla irregular (scripts/map/IslandShape.gd, docs/02 "Mapa
## aleatorio"). Mismas claves y valores que IslandShape.DEFAULTS (un test lo
## comprueba). Se copian al guardado de cada partida nueva: cambiarlos aqui solo
## afecta a las islas nuevas.
##  edge_water: celdas de mar en el borde de la rejilla
##  core_size / core_margin: el Nucleo y la tierra garantizada alrededor de su acera
##  fraction_min/max: parte de la rejilla util (sin el borde) que es tierra
##  land_min/max: celdas de tierra (la de antes era 1600-2304, toda construible)
##  power_min/max: superelipse (2 elipse, 3 casi cuadrada)
##  harmonic_amp: lobulos grandes; noise_amp / noise_freq: costa menuda
##  bays_* / capes_*: cuantas bahias y cabos, y de que tamano (en radios de isla)
##  close_radius: entrantes mas estrechos que unas 2x celdas se rellenan
##  open_radius: lenguas de tierra mas finas que unas 2x celdas se quitan
var island_coast := {
	"edge_water": 3,
	"core_size": 3,
	"core_margin": 3,
	"fraction_min": 0.46,
	"fraction_max": 0.58,
	"land_min": 1550,
	"land_max": 2300,
	"power_min": 2.0,
	"power_max": 3.0,
	"harmonic_amp": 0.30,
	"noise_amp": 0.30,
	"noise_freq": 0.05,
	"bays_min": 2,
	"bays_max": 4,
	"bay_size_min": 0.20,
	"bay_size_max": 0.36,
	"capes_min": 1,
	"capes_max": 3,
	"cape_length_min": 1.00,
	"cape_length_max": 1.25,
	"cape_width_min": 0.08,
	"cape_width_max": 0.14,
	"close_radius": 2.5,
	"open_radius": 1.5,
}

# ── Deposit Sizes (random range per type: min_w, max_w, min_h, max_h) ──
var deposit_sizes := {
	"gold_vein": {"min_w": 2, "max_w": 3, "min_h": 2, "max_h": 3},
	"iron_deposit": {"min_w": 2, "max_w": 3, "min_h": 2, "max_h": 3},
	"oil_well": {"min_w": 2, "max_w": 3, "min_h": 2, "max_h": 3},
	"forest": {"min_w": 2, "max_w": 4, "min_h": 2, "max_h": 4},
}

# ── Deposit Resource Mapping (which resource a deposit requires unlocked) ──

var deposit_resource_required := {
	"gold_vein": "gold",
	"iron_deposit": "steel",
	"oil_well": "oil",
	"forest": "wood",
}

# ── Resource Display Colors ──

var resource_colors := {
	"gold": Color(1.0, 0.85, 0.1),
	"steel": Color(0.7, 0.75, 0.8),
	"oil": Color(0.5, 0.4, 0.6),
	"wood": Color(0.55, 0.35, 0.15),
	"planks": Color(0.82, 0.62, 0.36),
	"ingots": Color(1.0, 0.72, 0.25),
	"beams": Color(0.55, 0.62, 0.72),
	"fuel": Color(0.85, 0.38, 0.2),
	"food": Color(0.55, 0.8, 0.3),
	## Repuestos (2026-10-14): solo se consiguen fuera, en escaramuzas (doc 21 §3.1).
	"parts": Color(0.66, 0.72, 0.6),
}

# ── Audio ──
# Volumes are linear [0.0, 1.0]; AudioManager converts to dB per bus.
# Master scales all others. Set any to 0.0 to mute that channel.

## Valores de serie bajos (bug 4): el primer arranque sonaba muy fuerte. Los
## deslizadores siguen una curva perceptual (AudioManager.slider_to_db), asi que
## 0.8 / 0.5 ya bajan de verdad. Quien ya guardo settings.cfg conserva lo suyo.
## Los de serie, en un sitio: Ajustes > Audio > Restablecer vuelve a estos.
const AUDIO_DEFAULTS := {"master": 0.8, "music": 0.35, "sfx": 0.5, "ambient": 0.4}
var audio_master_volume: float = AUDIO_DEFAULTS["master"]
## Bajada de 0.6 a 0.35: el dueno la encontraba muy invasiva. Quien ya guardo
## un volumen en settings.cfg conserva el suyo.
var audio_music_volume: float = AUDIO_DEFAULTS["music"]
## Musica si/no, aparte del volumen (Ajustes y el menu ☰). Apagada, AudioManager
## no arranca ninguna pista, ni al cambiar de era ni al entrar en combate.
var audio_music_enabled := true
var audio_sfx_volume: float = AUDIO_DEFAULTS["sfx"]
var audio_ambient_volume: float = AUDIO_DEFAULTS["ambient"]

# ── Camara: arrastrar el mapa ──
# El raton y el dedo mueven el mapa con la misma cuenta (agarrar el terreno y
# llevarlo), asi que lo unico que se ajusta por separado es cuanto hay que
# moverse antes de que un clic deje de ser un clic.

## Pixeles que el cursor recorre con el boton izquierdo pulsado antes de que el
## clic pase a ser un arrastre del mapa. Mas bajo: el mapa se mueve al minimo
## temblor y cuesta seleccionar un edificio. Mas alto: el arrastre parece que
## tarda en enganchar el terreno.
var mouse_drag_threshold_px := 6.0

## Lo mismo para el dedo, en dp (1 dp = 1/160 de pulgada): un dedo se mueve un par
## de milimetros incluso en un toque que el jugador siente inmovil, y eso son
## pixeles distintos en cada pantalla. Con los 12 px fisicos de antes, en una
## tablet de ~280 dpi un toque normal (1-2 mm) pasaba el umbral, se volvia
## arrastre y el aserradero no se colocaba. 14 dp son ~2,2 mm; el paneo no pierde
## nada por esperar, porque arranca desde donde se apoyo el dedo.
## InputService.touch_slop_px() lo pasa a pixeles del lienzo con el dpi real.
var touch_drag_threshold_dp := 14.0
## Suelo del umbral anterior, en pixeles del lienzo: por mucho que el dpi diga,
## un toque nunca se vuelve arrastre por menos de esto.
var touch_drag_threshold_px := 8.0

## Pellizco: cuanto tiene que cambiar la separacion entre los dos dedos (en
## pixeles) para mover el zoom. Absorbe el temblor de dos dedos quietos; si se
## sube, el zoom empieza a ir a tirones.
var pinch_zoom_dead_zone_px := 1.0

## Zoom por pellizco: unidades de distancia de camara por pixel de separacion
## ganada entre los dedos. Mas alto = el mapa se acerca de golpe.
var pinch_zoom_sensitivity := 0.05

# ── tactil ──
## Dos dedos: el gesto se bloquea en giro si la linea entre ellos gira esto (en
## grados) antes de que la separacion cambie pinch_lock_scale (8 %), y en zoom al
## reves. Mas bajo: cuesta hacer un pellizco que no gire. Mas alto: el giro tarda
## en engancharse.
var twist_lock_degrees := 8.0
var pinch_lock_scale := 0.08
## Sentido del giro con dos dedos (+1: el terreno gira con los dedos). Solo 3D.
var twist_rotate_sign := 1.0
## Mantener pulsado un boton de accion en pantalla lo repite: primero al tocar,
## luego tras hold_repeat_delay_sec, y despues cada hold_repeat_interval_sec.
var hold_repeat_delay_sec := 0.3
var hold_repeat_interval_sec := 0.08
## Grados por segundo que gira la camara con ↺/↻ mantenidos (tras el primer paso).
var hold_rotate_degrees_per_sec := 90.0
## Mantener el dedo quieto esto (segundos) sobre un control con tooltip lo ensena
## en una burbuja (TouchTooltip, docs/21 §9). Un toque mas corto pulsa como
## siempre. Mas bajo: un toque lento se queda leyendo en vez de pulsar.
var touch_tooltip_hold_sec := 0.5
## Opacidad de los controles en pantalla (cruceta, zoom, giro, colocar): fondo,
## borde y simbolo. Al pulsar un boton se ve entero; en reposo vuelve a esto.
## Del dispositivo, en settings.cfg [ui] touch_controls_opacity.
const TOUCH_OPACITY_MIN := 0.15
const TOUCH_OPACITY_MAX := 1.0
var ui_touch_controls_opacity := 0.45
## Tamano de los controles en pantalla (cruceta, zoom, girar, R, CANCELAR y el
## ✓ de colocar): "auto" es el del perfil de dispositivo
## (DeviceProfile.DEFAULTS[...]["controls_size"]: PC 100 %, tablet 115 %,
## movil 130 %); los demas lo fuerzan. Del dispositivo, en settings.cfg
## [interfaz] touch_controls_size (docs/21 §9, "Tamano de los controles").
const TOUCH_CONTROLS_SIZE_MODES := ["auto", "small", "normal", "large", "xlarge"]
const TOUCH_CONTROLS_SIZE_SCALES := {"small": 0.85, "normal": 1.0, "large": 1.25, "xlarge": 1.5}
var ui_touch_controls_size := "auto"

# ── User Settings persistence ──
# Device-local preferences (volumes, UI toggles) — separate from save_game.json
# so they survive "new game" and apply before any save is loaded.

const USER_SETTINGS_PATH := "user://settings.cfg"

## Whether the map cell grid overlay is shown permanently (toggle in Settings).
## Off by default (arte, 2026-10-05: "el suelo con la rejilla blanca parece un
## prototipo"): the grid shows only while placing or moving a building
## (BuildingPlacer forces it on), very faint; the alpha lives in the GridOverlay
## material in Main.tscn. Saved as [ui] grid_always: the old key grid_visible
## was written as true by every install, so it is ignored and dropped on save.
var ui_grid_visible := false

## Whether the on-screen helper callouts are shown ("?" button). OFF by default
## since the UI redesign (docs/28 §12, 2026-10-18): floating tips covered the
## map; they open from AYUDA (bottom bar) and the guided tutorial still forces
## the ones it needs. The choice persists once toggled.
var ui_helper_visible := false

## Los instructores (feat/instructores, docs/23 §9): el busto de la
## Capitana Remache y del Sargento Bombarda junto a las tarjetas del tutorial,
## los consejos y los partes de guerra. Ajustes > Interfaz los oculta; es del
## dispositivo ([ui] instructors_visible en settings.cfg), nunca del save.
var ui_instructors_visible := true

## Whether the game runs in exclusive fullscreen. Toggled with F11 or from the
## Settings panel; persists in user://settings.cfg like the rest of preferences.
var ui_fullscreen := false

## Vista del mapa: "3d" (Main.tscn) o "2d" (Main2D.tscn, docs/18-vista-2d.md).
## Cambiar el valor por defecto a "2d" es lo unico que hace falta para que la
## vista 2D sea la de serie. `--view=2d` en la linea de comandos manda sobre esto
## solo en esa sesion (ViewMode.gd).
var ui_view_mode := "3d"
## Controles tactiles en pantalla (D-pad, zoom, rotar, cancelar colocacion).
## "auto" sigue al perfil de dispositivo (DeviceProfile): tablet y movil los
## ensenan, PC nunca, aunque la pantalla sea tactil; "always" y "never" fuerzan. En escritorio sobran:
## hay WASD y rueda, y los botones ocupaban las cuatro esquinas de la pantalla.
## El mismo estado decide si los botones pequenos del HUD crecen a tamano dedo
## (UITheme.touch_px).
const TOUCH_CONTROLS_MODES := ["auto", "always", "never"]
var ui_touch_controls := "auto"
## Idioma de la interfaz ("es" / "en"). Vive en settings.cfg y no en la partida:
## es del dispositivo, sobrevive a "partida nueva" y se aplica antes de pintar nada.
var ui_locale := "es"
## Orientacion de la pantalla en movil (rediseno 2026-10, docs/28 §4): el
## juego se disena y se juega en horizontal; vertical es una opcion de Ajustes
## que solo tiene que funcionar. Del dispositivo: vive en settings.cfg.
const ORIENTATIONS := ["landscape", "portrait"]
var ui_orientation := "landscape"

# ── interfaz-dispositivos (docs/21-interfaz-y-dispositivos.md) ──
# Todo del dispositivo, en settings.cfg [interfaz]: una tablet y un PC del mismo
# jugador no tienen por que querer la misma letra ni la misma disposicion.

## Perfil de dispositivo: "auto" lo detecta DeviceProfile; "pc", "tablet" y
## "phone" lo fuerzan.
const DEVICE_PROFILE_MODES := ["auto", "pc", "tablet", "phone"]
var ui_device_profile := "auto"
## Escala global de la interfaz en %. 0 = la del perfil de dispositivo.
const UI_SCALE_MIN := 75
const UI_SCALE_MAX := 150
var ui_scale_pct := 0
## Tamano de texto: "auto" (el del perfil) o uno de UITheme.TEXT_SIZES.
var ui_text_size := "auto"
## Paleta de colores (UITheme.PALETTES), alto contraste y opacidad de paneles.
var ui_palette := "default"
var ui_high_contrast := false
var ui_panel_opacity := 1.0
## Calidad grafica del mapa 3D (WorldLook, docs/21 §12): "high" pone SSAO (solo
## Forward+), glow y sombras con cuatro cortes; "low" los quita y deja una sombra
## de un corte. "auto" es "low" con el renderizador Mobile o Compatibility
## (Android, el APK de QA) y "high" en Forward+ (PC). "minimal" es para "una
## papa" (docs/26 §7): sin sombras, MSAA, humo ni rejilla, menos caminantes, 3D
## a menor resolucion, 30 fps en PC y, en PC, el renderizador Mobile desde el
## siguiente arranque (GraphicsQuality).
const GRAPHICS_QUALITY_MODES := ["auto", "high", "low", "minimal"]
var ui_graphics_quality := "auto"
## Vista del combate (docs/15 §3, "Las dos vistas"): "front" (por defecto) los
## dos bandos cara a cara, sin casillas a la vista; "board" el tablero 8x8 en 3D.
## Preferencia del dispositivo ([interfaz] combat_view), nunca de la partida: las
## dos vistas mueven el mismo Encounter y una pelea da lo mismo en las dos.
const COMBAT_VIEWS := ["front", "board"]
var ui_combat_view := "front"
## Deteccion del primer arranque (DeviceProfile, docs/26 §7.2): si ya se hizo
## (no se repite sola) y por que decidio lo que decidio (para depurar).
var quality_detected := false
var quality_detected_reason := ""
## Version de la regla de deteccion con la que se decidio (settings.cfg
## [interfaz] quality_detect_version; sin la clave, 0 = la del 1.0.0). La 2 mide
## sin tope ni vsync y descarta las medidas pegadas a un tope; DeviceProfile
## repara una sola vez lo que decidio una version anterior con una medida mala.
const QUALITY_DETECT_VERSION := 2
var quality_detect_version := 0
## Nombres junto a los iconos del HUD ("Oro 300", feat/hud-y-tutorial): con siete
## numeros seguidos un chaval no sabe cual es la moral ni la comida (ronda 1.0,
## mejora 4). "auto" los pone en tableta y movil siempre y, en PC, mientras el
## jugador es nuevo: en sus primeras partidas (hud_words_new_runs acabadas) y solo
## la primera hora jugada de cada una. "always" y "never" fuerzan.
## settings.cfg [interfaz] hud_words; nunca en la partida.
const HUD_WORDS_MODES := ["auto", "always", "never"]
var ui_hud_words := "auto"
var hud_words_new_runs := 2
var hud_words_first_seconds := 3600.0
## Ids de HudRegistry que el jugador oculto.
var ui_hud_hidden: Array = []
## Disposicion movida a mano: {"<perfil>|<aspecto>": {panel_id: [dx, dy]}}.
var ui_layout: Dictionary = {}
## Tope de fotogramas por segundo: "auto" (el del perfil, DeviceProfile.DEFAULTS
## "fps"), un numero, o "unlimited" (sin tope propio: lo marca el vsync, es decir,
## el refresco de la pantalla). Sin tope el motor repinta la escena entera a 144 Hz
## en un monitor de 144 Hz aunque nada se mueva, y eso es bateria y calor.
const FPS_CAP_MODES := ["auto", "30", "45", "60", "90", "120", "unlimited"]
var ui_fps_cap := "auto"
## Fotogramas por segundo con la ventana sin foco o minimizada (nadie mira), y
## con el juego en pausa (menu de pausa, menu de titulo, prologo: solo se mueve el
## agua). Nunca por encima del tope elegido. Docs/21 §10.
var fps_background := 10
var fps_paused := 30
## Tope "auto" en PC con la calidad Minima (en tablet y movil ya es 30).
var fps_minimal_pc := 30

# ── Deteccion de la calidad en el primer arranque (docs/26 §7.2) ──
# Solo con la calidad en "auto" y sin quality_detected en settings.cfg. Paso 1:
# senales estaticas; paso 2: medir unos segundos detras del menu de titulo.

## Nombres de GPU flojas (expresiones regulares, sin distinguir mayusculas).
## Ampliable sin tocar codigo cuando un probador diga "en mi equipo va mal".
var quality_weak_gpu_patterns: Array = [
	r"Intel\(R\) HD Graphics( [2-6]\d\d\b|$| Family)",
	r"\bUHD Graphics 6\d\d\b",
	r"\bHD Graphics [45]\d\d\b",
	r"\bRadeon R[2-7]\b",
	r"\bRadeon\(TM\) Vega [368] ",
	r"\bMali-T",
	r"\bMali-G(31|51|52|57)\b",
	r"\bAdreno \(TM\) ([345]\d\d|61[023])\b",
	r"PowerVR",
	r"\bGE8\d\d\d\b",
]
## RAM del sistema (MB) a partir de la cual el equipo es flojo. 4600 y no 4096:
## un equipo de 4 GB declara algo menos (la integrada se queda una parte).
var quality_weak_ram_mb := 4600
## Hilos de CPU a partir de los cuales es flojo (2 nucleos / 4 hilos).
var quality_weak_threads := 4
## Un movil (perfil "phone") con esta RAM o menos va en Minima.
var quality_phone_ram_mb := 6600
## Paso 2: espera a que se asiente la carga y luego mide (segundos reales).
var quality_detect_warmup := 2.0
var quality_detect_seconds := 3.0
## Mediana o p95 del fotograma por encima de esto (ms) -> Minima; mediana
## por encima de quality_detect_low_ms midiendo en Alta -> Baja (nunca por debajo
## de 1,1 fotogramas del refresco de la pantalla: con vsync no se mide menos).
var quality_detect_median_ms := 25.0
var quality_detect_p95_ms := 33.0
var quality_detect_low_ms := 16.7
## Una medida que no mide la GPU sino un tope: si la mediana cae a menos de
## quality_detect_cap_tolerance_ms de 1000/N (N en quality_detect_known_caps, el
## refresco de la pantalla o su mitad), o si la distancia entre los percentiles
## 10 y 90 no llega a quality_detect_flat_ms (fotogramas clavados), no vale: se
## descarta y la calidad se queda en "auto". Nunca baja a Minima por eso (el
## 1.0.0 midio 33,3 ms en una RTX 3060: el tope de 30, no el equipo).
var quality_detect_known_caps: Array = [30, 60]
var quality_detect_cap_tolerance_ms := 1.0
var quality_detect_flat_ms := 0.3

# ── Perfil del jugador (settings.cfg [perfil]) ──
# Del jugador en este dispositivo, NO de la partida: sobrevive a "Nueva partida"
# y no viaja en save_game.json. Hoy solo sirve para desbloquear Gobernador.

## Partidas llevadas hasta su final: ganar, perder la Auditoria Final o una
## Supervivencia sellada. GameManager lo anota (record_run_finished).
var profile_runs_finished := 0
## Campanas ganadas (Auditoria Final superada).
var profile_campaigns_won := 0

## La partida activa (settings.cfg [partidas] activa): la ultima que se jugo en
## este dispositivo, la que abre "Continuar". Es preferencia del dispositivo, no
## estado de juego. 0 = ninguna todavia (GameManager elige al arrancar).
var saves_active_slot := 0

func _ready() -> void:
	# El registro local de errores va lo primero: asi recoge tambien lo que pase
	# al cargar los ajustes (docs/19 §7). Nunca sale del equipo.
	ErrorLog.install(self)
	# Una línea en el log: quien reporte un fallo con el .exe dirá en qué modo jugaba.
	print("[GameConfig] version %s, dev_mode=%s" % [ProjectSettings.get_setting("application/config/version", "?"), dev_mode])
	load_user_settings()
	# El modo de ventana se aplica en cuanto arranca, antes de que se dibuje la UI.
	_apply_window_mode()

## Resuelve dev_mode al arrancar (ver el comentario de la variable). El feature tag
## "editor" solo existe en el binario del editor, nunca en una plantilla de exportación.
static func _resolve_dev_mode() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--no-dev"):
		return false
	if args.has("--dev"):
		return true
	return OS.has_feature("editor")

func load_user_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(USER_SETTINGS_PATH) != OK:
		return
	audio_master_volume = clampf(float(cf.get_value("audio", "master", audio_master_volume)), 0.0, 1.0)
	audio_music_volume = clampf(float(cf.get_value("audio", "music", audio_music_volume)), 0.0, 1.0)
	audio_sfx_volume = clampf(float(cf.get_value("audio", "sfx", audio_sfx_volume)), 0.0, 1.0)
	audio_ambient_volume = clampf(float(cf.get_value("audio", "ambient", audio_ambient_volume)), 0.0, 1.0)
	audio_music_enabled = bool(cf.get_value("audio", "music_enabled", audio_music_enabled))
	ui_grid_visible = bool(cf.get_value("ui", "grid_always", ui_grid_visible))
	ui_helper_visible = bool(cf.get_value("ui", "helper_visible", ui_helper_visible))
	ui_instructors_visible = bool(cf.get_value("ui", "instructors_visible", ui_instructors_visible))
	ui_fullscreen = bool(cf.get_value("ui", "fullscreen", ui_fullscreen))
	var view := String(cf.get_value("ui", "view_mode", ui_view_mode))
	ui_view_mode = view if view in ["3d", "2d"] else ui_view_mode
	var touch_mode := String(cf.get_value("ui", "touch_controls", ui_touch_controls))
	# Un valor desconocido en el archivo (edicion a mano, version vieja) vuelve
	# a "auto" en vez de dejar los controles en un estado que nadie eligio.
	ui_touch_controls = touch_mode if touch_mode in TOUCH_CONTROLS_MODES else "auto"
	# Una sola clave: [ui] touch_controls_opacity. La vieja `touch_opacity` (menu
	# unico, #31) se lee si la nueva no esta y desaparece al guardar.
	var old_opacity: Variant = cf.get_value("ui", "touch_opacity", ui_touch_controls_opacity)
	ui_touch_controls_opacity = clampf(float(cf.get_value("ui", "touch_controls_opacity",
		old_opacity)), TOUCH_OPACITY_MIN, TOUCH_OPACITY_MAX)
	var locale := str(cf.get_value("ui", "locale", ui_locale))
	if Tr.LOCALES.has(locale):
		ui_locale = locale
	Tr.set_locale(ui_locale)
	_load_interface_settings(cf)
	var orient := String(cf.get_value("ui", "orientation", ui_orientation))
	ui_orientation = orient if orient in ORIENTATIONS else "landscape"
	apply_orientation()

## [interfaz]: cada valor se valida; uno desconocido vuelve al de serie en vez
## de dejar la interfaz en un estado que nadie eligio.
func _load_interface_settings(cf: ConfigFile) -> void:
	var prof := str(cf.get_value("interfaz", "device_profile", ui_device_profile))
	ui_device_profile = prof if prof in DEVICE_PROFILE_MODES else "auto"
	var scale := int(cf.get_value("interfaz", "ui_scale_pct", ui_scale_pct))
	ui_scale_pct = 0 if scale == 0 else clampi(scale, UI_SCALE_MIN, UI_SCALE_MAX)
	var text := str(cf.get_value("interfaz", "text_size", ui_text_size))
	ui_text_size = text if (text == "auto" or text in UITheme.TEXT_SIZES) else "auto"
	var pal := str(cf.get_value("interfaz", "palette", ui_palette))
	ui_palette = pal if pal in UITheme.PALETTES else "default"
	ui_high_contrast = bool(cf.get_value("interfaz", "high_contrast", ui_high_contrast))
	ui_panel_opacity = clampf(float(cf.get_value("interfaz", "panel_opacity", ui_panel_opacity)),
		UITheme.OPACITY_MIN, UITheme.OPACITY_MAX)
	var quality := str(cf.get_value("interfaz", "graphics_quality", ui_graphics_quality))
	ui_graphics_quality = quality if quality in GRAPHICS_QUALITY_MODES else "auto"
	var cview := str(cf.get_value("interfaz", "combat_view", ui_combat_view))
	ui_combat_view = cview if cview in COMBAT_VIEWS else "front"
	quality_detected = bool(cf.get_value("interfaz", "quality_detected", quality_detected))
	quality_detected_reason = str(cf.get_value("interfaz", "quality_detected_reason", quality_detected_reason))
	quality_detect_version = int(cf.get_value("interfaz", "quality_detect_version", 0))
	var words := str(cf.get_value("interfaz", "hud_words", ui_hud_words))
	ui_hud_words = words if words in HUD_WORDS_MODES else "auto"
	var hidden: Variant = cf.get_value("interfaz", "hud_hidden", ui_hud_hidden)
	ui_hud_hidden = []
	if hidden is Array:
		for id in hidden:
			# Un elemento retirado del HUD (la tarjeta de estado) no se arrastra.
			if not str(id) in HudRegistry.RETIRED:
				ui_hud_hidden.append(str(id))
	var layout: Variant = cf.get_value("interfaz", "layout", ui_layout)
	ui_layout = layout.duplicate(true) if layout is Dictionary else {}
	for key in ui_layout.keys():
		var moved: Variant = ui_layout[key]
		if moved is Dictionary:
			for id in HudRegistry.RETIRED:
				(moved as Dictionary).erase(id)
			if (moved as Dictionary).is_empty():
				ui_layout.erase(key)
	var fps := str(cf.get_value("interfaz", "fps_cap", ui_fps_cap))
	ui_fps_cap = fps if fps in FPS_CAP_MODES else "auto"
	var csize := str(cf.get_value("interfaz", "touch_controls_size", ui_touch_controls_size))
	ui_touch_controls_size = csize if csize in TOUCH_CONTROLS_SIZE_MODES else "auto"
	profile_runs_finished = maxi(0, int(cf.get_value("perfil", "runs_finished", profile_runs_finished)))
	profile_campaigns_won = maxi(0, int(cf.get_value("perfil", "campaigns_won", profile_campaigns_won)))
	saves_active_slot = maxi(0, int(cf.get_value("partidas", "activa", saves_active_slot)))

func save_user_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(USER_SETTINGS_PATH)  # keep unknown sections if the file already exists
	cf.set_value("audio", "master", audio_master_volume)
	cf.set_value("audio", "music", audio_music_volume)
	cf.set_value("audio", "sfx", audio_sfx_volume)
	cf.set_value("audio", "ambient", audio_ambient_volume)
	cf.set_value("audio", "music_enabled", audio_music_enabled)
	cf.set_value("ui", "grid_always", ui_grid_visible)
	if cf.has_section_key("ui", "grid_visible"):
		cf.erase_section_key("ui", "grid_visible")
	cf.set_value("ui", "helper_visible", ui_helper_visible)
	cf.set_value("ui", "instructors_visible", ui_instructors_visible)
	cf.set_value("ui", "fullscreen", ui_fullscreen)
	cf.set_value("ui", "view_mode", ui_view_mode)
	cf.set_value("ui", "touch_controls", ui_touch_controls)
	cf.set_value("ui", "touch_controls_opacity", ui_touch_controls_opacity)
	if cf.has_section_key("ui", "touch_opacity"):
		cf.erase_section_key("ui", "touch_opacity")
	cf.set_value("ui", "locale", ui_locale)
	cf.set_value("ui", "orientation", ui_orientation)
	cf.set_value("interfaz", "device_profile", ui_device_profile)
	cf.set_value("interfaz", "ui_scale_pct", ui_scale_pct)
	cf.set_value("interfaz", "text_size", ui_text_size)
	cf.set_value("interfaz", "palette", ui_palette)
	cf.set_value("interfaz", "high_contrast", ui_high_contrast)
	cf.set_value("interfaz", "panel_opacity", ui_panel_opacity)
	cf.set_value("interfaz", "graphics_quality", ui_graphics_quality)
	cf.set_value("interfaz", "combat_view", ui_combat_view)
	cf.set_value("interfaz", "quality_detected", quality_detected)
	cf.set_value("interfaz", "quality_detected_reason", quality_detected_reason)
	cf.set_value("interfaz", "quality_detect_version", quality_detect_version)
	cf.set_value("interfaz", "hud_words", ui_hud_words)
	cf.set_value("interfaz", "hud_hidden", ui_hud_hidden)
	cf.set_value("interfaz", "layout", ui_layout)
	cf.set_value("interfaz", "fps_cap", ui_fps_cap)
	cf.set_value("interfaz", "touch_controls_size", ui_touch_controls_size)
	cf.set_value("perfil", "runs_finished", profile_runs_finished)
	cf.set_value("perfil", "campaigns_won", profile_campaigns_won)
	cf.set_value("partidas", "activa", saves_active_slot)
	cf.save(USER_SETTINGS_PATH)

## Elige la vista del combate ("front" / "board"), la guarda en settings.cfg y
## devuelve si cambio. Un valor desconocido no hace nada.
func set_combat_view(view: String) -> bool:
	if not view in COMBAT_VIEWS or view == ui_combat_view:
		return false
	ui_combat_view = view
	save_user_settings()
	return true

## El perfil ya abre Gobernador: una partida terminada o una Campana ganada.
## (En dev_mode se ofrece siempre; eso lo decide GameMode.governor_unlocked().)
func governor_unlocked_by_profile() -> bool:
	return profile_runs_finished >= 1 or profile_campaigns_won >= 1

## Anota en el perfil que una partida llego a su final (y si fue una Campana
## ganada) y lo guarda. Lo llama GameManager; nunca toca la partida.
func record_run_finished(campaign_won: bool) -> void:
	profile_runs_finished += 1
	if campaign_won:
		profile_campaigns_won += 1
	save_user_settings()

# ── Controles tactiles ──

## Si ya ha llegado un toque de pantalla REAL en esta sesion (InputService lo
## avisa). No se guarda: un portatil tactil que hoy se usa con el dedo manana
## puede usarse con raton, y el ajuste explicito es "Siempre".
var _real_touch_seen := false

## Si los controles en pantalla deben verse ahora, resolviendo el "auto".
## Es la unica pregunta que hace OnScreenControls.
##
## "auto" = solo movil y tablet (decision de Bryan, 2026-10-04): sigue al perfil
## de dispositivo (DeviceProfile), y en PC NUNCA. Ni
## DisplayServer.is_touchscreen_available() ni un toque real los encienden en un
## PC: un portatil Windows tactil que se toca una vez no se llena de flechas. El
## portatil tactil elige "Siempre" a mano (lo dice LBL_TOUCH_AUTO_HINT en
## Ajustes), o el perfil Tablet.
func touch_controls_enabled() -> bool:
	match ui_touch_controls:
		"always":
			return true
		"never":
			return false
		_:
			return _touch_profile()

## Si la cruceta, el zoom y el girar en pantalla se ven (OnScreenControls).
## Distinto de touch_controls_enabled() (que dice "se juega con el dedo"):
## en "auto" solo la tablet los lleva; el telefono juega con gestos (rediseno
## 2026-10, docs/28 §12) y solo ve CANCELAR / girar edificio mientras coloca.
func onscreen_controls_visible() -> bool:
	match ui_touch_controls:
		"always":
			return true
		"never":
			return false
		_:
			var dp := get_node_or_null("/root/DeviceProfile")
			if dp != null and dp.has_method("onscreen_controls_default"):
				return dp.onscreen_controls_default()
			return _touch_profile()

## "auto" sigue al perfil de dispositivo (tablet y movil llevan controles en
## pantalla; PC no), asi que forzar el perfil Tablet en Ajustes los trae.
## Sin DeviceProfile (no deberia pasar) se mira el sistema, como antes.
func _touch_profile() -> bool:
	var dp := get_node_or_null("/root/DeviceProfile")
	if dp != null and dp.has_method("is_touch_profile"):
		return dp.is_touch_profile()
	return is_mobile_os()

## Movil de verdad: exportado a Android/iOS, o la web abierta en uno de ellos.
static func is_mobile_os() -> bool:
	for feature in ["mobile", "android", "ios", "web_android", "web_ios"]:
		if OS.has_feature(feature):
			return true
	return false

## InputService llama aqui con cada InputEventScreenTouch real (el proyecto no
## emula toques desde el raton, asi que un toque es un dedo). Solo se anota:
## en PC un toque ya no enciende los controles (ver touch_controls_enabled);
## sirve para que los textos de ayuda hablen de dedos (DeviceProfile.input_style).
func notice_real_touch() -> void:
	_real_touch_seen = true

func real_touch_seen() -> bool:
	return _real_touch_seen

## Cambia la orientacion, la guarda y la aplica (solo en movil: en PC la
## ventana manda).
func set_orientation(orient: String) -> void:
	if not orient in ORIENTATIONS:
		orient = "landscape"
	if ui_orientation == orient:
		return
	ui_orientation = orient
	save_user_settings()
	apply_orientation()

## Gira la pantalla en Android/iOS: horizontal o vertical, siguiendo el sensor
## dentro de esa orientacion. En escritorio no hace nada.
func apply_orientation() -> void:
	if not (OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("mobile")):
		return
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_PORTRAIT
		if ui_orientation == "portrait" else DisplayServer.SCREEN_SENSOR_LANDSCAPE)

## Cambia el modo, lo guarda y anuncia el estado resuelto para que los controles
## aparezcan o desaparezcan sin reiniciar.
func set_touch_controls(mode: String) -> void:
	if not mode in TOUCH_CONTROLS_MODES:
		mode = "auto"
	if ui_touch_controls == mode:
		return
	ui_touch_controls = mode
	save_user_settings()
	EventBus.touch_controls_changed.emit(touch_controls_enabled())

# ── Nombres junto a los iconos del HUD (feat/hud-y-tutorial) ──

## Si el HUD lleva ahora la palabra bajo cada icono, resolviendo el "auto".
## `played_seconds` < 0: lo jugado en esta partida (ProgressionManager). Pura
## con los dos ultimos argumentos, para las pruebas.
func hud_words_enabled(played_seconds: float = -1.0, touch_profile: int = -1) -> bool:
	match ui_hud_words:
		"always":
			return true
		"never":
			return false
	var touch := _touch_profile() if touch_profile < 0 else touch_profile == 1
	if touch:
		return true
	if profile_runs_finished >= hud_words_new_runs:
		return false
	if played_seconds < 0.0:
		var pm := get_node_or_null("/root/ProgressionManager")
		played_seconds = float(pm.get_played_seconds()) if pm != null else 0.0
	return played_seconds < hud_words_first_seconds

## Las palabras dependen ahora del reloj de la partida ("auto" en PC con un
## jugador nuevo): el HUD mira una vez por minuto si ya paso la primera hora.
func hud_words_timed() -> bool:
	return ui_hud_words == "auto" and not _touch_profile() \
		and profile_runs_finished < hud_words_new_runs

## Cambia el modo ("auto" / "always" / "never"), lo guarda y anuncia el estado
## resuelto: el HUD pone o quita las palabras sin recargar.
func set_hud_words(mode: String) -> void:
	if not mode in HUD_WORDS_MODES:
		mode = "auto"
	if ui_hud_words == mode:
		return
	ui_hud_words = mode
	save_user_settings()
	EventBus.hud_words_changed.emit(hud_words_enabled())

## Cambia la opacidad de los controles en pantalla y la anuncia (OnScreenControls
## la aplica al momento). `persist` = false mientras se arrastra el deslizador.
func set_touch_controls_opacity(value: float, persist: bool = true) -> void:
	ui_touch_controls_opacity = clampf(value, TOUCH_OPACITY_MIN, TOUCH_OPACITY_MAX)
	if persist:
		save_user_settings()
	EventBus.touch_controls_opacity_changed.emit(ui_touch_controls_opacity)

## Escala de los controles en pantalla que vale ahora (1.0 = 100 %), resolviendo
## el "auto" contra el perfil de dispositivo. Es la unica pregunta que hacen
## OnScreenControls, PlacementAssist y UILayoutManager.
func touch_controls_scale() -> float:
	return touch_controls_scale_for(ui_touch_controls_size, _profile_controls_size())

## Puro: la escala de un modo, con `profile_scale` para "auto".
static func touch_controls_scale_for(mode: String, profile_scale: float) -> float:
	if TOUCH_CONTROLS_SIZE_SCALES.has(mode):
		return float(TOUCH_CONTROLS_SIZE_SCALES[mode])
	return profile_scale

## El tamano de serie del perfil activo (sin DeviceProfile, 100 %).
func _profile_controls_size() -> float:
	var dp := get_node_or_null("/root/DeviceProfile")
	if dp != null and dp.has_method("defaults"):
		return float(dp.defaults().get("controls_size", 1.0))
	return 1.0

## Cambia el tamano, lo guarda y anuncia la escala resuelta (se ve al momento).
func set_touch_controls_size(mode: String, persist: bool = true) -> void:
	if not mode in TOUCH_CONTROLS_SIZE_MODES:
		mode = "auto"
	ui_touch_controls_size = mode
	if persist:
		save_user_settings()
	EventBus.touch_controls_size_changed.emit(touch_controls_scale())

# ── Pantalla completa ──

## Pone la ventana en el modo que marque ui_fullscreen. Sin senales: se usa
## tambien en _ready(), cuando EventBus todavia no existe.
## En movil no hay ventana que elegir: siempre pantalla completa (inmersiva en
## Android). "Ventana" alli significa enseñar las barras del sistema encima del
## juego, y es lo que pasaba con la preferencia por defecto (false).
func _apply_window_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var wanted := _wanted_window_mode(ui_fullscreen, OS.has_feature("mobile"))
	if DisplayServer.window_get_mode() != wanted:
		DisplayServer.window_set_mode(wanted)

## Modo de ventana que corresponde a la preferencia en esta plataforma.
static func _wanted_window_mode(fullscreen: bool, mobile: bool) -> DisplayServer.WindowMode:
	if mobile or fullscreen:
		return DisplayServer.WINDOW_MODE_FULLSCREEN
	return DisplayServer.WINDOW_MODE_WINDOWED

## Cambia a pantalla completa (o vuelve a ventana), lo guarda y lo anuncia.
func set_fullscreen(enabled: bool) -> void:
	if ui_fullscreen == enabled and not _window_mode_mismatched(enabled):
		return
	ui_fullscreen = enabled
	_apply_window_mode()
	save_user_settings()
	EventBus.fullscreen_changed.emit(ui_fullscreen)

## Cambia el idioma, lo guarda y lo anuncia. Un idioma sin tabla o el mismo que
## ya estaba no hace nada (ni guarda ni avisa): asi un clic repetido no recarga.
func set_locale(locale: String) -> void:
	if not Tr.LOCALES.has(locale) or locale == ui_locale:
		return
	ui_locale = locale
	Tr.set_locale(locale)
	save_user_settings()
	EventBus.locale_changed.emit(locale)

func toggle_fullscreen() -> void:
	set_fullscreen(not ui_fullscreen)

## True si la ventana no esta en el modo que dice la preferencia (p.ej. el
## usuario salio de pantalla completa con el gestor de ventanas).
func _window_mode_mismatched(enabled: bool) -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return DisplayServer.window_get_mode() != _wanted_window_mode(enabled, OS.has_feature("mobile"))

## Seconds to cross-fade between music tracks (e.g. on era change).
var audio_music_fade := 1.5

## Number of pooled voices for overlapping one-shot SFX.
var audio_sfx_voices := 8

# ── Economy ──

var demolish_refund_ratio := 0.5
## Quitar un tramo de carretera que deja edificios sin conexion no se deja: se
## resaltan esos edificios en el mapa estos segundos (docs/03, red de carreteras).
var road_block_highlight_seconds := 4.0
## Cuantos nombres caben en el aviso "Primero mueve: ..." (el resto, "+N").
var road_block_max_names := 2
var max_offline_seconds := 28800.0

# ── Autosave ──
## Segundos REALES entre guardados periodicos. No pasa por get_duration(): es
## una red contra cierres inesperados, no parte del ritmo del juego, y dev_mode
## no debe convertirlo en un guardado por segundo.
var autosave_interval := 60.0
## Ventana en la que una rafaga de eventos (fin de pelea + Diezmo + fin de
## expedicion llegan en el mismo instante) se funde en un solo guardado.
var autosave_debounce := 0.5

# ── Market Config ──

var market_base_prices := {
	"wood": 3,
	"steel": 8,
	"oil": 12,
	# Barata: comprar comida tiene que ser el remedio inmediato del hambre.
	"food": 2,
}

var market_spread := 0.3
var market_volatility := 0.15
var market_tick_interval := 60.0
var market_price_sensitivity := 0.02
var market_min_price_mult := 0.5
var market_max_price_mult := 2.5
var market_mean_reversion := 0.05

## Mercado dinamico (solo Gobernador, GameMode.market_dynamic()): un calendario
## FIJO que sigue a la Tormenta. Cada fase empuja el precio de lo que el jugador
## necesita en ella; el patron se repite igual en cada tormenta para que se pueda
## aprender y aprovechar (comprar madera en la calma, vender antes del Aviso...).
## Valores: desplazamiento sobre el precio medio (0.30 = +30 %).
##   warning      Aviso y Ceniza: todos quieren madera para tapiar y reparar.
##   storm        Tormenta: nadie mueve acero bajo el granizo; se malvende.
##   after_tithe  Tras el Diezmo: la Regencia ha sacado oro de la isla y lo que
##                queda vale menos: todo cuesta mas oro (y se vende por mas).
##   calm         Calma: vuelta a la media.
## La comida sube ANTES del Diezmo: en el Aviso todos hacen acopio y en la
## Tormenta las granjas rinden el 15 %; quien compra en la calma ahorra.
var market_calendar := {
	"calm": {},
	"warning": {"wood": 0.30, "food": 0.25},
	"storm": {"steel": -0.25, "food": 0.40},
	"after_tithe": {"wood": 0.15, "steel": 0.15, "oil": 0.15, "food": 0.15},
}
## Cuanto se acerca el precio a su objetivo del calendario en cada tick (0..1).
## Con 0.35 y ticks de 15 s, un Aviso de 45 s ya lleva la madera a ~+22 %.
var market_calendar_pull := 0.35
## El tick del mercado dinamico: mas corto que el de Colono (60 s) para que una
## fase de 45-60 s se note en el precio.
var market_dynamic_tick_interval := 15.0
## Cuanto dura "tras el Diezmo" desde que se resuelve (pagado o repelido).
var market_after_tithe_seconds := 120.0
## Por debajo de esta distancia al objetivo la flecha dice "estable".
var market_trend_deadband := 0.02

# ── Era Config ──

var era_names := {
	1: "ERA_FRONTIER",
	2: "ERA_INDUSTRIAL",
	3: "ERA_PETROLEUM",
}

# ── Milestone Definitions ──

var milestone_definitions := [
	{"id": "first_sawmill", "name": "MILE_PIONEER", "era": 1},
	{"id": "first_gold_mine", "name": "MILE_PROSPECTOR", "era": 1},
	{"id": "first_warehouse", "name": "MILE_STOCKPILER", "era": 1},
	{"id": "era_2", "name": "MILE_INDUSTRIALIST", "era": 2},
	{"id": "era_3", "name": "MILE_OIL_BARON", "era": 3},
	{"id": "market_10_trades", "name": "MILE_MERCHANT", "era": 0},
	{"id": "military_ready", "name": "MILE_COMMANDER", "era": 0},
	{"id": "hq_built", "name": "MILE_GENERAL", "era": 3},
	# hq_max ya no gana: convoca la Auditoria Final. El nombre decia "Victoria".
	{"id": "hq_max", "name": "MILE_AUDIT", "era": 3},
]

# ── Tech Tree Config ──

## Bonuses applied by researched techs (modified at runtime)
var tech_production_bonus := 0.0       # added to production multiplier
var tech_consumption_reduction := 0.0  # subtracted from consumption per pop
var tech_build_speed_bonus := 0.0      # subtracted from build times

## 15 techs across 3 branches, 5 tiers each
var tech_definitions := [
	# ── Industrial Branch (production & efficiency) ──
	{"id": "ind_1", "branch": "industrial", "tier": 1, "name": "TECH_IND_1",
	 "cost": {"gold": 150, "wood": 80}, "duration": 30.0, "requires": [],
	 "bonus": {"production_mult": 0.1}},
	{"id": "ind_2", "branch": "industrial", "tier": 2, "name": "TECH_IND_2",
	 "cost": {"gold": 300, "steel": 100}, "duration": 45.0, "requires": ["ind_1"],
	 "bonus": {"storage_bonus": 200}},
	{"id": "ind_3", "branch": "industrial", "tier": 3, "name": "TECH_IND_3",
	 "cost": {"gold": 500, "steel": 200, "wood": 100}, "duration": 60.0, "requires": ["ind_2"],
	 "bonus": {"production_mult": 0.15}},
	{"id": "ind_4", "branch": "industrial", "tier": 4, "name": "TECH_IND_4",
	 "cost": {"gold": 800, "steel": 300, "oil": 100}, "duration": 90.0, "requires": ["ind_3"],
	 "bonus": {"consumption_reduction": 0.3}},
	{"id": "ind_5", "branch": "industrial", "tier": 5, "name": "TECH_IND_5",
	 "cost": {"gold": 1200, "steel": 500, "oil": 200}, "duration": 120.0, "requires": ["ind_4"],
	 "bonus": {"production_mult": 0.25}},

	# ── Military Branch (defense & combat prep) ──
	{"id": "mil_1", "branch": "military", "tier": 1, "name": "TECH_MIL_1",
	 "cost": {"gold": 200, "steel": 50}, "duration": 30.0, "requires": [],
	 "bonus": {"morale_bonus": 1}},
	{"id": "mil_2", "branch": "military", "tier": 2, "name": "TECH_MIL_2",
	 "cost": {"gold": 350, "steel": 150}, "duration": 45.0, "requires": ["mil_1"],
	 "bonus": {"morale_bonus": 1}},
	{"id": "mil_3", "branch": "military", "tier": 3, "name": "TECH_MIL_3",
	 "cost": {"gold": 600, "steel": 250, "wood": 100}, "duration": 60.0, "requires": ["mil_2"],
	 "bonus": {"morale_bonus": 2}},
	{"id": "mil_4", "branch": "military", "tier": 4, "name": "TECH_MIL_4",
	 "cost": {"gold": 900, "steel": 400, "oil": 150}, "duration": 90.0, "requires": ["mil_3"],
	 "bonus": {"morale_bonus": 2}},
	{"id": "mil_5", "branch": "military", "tier": 5, "name": "TECH_MIL_5",
	 "cost": {"gold": 1500, "steel": 600, "oil": 300}, "duration": 120.0, "requires": ["mil_4"],
	 "bonus": {"morale_bonus": 3}},

	# ── Logistics Branch (market, storage, speed) ──
	{"id": "log_1", "branch": "logistics", "tier": 1, "name": "TECH_LOG_1",
	 "cost": {"gold": 120, "wood": 60}, "duration": 25.0, "requires": [],
	 "bonus": {"market_spread_reduction": 0.05}},
	{"id": "log_2", "branch": "logistics", "tier": 2, "name": "TECH_LOG_2",
	 "cost": {"gold": 250, "wood": 120, "steel": 50}, "duration": 40.0, "requires": ["log_1"],
	 "bonus": {"storage_bonus": 300}},
	{"id": "log_3", "branch": "logistics", "tier": 3, "name": "TECH_LOG_3",
	 "cost": {"gold": 450, "steel": 150, "wood": 80}, "duration": 55.0, "requires": ["log_2"],
	 "bonus": {"build_speed": 0.15}},
	{"id": "log_4", "branch": "logistics", "tier": 4, "name": "TECH_LOG_4",
	 "cost": {"gold": 700, "steel": 250, "oil": 100}, "duration": 80.0, "requires": ["log_3"],
	 "bonus": {"market_spread_reduction": 0.08}},
	{"id": "log_5", "branch": "logistics", "tier": 5, "name": "TECH_LOG_5",
	 "cost": {"gold": 1100, "steel": 400, "oil": 250}, "duration": 110.0, "requires": ["log_4"],
	 "bonus": {"storage_bonus": 500, "build_speed": 0.2}},
]

# ── Rango del gobernador (docs/06 §Rango) ──
#
# XP dentro de la partida, aparte de eras e hitos. Lo reparte RankManager
# escuchando el EventBus; el rango se DERIVA de la XP (nunca se guarda suelto),
# asi que cargar dos veces da el mismo rango y los mismos bonos.
#
# Curva: subir del rango n al n+1 cuesta 100 + 60*(n-1). Estimacion para una
# campana de 2-4 h (sin medir aun con tools/line_probe.gd): ~4500 XP de
# acciones (obras, mejoras, combate, tormentas, hitos) + ~1 XP por ciclo de
# produccion, unas 9000-11000 en total. El rango 18 cae al final de la campana.

## XP por fuente. Las claves son las que RankManager.XP_SOURCES conoce.
var rank_xp_sources := {
	"build": 15,            # construction_completed (ni calzadas ni Nucleo)
	"build_decoration": 5,  # construction_completed de una decoracion
	"upgrade": 25,          # building_upgrade_completed
	"production": 1,        # production_tick: un ciclo de produccion pasiva
	"process": 5,           # process_completed: fabricar a mano
	"mining": 5,            # mining_completed: minar un yacimiento a mano
	"trade": 5,             # market_trade_completed
	"train": 10,            # unit_trained
	"fight_won": 40,        # encounter_ended(victory) y defense_auto_resolved(victory)
	"expedition_won": 80,   # expedition_ended(0): la campana entera vuelve con botin
	"storm": 30,            # storm_ended: aguantar una tormenta...
	"storm_per_severity": 10, # ...mas esto por punto de severidad
	"milestone": 100,       # milestone_completed
	# Tres campanas (feat/tres-campanas): una mision ganada, y el jefe de campana.
	"campaign_mission": 60, # campaign_mission_won (no jefe)
	"campaign_boss": 250,   # campaign_mission_won del jefe de campana
}

## XP acumulada para ESTAR en cada rango (indice 0 = rango 1). 18 rangos.
var rank_xp_thresholds := [
	0, 100, 260, 480, 760, 1100, 1500, 1960, 2480,
	3060, 3700, 4400, 5160, 5980, 6860, 7800, 8800, 9860,
]

## Titulo de cada rango (clave de Tr: RANK_TITLE_<n>).
func rank_title_key(rank: int) -> String:
	return "RANK_TITLE_%d" % clampi(rank, 1, rank_xp_thresholds.size())

## Lo que da cada rango al alcanzarlo. Claves posibles:
##   buildings   ids de edificio que se desbloquean (antes, bloqueados)
##   limit       id -> huecos extra sobre building_limits
##   production  fraccion sumada al multiplicador de produccion (0.01 = +1 %)
##   storage     fraccion sobre el tope de la bolsa (0.02 = +2 %)
##   patterns    fondos de la bandera que se pueden elegir (COLONY_PATTERNS)
##   emblems     emblemas de la bandera (COLONY_EMBLEMS)
##   colors      colores de la bandera (colony_colors)
##   paints      pinturas del regimiento (REGIMENT_PAINTS; solo cosmetico)
## No toca los edificios basicos ni sus eras (la linea jugable sigue igual): el
## rango abre decoraciones, huecos extra y cosmeticos. Un edificio nuevo y
## opcional entra aqui con `buildings`.
var rank_rewards := {
	1: {"patterns": ["plain", "bands_h", "bands_v", "halves_h", "cross"],
		"emblems": ["none", "gear", "anchor", "wheat", "hammer"],
		"colors": ["ivory", "brass", "crimson", "steel", "moss", "soot"],
		"paints": ["plain"]},
	2: {"buildings": ["garden", "flower_planter", "hay_cart", "well"], "emblems": ["tower"]},
	3: {"production": 0.01, "patterns": ["border"], "colors": ["sky"], "buildings": ["bonfire", "windmill"], "paints": ["stripes"]},
	4: {"storage": 0.02, "emblems": ["star"]},
	5: {"buildings": ["fountain", "flagpole"]},
	6: {"production": 0.01, "patterns": ["diagonal", "saltire"], "paints": ["spots"]},
	7: {"colors": ["copper", "red"]},
	8: {"buildings": ["statue"], "storage": 0.02},
	9: {"production": 0.01, "patterns": ["quartered"], "emblems": ["wrench"], "paints": ["desert"]},
	10: {"limit": {"house": 2}},
	11: {"colors": ["grass", "slate"], "emblems": ["wheel"]},
	12: {"production": 0.01, "storage": 0.02, "patterns": ["canton", "hoist_triangle"], "paints": ["snow"]},
	13: {"buildings": ["palm_trees"], "emblems": ["ship"]},
	14: {"colors": ["terracotta", "gold"], "emblems": ["cogs"]},
	15: {"production": 0.01, "patterns": ["stripes"], "paints": ["parade"]},
	16: {"storage": 0.02, "limit": {"tower": 1}, "emblems": ["sun"]},
	17: {"limit": {"house": 2}, "patterns": ["waves"]},
	18: {"production": 0.02, "patterns": ["checks"], "emblems": ["airship"]},
}

# ── Bandera y nombre del pais (ColonyFlag, ColonyIdentity, RankManager) ──
# La bandera es una receta de piezas: un fondo (dibujo con uno o dos colores),
# un emblema encima y tres colores [fondo 1, fondo 2, emblema]. Todo se dibuja
# por codigo en scripts/ui/ColonyFlag.gd; nada viene de otro juego ni imita
# simbolos reales de estados, partidos o ideologias. Lo que abre cada rango esta
# en rank_rewards (patterns / emblems / colors).

## Fondos, en orden de la galeria.
const COLONY_PATTERNS := ["plain", "bands_h", "bands_v", "halves_h", "cross", "border",
	"diagonal", "saltire", "quartered", "canton", "hoist_triangle", "stripes", "waves", "checks"]
## Emblemas, en orden de la galeria. "none" = sin emblema.
const COLONY_EMBLEMS := ["none", "gear", "anchor", "wheat", "hammer", "tower", "star",
	"wrench", "wheel", "ship", "cogs", "sun", "airship"]
## Colores de la bandera. Los seis primeros son los de siempre de la colonia; el
## resto sale de la paleta de la maqueta (ToyPalette): marfil = CREAM, cielo =
## SKY, rojo = RED, hierba = GREEN, pizarra = SLATE, teja = TERRACOTTA, oro = BRASS.
var colony_colors := {
	"ivory": Color8(242, 222, 180),
	"brass": Color(0.80, 0.62, 0.25),
	"crimson": Color(0.68, 0.14, 0.14),
	"steel": Color(0.30, 0.45, 0.62),
	"moss": Color(0.33, 0.50, 0.24),
	"soot": Color(0.18, 0.18, 0.20),
	"sky": Color8(78, 160, 204),
	"copper": Color(0.72, 0.40, 0.20),
	"red": Color8(220, 50, 38),
	"grass": Color8(108, 172, 62),
	"slate": Color8(96, 98, 110),
	"terracotta": Color8(210, 92, 58),
	"gold": Color8(232, 172, 58),
}
const COLONY_COLOR_ORDER := ["ivory", "brass", "crimson", "steel", "moss", "soot", "sky",
	"copper", "red", "grass", "slate", "terracotta", "gold"]
## La bandera de serie (la de una partida sin nada que elegir).
const COLONY_DEFAULT_SPEC := {"pattern": "bands_h", "emblem": "gear", "colors": ["brass", "ivory", "crimson"]}
## Largo maximo del nombre del pais ("Republica de Puerto Hierro" cabe justo).
const COLONY_NAME_MAX := 26
## Las seis banderas de antes (guardados con "rank": {"flag", "color"}),
## traducidas a piezas al cargar: [fondo, emblema].
const COLONY_LEGACY_FLAGS := {
	"plain": ["plain", "none"], "band": ["bands_h", "none"], "cross": ["cross", "none"],
	"diagonal": ["diagonal", "none"], "gear": ["plain", "gear"], "chevron": ["hoist_triangle", "none"],
}

# ── Regimiento (solo cosmetico: ArmyManager guarda "regiment", RegimentLook lo
# pinta; docs/15 §12) ──
# El ejercito del jugador lleva nombre, color, emblema y pintura, y gana
# estrellas por combates ganados. Nada de esto cambia una sola cifra del combate.
# Color y emblema salen de las piezas de la bandera (colony_colors /
# COLONY_EMBLEMS, abiertas por rango); las pinturas, de rank_rewards "paints".

## Pinturas, en orden de la galeria. "plain" = liso (el de siempre).
const REGIMENT_PAINTS := ["plain", "stripes", "spots", "desert", "snow", "parade"]
## Combates ganados para cada estrella (1, 2 y 3 estrellas).
var regiment_star_wins := [10, 25, 50]

## Bonos del rango, aplicados en tiempo de ejecucion por RankManager (asigna el
## total del rango actual; nunca suma sobre lo que habia).
var rank_production_bonus := 0.0
var rank_storage_bonus := 0.0
var rank_limit_bonus: Dictionary = {}

# ── Aspecto de los edificios: obra, ruina y actividad (docs/03, docs/18) ──

## Fases de obra, compartidas por huella (1x1 / 2x2 / 3x3): valla con
## materiales -> solar con cimientos -> estructura a medio levantar. Se pasa de
## una a la siguiente cuando el progreso de la obra cruza cada umbral.
var construction_phase_thresholds := [0.34, 0.67]
## La obra de cada edificio (docs/03, "Obra por edificio"): las tres fases son
## las mismas para todos, pero cada edificio las viste a su manera. Lo que no
## diga su fila sale de construction_style_default. Campos:
## - "piles": que se apila en la fase 0 (y lo que sobra en la 1), en orden:
##   planks, beams, bricks, logs, sawdust, rivets, pipes, drums, sacks, stone,
##   crates, sandbags, gravel, soil.
## - "fence": la valla de la fase 0: planks, dark_planks, sheet (chapa), canvas (lona).
## - "tarp": color de la lona (la valla de lona y la que tapa una pila).
## - "frame": la silueta de la fase 2, que insinua el edificio: box, chimney,
##   gable, tower, tanks, dome, plinth, basin, hall, headframe, low, mast.
## - "frame_mat": de que son pilares y vigas: steel, wood, stone.
## - "site_fx": lo que se mueve mientras se trabaja: sparks (soldadura, edificios
##   de acero), dust (polvo, piedra y madera) o "" (nada mas que grua y banderin).
## - "flag": color del banderin que ondea en la valla o en la grua.
## - "crane": color de la grua.
## La disposicion (donde va cada pila, la puerta, el andamio, la grua...) no
## esta aqui: la decide la semilla de cada instancia (BuildingLook.site_layout).
var construction_style_default := {
	"piles": ["planks", "beams", "bricks"], "fence": "planks",
	"tarp": Color(0.52, 0.48, 0.38), "frame": "box", "frame_mat": "steel",
	"site_fx": "", "flag": Color(0.72, 0.13, 0.10), "crane": Color(0.95, 0.72, 0.10),
}
var construction_style := {
	"nucleo": {"piles": ["stone", "beams", "rivets"], "fence": "sheet", "tarp": Color(0.36, 0.34, 0.40),
		"frame": "dome", "frame_mat": "stone", "site_fx": "sparks", "flag": Color(0.77, 0.59, 0.16)},
	"house": {"piles": ["sacks", "bricks", "planks"], "fence": "planks", "tarp": Color(0.62, 0.55, 0.40),
		"frame": "gable", "frame_mat": "wood", "site_fx": "dust", "flag": Color(0.20, 0.42, 0.62)},
	"sawmill": {"piles": ["logs", "sawdust", "planks"], "fence": "dark_planks", "tarp": Color(0.40, 0.46, 0.26),
		"frame": "hall", "frame_mat": "wood", "site_fx": "dust", "flag": Color(0.90, 0.55, 0.12)},
	"gold_mine": {"piles": ["gravel", "beams", "crates"], "fence": "dark_planks", "tarp": Color(0.48, 0.34, 0.20),
		"frame": "headframe", "frame_mat": "wood", "site_fx": "dust", "flag": Color(0.93, 0.78, 0.32)},
	"warehouse": {"piles": ["crates", "planks", "sacks"], "fence": "planks", "tarp": Color(0.30, 0.38, 0.50),
		"frame": "hall", "frame_mat": "steel", "site_fx": "", "flag": Color(0.30, 0.55, 0.30)},
	"foundry": {"piles": ["beams", "rivets", "bricks"], "fence": "sheet", "tarp": Color(0.45, 0.22, 0.14),
		"frame": "chimney", "frame_mat": "steel", "site_fx": "sparks", "flag": Color(0.95, 0.45, 0.08)},
	"barracks": {"piles": ["sandbags", "crates", "beams"], "fence": "sheet", "tarp": Color(0.33, 0.37, 0.20),
		"frame": "hall", "frame_mat": "steel", "site_fx": "sparks", "flag": Color(0.72, 0.13, 0.10),
		"crane": Color(0.42, 0.45, 0.24)},
	"refinery": {"piles": ["pipes", "drums", "beams"], "fence": "sheet", "tarp": Color(0.18, 0.18, 0.20),
		"frame": "tanks", "frame_mat": "steel", "site_fx": "sparks", "flag": Color(0.95, 0.85, 0.20)},
	"tower": {"piles": ["sandbags", "beams", "rivets"], "fence": "canvas", "tarp": Color(0.30, 0.33, 0.18),
		"frame": "tower", "frame_mat": "steel", "site_fx": "sparks", "flag": Color(0.72, 0.13, 0.10)},
	"headquarters": {"piles": ["stone", "beams", "rivets"], "fence": "canvas", "tarp": Color(0.55, 0.12, 0.10),
		"frame": "mast", "frame_mat": "steel", "site_fx": "sparks", "flag": Color(0.77, 0.59, 0.16),
		"crane": Color(0.72, 0.13, 0.10)},
	"market": {"piles": ["crates", "sacks", "planks"], "fence": "canvas", "tarp": Color(0.70, 0.36, 0.16),
		"frame": "gable", "frame_mat": "wood", "site_fx": "dust", "flag": Color(0.20, 0.55, 0.50)},
	"laboratory": {"piles": ["drums", "pipes", "crates"], "fence": "sheet", "tarp": Color(0.22, 0.36, 0.42),
		"frame": "dome", "frame_mat": "steel", "site_fx": "sparks", "flag": Color(0.45, 0.80, 0.85)},
	"garden": {"piles": ["soil", "sacks", "planks"], "fence": "planks", "tarp": Color(0.36, 0.46, 0.24),
		"frame": "low", "frame_mat": "wood", "site_fx": "dust", "flag": Color(0.85, 0.35, 0.55)},
	"fountain": {"piles": ["stone", "pipes", "gravel"], "fence": "planks", "tarp": Color(0.30, 0.45, 0.58),
		"frame": "basin", "frame_mat": "stone", "site_fx": "dust", "flag": Color(0.25, 0.55, 0.78)},
	"statue": {"piles": ["stone", "stone", "sacks"], "fence": "canvas", "tarp": Color(0.58, 0.54, 0.46),
		"frame": "plinth", "frame_mat": "stone", "site_fx": "dust", "flag": Color(0.77, 0.59, 0.16)},
	# Edificios utiles de la 1.1 (feat/edificios-utiles-1).
	"windmill": {"piles": ["stone", "planks", "sacks"], "fence": "planks", "tarp": Color(0.62, 0.55, 0.40),
		"frame": "tower", "frame_mat": "stone", "site_fx": "dust", "flag": Color(0.30, 0.60, 0.22)},
	"silo": {"piles": ["rivets", "sacks", "planks"], "fence": "sheet", "tarp": Color(0.36, 0.40, 0.46),
		"frame": "tanks", "frame_mat": "steel", "site_fx": "sparks", "flag": Color(0.30, 0.60, 0.22)},
	"tavern": {"piles": ["bricks", "planks", "drums"], "fence": "planks", "tarp": Color(0.66, 0.42, 0.20),
		"frame": "gable", "frame_mat": "wood", "site_fx": "dust", "flag": Color(0.82, 0.63, 0.20)},
	"carpentry": {"piles": ["logs", "planks", "sawdust"], "fence": "dark_planks", "tarp": Color(0.46, 0.38, 0.24),
		"frame": "hall", "frame_mat": "wood", "site_fx": "dust", "flag": Color(0.80, 0.16, 0.10)},
	"well": {"piles": ["stone", "gravel", "pipes"], "fence": "planks", "tarp": Color(0.30, 0.45, 0.58),
		"frame": "basin", "frame_mat": "stone", "site_fx": "dust", "flag": Color(0.25, 0.55, 0.78)},
	"lighthouse": {"piles": ["stone", "beams", "sandbags"], "fence": "canvas", "tarp": Color(0.55, 0.12, 0.10),
		"frame": "tower", "frame_mat": "stone", "site_fx": "dust", "flag": Color(0.95, 0.74, 0.12)},
	"fuel_depot": {"piles": ["drums", "pipes", "rivets"], "fence": "sheet", "tarp": Color(0.18, 0.18, 0.20),
		"frame": "tanks", "frame_mat": "steel", "site_fx": "sparks", "flag": Color(0.95, 0.85, 0.20)},
	# Aire y mar (feat/aire-mar-reglas): grada de madera y chapa junto al agua;
	# hangar de chapa con mastil para el dirigible.
	"shipyard": {"piles": ["beams", "planks", "rivets"], "fence": "dark_planks", "tarp": Color(0.22, 0.32, 0.42),
		"frame": "hall", "frame_mat": "wood", "site_fx": "sparks", "flag": Color(0.20, 0.42, 0.62),
		"crane": Color(0.42, 0.45, 0.24)},
	"aerodrome": {"piles": ["drums", "beams", "rivets"], "fence": "sheet", "tarp": Color(0.36, 0.40, 0.46),
		"frame": "mast", "frame_mat": "steel", "site_fx": "sparks", "flag": Color(0.95, 0.74, 0.12)},
	# Decoraciones baratas (feat/decoraciones-1): obras pequenas y rapidas.
	"lamp_post": {"piles": ["rivets", "stone", "planks"], "fence": "planks", "tarp": Color(0.36, 0.34, 0.40),
		"frame": "mast", "frame_mat": "steel", "site_fx": "sparks", "flag": Color(0.93, 0.78, 0.32)},
	"park_bench": {"piles": ["planks", "rivets", "planks"], "fence": "planks", "tarp": Color(0.52, 0.42, 0.30),
		"frame": "low", "frame_mat": "wood", "site_fx": "dust", "flag": Color(0.20, 0.42, 0.62)},
	"hedge": {"piles": ["soil", "sacks", "soil"], "fence": "planks", "tarp": Color(0.36, 0.46, 0.24),
		"frame": "low", "frame_mat": "wood", "site_fx": "dust", "flag": Color(0.30, 0.60, 0.22)},
	"avenue_tree": {"piles": ["soil", "stone", "sacks"], "fence": "planks", "tarp": Color(0.36, 0.46, 0.24),
		"frame": "low", "frame_mat": "wood", "site_fx": "dust", "flag": Color(0.30, 0.60, 0.22)},
	"flower_planter": {"piles": ["soil", "bricks", "sacks"], "fence": "planks", "tarp": Color(0.62, 0.40, 0.30),
		"frame": "low", "frame_mat": "stone", "site_fx": "dust", "flag": Color(0.85, 0.35, 0.55)},
	"colony_sign": {"piles": ["planks", "logs", "planks"], "fence": "planks", "tarp": Color(0.52, 0.42, 0.30),
		"frame": "mast", "frame_mat": "wood", "site_fx": "dust", "flag": Color(0.72, 0.13, 0.10)},
	"hay_cart": {"piles": ["sacks", "planks", "sacks"], "fence": "planks", "tarp": Color(0.62, 0.55, 0.30),
		"frame": "low", "frame_mat": "wood", "site_fx": "dust", "flag": Color(0.93, 0.78, 0.32)},
	"bonfire": {"piles": ["logs", "stone", "logs"], "fence": "dark_planks", "tarp": Color(0.48, 0.34, 0.20),
		"frame": "low", "frame_mat": "stone", "site_fx": "dust", "flag": Color(0.90, 0.55, 0.12)},
	"flagpole": {"piles": ["beams", "stone", "rivets"], "fence": "canvas", "tarp": Color(0.55, 0.12, 0.10),
		"frame": "mast", "frame_mat": "steel", "site_fx": "sparks", "flag": Color(0.72, 0.13, 0.10)},
	"palm_trees": {"piles": ["soil", "sacks", "gravel"], "fence": "planks", "tarp": Color(0.70, 0.62, 0.42),
		"frame": "low", "frame_mat": "wood", "site_fx": "dust", "flag": Color(0.25, 0.55, 0.78)},
}
## La animacion de la obra (grua, polea, banderin): velocidad base de giro de
## la grua (rad/s de la fase del vaiven) y cuanto se abre el vaiven (rad). Cada
## instancia la multiplica por su propio factor (0,7-1,3) y arranca desfasada.
var construction_crane_speed := 0.45
var construction_crane_swing := 0.7
## Cada cuanto relee la vista 3D el estado de TODOS los edificios (un solo
## reloj para todo el mapa, no uno por edificio). Las senales de obra, ruina y
## reparacion repintan al instante; esto solo cubre el paso de fase y el
## encendido/apagado de la actividad.
var building_look_sync_interval := 0.25
## La animacion de "trabajando": hoja de 8 fotogramas en rejilla 4x2 a 12 fps.
## La anima un shader con TIME: ni timers ni tweens por edificio.
var building_fx_frames := 8
var building_fx_columns := 4
var building_fx_fps := 12.0
## Que efecto lleva cada edificio que trabaja. "smoke": humo de chimenea;
## "dust": serrin claro; "glow": luz que parpadea sin humo. Un edificio que no
## esta aqui no tiene animacion de actividad. Sus columnas de humo y su luz
## salen de la cima medida del modelo (3D) o de las chimeneas del dibujo (2D).
var building_active_fx := {
	"nucleo": "smoke", "gold_mine": "smoke", "foundry": "smoke", "refinery": "smoke",
	"headquarters": "smoke", "barracks": "smoke", "sawmill": "dust",
	"warehouse": "glow", "market": "glow", "laboratory": "glow", "tower": "glow",
	"tavern": "smoke", "carpentry": "dust", "lighthouse": "glow", "fuel_depot": "glow",
	"shipyard": "smoke", "aerodrome": "glow",
}
## Una ruina se hunde esta fraccion de su altura en el suelo y se inclina estos
## radianes: con el hollin y los escombros, se distingue de lejos.
var ruin_sink_ratio := 0.38
var ruin_tilt := 0.07

## Etapas visibles de dano entre sano y ruina (docs/03, "Etapas de dano"):
## por debajo de la primera proporcion de vida el edificio esta LEVE (grietas,
## tejas caidas, una tabla suelta), por debajo de la segunda GRAVE (chapa
## colgando, viga rota, humo negro y chispas). La ruina sigue siendo vida 0.
## Solo aspecto: ni el dano ni la reparacion cambian por esto.
var damage_stage_thresholds := [0.75, 0.4]
## Cuanto se ladea (radianes) y se hunde (fraccion de su altura) el modelo en
## cada etapa: [leve, grave]. La ruina usa ruin_tilt / ruin_sink_ratio.
var damage_tilt := [0.025, 0.05]
var damage_sink_ratio := [0.0, 0.05]

## La Tormenta a la vista (docs/21 §12), SOLO aspecto: las duraciones y los
## efectos de cada fase son los storm_* de mas abajo y no cambian por esto.
## Antes el cielo se quedaba oscuro todo el Aviso, la Ceniza y la Tormenta
## (2-3 minutos); ahora la llegada de la Tormenta es un GOLPE corto y marcado
## (oscuridad, rafaga de viento con ceniza) y el resto del tiempo el cielo
## queda apenas tenido. El HUD de la Tormenta sigue diciendo la fase.
## Cuanto dura el golpe en pleno (s, reales: no los acelera dev_mode), cuanto
## tarda en cerrarse y cuanto en abrirse hasta el tono de fondo.
var storm_visual_punch := 6.0
var storm_visual_punch_in := 0.7
var storm_visual_punch_out := 3.0
## El tono de fondo (peso de ceniza, 0-1) de cada fase fuera del golpe: el
## Aviso y la Ceniza apenas tinen; tras el golpe la Tormenta y el Diezmo se
## quedan en `storm_visual_linger`.
var storm_visual_warning := 0.12
var storm_visual_ash := 0.2
var storm_visual_linger := 0.22
## Motas de ceniza de la rafaga del golpe por perfil de dispositivo.
var storm_visual_gust_amount := {"pc": 160, "tablet": 110, "phone": 70}

# ── Parcela y atrezo de cada edificio (docs/03, "Parcela y atrezo") ──
## Cada edificio vive en su parcela (guia de estilo, regla 1): suelo propio que
## cubre la huella entera y atrezo en el patio que queda entre el modelo y el
## borde. Las dos vistas leen esta misma tabla (LotPlan), asi que dicen lo mismo.
##
## - "ground": "slabs" (losas), "dirt" (tierra batida), "plate" (chapa
##   remachada) o "grass" (hierba con bordillo).
## - "trim": lo que corre por el borde que no da a calzada: "fence" (valla baja),
##   "curb" (bordillo), "rail" (barandilla de hierro), "sandbags" (sacos
##   terreros) o "pipes" (tuberia con valvulas).
## - "yard": ancho del patio, en casillas. El modelo se encoge (solo en planta,
##   nunca en altura) para dejarlo libre; nunca se agranda.
## - "props": el atrezo que se reparte por el patio. El primero sale siempre;
##   el resto se elige con la semilla de la instancia (celda + id).
## - "count": cuantas piezas [min, max]. "accent": la familia del color saturado.
## - "signature": el elemento exagerado que el modelo GLB no trae (regla 3), en
##   la esquina "corner" del patio ("NE", "SW"...; "N" = las dos de atras): la
##   chimenea de la Fundicion, la grua del Almacen, la antena del Laboratorio,
##   el emblema del Cuartel General... Esa esquina no lleva atrezo. "ROOF":
##   encima del tejado, apoyado en la altura medida del modelo.
## - "keep_clear": esquinas sin atrezo por otra cosa (la del Nucleo es la del
##   mastil con la bandera del pais, ColonyFlag3D/2D). El Cuartel lleva la suya
##   en un mastil corto sobre el tejado (receta, FlagAnchor): ya no tiene el
##   mastil alto de la parcela con la bandera amarilla (2026-10-18), y el
##   Cuartel General no lleva bandera ninguna, ni en la parcela.
## Sin entrada (la calzada), sin parcela.
var building_lot_style := {
	"sawmill": {"ground": "dirt", "trim": "fence", "yard": 0.3, "accent": "industrial",
		"props": ["logs", "planks", "logs", "crate", "barrel", "lamp"], "count": [5, 7]},
	"gold_mine": {"ground": "dirt", "trim": "fence", "yard": 0.3, "accent": "industrial",
		"props": ["cart", "ore", "crate", "barrel", "lamp"], "count": [4, 6],
		"signature": "ore_heap", "corner": "SW"},
	"foundry": {"ground": "plate", "trim": "rail", "yard": 0.3, "accent": "industrial",
		"props": ["ingots", "coal", "ingots", "barrel", "crate", "drums"], "count": [4, 6],
		"signature": "chimney", "corner": "NE"},
	"refinery": {"ground": "plate", "trim": "pipes", "yard": 0.3, "accent": "industrial",
		"props": ["drums", "valve", "drums", "barrel", "crate"], "count": [4, 6],
		"signature": "manifold", "corner": "SE"},
	"warehouse": {"ground": "slabs", "trim": "curb", "yard": 0.3, "accent": "civic",
		"props": ["crate", "pallet", "crate", "sacks", "barrel", "crate"], "count": [5, 7],
		"signature": "crane", "corner": "NE"},
	"market": {"ground": "slabs", "trim": "curb", "yard": 0.28, "accent": "civic",
		"props": ["goods", "sacks", "goods", "barrel", "planter", "crate"], "count": [5, 7]},
	"laboratory": {"ground": "slabs", "trim": "rail", "yard": 0.28, "accent": "civic",
		"props": ["gas", "crate", "gas", "lamp", "planter"], "count": [4, 6],
		"signature": "antenna", "corner": "NW"},
	"barracks": {"ground": "dirt", "trim": "sandbags", "yard": 0.3, "accent": "military",
		"props": ["dummy", "target", "ammo", "dummy", "sacks"], "count": [4, 6]},
	"tower": {"ground": "plate", "trim": "sandbags", "yard": 0.3, "accent": "military",
		"props": ["ammo", "sacks", "ammo", "lamp", "barrel"], "count": [4, 6],
		"signature": "cannon", "corner": "SE"},
	"headquarters": {"ground": "slabs", "trim": "rail", "yard": 0.28, "accent": "military",
		"props": ["lamp", "planter", "ammo", "planter"], "count": [3, 5],
		"signature": "emblem", "corner": "ROOF"},
	# La Granja (rama comida): tierra batida, valla baja y sacos de la cosecha. El
	# patio es mas estrecho que el de los demas: el campo es el edificio.
	"farm": {"ground": "dirt", "trim": "fence", "yard": 0.25, "accent": "residential",
		"props": ["sacks", "barrel", "sacks", "crate", "sacks"], "count": [3, 5]},
	"house": {"ground": "grass", "trim": "fence", "yard": 0.3, "accent": "residential",
		"props": ["clothesline", "planter", "bench", "barrel", "planter"], "count": [3, 5]},
	"nucleo": {"ground": "slabs", "trim": "curb", "yard": 0.15, "accent": "civic",
		"props": ["lamp", "planter", "bench", "lamp", "planter"], "count": [6, 9],
		"keep_clear": ["NE"]},
	"garden": {"ground": "grass", "trim": "curb", "yard": 0.25, "accent": "residential",
		"props": ["bench", "lamp", "planter"], "count": [3, 5]},
	"fountain": {"ground": "slabs", "trim": "curb", "yard": 0.25, "accent": "civic",
		"props": ["bench", "lamp", "planter", "bench"], "count": [3, 5]},
	"statue": {"ground": "slabs", "trim": "curb", "yard": 0.25, "accent": "civic",
		"props": ["lamp", "planter", "bench"], "count": [3, 5]},
	# Edificios utiles de la 1.1 (feat/edificios-utiles-1). Patio 0,3 como los
	# demas: el modelo (UtilityToys / su horneado) mide 2,8 x 2,8 m.
	"windmill": {"ground": "dirt", "trim": "fence", "yard": 0.3, "accent": "residential",
		"props": ["sacks", "cart", "sacks", "barrel", "crate"], "count": [3, 5]},
	"silo": {"ground": "dirt", "trim": "fence", "yard": 0.3, "accent": "residential",
		"props": ["sacks", "crate", "sacks", "barrel"], "count": [3, 5]},
	"tavern": {"ground": "slabs", "trim": "curb", "yard": 0.3, "accent": "civic",
		"props": ["bench", "barrel", "lamp", "planter", "barrel"], "count": [4, 6]},
	"carpentry": {"ground": "dirt", "trim": "fence", "yard": 0.3, "accent": "industrial",
		"props": ["planks", "logs", "planks", "crate", "lamp"], "count": [4, 6]},
	"well": {"ground": "slabs", "trim": "curb", "yard": 0.3, "accent": "civic",
		"props": ["planter", "bench", "lamp", "barrel"], "count": [3, 5]},
	"lighthouse": {"ground": "plate", "trim": "sandbags", "yard": 0.3, "accent": "military",
		"props": ["lamp", "ammo", "sacks", "barrel"], "count": [3, 5]},
	"fuel_depot": {"ground": "plate", "trim": "pipes", "yard": 0.3, "accent": "industrial",
		"props": ["drums", "valve", "drums", "barrel", "crate"], "count": [4, 6]},
	# Aire y mar (feat/aire-mar-reglas): militares los dos.
	"shipyard": {"ground": "plate", "trim": "rail", "yard": 0.3, "accent": "military",
		"props": ["crate", "barrel", "planks", "ammo", "lamp"], "count": [4, 6]},
	"aerodrome": {"ground": "slabs", "trim": "sandbags", "yard": 0.3, "accent": "military",
		"props": ["drums", "ammo", "lamp", "crate", "barrel"], "count": [4, 6]},
	# Decoraciones baratas (feat/decoraciones-1): suelo, bordillo y una o dos
	# piezas de atrezo como mucho (la decoracion ya es atrezo, y cada pieza de
	# mas cuesta en la tablet).
	"lamp_post": {"ground": "slabs", "trim": "curb", "yard": 0.25, "accent": "civic", "props": ["planter", "bench"], "count": [1, 2]},
	"park_bench": {"ground": "slabs", "trim": "curb", "yard": 0.25, "accent": "civic", "props": ["planter", "lamp"], "count": [1, 2]},
	"hedge": {"ground": "grass", "trim": "curb", "yard": 0.25, "accent": "residential", "props": ["planter", "bench"], "count": [1, 2]},
	"avenue_tree": {"ground": "slabs", "trim": "curb", "yard": 0.25, "accent": "residential", "props": ["bench", "planter"], "count": [1, 2]},
	"flower_planter": {"ground": "slabs", "trim": "curb", "yard": 0.25, "accent": "residential", "props": ["bench", "lamp"], "count": [1, 2]},
	"colony_sign": {"ground": "grass", "trim": "curb", "yard": 0.25, "accent": "civic", "props": ["planter", "lamp"], "count": [1, 2]},
	"hay_cart": {"ground": "dirt", "trim": "fence", "yard": 0.25, "accent": "residential", "props": ["sacks", "barrel"], "count": [1, 2]},
	"bonfire": {"ground": "dirt", "trim": "curb", "yard": 0.25, "accent": "residential", "props": ["logs", "barrel"], "count": [1, 2]},
	"flagpole": {"ground": "slabs", "trim": "curb", "yard": 0.25, "accent": "civic", "props": ["lamp", "planter"], "count": [1, 2]},
	"palm_trees": {"ground": "grass", "trim": "curb", "yard": 0.25, "accent": "residential", "props": ["barrel", "crate"], "count": [1, 2]},
}
## El acento saturado de cada familia (guia, regla 4): rojo valvula en lo
## industrial, amarillo senal en lo militar, laton en lo civico, verde en lo
## residencial.
var building_lot_accents := {
	"industrial": Color(0.80, 0.16, 0.10),
	"military": Color(0.95, 0.74, 0.12),
	"civic": Color(0.82, 0.63, 0.20),
	"residential": Color(0.30, 0.60, 0.22),
}

# ── Velocidad del juego (x1 / x2) ──
# Un multiplicador que leen los servicios que tickean la simulacion, y NO
# Engine.time_scale: time_scale tambien acelera los tweens de la interfaz, la
# camara, los avisos, el autoguardado (que cuenta segundos reales) y el reloj
# del tutorial, y cada uno pediria su excepcion en archivos de otros. Aqui la
# interfaz va a su ritmo sin tocar nada y la simulacion pasa por sim_delta().
# Es estado del dispositivo, no de la partida: no viaja en save_game.json y al
# abrir el juego siempre es x1 (no se escribe en settings.cfg: seria un valor
# que nadie lee). Lo que si se guarda es el boton (oculto/movido, HudRegistry).
const GAME_SPEEDS := [1.0, 2.0]
var game_speed := 1.0

## Pone la velocidad (solo valores de GAME_SPEEDS) y avisa por EventBus.
func set_game_speed(speed: float) -> void:
	var next := speed if speed in GAME_SPEEDS else 1.0
	if is_equal_approx(next, game_speed):
		return
	game_speed = next
	EventBus.game_speed_changed.emit(game_speed)

## x1 <-> x2 (el boton del HUD y la tecla F).
func toggle_game_speed() -> void:
	var i := GAME_SPEEDS.find(game_speed)
	set_game_speed(GAME_SPEEDS[(i + 1) % GAME_SPEEDS.size()])

## El delta de simulacion de este fotograma: lo que tickean produccion,
## construccion, procesos, Tormenta, dia y noche, ejercito, eventos...
func sim_delta(delta: float) -> float:
	return delta * game_speed

## Una pausa o animacion del tablero de combate, acortada con x2. Para el
## turno enemigo (get_combat_ai_step_delay) y las animaciones de la vista de
## combate, que la leen de aqui y escuchan EventBus.game_speed_changed.
func combat_pace(seconds: float) -> float:
	return seconds / maxf(game_speed, 0.01)

# ── Duration Helpers ──

func get_duration(base: float) -> float:
	if dev_mode:
		return maxf(base * dev_time_scale, 1.0)
	return base * time_multiplier

func get_build_time(base: float) -> float:
	if base <= 0.0:
		return 0.0
	if dev_mode:
		return 2.0
	var speed_reduction := maxf(0.0, 1.0 - tech_build_speed_bonus)
	return base * time_multiplier * speed_reduction

func get_production_interval(base: float) -> float:
	if base <= 0.0:
		return 0.0
	if dev_mode:
		return 4.0
	return base * time_multiplier

func get_upgrade_duration(level: int) -> float:
	return get_duration(upgrade_base_duration * level)

# ── Upgrade Helpers ──

func get_upgrade_cost(data: BuildingData, to_level: int) -> Dictionary:
	if to_level < 1 or to_level > max_building_level:
		return {}
	# HQ has special override costs
	if data.id == "headquarters" and hq_upgrade_costs.has(to_level):
		var hq_cost_raw: Dictionary = hq_upgrade_costs[to_level]
		var cost := {}
		for res_name in hq_cost_raw:
			var type := ResourceManager.name_to_type(res_name)
			if type != -1:
				cost[type] = hq_cost_raw[res_name]
		return cost
	var mult: float = upgrade_cost_multiplier[to_level - 1]
	var cost := {}
	var base: Dictionary = data.get_base_cost()
	for type in base:
		cost[type] = int(base[type] * mult)
	# Repuestos: solo salen de las escaramuzas (doc 21 §3.1). Los pide el nivel 3
	# de los productores, para que salir sea una necesidad y no un extra.
	var parts: int = upgrade_parts_needed(data.id, to_level)
	if parts > 0:
		cost[ResourceManager.Type.PARTS] = parts
	return cost

## Repuestos que pide subir `building_id` a `to_level` (0 = ninguno). Tabla en
## `upgrade_parts_cost` / `upgrade_parts_buildings` (seccion de escaramuzas).
func upgrade_parts_needed(building_id: String, to_level: int) -> int:
	if not building_id in upgrade_parts_buildings:
		return 0
	return int(upgrade_parts_cost.get(to_level, 0))

func get_production_multiplier(level: int) -> float:
	if level < 1 or level > max_building_level:
		return 1.0
	return upgrade_production_multiplier[level - 1]

# ── Process/Mining with duration already scaled ──

func get_processes_for(building_id: String) -> Array:
	var procs: Array = building_processes.get(building_id, [])
	var result: Array = []
	for proc in procs:
		var copy: Dictionary = proc.duplicate()
		copy["duration"] = get_duration(proc["duration"])
		result.append(copy)
	return result

func get_mining_info(deposit_id: String) -> Dictionary:
	var data: Dictionary = mining_data.get(deposit_id, {})
	if data.is_empty():
		return {}
	var copy: Dictionary = data.duplicate()
	copy["duration"] = get_duration(data["duration"])
	return copy

func get_deposit_max_uses(deposit_id: String) -> int:
	return deposit_max_uses.get(deposit_id, 3)

# ── Building Limit Helpers ──

## Topes que suben con la era (decision D1 de Bryan, 14-10-2026; docs/03 §Topes).
## [era 1, era 2, era 3]. La era 1 es el tope de siempre (`building_limits`): una
## partida guardada nunca queda por encima de su tope. Regla general ≈ ×1,5 en la
## era 2 y ×2 en la era 3, con tres excepciones que no suben:
##   warehouse 5  la bolsa de la era 3 sin tecnologias es 1000 + 5×500 = 3500, el
##                precio justo del CG nivel 3 (hq_upgrade_costs[3] sin materiales).
##                Con 7 almacenes serian 4500 (5500 con las tecnologias) y el CG 3
##                dejaria de pedir la bolsa llena. La bolsa ya crece por era sola
##                (base_storage_cap_by_era 600/800/1000) y por nivel de almacen.
##   tower 6      4 torres ya dan el 60 % de mitigacion (storm_tower_mitigation_max)
##                y solo 2 salen al tablero (storm_tower_garrison_max): mas torres
##                no darian nada. El rango sigue dando +1 (rango 16).
##   unicos 1     Mercado, Laboratorio y Cuartel General (no estan en esta tabla).
## El Cuartel no esta: no tiene tope en ninguna era (Bryan, 18-10-2026). Lo que
## frena al ejercito no es cuantos cuarteles caben sino la capacidad, que crece
## cada vez menos y tiene techo (`get_army_capacity`), los huecos de
## entrenamiento (`army_training_slots_max`) y el sueldo en oro.
## Un id que no esta aqui usa `building_limits` en todas las eras.
var building_limits_by_era := {
	"sawmill": [5, 8, 10],
	"gold_mine": [4, 6, 8],
	"foundry": [3, 5, 6],
	"refinery": [2, 3, 4],
	"house": [10, 15, 20],
	"farm": [6, 9, 12],
	"warehouse": [5, 5, 5],
	"tower": [6, 6, 6],
	# Edificios utiles de la 1.1 (feat/edificios-utiles-1, doc 21 §6.3). El Faro
	# es unico; el Deposito de combustible no se levanta antes de la Refineria
	# (prerrequisito), asi que sus topes de era 1-2 no se ven.
	"windmill": [2, 3, 4],
	"silo": [2, 4, 5],
	"tavern": [1, 2, 3],
	"carpentry": [1, 2, 2],
	"well": [3, 5, 6],
	"lighthouse": [1, 1, 1],
	"fuel_depot": [2, 2, 3],
	# Aire y mar: sin tope desde 2026-10-18 (ver building_limits).
}

## El tope de `building_id` AHORA: la era en curso (ProgressionManager), mas los
## huecos del rango. -1 = sin tope. Es el unico sitio que deben leer las reglas
## de colocar, CONSTRUIR, ¿QUE HACER? y el tutorial. Nada de esto se guarda: sale
## de la era y del rango, que ya van en el save.
func get_building_limit(building_id: String) -> int:
	return get_building_limit_for_era(building_id, current_era())

## El tope de `building_id` en la era `era` (1..3, se acota), con el rango encima.
## Sandbox: -1 siempre (docs/20). Decoraciones: -1 siempre (las limita el terreno).
func get_building_limit_for_era(building_id: String, era: int) -> int:
	if GameMode.all_unlocked():
		return -1  # Sandbox: sin tope por tipo (ver docs/20-modos-de-juego.md).
	if is_uncapped_building(building_id):
		return -1
	var limit := base_building_limit(building_id, era)
	if limit < 0:
		return limit
	# Huecos extra que da el rango del gobernador (RankManager los asigna).
	return limit + int(rank_limit_bonus.get(building_id, 0))

## El tope de la tabla en `era`, sin rango ni modo. -1 = sin tope.
func base_building_limit(building_id: String, era: int) -> int:
	if building_limits_by_era.has(building_id):
		var row: Array = building_limits_by_era[building_id]
		if not row.is_empty():
			return int(row[clampi(era, 1, row.size()) - 1])
	return int(building_limits.get(building_id, -1))

## La proxima era en la que sube el tope de `building_id` y a cuanto (con el
## rango), o {} si ya no sube. Para "3/6 · era 2: 9" en CONSTRUIR.
func next_building_limit(building_id: String) -> Dictionary:
	var era := current_era()
	var now := get_building_limit_for_era(building_id, era)
	if now < 0:
		return {}
	for e in range(era + 1, max_era() + 1):
		var later := get_building_limit_for_era(building_id, e)
		if later > now:
			return {"era": e, "limit": later}
	return {}

## La era en curso, o 1 sin ProgressionManager (pruebas sin arbol, arranque).
func current_era() -> int:
	var pm := get_node_or_null("/root/ProgressionManager")
	return int(pm.get("current_era")) if pm != null else 1

func max_era() -> int:
	return base_storage_cap_by_era.size()

## Sin tope por tipo: las decoraciones (BuildingData.is_decoration, carreteras
## incluidas). Se mira el .tres y no una lista, para que una decoracion nueva no
## necesite entrada en ninguna tabla. Se recuerda por id.
var _uncapped_cache: Dictionary = {}
func is_uncapped_building(building_id: String) -> bool:
	if _uncapped_cache.has(building_id):
		return bool(_uncapped_cache[building_id])
	var path := "res://data/buildings/%s.tres" % building_id
	var data: BuildingData = null
	if ResourceLoader.exists(path):
		data = load(path) as BuildingData
	var uncapped := data != null and data.is_decoration
	_uncapped_cache[building_id] = uncapped
	return uncapped

func get_prerequisites(building_id: String) -> Array:
	if GameMode.all_unlocked():
		return []
	return building_prerequisites.get(building_id, [])

# ══════════════════════════════════════════════════════════════════════
# ── Army / Units (management → combat bridge) ──
# ══════════════════════════════════════════════════════════════════════
# Units are trained at Barracks, cost resources + time, consume gold upkeep,
# and contribute to Military Power. Combat (planned) will consume this army.

## Unit definitions. `era` gates availability; `power` feeds the Military Power
## score; `upkeep_gold` is deducted per upkeep tick; `train_time` in seconds.
var unit_types := {
	"infantry": {
		"name": "UNIT_INFANTRY",
		"tier": 1,
		"era": 1,
		"cost": {"gold": 40, "wood": 20},
		"train_time": 20.0,
		"upkeep_gold": 1,
		"power": 10,
	},
	"artillery": {
		"name": "UNIT_ARTILLERY",
		"tier": 2,
		"era": 2,
		# 2026-10-12: 120/50 y 45 s (antes 80/30 y 35 s). La guarnicion de la era 2
		# pesa algo mas (docs/22 §11).
		"cost": {"gold": 120, "steel": 50},
		"train_time": 45.0,
		"upkeep_gold": 2,
		"power": 28,
	},
	"vehicle": {
		"name": "UNIT_VEHICLE",
		"tier": 3,
		"era": 3,
		# 2026-10-12: 400/180/90 y 100 s (antes 140/60/30 y 55 s). Los seis
		# blindados del asedio son el ultimo gran esfuerzo de la era 3, no un tramite.
		# 2026-10-16: 300/130/60 + 8 vigas. Lo mismo en recursos (las 8 vigas son
		# 40 de acero y 20 de madera en la Fundicion), pero la espera de 400 de oro
		# se parte en dos decisiones: fabricar vigas y entrenar (docs/22 §11).
		"cost": {"gold": 300, "steel": 130, "oil": 60, "beams": 8},
		"train_time": 100.0,
		"upkeep_gold": 4,
		"power": 65,
	},
	# ── Aire y mar (feat/aire-mar-reglas, docs/15 §11) ──
	# `building` = donde se entrena (ArmyManager): barracks / shipyard / aerodrome.
	# Las de tierra no lo llevan escrito: sin clave es "barracks". El dominio de
	# cada una (land / sea / air) esta en combat_unit_stats, no aqui.
	# Los barcos salen del Astillero (era 2, junto al agua); los aviones y el
	# dirigible, del Aerodromo (era 3). Los precios estan a la altura de la
	# artilleria y del tanque: un barco de era 2 cuesta como un canon, el
	# Acorazado y los aviones como un tanque (sin medir con line_probe, docs/22).
	"torpedo_boat": {
		"name": "UNIT_TORPEDO_BOAT",
		"tier": 2,
		"era": 2,
		"building": "shipyard",
		"cost": {"gold": 100, "steel": 40, "wood": 40},
		"train_time": 40.0,
		"upkeep_gold": 2,
		"power": 24,
	},
	"gunboat": {
		"name": "UNIT_GUNBOAT",
		"tier": 2,
		"era": 2,
		"building": "shipyard",
		"cost": {"gold": 130, "steel": 60, "planks": 6},
		"train_time": 50.0,
		"upkeep_gold": 2,
		"power": 30,
	},
	"dreadnought": {
		"name": "UNIT_DREADNOUGHT",
		"tier": 3,
		"era": 3,
		"building": "shipyard",
		"cost": {"gold": 320, "steel": 160, "oil": 60, "beams": 10},
		"train_time": 110.0,
		"upkeep_gold": 5,
		"power": 75,
	},
	"fighter": {
		"name": "UNIT_FIGHTER",
		"tier": 3,
		"era": 3,
		"building": "aerodrome",
		"cost": {"gold": 200, "steel": 60, "fuel": 6},
		"train_time": 60.0,
		"upkeep_gold": 3,
		"power": 40,
	},
	"bomber": {
		"name": "UNIT_BOMBER",
		"tier": 3,
		"era": 3,
		"building": "aerodrome",
		# 1.1, reequilibrio (docs/16 "Aire y mar"): 300 de oro (antes 260). Con ataque
		# 18 ganaba el 100 % de las misiones de costa con 0,3 bajas.
		"cost": {"gold": 300, "steel": 90, "oil": 40, "fuel": 8},
		"train_time": 80.0,
		"upkeep_gold": 4,
		"power": 50,
	},
	"airship": {
		"name": "UNIT_AIRSHIP",
		"tier": 3,
		"era": 3,
		"building": "aerodrome",
		"cost": {"gold": 280, "steel": 60, "oil": 60, "fuel": 10},
		"train_time": 90.0,
		"upkeep_gold": 4,
		"power": 55,
	},
}

## Los tres edificios que entrenan tropa, en el orden en que la ensena el panel
## del ejercito (Tierra, Mar, Aire). Cada uno abre un hueco de entrenamiento por
## edificio, solo para SUS unidades (unit_types[...]["building"]).
const MILITARY_BUILDINGS := ["barracks", "shipyard", "aerodrome"]
## El dominio que entrena cada edificio militar (para agrupar el panel).
const MILITARY_BUILDING_DOMAIN := {"barracks": "land", "shipyard": "sea", "aerodrome": "air"}

## Army capacity: you may hold a few units even with no barracks; each barracks
## raises the ceiling. Bigger base = larger, stronger army.
##
## El Cuartel no tiene tope de edificios (Bryan, 18-10-2026), asi que el freno
## esta aqui, con los valores de antes como techo (con el tope 3/4/5 lo maximo
## eran 5 cuarteles: 3 + 8x5 = 43 plazas y 5 a la vez):
##   - los `army_full_capacity_barracks` primeros cuarteles dan +8 plazas cada
##     uno; los siguientes, +4 (`army_capacity_per_extra_barracks`);
##   - la tropa no pasa de `army_capacity_max` (43: se llega con 7 cuarteles);
##   - no se entrenan mas de `army_training_slots_max` (5) unidades a la vez.
## Un cuartel de mas sigue sirviendo (otro sitio que la Tormenta puede golpear,
## mas defensas repartidas, un repuesto si uno cae en ruinas), pero no infla el
## ejercito sin freno. Y el sueldo en oro de cada unidad sigue siendo el freno
## de fondo.
var army_base_capacity := 3
var army_capacity_per_barracks := 8
var army_full_capacity_barracks := 3
var army_capacity_per_extra_barracks := 4
var army_capacity_max := 43
var army_training_slots_max := 5
## Aire y mar (2026-10-17; sin tope de edificios desde 2026-10-18, integracion
## con fix/bandera-y-topes-militares). El MISMO criterio que el Cuartel: los
## `army_full_capacity_buildings` primeros dan sus plazas enteras
## (`army_capacity_per_building`), los siguientes `army_capacity_per_extra_building`,
## y lo de cada edificio no pasa de `army_capacity_max_by_building`. El Cuartel
## lee sus cifras de las variables de arriba (army_*_barracks, army_capacity_max
## menos la base), para que quien lo afine no toque dos sitios. Con los topes de
## antes (1/1/2) lo maximo eran 2 de cada: +8 por medio; ahora el techo es +12
## (4 de cada), y el ejercito entero no pasa de `army_capacity_max_total`
## (43 + 12 + 12 = 67).
var army_capacity_per_building := {"barracks": 8, "shipyard": 4, "aerodrome": 4}
var army_full_capacity_buildings := {"shipyard": 2, "aerodrome": 2}
var army_capacity_per_extra_building := {"shipyard": 2, "aerodrome": 2}
var army_capacity_max_by_building := {"shipyard": 12, "aerodrome": 12}
var army_capacity_max_total := 67
## Huecos de entrenamiento a la vez por tipo de edificio (uno por edificio hasta
## esto). El Cuartel, `army_training_slots_max`.
var army_training_slots_max_by_building := {"shipyard": 2, "aerodrome": 2}
## Seconds between upkeep deductions (scaled by dev_mode like other durations).
## 90 s desde la ronda final de la 1.1 (antes 30): el sueldo a un tercio. La
## sonda de la linea veia el oro a 0 en casi cada Tormenta de la era 3 y 10-45
## deserciones por partida; con 60 s quedaban 3-18, con 90 s 0-9 (docs/22 §15).
## El `upkeep_gold` de cada unidad no cambia: es lo que cobra cada nomina.
var army_upkeep_interval := 90.0

func get_unit_def(unit_id: String) -> Dictionary:
	return unit_types.get(unit_id, {})

func get_unit_ids() -> Array:
	return unit_types.keys()

func get_army_capacity(barracks_count: int) -> int:
	var n := maxi(0, barracks_count)
	var full := mini(n, army_full_capacity_barracks)
	var extra := n - full
	var cap := army_base_capacity + army_capacity_per_barracks * full 		+ army_capacity_per_extra_barracks * extra
	return mini(cap, army_capacity_max)

## Cuantas plazas suma el proximo cuartel a partir de `barracks_count` (0 si ya
## se esta en el techo). Para "+8 soldados" de la guia y el panel.
func army_capacity_gain(barracks_count: int) -> int:
	return get_army_capacity(barracks_count + 1) - get_army_capacity(barracks_count)

## Huecos de entrenamiento a la vez: uno por cuartel, hasta el techo.
func get_army_training_slots(barracks_count: int) -> int:
	return clampi(barracks_count, 0, army_training_slots_max)

## La capacidad con todos los edificios militares: `counts` = id -> cuantos hay
## (barracks / shipyard / aerodrome). LA funcion de la capacidad: el Cuartel por
## get_army_capacity() (base incluida) y cada flota por army_building_capacity(),
## con el techo global encima.
func get_army_capacity_for(counts: Dictionary) -> int:
	var total: int = get_army_capacity(int(counts.get("barracks", 0)))
	for building_id in counts:
		if String(building_id) == "barracks":
			continue
		total += army_building_capacity(String(building_id), int(counts[building_id]))
	return mini(total, army_capacity_max_total)

## Plazas que dan `count` edificios `building_id` que no son el Cuartel (sin la
## base): enteras los primeros, menos los siguientes, con su techo.
func army_building_capacity(building_id: String, count: int) -> int:
	var n := maxi(0, count)
	var full := mini(n, int(army_full_capacity_buildings.get(building_id, n)))
	var cap := int(army_capacity_per_building.get(building_id, 0)) * full 		+ int(army_capacity_per_extra_building.get(building_id, 0)) * (n - full)
	var top := int(army_capacity_max_by_building.get(building_id, -1))
	return cap if top < 0 else mini(cap, top)

## Huecos de entrenamiento de `count` edificios `building_id`: uno por edificio
## hasta el techo de su tipo.
func get_training_slots_for(building_id: String, count: int) -> int:
	if building_id == "barracks":
		return get_army_training_slots(count)
	var top := int(army_training_slots_max_by_building.get(building_id, -1))
	return maxi(0, count) if top < 0 else clampi(count, 0, top)

## Donde se entrena `unit_id`: "barracks" si su fila no dice otra cosa.
func get_unit_building(unit_id: String) -> String:
	return String(get_unit_def(unit_id).get("building", "barracks"))

## El dominio de `unit_id` (land / sea / air), de combat_unit_stats.
func get_unit_domain(unit_id: String) -> String:
	return String(get_combat_stats(unit_id).get("domain", "land"))

## Las unidades de un dominio, en el orden de unit_types.
func get_unit_ids_in_domain(domain: String) -> Array:
	var out: Array = []
	for unit_id in unit_types:
		if get_unit_domain(String(unit_id)) == domain:
			out.append(String(unit_id))
	return out

func get_army_upkeep_interval() -> float:
	return get_duration(army_upkeep_interval)

# ══════════════════════════════════════════════════════════════════════
# ── Combat (PVE expeditions) ──
# ══════════════════════════════════════════════════════════════════════
# The army trained above is spent here. Kept deliberately small: an 8x8 board
# with up to 6 units per side stays readable on a phone and resolves in minutes.

## Board and party limits.
var combat_board_size := Vector2i(8, 8)
var combat_deploy_cap := 6
## Rounds before the encounter is force-resolved by total HP (FR-015).
var combat_turn_limit := 20
## Seconds between enemy AI actions, so the player can follow what happened.
var combat_ai_step_delay := 0.45

## La IA del combate (CombatAI, docs/15 §8 "La IA", 1.1). Los dos bandos y
## AutoResolver la usan igual.
## Valor de un golpe = (parte de la vida del rival que se lleva) x (amenaza del
## rival para los nuestros) ^ `combat_ai_threat_weight`. 0 = solo la parte de la
## vida (el dano relativo, con la ventaja por tipo dentro); 1 = la amenaza pesa
## tanto como el dano.
var combat_ai_threat_weight := 1.0

## Per-unit combat stats, parallel to `unit_types`. `min_range` keeps artillery
## from firing at adjacent targets, which is what makes positioning matter.
##
## Los HP son lo unico que fija la DURACION de un encuentro: el dano es
## `atk - def` y no lleva dados, asi que las rondas salen de dividir vida entre
## golpe. Con los 30/22/60 originales un encuentro se resolvia en 3-5 rondas,
## poco mas de un minuto de reloj; x3.3 lo deja en 8-12 rondas, que es la
## ventana de 3-5 minutos que pide el diseno. `atk` y `def` no se tocan: son la
## relacion que hace que la artilleria pegue y el vehiculo aguante, y ademas la
## IA de objetivos esta fijada sobre esos numeros en `tests/combat/test_combat_ai.gd`.
## Medido en `tools/balance_probe.gd`; tablas en `docs/16-balance-combate.md`.
##
## `domain` es el medio por el que se mueve la unidad: "land" (tierra) para las
## tres de hoy. Ninguna regla lo lee todavia; existe para que las unidades de
## mar y aire (y, muy a futuro, espacio) entren sin cambiar el formato: el
## modelo puro lo expone (`CombatUnit.domain()`) y la vista 3D coloca la unidad
## segun el (docs/15 §11). Una entrada sin `domain` es de tierra.
var combat_unit_stats := {
	"infantry":  {"hp": 100, "atk": 8,  "def": 2, "move": 3, "range": 1, "min_range": 1, "initiative": 5, "domain": "land"},
	"artillery": {"hp": 75, "atk": 14, "def": 1, "move": 1, "range": 3, "min_range": 2, "initiative": 3, "domain": "land"},
	"vehicle":   {"hp": 200, "atk": 12, "def": 5, "move": 4, "range": 1, "min_range": 1, "initiative": 4, "domain": "land"},
	# ── Aire y mar (feat/aire-mar-reglas, docs/15 §11) ──
	# Mar: solo en casillas de agua o de orilla (combat_domain_moves).
	#   Lancha torpedera: rapida y fragil; sus torpedos rompen al Acorazado.
	#   Canonera: alcance medio, castiga la costa (infanteria) y caza lanchas.
	#   Acorazado: mucha vida, el que mas lejos dispara, lento; no a bocajarro.
	# Aire: vuela sobre todo (tierra, agua y orilla) y comparte casilla con las de
	# superficie (otra capa, ver CombatRules.layer_of).
	#   Caza: el mas rapido; el que derriba bombarderos y dirigibles.
	#   Bombardero: gran dano a tierra y barcos; sus bombas no tocan a otro avion.
	#   Dirigible: mucha vida y lento; apoyo desde arriba a 2 casillas.
	# `targets` corrige combat_domain_targets para esa unidad: dominio -> alcance
	# maximo (0 = no puede, -1 = su alcance normal).
	# 1.1, reequilibrio (docs/16 "Aire y mar"): la lancha ganaba el 5 % (era 2) y el
	# 0 % (era 3) de las misiones de costa: con alcance 1 desde el agua apenas
	# llegaba a nadie y caia de cuatro golpes. Vida 90 -> 120, defensa 1 -> 2,
	# alcance 1 -> 2 (los torpedos corren: alcanza la orilla y la primera fila de
	# tierra desde el agua). El acorazado sigue siendo su presa (x1,5).
	"torpedo_boat": {"hp": 120, "atk": 15, "def": 2, "move": 4, "range": 2, "min_range": 1, "initiative": 6, "domain": "sea"},
	"gunboat":      {"hp": 140, "atk": 12, "def": 3, "move": 3, "range": 3, "min_range": 1, "initiative": 4, "domain": "sea"},
	"dreadnought":  {"hp": 280, "atk": 16, "def": 6, "move": 2, "range": 4, "min_range": 2, "initiative": 2, "domain": "sea"},
	"fighter":      {"hp": 90, "atk": 12, "def": 2, "move": 5, "range": 1, "min_range": 1, "initiative": 7, "domain": "air"},
	# 1.1, reequilibrio: el bombardero arrasaba (100 % en costa, 0,3 bajas). Ataque
	# 18 -> 14 y vida 110 -> 95: sigue rompiendo lo pesado (x1,5) pero un caza o
	# dos infantes lo bajan antes.
	"bomber":       {"hp": 95, "atk": 14, "def": 1, "move": 4, "range": 1, "min_range": 1, "initiative": 3, "domain": "air",
		"targets": {"air": 0}},
	"airship":      {"hp": 260, "atk": 10, "def": 4, "move": 2, "range": 2, "min_range": 1, "initiative": 2, "domain": "air"},
}

## Quien puede pisar que (docs/15 §11). Cada dominio, las casillas en las que se
## planta y por las que pasa: "land" (tierra), "water" (agua), "shore" (orilla,
## de los dos). Un tablero sin terreno es todo tierra, asi que los barcos no
## despliegan en el (Encounter los deja en reserva) y todo lo de antes sigue igual.
var combat_domain_moves := {
	"land": ["land", "shore"],
	"sea": ["water", "shore"],
	"air": ["land", "water", "shore"],
}

## Quien puede pegar a quien (docs/15 §11): atacante (dominio) -> objetivo
## (dominio) -> alcance maximo. -1 = el alcance normal de la unidad; 0 = no
## puede; N = como mucho a N casillas. La fila `targets` de combat_unit_stats
## corrige esto para una unidad concreta (el bombardero no toca aviones).
##   * Tierra y mar al aire, solo a 1 casilla: fusiles y ametralladoras contra
##     lo que pasa por encima. Con el alcance minimo 2, la artilleria (y las
##     dotaciones de torre) NO pueden: no hay artilleria antiaerea, el caza es
##     el antiaereo.
##   * El aire, a todo con su alcance.
##   * Los barcos pegan a tierra con su alcance normal, desde el agua o la
##     orilla (es donde estan siempre).
## Una unidad de otra capa (aire contra superficie) justo encima o debajo esta a
## distancia 1, no 0: se pueden pegar (CombatRules.strike_distance).
var combat_domain_targets := {
	"land": {"land": -1, "sea": -1, "air": 1},
	"sea": {"land": -1, "sea": -1, "air": 1},
	"air": {"land": -1, "sea": -1, "air": -1},
}

## Los combates de costa (aire y mar, docs/15 §11). Un tablero de costa lleva
## `combat_coast_water_columns` columnas de agua en un lado (izquierda o
## derecha, por semilla) y una columna de orilla junto a ellas.
var combat_coast_water_columns := 2
## Desde que era hay salidas de costa (los barcos salen en la era 2).
var combat_coastal_min_era := 2
## La probabilidad de que una incursion de saqueadores sea de costa (piratas).
## Las expediciones al Puerto (SORTIE_DEST_DOCK) lo son siempre.
var combat_coastal_raid_chance := 0.35
## Repuestos de mas que da el ultimo combate de una salida de costa (botin).
var combat_loot_coastal_parts := 1
## Semilla del tablero de costa en casa: el Diezmo y el Ataque Final tienen agua
## solo si en tu guarnicion hay barcos (si no, siguen siendo todo tierra, como
## antes). Fija: la costa de tu isla no se mueve entre una visita y otra.
var combat_home_coast_seed := 7
## Mar abierto de la Campana de Mar (feat/tres-campanas): islotes de roca en las
## filas de en medio (CombatRules.open_sea_terrain). Los barcos los rodean.
var combat_sea_islets := 3

## Ventajas por tipo (piedra-papel-tijera, 2026-10-12, docs/15 §3 "Ventaja por
## tipo"). El circulo de tierra:
##   artilleria > vehiculo : el obus de alto explosivo raja la chapa remachada
##                           que las balas solo rayan;
##   vehiculo > infanteria : el blindado diesel arrolla la linea de fusiles;
##   infanteria > artilleria: la escuadra asalta la pieza a la bayoneta, donde el
##                           canon no puede bajar el tubo (su alcance minimo).
## `beats[a]` = los tipos a los que `a` pega con ventaja. La desventaja no se
## escribe: es el reves (si b esta en beats[a], b pega a "a" con desventaja).
## El multiplicador va sobre el dano neto (atk - def), con suelo de 1, en
## CombatRules.damage(): lo usan igual el jugador, la IA y AutoResolver.
##
## Aire y mar (2026-10-17, docs/15 §11), al estilo de Empires & Allies: un
## circulo dentro de cada medio y unos pocos cruces.
##   Mar:   lancha > acorazado (torpedos al casco grande) > canonera (la
##          supera en canones) > lancha (fuego rapido contra lo pequeno).
##   Aire:  caza > bombardero y caza > dirigible (lo derriba). Al caza le gana
##          la canonera (sus canones antiaereos).
##   Cruces: el bombardero rompe lo pesado (tanque, artilleria, canonera,
##          acorazado); la artilleria de costa gana a la canonera; la canonera
##          barre la infanteria de la playa; el dirigible castiga a la
##          infanteria y a la lancha desde arriba; el acorazado gana al tanque.
## Ninguna pareja va en los dos sentidos (lo comprueba test_air_sea_rules.gd).
var combat_type_advantage := {
	"beats": {
		"artillery": ["vehicle", "gunboat"],
		"vehicle": ["infantry"],
		"infantry": ["artillery"],
		"torpedo_boat": ["dreadnought"],
		"dreadnought": ["gunboat", "vehicle"],
		"gunboat": ["torpedo_boat", "infantry", "fighter"],
		"fighter": ["bomber", "airship"],
		"bomber": ["vehicle", "artillery", "gunboat", "dreadnought"],
		"airship": ["infantry", "torpedo_boat"],
	},
	"advantage": 1.5,
	"disadvantage": 0.75,
}

## Enemy scaling: deeper nodes and later eras field tougher rosters.
##
## Son deliberadamente pequenos. El multiplicador sube los HP **y** el ataque a
## la vez, asi que una escala `s` vale `s²` de poder de combate; y la misma
## presion engorda ademas el roster. El jugador, en cambio, no repone bajas ni
## cura entre nodos: su unico crecimiento son los drafts, que suman +2 a un stat.
## Con los 0.15/0.25/1.8 originales, ninguna expedicion se ganaba jamas — ni con
## seis unidades, ni en ninguna era (0% sobre 3.600 expediciones simuladas, la mitad de ellas bien jugadas).
var combat_enemy_scale_per_depth := 0.02
var combat_enemy_scale_per_era := 0.12
var combat_boss_multiplier := 1.15

## Expedition map shape (min, max).
var combat_map_depth := Vector2i(4, 6)
var combat_map_branching := Vector2i(2, 3)
var combat_draft_options := 3

## Node risk (0 low / 1 medium / 2 high). The same dial pushes the roster up and
## the loot with it, so taking the dangerous road is a bet, not a punishment.
## El lado del enemigo es pequeno por lo mismo que `combat_enemy_scale_per_depth`;
## el del botin no se toca, para que el riesgo siga pagando mas de lo que cuesta.
var combat_risk_enemy_scale := 0.05
var combat_risk_reward_bonus := 0.35

## Enemy roster size at depth 0, era 1, risk 0. Every pressure term grows it from
## here up to `combat_deploy_cap`.
var combat_enemy_base_slots := 2

## What one draft pick is worth. Kept modest on purpose: a run is 6-8 fights, not
## thirty, so a single pick should tilt a fight, never decide the expedition.
##
## `heal_pct` es la excepcion, y con motivo: es la UNICA forma de recuperar vida
## en toda la expedicion, y solo aparece en 3 de las 5 cartas. Al 0.3 original la
## columna llegaba al jefe con el deposito por debajo del 20%; al 0.5, un cuatro
## de era 1 bien jugado gana el 56% de las veces contra el 29% de antes. Cura a
## todos los vivos, asi que lo que sobra de un herido leve se pierde.
var combat_draft_values := {
	"atk": 2,
	"def": 2,
	"move": 1,
	"initiative": 2,
	"heal_pct": 0.5,
}
## A draft aimed at one unit type instead of the whole party hits harder, because
## it helps fewer units.
var combat_draft_focus_multiplier := 2

## Base reward per cleared encounter, scaled by node depth and risk.
var combat_reward_base := {"gold": 60, "wood": 30}

## La primera escaramuza de la partida (docs/15-combat.md §4). La pide el paso de
## ¿QUE HACER? en cuanto sale del cuartel la primera unidad, y no es una
## expedicion entera: es un solo nodo, sin mapa ni jefe, contra un enemigo debil.
## Con la expedicion normal la columna de un infante recien entrenado se estrella
## en el nodo 0 (dos infantes enteros) y nunca llega al jefe; esta se gana con un
## solo infante a cualquier moral (medido en tests/combat/test_first_sortie.gd).
## El botin es el doble largo del nodo 0 normal: tiene que notarse en la bolsa de
## la era 1 (600) y pagar de sobra el infante que costo (40 oro + 20 madera).
var combat_first_sortie_roster := {"infantry": 1}
## Multiplicador de HP y ataque del enemigo, en vez del de profundidad/era/riesgo.
## 0.6: un infante de 60 HP que pega 5 (3 de dano contra la defensa 2).
var combat_first_sortie_enemy_scale := 0.6
var combat_first_sortie_rewards := {"gold": 150, "wood": 100}

## Morale is the bridge between base and battlefield: a demoralised population
## reacts late and hits softer, and casualties cost morale back home.
##
## El rango de ataque es ancho a proposito. Es el unico modificador que solo
## tiene el jugador — el enemigo pelea siempre a 1.0 —, asi que es la palanca que
## permite que una columna pequena gane un nodo sin dejarse a nadie. Con el
## (0.85, 1.15) de antes, la moral de salida (75) daba un x1.075 que el redondeo
## se comia entero (8 x 1.075 = 8.6 -> 9, el mismo 9 que sin moral); con
## (0.60, 1.40) da x1.20, la infanteria pega 10 en vez de 9, y el mismo cuatro de
## era 1 pasa del 11% al 56% de expediciones ganadas. El rango sigue siendo
## **simetrico alrededor de 1.0**, que es la regla que fija
## `tests/combat/test_combat_rules.gd`: moral 50 no suma ni resta. El precio de
## la otra mitad es real: salir con la moral por los suelos es salir a perder,
## que es justo lo que la moral deberia significar.
var combat_morale_initiative_bonus := 2
var combat_morale_attack_range := Vector2(0.60, 1.40)
var combat_morale_on_victory := 8.0
## Defender la base (Diezmo / Impuesto; NO el Ataque Final): de las unidades del
## ejercito que caen, esta parte vuelve herida en vez de morir (redondeando a
## favor de las que vuelven; siempre cae al menos una). Decision de Bryan en la
## ronda final de la 1.1: la sonda de la linea veia la guarnicion entera caer en
## cada Diezmo de la era 3 y la columna de las campanas reponiendose sin fin
## (docs/22 §14). Hook de la Enfermeria (1.2): CombatManager.defense_wounded().
var combat_defense_return_share := 2.0 / 3.0
var combat_morale_per_casualty := 3.0

# ── Salidas: incursiones, expediciones cortas y botin exclusivo (doc 21 §3) ──
# 2026-10-14, rama feat/escaramuzas. Todo en claves NUEVAS: los combat_map_* y
# combat_reward_base de siempre siguen valiendo para la expedicion antigua (las
# partidas guardadas a medias, los tests y las sondas que lanzan con semilla).

## Cada cuanto se revisa el tablon de salidas (segundos reales). Barato: mira
## dos relojes y, si toca, sortea una oferta.
var combat_sortie_refresh_interval := 2.0
## Segundos de juego entre terminar una incursion (o una expedicion) y que
## aparezca la siguiente. Pasan por get_duration() (dev_mode los acorta). Una
## calma dura 360-600 s: hay una incursion por calma, mas o menos.
var combat_raid_cooldown := 240.0
var combat_expedition_cooldown := 480.0
## La expedicion de 3 combates aparece desde esta era (la incursion, con el
## primer Cuartel y la primera escaramuza ganada).
var combat_expedition_min_era := 2
## La incursion es un solo combate, un poco mas duro que la apertura de una
## expedicion (profundidad 1 en la curva de enemy_pressure).
var combat_raid_depth := 1
## Expedicion corta (D3 = A): apertura -> elegir 1 de 2 -> jefe = 3 combates.
## Mismo generador que la de siempre, con otros rangos.
var combat_expedition_depth := Vector2i(1, 1)
var combat_expedition_branching := Vector2i(2, 2)
## El jefe de la expedicion corta lleva esta infanteria de escolta menos.
var combat_expedition_boss_escort_cut := 1
## Vida que recupera la columna al pasar al siguiente combate de una expedicion
## corta (fraccion de la vida maxima de cada superviviente). La antigua no cura.
var combat_expedition_heal_between := 0.30
## El oro y la madera de las salidas nuevas: la mitad de la curva de siempre. Lo
## que de verdad paga una salida es el botin exclusivo de abajo.
var combat_sortie_reward_mult := 0.5

## Botin exclusivo (D2 = A). Repuestos: material nuevo, fuera de la bolsa.
## Colonos: habitantes al momento (hasta llenar las casas). Rebaja del Diezmo:
## un % menos en el proximo Diezmo (avanzadilla). Planos: abren edificios.
## Incursion de saqueadores: repuestos y colonos (rango min-max, sorteado al
## aparecer y visible antes de salir).
var combat_loot_raid_parts := Vector2i(1, 2)
var combat_loot_raid_colonists := Vector2i(2, 4)
## Incursion contra la avanzadilla de la Regencia (solo con la Tormenta armada y
## Diezmo en el modo): repuestos y una rebaja del proximo Diezmo. Se va con el
## Diezmo. La rebaja la aplica StormManager.add_tithe_discount() (rama
## feat/orden-regencia, doc 21 §2.2) con su storm_order_expedition_pct si existe;
## si no, con esta fraccion. Sin esa funcion (base sin la Orden) no rebaja nada:
## solo se anota y se ensena.
var combat_loot_outpost_parts := Vector2i(1, 1)
var combat_loot_outpost_tithe_pct := 0.10

## La rebaja del Diezmo que da echar la avanzadilla: la de la Orden de la
## Regencia si esa rama esta (storm_order_expedition_pct), si no la nuestra.
func sortie_tithe_discount_pct() -> float:
	if "storm_order_expedition_pct" in self:
		return float(get("storm_order_expedition_pct"))
	return combat_loot_outpost_tithe_pct
## Expedicion: repuestos por cada combate de paso; el jefe da mas, colonos y,
## si queda alguno por conseguir, un plano.
var combat_loot_expedition_node_parts := 2
var combat_loot_expedition_boss_parts := 4
var combat_loot_expedition_boss_colonists := 3

## Planos: edificios que solo se construyen con su plano (doc 21 §6.3). La lista
## puede empezar corta: un id solo se ofrece como botin cuando su
## data/buildings/<id>.tres existe, asi que las ramas que traigan esos edificios
## los activan sin tocar nada aqui. El candado lo pone quien construye
## (CombatManager.blueprint_locked(); PlacementRules tiene que llamarlo, como
## check_rank()).
var combat_blueprint_buildings := ["infirmary", "military_forge", "scrapyard", "diesel_plant"]

# ── Tres campañas: Tierra, Mar y Aire (feat/tres-campanas, docs/15 §13) ──
# Decision de Bryan (2026-10-18): tres cadenas de misiones APARTE, cada una de
# un solo medio (en la de mar solo barcos y sobre agua; en la de aire solo
# aviones), con un jefe al final. El Ataque Final pide las tres + el Cuartel
# General a nivel 3. Sin medir con la sonda (ronda final).

## Interruptor de las misiones MIXTAS (tierra y barcos en el mismo tablero: las
## incursiones de piratas y la expedicion al Puerto). Son "futuro": apagadas, su
## codigo sigue entero (ExpeditionGenerator.offer_is_coastal). Los tests que las
## fijan lo encienden a mano.
var combat_mixed_missions_enabled := false
## La expedicion corta de tres combates del tablon pasa a ser la Campana de
## Tierra: apagada, el tablon solo ofrece ataques rapidos (incursiones). Su
## codigo sigue entero; los tests que la fijan la encienden.
var combat_board_expeditions_enabled := false
## El Ataque Final pide las tres campanas ademas del Cuartel General a nivel 3
## (en los modos cuya regla `audit_needs_campaigns` lo diga). Apagado = como en
## la 1.0: el CG nivel 3 lo convoca solo (tests antiguos que lo fijan).
var final_audit_needs_campaigns := true

## Las tres campanas, en el orden en que se ensenan. `building`: el edificio que
## la abre (sin el, candado). `eras`: la era minima de cada mision; la ultima es
## la del JEFE (la longitud es el numero de misiones, jefe incluido). `fights`:
## combates de cada mision (el ultimo del mapa es su jefe de mision; en la del
## jefe de campana, el jefe). `bonus_res`: el recurso de mas que paga cada mision
## ganada (la de tierra, ninguno: paga colonos).
## Tierra: 5 + jefe; Mar: 4 + jefe; Aire: 4 + jefe = 16 misiones, 30 combates.
var campaign_defs := {
	"land": {
		"building": "barracks",
		"eras": [1, 1, 2, 2, 2, 3],
		"fights": [1, 1, 2, 2, 2, 3],
		"bonus_res": "",
	},
	"sea": {
		"building": "shipyard",
		"eras": [2, 2, 2, 3, 3],
		"fights": [1, 2, 2, 2, 3],
		"bonus_res": "steel",
	},
	"air": {
		"building": "aerodrome",
		"eras": [3, 3, 3, 3, 3],
		"fights": [1, 2, 2, 2, 3],
		"bonus_res": "oil",
	},
}
## El orden de las pestanas (y el que sigue ¿QUE HACER?).
const CAMPAIGN_DOMAINS := ["land", "sea", "air"]
## Cuanto pesa cada mision en la curva enemiga (enemy_pressure): mision N es
## como un nodo de profundidad N * esto, mas su propia profundidad dentro del mapa.
var campaign_level_step := 2
## Escala de los enemigos de cada mision de campana sobre la curva de siempre,
## una cifra por mision (la del jefe de campana, para sus combates de paso; el
## jefe lleva la suya abajo). Calibrada en la ronda final de la 1.1 con
## `tools/balance_probe.gd -- --only=campaigns --camp-calib=1` (docs/15 §13
## "Medido"): las misiones traen 2-3 cuerpos por combate (la curva de las
## expediciones) contra columnas de 6 y sin esto salian al 100 %; los jefes, con
## dos pesados y x1,10, al 0 %.
##   * La primera de cada campana es la de entrada: gana cualquier columna digna
##     (tierra, 3 infantes; la segunda ya pide 4). Subirla hasta disputarla
##     pide enemigos a x2, monstruos por unidad: no se hace.
##   * Las de en medio: la columna bien formada de su era gana el 60-100 %, la
##     floja (4 infantes, 4 lanchas, 3 cazas) no.
## El combate no tira dados: cada fila es un escalon, y entre dos cifras de la
## calibracion la tasa salta. Retocar de 0,02 en 0,02.
var campaign_enemy_mult := {
	"land": [1.5, 1.7, 1.30, 1.31, 1.15, 0.93],
	"sea": [1.6, 1.30, 1.25, 1.17, 0.90],
	"air": [1.4, 1.03, 1.02, 0.97, 0.78],
}
## El jefe de campana: la escala de jefe de siempre (combat_boss_multiplier) por
## esto, por medio. Antes 1,10 para todos (0 % de victorias); ahora la columna
## bien formada gana el 45-75 % (tierra 2+2+2, mar con acorazados, aire 6 cazas).
var campaign_boss_extra_scale := {"land": 0.93, "sea": 0.90, "air": 0.78}
## Cuantas unidades de su clase pesada lleva el jefe de campana ademas de su
## escolta, por medio (antes 2: el jefe era casi solo pesados y no se ganaba).
var campaign_boss_heavies := {"land": 1, "sea": 1, "air": 1}
## El jefe de campana que pide una unidad concreta, y cuantas en casa. El
## Leviatan es el reto de la era 3 (decision de Bryan): con la flota de la era 2
## gana el 0 %, con acorazados el 53-100 % (docs/15 §13 "Medido"). El panel de
## la campana y ¿QUE HACER? lo dicen antes de llegar a el.
var campaign_boss_counter := {"sea": "dreadnought"}
## Cada derrota en la mision que toca le quita al enemigo de esa mision un 5 %
## (escala x0,95 por derrota, nunca por debajo de x0,80); al ganarla se vuelve a
## x1. El mapa no cambia. Sin esto, como el combate no tira dados, una mision
## perdida con una columna se perdia siempre (sonda de la linea, ronda final de
## la 1.1: el Zepelin, 6 derrotas seguidas en la semilla 4).
var campaign_retry_ease := 0.95
var campaign_retry_floor := 0.80
var campaign_boss_counter_count := 2
## Segundos de juego entre ganar una mision y que la siguiente de la MISMA
## campana se pueda lanzar (la tropa descansa). Pasa por get_duration().
var campaign_mission_cooldown := 150.0
## Vida que recupera la columna entre dos combates de una mision.
var campaign_heal_between := 0.30
## Oro y madera: la curva de siempre por esto, todo en el ultimo combate de la
## mision (los de paso no pagan: abandonar y repetir no da botin dos veces).
var campaign_reward_mult := 0.75
## Lo exclusivo de cada mision ganada: repuestos (por medio), colonos (solo
## tierra), rebaja del proximo Impuesto en puntos de %, y el recurso de mas.
var campaign_mission_parts := {"land": 1, "sea": 2, "air": 2}
var campaign_mission_colonists := {"land": 2, "sea": 0, "air": 0}
var campaign_mission_tithe_pct := 5
var campaign_bonus_base := 30
var campaign_bonus_per_mission := 15
## El jefe de campana paga esto (y un plano si queda alguno por conseguir).
var campaign_boss_parts := 5
var campaign_boss_colonists := 4
var campaign_boss_tithe_pct := 15
## Que unidades valen en cada campana: las de su medio que puedan pegar a ese
## medio. El bombardero no toca aviones (combat_domain_targets), asi que en la de
## aire se queda en casa: alli no serviria de nada.
func campaign_unit_allowed(domain: String, unit_id: String) -> bool:
	if get_unit_domain(unit_id) != domain:
		return false
	var stats: Dictionary = get_combat_stats(unit_id)
	var targets: Dictionary = stats.get("targets", {})
	return int(targets.get(domain, -1)) != 0

## Numero de misiones de una campana (jefe incluido).
func campaign_mission_count(domain: String) -> int:
	return (campaign_defs.get(domain, {}).get("eras", []) as Array).size()

## La unidad que ¿QUE HACER? propone entrenar para una campana sin tropa en casa.
var campaign_suggested_unit := {"land": "artillery", "sea": "gunboat", "air": "fighter"}
## Cuantas de su medio pide ¿QUE HACER? antes de proponer la mision.
## 6 desde la ronda final de la 1.1 (antes 3): la columna que gana es la de 6
## (docs/15 §13 "Medido": 3 cazas pierden el 100 % de la mision 1 del Aire, 3
## infantes la 2 de Tierra). Si el tope de tropa no deja, pide lo que quepa.
var campaign_suggested_party := 6

## Repuestos que pide una mejora: nivel -> cantidad, solo para los edificios de
## la lista (los productores). El Cuartel General tiene su propia tabla.
var upgrade_parts_cost := {3: 3}
var upgrade_parts_buildings := ["sawmill", "gold_mine", "foundry", "refinery", "farm"]

## Retirada enemiga (D7 = B): en expediciones e incursiones, cuando a los
## enemigos les queda menos de esta fraccion de la vida con la que empezaron, se
## retiran y el combate se gana. Nunca en el Diezmo ni en el asedio.
var combat_retreat_ratio := 0.30
## "Resolver solo" (D6 = A): solo en incursiones y en el Diezmo, y solo cuando
## tu fuerza es al menos esta vez la del enemigo (CombatRules.side_strength).
var combat_auto_resolve_ratio := 2.0
## La etiqueta de la seleccion de tropa: Favorable desde esta proporcion,
## Dificil por debajo de la otra, Igualada entre medias.
var combat_odds_favorable := 1.25
var combat_odds_hard := 0.85

func get_combat_stats(unit_id: String) -> Dictionary:
	return combat_unit_stats.get(unit_id, {})

func get_combat_ai_step_delay() -> float:
	var base := combat_ai_step_delay if not dev_mode else combat_ai_step_delay * 0.5
	# x2 tambien acelera el turno enemigo (combat_pace).
	return combat_pace(base)

# ══════════════════════════════════════════════════════════════════════
# ── The Imperial Storm ──
# ══════════════════════════════════════════════════════════════════════
# The storm is dispatched, not rolled: it always announces itself and always runs
# the same three phases in the same order. What the dice decide is when the calm
# ends and whether a given warning amounts to anything — never how hard it hits.
# A disaster nobody can prepare for is noise; one that always means the same
# thing is arithmetic.

## How long the calm lasts. A range, not a metronome: a storm you can set your
## watch by stops being weather and becomes a spreadsheet column.
##
## Linea jugable (docs/22-linea-jugable.md): con 240-420 s la Tormenta volvia cada
## 7-10 minutos, 35-45 tormentas en una partida, y cada Diezmo es un tablero de
## 4-7 minutos: el jugador pasaba casi la mitad del tiempo peleando la misma
## pelea. Con 360-600 s son 9-18 tormentas hasta la victoria.
var storm_interval_min := 360.0
var storm_interval_max := 600.0

## The three phases are always exactly this long, in this order: Warning, Ash,
## Storm. The arrival is uncertain; what happens once it starts never is. That
## asymmetry is what makes the Warning worth acting on.
var storm_warning := 45.0
var storm_ash_duration := 60.0
var storm_duration := 60.0

## En que fase de la colonia se arma el reloj de la Tormenta. Hasta ella no
## existe: la colonia todavia no sale en el libro.
##
## EXPANSION = la primera Fundicion (era 2). Es el Acto II del diseno ("llega la
## primera Tormenta"): las chimeneas de la Fundicion son lo que se ve desde el
## mar. Armada con el primer Aserradero (antes), la primera tormenta caia en el
## minuto ~9 de una colonia que no puede tener Cuartel hasta la era 2, y el
## Diezmo se cobraba en obreros sin que el jugador hubiera podido hacer nada.
var storm_arm_phase: int = Phase.EXPANSION

## The first storm is deliberately late and gentle: it has to teach the cycle,
## not end the run. Diez minutos desde la Fundicion: lo justo para levantar el
## Cuartel y la guarnicion que la pelea. Nunca menor que storm_interval_max.
var storm_first_interval := 600.0
var storm_first_severity := 1

## La tormenta de prueba de la era 1 (decision de Bryan, 2026-10-04). Sin ella la
## era 1 eran 8-10 minutos sin otra presion que el consumo, y la primera Tormenta
## llegaba de nuevas con los Tasadores detras. Esta es un ensayo: Aviso, Ceniza,
## Tormenta y calma, con los consejos del Aviso, pero sin el Diezmo de verdad (solo
## el Impuesto de juguete, storm_trial_tithe_*), sin romper
## edificios ni la cola y con un mordisco de moral pequeno. Una vez por partida, y
## no arma el reloj de verdad (ese sigue llegando con la Fundicion).
##
## `storm_trial_at` son segundos de partida jugados (ProgressionManager), no de
## reloj de pared; pasan por get_duration(), asi que dev_mode los comprime. Si la
## Fundicion llega antes, la prueba ya no hace falta y no sale.
var storm_trial_at := 300.0
## Y nunca en medio del tutorial guiado: espera a que acabe y llega, como pronto,
## estos segundos de partida despues (2026-10-19, StormManager.trial_due_at).
var storm_trial_after_guide := 90.0

## La primera de estas obras sale con rebaja (id -> factor del precio), para que
## el tutorial no la pida cuando el oro esta en el suelo: la Mina de oro llega
## detras del Cuartel temprano y a 120 oro + 80 madera tardaba (queja de Bryan,
## 2026-10-19). Las siguientes, al precio de la ficha. BuildingData.get_cost.
var first_building_discount := {"gold_mine": 0.5}
var storm_trial_severity := 1
## Lo que deja producir durante su Ceniza y su Tormenta: bastante mas que una de
## verdad (0,5 y 0,15). Se nota, no hunde.
var storm_trial_production_multiplier := 0.75
## Fraccion del mordisco de moral de una tormenta normal. Con 0,25 una de
## severidad 1 se lleva 3 puntos en vez de 12.
var storm_trial_morale_factor := 0.25

## El Impuesto de juguete de la tormenta de prueba (2026-10-17, feat/cuartel-temprano).
## Al escampar bajan unos Cobradores de prueba: si hay tropas en casa, pelean en el
## tablero (el combate guiado, si aun no se dio); si no, se llevan un poco de la
## bolsa. Nunca edificios ni trabajadores, nunca dano. Asi el Cuartel temprano se
## entiende antes de que llegue la Tormenta de verdad.
##   force_max   cobradores, como mucho (uno por soldado en casa, de 1 a este tope)
##   unit        de que son los cobradores
##   enemy_scale lo debiles que vienen (vida y ataque), sobre 1,0
##   pct / cap   sin defensa: esta parte de lo guardado, y nunca mas de `cap`
var storm_trial_tithe_force_max := 2
var storm_trial_tithe_unit := "infantry"
var storm_trial_tithe_enemy_scale := 0.6
var storm_trial_tithe_pct := 0.10
var storm_trial_tithe_cap := 40

func get_storm_trial_at() -> float:
	return get_duration(storm_trial_at)

## Lo que se llevan los Cobradores de prueba con `stored` en la bolsa: una parte
## pequena y con tope. Pura, para las pruebas.
func get_trial_tithe_debt(stored: int) -> int:
	var share: int = int(float(maxi(0, stored)) * storm_trial_tithe_pct)
	return clampi(share, 0, maxi(0, storm_trial_tithe_cap))

## One Warning in four turns out to be nothing. The player still paid to prepare,
## and the Regency loses nothing by crying wolf — which is the point.
var storm_false_alarm_chance := 0.25
## What a false alarm costs: the assessment is deferred, not forgiven. This much
## severity is saved up and rides along with the next real storm.
var storm_false_alarm_carry := 1

## Production multiplier per biting phase. The Warning does not touch production
## at all — it is the one clean window in which to decide. Neither is zero:
## watching the factories crawl is worse than watching them stop.
var storm_ash_production_multiplier := 0.5
var storm_production_multiplier := 0.15
## Live, temporary multiplier applied on top of everything else in
## ProductionManager. 1.0 means nothing is happening. Only the STORM writes to
## it, and it is responsible for putting it back.
var event_production_multiplier := 1.0
## El mismo papel para los eventos aleatorios (la plaga). Es otra variable a
## proposito: si la plaga y la tormenta escribieran la misma, la que acabara
## primero borraria el castigo de la otra. Solo RandomEventManager la toca.
var random_event_production_multiplier := 1.0
## Lo que la plaga deja producir mientras dura: la mitad.
var plague_production_multiplier := 0.5

## Todo lo pasajero junto: tormenta por evento aleatorio. Se multiplican, nunca se
## pisan. ProductionManager lee esto y no las variables sueltas.
func get_event_production_multiplier() -> float:
	return event_production_multiplier * random_event_production_multiplier
## Morale lost per tick of ash, and how often those ticks land. The Warning
## costs none of it.
##
## Por punto de severidad, con decimales (StormManager lleva la cuenta). Una
## tormenta tiene 12 tics de ceniza y 12 de tormenta (x3): se lleva 12 puntos de
## moral por punto de severidad. Severidad 1 = -12 (se nota y se recupera en dos
## minutos), 3 = -36, 5 = -60 (muerde: hacen falta decoraciones o moral alta de
## entrada). Con el 2,0 de antes una tormenta de severidad 1 se llevaba 96 puntos
## y la moral vivia en 0 a partir de la segunda.
var storm_morale_per_tick := 0.25
## The Storm bleeds this much harder than the Ash. Same clock, three times the
## bill — the difference between the two phases has to be felt, not read.
var storm_morale_storm_multiplier := 3.0
var storm_tick_interval := 5.0

## Severity climbs with the era and with how much smoke you make. The Regency does
## not spend a storm on a province that does not show up in the ledger.
var storm_severity_max := 5
var storm_severity_per_era := 1
## One extra step of severity per this many producing buildings.
var storm_buildings_per_severity := 6

## Daño por tic de tormenta, como fracción de la salud máxima del edificio. Se
## multiplica por la severidad: una tormenta fuerte deja la base en ruinas.
##
## 0,03 y no 0,06: son 24 mordiscos por tormenta y van primero a torres y
## cuarteles. A 0,06 una severidad 3 ya arruinaba las dos torres ANTES del Diezmo,
## asi que sus dotaciones no llegaban nunca al tablero que venian a defender (la
## sonda: 1-3 Diezmos echados de ~40 por partida, con guarnicion de cinco). A
## 0,03 una severidad 5 deja las torres
## tocadas (~15% de vida con dos en pie) y sin torres las arruina.
var storm_damage_per_tick := 0.03
## Cuántos edificios muerde cada tic. No los toca todos: la tormenta se siente
## caprichosa, y eso hace que proteger los importantes signifique algo.
var storm_buildings_hit_per_tick := 2

## Las torres, por fin, sirven: cada una en pie reduce el daño de la tormenta.
## Es la palanca de preparación principal y la razón de que existan.
var storm_tower_mitigation := 0.15
var storm_tower_mitigation_max := 0.6

## Reparar cuesta esta fracción del coste de construcción, escalada por el daño
## recibido. Reparar un rasguño es barato; levantar una ruina, casi construirla.
var storm_repair_cost_ratio := 0.5

## ── A quién muerde primero ──
## El daño dejó de ser un sorteo. El orden es de balance, no de código: decide
## qué se siente al perder, y eso se afina en pruebas, no reescribiendo el
## algoritmo.
##
## Primero lo que sostiene la defensa y la moral, **decoraciones incluidas**.
## Romper una estatua es el golpe más legible que tiene la Tormenta: te quita
## justo el colchón de moral con el que contabas para aguantarla, y lo hace
## antes de pasar la cuenta.
var storm_targets_defense := ["tower", "barracks"]
## Después el techo. Perder casas duele a plazo —baja el aforo, no la
## producción—, así que va en segundo escalón y no en el primero.
var storm_targets_shelter := ["house"]
## La economía (fundición, refinería, minas, aserraderos, almacenes) solo entra
## en el reparto a partir de esta severidad. Que una tormenta menor no pueda
## tocar la fundición es lo que deja margen para rehacerse; si entrara siempre,
## la primera mala racha sería terminal.
var storm_production_target_severity := 4
## La regla anti-softlock: nunca cae el **último** de estos en pie. Sin madera y
## sin oro no hay con qué reparar, y una base que no puede repararse ya perdió
## sin que nadie se lo haya dicho todavía.
var storm_essential_buildings := ["sawmill", "gold_mine"]

func get_storm_damage(severity: int, max_health: int, towers: int) -> int:
	var raw: float = float(max_health) * storm_damage_per_tick * float(maxi(1, severity)) * GameMode.storm_damage_mult()
	return maxi(1, roundi(raw * (1.0 - get_storm_mitigation(towers))))

## Cuánto absorben las torres. Con techo: ninguna cantidad de torres vuelve a la
## base inmune, porque entonces la Tormenta dejaría de ser una amenaza.
func get_storm_mitigation(towers: int) -> float:
	return clampf(storm_tower_mitigation * float(maxi(0, towers)), 0.0, storm_tower_mitigation_max)

## Share of everything in store that the Assessors take when the Tithe is not
## repelled. A percentage, not a flat sum: hoarding into a storm is the mistake.
var storm_tithe_ratio := 0.25
## How many enemies the Assessors field, before severity scaling.
var storm_tithe_base_force := 3

## ── La Cuota Mínima ──
## El porcentaje solo no bastaba: con el almacén en cero se llevaban cero, así
## que meter la bolsa en la cola convertía el Diezmo en un trámite gratis. Ahora
## hay una **deuda base** que no depende de lo que tengas, y lo que no se cubre
## con recursos se cobra en carne. Los Tasadores no se van con las manos vacías;
## esa es toda su función en el mundo.
var storm_tithe_base_debt := 60
var storm_tithe_debt_per_severity := 40
var storm_tithe_debt_per_era := 30
## Lo que salda arruinar un edificio embargado. Alto a propósito: el embargo es
## el último recurso y tiene que cerrar la cuenta rápido, no desmantelar la base
## entera por una deuda pequeña.
var storm_tithe_building_value := 80
## Lo que salda llevarse a un obrero, y lo que cuesta de moral cada uno. Vale
## menos que un edificio porque la gente es lo último que se toca y lo que más
## se nota: un Diezmo que se lleva obreros tiene que doler durante horas.
var storm_tithe_worker_value := 50
## La primera visita es un alta en el libro, no un embargo: se llevan su
## porcentaje de lo almacenado y nada mas. Con la Cuota Minima desde el primer dia,
## el Diezmo de la primera tormenta (minuto ~9, sin cuartel posible hasta la era 2)
## se cobraba en obreros a una colonia de cinco casas: la primera lección era
## perder gente sin haber podido hacer nada (docs/22-linea-jugable.md).
var storm_first_tithe_has_floor := false
var storm_tithe_worker_morale := 10

## Carrera armamentística: cada Diezmo echado engorda la escolta que vuelve.
## Ganarles hoy no te quita el problema, te lo encarece — que es exactamente lo
## que hace una contaduría cuando una provincia demuestra que puede pagar más.
## Cuenta los Diezmos REPELIDOS (StormCycle.tithes_repelled), no las tormentas:
## contando las pagadas la escolta llegaba al tope a la séptima sin que el
## jugador hubiera ganado ninguna.
var storm_assessor_growth_per_win := 0.15
## Con techo, porque el tablero también lo tiene: sin tope, la escalada dejaría
## de leerse en cuanto la escolta desbordara `combat_deploy_cap`.
var storm_assessor_growth_max := 2.0

## Cuánto se llevan de lo almacenado, escalado por severidad. Vive aquí y no en
## StormManager porque es la curva del impuesto, no el procedimiento de cobro.
func get_tithe_ratio(severity: int) -> float:
	return clampf(
		storm_tithe_ratio * (float(severity) / float(maxi(1, storm_severity_max)) + 0.5),
		0.0, 0.9)

## La deuda del día. El suelo existe para el que llega con la bolsa vacía, no
## para abaratarle el Diezmo al que llega lleno: por eso manda el mayor de los
## dos, y el que acumula sigue pagando el porcentaje de siempre.
func get_tithe_debt(severity: int, era: int, stored: int, first_visit: bool = false) -> int:
	var floor_debt: int = storm_tithe_base_debt 		+ storm_tithe_debt_per_severity * maxi(0, severity - 1) 		+ storm_tithe_debt_per_era * maxi(0, era - 1)
	if first_visit and not storm_first_tithe_has_floor:
		floor_debt = 0
	var share: int = int(float(maxi(0, stored)) * get_tithe_ratio(severity))
	return int(round(float(maxi(floor_debt, share)) * GameMode.tithe_mult()))

## El multiplicador de la escolta por Diezmos echados.
func get_assessor_escalation(tithes_repelled: int) -> float:
	return clampf(
		1.0 + storm_assessor_growth_per_win * float(maxi(0, tithes_repelled)),
		1.0, storm_assessor_growth_max)

func get_storm_first_interval() -> float:
	return get_duration(storm_first_interval) * GameMode.storm_interval_mult()

## Bounds of the calm. The roll itself belongs to StormCycle's own generator, so
## the model stays deterministic under a seed.
func get_storm_interval_min() -> float:
	return get_duration(storm_interval_min) * GameMode.storm_interval_mult()

func get_storm_interval_max() -> float:
	return get_duration(storm_interval_max) * GameMode.storm_interval_mult()

## Severidad que el modo suma a toda tormenta (Supervivencia: +1). StormCycle la
## lee aqui para seguir sin conocer a nadie mas que a GameConfig.
func get_storm_severity_bonus() -> int:
	return GameMode.storm_severity_bonus()

func get_storm_warning() -> float:
	# El Faro alarga el Aviso (storm_warning_bonus, lo pone UtilityEffects).
	return get_duration(storm_warning + storm_warning_bonus)

func get_storm_ash_duration() -> float:
	return get_duration(storm_ash_duration)

func get_storm_duration() -> float:
	return get_duration(storm_duration)

func get_storm_tick_interval() -> float:
	return get_duration(storm_tick_interval)

# ── La Orden de la Regencia y el barometro (doc 21 §2.2, D5 = A) ──
# Claves NUEVAS. No tocan ninguna storm_* de antes: la curva del Diezmo, la
# escolta y el daño siguen donde estaban, y la rama de balance es su duena.

## Tope de la rebaja total del proximo Diezmo, sumando todas las fuentes. Con
## 0,5 el Diezmo nunca baja de la mitad: prepararse ayuda, no lo borra.
var storm_order_discount_max := 0.5
## Lo que rebaja entregar el encargo de la Regencia.
var storm_order_delivery_pct := 0.15
## Lo que rebaja ganar una escaramuza durante la calma. Lo aplica la rama de
## escaramuzas llamando a StormManager.add_tithe_discount("expedicion", esto).
var storm_order_expedition_pct := 0.10
## La tarjeta ensena la via de la mision solo con esto puesto. Encendido desde
## que la 1.0 la conecta: echar el campamento de la Regencia (incursion outpost)
## llama a StormManager.add_tithe_discount("expedicion", ...) en CombatManager._apply_loot.
var storm_order_expedition_way := true
## El encargo de la Regencia: cuanto pide de cada cosa (materiales primero; la
## madera y el oro solo si aun no hay ningun material). Se sortea uno por calma.
var storm_order_delivery_base := {
	"planks": 10, "ingots": 6, "beams": 6, "fuel": 8,
	"wood": 80, "gold": 60,
}
## Cuanto crece el encargo por tormenta pasada (0,2 = un 20 % mas cada una), y su
## tope como multiplicador.
var storm_order_delivery_growth := 0.2
var storm_order_delivery_growth_max := 2.0
## Las torres que pide la tercera via ("ten 2 torres en pie"). Solo es la meta que
## se ensena: lo que protegen sigue siendo get_storm_mitigation().
var storm_order_towers_goal := 2

## El barometro de la calma: muestra "entre X e Y min" hasta el Aviso, nunca el
## minuto exacto. El margen es +- esto (segundos de partida) alrededor de un
## centro movido al azar hasta `storm_barometer_jitter` veces el margen. El
## momento de verdad cae siempre dentro.
var storm_barometer_margin := 60.0
var storm_barometer_jitter := 0.5

func get_storm_barometer_margin() -> float:
	return get_duration(storm_barometer_margin)

# ══════════════════════════════════════════════════════════════════════
# ── Las torres en el tablero del Diezmo ──
# ══════════════════════════════════════════════════════════════════════
# Mitigar el daño ya justifica construir torres. Esto justifica tenerlas **en
# pie** el día que los Tasadores se bajan del carro: una torre entera pelea.

## Qué edificio cuenta como torre. Aquí para que ningún servicio vuelva a
## escribir "tower" a mano.
var storm_tower_building_id := "tower"

## Qué pone una torre en el tablero. Una torre es una posición fija con un
## reflector y un arma pesada: ve venir al enemigo de lejos y no maniobra. Eso es
## artillería (alcance 3, movimiento 1), no infantería — una dotación de torre
## que corretea por el tablero sería una unidad que no vive en ninguna parte.
var storm_tower_garrison_unit := "artillery"
## Dotaciones por torre en pie, y su tope. El tope existe por lo mismo que el de
## la mitigación: una fila de torres no puede convertir el Diezmo en un trámite.
var storm_tower_garrison_per_tower := 1
## Tope 4 desde 2026-10-12: el asedio del final pide preparacion, y cada torre de
## mas manda su dotacion cuando la guarnicion ya ha caido (el tablero solo deja
## sitio a 8 - guarnicion viva). Con 6 blindados y 2 torres el asedio se gana el
## 45 %; con 4 torres, el 82 % (docs/17). Objectives pide estas torres antes del
## Cuartel General nivel 3.
var storm_tower_garrison_max := 4
## Lo que pierde una torre cuando cae su dotacion en un tablero (Diezmo o
## Auditoria), como fraccion de su vida maxima. Queda dañada, nunca en ruinas:
## sigue en pie, pero hay que repararla (CombatManager.damage_towers_for_lost_crews).
var storm_tower_crew_loss_damage := 0.4

## Cuántas dotaciones se suman a la guarnición.
##
## Van **además** del tope de despliegue, no dentro: si ocuparan hueco de la
## guarnición, construir una torre sería cambiar un soldado entrenado por una
## dotación y las torres no aportarían nada al tablero, que es justo lo que
## venían a arreglar.
##
## El límite duro no es `combat_deploy_cap` sino el tablero. La defensa nunca
## pasa de una fila del defensor (`combat_board_size.x`), así que si alguien sube
## el tope de despliegue las torres ceden el sitio antes que desbordar la zona de
## despliegue y dejar unidades fuera del tablero.
func get_tower_garrison(standing_towers: int, garrison_size: int) -> int:
	var crews: int = mini(
		maxi(0, standing_towers) * storm_tower_garrison_per_tower, storm_tower_garrison_max)
	return maxi(0, mini(crews, combat_board_size.x - maxi(0, garrison_size)))

# ── Vida de la ciudad: obreros y ciudadanos que andan (solo vista, docs/04) ──

## Una figura por cada tantos habitantes (obreros y ciudadanos por separado).
var life_people_per_figure := 2
## Tope de figuras a la vez (dentro y fuera) por perfil de dispositivo. Una
## figura de mas cuesta una matriz por fotograma, no una llamada de dibujo:
## el tope es por la CPU del movil, no por la GPU.
var life_figure_cap := {"pc": 72, "tablet": 44, "phone": 26}
## Tope de calidad encima del del perfil (-1: ninguno). Lo pondra el preset de
## calidad "Minima" (equipos muy modestos); WorkerWalkers.figure_cap() se queda
## con el menor de los dos. 0 = nadie por la calle.
var life_figure_cap_quality := -1
## El tope de la calidad "Minima" (GraphicsQuality.apply_runtime lo pone en
## life_figure_cap_quality).
var life_figure_cap_minimal := 12
## Celdas por segundo andando, y cuanto apuran el paso en el Aviso de Tormenta.
var life_walk_speed := 1.5
var life_hurry_multiplier := 1.8
## Cuanto se quedan dentro (segundos reales, min y max): en el trabajo, en
## casa entre salida y salida, en el Mercado; y parados ante una decoracion o
## en mitad de un paseo.
var life_stay_work := Vector2(10.0, 20.0)
var life_stay_home := Vector2(4.0, 12.0)
var life_stay_market := Vector2(4.0, 8.0)
var life_pause_decoration := Vector2(3.0, 6.0)
var life_pause_stroll := Vector2(1.0, 2.5)
## La noche en la calle (DayClock; solo vista): la fraccion de figuras que
## quedan de noche cerrada y, de esas, la parte de ciudadanos (el resto son
## obreros: faroleros, vigilantes). Con 80 habitantes y 6 obreros, unas 4-5
## figuras. El paso al anochecer y al amanecer es a saltos de
## `life_night_step` cada `life_night_step_seconds` segundos reales.
var life_night_presence := 0.3
var life_night_citizen_share := 0.15
var life_night_step := 0.1
var life_night_step_seconds := 3.0

# ── Dia y noche (docs/21 §12) ──
#
# Solo visual hoy: el reloj (scripts/storm/DayCycle.gd, lo mueve DayClock) cambia
# la luz del mapa y nada mas. Un ciclo dura la suma de las cuatro fases: 16 min
# reales, con la noche corta (3 min) para que nunca se haga larga a oscuras. En
# dev_mode se comprime como todo (get_duration).

## Apagado = siempre de dia (la luz de Main.tscn tal cual) y el reloj quieto.
var day_cycle_enabled := true
var day_cycle_dawn := 90.0
var day_cycle_day := 600.0
var day_cycle_dusk := 90.0
var day_cycle_night := 180.0
## Cada cuantos segundos reales se repinta la luz del dia. Nada se recalcula por
## frame: entre dos repintados el cambio es de un 1-2 %, invisible.
var day_cycle_refresh := 2.0

func get_day_cycle_durations() -> Array:
	return [get_duration(day_cycle_dawn), get_duration(day_cycle_day),
		get_duration(day_cycle_dusk), get_duration(day_cycle_night)]

# ── Storage Helpers ──

## Tope base de la era. Una era fuera de tabla se acota a la mas cercana en vez de
## devolver 0: un save corrupto no puede dejar al jugador sin almacen.
func get_base_storage_cap(era: int) -> int:
	var keys: Array = base_storage_cap_by_era.keys()
	keys.sort()
	var clamped: int = clampi(era, int(keys[0]), int(keys[-1]))
	return int(base_storage_cap_by_era.get(clamped, base_storage_cap_by_era[keys[0]]))

## Tope de la bolsa compartida: escala con la era y con cada almacen en pie.
func get_storage_cap(warehouse_count: int, era: int = 1) -> int:
	if GameMode.infinite_resources():
		return sandbox_storage_cap
	var cap: int = get_base_storage_cap(era) + (warehouse_count * warehouse_storage_bonus) + tech_storage_bonus
	# El bono del rango del gobernador es un porcentaje pequeno sobre todo lo
	# demas (RankManager lo asigna, no lo suma: cargar dos veces no lo dobla).
	if rank_storage_bonus > 0.0:
		cap = int(round(float(cap) * (1.0 + rank_storage_bonus)))
	return cap

# ── Deposit Helpers ──

func is_deposit_unlocked(deposit_id: String) -> bool:
	var res_name: String = deposit_resource_required.get(deposit_id, "")
	if res_name.is_empty():
		return true
	return ResourceManager.is_unlocked_by_name(res_name)

# ══════════════════════════════════════════════════════════════════════
# ── Game Phase System (gradual unlock of mechanics) ──
# ══════════════════════════════════════════════════════════════════════
#
# Phase 0 "Fundacion"   — Build freely. No consumption, no morale changes, no market, no events.
# Phase 1 "Asentamiento" — Consumption starts (gentle). Pop growth starts.
# Phase 2 "Economia"     — Market unlocks. Morale becomes dynamic.
# Phase 3 "Supervivencia"— Random events start. Decorations affect morale.
# Phase 4+ "Expansion"   — Everything active (eras 2, 3 flow naturally).

enum Phase { FOUNDATION, SETTLEMENT, ECONOMY, SURVIVAL, EXPANSION }

## Which milestone triggers each phase transition
var phase_triggers := {
	Phase.SETTLEMENT: "first_sawmill",     # Build first Sawmill
	Phase.ECONOMY: "first_gold_mine",      # Build first Gold Mine
	Phase.SURVIVAL: "first_warehouse",     # Build first Warehouse
	Phase.EXPANSION: "era_2",              # Build Foundry (era 2)
}

## Gentle early-game timers (overrides for phases 1-2)
var early_consumption_interval := 60.0     # Phase 1-2: every 60s (vs 30s normal)
var early_morale_penalty := -3             # Phase 1-2: gentle penalty (vs -8)
var early_growth_interval := 40.0          # Phase 1-2: slow growth (vs 20s)

# ══════════════════════════════════════════════════════════════════════
# ── Cancelacion, hambruna y suelo de ruina ──
# ══════════════════════════════════════════════════════════════════════
# Tres reglas que van juntas: lo que cuesta arrepentirse, lo que cuesta no pagar
# y hasta donde se puede caer. Seccion aparte a proposito, para que el balance de
# la Tormenta y el de la economia se toquen sin pisarse.

## La Tasa de Corrupcion: que fraccion de lo pagado vuelve al cancelar un
## proceso, un minado o un entrenamiento — y lo que hoy se perdia al demoler con
## algo en curso. En calma solo se pierde la comision; con la Tormenta en marcha
## los Tasadores ya vienen de camino y la fuga de capitales se cobra el doble.
## Si cancelar fuese igual de barato siempre, cancelar seria gratis.
var cancel_refund_ratio := 0.70
var cancel_refund_ratio_storm := 0.40

## Tics de impago que se perdonan antes de que empiece a morir gente y a desertar
## tropa. Dos de gracia: al tercero duele. Margen para reaccionar, no para
## ignorarlo.
var unpaid_grace_ticks := 2
## Cuanto se pierde por tic una vez agotada la gracia.
var starvation_deaths_per_tick := 1
var desertion_units_per_tick := 1
## Moral que cuestan la hambruna y la desercion, ademas del golpe que ya pega el
## impago por si mismo.
var starvation_morale_penalty := -6
var desertion_morale_penalty := -5

## El suelo de ruina: se puede caer hasta el fondo, pero no se pierde la partida.
## Siempre queda alguien para volver a empezar.
var population_floor := 1
## Por debajo de esta poblacion la gente vuelve a nacer aunque la moral este bajo
## el umbral de crecimiento: son los cinco del Nucleo, justo los obreros del
## primer aserradero y la primera mina. Es la salida del pozo (docs/22-linea-jugable.md).
var population_regrow_floor := 5

## Cuanto devuelve cancelar ahora mismo.
func get_cancel_refund_ratio() -> float:
	return cancel_refund_ratio_storm if _storm_cycle_running() else cancel_refund_ratio

## Reembolso exacto de un coste (nombre de recurso -> cantidad). Redondea hacia
## abajo, y es exactamente el numero que la UI ensena antes de confirmar: nadie
## deberia descubrir el porcentaje perdiendolo.
func get_cancel_refund(cost: Dictionary) -> Dictionary:
	var ratio := get_cancel_refund_ratio()
	var refund := {}
	for res_name in cost:
		var amount := int(floor(float(cost[res_name]) * ratio))
		if amount > 0:
			refund[res_name] = amount
	return refund

## Si un contador de tics impagados ya agoto la gracia y toca cobrarselo.
func unpaid_hurts(unpaid_ticks: int) -> bool:
	return unpaid_ticks > unpaid_grace_ticks

## UNICA lectura de la fase de la Tormenta en todo el sistema de cancelacion.
## Aislada a proposito: cuando el ciclo gane fases nuevas o cambien de nombre,
## adaptarlo es esta linea y ninguna mas. Cualquier fase que no sea calma cuenta
## como "Tormenta en marcha", el Diezmo incluido — que es cuando mas duele.
## Pregunta a StormManager en vez de comparar fases: asi una Tormenta parada para
## siempre (asedio ganado) nunca vuelve a cobrar el 60% por cancelar.
func _storm_cycle_running() -> bool:
	return StormManager.is_cycle_active()

# ══════════════════════════════════════════════════════════════════════
# ── La cola abierta y lo que la Tormenta se lleva ──
# ══════════════════════════════════════════════════════════════════════
# La cola no se bloquea en ninguna fase: vaciar el almacen en procesos y
# entrenamientos es una decision legitima del jugador, y prohibirsela seria
# quitarle la unica palanca que tiene contra el Diezmo.
#
# El agujero que se cierra aqui no era cancelar colas: era llenarlas. El coste de
# un proceso se paga al instante, asi que meter el almacen en la cola hacia que
# los Tasadores auditaran ceros — y como los procesos tienen un margen de 1,5x
# (pagas 20 de madera, recibes 35), esconder ahi no solo salvaba los recursos,
# los multiplicaba. Era la jugada dominante del juego.

## Que fraccion de lo pagado sobrevive a la Tormenta. Cero, y no un porcentaje
## bajo: con cualquier reembolso por encima de cero la cola sigue siendo una caja
## fuerte mas barata que el Diezmo, que como mucho se lleva el 37,5%. El
## escondite solo deja de compensar cuando no devuelve absolutamente nada.
var storm_queue_loss_refund_ratio := 0.0

## Solo la TORMENTA arruina la cola. La Advertencia no cuesta nada y la Ceniza es
## la ultima ventana para decidir: si la Ceniza ya destruyera, el aviso que se da
## durante la Ceniza llegaria tarde por definicion y la regla seria injusta.
func storm_phase_ruins_queue(phase: int) -> bool:
	return phase == StormCycle.Phase.STORM

## Lo que se salva de una cosa en curso cuando rompe la Tormenta. Misma forma que
## `get_cancel_refund` a proposito: perderlo por la Tormenta y cancelarlo a mano
## son la misma operacion con distinto precio, y quien la aplique puede tratarlas
## igual sin preguntar cual de las dos fue.
func get_storm_loss_refund(cost: Dictionary) -> Dictionary:
	var refund := {}
	for res_name in cost:
		var amount := int(floor(float(cost[res_name]) * storm_queue_loss_refund_ratio))
		if amount > 0:
			refund[res_name] = amount
	return refund
# ── La Auditoria Final ──
# ══════════════════════════════════════════════════════════════════════
# El Cuartel General a nivel 3 ya no gana la partida: la convoca. La Regencia
# manda su auditoria definitiva y hay que sobrevivirla — varias oleadas seguidas
# contra la misma guarnicion, sin reentrenar entre medias.
#
# Todos los numeros de aqui se leen contra una sola pregunta: cuanto ejercito hay
# que tener en pie para que la ultima oleada siga siendo ganable despues de que
# las anteriores ya se hayan cobrado lo suyo. La atricion es el balance de
# verdad; estos valores solo deciden cuanto muerde.

## Cuantas oleadas trae el asedio (minimo, maximo). Sale de la semilla, no de una
## eleccion del jugador: convocar es apostar sin saber cuanto dura la noche.
## 4-5 desde 2026-10-12 (antes 3-5): un final mas exigente (docs/17, "2026-10-12").
var final_audit_waves := Vector2i(4, 5)

## Cuerpos de la primera oleada, y cuantos suma cada oleada siguiente. El techo
## real lo pone `combat_deploy_cap`: el tablero sigue siendo el mismo de siempre.
var final_audit_base_slots := 3
var final_audit_slots_per_wave := 1

## Multiplicador de HP/ATK por oleada y por era. Cuando los cuerpos ya no caben
## en el tablero, esta escalada es la unica que sigue apretando.
##
## Numeros deliberadamente pequenos, y no por timidez. Medidos con
## `tools/siege_probe.gd`; la tabla entera esta en `docs/17-balance-asedio.md`.
## Con la escalada anterior (0.22 / 0.25 / 1.5) el asedio se perdia SIEMPRE en la
## oleada 2, con la guarnicion maxima que el juego permite y en las 400 semillas
## probadas: el final del juego no se podia terminar. Tres razones:
##   * El multiplicador toca **HP y ATK a la vez**, asi que el poder efectivo va
##     con el cuadrado. Un +0.22 por oleada no es un +22% de dificultad.
##   * No es la unica cuesta. Los cuerpos ya suben solos (3, 4, 5, 6), la
##     formacion ya mete canones en la segunda y blindados en la tercera, y la
##     guarnicion no se cura ni se reentrena entre oleadas. La atricion es el
##     balance de verdad; esto solo decide cuanto muerde.
##   * La era ya entraba dos veces: el 0.25 por era valia +0.50 fijo en TODA
##     oleada, porque el Cuartel General es de era 3 y el asedio no se convoca
##     antes. La oleada de apertura salia ya a x1.5.
var final_audit_scale_per_wave := 0.03
## La era casi no varia aqui —el asedio solo se convoca en la 3— asi que esto es
## en la practica el peso base de la Regencia: +0.10 en todas sus oleadas. Se
## deja viva para que una Regencia que bajase antes lo hiciera mas floja.
var final_audit_scale_per_era := 0.05
## La ultima oleada baja con todo. Es el cierre del juego, no un escalon mas.
## El salto de verdad lo da la formacion (el cierre trae DOS blindados, ver
## `FinalAudit._compose()`); esto es lo que se le suma encima. Un 5% parece poco
## y no lo es: es lo que separa un asedio de 5 oleadas ganable el 44% de las
## veces de uno que no se gana nunca.
## 1.10 desde 2026-10-12 (antes 1.05), con 4-5 oleadas: seis blindados y cuatro
## torres ganan el 82 %, como antes con 3-5 oleadas y dos torres; cinco blindados,
## el 45 %; dos torres, el 45 %; las mixtas, nunca.
## 1.14 desde la ronda final de la 1.1 (2026-10-18, IA nueva + dirigible): con
## 1.10 la referencia (6 blindados, 4 torres) ganaba el 90 %; 1.12-1.13 lo mismo
## (88-90 %), 1.14 el 82,5 % y 1.15 se desploma al 57,5 % (docs/17 "Ronda final").
var final_audit_last_wave_multiplier := 1.14

## Formacion: un canon por cada N cuerpos, y el blindado no aparece hasta esta
## oleada. Cada oleada tiene que verse distinta antes de verse mas grande, o el
## asedio es la misma pelea cinco veces seguidas.
var final_audit_artillery_share := 3
var final_audit_armour_wave := 2
## La unica moneda al aire del asedio: a veces, un canon de mas.
var final_audit_extra_gun_chance := 0.35
## Aire y mar (feat/aire-mar-reglas, 2026-10-17): la Regencia trae dirigibles a
## la ULTIMA oleada desde esta era. Cada dirigible ocupa el hueco de un canon
## (si no hay canon, el de un infante): menos golpe de golpe, mas vida que
## tumbar, y solo se le pega a 1 casilla o con aviones. Si el jugador tiene
## aviones en su guarnicion al abrir la puerta, la ultima oleada trae ademas
## cazas de escolta (cada uno en el hueco de un infante).
##
## MEDIDO (2026-10-17, docs/17 "Aire y mar"): con 1 dirigible la guarnicion de
## referencia (6 blindados, 4 torres) baja del 86 % al 13,5 %. El dirigible no es
## solo vida: la IA de los dos bandos lo prefiere como objetivo (mas `power` que
## el canon y sin desventaja de tipo) y los blindados se pasan la ultima oleada
## arañandole 7 puntos por golpe mientras los canones los rompen; con vida 100
## sigue en el 77 %, y con 2 cazas propios en el 25 %.
##
## 1.1 (decision de Bryan): la IA ya elige por el dano que hace de verdad
## (CombatAI.shot_worth: parte de la vida que se lleva x amenaza del objetivo), no
## por el `power`, asi que los blindados van a por los canones y no persiguen al
## dirigible. ENCENDIDOS otra vez: 1 dirigible y, si tienes aviones, 1 caza de
## escolta. Sondeo corto con la IA nueva (40 semillas, 6 blindados, 4 torres):
## 87,5 % con dirigible y escolta (antes 13,5 %). Objetivo 75-85 %: se confirma
## en la ronda final de medidas (docs/17 "La IA nueva").
var final_audit_air_min_era := 3
var final_audit_airships_last_wave := 1
## 0 desde la ronda final (2026-10-18): con escolta, 6 blindados + 2 cazas ganaban
## el 49,5 % frente al 82,5 % de 6 blindados solos (castigaba tener Aerodromo);
## sin ella, el 65 %. El codigo se queda: volver es una cifra.
var final_audit_air_escort_fighters := 0

## Unidades vivas en casa que hacen falta para volver a convocar tras perder.
## Perder no acaba la partida, pero tampoco se rifa la victoria: hay que
## reconstruir el ejercito antes de que la Regencia vuelva a bajar.
var final_audit_resummon_min_units := 3

## La moral en el Ataque Final (decision de Bryan, ronda final de la 1.1): la
## guarnicion de casa y las dotaciones de las torres pelean con ESTE rango y no
## con combat_morale_attack_range. Con el general (0,60-1,40) la referencia
## (6 blindados, 4 torres) ganaba el 82,5 % con moral 100 y el 0 % con moral 75:
## el asedio dependia solo de la moral. Se defiende la propia casa, asi que la
## moral baja pesa menos; la de 100 vale lo mismo que fuera. Calibrado con
## tools/siege_probe.gd (docs/17 "Ronda final: la moral").
## Ataque 1,20-1,40 e iniciativa 0..+2 (a moral 75: x1,35 y +2; a 100, lo de
## siempre). Medido: moral 75 0 % -> 48,5 %; moral 100 sigue en 82,5 %.
## Con el ataque solo no basta: a moral 75 se quedaba en 27 % por la iniciativa
## (+1 con el rango general).
var final_audit_morale_attack_range := Vector2(1.20, 1.40)
## Iniciativa de la guarnicion: de x (moral 0) a y (moral 100), redondeado.
var final_audit_morale_initiative_range := Vector2(0.0, 2.0)

# ══════════════════════════════════════════════════════════════════════
# ── Modos de juego ──
# ══════════════════════════════════════════════════════════════════════
# La tabla de reglas por modo. Lo que un modo no lista lo hereda de "campaign",
# que es el juego de siempre. Quien lee esto es GameMode (scripts/services/
# GameMode.gd); ningun servicio mira el modo directamente. Detalle y motivos en
# docs/20-modos-de-juego.md.
var game_mode_rules := {
	"campaign": {
		"storm": true,
		# La tormenta de prueba de la era 1 (storm_trial_*).
		"storm_trial": true,
		"tithe": true,
		"audit_on_capstone": true,
		# Tres campanas (feat/tres-campanas): el Ataque Final pide ademas las tres
		# campanas (Tierra, Mar, Aire) completas. Supervivencia lo hereda: es la
		# Campana mas dura. Constructor no tiene asedio; Sandbox lo convoca a mano.
		"audit_needs_campaigns": true,
		"capstone_wins": false,
		"victory": true,
		"resummon": true,
		"offline": true,
		"random_events": true,
		"danger_events": true,
		"infinite_resources": false,
		"all_unlocked": false,
		"sandbox_tools": false,
		"storm_interval_mult": 1.0,
		"storm_severity_bonus": 0,
		"storm_damage_mult": 1.0,
		"tithe_mult": 1.0,
		"starting_resources_mult": 1.0,
		"starting_resources": {},
		"hidden_tips": [],
		# El tablon de encargos (ContractManager, feat/encargos).
		"contracts": true,
	},
	# Relajado: sin Tormenta, sin Diezmo, sin asedio. Los eventos buenos siguen;
	# los danos (tormenta menor, accidente, plaga, bandidos) no salen.
	"builder": {
		"storm": false,
		"storm_trial": false,
		"tithe": false,
		"audit_on_capstone": false,
		"audit_needs_campaigns": false,
		"capstone_wins": true,
		"danger_events": false,
		"hidden_tips": ["storm_incoming", "storm_ash", "storm_started", "tithe", "ruined", "final_audit"],
	},
	# Dificil: tormentas mas seguidas y mas duras, Diezmo mas caro, menos con que
	# empezar, nada de progreso offline y una sola Auditoria.
	"survival": {
		"resummon": false,
		"offline": false,
		"storm_interval_mult": 0.6,
		"storm_severity_bonus": 1,
		"storm_damage_mult": 1.25,
		"tithe_mult": 1.5,
		"starting_resources_mult": 0.75,
	},
	# Creativo / pruebas: todo abierto, recursos que no se acaban, la Tormenta y
	# la Auditoria solo cuando se invocan a mano. Sin victoria.
	"sandbox": {
		"storm": false,
		"storm_trial": false,
		"audit_on_capstone": false,
		"audit_needs_campaigns": false,
		"victory": false,
		"random_events": false,
		"infinite_resources": true,
		"all_unlocked": true,
		"sandbox_tools": true,
		# Con recursos infinitos un encargo no pide nada: sin tablon.
		"contracts": false,
		"starting_resources": {"gold": 20000, "steel": 20000, "oil": 20000, "wood": 20000, "food": 20000},
		"hidden_tips": ["final_audit"],
	},
}

## Niveles de la Campana (GameMode.Tier): "colonist" es el juego de siempre y
## manda en todo lo que "governor" no diga. Gobernador se desbloquea por perfil
## (governor_unlocked_by_profile) y es fijo para la partida. docs/20.
##   spoilage                lo acumulado sin recoger 2 h se echa a perder a medias
##                           (ProductionManager, spoil_after_seconds / spoil_ratio)
##   market_dynamic          calendario de la Tormenta + spread y tendencia visibles
##   combat_hard             enciende los tres multiplicadores de abajo
##   expedition_enemy_mult   escala (vida y ataque) de los enemigos de expedicion
##   tithe_force_mult        cuerpos de la escolta del Diezmo
##   audit_enemy_mult        escala de cada oleada de la Auditoria Final
## Las cifras de combate salen de tools/siege_probe.gd y tools/balance_probe.gd
## (docs/16 y docs/17): con la guarnicion maxima el asedio sigue >= 60 %.
var game_tier_rules := {
	"colonist": {
		"spoilage": false,
		"market_dynamic": false,
		"combat_hard": false,
		"expedition_enemy_mult": 1.0,
		"tithe_force_mult": 1.0,
		"audit_enemy_mult": 1.0,
	},
	"governor": {
		"spoilage": true,
		"market_dynamic": true,
		"combat_hard": true,
		"expedition_enemy_mult": 1.05,
		"tithe_force_mult": 1.34,
		# 1.05 desde 2026-10-12 (antes 1.06): con el asedio de 4-5 oleadas, x1.06
		# dejaba la guarnicion maxima en el 49 %; x1.05 la deja en el 64 % (>= 60 %).
		# 1.005 desde la ronda final de la 1.1 (IA nueva, dirigible, ultima oleada
		# x1.14): x1.05 daba el 23 %, x1.02 el 45 %, x1.01 el 57,5 % y x1.005 el
		# 67,5 % (docs/17 "Ronda final"). El Gobernador se nota en las expediciones,
		# las campanas y el Diezmo; en el asedio, casi nada.
		"audit_enemy_mult": 1.005,
	},
}

## Sandbox: la bolsa compartida no se llena nunca en la practica, y cada recurso
## se rellena hasta este suelo cada vez que se gasta.
var sandbox_storage_cap := 1000000
var sandbox_resource_floor := 20000

# ── Encargos (feat/encargos, doc 21 §2.3 y doc 14 §P3) ──
## Tablon de 3 encargos, uno por fuente. Modelo: scripts/economy/ContractBoard.gd;
## servicio: ContractManager. Valores sin medir con la sonda de linea.

## La era desde la que encarga cada fuente. La Regencia llega con el acero
## (Fundicion, era 2), que es cuando se arma el reloj de la Tormenta.
var contract_source_era := {"regency": 2, "neighbors": 1, "smuggler": 1}
## Segundos de juego (con get_duration) hasta el primer encargo de cada fuente,
## contados desde que la fuente se abre.
var contract_first_delay := {"regency": 45.0, "neighbors": 90.0, "smuggler": 360.0}
## Espera tras entregar, dejar pasar o rechazar un encargo.
var contract_cooldown := 120.0
## Si ninguna plantilla cabe aun (falta desbloquear lo que piden), se vuelve a
## mirar tras esta espera.
var contract_retry_delay := 30.0
## Cada era por encima de la de la plantilla, lo pedido y lo pagado en recursos
## crece este tanto (era +1 = x1,5; +2 = x2). Moral, colonos y rebaja no crecen.
var contract_era_step := 0.5
## Reputacion (solo Gobernador): suelo, y cuanto recorta cada punto los premios
## del siguiente encargo de esa fuente (-3 x 0,15 = premios al 55 %).
var contract_reputation_min := -3
var contract_reputation_step := 0.15
## La Regencia sin Diezmo (Constructor) o sin StormManager.add_tithe_discount
## paga esto en oro (por la escala de era) en vez de la rebaja.
var contract_tithe_fallback_gold := 150
## XP de rango por encargo cumplido (doc 21 §2.5).
var contract_rank_xp := 20
## Plantillas por fuente. `era` = era minima y de referencia para la escala;
## `ask` = lo que piden (recurso -> cantidad); `minutes` = plazo; `reward`:
##   gold/wood/steel/oil/food/... -> a la bolsa (o al taller)
##   morale          -> PopulationManager.adjust_morale
##   colonists       -> PopulationManager.add_colonists (solo si existe)
##   tithe_discount  -> % de rebaja del proximo Diezmo (StormManager.add_tithe_discount)
var contract_templates := {
	# Los vecinos: piden lo de casa y pagan en moral y gente.
	"neighbors": [
		{"id": "nb_wood", "era": 1, "ask": {"wood": 60}, "minutes": 4.0, "reward": {"morale": 8}},
		{"id": "nb_food", "era": 1, "ask": {"food": 40}, "minutes": 4.0, "reward": {"morale": 6, "gold": 30}},
		{"id": "nb_gold", "era": 1, "ask": {"gold": 80}, "minutes": 3.0, "reward": {"morale": 10}},
		{"id": "nb_planks", "era": 1, "ask": {"planks": 6}, "minutes": 5.0, "reward": {"morale": 12}},
		{"id": "nb_planks_people", "era": 1, "ask": {"planks": 8}, "minutes": 5.0, "reward": {"colonists": 3}},
		{"id": "nb_food_people", "era": 1, "ask": {"food": 60}, "minutes": 5.0, "reward": {"colonists": 2}},
	],
	# El contrabandista del puerto: pide materiales y paga en oro o en lo que
	# aun escasea.
	"smuggler": [
		{"id": "sm_wood", "era": 1, "ask": {"wood": 60}, "minutes": 4.0, "reward": {"gold": 140}},
		{"id": "sm_planks", "era": 1, "ask": {"planks": 10}, "minutes": 5.0, "reward": {"gold": 150}},
		{"id": "sm_ingots", "era": 1, "ask": {"ingots": 6}, "minutes": 5.0, "reward": {"gold": 170}},
		{"id": "sm_steel_for_wood", "era": 2, "ask": {"wood": 100}, "minutes": 5.0, "reward": {"steel": 40}},
		{"id": "sm_beams", "era": 2, "ask": {"beams": 8}, "minutes": 6.0, "reward": {"gold": 300}},
		{"id": "sm_oil_for_steel", "era": 2, "ask": {"steel": 60}, "minutes": 6.0, "reward": {"oil": 40}},
		{"id": "sm_fuel", "era": 3, "ask": {"fuel": 10}, "minutes": 6.0, "reward": {"gold": 320}},
	],
	# La Regencia: pide acero y lo que sale de el. Cumplir rebaja el proximo Diezmo.
	"regency": [
		{"id": "rg_steel", "era": 2, "ask": {"steel": 80}, "minutes": 5.0, "reward": {"tithe_discount": 10}},
		{"id": "rg_beams", "era": 2, "ask": {"beams": 10}, "minutes": 6.0, "reward": {"tithe_discount": 10}},
		{"id": "rg_ingots", "era": 2, "ask": {"ingots": 8}, "minutes": 6.0, "reward": {"tithe_discount": 10}},
		{"id": "rg_oil", "era": 3, "ask": {"oil": 60}, "minutes": 6.0, "reward": {"tithe_discount": 10}},
		{"id": "rg_fuel", "era": 3, "ask": {"fuel": 10}, "minutes": 7.0, "reward": {"tithe_discount": 15}},
	],
}

# ══════════════════════════════════════════════════════════════════════
# ── Edificios utiles de la 1.1 (feat/edificios-utiles-1, doc 21 §6.3) ──
# ══════════════════════════════════════════════════════════════════════
# Molino, Silo, Taberna, Carpinteria, Pozo, Faro y Deposito de combustible.
# Sus areas de efecto se calculan al construir, terminar, demoler, arruinar o
# reparar (UtilityEffects.refresh, nunca por frame) y quedan como meta en los
# edificios, igual que `connected` y `staffed`. Nada de esto viaja en el save:
# sale de los edificios, que ya van en el.
# Las distancias son en casillas, de borde a borde de las huellas (Chebyshev).

## Molino: las Granjas a esta distancia rinden +`windmill_farm_bonus`. Dos
## molinos no suman: una Granja cuenta el mejor (uno).
var windmill_radius := 4
var windmill_farm_bonus := 0.2

## Silo: comida que guarda cada uno fuera de la bolsa compartida.
var silo_food_storage := 300
## Silo en Gobernador (estropeado activo): con al menos uno en pie, lo cosechado
## en una Granja tarda esto mas en echarse a perder.
var silo_spoil_delay_mult := 1.5

## Deposito de combustible: petroleo que guarda cada uno fuera de la bolsa.
var fuel_depot_oil_storage := 500

## Taberna: en cada tic de consumo, cada Taberna con obreros y con una casa a
## `tavern_radius` gasta esto; si puede pagarlo, sube la moral y, en el tic de
## crecimiento, nace `tavern_growth_bonus` mas (hasta el tope de casas).
var tavern_radius := 4
var tavern_food_cost := 6
var tavern_gold_cost := 4
var tavern_morale := 2
var tavern_growth_bonus := 1

## Pozo: los edificios a `well_radius` reciben este tanto menos de dano de la
## Tormenta (no se suma entre pozos), y al acabar la Tormenta recuperan esta
## fraccion de su salud (los que no estan en ruinas).
var well_radius := 3
var well_storm_reduction := 0.2
var well_repair_ratio := 0.15

## Faro: segundos que alarga el Aviso de la Tormenta (uno basta: es unico).
var lighthouse_warning_bonus := 20.0
## Lo que alarga el Aviso ahora mismo (runtime, lo pone UtilityEffects).
var storm_warning_bonus := 0.0
## Multiplicador del tiempo hasta estropearse lo cosechado en Granjas (runtime).
var food_spoil_delay_mult := 1.0

## Talleres cuyas recetas NO repite el Nucleo (get_core_extra_processes): la
## Carpinteria hace lo mismo que el Aserradero, el Nucleo ya lo ofrece por el.
var core_skip_workshops := ["carpentry"]

## Lo que tarda en estropearse lo acumulado en un edificio de este tipo.
func spoil_after_for(building_id: String) -> float:
	if building_id == FISHING_DOCK_ID:
		return fishing_dock_spoil_after()
	if building_id == "farm":
		return spoil_after_seconds * maxf(1.0, food_spoil_delay_mult)
	return spoil_after_seconds

# ══════════════════════════════════════════════════════════════════════
# ── Muelle de pesca (feat/muelle-pesca, doc 21 §6.3 n.º 7) ──
# ══════════════════════════════════════════════════════════════════════
# Comida desde el agua: un edificio de era 1 que se planta en la orilla, pegado a
# un banco de peces (yacimiento de mar, MapGenerator.SHORE_DEPOSIT_IDS). Pesca
# solo, sin elegir cultivo: menos por minuto que la Granja con su cultivo largo,
# pero sin esperar ni replantar. Detalle y cifras: docs/03-buildings.md.
# El banco da comida Y oro en la misma fuente (fix/peces-en-el-mar): el .tres
# rinde 12 comida + 3 oro cada 30 s (0,4 comida/s y 0,1 oro/s; una Mina de oro
# da 8 oro/12 s = 0,67/s, asi que el oro del muelle es una propina, no otra mina).
#
# Sus filas en las tablas comunes (topes, regla de yacimiento, taller, obra,
# parcela...) no estan escritas dentro de cada tabla: las anade
# _register_fishing_dock() al crear GameConfig, para que este bloque viva solo y
# no choque con otras ramas que tocan las mismas tablas. Quien busque
# "fishing_dock" en una tabla y no lo vea, lo tiene aqui.

const FISHING_DOCK_ID := "fishing_dock"

## Topes por era (como la Granja, menos: lo limita tambien cuantos bancos hay).
var fishing_dock_limits_by_era := [3, 4, 6]
## Lo que cabe en el muelle antes de pararse (unos 6 minutos de pesca).
var fishing_dock_stock_cap := 150
## Pescado fresco (solo Gobernador, con estropeado): aguanta esta fraccion de lo
## que aguanta lo demas sin recoger. El Silo lo alarga igual que a la Granja.
var fishing_dock_spoil_mult := 0.5

## Bancos de peces por isla nueva: cuantos [min, max], separacion minima entre
## dos (casillas de agua o tierra entre sus huellas), probabilidad de que uno
## salga de 3 casillas de largo y cuanta agua queda entre la orilla y el banco
## (fix/peces-en-el-mar, 2026-10-19: "los peces no van en la costa, van en el
## mar"): entre `min_gap` y `max_gap` casillas de agua, nunca pegado a la arena.
## Por tipo de yacimiento de mar.
var sea_deposit_rolls := {
	"fish_shoal": {"min": 3, "max": 5, "spacing": 6, "long_chance": 0.35,
		"min_gap": 1, "max_gap": 3},
}
## Hasta donde llega un muelle a su banco (Chebyshev desde su huella: 4 = hasta
## tres casillas de agua por medio, las que deja `max_gap`), y a cuantos
## muelles da de comer un banco. El muelle va en la costa (toca el agua).
var fishing_dock_reach := 4
var fishing_dock_per_shoal := 2
## Yacimientos que no se agotan nunca: el panel no ensena usos (solo su frase
## DEP_SHORT_<ID>) y nada los gasta (no tienen minado a mano en mining_data).
var endless_deposits := ["fish_shoal"]

## Lo que tarda en estropearse lo que espera en un muelle.
func fishing_dock_spoil_after() -> float:
	return spoil_after_seconds * fishing_dock_spoil_mult * maxf(1.0, food_spoil_delay_mult)

func is_endless_deposit(deposit_id: String) -> bool:
	return deposit_id in endless_deposits

## Se evalua al crear GameConfig, despues de todas las tablas de arriba.
var _fishing_dock_registered := _register_fishing_dock()

func _register_fishing_dock() -> bool:
	var id := FISHING_DOCK_ID
	building_limits[id] = int(fishing_dock_limits_by_era[0])
	building_limits_by_era[id] = fishing_dock_limits_by_era.duplicate()
	# En la costa ("shore") y con su banco a `fishing_dock_reach` casillas, mar
	# adentro; un banco sirve a `fishing_dock_per_shoal` muelles ("per_deposit").
	building_deposit_rules[id] = {"deposit": "fish_shoal", "reach": fishing_dock_reach,
		"consumes": false, "shore": true, "per_deposit": fishing_dock_per_shoal,
		"message": "LBL_NEEDS_FISH_NEAR"}
	# Ahumar pescado: la madera que sobra (atasca la bolsa, docs/22) pasa a
	# comida que va derecha al almacen, donde nunca se estropea. 15 de madera
	# (45 de oro en el Mercado) por 25 de comida (50): un margen pequeno, es una
	# salida para la madera, no la via rapida. El Nucleo no lo repite: no toca el agua.
	building_processes[id] = [
		{"id": "smoke_fish", "name": "PROC_SMOKE_FISH", "duration": 45.0,
		 "cost": {"wood": 15}, "produces": {"food": 25}},
	]
	if not core_skip_workshops.has(id):
		core_skip_workshops.append(id)
	building_stock_caps[id] = fishing_dock_stock_cap
	if not upgrade_parts_buildings.has(id):
		upgrade_parts_buildings.append(id)
	# El banco de peces: tamano (lo sortea MapGenerator._fill_sea_type), recurso
	# que lo abre (la comida, desde el principio) y usos (no se gastan).
	deposit_sizes["fish_shoal"] = {"min_w": 2, "max_w": 3, "min_h": 2, "max_h": 3}
	deposit_resource_required["fish_shoal"] = "food"
	deposit_max_uses["fish_shoal"] = 1
	# Aspecto: obra de madera de barco y redes, parcela de tablas con su
	# ahumadero (humo cuando trabaja).
	construction_style[id] = {"piles": ["planks", "logs", "sacks"], "fence": "planks",
		"tarp": Color(0.30, 0.45, 0.58), "frame": "gable", "frame_mat": "wood", "site_fx": "dust",
		"flag": Color(0.25, 0.55, 0.78)}
	building_lot_style[id] = {"ground": "dirt", "trim": "fence", "yard": 0.3, "accent": "residential",
		"props": ["barrel", "crate", "sacks", "barrel"], "count": [3, 5]}
	building_active_fx[id] = "smoke"
	return true
