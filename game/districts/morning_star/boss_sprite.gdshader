shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D sprite_art : source_color, filter_nearest, repeat_disable;
uniform bool projection_layer = false;
uniform int severed_pairs = 0;
uniform float glow = 0.0;
uniform float flash = 0.0;
uniform float dissolve = 0.0;

void fragment() {
	vec4 art = texture(sprite_art, UV);
	vec2 pixel = floor(UV * vec2(64.0, 112.0));
	bool cyan = art.g > art.r + 0.03 && art.b > art.r + 0.025 && art.g > art.b - 0.025;
	bool projector = pixel.y < 67.0 || (pixel.y < 71.0 && cyan);
	if (art.a < 0.5 || projector != projection_layer) {
		discard;
	}
	if (projection_layer && pixel.y >= 60.0) {
		float spread = abs(pixel.x + 0.5 - 32.0);
		float outer = mix(9.0, 6.3, smoothstep(60.0, 70.0, pixel.y));
		float middle = mix(4.8, 3.0, smoothstep(60.0, 70.0, pixel.y));
		int pair = spread >= outer ? 1 : (spread >= middle ? 2 : 3);
		if (pair <= severed_pairs) {
			discard;
		}
	}
	if (projection_layer && dissolve > 0.0) {
		float noise = fract(sin(dot(pixel, vec2(53.117, 23.781))) * 43758.5453);
		float rank = pixel.y / 70.0 * 0.79 + noise * 0.21;
		bool amber = art.r > art.g * 1.22 && art.g > art.b * 1.45 && pixel.y < 27.0;
		if (rank > 1.0 - dissolve && (!amber || dissolve > 0.92)) {
			discard;
		}
	}
	vec3 tint = art.rgb * (1.0 + glow * 0.40);
	if (projection_layer && cyan && glow > 0.13) {
		float line = fract(pixel.y / 42.0 - TIME * 2.6);
		float band = (1.0 - smoothstep(0.032, 0.15, line)) * glow;
		tint = mix(tint, vec3(0.76, 1.0, 1.0), band * 0.78);
	}
	ALBEDO = mix(tint, vec3(0.92, 1.0, 1.0), flash * 0.48);
}
