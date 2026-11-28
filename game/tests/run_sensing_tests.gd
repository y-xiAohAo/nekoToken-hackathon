extends SceneTree

func _initialize() -> void:
	var failures: int = 0
	if OS.get_cmdline_user_args().has("--fail-probe"):
		failures += 1
	for suite: RefCounted in [SensingGeometryTests.new(), SensingKernelTests.new()]:
		var result: Dictionary = suite.run()
		print("%s: %d passed, %d failed" % [suite.get_script().get_global_name(), result.passed, result.failed])
		failures += result.failed
	quit(1 if failures > 0 else 0)
