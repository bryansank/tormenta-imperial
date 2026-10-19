extends RefCounted
## La bandera del pais, dibujada por codigo a partir de una receta de piezas:
##
##   {"pattern": "bands_h", "emblem": "gear", "colors": ["brass", "ivory", "crimson"]}
##
## `pattern` es el fondo (GameConfig.COLONY_PATTERNS, uno o dos colores),
## `emblem` lo que va encima (GameConfig.COLONY_EMBLEMS, "none" = nada) y
## `colors` tres ids de GameConfig.colony_colors: fondo 1, fondo 2 y emblema.
## Todo es geometria propia (circulos, cajas, poligonos): ningun dibujo de otro
## juego ni simbolos reales.
##
## Una sola fuente para todo lo que la ensena: la insignia del HUD, el editor
## (ColonyIdentityPanel), los partes, el mastil del Nucleo y de los Cuarteles
## (3D y 2D) y la lista de partidas guardadas, que la pinta desde el indice con
## `draw_spec()` sin cargar la partida.
##
## Siempre bonita: `fix_spec()` cambia el segundo color si se confunde con el
## primero y el del emblema si no se lee sobre lo que tiene debajo, y el emblema
## lleva un contorno fino del tono opuesto. El editor solo deja elegir colores
## que pasan (`fields_distinct()` / `emblem_legible()`).
##
## Rendimiento: cada imagen se genera UNA vez por receta y tamano y se guarda en
## cache (`texture()`); nada se repinta por frame. 96x64 con 2x2 muestras por
## pixel para el mapa y el HUD, 48x32 con una muestra para las miniaturas.
##
## Se carga por preload (sin class_name), como PlacementRules.

const W := 96
const H := 64
## Lo pequeno: listas de partidas, insignia del HUD, miniaturas del editor.
const SMALL_W := 48
const SMALL_H := 32
const BORDER_DARKEN := 0.55
## Contraste minimo (WCAG) del emblema contra cada color que tiene debajo.
const EMBLEM_MIN_CONTRAST := 1.9
## Dos colores de fondo se distinguen si su contraste llega a esto, o si sus
## tonos estan lejos (y los dos tienen color).
const FIELD_MIN_CONTRAST := 1.35
const FIELD_MIN_HUE := 0.16
const CACHE_MAX := 96

## Cada fondo: cuantos colores usa, donde va el emblema (centro en u,v de 0 a 1),
## su tamano (fraccion del alto) y sobre que colores del fondo cae ("on").
const PATTERNS := {
	"plain": {"fields": 1, "at": Vector2(0.5, 0.5), "size": 0.62, "on": [0]},
	"bands_h": {"fields": 2, "at": Vector2(0.5, 0.5), "size": 0.42, "on": [1]},
	"bands_v": {"fields": 2, "at": Vector2(0.5, 0.5), "size": 0.5, "on": [1]},
	"halves_h": {"fields": 2, "at": Vector2(0.5, 0.5), "size": 0.6, "on": [0, 1]},
	"cross": {"fields": 2, "at": Vector2(0.145, 0.2), "size": 0.32, "on": [0]},
	"border": {"fields": 2, "at": Vector2(0.5, 0.5), "size": 0.56, "on": [0]},
	"diagonal": {"fields": 2, "at": Vector2(0.5, 0.5), "size": 0.58, "on": [0, 1]},
	"saltire": {"fields": 2, "at": Vector2(0.5, 0.5), "size": 0.5, "on": [0, 1]},
	"quartered": {"fields": 2, "at": Vector2(0.5, 0.5), "size": 0.58, "on": [0, 1]},
	"canton": {"fields": 2, "at": Vector2(0.21, 0.25), "size": 0.38, "on": [1]},
	"hoist_triangle": {"fields": 2, "at": Vector2(0.15, 0.5), "size": 0.3, "on": [1]},
	"stripes": {"fields": 2, "at": Vector2(0.5, 0.5), "size": 0.6, "on": [0, 1]},
	"waves": {"fields": 2, "at": Vector2(0.5, 0.3), "size": 0.36, "on": [0]},
	"checks": {"fields": 2, "at": Vector2(0.5, 0.5), "size": 0.5, "on": [0]},
}

static var _cache := {}
static var _polys := {}

## Los edificios con mastil y bandera del pais (3D y 2D), ademas del Nucleo.
## Desde 2026-10-18 (Bryan) solo los Cuarteles: el Cuartel General ya no la
## lleva. Con Cuarteles sin tope puede haber muchas: todas comparten malla,
## material y shader (ColonyFlag3D) y ninguna tiene _process.
const FLAG_BUILDINGS := ["barracks"]

