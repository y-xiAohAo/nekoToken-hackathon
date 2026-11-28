shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never;

uniform vec4 tint : source_color = vec4(0.37, 0.86, 1.0, 0.6);

void fragment() {
	vec2 cell = floor(UV * vec2(16.0, 45.0));
	float bars = step(0.78, fract(cell.y / 7.0 + floor(TIME * 32.0) / 7.0));
	float rails = step(0.71, fract(cell.x * 0.29));
	float spark = bars * (0.30 + rails * 0.70);
	ALBEDO = mix(tint.rgb, vec3(0.87, 1.0, 1.0), spark * 0.83);
	ALPHA = tint.a * (0.62 + spark * 0.38);
}
