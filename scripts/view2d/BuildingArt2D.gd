extends RefCounted
## El dibujo de los edificios y yacimientos de la vista 2D, en codigo.
##
## Maqueta de juguete (2026-10-12, guia de estilo de edificios): los mismos
## diez colores calidos y saturados que la 3D (`ToyPalette`), volumenes gruesos
## y la funcion de cada edificio a la vista desde fuera, con UN elemento
## exagerado que da la silueta en miniatura (la sierra del Aserradero, la
## chimenea de la Fundicion, la columna de la Refineria, la cupula del
## Laboratorio, el canon de la Torre, la bandera del Cuartel...) y un acento por
## funcion: rojo en lo industrial, amarillo/negro en lo militar, laton en lo
## civico, verde en lo residencial. Contorno oscuro fino y sombra suave que lo
## ancla al suelo.
##
## Vista "de maqueta": desde arriba pero un poco desde el sur, como la camara
## 3D. Cada volumen ensena su tejado y, hacia abajo en PANTALLA, la pared
## (`_block`, `_cyl`); lo alto (mastiles, chimeneas) sube hacia arriba en
## pantalla. Como el edificio se dibuja girado, `draw_building` recibe el giro
## ("rot") y traduce "abajo en pantalla" a su marco local (`_set_view`): la
## pared siempre asoma por el sur de la pantalla y la luz siempre viene de
## arriba a la izquierda, gire como gire.
##
## Todo se dibuja centrado en (0, 0) sobre un CanvasItem, con la huella SIN girar
## (`size` en pixeles); quien llama aplica el giro con draw_set_transform. Lo usan
## Building2D (el mapa, a traves de la cache horneada ArtCache2D), el fantasma de
## colocacion y el icono del menu de construccion, asi que las tres cosas son
## siempre el mismo dibujo.

## La obra: estilo y disposicion compartidos con 3D (docs/03).
const LookRule := preload("res://scripts/buildings/BuildingLook.gd")
const SiteFx := preload("res://scripts/buildings/SiteFx.gd")
## La paleta comun de la maqueta (solo lectura).
const Toy := preload("res://scripts/buildings/ToyPalette.gd")

# ── Paleta: las diez casillas de ToyPalette ──────────────────────────
const CREAM: Color = Toy.COLORS[Toy.Slot.CREAM]
const STONE: Color = Toy.COLORS[Toy.Slot.STONE]
const SLATE: Color = Toy.COLORS[Toy.Slot.SLATE]
const IRON: Color = Toy.COLORS[Toy.Slot.IRON]
const WOOD: Color = Toy.COLORS[Toy.Slot.WOOD]
const TERRACOTTA: Color = Toy.COLORS[Toy.Slot.TERRACOTTA]
const RED: Color = Toy.COLORS[Toy.Slot.RED]
const BRASS: Color = Toy.COLORS[Toy.Slot.BRASS]
const GREEN: Color = Toy.COLORS[Toy.Slot.GREEN]
const SKY: Color = Toy.COLORS[Toy.Slot.SKY]
const GLOW: Color = Toy.COLORS[Toy.Slot.GLOW]

# Matices de esas casillas (claro / oscuro), hechos a mano porque una
# constante no puede llamar a lightened(). Cada uno dice de que casilla sale.
const GUNMETAL := Color8(96, 98, 110)        # SLATE
const STEEL := Color8(150, 152, 162)         # SLATE claro: hojas, chapa nueva
const BRASS_LIGHT := Color8(250, 210, 120)   # BRASS claro
const BRASS_DARK := Color8(178, 124, 30)     # BRASS oscuro
const COPPER := Color8(200, 112, 62)         # TERRACOTTA tostado: tuberias
const RUST := Color8(122, 72, 40)            # WOOD oscuro
const DARK_WOOD := Color8(104, 62, 34)       # WOOD oscuro
const LIGHT_WOOD := Color8(212, 152, 92)     # WOOD claro: tablones
const CONCRETE := Color8(186, 168, 140)      # STONE
const CONCRETE_DARK := Color8(140, 124, 102) # STONE oscuro
const FIRE := Color8(255, 138, 40)           # entre GLOW y RED
const FIRE_CORE := Color8(255, 236, 170)     # GLOW claro
const OIL_BLACK := Color8(32, 24, 24)        # IRON oscuro
const OLIVE := Color8(76, 124, 46)           # GREEN oscuro
const OLIVE_DARK := Color8(56, 94, 34)       # GREEN mas oscuro
const TILE_RED := Color8(210, 92, 58)        # TERRACOTTA
const TILE_RED_DARK := Color8(166, 66, 40)   # TERRACOTTA oscuro
const MARBLE := Color8(242, 222, 180)        # CREAM
const WATER := Color8(78, 160, 204)          # SKY
const LEAF := Color8(108, 172, 62)           # GREEN
const LEAF_DARK := Color8(70, 126, 40)       # GREEN oscuro
const IMPERIAL_RED := Color8(220, 50, 38)    # RED
## El contorno fino: IRON casi negro, calido. Separa el edificio de cualquier
## fondo, tambien con la Tormenta.
const OUTLINE := Color(0.13, 0.09, 0.08, 0.95)
## Sombra calida y suave (luz de arriba a la izquierda).
const SHADOW := Color(0.14, 0.07, 0.03, 0.26)
## Obra: tierra removida y el amarillo de peligro (el de la grua en 3D).
const SITE_DIRT := Color8(164, 112, 70)
const HAZARD := Color8(232, 172, 58)         # BRASS

## Hueco entre la huella y el borde del dibujo, para que dos edificios pegados
## se lean como dos.
const INSET := 2.0

## La plantilla de la parcela (compartida con la 3D).
const LotPlanRef := preload("res://scripts/buildings/LotPlan.gd")

## "Abajo en pantalla" y la direccion de la sombra, en el marco LOCAL del
## edificio que se esta dibujando (ver `_set_view`). Estado de un solo dibujo:
## lo fija cada llamada de entrada.
static var _down := Vector2(0, 1)
static var _shade := Vector2(0.55, 0.8)

# ── Entrada ───────────────────────────────────────────────────────────

## Dibuja el edificio `id` con huella `size` (px, sin girar) centrado en el origen.
## `opts`: "road_mask" (int, calzadas), "level" (int), "shadow" (bool, por defecto true),
## "inset" (px por lado: el patio de la parcela, que el edificio deja libre),
## "rot" (pasos de 90 grados con los que quien llama lo gira: la pared y la
## sombra caen siempre hacia abajo en pantalla), y en la Granja "growth" (0..1)
## y "ripe" (bool); "growth" < 0 pinta el campo sin cultivo (lo pone encima
## `draw_farm_crops`, que cambia sin rehornear el resto).
static func draw_building(ci: CanvasItem, id: String, size: Vector2, opts: Dictionary = {}) -> void:
	_set_view(int(opts.get("rot", 0)))
	var r := Rect2(-size * 0.5, size).grow(-INSET - float(opts.get("inset", 0.0)))
	if id == "road":
		_road(ci, Rect2(-size * 0.5, size), int(opts.get("road_mask", 0)))
		return
	var level: int = int(opts.get("level", 1))
	# El Nucleo (niveles 1-5, feat/nucleo-y-planos) no crece ni lleva zocalo:
	# gana sus propias piezas (_nucleo_level), como CoreTrim en 3D.
	if id == "nucleo":
		if bool(opts.get("shadow", true)):
			_ground_shadow(ci, r, minf(r.size.x, r.size.y) * 0.22)
		_nucleo(ci, r)
		if level > 1:
			_nucleo_level(ci, r, level)
		return
	# Mejorado: el MISMO dibujo, un 8 % mayor por nivel (como la 3D,
	# ProductionManager.apply_level_visual), alrededor del centro.
	r = grown_rect(r, level)
	var decor := bool(opts.get("decor", false))
	if bool(opts.get("shadow", true)):
		# Mejorado, mas alto: la sombra cae mas lejos (y abarca el zocalo).
		var sh := minf(r.size.x, r.size.y) * 0.22 * (1.0 + 0.3 * float(maxi(0, level - 1)))
		_ground_shadow(ci, plinth_rect(r, level), sh)
	if level > 1:
		_level_plinth(ci, r, level)
	match id:
		"nucleo": _nucleo(ci, r)
		"house": _house(ci, r)
		"sawmill": _sawmill(ci, r)
		"gold_mine": _gold_mine(ci, r)
		"warehouse": _warehouse(ci, r)
		"market": _market(ci, r)
		"laboratory": _laboratory(ci, r)
		"farm": _farm(ci, r, float(opts.get("growth", 0.6)), bool(opts.get("ripe", false)))
		"foundry": _foundry(ci, r)
		"barracks": _barracks(ci, r)
		"refinery": _refinery(ci, r)
		"tower": _tower(ci, r)
		"headquarters": _headquarters(ci, r)
		"garden": _garden(ci, r)
		"fountain": _fountain(ci, r)
		"statue": _statue(ci, r)
		# Edificios utiles de la 1.1 (dibujos al final del archivo).
		"windmill", "silo", "tavern", "carpentry", "well", "lighthouse", "fuel_depot":
			_utility(ci, id, r)
		"lamp_post": _lamp_post(ci, r)
		"park_bench": _park_bench(ci, r)
		"hedge": _hedge(ci, r)
		"avenue_tree": _avenue_tree(ci, r)
		"flower_planter": _flower_planter(ci, r)
		"colony_sign": _colony_sign(ci, r)
		"hay_cart": _hay_cart(ci, r)
		"bonfire": _bonfire(ci, r)
		"flagpole": _flagpole(ci, r)
		"palm_trees": _palm_trees(ci, r)
		# Mar y aire (1.1, feat/aire-mar-vista; dibujos al final del archivo).
		"shipyard": _shipyard(ci, r)
		"aerodrome": _aerodrome(ci, r)
		"fishing_dock": _fishing_dock(ci, r)
		_:
			_block(ci, r, minf(r.size.x, r.size.y) * 0.16, STONE, CONCRETE_DARK)
	if level > 1:
		_level_trim(ci, r, level, decor)

## El cultivo de la Granja, encima de su dibujo horneado sin cultivo: crece
## (`growth` 0..1, brotes que se hacen matas y se doran) sin rehornear nada.
static func draw_farm_crops(ci: CanvasItem, size: Vector2, inset: float, growth: float, ripe: bool) -> void:
	var r := Rect2(-size * 0.5, size).grow(-INSET - inset)
	_farm_crops(ci, _farm_field(r), growth, ripe)

## Pasa "abajo en pantalla" (y la sombra, de arriba-izquierda) al marco local
## de un edificio girado `steps` cuartos de vuelta.
static func _set_view(steps: int) -> void:
	var a := -float(steps) * PI * 0.5
	_down = Vector2(0, 1).rotated(a).round()
	_shade = Vector2(0.55, 0.8).rotated(a)

## La izquierda de la pantalla en el marco local (de donde viene la luz).
static func _left() -> Vector2:
	return Vector2(_down.y, -_down.x)

# ── Primitivas de maqueta ─────────────────────────────────────────────

## Sombra suave que ancla el volumen al suelo: dos manchas hacia abajo-derecha.
static func _ground_shadow(ci: CanvasItem, r: Rect2, h: float) -> void:
	ci.draw_rect(Rect2(r.position + _shade * h * 0.9, r.size).grow(1.0), Color(SHADOW, SHADOW.a * 0.55))
	ci.draw_rect(Rect2(r.position + _shade * h * 0.45, r.size), SHADOW)

## Parte `r` en [tejado, pared]: la pared es la franja de alto `h` del lado que
## da hacia abajo en pantalla.
static func _split(r: Rect2, h: float) -> Array:
	h = minf(h, minf(r.size.x, r.size.y) * 0.6)
	if _down.y > 0.5:
		return [Rect2(r.position, Vector2(r.size.x, r.size.y - h)), Rect2(Vector2(r.position.x, r.end.y - h), Vector2(r.size.x, h))]
	if _down.y < -0.5:
		return [Rect2(r.position + Vector2(0, h), Vector2(r.size.x, r.size.y - h)), Rect2(r.position, Vector2(r.size.x, h))]
	if _down.x > 0.5:
		return [Rect2(r.position, Vector2(r.size.x - h, r.size.y)), Rect2(Vector2(r.end.x - h, r.position.y), Vector2(h, r.size.y))]
	return [Rect2(r.position + Vector2(h, 0), Vector2(r.size.x - h, r.size.y)), Rect2(r.position, Vector2(h, r.size.y))]

## Un filo de `r` (el lado cuya normal es `n`), por dentro.
static func _edge(ci: CanvasItem, r: Rect2, n: Vector2, col: Color, w: float) -> void:
	var half := r.size * 0.5
	var along := Vector2(-n.y, n.x)
	var mid := r.get_center() + n * (absf(n.x) * half.x + absf(n.y) * half.y - w * 0.5)
	var length := absf(along.x) * half.x + absf(along.y) * half.y
	ci.draw_line(mid - along * length, mid + along * length, col, w)

## Un volumen de caja: contorno, pared hacia abajo en pantalla (alto `h`) y
## tejado con su filo de luz. Devuelve el tejado (la pared queda en `_wall`).
static var _wall := Rect2()
static func _block(ci: CanvasItem, r: Rect2, h: float, roof: Color, wall: Color) -> Rect2:
	var parts := _split(r, h)
	var top: Rect2 = parts[0]
	_wall = parts[1]
	ci.draw_rect(r.grow(1.0), OUTLINE)
	ci.draw_rect(_wall, wall)
	# La pared tambien recibe la luz por la izquierda: un poco mas clara alli.
	_edge(ci, _wall, _left(), wall.lightened(0.12), minf(3.0, _wall.size.x * 0.2))
	ci.draw_rect(top, roof)
	_edge(ci, top, -_down, roof.lightened(0.3), 1.5)
	_edge(ci, top, _left(), roof.lightened(0.14), 1.2)
	_edge(ci, top, _down, roof.darkened(0.32), 1.2)
	return top

## Ventanas o huecos repartidos a lo largo de la pared que da a la pantalla.
static func _wall_marks(ci: CanvasItem, wall: Rect2, count: int, fill: Color, frac := 0.55, frame := OUTLINE) -> void:
	var horizontal := absf(_down.y) > 0.5
	var length := wall.size.x if horizontal else wall.size.y
	var thick := wall.size.y if horizontal else wall.size.x
	var w := length / float(count) * frac
	var hh := thick * 0.55
	for i in count:
		var t := length * (i + 0.5) / float(count)
		var c := (Vector2(wall.position.x + t, wall.get_center().y) if horizontal else Vector2(wall.get_center().x, wall.position.y + t))
		var s := Vector2(w, hh) if horizontal else Vector2(hh, w)
		ci.draw_rect(Rect2(c - s * 0.5, s).grow(0.8), frame)
		ci.draw_rect(Rect2(c - s * 0.5, s), fill)

## Un cilindro de maqueta: tapa en `c` (arriba) y el cuerpo bajando `h` hacia
## abajo en pantalla. Contorno por debajo, luz por la izquierda.
static func _cyl(ci: CanvasItem, c: Vector2, rad: float, h: float, top: Color, wall: Color) -> void:
	var base := c + _down * h
	var perp := _left() * rad
	var po := _left() * (rad + 1.0)
	_dot(ci, base, rad + 1.0, OUTLINE)
	ci.draw_colored_polygon(PackedVector2Array([c + po, c - po, base - po, base + po]), OUTLINE)
	_dot(ci, c, rad + 1.0, OUTLINE)
	_dot(ci, base, rad, wall)
	ci.draw_colored_polygon(PackedVector2Array([c + perp, c - perp, base - perp, base + perp]), wall)
	if h > 2.0:
		ci.draw_line(c + perp * 0.55, base + perp * 0.55, wall.lightened(0.18), maxf(1.0, rad * 0.3))
		ci.draw_line(c - perp * 0.7, base - perp * 0.7, wall.darkened(0.18), maxf(1.0, rad * 0.25))
	_dot(ci, c, rad, top)
	_dot(ci, c + (perp - _down * rad) * 0.3, rad * 0.45, top.lightened(0.22))

## Un anillo de color alrededor del cuerpo de un cilindro (a `t` de su alto).
static func _cyl_band(ci: CanvasItem, c: Vector2, rad: float, h: float, t: float, w: float, col: Color) -> void:
	var p := c + _down * h * t
	var perp := _left() * rad
	ci.draw_colored_polygon(PackedVector2Array([p + perp, p - perp, p - perp + _down * w, p + perp + _down * w]), col)
	ci.draw_arc(p + _down * w, rad, _down.angle() - PI * 0.5, _down.angle() + PI * 0.5, 10, col, w * 0.9)

## Un mastil (vertical en la maqueta: sube hacia arriba en pantalla). Devuelve la punta.
static func _mast(ci: CanvasItem, base: Vector2, height: float, col := IRON, w := 2.0) -> Vector2:
	var tip := base - _down * height
	ci.draw_line(base + _shade * height * 0.3, base, Color(SHADOW, 0.3), w)
	ci.draw_line(base, tip, OUTLINE, w + 1.5)
	ci.draw_line(base, tip, col, w)
	return tip

## Un disco relleno con pocos lados (segun su radio). draw_circle() de Godot
## gasta 64 lados por disco aunque mida dos pixeles; con cientos de piezas de
## atrezo eso era la mitad de las primitivas del mapa. Los muy pequenos son un
## cuadrado.
static func _dot(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	if r <= 1.1:
		ci.draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), col)
		return
	var n := clampi(int(r * 1.6) + 6, 8, 32)
	var pts := PackedVector2Array()
	pts.resize(n)
	for i in n:
		var a := TAU * float(i) / float(n)
		pts[i] = c + Vector2(cos(a), sin(a)) * r
	ci.draw_colored_polygon(pts, col)

static func _plate(ci: CanvasItem, r: Rect2, fill: Color, border: Color, width: float = 1.5) -> void:
	ci.draw_rect(r, fill)
	# Luz arriba-izquierda, sombra abajo-derecha: relieve sin 3D.
	ci.draw_line(r.position + Vector2(1, 1), Vector2(r.end.x - 1, r.position.y + 1), fill.lightened(0.25), 2.0)
	ci.draw_line(r.position + Vector2(1, 1), Vector2(r.position.x + 1, r.end.y - 1), fill.lightened(0.18), 2.0)
	ci.draw_line(Vector2(r.position.x + 1, r.end.y - 1), r.end - Vector2(1, 1), fill.darkened(0.3), 2.0)
	ci.draw_line(Vector2(r.end.x - 1, r.position.y + 1), r.end - Vector2(1, 1), fill.darkened(0.25), 2.0)
	ci.draw_rect(r, border, false, width)

static func _rivets(ci: CanvasItem, r: Rect2, color: Color = BRASS, inset: float = 3.5) -> void:
	for p in [r.position + Vector2(inset, inset), Vector2(r.end.x - inset, r.position.y + inset),
			Vector2(r.position.x + inset, r.end.y - inset), r.end - Vector2(inset, inset)]:
		_dot(ci, p, 1.4, color.darkened(0.3))
		_dot(ci, p + Vector2(-0.3, -0.3), 0.8, color.lightened(0.4))

static func _disc(ci: CanvasItem, c: Vector2, radius: float, fill: Color, outline := OUTLINE, width := 1.25) -> void:
	_dot(ci, c, radius + width * 0.5, outline)
	_dot(ci, c, radius - width * 0.5, fill)

static func _shaded_disc(ci: CanvasItem, c: Vector2, radius: float, fill: Color) -> void:
	_dot(ci, c, radius + 0.8, OUTLINE)
	_dot(ci, c, radius, fill.darkened(0.18))
	_dot(ci, c - Vector2(radius, radius) * 0.15, radius * 0.8, fill)
	_dot(ci, c - Vector2(radius, radius) * 0.36, radius * 0.3, fill.lightened(0.35))

static func _poly(ci: CanvasItem, pts: PackedVector2Array, fill: Color, outline := OUTLINE, width := 1.25) -> void:
	ci.draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, outline, width, true)

## Lo que crece el dibujo por nivel por encima del 1 (el mismo 8 % que la 3D).
const LEVEL_GROWTH := 0.08

## Escala del dibujo de un edificio de nivel `level` (1 = tal cual).
static func level_scale(level: int) -> float:
	return 1.0 + LEVEL_GROWTH * float(maxi(0, level - 1))

## El nivel con el que crece el dibujo de `id`: el Nucleo no crece (sube hasta
## el 5 y gana piezas propias, _nucleo_level); el resto, su nivel.
static func growth_level(id: String, level: int) -> int:
	return 1 if id == "nucleo" else level

## `r` crecido alrededor de su centro segun el nivel.
static func grown_rect(r: Rect2, level: int) -> Rect2:
	var f := level_scale(level)
	if f == 1.0:
		return r
	var c := r.get_center()
	return Rect2(c - r.size * f * 0.5, r.size * f)

## El zocalo de un edificio mejorado: `r` (el edificio) mas un margen por nivel.
static func plinth_rect(r: Rect2, level: int) -> Rect2:
	if level <= 1:
		return r
	return r.grow(2.0 + 1.5 * float(level - 1))

## Lo que gana un edificio mejorado, como LevelTrim en 3D (2026-10-17): debajo,
## un zocalo de piedra con fleje de laton (dos escalones en el III); encima, en
## las esquinas de atras, chimeneas de ladrillo con bandas de laton (una en el
## II, dos en el III, la mayor con su farol); en las decoraciones, farolas en
## las esquinas en vez de chimeneas. Va dentro del dibujo horneado (una textura
## por nivel en ArtCache2D): nada por frame. Antes era un aro de laton sobre el
## tejado con un banderin rojo en el III (se leia como un recuadro y otra bandera).
static func _level_plinth(ci: CanvasItem, r: Rect2, level: int) -> void:
	var p := plinth_rect(r, level)
	var wall_h := 2.0 + 1.5 * float(level - 1)
	if level >= 3:
		_block(ci, p, wall_h, CONCRETE, CONCRETE_DARK)
		p = p.grow(-2.0)
	_block(ci, p, wall_h * (0.6 if level >= 3 else 1.0), MARBLE.darkened(0.06), CONCRETE_DARK)
	ci.draw_rect(p.grow(-0.5), BRASS_DARK, false, 1.2)

static func _level_trim(ci: CanvasItem, r: Rect2, level: int, decor := false) -> void:
	var c := r.get_center()
	var m := minf(r.size.x, r.size.y)
	var left := _left()
	var ext_d := absf(_down.x) * r.size.x * 0.5 + absf(_down.y) * r.size.y * 0.5
	var ext_l := absf(left.x) * r.size.x * 0.5 + absf(left.y) * r.size.y * 0.5
	if decor:
		# Farolas: las dos de delante en el II, las cuatro en el III.
		var spots := [Vector2(1, 1), Vector2(1, -1)]
		if level >= 3:
			spots.append_array([Vector2(-1, 1), Vector2(-1, -1)])
		var lh := 7.0 + 2.0 * float(level - 2)
		for sp: Vector2 in spots:
			var base := c + _down * sp.x * (ext_d + 1.0) + left * sp.y * (ext_l + 1.0)
			var tip := _mast(ci, base, lh, IRON, 1.4)
			_dot(ci, tip, 3.4, Color(GLOW, 0.35))
			_dot(ci, tip, 2.0, GLOW)
			_dot(ci, tip - _down * 1.6, 1.4, BRASS_LIGHT)
		return
	var rad := clampf(m * 0.075, 2.5, 4.5)
	var roof := clampf(m * 0.3, 8.0, 16.0)
	# Atras a la derecha la mayor; en el III, otra atras a la izquierda.
	# (_left() es, en el marco local, el lado +X de la pantalla: la derecha.)
	var sides := [1.0]
	if level >= 3:
		sides.append(-1.0)
	for i in sides.size():
		var side: float = sides[i]
		# La boca en lo alto de la huella (dentro del horneado); el cuerpo baja
		# hacia la pantalla, como se ve una chimenea alta desde la camara.
		var h := roof + 4.0 * float(level - 2) - 3.0 * float(i)
		var top := c - _down * (ext_d - rad * 1.4) + left * side * (ext_l - rad * 1.3)
		_cyl(ci, top, rad, h, TILE_RED, TILE_RED_DARK)
		_cyl_band(ci, top, rad, h, 0.3, 1.4, BRASS)
		_cyl_band(ci, top, rad, h, 0.6, 1.4, BRASS)
		_dot(ci, top, rad * 0.55, OIL_BLACK)
		if level >= 3 and i == 0:
			_dot(ci, top + _down * h * 0.45, rad * 0.5, GLOW)

## La marca de nivel de un edificio mejorado, sin girar (quien la llama ya
## quito el giro): galones de laton (dos en el II, tres en el III) en la esquina
## de abajo-izquierda de la huella `fp` (arriba van las chimeneas, a la derecha
## la bandera del pais), sin caja de fondo. Pocas ordenes de dibujo y solo al
## repintar.
static func draw_level_plate(ci: CanvasItem, fp: Vector2, level: int) -> void:
	if level <= 1:
		return
	# Dos galones en el II, tres en el III; el Nucleo llega al V (uno por nivel
	# por encima del 1).
	var bars := clampi(level, 2, 3) if level <= 3 else level - 1
	var w := 7.0
	var x := -fp.x * 0.5 + 4.0 + w * 0.5
	for i in bars:
		var y := fp.y * 0.5 - 4.0 - 3.2 * float(i)
		var pts := PackedVector2Array([Vector2(x - w * 0.5, y + 2.6), Vector2(x, y), Vector2(x + w * 0.5, y + 2.6)])
		ci.draw_polyline(pts, OUTLINE, 3.6)
		ci.draw_polyline(pts, BRASS, 2.0)

