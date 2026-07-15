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
}

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
}

var _streams: Dictionary = {}          # key → AudioStream (only for files that exist)
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next: int = 0
var _music_players: Array[AudioStreamPlayer] = []  # [0]=active, [1]=fading — swapped on change
var _ambient_player: AudioStreamPlayer
var _current_music_key: String = ""

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
	var p := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	p.stream = stream
	p.play()

## Cross-fades the music bus to the track for this key (e.g. "era_2", "victory").
func play_music(key: String) -> void:
	if key == _current_music_key:
		return
	var stream: AudioStream = _streams.get(key)
	if stream == null:
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
