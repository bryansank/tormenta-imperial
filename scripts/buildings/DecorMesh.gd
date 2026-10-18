extends RefCounted
## Las diez decoraciones baratas (feat/decoraciones-1, doc 21 §6.4) en 3D.
##
## Cada una es UNA malla con los dos materiales de la paleta (ToyPalette): una
## llamada de dibujo (dos si algo brilla: farol, hoguera), sin texturas, sin
## `_process`, y la misma malla para todas las instancias de un tipo.
##
## De donde sale la malla:
## - la horneada, si existe (`assets/models/toy/<id>_mesh.res`, la hace
##   `tools/build_toy_models.gd` con las recetas de `tools/toy_recipes/<id>.gd`
##   y piezas CC0 recoloreadas);
## - si no, la version procedural de aqui, con las mismas proporciones y solo
##   cajas, cilindros y bolas de LotMesh. Es la que se ve hasta el horneado del
##   pase final, y la reserva si un horneado falta.
##
## Marco: centro en el origen, suelo en y = 0, frente hacia +Z (la camara). Lo
## hace para unos 3 m de lado (el rectangulo que deja la parcela de 2x2 con su
## patio); BuildingLot.fit_model() lo encoge si hace falta, nunca lo agranda.
## Presupuesto (doc 21 §6.6): <= 600 triangulos por decoracion 2x2.

const MeshKit := preload("res://scripts/buildings/LotMesh.gd")
const Palette := preload("res://scripts/buildings/ToyPalette.gd")
const S := Palette.Slot

const IDS := ["lamp_post", "park_bench", "hedge", "avenue_tree", "flower_planter",
	"colony_sign", "hay_cart", "bonfire", "flagpole", "palm_trees"]
const BAKED := "res://assets/models/toy/%s_mesh.res"
const TRI_BUDGET := 600

## id -> Mesh (horneada o procedural), una por tipo para todo el mapa.
static var _cache := {}

## Las dieciocho restantes del catalogo (feat/decoraciones-y-trafico): misma
## malla compartida, mismo lote; su version procedural vive en DecorMesh2.
const More := preload("res://scripts/buildings/DecorMesh2.gd")

static func handles(id: String) -> bool:
	return id in IDS or More.handles(id)

## La malla del tipo `id` (cacheada), o null si no es una de estas.
static func mesh_for(id: String) -> Mesh:
	if not handles(id):
		return null
	if _cache.has(id):
		return _cache[id]
	var mesh: Mesh = null
	var path := BAKED % id
	if ResourceLoader.exists(path):
		mesh = load(path) as Mesh
	if mesh == null:
		mesh = procedural(id)
	_cache[id] = mesh
	return mesh

## Lo que pone el mapa (y la vista previa de CONSTRUIR): un MeshInstance3D con
## la malla compartida y, en las que tienen mastil (mastil, letrero), el
## Marker3D "FlagAnchor" de donde ColonyFlag3D cuelga la bandera del pais.
static func instantiate(id: String) -> MeshInstance3D:
	var mesh := mesh_for(id)
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "Toy_" + id
	mi.mesh = mesh
	add_flag_anchor(mi, id)
	return mi

## Cuelga de `model` el FlagAnchor de `id` si lo tiene (ver flag_anchor()).
static func add_flag_anchor(model: Node3D, id: String) -> void:
	var at: Variant = flag_anchor(id)
	if at == null:
		return
	var marker := Marker3D.new()
	marker.name = ANCHOR_NAME
	marker.position = at
	model.add_child(marker)

const ANCHOR_NAME := "FlagAnchor"
const BAKED_SCENE := "res://assets/models/toy/%s.tscn"
## Lo alto del mastil de la version procedural (marco de la malla).
const PROCEDURAL_FLAG := {"flagpole": Vector3(0, 3.6, 0), "colony_sign": Vector3(0.7, 2.25, 0)}
## id -> Vector3 o null (cacheado: se lee una vez por tipo).
static var _anchor_cache := {}

