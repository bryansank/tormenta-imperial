extends RefCounted
## Los tres edificios de economia de la 1.2 (feat/edificios-economia, doc 21
## §6.3 n.º 13, 14 y 16) y el barco del contrabandista, en maqueta de juguete.
##
## Igual que UtilityToys: cada uno es UNA malla con color por vertice y los dos
## materiales comunes (ToyPalette), montada con LotMesh. Ningun `_process`,
## ningun material propio, nada de texturas (doc 21 §6.6). Todo propio, sin
## piezas CC0.
##
## - En el juego, `create(id)` devuelve el modelo horneado
##   (`assets/models/toy/<id>.tscn`, receta tools/toy_recipes/<id>.gd) si
##   existe y, si no, esta malla procedural, compartida por todas las instancias.
## - Al hornear, la receta llama a `build_core(mk, id)`.
## - `ship_mesh()`: el barco (una malla para todo el mapa, nunca horneada aparte:
##   ya es barata). Proa hacia +X, linea de flotacion en y = 0.
##
## Marco de los edificios: centro en el origen, suelo en y = 0, frente hacia +Z
## (el Puerto: el muelle, que da al agua), dentro de los 2,8 x 2,8 m que deja
## la parcela de 2x2 con patio 0.3.
##
## Presupuesto (doc 21 §6.6): <= 1.500 triangulos por edificio, el barco ~500.

const MeshKit := preload("res://scripts/buildings/LotMesh.gd")
const Palette := preload("res://scripts/buildings/ToyPalette.gd")
const U := preload("res://scripts/buildings/UtilityToys.gd")
const S := Palette.Slot

const IDS := ["trade_port", "exchange", "diesel_plant"]
const TOY_DIR := "res://assets/models/toy/"

static var _meshes: Dictionary = {}
static var _ship: ArrayMesh = null

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

static func mesh(id: String) -> ArrayMesh:
	if _meshes.has(id):
		return _meshes[id]
	var mk := MeshKit.new()
	build_core(mk, id)
	var m := mk.commit()
	if m != null:
		m.resource_name = id
	_meshes[id] = m
	return m

## Monta el edificio en `mk`. Devuelve {"fx": Vector3} donde lo haya (la boca
## de la chimenea de la Central, para el humo).
static func build_core(mk, id: String) -> Dictionary:
	match id:
		"trade_port": return _trade_port(mk)
		"exchange": return _exchange(mk)
		"diesel_plant": return _diesel_plant(mk)
	return {}

static func C(slot: int, d := 0.0) -> Color:
	return Palette.tint(slot, d)

# ══════════════════════════════════════════════════════════════════════
# Puerto comercial (civico, acento laton). Exagerado: la GRUA de laton que
# saca una caja por encima del muelle. Atras, el tinglado de las mercancias
# (piedra y pizarra, portalon abierto); delante, el muelle de tablones con su
# canto de piedra, norays, cajas, sacos y un farol.
# ══════════════════════════════════════════════════════════════════════

