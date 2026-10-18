extends RefCounted
## Las areas de efecto de "defensa y vida" (doc 21 §6.3 n.º 11, 12 y 18, §6.4):
## Bastion (menos dano de la Tormenta a lo que hay detras y casillas de cobertura
## en el tablero de defensa), Chatarreria (reparar mas barato en su zona y
## chatarra tras la Tormenta), Telegrafo (un encargo mas, plazos mas largos) y la
## belleza del barrio (casas bonitas y elegantes).
##
## Regla pura sobre GridManager, como UtilityEffects: `refresh()` recorre los
## edificios UNA vez y deja el resultado en metas de los nodos y en tres valores
## de runtime de GameConfig; los servicios solo leen. La llama ProductionManager,
## agrupada y diferida, al colocar, terminar, demoler, arruinar, reparar o
## mejorar un edificio y al cargar (doc 21 §6.6: nunca por frame).
##
## Metas que escribe (y borra cuando ya no tocan):
## - "bastion_cover" (float) en los edificios detras de un Bastion en pie;
## - "scrap_cover" (float) en los edificios en la zona de una Chatarreria que
##   trabaja (descuento de la reparacion);
## - en las casas: "beauty" (int, puntos), "beauty_level" (1..3; sin meta = 1),
##   "beauty_room" (int) y "beauty_morale" (int). PopulationManager suma las dos
##   ultimas; las vistas pintan el nivel (BeautyTrim en 3D, Building2D en 2D).

const BASTION_META := "bastion_cover"
const SCRAP_META := "scrap_cover"
const BEAUTY_META := "beauty"
const BEAUTY_LEVEL_META := "beauty_level"
const BEAUTY_ROOM_META := "beauty_room"
const BEAUTY_MORALE_META := "beauty_morale"

const Fx := preload("res://scripts/buildings/UtilityEffects.gd")

## Recalcula todo. Devuelve un resumen (lo usan las pruebas y quien llama):
## {"bastions", "scrapyards", "telegraph", "cover_cells", "beauty_changed",
##  "pretty", "elegant"}. `beauty_changed`: alguna casa cambio de nivel o de
## puntos que cuentan (quien llama recuenta la gente y repinta).
static func refresh() -> Dictionary:
	var views: Array = GridManager.buildings_view()
	var bastions: Array = []
	var yards: Array = []
	var decos: Array = []
	var houses: Array = []
	var telegraph := false
	for info in views:
		var data: BuildingData = info.get("data")
		var node: Node = info.get("node")
		if data == null or node == null or not is_instance_valid(node):
			continue
		var up := BuildingHealth.is_operational(node)
		match data.id:
			"bastion":
				if up: bastions.append(info)
			"scrapyard":
				if up and _works(node): yards.append(info)
			"telegraph":
				if up and _works(node): telegraph = true
			"house":
				houses.append(info)
			_:
				if up and GameConfig.beauty_of(data, int(node.get_meta("level", 1))) > 0:
					decos.append(info)

	# Bastion -> lo que queda detras (lado del centro de la isla) y cerca.
	var center := island_center()
	for info in views:
		var node: Node = info.get("node")
		if node == null or not is_instance_valid(node):
			continue
		var covered := false
		if not bastions.is_empty():
			for b in bastions:
				if b.get("node") != node and is_behind(info, b, center, GameConfig.bastion_radius):
					covered = true
					break
		Fx._set_meta(node, BASTION_META, GameConfig.bastion_storm_reduction if covered else 0.0)
		# Chatarreria -> su zona (ella incluida: sus brigadas se arreglan lo suyo).
		var scrap := false
		for y in yards:
			if y.get("node") == node or Fx._gap(info, y) <= GameConfig.scrapyard_radius:
				scrap = true
				break
		Fx._set_meta(node, SCRAP_META, GameConfig.scrapyard_repair_discount if scrap else 0.0)

	# Belleza -> casas.
	var changed := false
	var pretty := 0
	var elegant := 0
	for h in houses:
		var node: Node = h["node"]
		var points := 0
		if BuildingHealth.is_operational(node) and bool(node.get_meta("connected", true)):
			for d in decos:
				if Fx._gap(h, d) <= GameConfig.beauty_radius:
					var dd: BuildingData = d["data"]
					points += GameConfig.beauty_of(dd, int((d["node"] as Node).get_meta("level", 1)))
		var lvl := GameConfig.beauty_level_for(points)
		if int(node.get_meta(BEAUTY_LEVEL_META, 1)) != lvl or int(node.get_meta(BEAUTY_META, 0)) != points:
			changed = true
		Fx._set_meta(node, BEAUTY_META, points)
		Fx._set_meta(node, BEAUTY_LEVEL_META, lvl if lvl > 1 else 0)
		Fx._set_meta(node, BEAUTY_ROOM_META, GameConfig.beauty_room_for(lvl))
		Fx._set_meta(node, BEAUTY_MORALE_META, GameConfig.beauty_morale_for(lvl))
		if lvl == 2:
			pretty += 1
		elif lvl >= 3:
			elegant += 1

	# Runtime: cobertura del proximo tablero de defensa y el tablon de encargos.
	GameConfig.defense_cover_cells = GameConfig.bastion_cover_cells_for(bastions.size())
	GameConfig.contract_extra_slots = GameConfig.telegraph_extra_contracts if telegraph else 0
	GameConfig.contract_duration_mult = 1.0 + GameConfig.telegraph_duration_bonus if telegraph else 1.0
	return {"bastions": bastions.size(), "scrapyards": yards.size(), "telegraph": telegraph,
		"cover_cells": GameConfig.defense_cover_cells, "beauty_changed": changed,
		"pretty": pretty, "elegant": elegant}