## Rayas amarillo/negro (lo militar) a lo largo de un rectangulo estrecho.
static func _hazard_strip(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(r, IRON)
	var horizontal := r.size.x >= r.size.y
	var length := r.size.x if horizontal else r.size.y
	var step := maxf(3.0, (r.size.y if horizontal else r.size.x) * 1.4)
	var t := 0.0
	while t < length:
		var a := t
		var b := minf(t + step * 0.5, length)
		if horizontal:
			ci.draw_rect(Rect2(Vector2(r.position.x + a, r.position.y), Vector2(b - a, r.size.y)), BRASS)
		else:
			ci.draw_rect(Rect2(Vector2(r.position.x, r.position.y + a), Vector2(r.size.x, b - a)), BRASS)
		t += step

# ── Edificios ─────────────────────────────────────────────────────────

## Nucleo MONUMENTAL (2026-10-14, como la receta 3D tools/toy_recipes/nucleo.gd:
## "que domine la colonia"), en sus mismas 3x3 casillas: peana cuadrada y
## escalinata circular; detras, las dos calderas con sus chimeneas altas (de
## ahi el humo); el tambor alto de enlucido con su anillo de columnas, cinturon
## de piedra y dos pisos de ventanas encendidas; la gran cupula de laton
## escalonada con nervios, la linterna encendida y, delante, la puerta con su
## escalinata, el manometro encima y dos faroles. Lo alto sube hacia arriba en
## pantalla. El mastil de la bandera sale de la linterna, pero lo pinta
## ColonyFlag2D (no se hornea: asi la bandera cuelga de su punta y el dibujo
## cabe en el margen de la cache); `flag_mount` dice donde.
static func _nucleo(ci: CanvasItem, r: Rect2) -> void:
	var g := _nucleo_geom(r)
	var m: float = g["m"]
	var c := r.get_center()
	var bc: Vector2 = g["base"]
	var rad: float = g["rad"]
	var drum_h: float = g["drum_h"]
	var dt: Vector2 = g["drum_top"]
	var front := Vector2(0, 1)
	# Peana cuadrada de losas
	_block(ci, r.grow(-m * 0.02), m * 0.03, Color8(214, 198, 170), CONCRETE_DARK)
	var slab := r.grow(-m * 0.06)
	for k in range(1, 4):
		var t := float(k) / 4.0
		ci.draw_line(Vector2(slab.position.x + slab.size.x * t, slab.position.y), Vector2(slab.position.x + slab.size.x * t, slab.end.y), CONCRETE, 1.0)
		ci.draw_line(Vector2(slab.position.x, slab.position.y + slab.size.y * t), Vector2(slab.end.x, slab.position.y + slab.size.y * t), CONCRETE, 1.0)
	# Calderas detras, con sus chimeneas altas y la tuberia al tambor
	for sx: float in [-1.0, 1.0]:
		var bpos: Vector2 = c + Vector2(sx * m * 0.3, -m * 0.3)
		var box := Rect2(bpos - Vector2(m * 0.12, m * 0.09), Vector2(m * 0.24, m * 0.18))
		_block(ci, box, m * 0.07, SLATE.lightened(0.12), IRON)
		ci.draw_line(bpos, bc + Vector2(sx * rad * 0.7, -rad * 0.4), OUTLINE, 4.0)
		ci.draw_line(bpos, bc + Vector2(sx * rad * 0.7, -rad * 0.4), BRASS_DARK, 2.4)
		var stack: Vector2 = _nucleo_stack(c, m, sx)
		_cyl(ci, stack, m * 0.045, m * 0.18, IRON.lightened(0.1), IRON.lightened(0.2))
		_cyl_band(ci, stack, m * 0.045, m * 0.18, 0.15, 1.5, BRASS)
		_dot(ci, stack, m * 0.028, OIL_BLACK)
	# Escalinata circular de dos peldanos
	_cyl(ci, bc, rad * 1.42, m * 0.025, STONE.darkened(0.04), CONCRETE_DARK)
	_cyl(ci, bc - _down * m * 0.025, rad * 1.3, m * 0.025, STONE, CONCRETE)
	var foot := bc - _down * m * 0.05
	# Columnas de detras (asoman por los lados del tambor)
	var columns: Array = []
	for k in 12:
		var a := TAU * float(k) / 12.0 + PI / 12.0
		columns.append(Vector2(cos(a), sin(a)))
	for dir: Vector2 in columns:
		if dir.dot(_down) < 0.0:
			_nucleo_column(ci, foot + dir * rad * 1.14, drum_h, m)
	# El tambor alto: zocalo, cinturon de piedra y dos pisos de ventanas
	_cyl(ci, dt, rad, drum_h - m * 0.05, CREAM.darkened(0.06), CREAM)
	_cyl_band(ci, dt, rad, drum_h - m * 0.05, 0.9, 2.0, STONE.darkened(0.08))
	_cyl_band(ci, dt, rad, drum_h - m * 0.05, 0.46, 1.5, STONE.lightened(0.04))
	ci.draw_arc(dt, rad * 1.02, 0.0, TAU, 24, BRASS_DARK, 2.0)
	# Entre las columnas (a +-30 grados): en el eje, abajo la puerta y arriba
	# el manometro.
	for t: float in [0.6, 0.2]:
		for side: float in [-1.0, 1.0]:
			var dir := _down.rotated(side * PI / 6.0)
			var p := foot + dir * rad * 0.94 - _down * drum_h * t
			var ws := Vector2(m * 0.035, m * 0.055)
			ci.draw_rect(Rect2(p - ws * 0.5, ws).grow(0.8), STONE.darkened(0.25))
			ci.draw_rect(Rect2(p - ws * 0.5, ws), GLOW)
	# Columnas de delante
	for dir: Vector2 in columns:
		if dir.dot(_down) >= 0.0:
			_nucleo_column(ci, foot + dir * rad * 1.14, drum_h, m)
	# Puerta grande con su escalinata, el manometro encima y dos faroles
	var door_c := foot + front * rad * 0.98
	_block(ci, Rect2(door_c + front * rad * 0.3 - Vector2(m * 0.11, m * 0.035), Vector2(m * 0.22, m * 0.07)), m * 0.02, STONE, CONCRETE_DARK)
	var ds := Vector2(m * 0.09, m * 0.11)
	var dp := door_c - _down * drum_h * 0.18
	ci.draw_rect(Rect2(dp - ds * 0.5, ds).grow(1.2), BRASS_DARK)
	ci.draw_rect(Rect2(dp - ds * 0.5, ds), DARK_WOOD)
	var gauge := door_c - _down * drum_h * 0.62
	_disc(ci, gauge, m * 0.05, BRASS, OUTLINE, 1.2)
	_dot(ci, gauge, m * 0.036, MARBLE)
	ci.draw_line(gauge, gauge + Vector2(m * 0.024, -m * 0.024), RED, 1.4)
	for sx: float in [-1.0, 1.0]:
		var lamp: Vector2 = door_c + front * rad * 0.42 + Vector2(sx * m * 0.12, 0)
		var lamp_top := _mast(ci, lamp, m * 0.07, IRON, 1.2)
		_dot(ci, lamp_top, 1.8, GLOW)
	# La cupula (exagerada): gajos de laton escalonados y nervios oscuros
	var tiers: Array = g["tiers"]
	for i in tiers.size():
		var tier: Array = tiers[i]
		_disc(ci, tier[0], tier[1], BRASS.lightened(0.05 * float(i)), OUTLINE, 1.0)
		_dot(ci, (tier[0] as Vector2) + (_left() - _down) * float(tier[1]) * 0.3, float(tier[1]) * 0.35, BRASS.lightened(0.12 + 0.05 * float(i)))
	for k in 8:
		var dir := Vector2.from_angle(TAU * float(k) / 8.0)
		if dir.dot(_down) < -0.3:
			continue
		var pts := PackedVector2Array()
		for tier in tiers:
			pts.append((tier[0] as Vector2) + dir * float(tier[1]))
		ci.draw_polyline(pts, BRASS_DARK.darkened(0.2), 1.2)
	# Linterna encendida en lo alto, con su balconcillo y su cupulin
	var lt: Vector2 = g["lantern"]
	_disc(ci, lt, rad * 0.26, IRON, OUTLINE, 1.0)
	_cyl(ci, lt - _down * m * 0.05, rad * 0.17, m * 0.05, BRASS_DARK, GLOW)
	_shaded_disc(ci, g["lantern_top"], rad * 0.13, BRASS)

## Las piezas que gana el Nucleo con su nivel (1.2, feat/nucleo-y-planos), las
## mismas que CoreTrim en 3D, sobre su dibujo y dentro de su huella: N2 farolas
## y losa delante; N3 alas bajas de ladrillo a los lados con ventanas
## encendidas; N4 torreones con cupulin de laton en las esquinas de delante y
## farolas detras (lo alto es el mastil de la bandera); N5 obeliscos con punta dorada en las esquinas. Se hornea con el
## resto del dibujo (una textura por nivel en ArtCache2D): nada por frame.
static func _nucleo_level(ci: CanvasItem, r: Rect2, level: int) -> void:
	var g := _nucleo_geom(r)
	var m: float = g["m"]
	var c := r.get_center()
	var left := _left()
	var ext_d := absf(_down.x) * r.size.x * 0.5 + absf(_down.y) * r.size.y * 0.5
	var ext_l := absf(left.x) * r.size.x * 0.5 + absf(left.y) * r.size.y * 0.5
	# N2: farolas delante y la losa de la escalinata.
	var front := c + _down * ext_d * 0.9
	_block(ci, Rect2(front - Vector2(m * 0.16, m * 0.03), Vector2(m * 0.32, m * 0.06)), m * 0.015, MARBLE, CONCRETE_DARK)
	for sx: float in [-1.0, 1.0]:
		var lamp_top := _mast(ci, front + left * sx * ext_l * 0.62, m * 0.09, IRON, 1.3)
		_dot(ci, lamp_top, 3.0, Color(GLOW, 0.35))
		_dot(ci, lamp_top, 1.8, GLOW)
	if level >= 3:
		# Alas bajas de ladrillo a los lados.
		for sx: float in [-1.0, 1.0]:
			var wc := c + left * sx * ext_l * 0.8 + _down * ext_d * 0.3
			var wing := Rect2(wc - Vector2(m * 0.07, m * 0.09), Vector2(m * 0.14, m * 0.18))
			_block(ci, wing, m * 0.06, TILE_RED, TILE_RED_DARK)
			ci.draw_rect(Rect2(wing.get_center() - Vector2(m * 0.025, m * 0.03), Vector2(m * 0.05, m * 0.04)), GLOW)
	if level >= 4:
		# Torreones en las esquinas de delante y dos farolas detras.
		for sx: float in [-1.0, 1.0]:
			var tc := c + _down * ext_d * 0.82 + left * sx * ext_l * 0.85
			_cyl(ci, tc, m * 0.05, m * 0.12, STONE.lightened(0.1), STONE)
			_shaded_disc(ci, tc - _down * m * 0.12, m * 0.05, BRASS)
		var back := c - _down * ext_d * 0.9
		for sx: float in [-1.0, 1.0]:
			var lt := _mast(ci, back + left * sx * ext_l * 0.45, m * 0.07, IRON, 1.2)
			_dot(ci, lt, 1.6, GLOW)
	if level >= 5:
		# Obeliscos en las cuatro esquinas, con la punta dorada.
		for sd: float in [-1.0, 1.0]:
			for sl: float in [-1.0, 1.0]:
				var foot := c + _down * sd * ext_d * 0.94 + left * sl * ext_l * 0.94
				var top := _mast(ci, foot, m * 0.13, STONE.lightened(0.1), 3.0)
				_dot(ci, top, 2.2, BRASS_LIGHT)

## Las medidas del Nucleo, compartidas por su dibujo y por `flag_mount`.
## El tambor se adelanta un poco hacia abajo en pantalla para que lo alto
## (cupula, linterna) quede dentro de la huella.
static func _nucleo_geom(r: Rect2) -> Dictionary:
	var m := minf(r.size.x, r.size.y)
	var c := r.get_center()
	var base := c + _down * m * 0.12
	var rad := m * 0.25
	var drum_h := m * 0.26
	var drum_top := base - _down * drum_h
	var dome_h := m * 0.19
	var tiers: Array = []
	for t in [[0.0, 1.0], [0.34, 0.92], [0.62, 0.74], [0.84, 0.5], [0.97, 0.24]]:
		tiers.append([drum_top - _down * dome_h * float(t[0]), rad * float(t[1])])
	var lantern: Vector2 = drum_top - _down * dome_h
	var lantern_top := lantern - _down * m * 0.06
	return {"m": m, "base": base, "rad": rad, "drum_h": drum_h, "drum_top": drum_top,
		"tiers": tiers, "lantern": lantern, "lantern_top": lantern_top}

## La boca de la chimenea de una caldera del Nucleo (`sx` -1 izquierda, 1 derecha).
static func _nucleo_stack(c: Vector2, m: float, sx: float) -> Vector2:
	return c + Vector2(sx * m * 0.34, -m * 0.3) - _down * m * 0.18

static func _nucleo_column(ci: CanvasItem, foot: Vector2, h: float, m: float) -> void:
	var top := foot - _down * h
	var w := maxf(1.5, m * 0.03)
	ci.draw_line(foot, top, OUTLINE, w + 1.5)
	ci.draw_line(foot, top, STONE.lightened(0.12), w)
	_dot(ci, top, w * 0.9, STONE)

## Vivienda: paredes crema con ventanas de luz calida, tejado de teja a dos
## aguas y una chimenea gorda (lo exagerado); un seto verde delante.
static func _house(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	var body := Rect2(r.position + r.size * Vector2(0.02, 0.0), r.size * Vector2(0.96, 0.8))
	var top := _gable(ci, body, m * 0.22, TILE_RED, CREAM, true)
	_wall_marks(ci, _wall, 3, GLOW, 0.42, DARK_WOOD)
	# Puerta de madera en medio de la pared
	var horizontal := absf(_down.y) > 0.5
	var dc := _wall.get_center()
	var ds := Vector2(m * 0.14, _wall.size.y * 0.8) if horizontal else Vector2(_wall.size.x * 0.8, m * 0.14)
	ci.draw_rect(Rect2(dc - ds * 0.5, ds).grow(0.8), OUTLINE)
	ci.draw_rect(Rect2(dc - ds * 0.5, ds), WOOD)
	# Chimenea de ladrillo con su remate
	var ch := Rect2(Vector2(top.end.x - top.size.x * 0.3, top.position.y + top.size.y * 0.06), Vector2(m * 0.17, m * 0.17))
	_ground_shadow(ci, ch, m * 0.1)
	var ct := _block(ci, ch, m * 0.08, TILE_RED_DARK, TILE_RED_DARK.darkened(0.25))
	ci.draw_rect(ct.grow(-ct.size.x * 0.22), OIL_BLACK)
	# Seto y flores (el acento verde de lo residencial)
	var hedge_y := r.position.y + r.size.y * 0.91
	for i in 4:
		var p := Vector2(r.position.x + r.size.x * (0.14 + 0.24 * i), hedge_y)
		_disc(ci, p, m * 0.075, GREEN, OUTLINE, 1.0)
		_dot(ci, p - Vector2(1, 1), m * 0.03, GREEN.lightened(0.3))
	_dot(ci, Vector2(r.position.x + r.size.x * 0.26, hedge_y - 1.0), 1.4, RED)
	_dot(ci, Vector2(r.position.x + r.size.x * 0.74, hedge_y - 1.0), 1.4, BRASS_LIGHT)

## Tejado a dos aguas sobre un volumen: la cumbrera a lo largo de x
## (`ridge_x`) o de y. El faldon que mira a la luz, mas claro.
static func _gable(ci: CanvasItem, r: Rect2, h: float, roof: Color, wall: Color, ridge_x: bool) -> Rect2:
	var top := _block(ci, r, h, roof, wall)
	var wall_saved := _wall
	var c := top.get_center()
	var a: Rect2
	var b: Rect2
	var na: Vector2
	if ridge_x:
		a = Rect2(top.position, Vector2(top.size.x, top.size.y * 0.5))
		b = Rect2(Vector2(top.position.x, c.y), Vector2(top.size.x, top.size.y * 0.5))
		na = Vector2(0, -1)
	else:
		a = Rect2(top.position, Vector2(top.size.x * 0.5, top.size.y))
		b = Rect2(Vector2(c.x, top.position.y), Vector2(top.size.x * 0.5, top.size.y))
		na = Vector2(-1, 0)
	var lit := na.dot(-_down) + na.dot(_left()) * 0.5 > 0.0
	ci.draw_rect(a, roof.lightened(0.1) if lit else roof.darkened(0.14))
	ci.draw_rect(b, roof.darkened(0.14) if lit else roof.lightened(0.1))
	# Hileras de teja paralelas a la cumbrera
	for half in [a, b]:
		var hr: Rect2 = half
		for i in range(1, 3):
			if ridge_x:
				var y := hr.position.y + hr.size.y * i / 3.0
				ci.draw_line(Vector2(hr.position.x + 1, y), Vector2(hr.end.x - 1, y), roof.darkened(0.3), 1.0)
			else:
				var x := hr.position.x + hr.size.x * i / 3.0
				ci.draw_line(Vector2(x, hr.position.y + 1), Vector2(x, hr.end.y - 1), roof.darkened(0.3), 1.0)
	if ridge_x:
		ci.draw_line(Vector2(top.position.x, c.y), Vector2(top.end.x, c.y), roof.lightened(0.35), 2.0)
	else:
		ci.draw_line(Vector2(c.x, top.position.y), Vector2(c.x, top.end.y), roof.lightened(0.35), 2.0)
	ci.draw_rect(top, OUTLINE, false, 1.0)
	_wall = wall_saved
	return top

## Aserradero abierto (como el 3D): media cubierta de chapa atras, el suelo de
## tablas al aire delante y, a la vista, la mesa con el tronco, el tablon cortado
## y la sierra ENORME de buje rojo (lo exagerado). Pilas de troncos y tablones.
static func _sawmill(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	# Suelo de tablas (plano)
	ci.draw_rect(r.grow(1.0), OUTLINE)
	ci.draw_rect(r, LIGHT_WOOD)
	for i in range(1, 7):
		var y := r.position.y + r.size.y * i / 7.0
		ci.draw_line(Vector2(r.position.x + 1, y), Vector2(r.end.x - 1, y), WOOD, 1.0)
	# Media cubierta atras (arriba en el marco local), con su pared
	var roof_r := Rect2(r.position, Vector2(r.size.x, r.size.y * 0.42))
	_ground_shadow(ci, roof_r, m * 0.12)
	var roof := _block(ci, roof_r, m * 0.12, SLATE.lightened(0.12), WOOD.darkened(0.2))
	for i in range(1, 7):
		var x := roof.position.x + roof.size.x * i / 7.0
		ci.draw_line(Vector2(x, roof.position.y + 1), Vector2(x, roof.end.y - 1), SLATE.lightened(0.32), 1.0)
	# Postes del frente
	for fx in [0.04, 0.96]:
		var p := Vector2(r.position.x + r.size.x * fx, r.position.y + r.size.y * 0.42)
		ci.draw_rect(Rect2(p - Vector2(2, 0), Vector2(4, r.size.y * 0.56)), OUTLINE)
		ci.draw_rect(Rect2(p - Vector2(1.2, 0), Vector2(2.4, r.size.y * 0.56)), DARK_WOOD)
	# Chimenea de la maquina de vapor, con el anillo rojo
	var chim := roof.position + roof.size * Vector2(0.84, 0.3)
	_cyl(ci, chim, m * 0.07, m * 0.08, IRON, SLATE)
	_dot(ci, chim, m * 0.035, RED)
	# Mesa de la sierra, de lado a lado
	var ty := r.position.y + r.size.y * 0.63
	var table := Rect2(Vector2(r.position.x + r.size.x * 0.06, ty - m * 0.08), Vector2(r.size.x * 0.88, m * 0.16))
	ci.draw_rect(table.grow(1.0), OUTLINE)
	ci.draw_rect(table, SLATE)
	# Tronco entrando por la izquierda y tablon saliendo por la derecha
	var log_r := Rect2(Vector2(table.position.x + 1, ty - m * 0.07), Vector2(r.size.x * 0.3, m * 0.14))
	ci.draw_rect(log_r.grow(0.8), OUTLINE)
	ci.draw_rect(log_r, WOOD)
	ci.draw_line(log_r.position + Vector2(0, 2), Vector2(log_r.end.x, log_r.position.y + 2), WOOD.lightened(0.2), 1.0)
	_disc(ci, Vector2(log_r.position.x + 1, ty), m * 0.07, LIGHT_WOOD.lightened(0.15), OUTLINE, 1.0)
	ci.draw_arc(Vector2(log_r.position.x + 1, ty), m * 0.035, 0.0, TAU, 10, WOOD, 1.0)
	var plank := Rect2(Vector2(r.position.x + r.size.x * 0.64, ty - m * 0.05), Vector2(r.size.x * 0.28, m * 0.1))
	ci.draw_rect(plank.grow(0.8), OUTLINE)
	ci.draw_rect(plank, CREAM)
	# Troncos delante a la izquierda, tablones delante a la derecha
	var lr := m * 0.07
	for k in 3:
		var p := Vector2(r.position.x + r.size.x * 0.12 + k * lr * 2.0, r.end.y - lr * 1.5)
		_disc(ci, p, lr, LIGHT_WOOD.lightened(0.1), OUTLINE, 1.0)
		_dot(ci, p, lr * 0.35, WOOD)
	var stack := Rect2(Vector2(r.position.x + r.size.x * 0.64, r.end.y - m * 0.2), Vector2(r.size.x * 0.3, m * 0.15))
	ci.draw_rect(stack.grow(0.8), OUTLINE)
	ci.draw_rect(stack, CREAM.darkened(0.06))
	for j in range(1, 3):
		var y := stack.position.y + stack.size.y * j / 3.0
		ci.draw_line(Vector2(stack.position.x, y), Vector2(stack.end.x, y), WOOD, 1.0)
	# La sierra: el elemento exagerado. Dientes, disco brillante y buje rojo.
	var b := Vector2(r.get_center().x, ty)
	var sr := m * 0.3
	_dot(ci, b + _shade * 2.5, sr * 1.02, SHADOW)
	_dot(ci, b, sr * 1.1, OUTLINE)
	for i in range(16):
		var ang := TAU * i / 16.0
		var pts := PackedVector2Array([b + Vector2.from_angle(ang) * sr * 0.86, b + Vector2.from_angle(ang + 0.2) * sr * 1.08,
			b + Vector2.from_angle(ang + 0.36) * sr * 0.86])
		ci.draw_colored_polygon(pts, STEEL.lightened(0.25))
	_dot(ci, b, sr * 0.88, STEEL.lightened(0.18))
	ci.draw_arc(b, sr * 0.6, 0.0, TAU, 18, STEEL.lightened(0.4), 1.0)
	ci.draw_arc(b, sr * 0.78, PI * 1.05, PI * 1.6, 8, Color(1, 1, 1, 0.75), 2.0)
	_disc(ci, b, sr * 0.28, RED, OUTLINE, 1.25)
	_dot(ci, b, sr * 0.09, BRASS_LIGHT)

## Mina de oro: el cerro de roca con la boca oscura entibada de madera, los
## railes que bajan al frente con la vagoneta llena de oro, y arriba el
## castillete con su rueda de laton (lo exagerado).
static func _gold_mine(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	var c := r.get_center()
	# Explanada de tierra
	ci.draw_rect(r.grow(1.0), OUTLINE)
	ci.draw_rect(r, SITE_DIRT.lightened(0.08))
	# El cerro: un monte de piedra con su cara de luz
	var hill := PackedVector2Array()
	var hc := c + Vector2(0, -r.size.y * 0.1)
	for i in 12:
		var a := TAU * i / 12.0
		var k := 1.0 + 0.1 * sin(a * 3.0)
		hill.append(hc + Vector2(cos(a) * r.size.x * 0.46, sin(a) * r.size.y * 0.34) * k)
	_poly(ci, hill, STONE, OUTLINE, 1.5)
	var lit := PackedVector2Array()
	for p in hill:
		lit.append(hc + (p - hc) * 0.62 - Vector2(2, 3))
	ci.draw_colored_polygon(lit, STONE.lightened(0.16))
	for p in [Vector2(-0.3, -0.12), Vector2(0.28, 0.0), Vector2(-0.12, 0.12)]:
		_dot(ci, hc + p * r.size, m * 0.04, CONCRETE_DARK)
	# Railes que salen de la boca hasta el borde
	var mouth := Vector2(c.x, r.position.y + r.size.y * 0.52)
	for side in [-1.0, 1.0]:
		ci.draw_line(Vector2(c.x + side * m * 0.09, mouth.y), Vector2(c.x + side * m * 0.09, r.end.y - 1), IRON, 1.5)
	for i in 5:
		var y := mouth.y + (r.end.y - mouth.y) * (i + 0.5) / 5.0
		ci.draw_line(Vector2(c.x - m * 0.14, y), Vector2(c.x + m * 0.14, y), DARK_WOOD, 1.5)
	# La boca entibada
	var mw := m * 0.34
	var arch := Rect2(Vector2(mouth.x - mw * 0.5, mouth.y - mw * 0.5), Vector2(mw, mw * 0.55))
	ci.draw_rect(arch.grow(2.5), OUTLINE)
	ci.draw_rect(arch.grow(1.5), WOOD)
	ci.draw_rect(arch, OIL_BLACK)
	ci.draw_rect(Rect2(arch.position - Vector2(2, 3), Vector2(arch.size.x + 4, 3)), DARK_WOOD)
	_dot(ci, arch.get_center() + Vector2(0, 1), 1.2, GLOW)
	# La vagoneta llena de oro, en los railes
	var cart := Rect2(Vector2(c.x - m * 0.15, r.end.y - m * 0.28), Vector2(m * 0.3, m * 0.18))
	ci.draw_rect(cart.grow(1.0), OUTLINE)
	ci.draw_rect(cart, RED)
	ci.draw_rect(Rect2(cart.position, Vector2(cart.size.x, 2)), RED.lightened(0.25))
	for p in [Vector2(0.25, 0.35), Vector2(0.55, 0.3), Vector2(0.75, 0.55), Vector2(0.4, 0.6)]:
		_disc(ci, cart.position + cart.size * p, m * 0.05, BRASS_LIGHT, BRASS_DARK, 1.0)
	# El castillete con su rueda (lo exagerado), sobre el cerro
	var wheel := Vector2(c.x + r.size.x * 0.22, r.position.y + r.size.y * 0.18)
	var foot_l := wheel + Vector2(-m * 0.14, m * 0.22)
	var foot_r := wheel + Vector2(m * 0.14, m * 0.22)
	for f in [foot_l, foot_r]:
		ci.draw_line(f, wheel, OUTLINE, 4.0)
		ci.draw_line(f, wheel, WOOD, 2.5)
	var wr := m * 0.15
	ci.draw_arc(wheel, wr, 0.0, TAU, 20, OUTLINE, 4.5)
	ci.draw_arc(wheel, wr, 0.0, TAU, 20, BRASS, 3.0)
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		ci.draw_line(wheel - Vector2.from_angle(a) * wr, wheel + Vector2.from_angle(a) * wr, BRASS_DARK, 1.2)
	_disc(ci, wheel, m * 0.045, RED, OUTLINE, 1.0)
	ci.draw_line(wheel, mouth + Vector2(0, -mw * 0.3), IRON, 1.0)

## Mercado: tres toldos grandes a rayas (lo exagerado) sobre su entarimado, con
## la mercancia delante de cada puesto. Acento de laton: el letrero.
static func _market(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	ci.draw_rect(r.grow(1.0), OUTLINE)
	ci.draw_rect(r, LIGHT_WOOD)
	for i in range(1, 6):
		var x := r.position.x + r.size.x * i / 6.0
		ci.draw_line(Vector2(x, r.position.y + 1), Vector2(x, r.end.y - 1), WOOD, 1.0)
	var stalls := [
		[Rect2(r.position + r.size * Vector2(0.02, 0.02), r.size * Vector2(0.46, 0.42)), RED, [RED.lightened(0.1), GREEN, RED]],
		[Rect2(r.position + r.size * Vector2(0.52, 0.02), r.size * Vector2(0.46, 0.42)), SKY, [BRASS_LIGHT, LIGHT_WOOD, BRASS]],
		[Rect2(r.position + r.size * Vector2(0.27, 0.52), r.size * Vector2(0.46, 0.4)), GREEN, [TERRACOTTA, BRASS_LIGHT, GREEN.lightened(0.2)]],
	]
	for s in stalls:
		var sr: Rect2 = s[0]
		var col: Color = s[1]
		_ground_shadow(ci, sr, m * 0.1)
		var top := _block(ci, sr, m * 0.08, CREAM, col.darkened(0.15))
		# Rayas del toldo
		var n := 4
		for k in n:
			if k % 2 == 0:
				var x0 := top.position.x + top.size.x * k / float(n)
				ci.draw_rect(Rect2(Vector2(x0, top.position.y), Vector2(top.size.x / float(n), top.size.y)), col)
		ci.draw_rect(top, OUTLINE, false, 1.0)
		# Faldon festoneado en la pared
		var horizontal := absf(_down.y) > 0.5
		var wl := _wall.size.x if horizontal else _wall.size.y
		for k in 5:
			var t := wl * (k + 0.5) / 5.0
			var p := (Vector2(_wall.position.x + t, _wall.end.y) if (horizontal and _down.y > 0) else
				(Vector2(_wall.position.x + t, _wall.position.y) if horizontal else
				(Vector2(_wall.end.x, _wall.position.y + t) if _down.x > 0 else Vector2(_wall.position.x, _wall.position.y + t))))
			_dot(ci, p, wl / 10.0, col)
		# La mercancia: tres montones delante del puesto
		var goods: Array = s[2]
		for k in 3:
			var g := sr.get_center() + Vector2(sr.size.x * (k - 1) * 0.3, -sr.size.y * 0.05)
			_disc(ci, g, m * 0.055, goods[k], OUTLINE, 1.0)
	# Letrero de laton en medio
	var sign_c := r.position + r.size * Vector2(0.5, 0.47)
	_disc(ci, sign_c, m * 0.06, BRASS, OUTLINE, 1.0)

## Laboratorio: un bloque crema con remaches y la gran cupula de cristal que
## brilla en azul (lo exagerado), con nervios de laton; una antena con la luz
## roja en la punta.
static func _laboratory(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	var top := _block(ci, r, m * 0.16, Color8(214, 198, 170), CREAM.darkened(0.08))
	_wall_marks(ci, _wall, 4, SKY.lightened(0.3), 0.45)
	_rivets(ci, top, BRASS)
	# La cupula: halo azul, cuerpo de cristal, nervios y brillo
	var c := top.get_center() - _down * m * 0.04
	var rad := m * 0.3
	_dot(ci, c, rad * 1.28, Color(SKY.lightened(0.3), 0.35))
	_cyl(ci, c, rad, m * 0.06, SKY, BRASS_DARK)
	_dot(ci, c, rad * 0.78, SKY.lightened(0.18))
	for i in 3:
		var a := PI * i / 3.0
		ci.draw_line(c - Vector2.from_angle(a) * rad, c + Vector2.from_angle(a) * rad, BRASS, 1.25)
	_dot(ci, c + (_left() - _down) * rad * 0.32, rad * 0.26, Color(1, 1, 1, 0.75))
	_disc(ci, c, m * 0.05, BRASS_LIGHT, OUTLINE, 1.0)
	# Antena con su luz
	var base := Vector2(top.end.x - m * 0.1, top.position.y + m * 0.14)
	var tip := _mast(ci, base, m * 0.28, IRON, 1.6)
	ci.draw_line(tip + _left() * 3.0 + _down * 3.0, tip - _left() * 3.0 + _down * 3.0, IRON, 1.2)
	_disc(ci, tip, 1.8, RED, OUTLINE, 1.0)

## Granja: el campo de surcos (el cultivo lo pone `_farm_crops`), el granero
## rojo con la cruz crema en el porton y el silo de laton (lo exagerado).
static func _farm(ci: CanvasItem, r: Rect2, growth: float, ripe: bool) -> void:
	var m := minf(r.size.x, r.size.y)
	ci.draw_rect(r.grow(1.0), OUTLINE)
	ci.draw_rect(r, SITE_DIRT)
	var field := _farm_field(r)
	ci.draw_rect(field, Color8(130, 84, 48))
	var rows := 4
	for i in rows:
		var y := field.position.y + field.size.y * (i + 0.5) / float(rows)
		ci.draw_line(Vector2(field.position.x + 1, y), Vector2(field.end.x - 1, y), Color8(96, 58, 32), 3.0)
	ci.draw_rect(field, OUTLINE, false, 1.0)
	if growth >= 0.0:
		_farm_crops(ci, field, growth, ripe)
	# Granero rojo
	var barn := Rect2(Vector2(field.end.x + 2, r.position.y + 1), Vector2(r.end.x - field.end.x - 3, r.size.y * 0.5))
	_ground_shadow(ci, barn, m * 0.12)
	var top := _gable(ci, barn, m * 0.14, SLATE.lightened(0.1), RED, false)
	var dc := _wall.get_center()
	var horizontal := absf(_down.y) > 0.5
	var ds := Vector2(_wall.size.x * 0.5, _wall.size.y * 0.8) if horizontal else Vector2(_wall.size.x * 0.8, _wall.size.y * 0.5)
	var door := Rect2(dc - ds * 0.5, ds)
	ci.draw_rect(door, RED.darkened(0.25))
	ci.draw_line(door.position, door.end, CREAM, 1.2)
	ci.draw_line(Vector2(door.end.x, door.position.y), Vector2(door.position.x, door.end.y), CREAM, 1.2)
	ci.draw_rect(door, CREAM, false, 1.0)
	# Silo de laton con su cupula
	var silo := Vector2(barn.get_center().x, r.position.y + r.size.y * 0.66)
	var sr := minf(barn.size.x * 0.42, m * 0.17)
	_cyl(ci, silo, sr, m * 0.2, BRASS, CREAM.darkened(0.05))
	_cyl_band(ci, silo, sr, m * 0.2, 0.45, 1.5, RED)
	_dot(ci, silo, sr * 0.3, BRASS_DARK)

static func _farm_field(r: Rect2) -> Rect2:
	return Rect2(r.position + Vector2(2, 2), Vector2(r.size.x * 0.6, r.size.y - 4))

static func _farm_crops(ci: CanvasItem, field: Rect2, growth: float, ripe: bool) -> void:
	var g := clampf(growth, 0.0, 1.0)
	var crop := BRASS if ripe else GREEN.lerp(BRASS, clampf((g - 0.55) / 0.45, 0.0, 1.0))
	var rows := 4
	var plants := 4
	for i in rows:
		var y := field.position.y + field.size.y * (i + 0.5) / float(rows)
		for k in plants:
			var x := field.position.x + field.size.x * (k + 0.5) / float(plants)
			var rad := lerpf(1.0, field.size.y / float(rows) * 0.42, g)
			_dot(ci, Vector2(x, y), rad + 0.6, crop.darkened(0.45))
			_dot(ci, Vector2(x, y), rad, crop)
			if rad > 2.0:
				_dot(ci, Vector2(x - rad * 0.3, y - rad * 0.3), rad * 0.4, crop.lightened(0.3))

## Deposito: la gran nave de chapa a rayas con la franja de laton y, en la
## pared, el porton abierto con las cajas dentro. La grua (lo exagerado) es el
## remate de su parcela.
static func _warehouse(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	var top := _block(ci, r, m * 0.24, SLATE.lightened(0.12), SLATE.darkened(0.12))
	# Chapa ondulada perpendicular a la pared
	var horizontal := absf(_down.y) > 0.5
	for i in range(1, 8):
		if horizontal:
			var x := top.position.x + top.size.x * i / 8.0
			ci.draw_line(Vector2(x, top.position.y + 1), Vector2(x, top.end.y - 1), SLATE.lightened(0.32), 1.0)
		else:
			var y := top.position.y + top.size.y * i / 8.0
			ci.draw_line(Vector2(top.position.x + 1, y), Vector2(top.end.x - 1, y), SLATE.lightened(0.32), 1.0)
	# Franja de laton atravesando el tejado
	if horizontal:
		ci.draw_rect(Rect2(Vector2(top.position.x, top.get_center().y - 2), Vector2(top.size.x, 4)), BRASS)
	else:
		ci.draw_rect(Rect2(Vector2(top.get_center().x - 2, top.position.y), Vector2(4, top.size.y)), BRASS)
	_rivets(ci, top, BRASS_LIGHT, 3.0)
	# El porton abierto en la pared, con cajas dentro
	var dc := _wall.get_center()
	var ds := Vector2(r.size.x * 0.46, _wall.size.y) if horizontal else Vector2(_wall.size.x, r.size.y * 0.46)
	var door := Rect2(dc - ds * 0.5, ds)
	ci.draw_rect(door.grow(1.0), BRASS_DARK)
	ci.draw_rect(door, OIL_BLACK)
	for k in 2:
		var bc := dc + (_left() * ds.length() * 0.18 * (1.0 if k == 0 else -1.0)) + _down * 1.0
		var bs := Vector2(m * 0.09, m * 0.09)
		ci.draw_rect(Rect2(bc - bs * 0.5, bs), WOOD)
		ci.draw_rect(Rect2(bc - bs * 0.5, bs), OUTLINE, false, 1.0)
	# El polipasto: una viga de laton que sale del tejado sobre el porton, con
	# su gancho y una caja colgando (la grua grande va en la parcela).
	var root := dc - _down * (_wall.size.y if horizontal else _wall.size.x) - _down * m * 0.18
	var tipp := root + _down * m * 0.3
	var lift := -_down * m * 0.14
	ci.draw_line(root + lift, tipp + lift, OUTLINE, 5.0)
	ci.draw_line(root + lift, tipp + lift, BRASS, 3.0)
	ci.draw_line(tipp + lift, tipp + lift * 0.3, IRON, 1.0)
	var cs := Vector2(m * 0.12, m * 0.12)
	ci.draw_rect(Rect2(tipp + lift * 0.3 - cs * 0.5, cs).grow(0.8), OUTLINE)
	ci.draw_rect(Rect2(tipp + lift * 0.3 - cs * 0.5, cs), LIGHT_WOOD)

## Fundicion: nave de ladrillo con la boca del horno encendida en la pared, una
## chimenea pequena y la GRANDE de ladrillo con el anillo rojo (lo exagerado).
static func _foundry(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	var top := _block(ci, r, m * 0.24, SLATE, TILE_RED)
	# Ladrillo en la pared
	var horizontal := absf(_down.y) > 0.5
	for i in range(1, 3):
		if horizontal:
			var y := _wall.position.y + _wall.size.y * i / 3.0
			ci.draw_line(Vector2(_wall.position.x, y), Vector2(_wall.end.x, y), TILE_RED_DARK, 1.0)
		else:
			var x := _wall.position.x + _wall.size.x * i / 3.0
			ci.draw_line(Vector2(x, _wall.position.y), Vector2(x, _wall.end.y), TILE_RED_DARK, 1.0)
	# La boca del horno, incandescente, en medio de la pared
	var dc := _wall.get_center()
	var ds := Vector2(r.size.x * 0.4, _wall.size.y * 0.8) if horizontal else Vector2(_wall.size.x * 0.8, r.size.y * 0.4)
	var mouth := Rect2(dc - ds * 0.5, ds)
	ci.draw_rect(mouth.grow(1.0), OUTLINE)
	ci.draw_rect(mouth, FIRE)
	ci.draw_rect(mouth.grow(-minf(ds.x, ds.y) * 0.25), FIRE_CORE)
	# Respiraderos en el tejado
	for k in 3:
		var p := top.position + top.size * Vector2(0.18 + 0.2 * k, 0.72)
		ci.draw_rect(Rect2(p - Vector2(2.5, 1.5), Vector2(5, 3)), IRON)
	# Chimenea pequena y la grande (lo exagerado)
	var a: Vector2 = r.position + r.size * (fx_anchors("foundry")[0] as Vector2)
	var b: Vector2 = r.position + r.size * (fx_anchors("foundry")[1] as Vector2)
	_cyl(ci, a, m * 0.09, m * 0.12, OIL_BLACK, TILE_RED_DARK)
	var ch := m * 0.46
	ci.draw_line(b + _down * ch, b + _down * ch + _shade * ch * 0.7, Color(SHADOW, 0.32), m * 0.2)
	_cyl(ci, b, m * 0.12, ch, OIL_BLACK, TILE_RED)
	for k in 3:
		_cyl_band(ci, b, m * 0.12, ch, 0.28 + 0.2 * k, 1.0, TILE_RED_DARK)
	_cyl_band(ci, b, m * 0.12, ch, 0.06, 2.5, RED)
	_dot(ci, b, m * 0.07, FIRE.darkened(0.2))
	_dot(ci, a, m * 0.04, FIRE.darkened(0.2))

## Cuartel: barracon de piedra con tejado de chapa, la franja amarillo/negro
## de lo militar y la estrella de laton. Encima, la peana del mastil corto: el
## palo y la bandera del pais los pinta ColonyFlag2D (`flag_mount`, como la
## receta 3D con su FlagAnchor), 2026-10-18.
static func _barracks(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	var body := Rect2(r.position + Vector2(0, r.size.y * 0.12), Vector2(r.size.x, r.size.y * 0.76))
	var top := _gable(ci, body, m * 0.2, OLIVE, STONE, true)
	_wall_marks(ci, _wall, 3, OIL_BLACK.lightened(0.15), 0.28)
	# Franja militar a lo largo de la cumbrera
	var c := top.get_center()
	_hazard_strip(ci, Rect2(Vector2(top.position.x + 2, c.y - 1.5), Vector2(top.size.x - 4, 3)))
	_star(ci, c + Vector2(-top.size.x * 0.24, -top.size.y * 0.22), m * 0.11, BRASS_LIGHT)
	# La peana del mastil (el palo y la bandera, ColonyFlag2D)
	var mb := _barracks_mast_base(r)
	_block(ci, Rect2(mb - Vector2(m * 0.04, m * 0.04), Vector2(m * 0.08, m * 0.08)), m * 0.025, STONE.darkened(0.12), CONCRETE_DARK)
	_dot(ci, mb, m * 0.018, IRON)
	# Estufa del barracon (de ahi sale el humo de "trabajando")
	var stove: Vector2 = r.position + r.size * (fx_anchors("barracks")[0] as Vector2)
	_cyl(ci, stove, m * 0.06, m * 0.1, OIL_BLACK, SLATE)

## Refineria: losa de chapa con un deposito grande (tapa crema, anillo rojo),
## uno pequeno, tuberias de laton con valvulas rojas y la columna de
## destilacion alta (lo exagerado) con la antorcha encendida.
static func _refinery(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	ci.draw_rect(r.grow(1.0), OUTLINE)
	_plate(ci, r, SLATE.lightened(0.18), OUTLINE, 1.0)
	_rivets(ci, r, BRASS, 3.0)
	var t1 := r.position + r.size * Vector2(0.3, 0.3)
	var t2 := r.position + r.size * Vector2(0.26, 0.74)
	var col: Vector2 = r.position + r.size * (fx_anchors("refinery")[0] as Vector2)
	var col_h := m * 0.44
	# Tuberias de laton entre todo (por el suelo)
	for pair in [[t1, t2], [t2, col + _down * col_h], [t1, col + _down * col_h * 0.6]]:
		ci.draw_line(pair[0], pair[1], OUTLINE, 5.0)
		ci.draw_line(pair[0], pair[1], BRASS, 3.0)
	for p in [(t1 + t2) * 0.5, (t2 + col + _down * col_h) * 0.5]:
		ci.draw_arc(p, 3.2, 0.0, TAU, 10, OUTLINE, 2.5)
		ci.draw_arc(p, 3.2, 0.0, TAU, 10, RED, 1.5)
	# Depositos
	_cyl(ci, t1, m * 0.2, m * 0.16, CREAM, CREAM.darkened(0.12))
	_cyl_band(ci, t1, m * 0.2, m * 0.16, 0.35, 2.0, RED)
	ci.draw_arc(t1, m * 0.11, 0.0, TAU, 16, STONE, 1.0)
	_cyl(ci, t2, m * 0.13, m * 0.1, STONE.lightened(0.1), STONE)
	# La columna de destilacion con sus anillos y la antorcha
	_cyl(ci, col, m * 0.11, col_h, SLATE.lightened(0.25), SLATE.lightened(0.1))
	for k in 3:
		_cyl_band(ci, col, m * 0.11, col_h, 0.2 + 0.28 * k, 1.5, RED)
	_dot(ci, col, m * 0.12, Color(FIRE, 0.45))
	_disc(ci, col, m * 0.06, FIRE, OUTLINE, 1.0)
	_dot(ci, col, m * 0.03, FIRE_CORE)

## Torre de vigilancia: bastion redondo de piedra con la franja amarillo/negro,
## corona de sacos terreros y el canon largo (lo exagerado) asomando; un foco.
static func _tower(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	var h := m * 0.5
	var c := r.get_center() - _down * m * 0.08
	var wall_h := m * 0.2
	_cyl(ci, c, h * 0.84, wall_h, CONCRETE, STONE.darkened(0.08))
	_cyl_band(ci, c, h * 0.84, wall_h, 0.45, 3.0, BRASS)
	# Corona de sacos
	for i in range(12):
		var a := TAU * i / 12.0
		_disc(ci, c + Vector2(cos(a), sin(a)) * h * 0.7, h * 0.13, CREAM.darkened(0.06), OUTLINE, 1.0)
	_dot(ci, c, h * 0.56, CONCRETE_DARK)
	# Torreta y canon
	var aim := Vector2(1.0, -0.55).normalized()
	ci.draw_line(c + _shade * 3.0, c + _shade * 3.0 + aim * h * 1.15, SHADOW, 5.0)
	ci.draw_line(c, c + aim * h * 1.15, OUTLINE, 6.5)
	ci.draw_line(c, c + aim * h * 1.15, IRON.lightened(0.18), 4.0)
	ci.draw_line(c + aim * h * 1.0, c + aim * h * 1.15, RED, 4.0)
	_shaded_disc(ci, c, h * 0.3, SLATE)
	_hazard_strip(ci, Rect2(c - Vector2(h * 0.18, h * 0.05), Vector2(h * 0.36, h * 0.1)))
	# Foco
	var lamp: Vector2 = r.position + r.size * (fx_anchors("tower")[0] as Vector2)
	_disc(ci, lamp, 2.6, GLOW, OUTLINE, 1.0)

## Cuartel General: escalinata de piedra, gran edificio crema con columnas en
## la fachada y estandartes rojos, tejado de pizarra con filo de laton y, en el
## centro, el emblema de la Regencia sobre su torreon (lo exagerado).
static func _headquarters(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	_block(ci, r, m * 0.06, Color8(214, 198, 170), CONCRETE)
	var hall := r.grow(-m * 0.08)
	var top := _block(ci, hall, m * 0.2, SLATE.lightened(0.05), CREAM)
	ci.draw_rect(top.grow(-1.5), BRASS, false, 1.5)
	# Columnas en la fachada
	_wall_marks(ci, _wall, 5, CREAM.darkened(0.25), 0.3, CREAM.darkened(0.4))
	# Estandartes rojos colgando del tejado
	var horizontal := absf(_down.y) > 0.5
	for fx in [0.2, 0.8]:
		var p := (Vector2(_wall.position.x + _wall.size.x * fx, _wall.get_center().y) if horizontal
			else Vector2(_wall.get_center().x, _wall.position.y + _wall.size.y * fx))
		var s := Vector2(m * 0.1, _wall.size.y * 1.1) if horizontal else Vector2(_wall.size.x * 1.1, m * 0.1)
		ci.draw_rect(Rect2(p - s * 0.5, s).grow(0.8), OUTLINE)
		ci.draw_rect(Rect2(p - s * 0.5, s), RED)
		_dot(ci, p, minf(s.x, s.y) * 0.25, BRASS_LIGHT)
	# El torreon con el emblema (sin mastil ni bandera del pais desde
	# 2026-10-18: la bandera va en el Nucleo y en los Cuarteles).
	var e := top.get_center() - _down * m * 0.02
	_cyl(ci, e, m * 0.22, m * 0.1, BRASS_DARK, CREAM.darkened(0.08))
	_emblem_2d(ci, e, m * 0.19, BRASS_LIGHT, false)

## Los dibujos que traen mastil para la bandera del pais (como el FlagAnchor de
## las recetas 3D): el Nucleo, el Cuartel, el mastil y el letrero de la
## colonia. Building2D les cuelga ColonyFlag2D.
static func has_flag_mount(id: String) -> bool:
	return id in ["nucleo", "barracks", "flagpole", "colony_sign"]

## Donde nace el mastil corto del Cuartel: sobre el tejado, a la derecha de la
## estrella y lejos del borde, para que la bandera (que cuelga hacia la
## derecha) no se salga de su casilla ni tape al vecino.
static func _barracks_mast_base(r: Rect2) -> Vector2:
	return Vector2(r.position.x + r.size.x * 0.6, r.position.y + r.size.y * 0.3)

## El mastil de la bandera del pais de un edificio, en el marco del NODO (sin
## girar: ya con el giro `steps` aplicado): {"base", "height", "flag_w"}, o {}
## si su dibujo no trae mastil (ColonyFlag2D pone entonces el suyo de reserva).
## Usa las mismas medidas que el dibujo (huella `size`, patio `inset`, nivel),
## asi que la bandera cuelga justo de lo alto de la linterna del Nucleo o del
## mastil del Cuartel.
static func flag_mount(id: String, size: Vector2, inset: float, steps: int, level: int = 1) -> Dictionary:
	if not has_flag_mount(id):
		return {}
	_set_view(steps)
	var r := grown_rect(Rect2(-size * 0.5, size).grow(-INSET - inset), level)
	var m := minf(r.size.x, r.size.y)
	var base := Vector2.ZERO
	var height := 0.0
	var flag_w := 0.0
	if id == "flagpole":
		var fp := _flagpole_mast(r, m)
		base = fp[0]
		height = fp[1]
		flag_w = m * 0.36
	elif id == "colony_sign":
		var cs := _colony_sign_mast(r, m)
		base = cs[0]
		height = cs[1]
		flag_w = m * 0.24
	elif id == "nucleo":
		base = _nucleo_geom(r)["lantern_top"]
		height = m * 0.3
		flag_w = m * 0.34
	else:
		# El Cuartel: mastil corto y bandera mediana (la del Cuartel General de
		# antes, m * 0.62 y m * 0.5, se veia enorme).
		base = _barracks_mast_base(r)
		height = m * 0.36
		flag_w = m * 0.3
	return {"base": base.rotated(float(steps) * PI * 0.5), "height": height, "flag_w": flag_w}

## Jardin: seto alrededor, cesped claro con un sendero, parterres de flores y
## un arbol grande y redondo (lo exagerado). Acento verde.
static func _garden(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	ci.draw_rect(r.grow(1.0), OUTLINE)
	ci.draw_rect(r, LEAF_DARK)
	ci.draw_rect(r.grow(-3.5), GREEN.lightened(0.12))
	# Sendero de piedra
	ci.draw_line(Vector2(r.position.x + 3, r.end.y - m * 0.22), Vector2(r.end.x - 3, r.position.y + m * 0.4), STONE.lightened(0.2), m * 0.1)
	# Parterres
	var cols := [RED, BRASS_LIGHT, CREAM, TERRACOTTA, RED]
	var pts := [Vector2(0.2, 0.24), Vector2(0.22, 0.6), Vector2(0.45, 0.8), Vector2(0.78, 0.78), Vector2(0.5, 0.42)]
	for i in pts.size():
		var p: Vector2 = r.position + r.size * (pts[i] as Vector2)
		_disc(ci, p, m * 0.08, LEAF_DARK, OUTLINE, 1.0)
		for k in 3:
			_dot(ci, p + Vector2.from_angle(TAU * k / 3.0 + i) * m * 0.035, m * 0.025, cols[i])
	# El arbol grande
	var t := r.position + r.size * Vector2(0.7, 0.36)
	var tr := m * 0.24
	_dot(ci, t + _shade * tr * 0.6, tr, SHADOW)
	_dot(ci, t, tr + 1.0, OUTLINE)
	_dot(ci, t, tr, GREEN.darkened(0.08))
	_dot(ci, t + (_left() - _down) * tr * 0.25, tr * 0.6, GREEN.lightened(0.12))
	_dot(ci, t + (_left() - _down) * tr * 0.42, tr * 0.22, GREEN.lightened(0.35))
	_dot(ci, t + Vector2(tr * 0.35, tr * 0.2), 1.6, RED)

## Fuente: pilon redondo de piedra con el agua azul y sus ondas, y el surtidor
## crema con la taza de laton en medio (lo exagerado).
static func _fountain(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	ci.draw_rect(r.grow(1.0), OUTLINE)
	ci.draw_rect(r, Color8(214, 198, 170))
	var h := m * 0.5
	var c := r.get_center() - _down * m * 0.03
	_cyl(ci, c, h * 0.88, m * 0.08, STONE.lightened(0.1), STONE.darkened(0.1))
	_dot(ci, c, h * 0.72, WATER.darkened(0.1))
	_dot(ci, c, h * 0.62, WATER)
	ci.draw_arc(c, h * 0.45, 0.4, 2.2, 10, WATER.lightened(0.45), 1.25)
	ci.draw_arc(c, h * 0.3, 3.5, 5.2, 10, WATER.lightened(0.45), 1.25)
	var spout_h := m * 0.2
	_cyl(ci, c - _down * spout_h * 0.6, h * 0.14, spout_h, BRASS, CREAM)
	var top := c - _down * spout_h * 0.6
	_disc(ci, top, h * 0.26, BRASS, OUTLINE, 1.0)
	_dot(ci, top, h * 0.16, WATER.lightened(0.25))
	for i in 6:
		_dot(ci, top + Vector2.from_angle(TAU * i / 6.0) * h * 0.34, 1.3, Color(1, 1, 1, 0.85))

## Estatua Imperial: pedestal de piedra en dos escalones y la figura de laton
## grande (lo exagerado): capa roja, hombros, cabeza y el brazo en alto con la
## antorcha encendida.
static func _statue(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	_block(ci, r.grow(-m * 0.04), m * 0.07, STONE.lightened(0.12), CONCRETE_DARK)
	var top := _block(ci, r.grow(-m * 0.2), m * 0.1, CREAM, STONE)
	var c := top.get_center() + _down * m * 0.06
	var fig_h := m * 0.3
	var shoulders := c - _down * fig_h
	var side := _left() * m * 0.15
	# Capa roja por detras, del hombro al pedestal
	ci.draw_colored_polygon(PackedVector2Array([shoulders + side * 1.05, shoulders - side * 1.05,
		c - side * 1.3 + _down * m * 0.03, c + side * 1.3 + _down * m * 0.03]), OUTLINE)
	ci.draw_colored_polygon(PackedVector2Array([shoulders + side * 0.95, shoulders - side * 0.95,
		c - side * 1.18, c + side * 1.18]), RED)
	# Cuerpo de laton
	_cyl(ci, shoulders, m * 0.1, fig_h * 0.9, BRASS, BRASS_DARK)
	# Cabeza
	var head := shoulders - _down * m * 0.12
	_disc(ci, head, m * 0.075, BRASS_LIGHT, OUTLINE, 1.0)
	# El brazo en alto con la antorcha
	var hand := shoulders - side * 1.3 - _down * m * 0.26
	ci.draw_line(shoulders - side * 0.6, hand, OUTLINE, 4.0)
	ci.draw_line(shoulders - side * 0.6, hand, BRASS, 2.5)
	_dot(ci, hand - _down * 2.0, 3.4, Color(FIRE, 0.5))
	_disc(ci, hand - _down * 1.5, 2.0, FIRE_CORE, OUTLINE, 1.0)

## Calzada: adoquin calido de piedra, con bordillo crema en los lados que no
## siguen la calle y la raya de laton en los tramos rectos.
static func _road(ci: CanvasItem, cell_rect: Rect2, mask: int) -> void:
	# La celda entera, como en 3D: los tramos vecinos se tocan y la red se lee
	# como una sola carretera. Bordillo en los lados que no siguen la calle.
	var base := Color8(150, 134, 112)
	var stone := Color8(172, 156, 132)
	var curb := Color8(226, 210, 178)
	var line := BRASS
	ci.draw_rect(cell_rect, base)
	var y := cell_rect.position.y + 2.5
	var row := 0
	while y < cell_rect.end.y - 2.0:
		var x := cell_rect.position.x + (2.5 if row % 2 == 0 else 5.5)
		while x < cell_rect.end.x - 2.0:
			ci.draw_rect(Rect2(Vector2(x, y), Vector2(4.5, 3.5)), stone)
			x += 6.0
		y += 5.0
		row += 1
	var cw := cell_rect.size.x * 0.16
	var p0 := cell_rect.position
	var sz := cell_rect.size
	var edge := Color8(120, 104, 84)
	if not (mask & 1):
		ci.draw_rect(Rect2(p0, Vector2(sz.x, cw)), curb)
		ci.draw_line(Vector2(p0.x, p0.y + cw), Vector2(p0.x + sz.x, p0.y + cw), edge, 1.0)
	if not (mask & 4):
		ci.draw_rect(Rect2(Vector2(p0.x, p0.y + sz.y - cw), Vector2(sz.x, cw)), curb)
		ci.draw_line(Vector2(p0.x, p0.y + sz.y - cw), Vector2(p0.x + sz.x, p0.y + sz.y - cw), edge, 1.0)
	if not (mask & 2):
		ci.draw_rect(Rect2(Vector2(p0.x + sz.x - cw, p0.y), Vector2(cw, sz.y)), curb)
		ci.draw_line(Vector2(p0.x + sz.x - cw, p0.y), Vector2(p0.x + sz.x - cw, p0.y + sz.y), edge, 1.0)
	if not (mask & 8):
		ci.draw_rect(Rect2(p0, Vector2(cw, sz.y)), curb)
		ci.draw_line(Vector2(p0.x + cw, p0.y), Vector2(p0.x + cw, p0.y + sz.y), edge, 1.0)
	var c := cell_rect.get_center()
	if (mask & 1) and (mask & 4) and not (mask & 2) and not (mask & 8):
		ci.draw_rect(Rect2(Vector2(c.x - 1.0, p0.y + 3.0), Vector2(2.0, sz.y - 6.0)), line)
	elif (mask & 2) and (mask & 8) and not (mask & 1) and not (mask & 4):
		ci.draw_rect(Rect2(Vector2(p0.x + 3.0, c.y - 1.0), Vector2(sz.x - 6.0, 2.0)), line)

static func _star(ci: CanvasItem, c: Vector2, radius: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(10):
		var a := -PI * 0.5 + TAU * i / 10.0
		var rr := radius if i % 2 == 0 else radius * 0.42
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	_poly(ci, pts, color, OUTLINE, 1.0)

# ── Estados encima del dibujo ─────────────────────────────────────────

## Obra: rayas de peligro en el borde, andamio en aspa y barra de progreso.
static func draw_construction(ci: CanvasItem, size: Vector2, progress: float) -> void:
	var r := Rect2(-size * 0.5, size).grow(-INSET)
	ci.draw_rect(r, Color(0.12, 0.1, 0.06, 0.45))
	# Andamio
	ci.draw_line(r.position, r.end, LIGHT_WOOD, 2.0)
	ci.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), LIGHT_WOOD, 2.0)
	# Rayas amarillo/negro por el borde
	var stripe := 6.0
	var t := 0.0
	var perimeter := 2.0 * (r.size.x + r.size.y)
	var i := 0
	while t < perimeter:
		var col := HAZARD if i % 2 == 0 else IRON
		var a := _perimeter_point(r, t)
		var b := _perimeter_point(r, minf(t + stripe, perimeter))
		ci.draw_line(a, b, col, 3.0)
		t += stripe
		i += 1
	# Barra de progreso bajo la huella
	var bar := Rect2(Vector2(r.position.x + 3, r.end.y - 7), Vector2(r.size.x - 6, 4))
	ci.draw_rect(bar.grow(1), OUTLINE)
	ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(progress, 0.0, 1.0), bar.size.y)), BRASS_LIGHT)

static func _perimeter_point(r: Rect2, t: float) -> Vector2:
	if t <= r.size.x:
		return r.position + Vector2(t, 0)
	t -= r.size.x
	if t <= r.size.y:
		return Vector2(r.end.x, r.position.y + t)
	t -= r.size.y
	if t <= r.size.x:
		return Vector2(r.end.x - t, r.end.y)
	t -= r.size.x
	return Vector2(r.position.x, r.end.y - t)

## Dano: en ruinas, ceniza y el dibujo de ruina (draw_ruin); herido, las marcas
## de su etapa (draw_damage_marks: leve o grave, docs/03 "Etapas de dano") o,
## por encima del umbral leve, solo un velo de ceniza. Mas la barra de vida.
## `n`: clase de huella (1, 2, 3), para el tamano de los escombros. Building2D
## no lo usa tal cual: hornea las marcas por etapa (ArtCache2D) y las ladea con
## el edificio; esto es el dibujo entero a mano (pruebas, sondas).
static func draw_damage(ci: CanvasItem, size: Vector2, ratio: float, ruined: bool, seed_val: int, n: int = 2) -> void:
	var r := Rect2(-size * 0.5, size).grow(-INSET)
	if ratio >= 1.0 and not ruined:
		return
	var stage := LookRule.damage_stage(ratio, ruined)
	if ruined:
		ci.draw_rect(r, Color(0.10, 0.09, 0.08, 0.75))
		# La ruina tiene dibujo propio (muro roto, cascotes, vigas); el humo
		# negro lo anima Building2D con la hoja de BuildingFx.
		draw_ruin(ci, size, seed_val, n)
	elif stage == LookRule.DAMAGE_NONE:
		draw_scratch(ci, size, ratio)
	else:
		draw_damage_marks(ci, size, stage, seed_val, n)
	draw_health_bar(ci, size, ratio)

## Un rasguno (vida por encima del umbral leve): solo un velo de ceniza, como
## la capa de BuildingHealth en 3D.
static func draw_scratch(ci: CanvasItem, size: Vector2, ratio: float) -> void:
	var r := Rect2(-size * 0.5, size).grow(-INSET)
	ci.draw_rect(r, Color(0.10, 0.09, 0.08, (1.0 - clampf(ratio, 0.0, 1.0)) * 0.5))

## La barra de vida de un edificio herido (arriba de la huella).
static func draw_health_bar(ci: CanvasItem, size: Vector2, ratio: float) -> void:
	var r := Rect2(-size * 0.5, size).grow(-INSET)
	var bar := Rect2(Vector2(r.position.x + 3, r.position.y + 3), Vector2(r.size.x - 6, 4))
	ci.draw_rect(bar.grow(1), OUTLINE)
	var col := RED if ratio < 0.34 else (BRASS if ratio < 0.67 else GREEN)
	ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(ratio, 0.0, 1.0), bar.size.y)), col)

## Las marcas de una etapa de dano (1 leve, 2 grave) sobre el dibujo del
## edificio, en pantalla (sin girar). Lo mismo que la 3D visto desde arriba:
## - Leve: velo de ceniza, grietas en el tejado, huecos de tejas que faltan,
##   tejas caidas al pie y una tabla suelta que asoma por un lado.
## - Grave: velo mas oscuro, mas grietas y huecos, tizne, una chapa suelta
##   torcida, una viga partida con ascuas y cascotes al pie. El humo negro y
##   las chispas los anima Building2D (hojas de BuildingFx).
## Determinista por `seed_val` (solo cuenta seed_val % DAMAGE_VARIANTS: asi se
## hornea una textura por etapa, tamano y variante).
static func draw_damage_marks(ci: CanvasItem, size: Vector2, stage: int, seed_val: int, n: int = 2) -> void:
	if stage < LookRule.DAMAGE_LIGHT or stage > LookRule.DAMAGE_HEAVY:
		return
	var heavy := stage == LookRule.DAMAGE_HEAVY
	var r := Rect2(-size * 0.5, size).grow(-INSET)
	var rng := RandomNumberGenerator.new()
	var variant := posmod(seed_val, DAMAGE_VARIANTS)
	rng.seed = 7919 * (variant + 1) + 31 * stage
	var side := 1.0 if variant % 2 == 0 else -1.0
	var m := minf(r.size.x, r.size.y)
	ci.draw_rect(r, Color(0.10, 0.09, 0.08, 0.32 if heavy else 0.14))
	# Tizne (grave): manchas que se salen un poco del tejado.
	if heavy:
		for k in range(2 + n):
			var p := r.position + Vector2(rng.randf_range(0.15, 0.85) * r.size.x, rng.randf_range(0.15, 0.85) * r.size.y)
			_dot(ci, p, rng.randf_range(4.0, 7.0) * (0.8 + 0.2 * n), Color(0.03, 0.03, 0.03, 0.45))
	# Huecos de tejas que faltan: rectangulos oscuros con el borde claro de la
	# teja rota, en la mitad de arriba (el tejado).
	for k in range(5 if heavy else 3):
		var c := r.position + Vector2(rng.randf_range(0.15, 0.85) * r.size.x, rng.randf_range(0.12, 0.6) * r.size.y)
		var hs := Vector2(rng.randf_range(0.05, 0.09), rng.randf_range(0.04, 0.07)) * m
		var hole := Rect2(c - hs, hs * 2.0)
		ci.draw_rect(hole, Color(0.06, 0.05, 0.05, 0.92))
		ci.draw_line(hole.position, Vector2(hole.end.x, hole.position.y), TILE_RED_DARK.lightened(0.2), 1.0)
	# Grietas en zigzag (negras con un filo claro: se leen sobre cualquier tejado).
	for k in range(4 if heavy else 2):
		var p := r.position + Vector2(rng.randf_range(0.15, 0.85) * r.size.x, rng.randf_range(0.15, 0.7) * r.size.y)
		var crack := PackedVector2Array([p])
		var dir := Vector2.from_angle(rng.randf() * TAU)
		for j in range(4 if heavy else 3):
			p += (dir * m * 0.09).rotated(rng.randf_range(-0.7, 0.7))
			crack.append(p)
		ci.draw_polyline(crack, Color(0.02, 0.02, 0.02, 0.95), 2.0 if heavy else 1.5)
		ci.draw_polyline(crack, Color(1, 1, 1, 0.18), 0.6)
	# Tejas caidas al pie (abajo en pantalla: delante del edificio).
	for k in range(6 if heavy else 4):
		var c := Vector2(r.position.x + rng.randf_range(0.1, 0.9) * r.size.x, r.end.y + rng.randf_range(-0.02, 0.1) * m)
		var t := Vector2.from_angle(rng.randf() * TAU) * m * 0.045
		var pts := PackedVector2Array([c - t - t.orthogonal() * 0.6, c + t - t.orthogonal() * 0.6, c + t + t.orthogonal() * 0.6, c - t + t.orthogonal() * 0.6])
		_poly(ci, pts, TERRACOTTA if k % 3 != 2 else CONCRETE_DARK, OUTLINE, 1.0)
	# Una tabla suelta que asoma por un costado, torcida.
	var plank_c := Vector2(r.get_center().x + side * r.size.x * 0.5, r.position.y + r.size.y * rng.randf_range(0.55, 0.75))
	var along := Vector2(side, 0.45).normalized() * m * 0.2
	var across := along.orthogonal().normalized() * 2.2
	_poly(ci, PackedVector2Array([plank_c - along - across, plank_c + along - across, plank_c + along + across, plank_c - along + across]), LIGHT_WOOD, OUTLINE, 1.0)
	if not heavy:
		return
	# Chapa suelta, torcida, en una esquina de arriba.
	var sc := Vector2(r.get_center().x - side * r.size.x * 0.3, r.position.y + r.size.y * 0.22)
	var sa := Vector2.from_angle(side * 0.5) * m * 0.14
	var sb := sa.orthogonal() * 0.7
	_poly(ci, PackedVector2Array([sc - sa - sb, sc + sa - sb, sc + sa + sb, sc - sa + sb]), STEEL, OUTLINE, 1.0)
	ci.draw_line(sc - sa * 0.6, sc + sa * 0.6, RUST, 1.5)
	# Viga partida que cruza el tejado y sale por un lado, con ascuas en la punta.
	var b0 := r.get_center() + Vector2(-side * r.size.x * 0.1, -r.size.y * 0.08)
	var b1 := r.get_center() + Vector2(side * r.size.x * 0.62, -r.size.y * 0.3)
	ci.draw_line(b0, b1, OUTLINE, 5.0)
	ci.draw_line(b0, b1, Color(0.2, 0.13, 0.09), 3.0)
	_dot(ci, b1, 1.8, FIRE)
	# Cascotes al pie del costado.
	for k in range(3 + n):
		var c := Vector2(r.get_center().x + side * r.size.x * rng.randf_range(0.42, 0.58), r.position.y + rng.randf_range(0.4, 0.95) * r.size.y)
		var rad := rng.randf_range(2.0, 3.8)
		var pts := PackedVector2Array()
		for s in 5:
			var a := TAU * s / 5.0 + rng.randf_range(-0.3, 0.3)
			pts.append(c + Vector2(cos(a), sin(a)) * rad * rng.randf_range(0.7, 1.1))
		_poly(ci, pts, CONCRETE if k % 2 == 0 else CONCRETE_DARK.lightened(0.1), OUTLINE, 1.0)

## Disposiciones de dano distintas (la misma cuenta que la 3D, SiteMesh).
const DAMAGE_VARIANTS := 3

## El ladeo de un edificio herido en 2D: un poco de cizalla y de hundimiento
## (vista de maqueta: lo que se inclina se lee como torcido), hacia `side`.
## Leve y grave; sano, la identidad.
static func damage_lean(stage: int, size: Vector2, side: float) -> Transform2D:
	if stage < LookRule.DAMAGE_LIGHT or stage > LookRule.DAMAGE_HEAVY:
		return Transform2D.IDENTITY
	var i := stage - 1
	var tilts: Array = GameConfig.damage_tilt
	var tilt := float(tilts[clampi(i, 0, tilts.size() - 1)]) if not tilts.is_empty() else 0.0
	# Cizalla de 2 a 3 veces la inclinacion 3D: vista desde arriba se nota menos.
	var skew := tilt * 2.6 * side
	var squash := 0.03 * float(stage)
	return Transform2D(0.0, Vector2(1.0, 1.0 - squash), skew, Vector2(0.0, size.y * squash * 0.5))

## Borde de seleccion en laton.
static func draw_selection(ci: CanvasItem, size: Vector2, pulse: float) -> void:
	var r := Rect2(-size * 0.5, size).grow(1.0 + pulse * 2.0)
	ci.draw_rect(r, Color(0, 0, 0, 0.6), false, 4.0)
	ci.draw_rect(r, Color(BRASS_LIGHT, 0.75 + pulse * 0.25), false, 2.0)

# ── Obra por fases (estilo por tipo, disposicion por instancia) ───────

## Colores de obra vistos desde arriba (los de la paleta de obra 3D).
const SITE_STONE := Color8(208, 192, 166)
const SITE_STONE_DARK := Color8(160, 144, 120)
const SITE_SACK := Color8(226, 200, 150)
const SITE_SANDBAG := Color8(200, 174, 124)
const SITE_SAWDUST := Color8(238, 204, 142)
const SITE_GRAVEL := Color8(156, 146, 132)
const SITE_SOIL := Color8(112, 72, 44)
const SITE_SHEET := Color8(128, 130, 142)
const SITE_CRATE := Color8(160, 98, 54)
const SITE_LOG := Color8(134, 82, 46)
const SITE_DRUM := Color8(190, 60, 40)

## Las tres fases de obra vistas desde arriba, como en 3D
## (DieselpunkBuildingFactory.create_construction_phase): 0 valla con
## materiales, 1 solar con cimientos, 2 estructura a medio levantar. El estilo
## de `building_id` (BuildingLook.site_style: materiales, valla, lona, silueta)
## y la semilla `seed_val` (BuildingLook.site_layout: donde va cada cosa) son
## los mismos que en 3D. Se pinta EN LUGAR del edificio; `n` es la clase de
## huella. Lleva debajo la barra de progreso. Lo que se mueve (pluma de la
## grua, banderin, chispas/polvo) no se pinta aqui: son nodos animados por
## shader que pone Building2D en los puntos de site_anchors().
static func draw_construction_phase(ci: CanvasItem, size: Vector2, phase: int, progress: float, n: int = 2,
		building_id: String = "", seed_val: int = 0) -> void:
	var r := Rect2(-size * 0.5, size).grow(-INSET)
	var style := LookRule.site_style(building_id)
	var layout := LookRule.site_layout(seed_val, style, n)
	ci.draw_rect(Rect2(r.position + Vector2(3, 4), r.size), SHADOW)
	ci.draw_rect(r, SITE_DIRT)
	# Terrones: la tierra removida se lee como obra, no como cesped.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for i in range(6 * n):
		var p := r.position + r.size * Vector2(rng.randf(), rng.randf())
		_dot(ci, p, 1.4, SITE_DIRT.darkened(0.25))
	var anchors := site_anchors(size, phase, n, style, layout)
	match phase:
		0: _site_fence(ci, r, n, style, layout)
		1: _site_foundation(ci, r, n, style, layout)
		_: _site_frame(ci, r, n, style, layout, anchors)
	# El palo del banderin (la tela la mueve Building2D).
	var flag: Vector2 = anchors["flag"]
	_dot(ci, flag, 2.2, OUTLINE)
	_dot(ci, flag, 1.4, DARK_WOOD.lightened(0.2))
	ci.draw_rect(r, OUTLINE, false, 1.5)
	var bar := Rect2(Vector2(r.position.x + 3, r.end.y - 7), Vector2(r.size.x - 6, 4))
	ci.draw_rect(bar.grow(1), OUTLINE)
	ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(progress, 0.0, 1.0), bar.size.y)), HAZARD)

## Donde van las piezas animadas de una obra 2D, en px del marco SIN girar y
## centrado: "flag" (pie del banderin), "fx" (chispas/polvo, o "" si no hay),
## "fx_kind", y "crane" ({mast, jib, angle}, o {} sin grua: solo desde 2x2 y en
## la fase 2). Mismos sitios que en 3D, porque salen de la misma disposicion.
static func site_anchors(size: Vector2, phase: int, n: int, style: Dictionary, layout: Dictionary) -> Dictionary:
	var r := Rect2(-size * 0.5, size).grow(-INSET)
	var half := r.size * 0.5
	var flag := Vector2.ZERO
	match phase:
		0:
			var gn := LookRule.side_normal(int(layout["gate_side"]))
			var glen := r.size.x if gn.x == 0.0 else r.size.y
			var off := half.y if gn.x == 0.0 else half.x
			flag = gn * (off - 2.0) + Vector2(-gn.y, gn.x) * glen * 0.2 * float(layout["flag_post"])
		1:
			flag = (layout["cone_corners"][1] as Vector2) * half * 0.8
		_:
			flag = Vector2.ZERO if String(style["frame"]) == "mast" else -(layout["crane_corner"] as Vector2) * half * 0.8
	var crane := {}
	if phase == 2 and n >= 2:
		var cc: Vector2 = layout["crane_corner"]
		var yaw := atan2(-cc.y, cc.x) + (float(layout["crane_yaw"]) / TAU - 0.5) * 1.2
		crane = {"mast": cc * half * 0.84, "jib": r.size.x * 0.7, "angle": atan2(sin(yaw), -cos(yaw))}
	return {
		"flag": flag,
		"fx": (layout["fx_spot"] as Vector2) * r.size,
		"fx_kind": SiteFx.fx_for(style, phase),
		"crane": crane,
	}

## Recorre los cuatro lados: [normal, inicio, fin] en px.
static func _sides(r: Rect2) -> Array:
	var out: Array = []
	var c := r.get_center()
	for side in 4:
		var nrm := LookRule.side_normal(side)
		var along := Vector2(-nrm.y, nrm.x)
		var length := r.size.x if nrm.x == 0.0 else r.size.y
		var off := r.size.y * 0.5 if nrm.x == 0.0 else r.size.x * 0.5
		var mid := c + nrm * off
		out.append([nrm, mid - along * length * 0.5, mid + along * length * 0.5])
	return out

## Fase 0: valla (tablas, chapa o lona) con la puerta en su lado y las pilas
## del estilo donde diga la semilla, una con lona, mas el desorden.
static func _site_fence(ci: CanvasItem, r: Rect2, n: int, style: Dictionary, layout: Dictionary) -> void:
	var fence := r.grow(-2)
	var kind := String(style["fence"])
	var col := LIGHT_WOOD
	var width := 2.0
	var post_col := DARK_WOOD
	match kind:
		"dark_planks": col = DARK_WOOD.lightened(0.15)
		"sheet":
			col = SITE_SHEET
			width = 3.0
			post_col = IRON
		"canvas":
			col = style["tarp"]
			width = 3.5
	var gate := int(layout["gate_side"])
	var step := 7.0 * float(layout["post_step"]) / 0.9
	var sides := _sides(fence)
	for side in 4:
		var s: Array = sides[side]
		var a: Vector2 = s[1]
		var b: Vector2 = s[2]
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.001)
		var gap := length * 0.16
		var mid := (a + b) * 0.5
		if side == gate:
			ci.draw_line(a, mid - dir * gap, col, width)
			ci.draw_line(mid + dir * gap, b, col, width)
			ci.draw_line(mid - dir * gap, mid + dir * gap, HAZARD, 2.0)
		else:
			ci.draw_line(a, b, col, width)
		var t := 0.0
		while t <= length:
			var p := a + dir * t
			if not (side == gate and absf(t - length * 0.5) < gap):
				ci.draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), post_col)
			t += step
	var m := minf(r.size.x, r.size.y)
	var piles: Array = layout["piles"]
	for k in piles.size():
		var p: Dictionary = piles[k]
		var c: Vector2 = r.get_center() + (p["pos"] as Vector2) * r.size
		var turned := absf(float(p["yaw"])) > PI * 0.25
		var dims := Vector2(m * 0.34, m * 0.2) * float(p["scale"])
		if turned:
			dims = Vector2(dims.y, dims.x)
		_pile_2d(ci, String(p["kind"]), Rect2(c - dims * 0.5, dims), turned)
		if k == int(layout["tarp_pile"]):
			var tarp := Rect2(c - dims * 0.5 + Vector2(dims.x * 0.3, -1), Vector2(dims.x * 0.75, dims.y + 2))
			ci.draw_rect(tarp, style["tarp"])
			ci.draw_line(tarp.position, tarp.end, (style["tarp"] as Color).darkened(0.3), 1.0)
			ci.draw_rect(tarp, OUTLINE, false, 1.0)
	for c in layout["clutter"]:
		var q: Vector2 = r.get_center() + (c["pos"] as Vector2) * r.size
		match String(c["kind"]):
			"barrel": _disc(ci, q, 2.6, SITE_DRUM, OUTLINE, 1.0)
			"crate":
				ci.draw_rect(Rect2(q - Vector2(3, 3), Vector2(6, 6)), SITE_CRATE)
				ci.draw_rect(Rect2(q - Vector2(3, 3), Vector2(6, 6)), OUTLINE, false, 1.0)
			_: _cone(ci, q)

## Una pila de material vista desde arriba en `p` (`turned`: tumbada en vertical).
static func _pile_2d(ci: CanvasItem, kind: String, p: Rect2, turned: bool) -> void:
	var long_axis := Vector2(0, 1) if turned else Vector2(1, 0)
	var across := Vector2(1, 0) if turned else Vector2(0, 1)
	var long_len := p.size.y if turned else p.size.x
	var across_len := p.size.x if turned else p.size.y
	var c := p.get_center()
	match kind:
		"planks":
			ci.draw_rect(p, LIGHT_WOOD)
			for j in range(1, 4):
				var o := c + across * (across_len * (j / 4.0 - 0.5))
				ci.draw_line(o - long_axis * long_len * 0.5, o + long_axis * long_len * 0.5, DARK_WOOD, 1.0)
		"beams", "pipes":
			var count := 3 if kind == "beams" else 4
			var bar_col := STEEL if kind == "beams" else COPPER
			for j in count:
				var o := c + across * (across_len * ((j + 0.5) / count - 0.5))
				var a := o - long_axis * long_len * 0.5
				var b := o + long_axis * long_len * 0.5
				ci.draw_line(a, b, OUTLINE, across_len / count + 1.0)
				ci.draw_line(a, b, bar_col, across_len / count - 1.0)
				if kind == "pipes":
					_dot(ci, b, across_len / count * 0.35, bar_col.darkened(0.45))
			return
		"logs":
			for j in 3:
				var o := c + across * (across_len * ((j + 0.5) / 3.0 - 0.5))
				var a := o - long_axis * long_len * 0.5
				var b := o + long_axis * long_len * 0.5
				ci.draw_line(a, b, OUTLINE, across_len / 3.0 + 1.0)
				ci.draw_line(a, b, SITE_LOG, across_len / 3.0 - 1.0)
				_dot(ci, b, across_len / 6.0, LIGHT_WOOD)
			return
		"bricks":
			ci.draw_rect(p, TILE_RED)
			ci.draw_line(Vector2(c.x, p.position.y), Vector2(c.x, p.end.y), TILE_RED_DARK, 1.0)
			ci.draw_line(Vector2(p.position.x, c.y), Vector2(p.end.x, c.y), TILE_RED_DARK, 1.0)
		"sawdust", "gravel", "soil":
			var fill: Color = {"sawdust": SITE_SAWDUST, "gravel": SITE_GRAVEL}.get(kind, SITE_SOIL)
			var rad := minf(p.size.x, p.size.y) * 0.75
			_disc(ci, c, rad, fill, OUTLINE, 1.0)
			_dot(ci, c - Vector2(rad, rad) * 0.25, rad * 0.45, fill.lightened(0.15))
			if kind == "gravel":
				for j in 5:
					_dot(ci, c + Vector2(cos(j * 1.3), sin(j * 1.3)) * rad * 0.55, 0.9, fill.darkened(0.4))
			return
		"rivets":
			var box := Rect2(p.position, Vector2(p.size.x * 0.45, p.size.y))
			ci.draw_rect(box, SITE_CRATE)
			ci.draw_rect(box, OUTLINE, false, 1.0)
			for j in 3:
				_disc(ci, Vector2(p.position.x + p.size.x * (0.6 + 0.14 * j), c.y + (j - 1) * 2.0), 2.2, RUST, OUTLINE, 1.0)
			return
		"drums":
			var rad := minf(p.size.x, p.size.y) * 0.32
			for o in [Vector2(-0.28, -0.1), Vector2(0.05, 0.12), Vector2(0.32, -0.12)]:
				_disc(ci, c + o * p.size, rad, SITE_DRUM, OUTLINE, 1.0)
				_dot(ci, c + o * p.size, rad * 0.4, SITE_DRUM.lightened(0.25))
			return
		"sacks", "sandbags":
			var fill := SITE_SACK if kind == "sacks" else SITE_SANDBAG
			var per := 3 if kind == "sacks" else 4
			for row in 2:
				for j in per:
					var o := c + long_axis * long_len * ((j + 0.5) / per - 0.5) + across * across_len * (row - 0.5) * 0.5
					_disc(ci, o, minf(long_len / per, across_len * 0.5) * 0.55, fill, OUTLINE, 1.0)
			return
		"stone":
			ci.draw_rect(Rect2(p.position, p.size * Vector2(0.55, 1.0)), SITE_STONE)
			ci.draw_rect(Rect2(p.position + p.size * Vector2(0.5, 0.15), p.size * Vector2(0.5, 0.75)), SITE_STONE_DARK)
			ci.draw_rect(Rect2(p.position, p.size * Vector2(0.55, 1.0)), OUTLINE, false, 1.0)
		"crates":
			for j in 2:
				var box := Rect2(p.position + Vector2(p.size.x * 0.5 * j, 0), Vector2(p.size.x * 0.5 - 1, p.size.y))
				ci.draw_rect(box, SITE_CRATE)
				ci.draw_line(box.position, box.end, DARK_WOOD, 1.0)
				ci.draw_line(Vector2(box.end.x, box.position.y), Vector2(box.position.x, box.end.y), DARK_WOOD, 1.0)
				ci.draw_rect(box, OUTLINE, false, 1.0)
			return
		_:
			ci.draw_rect(p, CONCRETE_DARK)
	ci.draw_rect(p, OUTLINE, false, 1.0)

## Fase 1: losa (de piedra en los de piedra) con zapatas, esperas de ferralla o
## estacas, conos y lo que sobro de la primera pila.
static func _site_foundation(ci: CanvasItem, r: Rect2, n: int, style: Dictionary, layout: Dictionary) -> void:
	var stone := String(style["frame_mat"]) == "stone"
	var slab := r.grow(-r.size.x * 0.08)
	_plate(ci, slab, SITE_STONE if stone else CONCRETE.lightened(0.2), OUTLINE, 1.5)
	var wood := String(style["frame_mat"]) == "wood"
	_foundation_hint_2d(ci, slab, style, layout)
	for p in _frame_points_2d(slab.grow(-slab.size.x * 0.08), n, String(style["frame"])):
		ci.draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), SITE_STONE_DARK if stone else CONCRETE_DARK)
		if wood:
			ci.draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), DARK_WOOD)
		else:
			_dot(ci, p + Vector2(-1.5, -1.5), 1.3, RUST)
			_dot(ci, p + Vector2(1.5, 1.5), 1.3, RUST)
	var half := r.size * 0.5
	var piles: Array = layout["piles"]
	if not piles.is_empty():
		var c: Vector2 = r.get_center() + (layout["leftover_corner"] as Vector2) * half * 0.72
		var m := minf(r.size.x, r.size.y)
		var dims := Vector2(m * 0.24, m * 0.14)
		_pile_2d(ci, String(piles[0]["kind"]), Rect2(c - dims * 0.5, dims), false)
	for corner in layout["cone_corners"]:
		_cone(ci, r.get_center() + (corner as Vector2) * (half - Vector2(5, 7)))

