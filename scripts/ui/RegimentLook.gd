extends RefCounted
## El regimiento del jugador: nombre, color, emblema, pintura y estrellas.
## SOLO COSMETICO (doc 21 §5.1, docs/15 §12): nada de aqui cambia una cifra del
## combate, ni lo lee CombatRules, Encounter o la IA.
##
## Lo guardado (ArmyManager, clave "regiment" dentro de "army"):
##
##   {"name": "", "color": "", "emblem": "", "paint": "plain", "wins": 0}
##
## "" en color o emblema = "el de la bandera" (RankManager.get_flag_spec()),
## asi un regimiento sin tocar sigue a la colonia si esta cambia de bandera.
## `resolve()` convierte eso en lo que se pinta (el "aspecto"), cambiando por el
## de la bandera cualquier pieza que el rango todavia no abra. No se recorta al
## cargar: ArmyManager carga antes que RankManager, y el rango nunca baja.
##
## Piezas: los colores y emblemas son los de la bandera (abiertos por rango con
## rank_rewards "colors" / "emblems"); las pinturas tienen su propia clave
## "paints" en rank_rewards. Las estrellas salen de los combates ganados
## (GameConfig.regiment_star_wins).
##
## Rendimiento: la insignia (disco con emblema y estrellas) y las muestras de
## pintura se generan UNA vez por aspecto y se guardan en cache; nada por frame.
## Se carga por preload (sin class_name), como ColonyFlag.

const ColonyFlag := preload("res://scripts/ui/ColonyFlag.gd")
const ColonyIdentity := preload("res://scripts/services/ColonyIdentity.gd")

## Lado de la insignia (cuadrada): disco arriba, estrellas abajo.
const BADGE := 56
const DISC_RADIUS := 21.0
const DISC_CENTER := Vector2(28.0, 23.0)
const STAR_RADIUS := 6.5
const STAR_Y := 48.0
## Las muestras de pintura del Cuartel.
const PAINT_THUMB := 40
const CACHE_MAX := 48
const MAX_STARS := 3

## Para "al azar": forma + apellido. Palabras llanas del tono del juego.
const FORMS := {
	"es": ["Regimiento", "Batallón", "Brigada", "Guardia", "Columna", "Compañía"],
	"en": ["Regiment", "Battalion", "Brigade", "Guard", "Column", "Company"],
}
const TAILS := {
	"es": ["de Hierro", "del Vapor", "de Latón", "del Faro", "de la Niebla", "del Yunque",
		"de las Calderas", "del Carbón", "de la Bahía", "del Cerro", "de la Tormenta", "del Puerto"],
	"en": ["Iron", "Steam", "Brass", "Lighthouse", "Fog", "Anvil",
		"Boiler", "Coal", "Bay", "Ridge", "Storm", "Harbour"],
}

static var _badges := {}
static var _paints := {}
static var _star_poly := PackedVector2Array()

# ── Lo guardado ──

static func defaults() -> Dictionary:
	return {"name": "", "color": "", "emblem": "", "paint": "plain", "wins": 0}

## Copia limpia de lo guardado: claves que falten o piezas desconocidas pasan a
## las de serie. No mira el rango (eso es `resolve()`). Idempotente.
static func normalized(data: Variant) -> Dictionary:
	var out := defaults()
	if not (data is Dictionary):
		return out
	var d: Dictionary = data
	var reg_name := ColonyIdentity.clean_name(str(d.get("name", "")))
	if not reg_name.is_empty() and not ColonyIdentity.is_name_allowed(reg_name):
		reg_name = ""
	out["name"] = reg_name
	var color_id := str(d.get("color", ""))
	out["color"] = color_id if GameConfig.colony_colors.has(color_id) else ""
	var emblem := str(d.get("emblem", ""))
	out["emblem"] = emblem if emblem in GameConfig.COLONY_EMBLEMS else ""
	var paint := str(d.get("paint", "plain"))
	out["paint"] = paint if paint in GameConfig.REGIMENT_PAINTS else "plain"
	out["wins"] = maxi(0, int(d.get("wins", 0)))
	return out

## Estrellas por combates ganados: 0..3.
static func stars_for(wins: int) -> int:
	var n := 0
	for need in GameConfig.regiment_star_wins:
		if wins >= int(need):
			n += 1
	return mini(n, MAX_STARS)

## Combates ganados que faltan para la siguiente estrella (0 = ya tiene todas).
static func wins_to_next_star(wins: int) -> int:
	for need in GameConfig.regiment_star_wins:
		if wins < int(need):
			return int(need) - wins
	return 0

# ── Piezas por rango ──

static func paint_rank(paint: String) -> int:
	return ColonyIdentity.piece_rank("paints", paint)

static func is_paint_open(paint: String, rank: int, all: bool = false) -> bool:
	return ColonyIdentity.is_piece_open("paints", paint, rank, all)

