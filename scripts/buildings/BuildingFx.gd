extends RefCounted
## Los efectos animados de los edificios (humo, serrin, luz que parpadea), en
## las dos vistas. Todo original y generado en codigo:
##
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

## Tinte de cada variante: el humo de una ruina es mas negro que el de una
## chimenea en marcha. Paleta de DieselpunkBuildingFactory.
static func tint_for(kind: String, variant: String = "") -> Color:
	if variant == "ruin":
		return Color(0.22, 0.2, 0.19, 0.9)
	match kind:
		"dust": return Color(0.86, 0.72, 0.5, 0.85)
		"glow": return Color(1.0, 0.62, 0.18, 0.95)
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

## Un brillo redondo cuya fuerza cambia en cada fotograma: parpadeo de llama.
static func _glow_frame(img: Image, o: Vector2i, i: int) -> void:
	var flicker := [1.0, 0.72, 0.9, 0.58, 0.96, 0.8, 0.64, 0.88]
	var k: float = flicker[i % flicker.size()]
	_soft_disc(img, o, Vector2(16, 16), 9.0 + 4.0 * k, 0.95 * k)

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

static func _blend(kind: String) -> String:
	return "blend_add" if kind == "glow" else "blend_mix"

static func material_3d(kind: String, variant: String = "") -> ShaderMaterial:
	var key := kind + ":" + variant
	if _mats3d.has(key):
		return _mats3d[key]
	var shader := Shader.new()
	shader.code = _SPATIAL % [", blend_add" if kind == "glow" else ""]
	var mat := ShaderMaterial.new()
	mat.shader = shader
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
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
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
