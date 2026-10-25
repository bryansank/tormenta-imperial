extends RefCounted
## Bastion, Chatarreria y Telegrafo (feat/edificios-defensa-vida, doc 21 §6.3
## n.º 11, 12 y 18) en la maqueta de juguete.
##
## Igual que UtilityToys: UNA malla con color por vertice y los dos materiales
## comunes (ToyPalette), montada con LotMesh; ningun `_process` ni material
## propio (doc 21 §6.6). En el juego, mientras no exista el horneado
## (`assets/models/toy/<id>.tscn`, receta en tools/toy_recipes/<id>.gd),
## `create()` da esta version procedural completa, una malla compartida por tipo.
## Al hornear, la receta llama a `build_core(mk, id, false)` y pone encima las
## piezas CC0 (valla de piedra, cajas, barriles, farol).
##
## Marco: el del modelo horneado (centro en el origen, suelo en y = 0, frente
## hacia +Z). Rectangulos que deja la parcela (GameConfig, bloque "Defensa y
## vida"): Bastion 2x1 con patio 0,08 -> 3,68 x 1,68 m; los otros dos, 2x2 con
## patio 0,3 -> 2,8 x 2,8 m. BuildingLot.fit_model los encaja.

const MeshKit := preload("res://scripts/buildings/LotMesh.gd")
const Palette := preload("res://scripts/buildings/ToyPalette.gd")
const U := preload("res://scripts/buildings/UtilityToys.gd")
const S := Palette.Slot

const IDS := ["bastion", "scrapyard", "telegraph"]
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
## piezas CC0. Devuelve {"fx": Vector3} donde lo haya.
static func build_core(mk, id: String, full: bool) -> Dictionary:
	match id:
		"bastion": return _bastion(mk, full)
		"scrapyard": return _scrapyard(mk, full)
		"telegraph": return _telegraph(mk, full)
	return {}

static func C(slot: int, d := 0.0) -> Color:
	return Palette.tint(slot, d)

# ══════════════════════════════════════════════════════════════════════
# Bastion (militar, acento amarillo). Un tramo de muro de sillares con almenas,
# el fleje de laton, sacos terreros al pie del lado de fuera (+Z) y una
# banderola de senal en un extremo. Exagerado: las almenas, mas gordas de lo
# que pediria un muro de verdad. ~500 triangulos.
# ══════════════════════════════════════════════════════════════════════

const BASTION_LEN := 3.5
const BASTION_DEPTH := 0.8
const BASTION_H := 0.95

