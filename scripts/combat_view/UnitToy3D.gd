extends Node3D
## Una unidad de juguete en el tablero 3D: su modelo horneado, la barra de vida
## encima, las marcas (jefe, dotacion de torre, en guardia) y las animaciones del
## "flow" (saltitos al andar, anticipacion, retroceso, sacudida, caida).
##
## Solo VISTA: no sabe de reglas ni lee el modelo. Board3D le dice que hacer con
## lo que ya paso (los eventos de Encounter que CombatManager publica) y le
## pasa la vida que tiene que ensenar. Todo se anima con tweens: nada de
## `_process`, ninguna luz propia, ningun material propio (el del bando es
## compartido, UnitModels3D).
##
## Jerarquia: self (casilla, giro) > _lift (altura del dominio, vaiven) >
## _body (saltos, retrocesos, inclinacion) > modelo. La barra cuelga de _lift,
## asi no tiembla con los golpes.

const Layout := preload("res://scripts/combat_view/BoardLayout3D.gd")
const Models := preload("res://scripts/combat_view/UnitModels3D.gd")

const HOP_HEIGHT := 0.38
const BAR_PX := Vector2i(64, 9)
const BAR_PIXEL := 0.022
## Las piezas horneadas miden 1,5 m de peana; en la casilla de 2 m se ven mejor
## algo mayores (la escala del modelo, no de la casilla).
const MODEL_SCALE := 1.22
const BAR_GAP := 0.32
const SPENT_ALPHA := 0.45

var uid: int = -1
var unit_id: String = ""
var side: int = 0
var domain: String = "land"
var max_hp: int = 1
var shown_hp: int = 1
var is_boss := false
var is_crew := false
var alive := true

var _lift: Node3D
var _body: Node3D
var _model: Node3D
var _bar: Node3D
var _bar_bg: Sprite3D
var _bar_fill: Sprite3D
var _guard: MeshInstance3D
## Aros en el suelo: rojo = se le puede pegar, laton = es su turno. Se ven aunque
## la pieza tape su casilla (la marca de la casilla queda debajo).
var _target_ring: MeshInstance3D
var _active_ring: MeshInstance3D
var _ring_pulse: Tween
var _muzzle_local := Vector3(0, 0.6, 0.8)
var _top := 1.1
var _bob: Tween

static var _bar_tex: Texture2D = null
static var _guard_mesh: Mesh = null
static var _guard_mat: Material = null
static var _ring_mats: Dictionary = {}
static var _shadow_mat: Material = null

## `info`: uid, unit_id, side, hp, max_hp, domain, boss, crew, team_color.
func setup(info: Dictionary) -> void:
	uid = int(info.get("uid", -1))
	unit_id = String(info.get("unit_id", ""))
	side = int(info.get("side", 0))
	domain = String(info.get("domain", "land"))
	max_hp = maxi(1, int(info.get("max_hp", 1)))
	shown_hp = int(info.get("hp", max_hp))
	is_boss = bool(info.get("boss", false))
	is_crew = bool(info.get("crew", false))
	name = "Unit_%d" % uid

	_lift = Node3D.new()
	_lift.name = "Lift"
	_lift.position.y = Layout.domain_height(domain)
	add_child(_lift)
	_body = Node3D.new()
	_body.name = "Body"
	_lift.add_child(_body)

	var team_color: Color = info.get("team_color", Color.WHITE)
	_model = Models.instantiate(unit_id, side, team_color)
	_model.name = "Model"
	_model.scale = Vector3.ONE * MODEL_SCALE
	_body.add_child(_model)
	var muzzle := _model.get_node_or_null("Muzzle") as Node3D
	if muzzle != null:
		_muzzle_local = muzzle.position * MODEL_SCALE
	var top := _model.get_node_or_null("Top") as Node3D
	if top != null:
		_top = top.position.y * MODEL_SCALE

	if is_boss:
		# El jefe: algo mas grande y con su estandarte (el halo de laton del 2D).
		_body.scale = Vector3.ONE * 1.12
		var mark := Models.instantiate_prop(Models.BOSS_MARK)
		if mark != null:
			mark.name = "BossMark"
			_lift.add_child(mark)
			_top = maxf(_top * 1.12, 1.9)
	if is_crew:
		var nest := Models.instantiate_prop(Models.CREW_NEST)
		if nest != null:
			nest.name = "CrewNest"
			add_child(nest)
	if domain != "land":
		_add_ground_shadow()
		_start_bob()

	_guard = MeshInstance3D.new()
	_guard.name = "Guard"
	_guard.mesh = _guard_ring_mesh()
	_guard.material_override = _guard_material()
	_guard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_guard.position.y = 0.16
	_guard.visible = false
	_lift.add_child(_guard)
	_target_ring = _ring("TargetRing", UITheme.DANGER.lightened(0.15), 1.12)
	_active_ring = _ring("ActiveRing", UITheme.ACCENT.lightened(0.2), 1.0)

	_build_bar()
	set_hp(shown_hp, false)

