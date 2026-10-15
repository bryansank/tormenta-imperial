extends RefCounted
## Los siete edificios utiles de la 1.1 (doc 21 §6.3, fila 2.6 del plan):
## Molino, Silo, Taberna, Carpinteria, Pozo, Faro y Deposito de combustible.
##
## Cada uno es UNA malla con color por vertice y los dos materiales comunes de
## la maqueta (ToyPalette), montada con LotMesh: una o dos llamadas de dibujo,
## ningun `_process`, ningun material propio (doc 21 §6.6).
##
## Dos usos:
## - En el juego, mientras no este horneado su modelo (`assets/models/toy/<id>.tscn`,
##   receta en tools/toy_recipes/<id>.gd), `create()` devuelve esta version
##   procedural completa (`full = true`), cacheada por id: todas las instancias
##   comparten la misma ArrayMesh. En cuanto el horneado exista, `create()` usa
##   el modelo horneado sin tocar el .tres.
## - Al hornear, la receta llama a `build_core(mk, id, false)`: el cuerpo propio
##   sin las piezas que la receta pone con CC0 (aspas, barriles, farol, torre,
##   depositos), y anade esas piezas encima.
##
## Marco: el del modelo horneado (centro en el origen, suelo en y = 0, frente
## hacia +Z), dentro del rectangulo que deja la parcela de 2x2 con patio 0.3
## (2.8 x 2.8 m). BuildingLot.fit_model lo encaja igual que a los demas.

const MeshKit := preload("res://scripts/buildings/LotMesh.gd")
const Palette := preload("res://scripts/buildings/ToyPalette.gd")
const S := Palette.Slot

const IDS := ["windmill", "silo", "tavern", "carpentry", "well", "lighthouse", "fuel_depot"]
const TOY_DIR := "res://assets/models/toy/"

static var _meshes: Dictionary = {}

static func handles(id: String) -> bool:
	return id in IDS

## El modelo para el mapa, el fantasma y la vista previa: el horneado si ya
## existe, si no la malla procedural (compartida). null si `id` no es de aqui.
static func create(id: String) -> Node3D:
	if not handles(id):
		return null
	var baked := TOY_DIR + id + ".tscn"
	if ResourceLoader.exists(baked):
		var scene := load(baked) as PackedScene
		if scene != null:
			var inst := scene.instantiate() as Node3D
			if inst != null:
				return inst
	var mi := MeshInstance3D.new()
	mi.name = "Toy_" + id
	mi.mesh = mesh(id)
	return mi

## La malla procedural completa de `id`, una sola por tipo para todo el mapa.
static func mesh(id: String) -> ArrayMesh:
	if _meshes.has(id):
		return _meshes[id]
	var mk := MeshKit.new()
	build_core(mk, id, true)
	var m := mk.commit()
	if m != null:
		m.resource_name = id
	_meshes[id] = m
	return m

## Monta el edificio en `mk`. `full`: tambien lo que en el horneado ponen las
## piezas CC0 (ver la cabecera). Devuelve {"fx": Vector3} donde lo haya.
static func build_core(mk, id: String, full: bool) -> Dictionary:
	match id:
		"windmill": return _windmill(mk, full)
		"silo": return _silo(mk, full)
		"tavern": return _tavern(mk, full)
		"carpentry": return _carpentry(mk, full)
		"well": return _well(mk, full)
		"lighthouse": return _lighthouse(mk, full)
		"fuel_depot": return _fuel_depot(mk, full)
	return {}

# ── Colores y piezas pequenas ─────────────────────────────────────────

static func C(slot: int, d := 0.0) -> Color:
	return Palette.tint(slot, d)

static func _wood(d := 0.0) -> Color:
	return C(S.WOOD, d - 0.04)

static func _block(mk, pos: Vector3, size: Vector3, col: Color, glow := false) -> void:
	mk.box(pos + Vector3(0, size.y * 0.5, 0), size, col, glow)

static func _face_basis(n: Vector3) -> Basis:
	n = n.normalized()
	var x := Vector3.UP.cross(n)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, n.cross(x).normalized(), n)

