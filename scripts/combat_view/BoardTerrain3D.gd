extends RefCounted
## El terreno del tablero 3D: una maqueta de 8x8 sobre su peana, puesta encima
## de la mesa de guerra. Casillas legibles (losetas de hierba a dos tonos, alguna
## de tierra, craters de obus pintados en el suelo), y en el borde, FUERA de las
## casillas, el atrezo: sacos terreros delante de cada bando, arbolitos, piedras,
## un poste de senales. Nada de lo que hay sobre una casilla parece un obstaculo:
## las reglas no tienen coberturas y el tablero no debe insinuarlas.
##
## Una sola malla con color por vertice y los dos materiales de la maqueta
## (LotMesh, ToyPalette): una llamada de dibujo. Se monta al abrir el tablero
## con una semilla del encuentro (cada pelea tiene su terreno) y no cambia.

const MeshKit := preload("res://scripts/buildings/LotMesh.gd")
const Palette := preload("res://scripts/buildings/ToyPalette.gd")
const Layout := preload("res://scripts/combat_view/BoardLayout3D.gd")
const S := Palette.Slot

## Borde de la peana alrededor de las casillas (metros).
const MARGIN := 1.7
const TILE_GAP := 0.1
const TILE_H := 0.14
## Cuanto baja la mesa de guerra bajo la peana.
const TABLE_Y := -0.75
## La mesa de guerra: madera muy oscura, apagada, para que la maqueta mande.
const TABLE_COLOR := Color(0.16, 0.11, 0.085)

## Escenarios (2026-10-12): los enemigos pueden llegar como sea. Solo cambia el
## decorado ALREDEDOR del 8x8; las casillas y las reglas son las mismas.
##   land   — campo abierto: sacos terreros, arbolitos y piedras (el de siempre).
##   beach  — playa: el fondo (lado de la Regencia) es arena y mar, con las
##            lanchas de los recaudadores varadas y un embarcadero.
##   forest — linde de bosque: arboleda cerrada por el fondo y un costado,
##            troncos cortados y tocones.
const SCENE_LAND := "land"
const SCENE_BEACH := "beach"
const SCENE_FOREST := "forest"
const SCENES := [SCENE_LAND, SCENE_BEACH, SCENE_FOREST]
## El morado de la Regencia (el mismo que hornea build_toy_models.gd).
const REGENCY := Color8(104, 58, 122)

## Que escenario toca. En casa (el Diezmo, el asedio) la Regencia viene por mar
## a la isla: playa casi siempre. Fuera, lo que salga de la semilla.
static func pick_scene(seed_value: int, is_defense: bool) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 2654435761 + 17
	var r := rng.randf()
	if is_defense:
		return SCENE_BEACH if r < 0.7 else SCENE_LAND
	if r < 0.4:
		return SCENE_LAND
	return SCENE_FOREST if r < 0.75 else SCENE_BEACH

static func C(slot: int, d := 0.0) -> Color:
	return Palette.tint(slot, d)