static func _bastion(mk, full: bool) -> Dictionary:
	var hl := BASTION_LEN * 0.5
	# Zarpa de piedra oscura (el muro se apoya en ella).
	U._block(mk, Vector3(0, 0, -0.05), Vector3(BASTION_LEN + 0.12, 0.12, BASTION_DEPTH + 0.2), C(S.STONE, -0.2))
	# Sillares en dos hileras al tresbolillo, dos tonos de piedra.
	var rows := 3
	var row_h := (BASTION_H - 0.12) / float(rows)
	for r in rows:
		var y := 0.12 + float(r) * row_h
		var n := 5
		var w := BASTION_LEN / float(n)
		var off := 0.5 * w if r % 2 == 1 else 0.0
		for i in n + (1 if r % 2 == 1 else 0):
			var x0: float = -hl + float(i) * w - off
			var x1: float = minf(x0 + w, hl)
			x0 = maxf(x0, -hl)
			if x1 - x0 < 0.05:
				continue
			var tone := -0.02 if (i + r) % 2 == 0 else -0.1
			U._block(mk, Vector3((x0 + x1) * 0.5, y, -0.05), Vector3(x1 - x0 - 0.03, row_h - 0.02, BASTION_DEPTH), C(S.STONE, tone))
	# Fleje de laton bajo las almenas, delante y detras.
	for z in [BASTION_DEPTH * 0.5 - 0.05 + 0.015, -BASTION_DEPTH * 0.5 - 0.05 - 0.015]:
		mk.box(Vector3(0, BASTION_H - 0.02, z), Vector3(BASTION_LEN + 0.04, 0.06, 0.03), C(S.BRASS))
	# Camino de ronda y almenas (cinco merlones gordos).
	U._block(mk, Vector3(0, BASTION_H, -0.05), Vector3(BASTION_LEN + 0.06, 0.06, BASTION_DEPTH + 0.06), C(S.STONE, 0.04))
	for i in 5:
		var x := -hl + 0.3 + float(i) * (BASTION_LEN - 0.6) / 4.0
		U._block(mk, Vector3(x, BASTION_H + 0.06, 0.12), Vector3(0.42, 0.34, 0.36), C(S.STONE, -0.04))
		mk.box(Vector3(x, BASTION_H + 0.41, 0.12), Vector3(0.46, 0.04, 0.4), C(S.STONE, 0.08))
	# Sacos terreros al pie, por fuera.
	var sack := C(S.CREAM, -0.22)
	for i in 7:
		var x := -hl + 0.25 + float(i) * (BASTION_LEN - 0.5) / 6.0
		mk.box(Vector3(x, 0.1, BASTION_DEPTH * 0.5 + 0.12), Vector3(0.42, 0.2, 0.26), sack if i % 2 == 0 else sack.darkened(0.06))
	for i in 6:
		var x := -hl + 0.45 + float(i) * (BASTION_LEN - 0.9) / 5.0
		mk.box(Vector3(x, 0.3, BASTION_DEPTH * 0.5 + 0.1), Vector3(0.4, 0.2, 0.24), sack.darkened(0.03))
	# Franja de peligro amarilla y negra en el canto (lo militar).
	for i in 8:
		var col := C(S.BRASS, 0.04) if i % 2 == 0 else C(S.IRON, -0.2)
		var x := -hl + 0.2 + float(i) * 0.12
		mk.box(Vector3(x, 0.55, BASTION_DEPTH * 0.5 - 0.03), Vector3(0.12, 0.12, 0.03), col)
	if full:
		# Banderola de senal y un farol en los extremos (en el horneado,
		# `pir:flag-high` y `ft:lantern`).
		U._pennant(mk, Vector3(hl - 0.2, BASTION_H + 0.06, -0.3), 0.85, C(S.BRASS, 0.04), C(S.IRON, -0.2))
		U._lantern(mk, Vector3(-hl + 0.2, BASTION_H + 0.06, -0.3), 0.45)
	return {}

# ══════════════════════════════════════════════════════════════════════
# Chatarreria (industrial, acento rojo). Un cobertizo de chapa al fondo, la
# grua con su electroiman (lo exagerado: un iman enorme colgado), montones de
# chatarra oxidada, un contenedor rojo y bidones. ~1.200 triangulos.
# ══════════════════════════════════════════════════════════════════════