# ── Barra de vida ────────────────────────────────────────────────────

func _build_bar() -> void:
	_bar = Node3D.new()
	_bar.name = "HealthBar"
	_bar.position.y = _top + BAR_GAP
	_lift.add_child(_bar)
	_bar_bg = _bar_sprite(0)
	_bar_bg.modulate = Color(0.06, 0.05, 0.05, 0.85)
	_bar_bg.scale = Vector3(1.08, 1.5, 1.0)
	_bar.add_child(_bar_bg)
	_bar_fill = _bar_sprite(1)
	_bar.add_child(_bar_fill)

func _bar_sprite(priority: int) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = _bar_texture()
	s.pixel_size = BAR_PIXEL
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.no_depth_test = true
	s.shaded = false
	s.double_sided = true
	s.render_priority = priority
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.region_enabled = true
	s.region_rect = Rect2(0, 0, BAR_PX.x, BAR_PX.y)
	return s

static func _bar_texture() -> Texture2D:
	if _bar_tex == null:
		var img := Image.create(BAR_PX.x, BAR_PX.y, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_bar_tex = ImageTexture.create_from_image(img)
	return _bar_tex

## La vida que ensena la barra (la del modelo puede ir por delante: la vista
## descuenta golpe a golpe a medida que los anima).
func set_hp(hp: int, animate := true) -> void:
	shown_hp = clampi(hp, 0, max_hp)
	var ratio := float(shown_hp) / float(max_hp)
	var color: Color = UITheme.POSITIVE if ratio > 0.5 else (UITheme.WARNING if ratio > 0.25 else UITheme.DANGER)
	color.a = _bar_fill.modulate.a if _bar_fill.modulate.a > 0.0 else 1.0
	_bar_fill.modulate = color
	if animate:
		var tw := create_tween()
		tw.tween_method(_set_bar_ratio, _bar_ratio(), ratio, 0.25).set_ease(Tween.EASE_OUT)
	else:
		_set_bar_ratio(ratio)

func _bar_ratio() -> float:
	return _bar_fill.region_rect.size.x / float(BAR_PX.x)

func _set_bar_ratio(r: float) -> void:
	var w := maxf(0.0, float(BAR_PX.x) * r)
	_bar_fill.region_rect = Rect2(0, 0, w, BAR_PX.y)
	# Centrada por defecto: se corre a la izquierda lo que falta, asi la barra
	# se vacia de derecha a izquierda como la del tablero 2D.
	_bar_fill.offset.x = -(float(BAR_PX.x) - w) * 0.5
	_bar_fill.visible = w > 0.5

func bar_ratio() -> float:
	return _bar_ratio()

## Una unidad que ya actuo apaga su barra (en 2D se apagaba la ficha).
func set_spent(spent: bool) -> void:
	if _bar_fill == null:
		return
	var a := SPENT_ALPHA if spent else 1.0
	_bar_fill.modulate.a = a
	_bar_bg.modulate.a = 0.85 * a

func set_defending(on: bool, animate := true) -> void:
	if _guard.visible == on:
		return
	_guard.visible = on
	if on and animate:
		_guard.scale = Vector3.ONE * 0.4
		var tw := create_tween()
		tw.tween_property(_guard, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func is_defending_shown() -> bool:
	return _guard.visible

## Se le puede pegar ahora: aro rojo que late.
func set_targeted(on: bool) -> void:
	if _target_ring.visible == on:
		return
	_target_ring.visible = on and alive
	_restart_pulse()

## Es su turno: aro de laton.
func set_active(on: bool) -> void:
	if _active_ring.visible == on:
		return
	_active_ring.visible = on and alive
	_restart_pulse()

func is_targeted() -> bool:
	return _target_ring.visible

func _ring(node_name: String, color: Color, s: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = _guard_ring_mesh()
	var key := color.to_html(false)
	if not _ring_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = color
		_ring_mats[key] = m
	mi.material_override = _ring_mats[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.05
	mi.scale = Vector3(s, 1.0, s)
	mi.visible = false
	add_child(mi)
	return mi

## Un solo tween de latido para los aros encendidos; ninguno, si no hay aros.
func _restart_pulse() -> void:
	if _ring_pulse != null:
		_ring_pulse.kill()
		_ring_pulse = null
	if not _target_ring.visible and not _active_ring.visible:
		return
	_ring_pulse = create_tween().set_loops()
	_ring_pulse.tween_method(_pulse_step, 0.0, 1.0, 0.9)

func _pulse_step(t: float) -> void:
	var k := 1.0 + 0.07 * sin(t * TAU)
	_target_ring.scale = Vector3(1.12 * k, 1.0, 1.12 * k)
	_active_ring.scale = Vector3(k, 1.0, k)

# ── Puntos de interes ────────────────────────────────────────────────

## De donde sale el disparo, en el mundo.
func muzzle_world() -> Vector3:
	return _body.global_transform * _muzzle_local

## Donde mirar / donde pega: el centro del cuerpo.
func chest_world() -> Vector3:
	return _lift.global_position + Vector3(0, _top * 0.5, 0)

func top_world() -> Vector3:
	return _lift.global_position + Vector3(0, _top + BAR_GAP + 0.25, 0)

func ground_world() -> Vector3:
	return global_position

# ── Animaciones (todas devuelven el Tween: quien llama decide si espera) ─

## Saltitos de juguete por la ruta, un salto por casilla, mirando a donde va.
func hop_along(points: Array, step_time: float) -> Tween:
	var tw := create_tween()
	var prev: Vector3 = position
	for p in points:
		var a: Vector3 = prev
		var b: Vector3 = p
		if a.distance_to(b) < 0.01:
			continue
		tw.tween_callback(func(): _face_now(b))
		tw.tween_method(func(t: float): _hop_step(a, b, t), 0.0, 1.0, step_time)
		prev = b
	tw.tween_callback(func(): _body.position.y = 0.0)
	return tw

func _hop_step(a: Vector3, b: Vector3, t: float) -> void:
	position = a.lerp(b, t)
	_body.position.y = sin(PI * t) * HOP_HEIGHT
	# Un poco de inclinacion al despegar y al caer: se siente el saltito.
	_body.rotation.x = sin(TAU * t) * 0.12

func _face_now(target: Vector3) -> void:
	rotation.y = Layout.yaw_towards(global_position, target)

## Gira hacia un punto por el camino corto.
func face_to(target: Vector3, time := 0.1) -> Tween:
	var want := Layout.yaw_towards(global_position, target)
	var delta := wrapf(want - rotation.y, -PI, PI)
	var tw := create_tween()
	tw.tween_property(self, "rotation:y", rotation.y + delta, time).set_trans(Tween.TRANS_SINE)
	return tw

## Anticipacion: se echa atras y se encoge antes de golpear.
func windup(time := 0.12) -> Tween:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_body, "position:z", -0.22, time).set_ease(Tween.EASE_OUT)
	tw.tween_property(_body, "rotation:x", -0.16, time).set_ease(Tween.EASE_OUT)
	tw.tween_property(_body, "scale:y", _body.scale.x * 0.9, time)
	return tw

## La embestida del cuerpo a cuerpo: sale hacia delante y vuelve.
func lunge(time := 0.1) -> Tween:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_body, "position:z", 0.42, time).set_ease(Tween.EASE_IN)
	tw.tween_property(_body, "rotation:x", 0.14, time)
	tw.tween_property(_body, "scale:y", _body.scale.x, time)
	return tw

## El culatazo de un disparo: atras de golpe.
func recoil(time := 0.08) -> Tween:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_body, "position:z", -0.32, time).set_ease(Tween.EASE_OUT)
	tw.tween_property(_body, "rotation:x", -0.1, time)
	tw.tween_property(_body, "scale:y", _body.scale.x, time)
	return tw

## Vuelta a la postura de reposo.
func settle(time := 0.16) -> Tween:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_body, "position", Vector3.ZERO, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_body, "rotation", Vector3.ZERO, time)
	tw.tween_property(_body, "scale", Vector3.ONE * _body.scale.x, time)
	return tw

