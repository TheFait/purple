shader_type canvas_item;
// Flame-coloured text: the glyph fill runs white-yellow at the bottom to orange and red at
// the top, with a flickering, upward-scrolling noise. The outline and the glow (drawn with
// their own, non-white colours) keep those colours, so only the fill burns.

uniform float height = 160.0;   // the label's height, for the gradient
uniform float flicker = 1.0;

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
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	bool fill = COLOR.r > 0.9 && COLOR.g > 0.9 && COLOR.b > 0.9;
	if (fill) {
		float y = clamp(local.y / height, 0.0, 1.0);   // 0 at the top, 1 at the bottom
		float n = noise(vec2(local.x * 0.04, local.y * 0.03 + TIME * 3.5)) * flicker;
		float heat = clamp(y + (n - 0.5) * 0.55, 0.0, 1.0);
		vec3 red = vec3(0.95, 0.12, 0.05);
		vec3 orange = vec3(1.0, 0.48, 0.0);
		vec3 yellow = vec3(1.0, 0.86, 0.25);
		vec3 white = vec3(1.0, 0.98, 0.85);
		vec3 c = heat < 0.4 ? mix(red, orange, heat / 0.4)
			: (heat < 0.75 ? mix(orange, yellow, (heat - 0.4) / 0.35) : mix(yellow, white, (heat - 0.75) / 0.25));
		COLOR = vec4(c, tex.a * COLOR.a);
	} else {
		COLOR = tex * COLOR;
	}
}
