// La Tormenta sobre la isla (docs/21 §12). Lo incluyen los cinco shaders de
// la isla: cesped, canto, playa, espuma y agua.
//
// StormSky fija `storm_weight` en cada material con el mismo peso y el mismo
// fundido que el cielo (0 = calma, 1 = la peor tormenta). La luz que baja ya
// oscurece lo que tiene luz; esto le quita el color de juguete: lo desatura y
// lo enfria hacia la pizarra de ToyPalette (SLATE), que es el aire de ceniza de
// hierro visto sobre la hierba. Una mezcla y un producto: gratis en Mobile.
uniform float storm_weight : hint_range(0.0, 1.0) = 0.0;

// Version sencilla de cada shader (WorldLook: calidades baja y minima). El
// mismo valor en todo el material, asi que la rama no divide el trabajo de la
// GPU: se salta ondas, lineas de espuma y grano. Nada de bucles ni texturas.
uniform bool simple = false;

// Hacia que tono frio va el color (multiplicador, pizarra azulada).
const vec3 STORM_COLD = vec3(0.86, 0.91, 1.0);

// `strength` dice cuanto pesa en esta superficie (1 = todo).
vec3 storm_grade(vec3 c, float strength) {
	float w = clamp(storm_weight * strength, 0.0, 1.0);
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 cold = mix(vec3(l), c, 0.3) * STORM_COLD * 0.78;
	return mix(c, cold, w);
}
