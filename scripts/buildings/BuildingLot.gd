extends Node3D
## La parcela de un edificio 3D (docs/03, "Parcela y atrezo"; guia de estilo,
## reglas 1 y 5): el suelo que cubre la huella entera, la sombra de contacto que
## ancla el modelo, el borde oscuro que separa la parcela de la isla, el remate
## de los lados que no dan a calzada y el atrezo del patio.
##
## Cuelga de cada edificio (hijo "Lot", lo pone BuildingPlacer) y esta en el
## grupo "building_fx": ni el hollin de BuildingHealth ni la medida de la cima
## la tocan. La colocacion la decide LotPlan (compartida con la 2D); aqui solo
## se construye la malla:
##
## - "Ground": un plano con la textura de su suelo (una por tipo de suelo y
##   huella, cacheada para todo el mapa).
## - "ContactShadow": un plano con una mancha oscura de borde duro bajo el
##   modelo (sombra de contacto + AO), material unico para todo el mapa.
## - "Props": borde, remate y atrezo en UNA malla con color por vertice
##   (LotMesh): una llamada de dibujo por parcela.
##
## Nada por frame: se reconstruye solo cuando cambia algo que la parcela ve
## (su celda, las calzadas de al lado, la obra o la ruina), por senales.

const Plan := preload("res://scripts/buildings/LotPlan.gd")
const MeshKit := preload("res://scripts/buildings/LotMesh.gd")
const LookRule := preload("res://scripts/buildings/BuildingLook.gd")
const Tone := preload("res://scripts/buildings/ToyTones.gd")

## Alturas de cada capa sobre la isla (separadas lo bastante para no parpadear
## con la camara ortografica). La obra (0.04) y la ruina (0.03) quedan encima.
const Y_GROUND := 0.012
const Y_SHADOW := 0.022
const BORDER_H := 0.034

## Los tonos del atrezo: todos de la paleta de la maqueta (ToyTones -> ToyPalette),
## los mismos que llevan los edificios horneados.
static var WOOD: Color = Tone.of("wood")
static var WOOD_LIGHT: Color = Tone.of("wood_light")
static var DARK_WOOD: Color = Tone.of("wood_dark")
static var IRON: Color = Tone.of("iron")
static var STEEL: Color = Tone.of("steel")
static var RUST: Color = Tone.of("rust")
static var COPPER: Color = Tone.of("copper")
static var BRASS: Color = Tone.of("brass")
static var STONE: Color = Tone.of("stone")
static var TERRACOTTA: Color = Tone.of("terracotta")
static var SACK: Color = Tone.of("sack")
static var LEAF: Color = Tone.of("leaf")
static var GOLD: Color = Tone.of("gold")
static var COAL: Color = Tone.of("coal")
static var OLIVE: Color = Tone.of("olive")
static var WARM: Color = Tone.of("warm")
static var HAZARD: Color = Tone.of("terracotta")
static var BORDER: Color = Tone.of("border")

static var _ground_mats: Dictionary = {}
static var _ground_meshes: Dictionary = {}
static var _shadow_mat: StandardMaterial3D = null
static var _shadow_meshes: Dictionary = {}

var _building: Node3D = null
var _data: BuildingData = null
var _cell := 2.0
var _ground: MeshInstance3D = null
var _shadow: MeshInstance3D = null
var _props: MeshInstance3D = null
## Lo que la parcela tiene construido: [origen, lados de calzada locales, estado, fase].
var _key: Array = []
var _origin := Vector2i(-99999, -99999)
var _road_sides := 0
var _state := "idle"
var _phase := 0
var _plan: Dictionary = {}
## Rectangulo real del modelo (metros, marco local) tras encajarlo.
var _model_rect := Rect2()
## Cima del modelo (metros): lo exagerado se mide con ella para no atravesarlo.
var _model_top := 2.0
## Altura del tejado en el centro del modelo (para lo que va encima: el emblema).
var _model_roof := 2.0

func setup(building: Node3D, data: BuildingData, cell_size: float = -1.0) -> void:
	name = "Lot"
	add_to_group("building_fx")
	_building = building
	_data = data
	_cell = cell_size if cell_size > 0.0 else GridManager.cell_size
	var model := _find_model()
	var mr := Plan.model_rect(data.id, data.grid_size)
	_model_rect = Rect2(mr.position * _cell, mr.size * _cell)
	_model_top = maxf(1.0, data.mesh_height)
	if model != null:
		var a := model_aabb(model, building)
		if a.size != Vector3.ZERO:
			_model_rect = Rect2(Vector2(a.position.x, a.position.z), Vector2(a.size.x, a.size.z))
			_model_top = maxf(0.5, a.end.y)
			_model_roof = _model_top
			if bool(Plan.signature_of(data.id).get("on_roof", false)):
				_model_roof = roof_height(model, building, _model_rect.get_center(), 0.45)
	_ground = MeshInstance3D.new()
	_ground.name = "Ground"
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ground.position.y = Y_GROUND
	add_child(_ground)
	_shadow = MeshInstance3D.new()
	_shadow.name = "ContactShadow"
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.mesh = _shadow_mesh(_model_rect.size)
	_shadow.material_override = shadow_material()
	_shadow.position = Vector3(_model_rect.get_center().x, Y_SHADOW, _model_rect.get_center().y)
	add_child(_shadow)
	_props = MeshInstance3D.new()
	_props.name = "Props"
	_props.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_props)

func _ready() -> void:
	for sig in [EventBus.building_placed, EventBus.building_demolished, EventBus.building_moved,
			EventBus.game_load_completed]:
		(sig as Signal).connect(_on_map_changed)
	refresh.call_deferred()

func _on_map_changed(_a = null, _b = null) -> void:
	refresh.call_deferred()

## Relee celda y calzadas vecinas de la rejilla y reconstruye si cambiaron.
func refresh() -> void:
	if _building == null or not is_instance_valid(_building) or not is_inside_tree():
		return
	var info := GridManager.get_building_info(_building)
	var origin := _origin
	var world_sides := 0
	var steps := int(_building.get_meta("rotation_steps", 0))
	if not info.is_empty():
		origin = info["origin_cell"]
		var size: Vector2i = (info["data"] as BuildingData).grid_size
		world_sides = Plan.road_sides_of(origin, size)
	elif origin.x < -9999:
		origin = GridManager.world_to_cell(_building.global_position)
	build(origin, Plan.local_sides(world_sides, steps, false), _state, _phase)

