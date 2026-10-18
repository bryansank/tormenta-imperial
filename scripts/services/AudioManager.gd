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
	# Tema de combate propio: "Battle Theme A" de cynicmusic (CC0, OpenGameArt).
	"combat": "combat",
}

## Music key the combat theme is stored under; encounters cross-fade to it.
const MUSIC_COMBAT_KEY := "combat"

## Cuatro bucles cortos (40 s, OGG en streaming); suena uno, y dos solo mientras
## se funden. `day` = olas + pajaros; `night` = grillos + olas suaves, sin
## pajaros; `storm` = viento + lluvia + truenos lejanos (los pajaros callan con la
## Tormenta); `coast` = la orilla del tablero (resaca mas cerca, brisa, gaviotas)
## mientras hay un tablero abierto. Generados por sintesis con
## tools/gen_ambient_audio.gd (obra propia).
const AMBIENT_MANIFEST := {
	"day": "day",
	"night": "night",
	"storm": "storm",
	"coast": "coast",
}
const AMBIENT_DAY := "day"
const AMBIENT_NIGHT := "night"
const AMBIENT_STORM := "storm"
const AMBIENT_COAST := "coast"
## Ganancia de cada bucle (dB): el ambiente es una cama, va por debajo de todo.
const AMBIENT_GAIN_DB := {
	"day": -4.0,
	"night": -5.0,
	"storm": -3.0,
	# Bajo los disparos: en el tablero mandan los efectos.
	"coast": -7.0,
}
const AMBIENT_FADE_SECONDS := 4.0
const AMBIENT_SILENT_DB := -50.0

## Ningun efecto con meta de este nombre suena al pulsarse (boton con sonido propio).
const UI_SILENT_META := "no_click_sfx"
## Tras un tablero ganado ya ha sonado la fanfarria: el Diezmo repelido no la pisa.
const TITHE_AFTER_VICTORY_MSEC := 2500

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
	"ui_click": "ui_click",               # cualquier boton (enganche automatico)
	"ui_toggle": "ui_toggle",             # interruptores, casillas y pestanas
	"insufficient": "insufficient",
	# ── Combate: cada clave tiene su clip (ver assets/audio/MANIFEST.md) ──
	"combat_start": "combat_start",       # encounter_started: golpe de tambor
	"combat_hit": "combat_hit",           # unit_attacked: impacto metalico
	"combat_unit_lost": "combat_unit_lost",  # unit_died: estallido sordo
	"combat_victory": "combat_victory",   # encounter_ended(true): saxo que sube
	"combat_defeat": "combat_defeat",     # encounter_ended(false) / expedicion perdida
	"expedition_start": "expedition_start",  # expedition_started: redoble corto
	"expedition_return": "expedition_return",  # expedition_ended(victoria)
	"audit_summoned": "audit_summoned",   # final_audit_summoned: campana grave
	"storm_halted": "storm_halted",       # storm_halted_forever: acorde claro
	"rank_up": "rank_up",                 # governor_rank_up: toque de ascenso
	# ── Combate por tipo de unidad (sintesis propia, tools/gen_combat_audio.gd) ──
	# Quien suena lo eligen ATTACK_SFX / MOVE_SFX / DEATH_SFX_BY_DOMAIN segun la
	# unidad del tablero; `combat_hit` y `combat_unit_lost` quedan de reserva.
	"shot_rifle": "shot_rifle",           # ataca la infanteria
	"shot_cannon": "shot_cannon",         # artilleria, canonera, acorazado
	"tank_fire": "tank_fire",             # ataca el blindado
	"tank_engine": "tank_engine",         # el blindado se mueve
	"plane_prop": "plane_prop",           # caza o bombardero se mueven
	"plane_strafe": "plane_strafe",       # ataca el caza
	"bomb_drop": "bomb_drop",             # bombardero y dirigible atacan
	"airship_drone": "airship_drone",     # el dirigible se mueve
	"ship_horn": "ship_horn",             # un barco se mueve
	"torpedo": "torpedo",                 # ataca la lancha torpedera
	"splash": "splash",                   # le dan a un barco
	"unit_sunk": "unit_sunk",             # cae un barco
	"unit_downed": "unit_downed",         # cae un aparato
	# ── La Tormenta ──
	"storm_warning": "storm_warning",     # fase Aviso: sirena lejana (sintesis)
	"storm_thunder": "storm_thunder",     # fase Tormenta: trueno (sintesis)
	"tithe_demanded": "tithe_demanded",   # fase Diezmo: campana
	"tithe_collected": "tithe_collected", # tithe_resolved: se lo llevaron (monedas)
	"tithe_repelled": "tithe_repelled",   # tithe_resolved: no se llevaron nada
	# ── Comida (rama comida-granja-recoger; solo si la senal existe) ──
	"collect": "collect",                 # production_collected: recoger produccion
	"harvest": "harvest",                 # production_collected con comida: cosecha
}

