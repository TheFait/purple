shader_type canvas_item;
// The fakeout's lights-out: the whole screen goes dark except a soft oval of light on the
// card. Coordinates are the rect's local pixels. Fade the node's modulate to bring it in.

uniform vec2 center = vec2(360.0, 500.0);
uniform vec2 radii = vec2(220.0, 300.0);
uniform float softness = 0.35;
uniform float darkness = 0.93;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	float r = length((local - center) / radii);
	float a = smoothstep(1.0 - softness, 1.0 + softness, r) * darkness;
	// A faint violet bloom just inside the edge of the light.
	vec3 col = mix(vec3(0.0, 0.0, 0.02), vec3(0.25, 0.05, 0.3), (1.0 - smoothstep(0.7, 1.1, r)) * 0.4);
	COLOR = vec4(col, a);
}
