extends Node
## Central audio service. Subscribes to EventBus signals and plays music, ambience
## and one-shot SFX — no other service calls it directly (Service-Signal-Component).
##
## Robustness: audio files are optional. Any clip listed in the MANIFEST that is not
## present on disk is skipped silently at load, so the game runs perfectly with zero
## audio installed. Drop files into assets/audio/{music,sfx,ambient}/ (see MANIFEST.md)
## and they light up automatically — no code changes needed.
##
## Buses (Master → Music / SFX / Ambient) are created at runtime if missing, so no
## editor-side default_bus_layout.tres is required.

const MUSIC_DIR := "res://assets/audio/music/"
const SFX_DIR := "res://assets/audio/sfx/"
const AMBIENT_DIR := "res://assets/audio/ambient/"

const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_AMBIENT := "Ambient"

## Logical key → filename (without extension). AudioManager tries .ogg then .wav.
## Add a key here and a matching signal hook in _connect_events() to wire new audio.
const MUSIC_MANIFEST := {
	"era_1": "era_1_frontier",
	"era_2": "era_2_industrial",
	"era_3": "era_3_petroleum",
	"victory": "victory",
	# Combat theme. No dedicated track yet: the Era 3 piece is the densest of the
	# four, so it doubles as the battle theme. Drop a `combat.ogg` and repoint this.
	"combat": "era_3_petroleum",
}

## Music key the combat theme is stored under; encounters cross-fade to it.
const MUSIC_COMBAT_KEY := "combat"

const AMBIENT_MANIFEST := {
	"base": "base_ambient",
}

const SFX_MANIFEST := {
	"build_place": "build_place",
	"build_complete": "build_complete",
	"upgrade_complete": "upgrade_complete",
	"demolish": "demolish",
	"trade_buy": "trade_buy",
	"trade_sell": "trade_sell",
	"unlock": "unlock",
	"era_up": "era_up",
	"milestone": "milestone",
	"event_danger": "event_danger",
	"event_positive": "event_positive",
	"process_done": "process_done",
	"mining_done": "mining_done",
	"unit_ready": "unit_ready",
	"ui_click": "ui_click",
	"insufficient": "insufficient",
	# ── Combat (T042) ── every key below reuses a clip that already ships; the
	# ideal replacement for each one is listed in assets/audio/MANIFEST.md.
	"combat_start": "event_danger",       # encounter_started: alarm, the fight is on
	"combat_hit": "build_place",          # unit_attacked: heavy metallic thunk
	"combat_unit_lost": "demolish",       # unit_died: collapse / debris
	"combat_victory": "milestone",        # encounter_ended(true): fanfare stamp
	"combat_defeat": "insufficient",      # encounter_ended(false) / lost expedition
	"expedition_start": "unit_ready",     # expedition_started: military whistle
	"expedition_return": "era_up",        # expedition_ended(victory): brass sting
	"audit_summoned": "event_danger",     # final_audit_summoned: the bell tolls
	"storm_halted": "unlock",             # storm_halted_forever: the sky clears
}

## Same clip requested twice inside this window plays once. An AI turn can land
## several `unit_attacked` in a burst; stacking the identical hit only gets
## louder and would eat every voice in the pool (GameConfig.audio_sfx_voices).
const SFX_BURST_GAP_MSEC := 60

var _streams: Dictionary = {}          # key → AudioStream (only for files that exist)
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next: int = 0
var _sfx_last_msec: Dictionary = {}    # key → Time.get_ticks_msec() of its last play
var _music_players: Array[AudioStreamPlayer] = []  # [0]=active, [1]=fading — swapped on change
var _ambient_player: AudioStreamPlayer
var _current_music_key: String = ""
var _music_before_combat: String = ""  # what was playing when the first encounter opened
var _combat_session: int = 0           # bumps per encounter_started; guards the deferred restore

