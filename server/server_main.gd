extends Node

func _ready() -> void:
	var port := Net.DEFAULT_PORT
	Net.start_server(port)
	print("SERVER: Purple listening on %d" % port)
