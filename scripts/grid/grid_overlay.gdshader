shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform vec4 grid_color : source_color = vec4(0.85, 0.85, 0.75, 0.35);
uniform float cell_size : hint_range(0.5, 10.0) = 2.0;
uniform float line_width : hint_range(0.01, 0.15) = 0.04;
uniform float fade_distance : hint_range(10.0, 100.0) = 40.0;

varying vec3 world_vertex;

void vertex() {
	world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 coord = world_vertex.xz / cell_size;
	vec2 grid = abs(fract(coord - 0.5) - 0.5);
	vec2 line_w = fwidth(coord) * line_width / 0.02;
	vec2 draw = smoothstep(vec2(0.0), line_w, grid);
	float line = 1.0 - min(draw.x, draw.y);

	// Fade out at distance to avoid noise and save GPU
	float dist = length(world_vertex.xz - CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(fade_distance * 0.6, fade_distance, dist);

	ALBEDO = grid_color.rgb;
	ALPHA = line * grid_color.a * fade;
}