static func flies_over(data: BuildingData) -> bool:
	return data != null and (data.is_core or data.id in FLAG_BUILDINGS)

# ── Recetas ──

## Copia limpia de una receta: claves que falten o piezas desconocidas pasan a
## las de serie, siempre tres colores. No mira el rango ni la legibilidad.
static func normalized(spec: Dictionary) -> Dictionary:
	var def: Dictionary = GameConfig.COLONY_DEFAULT_SPEC
	var pattern := String(spec.get("pattern", def["pattern"]))
	if not (pattern in GameConfig.COLONY_PATTERNS):
		pattern = def["pattern"]
	var emblem := String(spec.get("emblem", def["emblem"]))
	if not (emblem in GameConfig.COLONY_EMBLEMS):
		emblem = def["emblem"]
	var colors: Array = []
	var raw: Variant = spec.get("colors", [])
	for i in 3:
		var c := String(def["colors"][i])
		if raw is Array and i < (raw as Array).size():
			c = String(raw[i])
		if not GameConfig.colony_colors.has(c):
			c = String(def["colors"][i])
		colors.append(c)
	return {"pattern": pattern, "emblem": emblem, "colors": colors}

static func spec_key(spec: Dictionary) -> String:
	var s := normalized(spec)
	return "%s|%s|%s" % [s["pattern"], s["emblem"], ",".join(s["colors"])]

static func fields_of(pattern: String) -> int:
	return int(PATTERNS.get(pattern, PATTERNS["plain"])["fields"])

static func color_of(color_id: String) -> Color:
	return GameConfig.colony_colors.get(color_id, GameConfig.colony_colors["brass"])

## ¿Se distinguen dos colores de fondo?
static func fields_distinct(a_id: String, b_id: String) -> bool:
	if a_id == b_id:
		return false
	var a := color_of(a_id)
	var b := color_of(b_id)
	if UITheme.contrast_ratio(a, b) >= FIELD_MIN_CONTRAST:
		return true
	var dh := absf(a.h - b.h)
	dh = minf(dh, 1.0 - dh)
	return dh >= FIELD_MIN_HUE and a.s > 0.3 and b.s > 0.3

## Los colores que tiene debajo el emblema con este fondo.
static func colors_under_emblem(pattern: String, colors: Array) -> Array:
	var out: Array = []
	for idx in PATTERNS.get(pattern, PATTERNS["plain"])["on"]:
		out.append(String(colors[int(idx)]))
	return out

## Contraste mas bajo del color `emblem_color` contra lo que tendria debajo.
static func emblem_contrast(pattern: String, colors: Array, emblem_color: String) -> float:
	var worst := 21.0
	for under in colors_under_emblem(pattern, colors):
		worst = minf(worst, UITheme.contrast_ratio(color_of(emblem_color), color_of(under)))
	return worst

static func emblem_legible(pattern: String, colors: Array, emblem_color: String) -> bool:
	return emblem_contrast(pattern, colors, emblem_color) >= EMBLEM_MIN_CONTRAST

## Arregla una receta para que quede bonita, eligiendo entre `allowed` (ids de
## color; vacio = todos): si el fondo 2 se confunde con el 1, el que mas
## contrasta; si el emblema no se lee, el que mejor se lee. Determinista e
## idempotente: una receta ya buena sale igual.
static func fix_spec(spec: Dictionary, allowed: Array = []) -> Dictionary:
	var s := normalized(spec)
	var pool: Array = allowed if not allowed.is_empty() else GameConfig.COLONY_COLOR_ORDER
	var colors: Array = s["colors"]
	if fields_of(s["pattern"]) == 2 and not fields_distinct(colors[0], colors[1]):
		var best := String(colors[1])
		var best_score := -1.0
		for c in pool:
			if c == colors[0]:
				continue
			var score := UITheme.contrast_ratio(color_of(c), color_of(colors[0]))
			if fields_distinct(colors[0], c):
				score += 100.0
			if score > best_score:
				best_score = score
				best = c
		colors[1] = best
	if s["emblem"] != "none" and not emblem_legible(s["pattern"], colors, colors[2]):
		var best := String(colors[2])
		var best_score := emblem_contrast(s["pattern"], colors, colors[2])
		for c in pool:
			var score := emblem_contrast(s["pattern"], colors, c)
			if score > best_score + 0.001:
				best_score = score
				best = c
		colors[2] = best
	s["colors"] = colors
	return s

