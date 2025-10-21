shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec2 uv = SCREEN_UV;

	vec2 offset = vec2(0.005 * intensity);

	float r = texture(SCREEN_TEXTURE, uv + offset).r;
	float g = texture(SCREEN_TEXTURE, uv).g;
	float b = texture(SCREEN_TEXTURE, uv - offset).b;

	COLOR = vec4(r, g, b, 1.0);
}
