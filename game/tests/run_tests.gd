extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: int = 0
	for suite: RefCounted in [SessionKernelTests.new(), WorldCommandTests.new(), RuntimeMotionTests.new(), RuntimeSceneTests.new()]:
		var result: Dictionary = await suite.run()
		print("%s: %d passed, %d failed" % [suite.get_script().get_global_name(), result["passed"], result["failed"]])
		failures += result["failed"]
	quit(1 if failures > 0 else 0)