# ── Texturas ──

## Textura de una receta, cacheada por receta y tamano.
static func texture(spec: Dictionary, w: int = W, h: int = H) -> Texture2D:
	var key := "%s@%dx%d" % [spec_key(spec), w, h]
	if _cache.has(key):
		return _cache[key]
	if _cache.size() >= CACHE_MAX:
		_cache.clear()
	var ss := 2 if w >= W else 1
	var tex := ImageTexture.create_from_image(make_image(spec, w, h, ss))
	_cache[key] = tex
	return tex

## La pequena (48x32), para listas y el HUD.
static func small_texture(spec: Dictionary) -> Texture2D:
	return texture(spec, SMALL_W, SMALL_H)

## La bandera del pais de esta partida.
static func current_texture() -> Texture2D:
	return texture(RankManager.get_flag_spec())

static func current_small_texture() -> Texture2D:
	return small_texture(RankManager.get_flag_spec())

## Pinta la bandera de `spec` en `rect` de cualquier CanvasItem (desde su
## _draw). Para la lista de partidas: lee la receta del indice y no carga nada.
static func draw_spec(canvas_item: CanvasItem, rect: Rect2, spec: Dictionary) -> void:
	var big := rect.size.x > float(SMALL_W) * 1.25
	var tex := texture(spec) if big else small_texture(spec)
	canvas_item.draw_texture_rect(tex, rect, false)

static func clear_cache() -> void:
	_cache.clear()

## La imagen de una receta. `ss` = muestras por lado en cada pixel (suavizado).
static func make_image(spec: Dictionary, w: int = W, h: int = H, ss: int = 2) -> Image:
	var s := normalized(spec)
	var pattern: String = s["pattern"]
	var emblem: String = s["emblem"]
	var c0 := color_of(s["colors"][0])
	var c1 := color_of(s["colors"][1]) if fields_of(pattern) == 2 else c0
	var ce := color_of(s["colors"][2])
	var info: Dictionary = PATTERNS.get(pattern, PATTERNS["plain"])
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var n := maxi(1, ss)
	var inv := 1.0 / float(n * n)
	# El emblema: cuadrado de lado `size * h` centrado en `at`.
	var radius: float = float(info["size"]) * float(h) * 0.5
	var center := Vector2(float(info["at"].x) * float(w), float(info["at"].y) * float(h))
	var cover := PackedFloat32Array()
	cover.resize(w * h)
	for y in range(h):
		for x in range(w):
			var mix := 0.0
			var hit := 0.0
			var near := emblem != "none" and absf(x + 0.5 - center.x) <= radius + 1.0 \
				and absf(y + 0.5 - center.y) <= radius + 1.0
			for sy in n:
				for sx in n:
					var px := float(x) + (float(sx) + 0.5) / float(n)
					var py := float(y) + (float(sy) + 0.5) / float(n)
					mix += float(_field(pattern, px / float(w), py / float(h)))
					if near and _emblem_hit(emblem, Vector2((px - center.x) / radius, (py - center.y) / radius)):
						hit += 1.0
			cover[y * w + x] = hit * inv
			img.set_pixel(x, y, c0.lerp(c1, mix * inv))
	if emblem != "none":
		# Contorno de un pixel del tono opuesto: se lee sobre cualquier fondo.
		var outline := Color(0.10, 0.09, 0.08) if UITheme.contrast_ratio(ce, Color.BLACK) > 6.0 else Color(0.96, 0.92, 0.82)
		for y in range(h):
			for x in range(w):
				var cov: float = cover[y * w + x]
				var dil := cov
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						var nx := x + ox
						var ny := y + oy
						if nx >= 0 and ny >= 0 and nx < w and ny < h:
							dil = maxf(dil, cover[ny * w + nx])
				if dil <= 0.0:
					continue
				var c := img.get_pixel(x, y).lerp(outline, dil * 0.85)
				img.set_pixel(x, y, c.lerp(ce, cov))
	# Ribete oscuro de un pixel: se recorta sobre cualquier fondo.
	var dark := c0.darkened(BORDER_DARKEN)
	for x in range(w):
		img.set_pixel(x, 0, dark)
		img.set_pixel(x, h - 1, dark)
	for y in range(h):
		img.set_pixel(0, y, dark)
		img.set_pixel(w - 1, y, dark)
	return img

# ── Fondos: 0 = color 1, 1 = color 2, en (u, v) de 0 a 1 ──