static func _trade_port(mk) -> Dictionary:
	var stone := C(S.STONE, -0.08)
	# Zocalo de piedra de toda la parcela del modelo
	U._block(mk, Vector3(0, 0, -0.3), Vector3(2.7, 0.12, 2.1), stone)
	# El muelle: tablones sobre el canto de piedra, en la mitad de delante
	U._block(mk, Vector3(0, 0, 0.95), Vector3(2.75, 0.16, 0.9), C(S.STONE, -0.2))
	for k in 7:
		var x := -1.2 + k * 0.4
		mk.box(Vector3(x, 0.19, 0.95), Vector3(0.36, 0.05, 0.86), U._wood(0.04 if k % 2 == 0 else -0.04))
	# Canto del muelle con defensas (neumaticos de madera) y norays
	mk.box(Vector3(0, 0.12, 1.39), Vector3(2.75, 0.12, 0.06), U._wood(-0.2))
	for x in [-1.0, 0.0, 1.0]:
		mk.cyl(Vector3(x, 0.22, 1.25), 0.07, 0.14, C(S.IRON, 0.05), 6)
		mk.ball(Vector3(x, 0.38, 1.25), 0.08, C(S.IRON, 0.05), Vector3(1, 0.6, 1))
	# El tinglado: nave de piedra con tejado de pizarra y portalon
	var shed := Vector3(-0.35, 0.12, -0.55)
	U._block(mk, shed, Vector3(1.8, 0.95, 1.2), C(S.CREAM, -0.06))
	U._gable(mk, shed + Vector3(0, 0.95, 0), 1.8, 1.2, 0.45, C(S.SLATE, -0.04), C(S.CREAM, -0.06))
	mk.box(shed + Vector3(0, 0.38, 0.61), Vector3(0.7, 0.76, 0.04), C(S.IRON, 0.15))
	mk.box(shed + Vector3(0, 0.38, 0.63), Vector3(0.6, 0.66, 0.02), C(S.IRON, -0.1))
	U._window(mk, shed + Vector3(-0.62, 0.62, 0.6), Vector3.BACK, 0.22, 0.2, C(S.IRON))
	U._window(mk, shed + Vector3(0.62, 0.62, 0.6), Vector3.BACK, 0.22, 0.2, C(S.IRON))
	# Rotulo de laton sobre el portalon
	mk.box(shed + Vector3(0, 0.88, 0.62), Vector3(0.9, 0.16, 0.04), C(S.BRASS, 0.05))
	# La grua (lo exagerado): torre de laton en la esquina derecha, pluma que
	# sale por encima del muelle hacia el agua y una caja colgando
	var foot := Vector3(0.95, 0.12, 0.2)
	mk.box(foot + Vector3(0, 0.08, 0), Vector3(0.5, 0.16, 0.5), C(S.IRON, 0.05))
	mk.box(foot + Vector3(0, 0.95, 0), Vector3(0.22, 1.6, 0.22), C(S.BRASS))
	for t in [0.35, 0.7]:
		mk.box(foot + Vector3(0, 1.6 * t + 0.16, 0), Vector3(0.28, 0.06, 0.28), C(S.IRON))
	mk.box(foot + Vector3(-0.05, 1.82, 0.05), Vector3(0.36, 0.3, 0.36), C(S.RED, -0.05))
	var jib0 := foot + Vector3(0, 1.85, 0)
	var jib1 := Vector3(0.55, 2.05, 1.28)
	mk.beam(jib0, jib1, 0.14, C(S.BRASS, 0.05))
	mk.beam(foot + Vector3(0, 2.15, 0), jib1, 0.05, C(S.IRON))
	mk.beam(jib1, jib1 + Vector3(0, -0.85, 0), 0.03, C(S.IRON))
	mk.box(jib1 + Vector3(0, -1.0, 0), Vector3(0.34, 0.28, 0.34), U._wood(0.06))
	mk.box(jib1 + Vector3(0, -1.0, 0), Vector3(0.36, 0.05, 0.36), C(S.IRON))
	# Mercancias en el muelle: cajas apiladas, sacos y un barril
	mk.box(Vector3(-0.95, 0.36, 0.9), Vector3(0.36, 0.3, 0.36), U._wood(0.02))
	mk.box(Vector3(-0.6, 0.36, 0.95), Vector3(0.3, 0.3, 0.3), U._wood(-0.06))
	mk.box(Vector3(-0.8, 0.66, 0.92), Vector3(0.3, 0.3, 0.3), U._wood(0.08))
	U._sack(mk, Vector3(-0.2, 0.22, 0.85))
	U._sack(mk, Vector3(0.05, 0.22, 0.95))
	U._barrel(mk, Vector3(0.3, 0.22, 0.8))
	U._lantern(mk, Vector3(-1.25, 0.22, 1.2), 0.75)
	# Banderin del puerto en el tinglado
	U._pennant(mk, shed + Vector3(-0.85, 1.4, 0.0), 0.8, C(S.BRASS), C(S.SKY))
	return {}

# ══════════════════════════════════════════════════════════════════════
# Casa de cambio (civico, acento laton). Exagerado: la GRAN moneda de oro en el
# fronton. Edificio de dos plantas con escalinata, cuatro columnas en el
# portico y dos estandartes rojos.
# ══════════════════════════════════════════════════════════════════════

