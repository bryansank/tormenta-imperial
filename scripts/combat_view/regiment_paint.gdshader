shader_type spatial;
// La pintura del regimiento sobre la superficie "team" de nuestras unidades
// (UnitModels3D.team_material). Solo cosmetica (docs/15 §11).
//
// Un patron procedural en espacio del modelo, sin texturas: liso, rayas,
// manchas, desierto, nieve y gala. El color por vertice de la malla (grises
// horneados, en sRGB como en ToyPalette.make_solid) da la luz y la sombra;
// la pintura lo multiplica. Un material por color y pintura, compartido por
// todas las piezas que lo llevan: una pelea entera suma, como mucho, uno.
// El mismo dibujo en plano: RegimentLook.paint_color().

uniform vec4 team_color : source_color = vec4(0.8, 0.62, 0.25, 1.0);
// Indice en GameConfig.REGIMENT_PAINTS.
uniform int paint = 0;

varying vec3 local_pos;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x);
	float b = mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x);
	float c = mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x);
	float d = mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x);
	return mix(mix(a, b, f.y), mix(c, d, f.y), f.z);
}

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 c = team_color.rgb;
	vec3 col = c;
	float rough = 0.82;
	if (paint == 1) {
		// Rayas en diagonal, la segunda franja a media luz.
		float t = fract((local_pos.x + local_pos.y * 0.6 + local_pos.z * 0.3) * 2.6);
		col = t < 0.5 ? c : c * 0.3;
	} else if (paint == 2) {
		// Manchas: oscuras de monte y claras del color.
		float n = vnoise(local_pos * 3.2);
		col = n > 0.58 ? mix(c * 0.18, vec3(0.03, 0.04, 0.012), 0.5) : (n < 0.32 ? min(c * 1.35, vec3(1.0)) : c);
	} else if (paint == 3) {
		// Desierto: arena con manchas pardas y del color.
		float n = vnoise(local_pos * 2.6);
		col = n > 0.62 ? c : (n < 0.3 ? vec3(0.21, 0.12, 0.05) : vec3(0.6, 0.42, 0.18));
	} else if (paint == 4) {
		// Nieve: blanco con gris y manchas del color.
		float n = vnoise(local_pos * 2.6);
		col = n > 0.62 ? c : (n < 0.28 ? vec3(0.32, 0.34, 0.39) : vec3(0.83, 0.85, 0.91));
	} else if (paint == 5) {
		// Gala: el color con filetes de laton y algo de brillo.
		col = fract(local_pos.y * 3.0) < 0.18 ? vec3(0.68, 0.4, 0.06) : c;
		rough = 0.5;
	}
	ALBEDO = srgb_to_linear(COLOR.rgb) * col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
}