## Lo que ya asoma en los cimientos de cada silueta (como en 3D): base de la
## chimenea, anillos, zapata de la torre, escalon, bancales, durmientes.
static func _foundation_hint_2d(ci: CanvasItem, slab: Rect2, style: Dictionary, layout: Dictionary) -> void:
	var c := slab.get_center()
	var cc: Vector2 = layout["crane_corner"]
	var m := minf(slab.size.x, slab.size.y)
	match String(style["frame"]):
		"chimney":
			_disc(ci, c - cc * slab.size * 0.26, m * 0.19, TILE_RED, OUTLINE, 1.0)
		"tanks":
			for side in [-1.0, 1.0]:
				_disc(ci, c + Vector2(side * slab.size.x * 0.24, 0), m * 0.2, CONCRETE_DARK, OUTLINE, 1.0)
		"dome", "basin":
			ci.draw_arc(c, m * 0.4, 0.0, TAU, 28, OUTLINE, 5.0)
			ci.draw_arc(c, m * 0.4, 0.0, TAU, 28, SITE_STONE_DARK if style["frame_mat"] == "stone" else CONCRETE_DARK, 3.5)
		"tower":
			var pad := Rect2(c - slab.size * 0.3, slab.size * 0.6)
			ci.draw_rect(pad, CONCRETE_DARK)
			ci.draw_rect(pad, OUTLINE, false, 1.0)
		"plinth":
			var step := Rect2(c - slab.size * 0.4, slab.size * 0.8)
			ci.draw_rect(step, SITE_STONE.darkened(0.08))
			ci.draw_rect(step, OUTLINE, false, 1.0)
		"low":
			for zs in [-1.0, 1.0]:
				var bed := Rect2(Vector2(c.x - slab.size.x * 0.3, c.y + zs * slab.size.y * 0.18 - 4), Vector2(slab.size.x * 0.6, 8))
				ci.draw_rect(bed, SITE_SOIL)
				ci.draw_rect(bed, OUTLINE, false, 1.0)
		"headframe":
			for zs in [-1.0, 1.0]:
				for xs in [-1.0, 1.0]:
					var p := c + Vector2(xs * slab.size.x * 0.35, zs * slab.size.y * 0.18)
					ci.draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), CONCRETE_DARK)
					ci.draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), OUTLINE, false, 1.0)
		"gable", "hall":
			var sill := slab.grow(-slab.size.x * 0.08)
			ci.draw_rect(sill, OUTLINE, false, 4.0)
			ci.draw_rect(sill, DARK_WOOD.lightened(0.2) if style["frame_mat"] == "wood" else GUNMETAL, false, 2.5)
		"mast":
			_disc(ci, c, 5.0, CONCRETE_DARK, OUTLINE, 1.0)

