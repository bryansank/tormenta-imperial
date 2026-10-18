extends GdUnitTestSuite
## Sonido por tipo de unidad (tierra, mar y aire) y el ambiente que sigue al dia,
## a la Tormenta y al tablero. Sin altavoz: se prueba que cada clave tiene su
## fichero, que pesa poco, que cada unidad del juego tiene a que sonar y que el
## bucle elegido cambia con la noche, la Tormenta y el tablero abierto.

const UNIT_SFX_KEYS := [
	"shot_rifle", "shot_cannon", "tank_fire", "tank_engine", "plane_prop",
	"plane_strafe", "bomb_drop", "airship_drone", "ship_horn", "torpedo",
	"splash", "unit_sunk", "unit_downed",
]
## Un efecto corto, mono y en OGG no pasa de esto (el APK tiene que seguir pequeno).
const MAX_SFX_BYTES := 30 * 1024
## Un bucle de ambiente de 40 s a 22 050 Hz.
const MAX_AMBIENT_BYTES := 400 * 1024

var _saved_key := ""
var _saved_night := false
var _saved_phase := -1
var _saved_board := false

func before_test() -> void:
	_saved_key = AudioManager._ambient_key
	_saved_night = AudioManager._night
	_saved_phase = AudioManager._storm_phase
	_saved_board = AudioManager._board_open

func after_test() -> void:
	AudioManager._night = _saved_night
	AudioManager._storm_phase = _saved_phase
	AudioManager._board_open = _saved_board
	AudioManager.set_ambient(_saved_key)

func _clip_path(dir: String, base: String) -> String:
	for ext in [".ogg", ".wav", ".mp3"]:
		if FileAccess.file_exists(dir + base + ext):
			return dir + base + ext
	return ""