## Donde va la bandera del pais en la malla de `id` (su marco), o null. Con la
## malla horneada, el FlagAnchor que dejo el horneado en `<id>.tscn` (se lee del
## SceneState, sin instanciar la escena); sin hornear, el de la procedural.
static func flag_anchor(id: String) -> Variant:
	if _anchor_cache.has(id):
		return _anchor_cache[id]
	var at: Variant = null
	# Solo las que tienen mastil: las demas no cargan su escena para nada.
	if not PROCEDURAL_FLAG.has(id):
		at = null
	elif ResourceLoader.exists(BAKED % id):
		at = _baked_anchor(id)
	else:
		at = PROCEDURAL_FLAG.get(id, null)
	_anchor_cache[id] = at
	return at

static func _baked_anchor(id: String) -> Variant:
	var path := BAKED_SCENE % id
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var state := scene.get_state()
	for i in state.get_node_count():
		if state.get_node_name(i) != ANCHOR_NAME:
			continue
		# El horneado lo guarda como `transform` (Marker3D.position escrito asi).
		for k in state.get_node_property_count(i):
			var prop := state.get_node_property_name(i, k)
			if prop == "transform":
				return (state.get_node_property_value(i, k) as Transform3D).origin
			if prop == "position":
				return state.get_node_property_value(i, k)
		return Vector3.ZERO
	return null

## La version procedural, sin cache (las pruebas la miden).
static func procedural(id: String) -> ArrayMesh:
	var mk := MeshKit.new()
	build(mk, id)
	return mk.commit()

static func build(mk, id: String) -> void:
	match id:
		"lamp_post": _lamp_post(mk)
		"park_bench": _park_bench(mk)
		"hedge": _hedge(mk)
		"avenue_tree": _avenue_tree(mk)
		"flower_planter": _flower_planter(mk)
		"colony_sign": _colony_sign(mk)
		"hay_cart": _hay_cart(mk)
		"bonfire": _bonfire(mk)
		"flagpole": _flagpole(mk)
		"palm_trees": _palm_trees(mk)
		_: More.build(mk, id)

# ── Colores ───────────────────────────────────────────────────────────

static func C(slot: int, d := 0.0) -> Color:
	return Palette.tint(slot, d)

# ── Piezas propias que tambien usan las recetas del horneado ──────────

## Caja apoyada en `pos.y`, centrada en planta.
static func block(mk, pos: Vector3, size: Vector3, col: Color, glow := false) -> void:
	mk.box(pos + Vector3(0, size.y * 0.5, 0), size, col, glow)

## Flores: cubitos de color sobre una mata (no hay flores CC0: doc 22 §3.5).
static func flowers(mk, c: Vector3, r: float, count := 4, seed_val := 0) -> void:
	var cols := [S.RED, S.BRASS, S.CREAM, S.TERRACOTTA]
	for i in count:
		var a := TAU * float(i) / float(count) + float(seed_val) * 0.7
		var p := c + Vector3(cos(a) * r, 0.0, sin(a) * r)
		mk.box(p, Vector3(0.11, 0.11, 0.11), C(cols[(i + seed_val) % cols.size()], 0.08))

## Paca de heno: caja dorada con dos cintas.
static func hay_bale(mk, pos: Vector3, size: Vector3, rot_deg := 0.0) -> void:
	var saved: Transform3D = mk.xf
	mk.xf = saved * Transform3D(Basis(Vector3.UP, deg_to_rad(rot_deg)), pos)
	block(mk, Vector3.ZERO, size, C(S.BRASS, -0.06))
	for sx in [-0.25, 0.25]:
		block(mk, Vector3(size.x * sx, 0, 0), Vector3(0.04, size.y + 0.01, size.z + 0.01), C(S.WOOD, -0.1))
	mk.xf = saved

## Llama: dos conos encendidos (superficie de brillo, sin luz real).
static func flame(mk, base: Vector3, r: float, h: float) -> void:
	mk.cyl(base, r, h, C(S.GLOW, 0.05), 5, Vector3.UP, 0.0, true)
	mk.cyl(base + Vector3(0.05, 0, -0.04), r * 0.6, h * 1.35, Palette.color(S.GLOW).lightened(0.25), 4, Vector3.UP, 0.0, true)

# La bandera de mastil y letrero ya no se hornea: es la del pais, la cuelga
# ColonyFlag3D del FlagAnchor (feat/decoraciones-remates).

# ── Las diez ──────────────────────────────────────────────────────────

