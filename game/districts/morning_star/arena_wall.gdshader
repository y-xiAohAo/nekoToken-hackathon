shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

varying float arena_z;
uniform vec4 phase_color : source_color = vec4(0.33, 0.90, 0.96, 1.0);
uniform float phase_energy = 0.0;

void vertex() {
	arena_z = VERTEX.z;
}

void fragment() {
	float rear = smoothstep(0.0, 8.0, -arena_z);
	float edge = step(UV.x, 0.018) + step(0.982, UV.x);
	float top = step(UV.y, 0.018);
	float base = step(0.96, UV.y);
	float scan = step(0.88, fract(UV.y * 8.0));
	float pulse = 1.0 - smoothstep(0.0, 0.025, abs(UV.y - fract(-TIME * 0.23)));
	ALBEDO = mix(phase_color.rgb * 0.40, phase_color.rgb, max(edge, base * 0.66));
	ALPHA = (0.045 + edge * 0.30 + top * 0.14 + base * 0.12 + scan * 0.034 + pulse * (0.07 + phase_energy * 0.19))
		* mix(0.23, 1.0, rear);
}