## `front` (la vista frontal, docs/15 §3 "Las dos vistas"): el mismo decorado de
## borde, pero el suelo es un CAMPO seguido que llega al horizonte, sin losetas
## ni juntas: no se ve ninguna casilla. Y menos cajas que el tablero (un plano
## para el campo en vez de 64 losetas), asi que no cuesta mas.
static func build(board: Vector2i, seed_value: int, simple := false, scene := SCENE_LAND, front := false) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mk := MeshKit.new()
	var ext := Layout.board_extent(board)
	var w := ext.x + MARGIN * 2.0
	var d := ext.y + MARGIN * 2.0
	if front:
		_field(mk, board, ext, rng, simple, scene)
		_edges(mk, board, ext, rng, simple, scene)
		match scene:
			SCENE_BEACH:
				_beach(mk, ext, w, d, rng, simple)
			SCENE_FOREST:
				_forest(mk, ext, rng, simple)
		_far_trees(mk, ext, rng, simple, scene)
		_divider(mk, ext, rng, simple, scene)
		return mk.commit()

	# La mesa de guerra: madera oscura, muy grande, para que la maqueta no flote.
	mk.flat(Vector3(0, TABLE_Y, 0), Vector2(w * 8.0, d * 8.0), TABLE_COLOR)
	# Peana: costados de madera, canto de laton y la tierra del borde.
	mk.box(Vector3(0, (TABLE_Y - 0.12) * 0.5, 0), Vector3(w, -0.12 - TABLE_Y, d), C(S.WOOD, -0.2))
	mk.box(Vector3(0, -0.15, 0), Vector3(w + 0.08, 0.06, d + 0.08), C(S.BRASS, -0.12))
	mk.flat(Vector3(0, -0.11, 0), Vector2(w, d), C(S.GREEN, -0.3))
	# Zocalo oscuro bajo las casillas: entre loseta y loseta se ve la junta.
	mk.box(Vector3(0, -0.13, 0), Vector3(ext.x + 0.16, 0.05, ext.y + 0.16), C(S.IRON, 0.1))

	_tiles(mk, board, rng, simple)
	_edges(mk, board, ext, rng, simple, scene)
	match scene:
		SCENE_BEACH:
			_beach(mk, ext, w, d, rng, simple)
		SCENE_FOREST:
			_forest(mk, ext, rng, simple)
	return mk.commit()

static func _tiles(mk, board: Vector2i, rng: RandomNumberGenerator, simple: bool) -> void:
	var size := Layout.CELL - TILE_GAP
	# Craters: dos o tres en la tierra de nadie (filas centrales).
	var craters := {}
	for i in rng.randi_range(2, 3):
		craters[Vector2i(rng.randi_range(0, board.x - 1), rng.randi_range(2, board.y - 3))] = true
	for y in board.y:
		for x in board.x:
			var cell := Vector2i(x, y)
			var c := Layout.cell_to_world(cell, board)
			var dark := (x + y) % 2 == 1
			var col := C(S.GREEN, -0.04 if not dark else -0.14)
			var dirt := rng.randf() < 0.14 and not craters.has(cell)
			if dirt:
				# Tierra batida: parda y apagada, que no compita con las marcas.
				col = C(S.STONE, -0.12 if not dark else -0.2).lerp(C(S.WOOD, 0.0), 0.35)
			col = col.darkened(rng.randf() * 0.04)
			mk.box(c + Vector3(0, -TILE_H * 0.5, 0), Vector3(size, TILE_H, size), col)
			if craters.has(cell):
				# Mancha de tierra quemada con un labio de terrones: pintada en el
				# suelo (2 cm), se pisa como cualquier casilla.
				mk.cyl(c + Vector3(0, 0.0, 0), 0.66, 0.02, C(S.WOOD, -0.25), 9)
				mk.cyl(c + Vector3(0, 0.0, 0), 0.4, 0.025, C(S.IRON, 0.05), 7)
				if not simple:
					for k in 5:
						var a := TAU * float(k) / 5.0 + rng.randf() * 0.4
						mk.box(c + Vector3(cos(a) * 0.7, 0.03, sin(a) * 0.7), Vector3(0.16, 0.06, 0.12), C(S.WOOD, -0.12))
			elif not simple and rng.randf() < 0.32:
				# Mata de hierba o piedrecita en una esquina, nunca en el centro.
				var corner := Vector3(0.62 * (1.0 if rng.randf() < 0.5 else -1.0), 0, 0.62 * (1.0 if rng.randf() < 0.5 else -1.0))
				if rng.randf() < 0.7:
					mk.box(c + corner + Vector3(0, 0.05, 0), Vector3(0.08, 0.1, 0.08), C(S.GREEN, 0.06))
					mk.box(c + corner + Vector3(0.09, 0.04, 0.05), Vector3(0.07, 0.08, 0.07), C(S.GREEN, 0.0))
				else:
					mk.box(c + corner + Vector3(0, 0.03, 0), Vector3(0.14, 0.06, 0.11), C(S.STONE, -0.05))

