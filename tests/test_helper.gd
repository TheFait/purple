extends RefCounted
class_name TestHelper
## Minimal assert helper for headless SceneTree tests.

var _passed := 0
var _failed := 0

func check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("OK: ", message)
	else:
		_failed += 1
		print("FAIL: ", message)

func eq(actual, expected, message: String) -> void:
	check(actual == expected, "%s (got %s, expected %s)" % [message, actual, expected])

func finish() -> void:
	print("RESULT: %s  (%d passed, %d failed)" % ["PASS" if _failed == 0 else "FAIL", _passed, _failed])