## Tejado a dos aguas con la cumbrera a lo largo de X: `c` en el centro a la
## altura del alero, `w` x `d` la planta que cubre, `h` lo que sube. Alero de
## 0.1 por lado; los pinones con el color de la pared.
static func _gable(mk, c: Vector3, w: float, d: float, h: float, roof: Color, wall: Color) -> void:
	var hw := w * 0.5 + 0.1
	var hd := d * 0.5 + 0.1
	var nf := Vector3(0, hd, h).normalized()
	var nb := Vector3(0, hd, -h).normalized()
	mk._quad(c + Vector3(-hw, 0, hd), c + Vector3(hw, 0, hd), c + Vector3(hw, h, 0), c + Vector3(-hw, h, 0), nf, roof, false)
	mk._quad(c + Vector3(-hw, 0, -hd), c + Vector3(hw, 0, -hd), c + Vector3(hw, h, 0), c + Vector3(-hw, h, 0), nb, roof.darkened(0.08), false)
	for sx in [-1.0, 1.0]:
		var x: float = sx * w * 0.5
		mk._tri(c + Vector3(x, 0, -d * 0.5), c + Vector3(x, 0, d * 0.5), c + Vector3(x, h, 0), Vector3(sx, 0, 0), wall.darkened(0.05), false)
	mk.box(c + Vector3(0, h + 0.04, 0), Vector3(w + 0.24, 0.08, 0.1), roof.darkened(0.2))

## Ventana encendida en la cara de normal `n` (centro `pos` sobre la pared).
static func _window(mk, pos: Vector3, n: Vector3, w: float, h: float, frame: Color) -> void:
	var saved: Transform3D = mk.xf
	mk.xf = saved * Transform3D(_face_basis(n), pos)
	mk.box(Vector3(0, 0, 0.03), Vector3(w + 0.1, h + 0.1, 0.06), frame)
	mk.box(Vector3(0, 0, 0.065), Vector3(w, h, 0.02), C(S.GLOW), true)
	mk.xf = saved

## Puerta en la cara +Z (frente), con su marco.
static func _door(mk, pos: Vector3, w: float, h: float, leaf: Color) -> void:
	mk.box(pos + Vector3(0, h * 0.5 + 0.02, 0.02), Vector3(w + 0.12, h + 0.06, 0.05), _wood(-0.18))
	mk.box(pos + Vector3(0, h * 0.5, 0.05), Vector3(w, h, 0.04), leaf)

## Barril de pie (sustituto del `kk:barrel` / `pir:barrel` del horneado).
static func _barrel(mk, base: Vector3, r := 0.15, h := 0.34) -> void:
	mk.cyl(base, r, h, _wood(-0.02), 8)
	for t in [0.22, 0.72]:
		mk.cyl(base + Vector3(0, h * t, 0), r + 0.015, 0.04, C(S.IRON, 0.1), 8)

## Saco de grano (sustituto del `kk:sack`).
static func _sack(mk, base: Vector3, s := 0.18) -> void:
	mk.ball(base + Vector3(0, s * 0.8, 0), s, C(S.CREAM, -0.12), Vector3(1.0, 0.85, 0.8))

## Farol encendido sobre un poste (sustituto del `ft:lantern`).
static func _lantern(mk, base: Vector3, h := 0.9) -> void:
	mk.cyl(base, 0.035, h, C(S.IRON, 0.1), 6)
	mk.box(base + Vector3(0, h + 0.08, 0), Vector3(0.14, 0.16, 0.14), C(S.GLOW), true)
	mk.cyl(base + Vector3(0, h + 0.16, 0), 0.11, 0.08, C(S.IRON), 6, Vector3.UP, 0.0)

## Mastil con banderola de dos franjas (sustituto del `pir:flag-high`).
static func _pennant(mk, base: Vector3, h: float, a: Color, b: Color) -> void:
	mk.cyl(base, 0.04, h, C(S.IRON, 0.1), 6)
	mk.ball(base + Vector3(0, h + 0.04, 0), 0.06, C(S.BRASS))
	mk.box(base + Vector3(0.26, h - 0.12, 0), Vector3(0.44, 0.14, 0.03), a)
	mk.box(base + Vector3(0.22, h - 0.26, 0), Vector3(0.36, 0.14, 0.03), b)

