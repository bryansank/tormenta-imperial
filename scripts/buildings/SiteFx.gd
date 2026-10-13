extends RefCounted
## La animacion de las obras, en las dos vistas (docs/03, "Obra por edificio"):
## la grua que gira a un lado y a otro, la polea que sube y baja, el banderin
## que ondea. Las chispas de soldadura y el polvo son hojas de BuildingFx.
##
## Igual que BuildingFx: todo lo mueve un shader con TIME. Ni timers, ni tweens,
## ni AnimationPlayer por edificio, ni _process: CPU cero. Cada instancia saca
## su desfase y su velocidad (0,7-1,3 veces la base) de su posicion en el mundo,
## asi que dos gruas vecinas nunca giran al unisono; el giro de partida de cada
## grua lo pone la semilla de la obra (BuildingLook.site_layout).
##
## - **3D**: las piezas que giran (pluma, contrapeso, cable con gancho) son
##   mallas cuyo origen es el eje de la grua; el shader las gira en espacio de
##   modelo. El gancho, ademas, sube y baja: solo se mueven sus vertices por
##   debajo del eje, asi que el cable se acorta y se alarga.
## - **2D**: la pluma es un Line2D y el carro un Polygon2D con el origen en el
##   mastil; el shader los gira y desliza el carro por la pluma.
## - **Materiales compartidos**: uno por color y papel para todo el mapa (el
##   renderizador Mobile los agrupa). Sin uniforms por instancia (el
##   renderizador Compatibility del APK de QA no los tiene).

const _CRANE_3D := """
shader_type spatial;
uniform vec4 albedo : source_color = vec4(0.95, 0.72, 0.1, 1.0);
uniform float swing = 0.7;
uniform float speed = 0.45;
uniform float bob = 0.0;
uniform bool vc_srgb = false;
varying vec3 v_col;
void vertex() {
	v_col = COLOR.rgb;
	float h = fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453);
	float t = TIME * speed * (0.7 + 0.6 * fract(h * 7.13)) + h * 6.2831;
	if (bob > 0.0 && VERTEX.y < -0.05) {
		VERTEX.y += bob * (0.5 + 0.5 * sin(t * 2.3));
	}
	float a = sin(t) * swing;
	mat2 r = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a)));
	VERTEX.xz = r * VERTEX.xz;
	NORMAL.xz = r * NORMAL.xz;
}
void fragment() {
	// Color por vertice (las piezas son de la maqueta, ToyPalette), leido
	// igual que el material solido de la paleta.
	vec3 c = v_col;
	if (vc_srgb) {
		c = mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
	}
	ALBEDO = albedo.rgb * c;
	ROUGHNESS = 0.82;
}
"""

const _FLAG_3D := """
shader_type spatial;
render_mode cull_disabled;
// Sin source_color: el color es de ToyPalette y se lee como el color por
// vertice del material solido de la paleta (vc_srgb dice como).
uniform vec4 albedo = vec4(0.86, 0.2, 0.15, 1.0);
uniform bool vc_srgb = false;
void vertex() {
	float h = fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453);
	float w = clamp(UV.x, 0.0, 1.0);
	VERTEX.z += sin(TIME * (4.0 + 2.0 * h) - UV.x * 5.0 + h * 6.2831) * 0.07 * w;
}
void fragment() {
	vec3 c = albedo.rgb;
	if (vc_srgb) {
		c = mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
	}
	ALBEDO = c;
	ROUGHNESS = 0.82;
}
"""

const _CRANE_2D := """
shader_type canvas_item;
uniform float swing = 0.7;
uniform float speed = 0.45;
uniform float travel = 0.0;
void vertex() {
	float h = fract(sin(dot(MODEL_MATRIX[3].xy, vec2(12.9898, 78.233))) * 43758.5453);
	float t = TIME * speed * (0.7 + 0.6 * fract(h * 7.13)) + h * 6.2831;
	vec2 v = VERTEX;
	v.x += travel * (0.5 + 0.5 * sin(t * 2.3));
	float a = sin(t) * swing;
	VERTEX = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * v;
}
"""

const _FLAG_2D := """
shader_type canvas_item;
void vertex() {
	float h = fract(sin(dot(MODEL_MATRIX[3].xy, vec2(12.9898, 78.233))) * 43758.5453);
	float w = clamp(VERTEX.x / 10.0, 0.0, 1.0);
	VERTEX.y += sin(TIME * (4.0 + 2.0 * h) - VERTEX.x * 0.6 + h * 6.2831) * 1.6 * w;
}
"""

const Tone := preload("res://scripts/buildings/ToyTones.gd")

static var _shaders: Dictionary = {}
static var _mats: Dictionary = {}

static func _shader(key: String, code: String) -> Shader:
	if not _shaders.has(key):
		var s := Shader.new()
		s.code = code
		_shaders[key] = s
	return _shaders[key]

## Material de las piezas que giran con la grua (3D). `bob` > 0: ademas sube y
## baja lo que cuelga por debajo del eje (el gancho). Uno por color y bob. Las
## piezas traen su color por vertice (ToyPalette); `color` lo multiplica
## (blanco = tal cual, lo que usa la obra de la maqueta).
static func crane_material_3d(color: Color, bob: float = 0.0) -> ShaderMaterial:
	var key := "crane3d:%s:%.2f" % [color.to_html(), bob]
	if _mats.has(key):
		return _mats[key]
	var mat := ShaderMaterial.new()
	mat.shader = _shader("crane3d", _CRANE_3D)
	mat.set_shader_parameter("albedo", color)
	mat.set_shader_parameter("swing", GameConfig.construction_crane_swing)
	mat.set_shader_parameter("speed", GameConfig.construction_crane_speed)
	mat.set_shader_parameter("bob", bob)
	mat.set_shader_parameter("vc_srgb", Tone.vertex_color_is_srgb())
	_mats[key] = mat
	return mat

static func flag_material_3d(color: Color) -> ShaderMaterial:
	var key := "flag3d:" + color.to_html()
	if _mats.has(key):
		return _mats[key]
	var mat := ShaderMaterial.new()
	mat.shader = _shader("flag3d", _FLAG_3D)
	mat.set_shader_parameter("albedo", color)
	mat.set_shader_parameter("vc_srgb", Tone.vertex_color_is_srgb())
	_mats[key] = mat
	return mat

## Pluma (travel 0) o carro (travel > 0, px que recorre por la pluma) en 2D.
static func crane_material_2d(travel: float = 0.0) -> ShaderMaterial:
	var key := "crane2d:%.1f" % travel
	if _mats.has(key):
		return _mats[key]
	var mat := ShaderMaterial.new()
	mat.shader = _shader("crane2d", _CRANE_2D)
	mat.set_shader_parameter("swing", GameConfig.construction_crane_swing)
	mat.set_shader_parameter("speed", GameConfig.construction_crane_speed)
	mat.set_shader_parameter("travel", travel)
	_mats[key] = mat
	return mat

## El color del banderin 2D va en el color del Polygon2D: un solo material.
static func flag_material_2d() -> ShaderMaterial:
	if _mats.has("flag2d"):
		return _mats["flag2d"]
	var mat := ShaderMaterial.new()
	mat.shader = _shader("flag2d", _FLAG_2D)
	_mats["flag2d"] = mat
	return mat

## El efecto de obra de un estilo en una fase: "sparks" (solo con estructura o
## ferralla: fases 1 y 2), "dust" (en todas) o "".
static func fx_for(style: Dictionary, phase: int) -> String:
	var kind := String(style.get("site_fx", ""))
	if kind == "sparks" and phase == 0:
		return ""
	return kind
