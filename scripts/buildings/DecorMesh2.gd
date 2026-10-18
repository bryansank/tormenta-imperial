extends RefCounted
## Las dieciocho decoraciones que faltaban del catalogo (doc 21 §6.4, n.º 9-28
## salvo el mastil y las palmeras; feat/decoraciones-y-trafico) en 3D, version
## procedural.
##
## Las sirve DecorMesh (handles / mesh_for / instantiate): cada una es UNA malla
## de los dos materiales de la paleta (ToyPalette), compartida por todas sus
## instancias y dibujada en lote por DecorBatch3D (un MultiMesh por tipo). La
## horneada (`assets/models/toy/<id>_mesh.res`, recetas en
## tools/toy_recipes/<id>.gd con piezas CC0) manda; esta es la reserva y la base
## de las recetas: `cc0 = true` deja fuera la parte que la receta pone con una
## pieza CC0 (el puesto, la valla, la pila de la fuente...).
##
## Marco: centro en el origen, suelo en y = 0, frente hacia +Z. Unos 3 m de lado
## (la parcela 2x2 con su patio); la Plaza del Gobernador (3x3), unos 5 m.
## Presupuesto (doc 21 §6.6): <= 600 triangulos por decoracion 2x2; la Plaza,
## <= 1.500. Sin texturas, sin luces (lo que brilla va a la superficie GLOW),
## sin `_process`: nada se anima (el molino y el dirigible, quietos).

const Palette := preload("res://scripts/buildings/ToyPalette.gd")
const S := Palette.Slot

const IDS := ["flower_stall", "community_garden", "small_fountain", "entrance_arch",
	"bandstand", "beached_boat", "gear_garden", "fair_stage", "fair_tent", "pond_bridge",
	"water_mill", "museum_cannon", "container_mural", "clock_tower", "wreck_monument",
	"storm_column", "moored_airship", "governor_plaza"]

static func handles(id: String) -> bool:
	return id in IDS

static func build(mk, id: String, cc0 := false) -> void:
	match id:
		"flower_stall": _flower_stall(mk, cc0)
		"community_garden": _community_garden(mk, cc0)
		"small_fountain": _small_fountain(mk, cc0)
		"entrance_arch": _entrance_arch(mk, cc0)
		"bandstand": _bandstand(mk, cc0)
		"beached_boat": _beached_boat(mk, cc0)
		"gear_garden": _gear_garden(mk, cc0)
		"fair_stage": _fair_stage(mk, cc0)
		"fair_tent": _fair_tent(mk, cc0)
		"pond_bridge": _pond_bridge(mk, cc0)
		"water_mill": _water_mill(mk, cc0)
		"museum_cannon": _museum_cannon(mk, cc0)
		"container_mural": _container_mural(mk, cc0)
		"clock_tower": _clock_tower(mk, cc0)
		"wreck_monument": _wreck_monument(mk, cc0)
		"storm_column": _storm_column(mk, cc0)
		"moored_airship": _moored_airship(mk, cc0)
		"governor_plaza": _governor_plaza(mk, cc0)

# ── Ayudas (las mismas que DecorMesh; aqui sin precargarla: sin ciclo) ──

static func C(slot: int, d := 0.0) -> Color:
	return Palette.tint(slot, d)

## Caja apoyada en `pos.y`, centrada en planta.
static func block(mk, pos: Vector3, size: Vector3, col: Color, glow := false) -> void:
	mk.box(pos + Vector3(0, size.y * 0.5, 0), size, col, glow)

## Flores: cubitos de color (no hay flores CC0).
static func flowers(mk, c: Vector3, r: float, count := 4, seed_val := 0) -> void:
	var cols := [S.RED, S.BRASS, S.CREAM, S.TERRACOTTA]
	for i in count:
		var a := TAU * float(i) / float(count) + float(seed_val) * 0.7
		mk.box(c + Vector3(cos(a) * r, 0.0, sin(a) * r), Vector3(0.11, 0.11, 0.11), C(cols[(i + seed_val) % cols.size()], 0.08))

## Con `mk.xf` girado y desplazado mientras dura `fn` (piezas giradas).
static func at(mk, xf: Transform3D, fn: Callable) -> void:
	var saved: Transform3D = mk.xf
	mk.xf = saved * xf
	fn.call()
	mk.xf = saved

