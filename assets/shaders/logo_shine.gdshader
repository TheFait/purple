shader_type canvas_item;
// A highlight that sweeps down across glyphs once per road-grid cycle, so it stays
// in time with vapor_bg's scrolling floor. Keep scroll_speed equal to that shader's.

uniform float scroll_speed = 0.35;
uniform float sweep_from : hint_range(0.0, 1.0) = 0.04;   // screen-height fraction where the sweep starts
uniform float sweep_to : hint_range(0.0, 1.0) = 0.17;     // ...and where it ends
uniform float sweep_portion : hint_range(0.1, 1.0) = 0.6; // share of each cycle spent sweeping
uniform float band_width : hint_range(0.005, 0.1) = 0.02; // in screen-height fractions
uniform float slant : hint_range(-0.5, 0.5) = 0.06;
uniform float strength : hint_range(0.0, 2.0) = 1.2;
uniform vec4 shine_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	float phase = clamp(fract(TIME * scroll_speed) / sweep_portion, 0.0, 1.0);
	float margin = band_width * 1.5;
	float pos = mix(sweep_from - margin, sweep_to + margin, phase);
	float y = SCREEN_UV.y + (SCREEN_UV.x - 0.5) * slant;
	float band = smoothstep(band_width, 0.0, abs(y - pos));
	COLOR.rgb = mix(COLOR.rgb, shine_color.rgb, band * 0.85) + shine_color.rgb * band * band * strength * 0.3;
}