## Ganancia por clip (dB), por NOMBRE DE FICHERO: una clave que reuse el clip de
## otra se lleva su misma ganancia. Los efectos vienen masterizados casi a
## 0 dBFS (era_up pasa de 0 y recorta) y sonaban ~15 dB por encima de la musica
## (diagnostico de jugabilidad, bug 4: el volumen inicial era demasiado alto). Se atenuan aqui en vez de
## reescribir los ficheros: los clics suenan en cada boton y van los mas bajos.
## Los jingles de saxo vienen ~9 dB por debajo de los de acero: bajan menos.
const SFX_GAIN_DB := {
	"era_up": -11.0,
	"ui_click": -13.0,
	"ui_toggle": -15.0,
	"build_place": -8.0,
	"event_danger": -8.0,
	"milestone": -8.0,
	"combat_start": -9.0,
	"combat_hit": -13.0,
	"combat_unit_lost": -14.0,
	"combat_victory": -4.0,
	"combat_defeat": -4.0,
	"expedition_start": -9.0,
	"expedition_return": -4.0,
	"audit_summoned": -6.0,
	"storm_halted": -9.0,
	"rank_up": -10.0,
	# Los sintetizados vienen a -3 dBFS de pico. Los de movimiento, mas bajos:
	# suenan en casi cada turno.
	"shot_rifle": -12.0,
	"shot_cannon": -10.0,
	"tank_fire": -10.0,
	"tank_engine": -16.0,
	"plane_prop": -15.0,
	"plane_strafe": -12.0,
	"bomb_drop": -10.0,
	"airship_drone": -17.0,
	"ship_horn": -16.0,
	"torpedo": -10.0,
	"splash": -14.0,
	"unit_sunk": -11.0,
	"unit_downed": -11.0,
	"storm_warning": -9.0,
	"storm_thunder": -8.0,
	"tithe_demanded": -7.0,
	"tithe_collected": -3.0,
	"tithe_repelled": -9.0,
	"collect": -3.0,
	"harvest": -12.0,
}
## Lo que no esta en SFX_GAIN_DB: todos los efectos se bajan algo.
const SFX_DEFAULT_GAIN_DB := -6.0

