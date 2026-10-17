extends RefCounted
## Los tonos de todo lo que rodea a los edificios en la maqueta: obra, andamio,
## ruina, atrezo de las parcelas, calzada y la gente que anda. Ninguno es un
## color nuevo: cada uno es una casilla de ToyPalette, aclarada u oscurecida con
## `ToyPalette.tint()`. Asi el borde de una parcela, la valla de una obra y el
## casco de un obrero son del mismo juego que el edificio horneado de al lado.
##
## La tabla es por papel ("wood", "brick", "pave"...), no por casilla: quien
## pinta pide lo que es, y si mañana la madera de la maqueta cambia de tono,
## cambia en un solo sitio.

const Palette := preload("res://scripts/buildings/ToyPalette.gd")
const S := Palette.Slot

## papel -> [casilla, matiz (-0.4..0.25)].
const TABLE := {
	# Madera
	"wood": [S.WOOD, 0.0], "wood_light": [S.WOOD, 0.2], "wood_dark": [S.WOOD, -0.32],
	"log": [S.WOOD, -0.12], "log_end": [S.CREAM, -0.12], "crate": [S.WOOD, 0.1],
	"sawdust": [S.CREAM, -0.06],
	# Hierro y acero
	"iron": [S.IRON, 0.0], "coal": [S.IRON, -0.25], "char": [S.IRON, -0.3],
	"scorch": [S.IRON, -0.12], "border": [S.IRON, -0.2],
	"steel": [S.SLATE, 0.0], "sheet": [S.SLATE, 0.16], "steel_light": [S.SLATE, 0.24],
	# Teja, ladrillo, cobre
	"brick": [S.TERRACOTTA, -0.14], "copper": [S.TERRACOTTA, -0.1], "rust": [S.TERRACOTTA, -0.34],
	"terracotta": [S.TERRACOTTA, 0.0],
	# Laton y senal
	"brass": [S.BRASS, 0.0], "gold": [S.BRASS, 0.14], "hazard": [S.BRASS, 0.04],
	# Piedra y tierra
	"stone": [S.STONE, 0.0], "stone_light": [S.STONE, 0.04], "stone_dark": [S.STONE, -0.18],
	"concrete": [S.STONE, -0.06], "concrete_dark": [S.SLATE, 0.06], "gravel": [S.STONE, -0.12],
	"rubble": [S.STONE, -0.3], "dirt": [S.WOOD, -0.08], "soil": [S.WOOD, -0.36],
	"ore": [S.WOOD, -0.2],
	# Tela
	"cream": [S.CREAM, 0.0], "canvas": [S.CREAM, -0.04], "sack": [S.CREAM, -0.12],
	"sandbag": [S.STONE, -0.04],
	# Verde
	"leaf": [S.GREEN, 0.0], "leaf_dark": [S.GREEN, -0.2], "grass": [S.GREEN, -0.1],
	"olive": [S.GREEN, -0.4],
	# Acentos
	"red": [S.RED, 0.0], "drum": [S.RED, -0.1], "sky": [S.SKY, 0.0], "glass": [S.SKY, 0.16],
	"navy": [S.SKY, -0.32],
	# Sin luz (ventanas, brasas, faroles): van a la superficie de brillo.
	"warm": [S.GLOW, 0.0], "ember": [S.TERRACOTTA, 0.16], "blue_light": [S.SKY, 0.24],
	# Calzada
	"pave": [S.STONE, -0.4], "pave_dark": [S.STONE, -0.52], "curb": [S.CREAM, -0.08],
	"curb_dark": [S.STONE, 0.0], "line": [S.BRASS, 0.0],
	# Piel (figuritas)
	"skin_light": [S.WOOD, 0.36], "skin_dark": [S.WOOD, -0.12],
}

## El tono de un papel. Uno que no este en la tabla sale en piedra (y avisa).
static func of(role: String) -> Color:
	var row = TABLE.get(role)
	if row == null:
		push_warning("ToyTones: papel desconocido '%s'" % role)
		return Palette.color(S.STONE)
	return Palette.tint(int(row[0]), float(row[1]))

## Un color suelto de una tabla de GameConfig (acento de parcela, lona,
## banderin, grua) llevado a la paleta con la misma regla del horneado
## (ToyPalette.slot_of + shade). Los rojos muy vivos van al rojo valvula, y el
## "cristal oscuro" de slot_of (que en un modelo es ventana) se queda en pizarra.
static func snap(c: Color) -> Color:
	var slot := Palette.slot_of(c)
	if slot == S.TERRACOTTA and c.s > 0.72:
		slot = S.RED
	elif slot == S.GLOW:
		slot = S.SLATE
	return Palette.tint(slot, Palette.shade(c) * 0.35)

## Si el material solido de la maqueta trata el color por vertice como sRGB.
## Los shaders propios (grua, banderin, figuritas) lo leen para pintar igual.
static func vertex_color_is_srgb() -> bool:
	var m := Palette.solid_material()
	return m is BaseMaterial3D and (m as BaseMaterial3D).vertex_color_is_srgb
