extends SceneTree

func _initialize() -> void:
	var t := TestHelper.new()
	var j := JoinThrottle.new()
	var now := 1_000_000
	t.check(not j.blocked(7, now), "a new peer is not blocked")
	for i in JoinThrottle.MAX_FAILURES - 1:
		j.record_failure(7, now + i * 1000)
	t.check(not j.blocked(7, now + 10_000), "one failure short of the limit is allowed")
	j.record_failure(7, now + 5000)
	t.check(j.blocked(7, now + 6000), "the fifth failure in a minute blocks")
	t.check(j.seconds_left(7, now + 6000) > 0, "and says how long to wait")
	t.check(not j.blocked(8, now + 6000), "another peer is unaffected")
	t.check(not j.blocked(7, now + JoinThrottle.WINDOW_MSEC + 100), "old failures age out")
	j.record_failure(9, now)
	j.forget(9)
	t.check(not j.blocked(9, now), "forgetting a peer clears their failures")
	t.finish()
	quit()