## El campo de la vista frontal: hierba seguida hasta el horizonte, la tierra
## de nadie batida en medio (una franja parda de bordes irregulares) y craters
## donde caigan, no en el centro de ninguna casilla.
static func _field(mk, board: Vector2i, ext: Vector2, rng: RandomNumberGenerator, simple: bool, scene := SCENE_LAND) -> void:
	var y0 := -0.11
	# El campo grande y, encima, el del frente (un poco mas claro): sin peana ni
	# mesa, el suelo sigue hasta perderse. En la playa el campo acaba en la
	# orilla (detras esta el mar de _beach, mas bajo).
	var back := -ext.y * 4.5
	if scene == SCENE_BEACH:
		back = -(ext.y * 0.5 + MARGIN)
	var front_edge := ext.y * 4.5
	mk.flat(Vector3(0, y0 - 0.02, (back + front_edge) * 0.5), Vector2(ext.x * 9.0, front_edge - back), C(S.GREEN, -0.22))
	var near_back := maxf(back, -(ext.y * 0.5 + MARGIN * 1.5))
	var near_front := ext.y * 0.5 + MARGIN * 1.5
	mk.flat(Vector3(0, y0, (near_back + near_front) * 0.5), Vector2(ext.x + MARGIN * 3.0, near_front - near_back), C(S.GREEN, -0.08))
	# Tierra de nadie: las filas del medio, en manchas solapadas.
	var dirt := C(S.STONE, -0.16).lerp(C(S.WOOD, 0.0), 0.35)
	var hx := ext.x * 0.5
	var x := -hx - 0.6
	while x < hx + 0.6:
		var wd := rng.randf_range(1.6, 2.6)
		var dz := rng.randf_range(2.6, 4.0)
		mk.flat(Vector3(x + wd * 0.5, y0 + 0.008, rng.randf_range(-0.5, 0.5)), Vector2(wd, dz), dirt.darkened(rng.randf() * 0.08))
		x += wd * 0.8
	# Craters sueltos en la tierra de nadie y alguno mas cerca de cada bando.
	for i in (3 if simple else 6):
		var c := Vector3(rng.randf_range(-hx + 0.6, hx - 0.6), y0 + 0.012, rng.randf_range(-ext.y * 0.3, ext.y * 0.3))
		mk.cyl(c, rng.randf_range(0.5, 0.75), 0.02, C(S.WOOD, -0.25), 9)
		mk.cyl(c, 0.32, 0.025, C(S.IRON, 0.05), 7)
	if simple:
		return
	# Matas sueltas por el campo, a voleo (no en rejilla).
	for i in 26:
		var p := Vector3(rng.randf_range(-hx - 1.0, hx + 1.0), y0, rng.randf_range(-ext.y * 0.5 - 1.0, ext.y * 0.5 + 1.0))
		mk.box(p + Vector3(0, 0.05, 0), Vector3(0.09, 0.1, 0.09), C(S.GREEN, 0.04))
		mk.box(p + Vector3(0.1, 0.04, 0.05), Vector3(0.07, 0.08, 0.07), C(S.GREEN, -0.02))

