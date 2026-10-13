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

static func C(slot: int, d := 0.0) -> Color:
	return Palette.tint(slot, d)

static func build(board: Vector2i, seed_value: int, simple := false) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mk := MeshKit.new()
	var ext := Layout.board_extent(board)
	var w := ext.x + MARGIN * 2.0
	var d := ext.y + MARGIN * 2.0

	# La mesa de guerra: madera oscura, muy grande, para que la maqueta no flote.
	mk.flat(Vector3(0, TABLE_Y, 0), Vector2(w * 8.0, d * 8.0), TABLE_COLOR)
	# Peana: costados de madera, canto de laton y la tierra del borde.
	mk.box(Vector3(0, (TABLE_Y - 0.12) * 0.5, 0), Vector3(w, -0.12 - TABLE_Y, d), C(S.WOOD, -0.2))
	mk.box(Vector3(0, -0.15, 0), Vector3(w + 0.08, 0.06, d + 0.08), C(S.BRASS, -0.12))
	mk.flat(Vector3(0, -0.11, 0), Vector2(w, d), C(S.GREEN, -0.3))
	# Zocalo oscuro bajo las casillas: entre loseta y loseta se ve la junta.
	mk.box(Vector3(0, -0.13, 0), Vector3(ext.x + 0.16, 0.05, ext.y + 0.16), C(S.IRON, 0.1))

	_tiles(mk, board, rng, simple)
	_edges(mk, board, ext, rng, simple)
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

static func _edges(mk, board: Vector2i, ext: Vector2, rng: RandomNumberGenerator, simple: bool) -> void:
	var hx := ext.x * 0.5
	var hz := ext.y * 0.5
	var y0 := -0.11
	# Sacos terreros delante de cada bando, en el borde (fuera de las casillas):
	# el jugador abajo (+Z), la Regencia arriba (-Z). Con un hueco en medio.
	for sz in [1.0, -1.0]:
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
