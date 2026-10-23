extends CanvasLayer


func _ready():
	$ScreenCover.modulate = "00000000"
	var theme := NeonTheme.build()
	$Control3.theme = theme
	var title: Label = $Control2/Label
	title.add_theme_font_override("font", NeonTheme.FONT_DISPLAY)
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", NeonTheme.PINK)
	title.add_theme_color_override("font_shadow_color", Color(NeonTheme.PINK, 0.8))
	title.add_theme_constant_override("shadow_outline_size", 14)
	# The shine's scroll_speed matches the road's, so it sweeps once per grid line.
	var shine := ShaderMaterial.new()
	shine.shader = load("res://assets/shaders/logo_shine.gdshader")
	var road := $Background/Backdrop.material as ShaderMaterial
	shine.set_shader_parameter("scroll_speed", road.get_shader_parameter("scroll_speed"))
	title.material = shine
	var button: Button = $Control3/Button
	NeonTheme.accent_button(button, NeonTheme.PINK)
	button.add_theme_font_size_override("font_size", 34)


func _on_button_pressed():
	$AnimationPlayer.play("fade_to_black")
	await $AnimationPlayer.animation_finished
	LevelTransition.change_scene("res://scenes/game.tscn")