static func _exchange(mk) -> Dictionary:
	var cream := C(S.CREAM, -0.02)
	# Zocalo y escalinata (tres peldanos hacia delante)
	U._block(mk, Vector3(0, 0, -0.15), Vector3(2.6, 0.18, 2.2), C(S.STONE, -0.05))
	for k in 3:
		U._block(mk, Vector3(0, 0, 1.0 + k * 0.12), Vector3(1.6 - k * 0.1, 0.18 - k * 0.06, 0.16), C(S.STONE, 0.05 - k * 0.05))
	# Cuerpo de dos plantas
	var body := Vector3(0, 0.18, -0.35)
	U._block(mk, body, Vector3(2.2, 1.55, 1.4), cream)
	mk.box(body + Vector3(0, 0.78, 0.71), Vector3(2.24, 0.08, 0.04), C(S.STONE, -0.05))
	for x in [-0.7, 0.7]:
		for y in [0.4, 1.15]:
			U._window(mk, body + Vector3(x, y, 0.7), Vector3.BACK, 0.26, 0.32, C(S.IRON))
	U._door(mk, body + Vector3(0, 0, 0.7), 0.42, 0.7, U._wood(-0.15))
	# Cornisa y tejado bajo de pizarra
	mk.box(body + Vector3(0, 1.6, 0), Vector3(2.36, 0.1, 1.56), C(S.STONE, 0.05))
	U._gable(mk, body + Vector3(0, 1.65, 0), 2.2, 1.4, 0.32, C(S.SLATE, -0.06), cream)
	# Portico: cuatro columnas y su dintel con fronton
	for x in [-0.75, -0.25, 0.25, 0.75]:
		mk.cyl(Vector3(x, 0.18, 0.62), 0.09, 1.25, C(S.CREAM, 0.06), 8)
		mk.box(Vector3(x, 0.24, 0.62), Vector3(0.24, 0.12, 0.24), C(S.STONE))
		mk.box(Vector3(x, 1.45, 0.62), Vector3(0.24, 0.08, 0.24), C(S.STONE))
	mk.box(Vector3(0, 1.55, 0.62), Vector3(1.85, 0.14, 0.3), C(S.STONE, 0.04))
	mk._tri(Vector3(-0.95, 1.62, 0.78), Vector3(0.95, 1.62, 0.78), Vector3(0, 2.0, 0.78), Vector3.BACK, C(S.CREAM, -0.05), false)
	mk._quad(Vector3(-0.95, 1.62, 0.46), Vector3(0, 2.0, 0.46), Vector3(0, 2.0, 0.78), Vector3(-0.95, 1.62, 0.78), Vector3(-0.38, 0.95, 0).normalized(), C(S.SLATE, -0.04), false)
	mk._quad(Vector3(0.95, 1.62, 0.46), Vector3(0, 2.0, 0.46), Vector3(0, 2.0, 0.78), Vector3(0.95, 1.62, 0.78), Vector3(0.38, 0.95, 0).normalized(), C(S.SLATE, -0.1), false)
	# La moneda (lo exagerado): disco de laton de canto, de cara al frente,
	# encima del fronton, con su sello en relieve
	var coin := Vector3(0, 2.55, 0.5)
	mk.cyl(coin + Vector3(0, 0, -0.06), 0.52, 0.12, C(S.BRASS, 0.08), 14, Vector3.BACK, -1.0, false, true)
	mk.cyl(coin + Vector3(0, 0, 0.06), 0.36, 0.03, C(S.BRASS, -0.12), 12, Vector3.BACK)
	mk.box(coin + Vector3(0, 0, 0.1), Vector3(0.08, 0.38, 0.03), C(S.BRASS, 0.15))
	mk.box(coin + Vector3(0, 0.12, 0.1), Vector3(0.26, 0.06, 0.03), C(S.BRASS, 0.15))
	mk.box(coin + Vector3(0, -0.12, 0.1), Vector3(0.26, 0.06, 0.03), C(S.BRASS, 0.15))
	mk.box(coin + Vector3(0, -0.6, -0.05), Vector3(0.12, 0.3, 0.12), C(S.IRON))
	# Estandartes rojos a los lados de la puerta
	for sx in [-1.0, 1.0]:
		var p := Vector3(sx * 1.15, 0.18, 0.55)
		mk.cyl(p, 0.035, 1.5, C(S.IRON, 0.1), 6)
		mk.box(p + Vector3(0, 1.15, 0.06), Vector3(0.3, 0.6, 0.03), C(S.RED))
		mk.box(p + Vector3(0, 1.15, 0.08), Vector3(0.12, 0.12, 0.02), C(S.BRASS))
	return {}

