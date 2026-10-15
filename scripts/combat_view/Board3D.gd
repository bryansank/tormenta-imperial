extends Node3D
## El tablero 3D del combate (docs/15 §3, "El tablero 3D"): la maqueta de 8x8,
## las unidades de juguete, la camara y la cola de animaciones del "flow".
##
## Es VISTA pura, como el tablero 2D de BattleScreen. No decide nada: cuando
## llega a sus manos, el modelo (Encounter) ya movio, ya pego, ya mato. Lo que
## hace es CONTARLO a su ritmo. BattleScreen le pasa los eventos que
## CombatManager publica en el EventBus (movido, ataco, murio, en guardia,
## turno) y aqui se encolan y se animan uno detras de otro: la ruta casilla a
## casilla con saltitos, la anticipacion del golpe, el proyectil, el impacto con
## sacudida y numero, la caida. Mientras la cola no se vacie el tablero esta
## "ocupado" (`is_busy()`): BattleScreen no deja actuar al jugador ni saca el
## parte, para que nunca se juegue sobre lo que aun no se ha visto. Al vaciarse
## se reconcilia con el modelo (por si algo no llego a animarse) y emite `idle`.
##
## Rendimiento ("en una papa"): una luz direccional para todo (sombra solo si la
## calidad lo permite), un terreno de una malla, las marcas de casilla en una
## MultiMesh, unidades de 400-600 triangulos con los materiales compartidos, y
## todo animado con tweens. Nada de `_process`.

signal idle()
## Un evento de la cola empieza a animarse (sondas y pruebas: saber que se ve).
signal event_played(ev: Dictionary)

const Layout := preload("res://scripts/combat_view/BoardLayout3D.gd")
const Terrain := preload("res://scripts/combat_view/BoardTerrain3D.gd")
const UnitToy := preload("res://scripts/combat_view/UnitToy3D.gd")
const MARKS_SHADER := preload("res://scripts/combat_view/board_marks.gdshader")

enum Mark { NONE, MOVE, TARGET, ACTIVE, HOVER }

## Tiempos base (segundos). La cola los acorta si se acumula trabajo.
const MOVE_STEP := 0.14
const FACE_TIME := 0.1
const WINDUP_TIME := 0.13
const SHELL_TIME := 0.4
const TRACER_TIME := 0.08
const SETTLE_TIME := 0.18
const AFTER_HIT := 0.2
const DEATH_TIME := 0.55
const DEPLOY_TIME := 0.38
const DEPLOY_STAGGER := 0.06

## Camara: picado y giro de la vista isometrica; el giro leve del jugador
## (rueda / pellizco) y cuanto sigue la camara a quien actua.
const CAM_PITCH_DEG := 52.0
const CAM_YAW_DEG := -24.0
const CAM_FOV := 34.0
const ZOOM_MIN := 0.82
const ZOOM_MAX := 1.12
const FOLLOW_WEIGHT := 0.2
const FOLLOW_MAX := 1.1

## La vista frontal (docs/15 §3, "Las dos vistas"): los dos bandos cara a cara,
## los nuestros abajo a la izquierda y la Regencia arriba a la derecha, con la
## camara mas baja y de costado; sin marcas de casilla y con el campo seguido.
## Es la MISMA maqueta, las mismas piezas y la misma cola: solo cambian la
## camara, el suelo y que no se pintan casillas.
const STYLE_BOARD := "board"
const STYLE_FRONT := "front"
const STYLES := [STYLE_FRONT, STYLE_BOARD]
const FRONT_PITCH_DEG := 30.0
const FRONT_YAW_DEG := 60.0
const FRONT_FOV := 30.0
## En el frente las piezas van mas grandes (unidades mas grandes, como en la
## referencia) y las manchas de "puedes ir aqui" son discos en el suelo.
const FRONT_UNIT_SCALE := 1.3

const PLAYER := 0

@onready var _pivot: Node3D = $CamPivot
@onready var _camera: Camera3D = $CamPivot/Camera3D
@onready var _sun: DirectionalLight3D = $Sun
@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _terrain: MeshInstance3D = $Terrain
@onready var _marks: MultiMeshInstance3D = $Marks
@onready var _units_root: Node3D = $Units
@onready var _fx = $Fx

