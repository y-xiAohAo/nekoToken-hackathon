shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float radius = length(p);
	float rim = 1.0 - smoothstep(0.022, 0.068, abs(radius - 0.83));
	float inner = 1.0 - smoothstep(0.67, 0.86, radius);
	float angle = atan(p.y, p.x);
	float ticks = step(0.44, fract(angle * 2.55 + TIME * 0.18));
	float scan = step(0.79, fract(UV.y * 23.0 + TIME * 1.15));
	float rise = 1.0 - smoothstep(0.0, 0.043, abs(UV.y - fract(-TIME * 0.66)));
	float outer = (1.0 - smoothstep(0.012, 0.048, abs(radius - 0.95))) * ticks;
	ALBEDO = mix(vec3(0.065, 0.44, 0.59), vec3(0.60, 0.98, 1.0), max(rim, rise * inner));
	ALPHA = clamp(rim * 0.91 + outer * 0.52 + inner * (0.18 + scan * 0.15 + rise * 0.35), 0.0, 1.0);
}