## El impacto: sacudida que se apaga y un aplastamiento de juguete.
func hit_shake(time := 0.22) -> Tween:
	var base := _body.scale.x
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(t: float): _body.position.x = sin(t * 38.0) * 0.12 * (1.0 - t), 0.0, 1.0, time)
	_body.scale = Vector3(base * 1.12, base * 0.82, base * 1.12)
	tw.tween_property(_body, "scale", Vector3.ONE * base, time).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func(): _body.position.x = 0.0)
	return tw

## La caida: se vuelca de lado, se hunde en el suelo y desaparece.
func die(time := 0.5) -> Tween:
	alive = false
	_bar.visible = false
	_guard.visible = false
	set_targeted(false)
	set_active(false)
	if _bob != null:
		_bob.kill()
	var tw := create_tween()
	tw.tween_property(_body, "rotation:z", deg_to_rad(88.0) * (1.0 if uid % 2 == 0 else -1.0), time * 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_body, "position:y", 0.12, time * 0.45)
	tw.tween_interval(time * 0.15)
	tw.tween_property(_body, "position:y", -1.2, time * 0.4).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): visible = false)
	return tw

## Sin animar: la unidad ya no esta (reconciliacion con el modelo).
func remove_now() -> void:
	alive = false
	visible = false

# ── Dominios futuros ─────────────────────────────────────────────────

