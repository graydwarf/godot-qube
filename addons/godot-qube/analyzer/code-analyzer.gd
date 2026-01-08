# Godot Qube - Code quality analyzer for GDScript
# https://poplava.itch.io
class_name QubeAnalyzer
extends RefCounted
## Core analysis engine - reusable by CLI, plugin, or external tools

const AnalysisConfigClass = preload("res://addons/godot-qube/analyzer/analysis-config.gd")
const AnalysisResultClass = preload("res://addons/godot-qube/analyzer/analysis-result.gd")
const FileResultClass = preload("res://addons/godot-qube/analyzer/file-result.gd")
const IssueClass = preload("res://addons/godot-qube/analyzer/issue.gd")

const IGNORE_PATTERN := "qube:ignore"
const IGNORE_NEXT_LINE_PATTERN := "qube:ignore-next-line"

var config
var result
var _start_time: int
var _current_lines: Array = []
var _current_file_path: String = ""

# Checkers
var _naming_checker: QubeNamingChecker
var _function_checker: QubeFunctionChecker
var _unused_checker: QubeUnusedChecker
var _style_checker: QubeStyleChecker


func _init(p_config = null) -> void:
	config = p_config if p_config else AnalysisConfigClass.get_default()
	_naming_checker = QubeNamingChecker.new(config)
	_function_checker = QubeFunctionChecker.new(config, _naming_checker)
	_unused_checker = QubeUnusedChecker.new(config)
	_style_checker = QubeStyleChecker.new(config)


func analyze_directory(path: String):
	result = AnalysisResultClass.new()
	_start_time = Time.get_ticks_msec()
	_scan_directory(path)
	result.analysis_time_ms = Time.get_ticks_msec() - _start_time
	return result


func analyze_file(file_path: String):
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("Failed to open file: %s" % file_path)
		return null

	var content := file.get_as_text()
	return analyze_content(content, file_path)


func analyze_content(content: String, file_path: String):
	var lines := content.split("\n")
	_current_lines = lines
	_current_file_path = file_path
	var file_result = FileResultClass.create(file_path, lines.size())

	_analyze_file_level(lines, file_path, file_result)
	_function_checker.analyze_functions(lines, file_result, _create_add_issue_callback(file_path))
	_check_god_class(file_path, file_result)
	_unused_checker.check_unused(lines, _create_add_issue_callback(file_path))
	_calculate_debt_score(file_result)

	_current_lines = []
	_current_file_path = ""
	return file_result


func _create_add_issue_callback(file_path: String) -> Callable:
	return func(line_num: int, severity: String, check_id: String, message: String) -> void:
		_add_issue_from_checker(file_path, line_num, severity, check_id, message)


func _add_issue_from_checker(file_path: String, line_num: int, severity: String, check_id: String, message: String) -> void:
	var sev = _severity_from_string(severity)
	var issue = IssueClass.create(file_path, line_num, sev, check_id, message)
	if _should_ignore_issue(line_num, check_id):
		result.add_ignored_issue(issue)
		return
	result.add_issue(issue)


func _severity_from_string(severity: String) -> int:
	match severity:
		"critical": return IssueClass.Severity.CRITICAL
		"warning": return IssueClass.Severity.WARNING
		"info": return IssueClass.Severity.INFO
		_: return IssueClass.Severity.INFO


# Check if an issue should be ignored based on inline comments
func _should_ignore_issue(line_num: int, check_id: String) -> bool:
	if _current_lines.is_empty():
		return false

	var line_idx := line_num - 1
	if line_idx < 0 or line_idx >= _current_lines.size():
		return false

	var current_line: String = _current_lines[line_idx]

	# Check current line for # qube:ignore or # qube:ignore:check-id
	if IGNORE_PATTERN in current_line:
		var ignore_pos := current_line.find(IGNORE_PATTERN)
		if ignore_pos >= 0 and not IGNORE_NEXT_LINE_PATTERN in current_line:
			var after_ignore := current_line.substr(ignore_pos + IGNORE_PATTERN.length())
			if after_ignore.begins_with(":"):
				var specific_check := after_ignore.substr(1).split(" ")[0].split("\t")[0].strip_edges()
				return specific_check == check_id
			else:
				return true

	# Check previous line for # qube:ignore-next-line
	if line_idx > 0:
		var prev_line: String = _current_lines[line_idx - 1]
		if IGNORE_NEXT_LINE_PATTERN in prev_line:
			var ignore_pos := prev_line.find(IGNORE_NEXT_LINE_PATTERN)
			if ignore_pos >= 0:
				var after_ignore := prev_line.substr(ignore_pos + IGNORE_NEXT_LINE_PATTERN.length())
				if after_ignore.begins_with(":"):
					var specific_check := after_ignore.substr(1).split(" ")[0].split("\t")[0].strip_edges()
					return specific_check == check_id
				else:
					return true

	return false