## Arboledas lejanas a los lados y al fondo del frente: el campo no acaba en un
## borde de mesa. Pocos arboles grandes (cada uno, dos conos y un tronco).
static func _far_trees(mk, ext: Vector2, rng: RandomNumberGenerator, simple: bool, scene: String) -> void:
	var y0 := -0.13
	var hx := ext.x * 0.5
	var hz := ext.y * 0.5
	var n := 6 if simple else 14
	for i in n:
		var side := -1.0 if i % 2 == 0 else 1.0
		var p := Vector3(side * rng.randf_range(hx + 3.0, hx + 9.0), y0, rng.randf_range(-hz - 6.0, hz + 4.0))
		_tree(mk, p, rng.randf_range(1.3, 2.0))
	if scene == SCENE_BEACH:
		return
	for i in (4 if simple else 9):
		var p := Vector3(rng.randf_range(-hx - 6.0, hx + 6.0), y0, -hz - rng.randf_range(3.5, 9.0))
		_tree(mk, p, rng.randf_range(1.4, 2.1))

static func _edges(mk, board: Vector2i, ext: Vector2, rng: RandomNumberGenerator, simple: bool, scene := SCENE_LAND) -> void:
	var hx := ext.x * 0.5
	var hz := ext.y * 0.5
	var y0 := -0.11
	# Sacos terreros delante de cada bando, en el borde (fuera de las casillas):
	# el jugador abajo (+Z), la Regencia arriba (-Z). Con un hueco en medio.
	for sz in [1.0, -1.0]:
		# En la playa el fondo es arena de desembarco: sin parapeto enemigo.
		if sz < 0.0 and scene == SCENE_BEACH:
			continue
		var z: float = sz * (hz + 0.55)
		for seg in [[-hx + 0.4, -1.2], [1.2, hx - 0.4]]:
			_sandbags(mk, Vector3(seg[0], y0, z), Vector3(seg[1], y0, z), 2 if not simple else 1)
	# Arbolitos de juguete en las esquinas y algunos sueltos a los lados.
	var spots: Array = [Vector2(-hx - 0.9, -hz - 0.8), Vector2(hx + 0.9, -hz - 0.9), Vector2(-hx - 0.85, hz + 0.9), Vector2(hx + 0.9, hz + 0.8)]
	if not simple:
		for i in 4:
			var side := -1.0 if i % 2 == 0 else 1.0
			spots.append(Vector2(side * (hx + 0.85), rng.randf_range(-hz + 1.0, hz - 1.0)))
	for p in spots:
		_tree(mk, Vector3(p.x, y0, p.y), rng.randf_range(0.85, 1.2))
	if simple:
		return
	# Piedras y un poste de senales en el costado.
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		var p := Vector3(side * (hx + rng.randf_range(0.3, 1.3)), y0, rng.randf_range(-hz, hz))
		mk.box(p + Vector3(0, 0.1, 0), Vector3(rng.randf_range(0.2, 0.4), 0.2, rng.randf_range(0.2, 0.35)), C(S.STONE, -0.1 + rng.randf() * 0.08))
	var post := Vector3(-hx - 0.8, y0, hz * 0.3)
	mk.box(post + Vector3(0, 0.55, 0), Vector3(0.1, 1.1, 0.1), C(S.WOOD, -0.15))
	mk.box(post + Vector3(0.18, 0.95, 0), Vector3(0.5, 0.18, 0.06), C(S.CREAM, -0.05))
	mk.box(post + Vector3(0.22, 0.7, 0), Vector3(0.45, 0.16, 0.06), C(S.BRASS, -0.05))

static func _sandbags(mk, a: Vector3, b: Vector3, rows: int) -> void:
	var dvec := b - a
	var n := maxi(1, int(dvec.length() / 0.4))
	for r in rows:
		for i in n:
			var t := (float(i) + 0.5 + (0.5 if r % 2 == 1 else 0.0)) / float(n)
			if t > 1.0:
				continue
			var p := a + dvec * t + Vector3(0, r * 0.2, 0)
			var col := C(S.CREAM, -0.2 - 0.05 * float((i + r) % 2))
			mk.box(p + Vector3(0, 0.1, 0), Vector3(0.4, 0.2, 0.26), col)
			mk.box(p + Vector3(0, 0.21, 0), Vector3(0.32, 0.03, 0.2), col.lightened(0.06))