var board := Vector2i(8, 8)
var _encounter = null
var _toys: Dictionary = {}        ## uid -> UnitToy3D
var _cell_of: Dictionary = {}     ## uid -> Vector2i, donde la VISTA la tiene
var _queue: Array = []
var _pumping := false
var _gen := 0
var _active_uid := -1
var _simple := false
var _team_color := Color(0.8, 0.62, 0.25)
## El aspecto del regimiento (RegimentLook.resolve) para nuestras piezas; vacio
## = sin insignia ni pintura. Solo cosmetico.
var _regiment: Dictionary = {}
var _boss_uid := -1
## El escenario de la maqueta (BoardTerrain3D.SCENES): solo decorado.
var _scene := "land"
## "front" o "board" (STYLES). Lo pone BattleScreen con la preferencia.
var _style := STYLE_BOARD
var _seed := 1

var _mark_of: Dictionary = {}     ## cell -> Mark
var _hover := Vector2i(-1, -1)

var _fit_dist := 30.0
var _zoom := 1.0
var _punch := 1.0
var _base_offset := Vector2.ZERO
var _center := Vector3.ZERO
var _safe_margins := Vector4(90, 110, 16, 16)   ## arriba, abajo, izquierda, derecha (px)
var _follow_tween: Tween
var _shake_tween: Tween
var _sway_tween: Tween

func _ready() -> void:
	_camera.fov = _fov()
	_pivot.rotation.y = deg_to_rad(_yaw_deg())
	_build_environment()
	_build_marks_mesh()
	get_viewport().size_changed.connect(_fit)

# ── Montaje ──────────────────────────────────────────────────────────

## Monta la pelea que acaba de abrirse. `opts`: team_color (colonia), boss_uid,
## crew_uids (Dictionary uid -> true), seed, simple (calidad sencilla),
## regiment (aspecto del regimiento: pintura, insignia y estrellas de las nuestras).
func setup(encounter, opts: Dictionary = {}) -> void:
	_gen += 1
	_queue.clear()
	_pumping = false
	_encounter = encounter
	board = encounter.board_size
	_team_color = opts.get("team_color", _team_color)
	_boss_uid = int(opts.get("boss_uid", -1))
	_regiment = opts.get("regiment", {})
	_simple = bool(opts.get("simple", _simple))
	var crews: Dictionary = opts.get("crew_uids", {})
	_fx.simple = _simple
	_fx.clear()
	for child in _units_root.get_children():
		child.queue_free()
	_toys.clear()
	_cell_of.clear()
	_mark_of.clear()
	_active_uid = -1

	_scene = String(opts.get("scene", Terrain.SCENE_LAND))
	_seed = int(opts.get("seed", 1))
	var st := String(opts.get("style", _style))
	_style = st if st in STYLES else STYLE_BOARD
	_build_terrain()
	_layout_marks()

	for unit in encounter.units:
		if not unit.is_alive() or unit.position.x < 0:
			continue
		var toy: Node3D = UnitToy.new()
		_units_root.add_child(toy)
		toy.setup({
			"uid": unit.uid, "unit_id": unit.unit_id, "side": unit.side,
			"hp": unit.hp, "max_hp": unit.max_hp, "domain": unit.domain(),
			"boss": unit.uid == _boss_uid, "crew": crews.has(unit.uid),
			"team_color": _team_color,
			"regiment": _regiment if unit.side == PLAYER else {},
		})
		toy.position = _world_of(unit.position)
		# Cada bando mira al otro: los nuestros al fondo, la Regencia hacia aca.
		toy.rotation.y = PI if unit.side == PLAYER else 0.0
		_toys[unit.uid] = toy
		_cell_of[unit.uid] = unit.position

	_center = Vector3.ZERO
	_pivot.position = _center
	_zoom = 1.0
	_punch = 1.0
	_apply_style_look()
	_place_toys()
	_fit()
	_start_sway()
	push({"e": "deploy"})

