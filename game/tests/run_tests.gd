extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: int = 0
	if OS.get_cmdline_user_args().has("--fail-probe"):
		failures += 1
	var suites: Array[RefCounted] = [SessionKernelTests.new(), WorldCommandTests.new(), RuntimeMotionTests.new(), RuntimeSceneTests.new(), SensingRuntimeTests.new(), Module5WorldTests.new(), Module5CycleTests.new(), PlayerAssistantContractTests.new(), RuntimeContactTests.new(), RuntimeRobotContactTests.new(), Module7BDualAgentTests.new(), Module6CheckpointTests.new(), Module6ResetTests.new(), Module6ReportsTests.new(), Module6RoundProtocolTests.new(), Module6SceneTests.new(), Module6RoundTests.new()]
	if OS.get_cmdline_user_args().has("--contact-only"):
		suites = [PlayerAssistantContractTests.new(), RuntimeContactTests.new(), RuntimeRobotContactTests.new()]
	if OS.get_cmdline_user_args().has("--module5-only"):
		suites = [Module5WorldTests.new(), Module5CycleTests.new()]
	if OS.get_cmdline_user_args().has("--module6-only"):
		suites = [Module6CheckpointTests.new(), Module6ResetTests.new(), Module6ReportsTests.new(), Module6RoundProtocolTests.new(), Module6SceneTests.new(), Module6RoundTests.new()]
	if OS.get_cmdline_user_args().has("--module7b-only"):
		suites = [PlayerAssistantContractTests.new(), RuntimeRobotContactTests.new(), Module7BDualAgentTests.new()]
	for suite: RefCounted in suites:
		var result: Dictionary = await suite.run()
		print("%s: %d passed, %d failed" % [suite.get_script().get_global_name(), result["passed"], result["failed"]])
		failures += result["failed"]
	quit(1 if failures > 0 else 0)
