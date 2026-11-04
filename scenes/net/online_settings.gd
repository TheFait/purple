extends RefCounted
class_name OnlineSettings
## What the online screens remember between launches: the player's name and the last server.

const DEFAULT_ADDRESS := "127.0.0.1"
const SESSION_MAX_AGE_SEC := 120   # a saved game older than this (since we last heard from it) is long gone

## Headless runs (the automated tests) keep their own file so they never touch a player's settings.
static func _path() -> String:
	return "user://online_headless.cfg" if DisplayServer.get_name() == "headless" else "user://online.cfg"

static func load_name() -> String:
	return String(_load("name", ""))

static func load_address() -> String:
	return String(_load("address", DEFAULT_ADDRESS))

static func save(player_name: String, address: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(_path())   # keep anything else already stored
	cfg.set_value("online", "name", player_name)
	cfg.set_value("online", "address", address)
	cfg.save(_path())

## Remember the game we are in, so an app that was closed or crashed can rejoin its seat.
static func save_session(token: String, address: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(_path())
	cfg.set_value("session", "token", token)
	cfg.set_value("session", "address", address)
	cfg.set_value("session", "seen", Time.get_unix_time_from_system())
	cfg.save(_path())

## The saved game as {token, address}, or {} when there is none or it is too old to matter.
static func load_session() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(_path()) != OK or not cfg.has_section_key("session", "token"):
		return {}
	var age := Time.get_unix_time_from_system() - float(cfg.get_value("session", "seen", 0.0))
	if age > SESSION_MAX_AGE_SEC:
		return {}
	return {"token": String(cfg.get_value("session", "token", "")), "address": String(cfg.get_value("session", "address", DEFAULT_ADDRESS))}

static func has_session() -> bool:
	return not load_session().is_empty()

## We are still in the game right now: keep the saved session fresh.
static func touch_session() -> void:
	var saved := load_session()
	if not saved.is_empty():
		save_session(saved.token, saved.address)

static func clear_session() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_path()) == OK and cfg.has_section("session"):
		cfg.erase_section("session")
		cfg.save(_path())

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
	if cfg.load(_path()) == OK:
		return cfg.get_value("online", key, fallback)
	return fallback
