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
## Si los quads y sprites nuevos nacen visibles. En calidad Minima, no: los pone
## GraphicsQuality.apply_runtime(), que tambien apaga los ya creados (grupo
## FX_GROUP). Solo la hoja animada: su contenedor lo sigue encendiendo y
## apagando el aspecto del edificio.
static var anim_visible := true
const FX_GROUP := "building_fx_anim"
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
		mi.remove_from_group(FX_GROUP)
		mi.visible = true
		parent.add_child(mi)
		out.append(mi)
	# La mota del polvo de obra terminada (V1): su material tambien se compila aqui.
	var burst := MeshInstance3D.new()
	burst.mesh = burst_mesh_3d()
	burst.scale = Vector3.ONE * 0.01
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(burst)
	out.append(burst)
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
	mi.add_to_group(FX_GROUP)
	mi.visible = anim_visible
	return mi

# ── Obra terminada: salto y polvo (V1, rediseno 2026-10-14) ───────────

## El salto: 1,0 -> BOUNCE_PEAK -> 1,0 en BOUNCE_UP + BOUNCE_DOWN segundos.
const BOUNCE_PEAK := 1.12
const BOUNCE_UP := 0.12
const BOUNCE_DOWN := 0.18
## El polvo: una rafaga unica de BURST_COUNT motas que se abren y se apagan.
const BURST_COUNT := 8
const BURST_LIFETIME := 0.7
const BURST_TINT := Color(0.82, 0.74, 0.62, 0.85)

static var _burst_tex: Texture2D = null
static var _burst_mesh: QuadMesh = null
static var _burst_ramp: Gradient = null
static var _burst_curve: Curve = null

## Un Tween de `host` que lleva `set_k` (recibe el factor de escala) de 1,0 al
## pico y de vuelta, con un rebote de juguete al caer. Sin _process: lo mueve el
## arbol mientras dura (0,3 s) y muere con `host`.
static func bounce(host: Node, set_k: Callable) -> Tween:
	var tw := host.create_tween()
	tw.tween_method(set_k, 1.0, BOUNCE_PEAK, BOUNCE_UP).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(set_k, BOUNCE_PEAK, 1.0, BOUNCE_DOWN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tw

## Una mota blanda (blanco con alfa: el color lo pone el tinte), para las dos vistas.
static func burst_texture() -> Texture2D:
	if _burst_tex == null:
		var img := Image.create_empty(FRAME_PX, FRAME_PX, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 0))
		_soft_disc(img, Vector2i.ZERO, Vector2(16, 16), 15.0, 1.0)
		_burst_tex = ImageTexture.create_from_image(img)
	return _burst_tex

## Alfa que se apaga y tamano que crece: compartidos por todas las rafagas.
static func _burst_shared() -> void:
	if _burst_ramp == null:
		_burst_ramp = Gradient.new()
		_burst_ramp.set_color(0, Color(1, 1, 1, 1))
		_burst_ramp.set_color(1, Color(1, 1, 1, 0))
		_burst_ramp.add_point(0.35, Color(1, 1, 1, 0.8))
	if _burst_curve == null:
		_burst_curve = Curve.new()
		_burst_curve.add_point(Vector2(0.0, 0.45))
		_burst_curve.add_point(Vector2(1.0, 1.0))

## El quad de la mota 3D, con su material (uno para todo el mapa).
static func burst_mesh_3d() -> QuadMesh:
	if _burst_mesh == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = burst_texture()
		mat.albedo_color = BURST_TINT
		mat.no_depth_test = false
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat.disable_receive_shadows = true
		_burst_mesh = QuadMesh.new()
		_burst_mesh.size = Vector2(1, 1)
		_burst_mesh.material = mat
	return _burst_mesh

## Rafaga de polvo 3D al pie de un edificio de `radius` (medio lado de su huella).
## Un CPUParticles3D de un solo disparo que se borra al acabar: nada por frame
## cuando no hay obra que terminar. Quien llama mira la calidad (Minima: nada).
static func dust_burst_3d(radius: float) -> CPUParticles3D:
	_burst_shared()
	var p := CPUParticles3D.new()
	p.name = "Fx_burst"
	p.mesh = burst_mesh_3d()
	p.amount = BURST_COUNT
	p.lifetime = BURST_LIFETIME
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = true
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius
	p.emission_ring_inner_radius = radius * 0.75
	p.emission_ring_height = 0.05
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0, -2.5, 0)
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.scale_amount_min = 0.7 + radius * 0.15
	p.scale_amount_max = 1.0 + radius * 0.2
	p.scale_amount_curve = _burst_curve
	p.color_ramp = _burst_ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_to_group("building_fx")
	p.finished.connect(p.queue_free)
	return p

## La misma rafaga en la vista 2D: `radius_px` es medio lado de la huella.
static func dust_burst_2d(radius_px: float) -> CPUParticles2D:
	_burst_shared()
	var p := CPUParticles2D.new()
	p.name = "Fx_burst"
	p.texture = burst_texture()
	p.amount = BURST_COUNT
	p.lifetime = BURST_LIFETIME
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = true
	# Vista cenital: las motas salen del borde de la huella y se abren hacia fuera.
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
	p.emission_sphere_radius = radius_px
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = radius_px * 0.2
	p.initial_velocity_max = radius_px * 0.4
	p.radial_accel_min = radius_px * 1.6
	p.radial_accel_max = radius_px * 2.4
	p.damping_min = radius_px * 0.8
	p.damping_max = radius_px * 1.2
	p.gravity = Vector2.ZERO
	var s := radius_px / float(FRAME_PX) * 0.7
	p.scale_amount_min = s * 0.8
	p.scale_amount_max = s * 1.2
	p.scale_amount_curve = _burst_curve
	p.color = BURST_TINT
	p.color_ramp = _burst_ramp
	p.finished.connect(p.queue_free)
	return p

## Un Sprite2D animado de `size_px` de lado, recortado al fotograma 0.
static func sprite_2d(kind: String, size_px: float, variant: String = "") -> Sprite2D:
	var s := Sprite2D.new()
	s.name = "Fx_" + kind
	s.texture = sheet(kind)
	s.region_enabled = true
	s.region_rect = Rect2(0, 0, FRAME_PX, FRAME_PX)
	s.material = material_2d(kind, variant)
	s.scale = Vector2.ONE * (size_px / float(FRAME_PX))
	s.add_to_group(FX_GROUP)
	s.visible = anim_visible
	return s
