extends GdUnitTestSuite
## Combat audio, checked without a speaker. Nothing here depends on a sound being
## heard: the tests prove the EventBus wiring, that every combat key points at a
## clip that actually ships, and the pure bookkeeping behind the burst guard and
## the music that returns after a fight.

const COMBAT_SFX_KEYS := [
	"combat_start", "combat_hit", "combat_unit_lost", "combat_victory", "combat_defeat",
	"expedition_start", "expedition_return", "audit_summoned", "storm_halted",
]
const COMBAT_SIGNALS := [
	"encounter_started", "unit_attacked", "unit_died", "encounter_ended",
	"expedition_started", "expedition_ended",
]
## Wired only once the Storm's final chapter declares them on the EventBus.
const OPTIONAL_SIGNALS := ["final_audit_summoned", "storm_halted_forever"]
## Cada senal opcional con SU manejador: reconectar una con el manejador de la
## otra si que anade una conexion, y eso no prueba idempotencia, prueba otra cosa.
const OPTIONAL_HANDLERS := {
	"final_audit_summoned": "_on_final_audit_summoned",
	"storm_halted_forever": "_on_storm_halted_forever",
}

var _saved_last_msec: Dictionary = {}
var _saved_before_combat: String = ""
var _saved_era: int = 1

func before_test() -> void:
	_saved_last_msec = AudioManager._sfx_last_msec.duplicate()
	_saved_before_combat = AudioManager._music_before_combat
	_saved_era = ProgressionManager.current_era
	AudioManager._sfx_last_msec.clear()

func after_test() -> void:
	AudioManager._sfx_last_msec = _saved_last_msec
	AudioManager._music_before_combat = _saved_before_combat
	ProgressionManager.current_era = _saved_era

func _clip_exists(dir: String, base: String) -> bool:
	for ext in [".ogg", ".wav", ".mp3"]:
		if FileAccess.file_exists(dir + base + ext):
			return true
	return false

## True when AudioManager holds a connection on this EventBus signal.
func _audio_listens_to(signal_name: String) -> bool:
	for conn in EventBus.get_signal_connection_list(signal_name):
		var callable: Callable = conn["callable"]
		if callable.get_object() == AudioManager:
			return true
	return false

# ── Wiring ───────────────────────────────────────────────────────────

func test_every_combat_signal_reaches_audio_manager() -> void:
	for signal_name in COMBAT_SIGNALS:
		assert_bool(_audio_listens_to(signal_name)) \
			.override_failure_message("AudioManager is not listening to EventBus.%s" % signal_name) \
			.is_true()

func test_final_audit_signals_are_wired_as_soon_as_they_exist() -> void:
	for signal_name in OPTIONAL_SIGNALS:
		if EventBus.has_signal(signal_name):
			assert_bool(_audio_listens_to(signal_name)) \
				.override_failure_message("EventBus.%s exists but AudioManager ignores it" % signal_name) \
				.is_true()

func test_optional_wiring_is_idempotent() -> void:
	# Calling the optional hook twice must not double-connect anything.
	for signal_name in OPTIONAL_SIGNALS:
		if not EventBus.has_signal(signal_name):
			continue
		var handler: Callable = Callable(AudioManager, String(OPTIONAL_HANDLERS[signal_name]))
		var before: int = EventBus.get_signal_connection_list(signal_name).size()
		AudioManager._connect_optional(signal_name, handler)
		assert_int(EventBus.get_signal_connection_list(signal_name).size()).is_equal(before)

# ── Manifest: every key points at a real file ────────────────────────

func test_every_combat_sfx_key_is_in_the_manifest() -> void:
	for key in COMBAT_SFX_KEYS:
		assert_bool(AudioManager.SFX_MANIFEST.has(key)) \
			.override_failure_message("SFX_MANIFEST lacks %s" % key).is_true()

func test_every_combat_sfx_key_points_at_an_installed_clip() -> void:
	for key in COMBAT_SFX_KEYS:
		var base: String = String(AudioManager.SFX_MANIFEST.get(key, ""))
		assert_bool(_clip_exists(AudioManager.SFX_DIR, base)) \
			.override_failure_message("%s -> %s has no file under %s" % [key, base, AudioManager.SFX_DIR]) \
			.is_true()

func test_victory_and_defeat_do_not_share_a_clip() -> void:
	assert_str(String(AudioManager.SFX_MANIFEST["combat_victory"])) \
		.is_not_equal(String(AudioManager.SFX_MANIFEST["combat_defeat"]))

func test_combat_theme_reuses_an_installed_track() -> void:
	var key: String = AudioManager.MUSIC_COMBAT_KEY
	assert_bool(AudioManager.MUSIC_MANIFEST.has(key)).is_true()
	var base: String = String(AudioManager.MUSIC_MANIFEST[key])
	assert_bool(_clip_exists(AudioManager.MUSIC_DIR, base)) \
		.override_failure_message("combat theme %s has no file under %s" % [base, AudioManager.MUSIC_DIR]) \
		.is_true()

# ── Burst guard: an AI turn full of hits must not drain the voice pool ──

func test_the_same_hit_twice_in_a_burst_plays_once() -> void:
	assert_bool(AudioManager._burst_guard_allows("combat_hit", 1000)).is_true()
	assert_bool(AudioManager._burst_guard_allows("combat_hit", 1000 + AudioManager.SFX_BURST_GAP_MSEC - 1)).is_false()

func test_the_hit_plays_again_once_the_gap_has_passed() -> void:
	assert_bool(AudioManager._burst_guard_allows("combat_hit", 1000)).is_true()
	assert_bool(AudioManager._burst_guard_allows("combat_hit", 1000 + AudioManager.SFX_BURST_GAP_MSEC)).is_true()

func test_different_clips_in_the_same_burst_all_play() -> void:
	assert_bool(AudioManager._burst_guard_allows("combat_hit", 1000)).is_true()
	assert_bool(AudioManager._burst_guard_allows("combat_unit_lost", 1000)).is_true()

func test_a_burst_never_needs_more_than_the_configured_voices() -> void:
	# Distinct keys are what can overlap; the pool holds audio_sfx_voices players.
	assert_int(AudioManager._sfx_players.size()).is_equal(maxi(1, GameConfig.audio_sfx_voices))

# ── Music after the fight ────────────────────────────────────────────

func test_after_combat_the_music_returns_to_the_current_era() -> void:
	ProgressionManager.current_era = 2
	AudioManager._music_before_combat = "era_1"  # era advanced mid-expedition
	assert_str(AudioManager._music_key_after_combat()).is_equal("era_2")

func test_with_nothing_playing_before_the_era_track_is_chosen() -> void:
	ProgressionManager.current_era = 3
	AudioManager._music_before_combat = ""
	assert_str(AudioManager._music_key_after_combat()).is_equal("era_3")

func test_a_non_era_theme_playing_before_combat_is_resumed_as_is() -> void:
	AudioManager._music_before_combat = "victory"
	assert_str(AudioManager._music_key_after_combat()).is_equal("victory")

func test_the_era_key_is_clamped_to_the_three_eras() -> void:
	ProgressionManager.current_era = 9
	AudioManager._music_before_combat = ""
	assert_str(AudioManager._music_key_after_combat()).is_equal("era_3")
