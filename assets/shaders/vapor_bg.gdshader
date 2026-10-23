shader_type canvas_item;
// Vaporwave backdrop: gradient sky, glowing suit-diamond, stars, scrolling neon grid floor.
// Draw on a full-screen ColorRect. Every colour below is editable in the Inspector:
// select Game > Background > Backdrop > Material (scenes/game.tscn).

group_uniforms layout;
uniform float aspect = 0.5625;          // viewport width / height
uniform float horizon = 0.6;            // where the sky meets the floor (0 top .. 1 bottom)
uniform float scroll_speed = 0.35;
uniform float diamond_size : hint_range(0.05, 0.4) = 0.24;
uniform float diamond_y : hint_range(0.0, 0.6) = 0.2;   // centre height above the horizon
uniform float pulse : hint_range(0.0, 1.0) = 0.0;       // driven from script on impacts

group_uniforms sky;
uniform vec4 sky_top : source_color = vec4(0.03, 0.0, 0.14, 1.0);        // deep indigo
uniform vec4 sky_horizon : source_color = vec4(0.62, 0.05, 0.55, 1.0);  // magenta

group_uniforms diamond;
uniform vec4 diamond_top : source_color = vec4(1.0, 0.85, 0.25, 1.0);    // gold
uniform vec4 diamond_bottom : source_color = vec4(1.0, 0.1, 0.6, 1.0);   // hot pink
uniform vec4 diamond_ring : source_color = vec4(1.0, 1.0, 1.0, 1.0);    // inner outline
uniform float ring_strength : hint_range(0.0, 1.0) = 0.55;
uniform float stripe_start : hint_range(0.0, 0.9) = 0.4;       // stripes begin this far down the gem (0 top .. 1 bottom)
uniform float stripe_count : hint_range(1.0, 16.0) = 7.0;      // number of bands in the striped part
uniform float stripe_gap_top : hint_range(0.0, 1.0) = 0.12;    // cut-out share of a band where stripes start
uniform float stripe_gap_bottom : hint_range(0.0, 1.0) = 0.65; // ...and at the bottom tip: bars get thicker downward
uniform float stripe_scroll = 0.03;                             // slow downward drift, like the retro sun

group_uniforms floor;
uniform vec4 floor_horizon : source_color = vec4(0.34, 0.03, 0.3, 1.0);  // floor colour at the horizon
uniform vec4 floor_bottom : source_color = vec4(0.03, 0.0, 0.14, 1.0);  // floor colour at screen bottom
uniform vec4 grid_color : source_color = vec4(0.1, 0.95, 1.0, 1.0);     // grid lines (cyan)
uniform vec4 grid_glow : source_color = vec4(1.0, 0.15, 0.8, 1.0);       // pink glow on the lines

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float circle(vec2 p, vec2 c, float r) {
	return smoothstep(r, r - 0.05, length(p - c));
}

// Card-suit glyphs in a cell: p in -0.5..0.5, +y up. Returns coverage 0..1.
float suit_shape(vec2 p, int kind) {
	if (kind == 0) {         // heart
		vec2 q = vec2(p.x * 2.5, p.y * 2.5 + 0.1);
		float v = pow(q.x * q.x + q.y * q.y - 1.0, 3.0) - q.x * q.x * q.y * q.y * q.y;
		return smoothstep(0.08, -0.08, v);
	} else if (kind == 1) {  // diamond
		return smoothstep(0.46, 0.4, abs(p.x) / 0.7 + abs(p.y));
	} else if (kind == 2) {  // spade: upside-down heart plus a stem
		vec2 q = vec2(p.x * 2.5, -p.y * 2.5 + 0.35);
		float v = pow(q.x * q.x + q.y * q.y - 1.0, 3.0) - q.x * q.x * q.y * q.y * q.y;
		float body = smoothstep(0.08, -0.08, v);
		float stem = step(abs(p.x), 0.05 + 0.2 * clamp(-p.y - 0.18, 0.0, 0.3)) * step(-0.46, p.y) * step(p.y, -0.1);
		return max(body, stem);
	}
	// club: three lobes plus a stem
	float lobes = max(circle(p, vec2(0.0, 0.17), 0.19), max(circle(p, vec2(-0.2, -0.06), 0.19), circle(p, vec2(0.2, -0.06), 0.19)));
	float stem = step(abs(p.x), 0.05 + 0.2 * clamp(-p.y - 0.12, 0.0, 0.3)) * step(-0.46, p.y) * step(p.y, -0.02);
	return max(lobes, stem);
}