## Fase 2: losa, la silueta del edificio, andamio en su lado y el mastil de la
## grua (la pluma la anima Building2D).
static func _site_frame(ci: CanvasItem, r: Rect2, n: int, style: Dictionary, layout: Dictionary, anchors: Dictionary) -> void:
	var slab := r.grow(-r.size.x * 0.08)
	var stone := String(style["frame_mat"]) == "stone"
	_plate(ci, slab, SITE_STONE if stone else CONCRETE.lightened(0.2), OUTLINE, 1.5)
	var mat_col: Color = {"wood": WOOD, "stone": SITE_STONE_DARK}.get(String(style["frame_mat"]), GUNMETAL)
	var inner := slab.grow(-slab.size.x * 0.08)
	var c := slab.get_center()
	var cc: Vector2 = layout["crane_corner"]
	match String(style["frame"]):
		"chimney":
			_site_box(ci, slab, inner, n, mat_col)
			var ch := c - cc * slab.size * 0.26
			var rad := minf(slab.size.x, slab.size.y) * 0.17
			_disc(ci, ch, rad, TILE_RED, OUTLINE, 1.5)
			ci.draw_arc(ch, rad * 0.8, 0.0, TAU, 16, GUNMETAL, 1.5)
			_disc(ci, ch, rad * 0.5, OIL_BLACK, OUTLINE, 1.0)
		"gable", "hall":
			for p in _site_points(inner, n):
				_pillar_2d(ci, p, mat_col)
			var count := n + 2
			for i in count:
				var x := lerpf(inner.position.x, inner.end.x, float(i) / float(count - 1))
				ci.draw_line(Vector2(x, slab.position.y + 2), Vector2(x, slab.end.y - 2), OUTLINE, 3.0)
				ci.draw_line(Vector2(x, slab.position.y + 2), Vector2(x, slab.end.y - 2), mat_col.lightened(0.15), 1.6)
			if String(style["frame"]) == "gable":
				# Medio faldon ya entablado: el tejado a dos aguas que viene.
				var plank := Rect2(Vector2(inner.position.x, slab.position.y + 2), Vector2(inner.size.x * 0.55, c.y - slab.position.y - 2))
				ci.draw_rect(plank, LIGHT_WOOD)
				for j in range(1, 5):
					var y := plank.position.y + plank.size.y * j / 5.0
					ci.draw_line(Vector2(plank.position.x, y), Vector2(plank.end.x, y), DARK_WOOD, 1.0)
				ci.draw_rect(plank, OUTLINE, false, 1.0)
			else:
				# Cerchas en aspa de nave.
				for i in count - 1:
					var x0 := lerpf(inner.position.x, inner.end.x, float(i) / float(count - 1))
					var x1 := lerpf(inner.position.x, inner.end.x, float(i + 1) / float(count - 1))
					ci.draw_line(Vector2(x0, inner.position.y), Vector2(x1, inner.end.y), mat_col, 1.2)
					ci.draw_line(Vector2(x1, inner.position.y), Vector2(x0, inner.end.y), mat_col, 1.2)
			ci.draw_line(Vector2(slab.position.x + 2, c.y), Vector2(slab.end.x - 2, c.y), OUTLINE, 4.0)
			ci.draw_line(Vector2(slab.position.x + 2, c.y), Vector2(slab.end.x - 2, c.y), mat_col.lightened(0.3), 2.4)
		"tower":
			var outer := Rect2(c - slab.size * 0.3, slab.size * 0.6)
			var top := Rect2(c - slab.size * 0.18, slab.size * 0.36)
			ci.draw_rect(top, mat_col.darkened(0.1))
			for k in 4:
				var a: Vector2 = c + (LookRule.CORNERS[k] as Vector2) * slab.size * 0.3
				var b: Vector2 = c + (LookRule.CORNERS[k] as Vector2) * slab.size * 0.18
				var a2: Vector2 = c + (LookRule.CORNERS[(k + 1) % 4] as Vector2) * slab.size * 0.18
				ci.draw_line(a, b, mat_col, 3.0)
				ci.draw_line(a, a2, mat_col.lightened(0.2), 1.2)
			ci.draw_rect(outer, mat_col, false, 2.0)
			ci.draw_rect(top, OUTLINE, false, 1.0)
		"tanks":
			var rad := minf(slab.size.x, slab.size.y) * 0.2
			for side in [-1.0, 1.0]:
				var tc := c + Vector2(side * slab.size.x * 0.24, 0)
				if side > 0.0:
					_disc(ci, tc, rad, SITE_SHEET, OUTLINE, 1.0)
				ci.draw_arc(tc, rad, 0.0, TAU, 20, OUTLINE, 3.0)
				ci.draw_arc(tc, rad, 0.0, TAU, 20, mat_col.lightened(0.2), 1.8)
				for k in 6:
					_dot(ci, tc + Vector2.from_angle(TAU * k / 6.0) * rad, 1.6, mat_col)
			ci.draw_line(c + Vector2(-slab.size.x * 0.24, slab.size.y * 0.12), c + Vector2(slab.size.x * 0.24, slab.size.y * 0.12), COPPER, 2.5)
		"dome":
			var rad := minf(slab.size.x, slab.size.y) * 0.4
			for p in _frame_points_2d(inner, n, "dome"):
				_pillar_2d(ci, p, mat_col)
			ci.draw_arc(c, rad, 0.0, TAU, 28, OUTLINE, 3.5)
			ci.draw_arc(c, rad, 0.0, TAU, 28, mat_col.lightened(0.2), 2.0)
			for k in 6:
				var tip := c + Vector2.from_angle(TAU * k / 6.0) * rad
				ci.draw_line(tip, c, mat_col.lightened(0.1), 1.6)
			_disc(ci, c, 3.0, mat_col, OUTLINE, 1.0)
		"plinth":
			for i in 3:
				var s := 0.8 - 0.18 * i
				var step := Rect2(c - slab.size * s * 0.5, slab.size * s)
				ci.draw_rect(step, SITE_STONE if i % 2 == 0 else SITE_STONE_DARK)
				ci.draw_rect(step, OUTLINE, false, 1.0)
			var fig := Rect2(c - Vector2(5, 5), Vector2(10, 10))
			ci.draw_rect(fig, style["tarp"])
			ci.draw_rect(fig, OUTLINE, false, 1.0)
			for k in 4:
				_dot(ci, c + (LookRule.CORNERS[k] as Vector2) * slab.size * 0.3, 1.8, DARK_WOOD)
		"basin":
			var count := 10 + 2 * n
			for k in count:
				if k % 5 == 4:
					continue
				var p := c + Vector2.from_angle(TAU * k / count) * slab.size * 0.38
				ci.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), SITE_STONE)
				ci.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), OUTLINE, false, 1.0)
			for k in 3:
				ci.draw_line(c + Vector2.from_angle(TAU * k / 3.0 + 0.3) * slab.size * 0.32, c, DARK_WOOD, 1.6)
			_disc(ci, c, 2.5, COPPER, OUTLINE, 1.0)
		"headframe":
			for p in _site_points(inner, 1):
				_pillar_2d(ci, p, mat_col)
			for zs in [-1.0, 1.0]:
				for xs in [-1.0, 1.0]:
					ci.draw_line(c + Vector2(xs * slab.size.x * 0.35, zs * slab.size.y * 0.18), c + Vector2(0, zs * slab.size.y * 0.1), mat_col, 2.4)
			ci.draw_line(c + Vector2(-5, 0), c + Vector2(5, 0), OUTLINE, 4.0)
			ci.draw_arc(c, 4.0, 0.0, TAU, 12, STEEL, 1.5)
		"low":
			for zs in [-1.0, 1.0]:
				var bed := Rect2(Vector2(c.x - slab.size.x * 0.3, c.y + zs * slab.size.y * 0.18 - 4), Vector2(slab.size.x * 0.6, 8))
				ci.draw_rect(bed, SITE_SOIL)
				ci.draw_rect(bed, OUTLINE, false, 1.0)
			for i in 4:
				var x := lerpf(c.x - slab.size.x * 0.32, c.x + slab.size.x * 0.32, float(i) / 3.0)
				ci.draw_line(Vector2(x, c.y - slab.size.y * 0.32), Vector2(x, c.y + slab.size.y * 0.32), mat_col, 1.4)
			for k in 4:
				_pillar_2d(ci, c + (LookRule.CORNERS[k] as Vector2) * slab.size * 0.32, mat_col)
		"mast":
			_site_box(ci, slab, inner, n, mat_col)
			_disc(ci, c, 3.0, STEEL, OUTLINE, 1.0)
		_:
			_site_box(ci, slab, inner, n, mat_col)
	# Andamio: tablones en el lado de la semilla.
	var side: Array = _sides(slab.grow(-4))[int(layout["scaffold_side"])]
	var a: Vector2 = side[1]
	var b: Vector2 = side[2]
	ci.draw_line(a, b, OUTLINE, 6.0)
	ci.draw_line(a, b, LIGHT_WOOD, 4.0)
	var crane: Dictionary = anchors["crane"]
	if not crane.is_empty():
		var mast: Vector2 = crane["mast"]
		var col: Color = style["crane"]
		ci.draw_rect(Rect2(mast - Vector2(4, 4), Vector2(8, 8)), col)
		ci.draw_rect(Rect2(mast - Vector2(4, 4), Vector2(8, 8)), OUTLINE, false, 1.0)

