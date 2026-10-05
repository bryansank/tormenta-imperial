extends RefCounted
## El aspecto de un edificio en el mapa, en las dos vistas: obra (con su fase),
## mejora, ruina, trabajando o quieto. Es la regla, pura y estatica: de los
## hechos del edificio al aspecto. Quien lo pinta es BuildingLookVisual (3D) y
## Building2D (2D); los dos preguntan aqui, asi que nunca discrepan.
##
## Las tres fases de obra son compartidas por HUELLA, no por edificio: una
## parcela 2x2 en obras se ve igual levante lo que levante. Lo que cambia con la
## huella es el tamano y cuantas piezas lleva (postes, pilas, pilares).

const Badge := preload("res://scripts/buildings/BuildingStatusBadge.gd")

enum Look { IDLE, CONSTRUCTION, UPGRADE, RUIN, ACTIVE }

## Fase 0: valla con materiales apilados. 1: solar despejado con cimientos.
## 2: estructura a medio levantar (pilares, forjado y andamio).
const PHASE_FENCE := 0
const PHASE_FOUNDATION := 1
const PHASE_FRAME := 2
const PHASE_COUNT := 3

## Fase de obra para un progreso 0..1, con los umbrales de GameConfig.
static func phase_for(progress: float, thresholds: Array = []) -> int:
	if thresholds.is_empty():
		thresholds = GameConfig.construction_phase_thresholds
	var phase := 0
	for t in thresholds:
		if progress >= float(t):
			phase += 1
	return clampi(phase, 0, PHASE_COUNT - 1)

## Clase de huella: 1, 2 o 3 (el lado mayor, recortado). Una 2x1 es de las de 2.
static func footprint_class(size: Vector2i) -> int:
	return clampi(maxi(size.x, size.y), 1, 3)

## El efecto de actividad de un edificio ("smoke", "dust", "glow") o "".
static func fx_kind(building_id: String) -> String:
	return String(GameConfig.building_active_fx.get(building_id, ""))

## Regla: hechos -> {"look": Look, "phase": int}.
## Hechos: "under_construction", "upgrade" (la obra es una mejora), "progress"
## (0..1), "ruined", "working" (el badge dice trabajando), "fx" (tiene efecto).
## Orden: la obra manda (una torre a medio levantar no es una ruina aunque la
## tormenta la tocara), luego la ruina, luego la actividad.
static func derive(facts: Dictionary) -> Dictionary:
	if bool(facts.get("under_construction", false)):
		if bool(facts.get("upgrade", false)):
			return {"look": Look.UPGRADE, "phase": PHASE_FRAME}
		return {"look": Look.CONSTRUCTION, "phase": phase_for(float(facts.get("progress", 0.0)))}
	if bool(facts.get("ruined", false)):
		return {"look": Look.RUIN, "phase": 0}
	if bool(facts.get("working", false)) and String(facts.get("fx", "")) != "":
		return {"look": Look.ACTIVE, "phase": 0}
	return {"look": Look.IDLE, "phase": 0}

## Los hechos de un edificio real (3D o 2D: los dos llevan las mismas metas y
## un hijo "StatusBadge" con get_status()).
static func facts_of(node: Node, data: BuildingData) -> Dictionary:
	var building := node.has_meta("under_construction")
	var working := false
	var badge := node.get_node_or_null("StatusBadge")
	if badge != null and badge.has_method("get_status"):
		working = int(badge.get_status()) == Badge.Status.WORKING
	return {
		"under_construction": building,
		"upgrade": building and ProductionManager.get_upgrade_target(node) > 0,
		"progress": ProductionManager.get_construction_progress(node) if building else 1.0,
		"ruined": BuildingHealth.is_ruined(node),
		"working": working,
		"fx": fx_kind(data.id) if data else "",
	}