## Cambia de vista con la pelea abierta (el selector de la cabecera). No toca
## piezas ni cola: solo suelo, marcas y camara. Rehacer el suelo es una malla.
func set_style(style: String) -> void:
	if not style in STYLES or style == _style:
		return
	_style = style
	if _encounter != null:
		_build_terrain()
	_apply_style_look()
	# Las piezas pasan a sus sitios de la otra vista. BattleScreen solo llama aqui
	# con la cola vacia (_after_board_animations): no se corta ninguna animacion.
	_place_toys()
	_layout_marks()
	_fit()
	_start_sway()

func style() -> String:
	return _style

func is_front() -> bool:
	return _style == STYLE_FRONT

## Donde se dibuja una casilla en esta vista: el centro en el tablero; en el
## frente, su sitio libre (BoardLayout3D.spot_offset), que no parece rejilla.
func _world_of(cell: Vector2i) -> Vector3:
	var p := Layout.cell_to_world(cell, board)
	if is_front():
		p += Layout.spot_offset(cell, _seed)
	return p

## Coloca las piezas quietas en sus sitios de la vista actual y con su tamano.
func _place_toys() -> void:
	for uid in _toys:
		var toy = _toys[uid]
		toy.set_view_scale(FRONT_UNIT_SCALE if is_front() else 1.0)
		if _cell_of.has(uid):
			toy.position = _world_of(_cell_of[uid])

func _build_terrain() -> void:
	_terrain.mesh = Terrain.build(board, _seed, _simple, _scene, is_front())

## Lo que cambia entre las dos vistas ademas del suelo: las marcas de casilla
## (en el frente no hay) y el fondo (en el frente, un cielo de bruma en vez de
## la sala oscura de la mesa de guerra).
func _apply_style_look() -> void:
	# En el frente las marcas siguen, pero como manchas en el suelo (solo los
	# sitios a los que se puede ir; objetivo y turno los dicen los aros).
	_marks.visible = true
	if _marks.multimesh != null:
		_marks.multimesh.mesh = _front_spot_mesh() if is_front() else _tile_mark_mesh
	_camera.fov = _fov()
	if _world_env != null and _world_env.environment != null:
		_world_env.environment.background_color = FRONT_SKY if is_front() else UITheme.BG_DARK.darkened(0.35)

## Bruma del horizonte del frente: el cielo de la paleta, apagado y calido.
const FRONT_SKY := Color(0.55, 0.6, 0.58)

func _pitch_deg() -> float:
	return FRONT_PITCH_DEG if is_front() else CAM_PITCH_DEG

func _yaw_deg() -> float:
	return FRONT_YAW_DEG if is_front() else CAM_YAW_DEG

func _fov() -> float:
	return FRONT_FOV if is_front() else CAM_FOV

## Calidad: sombras del sol solo si la calidad las tiene; polvo fuera en sencilla.
func apply_quality(settings: Dictionary) -> void:
	_sun.shadow_enabled = bool(settings.get("shadows", true))
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 70.0
	_simple = not bool(settings.get("high", true))
	if _fx != null:
		_fx.simple = _simple

func set_safe_margins(top: float, bottom: float, left := 16.0, right := 16.0) -> void:
	_safe_margins = Vector4(top, bottom, left, right)
	_fit()

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = UITheme.BG_DARK.darkened(0.35)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.9, 0.76)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	_world_env.environment = env

# ── Cola de animaciones ──────────────────────────────────────────────

func push(ev: Dictionary) -> void:
	_queue.append(ev)
	if not _pumping:
		_pump()

func is_busy() -> bool:
	return _pumping or not _queue.is_empty()

func queue_size() -> int:
	return _queue.size()

func _pump() -> void:
	_pumping = true
	var gen := _gen
	while not _queue.is_empty():
		var ev: Dictionary = _queue.pop_front()
		event_played.emit(ev)
		await _play(ev)
		if gen != _gen:
			return
	_pumping = false
	_reconcile()
	idle.emit()

## Si hay cola, todo va mas deprisa: la vista nunca se queda muy atras del modelo.
## Con el juego a x2 (GameConfig.combat_pace) todo dura la mitad.
func _tempo() -> float:
	return GameConfig.combat_pace(1.0) / (1.0 + 0.45 * float(clampi(_queue.size(), 0, 5)))