static func _tree(mk, base: Vector3, s: float) -> void:
	mk.cyl(base, 0.09 * s, 0.4 * s, C(S.WOOD, -0.2), 6)
	mk.cyl(base + Vector3(0, 0.3 * s, 0), 0.5 * s, 0.7 * s, C(S.GREEN, -0.1), 7, Vector3.UP, 0.0)
	mk.cyl(base + Vector3(0, 0.75 * s, 0), 0.36 * s, 0.6 * s, C(S.GREEN, 0.0), 7, Vector3.UP, 0.0)

# ── Escenarios ───────────────────────────────────────────────────────

## Playa: arena en el borde del fondo y el mar detras, con lanchas de la
## Regencia varadas y un embarcadero de tablas.
static func _beach(mk, ext: Vector2, w: float, d: float, rng: RandomNumberGenerator, simple: bool) -> void:
	var hz := ext.y * 0.5
	var sand := C(S.CREAM, -0.12)
	# Arena sobre el borde del fondo (encima del cesped de la peana).
	mk.flat(Vector3(0, -0.1, -hz - MARGIN * 0.5 - 0.04), Vector2(w, MARGIN + 0.08), sand)
	# El mar: una lamina grande al fondo, sobre la mesa, y la espuma en la orilla.
	var shore := -d * 0.5
	mk.flat(Vector3(0, -0.24, shore - 40.0), Vector2(w * 8.0, 80.0), C(S.SKY, -0.18))
	mk.flat(Vector3(0, -0.235, shore - 0.35), Vector2(w + 0.6, 0.7), C(S.SKY, 0.12))
	mk.box(Vector3(0, -0.2, shore - 0.05), Vector3(w + 0.2, 0.08, 0.14), C(S.CREAM, 0.05))
	# Las lanchas de los recaudadores, proa a la playa.
	var count := 2 if simple else 3
	for i in count:
		var x := (float(i) - float(count - 1) * 0.5) * (w / float(count + 0.5)) + rng.randf_range(-0.6, 0.6)
		_launch(mk, Vector3(x, -0.24, shore - 1.6 - rng.randf() * 1.2), rng.randf_range(-12.0, 12.0))
	if simple:
		return
	# Embarcadero de tablas y un par de cajas del Diezmo en la arena.
	var jx := -w * 0.32
	for k in 6:
		mk.box(Vector3(jx, -0.12, shore - 0.3 - k * 0.5), Vector3(0.9, 0.06, 0.42), C(S.WOOD, -0.08 - 0.04 * float(k % 2)))
	for k in 4:
		mk.box(Vector3(jx + (0.5 if k % 2 == 0 else -0.5), -0.3, shore - 0.6 - (k / 2) * 1.6), Vector3(0.1, 0.5, 0.1), C(S.WOOD, -0.25))
	for k in 2:
		mk.box(Vector3(w * 0.28 + k * 0.5, -0.0, -hz - 0.9 - k * 0.2), Vector3(0.4, 0.3, 0.4), C(S.WOOD, 0.0))

## Una lancha de desembarco: casco de madera, franja morada, garita y chimenea.
static func _launch(mk, base: Vector3, rot: float) -> void:
	var saved: Transform3D = mk.xf
	mk.xf = mk.xf * Transform3D(Basis(Vector3.UP, deg_to_rad(rot)), base)
	mk.box(Vector3(0, 0.18, 0), Vector3(1.0, 0.36, 2.1), C(S.WOOD, -0.2))
	mk.box(Vector3(0, 0.34, 0), Vector3(1.04, 0.08, 2.14), REGENCY)
	mk.box(Vector3(0, 0.3, 1.05), Vector3(0.7, 0.24, 0.12), C(S.WOOD, -0.28))
	mk.box(Vector3(0, 0.55, -0.45), Vector3(0.62, 0.42, 0.6), C(S.SLATE, -0.05))
	mk.cyl(Vector3(0.12, 0.76, -0.65), 0.08, 0.4, C(S.IRON, 0.05), 6)
	mk.box(Vector3(0, 0.79, -0.45), Vector3(0.68, 0.05, 0.66), REGENCY.darkened(0.2))
	mk.xf = saved

