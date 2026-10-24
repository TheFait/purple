extends RefCounted
class_name OnlineSettings
## What the online screens remember between launches: the player's name and the last server.

const PATH := "user://online.cfg"
const DEFAULT_ADDRESS := "127.0.0.1"

static func load_name() -> String:
	return String(_load("name", ""))

static func load_address() -> String:
	return String(_load("address", DEFAULT_ADDRESS))

static func save(player_name: String, address: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)   # keep anything else already stored
	cfg.set_value("online", "name", player_name)
	cfg.set_value("online", "address", address)
	cfg.save(PATH)

## Splits "host" or "host:port" into [host, port].
static func parse_address(text: String, default_port: int) -> Array:
	var host := text.strip_edges()
	var port := default_port
	if host.count(":") == 1:
		var parts := host.split(":")
		host = parts[0]
		if parts[1].is_valid_int():
			port = int(parts[1])
	if host.is_empty():
		host = DEFAULT_ADDRESS
	return [host, port]

static func _load(key: String, fallback: Variant) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		return cfg.get_value("online", key, fallback)
	return fallback