## El rango que abre una pieza del regimiento (0 = ninguno).
static func piece_rank_of(kind: String, id: String) -> int:
	return ColonyIdentity.piece_rank(kind, id)

static func paint_index(paint: String) -> int:
	return maxi(0, GameConfig.REGIMENT_PAINTS.find(paint))

## ¿Se puede elegir esta pieza ("colors", "emblems", "paints") con este rango?
static func is_open(kind: String, id: String, rank: int, all: bool = false) -> bool:
	if kind == "paints":
		return is_paint_open(id, rank, all)
	return ColonyIdentity.is_piece_open(kind, id, rank, all)

# ── Lo que se pinta ──

## El aspecto del regimiento: lo guardado con lo de la bandera donde haga falta
## y con cada pieza cerrada por rango cambiada por la de la bandera (o liso).
## Devuelve: name (para ensenar), color_id, color, emblem, paint, paint_index,
## wins, stars.
static func resolve(regiment: Dictionary, rank: int, all: bool, flag_spec: Dictionary) -> Dictionary:
	var r := normalized(regiment)
	var flag := ColonyFlag.normalized(flag_spec)
	var color_id: String = r["color"]
	if color_id == "" or not ColonyIdentity.is_piece_open("colors", color_id, rank, all):
		color_id = String(flag["colors"][0])
	var emblem: String = r["emblem"]
	if emblem == "" or not ColonyIdentity.is_piece_open("emblems", emblem, rank, all):
		emblem = String(flag["emblem"])
	var paint: String = r["paint"]
	if not is_paint_open(paint, rank, all):
		paint = "plain"
	var wins: int = r["wins"]
	return {
		"name": display_name(r["name"]),
		"color_id": color_id,
		"color": ColonyFlag.color_of(color_id),
		"emblem": emblem,
		"paint": paint,
		"paint_index": paint_index(paint),
		"wins": wins,
		"stars": stars_for(wins),
	}

static func display_name(raw_name: String) -> String:
	return raw_name if not raw_name.is_empty() else Tr.t("REGIMENT_DEFAULT_NAME")

## Un nombre al azar ("Brigada del Faro" / "Lighthouse Brigade"). Misma semilla
## y mismo idioma, mismo nombre; siempre pasa el filtro del nombre del pais.
static func random_name(seed_value: int, locale: String = "es") -> String:
	var lang := locale if FORMS.has(locale) else "es"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var forms: Array = FORMS[lang]
	var tails: Array = TAILS[lang]
	for _try in 8:
		var form: String = forms[rng.randi() % forms.size()]
		var tail: String = tails[rng.randi() % tails.size()]
		var out := ("%s %s" % [form, tail]) if lang == "es" else ("%s %s" % [tail, form])
		if out.length() <= GameConfig.COLONY_NAME_MAX and ColonyIdentity.is_name_allowed(out):
			return out
	return String(forms[0])

# ── Insignia: disco del color con el emblema, y las estrellas debajo ──

static func badge_key(look: Dictionary, with_stars: bool = true) -> String:
	return "%s|%s|%d" % [String(look.get("color_id", "brass")), String(look.get("emblem", "none")),
		int(look.get("stars", 0)) if with_stars else 0]

## La insignia de un aspecto, cacheada. La comparten todas las fichas propias
## de una pelea (una sola textura) y la tarjeta del Cuartel.
static func badge_texture(look: Dictionary, with_stars: bool = true) -> Texture2D:
	var key := badge_key(look, with_stars)
	if _badges.has(key):
		return _badges[key]
	if _badges.size() >= CACHE_MAX:
		_badges.clear()
	var stars := int(look.get("stars", 0)) if with_stars else 0
	var tex := ImageTexture.create_from_image(
		make_badge_image(String(look.get("color_id", "brass")), String(look.get("emblem", "none")), stars))
	_badges[key] = tex
	return tex