## Un engranaje de pie (eje en Z) de radio `r`: disco y `teeth` dientes.
static func cog(mk, center: Vector3, r: float, depth: float, col: Color, teeth := 8) -> void:
	mk.cyl(center - Vector3(0, 0, depth * 0.5), r * 0.82, depth, col, 10, Vector3(0, 0, 1), -1.0, false, true)
	mk.cyl(center - Vector3(0, 0, depth * 0.6), r * 0.25, depth * 1.2, C(S.IRON, 0.05), 6, Vector3(0, 0, 1))
	for i in teeth:
		var a := TAU * float(i) / float(teeth)
		var p := center + Vector3(cos(a), sin(a), 0) * r * 0.9
		at(mk, Transform3D(Basis(Vector3(0, 0, 1), a), p), func(): mk.box(Vector3.ZERO, Vector3(r * 0.26, r * 0.2, depth), col))

## Farol de plaza: fuste de hierro y farol encendido (sin luz real).
static func lamp(mk, base: Vector3, h: float) -> void:
	block(mk, base, Vector3(0.3, 0.12, 0.3), C(S.STONE, -0.05))
	mk.cyl(base + Vector3(0, 0.12, 0), 0.05, h, C(S.IRON, 0.05), 5)
	mk.box(base + Vector3(0, h + 0.24, 0), Vector3(0.2, 0.26, 0.2), C(S.GLOW), true)
	mk.cyl(base + Vector3(0, h + 0.37, 0), 0.16, 0.12, C(S.IRON), 4, Vector3.UP, 0.0)

# ── Era 1 ─────────────────────────────────────────────────────────────

## Puesto de flores (n.º 9): mostrador de madera con toldo a rayas verdes y
## crema (lo exagerado), cajas de flores encima y cubos delante.
static func _flower_stall(mk, cc0: bool) -> void:
	if not cc0:
		block(mk, Vector3(0, 0, -0.1), Vector3(2.0, 0.75, 0.7), C(S.WOOD, 0.02))
		for x in [-0.95, 0.95]:
			for z in [-0.45, 0.3]:
				block(mk, Vector3(x, 0, z), Vector3(0.1, 1.85, 0.1), C(S.WOOD, -0.15))
		for i in 5:
			var col := C(S.GREEN, -0.02) if i % 2 == 0 else C(S.CREAM)
			at(mk, Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(-0.92 + 0.46 * i, 2.0, 0.0)),
				func(): mk.box(Vector3.ZERO, Vector3(0.46, 0.06, 1.3), col))
	for i in 3:
		var p := Vector3(-0.62 + 0.62 * i, 0.75, -0.1)
		block(mk, p, Vector3(0.5, 0.16, 0.42), C(S.WOOD, -0.1))
		flowers(mk, p + Vector3(0, 0.22, 0), 0.13, 4, i)
	for x in [-0.6, 0.55]:
		mk.cyl(Vector3(x, 0, 0.75), 0.17, 0.32, C(S.SLATE, 0.05), 6, Vector3.UP, 0.2)
		mk.ball(Vector3(x, 0.42, 0.75), 0.17, C(S.GREEN, -0.04))

## Huerto vecinal (n.º 10): bancales de tierra con sus hileras de verdura,
## valla baja de madera alrededor y una azada clavada.
static func _community_garden(mk, cc0: bool) -> void:
	block(mk, Vector3.ZERO, Vector3(2.7, 0.06, 2.7), C(S.WOOD, -0.22))
	for row in 3:
		var z := -0.8 + 0.8 * row
		block(mk, Vector3(0, 0.06, z), Vector3(2.1, 0.14, 0.5), C(S.WOOD, -0.3))
		for k in 5:
			var col := C(S.GREEN, -0.05 + 0.05 * (k % 2)) if row != 1 else C(S.RED, -0.05)
			block(mk, Vector3(-0.8 + 0.4 * k, 0.2, z), Vector3(0.24, 0.2 if row != 1 else 0.14, 0.24), col)
	if not cc0:
		var post := C(S.WOOD, -0.08)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				block(mk, Vector3(sx * 1.32, 0, sz * 1.32), Vector3(0.1, 0.55, 0.1), post)
		for side in 4:
			var a := Vector3(1.32, 0.38, -1.32).rotated(Vector3.UP, side * PI * 0.5)
			var b := Vector3(1.32, 0.38, 1.32).rotated(Vector3.UP, side * PI * 0.5)
			if side == 0:
				continue
			mk.beam(a, b, 0.06, post)
		mk.beam(Vector3(1.0, 0.0, 1.1), Vector3(1.15, 0.9, 1.05), 0.05, C(S.WOOD, -0.12))
		mk.box(Vector3(1.0, 0.04, 1.1), Vector3(0.2, 0.06, 0.04), C(S.IRON, 0.05))