## Farola: peana, fuste de hierro alto (lo exagerado) con dos brazos y dos
## faroles encendidos.
static func _lamp_post(mk) -> void:
	var iron := C(S.IRON, 0.05)
	block(mk, Vector3.ZERO, Vector3(0.55, 0.18, 0.55), C(S.STONE, -0.05))
	mk.cyl(Vector3(0, 0.18, 0), 0.13, 0.35, iron, 6, Vector3.UP, 0.08)
	mk.cyl(Vector3(0, 0.5, 0), 0.07, 2.0, iron, 6)
	mk.cyl(Vector3(0, 2.5, 0), 0.06, 0.25, C(S.BRASS), 6, Vector3.UP, 0.0)
	for sx in [-1.0, 1.0]:
		mk.beam(Vector3(0, 2.3, 0), Vector3(sx * 0.5, 2.35, 0), 0.06, iron)
		var c := Vector3(sx * 0.55, 1.98, 0)
		mk.box(c + Vector3(0, 0.16, 0), Vector3(0.24, 0.32, 0.24), C(S.GLOW), true)
		block(mk, c + Vector3(0, 0.32, 0), Vector3(0.3, 0.05, 0.3), iron)
		mk.cyl(c + Vector3(0, 0.37, 0), 0.2, 0.14, iron, 4, Vector3.UP, 0.0)

## Banco: dos bancos de madera frente a frente (respaldo hacia fuera) y una
## mata en maceta en medio, con su papelera.
static func _park_bench(mk) -> void:
	for sz in [-1.0, 1.0]:
		var saved: Transform3D = mk.xf
		mk.xf = saved * Transform3D(Basis(Vector3.UP, PI if sz > 0.0 else 0.0), Vector3(0, 0, sz * 0.7))
		for sx in [-0.55, 0.55]:
			block(mk, Vector3(sx, 0, 0), Vector3(0.08, 0.42, 0.45), C(S.IRON, 0.05))
		block(mk, Vector3(0, 0.38, 0), Vector3(1.4, 0.08, 0.42), C(S.WOOD, 0.04))
		mk.box(Vector3(0, 0.7, -0.2), Vector3(1.4, 0.3, 0.07), C(S.WOOD, -0.02))
		mk.xf = saved
	mk.cyl(Vector3.ZERO, 0.24, 0.32, C(S.TERRACOTTA, -0.05), 6, Vector3.UP, 0.3)
	mk.ball(Vector3(0, 0.55, 0), 0.32, C(S.GREEN, -0.05))
	mk.cyl(Vector3(1.0, 0, 0), 0.14, 0.5, C(S.SLATE), 6)

## Seto: seto recortado en U, abierto hacia delante, con una bola en cada
## esquina de atras (lo exagerado) y un arbolito en maceta en medio.
static func _hedge(mk) -> void:
	var g := C(S.GREEN, -0.15)
	block(mk, Vector3(0, 0, -1.05), Vector3(2.5, 0.75, 0.42), g)
	for sx in [-1.0, 1.0]:
		block(mk, Vector3(sx * 1.05, 0, 0.15), Vector3(0.42, 0.75, 2.0), g.lightened(0.03))
		mk.ball(Vector3(sx * 1.05, 0.95, -1.05), 0.3, C(S.GREEN, -0.05))
	mk.cyl(Vector3(0, 0, 0.2), 0.22, 0.3, C(S.TERRACOTTA, -0.05), 6, Vector3.UP, 0.28)
	mk.cyl(Vector3(0, 0.3, 0.2), 0.04, 0.45, C(S.WOOD, -0.15), 4)
	mk.ball(Vector3(0, 0.85, 0.2), 0.3, C(S.GREEN, 0.02))