## La imagen de la insignia (BADGE x BADGE, fondo transparente). El emblema lo
## dibuja ColonyFlag sobre un fondo liso del color, con su tinta arreglada para
## que se lea (fix_spec); aqui solo se recorta en disco con un ribete oscuro.
static func make_badge_image(color_id: String, emblem: String, stars: int) -> Image:
	var fill := ColonyFlag.color_of(color_id)
	var disc_px := int(DISC_RADIUS * 2.0)
	var spec := ColonyFlag.fix_spec({"pattern": "plain", "emblem": emblem if emblem in GameConfig.COLONY_EMBLEMS else "none",
		"colors": [color_id, color_id, "ivory"]})
	var face := ColonyFlag.make_image(spec, disc_px, disc_px, 2)
	var rim := fill.darkened(0.55)
	var img := Image.create(BADGE, BADGE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var origin := DISC_CENTER - Vector2(DISC_RADIUS, DISC_RADIUS)
	for y in BADGE:
		for x in BADGE:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var d := p.distance_to(DISC_CENTER)
			var alpha := clampf(DISC_RADIUS - d + 0.5, 0.0, 1.0)
			if alpha <= 0.0:
				continue
			var c := rim
			if d < DISC_RADIUS - 2.5:
				var fx := clampi(int(p.x - origin.x), 1, disc_px - 2)
				var fy := clampi(int(p.y - origin.y), 1, disc_px - 2)
				c = face.get_pixel(fx, fy)
			c.a = alpha
			img.set_pixel(x, y, c)
	_draw_stars(img, clampi(stars, 0, MAX_STARS))
	return img

## Estrellas de laton con contorno oscuro, centradas bajo el disco.
static func _draw_stars(img: Image, count: int) -> void:
	if count <= 0:
		return
	if _star_poly.is_empty():
		for i in 10:
			var a := -PI / 2.0 + float(i) * TAU / 10.0
			var rr := 1.0 if i % 2 == 0 else 0.45
			_star_poly.append(Vector2(cos(a), sin(a)) * rr)
	var gold: Color = GameConfig.colony_colors.get("gold", Color(0.9, 0.68, 0.23))
	var ink := Color(0.13, 0.09, 0.05)
	var step := STAR_RADIUS * 2.1
	var x0 := DISC_CENTER.x - step * float(count - 1) * 0.5
	for s in count:
		var c := Vector2(x0 + step * float(s), STAR_Y)
		var r_out := STAR_RADIUS + 1.4
		for y in range(int(c.y - r_out) - 1, int(c.y + r_out) + 2):
			for x in range(int(c.x - r_out) - 1, int(c.x + r_out) + 2):
				if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
					continue
				var inner := 0.0
				var outer := 0.0
				for sy in 2:
					for sx in 2:
						var q := Vector2(float(x) + 0.25 + 0.5 * sx, float(y) + 0.25 + 0.5 * sy) - c
						if Geometry2D.is_point_in_polygon(q / STAR_RADIUS, _star_poly):
							inner += 0.25
						if Geometry2D.is_point_in_polygon(q / r_out, _star_poly):
							outer += 0.25
				if outer <= 0.0:
					continue
				var under := img.get_pixel(x, y)
				var col := under.lerp(ink, outer) if under.a > 0.0 else Color(ink, outer)
				col = col.lerp(gold, inner)
				col.a = maxf(under.a, outer)
				img.set_pixel(x, y, col)

# ── Pinturas: el mismo dibujo que regiment_paint.gdshader, en plano ──

## Una muestra de la pintura con el color del regimiento (la galeria del
## Cuartel). Cacheada por pintura y color.
static func paint_texture(paint: String, color_id: String) -> Texture2D:
	var key := "%s|%s" % [paint, color_id]
	if _paints.has(key):
		return _paints[key]
	if _paints.size() >= CACHE_MAX:
		_paints.clear()
	var base := ColonyFlag.color_of(color_id)
	var img := Image.create(PAINT_THUMB, PAINT_THUMB, false, Image.FORMAT_RGBA8)
	for y in PAINT_THUMB:
		for x in PAINT_THUMB:
			var p := Vector2(float(x), float(PAINT_THUMB - y)) / float(PAINT_THUMB) * 1.5
			img.set_pixel(x, y, paint_color(paint, base, p))
	var tex := ImageTexture.create_from_image(img)
	_paints[key] = tex
	return tex

## El color de la pintura en un punto (en metros del modelo, y hacia arriba).
## Pura: la prueba la fija. El shader hace lo mismo en 3D.
static func paint_color(paint: String, base: Color, p: Vector2) -> Color:
	match paint:
		"stripes":
			var t := fposmod((p.x + p.y * 0.6) * 2.6, 1.0)
			return base if t < 0.5 else base.darkened(0.5)
		"spots":
			var n := _noise(p * 3.2)
			if n > 0.58:
				return base.darkened(0.6).lerp(Color(0.2, 0.22, 0.12), 0.5)
			return base.lightened(0.15) if n < 0.32 else base
		"desert":
			var n := _noise(p * 2.6)
			if n > 0.62:
				return base
			return Color(0.5, 0.38, 0.25) if n < 0.3 else Color(0.8, 0.68, 0.46)
		"snow":
			var n := _noise(p * 2.6)
			if n > 0.62:
				return base
			return Color(0.6, 0.62, 0.66) if n < 0.28 else Color(0.92, 0.93, 0.96)
		"parade":
			return Color(0.85, 0.66, 0.28) if fposmod(p.y * 3.0, 1.0) < 0.18 else base
	return base

static func _hash(v: Vector2) -> float:
	return fposmod(sin(v.dot(Vector2(127.1, 311.7))) * 43758.5453, 1.0)

static func _noise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	f = f * f * (Vector2(3, 3) - 2.0 * f)
	var a := _hash(i)
	var b := _hash(i + Vector2(1, 0))
	var c := _hash(i + Vector2(0, 1))
	var d := _hash(i + Vector2(1, 1))
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)

static func clear_cache() -> void:
	_badges.clear()
	_paints.clear()