## Fuente pequena (n.º 12): pila cuadrada de piedra con su agua, una columnita
## con su taza y el chorro.
static func _small_fountain(mk, cc0: bool) -> void:
	if not cc0:
		for side in 4:
			at(mk, Transform3D(Basis(Vector3.UP, side * PI * 0.5), Vector3.ZERO),
				func(): block(mk, Vector3(0, 0, 1.0), Vector3(2.2, 0.42, 0.2), C(S.STONE, 0.02)))
		block(mk, Vector3.ZERO, Vector3(1.9, 0.3, 1.9), C(S.SKY, -0.04))
	mk.cyl(Vector3(0, 0.2, 0), 0.16, 0.9, C(S.STONE, 0.05), 8)
	mk.cyl(Vector3(0, 1.05, 0), 0.2, 0.12, C(S.STONE, 0.08), 8, Vector3.UP, 0.48)
	mk.cyl(Vector3(0, 1.17, 0), 0.4, 0.04, C(S.SKY, 0.04), 8)
	mk.cyl(Vector3(0, 1.17, 0), 0.05, 0.45, C(S.SKY, 0.15), 5, Vector3.UP, 0.02)

## Arco de entrada (n.º 13): dos pilares de piedra con capitel, el dintel con
## su placa de laton, un estandarte rojo colgando y dos setos al pie.
static func _entrance_arch(mk, cc0: bool) -> void:
	for sx in [-1.0, 1.0]:
		block(mk, Vector3(sx * 1.05, 0, 0), Vector3(0.6, 0.3, 0.6), C(S.STONE, -0.06))
		if not cc0:
			block(mk, Vector3(sx * 1.05, 0.3, 0), Vector3(0.42, 2.2, 0.42), C(S.STONE, 0.05))
		block(mk, Vector3(sx * 1.05, 2.5, 0), Vector3(0.56, 0.16, 0.56), C(S.STONE, -0.02))
		mk.ball(Vector3(sx * 1.05, 0.35, 0.55), 0.26, C(S.GREEN, -0.08), Vector3(1.2, 0.9, 0.9))
	block(mk, Vector3(0, 2.66, 0), Vector3(2.7, 0.42, 0.5), C(S.STONE, 0.08))
	mk.box(Vector3(0, 2.87, 0.26), Vector3(1.1, 0.24, 0.03), C(S.BRASS))
	block(mk, Vector3(0, 3.08, 0), Vector3(0.5, 0.22, 0.4), C(S.STONE, 0.02))
	if not cc0:
		mk.box(Vector3(0, 2.1, 0.0), Vector3(0.6, 0.9, 0.04), C(S.RED, -0.02))
		mk.box(Vector3(0, 1.62, 0.0), Vector3(0.6, 0.06, 0.05), C(S.BRASS, -0.05))

## Bote varado (n.º 16, solo en la costa): corro de arena, el bote de remos
## tumbado con sus remos y unas piedras.
static func _beached_boat(mk, cc0: bool) -> void:
	mk.cyl(Vector3.ZERO, 1.4, 0.05, C(S.CREAM, -0.08), 10)
	if not cc0:
		at(mk, Transform3D(Basis(Vector3(0, 0, 1), 0.18) * Basis(Vector3.UP, 0.5), Vector3(0, 0.05, 0)), func():
			mk.ball(Vector3(0, 0.22, 0), 1.0, C(S.WOOD, -0.04), Vector3(1.25, 0.38, 0.55))
			mk.box(Vector3(0, 0.42, 0), Vector3(1.9, 0.04, 0.6), C(S.WOOD, -0.25))
			for x in [-0.5, 0.35]:
				mk.box(Vector3(x, 0.46, 0), Vector3(0.14, 0.06, 0.62), C(S.WOOD, 0.08))
			mk.box(Vector3(0, 0.33, 0), Vector3(2.4, 0.06, 0.08), C(S.RED, -0.05)))
		for i in 3:
			mk.ball(Vector3(-0.9 + 0.35 * i, 0.12, 0.9 - 0.2 * i), 0.16 + 0.04 * i, C(S.STONE, -0.1 + 0.05 * i), Vector3(1.0, 0.7, 1.0))
	mk.beam(Vector3(-0.2, 0.08, 1.0), Vector3(1.1, 0.06, 0.55), 0.06, C(S.WOOD, 0.05))
	mk.box(Vector3(1.15, 0.06, 0.53), Vector3(0.28, 0.04, 0.14), C(S.WOOD, 0.05))

# ── Era 2 ─────────────────────────────────────────────────────────────