## La estructura de caja: medio forjado arriba, vigas de borde y pilares.
static func _site_box(ci: CanvasItem, slab: Rect2, inner: Rect2, n: int, mat_col: Color) -> void:
	var deck := Rect2(slab.position, Vector2(slab.size.x, slab.size.y * 0.48))
	ci.draw_rect(deck, CONCRETE)
	ci.draw_rect(deck, OUTLINE, false, 1.0)
	ci.draw_rect(slab.grow(-2), mat_col, false, 3.0)
	for p in _site_points(inner, n):
		_pillar_2d(ci, p, mat_col)

static func _pillar_2d(ci: CanvasItem, p: Vector2, col: Color) -> void:
	ci.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), col.lightened(0.15))
	ci.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), OUTLINE, false, 1.0)

## Puntos de pilar: esquinas para la clase 1, rejilla 3x3 para la 2, 4x4 la 3.
static func _site_points(r: Rect2, n: int) -> Array:
	var per := clampi(n, 1, 3) + 1
	var pts: Array = []
	for i in per:
		for j in per:
			pts.append(r.position + r.size * Vector2(float(i) / float(per - 1), float(j) / float(per - 1)))
	return pts

## Como en 3D: rejilla, o anillo para las siluetas redondas.
static func _frame_points_2d(r: Rect2, n: int, shape: String) -> Array:
	if shape in ["dome", "basin", "tanks"]:
		var pts: Array = []
		var count := 4 + 2 * n
		for k in count:
			pts.append(r.get_center() + Vector2.from_angle(TAU * k / count) * r.size * 0.48)
		return pts
	return _site_points(r, n)

static func _cone(ci: CanvasItem, c: Vector2) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3), c + Vector2(3, 3), c + Vector2(-3, 3)]), Color8(240, 120, 40))
	ci.draw_line(c + Vector2(-2, 1), c + Vector2(2, 1), Color(1, 1, 1, 0.9), 1.0)

# ── Ruina ─────────────────────────────────────────────────────────────

## Ruina: encima del dibujo del edificio, tizne, un muro roto, cascotes y vigas
## carbonizadas con ascuas. Mucho mas oscura y quebrada que un edificio tocado,
## para que se distinga desde lejos. Determinista por `seed_val`.
static func draw_ruin(ci: CanvasItem, size: Vector2, seed_val: int, n: int = 2) -> void:
	var r := Rect2(-size * 0.5, size).grow(-INSET)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	ci.draw_rect(r, Color(0.06, 0.05, 0.04, 0.72))
	# Manchas de hollin que se salen un poco de la huella
	for k in range(3 + n):
		var p := r.position + Vector2(rng.randf() * r.size.x, rng.randf() * r.size.y)
		_dot(ci, p, rng.randf_range(5.0, 9.0) * (0.8 + 0.2 * n), Color(0.02, 0.02, 0.02, 0.55))
	# Muro roto: borde superior dentado
	var wall := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y)])
	var x := r.end.x
	var steps := 5 + n
	for i in steps + 1:
		x = r.end.x - r.size.x * float(i) / float(steps)
		wall.append(Vector2(x, r.position.y + rng.randf_range(3.0, 10.0)))
	ci.draw_colored_polygon(wall, CONCRETE_DARK)
	ci.draw_polyline(wall, OUTLINE, 1.5)
	# Cascotes
	for k in range(6 + 3 * n):
		var c := r.position + Vector2(rng.randf_range(0.1, 0.9) * r.size.x, rng.randf_range(0.2, 0.9) * r.size.y)
		var rad := rng.randf_range(2.0, 4.5)
		var pts := PackedVector2Array()
		for s in 5:
			var a := TAU * s / 5.0 + rng.randf_range(-0.3, 0.3)
			pts.append(c + Vector2(cos(a), sin(a)) * rad * rng.randf_range(0.7, 1.1))
		_poly(ci, pts, CONCRETE if k % 2 == 0 else CONCRETE_DARK.lightened(0.1), OUTLINE, 1.0)
	# Vigas carbonizadas cruzadas, con ascuas en la punta
	for k in range(2 + n):
		var a0 := r.position + Vector2(rng.randf_range(0.1, 0.9) * r.size.x, rng.randf_range(0.3, 0.9) * r.size.y)
		var dir := Vector2.from_angle(rng.randf() * TAU) * minf(r.size.x, r.size.y) * rng.randf_range(0.35, 0.55)
		ci.draw_line(a0, a0 + dir, OUTLINE, 5.0)
		ci.draw_line(a0, a0 + dir, Color(0.16, 0.11, 0.08), 3.0)
		_dot(ci, a0 + dir, 1.6, FIRE)
	# Grietas
	for k in range(3):
		var p := r.position + Vector2(rng.randf() * r.size.x, rng.randf() * r.size.y)
		var crack := PackedVector2Array([p])
		for j in range(4):
			p += Vector2(rng.randf_range(-7, 7), rng.randf_range(-7, 7))
			crack.append(p)
		ci.draw_polyline(crack, Color(0.02, 0.02, 0.02), 1.5)

# ── Actividad ─────────────────────────────────────────────────────────

## Donde sale el humo (o la luz) de cada edificio, en fracciones de su huella
## SIN girar: las chimeneas y bocas del propio dibujo de arriba.
static func fx_anchors(id: String) -> Array:
	match id:
		"foundry": return [Vector2(0.22, 0.3), Vector2(0.76, 0.06)]
		"refinery": return [Vector2(0.74, 0.2)]
		"gold_mine": return [Vector2(0.5, 0.44)]
		"sawmill": return [Vector2(0.5, 0.63)]
		"barracks": return [Vector2(0.24, 0.3)]
		"tower": return [Vector2(0.28, 0.72)]
		"warehouse": return [Vector2(0.5, 0.85)]
		"laboratory": return [Vector2(0.5, 0.4)]
		# La chimenea de la caldera izquierda (la "fx" de la receta 3D).
		"nucleo": return [Vector2(0.16, 0.04)]
		# Edificios utiles de la 1.1: chimenea de la Taberna, banco de la
		# Carpinteria, fanal del Faro, boca de carga del Deposito.
		"tavern": return [Vector2(0.24, 0.12)]
		"carpentry": return [Vector2(0.4, 0.4)]
		"lighthouse": return [Vector2(0.42, 0.1)]
		"fuel_depot": return [Vector2(0.84, 0.82)]
		# Muelle de pesca: la chimenea del ahumadero.
		"fishing_dock": return [Vector2(0.2, 0.08)]
	return [Vector2(0.5, 0.45)]

# ── Parcela y atrezo (docs/03, "Parcela y atrezo") ────────────────────

const LOT_CHAR := Color8(38, 28, 24)
const LOT_BORDER := Color(0.2, 0.13, 0.09, 0.85)

## El suelo de la parcela, su borde oscuro y el remate de los lados sin
## calzada, para un plan de LotPlan. `size`: la huella SIN girar (px). Va
## debajo del edificio.
static func draw_lot_ground(ci: CanvasItem, plan: Dictionary, size: Vector2) -> void:
	if plan.is_empty():
		return
	var lot := Rect2(-size * 0.5, size)
	var cell := size.x / maxf(1.0, (plan["lot"] as Vector2).x)
	var state := String(plan["state"])
	var kind := String(plan["ground"])
	var base := _ground_color(kind)
	if state == "ruin":
		base = base.lerp(LOT_CHAR, 0.45)
	ci.draw_rect(lot, base)
	_ground_pattern(ci, lot, kind, cell, base)
	for run in plan["trim_runs"]:
		_trim_2d(ci, String(plan["trim"]), run, cell, _accent_of(plan))
	ci.draw_rect(lot.grow(-0.75), LOT_BORDER, false, 1.5)

## Sombra de contacto bajo el edificio: una mancha oscura que lo ancla al suelo
## y un filo mas oscuro donde lo toca (el borde que lo separa del fondo).
static func draw_lot_shadow(ci: CanvasItem, model_px: Rect2) -> void:
	# Solo la oclusion de contacto: la sombra proyectada y el contorno van en el
	# propio dibujo del edificio (horneado), con la luz siempre de arriba-izquierda.
	ci.draw_rect(model_px.grow(2.0), Color(SHADOW, 0.12))

## El atrezo del patio. Va encima del edificio (no se tocan: el plan lo deja
## en el patio) y, en ruina, encima de los escombros.
static func draw_lot_props(ci: CanvasItem, plan: Dictionary, size: Vector2) -> void:
	if plan.is_empty():
		return
	var cell := size.x / maxf(1.0, (plan["lot"] as Vector2).x)
	var accent: Color = _accent_of(plan)
	for p in plan["props"]:
		var c: Vector2 = (p["pos"] as Vector2) * cell
		var rad := float(p["radius"]) * cell
		draw_lot_prop(ci, String(p["kind"]), c, rad, float(p["rot"]), accent,
			bool(p.get("toppled", false)), bool(p.get("snapped", false)), bool(p.get("burnt", false)))
	draw_lot_signature(ci, plan, size)

## El suelo de la parcela, en la paleta: tierra batida (WOOD claro), chapa
## (SLATE claro), cesped segado (GREEN claro) y losas (STONE/CREAM).
static func _ground_color(kind: String) -> Color:
	match kind:
		"dirt": return Color8(190, 138, 88)
		"plate": return Color8(136, 138, 148)
		"grass": return Color8(130, 190, 76)
	return Color8(214, 198, 170)

static func _ground_pattern(ci: CanvasItem, lot: Rect2, kind: String, cell: float, base: Color) -> void:
	match kind:
		"slabs", "plate":
			var step := cell * 0.5
			var line := base.darkened(0.35) if kind == "slabs" else base.darkened(0.45)
			var x := lot.position.x + step
			while x < lot.end.x - 1.0:
				ci.draw_line(Vector2(x, lot.position.y), Vector2(x, lot.end.y), line, 1.0)
				x += step
			var y := lot.position.y + step
			while y < lot.end.y - 1.0:
				ci.draw_line(Vector2(lot.position.x, y), Vector2(lot.end.x, y), line, 1.0)
				y += step
			if kind == "plate":
				var yy := lot.position.y + step * 0.15
				while yy < lot.end.y:
					var xx := lot.position.x + step * 0.15
					while xx < lot.end.x:
						_dot(ci, Vector2(xx, yy), 0.9, BRASS.darkened(0.1))
						xx += step * 0.7
					yy += step * 0.7
		"dirt":
			for i in int(lot.size.x * lot.size.y / 90.0):
				var p := lot.position + lot.size * Vector2(fposmod(i * 0.381, 1.0), fposmod(i * 0.617 + 0.21, 1.0))
				_dot(ci, p, 1.1, base.darkened(0.22) if i % 3 else base.lightened(0.18))
		"grass":
			for i in int(lot.size.x * lot.size.y / 70.0):
				var p := lot.position + lot.size * Vector2(fposmod(i * 0.437, 1.0), fposmod(i * 0.719 + 0.07, 1.0))
				ci.draw_line(p, p + Vector2(0.6, -2.2), base.lightened(0.18) if i % 2 else base.darkened(0.2), 1.0)

static func _trim_2d(ci: CanvasItem, trim: String, run: Dictionary, cell: float, accent: Color) -> void:
	var a: Vector2 = (run["a"] as Vector2) * cell
	var b: Vector2 = (run["b"] as Vector2) * cell
	var broken := int(run.get("broken", 0))
	var segs := maxi(2, int(a.distance_to(b) / (cell * 0.25)))
	var w := cell * 0.06
	for i in segs:
		if broken != 0 and (broken >> (i % 30)) & 1 == 1 and (broken >> ((i + 7) % 30)) & 1 == 1:
			continue
		var p0 := a.lerp(b, float(i) / float(segs))
		var p1 := a.lerp(b, float(i + 1) / float(segs))
		var dim := 0.55 if broken != 0 else 0.0
		match trim:
			"fence":
				ci.draw_line(p0, p1, LIGHT_WOOD.lerp(LOT_CHAR, dim), maxf(1.5, w))
				ci.draw_rect(Rect2(p0 - Vector2(1.5, 1.5), Vector2(3, 3)), DARK_WOOD)
			"rail":
				ci.draw_line(p0, p1, IRON.lightened(0.15).lerp(LOT_CHAR, dim), maxf(1.5, w * 0.8))
				_dot(ci, p0, 1.6, IRON)
			"sandbags":
				var mid := (p0 + p1) * 0.5
				var sack := CREAM.darkened(0.16).lerp(LOT_CHAR, dim)
				_dot(ci, mid, maxf(2.0, w * 1.1), sack.darkened(0.25))
				_dot(ci, mid - Vector2(0.4, 0.4), maxf(1.6, w * 0.9), sack)
			"pipes":
				ci.draw_line(p0, p1, COPPER.darkened(0.25).lerp(LOT_CHAR, dim), maxf(2.5, w * 1.2))
				ci.draw_line(p0, p1, COPPER.lerp(LOT_CHAR, dim), maxf(1.2, w * 0.6))
				if i % 3 == 1:
					_disc(ci, (p0 + p1) * 0.5, maxf(2.0, w), accent, OUTLINE, 1.0)
			_:
				ci.draw_line(p0, p1, (Color8(226, 210, 178) if i % 2 == 0 else Color8(200, 184, 154)).lerp(LOT_CHAR, dim), maxf(2.0, w * 1.4))

