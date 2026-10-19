// Los bancales de la Granja (docs/03, "La Granja"): los tres cultivos y el
// rotor del molino en una sola malla (tools/toy_crops.gd explica que lleva cada
// vertice). Un material para todas las granjas del mapa; lo de cada una va en
// parametros POR INSTANCIA que pone FarmCrops3D cuando cambian (el angulo del
// rotor, cada frame mientras trabaja). Sin texturas ni bucles: barato en Mobile
// y en Compatibility.
//
// Luz como el resto de la maqueta (toy_solid: color por vertice en sRGB,
// rugoso, sin metal): de noche y en la Tormenta baja con la luz de la escena,
// igual que los edificios, y nada brilla por su cuenta.
shader_type spatial;
render_mode cull_back;

// 0 recien plantado .. 1 listo.
instance uniform float growth : hint_range(0.0, 1.0) = 0.6;
// Cultivo: 0 lechugas, 1 patatas, 2 trigo (GameConfig.farm_crops, en orden).
instance uniform float crop = 0.0;
// 1: la cosecha espera a ser recogida (alto, del color maduro, y late).
instance uniform float ripe = 0.0;
// Viento: 1 calma; mas en la ceniza y la Tormenta.
instance uniform float wind = 1.0;
// Giro del rotor del molino, en radianes (solo avanza mientras trabaja).
instance uniform float rotor_angle = 0.0;

// La paleta de ToyPalette, en sRGB (se pasa a lineal abajo).
const vec3 SPROUT = vec3(0.62, 0.82, 0.40);
const vec3 LEAF = vec3(0.424, 0.675, 0.243);      // GREEN
const vec3 LETTUCE_HEART = vec3(0.78, 0.89, 0.52);
const vec3 POTATO_LEAF = vec3(0.33, 0.55, 0.21);
const vec3 POTATO_RIPE = vec3(0.56, 0.58, 0.27);
const vec3 POTATO_FLOWER = vec3(0.949, 0.871, 0.706); // CREAM
const vec3 WHEAT_RIPE = vec3(0.80, 0.60, 0.26);
const vec3 WHEAT_EAR = vec3(0.910, 0.675, 0.227);   // BRASS

varying vec3 v_col;
varying float v_pulse;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	int variant = int(round(CUSTOM0.w));
	vec3 off = CUSTOM0.xyz;
	bool shown = variant == 0 || variant == 3;
	vec3 base = VERTEX - (shown ? off : vec3(0.0));
	v_pulse = 0.0;
	if (variant == 3) {
		float s = sin(rotor_angle);
		float c = cos(rotor_angle);
		off.xy = vec2(c * off.x - s * off.y, s * off.x + c * off.y);
		NORMAL.xy = vec2(c * NORMAL.x - s * NORMAL.y, s * NORMAL.x + c * NORMAL.y);
		VERTEX = base + off;
		v_col = to_linear(COLOR.rgb);
	} else if (variant != int(round(crop))) {
		// Otro cultivo: plegado en su base (triangulos vacios, no se pintan).
		VERTEX = base;
		v_col = vec3(0.0);
	} else {
		float g = clamp(growth, 0.0, 1.0);
		float full = max(g, ripe);
		// Brote bajo y estrecho -> planta entera.
		float ys = mix(0.16, 1.0, full);
		float xs = mix(0.4, 1.0, full);
		vec3 p = vec3(off.x * xs, off.y * ys, off.z * xs);
		// Se mece: mas arriba, mas; cada planta con su fase.
		float phase = base.x * 3.1 + base.z * 2.3;
		float h = max(p.y, 0.0);
		float sway = wind * h;
		p.x += sin(TIME * (1.5 + 0.4 * wind) + phase) * 0.09 * sway;
		p.z += cos(TIME * (1.2 + 0.3 * wind) + phase * 1.3) * 0.05 * sway;
		VERTEX = base + p;
		// Color: brote claro -> hoja -> maduro; la cabeza va a su color al final.
		float ripen = max(smoothstep(0.55, 1.0, g), ripe);
		vec3 leaf;
		vec3 head;
		if (variant == 0) {
			leaf = mix(SPROUT, LEAF, smoothstep(0.0, 0.5, g));
			head = mix(leaf, LETTUCE_HEART, ripen);
		} else if (variant == 1) {
			leaf = mix(mix(SPROUT, POTATO_LEAF, smoothstep(0.0, 0.5, g)), POTATO_RIPE, ripen * 0.7);
			head = mix(leaf, POTATO_FLOWER, ripen);
		} else {
			leaf = mix(mix(SPROUT, LEAF, smoothstep(0.0, 0.5, g)), WHEAT_RIPE, ripen);
			head = mix(leaf, WHEAT_EAR, ripen);
		}
		vec3 col = UV.y > 0.5 ? head : leaf;
		// Matiz de la cara y sombra de contacto al pie de la planta.
		float ao = mix(0.72, 1.0, clamp(h / 0.12, 0.0, 1.0));
		v_col = to_linear(col) * UV.x * ao;
		// Lleno para recoger: la cosecha late un poco (sin brillar de noche).
		v_pulse = ripe * (0.5 + 0.5 * sin(TIME * 2.6 + phase));
	}
}

void fragment() {
	ALBEDO = v_col * (1.0 + 0.16 * v_pulse);
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
}
