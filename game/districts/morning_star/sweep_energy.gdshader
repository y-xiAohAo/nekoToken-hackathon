shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

void fragment() {
	float column = floor(UV.x * 6.0);
	float step_height = 0.12 + fract(column * 0.39 + floor(TIME * 12.0) * 0.17) * 0.20;
	float edge = 1.0 - smoothstep(0.018, 0.065, abs(UV.y - step_height));
	float scan = step(0.82, fract(UV.y * 5.0 - TIME * 5.3));
	float base = smoothstep(0.63, 1.0, UV.y);
	float body = step(step_height, UV.y) * (0.16 + scan * 0.20 + base * 0.43);
	ALBEDO = mix(vec3(0.15, 0.78, 0.97), vec3(0.79, 1.0, 1.0), max(edge, base * 0.56));
	ALPHA = clamp(body + edge * 0.68, 0.0, 1.0);
}