## Una pieza de atrezo vista desde arriba, en `c` con radio `rad` (px). Volcada:
## tumbada a lo largo de su lado; partida: un munon; quemada: hacia el carbon.
static func draw_lot_prop(ci: CanvasItem, kind: String, c: Vector2, rad: float, rot: float, accent: Color, toppled := false, snapped := false, burnt := false) -> void:
	var dim := 0.6 if burnt else 0.0
	var col := _prop_color(kind, accent).lerp(LOT_CHAR, dim)
	_dot(ci, c + Vector2(1.2, 1.6), rad, Color(0, 0, 0, 0.25))
	if snapped:
		_disc(ci, c, rad * 0.45, col, OUTLINE, 1.0)
		ci.draw_line(c, c + Vector2.from_angle(rot) * rad * 1.4, col.darkened(0.2), 2.0)
		return
	if toppled:
		var d := Vector2.from_angle(rot)
		ci.draw_line(c - d * rad * 1.1, c + d * rad * 1.1, OUTLINE, rad * 1.2)
		ci.draw_line(c - d * rad * 1.0, c + d * rad * 1.0, col, rad * 0.9)
		return
	match kind:
		"barrel", "drums":
			var n := 2 if kind == "drums" else 1
			for k in n:
				var o := Vector2.from_angle(rot) * rad * (0.5 if n == 2 else 0.0) * (1.0 if k == 0 else -1.0)
				var cc := (accent if (kind == "drums" and k == 0) else col).lerp(LOT_CHAR, dim)
				_disc(ci, c + o, rad * (0.55 if n == 2 else 0.8), cc, OUTLINE, 1.0)
				ci.draw_arc(c + o, rad * (0.35 if n == 2 else 0.5), 0.0, TAU, 10, cc.darkened(0.3), 1.0)
		"crate", "ammo", "goods", "pallet":
			_rot_rect(ci, c, Vector2(rad * 1.5, rad * 1.5), rot, col)
			if kind == "ammo":
				_rot_rect(ci, c, Vector2(rad * 1.5, rad * 0.35), rot, accent.lerp(LOT_CHAR, dim), false)
			elif kind == "goods":
				for k in 3:
					_dot(ci, c + Vector2.from_angle(rot) * rad * (k - 1) * 0.45, rad * 0.28, [RED, BRASS, GREEN][k].lerp(LOT_CHAR, dim))
			elif kind == "pallet":
				_rot_rect(ci, c, Vector2(rad * 1.2, rad * 1.2), rot, Color8(200, 184, 154).lerp(LOT_CHAR, dim))
			else:
				var d := Vector2.from_angle(rot) * rad * 0.7
				var e := Vector2.from_angle(rot + PI * 0.5) * rad * 0.7
				ci.draw_line(c - d - e, c + d + e, DARK_WOOD, 1.0)
				ci.draw_line(c - d + e, c + d - e, DARK_WOOD, 1.0)
		"logs", "planks":
			var d := Vector2.from_angle(rot)
			var e := Vector2.from_angle(rot + PI * 0.5)
			for k in 3:
				var o := e * rad * (k - 1) * 0.6
				ci.draw_line(c + o - d * rad, c + o + d * rad, OUTLINE, rad * 0.62)
				ci.draw_line(c + o - d * rad * 0.95, c + o + d * rad * 0.95, col if k % 2 == 0 else col.lightened(0.12), rad * 0.45)
				if kind == "logs":
					_dot(ci, c + o + d * rad, rad * 0.24, LIGHT_WOOD.lerp(LOT_CHAR, dim))
		"sacks", "ore", "coal":
			for k in 3:
				var o := Vector2.from_angle(rot + TAU * k / 3.0) * rad * 0.4
				_disc(ci, c + o, rad * 0.5, col if k != 1 else col.lightened(0.1), OUTLINE, 1.0)
			if kind == "ore":
				for k in 3:
					_dot(ci, c + Vector2.from_angle(rot + 1.0 + TAU * k / 3.0) * rad * 0.35, rad * 0.18, BRASS_LIGHT.lerp(LOT_CHAR, dim))
		"cart":
			_rot_rect(ci, c, Vector2(rad * 1.8, rad * 0.9), rot, IRON, false)
			_rot_rect(ci, c, Vector2(rad * 1.2, rad * 1.0), rot, RUST.lerp(LOT_CHAR, dim))
			_dot(ci, c, rad * 0.3, BRASS_LIGHT.lerp(LOT_CHAR, dim))
		"ingots":
			var d := Vector2.from_angle(rot + PI * 0.5)
			for k in 3:
				_rot_rect(ci, c + d * rad * (k - 1) * 0.45, Vector2(rad * 1.5, rad * 0.35), rot, (BRASS if k == 1 else STEEL).lerp(LOT_CHAR, dim))
		"lamp":
			if not burnt:
				_dot(ci, c, rad * 1.5, Color(GLOW, 0.28))
			_disc(ci, c, rad * 0.45, IRON, OUTLINE, 1.0)
			_dot(ci, c, rad * 0.25, GLOW.lerp(LOT_CHAR, dim))
		"bench":
			_rot_rect(ci, c, Vector2(rad * 2.0, rad * 0.7), rot, col)
		"planter":
			_rot_rect(ci, c, Vector2(rad * 1.3, rad * 1.3), rot, TERRACOTTA.lerp(LOT_CHAR, dim))
			_disc(ci, c, rad * 0.55, LEAF.lerp(LOT_CHAR, dim), LEAF_DARK, 1.0)
			_dot(ci, c + Vector2(rad * 0.2, -rad * 0.15), rad * 0.15, RED.lerp(LOT_CHAR, dim))
		"gas":
			var d := Vector2.from_angle(rot)
			for k in 3:
				_disc(ci, c + d * rad * (k - 1) * 0.6, rad * 0.3, (OLIVE if k != 1 else SKY).lerp(LOT_CHAR, dim), OUTLINE, 1.0)
		"dummy":
			_disc(ci, c, rad * 0.45, CREAM.darkened(0.12).lerp(LOT_CHAR, dim), OUTLINE, 1.0)
			var d := Vector2.from_angle(rot) * rad * 0.85
			ci.draw_line(c - d, c + d, DARK_WOOD, 2.0)
		"target":
			_disc(ci, c, rad * 0.9, CREAM.lerp(LOT_CHAR, dim), OUTLINE, 1.0)
			_dot(ci, c, rad * 0.62, RED.lerp(LOT_CHAR, dim))
			_dot(ci, c, rad * 0.35, CREAM.lerp(LOT_CHAR, dim))
			_dot(ci, c, rad * 0.15, accent.lerp(LOT_CHAR, dim))
		"flag":
			_dot(ci, c, rad * 0.3, IRON)
			var tip := c + Vector2.from_angle(rot) * rad * 1.3
			ci.draw_colored_polygon(PackedVector2Array([c, tip + Vector2(0, -rad * 0.3), tip + Vector2(0, rad * 0.5)]), accent.lerp(LOT_CHAR, dim))
		"clothesline":
			var d := Vector2.from_angle(rot) * rad
			ci.draw_line(c - d, c + d, CREAM.darkened(0.1), 1.0)
			for k in 3:
				_rot_rect(ci, c + d * (k - 1) * 0.6, Vector2(rad * 0.4, rad * 0.25), rot, [CREAM, accent, SKY][k].lerp(LOT_CHAR, dim))
		"valve":
			_disc(ci, c, rad * 0.55, accent.lerp(LOT_CHAR, dim), OUTLINE, 1.0)
			ci.draw_line(c - Vector2(rad * 0.5, 0), c + Vector2(rad * 0.5, 0), COPPER, 1.5)
			ci.draw_line(c - Vector2(0, rad * 0.5), c + Vector2(0, rad * 0.5), COPPER, 1.5)
		"stake":
			_dot(ci, c, rad * 0.22, LIGHT_WOOD)
			ci.draw_colored_polygon(PackedVector2Array([c, c + Vector2(rad * 0.7, -rad * 0.2), c + Vector2(0, -rad * 0.45)]), Color8(240, 120, 40))
		_:
			_disc(ci, c, rad * 0.7, col, OUTLINE, 1.0)

## El elemento exagerado visto desde arriba (la chimenea, la grua, la antena,
## el emblema...), en su esquina del patio: el mismo que en 3D (BuildingLot).
static func draw_lot_signature(ci: CanvasItem, plan: Dictionary, size: Vector2) -> void:
	var sig: Dictionary = plan.get("signature", {})
	if sig.is_empty():
		return
	var corners: Array = sig.get("corners", [])
	var cell := size.x / maxf(1.0, (plan["lot"] as Vector2).x)
	if bool(sig.get("on_roof", false)):
		# El emblema del Cuartel General ya va en su propio dibujo (torreon).
		return
	if corners.is_empty():
		return
	var yard := float(plan["yard"])
	var fp: Vector2i = plan["footprint"]
	var sgn: Vector2 = corners[0]
	var c: Vector2 = LotPlanRef.corner_center(fp, yard, sgn) * cell
	var r := yard * cell * 0.45
	var mr: Rect2 = plan["model"]
	var model := Rect2(mr.position * cell, mr.size * cell)
	var ruined := bool(sig.get("ruined", false))
	var dim := 0.65 if ruined else 0.0
	var accent: Color = _accent_of(plan)
	match String(sig["kind"]):
		"chimney":
			_dot(ci, c + Vector2(3, 4), r * 1.05, Color(0, 0, 0, 0.3))
			_disc(ci, c, r, TILE_RED.lerp(LOT_CHAR, dim), OUTLINE, 1.5)
			if not ruined:
				ci.draw_arc(c, r * 0.78, 0.0, TAU, 14, accent, 2.0)
				_dot(ci, c, r * 0.55, OIL_BLACK)
				_dot(ci, c, r * 0.3, FIRE)
		"crane":
			var yellow := BRASS.lerp(LOT_CHAR, dim)
			var tip := Vector2(model.get_center().x, model.end.y + yard * cell * 0.5)
			if not ruined:
				ci.draw_line(c + Vector2(4, 5), tip + Vector2(4, 5), Color(0, 0, 0, 0.3), 4.0)
				ci.draw_line(c, tip, OUTLINE, 4.5)
				ci.draw_line(c, tip, yellow, 2.5)
				var back := c + (c - tip).normalized() * cell * 0.25
				ci.draw_line(c, back, OUTLINE, 4.0)
				ci.draw_line(c, back, yellow, 2.2)
				ci.draw_rect(Rect2(back - Vector2(3, 3), Vector2(6, 6)), CONCRETE_DARK)
				_rot_rect(ci, tip, Vector2(r * 1.3, r * 1.3), 0.0, WOOD)
			ci.draw_rect(Rect2(c - Vector2(r * 0.6, r * 0.6), Vector2(r * 1.2, r * 1.2)), yellow)
			ci.draw_rect(Rect2(c - Vector2(r * 0.6, r * 0.6), Vector2(r * 1.2, r * 1.2)), OUTLINE, false, 1.5)
		"antenna":
			var pts := PackedVector2Array()
			for i in 3:
				pts.append(c + Vector2.from_angle(TAU * i / 3.0 + 0.3) * r)
			ci.draw_colored_polygon(pts, Color(0, 0, 0, 0.2))
			for i in 3:
				ci.draw_line(pts[i], pts[(i + 1) % 3], COPPER.lerp(LOT_CHAR, dim), 1.5)
				ci.draw_line(pts[i], c, IRON, 1.5)
			if not ruined:
				_dot(ci, c, r * 0.9, Color(SKY.lightened(0.35), 0.3))
				_dot(ci, c, r * 0.35, SKY.lightened(0.3))
		"flag":
			ci.draw_rect(Rect2(c - Vector2(r * 0.5, r * 0.5), Vector2(r, r)), STONE.lerp(LOT_CHAR, dim))
			_dot(ci, c, 2.0, IRON)
			if not ruined:
				var d := -1.0 if sgn.x > 0 else 1.0
				var f := PackedVector2Array([c, c + Vector2(d * cell * 0.62, -r * 0.4), c + Vector2(d * cell * 0.62, r * 0.9), c + Vector2(0, r * 0.6)])
				_poly(ci, f, accent, OUTLINE, 1.0)
				ci.draw_line(c + Vector2(0, r * 0.15), c + Vector2(d * cell * 0.62, r * 0.25), OUTLINE, 2.0)
		"manifold":
			var to := Vector2(model.end.x if sgn.x > 0 else model.position.x, c.y - r * 0.5)
			if not ruined:
				ci.draw_line(c - Vector2(0, r * 0.5), to, COPPER.darkened(0.25), 4.0)
				ci.draw_line(c - Vector2(0, r * 0.5), to, COPPER, 2.0)
			for p in [Vector2(-0.55, -0.5), Vector2(0.55, -0.5), Vector2(0, 0.45)]:
				_disc(ci, c + p * r, 2.5, COPPER.lerp(LOT_CHAR, dim), OUTLINE, 1.0)
			if not ruined:
				var w := c + Vector2(0, r * 0.45)
				ci.draw_arc(w, r * 0.62, 0.0, TAU, 14, OUTLINE, 3.5)
				ci.draw_arc(w, r * 0.62, 0.0, TAU, 14, RED, 2.2)
				for i in 3:
					ci.draw_line(w, w + Vector2.from_angle(TAU * i / 3.0) * r * 0.6, RED, 1.5)
		"ore_heap":
			_disc(ci, c, r * 1.1, STONE.darkened(0.12).lerp(LOT_CHAR, dim), OUTLINE, 1.5)
			for p in [Vector2(-0.35, 0.2), Vector2(0.3, -0.25), Vector2(0.05, 0.05), Vector2(0.45, 0.35), Vector2(-0.3, -0.4)]:
				_dot(ci, c + p * r * 1.2, r * 0.22, BRASS_LIGHT.lerp(LOT_CHAR, dim))
			if not ruined:
				_dot(ci, c + Vector2(0.05, 0.05) * r, r * 0.12, FIRE_CORE)
				ci.draw_line(c + Vector2(r * 0.6, 0), c + Vector2(r * 0.1, -r * 0.6), WOOD, 2.0)
		"cannon":
			for i in 9:
				var p := c + Vector2.from_angle(TAU * i / 9.0) * r * 1.05
				_disc(ci, p, r * 0.3, CREAM.darkened(0.16).lerp(LOT_CHAR, dim), OUTLINE, 1.0)
			_disc(ci, c, r * 0.45, OLIVE.lerp(LOT_CHAR, dim), OUTLINE, 1.0)
			if not ruined:
				var out := sgn.normalized()
				ci.draw_line(c - out * r * 0.4, c + out * r * 1.3, OUTLINE, 5.0)
				ci.draw_line(c - out * r * 0.4, c + out * r * 1.3, GUNMETAL.lightened(0.1), 3.0)

## Emblema de la Regencia visto desde arriba: rueda dentada de laton, disco
## rojo y el rayo de la Tormenta.
static func _emblem_2d(ci: CanvasItem, e: Vector2, re: float, accent: Color, ruined: bool) -> void:
	if ruined:
		_disc(ci, e, re * 0.5, IRON, OUTLINE, 1.0)
		return
	_dot(ci, e + Vector2(3, 4), re * 1.1, Color(0, 0, 0, 0.3))
	for i in 14:
		var a := TAU * i / 14.0
		ci.draw_line(e + Vector2.from_angle(a) * re * 0.8, e + Vector2.from_angle(a) * re * 1.14, BRASS, 3.5)
	_disc(ci, e, re * 0.92, BRASS, OUTLINE, 1.5)
	_disc(ci, e, re * 0.64, RED, OUTLINE, 1.0)
	ci.draw_polyline(PackedVector2Array([e + Vector2(-0.12, -0.45) * re, e + Vector2(0.12, -0.05) * re, e + Vector2(-0.1, 0.02) * re, e + Vector2(0.14, 0.45) * re]), accent.lightened(0.15), 3.0)

static func _accent_of(plan: Dictionary) -> Color:
	return lot_accent(String(plan.get("id", ""))) if plan.has("id") else (plan["accent"] as Color)

static func _prop_color(kind: String, accent: Color) -> Color:
	match kind:
		"barrel": return WOOD
		"drums": return SLATE
		"crate", "bench": return WOOD
		"goods", "pallet": return LIGHT_WOOD
		"ammo": return OLIVE
		"logs": return RUST
		"planks": return LIGHT_WOOD
		"sacks": return CREAM.darkened(0.08)
		"ore": return STONE
		"coal": return IRON
		"cart": return RED
		"lamp": return IRON
	return accent

## El acento de la parcela por familia, en la paleta de la maqueta: rojo
## industrial, amarillo senal militar, laton civico, verde residencial.
static func lot_accent(id: String) -> Color:
	match String(LotPlanRef.style_of(id).get("accent", "civic")):
		"industrial": return RED
		"military": return BRASS
		"residential": return GREEN
	return BRASS_LIGHT

## Rectangulo girado `rot` centrado en `c`, con contorno.
static func _rot_rect(ci: CanvasItem, c: Vector2, size: Vector2, rot: float, fill: Color, outline := true) -> void:
	var d := Vector2.from_angle(rot) * size.x * 0.5
	var e := Vector2.from_angle(rot + PI * 0.5) * size.y * 0.5
	var pts := PackedVector2Array([c - d - e, c + d - e, c + d + e, c - d + e])
	if outline:
		_poly(ci, pts, fill, OUTLINE, 1.0)
	else:
		ci.draw_colored_polygon(pts, fill)

# ── Yacimientos ──
# Los cuatro yacimientos en "maqueta", con el mismo vocabulario que la 3D
# (scripts/map/DepositMesh.gd): suelo de borde irregular con su reborde
# oscuro, piezas con volumen (pared hacia abajo en pantalla, luz por la
# izquierda, sombra hacia abajo-derecha) y un elemento exagerado por tipo:
# el pino alto del bosque, el racimo de cristales del oro, las dos agujas del
# hierro y la torreta del petroleo. `stage` (4 entero .. 1 casi gastado) quita
# arboles, cristales, pepitas y mineral, y encoge la balsa de petroleo.

## Pixeles de alto por metro de altura (la maqueta vista de tres cuartos).
const DEP_RISE := 7.0

## Dibuja el yacimiento `deposit_id` sobre `size` px centrado en el origen.
## Determinista por `seed_val` (la variante) y `stage`: el mismo dibujo siempre.
static func draw_deposit(ci: CanvasItem, deposit_id: String, size: Vector2, seed_val: int, stage: int = 4) -> void:
	_set_view(0)
	var r := Rect2(-size * 0.5, size).grow(-2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([deposit_id, seed_val])
	var f := float(clampi(stage, 1, 4)) / 4.0
	match deposit_id:
		"forest": _dep_forest(ci, r, rng, f)
		"gold_vein": _dep_gold(ci, r, rng, f)
		"iron_deposit": _dep_iron(ci, r, rng, f)
		"oil_well": _dep_oil(ci, r, rng, f)
		"fish_shoal": _dep_fish_shoal(ci, r, rng)
		_:
			ci.draw_rect(r, Color(0.5, 0.5, 0.5, 0.6))

# ── Bosque ──

static func _dep_forest(ci: CanvasItem, r: Rect2, rng: RandomNumberGenerator, f: float) -> void:
	_dep_ground(ci, r, rng, LEAF_DARK.darkened(0.12), OLIVE_DARK.darkened(0.3))
	var pts := _dep_points(rng, r, 19.0, 9.0)
	var hero := 0
	for i in pts.size():
		if (pts[i] as Vector2).y < (pts[hero] as Vector2).y:
			hero = i
	var kept := maxi(1, ceili(float(pts.size()) * f))
	var order: Array = range(pts.size())
	order.erase(hero)
	order.push_front(hero)
	var items: Array = []
	for k in order.size():
		var i: int = order[k]
		# Mismo numero de tiradas por arbol en cualquier etapa: talar uno no
		# cambia a los demas.
		var round_roll := rng.randf()
		var h := rng.randf_range(1.15, 1.6)
		var tone := rng.randf()
		var kind := "stump"
		if k < kept:
			if i == hero:
				kind = "hero"
			elif round_roll < 0.3:
				kind = "round"
			else:
				kind = "pine"
		items.append({"p": pts[i], "kind": kind, "h": h, "tone": tone})
	# Matorral, debajo de todo
	for k in maxi(2, int(r.size.x * r.size.y / 1500.0)):
		var b := r.get_center() + Vector2(rng.randf_range(-0.42, 0.42) * r.size.x, rng.randf_range(-0.42, 0.42) * r.size.y)
		_dot(ci, b, 3.6, OUTLINE)
		_dot(ci, b, 2.8, OLIVE)
	# La pila de troncos, abajo a la derecha
	var pile := r.end - Vector2(10, 7)
	_dep_log(ci, pile + Vector2(-2.5, 0))
	_dep_log(ci, pile + Vector2(2.5, 0))
	_dep_log(ci, pile + Vector2(0, -3))
	# De atras adelante: las copas de delante tapan a las de detras
	items.sort_custom(func(a, b): return (a["p"] as Vector2).y < (b["p"] as Vector2).y)
	for it in items:
		var p: Vector2 = it["p"]
		match String(it["kind"]):
			"stump": _dep_stump(ci, p)
			"round": _dep_round_tree(ci, p, float(it["h"]) * 0.85, float(it["tone"]))
			"hero": _dep_pine(ci, p, float(it["h"]) * 1.35, float(it["tone"]))
			_: _dep_pine(ci, p, float(it["h"]), float(it["tone"]))

static func _dep_pine(ci: CanvasItem, p: Vector2, h: float, tone: float) -> void:
	var hp := h * DEP_RISE * 1.6
	var w := h * 6.0
	_dep_shadow(ci, p, w * 0.9, hp)
	var base := LEAF_DARK.lerp(OLIVE, tone * 0.6)
	ci.draw_line(p, p - Vector2(0, hp * 0.3), OUTLINE, 3.0)
	ci.draw_line(p, p - Vector2(0, hp * 0.3), DARK_WOOD, 1.6)
	for t in 3:
		var y0 := p.y - hp * (0.18 + 0.24 * t)
		var hw := w * (1.0 - 0.22 * t)
		var tip := Vector2(p.x, y0 - hp * 0.42)
		var tri := PackedVector2Array([Vector2(p.x - hw, y0), Vector2(p.x + hw, y0), tip])
		var col := base.lightened(0.06 * t)
		_poly(ci, tri, col, OUTLINE, 1.2)
		# Mitad en luz (izquierda)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(p.x - hw + 1.5, y0 - 0.8), Vector2(p.x, y0 - 0.8), tip + Vector2(0, 1.5)]), col.lightened(0.14))

static func _dep_round_tree(ci: CanvasItem, p: Vector2, h: float, tone: float) -> void:
	var hp := h * DEP_RISE * 1.6
	var rad := h * 5.5
	var leaf := LEAF.lerp(GREEN.lightened(0.1), tone)
	if tone > 0.9:
		leaf = BRASS.darkened(0.06) if tone > 0.95 else TERRACOTTA
	_dep_shadow(ci, p, rad, hp)
	ci.draw_line(p, p - Vector2(0, hp * 0.5), OUTLINE, 3.0)
	ci.draw_line(p, p - Vector2(0, hp * 0.5), DARK_WOOD, 1.6)
	var c := p - Vector2(0, hp * 0.62)
	_dot(ci, c, rad + 1.2, OUTLINE)
	_dot(ci, c, rad, leaf.darkened(0.1))
	_dot(ci, c - Vector2(rad, rad) * 0.2, rad * 0.7, leaf)
	_dot(ci, c - Vector2(rad, rad) * 0.42, rad * 0.25, leaf.lightened(0.3))

static func _dep_stump(ci: CanvasItem, p: Vector2) -> void:
	_dot(ci, p + Vector2(0, 1.5), 3.6, OUTLINE)
	_dot(ci, p + Vector2(0, 1.0), 2.9, DARK_WOOD)
	_dot(ci, p, 2.9, OUTLINE)
	_dot(ci, p, 2.3, MARBLE.darkened(0.12))
	_dot(ci, p, 0.9, LIGHT_WOOD)

static func _dep_log(ci: CanvasItem, c: Vector2) -> void:
	var a := c - Vector2(0, 5)
	var b := c + Vector2(0, 5)
	ci.draw_line(a, b, OUTLINE, 5.0)
	ci.draw_line(a, b, WOOD.darkened(0.12), 3.4)
	_dot(ci, b, 2.4, OUTLINE)
	_dot(ci, b, 1.7, MARBLE.darkened(0.1))

# ── Oro ──

static func _dep_gold(ci: CanvasItem, r: Rect2, rng: RandomNumberGenerator, f: float) -> void:
	_dep_ground(ci, r, rng, CONCRETE.darkened(0.1), CONCRETE_DARK.darkened(0.3))
	_dep_patches(ci, r, rng, 3, MARBLE.darkened(0.14))
	var m := minf(minf(r.size.x, r.size.y), 74.0)
	var c := r.get_center() + Vector2(0, -r.size.y * 0.06)
	var rocks: Array = []
	for p in _dep_points(rng, r, 20.0, 9.0):
		if (p as Vector2).distance_to(c) < m * 0.3:
			continue
		rocks.append({"p": p, "rad": rng.randf_range(3.6, 5.6), "h": rng.randf_range(2.0, 3.6)})
	rocks.sort_custom(func(a, b): return (a["p"] as Vector2).y < (b["p"] as Vector2).y)
	var tops: Array = []
	# Las de detras, antes que la pena madre
	for rk in rocks:
		if (rk["p"] as Vector2).y < c.y:
			tops.append(_dep_rock(ci, rk["p"], rk["rad"], rk["h"], CONCRETE.lightened(0.04), rng, 5))
	# La pena madre con el racimo encima
	var top := _dep_rock(ci, c, m * 0.24, m * 0.13, CONCRETE.lightened(0.06), rng, 7)
	var crystals := maxi(1, int(round(6.0 * f)))
	var h0 := m * 0.3
	# Azar aparte para lo que se gasta: las penas no cambian entre etapas.
	var crng := _dep_fork(rng)
	var vrng := _dep_fork(rng)
	for k in range(crystals - 1, -1, -1):
		var lean := 0.0 if k == 0 else (float(k) - 3.0) * 0.25
		var at := top + (Vector2.ZERO if k == 0 else Vector2((float(k) - 3.0) * m * 0.035, 2.0))
		var h := h0 if k == 0 else crng.randf_range(0.45, 0.7) * h0
		_dep_crystal(ci, at, h, maxf(2.5, h * 0.24), lean)
	if f > 0.3:
		_dep_sparkle(ci, top - Vector2(0, h0 - 1.0), 3.5)
		_dep_sparkle(ci, top + Vector2(h0 * 0.22, -h0 * 0.4), 2.5)
	for rk in rocks:
		if (rk["p"] as Vector2).y >= c.y:
			tops.append(_dep_rock(ci, rk["p"], rk["rad"], rk["h"], CONCRETE.lightened(0.04), rng, 5))
	for k in mini(tops.size(), int(round(3.0 * f))):
		_dep_crystal(ci, tops[k], 6.0, 2.2, vrng.randf_range(-0.3, 0.3))
	# Pepitas al pie (una de cada tres, encendida)
	for k in int(round(9.0 * f)):
		var a := rng.randf() * TAU
		var p := c + Vector2(cos(a), sin(a) * 0.8) * rng.randf_range(m * 0.27, m * 0.4)
		_dot(ci, p, 2.4, OUTLINE)
		_dot(ci, p, 1.8, FIRE_CORE if k % 3 == 0 else BRASS_LIGHT)
	_dep_pennant(ci, Vector2(r.end.x - 7, r.end.y - 5), 15.0)

static func _dep_crystal(ci: CanvasItem, base: Vector2, h: float, w: float, lean: float) -> void:
	var up := Vector2(sin(lean), -cos(lean))
	var side := Vector2(-up.y, up.x)
	var tip := base + up * h
	var l := base + up * h * 0.55 - side * w
	var rr := base + up * h * 0.55 + side * w
	_poly(ci, PackedVector2Array([base, l, tip, rr]), BRASS_DARK, OUTLINE, 1.2)
	ci.draw_colored_polygon(PackedVector2Array([base + up, l + side * 0.8, tip - up * 0.8, base + up * h * 0.5]), BRASS_LIGHT)
	ci.draw_line(tip - up * 1.0, l + side * 1.2, FIRE_CORE, 1.0)

static func _dep_sparkle(ci: CanvasItem, c: Vector2, s: float) -> void:
	ci.draw_line(c - Vector2(s, 0), c + Vector2(s, 0), FIRE_CORE, 1.2)
	ci.draw_line(c - Vector2(0, s), c + Vector2(0, s), FIRE_CORE, 1.2)
	_dot(ci, c, 1.1, Color.WHITE)

static func _dep_pennant(ci: CanvasItem, base: Vector2, height: float) -> void:
	var tip := _mast(ci, base, height, WOOD, 1.6)
	_poly(ci, PackedVector2Array([tip, tip + Vector2(0, 5), tip + Vector2(9, 2)]), IMPERIAL_RED, OUTLINE, 1.0)

# ── Hierro ──

static func _dep_iron(ci: CanvasItem, r: Rect2, rng: RandomNumberGenerator, f: float) -> void:
	_dep_ground(ci, r, rng, CONCRETE_DARK.darkened(0.25), IRON)
	_dep_patches(ci, r, rng, 4, RUST.darkened(0.05))
	var m := minf(minf(r.size.x, r.size.y), 74.0)
	var c := r.get_center() + Vector2(0, -r.size.y * 0.05)
	var crags: Array = []
	var pts := _dep_points(rng, r, 18.0, 8.0)
	var kept := maxi(1, ceili(float(pts.size()) * f))
	var k := 0
	for p in pts:
		if (p as Vector2).distance_to(c) < m * 0.28:
			continue
		var roll := rng.randf()
		var col := GUNMETAL.darkened(rng.randf_range(0.0, 0.2))
		if roll < 0.45:
			col = RUST.lightened(rng.randf_range(0.0, 0.15))
		elif roll < 0.6:
			col = IRON.lightened(0.15)
		var hh := rng.randf_range(3.0, 6.0) * (1.0 if k < kept else 0.35)
		crags.append({"p": p, "rad": rng.randf_range(3.6, 5.2), "h": hh, "col": col, "lean": rng.randf_range(-0.12, 0.12)})
		k += 1
	# Las dos agujas (lo exagerado), una de pizarra y otra de oxido
	for side in [-1.0, 1.0]:
		var h: float = (m * 0.26 if side < 0.0 else m * 0.21) * lerpf(0.45, 1.0, f)
		crags.append({"p": c + Vector2(side * m * 0.13, 0), "rad": m * 0.13, "h": h, "col": GUNMETAL if side < 0.0 else RUST, "lean": -side * 0.2})
	crags.sort_custom(func(a, b): return (a["p"] as Vector2).y < (b["p"] as Vector2).y)
	for cg in crags:
		_dep_crag(ci, cg["p"], cg["rad"], cg["h"], cg["col"], float(cg["lean"]), rng)
	# El monton de mineral, delante
	var pile := Vector2(c.x + m * 0.18, r.end.y - 8.0)
	for i in int(round(10.0 * f)) + 2:
		var a := rng.randf() * TAU
		var p := pile + Vector2(cos(a), sin(a) * 0.6) * rng.randf_range(0.0, 5.0)
		_rot_rect(ci, p, Vector2(3.2, 2.6), rng.randf() * TAU, TILE_RED_DARK.darkened(rng.randf_range(0.2, 0.45)))

## Una cresta: base poligonal, cuerpo que sube `h` px estrechandose, inclinado
## `lean`, con una banda de oxido y la cima oxidada.
static func _dep_crag(ci: CanvasItem, p: Vector2, rad: float, h: float, col: Color, lean: float, rng: RandomNumberGenerator) -> void:
	var sides := rng.randi_range(4, 5)
	var base := PackedVector2Array()
	var top := PackedVector2Array()
	var shift := Vector2(lean * h, -h)
	for s in sides:
		var a := TAU * s / float(sides) + rng.randf_range(-0.3, 0.3)
		var d := Vector2(cos(a), sin(a) * 0.7) * rad
		base.append(p + d)
		top.append(p + shift + d * 0.45)
	var shadow := PackedVector2Array()
	for q in base:
		shadow.append(q + _shade * h * 0.5)
	ci.draw_colored_polygon(shadow, SHADOW)
	var body_pts := PackedVector2Array(base)
	body_pts.append_array(top)
	var hull := Geometry2D.convex_hull(body_pts)
	if hull.size() > 3:
		hull.remove_at(hull.size() - 1)
		_poly(ci, hull, col.darkened(0.25), OUTLINE, 1.3)
	# Cara de luz (izquierda) del cuerpo
	ci.draw_colored_polygon(PackedVector2Array([p - Vector2(rad * 0.8, 0), p + shift - Vector2(rad * 0.36, 0), p + shift, p]), col)
	# Banda: de oxido en la roca gris, de hierro oscuro en la roja
	var bcol := IRON if col.r > col.b + 0.12 else RUST
	ci.draw_line(p + shift * 0.4 - Vector2(rad * 0.75, 0), p + shift * 0.4 + Vector2(rad * 0.75, 0), bcol, 1.6)
	_poly(ci, top, col.lightened(0.12), OUTLINE, 1.0)
	_dot(ci, p + shift, rad * 0.22, bcol.lightened(0.1))

# ── Petroleo ──

static func _dep_oil(ci: CanvasItem, r: Rect2, rng: RandomNumberGenerator, f: float) -> void:
	_dep_ground(ci, r, rng, DARK_WOOD.darkened(0.3), IRON)
	var shrink := lerpf(0.5, 1.0, f)
	var pc := r.get_center() + Vector2(0, r.size.y * 0.08)
	var rx := r.size.x * 0.3 * shrink
	var ry := r.size.y * 0.25 * shrink
	# Charcos satelite (solo mientras queda mucho), con su propio azar
	var srng := _dep_fork(rng)
	if f > 0.5:
		for sx in [-1.0, 1.0]:
			var sp: Vector2 = pc + Vector2(sx * r.size.x * 0.33, -sx * r.size.y * 0.2)
			_poly(ci, _dep_oval(sp, r.size.x * 0.08, r.size.y * 0.06, srng), OIL_BLACK, OUTLINE, 1.0)
	# La balsa: reborde de brea, negro, reflejo y chispas
	_poly(ci, _dep_oval(pc, rx + 2.5, ry + 2.0, rng), IRON.darkened(0.2), OUTLINE, 1.4)
	ci.draw_colored_polygon(_dep_oval(pc, rx, ry, rng), OIL_BLACK)
	ci.draw_colored_polygon(_dep_oval(pc - Vector2(rx, ry) * 0.25, rx * 0.42, ry * 0.32, rng), OIL_BLACK.lerp(SKY.darkened(0.45), 0.45))
	ci.draw_line(pc + Vector2(-rx * 0.5, -ry * 0.42), pc + Vector2(-rx * 0.2, -ry * 0.42), SKY.lightened(0.15), 1.5)
	ci.draw_line(pc + Vector2(-rx * 0.12, -ry * 0.55), pc + Vector2(-rx * 0.02, -ry * 0.55), SKY.lightened(0.15), 1.2)
	for k in 3:
		var a := rng.randf() * TAU
		var bp := pc + Vector2(cos(a) * rx, sin(a) * ry) * 0.5
		ci.draw_arc(bp, 2.0, 0.0, TAU, 10, IRON.lightened(0.25), 1.0)
	# Juncos en el borde de delante
	for k in 6:
		var a := rng.randf_range(0.3, 2.6)
		var p := pc + Vector2(cos(a) * (rx + 1.0), sin(a) * (ry + 1.5))
		ci.draw_line(p, p + Vector2(rng.randf_range(-1.5, 1.5), -rng.randf_range(3.0, 5.0)), OLIVE, 1.3)
	# La torreta de prospeccion (cuatro patas), detras de la balsa
	var tp := Vector2(pc.x, pc.y - ry - 4.0)
	var tw := 7.0
	var th := 2.0 * DEP_RISE * 1.6
	var apex := tp - Vector2(0, th)
	ci.draw_colored_polygon(PackedVector2Array([tp + Vector2(-tw, 0), tp + Vector2(tw, 0), tp + _shade * th * 0.7]), SHADOW)
	for back in [1.0, 0.0]:
		for sx in [-1.0, 1.0]:
			var foot: Vector2 = tp + Vector2(sx * tw, -back * 3.0)
			var head: Vector2 = apex + Vector2(sx * 1.5, 0)
			ci.draw_line(foot, head, OUTLINE, 3.2)
			ci.draw_line(foot, head, WOOD if back < 0.5 else DARK_WOOD, 1.8)
	for t in [0.3, 0.62]:
		var y: float = tp.y - th * t
		var hw := lerpf(tw, 1.5, t)
		ci.draw_line(Vector2(tp.x - hw, y), Vector2(tp.x + hw, y), DARK_WOOD, 1.4)
	ci.draw_line(apex, apex + Vector2(0, th * 0.55), IRON, 1.0)
	_cyl(ci, apex + Vector2(0, th * 0.55), 1.8, 2.5, GUNMETAL.lightened(0.2), GUNMETAL)
	_disc(ci, apex, 2.4, IMPERIAL_RED, OUTLINE, 1.0)
	ci.draw_line(apex, apex - Vector2(0, 6), OUTLINE, 1.2)
	_poly(ci, PackedVector2Array([apex - Vector2(0, 6), apex - Vector2(0, 1.5), apex + Vector2(8, -4)]), IMPERIAL_RED, OUTLINE, 1.0)
	# Bidones: uno de pie y uno volcado
	var bx := r.end.x - 8.0
	var drum_top := Vector2(bx, pc.y - r.size.y * 0.24)
	_cyl(ci, drum_top, 4.0, 5.5, IMPERIAL_RED.lightened(0.12), IMPERIAL_RED.darkened(0.15))
	_cyl_band(ci, drum_top, 4.0, 5.5, 0.5, 1.2, IMPERIAL_RED.darkened(0.4))
	_rot_rect(ci, Vector2(bx - 1.0, pc.y + 4.0), Vector2(10.0, 7.0), 0.3, IMPERIAL_RED.darkened(0.1))
	_dot(ci, Vector2(bx + 4.0, pc.y + 5.5), 3.0, IMPERIAL_RED.lightened(0.1))

static func _dep_oval(c: Vector2, rx: float, ry: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 14:
		var a := TAU * float(i) / 14.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry) * rng.randf_range(0.88, 1.04))
	return pts

