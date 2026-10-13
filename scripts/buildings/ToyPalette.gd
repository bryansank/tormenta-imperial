extends RefCounted
## La paleta comun de la "maqueta" (docs/03, "Modelos: maqueta de juguete"):
## diez colores calidos y saturados que comparten TODOS los modelos 3D de
## edificios, el atrezo de las parcelas, las calzadas y los yacimientos.
##
## Las piezas CC0 (KayKit, Kenney) traen su propio atlas de degradados; el
## horneado (tools/build_toy_models.gd) muestrea ese atlas en cada vertice y lo
## pasa por `slot_of()` + `shade()`: el tono decide la casilla de la paleta y la
## luminosidad original solo matiza (mas claro / mas oscuro), asi que cada
## pieza conserva su volumen pero todas parecen del mismo juego. Las piezas
## propias (chimeneas, tuberias, valvulas) se pintan directamente con `color()`.
##
## Todo va en color por vertice con DOS materiales para todo el mapa
## (`solid_material()` con luz, `glow_material()` sin luz para ventanas,
## brasas y faroles): una o dos llamadas de dibujo por edificio.

enum Slot { CREAM, STONE, SLATE, IRON, WOOD, TERRACOTTA, RED, BRASS, GREEN, SKY, GLOW }

## La paleta: [nombre, color]. El indice es el Slot.
const COLORS := [
	Color8(242, 222, 180),  # CREAM: enlucido, yeso, lona clara
	Color8(186, 168, 140),  # STONE: piedra calida, bordillos, sillares
	Color8(96, 98, 110),    # SLATE: chapa, pizarra, acero pavonado
	Color8(58, 46, 42),     # IRON: hierro oscuro, carbon, remaches
	Color8(160, 98, 54),    # WOOD: madera, tablones, vigas
	Color8(210, 92, 58),    # TERRACOTTA: tejas, ladrillo
	Color8(220, 50, 38),    # RED: rojo valvula (acento industrial)
	Color8(232, 172, 58),   # BRASS: laton, oro, amarillo senal
	Color8(108, 172, 62),   # GREEN: hoja, cesped, setos
	Color8(78, 160, 204),   # SKY: agua, cristal, la luz del laboratorio
	Color8(255, 206, 110),  # GLOW: ventana encendida, farol (sin luz)
]

const NAMES := ["CREAM", "STONE", "SLATE", "IRON", "WOOD", "TERRACOTTA", "RED", "BRASS", "GREEN", "SKY", "GLOW"]

const SOLID_PATH := "res://assets/models/toy/toy_solid.tres"
const GLOW_PATH := "res://assets/models/toy/toy_glow.tres"

static var _solid: Material = null
static var _glow: Material = null

static func color(slot: int) -> Color:
	return COLORS[clampi(slot, 0, COLORS.size() - 1)]

static func slot_named(slot_name: String) -> int:
	return NAMES.find(slot_name.to_upper())

## El material con luz de todo lo horneado (color por vertice). Si el .tres
## no esta (pruebas sin importar), uno igual en memoria.
static func solid_material() -> Material:
	if _solid == null:
		if ResourceLoader.exists(SOLID_PATH):
			_solid = load(SOLID_PATH)
		else:
			_solid = make_solid()
	return _solid

static func glow_material() -> Material:
	if _glow == null:
		if ResourceLoader.exists(GLOW_PATH):
			_glow = load(GLOW_PATH)
		else:
			_glow = make_glow()
	return _glow

static func make_solid() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	# La paleta esta escrita en sRGB (Color8): sin esto el color por vertice se
	# leeria como lineal y todo saldria lavado, pastel en vez de calido.
	m.vertex_color_is_srgb = true
	m.roughness = 0.82
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	return m

static func make_glow() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

## La casilla de la paleta para un color muestreado de un atlas ajeno.
## Neutros por luminosidad; el resto por tono. Pura: la prueba la fija.
static func slot_of(c: Color) -> int:
	var h := c.h
	var s := c.s
	var v := c.v
	if v < 0.17:
		return Slot.IRON
	# Cristales y ventanas de los packs: azul marino oscuro -> ventana encendida.
	if h > 0.52 and h < 0.72 and s > 0.35 and v < 0.42:
		return Slot.GLOW
	if s < 0.16:
		if v > 0.82:
			return Slot.CREAM
		if v > 0.52:
			return Slot.STONE
		if v > 0.3:
			return Slot.SLATE
		return Slot.IRON
	if h < 0.035 or h > 0.92:
		return Slot.TERRACOTTA if v > 0.45 else Slot.WOOD
	if h < 0.105:
		# Naranjas y marrones: lo muy vivo y claro es teja, lo apagado madera.
		if s > 0.62 and v > 0.78:
			return Slot.TERRACOTTA
		if s < 0.42 and v > 0.72:
			return Slot.CREAM
		return Slot.WOOD
	if h < 0.18:
		return Slot.BRASS if s > 0.4 else Slot.STONE
	if h < 0.47:
		return Slot.GREEN
	if h < 0.72:
		return Slot.SKY if (s > 0.45 and v > 0.55) else Slot.SLATE
	return Slot.SLATE

## Matiz de luminosidad (-0.25..0.2) que conserva el degradado del original.
static func shade(c: Color) -> float:
	return clampf((c.v - 0.6) * 0.55, -0.25, 0.2)

## El color final de una casilla con su matiz.
static func tint(slot: int, delta: float) -> Color:
	var p := color(slot)
	if slot == Slot.GLOW:
		return p
	return p.lightened(delta) if delta >= 0.0 else p.darkened(-delta)
