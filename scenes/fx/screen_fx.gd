class_name ScreenFx
extends Node
## Juice toolbox: screen shake, flash, chromatic aberration, confetti and slam text.
## Builds its own post-process layer in code; the UI just calls the methods below.

const POST_SHADER := preload("res://assets/shaders/post_fx.gdshader")

var _post_mat: ShaderMaterial
var _post_layer: CanvasLayer
var _shake_layers: Array[CanvasLayer] = []
var _host: Control
var _shake_amp: float = 0.0
var _shake_decay: float = 0.0
var _vignette_tween: Tween
var _vignette: float = 0.25   # mirrors the shader default

func setup(host: Control, shake_layers: Array[CanvasLayer]) -> void:
	_host = host
	_shake_layers = shake_layers
	_post_layer = CanvasLayer.new()
	_post_layer.layer = 50
	add_child(_post_layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = POST_SHADER
	rect.material = _post_mat
	_post_layer.add_child(rect)

func _process(delta: float) -> void:
	if _shake_amp <= 0.01:
		if _shake_amp != 0.0:
			_shake_amp = 0.0
			_apply_shake(Vector2.ZERO)
		return
	_apply_shake(Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake_amp)
	_shake_amp = max(0.0, _shake_amp - _shake_decay * delta)

func _apply_shake(v: Vector2) -> void:
	for l in _shake_layers:
		l.offset = v

## Trauma-style shake: amplitude in pixels, decays linearly over `duration`.
func shake(amplitude: float, duration: float = 0.5) -> void:
	_shake_amp = max(_shake_amp, amplitude)
	_shake_decay = _shake_amp / max(0.05, duration)

func flash(color: Color, peak: float = 0.6, duration: float = 0.35) -> void:
	_post_mat.set_shader_parameter("flash_color", color)
	_tween_param("flash", peak, 0.0, duration, 0.02)

func aberrate(amount: float, duration: float = 0.6) -> void:
	_tween_param("aberration", amount, 0.0, duration, 0.0)

## Darken the edges (suspense) — hold with set_vignette, release by calling with 0.25.
func set_vignette(target: float, duration: float = 0.4, color: Color = Color.BLACK) -> void:
	_post_mat.set_shader_parameter("vignette_color", color)
	if _vignette_tween:
		_vignette_tween.kill()
	_vignette_tween = create_tween()
	_vignette_tween.tween_method(_set_vignette_value, _vignette, target, maxf(duration, 0.001))

func _set_vignette_value(v: float) -> void:
	_vignette = v
	_post_mat.set_shader_parameter("vignette", v)

func _tween_param(param: String, from: float, to: float, duration: float, attack: float) -> void:
	var tw := create_tween()
	if attack > 0.0:
		tw.tween_method(func(v: float): _post_mat.set_shader_parameter(param, v), 0.0, from, attack)
	else:
		_post_mat.set_shader_parameter(param, from)
	tw.tween_method(func(v: float): _post_mat.set_shader_parameter(param, v), from, to, duration).set_ease(Tween.EASE_OUT)

## One-shot burst of confetti squares from a global position.
func confetti(at: Vector2, amount: int, colors: PackedColorArray, power: float = 1.0) -> void:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = 1.6
	p.spread = 180.0
	p.gravity = Vector2(0, 520)
	p.initial_velocity_min = 260.0 * power
	p.initial_velocity_max = 620.0 * power
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.scale_amount_min = 5.0
	p.scale_amount_max = 11.0
	var initial := Gradient.new()
	var offsets := PackedFloat32Array()
	for i in colors.size():
		offsets.append(float(i) / max(1, colors.size() - 1))
	initial.offsets = offsets
	initial.colors = colors
	p.color_initial_ramp = initial
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.6, 1.0])
	fade.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	p.color_ramp = fade
	p.position = at
	_host.add_child(p)
	p.restart()
	get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)

## Slams a big word onto the screen (scale-in overshoot, hold, fade). Awaitable.
func slam_text(text: String, color: Color, size: int = 96, hold: float = 0.7, font: Font = null) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 14)
	l.add_theme_color_override("font_shadow_color", Color(color.r, color.g, color.b, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.pivot_offset = _host.size * 0.5
	l.scale = Vector2(3.0, 3.0)
	l.modulate.a = 0.0
	l.rotation = randf_range(-0.08, 0.08)
	_host.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 1.0, 0.1)
	tw.chain().tween_interval(hold)
	tw.chain().tween_property(l, "modulate:a", 0.0, 0.3)
	await tw.finished
	l.queue_free()