# ── Piezas comunes ──

## Suelo de borde irregular (superelipse) con su reborde oscuro.
static func _dep_ground(ci: CanvasItem, r: Rect2, rng: RandomNumberGenerator, fill: Color, rim: Color) -> void:
	var c := r.get_center()
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		var ca := cos(a)
		var sa := sin(a)
		var k := pow(pow(absf(ca), 4.0) + pow(absf(sa), 4.0), -0.25) * rng.randf_range(0.9, 1.0)
		var d := Vector2(ca * r.size.x * 0.5, sa * r.size.y * 0.5) * k
		outer.append(c + d)
		inner.append(c + d * 0.94)
	_poly(ci, outer, rim, OUTLINE, 1.2)
	ci.draw_colored_polygon(inner, fill)

static func _dep_patches(ci: CanvasItem, r: Rect2, rng: RandomNumberGenerator, n: int, col: Color) -> void:
	for k in n:
		var p := r.get_center() + Vector2(rng.randf_range(-0.3, 0.3) * r.size.x, rng.randf_range(-0.3, 0.3) * r.size.y)
		ci.draw_colored_polygon(_dep_oval(p, rng.randf_range(4.0, 7.0), rng.randf_range(3.0, 5.0), rng), col)

## Un azar hijo, sacado siempre: lo que viene despues no cambia con la etapa.
static func _dep_fork(rng: RandomNumberGenerator) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = rng.randi()
	return r

## Sombra de una pieza de alto `h` px: una mancha hacia abajo-derecha.
static func _dep_shadow(ci: CanvasItem, p: Vector2, rad: float, h: float) -> void:
	_dot(ci, p + _shade * h * 0.35, rad, SHADOW)

## Una pena: base, cuerpo que sube `h` px y cara de arriba mas clara.
## Devuelve el centro de la cara de arriba (donde va un cristal).
static func _dep_rock(ci: CanvasItem, p: Vector2, rad: float, h: float, col: Color, rng: RandomNumberGenerator, sides: int) -> Vector2:
	var base := PackedVector2Array()
	var top := PackedVector2Array()
	for s in sides:
		var a := TAU * s / float(sides) + rng.randf_range(-0.25, 0.25)
		var d := Vector2(cos(a), sin(a) * 0.75) * rad * rng.randf_range(0.85, 1.05)
		base.append(p + d)
		top.append(p + Vector2(0, -h) + d * 0.65)
	var shadow := PackedVector2Array()
	for q in base:
		shadow.append(q + _shade * h * 0.5)
	ci.draw_colored_polygon(shadow, SHADOW)
	var all_pts := PackedVector2Array(base)
	all_pts.append_array(top)
	var hull := Geometry2D.convex_hull(all_pts)
	if hull.size() > 3:
		hull.remove_at(hull.size() - 1)
		_poly(ci, hull, col.darkened(0.28), OUTLINE, 1.3)
	_poly(ci, top, col, OUTLINE, 1.0)
	var tc := p + Vector2(0, -h)
	ci.draw_colored_polygon(PackedVector2Array([top[0], top[1], tc]), col.lightened(0.16))
	return tc

## Puntos repartidos por `r` (rejilla con jitter), en orden al azar.
static func _dep_points(rng: RandomNumberGenerator, r: Rect2, spacing: float, margin: float) -> Array:
	var w := r.size.x - margin * 2.0
	var h := r.size.y - margin * 2.0
	var nx := maxi(1, int(floor(w / spacing)) + 1)
	var ny := maxi(1, int(floor(h / spacing)) + 1)
	var out: Array = []
	for iy in ny:
		for ix in nx:
			var fx := float(ix) / float(nx - 1) if nx > 1 else 0.5
			var fy := float(iy) / float(ny - 1) if ny > 1 else 0.5
			var x := r.position.x + margin + w * fx
			var y := r.position.y + margin + h * fy
			out.append(Vector2(x + rng.randf_range(-0.22, 0.22) * spacing, y + rng.randf_range(-0.22, 0.22) * spacing))
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = out[i]
		out[i] = out[j]
		out[j] = t
	return out


# ══════════════════════════════════════════════════════════════════════
# ── Edificios utiles de la 1.1 (feat/edificios-utiles-1, doc 21 §6.3) ──
# ══════════════════════════════════════════════════════════════════════
# El mismo vocabulario que la 3D (scripts/buildings/UtilityToys.gd): cada uno
# con su elemento exagerado (las aspas, los silos, el letrero, el caballete de
# tablones, la bomba de laton, el fanal, el gran tanque).

static func _utility(ci: CanvasItem, id: String, r: Rect2) -> void:
	match id:
		"windmill": _windmill(ci, r)
		"silo": _silo(ci, r)
		"tavern": _tavern(ci, r)
		"carpentry": _carpentry(ci, r)
		"well": _well(ci, r)
		"lighthouse": _lighthouse(ci, r)
		"fuel_depot": _fuel_depot(ci, r)