## Quiosco de musica (n.º 14): tarima redonda de piedra con escalon, seis
## columnas finas de hierro y el tejado en punta rojo con remate de laton (lo
## exagerado), y una tuba en un atril.
static func _bandstand(mk, cc0: bool) -> void:
	mk.cyl(Vector3.ZERO, 1.35, 0.4, C(S.STONE, 0.02), 10)
	block(mk, Vector3(0, 0, 1.3), Vector3(0.9, 0.2, 0.35), C(S.STONE, -0.05))
	for i in 6:
		var a := TAU * float(i) / 6.0 + PI / 6.0
		mk.cyl(Vector3(cos(a) * 1.15, 0.4, sin(a) * 1.15), 0.05, 1.45, C(S.IRON, 0.08), 4)
	mk.cyl(Vector3(0, 1.85, 0), 1.32, 0.1, C(S.CREAM, -0.04), 10)
	if not cc0:
		mk.cyl(Vector3(0, 1.95, 0), 1.45, 0.85, C(S.RED, -0.02), 10, Vector3.UP, 0.0)
	mk.ball(Vector3(0, 2.9, 0), 0.12, C(S.BRASS))
	mk.cyl(Vector3(0.3, 0.4, -0.2), 0.03, 0.55, C(S.IRON), 4)
	mk.cyl(Vector3(-0.2, 0.4, 0.1), 0.18, 0.5, C(S.BRASS, 0.04), 8, Vector3.UP, 0.08)
	mk.cyl(Vector3(-0.2, 0.9, 0.1), 0.08, 0.15, C(S.BRASS, 0.08), 8, Vector3.UP, 0.22)

## Jardin de engranajes (n.º 17): escultura dieselpunk de tres engranajes de
## laton de pie y engranados, sobre peanas, entre dos setos recortados.
static func _gear_garden(mk, cc0: bool) -> void:
	block(mk, Vector3.ZERO, Vector3(2.8, 0.06, 2.0), C(S.GREEN, -0.04))
	block(mk, Vector3(0, 0.06, -0.1), Vector3(2.3, 0.25, 0.6), C(S.STONE, 0.02))
	if not cc0:
		cog(mk, Vector3(-0.55, 1.15, -0.1), 0.85, 0.22, C(S.BRASS, 0.02), 10)
		cog(mk, Vector3(0.78, 0.95, -0.1), 0.62, 0.22, C(S.BRASS, -0.06), 8)
	cog(mk, Vector3(0.62, 1.88, -0.1), 0.38, 0.18, C(S.TERRACOTTA, 0.05), 6)
	for sx in [-1.0, 1.0]:
		block(mk, Vector3(sx * 1.05, 0.06, 0.7), Vector3(0.7, 0.45, 0.4), C(S.GREEN, -0.12))

## Escenario de feria (n.º 18): tarima de madera con tablones, telon rojo
## al fondo entre dos postes con banderolas, candilejas encendidas y escalera.
static func _fair_stage(mk, cc0: bool) -> void:
	block(mk, Vector3(0, 0, -0.2), Vector3(2.7, 0.55, 1.8), C(S.WOOD, -0.05))
	for i in 5:
		mk.box(Vector3(-1.08 + 0.54 * i, 0.56, -0.2), Vector3(0.5, 0.02, 1.78), C(S.WOOD, 0.05 - 0.03 * (i % 2)))
	for x in [-1.25, 1.25]:
		block(mk, Vector3(x, 0.55, -1.0), Vector3(0.14, 2.0, 0.14), C(S.WOOD, -0.18))
	block(mk, Vector3(0, 2.4, -1.0), Vector3(2.7, 0.2, 0.18), C(S.WOOD, -0.12))
	mk.box(Vector3(0, 1.5, -1.02), Vector3(2.35, 1.7, 0.06), C(S.RED, -0.08))
	mk.box(Vector3(0, 2.25, -0.97), Vector3(2.45, 0.22, 0.04), C(S.BRASS, -0.04))
	if not cc0:
		for x in [-1.25, 1.25]:
			mk.box(Vector3(x, 1.9, -0.9), Vector3(0.04, 0.7, 0.4), C(S.GREEN, 0.02))
	for i in 5:
		mk.box(Vector3(-0.9 + 0.45 * i, 0.6, 0.62), Vector3(0.14, 0.08, 0.08), C(S.GLOW), true)
	block(mk, Vector3(0.9, 0, 0.85), Vector3(0.6, 0.27, 0.3), C(S.WOOD, -0.1))

