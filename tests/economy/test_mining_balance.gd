extends GdUnitTestSuite
## Era 1 de 8-12 minutos (decision de Bryan, 2026-10-04): el minado a mano ya no
## es la via rapida a la Fundicion. Con 20 de oro cada 12 s, dos obreros minando
## sacaban 2,5 veces lo que una Mina de oro con tres, y el jugador que minaba
## llegaba a la era 2 en el minuto 3,8 (docs/22-linea-jugable.md §5.4).
##
## La regla que se fija: por obrero y por minuto, una veta o un bosque a mano no
## rinden mas que su extractor.

const PAIRS := {
	"gold_vein": ["gold_mine", "gold"],
	"forest": ["sawmill", "wood"],
}

func _per_worker_minute(amount: float, seconds: float, workers: int) -> float:
	return amount / maxf(seconds, 0.001) * 60.0 / float(maxi(1, workers))

func test_hand_mining_never_beats_its_extractor_per_worker() -> void:
	for deposit_id in PAIRS:
		var building_id: String = PAIRS[deposit_id][0]
		var res: String = PAIRS[deposit_id][1]
		var mine: Dictionary = GameConfig.mining_data[deposit_id]
		var by_hand: float = _per_worker_minute(
			float(mine["produces"][res]), float(mine["duration"]), GameConfig.mining_workers)
		var data: BuildingData = load("res://data/buildings/%s.tres" % building_id)
		var produced: int = int(data.get("produces_" + res))
		var by_building: float = _per_worker_minute(
			float(produced), data.production_interval, data.workers_required)
		assert_float(by_hand).override_failure_message(
			"%s a mano: %.1f por obrero y minuto; %s: %.1f" % [deposit_id, by_hand, building_id, by_building]
		).is_less_equal(by_building)

func test_the_era_one_numbers_are_the_measured_ones() -> void:
	# Los que se midieron con tools/line_probe.gd (docs/22 §5.5).
	assert_float(float(GameConfig.mining_data["gold_vein"]["duration"])).is_equal(30.0)
	assert_int(int(GameConfig.mining_data["gold_vein"]["produces"]["gold"])).is_equal(12)
	assert_float(float(GameConfig.mining_data["forest"]["duration"])).is_equal(20.0)
	assert_int(int(GameConfig.mining_data["forest"]["produces"]["wood"])).is_equal(10)
