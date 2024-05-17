extends CanvasLayer


func _ready():
	$ScreenCover.modulate = "00000000"


func _on_button_pressed():
	$AnimationPlayer.play("fade_to_black")
	await $AnimationPlayer.animation_finished
	LevelTransition.change_scene("res://scenes/game.tscn")
