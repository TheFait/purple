shader_type canvas_item;
// Full-screen post pass: chromatic aberration, flash, edge vignette, faint scanlines.
// Scripts drive `aberration`, `flash` and `vignette` (see scenes/fx/screen_fx.gd).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float aberration = 0.0;
uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 0.1, 0.3, 1.0);
uniform float vignette = 0.25;
uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float scanlines = 0.05;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = (uv - 0.5) * aberration;
	vec3 col;
	col.r = texture(screen_tex, uv + d).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - d).b;

	float v = smoothstep(0.35, 0.95, length((uv - 0.5) * vec2(1.0, 1.25)));
	col = mix(col, vignette_color.rgb, v * vignette);
	col *= 1.0 - scanlines * (0.5 + 0.5 * sin(uv.y * 900.0));
	col = mix(col, flash_color.rgb, flash);
	COLOR = vec4(col, 1.0);
}
