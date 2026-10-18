extends GdUnitTestSuite
## El servicio de las amenazas de costa (ThreatManager, feat/amenazas-costa):
## guardado y reset, ofertas para ATAQUES RAPIDOS (sin pecios ni la atacada),
## tocar la marca, trabajadores en el pecio y el cierre al volver la columna.
##
## Escrito SIN EJECUTAR (regla de Bryan: un solo pase de pruebas al final).

const SaveParking := preload("res://tests/save/save_parking.gd")
const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")
const BACKUP_PATH := "user://save_game.threats.bak"

var _saved: Dictionary = {}

func before(do_skip := SaveParking.in_player_dir(), skip_reason := "Carpeta de usuario del jugador: lanza los tests con tools/run_tests.sh") -> void:
	pass

func before_test() -> void:
	SaveParking.park(BACKUP_PATH)
	_saved = ThreatManager.get_save_data()
	ThreatManager.reset()

func after_test() -> void:
	ThreatManager.load_save_data(_saved)
	SaveParking.restore(BACKUP_PATH)

## Tres amenazas a mano: saqueadores libres (1), avanzadilla atacada (2) y un
## pecio explorandose (3).
func _three() -> Dictionary:
	return {
		"threats": [
			{"id": 1, "type": "raiders", "x": 3, "y": 1, "water": false, "seed": 11, "era": 2,
				"born": 0.0, "ends": 99999.0, "state": "idle", "explore_ends": 0.0, "seen": false},
			{"id": 2, "type": "vanguard", "x": 20, "y": 1, "water": false, "seed": 22, "era": 2,
				"born": 0.0, "ends": 99999.0, "state": "engaged", "explore_ends": 0.0, "seen": true},
			{"id": 3, "type": "wreck", "x": 30, "y": 30, "water": false, "seed": 33, "era": 2,
				"born": 0.0, "ends": 99999.0, "state": "exploring", "explore_ends": 99999.0, "seen": true},
		],
		"next_spawn_at": 500.0,
		"spawned": 3,
		"next_id": 4,
	}

func test_reset_empties_the_coast() -> void:
	ThreatManager.load_save_data(_three())
	ThreatManager.reset()
	assert_array(ThreatManager.get_threats()).is_empty()
	assert_float(ThreatManager.get_board().next_spawn_at).is_equal(-1.0)

func test_save_round_trip() -> void:
	ThreatManager.load_save_data(_three())
	var data: Dictionary = ThreatManager.get_save_data()
	ThreatManager.reset()
	ThreatManager.load_save_data(JSON.parse_string(JSON.stringify(data)))
	assert_int(ThreatManager.get_threats().size()).is_equal(3)
	# Idempotente: cargar otra vez no suma nada.
	ThreatManager.load_save_data(data)
	assert_int(ThreatManager.get_threats().size()).is_equal(3)

func test_attack_offers_skip_wrecks_and_engaged() -> void:
	ThreatManager.load_save_data(_three())
	var offers: Array = ThreatManager.get_attack_offers()
	assert_int(offers.size()).is_equal(1)
	assert_int(int(offers[0]["threat_id"])).is_equal(1)
	assert_str(String(offers[0]["kind"])).is_equal(Generator.KIND_THREAT)
	assert_int(ThreatManager.get_wrecks().size()).is_equal(1)

func test_tapping_near_the_mark_finds_it() -> void:
	ThreatManager.load_save_data(_three())
	assert_int(ThreatManager.threat_at_cell(Vector2i(3, 1))).is_equal(1)
	assert_int(ThreatManager.threat_at_cell(Vector2i(4, 2))).is_equal(1)
	assert_int(ThreatManager.threat_at_cell(Vector2i(10, 10))).is_equal(0)

func test_exploring_wreck_holds_workers() -> void:
	ThreatManager.load_save_data(_three())
	assert_int(ThreatManager.busy_workers()).is_equal(GameConfig.threat_wreck_workers)

func test_winning_clears_the_engaged_threat() -> void:
	ThreatManager.load_save_data(_three())
	ThreatManager._on_expedition_ended(Expedition.RESULT_WON, {}, {})
	assert_dict(ThreatManager.get_threat(2)).is_empty()
	assert_dict(ThreatManager.get_threat(1)).is_not_empty()

func test_losing_leaves_it_on_the_shore() -> void:
	ThreatManager.load_save_data(_three())
	ThreatManager._on_expedition_ended(Expedition.RESULT_LOST, {}, {})
	assert_str(String(ThreatManager.get_threat(2)["state"])).is_equal(ThreatBoard.STATE_IDLE)

func test_a_wreck_cannot_be_attacked_and_a_raid_cannot_be_explored() -> void:
	ThreatManager.load_save_data(_three())
	assert_str(ThreatManager.explore_block_reason(1)).is_not_empty()
	assert_str(ThreatManager.attack_block_reason(2)).is_equal("THREAT_ENGAGED")
	assert_str(ThreatManager.explore_block_reason(3)).is_equal("THREAT_EXPLORING")
	assert_str(ThreatManager.attack_block_reason(99)).is_equal("THREAT_GONE")

func test_loot_shown_is_the_loot_paid() -> void:
	ThreatManager.load_save_data(_three())
	var offer: Dictionary = ThreatBoard.offer_for(ThreatManager.get_board().get_threat(1))
	var map: Array = Generator.threat_map(offer)
	assert_dict(ThreatManager.rewards_of(1)).is_equal(map[0]["rewards"])
	assert_dict(ThreatManager.loot_of(1)).is_equal(map[0]["loot"])