## El estado de la obra o la ruina (lo llama BuildingLookVisual.apply).
func set_look(look: int, phase: int) -> void:
	var state := Plan.state_for(look)
	var p := phase if state == "construction" else 0
	if state == _state and p == _phase and not _key.is_empty():
		return
	_state = state
	_phase = p
	if _origin.x > -9999:
		build(_origin, _road_sides, _state, _phase)

## Construye la parcela para `origin` (la semilla) con `road_sides` lados
## LOCALES de calzada. Si nada cambio desde la ultima vez, no hace nada.
func build(origin: Vector2i, road_sides: int, state: String = "idle", phase: int = 0) -> void:
	var key := [origin, road_sides, state, phase]
	if key == _key:
		return
	_key = key
	_origin = origin
	_road_sides = road_sides
	_state = state
	_phase = phase
	_plan = Plan.plan(_data.id, _data.grid_size, Plan.seed_for(origin, _data.id), road_sides, state, phase)
	if _plan.is_empty():
		return
	var lot: Vector2 = _plan["lot"] * _cell
	var ground := String(_plan["ground"])
	if state == "ruin":
		ground += ":scorched"
	_ground.mesh = _ground_mesh(_data.grid_size, lot)
	_ground.material_override = ground_material(ground, _data.grid_size)
	# En obra el modelo no esta: no hay sombra que anclar.
	_shadow.visible = state != "construction"
	_props.mesh = build_props_mesh(_plan, _cell, _model_rect, _model_top, _model_roof)

func get_plan() -> Dictionary:
	return _plan

func get_state() -> String:
	return _state

func get_props_node() -> MeshInstance3D:
	return _props

func get_ground() -> MeshInstance3D:
	return _ground

func get_shadow() -> MeshInstance3D:
	return _shadow

func get_model_rect() -> Rect2:
	return _model_rect

func get_model_top() -> float:
	return _model_top

func get_model_roof() -> float:
	return _model_roof

## Altura de la malla en el entorno de `center` (x, z; radio `radius`), en el
## espacio de `space`: el vertice mas alto de los triangulos que caen dentro.
## Se calcula una vez al crear el edificio, y solo si algo va sobre el tejado.
static func roof_height(model: Node3D, space: Node3D, center: Vector2, radius: float) -> float:
	var best := [-INF]
	_roof_rec(model, _chain_to(model, space), center, radius, best)
	return best[0] if best[0] > -INF else model_aabb(model, space).end.y