## Disparo de cada tipo de unidad (CombatUnit.unit_id). Un tipo que no este aqui
## suena por su dominio (ATTACK_SFX_BY_DOMAIN) y, si tampoco, con `combat_hit`.
const ATTACK_SFX := {
	"infantry": "shot_rifle",
	"artillery": "shot_cannon",
	"vehicle": "tank_fire",
	"torpedo_boat": "torpedo",
	"gunboat": "shot_cannon",
	"dreadnought": "shot_cannon",
	"fighter": "plane_strafe",
	"bomber": "bomb_drop",
	"airship": "bomb_drop",
}
const ATTACK_SFX_BY_DOMAIN := {
	"land": "combat_hit",
	"sea": "shot_cannon",
	"air": "plane_strafe",
}
## Movimiento: solo lo que lleva motor. La infanteria y la artilleria se mueven
## en silencio (a pie no merece un sonido por turno).
const MOVE_SFX := {
	"vehicle": "tank_engine",
	"fighter": "plane_prop",
	"bomber": "plane_prop",
	"airship": "airship_drone",
}
const MOVE_SFX_BY_DOMAIN := {
	"sea": "ship_horn",
	"air": "plane_prop",
}
## Caida segun el medio: un barco se hunde, un aparato se estrella; en tierra,
## el estallido de siempre.
const DEATH_SFX_BY_DOMAIN := {
	"land": "combat_unit_lost",
	"sea": "unit_sunk",
	"air": "unit_downed",
}
## Lo que suena ademas del disparo segun a quien le dan (solo al agua).
const IMPACT_SFX_BY_DOMAIN := {
	"sea": "splash",
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
var _ambient_players: Dictionary = {}  # ambient key → AudioStreamPlayer
var _ambient_tweens: Dictionary = {}   # ambient key → Tween del fundido en curso
var _ambient_key: String = ""          # el bucle que deberia sonar ("" = ninguno)
var _storm_phase: int = -1             # ultima fase de la Tormenta oida (-1 = ninguna)
var _night: bool = false               # DayClock: es de noche (fase NIGHT)
var _board_open: bool = false          # hay un tablero de combate abierto (ambiente de costa)
var _hooked_buttons: Dictionary = {}   # instance_id → true: botones ya enganchados
var _current_music_key: String = ""
var _music_before_combat: String = ""  # what was playing when the first encounter opened
var _combat_session: int = 0           # bumps per encounter_started; guards the deferred restore

func _ready() -> void:
	# La musica sigue sonando con el juego en pausa (menu principal y de pausa):
	# un AudioStreamPlayer pausado corta la pista. Los SFX no molestan: con el
	# arbol parado nadie emite las senales que los disparan.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_build_players()
	_load_manifest(MUSIC_MANIFEST, MUSIC_DIR)
	_load_manifest(AMBIENT_MANIFEST, AMBIENT_DIR)
	_make_ambient_loop()
	_load_manifest(SFX_MANIFEST, SFX_DIR)
	_apply_volumes()
	_connect_events()
	_hook_ui_sounds()

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

	for key in AMBIENT_MANIFEST:
		var a := AudioStreamPlayer.new()
		a.bus = BUS_AMBIENT
		a.volume_db = AMBIENT_SILENT_DB
		a.finished.connect(_on_ambient_finished.bind(String(key)))
		add_child(a)
		_ambient_players[key] = a

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

## Los bucles de ambiente se marcan en bucle aqui, sin depender de como los
## importe el editor (el reinicio en `finished` queda de red por si acaso).
func _make_ambient_loop() -> void:
	for key in AMBIENT_MANIFEST:
		var stream: AudioStream = _streams.get(key)
		if stream == null:
			continue
		if stream is AudioStreamWAV:
			var wav := stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_end = wav.data.size() / (4 if wav.stereo else 2)
		elif "loop" in stream:
			stream.set("loop", true)

# ── Volume control (public — wire to a settings UI later) ─────────────

func _apply_volumes() -> void:
	_set_bus_volume("Master", GameConfig.audio_master_volume)
	_apply_music_bus()
	_set_bus_volume(BUS_SFX, GameConfig.audio_sfx_volume)
	_set_bus_volume(BUS_AMBIENT, GameConfig.audio_ambient_volume)

func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var v := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, v <= 0.0)
	AudioServer.set_bus_volume_db(idx, slider_to_db(v))

## Curva perceptual del deslizador: dB = linear_to_db(v * v). Con la lineal de
## antes, del 100 % al 50 % solo bajaban 6 dB y el deslizador "no hacia nada"
## hasta el ultimo tramo; asi el 50 % baja 12 dB y el 25 %, 24. El rango sigue
## siendo 0..1, asi que los settings.cfg guardados siguen valiendo. 0 = silencio.
static func slider_to_db(v: float) -> float:
	var c := clampf(v, 0.0, 1.0)
	if c <= 0.0:
		return -80.0
	return maxf(-80.0, linear_to_db(c * c))

## Ganancia fija de un efecto (dB), segun su fichero.
func sfx_gain_db(key: String) -> float:
	var file: String = String(SFX_MANIFEST.get(key, key))
	return float(SFX_GAIN_DB.get(file, SFX_DEFAULT_GAIN_DB))

func set_music_volume(linear: float) -> void:
	GameConfig.audio_music_volume = clampf(linear, 0.0, 1.0)
	_apply_music_bus()