func _add_issue(file_path: String, line_num: int, severity, check_id: String, message: String) -> void:
	var issue = IssueClass.create(file_path, line_num, severity, check_id, message)
	if _should_ignore_issue(line_num, check_id):
		result.add_ignored_issue(issue)
		return
	result.add_issue(issue)


func _scan_directory(path: String) -> void:
	var normalized_path := path
	if OS.has_feature("windows") and not path.begins_with("res://") and not path.begins_with("user://"):
		normalized_path = path.replace("/", "\\")
	var dir := DirAccess.open(normalized_path)
	if not dir:
		push_error("Failed to open directory: %s" % path)
		return

	if config.respect_gdignore and dir.file_exists(".gdignore"):
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		var full_path := path.path_join(file_name)

		if dir.current_is_dir():
			if not file_name.begins_with(".") and not config.is_path_excluded(full_path):
				_scan_directory(full_path)
		elif file_name.ends_with(".gd"):
			if not config.is_path_excluded(full_path):
				var file_result = analyze_file(full_path)
				if file_result:
					result.add_file_result(file_result)

		file_name = dir.get_next()

	dir.list_dir_end()


func _analyze_file_level(lines: Array, file_path: String, file_result) -> void:
	var line_count := lines.size()

	# Check file length
	if config.check_file_length:
		_check_file_length(file_path, line_count)

	# Line-by-line checks
	for i in range(line_count):
		var line: String = lines[i]
		var trimmed := line.strip_edges()
		var line_num := i + 1

		# Style checks (long lines, TODO, print, magic numbers, etc.)
		var style_issues := _style_checker.check_line(line, trimmed, line_num, file_result)
		for issue in style_issues:
			_add_issue(file_path, issue.line, _severity_from_string(issue.severity), issue.check_id, issue.message)

		# Naming convention checks
		if config.check_naming_conventions:
			var naming_issues := _naming_checker.check_line(line, line_num)
			for issue in naming_issues:
				_add_issue(file_path, issue.line, _severity_from_string(issue.severity), issue.check_id, issue.message)


func _check_file_length(file_path: String, line_count: int) -> void:
	if line_count > config.line_limit_hard:
		_add_issue(file_path, 1, IssueClass.Severity.CRITICAL, "file-length",
			"File exceeds %d lines (%d)" % [config.line_limit_hard, line_count])
	elif line_count > config.line_limit_soft:
		_add_issue(file_path, 1, IssueClass.Severity.WARNING, "file-length",
			"File exceeds %d lines (%d)" % [config.line_limit_soft, line_count])


func _check_god_class(file_path: String, file_result) -> void:
	if not config.check_god_class:
		return

	var public_funcs := 0
	var signal_count: int = file_result.signals_found.size()

	for func_info in file_result.functions:
		var func_name: String = func_info.get("name", "")
		if not func_name.begins_with("_"):
			public_funcs += 1

	var is_god_class := false
	var reasons: Array[String] = []

	if public_funcs > config.god_class_functions:
		is_god_class = true
		reasons.append("%d public functions (max %d)" % [public_funcs, config.god_class_functions])

	if signal_count > config.god_class_signals:
		is_god_class = true
		reasons.append("%d signals (max %d)" % [signal_count, config.god_class_signals])

	if is_god_class:
		_add_issue(file_path, 1, IssueClass.Severity.WARNING, "god-class",
			"God class detected: %s" % ", ".join(reasons))


func _calculate_debt_score(file_result) -> void:
	var score := 0
	var line_count: int = file_result.line_count

	if line_count > config.line_limit_hard:
		score += 50
	elif line_count > config.line_limit_soft:
		score += 20

	for func_info in file_result.functions:
		var func_lines: int = func_info.get("line_count", 0)
		if func_lines > config.function_line_critical:
			score += 20
		elif func_lines > config.function_line_limit:
			score += 10

		if func_info.get("params", 0) > config.max_parameters:
			score += 5

		if func_info.get("max_nesting", 0) > config.max_nesting:
			score += 5

		var complexity: int = func_info.get("complexity", 0)
		if complexity > config.cyclomatic_critical:
			score += 25
		elif complexity > config.cyclomatic_warning:
			score += 10

	file_result.debt_score = score