func _play(ev: Dictionary) -> void:
	match String(ev.get("e", "")):
		"deploy":
			await _play_deploy()
		"move":
			await _play_move(int(ev["uid"]), ev["from"], ev["to"])
		"attack":
			await _play_attack(int(ev["attacker"]), int(ev["target"]), int(ev["damage"]))
		"die":
			await _play_die(int(ev["uid"]))
		"defend":
			await _play_defend(int(ev["uid"]))
		"turn":
			_play_turn(int(ev["uid"]))
		_:
			pass

## El despliegue: las piezas caen sobre la maqueta, primero las de la Regencia.
func _play_deploy() -> void:
	var order: Array = _toys.values()
	order.sort_custom(func(a, b): return a.side > b.side if a.side != b.side else a.uid < b.uid)
	var last: Tween = null
	var i := 0
	for toy in order:
		var rest: Vector3 = toy.position
		toy.position = rest + Vector3(0, 3.2, 0)
		toy.scale = Vector3.ONE * 0.6
		var tw: Tween = toy.create_tween()
		tw.tween_interval(GameConfig.combat_pace(DEPLOY_STAGGER) * float(i))
		tw.tween_property(toy, "position", rest, GameConfig.combat_pace(DEPLOY_TIME)).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(toy, "scale", Vector3.ONE, GameConfig.combat_pace(DEPLOY_TIME) * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		last = tw
		i += 1
	if last != null:
		await last.finished

func _play_move(uid: int, from: Vector2i, to: Vector2i) -> void:
	var toy = _toys.get(uid)
	if toy == null or not toy.alive:
		_cell_of[uid] = to
		return
	var start: Vector2i = _cell_of.get(uid, from)
	var route: Array = Layout.path(start, to, _occupied_except(uid), board)
	var points: Array = []
	for i in range(1, route.size()):
		points.append(_world_of(route[i]))
	_cell_of[uid] = to
	_follow(_world_of(to), 0.35)
	var tw: Tween = toy.hop_along(points, MOVE_STEP * _tempo())
	await tw.finished

func _play_attack(attacker: int, target: int, damage: int) -> void:
	var a = _toys.get(attacker)
	var t = _toys.get(target)
	if a == null or t == null or not t.alive:
		if t != null:
			t.set_hp(t.shown_hp - damage, false)
		return
	var k := _tempo()
	var dist := Layout.cell_distance(_cell_of.get(attacker, Vector2i.ZERO), _cell_of.get(target, Vector2i.ZERO))
	_follow((a.global_position + t.global_position) * 0.5, 0.3)
	await a.face_to(t.global_position, FACE_TIME * k).finished
	await a.windup(WINDUP_TIME * k).finished
	match attack_kind(a.unit_id, dist):
		"shell":
			a.recoil()
			_fx.muzzle_flash(a.muzzle_world(), 0.75)
			_punch_zoom(0.95, 0.3)
			await _fx.shell(a.muzzle_world(), t.chest_world(), SHELL_TIME * k).finished
		"melee":
			await a.lunge(0.09 * k).finished
			_fx.muzzle_flash(a.muzzle_world(), 0.45)
			_fx.muzzle_flash(a.muzzle_world() + Vector3(0.3, -0.05, 0), 0.35)
		_:
			a.recoil()
			_fx.muzzle_flash(a.muzzle_world(), 0.6)
			await _fx.tracer(a.muzzle_world(), t.chest_world(), TRACER_TIME * k).finished
	_impact(t, damage)
	a.settle(SETTLE_TIME * k)
	await _wait(AFTER_HIT * k)

## Que animacion de ataque toca: la artilleria tira por elevacion; quien pega a
## una casilla de distancia sin canon, a la bayoneta; el resto, disparo directo.
static func attack_kind(unit_id: String, dist: int) -> String:
	if unit_id == "artillery":
		return "shell"
	if unit_id == "infantry" and dist <= 1:
		return "melee"
	return "shot"

func _impact(t, damage: int) -> void:
	t.hit_shake()
	t.set_hp(t.shown_hp - damage)
	_fx.damage_number(t.top_world(), damage)
	_fx.puff(t.ground_world() + Vector3(0, 0.35, 0))
	_shake_camera(0.18)

func _play_die(uid: int) -> void:
	var toy = _toys.get(uid)
	_cell_of.erase(uid)
	if toy == null or not toy.alive:
		return
	var at: Vector3 = toy.global_position
	var tw: Tween = toy.die(DEATH_TIME * _tempo())
	await tw.finished
	_fx.crater(at)

func _play_defend(uid: int) -> void:
	var toy = _toys.get(uid)
	if toy == null or not toy.alive:
		return
	toy.set_defending(true)
	await _wait(0.25 * _tempo())

func _play_turn(uid: int) -> void:
	var prev = _toys.get(_active_uid)
	if prev != null and prev.alive and _active_uid != uid:
		prev.set_spent(true)
	_active_uid = uid
	var toy = _toys.get(uid)
	if toy == null:
		return
	toy.set_spent(false)
	for other in _toys:
		_toys[other].set_targeted(false)
		_toys[other].set_active(other == uid)
	_set_only_mark(_cell_of.get(uid, Vector2i(-1, -1)), Mark.ACTIVE)
	_follow(toy.global_position, 0.4)

## Las casillas ocupadas segun la vista, menos la de quien se mueve.
func _occupied_except(uid: int) -> Dictionary:
	var out := {}
	for other in _cell_of:
		if other != uid:
			out[_cell_of[other]] = true
	return out

func _wait(seconds: float) -> void:
	await get_tree().create_timer(maxf(0.01, seconds), false).timeout

## Al vaciarse la cola: lo que diga el modelo manda. Si algo no llego a
## animarse (un evento perdido, un tablero reabierto), se coloca sin animar.
func _reconcile() -> void:
	if _encounter == null:
		return
	for unit in _encounter.units:
		var toy = _toys.get(unit.uid)
		if toy == null:
			continue
		if not unit.is_alive():
			if toy.alive:
				toy.remove_now()
				_fx.crater(toy.global_position)
			_cell_of.erase(unit.uid)
			continue
		if _cell_of.get(unit.uid, Vector2i(-99, -99)) != unit.position:
			_cell_of[unit.uid] = unit.position
			toy.position = _world_of(unit.position)
		if toy.shown_hp != unit.hp:
			toy.set_hp(unit.hp, false)
		toy.set_defending(unit.defending, false)
		toy.set_spent(unit.has_acted)

# ── Lectura (BattleScreen, pruebas) ──────────────────────────────────

func toy(uid: int) -> Node3D:
	return _toys.get(uid)

func scene_name() -> String:
	return _scene

func toy_count() -> int:
	return _toys.size()

func shown_cell(uid: int) -> Vector2i:
	return _cell_of.get(uid, Vector2i(-1, -1))

func camera() -> Camera3D:
	return _camera

func mark_at(cell: Vector2i) -> int:
	return int(_mark_of.get(cell, Mark.NONE))

# ── Marcas de casilla ────────────────────────────────────────────────

## Lo que el jugador puede hacer ahora: su unidad, a donde llega, a quien pega.
## `hints`: uid -> ventaja de tipo del atacante contra ese objetivo (+1 / -1).
func show_state(active_uid: int, moves: Array, targets: Array, hints: Dictionary = {}) -> void:
	for uid in _toys:
		_toys[uid].set_targeted(targets.has(uid))
		if targets.has(uid):
			_toys[uid].set_target_hint(int(hints.get(uid, 0)))
		_toys[uid].set_active(uid == active_uid)
	_mark_of.clear()
	for cell in moves:
		_mark_of[cell] = Mark.MOVE
	for uid in targets:
		var c: Vector2i = _cell_of.get(uid, Vector2i(-1, -1))
		if c.x >= 0:
			_mark_of[c] = Mark.TARGET
	var ac: Vector2i = _cell_of.get(active_uid, Vector2i(-1, -1))
	if ac.x >= 0:
		_mark_of[ac] = Mark.ACTIVE
	# En el frente solo se iluminan los sitios a los que ir (manchas); el turno y
	# los objetivos ya los dicen el aro azul, el rojo y la mira.
	if is_front():
		for c in _mark_of.keys():
			if int(_mark_of[c]) != Mark.MOVE:
				_mark_of.erase(c)
	_paint_marks()

func clear_marks() -> void:
	for uid in _toys:
		_toys[uid].set_targeted(false)
	_mark_of.clear()
	_paint_marks()

func set_hover(cell: Vector2i) -> void:
	if is_front():
		cell = Vector2i(-1, -1)
	if cell == _hover:
		return
	_hover = cell
	_paint_marks()

func _set_only_mark(cell: Vector2i, mark: int) -> void:
	_mark_of.clear()
	if cell.x >= 0 and not is_front():
		_mark_of[cell] = mark
	_paint_marks()

func _mark_color(mark: int) -> Color:
	match mark:
		Mark.MOVE:
			return Color(UITheme.INFO.lightened(0.3), 1.0)
		Mark.TARGET:
			return Color(UITheme.DANGER.lightened(0.2), 1.0)
		Mark.ACTIVE:
			return Color(UITheme.ACCENT.lightened(0.2), 1.0)
		Mark.HOVER:
			return Color(1, 1, 1, 0.55)
	return Color(0, 0, 0, 0)

func _build_marks_mesh() -> void:
	# Marco grueso (alfa 1) y relleno tenue (alfa 0.3) en una malla plana.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := (Layout.CELL - 0.16) * 0.5
	var b := 0.16
	var fill := Color(1, 1, 1, 0.3)
	var edge := Color(1, 1, 1, 1)
	_quad(st, Vector2(-h + b, -h + b), Vector2(h - b, h - b), fill)
	_quad(st, Vector2(-h, -h), Vector2(h, -h + b), edge)
	_quad(st, Vector2(-h, h - b), Vector2(h, h), edge)
	_quad(st, Vector2(-h, -h + b), Vector2(-h + b, h - b), edge)
	_quad(st, Vector2(h - b, -h + b), Vector2(h, h - b), edge)
	var mesh := st.commit()
	_tile_mark_mesh = mesh
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	_marks.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = MARKS_SHADER
	_marks.material_override = mat
	_marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

var _tile_mark_mesh: Mesh = null
static var _spot_mesh: Mesh = null

## La mancha del frente: un disco de borde suave (centro tenue, aro intenso), no
## un cuadrado. Misma MultiMesh y mismo shader que las casillas.
static func _front_spot_mesh() -> Mesh:
	if _spot_mesh == null:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var segs := 16
		var r_in := 0.5
		var r_out := 0.72
		for i in segs:
			var a0 := TAU * float(i) / float(segs)
			var a1 := TAU * float(i + 1) / float(segs)
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			for v in [[Vector3.ZERO, 0.22], [d1 * r_in, 0.35], [d0 * r_in, 0.35]]:
				st.set_color(Color(1, 1, 1, v[1]))
				st.set_normal(Vector3.UP)
				st.add_vertex(v[0])
			for v in [[d0 * r_in, 0.9], [d1 * r_in, 0.9], [d1 * r_out, 0.0], [d0 * r_in, 0.9], [d1 * r_out, 0.0], [d0 * r_out, 0.0]]:
				st.set_color(Color(1, 1, 1, v[1]))
				st.set_normal(Vector3.UP)
				st.add_vertex(v[0])
		_spot_mesh = st.commit()
	return _spot_mesh

static func _quad(st: SurfaceTool, a: Vector2, b: Vector2, col: Color) -> void:
	var p := [Vector3(a.x, 0, a.y), Vector3(b.x, 0, a.y), Vector3(b.x, 0, b.y), Vector3(a.x, 0, b.y)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_color(col)
		st.set_normal(Vector3.UP)
		st.add_vertex(p[i])

func _layout_marks() -> void:
	var mm: MultiMesh = _marks.multimesh
	mm.instance_count = board.x * board.y
	for y in board.y:
		for x in board.x:
			var i := y * board.x + x
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, _world_of(Vector2i(x, y)) + Vector3(0, 0.035, 0)))
			mm.set_instance_custom_data(i, Color(0, 0, 0, 0))
	_paint_marks()