func _ready() -> void:
	_ensure_buses()
	_build_players()
	_load_manifest(MUSIC_MANIFEST, MUSIC_DIR)
	_load_manifest(AMBIENT_MANIFEST, AMBIENT_DIR)
	_load_manifest(SFX_MANIFEST, SFX_DIR)
	_apply_volumes()
	_connect_events()

# ── Setup ─────────────────────────────────────────────────────────────

func _ensure_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX, BUS_AMBIENT]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")

func _build_players() -> void:
	var voices: int = maxi(1, GameConfig.audio_sfx_voices)
	for i in range(voices):
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_sfx_players.append(p)

	for i in range(2):
		var m := AudioStreamPlayer.new()
		m.bus = BUS_MUSIC
		m.finished.connect(_on_music_finished.bind(m))
		add_child(m)
		_music_players.append(m)

	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = BUS_AMBIENT
	_ambient_player.finished.connect(_on_ambient_finished)
	add_child(_ambient_player)

func _load_manifest(manifest: Dictionary, dir: String) -> void:
	for key in manifest:
		var base_path: String = dir + String(manifest[key])
		for ext: String in [".ogg", ".wav", ".mp3"]:
			var path: String = base_path + ext
			if ResourceLoader.exists(path):
				var stream: Resource = load(path)
				if stream is AudioStream:
					_streams[key] = stream
				break

# ── Volume control (public — wire to a settings UI later) ─────────────

func _apply_volumes() -> void:
	_set_bus_volume("Master", GameConfig.audio_master_volume)
	_set_bus_volume(BUS_MUSIC, GameConfig.audio_music_volume)
	_set_bus_volume(BUS_SFX, GameConfig.audio_sfx_volume)
	_set_bus_volume(BUS_AMBIENT, GameConfig.audio_ambient_volume)

func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var v := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, v <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(v) if v > 0.0 else -80.0)

func set_music_volume(linear: float) -> void:
	GameConfig.audio_music_volume = clampf(linear, 0.0, 1.0)
	_set_bus_volume(BUS_MUSIC, GameConfig.audio_music_volume)

func set_sfx_volume(linear: float) -> void:
	GameConfig.audio_sfx_volume = clampf(linear, 0.0, 1.0)
	_set_bus_volume(BUS_SFX, GameConfig.audio_sfx_volume)

func set_ambient_volume(linear: float) -> void:
	GameConfig.audio_ambient_volume = clampf(linear, 0.0, 1.0)
	_set_bus_volume(BUS_AMBIENT, GameConfig.audio_ambient_volume)

func set_master_volume(linear: float) -> void:
	GameConfig.audio_master_volume = clampf(linear, 0.0, 1.0)
	_set_bus_volume("Master", GameConfig.audio_master_volume)

# ── Playback (public) ─────────────────────────────────────────────────

## Plays a one-shot SFX by manifest key. No-op if the clip is not installed.
func play_sfx(key: String) -> void:
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		return
	if not _burst_guard_allows(key, Time.get_ticks_msec()):
		return
	var p := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	p.stream = stream
	p.play()

## True when `key` may play at `now_msec`; records the play when it does.
## Pure bookkeeping (no audio), so it can be tested headless.
func _burst_guard_allows(key: String, now_msec: int) -> bool:
	var last: int = int(_sfx_last_msec.get(key, -SFX_BURST_GAP_MSEC))
	if now_msec - last < SFX_BURST_GAP_MSEC:
		return false
	_sfx_last_msec[key] = now_msec
	return true