## Deposito vertical con cupula y aros (sustituto de `kn:detail-tank*`).
static func _tank(mk, base: Vector3, r: float, h: float, col: Color, band: Color) -> void:
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		mk.box(base + Vector3(cos(a) * r * 0.75, 0.08, sin(a) * r * 0.75), Vector3(0.1, 0.16, 0.1), C(S.IRON))
	mk.cyl(base + Vector3(0, 0.16, 0), r, h, col, 12)
	mk.ball(base + Vector3(0, 0.16 + h, 0), r, col.lightened(0.05), Vector3(1, 0.4, 1))
	for t in [0.2, 0.8]:
		mk.cyl(base + Vector3(0, 0.16 + h * t - 0.05, 0), r + 0.03, 0.1, band, 12)

static func _pipe(mk, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return
	mk.cyl(a, r, length, col, 6, d / length)

## Rueda de valvula roja de cara a `n` (el acento industrial).
static func _valve(mk, c: Vector3, r: float, n: Vector3) -> void:
	var saved: Transform3D = mk.xf
	mk.xf = saved * Transform3D(_face_basis(n), c)
	mk.cyl(Vector3(0, 0, -0.03), r, 0.06, C(S.RED), 8, Vector3.BACK, -1.0, false, true)
	mk.cyl(Vector3(0, 0, 0.0), r * 0.35, 0.06, C(S.IRON), 6, Vector3.BACK)
	mk.xf = saved

# ══════════════════════════════════════════════════════════════════════
# Molino (residencial, acento verde). Exagerado: las aspas, mas grandes de lo
# que pediria la torre. Torre de piedra encalada, caperuza de madera, sacos de
# harina y un carro a la puerta.
# ══════════════════════════════════════════════════════════════════════

## Centro del buje de las aspas (lo usa la receta para colocar `ft:windmill`).
const WINDMILL_HUB := Vector3(0.0, 2.55, 0.62)
const WINDMILL_BLADE := 1.2

static func _windmill(mk, full: bool) -> Dictionary:
	var stone := C(S.CREAM, -0.04)
	_block(mk, Vector3(0, 0, -0.1), Vector3(1.7, 0.14, 1.7), C(S.STONE, -0.1))
	# Torre troncocónica de 8 lados y su cornisa
	mk.cyl(Vector3(0, 0.14, -0.1), 0.72, 2.1, stone, 8, Vector3.UP, 0.56)
	mk.cyl(Vector3(0, 0.95, -0.1), 0.66, 0.08, C(S.STONE, -0.05), 8)
	mk.cyl(Vector3(0, 2.2, -0.1), 0.62, 0.1, _wood(-0.15), 8)
	# Caperuza de madera (cono) con su bola de laton
	mk.cyl(Vector3(0, 2.3, -0.1), 0.64, 0.75, _wood(0.02), 8, Vector3.UP, 0.0)
	mk.ball(Vector3(0, 3.1, -0.1), 0.08, C(S.BRASS))
	# Puerta, dos ventanas encendidas
	_door(mk, Vector3(0, 0.14, 0.58), 0.38, 0.62, C(S.GREEN, -0.1))
	_window(mk, Vector3(0, 1.55, 0.5), Vector3.BACK, 0.22, 0.26, _wood(-0.15))
	_window(mk, Vector3(-0.62, 1.2, -0.1), Vector3.LEFT, 0.2, 0.24, _wood(-0.15))
	# El eje que sale de la caperuza
	mk.cyl(Vector3(0, WINDMILL_HUB.y, 0.25), 0.07, WINDMILL_HUB.z - 0.25, C(S.IRON), 6, Vector3.BACK)
	if full:
		_windmill_blades(mk)
	# Cobertizo del grano a un lado, sacos y carro
	_block(mk, Vector3(0.95, 0, 0.45), Vector3(0.6, 0.55, 0.7), _wood(0.05))
	_gable(mk, Vector3(0.95, 0.55, 0.45), 0.6, 0.7, 0.28, C(S.TERRACOTTA), _wood(0.05))
	if full:
		for p in [Vector3(-0.55, 0, 0.85), Vector3(-0.8, 0, 0.7), Vector3(-0.66, 0.22, 0.78)]:
			_sack(mk, p)
		_barrel(mk, Vector3(0.55, 0, 1.0))
	return {}

## Las aspas: cuatro brazos con su tela de tablillas, en el plano XY, frente +Z.
static func _windmill_blades(mk) -> void:
	var hub := WINDMILL_HUB
	mk.ball(hub, 0.12, C(S.BRASS))
	for k in 4:
		var a := PI * 0.25 + float(k) * PI * 0.5
		var dir := Vector3(cos(a), sin(a), 0)
		var side := Vector3(-dir.y, dir.x, 0)
		mk.beam(hub, hub + dir * WINDMILL_BLADE, 0.06, _wood(-0.2))
		# La tela: una tabla ancha a un lado del brazo
		var mid := hub + dir * (WINDMILL_BLADE * 0.58) + side * 0.12 + Vector3(0, 0, 0.02)
		var saved: Transform3D = mk.xf
		mk.xf = saved * Transform3D(Basis(Vector3.BACK, a), mid)
		mk.box(Vector3.ZERO, Vector3(WINDMILL_BLADE * 0.8, 0.22, 0.03), C(S.CREAM, -0.02))
		mk.xf = saved

# ══════════════════════════════════════════════════════════════════════
# Silo (residencial). Exagerado: los dos silos altos de chapa con aros de
# laton y caperuza de teja. Tolva y caseta de carga delante.
# ══════════════════════════════════════════════════════════════════════

static func _silo(mk, full: bool) -> Dictionary:
	_block(mk, Vector3(0, 0, 0), Vector3(2.5, 0.12, 2.3), C(S.STONE, -0.1))
	var body := C(S.SLATE, 0.12)
	for p in [Vector3(-0.55, 0.12, -0.45), Vector3(0.6, 0.12, -0.35)]:
		var h: float = 2.5 if p.x < 0.0 else 2.1
		var r: float = 0.55 if p.x < 0.0 else 0.48
		mk.cyl(p, r, h, body, 10)
		for t in [0.15, 0.5, 0.85]:
			mk.cyl(p + Vector3(0, h * t, 0), r + 0.03, 0.07, C(S.BRASS), 10)
		mk.cyl(p + Vector3(0, h, 0), r + 0.08, 0.5, C(S.TERRACOTTA), 10, Vector3.UP, 0.05)
		# Escalerilla de servicio por delante
		for sx in [-0.09, 0.09]:
			mk.box(p + Vector3(sx, h * 0.5, r + 0.04), Vector3(0.03, h, 0.03), C(S.IRON, 0.1))
	# Pasarela entre los dos y la tolva que baja a la caseta
	mk.beam(Vector3(-0.55, 2.3, -0.45), Vector3(0.6, 2.0, -0.35), 0.1, C(S.IRON, 0.08))
	_pipe(mk, Vector3(0.6, 1.2, -0.05), Vector3(0.6, 0.75, 0.45), 0.1, C(S.BRASS, -0.05))
	_block(mk, Vector3(0.6, 0.12, 0.75), Vector3(0.8, 0.6, 0.6), _wood(0.04))
	_gable(mk, Vector3(0.6, 0.72, 0.75), 0.8, 0.6, 0.25, C(S.SLATE, -0.05), _wood(0.04))
	_door(mk, Vector3(0.6, 0.12, 1.05), 0.36, 0.48, _wood(-0.1))
	if full:
		for p in [Vector3(-0.6, 0.12, 0.8), Vector3(-0.85, 0.12, 0.62), Vector3(-0.35, 0.12, 0.95)]:
			_sack(mk, p, 0.17)
		_barrel(mk, Vector3(-1.05, 0.12, 0.95))
	return {}

# ══════════════════════════════════════════════════════════════════════
# Taberna (civico, acento laton). Exagerado: el gran letrero colgado con la
# jarra dorada. Dos plantas de enlucido con entramado, ventanas encendidas,
# bancos y barriles a la puerta, chimenea con humo.
# ══════════════════════════════════════════════════════════════════════

static func _tavern(mk, full: bool) -> Dictionary:
	var cream := C(S.CREAM)
	var beam := _wood(-0.18)
	var c := Vector3(0, 0, -0.35)
	_block(mk, c, Vector3(2.4, 0.12, 1.75), C(S.STONE, -0.12))
	_block(mk, c + Vector3(0, 0.12, 0), Vector3(2.2, 1.6, 1.5), cream)
	# Entramado: postes en las esquinas y viga entre plantas
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mk.box(c + Vector3(sx * 1.09, 0.92, sz * 0.74), Vector3(0.1, 1.6, 0.1), beam)
	mk.box(c + Vector3(0, 0.9, 0.76), Vector3(2.22, 0.09, 0.06), beam)
	_gable(mk, c + Vector3(0, 1.72, 0), 2.2, 1.5, 0.8, C(S.TERRACOTTA), cream)
	# Chimenea de ladrillo (de ella sale el humo)
	var chim := Vector3(-0.65, 1.75, -0.75)
	mk.box(chim + Vector3(0, 0.45, 0), Vector3(0.3, 0.9, 0.3), C(S.TERRACOTTA, -0.15))
	mk.box(chim + Vector3(0, 0.93, 0), Vector3(0.38, 0.08, 0.38), C(S.IRON))
	var fz := c.z + 0.75
	_door(mk, Vector3(-0.35, 0.12, fz), 0.5, 0.7, C(S.GREEN, -0.12))
	for x in [0.35, 0.8]:
		_window(mk, Vector3(x, 0.55, fz), Vector3.BACK, 0.3, 0.28, beam)
	for x in [-0.6, 0.0, 0.6]:
		_window(mk, Vector3(x, 1.32, fz), Vector3.BACK, 0.3, 0.28, beam)
	_window(mk, Vector3(1.1, 0.55, c.z), Vector3.RIGHT, 0.3, 0.28, beam)
	# El letrero exagerado: brazo de hierro y tabla de laton con la jarra
	mk.beam(Vector3(-0.95, 1.5, fz + 0.02), Vector3(-0.95, 1.5, fz + 0.62), 0.05, C(S.IRON, 0.1))
	mk.box(Vector3(-0.95, 1.18, fz + 0.5), Vector3(0.06, 0.55, 0.62), C(S.BRASS))
	mk.box(Vector3(-0.92, 1.18, fz + 0.5), Vector3(0.04, 0.3, 0.2), C(S.CREAM))
	mk.box(Vector3(-0.91, 1.18, fz + 0.62), Vector3(0.04, 0.16, 0.06), C(S.CREAM))
	# Bancos y mesa delante
	for x in [0.25, 0.95]:
		mk.box(Vector3(x, 0.2, fz + 0.45), Vector3(0.5, 0.06, 0.18), _wood(0.05))
		mk.box(Vector3(x, 0.1, fz + 0.45), Vector3(0.06, 0.2, 0.14), beam)
	_block(mk, Vector3(0.6, 0, fz + 0.75), Vector3(0.5, 0.36, 0.32), _wood(0.0))
	if full:
		_barrel(mk, Vector3(-0.95, 0, fz + 0.95))
		_barrel(mk, Vector3(-0.62, 0, fz + 1.0))
		_barrel(mk, Vector3(-0.8, 0.34, fz + 0.97), 0.13, 0.28)
		_lantern(mk, Vector3(1.15, 0, fz + 1.0), 0.95)
	return {"fx": chim + Vector3(0, 1.0, 0)}

# ══════════════════════════════════════════════════════════════════════
# Carpinteria (industrial, acento rojo). Exagerado: el gran caballete de
# tablones apoyados, mas alto que el cobertizo. Cobertizo abierto de postes
# con banco de trabajo y la sierra de mano roja colgada.
# ══════════════════════════════════════════════════════════════════════

static func _carpentry(mk, full: bool) -> Dictionary:
	var post := _wood(-0.15)
	_block(mk, Vector3(0, 0, -0.25), Vector3(2.4, 0.1, 1.8), _wood(0.12))
	# Cobertizo: cuatro postes y tejado de una agua (de chapa)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var h: float = 1.55 if sz < 0.0 else 1.25
			mk.box(Vector3(sx * 1.0, 0.1 + h * 0.5, -0.25 + sz * 0.72), Vector3(0.12, h, 0.12), post)
	var a := atan2(0.3, 1.6)
	var saved: Transform3D = mk.xf
	mk.xf = saved * Transform3D(Basis(Vector3.RIGHT, a), Vector3(0, 1.55, -0.25))
	mk.box(Vector3.ZERO, Vector3(2.3, 0.08, 1.85), C(S.SLATE, 0.05), false, true)
	mk.xf = saved
	# Pared de fondo de tablas
	mk.box(Vector3(0, 0.85, -0.95), Vector3(2.0, 1.5, 0.08), _wood(0.0))
	# Banco de trabajo con un tablon y la sierra roja colgada en la pared
	_block(mk, Vector3(-0.3, 0.1, -0.35), Vector3(1.2, 0.5, 0.5), _wood(-0.06))
	mk.box(Vector3(-0.3, 0.64, -0.35), Vector3(1.1, 0.05, 0.22), _wood(0.15))
	mk.box(Vector3(0.4, 1.0, -0.89), Vector3(0.5, 0.16, 0.03), C(S.SLATE, 0.2))
	mk.box(Vector3(0.68, 1.0, -0.88), Vector3(0.14, 0.12, 0.05), C(S.RED))
	# El caballete exagerado: un bastidor en A con tablones de pie
	var rack := Vector3(1.0, 0.1, 0.65)
	mk.beam(rack + Vector3(-0.45, 0, 0.18), rack + Vector3(0, 2.0, 0), 0.07, post)
	mk.beam(rack + Vector3(0.45, 0, 0.18), rack + Vector3(0, 2.0, 0), 0.07, post)
	mk.box(rack + Vector3(0, 0.08, 0.2), Vector3(1.0, 0.08, 0.14), post)
	for k in 5:
		var x := -0.36 + k * 0.18
		var lean := Basis(Vector3.RIGHT, -0.18)
		var s2: Transform3D = mk.xf
		mk.xf = s2 * Transform3D(lean, rack + Vector3(x, 0.95, 0.06))
		mk.box(Vector3.ZERO, Vector3(0.13, 1.8 - 0.12 * (k % 2), 0.05), _wood(0.12 - 0.05 * (k % 3)))
		mk.xf = s2
	if full:
		# Pila de tablones y troncos a la izquierda
		for l in 3:
			mk.box(Vector3(-0.95, 0.15 + l * 0.09, 0.75), Vector3(0.8, 0.08, 0.36), _wood(0.12 - 0.04 * (l % 2)))
		mk.cyl(Vector3(-1.2, 0.18, 0.25), 0.14, 0.7, _wood(-0.12), 7, Vector3.BACK)
		_barrel(mk, Vector3(0.1, 0.1, 0.95))
	return {"fx": Vector3(-0.3, 0.75, -0.35)}

# ══════════════════════════════════════════════════════════════════════
# Pozo (civico, acento laton). Exagerado: la bomba de laton con su gran
# volante. Brocal de piedra, tejadillo, cubos rojos contra el fuego.
# ══════════════════════════════════════════════════════════════════════

static func _well(mk, full: bool) -> Dictionary:
	# Plaza de losas
	_block(mk, Vector3(0, 0, 0), Vector3(2.3, 0.08, 2.3), C(S.STONE, 0.02))
	var wc := Vector3(-0.15, 0.08, -0.15)
	# Brocal y agua
	mk.cyl(wc, 0.62, 0.55, C(S.STONE, -0.08), 10)
	mk.cyl(wc + Vector3(0, 0.55, 0), 0.68, 0.08, C(S.STONE, 0.06), 10)
	mk.cyl(wc + Vector3(0, 0.6, 0), 0.5, 0.04, C(S.SKY, -0.18), 10)
	# Tejadillo sobre dos postes, con el torno y la cuerda
	for sx in [-1.0, 1.0]:
		mk.box(wc + Vector3(sx * 0.6, 0.85, 0), Vector3(0.1, 1.6, 0.1), _wood(-0.15))
	mk.cyl(wc + Vector3(-0.6, 1.25, 0), 0.06, 1.2, _wood(-0.05), 6, Vector3.RIGHT)
	mk.beam(wc + Vector3(0, 1.25, 0), wc + Vector3(0, 0.85, 0), 0.025, C(S.CREAM, -0.2))
	_gable(mk, wc + Vector3(0, 1.62, 0), 1.3, 0.9, 0.42, C(S.TERRACOTTA), _wood(-0.1))
	# La bomba de laton (exagerada) con su volante y el canalon
	var pump := Vector3(0.75, 0.08, 0.55)
	mk.cyl(pump, 0.16, 1.05, C(S.BRASS), 8)
	mk.ball(pump + Vector3(0, 1.08, 0), 0.18, C(S.BRASS, 0.08))
	_valve(mk, pump + Vector3(-0.2, 0.75, 0), 0.32, Vector3.LEFT)
	_pipe(mk, pump + Vector3(0, 0.6, 0.12), pump + Vector3(0, 0.6, 0.5), 0.06, C(S.BRASS, -0.08))
	# Pila del agua bajo el canalon
	_block(mk, pump + Vector3(0, 0, 0.6), Vector3(0.5, 0.22, 0.32), C(S.STONE, -0.05))
	mk.box(pump + Vector3(0, 0.23, 0.6), Vector3(0.38, 0.02, 0.2), C(S.SKY, -0.1))
	# Cubos rojos contra el fuego colgados de un listón
	mk.box(Vector3(-0.85, 0.65, 0.85), Vector3(0.7, 0.06, 0.06), _wood(-0.15))
	for sx in [-1.0, 1.0]:
		mk.box(Vector3(-0.85 + sx * 0.33, 0.35, 0.85), Vector3(0.06, 0.62, 0.06), _wood(-0.15))
	if full:
		for k in 3:
			mk.cyl(Vector3(-1.1 + k * 0.25, 0.42, 0.88), 0.08, 0.18, C(S.RED), 8, Vector3.UP, 0.1)
		_barrel(mk, Vector3(0.95, 0.08, -0.8), 0.15, 0.3)
	return {}

# ══════════════════════════════════════════════════════════════════════
# Faro / torre de vigia (militar, acento amarillo). Exagerado: el fanal
# encendido con su reflector. Torre de piedra con franjas rojas, galeria de
# hierro y caperuza roja; caseta del vigia al pie.
# ══════════════════════════════════════════════════════════════════════

## Altura de la galeria en la version procedural.
const LIGHTHOUSE_TOWER_H := 2.6

static func _lighthouse(mk, full: bool) -> Dictionary:
	_block(mk, Vector3(0, 0, 0), Vector3(2.4, 0.12, 2.4), C(S.STONE, -0.1))
	var base := Vector3(-0.15, 0.12, -0.2)
	if full:
		mk.cyl(base, 0.68, LIGHTHOUSE_TOWER_H, C(S.CREAM, -0.02), 10, Vector3.UP, 0.48)
		for t in [0.22, 0.62]:
			var r := lerpf(0.68, 0.48, t) + 0.02
			mk.cyl(base + Vector3(0, LIGHTHOUSE_TOWER_H * t, 0), r, 0.28, C(S.RED), 10)
		_door(mk, base + Vector3(0, 0, 0.66), 0.32, 0.56, _wood(-0.1))
		_window(mk, base + Vector3(0, 1.75, 0.53), Vector3.BACK, 0.16, 0.22, C(S.IRON))
		lighthouse_lamp(mk, base + Vector3(0, LIGHTHOUSE_TOWER_H, 0))
		_pennant(mk, Vector3(0.95, 0.12, -0.95), 2.0, C(S.BRASS), C(S.IRON))
	# Caseta del vigia con su ventana y sacos terreros
	var hut := Vector3(0.75, 0.12, 0.65)
	_block(mk, hut, Vector3(0.75, 0.6, 0.6), C(S.STONE, 0.02))
	_gable(mk, hut + Vector3(0, 0.6, 0), 0.75, 0.6, 0.25, C(S.SLATE, -0.05), C(S.STONE, 0.02))
	_window(mk, hut + Vector3(0, 0.35, 0.3), Vector3.BACK, 0.24, 0.18, C(S.IRON))
	for k in 3:
		mk.box(Vector3(-0.9 + k * 0.32, 0.2, 0.95), Vector3(0.3, 0.16, 0.2), C(S.CREAM, -0.18))
	return {}

## El remate del Faro sobre `top` (la cima de la torre): galeria con baranda,
## fanal encendido, reflector y caperuza roja. Lo usa tambien la receta encima
## de `pir:tower-complete-small`.
static func lighthouse_lamp(mk, top: Vector3) -> void:
	mk.cyl(top, 0.72, 0.08, C(S.IRON, 0.05), 10)
	for i in 8:
		var a := TAU * float(i) / 8.0
		mk.box(top + Vector3(cos(a) * 0.66, 0.2, sin(a) * 0.66), Vector3(0.04, 0.3, 0.04), C(S.IRON, 0.1))
	mk.cyl(top + Vector3(0, 0.33, 0), 0.68, 0.04, C(S.BRASS, -0.05), 10)
	# El fanal: cristal encendido (sin luz real) y el reflector hacia delante
	mk.cyl(top + Vector3(0, 0.08, 0), 0.36, 0.55, C(S.GLOW), 8, Vector3.UP, -1.0, true)
	mk.cyl(top + Vector3(0, 0.32, 0.12), 0.18, 0.5, C(S.GLOW), 8, Vector3.BACK, 0.34, true)
	mk.cyl(top + Vector3(0, 0.63, 0), 0.46, 0.45, C(S.RED), 8, Vector3.UP, 0.0)
	mk.ball(top + Vector3(0, 1.1, 0), 0.08, C(S.BRASS))

# ══════════════════════════════════════════════════════════════════════
# Deposito de combustible (industrial, acento rojo). Exagerado: el gran tanque
# con franja de peligro y cupula. Suelo de chapa, colector de tuberias con
# valvulas rojas y bidones.
# ══════════════════════════════════════════════════════════════════════

static func _fuel_depot(mk, full: bool) -> Dictionary:
	_block(mk, Vector3(0, 0, 0), Vector3(2.5, 0.1, 2.4), C(S.SLATE, -0.06))
	if full:
		_tank(mk, Vector3(-0.45, 0.1, -0.35), 0.75, 1.8, C(S.CREAM, -0.05), C(S.RED))
		_tank(mk, Vector3(0.8, 0.1, -0.55), 0.45, 1.1, C(S.SLATE, 0.18), C(S.BRASS))
		# Franja de peligro del grande
		for i in 8:
			var a := TAU * float(i) / 8.0
			mk.box(Vector3(-0.45, 1.25, -0.35) + Vector3(cos(a), 0, sin(a)) * 0.77, Vector3(0.2, 0.14, 0.2), C(S.BRASS) if i % 2 == 0 else C(S.IRON))
	# Colector: tuberia que sale de los tanques hacia la boca de carga
	_pipe(mk, Vector3(-0.45, 0.45, 0.42), Vector3(0.9, 0.45, 0.42), 0.08, C(S.SLATE, 0.2))
	_pipe(mk, Vector3(0.8, 0.45, -0.1), Vector3(0.8, 0.45, 0.42), 0.07, C(S.SLATE, 0.2))
	for x in [-0.1, 0.5]:
		mk.cyl(Vector3(x, 0.1, 0.42), 0.05, 0.35, C(S.IRON), 6)
		_valve(mk, Vector3(x, 0.62, 0.42), 0.12, Vector3.UP)
	# Boca de carga con su manguera
	_block(mk, Vector3(1.0, 0.1, 0.75), Vector3(0.35, 0.55, 0.3), C(S.RED, -0.05))
	mk.box(Vector3(1.0, 0.5, 0.92), Vector3(0.2, 0.12, 0.04), C(S.GLOW), true)
	if full:
		for p in [Vector3(-0.9, 0.1, 0.9), Vector3(-0.6, 0.1, 0.98), Vector3(-0.3, 0.1, 0.9)]:
			mk.cyl(p, 0.14, 0.36, C(S.RED, -0.1), 8)
			mk.cyl(p + Vector3(0, 0.12, 0), 0.15, 0.04, C(S.IRON), 8)
	return {}