func _paint_marks() -> void:
	var mm: MultiMesh = _marks.multimesh
	if mm == null or mm.instance_count != board.x * board.y:
		return
	for y in board.y:
		for x in board.x:
			var cell := Vector2i(x, y)
			var mark: int = int(_mark_of.get(cell, Mark.NONE))
			if mark == Mark.NONE and cell == _hover:
				mark = Mark.HOVER
			mm.set_instance_custom_data(y * board.x + x, _mark_color(mark))

# ── Toque y raton ────────────────────────────────────────────────────

## La casilla bajo un punto de la pantalla (coordenadas del SubViewport). Una
## pieza se toca por su cuerpo, no por el suelo de detras: primero se mira si el
## punto cae sobre alguna unidad, despues el suelo.
func pick_cell(screen: Vector2) -> Vector2i:
	var best := -1
	var best_d := INF
	var radius := _unit_pick_radius()
	for uid in _toys:
		var toy = _toys[uid]
		if not toy.alive or not toy.visible or _camera.is_position_behind(toy.chest_world()):
			continue
		var d := _camera.unproject_position(toy.chest_world()).distance_to(screen)
		if d < radius and d < best_d:
			best = uid
			best_d = d
	if best >= 0:
		return _cell_of.get(best, Vector2i(-1, -1))
	var origin := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return Vector2i(-1, -1)
	var t := -origin.y / dir.y
	if t < 0.0:
		return Vector2i(-1, -1)
	return Layout.world_to_cell(origin + dir * t, board)