## The Music bus obeys the volume slider AND the on/off switch: with music off
## the bus stays muted whatever the slider says.
func _apply_music_bus() -> void:
	_set_bus_volume(BUS_MUSIC, GameConfig.audio_music_volume if GameConfig.audio_music_enabled else 0.0)

# ── Music on/off (the owner found it invasive: it has to be one click away) ──

## Switches music on or off, persists it and tells the UI. Off stops both music
## players and mutes the bus; the track the game WANTS keeps being tracked
## (era changes, combat), so switching back on resumes the right one instead of
## whatever was playing when it was muted. SFX and ambience are untouched.
func set_music_enabled(enabled: bool) -> void:
	if GameConfig.audio_music_enabled == enabled:
		return
	GameConfig.audio_music_enabled = enabled
	GameConfig.save_user_settings()
	_apply_music_bus()
	if enabled:
		var wanted := _current_music_key
		_current_music_key = ""
		if not wanted.is_empty():
			play_music(wanted)
	else:
		for m in _music_players:
			m.stop()
	EventBus.music_toggled.emit(enabled)

func toggle_music() -> void:
	set_music_enabled(not GameConfig.audio_music_enabled)

func is_music_enabled() -> bool:
	return GameConfig.audio_music_enabled

## True while any music player is actually sounding. For tests and probes.
func is_music_playing() -> bool:
	for m in _music_players:
		if m.playing:
			return true
	return false

## The track the game currently wants (plays or would play with music on).
func get_music_key() -> String:
	return _current_music_key

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
	p.volume_db = sfx_gain_db(key)
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
## With music switched off only the wanted key is recorded: nothing starts, so
## an era change or a combat cross-fade can never turn music back on by itself.
func play_music(key: String) -> void:
	if key == _current_music_key:
		return
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		return
	if not GameConfig.audio_music_enabled:
		_current_music_key = key
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

## Arranca el ambiente que toca segun la fase de la Tormenta (dia o tormenta).
func start_ambient() -> void:
	set_ambient(_ambient_for_phase(_storm_phase, _night, _board_open))

## Vuelve a elegir el bucle con lo que se sabe ahora (si ya sonaba alguno).
func _refresh_ambient() -> void:
	if not _ambient_key.is_empty():
		set_ambient(_ambient_for_phase(_storm_phase, _night, _board_open))

## Funde el ambiente hacia `key` ("day", "storm" o "" para silencio). Solo hay
## dos reproductores y solo los dos suenan durante el fundido. Si falta el
## fichero de `key`, el otro se apaga igual y no suena nada (sin error).
func set_ambient(key: String) -> void:
	var same := key == _ambient_key
	_ambient_key = key
	for k in _ambient_players:
		var p: AudioStreamPlayer = _ambient_players[k]
		if k == key:
			var stream: AudioStream = _streams.get(k)
			if stream == null:
				continue
			if same and p.playing:
				continue
			if not p.playing:
				p.stream = stream
				p.volume_db = AMBIENT_SILENT_DB
				p.play()
			_fade_ambient(String(k), float(AMBIENT_GAIN_DB.get(k, -4.0)), false)
		elif p.playing:
			_fade_ambient(String(k), AMBIENT_SILENT_DB, true)

## The ambience loop wanted right now ("" = none). For tests and probes.
func get_ambient_key() -> String:
	return _ambient_key

func _fade_ambient(key: String, target_db: float, stop_after: bool) -> void:
	var p: AudioStreamPlayer = _ambient_players[key]
	var old: Tween = _ambient_tweens.get(key)
	if old != null and old.is_valid():
		old.kill()
	var tw := create_tween()
	tw.tween_property(p, "volume_db", target_db, AMBIENT_FADE_SECONDS)
	if stop_after:
		tw.tween_callback(func() -> void:
			if _ambient_key != key:
				p.stop())
	_ambient_tweens[key] = tw

