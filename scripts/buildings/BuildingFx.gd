extends RefCounted
## Los efectos animados de los edificios (humo, serrin, luz que parpadea), en
## las dos vistas. Todo original y generado en codigo:
##
## - **Los efectos**: humo, serrin y farol de "trabajando"; humo negro de ruina
##   (variante "ruin"); y en las obras chispas de soldadura ("sparks") y polvo
##   ("dust" con la variante "site"), ver SiteFx.
## - **La hoja**: 8 fotogramas en rejilla 4x2 (GameConfig.building_fx_*),
##   dibujados aqui pixel a pixel y cacheados (una textura por efecto para todo
##   el mapa).
## - **La animacion**: un shader que elige el fotograma con TIME. Ni timers, ni
##   tweens, ni AnimationPlayer por edificio: el coste en CPU es cero, y en GPU
##   un quad transparente por columna de humo. Cada edificio arranca en un
##   fotograma distinto (sale de su posicion), para que dos fundiciones no
##   echen humo al compas.
## - **Un material por efecto** compartido por todos los edificios: el
##   renderizador Mobile los agrupa.

const FRAME_PX := 32

const _SPATIAL := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled%s;
uniform sampler2D sheet : source_color, filter_linear, repeat_disable;
uniform float frames = 8.0;
uniform float columns = 4.0;
uniform float fps = 12.0;
uniform vec4 tint : source_color = vec4(1.0);
varying float v_offset;
void vertex() {
	// De cara a la camara, como la barra de obra de ProductionManager.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	v_offset = fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453) * frames;
}
void fragment() {
	float f = floor(mod(TIME * fps + v_offset, frames));
	float rows = ceil(frames / columns);
	vec2 cell = vec2(mod(f, columns), floor(f / columns));
	vec4 c = texture(sheet, (cell + UV) / vec2(columns, rows)) * tint;
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
"""

const _CANVAS := """
shader_type canvas_item;
render_mode %s;
uniform float frames = 8.0;
uniform float columns = 4.0;
uniform float fps = 12.0;
uniform vec4 tint : source_color = vec4(1.0);
varying float v_offset;
void vertex() {
	v_offset = fract(sin(dot(MODEL_MATRIX[3].xy, vec2(12.9898, 78.233))) * 43758.5453) * frames;
}
void fragment() {
	// El Sprite2D recorta el fotograma 0 (region); aqui se desplaza al que toca.
	float f = floor(mod(TIME * fps + v_offset, frames));
	float rows = ceil(frames / columns);
	vec2 cell = vec2(mod(f, columns), floor(f / columns));
	COLOR = texture(TEXTURE, UV + cell / vec2(columns, rows)) * tint;
}
"""

static var _sheets: Dictionary = {}
static var _mats3d: Dictionary = {}
static var _mats2d: Dictionary = {}
static var _quads: Dictionary = {}

## Tinte de cada variante: el humo de una ruina es mas negro que el de una
## chimenea en marcha. Paleta de DieselpunkBuildingFactory.
static func tint_for(kind: String, variant: String = "") -> Color:
	if variant == "ruin":
		return Color(0.22, 0.2, 0.19, 0.9)
	if variant == "site":
		# Polvo de obra: mas gris y menos denso que el serrin del aserradero.
		return Color(0.74, 0.68, 0.58, 0.7)
	match kind:
		"sparks": return Color(1.0, 0.78, 0.35, 1.0)
		"dust": return Color(0.86, 0.72, 0.5, 0.85)
		# El farol ya lleva sus colores pintados en la hoja.
		"glow": return Color(1.0, 1.0, 1.0, 1.0)
	return Color(0.8, 0.8, 0.78, 0.8)

static func frames() -> int:
	return maxi(1, int(GameConfig.building_fx_frames))

static func columns() -> int:
	return clampi(int(GameConfig.building_fx_columns), 1, frames())

static func rows() -> int:
	return ceili(float(frames()) / float(columns()))

# ── La hoja de sprites ────────────────────────────────────────────────

## Hoja de `kind` ("smoke", "dust", "glow"), cacheada. Fotogramas de FRAME_PX
## en rejilla columns() x rows(). Blanco con alfa: el color lo pone el tinte.
static func sheet(kind: String) -> Texture2D:
	if _sheets.has(kind):
		return _sheets[kind]
	var tex := ImageTexture.create_from_image(sheet_image(kind))
	_sheets[kind] = tex
	return tex

static func sheet_image(kind: String) -> Image:
	var n := frames()
	var cols := columns()
	var img := Image.create_empty(FRAME_PX * cols, FRAME_PX * rows(), false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	for i in n:
		var origin := Vector2i((i % cols) * FRAME_PX, (i / cols) * FRAME_PX)
		var t := float(i) / float(n)
		match kind:
			"glow": _glow_frame(img, origin, i)
			"sparks": _sparks_frame(img, origin, i, t)
			"dust": _dust_frame(img, origin, t)
			_: _smoke_frame(img, origin, t)
	return img

## Tres bocanadas que suben, crecen y se desvanecen; el ciclo cierra en bucle.
static func _smoke_frame(img: Image, o: Vector2i, t: float) -> void:
	for k in 3:
		var ph := fposmod(t + float(k) / 3.0, 1.0)
		var c := Vector2(16.0 + sin(ph * TAU + k) * 3.0 * ph, 27.0 - ph * 19.0)
		var r := 5.0 + ph * 9.0
		var a := (1.0 - ph) * minf(1.0, ph * 5.0 + 0.3) * 0.95
		_soft_disc(img, o, c, r, a)

## Motas de serrin que saltan en abanico desde abajo.
static func _dust_frame(img: Image, o: Vector2i, t: float) -> void:
	for k in 9:
		var ph := fposmod(t + float(k) / 9.0, 1.0)
		var ang := -PI * 0.5 + (float(k) - 4.0) * 0.28
		var c := Vector2(16, 27) + Vector2(cos(ang), sin(ang)) * ph * 20.0 + Vector2(0, ph * ph * 7.0)
		_soft_disc(img, o, c, 2.4 + ph * 2.2, 1.0 - ph * 0.85)

## Un farol pequeno encendido (arte, 2026-10-05): sombrerete y base de hierro,
## cristal calido que parpadea un poco y un halo tenue. Sustituye a la bola
## naranja de antes, que desde la camara parecia un fallo. Pintado en color:
## su tinte es blanco.
static func _glow_frame(img: Image, o: Vector2i, i: int) -> void:
	var flicker := [1.0, 0.82, 0.94, 0.76, 0.98, 0.88, 0.8, 0.92]
	var k: float = flicker[i % flicker.size()]
	var iron := Color(0.17, 0.14, 0.12, 1.0)
	var lit := Color(1.0, 0.72, 0.28).lerp(Color(1.0, 0.95, 0.62), k)
	# Halo: muy suave, solo para que el cristal no quede recortado.
	for y in range(4, 28):
		for x in range(4, 28):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(16, 15)) / 11.0
			if d < 1.0:
				img.set_pixel(o.x + x, o.y + y, Color(1.0, 0.82, 0.45, (1.0 - d) * (1.0 - d) * 0.35 * k))
	_paint_rect(img, o, 15, 3, 17, 4, iron)       # asa
	_paint_rect(img, o, 14, 5, 18, 5, iron)       # sombrerete
	_paint_rect(img, o, 13, 6, 19, 6, iron)
	_paint_rect(img, o, 12, 7, 20, 8, iron)
	_paint_rect(img, o, 12, 9, 20, 20, lit)       # cristal
	_paint_rect(img, o, 12, 9, 12, 20, iron)      # montantes
	_paint_rect(img, o, 20, 9, 20, 20, iron)
	_paint_rect(img, o, 16, 9, 16, 20, Color(iron, 0.55))
	_paint_rect(img, o, 11, 21, 21, 22, iron)     # base
	_paint_rect(img, o, 14, 23, 18, 24, iron)

static func _paint_rect(img: Image, o: Vector2i, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			img.set_pixel(o.x + x, o.y + y, c)

## Chispas de soldadura: un punto blanco que chisporrotea y motas que saltan
## en abanico y caen. El fogonazo cambia de fuerza cada fotograma.
static func _sparks_frame(img: Image, o: Vector2i, i: int, t: float) -> void:
	var flash := [1.0, 0.55, 0.85, 0.4, 0.95, 0.6, 0.75, 0.5]
	var k: float = flash[i % flash.size()]
	_soft_disc(img, o, Vector2(16, 22), 3.0 + 3.0 * k, k)
	for m in 7:
		var ph := fposmod(t + float(m) / 7.0, 1.0)
		var ang := -PI * 0.5 + (float(m) - 3.0) * 0.45
		var c := Vector2(16, 22) + Vector2(cos(ang), sin(ang)) * ph * 14.0 + Vector2(0, ph * ph * 12.0)
		_soft_disc(img, o, c, 1.6, 1.0 - ph * 0.7)

## Disco de borde suave, mezclado por maximo de alfa (las bocanadas se funden).
static func _soft_disc(img: Image, o: Vector2i, c: Vector2, r: float, alpha: float) -> void:
	if alpha <= 0.0 or r <= 0.0:
		return
	for y in range(maxi(0, int(c.y - r - 1)), mini(FRAME_PX, int(c.y + r + 2))):
		for x in range(maxi(0, int(c.x - r - 1)), mini(FRAME_PX, int(c.x + r + 2))):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / r
			if d >= 1.0:
				continue
			var a := alpha * (1.0 - d * d)
			var px := img.get_pixel(o.x + x, o.y + y)
			if a > px.a:
				img.set_pixel(o.x + x, o.y + y, Color(1, 1, 1, a))

# ── Materiales ────────────────────────────────────────────────────────

## Las chispas se suman (son luz pura); el humo y el farol se mezclan (el farol
## tiene hierro oscuro, que sumado desapareceria).
static func _additive(kind: String) -> bool:
	return kind == "sparks"

static func _blend(kind: String) -> String:
	return "blend_add" if _additive(kind) else "blend_mix"

## Dos shaders 3D para todos los efectos (mezcla y suma), compartidos: cada
## material nuevo ya no compila el suyo. Los calienta warm_up() al cargar.
static var _shaders3d: Dictionary = {}

static func _shader_3d(additive: bool) -> Shader:
	if not _shaders3d.has(additive):
		var shader := Shader.new()
		shader.code = _SPATIAL % [", blend_add" if additive else ""]
		_shaders3d[additive] = shader
	return _shaders3d[additive]

## Los efectos 3D que pueden salir en partida: [tipo, variante].
const WARM_KINDS := [["smoke", ""], ["dust", ""], ["glow", ""], ["sparks", ""],
	["smoke", "ruin"], ["dust", "site"]]

## Crea ya todos los materiales 3D (hojas de sprites incluidas) y cuelga de
## `parent` un quad diminuto de cada uno: el motor compila sus shaders y
## pipelines al dibujarlos una vez, en la carga, y no la primera vez que una
## fundicion echa humo. Devuelve los quads (quien llama los libera).
static func warm_up(parent: Node3D) -> Array:
	var out: Array = []
	for pair in WARM_KINDS:
		var mi := quad_3d(String(pair[0]), 0.01, String(pair[1]))
		mi.remove_from_group("building_fx")
		parent.add_child(mi)
		out.append(mi)
	return out

static func material_3d(kind: String, variant: String = "") -> ShaderMaterial:
	var key := kind + ":" + variant
	if _mats3d.has(key):
		return _mats3d[key]
	var mat := ShaderMaterial.new()
	mat.shader = _shader_3d(_additive(kind))
	mat.set_shader_parameter("sheet", sheet(kind))
	_set_common(mat, kind, variant)
	_mats3d[key] = mat
	return mat

static func material_2d(kind: String, variant: String = "") -> ShaderMaterial:
	var key := kind + ":" + variant
	if _mats2d.has(key):
		return _mats2d[key]
	var shader := Shader.new()
	shader.code = _CANVAS % _blend(kind)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_set_common(mat, kind, variant)
	_mats2d[key] = mat
	return mat

static func _set_common(mat: ShaderMaterial, kind: String, variant: String) -> void:
	mat.set_shader_parameter("frames", float(frames()))
	mat.set_shader_parameter("columns", float(columns()))
	mat.set_shader_parameter("fps", float(GameConfig.building_fx_fps))
	mat.set_shader_parameter("tint", tint_for(kind, variant))

# ── Nodos listos para colgar ──────────────────────────────────────────

## Un quad 3D animado de `size` unidades. En el grupo "building_fx": ni el
## hollin de BuildingHealth ni la medida de la cima lo tocan.
static func quad_3d(kind: String, size: float, variant: String = "") -> MeshInstance3D:
	# Un QuadMesh por medida para todo el mapa (antes, uno por efecto).
	var qkey := snappedf(size, 0.001)
	if not _quads.has(qkey):
		var q := QuadMesh.new()
		q.size = Vector2(size, size)
		_quads[qkey] = q
	var quad: QuadMesh = _quads[qkey]
	var mi := MeshInstance3D.new()
	mi.name = "Fx_" + kind
	mi.mesh = quad
	mi.material_override = material_3d(kind, variant)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_to_group("building_fx")
	return mi

## Un Sprite2D animado de `size_px` de lado, recortado al fotograma 0.
static func sprite_2d(kind: String, size_px: float, variant: String = "") -> Sprite2D:
	var s := Sprite2D.new()
	s.name = "Fx_" + kind
	s.texture = sheet(kind)
	s.region_enabled = true
	s.region_rect = Rect2(0, 0, FRAME_PX, FRAME_PX)
	s.material = material_2d(kind, variant)
	s.scale = Vector2.ONE * (size_px / float(FRAME_PX))
	return s