## Medio cuerpo de una pieza, en pixeles, a la distancia de la camara.
func _unit_pick_radius() -> float:
	var a := _camera.unproject_position(Vector3.ZERO)
	var b := _camera.unproject_position(Vector3(0.75, 0, 0))
	return maxf(14.0, a.distance_to(b))

## Las coordenadas de pantalla del centro de una casilla (pruebas, sondas).
func cell_screen(cell: Vector2i) -> Vector2:
	return _camera.unproject_position(_world_of(cell))

func unit_screen(uid: int) -> Vector2:
	var toy = _toys.get(uid)
	return _camera.unproject_position(toy.chest_world()) if toy != null else Vector2(-1, -1)

## "Infanteria 80/100" sobre la pieza tocada (con el dedo no hay tooltip).
func inspect(uid: int, text: String) -> void:
	var toy = _toys.get(uid)
	if toy == null or not toy.alive:
		return
	for child in _fx.get_children():
		if child.name.begins_with("InfoLabel"):
			child.queue_free()
	var col: Color = UITheme.POSITIVE.lightened(0.3) if toy.side == PLAYER else UITheme.DANGER.lightened(0.35)
	_fx.info_label(toy.top_world() + Vector3(0, 0.45, 0), text, col)

# ── Camara ───────────────────────────────────────────────────────────