## Que bucle toca. La Tormenta manda sobre todo: la ceniza trae el viento y no
## se va hasta que vuelve la calma (el Aviso aun no cuenta), haya tablero o no
## (la defensa del Diezmo se pelea bajo la lluvia). Sin Tormenta, con un tablero
## abierto, la costa; si no, de noche los grillos y el resto del dia (alba y
## ocaso incluidos), olas y pajaros.
func _ambient_for_phase(phase: int, night: bool = false, board: bool = false) -> String:
	if phase == StormCycle.Phase.ASH or phase == StormCycle.Phase.STORM \
			or phase == StormCycle.Phase.TITHE:
		return AMBIENT_STORM
	if board:
		return AMBIENT_COAST
	return AMBIENT_NIGHT if night else AMBIENT_DAY

func stop_music() -> void:
	_current_music_key = ""
	for m in _music_players:
		m.stop()

## Silences every voice before the engine tears the ObjectDB down. A track still
## playing at quit keeps its Ogg playback alive past the audio server, and Godot
## reports leaked instances at exit — only sometimes, because it is a race with
## the audio thread. Autoloads receive _exit_tree on quit, so this is the hook.
## The key is cleared first so the loop keep-alive cannot restart a player that
## is being shut down; the streams are dropped so the resources can be freed.
func _exit_tree() -> void:
	_current_music_key = ""
	for m in _music_players:
		m.stop()
		m.stream = null
	for p in _sfx_players:
		p.stop()
		p.stream = null
	_ambient_key = ""
	for k in _ambient_players:
		var a: AudioStreamPlayer = _ambient_players[k]
		a.stop()
		a.stream = null
	_streams.clear()

# ── Loop keep-alive (in case the imported clip isn't flagged as looping) ──

func _on_music_finished(player: AudioStreamPlayer) -> void:
	# Only the active player (index 0) loops; the fading-out one is left stopped.
	if player == _music_players[0] and not _current_music_key.is_empty() and GameConfig.audio_music_enabled:
		player.play()

func _on_ambient_finished(key: String) -> void:
	var p: AudioStreamPlayer = _ambient_players[key]
	if key == _ambient_key and p.stream != null:
		p.play()

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
	EventBus.unit_moved.connect(_on_unit_moved)
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.encounter_ended.connect(_on_encounter_ended)
	EventBus.encounter_closed.connect(_on_encounter_closed)
	EventBus.expedition_started.connect(_on_expedition_started)
	EventBus.expedition_ended.connect(_on_expedition_ended)
	EventBus.governor_rank_up.connect(_on_rank_up)
	# Final Audit.
	EventBus.final_audit_summoned.connect(_on_final_audit_summoned)
	EventBus.storm_halted_forever.connect(_on_storm_halted_forever)
	# Volverse el Imperio: una isla tomada suena como un ascenso (sin sonido nuevo).
	EventBus.island_conquered.connect(func(_i): play_sfx("rank_up"))
	# La Tormenta: el ambiente sigue a la fase y cada cambio relevante suena.
	EventBus.storm_phase_changed.connect(_on_storm_phase_changed)
	# Dia y noche (DayClock): de noche cambia el ambiente, nada mas.
	EventBus.day_phase_changed.connect(_on_day_phase_changed)
	EventBus.tithe_resolved.connect(_on_tithe_resolved)
	# Recoger produccion (y la cosecha de la Granja).
	EventBus.production_collected.connect(_on_production_collected)
	# Encargos (feat/encargos): entregar uno suena como un hito pequeno.
	EventBus.contract_delivered.connect(_on_contract_delivered)

func _on_contract_delivered(_source = null, _contract = null, _reward = null) -> void:
	play_sfx("milestone")

func _on_building_placed(_data: Resource, _cell: Vector2i) -> void:
	play_sfx("build_place")

func _on_construction_completed(_node: Node) -> void:
	play_sfx("build_complete")

func _on_upgrade_completed(_node: Node, _level: int) -> void:
	play_sfx("upgrade_complete")

func _on_demolished(_node: Node, _cell: Vector2i) -> void:
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

func _on_process_completed(_node: Node, _id: String) -> void:
	play_sfx("process_done")

func _on_mining_completed(_node: Node, _id: String) -> void:
	play_sfx("mining_done")

func _on_unit_trained(_id: String) -> void:
	play_sfx("unit_ready")