static func _scrapyard(mk, full: bool) -> Dictionary:
	# Suelo de grava apisonada.
	U._block(mk, Vector3(0, 0, 0), Vector3(2.5, 0.06, 2.5), C(S.STONE, -0.22))
	# Cobertizo de chapa al fondo a la izquierda, con tejado a un agua.
	var shed := Vector3(-0.55, 0.06, -0.6)
	U._block(mk, shed, Vector3(1.3, 0.95, 1.0), C(S.SLATE, 0.06))
	for i in 6:
		mk.box(shed + Vector3(-0.55 + i * 0.22, 0.5, 0.51), Vector3(0.04, 0.9, 0.02), C(S.SLATE, -0.06))
	var roof_c := shed + Vector3(0, 0.95, 0)
	mk.box(roof_c + Vector3(0, 0.08, 0), Vector3(1.45, 0.06, 1.15), C(S.TERRACOTTA, -0.3))
	U._door(mk, shed + Vector3(0.2, 0, 0.5), 0.5, 0.7, C(S.RED, -0.1))
	U._window(mk, shed + Vector3(-0.35, 0.62, 0.51), Vector3.BACK, 0.26, 0.2, C(S.IRON))
	# La grua: mastil amarillo, pluma y el electroiman.
	var post := Vector3(0.8, 0.06, -0.75)
	U._block(mk, post, Vector3(0.36, 0.14, 0.36), C(S.IRON))
	mk.cyl(post + Vector3(0, 0.14, 0), 0.09, 2.0, C(S.BRASS, 0.02), 8)
	mk.box(post + Vector3(-0.25, 2.1, 0.35), Vector3(0.14, 0.14, 1.3), C(S.BRASS, 0.02))
	mk.box(post + Vector3(0, 2.2, -0.15), Vector3(0.22, 0.22, 0.3), C(S.IRON, -0.1))
	var hook := post + Vector3(-0.25, 2.03, 0.9)
	mk.beam(hook, hook + Vector3(0, -0.75, 0), 0.02, C(S.IRON, -0.2))
	mk.cyl(hook + Vector3(0, -0.95, 0), 0.32, 0.18, C(S.IRON, -0.08), 12)
	mk.cyl(hook + Vector3(0, -0.8, 0), 0.12, 0.06, C(S.RED), 8)
	# Chatarra colgando del iman (planchas sueltas).
	mk.box(hook + Vector3(0.05, -1.05, 0), Vector3(0.4, 0.04, 0.3), C(S.TERRACOTTA, -0.34))
	# Montones de chatarra oxidada.
	var heap := Vector3(-0.2, 0.06, 0.55)
	var rust := C(S.TERRACOTTA, -0.34)
	var pieces := [
		[Vector3(0, 0, 0), Vector3(0.9, 0.22, 0.6), 0.0],
		[Vector3(-0.1, 0.22, 0.05), Vector3(0.6, 0.18, 0.4), 0.2],
		[Vector3(0.12, 0.4, -0.02), Vector3(0.36, 0.14, 0.26), -0.3],
		[Vector3(0.45, 0.0, 0.2), Vector3(0.3, 0.3, 0.3), 0.4],
	]
	for p in pieces:
		var saved: Transform3D = mk.xf
		mk.xf = saved * Transform3D(Basis(Vector3.UP, float(p[2])), heap + (p[0] as Vector3))
		U._block(mk, Vector3.ZERO, p[1] as Vector3, rust if int((p[1] as Vector3).x * 10.0) % 2 == 0 else C(S.SLATE, -0.18))
		mk.xf = saved
	# Una rueda dentada vieja apoyada (lo dieselpunk) y un tubo suelto.
	U._valve(mk, heap + Vector3(-0.55, 0.3, 0.15), 0.3, Vector3.BACK)
	U._pipe(mk, heap + Vector3(-0.4, 0.08, 0.4), heap + Vector3(0.6, 0.08, 0.5), 0.06, C(S.SLATE, -0.1))
	# Contenedor rojo a la derecha (en el horneado, cajas `kk:crate_long_A`).
	var box_c := Vector3(0.9, 0.06, 0.6)
	U._block(mk, box_c, Vector3(0.6, 0.6, 1.0), C(S.RED, -0.12))
	for i in 5:
		mk.box(box_c + Vector3(-0.31, 0.3, -0.4 + i * 0.2), Vector3(0.02, 0.56, 0.04), C(S.RED, -0.24))
	if full:
		U._barrel(mk, Vector3(-1.05, 0.06, 0.95), 0.14, 0.3)
		U._barrel(mk, Vector3(-0.8, 0.06, 1.05), 0.14, 0.3)
		U._lantern(mk, Vector3(0.3, 0.06, -1.05), 0.8)
	return {"fx": heap + Vector3(0, 0.6, 0)}

# ══════════════════════════════════════════════════════════════════════
# Telegrafo (civico, acento laton). Una oficina de ladrillo con tejado de
# pizarra, el mastil de celosia (lo exagerado: mas alto que nada en el barrio)
# con sus aisladores, la lampara roja de senales encendida en lo alto y los
# hilos que bajan a un poste. ~1.000 triangulos.
# ══════════════════════════════════════════════════════════════════════

const TELEGRAPH_MAST_H := 3.0