## Partida nueva: nada de lo de arriba sigue en pie.
static func clear() -> void:
	GameConfig.defense_cover_cells = 0
	GameConfig.contract_extra_slots = 0
	GameConfig.contract_duration_mult = 1.0

## El nivel de belleza de una casa (1 = la de siempre).
static func beauty_level(node: Node) -> int:
	if node == null or not is_instance_valid(node):
		return 1
	return maxi(1, int(node.get_meta(BEAUTY_LEVEL_META, 1)))

## Con obreros (o sin necesitarlos): los retirados o sin gente no trabajan.
static func _works(node: Node) -> bool:
	if bool(node.get_meta("workers_off", false)):
		return false
	if not bool(node.get_meta("connected", true)):
		return false
	return bool(node.get_meta("staffed", true))

# ── Geometria pura (la usan las pruebas sin escena) ───────────────────

## El centro de la isla en casillas: el mar queda hacia fuera de el.
static func island_center() -> Vector2:
	var r: Rect2i = GridManager.land_bounds()
	if r.size == Vector2i.ZERO:
		return Vector2(GridManager.grid_width, GridManager.grid_height) * 0.5
	return Vector2(r.position) + Vector2(r.size) * 0.5

## El centro de una huella (lista de celdas) en casillas.
static func footprint_center(cells: Array) -> Vector2:
	if cells.is_empty():
		return Vector2.ZERO
	var acc := Vector2.ZERO
	for c in cells:
		acc += Vector2(c) + Vector2(0.5, 0.5)
	return acc / float(cells.size())

## `info` esta detras del muro `wall`: a `radius` casillas o menos (borde a
## borde) y del lado del centro de la isla (mirando desde el muro, no hacia
## fuera). Lo que esta justo al lado, a la par del muro, tambien cuenta. Un muro
## en el mismo centro de la isla no tiene "fuera": cubre todo su radio.
static func is_behind(info: Dictionary, wall: Dictionary, center: Vector2, radius: int) -> bool:
	if Fx._gap(info, wall) > radius:
		return false
	var wc := footprint_center(wall.get("cells", []))
	var outward := wc - center
	if outward.length() < 0.5:
		return true
	var bc := footprint_center(info.get("cells", []))
	return (bc - wc).dot(outward.normalized()) <= 0.75

# ── Tras la Tormenta: las brigadas de la Chatarreria ──────────────────