## Sombra en el suelo de lo que no apoya (aire) o flota (mar): sin ella, una
## pieza en el aire no se sabe en que casilla esta.
func _add_ground_shadow() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "GroundShadow"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.7
	cyl.bottom_radius = 0.7
	cyl.height = 0.02
	cyl.radial_segments = 12
	cyl.rings = 1
	mi.mesh = cyl
	if _shadow_mat == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0, 0, 0, 0.35)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shadow_mat = m
	mi.material_override = _shadow_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.y = 0.03
	add_child(mi)

func _start_bob() -> void:
	_bob = create_tween().set_loops()
	var h := _lift.position.y
	_bob.tween_property(_lift, "position:y", h + 0.12, 1.1).set_trans(Tween.TRANS_SINE)
	_bob.tween_property(_lift, "position:y", h, 1.1).set_trans(Tween.TRANS_SINE)

# ── Recursos compartidos ─────────────────────────────────────────────

## El aro de "en guardia": laton, alrededor de la peana. Una malla para todos.
static func _guard_ring_mesh() -> Mesh:
	if _guard_mesh == null:
		var t := TorusMesh.new()
		t.inner_radius = 0.82
		t.outer_radius = 0.95
		t.rings = 16
		t.ring_segments = 4
		_guard_mesh = t
	return _guard_mesh

static func _guard_material() -> Material:
	if _guard_mat == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = UITheme.INFO.lightened(0.25)
		_guard_mat = m
	return _guard_mat