static func _telegraph(mk, full: bool) -> Dictionary:
	# Acera de losas.
	U._block(mk, Vector3(0, 0, 0), Vector3(2.5, 0.06, 2.5), C(S.STONE, 0.02))
	# La oficina de ladrillo, con zocalo de piedra.
	var off := Vector3(-0.3, 0.06, 0.15)
	U._block(mk, off, Vector3(1.7, 0.16, 1.3), C(S.STONE, -0.08))
	U._block(mk, off + Vector3(0, 0.16, 0), Vector3(1.6, 0.95, 1.2), C(S.TERRACOTTA, -0.12))
	U._gable(mk, off + Vector3(0, 1.11, 0), 1.6, 1.2, 0.5, C(S.SLATE, -0.1), C(S.TERRACOTTA, -0.12))
	U._door(mk, off + Vector3(0.35, 0.16, 0.6), 0.36, 0.62, C(S.GREEN, -0.25))
	U._window(mk, off + Vector3(-0.35, 0.62, 0.61), Vector3.BACK, 0.4, 0.3, C(S.CREAM, -0.1))
	U._window(mk, off + Vector3(-0.81, 0.62, 0.0), Vector3.LEFT, 0.3, 0.3, C(S.CREAM, -0.1))
	# Rotulo de laton sobre la puerta (el acento civico).
	mk.box(off + Vector3(0, 1.0, 0.63), Vector3(1.1, 0.16, 0.04), C(S.BRASS))
	mk.box(off + Vector3(0, 1.0, 0.655), Vector3(0.9, 0.06, 0.02), C(S.IRON, -0.2))
	# Chimenea pequena.
	U._block(mk, off + Vector3(0.5, 1.2, -0.3), Vector3(0.2, 0.5, 0.2), C(S.TERRACOTTA, -0.2))
	# El mastil de celosia al fondo a la derecha: cuatro patas y travesanos.
	var m := Vector3(0.85, 0.06, -0.8)
	var steel := C(S.IRON, 0.08)
	var leg := 0.2
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var a := m + Vector3(sx * leg, 0, sz * leg)
			var b := m + Vector3(sx * 0.05, TELEGRAPH_MAST_H, sz * 0.05)
			mk.beam(a, b, 0.025, steel)
	for k in 5:
		var t := float(k + 1) / 6.0
		var hw := lerpf(leg, 0.05, t)
		var y := TELEGRAPH_MAST_H * t
		mk.box(m + Vector3(0, y, hw), Vector3(hw * 2.0, 0.03, 0.03), steel)
		mk.box(m + Vector3(0, y, -hw), Vector3(hw * 2.0, 0.03, 0.03), steel)
		mk.box(m + Vector3(hw, y, 0), Vector3(0.03, 0.03, hw * 2.0), steel)
		mk.box(m + Vector3(-hw, y, 0), Vector3(0.03, 0.03, hw * 2.0), steel)
	# Crucetas con aisladores blancos.
	for y in [TELEGRAPH_MAST_H * 0.72, TELEGRAPH_MAST_H * 0.86]:
		mk.box(m + Vector3(0, y, 0), Vector3(0.7, 0.04, 0.05), C(S.WOOD, -0.2))
		for sx in [-0.3, -0.1, 0.1, 0.3]:
			mk.cyl(m + Vector3(sx, y + 0.02, 0), 0.03, 0.08, C(S.CREAM), 6)
	# La lampara de senales (encendida, sin luz real) y la bola de laton.
	var top := m + Vector3(0, TELEGRAPH_MAST_H, 0)
	mk.box(top + Vector3(0, 0.08, 0), Vector3(0.16, 0.16, 0.16), C(S.RED, 0.1), true)
	mk.ball(top + Vector3(0, 0.26, 0), 0.08, C(S.BRASS, 0.1))
	# Los hilos: de la cruceta a la oficina (dos hilos finos).
	var roof_hook := off + Vector3(0.6, 1.45, -0.2)
	mk.beam(m + Vector3(-0.3, TELEGRAPH_MAST_H * 0.72 + 0.06, 0), roof_hook, 0.012, C(S.IRON, -0.3))
	mk.beam(m + Vector3(-0.1, TELEGRAPH_MAST_H * 0.86 + 0.06, 0), roof_hook + Vector3(0, 0.05, 0.1), 0.012, C(S.IRON, -0.3))
	if full:
		# Poste de hilos delante (madera) y un farol (en el horneado, `ft:lantern`).
		var pole := Vector3(1.0, 0.06, 0.95)
		mk.cyl(pole, 0.05, 1.5, C(S.WOOD, -0.18), 6)
		mk.box(pole + Vector3(0, 1.4, 0), Vector3(0.4, 0.04, 0.05), C(S.WOOD, -0.2))
		mk.beam(pole + Vector3(-0.15, 1.44, 0), m + Vector3(0.3, TELEGRAPH_MAST_H * 0.72 + 0.06, 0), 0.012, C(S.IRON, -0.3))
		U._lantern(mk, Vector3(-1.05, 0.06, 1.0), 0.8)
	return {"fx": top + Vector3(0, 0.1, 0)}