## Despeja las ruinas de la zona de cada Chatarreria que trabaja: acero por
## ruina, repuestos por cada par, y levanta alguna para que vuelva a funcionar.
## Cada ruina cuenta una vez aunque la cubran dos chatarrerias. Devuelve
## {"ruins", "steel", "parts", "lifted"}; quien llama (StormManager) paga y avisa.
## Puro sobre GridManager + BuildingHealth; no toca la bolsa.
static func salvage_plan() -> Dictionary:
	var views: Array = GridManager.buildings_view()
	var yards: Array = []
	for info in views:
		var data: BuildingData = info.get("data")
		var node: Node = info.get("node")
		if data == null or node == null or not is_instance_valid(node):
			continue
		if data.id == GameConfig.SCRAPYARD_ID and BuildingHealth.is_operational(node) and _works(node):
			yards.append(info)
	var out := {"ruins": 0, "steel": 0, "parts": 0, "lifted": [], "yards": yards.size()}
	if yards.is_empty():
		return out
	var taken: Dictionary = {}
	for y in yards:
		var ruins: Array = []
		for info in views:
			var node: Node = info.get("node")
			if node == null or not is_instance_valid(node) or taken.has(node):
				continue
			if not BuildingHealth.is_ruined(node) or node.has_meta("under_construction"):
				continue
			if Fx._gap(info, y) <= GameConfig.scrapyard_radius:
				ruins.append(node)
				taken[node] = true
		out["ruins"] = int(out["ruins"]) + ruins.size()
		out["steel"] = int(out["steel"]) + ruins.size() * GameConfig.scrapyard_steel_per_ruin
		out["parts"] = int(out["parts"]) + mini(GameConfig.scrapyard_parts_max,
			floori(float(ruins.size()) / float(maxi(1, GameConfig.scrapyard_ruins_per_part))))
		for i in mini(GameConfig.scrapyard_brigade_lifts, ruins.size()):
			(out["lifted"] as Array).append(ruins[i])
	return out

# ── Lo que dice la ficha del edificio ─────────────────────────────────

## Una linea para la ficha (BuildingInfoPanel), o "" si no hay nada que decir.
static func info_line(node: Node, data: BuildingData) -> String:
	if node == null or data == null or not is_instance_valid(node):
		return ""
	var parts: Array = []
	match data.id:
		"house":
			var lvl := beauty_level(node)
			var pts := int(node.get_meta(BEAUTY_META, 0))
			var key: String = ["LBL_BEAUTY_PLAIN", "LBL_BEAUTY_PRETTY", "LBL_BEAUTY_ELEGANT"][clampi(lvl, 1, 3) - 1]
			parts.append(Tr.t(key) % pts)
			if lvl < 3:
				parts.append(Tr.t("LBL_BEAUTY_NEXT") % int(GameConfig.beauty_levels[lvl - 1]))
		"bastion":
			parts.append(Tr.t("LBL_BASTION_INFO") % [count_covered(node, BASTION_META),
				roundi(GameConfig.bastion_storm_reduction * 100.0), GameConfig.bastion_cover_defense])
		"scrapyard":
			parts.append(Tr.t("LBL_SCRAPYARD_INFO") % [roundi(GameConfig.scrapyard_repair_discount * 100.0),
				GameConfig.scrapyard_radius])
		"telegraph":
			parts.append(Tr.t("LBL_TELEGRAPH_INFO") % [GameConfig.telegraph_extra_contracts,
				roundi(GameConfig.telegraph_duration_bonus * 100.0)])
	if float(node.get_meta(BASTION_META, 0.0)) > 0.0 and data.id != GameConfig.BASTION_ID:
		parts.append(Tr.t("LBL_BEHIND_BASTION") % roundi(float(node.get_meta(BASTION_META, 0.0)) * 100.0))
	return "\n".join(parts)

## Cuantos edificios llevan `meta` cerca de `source` (para la ficha; no por frame).
static func count_covered(source: Node, meta: String) -> int:
	var info: Dictionary = GridManager.get_building_info(source)
	if info.is_empty():
		return 0
	var center := island_center()
	var n := 0
	for other in GridManager.buildings_view():
		var node: Node = other.get("node")
		if node == null or node == source or not is_instance_valid(node):
			continue
		if float(node.get_meta(meta, 0.0)) <= 0.0:
			continue
		if meta == BASTION_META and not is_behind(other, info, center, GameConfig.bastion_radius):
			continue
		var d: BuildingData = other.get("data")
		if d != null and d.id == "road":
			continue
		n += 1
	return n