# ══════════════════════════════════════════════════════════════════════
# Central diesel (industrial, acento rojo). Exagerado: la CHIMENEA alta con
# franjas rojas y el gran volante de laton. Nave de chapa con lucernario,
# tanque de combustible, tuberias y valvulas rojas.
# ══════════════════════════════════════════════════════════════════════

## La boca de la chimenea (el humo sale de ahi).
const DIESEL_STACK := Vector3(0.9, 3.2, -0.75)

static func _diesel_plant(mk) -> Dictionary:
	U._block(mk, Vector3(0, 0, 0), Vector3(2.6, 0.1, 2.5), C(S.SLATE, -0.08))
	# La nave de las maquinas
	var hall := Vector3(-0.3, 0.1, -0.25)
	U._block(mk, hall, Vector3(1.8, 1.1, 1.6), C(S.SLATE, 0.12))
	for k in 5:
		mk.box(hall + Vector3(-0.8 + k * 0.4, 0.55, 0.81), Vector3(0.05, 1.1, 0.03), C(S.SLATE, -0.1))
	U._gable(mk, hall + Vector3(0, 1.1, 0), 1.8, 1.6, 0.35, C(S.IRON, 0.1), C(S.SLATE, 0.12))
	# Lucernario encendido a lo largo de la cumbrera
	mk.box(hall + Vector3(0, 1.5, 0), Vector3(1.4, 0.14, 0.3), C(S.GLOW), true)
	U._window(mk, hall + Vector3(-0.45, 0.6, 0.8), Vector3.BACK, 0.34, 0.3, C(S.IRON))
	U._window(mk, hall + Vector3(0.45, 0.6, 0.8), Vector3.BACK, 0.34, 0.3, C(S.IRON))
	mk.box(hall + Vector3(0, 0.3, 0.81), Vector3(0.4, 0.55, 0.03), C(S.RED, -0.15))
	# La chimenea (lo exagerado): alta, de ladrillo, con dos franjas rojas
	var base := Vector3(DIESEL_STACK.x, 0.1, DIESEL_STACK.z)
	U._block(mk, base, Vector3(0.6, 0.35, 0.6), C(S.STONE, -0.1))
	mk.cyl(base + Vector3(0, 0.35, 0), 0.24, DIESEL_STACK.y - 0.45, C(S.TERRACOTTA, -0.1), 10, Vector3.UP, 0.18)
	for t in [0.55, 0.85]:
		var y: float = 0.35 + (DIESEL_STACK.y - 0.45) * float(t)
		var r: float = lerpf(0.24, 0.18, float(t)) + 0.02
		mk.cyl(base + Vector3(0, y, 0), r, 0.14, C(S.RED), 10)
	mk.cyl(Vector3(DIESEL_STACK.x, DIESEL_STACK.y - 0.06, DIESEL_STACK.z), 0.22, 0.1, C(S.IRON), 10)
	# El volante de laton junto a la nave (de cara al frente)
	var wheel := Vector3(0.85, 0.75, 0.55)
	mk.box(Vector3(0.85, 0.1 + 0.25, 0.55), Vector3(0.24, 0.5, 0.3), C(S.IRON))
	mk.cyl(wheel + Vector3(0, 0, -0.07), 0.55, 0.14, C(S.BRASS), 12, Vector3.BACK, -1.0, false, true)
	mk.cyl(wheel + Vector3(0, 0, 0.07), 0.38, 0.04, C(S.BRASS, -0.2), 12, Vector3.BACK)
	for i in 4:
		var a := PI * 0.25 + float(i) * PI * 0.5
		mk.box(wheel + Vector3(cos(a) * 0.2, sin(a) * 0.2, 0.1), Vector3(0.07, 0.07, 0.04), C(S.IRON))
	mk.cyl(wheel + Vector3(0, 0, 0.08), 0.09, 0.08, C(S.RED), 6, Vector3.BACK)
	# Correa del volante a la nave
	mk.beam(wheel + Vector3(-0.3, 0.3, 0), hall + Vector3(0.9, 0.85, 0.5), 0.05, C(S.IRON, -0.1))
	# Tanque de combustible y tuberias
	U._tank(mk, Vector3(-0.85, 0.1, 0.85), 0.32, 0.55, C(S.CREAM, -0.05), C(S.RED))
	U._pipe(mk, Vector3(-0.55, 0.4, 0.85), Vector3(0.0, 0.4, 0.85), 0.06, C(S.SLATE, 0.2))
	U._pipe(mk, Vector3(0.0, 0.4, 0.85), Vector3(0.0, 0.4, 0.58), 0.06, C(S.SLATE, 0.2))
	U._valve(mk, Vector3(-0.25, 0.55, 0.85), 0.1, Vector3.UP)
	U._pipe(mk, hall + Vector3(0.9, 0.9, -0.3), base + Vector3(-0.3, 0.9, 0), 0.07, C(S.SLATE, 0.15))
	for p in [Vector3(0.2, 0.1, 1.05), Vector3(0.48, 0.1, 1.08)]:
		mk.cyl(p, 0.12, 0.32, C(S.RED, -0.1), 8)
		mk.cyl(p + Vector3(0, 0.11, 0), 0.13, 0.04, C(S.IRON), 8)
	return {"fx": DIESEL_STACK}