## Cross-fades the music bus to the track for this key (e.g. "era_2", "victory").
func play_music(key: String) -> void:
	if key == _current_music_key:
		return
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		return
	# Two keys can share one file (e.g. "combat" borrows the Era 3 track). If it
	# is already playing, just adopt the new name instead of fading it into itself.
	if stream == _streams.get(_current_music_key) and _music_players[0].playing:
		_current_music_key = key
		return
	_current_music_key = key

	var incoming := _music_players[1]
	var outgoing := _music_players[0]
	_music_players[0] = incoming
	_music_players[1] = outgoing

	var fade: float = maxf(0.01, GameConfig.audio_music_fade)
	incoming.stream = stream
	incoming.volume_db = -40.0
	incoming.play()
	var tin := create_tween()
	tin.tween_property(incoming, "volume_db", 0.0, fade)

	if outgoing.playing:
		var tout := create_tween()
		tout.tween_property(outgoing, "volume_db", -40.0, fade)
		tout.tween_callback(outgoing.stop)

## Switches music to the track matching an era number (1-3). Public so a loader
## can restore the correct track after a saved game finishes loading.
func play_music_for_era(era: int) -> void:
	play_music("era_%d" % clampi(era, 1, 3))

func start_ambient() -> void:
	if _ambient_player.playing:
		return
	var stream: AudioStream = _streams.get("base")
	if stream == null:
		return
	_ambient_player.stream = stream
	_ambient_player.play()

func stop_music() -> void:
	_current_music_key = ""
	for m in _music_players:
		m.stop()

# ── Loop keep-alive (in case the imported clip isn't flagged as looping) ──

func _on_music_finished(player: AudioStreamPlayer) -> void:
	# Only the active player (index 0) loops; the fading-out one is left stopped.
	if player == _music_players[0] and not _current_music_key.is_empty():
		player.play()

func _on_ambient_finished() -> void:
	if _ambient_player.stream != null:
		_ambient_player.play()

# ── EventBus wiring ───────────────────────────────────────────────────

func _connect_events() -> void:
	EventBus.building_placed.connect(_on_building_placed)
	EventBus.construction_completed.connect(_on_construction_completed)
	EventBus.building_upgrade_completed.connect(_on_upgrade_completed)
	EventBus.building_demolished.connect(_on_demolished)
	EventBus.market_trade_completed.connect(_on_trade_completed)
	EventBus.resource_unlocked.connect(_on_resource_unlocked)
	EventBus.era_advanced.connect(_on_era_advanced)
	EventBus.milestone_completed.connect(_on_milestone_completed)
	EventBus.victory_achieved.connect(_on_victory)
	EventBus.random_event_started.connect(_on_random_event)
	EventBus.process_completed.connect(_on_process_completed)
	EventBus.mining_completed.connect(_on_mining_completed)
	EventBus.unit_trained.connect(_on_unit_trained)
	EventBus.resources_insufficient.connect(_on_insufficient)
	EventBus.game_new_started.connect(_on_game_started)
	EventBus.game_load_completed.connect(_on_game_started)
	# Combat (T042)
	EventBus.encounter_started.connect(_on_encounter_started)
	EventBus.unit_attacked.connect(_on_unit_attacked)
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.encounter_ended.connect(_on_encounter_ended)
	EventBus.expedition_started.connect(_on_expedition_started)
	EventBus.expedition_ended.connect(_on_expedition_ended)
	# Final Audit. These signals arrive with the Storm's final chapter; until that
	# branch lands they may not exist, so they are wired only when present.
	_connect_optional("final_audit_summoned", _on_final_audit_summoned)
	_connect_optional("storm_halted_forever", _on_storm_halted_forever)

## Connects to an EventBus signal that may not be declared yet. Handlers take
## optional arguments so they accept whatever arity the signal ends up having.
func _connect_optional(signal_name: String, handler: Callable) -> void:
	if not EventBus.has_signal(signal_name):
		return
	if EventBus.is_connected(signal_name, handler):
		return
	EventBus.connect(signal_name, handler)

func _on_building_placed(_data: Resource, _cell: Vector2i) -> void:
	play_sfx("build_place")

func _on_construction_completed(_node: Node3D) -> void:
	play_sfx("build_complete")

func _on_upgrade_completed(_node: Node3D, _level: int) -> void:
	play_sfx("upgrade_complete")

