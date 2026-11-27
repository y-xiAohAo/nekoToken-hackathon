extends RefCounted
class_name PhysicsStepResult


var accepted: bool
var error: String
var report_boundary: ReportBoundary


func _init(p_accepted: bool, p_error: String = "", p_report_boundary: ReportBoundary = null) -> void:
	accepted = p_accepted
	error = p_error
	report_boundary = p_report_boundary