## Carpa de feria (n.º 19): carpa redonda roja con techo crema en punta, la
## entrada abierta, banderines y el mastil con el gallardete.
static func _fair_tent(mk, cc0: bool) -> void:
	if not cc0:
		mk.cyl(Vector3.ZERO, 1.25, 1.1, C(S.RED, -0.04), 10)
		mk.cyl(Vector3(0, 1.1, 0), 1.4, 0.95, C(S.CREAM), 10, Vector3.UP, 0.0)
		mk.box(Vector3(0, 0.45, 1.2), Vector3(0.6, 0.9, 0.12), C(S.IRON, -0.1))
	for i in 5:
		var a := TAU * float(i) / 5.0 + 0.3
		mk.box(Vector3(cos(a) * 1.28, 1.05, sin(a) * 1.28), Vector3(0.18, 0.14, 0.04), C(S.BRASS if i % 2 == 0 else S.SKY))
	mk.cyl(Vector3(0, 2.0, 0), 0.04, 0.9, C(S.IRON, 0.05), 4)
	mk.box(Vector3(0.24, 2.7, 0), Vector3(0.44, 0.22, 0.03), C(S.BRASS if cc0 else S.RED, 0.02))
	for x in [-1.3, 1.3]:
		mk.beam(Vector3(x * 0.8, 1.1, 0.8), Vector3(x, 0.0, 1.25), 0.03, C(S.WOOD, -0.1))

## Estanque con puente (n.º 20): borde de piedra, agua, nenufares y juncos,
## y un puentecito de madera en arco que lo cruza (lo exagerado).
static func _pond_bridge(mk, cc0: bool) -> void:
	mk.cyl(Vector3.ZERO, 1.4, 0.14, C(S.STONE, -0.02), 12)
	mk.cyl(Vector3.ZERO, 1.22, 0.16, C(S.SKY, -0.06), 12)
	if not cc0:
		for p in [Vector3(-0.6, 0.17, -0.5), Vector3(0.5, 0.17, 0.6), Vector3(-0.3, 0.17, 0.75)]:
			mk.cyl(p, 0.16, 0.02, C(S.GREEN, 0.0), 6)
	for i in 2:
		var x := -1.1 + 0.2 * i
		mk.beam(Vector3(x, 0.1, -0.9 + 0.1 * i), Vector3(x + 0.05, 0.6, -0.95 + 0.1 * i), 0.04, C(S.GREEN, -0.1))
	var pts := [Vector3(-1.5, 0.12, 0), Vector3(-0.6, 0.45, 0), Vector3(0.6, 0.45, 0), Vector3(1.5, 0.12, 0)]
	for i in 3:
		mk.beam(pts[i], pts[i + 1], 0.5, C(S.WOOD, 0.02))
		for sz in [-0.27, 0.27]:
			mk.beam(pts[i] + Vector3(0, 0.38, sz), pts[i + 1] + Vector3(0, 0.38, sz), 0.05, C(S.WOOD, -0.15))
	for p in pts:
		for sz in [-0.27, 0.27]:
			block(mk, p + Vector3(0, 0, sz), Vector3(0.07, 0.42, 0.07), C(S.WOOD, -0.15))

## Molino de agua (n.º 21): casita de piedra con tejado de teja, el canal de
## agua y la rueda grande de madera con sus palas (lo exagerado; quieta).
static func _water_mill(mk, _cc0: bool) -> void:
	block(mk, Vector3(-0.35, 0, -0.1), Vector3(1.5, 1.2, 1.4), C(S.STONE, 0.04))
	for s in [-1.0, 1.0]:
		at(mk, Transform3D(Basis(Vector3(0, 0, 1), s * 0.62), Vector3(-0.35 + s * 0.42, 1.48, -0.1)),
			func(): mk.box(Vector3.ZERO, Vector3(1.0, 0.08, 1.55), C(S.TERRACOTTA, 0.02)))
	mk.box(Vector3(-0.35, 0.45, 0.61), Vector3(0.36, 0.7, 0.04), C(S.WOOD, -0.15))
	mk.box(Vector3(-0.8, 0.8, 0.61), Vector3(0.26, 0.26, 0.04), C(S.GLOW), true)
	block(mk, Vector3(0.95, 0, 0), Vector3(0.75, 0.1, 2.8), C(S.STONE, -0.08))
	block(mk, Vector3(0.95, 0.1, 0), Vector3(0.55, 0.06, 2.8), C(S.SKY, -0.02))
	var hub := Vector3(0.95, 0.95, -0.05)
	mk.cyl(hub - Vector3(0.18, 0, 0), 0.85, 0.08, C(S.WOOD, -0.08), 10, Vector3.RIGHT, -1.0, false, true)
	mk.cyl(hub + Vector3(0.1, 0, 0), 0.85, 0.08, C(S.WOOD, -0.08), 10, Vector3.RIGHT, -1.0, false, true)
	mk.cyl(hub - Vector3(0.45, 0, 0), 0.1, 0.7, C(S.IRON, 0.05), 6, Vector3.RIGHT)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var p := hub + Vector3(0, sin(a), cos(a)) * 0.85
		at(mk, Transform3D(Basis(Vector3.RIGHT, -a), p), func(): mk.box(Vector3.ZERO, Vector3(0.4, 0.05, 0.3), C(S.WOOD, 0.04)))