func _on_insufficient(_res: String, _required: int, _available: int) -> void:
	play_sfx("insufficient")

func _on_game_started() -> void:
	# La fase se lee del servicio: una partida guardada en plena Tormenta vuelve
	# con viento, y una nueva empieza de dia. Sin sonido de cambio de fase.
	_storm_phase = _current_storm_phase()
	_night = _current_is_night()
	_board_open = CombatManager.is_board_open()
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
	_board_open = true
	_refresh_ambient()

## Cerrado el tablero vuelve el ambiente de la isla, salvo que se haya abierto
## otro detras (la oleada siguiente del asedio): se pregunta a CombatManager.
func _on_encounter_closed() -> void:
	_board_open = CombatManager.is_board_open()
	_refresh_ambient()

## El disparo segun quien ataca, y el agua si le dan a un barco. Las unidades se
## leen del tablero abierto; si no se encuentran (una pelea resuelta a ciegas),
## suena el golpe de siempre.
func _on_unit_attacked(attacker_uid: int, target_uid: int, _damage: int) -> void:
	var attacker := _board_unit(attacker_uid)
	if attacker == null:
		play_sfx("combat_hit")
	else:
		play_sfx(attack_sfx_for(attacker.unit_id, attacker.domain()))
	var target := _board_unit(target_uid)
	if target != null:
		var impact := impact_sfx_for(target.domain())
		if not impact.is_empty():
			play_sfx(impact)

func _on_unit_moved(unit_uid: int, _from: Vector2i, _to: Vector2i) -> void:
	var unit := _board_unit(unit_uid)
	if unit == null:
		return
	var key := move_sfx_for(unit.unit_id, unit.domain())
	if not key.is_empty():
		play_sfx(key)

func _on_unit_died(unit_uid: int, _side: int) -> void:
	var unit := _board_unit(unit_uid)
	play_sfx(death_sfx_for(unit.domain() if unit != null else "land"))

func _board_unit(uid: int) -> CombatUnit:
	return CombatManager.get_unit(uid)

## Clave del disparo de un tipo de unidad. Puro: se prueba sin tablero.
func attack_sfx_for(unit_id: String, domain: String) -> String:
	if ATTACK_SFX.has(unit_id):
		return String(ATTACK_SFX[unit_id])
	return String(ATTACK_SFX_BY_DOMAIN.get(domain, "combat_hit"))

## Clave del movimiento ("" = se mueve sin sonido).
func move_sfx_for(unit_id: String, domain: String) -> String:
	if MOVE_SFX.has(unit_id):
		return String(MOVE_SFX[unit_id])
	return String(MOVE_SFX_BY_DOMAIN.get(domain, ""))

func death_sfx_for(domain: String) -> String:
	return String(DEATH_SFX_BY_DOMAIN.get(domain, "combat_unit_lost"))

## Lo que suena encima del disparo segun el medio del blanco ("" = nada).
func impact_sfx_for(domain: String) -> String:
	return String(IMPACT_SFX_BY_DOMAIN.get(domain, ""))

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

func _on_rank_up(_rank: int, _rewards: Dictionary) -> void:
	play_sfx("rank_up")

func _on_final_audit_summoned(_a = null, _b = null, _c = null) -> void:
	play_sfx("audit_summoned")

func _on_storm_halted_forever(_a = null, _b = null, _c = null) -> void:
	play_sfx("storm_halted")

# ── La Tormenta ──────────────────────────────────────────────────────

## De noche segun DayClock (con el ciclo apagado, siempre de dia).
func _current_is_night() -> bool:
	return DayClock.is_night()

## Al cambiar la fase del dia solo se elige otro bucle; si la Tormenta esta
## encima, sigue mandando ella. Sin sonido propio.
func _on_day_phase_changed(phase = 0, _hour = 0.0) -> void:
	_night = int(phase) == DayCycle.Phase.NIGHT
	_refresh_ambient()

func _current_storm_phase() -> int:
	return StormManager.get_phase()