func _on_demolished(_node: Node3D, _cell: Vector2i) -> void:
	play_sfx("demolish")

func _on_trade_completed(_res: String, _amount: int, is_buy: bool, _total: int) -> void:
	play_sfx("trade_buy" if is_buy else "trade_sell")

func _on_resource_unlocked(_res: String) -> void:
	play_sfx("unlock")

func _on_era_advanced(new_era: int) -> void:
	play_sfx("era_up")
	play_music_for_era(new_era)

func _on_milestone_completed(_id: String) -> void:
	play_sfx("milestone")

func _on_victory(_stats: Dictionary) -> void:
	play_music("victory")

func _on_random_event(_id: String, event_data: Dictionary) -> void:
	# event_data carries a "type"/"category" of "danger" or "positive".
	var kind := String(event_data.get("type", event_data.get("category", "")))
	play_sfx("event_danger" if kind == "danger" else "event_positive")

func _on_process_completed(_node: Node3D, _id: String) -> void:
	play_sfx("process_done")

func _on_mining_completed(_node: Node3D, _id: String) -> void:
	play_sfx("mining_done")

func _on_unit_trained(_id: String) -> void:
	play_sfx("unit_ready")

func _on_insufficient(_res: String, _required: int, _available: int) -> void:
	play_sfx("insufficient")

func _on_game_started() -> void:
	start_ambient()
	# Default to Era 1 music; era_advanced switches tracks as the player progresses.
	if _current_music_key.is_empty():
		play_music("era_1")

# ── Combat (T042) ─────────────────────────────────────────────────────

func _on_encounter_started(_index: int, _is_boss: bool) -> void:
	_combat_session += 1
	play_sfx("combat_start")
	if _current_music_key != MUSIC_COMBAT_KEY:
		_music_before_combat = _current_music_key
	play_music(MUSIC_COMBAT_KEY)

func _on_unit_attacked(_attacker_uid: int, _target_uid: int, _damage: int) -> void:
	play_sfx("combat_hit")

func _on_unit_died(_unit_uid: int, _side: int) -> void:
	play_sfx("combat_unit_lost")

func _on_encounter_ended(victory: bool, _turns_used: int) -> void:
	play_sfx("combat_victory" if victory else "combat_defeat")
	# An expedition may chain the next encounter right behind this one. Decide
	# next frame: if encounter_started bumped the session meanwhile, keep the theme.
	var session := _combat_session
	(func() -> void:
		if session == _combat_session:
			_restore_music_after_combat()
	).call_deferred()

func _on_expedition_started(_expedition_id: int, _node_count: int) -> void:
	play_sfx("expedition_start")

## `result`: 0 = victory, 1 = defeat, 2 = abandoned (see EventBus).
func _on_expedition_ended(result: int, _rewards: Dictionary, _casualties: Dictionary) -> void:
	play_sfx("expedition_return" if result == 0 else "combat_defeat")
	_restore_music_after_combat()

func _on_final_audit_summoned(_a = null, _b = null, _c = null) -> void:
	play_sfx("audit_summoned")

func _on_storm_halted_forever(_a = null, _b = null, _c = null) -> void:
	play_sfx("storm_halted")

## Leaves the combat theme for whatever should be playing now. Only acts while
## the combat theme is actually on: if victory (or a future storm theme) took
## over the bus during the fight, that track stays.
func _restore_music_after_combat() -> void:
	if _current_music_key != MUSIC_COMBAT_KEY:
		return
	play_music(_music_key_after_combat())

## Era tracks are re-derived from ProgressionManager (the era may have advanced
## mid-expedition); any other theme that was playing before is resumed as-is.
func _music_key_after_combat() -> String:
	var previous := _music_before_combat
	if previous.is_empty() or previous.begins_with("era_") or previous == MUSIC_COMBAT_KEY:
		return "era_%d" % clampi(ProgressionManager.current_era, 1, 3)
	return previous