## Canon de museo (n.º 22, al echar el primer Diezmo): peana de dos escalones
## con su placa, el canon de hierro en su cureña y una piramide de balas.
static func _museum_cannon(mk, cc0: bool) -> void:
	block(mk, Vector3.ZERO, Vector3(2.2, 0.22, 1.6), C(S.STONE, -0.06))
	block(mk, Vector3(0, 0.22, 0), Vector3(1.8, 0.22, 1.2), C(S.STONE, 0.04))
	mk.box(Vector3(0, 0.33, 0.61), Vector3(0.7, 0.14, 0.02), C(S.BRASS))
	if not cc0:
		block(mk, Vector3(0, 0.44, -0.1), Vector3(0.55, 0.32, 1.0), C(S.WOOD, -0.1))
		for sx in [-1.0, 1.0]:
			mk.cyl(Vector3(sx * 0.32, 0.72, 0.15), 0.3, 0.08, C(S.WOOD, -0.18), 8, Vector3.RIGHT * sx, -1.0, false, true)
		var tilt := Basis(Vector3.RIGHT, -0.18)
		mk.cyl(Vector3(0, 0.95, -0.55), 0.2, 1.5, C(S.IRON, 0.08), 8, (tilt * Vector3(0, 0, 1)).normalized(), 0.15)
		mk.ball(Vector3(0, 0.95, -0.6), 0.2, C(S.IRON, 0.04))
	for p in [Vector3(-0.65, 0.44, 0.35), Vector3(-0.45, 0.44, 0.35), Vector3(-0.55, 0.44, 0.18), Vector3(-0.55, 0.6, 0.29)]:
		mk.ball(p + Vector3(0, 0.08, 0), 0.09, C(S.IRON, -0.05))

## Mural de contenedores (n.º 23): dos contenedores apilados de colores con
## sus nervios y, delante, un panel pintado con franjas (el mural).
static func _container_mural(mk, cc0: bool) -> void:
	var specs := [[Vector3(-0.1, 0, -0.35), C(S.RED, -0.06)], [Vector3(0.15, 1.0, -0.35), C(S.SKY, -0.1)]]
	for k in specs.size():
		if cc0 and k == 0:
			continue
		var base: Vector3 = specs[k][0]
		var col: Color = specs[k][1]
		block(mk, base, Vector3(2.4, 1.0, 1.0), col)
		for i in 5:
			mk.box(base + Vector3(-1.0 + 0.5 * i, 0.5, 0.51), Vector3(0.05, 0.94, 0.03), col.darkened(0.2))
	mk.box(Vector3(0, 0.7, 0.42), Vector3(2.0, 1.1, 0.05), C(S.CREAM, -0.02))
	var bands := [S.RED, S.BRASS, S.GREEN, S.SKY]
	for i in bands.size():
		mk.box(Vector3(-0.72 + 0.48 * i, 0.7, 0.45), Vector3(0.4, 0.9, 0.02), C(bands[i], 0.02))
	mk.ball(Vector3(0, 0.8, 0.47), 0.2, C(S.CREAM, 0.05), Vector3(1.0, 1.0, 0.15))
	block(mk, Vector3(-1.0, 0, 0.9), Vector3(0.5, 0.4, 0.4), C(S.WOOD, -0.05))

## Torre del reloj (n.º 24): base de piedra, fuste crema con bandas de laton,
## la esfera del reloj en cada cara con sus agujas y el tejado en punta.
static func _clock_tower(mk, cc0: bool) -> void:
	block(mk, Vector3.ZERO, Vector3(1.6, 0.5, 1.6), C(S.STONE, -0.04))
	block(mk, Vector3(0, 0.5, 0), Vector3(1.15, 2.6, 1.15), C(S.CREAM, -0.04))
	mk.box(Vector3(0, 0.6, 0.58), Vector3(0.45, 0.8, 0.03), C(S.WOOD, -0.15))
	for y in [1.4, 3.1]:
		block(mk, Vector3(0, y, 0), Vector3(1.25, 0.12, 1.25), C(S.BRASS, -0.04))
	block(mk, Vector3(0, 3.1, 0), Vector3(1.2, 0.8, 1.2), C(S.STONE, 0.04))
	for side in 4:
		at(mk, Transform3D(Basis(Vector3.UP, side * PI * 0.5), Vector3.ZERO), func():
			mk.cyl(Vector3(0, 3.5, 0.6), 0.36, 0.04, C(S.CREAM, 0.08), 10, Vector3(0, 0, 1))
			mk.box(Vector3(0, 3.6, 0.65), Vector3(0.04, 0.22, 0.02), C(S.IRON))
			mk.box(Vector3(0.07, 3.5, 0.65), Vector3(0.16, 0.04, 0.02), C(S.IRON)))
	if not cc0:
		mk.cyl(Vector3(0, 3.9, 0), 0.95, 0.95, C(S.TERRACOTTA, -0.02), 4, Vector3.UP, 0.0)
	mk.ball(Vector3(0, 4.92, 0), 0.1, C(S.BRASS))

