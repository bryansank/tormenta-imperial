extends GdUnitTestSuite
## Ronda de la 1.1 (sonda de linea, 2026-10-18): con el Cuartel General a nivel 3,
## mientras la campana que toca solo espera (su tropa descansa), ¿QUE HACER? pide
## preparar otra que falte (su edificio o su tropa) en vez de quedarse en "la
## mision" hasta que acabe el descanso. ArmyManager cuenta edificios en el
## "BuildingPlacer" de la escena actual: se aparca uno de mentira.

class FakePlacer extends Node:
	var counts: Dictionary = {}
	func count_building(building_id: String) -> int:
		return int(counts.get(building_id, 0))

const Objectives := preload("res://scripts/services/Objectives.gd")

var _placer: FakePlacer
var _scene: Node
var _made_scene := false
var _saved_army: Dictionary = {}
var _saved_campaigns: Dictionary = {}
var _saved_era := 1
var _saved_mode := 0
var _saved_hq_max := false
var _saved_first_sortie := false

func before_test() -> void:
	_saved_army = ArmyManager.get_save_data()
	_saved_campaigns = CombatManager.get_campaigns_save_data()
	_saved_era = ProgressionManager.current_era
	_saved_mode = GameMode.current
	_saved_hq_max = bool(ProgressionManager.milestones_completed.get("hq_max", false))
	_saved_first_sortie = TutorialManager.first_sortie_done
	GameMode.begin_run(GameMode.Mode.CAMPAIGN)
	ProgressionManager.current_era = 3
	ProgressionManager.milestones_completed["hq_max"] = true
	TutorialManager.first_sortie_done = true
	_scene = get_tree().current_scene
	if _scene == null:
		_scene = Node.new()
		_scene.name = "CampaignGatePrepScene"
		get_tree().root.add_child(_scene)
		get_tree().current_scene = _scene
		_made_scene = true
	_placer = FakePlacer.new()
	_placer.name = "BuildingPlacer"
	_scene.add_child(_placer)

func after_test() -> void:
	_scene.remove_child(_placer)
	_placer.free()
	if _made_scene:
		get_tree().current_scene = null
		get_tree().root.remove_child(_scene)
		_scene.free()
	ArmyManager.load_save_data(_saved_army)
	CombatManager.load_campaigns_save_data(_saved_campaigns)
	ProgressionManager.current_era = _saved_era
	if _saved_hq_max:
		ProgressionManager.milestones_completed["hq_max"] = true
	else:
		ProgressionManager.milestones_completed.erase("hq_max")
	TutorialManager.first_sortie_done = _saved_first_sortie
	GameMode.current = _saved_mode

## Tierra hecha; Mar con Astillero y barcos en casa pero descansando; Aire sin
## Aerodromo. Lo siguiente es el Aerodromo, no esperar al Mar.
func test_while_one_campaign_rests_the_panel_prepares_the_next() -> void:
	_placer.counts = {"barracks": 1, "shipyard": 1}
	ArmyManager.load_save_data({"units": {"gunboat": 3, "torpedo_boat": 1}})
	var now: float = ProgressionManager.get_played_seconds()
	CombatManager.load_campaigns_save_data({"seed": 7,
		"progress": {"land": GameConfig.campaign_mission_count("land"), "sea": 1, "air": 0},
		"next_at": {"land": 0.0, "sea": now + 600.0, "air": 0.0}})
	assert_str(CombatManager.campaign_lock_reason("sea")).is_equal("CAMP_LOCK_REST")
	var gate: Dictionary = Objectives.campaign_gate_step()
	assert_str(String(gate.get("kind", ""))).is_equal("build")
	assert_str(String(gate.get("id", ""))).is_equal("aerodrome")

## Con la del Mar lista para salir, el panel la pide a ella (no cambia nada).
## Columna de 6 en casa: desde la ronda final el panel pide 6 de su medio (o la
## que ya salga "Favorable") antes de la mision (campaign_suggested_party).
func test_a_campaign_ready_to_launch_still_comes_first() -> void:
	_placer.counts = {"barracks": 1, "shipyard": 1}
	ArmyManager.load_save_data({"units": {"gunboat": 4, "torpedo_boat": 2}})
	CombatManager.load_campaigns_save_data({"seed": 7,
		"progress": {"land": GameConfig.campaign_mission_count("land"), "sea": 1, "air": 0}})
	var gate: Dictionary = Objectives.campaign_gate_step()
	assert_str(String(gate.get("kind", ""))).is_equal("campaign")
	assert_str(String(gate.get("id", ""))).is_equal("sea")

## Con 4 barcos que no salen "Favorable", el panel pide reponer hasta 6 antes de
## la mision (antes pedia 3 y el jugador perdia la primera vez).
func test_a_small_fleet_is_asked_to_grow_before_the_mission() -> void:
	_placer.counts = {"barracks": 1, "shipyard": 1, "aerodrome": 1}
	ArmyManager.load_save_data({"units": {"gunboat": 3, "torpedo_boat": 1}})
	CombatManager.load_campaigns_save_data({"seed": 7,
		"progress": {"land": GameConfig.campaign_mission_count("land"), "sea": 1, "air": 0}})
	if Objectives.campaign_home_favorable("sea"):
		return
	var gate: Dictionary = Objectives.campaign_gate_step()
	assert_str(String(gate.get("kind", ""))).is_equal("train")
