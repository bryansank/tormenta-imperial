shader_type spatial;
// Las marcas de casilla del tablero 3D (Board3D): alcanzables, objetivos, la
// unidad activa, la casilla bajo el puntero. Una sola MultiMesh, una llamada de
// dibujo. El color de cada casilla va en INSTANCE_CUSTOM (alfa 0 = apagada); el
// alfa por vertice separa el marco (1) del relleno (tenue). El latido es TIME:
// nada que mover desde GDScript.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

varying vec4 v_col;

void vertex() {
	v_col = INSTANCE_CUSTOM * COLOR;
}

void fragment() {
	if (v_col.a < 0.01) {
		discard;
	}
	float pulse = 0.82 + 0.18 * sin(TIME * 5.0);
	ALBEDO = v_col.rgb;
	ALPHA = v_col.a * pulse;
}