static func _field(pattern: String, u: float, v: float) -> int:
	match pattern:
		"plain":
			return 0
		"bands_h":
			return 1 if absf(v - 0.5) < 0.25 else 0
		"bands_v":
			return 1 if absf(u - 0.5) < 0.2 else 0
		"halves_h":
			return 0 if v < 0.5 else 1
		"cross":
			# Cruz nordica: el brazo vertical, hacia el mastil.
			return 1 if absf(v - 0.5) < 0.1 or absf(u - 0.36) < 0.067 else 0
		"border":
			return 1 if u < 0.08 or u > 0.92 or v < 0.12 or v > 0.88 else 0
		"diagonal":
			return 0 if u + v < 1.0 else 1
		"saltire":
			# Aspa: las dos diagonales, con el mismo grosor en pixeles.
			var d1 := absf(u - v) * 1.5 / 1.803
			var d2 := absf(u + v - 1.0) * 1.5 / 1.803
			return 1 if minf(d1, d2) < 0.075 else 0
		"quartered":
			return 1 if (u < 0.5) != (v < 0.5) else 0
		"canton":
			return 1 if u < 0.42 and v < 0.5 else 0
		"hoist_triangle":
			return 1 if u < 0.45 * (1.0 - absf(v - 0.5) * 2.0) else 0
		"stripes":
			return int(floor(v * 5.0)) % 2
		"waves":
			var edge := 0.62 + 0.06 * sin(u * TAU * 2.5)
			if v < edge:
				return 0
			return 0 if v > edge + 0.12 and v < edge + 0.18 else 1
		"checks":
			# Ajedrezado de 6x4 con un disco liso en el centro para el emblema.
			if Vector2((u - 0.5) * 1.5, v - 0.5).length() < 0.3:
				return 0
			return (int(floor(u * 6.0)) + int(floor(v * 4.0))) % 2
	return 0

# ── Emblemas: q en [-1, 1] (x a la derecha, y hacia abajo) ──

static func _emblem_hit(emblem: String, q: Vector2) -> bool:
	if absf(q.x) > 1.0 or absf(q.y) > 1.0:
		return false
	match emblem:
		"gear":
			return _gear(q, Vector2.ZERO, 1.0, 8, 0.3)
		"cogs":
			return _gear(q, Vector2(-0.3, 0.22), 0.7, 8, 0.22) or _gear(q, Vector2(0.52, -0.5), 0.46, 6, 0.15)
		"anchor":
			var ring := (q - Vector2(0, -0.74)).length()
			if ring < 0.2 and ring > 0.09:
				return true
			if absf(q.x) < 0.08 and q.y > -0.56 and q.y < 0.8:
				return true
			if absf(q.x) < 0.42 and absf(q.y + 0.38) < 0.07:
				return true
			var arc := (q - Vector2(0, 0.1)).length()
			if q.y > 0.28 and absf(arc - 0.66) < 0.085:
				return true
			return _in_poly(q, "anchor_l") or _in_poly(q, "anchor_r")
		"wheat":
			if absf(q.x) < 0.055 and q.y > -0.6 and q.y < 0.95:
				return true
			if _ellipse(q, Vector2(0, -0.76), 0.1, 0.2, 0.0):
				return true
			for i in 4:
				var y := -0.5 + 0.25 * float(i)
				if _ellipse(q, Vector2(-0.19, y), 0.22, 0.095, 0.6) or _ellipse(q, Vector2(0.19, y), 0.22, 0.095, -0.6):
					return true
			return false
		"hammer":
			var p := q.rotated(deg_to_rad(-35.0))
			if absf(p.x) < 0.55 and p.y > -0.82 and p.y < -0.45:
				return true
			return absf(p.x) < 0.11 and p.y > -0.45 and p.y < 0.92
		"tower":
			if absf(q.x) < 0.16 and (q.y > 0.45 or (q - Vector2(0, 0.45)).length() < 0.16):
				return false
			if absf(q.x) < 0.07 and q.y > -0.2 and q.y < 0.12:
				return false
			if absf(q.x) < 0.46 and q.y > -0.4 and q.y < 0.92:
				return true
			if absf(q.x) < 0.58 and q.y > 0.76 and q.y < 0.92:
				return true
			if q.y > -0.7 and q.y <= -0.4:
				return absf(q.x + 0.34) < 0.12 or absf(q.x) < 0.12 or absf(q.x - 0.34) < 0.12
			return false
		"star":
			return _in_poly(q, "star")
		"wrench":
			var p := q.rotated(deg_to_rad(45.0))
			if absf(p.x) < 0.12 and p.y > -0.35 and p.y < 0.62:
				return true
			var head := (p - Vector2(0, -0.58)).length()
			if head < 0.36 and not (absf(p.x) < 0.13 and p.y < -0.5):
				return true
			var tail := (p - Vector2(0, 0.72)).length()
			return tail < 0.22 and tail > 0.09
		"wheel":
			var r := q.length()
			if absf(r - 0.6) < 0.1 or r < 0.2:
				return true
			var a := atan2(q.y, q.x)
			var k := roundf(a / (PI / 4.0))
			var spoke := a - k * PI / 4.0
			if r < 0.84 and r * absf(sin(spoke)) < 0.065:
				return true
			return (q - Vector2(cos(k * PI / 4.0), sin(k * PI / 4.0)) * 0.88).length() < 0.12
		"ship":
			if _in_poly(q, "hull"):
				return true
			if q.x > -0.55 and q.x < 0.35 and q.y > -0.05 and q.y < 0.22:
				return true
			if q.x > -0.2 and q.x < 0.08 and q.y > -0.56 and q.y < 0.0:
				return true
			if q.x > 0.45 and q.x < 0.52 and q.y > -0.42 and q.y < 0.0:
				return true
			return (q - Vector2(0.2, -0.7)).length() < 0.14 or (q - Vector2(0.46, -0.86)).length() < 0.11
		"sun":
			var r := q.length()
			if r < 0.42:
				return true
			if r < 0.54 or r > 0.98:
				return false
			var t := fposmod(atan2(q.y, q.x) / TAU * 12.0, 1.0)
			var tri := 1.0 - absf(t - 0.5) * 2.0
			return tri > 0.35 + 0.65 * (r - 0.54) / 0.44
		"airship":
			if _ellipse(q, Vector2(0.06, -0.2), 0.86, 0.4, 0.0):
				return true
			if _in_poly(q, "fin_up") or _in_poly(q, "fin_down"):
				return true
			if q.x > -0.3 and q.x < 0.25 and q.y > 0.3 and q.y < 0.5:
				return true
			if (absf(q.x + 0.2) < 0.04 or absf(q.x - 0.15) < 0.04) and q.y > 0.1 and q.y < 0.32:
				return true
			return q.x > -0.44 and q.x < -0.37 and q.y > 0.24 and q.y < 0.56
	return false

