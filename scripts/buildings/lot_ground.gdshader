shader_type spatial;
render_mode specular_schlick_ggx;
#include "res://scripts/map/storm_grade.gdshaderinc"

// El suelo de una parcela (BuildingLot): la textura de su tipo (losas, tierra,
// chapa, cesped) repetida una vez por casilla, con la misma Tormenta y la
// misma noche que la isla (storm_grade). StormSky pone `storm_weight` y
// `night_weight` en estos materiales a la vez que en los de la isla: nada por
// frame, un producto y una mezcla en la GPU. Hay pocos materiales (uno por
// tipo de suelo y huella), compartidos por todo el mapa.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform float roughness_val : hint_range(0.0, 1.0) = 0.92;
// Cuanto le llega la Tormenta y la noche (1 = como la hierba de la isla).
uniform float grade_strength : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec3 c = texture(albedo_tex, UV * uv_scale).rgb * tint.rgb;
	ALBEDO = storm_grade(c, grade_strength);
	ROUGHNESS = roughness_val;
	METALLIC = 0.0;
}
