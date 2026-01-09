# GDScript Linter - Static code quality analyzer
# https://poplava.itch.io
class_name GDLintResult
extends RefCounted
## Holds complete results from a code analysis run

const IssueClass = preload("res://addons/gdscript-linter/analyzer/issue.gd")
const FileResultClass = preload("res://addons/gdscript-linter/analyzer/file-result.gd")

var issues: Array = []
var ignored_issues: Array = []
var files_analyzed: int = 0
var total_lines: int = 0
var analysis_time_ms: int = 0

# Per-file data for detailed reporting
var file_results: Array = []

func add_issue(issue) -> void:
	issues.append(issue)

func add_ignored_issue(issue) -> void:
	ignored_issues.append(issue)

func add_file_result(result) -> void:
	file_results.append(result)
	files_analyzed += 1
	total_lines += result.line_count

func get_issues_by_severity(severity: int) -> Array:
	var filtered: Array = []
	for issue in issues:
		if issue.severity == severity:
			filtered.append(issue)
	return filtered

func get_issues_for_file(path: String) -> Array:
	var filtered: Array = []
	for issue in issues:
		if issue.file_path == path:
			filtered.append(issue)
	return filtered

func get_critical_count() -> int:
	return get_issues_by_severity(IssueClass.Severity.CRITICAL).size()

func get_warning_count() -> int:
	return get_issues_by_severity(IssueClass.Severity.WARNING).size()

func get_info_count() -> int:
	return get_issues_by_severity(IssueClass.Severity.INFO).size()

func get_total_debt_score() -> int:
	var score := 0
	for file_result in file_results:
		score += file_result.debt_score
	return score

func get_exit_code() -> int:
	if get_critical_count() > 0:
		return 2
	if get_warning_count() > 0:
		return 1
	return 0

func to_dict() -> Dictionary:
	var issues_array := []
	for issue in issues:
		issues_array.append(issue.to_dict())

	var files_array := []
	for file_result in file_results:
		files_array.append(file_result.to_dict())

	return {
		"summary": {
			"files_analyzed": files_analyzed,
			"total_lines": total_lines,
			"total_issues": issues.size(),
			"critical": get_critical_count(),
			"warnings": get_warning_count(),
			"info": get_info_count(),
			"debt_score": get_total_debt_score(),
			"analysis_time_ms": analysis_time_ms
		},
		"issues": issues_array,
		"files": files_array
	}