## Linde de bosque: arboleda cerrada al fondo y en un costado, troncos cortados.
static func _forest(mk, ext: Vector2, rng: RandomNumberGenerator, simple: bool) -> void:
	var hx := ext.x * 0.5
	var hz := ext.y * 0.5
	var y0 := -0.11
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var step := 1.1 if not simple else 1.6
	var x := -hx - 0.6
	while x <= hx + 0.6:
		_tree(mk, Vector3(x + rng.randf_range(-0.2, 0.2), y0, -hz - 1.05 + rng.randf_range(-0.25, 0.25)), rng.randf_range(1.0, 1.45))
		x += step
	var z := -hz
	while z <= hz:
		_tree(mk, Vector3(side * (hx + 1.0) + rng.randf_range(-0.2, 0.2), y0, z + rng.randf_range(-0.2, 0.2)), rng.randf_range(0.95, 1.35))
		z += step
	if simple:
		return
	for k in 3:
		var p := Vector3(-side * (hx + 0.9), y0, rng.randf_range(-hz + 1.0, hz - 1.0))
		mk.cyl(p - Vector3(0.45, -0.12, 0), 0.12, 0.9, C(S.WOOD, -0.18), 7, Vector3.RIGHT)
		mk.cyl(p + Vector3(0, 0, 0.45), 0.16, 0.2, C(S.WOOD, -0.1), 7)

## La linea entre los dos bandos en la vista frontal, segun el escenario: un
## arroyo en campo abierto, la linea de la marea en la playa, un seto bajo en la
## linde del bosque. Va a ras de suelo y con huecos: se cruza como cualquier
## casilla (las reglas no tienen obstaculos y el decorado no debe insinuarlos).
## Corre a lo largo de X por el medio del tablero (entre la fila 3 y la 4).
static func _divider(mk, ext: Vector2, rng: RandomNumberGenerator, simple: bool, scene: String) -> void:
	var hx := ext.x * 0.5
	var y0 := -0.11
	var x := -hx - 2.5
	while x < hx + 2.5:
		var seg := rng.randf_range(1.2, 2.2)
		var z := rng.randf_range(-0.25, 0.25)
		match scene:
			SCENE_BEACH:
				# Arena mojada y una raya de espuma.
				mk.flat(Vector3(x + seg * 0.5, y0 + 0.014, z), Vector2(seg * 1.05, 0.7), C(S.STONE, -0.1))
				mk.flat(Vector3(x + seg * 0.5, y0 + 0.018, z + 0.22), Vector2(seg * 0.9, 0.12), C(S.CREAM, 0.1))
			SCENE_FOREST:
				# Seto bajo a trozos, con hueco entre trozo y trozo.
				if rng.randf() < 0.65:
					mk.box(Vector3(x + seg * 0.4, y0 + 0.11, z), Vector3(seg * 0.6, 0.22, 0.3), C(S.GREEN, -0.18 + rng.randf() * 0.06))
			_:
				# Arroyo: agua somera con orillas de tierra y alguna piedra de paso.
				mk.flat(Vector3(x + seg * 0.5, y0 + 0.012, z), Vector2(seg * 1.05, 0.8), C(S.WOOD, -0.1))
				mk.flat(Vector3(x + seg * 0.5, y0 + 0.018, z), Vector2(seg * 1.05, 0.46), C(S.SKY, -0.05))
				if not simple and rng.randf() < 0.5:
					mk.box(Vector3(x + seg * 0.5, y0 + 0.04, z), Vector3(0.26, 0.06, 0.22), C(S.STONE, -0.05))
		x += seg