## Arbol de paseo: alcorque de hierro con su tierra, tronco y copa de tres
## bolas, alta y redonda (lo exagerado).
static func _avenue_tree(mk) -> void:
	block(mk, Vector3.ZERO, Vector3(1.1, 0.08, 1.1), C(S.IRON, 0.08))
	block(mk, Vector3(0, 0.08, 0), Vector3(0.9, 0.02, 0.9), C(S.WOOD, -0.2))
	mk.cyl(Vector3.ZERO, 0.13, 1.5, C(S.WOOD, -0.12), 6, Vector3.UP, 0.09)
	mk.ball(Vector3(0, 1.75, 0), 0.75, C(S.GREEN, -0.08), Vector3(1.0, 0.85, 1.0))
	mk.ball(Vector3(-0.3, 2.25, 0.1), 0.48, C(S.GREEN, 0.0))
	mk.ball(Vector3(0.28, 2.35, -0.12), 0.42, C(S.GREEN, 0.06))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			block(mk, Vector3(sx * 0.62, 0, sz * 0.62), Vector3(0.07, 0.45, 0.07), C(S.IRON, 0.05))

## Macetero: tres macetas de barro de alturas distintas, cada una con su mata
## y sus flores.
static func _flower_planter(mk) -> void:
	var pots := [[Vector3(-0.55, 0, 0.25), 0.36, 0.5], [Vector3(0.5, 0, 0.35), 0.3, 0.38], [Vector3(0.05, 0, -0.5), 0.42, 0.62]]
	var i := 0
	for p in pots:
		var base: Vector3 = p[0]
		var r: float = p[1]
		var h: float = p[2]
		mk.cyl(base, r * 0.8, h, C(S.TERRACOTTA, -0.04 + 0.03 * i), 8, Vector3.UP, r)
		block(mk, base + Vector3(0, h, 0), Vector3(r * 1.5, 0.03, r * 1.5), C(S.WOOD, -0.2))
		mk.ball(base + Vector3(0, h + 0.18, 0), r * 0.85, C(S.GREEN, -0.05), Vector3(1.0, 0.7, 1.0))
		flowers(mk, base + Vector3(0, h + 0.32, 0), r * 0.55, 3 + (i % 2), i)
		i += 1

## Letrero de la colonia: dos postes, el tablero con su marco de laton y un
## mastil corto (la bandera del pais la cuelga ColonyFlag3D, PROCEDURAL_FLAG).
static func _colony_sign(mk) -> void:
	var post := C(S.WOOD, -0.12)
	for sx in [-0.7, 0.7]:
		block(mk, Vector3(sx, 0, 0), Vector3(0.14, 1.35, 0.14), post)
	mk.box(Vector3(0, 1.0, 0.05), Vector3(1.7, 0.62, 0.08), C(S.BRASS, -0.05))
	mk.box(Vector3(0, 1.0, 0.1), Vector3(1.55, 0.5, 0.04), C(S.CREAM))
	mk.box(Vector3(0, 1.0, 0.13), Vector3(1.1, 0.1, 0.02), C(S.IRON))
	mk.cyl(Vector3(0.7, 1.35, 0), 0.04, 0.9, C(S.IRON, 0.05), 4)
	mk.ball(Vector3(-0.5, 0.24, 0.45), 0.24, C(S.GREEN, -0.05))

## Carro de heno: carro de madera con sus dos ruedas, el heno amontonado
## (lo exagerado), dos pacas y un saco al lado.
## `sack` = false: sin el saco (la receta horneada pone el de KayKit).
static func _hay_cart(mk, sack := true) -> void:
	var wood := C(S.WOOD, -0.05)
	block(mk, Vector3(-0.2, 0.35, 0), Vector3(1.3, 0.35, 0.9), wood)
	for sz in [-0.4, 0.4]:
		mk.beam(Vector3(0.4, 0.5, sz), Vector3(1.2, 0.65, sz * 1.1), 0.06, C(S.WOOD, -0.15))
		block(mk, Vector3(0.3, 0, sz), Vector3(0.07, 0.35, 0.07), C(S.WOOD, -0.15))
	for sz in [-0.5, 0.36]:
		mk.cyl(Vector3(-0.85, 0.32, sz), 0.32, 0.14, C(S.WOOD, -0.18), 8, Vector3(0, 0, 1), -1.0, false, true)
	mk.ball(Vector3(-0.2, 0.8, 0), 0.6, C(S.BRASS, -0.02), Vector3(1.2, 0.55, 0.8))
	mk.ball(Vector3(-0.35, 1.05, 0.05), 0.35, C(S.BRASS, 0.04), Vector3(1.1, 0.6, 1.0))
	hay_bale(mk, Vector3(0.45, 0, -0.95), Vector3(0.8, 0.4, 0.5), 10.0)
	hay_bale(mk, Vector3(0.95, 0, 0.75), Vector3(0.8, 0.4, 0.5), -25.0)
	if sack:
		mk.ball(Vector3(-0.9, 0.25, 0.85), 0.25, C(S.CREAM, -0.12), Vector3(0.9, 1.0, 0.8))