void fragment() {
	vec2 uv = UV;
	vec3 col;

	if (uv.y < horizon) {
		float t = uv.y / horizon;
		col = mix(sky_top.rgb, sky_horizon.rgb, pow(t, 1.6));

		// Card suits drifting in and out like twinkling stars, only in the upper sky.
		vec2 sp = vec2(uv.x * aspect, uv.y) * 40.0;
		vec2 cell = floor(sp);
		float h = hash(cell);
		vec2 local = fract(sp) - 0.5;
		local.y = -local.y;
		int kind = int(floor(hash(cell + 7.7) * 4.0));
		float glyph = suit_shape(local * 1.25, kind) * step(0.94, h);
		float twinkle = 0.5 + 0.5 * sin(TIME * 2.0 + h * 40.0);
		vec3 tint = kind < 2 ? vec3(1.0, 0.8, 0.95) : vec3(0.85, 0.95, 1.0);
		col += tint * glyph * twinkle * (1.0 - t * 0.6) * 1.3;

		// Diamond (the card-suit shape): |x|/0.7 + |y| < r, taller than wide.
		vec2 c = vec2(0.5, horizon - diamond_y);
		vec2 p = vec2((uv.x - c.x) * aspect, uv.y - c.y);
		float r = diamond_size + pulse * 0.02;
		float d = abs(p.x) / 0.7 + abs(p.y);
		float fill = smoothstep(r, r - 0.004, d);
		float local_y = clamp((p.y + r) / (2.0 * r), 0.0, 1.0);     // 0 top .. 1 bottom
		// Retro-sun stripes: horizontal slits that widen toward the bottom tip.
		float sy = clamp((local_y - stripe_start) / (1.0 - stripe_start), 0.0, 1.0);
		float band = fract(sy * stripe_count - TIME * stripe_scroll);
		float gap = mix(stripe_gap_top, stripe_gap_bottom, sy);
		float slit = smoothstep(1.0 - gap - 0.02, 1.0 - gap, band) * smoothstep(0.02, 0.05, sy);  // no hairline where the stripes begin
		fill *= 1.0 - slit;
		vec3 gem = mix(diamond_top.rgb, diamond_bottom.rgb, local_y);
		// Inner outline, like the pip on a card.
		float ring = smoothstep(0.007, 0.0, abs(d - r * 0.72)) * ring_strength;
		gem = mix(gem, diamond_ring.rgb, ring);
		col = mix(col, gem, fill);
		// Bright rim so the shape holds against the pink horizon.
		col = mix(col, diamond_ring.rgb, smoothstep(0.008, 0.0, abs(d - r)) * ring_strength * 1.4 * (1.0 - slit));
		// Glow halo
		col += mix(diamond_top.rgb, diamond_bottom.rgb, 0.5) * exp(-max(d - r, 0.0) * 14.0) * (0.3 + pulse * 0.4) * (1.0 - fill);
	} else {
		// Floor: perspective grid.
		float y = uv.y - horizon;
		float z = 1.0 / max(y, 0.0001);
		float x = (uv.x - 0.5) / aspect * z * 0.18;
		float zz = z * 0.12 + TIME * scroll_speed;

		vec2 g = vec2(x, zz);
		vec2 fw = fwidth(g) * 1.2;
		vec2 line = abs(fract(g - 0.5) - 0.5) / max(fw, vec2(0.0001));
		float grid = 1.0 - clamp(min(line.x, line.y), 0.0, 1.0);

		float fade = smoothstep(0.0, 0.22, y);
		col = mix(floor_horizon.rgb, floor_bottom.rgb, clamp(y * 2.2, 0.0, 1.0));
		col += grid_color.rgb * grid * fade * 1.1;
		col += grid_glow.rgb * grid * fade * 0.5 * (0.6 + pulse);
		// Horizon glow line
		col += sky_horizon.rgb * exp(-y * 28.0) * 0.8;
	}

	COLOR = vec4(col, 1.0);
}