static func _gear(q: Vector2, c: Vector2, radius: float, teeth: int, hole: float) -> bool:
	var p := (q - c) / radius
	var r := p.length()
	if r > 1.0 or r < hole:
		return false
	if r < 0.74:
		return true
	var t := fposmod(atan2(p.y, p.x) / TAU * float(teeth), 1.0)
	return absf(t - 0.5) < 0.24

static func _ellipse(q: Vector2, c: Vector2, rx: float, ry: float, angle: float) -> bool:
	var p := (q - c).rotated(-angle)
	return (p.x * p.x) / (rx * rx) + (p.y * p.y) / (ry * ry) < 1.0

static func _in_poly(q: Vector2, poly_name: String) -> bool:
	if _polys.is_empty():
		_build_polys()
	return Geometry2D.is_point_in_polygon(q, _polys[poly_name])

static func _build_polys() -> void:
	var star := PackedVector2Array()
	for i in 16:
		var a := -PI / 2.0 + float(i) * TAU / 16.0
		var rr := 0.98 if i % 2 == 0 else 0.4
		if i % 4 == 2:
			rr = 0.7
		star.append(Vector2(cos(a), sin(a)) * rr)
	_polys["star"] = star
	_polys["anchor_l"] = PackedVector2Array([Vector2(-0.82, 0.44), Vector2(-0.48, 0.44), Vector2(-0.7, 0.12)])
	_polys["anchor_r"] = PackedVector2Array([Vector2(0.82, 0.44), Vector2(0.48, 0.44), Vector2(0.7, 0.12)])
	_polys["hull"] = PackedVector2Array([Vector2(-0.92, 0.2), Vector2(0.92, 0.2), Vector2(0.62, 0.62), Vector2(-0.66, 0.62)])
	_polys["fin_up"] = PackedVector2Array([Vector2(-0.6, -0.2), Vector2(-0.98, -0.66), Vector2(-0.92, -0.2)])
	_polys["fin_down"] = PackedVector2Array([Vector2(-0.6, -0.2), Vector2(-0.98, 0.26), Vector2(-0.92, -0.2)])
