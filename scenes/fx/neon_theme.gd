class_name NeonTheme
extends RefCounted
## Builds the shared vaporwave-casino Theme in code (palette, fonts, button/panel styles).

const PINK := Color("ff2bd6")
const CYAN := Color("19f0ff")
const GOLD := Color("ffd23f")
const PURPLE := Color("9b4dff")
const RED := Color("ff2e4d")
const GREEN := Color("39ffa0")
const INK := Color("0d0221")
const PANEL := Color(0.07, 0.02, 0.17, 0.82)
const TEXT := Color("f4e9ff")

const FONT_DISPLAY := preload("res://assets/fonts/Monoton-Regular.ttf")
const FONT_HEAD := preload("res://assets/fonts/Orbitron.ttf")
const FONT_BODY := preload("res://assets/fonts/Rajdhani-Bold.ttf")

static func panel_style(border: Color, fill: Color = PANEL, radius: int = 18, border_w: int = 3, glow: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(border.r, border.g, border.b, 0.55)
	s.shadow_size = glow
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

static func button_styles(accent: Color, radius: int = 16) -> Dictionary:
	var normal := panel_style(accent, Color(INK.r, INK.g, INK.b, 0.85), radius, 3, 8)
	var hover := panel_style(accent.lightened(0.25), Color(accent.r, accent.g, accent.b, 0.22), radius, 3, 16)
	var pressed := panel_style(Color.WHITE, Color(accent.r, accent.g, accent.b, 0.55), radius, 4, 22)
	var disabled := panel_style(accent.darkened(0.6), Color(INK.r, INK.g, INK.b, 0.5), radius, 2, 0)
	disabled.shadow_color = Color(0, 0, 0, 0)
	return {"normal": normal, "hover": hover, "pressed": pressed, "disabled": disabled}

## Apply a per-button accent (e.g. pink for Higher, cyan for Lower) on top of the base theme.
## `radius` rounds the corners; a large value turns small buttons into circles and pills.
static func accent_button(b: Button, accent: Color, radius: int = 16) -> void:
	var st := button_styles(accent, radius)
	b.add_theme_stylebox_override("normal", st.normal)
	b.add_theme_stylebox_override("hover", st.hover)
	b.add_theme_stylebox_override("pressed", st.pressed)
	b.add_theme_stylebox_override("disabled", st.disabled)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", accent.lightened(0.5))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", accent.darkened(0.5))

static func build() -> Theme:
	var t := Theme.new()
	t.default_font = FONT_BODY
	t.default_font_size = 22

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(PINK.r, PINK.g, PINK.b, 0.5))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 0)
	t.set_constant("outline_size", "Label", 0)

	var st := button_styles(CYAN)
	t.set_stylebox("normal", "Button", st.normal)
	t.set_stylebox("hover", "Button", st.hover)
	t.set_stylebox("pressed", "Button", st.pressed)
	t.set_stylebox("disabled", "Button", st.disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_font("font", "Button", FONT_HEAD)
	t.set_font_size("font_size", "Button", 22)
	t.set_color("font_color", "Button", CYAN.lightened(0.5))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", CYAN.darkened(0.55))

	t.set_stylebox("panel", "PanelContainer", panel_style(PURPLE))
	t.set_stylebox("panel", "Panel", panel_style(PURPLE))

	t.set_stylebox("panel", "TooltipPanel", panel_style(CYAN, Color(INK.r, INK.g, INK.b, 0.95), 12, 2, 10))
	t.set_font("font", "TooltipLabel", FONT_BODY)
	t.set_font_size("font_size", "TooltipLabel", 22)
	t.set_color("font_color", "TooltipLabel", TEXT)
	return t