func zoom_by(factor: float) -> void:
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	_apply_camera()

func _apply_camera() -> void:
	var dist := _fit_dist * _zoom * _punch
	var pitch := deg_to_rad(_pitch_deg())
	_camera.position = Vector3(0, sin(pitch), cos(pitch)) * dist
	_camera.rotation = Vector3(-pitch, 0, 0)

## Encaja el tablero (con su peana) en el hueco que dejan la cabecera y los
## botones: busca la distancia y despues corre la imagen para centrarlo.
func _fit() -> void:
	if _camera == null or not is_inside_tree():
		return
	var size: Vector2 = get_viewport().get_visible_rect().size
	if size.x < 8.0 or size.y < 8.0:
		return
	var m := _safe_margins
	var safe := Rect2(m.z, m.x, size.x - m.z - m.w, size.y - m.x - m.y)
	if safe.size.x < 40.0 or safe.size.y < 40.0:
		safe = Rect2(Vector2.ZERO, size)
	var ext := Layout.board_extent(board) * 0.5 + Vector2(0.9, 0.9)
	var pts: Array = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			pts.append(Vector3(sx * ext.x, 0.0, sz * ext.y))
			pts.append(Vector3(sx * ext.x, 1.4, sz * ext.y))
	var saved_zoom := _zoom
	var saved_punch := _punch
	_zoom = 1.0
	_punch = 1.0
	_camera.h_offset = 0.0
	_camera.v_offset = 0.0
	var lo := 8.0
	var hi := 120.0
	for i in 22:
		_fit_dist = (lo + hi) * 0.5
		_apply_camera()
		var r := _projected_rect(pts)
		if r.size.x <= safe.size.x and r.size.y <= safe.size.y:
			hi = _fit_dist
		else:
			lo = _fit_dist
	_fit_dist = hi
	_apply_camera()
	# Centrar en el hueco: se corre la imagen (h/v_offset, en metros a la
	# distancia del pivote), dos pasadas para afinar.
	for i in 2:
		var r := _projected_rect(pts)
		var delta := safe.get_center() - r.get_center()
		var px_per_m := size.y / (2.0 * _fit_dist * tan(deg_to_rad(_fov()) * 0.5))
		_camera.h_offset -= delta.x / px_per_m
		_camera.v_offset += delta.y / px_per_m
	_base_offset = Vector2(_camera.h_offset, _camera.v_offset)
	_zoom = saved_zoom
	_punch = saved_punch
	_apply_camera()