static func _chain_to(node: Node3D, space: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != space:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf

static func _roof_rec(node: Node, xf: Transform3D, center: Vector2, radius: float, best: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var faces: PackedVector3Array = (node as MeshInstance3D).mesh.get_faces()
		for v in faces:
			var w: Vector3 = xf * v
			if Vector2(w.x, w.z).distance_to(center) <= radius and w.y > best[0]:
				best[0] = w.y
	for c in node.get_children():
		if c is Node3D and not (c is Label3D or c is Sprite3D or c.is_in_group("building_fx")):
			_roof_rec(c, xf * (c as Node3D).transform, center, radius, best)

func _find_model() -> Node3D:
	if _building == null:
		return null
	for child in _building.get_children():
		if child == self or not (child is Node3D) or child is Label3D or child is Sprite3D:
			continue
		if child.is_in_group("building_fx"):
			continue
		return child
	return null

# ── El modelo, dentro de su rectangulo ────────────────────────────────

## AABB de las mallas de `node`, en el espacio de `space` (un ancestro). Sin
## lo del grupo "building_fx" ni rotulos.
static func model_aabb(node: Node3D, space: Node3D = null) -> AABB:
	var xf := Transform3D.IDENTITY
	if space != null and node != space:
		var chain: Array = []
		var n: Node = node
		while n != null and n != space:
			if n is Node3D:
				chain.push_front((n as Node3D).transform)
			n = n.get_parent()
		for t in chain:
			xf = xf * t
	elif space == null:
		xf = node.transform
	var acc := [AABB(), false]
	_aabb_rec(node, xf, acc)
	return acc[0]

static func _aabb_rec(node: Node, xf: Transform3D, acc: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var a: AABB = xf * (node as MeshInstance3D).mesh.get_aabb()
		acc[0] = a if not acc[1] else (acc[0] as AABB).merge(a)
		acc[1] = true
	for c in node.get_children():
		if not (c is Node3D) or c is Label3D or c is Sprite3D or c.is_in_group("building_fx"):
			continue
		_aabb_rec(c, xf * (c as Node3D).transform, acc)

## Encoge el modelo EN PLANTA (nunca en altura, nunca lo agranda) y lo centra
## para que quepa en su rectangulo y deje libre el patio de la parcela. Lo usan
## el edificio del mapa y el fantasma de colocar, asi que coinciden.
static func fit_model(model: Node3D, data: BuildingData, cell_size: float) -> void:
	if model == null or data == null or not Plan.has_lot(data.id):
		return
	var a := model_aabb(model)
	if a.size.x <= 0.0 or a.size.z <= 0.0:
		return
	var target := Plan.model_rect(data.id, data.grid_size).size * cell_size
	var f := minf(1.0, minf(target.x / a.size.x, target.y / a.size.z))
	var center := a.get_center()
	model.scale.x *= f
	model.scale.z *= f
	# Centrado en planta: escalar alrededor de su origen deja el centro en
	# p + f * (c - p); se mueve el origen para que ese centro caiga en (0, 0).
	model.position.x = -f * (center.x - model.position.x)
	model.position.z = -f * (center.z - model.position.z)

# ── Suelo ─────────────────────────────────────────────────────────────

static func _ground_mesh(footprint: Vector2i, lot: Vector2) -> PlaneMesh:
	var key := "%d,%d" % [footprint.x, footprint.y]
	if _ground_meshes.has(key):
		return _ground_meshes[key]
	var plane := PlaneMesh.new()
	plane.size = lot - Vector2(0.04, 0.04)
	_ground_meshes[key] = plane
	return plane

const GROUND_SHADER := preload("res://scripts/buildings/lot_ground.gdshader")
## Cuanto le llegan la Tormenta y la noche a cada suelo: el cesped como la
## hierba de la isla; losas, tierra y chapa algo menos (son "de juguete").
const GROUND_GRADE := {"grass": 1.0, "dirt": 0.8}
const GROUND_GRADE_DEFAULT := 0.6

static var _ground_texs: Dictionary = {}

## Material del suelo `kind` ("slabs", "dirt", "plate", "grass", con ":scorched"
## en ruina) para una huella: la textura se repite una vez por casilla. Lleva
## la Tormenta y la noche de la isla (lot_ground.gdshader, storm_grade): nace
## con el peso que tenga StormSky ahora y StormSky lo mueve con la isla
## (set_ground_param). Una textura por tipo de suelo para todo el mapa.
static func ground_material(kind: String, footprint: Vector2i) -> ShaderMaterial:
	var key := "%s|%d,%d" % [kind, footprint.x, footprint.y]
	if _ground_mats.has(key):
		return _ground_mats[key]
	var base := kind.get_slice(":", 0)
	if not _ground_texs.has(base):
		_ground_texs[base] = ImageTexture.create_from_image(ground_image(base))
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	mat.set_shader_parameter("albedo_tex", _ground_texs[base])
	mat.set_shader_parameter("uv_scale", Vector2(footprint.x, footprint.y))
	mat.set_shader_parameter("roughness_val", 0.6 if base == "plate" else 0.92)
	mat.set_shader_parameter("grade_strength", float(GROUND_GRADE.get(base, GROUND_GRADE_DEFAULT)))
	if kind.ends_with(":scorched"):
		mat.set_shader_parameter("tint", Color(0.42, 0.38, 0.35))
	var sky := _storm_sky()
	if sky != null:
		mat.set_shader_parameter("storm_weight", float(sky.get_island_weight()))
		mat.set_shader_parameter("night_weight", float(sky.get_island_night_weight()))
	_ground_mats[key] = mat
	return mat

## Pone `param` ("storm_weight" o "night_weight") en todos los suelos de
## parcela. Lo llama StormSky junto con los materiales de la isla: solo cuando
## cambia el peso, nunca por frame.
static func set_ground_param(param: String, value: float) -> void:
	for key in _ground_mats:
		(_ground_mats[key] as ShaderMaterial).set_shader_parameter(param, value)

static func _storm_sky() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	var sky := loop.root.get_node_or_null("StormSky")
	return sky if sky != null and sky.has_method("get_island_weight") else null

## La textura de una casilla de suelo, 64x64, generada aqui (sin assets).
static func ground_image(kind: String) -> Image:
	var s := 64
	var img := Image.create_empty(s, s, true, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	for y in s:
		for x in s:
			var c: Color
			match kind:
				"dirt":
					c = Tone.of("dirt").darkened(rng.randf_range(-0.06, 0.12))
				"plate":
					c = Tone.of("steel").darkened(rng.randf_range(0.0, 0.06))
					if x % 32 == 0 or y % 32 == 0:
						c = Tone.of("iron")
					elif x % 32 == 1 or y % 32 == 1:
						c = c.lightened(0.15)
					var rx := x % 32
					var ry := y % 32
					if (rx == 4 or rx == 28) and (ry == 4 or ry == 28 or ry == 16):
						c = Tone.of("brass")
				"grass":
					c = Tone.of("grass").darkened(rng.randf_range(-0.08, 0.14))
				_:
					# Losas: 2x2 por casilla, cada una con su tono, llaga oscura.
					var tile := (x / 32) + (y / 32) * 2
					var tone := 0.04 * float((tile * 7 + 3) % 5) - 0.08
					c = Tone.of("stone").darkened(tone + rng.randf_range(0.0, 0.04))
					if x % 32 < 2 or y % 32 < 2:
						c = Tone.of("stone_dark")
			img.set_pixel(x, y, c)
	if kind == "dirt":
		# Guijarros.
		for k in 18:
			var p := Vector2i(rng.randi_range(1, s - 3), rng.randi_range(1, s - 3))
			img.set_pixel(p.x, p.y, Tone.of("stone"))
			img.set_pixel(p.x + 1, p.y, Tone.of("soil"))
	img.generate_mipmaps()
	return img

# ── Sombra de contacto ────────────────────────────────────────────────

static func _shadow_mesh(model_size: Vector2) -> PlaneMesh:
	var grow := 1.22
	var size := (model_size * grow).snapped(Vector2(0.05, 0.05))
	var key := "%.2f,%.2f" % [size.x, size.y]
	if _shadow_meshes.has(key):
		return _shadow_meshes[key]
	var plane := PlaneMesh.new()
	plane.size = size
	_shadow_meshes[key] = plane
	return plane

## Un solo material para todas las sombras: un rectangulo de esquinas suaves,
## oscuro y con el filo marcado donde toca el modelo (el AO de contacto) que se
## desvanece hacia fuera. La textura se estira al tamano de cada modelo.
static func shadow_material() -> StandardMaterial3D:
	if _shadow_mat != null:
		return _shadow_mat
	var s := 64
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	var inner := 1.0 / 1.22
	for y in s:
		for x in s:
			var u := absf((x + 0.5) / s * 2.0 - 1.0)
			var v := absf((y + 0.5) / s * 2.0 - 1.0)
			# Distancia "cuadrada redondeada" normalizada al borde del modelo.
			var d := pow(pow(u, 6.0) + pow(v, 6.0), 1.0 / 6.0) / inner
			var a := 0.0
			if d <= 1.0:
				a = lerpf(0.42, 0.62, smoothstep(0.75, 1.0, d))
			else:
				a = 0.62 * (1.0 - smoothstep(1.0, 1.0 / inner, d))
			img.set_pixel(x, y, Color(0, 0, 0, a))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.albedo_color = Color(0.05, 0.04, 0.03, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_shadow_mat = mat
	return mat

# ── Borde, remate y atrezo ────────────────────────────────────────────

## La malla de la parcela entera (borde oscuro, remate, atrezo) para un plan.
static func build_props_mesh(plan: Dictionary, cell: float, model_rect := Rect2(), model_top := 2.0, model_roof := -1.0) -> ArrayMesh:
	var mb = MeshKit.new()
	var lot: Vector2 = plan["lot"] * cell
	var accent: Color = Tone.snap(plan["accent"])
	# Borde oscuro fino alrededor de la parcela: la separa de la isla en cualquier
	# fondo (tambien con la Tormenta oscureciendo la luz).
	var bw := 0.05
	var h := lot * 0.5
	mb.box(Vector3(0, BORDER_H * 0.5, -h.y + bw * 0.5), Vector3(lot.x, BORDER_H, bw), BORDER)
	mb.box(Vector3(0, BORDER_H * 0.5, h.y - bw * 0.5), Vector3(lot.x, BORDER_H, bw), BORDER)
	mb.box(Vector3(-h.x + bw * 0.5, BORDER_H * 0.5, 0), Vector3(bw, BORDER_H, lot.y - bw * 2.0), BORDER)
	mb.box(Vector3(h.x - bw * 0.5, BORDER_H * 0.5, 0), Vector3(bw, BORDER_H, lot.y - bw * 2.0), BORDER)
	var trim := String(plan["trim"])
	for run in plan["trim_runs"]:
		_add_trim(mb, trim, run, cell, accent)
	for p in plan["props"]:
		var r := float(p["radius"]) * cell
		var pos: Vector2 = (p["pos"] as Vector2) * cell
		var basis := Basis(Vector3.UP, -float(p["rot"]))
		var xf := Transform3D(basis, Vector3(pos.x, 0.0, pos.y))
		var height := prop_height(String(p["kind"]), r)
		if bool(p.get("toppled", false)):
			xf = xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(height * 0.5, r, 0.0))
		elif bool(p.get("snapped", false)):
			xf = xf * Transform3D(Basis(Vector3.BACK, 0.35).scaled(Vector3(1.0, 0.45, 1.0)), Vector3.ZERO)
		mb.xf = xf
		mb.burnt = 0.65 if bool(p.get("burnt", false)) else 0.0
		add_prop(mb, String(p["kind"]), r, accent)
	mb.xf = Transform3D.IDENTITY
	mb.burnt = 0.0
	var sig: Dictionary = plan.get("signature", {})
	if not sig.is_empty():
		if model_rect.size == Vector2.ZERO:
			var mr: Rect2 = plan["model"]
			model_rect = Rect2(mr.position * cell, mr.size * cell)
		add_signature(mb, sig, plan, cell, model_rect, model_top, accent, model_roof if model_roof > 0.0 else model_top)
	return mb.commit()

# ── El elemento exagerado (guia de estilo, regla 3) ───────────────────

## La pieza que da silueta en miniatura, en su esquina del patio. Se mide con
## la cima y el rectangulo REALES del modelo: lo que pasa por encima va por
## encima de la cima y lo que baja, baja por el patio, nunca por dentro.
## En ruina se queda en un munon quemado.
static func add_signature(mb, sig: Dictionary, plan: Dictionary, cell: float, mr: Rect2, top: float, accent: Color, roof := 2.0) -> void:
	var yard := float(plan["yard"]) * cell
	var fp: Vector2i = plan["footprint"]
	var corners: Array = sig.get("corners", [])
	if bool(sig.get("on_roof", false)):
		_roof_emblem(mb, Vector3(mr.get_center().x, roof, mr.get_center().y), minf(mr.size.x, mr.size.y), bool(sig.get("ruined", false)), accent)
		return
	if corners.is_empty():
		return
	var c2: Vector2 = Plan.corner_center(fp, float(plan["yard"]), corners[0]) * cell
	var c := Vector3(c2.x, 0.0, c2.y)
	var sgn: Vector2 = corners[0]
	var r := yard * 0.45
	var ruined := bool(sig.get("ruined", false))
	mb.burnt = 0.7 if ruined else 0.0
	var k := 0.4 if ruined else 1.0
	match String(sig["kind"]):
		"chimney":
			var h := maxf(top * 1.5, 3.6) * k
			var brick := Tone.of("brick")
			mb.box(c + Vector3(0, 0.15, 0), Vector3(r * 2.1, 0.3, r * 2.1), STONE.darkened(0.2))
			mb.cyl(c + Vector3(0, 0.3, 0), r * 0.95, h - 0.3, brick, 10, Vector3.UP, r * 0.7)
			for t in [0.3, 0.55]:
				mb.cyl(c + Vector3(0, h * t, 0), lerpf(r * 0.95, r * 0.7, t) + 0.025, 0.1, IRON, 10)
			if not ruined:
				mb.cyl(c + Vector3(0, h - 0.55, 0), r * 0.74, 0.28, accent, 10)
				mb.cyl(c + Vector3(0, h, 0), r * 0.8, 0.12, IRON, 10)
				mb.cyl(c + Vector3(0, h + 0.1, 0), r * 0.55, 0.03, Tone.of("ember"), 10, Vector3.UP, -1.0, true)
				# Tiro de humos hasta la esquina del edificio.
				var hp := top * 0.45
				var to := Vector3(mr.end.x - 0.12 if sgn.x > 0 else mr.position.x + 0.12, hp, mr.position.y + 0.12 if sgn.y < 0 else mr.end.y - 0.12)
				mb.beam(c + Vector3(0, hp, 0), to, 0.16, COPPER.darkened(0.15))
		"crane":
			var hm := (top + 1.1) * k
			var yellow := Tone.of("hazard")
			var s := r * 0.55
			for lx in [-s, s]:
				for lz in [-s, s]:
					mb.beam(c + Vector3(lx, 0, lz), c + Vector3(lx * 0.7, hm, lz * 0.7), 0.06, yellow)
			var y := 0.5
			while y < hm - 0.3:
				mb.box(c + Vector3(0, y, 0), Vector3(s * 2.0, 0.04, s * 2.0), yellow.darkened(0.25))
				y += 0.6
			if not ruined:
				var tip := Vector3(mr.get_center().x, hm, mr.end.y + yard * 0.5)
				var base := c + Vector3(0, hm, 0)
				mb.beam(base, tip, 0.12, yellow)
				var back := base + (base - tip).normalized() * 0.9
				back.y = hm
				mb.beam(base, back, 0.1, yellow)
				mb.box(back + Vector3(0, -0.15, 0), Vector3(0.35, 0.35, 0.35), Tone.of("steel"))
				mb.box(base + Vector3(0, 0.22, 0), Vector3(0.32, 0.3, 0.32), Tone.of("iron"))
				var hang := 1.25
				mb.beam(tip, Vector3(tip.x, hang + 0.3, tip.z), 0.025, IRON)
				mb.box(Vector3(tip.x, hang + 0.3, tip.z), Vector3(0.08, 0.1, 0.08), IRON)
				mb.box(Vector3(tip.x, hang, tip.z), Vector3(0.42, 0.4, 0.42), WOOD)
				mb.box(Vector3(tip.x, hang, tip.z), Vector3(0.44, 0.06, 0.44), DARK_WOOD)
		"antenna":
			var h := maxf(top * 1.7, 4.5) * k
			var legs: Array = []
			for i in 3:
				var a := TAU * float(i) / 3.0 + 0.3
				legs.append(Vector3(cos(a), 0, sin(a)))
			for l in legs:
				mb.beam(c + (l as Vector3) * r * 0.9, c + (l as Vector3) * r * 0.15 + Vector3(0, h, 0), 0.05, IRON)
			var y := 0.6
			while y < h - 0.2:
				var w := lerpf(r * 0.9, r * 0.15, y / h)
				for i in 3:
					mb.beam(c + (legs[i] as Vector3) * w + Vector3(0, y, 0), c + (legs[(i + 1) % 3] as Vector3) * w + Vector3(0, y, 0), 0.03, COPPER)
				y += 0.7
			if not ruined:
				mb.cyl(c + Vector3(0, h, 0), 0.03, 0.7, IRON, 5)
				mb.ball(c + Vector3(0, h + 0.75, 0), 0.14, Tone.of("blue_light"), Vector3.ONE, true)
				mb.cyl(c + Vector3(0, h * 0.75, 0.05), 0.32, 0.12, Tone.of("cream"), 10, Vector3(0.0, 0.5, 1.0), 0.05)
		"flag":
			var h := maxf(top * 1.6, 4.2) * k
			mb.box(c + Vector3(0, 0.12, 0), Vector3(r * 1.6, 0.24, r * 1.6), STONE)
			mb.cyl(c, 0.06, h, IRON, 6)
			if not ruined:
				var dir := -1.0 if sgn.x > 0 else 1.0
				var f := c + Vector3(dir * 0.68, h - 0.5, 0)
				mb.box(f, Vector3(1.3, 0.85, 0.04), accent)
				mb.box(f, Vector3(1.32, 0.22, 0.05), Tone.of("iron"))
				mb.ball(c + Vector3(0, h + 0.08, 0), 0.11, BRASS)
		"manifold":
			var h := 1.5 * k
			mb.box(c + Vector3(0, 0.06, 0), Vector3(r * 2.0, 0.12, r * 2.0), IRON)
			var pipes := [Vector3(-r * 0.55, 0, -r * 0.5), Vector3(r * 0.55, 0, -r * 0.5), Vector3(0, 0, r * 0.45)]
			for i in pipes.size():
				mb.cyl(c + (pipes[i] as Vector3), 0.07, h * (0.8 + 0.15 * i), COPPER, 7)
			if not ruined:
				mb.beam(c + Vector3(-r * 0.55, h * 0.75, -r * 0.5), c + Vector3(r * 0.55, h * 0.75, -r * 0.5), 0.1, COPPER.darkened(0.1))
				var to := Vector3(mr.end.x - 0.1 if sgn.x > 0 else mr.position.x + 0.1, h * 0.75, c.z - r * 0.5)
				mb.beam(c + Vector3(0, h * 0.75, -r * 0.5), to, 0.1, COPPER.darkened(0.1))
				_valve_wheel(mb, c + Vector3(0, h * 0.62, r * 0.45 + 0.08), 0.36, Tone.of("red"))
				_valve_wheel(mb, c + Vector3(r * 0.55, h * 0.95, -r * 0.5 + 0.1), 0.18, Tone.of("brass"))
				mb.cyl(c + Vector3(-r * 0.55, h * 0.9, -r * 0.5 + 0.08), 0.12, 0.04, Tone.of("cream"), 10, Vector3.BACK, -1.0, true)
		"ore_heap":
			mb.cyl(c, r * 1.35, 0.85 * maxf(k, 0.5), Tone.of("ore"), 8, Vector3.UP, r * 0.2)
			var nuggets := [Vector3(-0.3, 0.35, 0.25), Vector3(0.25, 0.3, -0.2), Vector3(0.05, 0.55, 0.05), Vector3(0.4, 0.15, 0.3), Vector3(-0.4, 0.12, -0.3), Vector3(0.1, 0.2, 0.45)]
			for i in nuggets.size():
				mb.ball(c + (nuggets[i] as Vector3) * r * 1.5, r * 0.3, GOLD if i % 2 == 0 else GOLD.lightened(0.2), Vector3.ONE, i == 2 and not ruined)
			if not ruined:
				# Pico clavado en el monton
				mb.beam(c + Vector3(r * 0.6, 0.3, 0), c + Vector3(r * 0.2, 1.1, r * 0.3), 0.05, WOOD)
				mb.beam(c + Vector3(0.0, 1.1, r * 0.15), c + Vector3(r * 0.45, 1.05, r * 0.45), 0.07, IRON)
		"cannon":
			for i in 9:
				var a := TAU * float(i) / 9.0
				var p := c + Vector3(cos(a), 0, sin(a)) * r * 1.05
				var saved: Transform3D = mb.xf
				mb.xf = saved * Transform3D(Basis(Vector3.UP, -a), p)
				mb.box(Vector3(0, 0.1, 0), Vector3(0.18, 0.2, 0.3), Tone.of("sandbag"))
				mb.xf = saved
			if not ruined:
				var out := Vector3(sgn.x, 0, sgn.y).normalized()
				mb.box(c + Vector3(0, 0.25, 0), Vector3(0.36, 0.22, 0.36), OLIVE)
				# El canon, exagerado: mas largo y grueso que lo que pide el nido.
				var base := c + Vector3(0, 0.45, 0) - out * 0.35
				var tip := c + out * 0.55 + Vector3(0, 1.0, 0)
				mb.beam(base, tip, 0.24, IRON)
				mb.beam(tip - (tip - base).normalized() * 0.14, tip, 0.3, Tone.of("coal"))
				mb.box(base, Vector3(0.3, 0.26, 0.3), OLIVE.darkened(0.1))
				var wheel_axis := out.cross(Vector3.UP).normalized()
				for side in [-1.0, 1.0]:
					mb.cyl(c + wheel_axis * side * 0.2 + Vector3(0, 0.22, 0), 0.2, 0.05, DARK_WOOD, 8, wheel_axis * side)
				mb.box(c + Vector3(0, 0.3, 0) + wheel_axis * 0.15, Vector3(0.12, 0.08, 0.12), accent)
	mb.burnt = 0.0

## El emblema del Cuartel General sobre su tejado: un pedestal, un mastil corto
## y el disco de cara a la camara, un 40 % mas grande de lo que pediria el
## edificio. Lo de abajo apoya en el tejado medido; nada lo atraviesa.
static func _roof_emblem(mb, base: Vector3, width: float, ruined: bool, accent: Color) -> void:
	mb.burnt = 0.7 if ruined else 0.0
	mb.box(base + Vector3(0, 0.1, 0), Vector3(0.7, 0.2, 0.5), IRON.lightened(0.1))
	if ruined:
		mb.beam(base + Vector3(0, 0.2, 0), base + Vector3(0.35, 0.55, 0.1), 0.1, IRON)
		mb.burnt = 0.0
		return
	var re := clampf(width * 0.24, 0.55, 0.85)
	mb.cyl(base + Vector3(0, 0.2, -0.05), 0.08, re * 0.9, IRON, 6)
	var e := base + Vector3(0, 0.2 + re * 0.9 + re * 0.55, 0.0)
	for side in [-1.0, 1.0]:
		mb.beam(base + Vector3(side * 0.3, 0.2, -0.1), e + Vector3(side * re * 0.7, -re * 0.4, -0.06), 0.05, IRON)
	_emblem(mb, e, re, accent)
	mb.burnt = 0.0

static func _valve_wheel(mb, c: Vector3, rad: float, col: Color) -> void:
	for i in 10:
		var a0 := TAU * float(i) / 10.0
		var a1 := TAU * float(i + 1) / 10.0
		mb.beam(c + Vector3(cos(a0), sin(a0), 0) * rad, c + Vector3(cos(a1), sin(a1), 0) * rad, rad * 0.16, col)
	for i in 3:
		var a := TAU * float(i) / 3.0
		mb.beam(c, c + Vector3(cos(a), sin(a), 0) * rad, rad * 0.1, col.darkened(0.2))
	mb.cyl(c - Vector3(0, 0, 0.04), rad * 0.18, 0.08, IRON, 6, Vector3.BACK)

## Emblema de la Regencia (propio): rueda dentada de laton con el rayo de la
## Tormenta sobre un disco rojo, de cara a la camara.
static func _emblem(mb, c: Vector3, re: float, accent: Color) -> void:
	mb.cyl(c - Vector3(0, 0, 0.04), re, 0.08, Tone.of("iron"), 20, Vector3.BACK)
	for i in 14:
		var a := TAU * float(i) / 14.0
		var saved: Transform3D = mb.xf
		mb.xf = saved * Transform3D(Basis(Vector3.BACK, a), c + Vector3(cos(a), sin(a), 0) * re)
		mb.box(Vector3.ZERO, Vector3(re * 0.22, re * 0.18, 0.1), BRASS)
		mb.xf = saved
	mb.cyl(c + Vector3(0, 0, 0.04), re * 0.8, 0.02, BRASS, 20, Vector3.BACK)
	mb.cyl(c + Vector3(0, 0, 0.06), re * 0.62, 0.02, Tone.of("red"), 20, Vector3.BACK)
	# El rayo: tres tramos en zigzag, en el amarillo militar.
	var z := c.z + 0.1
	var pts := [Vector2(-0.12, 0.45), Vector2(0.12, 0.05), Vector2(-0.1, -0.02), Vector2(0.14, -0.45)]
	for i in 3:
		var p0: Vector2 = pts[i] * re
		var p1: Vector2 = pts[i + 1] * re
		mb.beam(Vector3(c.x + p0.x, c.y + p0.y, z), Vector3(c.x + p1.x, c.y + p1.y, z), re * 0.11, accent.lightened(0.15))

## Remate de un lado. En ruina, `broken` (bits) se come tramos sueltos.
static func _add_trim(mb, trim: String, run: Dictionary, cell: float, accent: Color) -> void:
	var a: Vector2 = (run["a"] as Vector2) * cell
	var b: Vector2 = (run["b"] as Vector2) * cell
	var length := a.distance_to(b)
	var dir := (b - a).normalized()
	var segs := maxi(2, int(length / 0.5))
	var broken := int(run.get("broken", 0))
	mb.burnt = 0.6 if broken != 0 else 0.0
	for i in segs:
		if broken != 0 and (broken >> (i % 30)) & 1 == 1 and (broken >> ((i + 7) % 30)) & 1 == 1:
			continue
		var p0 := a + dir * length * float(i) / float(segs)
		var p1 := a + dir * length * float(i + 1) / float(segs)
		var c := (p0 + p1) * 0.5
		var seg_len := length / float(segs)
		var along_x := absf(dir.x) > 0.5
		match trim:
			"fence":
				mb.cyl(Vector3(p0.x, 0, p0.y), 0.035, 0.34, DARK_WOOD, 5)
				for y in [0.14, 0.27]:
					_seg(mb, c, along_x, seg_len, 0.04, y, 0.045, WOOD)
			"rail":
				mb.cyl(Vector3(p0.x, 0, p0.y), 0.03, 0.42, IRON, 5)
				_seg(mb, c, along_x, seg_len, 0.05, 0.42, 0.04, IRON)
				_seg(mb, c, along_x, seg_len, 0.025, 0.2, 0.025, IRON.lightened(0.12))
			"sandbags":
				var bag := Tone.of("sandbag")
				_seg(mb, c, along_x, seg_len * 0.94, 0.12, 0.08, 0.16, bag)
				_seg(mb, c, along_x, seg_len * 0.7, 0.1, 0.21, 0.11, bag.lightened(0.08))
			"pipes":
				if i % 2 == 0:
					mb.box(Vector3(p0.x, 0.1, p0.y), Vector3(0.08, 0.2, 0.08), IRON)
				mb.cyl(Vector3(p0.x, 0.24, p0.y), 0.05, seg_len, COPPER, 6, Vector3(dir.x, 0, dir.y))
				if i % 3 == 1:
					mb.cyl(Vector3(c.x, 0.24, c.y), 0.11, 0.03, accent, 8, Vector3.BACK if along_x else Vector3.RIGHT)
			_:
				# Bordillo de piedra (tambien el de la hierba de casas y jardines).
				_seg(mb, c, along_x, seg_len, 0.1, 0.05, 0.1, STONE.lightened(0.05) if i % 2 == 0 else STONE)
	mb.burnt = 0.0

## Un tramo recto del remate: `seg_len` a lo largo del lado, `across` de ancho,
## centrado en `c` a la altura `y` con alto `h`.
static func _seg(mb, c: Vector2, along_x: bool, seg_len: float, across: float, y: float, h: float, col: Color) -> void:
	var size := Vector3(seg_len, h, across) if along_x else Vector3(across, h, seg_len)
	mb.box(Vector3(c.x, y, c.y), size, col)

## Altura aproximada de una pieza (para volcarla sobre el suelo).
static func prop_height(kind: String, r: float) -> float:
	match kind:
		"barrel": return 2.0 * r
		"crate", "goods": return 1.4 * r
		"logs": return 1.3 * r
		"drums", "valve": return 1.7 * r
		"cart", "planter", "bench": return 1.2 * r
		"ore", "sacks", "ammo": return 0.9 * r
		"coal", "pallet": return 0.7 * r
		"planks", "ingots": return 0.55 * r
	return 2.0 * r

## Una pieza de atrezo de radio `r` (metros) centrada en el origen, sobre el
## suelo, con su eje largo en X. Volumenes gruesos y un acento saturado.
static func add_prop(mb, kind: String, r: float, accent: Color) -> void:
	match kind:
		"barrel":
			mb.cyl(Vector3.ZERO, 0.78 * r, 2.0 * r, RUST, 8)
			for y in [0.3, 1.55]:
				mb.cyl(Vector3(0, y * r, 0), 0.82 * r, 0.14 * r, IRON, 8)
			mb.cyl(Vector3(0, 2.0 * r, 0), 0.3 * r, 0.03 * r, accent, 6)
		"crate":
			mb.box(Vector3(0, 0.7 * r, 0), Vector3(1.5, 1.4, 1.5) * r, WOOD)
			mb.box(Vector3(0, 0.7 * r, 0), Vector3(1.54, 0.16, 1.54) * r, DARK_WOOD)
			mb.box(Vector3(0, 1.41 * r, 0), Vector3(1.5, 0.04, 0.22) * r, DARK_WOOD)
		"goods":
			mb.box(Vector3(0, 0.5 * r, 0), Vector3(1.6, 1.0, 1.2) * r, WOOD_LIGHT)
			mb.box(Vector3(0, 0.98 * r, 0), Vector3(1.64, 0.08, 1.24) * r, DARK_WOOD)
			var fruit := [Tone.of("red"), Tone.of("gold"), Tone.of("leaf"), accent]
			for i in 4:
				mb.ball(Vector3((-0.5 + 0.33 * i) * r, 1.15 * r, (0.2 if i % 2 == 0 else -0.2) * r), 0.26 * r, fruit[i])
		"sacks":
			mb.ball(Vector3(-0.45 * r, 0.3 * r, 0), 0.55 * r, SACK, Vector3(1.0, 0.6, 0.8))
			mb.ball(Vector3(0.45 * r, 0.3 * r, 0.1 * r), 0.55 * r, SACK.darkened(0.08), Vector3(1.0, 0.6, 0.8))
			mb.ball(Vector3(0.0, 0.7 * r, 0.05 * r), 0.5 * r, SACK.lightened(0.06), Vector3(1.0, 0.6, 0.8))
		"logs":
			for l in [Vector3(0, 0.33, -0.34), Vector3(0, 0.33, 0.34), Vector3(0, 0.9, 0)]:
				var base := Vector3(-1.0 * r, l.y * r, l.z * r)
				mb.cyl(base, 0.33 * r, 2.0 * r, Tone.of("log"), 7, Vector3.RIGHT)
				mb.cyl(base - Vector3(0.01, 0, 0), 0.27 * r, 0.02, WOOD_LIGHT, 7, Vector3.LEFT)
		"planks":
			for layer in 4:
				for j in 3:
					var col := WOOD_LIGHT if (layer + j) % 2 == 0 else WOOD
					mb.box(Vector3(0, (0.07 + 0.13 * layer) * r, (-0.45 + 0.45 * j) * r), Vector3(2.0, 0.12, 0.42) * r, col)
		"lamp":
			mb.box(Vector3(0, 0.12 * r, 0), Vector3(0.45, 0.24, 0.45) * r, IRON)
			mb.cyl(Vector3.ZERO, 0.09 * r, 6.2 * r, IRON, 6)
			mb.box(Vector3(0, 6.35 * r, 0), Vector3(0.5, 0.18, 0.5) * r, IRON)
			mb.ball(Vector3(0, 5.95 * r, 0), 0.3 * r, WARM, Vector3.ONE, true)
		"ore":
			mb.cyl(Vector3.ZERO, 0.95 * r, 0.9 * r, Tone.of("ore"), 7, Vector3.UP, 0.15 * r)
			for g in [Vector3(-0.3, 0.55, 0.2), Vector3(0.25, 0.45, -0.25), Vector3(0.05, 0.85, 0.0), Vector3(0.5, 0.25, 0.35)]:
				mb.ball(g * r, 0.22 * r, GOLD)
		"cart":
			for z in [-0.35, 0.35]:
				mb.box(Vector3(0, 0.03 * r, z * r), Vector3(2.0, 0.06, 0.08) * r, IRON)
			for x in [-0.7, 0.0, 0.7]:
				mb.box(Vector3(x * r, 0.02 * r, 0), Vector3(0.18, 0.04, 1.0) * r, DARK_WOOD)
			mb.box(Vector3(0, 0.62 * r, 0), Vector3(1.3, 0.7, 0.9) * r, RUST, false, true)
			for x in [-0.4, 0.4]:
				for z in [-0.42, 0.42]:
					mb.cyl(Vector3(x * r, 0.22 * r, z * r * 1.05), 0.2 * r, 0.06 * r, IRON, 6, Vector3.BACK if z > 0 else Vector3.FORWARD)
			for g in [Vector3(-0.3, 1.0, 0.1), Vector3(0.25, 1.02, -0.15), Vector3(0.0, 1.1, 0.0)]:
				mb.ball(g * r, 0.24 * r, GOLD)
		"ingots":
			for layer in 2:
				for j in 3:
					var glow := layer == 1 and j == 1
					var col := Tone.of("ember") if glow else STEEL
					var b := Vector3(0, (0.12 + 0.24 * layer) * r, (-0.42 + 0.42 * j) * r)
					mb.box(b, Vector3(1.6, 0.22, 0.36) * r, col, glow)
		"coal":
			mb.cyl(Vector3.ZERO, 0.9 * r, 0.7 * r, COAL, 7, Vector3.UP, 0.12 * r)
			mb.ball(Vector3(0.5 * r, 0.12 * r, 0.4 * r), 0.2 * r, COAL.lightened(0.1))
		"drums":
			for k in 2:
				var x := (-0.48 + 0.96 * k) * r
				var col := accent if k == 0 else Tone.of("steel")
				mb.cyl(Vector3(x, 0, 0), 0.47 * r, 1.7 * r, col, 8)
				mb.cyl(Vector3(x, 0.55 * r, 0), 0.5 * r, 0.1 * r, IRON, 8)
				mb.cyl(Vector3(x, 1.15 * r, 0), 0.5 * r, 0.1 * r, IRON, 8)
		"valve":
			mb.box(Vector3(0, 0.1 * r, 0), Vector3(0.6, 0.2, 0.6) * r, IRON)
			mb.cyl(Vector3.ZERO, 0.16 * r, 1.5 * r, COPPER, 6)
			mb.cyl(Vector3(0, 1.1 * r, -0.05 * r), 0.55 * r, 0.1 * r, accent, 8, Vector3.BACK)
			mb.cyl(Vector3(0, 0.6 * r, 0), 0.12 * r, 0.9 * r, COPPER, 6, Vector3.RIGHT)
		"gas":
			mb.box(Vector3(0, 0.08 * r, 0), Vector3(1.8, 0.16, 0.7) * r, IRON)
			for k in 3:
				var x := (-0.6 + 0.6 * k) * r
				var col := Tone.of("leaf_dark") if k != 1 else Tone.of("sky")
				mb.cyl(Vector3(x, 0.16 * r, 0), 0.24 * r, 2.4 * r, col, 7)
				mb.cyl(Vector3(x, 2.56 * r, 0), 0.1 * r, 0.25 * r, BRASS, 6)
			mb.box(Vector3(0, 1.8 * r, -0.3 * r), Vector3(1.9, 0.08, 0.06) * r, IRON)
		"dummy":
			mb.cyl(Vector3.ZERO, 0.08 * r, 3.4 * r, DARK_WOOD, 5)
			mb.cyl(Vector3(0, 1.3 * r, 0), 0.42 * r, 1.4 * r, SACK, 7)
			mb.ball(Vector3(0, 3.1 * r, 0), 0.34 * r, SACK.lightened(0.05))
			mb.box(Vector3(0, 2.45 * r, 0), Vector3(1.7, 0.14, 0.14) * r, DARK_WOOD)
			mb.box(Vector3(0, 2.1 * r, 0.42 * r), Vector3(0.3, 0.3, 0.04) * r, accent)
		"target":
			mb.beam(Vector3(-0.5 * r, 0, 0.3 * r), Vector3(0, 2.4 * r, 0), 0.1 * r, DARK_WOOD)
			mb.beam(Vector3(0.5 * r, 0, 0.3 * r), Vector3(0, 2.4 * r, 0), 0.1 * r, DARK_WOOD)
			var rings := [[0.95, Tone.of("cream")], [0.7, Tone.of("red")], [0.45, Tone.of("cream")], [0.2, accent]]
			for i in rings.size():
				mb.cyl(Vector3(0, 1.6 * r, (0.12 + 0.03 * i) * r), float(rings[i][0]) * r, 0.03 * r, rings[i][1], 10, Vector3.BACK)
		"flag":
			mb.box(Vector3(0, 0.1 * r, 0), Vector3(0.6, 0.2, 0.6) * r, STONE)
			mb.cyl(Vector3.ZERO, 0.07 * r, 8.0 * r, IRON, 6)
			mb.box(Vector3(0.85 * r, 7.3 * r, 0), Vector3(1.6, 1.1, 0.05) * r, accent)
			mb.box(Vector3(0.85 * r, 7.3 * r, 0), Vector3(1.62, 0.25, 0.06) * r, Tone.of("iron"))
			mb.ball(Vector3(0, 8.1 * r, 0), 0.16 * r, BRASS)
		"ammo":
			mb.box(Vector3(0, 0.4 * r, 0), Vector3(1.6, 0.8, 1.0) * r, OLIVE)
			mb.box(Vector3(0, 0.55 * r, 0), Vector3(1.62, 0.16, 1.02) * r, accent)
			mb.box(Vector3(0, 0.82 * r, 0), Vector3(1.0, 0.06, 0.3) * r, IRON)
		"bench":
			mb.box(Vector3(0, 0.55 * r, 0), Vector3(2.0, 0.12, 0.6) * r, WOOD)
			mb.box(Vector3(0, 0.95 * r, -0.3 * r), Vector3(2.0, 0.42, 0.1) * r, WOOD)
			for x in [-0.8, 0.8]:
				mb.box(Vector3(x * r, 0.27 * r, 0), Vector3(0.12, 0.55, 0.55) * r, IRON)
		"planter":
			mb.box(Vector3(0, 0.3 * r, 0), Vector3(1.2, 0.6, 1.2) * r, TERRACOTTA)
			mb.ball(Vector3(0, 0.82 * r, 0), 0.62 * r, LEAF, Vector3(1.0, 0.8, 1.0))
			mb.ball(Vector3(0.3 * r, 1.12 * r, 0.2 * r), 0.16 * r, accent if accent.g < 0.5 else Tone.of("red"))
			mb.ball(Vector3(-0.25 * r, 1.08 * r, -0.2 * r), 0.15 * r, Tone.of("gold"))
		"clothesline":
			for x in [-1.0, 1.0]:
				mb.cyl(Vector3(x * r, 0, 0), 0.07 * r, 3.4 * r, DARK_WOOD, 5)
			mb.box(Vector3(0, 3.2 * r, 0), Vector3(2.0, 0.03, 0.03) * r, Tone.of("cream"))
			var cloth := [Tone.of("cream"), accent, Tone.of("sky")]
			for i in 3:
				mb.box(Vector3((-0.6 + 0.6 * i) * r, 2.75 * r, 0), Vector3(0.45, 0.85, 0.03) * r, cloth[i])
		"stake":
			mb.cyl(Vector3.ZERO, 0.06 * r, 2.6 * r, WOOD_LIGHT, 5)
			mb.box(Vector3(0.25 * r, 2.35 * r, 0), Vector3(0.5, 0.32, 0.03) * r, HAZARD)
		"pallet":
			mb.box(Vector3(0, 0.09 * r, 0), Vector3(1.7, 0.18, 1.7) * r, WOOD)
			for k in 3:
				mb.box(Vector3(0, (0.27 + 0.18 * k) * r, 0), Vector3(1.5, 0.17, 1.5) * r, STONE.darkened(0.04 * k))
		_:
			mb.box(Vector3(0, 0.5 * r, 0), Vector3(r, r, r), WOOD)