func _size_of(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var n := f.get_length()
	f.close()
	return n

func _audio_listens_to(signal_name: String) -> bool:
	for conn in EventBus.get_signal_connection_list(signal_name):
		var callable: Callable = conn["callable"]
		if callable.get_object() == AudioManager:
			return true
	return false

# â”€â”€ Ficheros: existen y pesan poco â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

func test_every_unit_sfx_key_has_a_small_clip() -> void:
	for key in UNIT_SFX_KEYS:
		assert_bool(AudioManager.SFX_MANIFEST.has(key)) \
			.override_failure_message("SFX_MANIFEST lacks %s" % key).is_true()
		var path := _clip_path(AudioManager.SFX_DIR, String(AudioManager.SFX_MANIFEST.get(key, key)))
		assert_str(path).override_failure_message("%s has no file" % key).is_not_empty()
		assert_int(_size_of(path)) \
			.override_failure_message("%s weighs %d bytes" % [key, _size_of(path)]) \
			.is_between(1, MAX_SFX_BYTES)

func test_every_unit_sfx_key_has_its_own_gain() -> void:
	for key in UNIT_SFX_KEYS:
		assert_bool(AudioManager.SFX_GAIN_DB.has(key)) \
			.override_failure_message("SFX_GAIN_DB lacks %s" % key).is_true()
		assert_float(AudioManager.sfx_gain_db(key)).is_less(-6.0)

func test_every_ambient_loop_has_a_file_of_reasonable_size() -> void:
	for key in AudioManager.AMBIENT_MANIFEST:
		var path := _clip_path(AudioManager.AMBIENT_DIR, String(AudioManager.AMBIENT_MANIFEST[key]))
		assert_str(path).override_failure_message("ambient %s has no file" % key).is_not_empty()
		assert_int(_size_of(path)).is_between(1, MAX_AMBIENT_BYTES)

func test_the_coast_loop_is_in_the_manifest_with_its_gain() -> void:
	assert_bool(AudioManager.AMBIENT_MANIFEST.has(AudioManager.AMBIENT_COAST)).is_true()
	assert_bool(AudioManager.AMBIENT_GAIN_DB.has(AudioManager.AMBIENT_COAST)).is_true()

# â”€â”€ Cada unidad del juego suena a algo que existe â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

func test_every_combat_unit_attack_points_at_an_installed_clip() -> void:
	for unit_id in GameConfig.combat_unit_stats:
		var domain := GameConfig.get_unit_domain(unit_id)
		var key := AudioManager.attack_sfx_for(unit_id, domain)
		assert_bool(AudioManager.SFX_MANIFEST.has(key)) \
			.override_failure_message("%s attacks with unknown key %s" % [unit_id, key]).is_true()
		assert_str(_clip_path(AudioManager.SFX_DIR, String(AudioManager.SFX_MANIFEST[key]))).is_not_empty()

func test_attack_sounds_follow_the_unit_type() -> void:
	assert_str(AudioManager.attack_sfx_for("infantry", "land")).is_equal("shot_rifle")
	assert_str(AudioManager.attack_sfx_for("artillery", "land")).is_equal("shot_cannon")
	assert_str(AudioManager.attack_sfx_for("vehicle", "land")).is_equal("tank_fire")
	assert_str(AudioManager.attack_sfx_for("torpedo_boat", "sea")).is_equal("torpedo")
	assert_str(AudioManager.attack_sfx_for("fighter", "air")).is_equal("plane_strafe")
	assert_str(AudioManager.attack_sfx_for("bomber", "air")).is_equal("bomb_drop")

func test_an_unknown_unit_sounds_by_its_domain_and_falls_back_to_the_hit() -> void:
	assert_str(AudioManager.attack_sfx_for("mystery_ship", "sea")).is_equal("shot_cannon")
	assert_str(AudioManager.attack_sfx_for("mystery_plane", "air")).is_equal("plane_strafe")
	assert_str(AudioManager.attack_sfx_for("mystery", "space")).is_equal("combat_hit")

func test_only_engines_make_noise_when_moving() -> void:
	assert_str(AudioManager.move_sfx_for("infantry", "land")).is_empty()
	assert_str(AudioManager.move_sfx_for("artillery", "land")).is_empty()
	assert_str(AudioManager.move_sfx_for("vehicle", "land")).is_equal("tank_engine")
	assert_str(AudioManager.move_sfx_for("gunboat", "sea")).is_equal("ship_horn")
	assert_str(AudioManager.move_sfx_for("fighter", "air")).is_equal("plane_prop")
	assert_str(AudioManager.move_sfx_for("airship", "air")).is_equal("airship_drone")

func test_a_falling_unit_sounds_by_its_domain() -> void:
	assert_str(AudioManager.death_sfx_for("land")).is_equal("combat_unit_lost")
	assert_str(AudioManager.death_sfx_for("sea")).is_equal("unit_sunk")
	assert_str(AudioManager.death_sfx_for("air")).is_equal("unit_downed")
	assert_str(AudioManager.death_sfx_for("")).is_equal("combat_unit_lost")

func test_only_a_hit_on_a_ship_adds_the_splash() -> void:
	assert_str(AudioManager.impact_sfx_for("sea")).is_equal("splash")
	assert_str(AudioManager.impact_sfx_for("land")).is_empty()
	assert_str(AudioManager.impact_sfx_for("air")).is_empty()

func test_moves_and_board_closing_are_wired() -> void:
	for signal_name in ["unit_moved", "encounter_closed", "day_phase_changed", "storm_phase_changed"]:
		assert_bool(_audio_listens_to(signal_name)) \
			.override_failure_message("AudioManager is not listening to EventBus.%s" % signal_name) \
			.is_true()

func test_a_move_or_attack_with_no_board_does_not_break() -> void:
	# Sin tablero no hay unidad que leer: suena el golpe de reserva y nada mas.
	AudioManager._on_unit_moved(999999, Vector2i.ZERO, Vector2i.ONE)
	AudioManager._on_unit_attacked(999999, 999998, 5)
	AudioManager._on_unit_died(999999, 1)
	assert_bool(true).is_true()

# â”€â”€ Que bucle toca â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

func test_day_night_storm_and_board_choose_their_loop() -> void:
	var calm := StormCycle.Phase.CALM
	assert_str(AudioManager._ambient_for_phase(calm, false, false)).is_equal("day")
	assert_str(AudioManager._ambient_for_phase(calm, true, false)).is_equal("night")
	assert_str(AudioManager._ambient_for_phase(calm, false, true)).is_equal("coast")
	assert_str(AudioManager._ambient_for_phase(calm, true, true)).is_equal("coast")
	assert_str(AudioManager._ambient_for_phase(StormCycle.Phase.WARNING, false, true)).is_equal("coast")

func test_the_storm_rules_over_the_board_and_the_night() -> void:
	for phase in [StormCycle.Phase.ASH, StormCycle.Phase.STORM, StormCycle.Phase.TITHE]:
		assert_str(AudioManager._ambient_for_phase(phase, true, true)).is_equal("storm")
		assert_str(AudioManager._ambient_for_phase(phase, false, false)).is_equal("storm")

func test_nightfall_switches_the_playing_loop() -> void:
	AudioManager._storm_phase = StormCycle.Phase.CALM
	AudioManager._board_open = false
	AudioManager.set_ambient("day")
	AudioManager._on_day_phase_changed(DayCycle.Phase.NIGHT, 22.0)
	assert_str(AudioManager.get_ambient_key()).is_equal("night")
	AudioManager._on_day_phase_changed(DayCycle.Phase.DAWN, 6.0)
	assert_str(AudioManager.get_ambient_key()).is_equal("day")

func test_the_storm_phase_switches_the_playing_loop() -> void:
	AudioManager._storm_phase = StormCycle.Phase.CALM
	AudioManager._night = false
	AudioManager._board_open = false
	AudioManager.set_ambient("day")
	AudioManager._on_storm_phase_changed(StormCycle.Phase.ASH, 30.0)
	assert_str(AudioManager.get_ambient_key()).is_equal("storm")
	AudioManager._on_storm_phase_changed(StormCycle.Phase.CALM, 300.0)
	assert_str(AudioManager.get_ambient_key()).is_equal("day")

func test_closing_the_board_brings_the_island_back() -> void:
	AudioManager._storm_phase = StormCycle.Phase.CALM
	AudioManager._night = true
	AudioManager._board_open = true
	AudioManager.set_ambient("coast")
	# En los tests no hay tablero abierto: CombatManager.is_board_open() es false.
	AudioManager._on_encounter_closed()
	assert_bool(AudioManager._board_open).is_false()
	assert_str(AudioManager.get_ambient_key()).is_equal("night")

func test_with_no_ambient_playing_a_phase_change_starts_nothing() -> void:
	AudioManager.set_ambient("")
	AudioManager._on_day_phase_changed(DayCycle.Phase.NIGHT, 22.0)
	assert_str(AudioManager.get_ambient_key()).is_empty()