# ══════════════════════════════════════════════════════════════════════
# El barco del contrabandista: un vapor pequeno con vela. Casco oscuro con
# franja roja, cubierta de tablones, caseta con ventanas encendidas, chimenea
# con aro de laton, un palo con la vela parda y cajas en cubierta. Proa hacia
# +X, linea de flotacion en y = 0. ~420 triangulos.
# ══════════════════════════════════════════════════════════════════════

const SHIP_LENGTH := 4.2

static func ship_mesh() -> ArrayMesh:
	if _ship != null:
		return _ship
	var mk := MeshKit.new()
	_build_ship(mk)
	_ship = mk.commit()
	if _ship != null:
		_ship.resource_name = "smuggler_ship"
	return _ship

static func _build_ship(mk) -> void:
	var hull := C(S.IRON, 0.12)
	var deck_y := 0.42
	# Casco: contorno de cubierta (popa cuadrada, proa en punta) que baja hacia
	# una quilla mas estrecha
	var top := [Vector2(-2.0, -0.62), Vector2(1.1, -0.62), Vector2(2.1, 0.0), Vector2(1.1, 0.62), Vector2(-2.0, 0.62)]
	var bot := [Vector2(-1.8, -0.3), Vector2(0.9, -0.3), Vector2(1.7, 0.0), Vector2(0.9, 0.3), Vector2(-1.8, 0.3)]
	var y0 := -0.18
	for i in top.size():
		var j := (i + 1) % top.size()
		var a := Vector3(top[i].x, deck_y, top[i].y)
		var b := Vector3(top[j].x, deck_y, top[j].y)
		var c := Vector3(bot[j].x, y0, bot[j].y)
		var d := Vector3(bot[i].x, y0, bot[i].y)
		var n := (b - a).cross(d - a).normalized()
		if n.dot(Vector3((a.x + b.x) * 0.5, 0, (a.z + b.z) * 0.5)) < 0.0:
			n = -n
		mk._quad(a, b, c, d, n, hull, false)
		# Franja roja bajo la borda
		var a2 := a.lerp(d, 0.18)
		var b2 := b.lerp(c, 0.18)
		var a3 := a.lerp(d, 0.3)
		var b3 := b.lerp(c, 0.3)
		mk._quad(a2 + n * 0.01, b2 + n * 0.01, b3 + n * 0.01, a3 + n * 0.01, n, C(S.RED, -0.05), false)
	# Cubierta de tablones
	var deck := Vector3(0, deck_y, 0)
	mk._quad(deck + Vector3(top[0].x, 0, top[0].y), deck + Vector3(top[1].x, 0, top[1].y),
		deck + Vector3(top[3].x, 0, top[3].y), deck + Vector3(top[4].x, 0, top[4].y), Vector3.UP, U._wood(0.08), false)
	mk._tri(deck + Vector3(top[1].x, 0, top[1].y), deck + Vector3(top[2].x, 0, top[2].y),
		deck + Vector3(top[3].x, 0, top[3].y), Vector3.UP, U._wood(0.08), false)
	# Borda baja
	mk.box(Vector3(-0.45, deck_y + 0.07, -0.6), Vector3(3.1, 0.14, 0.05), U._wood(-0.12))
	mk.box(Vector3(-0.45, deck_y + 0.07, 0.6), Vector3(3.1, 0.14, 0.05), U._wood(-0.12))
	mk.box(Vector3(-1.98, deck_y + 0.07, 0), Vector3(0.05, 0.14, 1.2), U._wood(-0.12))
	# Caseta a popa con ventanas encendidas
	var cab := Vector3(-1.25, deck_y, 0)
	U._block(mk, cab, Vector3(0.9, 0.5, 0.8), C(S.CREAM, -0.08))
	mk.box(cab + Vector3(0, 0.55, 0), Vector3(1.0, 0.08, 0.9), C(S.SLATE, -0.05))
	for z in [-0.41, 0.41]:
		mk.box(cab + Vector3(0.1, 0.3, z), Vector3(0.36, 0.14, 0.02), C(S.GLOW), true)
	# Chimenea con aro de laton (vapor del contrabando)
	mk.cyl(cab + Vector3(0.6, 0.0, 0), 0.13, 1.05, C(S.IRON, 0.05), 8)
	mk.cyl(cab + Vector3(0.6, 0.78, 0), 0.15, 0.12, C(S.BRASS), 8)
	# Palo y vela parda (a lo largo del barco, se lee de perfil)
	var mast := Vector3(0.35, deck_y, 0)
	mk.cyl(mast, 0.05, 2.0, U._wood(-0.15), 6)
	mk.beam(mast + Vector3(-0.05, 0.45, 0), mast + Vector3(1.25, 0.45, 0), 0.05, U._wood(-0.15))
	mk._tri(mast + Vector3(0.0, 1.9, 0.02), mast + Vector3(0.05, 0.55, 0.02), mast + Vector3(1.2, 0.55, 0.02),
		Vector3.BACK, C(S.TERRACOTTA, -0.25), false)
	mk._tri(mast + Vector3(0.0, 1.9, -0.02), mast + Vector3(0.05, 0.55, -0.02), mast + Vector3(1.2, 0.55, -0.02),
		Vector3.FORWARD, C(S.TERRACOTTA, -0.32), false)
	# Banderin negro con la calavera (un punto crema) en lo alto
	mk.box(mast + Vector3(-0.18, 1.88, 0), Vector3(0.32, 0.18, 0.02), C(S.IRON, -0.1))
	mk.box(mast + Vector3(-0.18, 1.88, 0.015), Vector3(0.08, 0.08, 0.01), C(S.CREAM))
	# Mercancia en cubierta: cajas, un barril y un farol a proa
	mk.box(Vector3(0.95, deck_y + 0.15, -0.25), Vector3(0.3, 0.3, 0.3), U._wood(0.05))
	mk.box(Vector3(0.95, deck_y + 0.15, 0.2), Vector3(0.28, 0.3, 0.28), U._wood(-0.05))
	mk.box(Vector3(0.95, deck_y + 0.42, -0.05), Vector3(0.26, 0.24, 0.26), C(S.BRASS, -0.15))
	U._barrel(mk, Vector3(-0.3, deck_y, 0.32), 0.13, 0.3)
	mk.box(Vector3(1.75, deck_y + 0.28, 0), Vector3(0.1, 0.12, 0.1), C(S.GLOW), true)
	mk.cyl(Vector3(1.75, deck_y, 0), 0.025, 0.22, C(S.IRON), 4)