## Molino: torre encalada con caperuza de madera y las aspas ENORMES en X;
## cobertizo del grano y sacos.
static func _windmill(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	var shed := Rect2(r.position + r.size * Vector2(0.62, 0.6), r.size * Vector2(0.34, 0.34))
	_gable(ci, shed, m * 0.08, TILE_RED, LIGHT_WOOD, true)
	for k in 3:
		_shaded_disc(ci, r.position + r.size * Vector2(0.14 + k * 0.09, 0.86 - (k % 2) * 0.05), m * 0.05, CREAM.darkened(0.12))
	var base := r.position + r.size * Vector2(0.42, 0.62)
	var h := m * 0.42
	var top := base - _down * h
	_cyl(ci, top, m * 0.17, h, CREAM.darkened(0.04), CREAM.darkened(0.16))
	_disc(ci, top, m * 0.15, WOOD, OUTLINE, 1.2)
	_dot(ci, top + (_left() - _down) * m * 0.03, m * 0.06, LIGHT_WOOD)
	# Aspas: cuatro brazos con su tela, en X sobre la caperuza
	var hub := top - _down * m * 0.04
	for k in 4:
		var a := PI * 0.25 + float(k) * PI * 0.5
		var dir := Vector2(cos(a), sin(a))
		var tip := hub + dir * m * 0.44
		ci.draw_line(hub, tip, OUTLINE, 3.5)
		ci.draw_line(hub, tip, DARK_WOOD, 2.0)
		var side := Vector2(-dir.y, dir.x) * m * 0.07
		var p0 := hub + dir * m * 0.14
		_poly(ci, PackedVector2Array([p0, tip, tip + side, p0 + side]), CREAM, OUTLINE, 1.0)
	_disc(ci, hub, m * 0.045, BRASS, OUTLINE, 1.0)

## Silo: dos silos altos de chapa con aros de laton y caperuza de teja; tolva
## a la caseta de carga.
static func _silo(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	var shed := Rect2(r.position + r.size * Vector2(0.52, 0.66), r.size * Vector2(0.4, 0.3))
	_gable(ci, shed, m * 0.08, SLATE, LIGHT_WOOD, true)
	var tops := [r.position + r.size * Vector2(0.3, 0.18), r.position + r.size * Vector2(0.7, 0.24)]
	var hs := [m * 0.42, m * 0.34]
	var rads := [m * 0.18, m * 0.15]
	for i in 2:
		var c: Vector2 = tops[i]
		var h: float = hs[i]
		var rad: float = rads[i]
		_cyl(ci, c, rad, h, SLATE.lightened(0.2), SLATE.lightened(0.05))
		for t in [0.25, 0.6]:
			_cyl_band(ci, c, rad, h, t, 1.5, BRASS)
		_disc(ci, c, rad * 0.9, TILE_RED, OUTLINE, 1.0)
		_dot(ci, c, rad * 0.25, TILE_RED_DARK)
	var a: Vector2 = tops[1] + _down * float(hs[1]) * 0.7
	var b := shed.get_center()
	ci.draw_line(a, b, OUTLINE, 5.0)
	ci.draw_line(a, b, BRASS, 3.0)
	for k in 2:
		_shaded_disc(ci, r.position + r.size * Vector2(0.14 + k * 0.12, 0.85), m * 0.05, CREAM.darkened(0.12))

## Taberna: casa de dos plantas con tejado de teja, ventanas encendidas,
## chimenea y el GRAN letrero de laton con la jarra; barriles delante.
static func _tavern(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	var body := Rect2(r.position + r.size * Vector2(0.04, 0.0), r.size * Vector2(0.92, 0.72))
	var top := _gable(ci, body, m * 0.26, TILE_RED, CREAM, true)
	_wall_marks(ci, _wall, 4, GLOW, 0.45, DARK_WOOD)
	var ch := Rect2(r.position + r.size * Vector2(0.18, 0.04), Vector2(m * 0.14, m * 0.14))
	var ct := _block(ci, ch, m * 0.07, TILE_RED_DARK, TILE_RED_DARK.darkened(0.25))
	ci.draw_rect(ct.grow(-ct.size.x * 0.22), OIL_BLACK)
	# El letrero exagerado colgado de su brazo, con la jarra
	var arm := top.position + top.size * Vector2(0.08, 1.0) + _down * m * 0.1
	var sign_c := arm + _down * m * 0.12
	ci.draw_line(arm, sign_c, OUTLINE, 2.5)
	var sr := Rect2(sign_c - Vector2(m * 0.11, m * 0.08), Vector2(m * 0.22, m * 0.16))
	_plate(ci, sr, BRASS, OUTLINE, 1.2)
	var mug := Rect2(sr.get_center() - Vector2(m * 0.035, m * 0.045), Vector2(m * 0.07, m * 0.09))
	ci.draw_rect(mug, CREAM)
	ci.draw_rect(mug, OUTLINE, false, 1.0)
	for k in 2:
		_shaded_disc(ci, r.position + r.size * Vector2(0.62 + k * 0.13, 0.88), m * 0.06, WOOD)
	ci.draw_rect(Rect2(r.position + r.size * Vector2(0.3, 0.85), r.size * Vector2(0.22, 0.05)), LIGHT_WOOD)

## Carpinteria: cobertizo abierto de chapa sobre suelo de tablas, banco con
## tablon, y el caballete de tablones de pie (lo exagerado).
static func _carpentry(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	ci.draw_rect(r.grow(1.0), OUTLINE)
	ci.draw_rect(r, LIGHT_WOOD.darkened(0.08))
	for i in range(1, 7):
		var y := r.position.y + r.size.y * i / 7.0
		ci.draw_line(Vector2(r.position.x + 1, y), Vector2(r.end.x - 1, y), WOOD, 1.0)
	var roof := Rect2(r.position, r.size * Vector2(1.0, 0.48))
	var top := _block(ci, roof, m * 0.14, SLATE.lightened(0.12), DARK_WOOD)
	for i in range(1, 6):
		var x := top.position.x + top.size.x * i / 6.0
		ci.draw_line(Vector2(x, top.position.y + 1), Vector2(x, top.end.y - 1), SLATE.lightened(0.3), 1.0)
	var bench := Rect2(r.position + r.size * Vector2(0.14, 0.58), r.size * Vector2(0.4, 0.14))
	_block(ci, bench, m * 0.05, LIGHT_WOOD, DARK_WOOD)
	ci.draw_rect(Rect2(bench.position + bench.size * Vector2(0.65, 0.2), bench.size * Vector2(0.25, 0.5)), RED)
	# El caballete de tablones (exagerado), de pie a la derecha
	var base := r.position + r.size * Vector2(0.76, 0.9)
	for k in 5:
		var off := _left() * m * (0.12 - k * 0.06)
		var tip := base + off - _down * m * (0.62 - (k % 2) * 0.06)
		ci.draw_line(base + off, tip, OUTLINE, 5.0)
		ci.draw_line(base + off, tip, LIGHT_WOOD.lightened(0.05 * (k % 3)), 3.2)
	ci.draw_line(base + _left() * m * 0.16, base - _left() * m * 0.16, DARK_WOOD, 3.0)

## Pozo: plaza de losas, brocal de piedra con el agua, tejadillo, la bomba de
## laton con su volante rojo (lo exagerado) y los cubos contra el fuego.
static func _well(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	ci.draw_rect(r.grow(1.0), OUTLINE)
	_plate(ci, r, CONCRETE, CONCRETE_DARK, 1.0)
	var wc := r.position + r.size * Vector2(0.42, 0.46)
	_cyl(ci, wc, m * 0.22, m * 0.08, STONE.lightened(0.08), STONE.darkened(0.12))
	_dot(ci, wc, m * 0.15, WATER.darkened(0.3))
	_dot(ci, wc + Vector2(-1, -1) * m * 0.04, m * 0.05, WATER)
	var roof := Rect2(wc - Vector2(m * 0.26, m * 0.18) - _down * m * 0.2, Vector2(m * 0.52, m * 0.2))
	_gable(ci, roof, m * 0.04, TILE_RED, DARK_WOOD, true)
	var pump := r.position + r.size * Vector2(0.8, 0.62)
	_cyl(ci, pump - _down * m * 0.2, m * 0.07, m * 0.2, BRASS_LIGHT, BRASS)
	var wheel := pump - _down * m * 0.12 + _left() * m * 0.1
	ci.draw_arc(wheel, m * 0.08, 0.0, TAU, 12, OUTLINE, 3.0)
	ci.draw_arc(wheel, m * 0.08, 0.0, TAU, 12, RED, 1.8)
	for k in 3:
		_disc(ci, r.position + r.size * Vector2(0.14 + k * 0.1, 0.88), m * 0.04, RED, OUTLINE, 1.0)

## Faro: torre alta encalada con franjas rojas, galeria, el fanal encendido
## con su halo (lo exagerado) y caperuza roja; caseta del vigia.
static func _lighthouse(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	ci.draw_rect(r.grow(1.0), OUTLINE)
	_plate(ci, r, SLATE.lightened(0.18), OUTLINE, 1.0)
	_rivets(ci, r, BRASS, 3.0)
	var hut := Rect2(r.position + r.size * Vector2(0.6, 0.62), r.size * Vector2(0.34, 0.3))
	_gable(ci, hut, m * 0.07, SLATE, STONE, true)
	var base := r.position + r.size * Vector2(0.42, 0.7)
	var h := m * 0.6
	var top := base - _down * h
	_cyl(ci, top, m * 0.15, h, CREAM, CREAM.darkened(0.14))
	for t in [0.3, 0.65]:
		_cyl_band(ci, top, m * 0.15, h, t, 3.0, RED)
	_dot(ci, top, m * 0.3, Color(GLOW, 0.22))
	_disc(ci, top, m * 0.19, IRON, OUTLINE, 1.0)
	_disc(ci, top, m * 0.12, GLOW, OUTLINE, 1.0)
	_dot(ci, top, m * 0.06, FIRE_CORE)
	_disc(ci, top - _down * m * 0.05, m * 0.08, RED, OUTLINE, 1.0)
	_dot(ci, top - _down * m * 0.07, m * 0.025, BRASS_LIGHT)

## Deposito de combustible: suelo de chapa, el GRAN tanque con su franja de
## peligro, uno pequeno, colector con valvulas rojas y bidones.
static func _fuel_depot(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	ci.draw_rect(r.grow(1.0), OUTLINE)
	_plate(ci, r, SLATE.darkened(0.05), OUTLINE, 1.0)
	_rivets(ci, r, BRASS, 3.0)
	var big := r.position + r.size * Vector2(0.36, 0.22)
	var small := r.position + r.size * Vector2(0.78, 0.26)
	var mouth := r.position + r.size * Vector2(0.84, 0.82)
	for pair in [[big + _down * m * 0.3, mouth], [small + _down * m * 0.18, mouth]]:
		ci.draw_line(pair[0], pair[1], OUTLINE, 5.0)
		ci.draw_line(pair[0], pair[1], STEEL, 3.0)
	for p in [(big + mouth) * 0.5 + _down * m * 0.12, (small + mouth) * 0.5]:
		ci.draw_arc(p, 3.2, 0.0, TAU, 10, OUTLINE, 2.5)
		ci.draw_arc(p, 3.2, 0.0, TAU, 10, RED, 1.5)
	_cyl(ci, big, m * 0.26, m * 0.3, CREAM, CREAM.darkened(0.12))
	_cyl_band(ci, big, m * 0.26, m * 0.3, 0.45, 3.0, HAZARD)
	_cyl_band(ci, big, m * 0.26, m * 0.3, 0.15, 1.5, RED)
	ci.draw_arc(big, m * 0.14, 0.0, TAU, 16, STONE, 1.0)
	_cyl(ci, small, m * 0.14, m * 0.18, STEEL, SLATE.lightened(0.1))
	_cyl_band(ci, small, m * 0.14, m * 0.18, 0.4, 1.5, BRASS)
	var box := Rect2(mouth - Vector2(m * 0.07, m * 0.07), Vector2(m * 0.14, m * 0.14))
	ci.draw_rect(box.grow(1.0), OUTLINE)
	ci.draw_rect(box, RED)
	_dot(ci, mouth, m * 0.025, GLOW)
	for k in 3:
		_shaded_disc(ci, r.position + r.size * Vector2(0.12 + k * 0.11, 0.86), m * 0.05, RED.darkened(0.1))

# ── Decoraciones baratas (feat/decoraciones-1, doc 21 §6.4) ───────────
# Las mismas diez que DecorMesh en 3D, con el mismo vocabulario: un suelo que
# llena el rectangulo (encima de la sombra de draw_building) y la pieza
# exagerada de cada una. Solo primitivas baratas: se hornean en ArtCache2D.

## El suelo de la decoracion: losas, cesped o tierra con su borde.
static func _deco_pad(ci: CanvasItem, r: Rect2, kind: String) -> void:
	var fill := Color8(214, 198, 170)
	match kind:
		"grass": fill = GREEN.lightened(0.1)
		"dirt": fill = SITE_DIRT.lightened(0.12)
	ci.draw_rect(r.grow(1.0), OUTLINE)
	ci.draw_rect(r, fill.darkened(0.1))
	ci.draw_rect(r.grow(-2.5), fill)

## Farola: peana, fuste alto de hierro y dos faroles encendidos.
static func _lamp_post(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	_deco_pad(ci, r, "slabs")
	var c := r.get_center() + _down * m * 0.22
	_disc(ci, c, m * 0.1, STONE, OUTLINE, 1.0)
	var tip := _mast(ci, c, m * 0.55, IRON, 2.5)
	for s in [-1.0, 1.0]:
		var lamp: Vector2 = tip + _left() * m * 0.13 * s + _down * m * 0.04
		ci.draw_line(tip, lamp, IRON, 2.0)
		_dot(ci, lamp, m * 0.1, Color(GLOW, 0.3))
		_disc(ci, lamp, m * 0.05, GLOW, OUTLINE, 1.0)

## Banco: dos bancos de madera frente a frente y una mata en maceta.
static func _park_bench(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	_deco_pad(ci, r, "slabs")
	var c := r.get_center()
	var along := Vector2(absf(_down.y), absf(_down.x))
	var across := Vector2(absf(_down.x), absf(_down.y))
	for s in [-1.0, 1.0]:
		var bc: Vector2 = c + _down * m * 0.28 * s
		var size := along * m * 0.62 + across * m * 0.14
		_block(ci, Rect2(bc - size * 0.5, size), m * 0.05, LIGHT_WOOD, DARK_WOOD)
	_cyl(ci, c, m * 0.08, m * 0.05, TERRACOTTA, TILE_RED_DARK)
	_shaded_disc(ci, c - _down * m * 0.05, m * 0.1, GREEN)

## Seto: seto recortado en U, abierto hacia delante, con su bola en maceta.
static func _hedge(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	_deco_pad(ci, r, "grass")
	var t := m * 0.16
	var h := m * 0.08
	_block(ci, Rect2(r.position, Vector2(r.size.x, t)), h, GREEN.darkened(0.05), LEAF_DARK)
	_block(ci, Rect2(r.position + Vector2(0, t), Vector2(t, r.size.y - t)), h, GREEN.darkened(0.05), LEAF_DARK)
	_block(ci, Rect2(Vector2(r.end.x - t, r.position.y + t), Vector2(t, r.size.y - t)), h, GREEN.darkened(0.05), LEAF_DARK)
	var c := r.get_center() + Vector2(0, m * 0.08)
	_cyl(ci, c, m * 0.08, m * 0.05, TERRACOTTA, TILE_RED_DARK)
	_shaded_disc(ci, c - _down * m * 0.1, m * 0.12, GREEN)

## Arbol de paseo: alcorque de hierro y una copa grande y redonda.
static func _avenue_tree(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	_deco_pad(ci, r, "slabs")
	var c := r.get_center()
	var g := Rect2(c - Vector2(m, m) * 0.2, Vector2(m, m) * 0.4)
	ci.draw_rect(g.grow(1.0), OUTLINE)
	ci.draw_rect(g, IRON.lightened(0.15))
	ci.draw_rect(g.grow(-2.5), DARK_WOOD)
	var t := c - _down * m * 0.12
	var tr := m * 0.3
	_dot(ci, t + _shade * tr * 0.6, tr, SHADOW)
	_dot(ci, t, tr + 1.0, OUTLINE)
	_dot(ci, t, tr, GREEN.darkened(0.08))
	_dot(ci, t + (_left() - _down) * tr * 0.25, tr * 0.6, GREEN.lightened(0.12))
	_dot(ci, t + (_left() - _down) * tr * 0.42, tr * 0.22, GREEN.lightened(0.35))

## Macetero: tres macetas de barro con su mata y flores de colores.
static func _flower_planter(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	_deco_pad(ci, r, "slabs")
	var cols := [RED, BRASS_LIGHT, CREAM, TERRACOTTA]
	var pots := [Vector2(0.28, 0.62), Vector2(0.72, 0.68), Vector2(0.5, 0.3)]
	var sizes := [0.13, 0.11, 0.15]
	for i in pots.size():
		var p: Vector2 = r.position + r.size * (pots[i] as Vector2)
		var pr: float = m * float(sizes[i])
		_cyl(ci, p, pr, m * 0.07, DARK_WOOD, TERRACOTTA)
		_shaded_disc(ci, p - _down * pr * 0.25, pr * 0.95, GREEN)
		for k in 3:
			_dot(ci, p - _down * pr * 0.25 + Vector2.from_angle(TAU * k / 3.0 + i) * pr * 0.5, maxf(1.2, pr * 0.22), cols[(i + k) % cols.size()])

## Letrero de la colonia: dos postes, el tablero con marco de laton y su
## mastil; la bandera del pais la pone ColonyFlag2D (flag_mount).
static func _colony_sign(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	_deco_pad(ci, r, "grass")
	var c := r.get_center() + _down * m * 0.18
	var side := _left() * m * 0.22
	var a := _mast(ci, c + side, m * 0.3, DARK_WOOD, 2.5)
	var b := _mast(ci, c - side, m * 0.3, DARK_WOOD, 2.5)
	_poly(ci, PackedVector2Array([a, b, b + _down * m * 0.16, a + _down * m * 0.16]), BRASS, OUTLINE, 1.25)
	ci.draw_colored_polygon(PackedVector2Array([a.lerp(b, 0.08) + _down * 2.0, b.lerp(a, 0.08) + _down * 2.0,
		b.lerp(a, 0.08) + _down * (m * 0.16 - 2.0), a.lerp(b, 0.08) + _down * (m * 0.16 - 2.0)]), CREAM)
	ci.draw_line(a.lerp(b, 0.25) + _down * m * 0.08, b.lerp(a, 0.25) + _down * m * 0.08, IRON, 1.5)
	var mast := _colony_sign_mast(r, m)
	_mast(ci, mast[0], mast[1], IRON, 1.8)

## [base, alto] del mastil del letrero (lo comparten su dibujo y flag_mount).
static func _colony_sign_mast(r: Rect2, m: float) -> Array:
	var c := r.get_center() + _down * m * 0.18
	var side := _left() * m * 0.22
	return [c - side * 1.6 + _down * m * 0.02, m * 0.5]

## Carro de heno: carro de madera con dos ruedas, el heno amontonado encima y
## dos pacas al lado.
static func _hay_cart(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	_deco_pad(ci, r, "dirt")
	var c := r.get_center() - _down * m * 0.04
	var size := Vector2(m * 0.48, m * 0.34)
	var top := _block(ci, Rect2(c - size * 0.5, size), m * 0.08, LIGHT_WOOD, DARK_WOOD)
	for s in [-1.0, 1.0]:
		_disc(ci, c + _left() * size.x * 0.48 * s + _down * size.y * 0.42, m * 0.08, DARK_WOOD, OUTLINE, 1.25)
	_shaded_disc(ci, top.get_center() - _down * m * 0.04, m * 0.17, BRASS)
	for p in [Vector2(0.18, 0.8), Vector2(0.8, 0.2)]:
		var bc: Vector2 = r.position + r.size * (p as Vector2)
		var bs := Vector2(m * 0.2, m * 0.13)
		_block(ci, Rect2(bc - bs * 0.5, bs), m * 0.05, BRASS_LIGHT, BRASS_DARK)

## Hoguera: corro de piedras, troncos cruzados, la llama encendida y dos
## troncos para sentarse.
static func _bonfire(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	_deco_pad(ci, r, "dirt")
	var c := r.get_center()
	_dot(ci, c, m * 0.3, Color(FIRE, 0.18))
	for i in 8:
		_disc(ci, c + Vector2.from_angle(TAU * i / 8.0) * m * 0.2, m * 0.05, STONE.darkened(0.05 * (i % 3)), OUTLINE, 1.0)
	_dot(ci, c, m * 0.15, IRON)
	for i in 3:
		var d := Vector2.from_angle(TAU * i / 3.0 + 0.4) * m * 0.14
		ci.draw_line(c - d, c + d, OUTLINE, 4.0)
		ci.draw_line(c - d, c + d, DARK_WOOD, 2.6)
	_dot(ci, c - _down * m * 0.03, m * 0.1, FIRE)
	_dot(ci, c - _down * m * 0.06, m * 0.05, FIRE_CORE)
	for s in [-1.0, 1.0]:
		var lc: Vector2 = c + _down * m * 0.38 * s
		ci.draw_line(lc - _left() * m * 0.2, lc + _left() * m * 0.2, OUTLINE, m * 0.09 + 2.0)
		ci.draw_line(lc - _left() * m * 0.2, lc + _left() * m * 0.2, LIGHT_WOOD, m * 0.09)

## Mastil con bandera: peana de dos escalones y el mastil alto; la bandera
## del pais la pone ColonyFlag2D (flag_mount).
static func _flagpole(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	_deco_pad(ci, r, "slabs")
	var mast := _flagpole_mast(r, m)
	var base: Vector2 = mast[0]
	_block(ci, Rect2(base - Vector2(m, m) * 0.17, Vector2(m, m) * 0.34), m * 0.05, STONE.lightened(0.1), CONCRETE_DARK)
	_block(ci, Rect2(base - Vector2(m, m) * 0.1, Vector2(m, m) * 0.2), m * 0.05, CREAM, STONE)
	var tip := _mast(ci, base, mast[1], IRON, 2.5)
	_disc(ci, tip, 2.2, BRASS, OUTLINE, 1.0)

## [base, alto] del mastil (lo comparten su dibujo y flag_mount).
static func _flagpole_mast(r: Rect2, m: float) -> Array:
	return [r.get_center() + _down * m * 0.2, m * 0.72]

## Palmeras: corro de arena y dos palmeras con las hojas abiertas.
static func _palm_trees(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	_deco_pad(ci, r, "grass")
	_disc(ci, r.get_center(), m * 0.44, CREAM.darkened(0.06), CREAM.darkened(0.25), 1.5)
	for p in [[Vector2(0.36, 0.62), 0.42, 0.2], [Vector2(0.66, 0.7), 0.3, 0.16]]:
		var base: Vector2 = r.position + r.size * (p[0] as Vector2)
		var crown: Vector2 = base - _down * m * float(p[1]) + _left() * m * 0.04
		ci.draw_line(base, crown, OUTLINE, 5.0)
		ci.draw_line(base, crown, WOOD, 3.2)
		var leaf: float = m * float(p[2])
		for i in 5:
			var d := Vector2.from_angle(TAU * i / 5.0 + 0.3)
			var tip := crown + d * leaf
			var side := Vector2(-d.y, d.x) * leaf * 0.22
			_poly(ci, PackedVector2Array([crown, tip + side, tip + d * 2.0, tip - side]), GREEN.darkened(0.04 * (i % 2)), OUTLINE, 1.0)
		_dot(ci, crown, 2.2, DARK_WOOD)


# ══════════════════════════════════════════════════════════════════════
# ── Mar y aire (1.1, feat/aire-mar-vista) ──
# ══════════════════════════════════════════════════════════════════════
# Los mismos edificios que sus maquetas 3D (tools/toy_recipes/shipyard.gd y
# aerodrome.gd), en el marco local del edificio: el lado de delante (+y local,
# abajo en pantalla sin girar) es el del agua en el Astillero y el de la pista
# en el Aerodromo. Cada uno con su elemento exagerado: la grua de portico y el
# mastil con el dirigible.

## Astillero: tierra atras con la nave del taller y su chimenea; delante la
## darsena (agua entre dos muelles) con la grada, el casco a medio hacer y la
## GRUA de portico amarilla cruzando por encima.
static func _shipyard(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	var land := Rect2(r.position, Vector2(r.size.x, r.size.y * 0.46))
	ci.draw_rect(r.grow(1.0), OUTLINE)
	ci.draw_rect(land, CONCRETE_DARK)
	var quay := r.size.x * 0.13
	var dock := Rect2(Vector2(r.position.x, land.end.y), Vector2(r.size.x, r.end.y - land.end.y))
	for left in [true, false]:
		var q := Rect2(Vector2(dock.position.x if left else dock.end.x - quay, dock.position.y), Vector2(quay, dock.size.y))
		_plate(ci, q, CONCRETE, OUTLINE, 1.0)
		_dot(ci, q.get_center() + Vector2((quay * 0.2) * (1.0 if left else -1.0), -dock.size.y * 0.2), m * 0.025, IRON)
	var water := Rect2(dock.position + Vector2(quay, 0), Vector2(dock.size.x - quay * 2.0, dock.size.y))
	ci.draw_rect(water, WATER.darkened(0.12))
	for k in 3:
		var y := water.position.y + water.size.y * (0.3 + 0.25 * k)
		var x0 := water.position.x + water.size.x * (0.12 + 0.2 * float(k % 2))
		ci.draw_line(Vector2(x0, y), Vector2(x0 + water.size.x * 0.26, y), WATER.lightened(0.3), 1.2)
	# La grada y el casco a medio hacer (proa hacia el agua)
	var slip := Rect2(Vector2(r.get_center().x - m * 0.17, land.end.y - m * 0.1), Vector2(m * 0.34, water.end.y - land.end.y + m * 0.06))
	ci.draw_rect(slip, LIGHT_WOOD.darkened(0.15))
	for k in 6:
		var y := slip.position.y + slip.size.y * (float(k) + 0.5) / 6.0
		ci.draw_line(Vector2(slip.position.x, y), Vector2(slip.end.x, y), DARK_WOOD, 1.0)
	var cx := slip.get_center().x
	var y0 := slip.position.y + m * 0.04
	var y1 := slip.end.y - m * 0.04
	var hw := m * 0.12
	var hull := PackedVector2Array([Vector2(cx - hw, y0), Vector2(cx + hw, y0), Vector2(cx + hw, y1 - hw * 1.4),
		Vector2(cx, y1), Vector2(cx - hw, y1 - hw * 1.4)])
	_poly(ci, hull, GUNMETAL, OUTLINE, 1.2)
	ci.draw_line(Vector2(cx, y0), Vector2(cx, y1), TILE_RED, 2.0)
	for k in 5:
		var y := y0 + (y1 - y0) * (float(k) + 0.5) / 6.0
		ci.draw_line(Vector2(cx - hw * 0.9, y), Vector2(cx + hw * 0.9, y), LIGHT_WOOD, 1.2)
	# La nave del taller y su chimenea, atras a la izquierda
	var shed := Rect2(r.position + Vector2(r.size.x * 0.04, r.size.y * 0.04), Vector2(r.size.x * 0.4, r.size.y * 0.3))
	_gable(ci, shed, m * 0.1, SLATE, CREAM.darkened(0.08), true)
	_wall_marks(ci, _wall, 2, GLOW, 0.35, DARK_WOOD)
	var ch := r.position + Vector2(r.size.x * 0.1, r.size.y * 0.08)
	_cyl(ci, ch - _down * m * 0.14, m * 0.045, m * 0.14, SLATE.darkened(0.2), SLATE.darkened(0.3))
	_cyl_band(ci, ch - _down * m * 0.14, m * 0.045, m * 0.14, 0.3, 1.5, IMPERIAL_RED)
	# Chapa y tablones, atras a la derecha
	var sheets := Rect2(r.position + r.size * Vector2(0.66, 0.08), r.size * Vector2(0.26, 0.12))
	ci.draw_rect(sheets, STEEL)
	ci.draw_rect(sheets, OUTLINE, false, 1.0)
	var planks := Rect2(r.position + r.size * Vector2(0.66, 0.26), r.size * Vector2(0.26, 0.1))
	ci.draw_rect(planks, LIGHT_WOOD)
	ci.draw_rect(planks, OUTLINE, false, 1.0)
	# La grua de portico (lo exagerado): las patas sobre los muelles y la viga
	# amarilla cruzando la darsena, con el carro y el gancho
	var gy := dock.position.y + dock.size.y * 0.42
	var beam := Rect2(Vector2(r.position.x + quay * 0.2, gy - m * 0.05), Vector2(r.size.x - quay * 0.4, m * 0.1))
	ci.draw_rect(Rect2(beam.position + _shade * m * 0.12, beam.size), Color(SHADOW, 0.35))
	ci.draw_rect(beam.grow(1.0), OUTLINE)
	ci.draw_rect(beam, BRASS)
	ci.draw_line(beam.position + Vector2(1, 1), Vector2(beam.end.x - 1, beam.position.y + 1), BRASS_LIGHT, 1.5)
	for left in [true, false]:
		var leg := Rect2(Vector2(dock.position.x + quay * 0.15 if left else dock.end.x - quay * 0.85, gy - m * 0.09), Vector2(quay * 0.7, m * 0.18))
		_hazard_strip(ci, leg)
		ci.draw_rect(leg, OUTLINE, false, 1.0)
	var trolley := Rect2(Vector2(r.get_center().x + m * 0.01, gy - m * 0.06), Vector2(m * 0.1, m * 0.12))
	ci.draw_rect(trolley, GUNMETAL)
	ci.draw_rect(trolley, OUTLINE, false, 1.0)
	_dot(ci, trolley.get_center() + Vector2(0, m * 0.1), m * 0.025, IMPERIAL_RED)

## Aerodromo: hierba con la pista delante (asfalto, rayas y balizas), el hangar
## de media cana atras a la izquierda con el portalon abierto, y atras a la
## derecha el MASTIL de amarre con el dirigible y la manga de viento.
static func _aerodrome(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	ci.draw_rect(r.grow(1.0), OUTLINE)
	ci.draw_rect(r, OLIVE_DARK)
	# La pista
	var strip := Rect2(Vector2(r.position.x, r.end.y - r.size.y * 0.3), Vector2(r.size.x, r.size.y * 0.24))
	ci.draw_rect(strip, OIL_BLACK.lightened(0.18))
	ci.draw_line(strip.position, Vector2(strip.end.x, strip.position.y), OIL_BLACK.lightened(0.35), 1.0)
	for k in 5:
		var x := strip.position.x + strip.size.x * (0.08 + 0.21 * k)
		ci.draw_rect(Rect2(Vector2(x, strip.get_center().y - 1.0), Vector2(strip.size.x * 0.09, 2.0)), CREAM)
	for p in [strip.position + Vector2(3, 3), Vector2(strip.end.x - 3, strip.position.y + 3),
			Vector2(strip.position.x + 3, strip.end.y - 3), strip.end - Vector2(3, 3)]:
		_dot(ci, p, 1.8, GLOW)
	# El hangar de media cana (las costillas de la chapa) y su portalon
	var hg := Rect2(r.position + r.size * Vector2(0.04, 0.05), r.size * Vector2(0.44, 0.52))
	ci.draw_rect(Rect2(hg.position + _shade * m * 0.08, hg.size), SHADOW)
	ci.draw_rect(hg.grow(1.0), OUTLINE)
	ci.draw_rect(hg, STEEL)
	ci.draw_rect(Rect2(hg.position, Vector2(hg.size.x * 0.3, hg.size.y)), STEEL.lightened(0.15))
	ci.draw_rect(Rect2(Vector2(hg.end.x - hg.size.x * 0.25, hg.position.y), Vector2(hg.size.x * 0.25, hg.size.y)), GUNMETAL)
	for k in range(1, 5):
		var y := hg.position.y + hg.size.y * float(k) / 5.0
		ci.draw_line(Vector2(hg.position.x, y), Vector2(hg.end.x, y), GUNMETAL.darkened(0.2), 1.2)
	var door := Rect2(Vector2(hg.position.x + hg.size.x * 0.15, hg.end.y - m * 0.05), Vector2(hg.size.x * 0.7, m * 0.06))
	ci.draw_rect(door, OIL_BLACK)
	_hazard_strip(ci, Rect2(Vector2(door.position.x, door.position.y - 3.0), Vector2(door.size.x, 3.0)))
	# Bidones junto al hangar
	for k in 3:
		_shaded_disc(ci, r.position + r.size * Vector2(0.56 + k * 0.08, 0.6), m * 0.035, IMPERIAL_RED if k != 1 else OLIVE)
	# La manga de viento
	var sock_base := r.position + r.size * Vector2(0.9, 0.55)
	var sock_tip := _mast(ci, sock_base, m * 0.2, IRON, 1.5)
	_poly(ci, PackedVector2Array([sock_tip, sock_tip + Vector2(-m * 0.14, m * 0.02), sock_tip + Vector2(-m * 0.12, m * 0.06)]), IMPERIAL_RED, OUTLINE, 1.0)
	# El mastil de amarre (lo exagerado): celosia de laton y el faro arriba
	var mb := r.position + r.size * Vector2(0.78, 0.26)
	var tip := _mast(ci, mb, m * 0.38, BRASS_DARK, 3.0)
	for t in [0.33, 0.66]:
		var p: Vector2 = mb.lerp(tip, t)
		ci.draw_line(p - _left() * m * 0.04, p + _left() * m * 0.04, BRASS_DARK, 1.5)
	_dot(ci, tip, m * 0.03, GLOW)
	# El dirigible amarrado de la proa, flotando hacia el centro de la parcela
	var c := tip + Vector2(-m * 0.24, m * 0.08)
	var rx := m * 0.2
	var ry := m * 0.085
	var shadow := PackedVector2Array()
	var body := PackedVector2Array()
	for i in 16:
		var a := TAU * float(i) / 16.0
		var q := Vector2(cos(a) * rx, sin(a) * ry)
		body.append(c + q)
		shadow.append(c + q + _shade * m * 0.22)
	ci.draw_colored_polygon(shadow, Color(SHADOW, 0.3))
	_poly(ci, body, CREAM, OUTLINE, 1.3)
	ci.draw_line(c + Vector2(-rx * 0.6, -ry * 0.55), c + Vector2(rx * 0.4, -ry * 0.75), CREAM.lightened(0.4), 1.5)
	for f in [-0.35, 0.25]:
		var x: float = c.x + rx * f
		var h: float = ry * sqrt(maxf(0.0, 1.0 - f * f)) * 0.95
		ci.draw_line(Vector2(x, c.y - h), Vector2(x, c.y + h), IMPERIAL_RED, 2.5)
	_poly(ci, PackedVector2Array([c + Vector2(-rx * 0.85, 0), c + Vector2(-rx * 1.15, -ry * 0.9), c + Vector2(-rx * 1.15, ry * 0.9)]), IMPERIAL_RED, OUTLINE, 1.0)
	ci.draw_line(c + Vector2(rx, 0), tip, IRON, 1.2)


# ══════════════════════════════════════════════════════════════════════
# ── Muelle de pesca (feat/muelle-pesca) ──
# ══════════════════════════════════════════════════════════════════════
# El mismo vocabulario que su receta 3D (tools/toy_recipes/fishing_dock.gd):
# tarima de tablas, el ahumadero de tejado rojo con su chimenea, el tendedero
# con peces colgados, la barca boca arriba con su franja roja y barriles.

static func _fishing_dock(ci: CanvasItem, r: Rect2) -> void:
	var m := minf(r.size.x, r.size.y)
	# La tarima: tablas claras con sus juntas y los pilotes de las esquinas.
	ci.draw_rect(r.grow(1.0), OUTLINE)
	ci.draw_rect(r, LIGHT_WOOD.darkened(0.08))
	var horizontal := absf(_down.y) > 0.5
	for i in range(1, 7):
		var t := float(i) / 7.0
		if horizontal:
			var y := r.position.y + r.size.y * t
			ci.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), DARK_WOOD.lightened(0.1), 1.0)
		else:
			var x := r.position.x + r.size.x * t
			ci.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), DARK_WOOD.lightened(0.1), 1.0)
	for p in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
		_disc(ci, (p as Vector2).lerp(r.get_center(), 0.06), m * 0.045, DARK_WOOD, OUTLINE, 1.0)
	# El ahumadero (arriba a la izquierda) con su chimenea de piedra.
	var hut := Rect2(r.position + r.size * Vector2(0.06, 0.08), r.size * Vector2(0.5, 0.42))
	_gable(ci, hut, m * 0.12, TILE_RED, WOOD, true)
	var chimney := r.position + r.size * Vector2(0.2, 0.08)
	_cyl(ci, chimney - _down * m * 0.1, m * 0.05, m * 0.1, STONE, CONCRETE_DARK)
	# El tendedero (arriba a la derecha): dos postes, la cuerda y tres peces.
	var a := r.position + r.size * Vector2(0.64, 0.16)
	var b := r.position + r.size * Vector2(0.92, 0.16)
	var ta := _mast(ci, a, m * 0.2, DARK_WOOD, 2.0)
	var tb := _mast(ci, b, m * 0.2, DARK_WOOD, 2.0)
	ci.draw_line(ta, tb, OUTLINE, 1.5)
	for k in 3:
		var hang: Vector2 = ta.lerp(tb, 0.22 + 0.28 * float(k))
		_fish_2d(ci, hang + _down * m * 0.06, m * 0.05, STEEL.lightened(0.1), _down)
	# La barca boca arriba en la tarima (abajo): casco de madera, franja roja.
	var boat := r.position + r.size * Vector2(0.42, 0.74)
	var hull := PackedVector2Array()
	for i in 16:
		var ang := TAU * float(i) / 16.0
		var k2 := 1.0 if cos(ang) > 0.0 else 0.82
		hull.append(boat + Vector2(cos(ang) * r.size.x * 0.3 * k2, sin(ang) * r.size.y * 0.1))
	_poly(ci, hull, WOOD, OUTLINE, 1.2)
	ci.draw_line(boat - Vector2(r.size.x * 0.24, 0), boat + Vector2(r.size.x * 0.27, 0), RED, 2.0)
	ci.draw_line(boat + Vector2(-r.size.x * 0.05, -r.size.y * 0.09), boat + Vector2(r.size.x * 0.12, r.size.y * 0.12), LIGHT_WOOD, 1.6)
	# Barriles de pescado y una cesta con la pesca.
	for p in [Vector2(0.82, 0.58), Vector2(0.9, 0.7)]:
		_cyl(ci, r.position + r.size * (p as Vector2), m * 0.06, m * 0.07, DARK_WOOD.lightened(0.15), DARK_WOOD)
	var basket := r.position + r.size * Vector2(0.8, 0.88)
	_disc(ci, basket, m * 0.07, LIGHT_WOOD, OUTLINE, 1.0)
	_fish_2d(ci, basket + Vector2(-m * 0.02, -m * 0.01), m * 0.035, STEEL, Vector2.RIGHT)
	_fish_2d(ci, basket + Vector2(m * 0.02, m * 0.02), m * 0.035, BRASS_LIGHT, Vector2.LEFT)

## Un pez de juguete visto desde arriba: cuerpo oval y cola en V hacia `dir`
## (la cola va al lado contrario del morro).
static func _fish_2d(ci: CanvasItem, c: Vector2, s: float, col: Color, dir: Vector2) -> void:
	var d := dir.normalized()
	var side := Vector2(-d.y, d.x)
	var body := PackedVector2Array()
	for i in 10:
		var ang := TAU * float(i) / 10.0
		body.append(c + d * cos(ang) * s * 1.4 + side * sin(ang) * s * 0.6)
	var tail := c - d * s * 1.3
	_poly(ci, PackedVector2Array([tail, tail - d * s * 0.7 + side * s * 0.6, tail - d * s * 0.7 - side * s * 0.6]), col.darkened(0.2), OUTLINE, 1.0)
	_poly(ci, body, col, OUTLINE, 1.0)
	_dot(ci, c + d * s * 0.8 + side * s * 0.15, maxf(0.8, s * 0.15), IRON)

## El banco de peces en 2D (repasado en feat/vista2d-y-prologo): antes era un
## ovalo claro con borde y el centro oscuro, y sobre la arena parecia un charco.
## Ahora no tiene borde: es agua (la isla abre una cala en la arena encima,
## Island2D.set_sand_holes) con una mancha honda difusa, ondas en corro, las
## sombras de los peces bajo el agua, unos pocos lomos que asoman con su
## estela, el pez que salta (lo exagerado) y la boya roja y blanca.
static func _dep_fish_shoal(ci: CanvasItem, r: Rect2, rng: RandomNumberGenerator) -> void:
	var c := r.get_center()
	var m := minf(r.size.x, r.size.y)
	# Lo hondo: tres capas cada vez mas pequenas y opacas, sin contorno.
	for i in 3:
		var t := float(i) / 2.0
		ci.draw_colored_polygon(_dep_oval(c, r.size.x * (0.48 - 0.12 * t), r.size.y * (0.44 - 0.11 * t), rng), Color(SKY.darkened(0.45), 0.18 + 0.12 * t))
	# Ondas: arcos claros alrededor del corro (el agua se mueve donde hay peces).
	for k in 3:
		var rr := m * (0.22 + 0.11 * float(k))
		var a0 := rng.randf() * TAU
		for j in 3:
			var from := a0 + TAU * float(j) / 3.0
			var arc := PackedVector2Array()
			for s in 7:
				var a := from + 1.3 * float(s) / 6.0
				arc.append(c + Vector2(cos(a) * rr * (r.size.x / m), sin(a) * rr * 0.75 * (r.size.y / m)))
			ci.draw_polyline(arc, Color(CREAM, 0.55 - 0.13 * float(k)), maxf(1.0, m * 0.018))
	# Las sombras de los peces, bajo el agua, nadando en corro.
	var n := 6 + int(r.size.x * r.size.y / (m * m))
	for k in n:
		var ang := TAU * float(k) / float(n) + rng.randf_range(-0.25, 0.25)
		var rad := rng.randf_range(0.12, 0.3)
		var p := c + Vector2(cos(ang) * r.size.x * rad, sin(ang) * r.size.y * rad * 0.9)
		var heading := Vector2.from_angle(ang + PI * 0.5)
		_fish_shadow(ci, p, m * rng.randf_range(0.04, 0.055), heading)
	# Tres lomos que asoman, con su estela de espuma.
	for k in 3:
		var ang := TAU * float(k) / 3.0 + rng.randf()
		var p := c + Vector2(cos(ang) * r.size.x * 0.2, sin(ang) * r.size.y * 0.18)
		var heading := Vector2.from_angle(ang + PI * 0.5)
		ci.draw_polyline(PackedVector2Array([p - heading * m * 0.06, p - heading * m * 0.13 + Vector2(-heading.y, heading.x) * m * 0.02, p - heading * m * 0.2]), Color(CREAM, 0.7), maxf(1.0, m * 0.02))
		_fish_2d(ci, p, m * 0.05, STEEL.lightened(rng.randf_range(0.05, 0.25)), heading)
	# El que salta: en arco por encima del agua, con su sombra y salpicadura.
	var jump := c + Vector2(rng.randf_range(-0.15, 0.15) * r.size.x, rng.randf_range(0.0, 0.12) * r.size.y)
	_dot(ci, jump, m * 0.08, Color(IRON, 0.25))
	for k in 5:
		var ang := TAU * float(k) / 5.0
		_dot(ci, jump + Vector2(cos(ang), sin(ang) * 0.6) * m * 0.1, maxf(1.0, m * 0.018), CREAM)
	_fish_2d(ci, jump + Vector2(0, -m * 0.16), m * 0.08, BRASS_LIGHT, Vector2(1, -0.5))
	# La boya, con su onda.
	var buoy := r.position + r.size * Vector2(0.84, 0.18)
	_dot(ci, buoy + Vector2(0, m * 0.02), m * 0.075, Color(CREAM, 0.35))
	_cyl(ci, buoy, m * 0.05, m * 0.05, CREAM, RED)
	_mast(ci, buoy, m * 0.12, IRON, 1.5)

## La sombra de un pez bajo el agua: el mismo cuerpo que _fish_2d, oscuro y
## translucido, sin contorno.
static func _fish_shadow(ci: CanvasItem, c: Vector2, s: float, dir: Vector2) -> void:
	var d := dir.normalized()
	var side := Vector2(-d.y, d.x)
	var body := PackedVector2Array()
	for i in 8:
		var ang := TAU * float(i) / 8.0
		body.append(c + d * cos(ang) * s * 1.4 + side * sin(ang) * s * 0.55)
	var col := Color(SKY.darkened(0.7), 0.55)
	ci.draw_colored_polygon(body, col)
	var tail := c - d * s * 1.3
	ci.draw_colored_polygon(PackedVector2Array([tail, tail - d * s * 0.7 + side * s * 0.55, tail - d * s * 0.7 - side * s * 0.55]), col)