## Pecio monumento (n.º 25, solo en la costa): el casco roto medio enterrado en
## la arena, las cuadernas al aire, el mastil partido y el cofre.
static func _wreck_monument(mk, cc0: bool) -> void:
	mk.cyl(Vector3.ZERO, 1.45, 0.06, C(S.CREAM, -0.1), 10)
	at(mk, Transform3D(Basis(Vector3(0, 0, 1), -0.25) * Basis(Vector3.UP, -0.4), Vector3(0.1, 0.0, -0.15)), func():
		mk.ball(Vector3(0, 0.15, 0), 1.0, C(S.WOOD, -0.18), Vector3(1.35, 0.45, 0.6))
		for i in 5:
			var x := -0.8 + 0.4 * i
			for sz in [-1.0, 1.0]:
				mk.beam(Vector3(x, 0.35, sz * 0.5), Vector3(x + 0.05, 0.95 - 0.08 * i, sz * 0.32), 0.07, C(S.WOOD, -0.25)))
	mk.beam(Vector3(-0.2, 0.3, -0.2), Vector3(-0.75, 2.0, -0.5), 0.13, C(S.WOOD, -0.1))
	mk.beam(Vector3(-0.68, 1.75, -0.47), Vector3(-0.2, 1.95, -0.65), 0.07, C(S.WOOD, -0.12))
	if not cc0:
		block(mk, Vector3(0.85, 0.05, 0.75), Vector3(0.55, 0.32, 0.38), C(S.WOOD, 0.02))
		mk.box(Vector3(0.85, 0.42, 0.75), Vector3(0.57, 0.08, 0.4), C(S.BRASS, -0.08))
	for i in 3:
		mk.ball(Vector3(-1.0 + 0.3 * i, 0.12, 0.85 - 0.15 * i), 0.18, C(S.STONE, -0.1 + 0.04 * i), Vector3(1.0, 0.7, 1.0))

# ── Era 3 ─────────────────────────────────────────────────────────────

## Columna de la Tormenta repelida (n.º 26, al echar cinco Diezmos): peana de
## escalones, columna alta de piedra con capitel de laton y encima el rayo de
## la Tormenta partido en dos (lo exagerado), y su placa.
static func _storm_column(mk, cc0: bool) -> void:
	block(mk, Vector3.ZERO, Vector3(2.2, 0.2, 2.2), C(S.STONE, -0.08))
	block(mk, Vector3(0, 0.2, 0), Vector3(1.6, 0.2, 1.6), C(S.STONE, -0.02))
	block(mk, Vector3(0, 0.4, 0), Vector3(1.0, 0.35, 1.0), C(S.STONE, 0.05))
	mk.box(Vector3(0, 0.58, 0.51), Vector3(0.6, 0.2, 0.02), C(S.BRASS))
	if not cc0:
		mk.cyl(Vector3(0, 0.75, 0), 0.3, 2.4, C(S.STONE, 0.08), 8, Vector3.UP, 0.26)
	block(mk, Vector3(0, 3.15, 0), Vector3(0.75, 0.18, 0.75), C(S.BRASS, -0.02))
	var bolt := [Vector3(0.25, 4.6, 0), Vector3(-0.15, 4.05, 0), Vector3(0.15, 3.95, 0)]
	mk.beam(bolt[0], bolt[1], 0.13, C(S.BRASS, 0.08))
	mk.beam(bolt[1], bolt[2], 0.13, C(S.BRASS, 0.08))
	mk.beam(Vector3(-0.05, 3.85, 0), Vector3(-0.25, 3.35, 0), 0.13, C(S.BRASS, 0.04))
	mk.box(Vector3(0.0, 3.9, 0), Vector3(0.1, 0.1, 0.1), C(S.GLOW), true)

