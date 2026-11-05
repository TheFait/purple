shader_type canvas_item;
// Burns whatever a CanvasGroup holds away from the bottom up: a ragged, flickering line
// rises from bottom_y to top_y as `progress` goes 0 -> 1. Below the line is gone; just
// above it the picture glows white-hot, then orange, then chars dark before it shows clean.
// Used by Table.burn_away (a Posted pair of cards). Coordinates are the group's local space.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float top_y = 0.0;
uniform float bottom_y = 300.0;
uniform float edge = 26.0;     // depth of the hot / charred band above the line, in pixels
uniform float wobble = 26.0;   // how ragged the burn line is, in pixels

varying vec2 local;

void vertex() {
	local = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec4 c = textureLod(screen_texture, SCREEN_UV, 0.0);
	float n = noise(local * 0.03) * 0.6 + noise(local * 0.09 + vec2(0.0, TIME * 2.0)) * 0.4;
	// Start fully below the cards and finish fully above them, ragged edge included.
	float line = mix(bottom_y + wobble + 4.0, top_y - wobble - edge * 2.0, progress);
	float d = local.y - line + (n - 0.5) * 2.0 * wobble;   // > 0: already burnt
	if (d > 0.0) {
		discard;
	}
	float t = clamp(-d / edge, 0.0, 1.0);   // 0 on the burning edge, 1 well clear of it
	vec3 hot = mix(vec3(1.0, 0.96, 0.7), vec3(1.0, 0.4, 0.02), smoothstep(0.0, 0.35, t));
	vec3 charred = mix(hot, c.rgb * 0.12, smoothstep(0.3, 0.65, t));
	vec3 col = mix(charred, c.rgb, smoothstep(0.65, 1.0, t));
	col += vec3(1.0, 0.5, 0.1) * (1.0 - smoothstep(0.0, 0.25, t)) * 0.6;
	COLOR = vec4(col, c.a);
}