func _projected_rect(pts: Array) -> Rect2:
	var r := Rect2(_camera.unproject_position(pts[0]), Vector2.ZERO)
	for p in pts:
		r = r.expand(_camera.unproject_position(p))
	return r

## La camara se va un poco hacia donde pasa algo, sin perder el tablero.
func _follow(point: Vector3, time: float) -> void:
	var target := _center.lerp(Vector3(point.x, 0, point.z), FOLLOW_WEIGHT)
	var off := target - _center
	if off.length() > FOLLOW_MAX:
		target = _center + off.normalized() * FOLLOW_MAX
	if _follow_tween != null:
		_follow_tween.kill()
	_follow_tween = create_tween()
	_follow_tween.tween_property(_pivot, "position", target, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

## El acercamiento de un disparo gordo: entra y vuelve.
func _punch_zoom(factor: float, time: float) -> void:
	var tw := create_tween()
	tw.tween_method(_set_punch, 1.0, factor, time * 0.4).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_punch, factor, 1.0, time * 0.6).set_ease(Tween.EASE_IN_OUT)

func _set_punch(v: float) -> void:
	_punch = v
	_apply_camera()

## Temblor del impacto: la imagen salta unos centimetros y vuelve.
func _shake_camera(time: float) -> void:
	if _shake_tween != null:
		_shake_tween.kill()
	_shake_tween = create_tween()
	_shake_tween.tween_method(_shake_step, 0.0, 1.0, time)
	_shake_tween.tween_callback(_shake_step.bind(1.0))

func _shake_step(t: float) -> void:
	var amp := 0.14 * (1.0 - t)
	_camera.h_offset = _base_offset.x + sin(t * 47.0) * amp
	_camera.v_offset = _base_offset.y + cos(t * 39.0) * amp * 0.7

## El giro leve de la maqueta en reposo: unos grados, muy despacio. En la
## calidad sencilla no hay: la imagen quieta tambien cuesta menos de mirar.
func _start_sway() -> void:
	if _sway_tween != null:
		_sway_tween.kill()
		_sway_tween = null
	var yaw := deg_to_rad(_yaw_deg())
	_pivot.rotation.y = yaw
	if _simple:
		return
	_sway_tween = create_tween().set_loops()
	_sway_tween.tween_property(_pivot, "rotation:y", yaw + deg_to_rad(2.0), 5.0).set_trans(Tween.TRANS_SINE)
	_sway_tween.tween_property(_pivot, "rotation:y", yaw - deg_to_rad(2.0), 10.0).set_trans(Tween.TRANS_SINE)
	_sway_tween.tween_property(_pivot, "rotation:y", yaw, 5.0).set_trans(Tween.TRANS_SINE)