## Dirigible amarrado (n.º 27): mastil de amarre de celosia con su remate y el
## dirigible de lona crema con aletas rojas y la barquilla, atado de la proa.
static func _moored_airship(mk, cc0: bool) -> void:
	var iron := C(S.IRON, 0.05)
	var m := Vector3(-1.05, 0, 0)
	block(mk, m, Vector3(0.8, 0.15, 0.8), C(S.STONE, -0.05))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			mk.beam(m + Vector3(sx * 0.3, 0.15, sz * 0.3), m + Vector3(sx * 0.1, 2.6, sz * 0.1), 0.05, iron)
	for y in [0.9, 1.7]:
		var w := lerpf(0.3, 0.1, (y - 0.15) / 2.45)
		block(mk, m + Vector3(0, y, 0), Vector3(w * 2.0 + 0.06, 0.05, w * 2.0 + 0.06), iron)
	mk.cyl(m + Vector3(0, 2.6, 0), 0.14, 0.2, C(S.BRASS), 6, Vector3.UP, 0.08)
	if not cc0:
		mk.cyl(m + Vector3(0.5, 0.15, 0.6), 0.3, 0.6, C(S.SLATE, 0.05), 8)
	var body := Vector3(0.45, 2.55, 0)
	mk.cyl(body - Vector3(0.75, 0, 0), 0.62, 1.5, C(S.CREAM, -0.04), 8, Vector3.RIGHT)
	mk.ball(body - Vector3(0.75, 0, 0), 0.62, C(S.CREAM, -0.02), Vector3(0.75, 1.0, 1.0))
	mk.cyl(body + Vector3(0.75, 0, 0), 0.62, 0.75, C(S.CREAM, -0.08), 8, Vector3.RIGHT, 0.12)
	mk.box(body + Vector3(1.25, 0.45, 0), Vector3(0.45, 0.4, 0.05), C(S.RED, -0.04))
	mk.box(body + Vector3(1.25, 0, 0), Vector3(0.45, 0.05, 1.0), C(S.RED, -0.04))
	mk.box(body + Vector3(0, -0.36, 0), Vector3(1.9, 0.06, 0.08), C(S.RED, -0.04))
	block(mk, body + Vector3(-0.05, -0.92, 0), Vector3(0.75, 0.3, 0.36), C(S.WOOD, -0.06))
	mk.box(body + Vector3(-0.05, -0.75, 0.185), Vector3(0.5, 0.08, 0.02), C(S.GLOW), true)
	mk.beam(body + Vector3(-0.3, -0.62, 0), body + Vector3(-0.3, -0.48, 0), 0.03, iron)
	mk.beam(body + Vector3(0.2, -0.62, 0), body + Vector3(0.2, -0.48, 0), 0.03, iron)
	mk.beam(m + Vector3(0, 2.6, 0), body - Vector3(1.25, 0, 0), 0.03, iron)

## Plaza del Gobernador (n.º 28, 3x3): la mayor. Suelo de losas, la fuente
## redonda en el centro con la estatua del Gobernador de laton encima (lo
## exagerado), cuatro farolas en las esquinas, parterres y la escalinata.
static func _governor_plaza(mk, cc0: bool) -> void:
	block(mk, Vector3.ZERO, Vector3(5.0, 0.1, 5.0), C(S.STONE, 0.02))
	block(mk, Vector3(0, 0.1, 0), Vector3(3.6, 0.02, 3.6), C(S.CREAM, -0.08))
	if not cc0:
		mk.cyl(Vector3(0, 0.1, 0), 1.35, 0.4, C(S.STONE, 0.06), 12)
		mk.cyl(Vector3(0, 0.1, 0), 1.18, 0.42, C(S.SKY, -0.04), 12)
	block(mk, Vector3(0, 0, 2.35), Vector3(2.0, 0.1, 0.3), C(S.STONE, -0.06))
	# Pedestal y estatua (figura de juguete de laton: piernas, levita, cabeza
	# y bicornio, el brazo senalando).
	block(mk, Vector3(0, 0.3, 0), Vector3(0.7, 0.9, 0.7), C(S.STONE, 0.1))
	block(mk, Vector3(0, 1.2, 0), Vector3(0.85, 0.12, 0.85), C(S.STONE, 0.04))
	var g := C(S.BRASS, -0.04)
	block(mk, Vector3(0, 1.32, 0), Vector3(0.36, 0.5, 0.24), g.darkened(0.1))
	mk.cyl(Vector3(0, 1.8, 0), 0.24, 0.6, g, 8, Vector3.UP, 0.18)
	mk.ball(Vector3(0, 2.55, 0), 0.17, g.lightened(0.05))
	mk.box(Vector3(0, 2.72, 0), Vector3(0.52, 0.12, 0.2), g.darkened(0.15))
	mk.beam(Vector3(0.2, 2.25, 0), Vector3(0.6, 2.45, 0.25), 0.09, g)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			lamp(mk, Vector3(sx * 2.05, 0.1, sz * 2.05), 1.6)
			block(mk, Vector3(sx * 1.45, 0.1, sz * 2.05), Vector3(0.7, 0.22, 0.45), C(S.GREEN, -0.12))
			flowers(mk, Vector3(sx * 1.45, 0.38, sz * 2.05), 0.15, 3, int(2 + sx + sz * 2))
