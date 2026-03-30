shader_type spatial;

// Procedural grass texture — varied green tones with subtle noise pattern
uniform vec4 grass_color_1 : source_color = vec4(0.30, 0.52, 0.18, 1.0);
uniform vec4 grass_color_2 : source_color = vec4(0.38, 0.58, 0.22, 1.0);
uniform vec4 grass_color_3 : source_color = vec4(0.25, 0.45, 0.15, 1.0);
uniform float noise_scale : hint_range(1.0, 50.0) = 12.0;
uniform float detail_scale : hint_range(10.0, 200.0) = 80.0;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.85;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Simple hash-based noise
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float val = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		val += amp * noise(p);
		p *= 2.1;
		amp *= 0.45;
	}
	return val;
}

void fragment() {
	vec2 uv = world_pos.xz;

	// Large-scale color variation
	float n1 = fbm(uv / noise_scale);
	// Small-scale grass detail
	float n2 = fbm(uv / detail_scale * noise_scale);
	// Combine
	float blend = smoothstep(0.35, 0.65, n1);
	vec3 col = mix(grass_color_1.rgb, grass_color_2.rgb, blend);

	// Add darker patches
	float dark = fbm(uv / (noise_scale * 0.7) + vec2(50.0, 50.0));
	col = mix(col, grass_color_3.rgb, smoothstep(0.5, 0.7, dark) * 0.6);

	// Fine grass-blade detail
	float detail = noise(uv * detail_scale * 0.15);
	col *= 0.9 + 0.1 * detail;

	ALBEDO = col;
	ROUGHNESS = roughness_val;
	METALLIC = 0.0;
}