## Hoguera: corro de piedras, troncos en tienda y la llama encendida (lo
## exagerado, brilla de noche sin luz real), con dos troncos para sentarse.
static func _bonfire(mk) -> void:
	for i in 8:
		var a := TAU * float(i) / 8.0
		mk.box(Vector3(cos(a) * 0.55, 0.08, sin(a) * 0.55), Vector3(0.24, 0.16, 0.2), C(S.STONE, -0.08 + 0.04 * (i % 3)))
	block(mk, Vector3.ZERO, Vector3(0.8, 0.03, 0.8), C(S.IRON, -0.1))
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.4
		mk.beam(Vector3(cos(a) * 0.38, 0.05, sin(a) * 0.38), Vector3(0, 0.62, 0), 0.09, C(S.WOOD, -0.18))
	flame(mk, Vector3(0, 0.05, 0), 0.28, 0.7)
	for sz in [-1.0, 1.0]:
		mk.cyl(Vector3(-0.55, 0.16, sz * 1.15), 0.16, 1.1, C(S.WOOD, -0.08), 6, Vector3.RIGHT, -1.0, false, true)

## Mastil con bandera: peana de dos escalones y mastil alto (lo exagerado) con
## remate de laton; la bandera del pais la cuelga ColonyFlag3D (PROCEDURAL_FLAG).
static func _flagpole(mk) -> void:
	block(mk, Vector3.ZERO, Vector3(1.0, 0.2, 1.0), C(S.STONE, -0.08))
	block(mk, Vector3(0, 0.2, 0), Vector3(0.6, 0.2, 0.6), C(S.STONE, 0.04))
	mk.cyl(Vector3(0, 0.4, 0), 0.07, 3.2, C(S.IRON, 0.08), 6, Vector3.UP, 0.05)
	mk.cyl(Vector3(0, 3.6, 0), 0.1, 0.18, C(S.BRASS), 6, Vector3.UP, 0.0)

## Palmeras: corro de arena y dos palmeras, una recta y otra inclinada, con
## las hojas caidas.
static func _palm_trees(mk) -> void:
	mk.cyl(Vector3.ZERO, 1.3, 0.05, C(S.CREAM, -0.08), 8)
	_palm(mk, Vector3(-0.45, 0.05, -0.3), Vector3(0.05, 1, 0), 2.4)
	_palm(mk, Vector3(0.55, 0.05, 0.35), Vector3(0.35, 1, 0.2).normalized(), 1.9)
	mk.box(Vector3(0.1, 0.12, 0.8), Vector3(0.25, 0.14, 0.22), C(S.STONE, -0.1))

## `nuts` = false: sin el racimo de cocos (la receta horneada, por presupuesto).
static func _palm(mk, base: Vector3, dir: Vector3, h: float, nuts := true) -> void:
	var trunk := C(S.WOOD, -0.02)
	var seg := h / 3.0
	var p := base
	var d := dir.normalized()
	for i in 3:
		mk.cyl(p, 0.12 - 0.02 * i, seg, trunk.darkened(0.05 * i), 5, d, 0.1 - 0.02 * i)
		p += d * seg
		d = (d + Vector3(dir.x, 0, dir.z) * 0.3).normalized()
	var leaf := C(S.GREEN, -0.04)
	for i in 5:
		var a := TAU * float(i) / 5.0
		var out := Vector3(cos(a), 0, sin(a))
		mk.beam(p, p + out * 0.6 + Vector3(0, 0.15, 0), 0.12, leaf)
		mk.beam(p + out * 0.6 + Vector3(0, 0.15, 0), p + out * 0.95 - Vector3(0, 0.3, 0), 0.1, leaf.darkened(0.08))
	if nuts:
		mk.ball(p - Vector3(0, 0.08, 0), 0.13, C(S.WOOD, -0.2))
