extends RefCounted
## La bandera de la colonia, dibujada a mano pixel a pixel: seis disenos
## (GameConfig.COLONY_FLAGS) en el color que elija el jugador. Una sola fuente
## para todo lo que la ensena: la insignia del HUD, la galeria de ☰ MENU >
## COLONIA, el mastil del Nucleo (3D y 2D) y las fichas propias del tablero.
##
## Se carga por preload (sin class_name), como PlacementRules.

const W := 48
const H := 32
## El segundo color de todas las banderas: marfil de papel viejo.
const IVORY := Color(0.93, 0.87, 0.72)
const BORDER_DARKEN := 0.55

static var _cache := {}

## Textura de la bandera `flag_id` en `color`. Cacheada por diseno y color.
static func texture(flag_id: String, color: Color) -> Texture2D:
	var key := "%s|%s" % [flag_id, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var tex := ImageTexture.create_from_image(make_image(flag_id, color))
	_cache[key] = tex
	return tex

## La bandera de la colonia de esta partida.
static func current_texture() -> Texture2D:
	return texture(RankManager.get_flag(), RankManager.get_color())

static func make_image(flag_id: String, color: Color) -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var dark := color.darkened(BORDER_DARKEN)
	for y in range(H):
		for x in range(W):
			var c := _pixel(flag_id, x, y, color, dark)
			# Ribete oscuro de un pixel: se lee sobre cualquier fondo.
			if x == 0 or y == 0 or x == W - 1 or y == H - 1:
				c = dark
			img.set_pixel(x, y, c)
	return img

static func _pixel(flag_id: String, x: int, y: int, color: Color, dark: Color) -> Color:
	var u := (float(x) + 0.5) / float(W)
	var v := (float(y) + 0.5) / float(H)
	match flag_id:
		"plain":
			return color
		"band":
			return IVORY if absf(v - 0.5) < 0.17 else color
		"cross":
			# Cruz nordica: el brazo vertical, hacia el mastil.
			return IVORY if absf(v - 0.5) < 0.12 or absf(u - 0.36) < 0.08 else color
		"diagonal":
			return color if u + v * (float(H) / float(W)) * 1.5 < 1.0 else dark
		"gear":
			# Engranaje imperial: disco marfil con dientes y buje oscuro.
			var d := Vector2((u - 0.5) * float(W), (v - 0.5) * float(H)).length()
			var angle := atan2(v - 0.5, u - 0.5)
			var teeth := 0.5 + 0.5 * signf(sin(angle * 8.0))
			var outer := float(H) * (0.30 + 0.07 * teeth)
			if d < float(H) * 0.12:
				return dark
			if d < outer:
				return IVORY
			return color
		"chevron":
			# Galon: triangulo marfil desde el mastil.
			return IVORY if u < 0.45 * (1.0 - absf(v - 0.5) * 2.0) else color
	return color