## Ambiente al dia con la fase, y un sonido por cada cambio que importa: el
## Aviso (sirena lejana), la Tormenta encima (trueno) y el Diezmo (campana). La
## ceniza no suena aparte: la anuncia el viento que entra. Repetir la fase en la
## que ya se esta (p. ej. CALM tras parar la Tormenta para siempre) no suena.
func _on_storm_phase_changed(phase: int = 0, _seconds_left: float = 0.0) -> void:
	var previous := _storm_phase
	_storm_phase = phase
	_refresh_ambient()
	if phase == previous:
		return
	match phase:
		StormCycle.Phase.WARNING:
			play_sfx("storm_warning")
		StormCycle.Phase.STORM:
			play_sfx("storm_thunder")
		StormCycle.Phase.TITHE:
			play_sfx("tithe_demanded")

## `paid` es true cuando NO se llevaron nada (repelido, o un modo sin Diezmo) y
## false cuando cobraron (`taken` dice que). Tras un tablero ganado la fanfarria
## de victoria ya ha sonado: el repelido no se le pone encima.
func _on_tithe_resolved(paid = true, taken = {}) -> void:
	var got: Dictionary = taken if taken is Dictionary else {}
	if not bool(paid) or not got.is_empty():
		play_sfx("tithe_collected")
		return
	if _played_within("combat_victory", TITHE_AFTER_VICTORY_MSEC):
		return
	play_sfx("tithe_repelled")

## True si `key` sono hace menos de `msec`.
func _played_within(key: String, msec: int) -> bool:
	if not _sfx_last_msec.has(key):
		return false
	return Time.get_ticks_msec() - int(_sfx_last_msec[key]) < msec

# ── Recoger y cosechar ───────────────────────────────────────────────

## Recoger lo de un edificio; si lo recogido es comida, es la cosecha de la
## Granja. "Recoger todo" emite una vez por edificio en el mismo frame: el
## limite de rafaga deja un solo sonido.
func _on_production_collected(_node = null, collected = null, _c = null) -> void:
	var got: Dictionary = collected if collected is Dictionary else {}
	play_sfx("harvest" if got.has("food") else "collect")

# ── UI: clic en todos los botones, sin tocar cada panel ──────────────

## Engancha cada BaseButton (y cada TabBar) que entre al arbol, y los que ya
## esten. Un boton con la meta UI_SILENT_META no suena.
func _hook_ui_sounds() -> void:
	get_tree().node_added.connect(_on_node_added_for_ui)
	_hook_tree.call_deferred(get_tree().root)

func _hook_tree(node: Node) -> void:
	_on_node_added_for_ui(node)
	for child in node.get_children(true):
		_hook_tree(child)

func _on_node_added_for_ui(node: Node) -> void:
	if not (node is BaseButton or node is TabBar):
		return
	var id := node.get_instance_id()
	if _hooked_buttons.has(id):
		return
	# Un boton que sale y vuelve a entrar (reparentado) conserva su conexion: por
	# eso se recuerda por id y no se vuelve a enganchar.
	if _hooked_buttons.size() > 4096:
		_prune_hooked_buttons()
	_hooked_buttons[id] = true
	if node is TabBar:
		(node as TabBar).tab_clicked.connect(_on_ui_tab_clicked.bind(node))
	else:
		(node as BaseButton).pressed.connect(_on_ui_button_pressed.bind(node))

## Olvida los botones ya liberados (los id no se reutilizan).
func _prune_hooked_buttons() -> void:
	for id in _hooked_buttons.keys():
		if not is_instance_id_valid(int(id)):
			_hooked_buttons.erase(id)

## Interruptores y casillas suenan distinto (mas bajo) que un boton normal.
func ui_sound_for(btn: BaseButton) -> String:
	if btn.toggle_mode or btn is CheckBox or btn is CheckButton:
		return "ui_toggle"
	return "ui_click"

func _on_ui_button_pressed(btn: BaseButton) -> void:
	if not is_instance_valid(btn) or btn.has_meta(UI_SILENT_META):
		return
	play_sfx(ui_sound_for(btn))

func _on_ui_tab_clicked(_tab: int, bar: TabBar) -> void:
	if not is_instance_valid(bar) or bar.has_meta(UI_SILENT_META):
		return
	play_sfx("ui_toggle")

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
