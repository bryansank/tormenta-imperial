extends GdUnitTestSuite
## Las marcas de las amenazas de costa en las dos vistas (feat/amenazas-costa):
## una por amenaza, se quitan al irse, y la malla 3D sale de la cache.
##
## Escrito SIN EJECUTAR (regla de Bryan: un solo pase de pruebas al final).

const SaveParking := preload("res://tests/save/save_parking.gd")
const Marks3D := preload("res://scripts/map/ThreatMarks3D.gd")
const Marks2D := preload("res://scripts/view2d/ThreatMarks2D.gd")
const Generator := preload("res://scripts/combat/ExpeditionGenerator.gd")
const BACKUP_PATH := "user://save_game.threatmarks.bak"

var _saved: Dictionary = {}

func before(do_skip := SaveParking.in_player_dir(), skip_reason := "Carpeta de usuario del jugador: lanza los tests con tools/run_tests.sh") -> void:
	pass

func before_test() -> void:
	SaveParking.park(BACKUP_PATH)
	_saved = ThreatManager.get_save_data()

func after_test() -> void:
	ThreatManager.load_save_data(_saved)
	SaveParking.restore(BACKUP_PATH)

func _two() -> Dictionary:
	return {"threats": [
		{"id": 1, "type": "raiders", "x": 2, "y": 1, "water": true, "seed": 5, "era": 2,
			"born": 0.0, "ends": 999.0, "state": "idle", "explore_ends": 0.0, "seen": false},
		{"id": 2, "type": "wreck", "x": 30, "y": 2, "water": false, "seed": 6, "era": 2,
			"born": 0.0, "ends": 999.0, "state": "idle", "explore_ends": 0.0, "seen": false},
	], "next_spawn_at": 100.0, "next_id": 3}

func test_3d_one_mesh_per_threat_and_they_go_away() -> void:
	var marks = auto_free(Marks3D.new())
	add_child(marks)
	ThreatManager.load_save_data(_two())
	marks.sync()
	assert_int(marks.mark_count()).is_equal(2)
	ThreatManager.reset()
	marks.sync()
	assert_int(marks.mark_count()).is_equal(0)

func test_3d_meshes_are_cached_per_type() -> void:
	var a: ArrayMesh = Marks3D.mesh_for(Generator.THREAT_VANGUARD, false)
	var b: ArrayMesh = Marks3D.mesh_for(Generator.THREAT_VANGUARD, false)
	assert_object(a).is_same(b)
	assert_object(Marks3D.mesh_for(Generator.THREAT_RAIDERS, true)).is_not_same(Marks3D.mesh_for(Generator.THREAT_RAIDERS, false))
	assert_int(a.get_surface_count()).is_equal(1)

func test_2d_draws_every_threat() -> void:
	var marks = auto_free(Marks2D.new())
	add_child(marks)
	ThreatManager.load_save_data(_two())
	marks.sync()
	assert_int(marks.mark_count()).is_equal(2)
	assert_int(marks.z_index).is_equal(1)
