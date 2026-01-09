# GDScript Linter - Static code quality analyzer
# https://poplava.itch.io
class_name GDLintAnalyzer
extends RefCounted
## Core analysis engine - reusable by CLI, plugin, or external tools

const AnalysisConfigClass = preload("res://addons/gdscript-linter/analyzer/analysis-config.gd")
const AnalysisResultClass = preload("res://addons/gdscript-linter/analyzer/analysis-result.gd")
const FileResultClass = preload("res://addons/gdscript-linter/analyzer/file-result.gd")
const IssueClass = preload("res://addons/gdscript-linter/analyzer/issue.gd")

var config
var result
var _start_time: int
var _ignore_handler: GDLintIgnoreHandler

# Checkers
var _naming_checker: GDLintNamingChecker
var _function_checker: GDLintFunctionChecker
var _unused_checker: GDLintUnusedChecker
var _style_checker: GDLintStyleChecker


func _init(p_config = null) -> void:
	config = p_config if p_config else AnalysisConfigClass.get_default()
	_naming_checker = GDLintNamingChecker.new(config)
	_function_checker = GDLintFunctionChecker.new(config, _naming_checker)
	_unused_checker = GDLintUnusedChecker.new(config)
	_style_checker = GDLintStyleChecker.new(config)
	_ignore_handler = GDLintIgnoreHandler.new()


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
	_ignore_handler.initialize(lines)
	var file_result = FileResultClass.create(file_path, lines.size())

	_analyze_file_level(lines, file_path, file_result)
	_function_checker.analyze_functions(lines, file_result, _create_add_issue_callback(file_path), _create_pinned_issue_callback(file_path))
	_check_god_class(file_path, file_result)
	_unused_checker.check_unused(lines, _create_add_issue_callback(file_path))
	_calculate_debt_score(file_result)

	_ignore_handler.clear()
	return file_result


func _create_add_issue_callback(file_path: String) -> Callable:
	return func(line_num: int, severity: String, check_id: String, message: String) -> void:
		_add_issue_from_checker(file_path, line_num, severity, check_id, message)


func _create_pinned_issue_callback(file_path: String) -> Callable:
	return func(line_num: int, severity: String, check_id: String, message: String, actual_value: int, limit: int, context: String) -> void:
		_add_pinned_issue_from_checker(file_path, line_num, severity, check_id, message, actual_value, limit, context)


func _add_issue_from_checker(file_path: String, line_num: int, severity: String, check_id: String, message: String) -> void:
	var sev = _severity_from_string(severity)
	var issue = IssueClass.create(file_path, line_num, sev, check_id, message)
	if config.respect_ignore_directives and _ignore_handler.should_ignore(line_num, check_id):
		result.add_ignored_issue(issue)
		return
	result.add_issue(issue)


func _add_pinned_issue_from_checker(file_path: String, line_num: int, severity: String, check_id: String, message: String, actual_value: int, limit: int, context: String) -> void:
	# Bypass ignore handling if disabled
	if not config.respect_ignore_directives:
		var sev = _severity_from_string(severity)
		var issue = IssueClass.create(file_path, line_num, sev, check_id, message)
		result.add_issue(issue)
		return

	var pin_result := _ignore_handler.check_with_pin(line_num, check_id, actual_value, limit)

	match pin_result.action:
		"ignore":
			# Pinned value matches or no pin - add to ignored
			var sev = _severity_from_string(severity)
			var issue = IssueClass.create(file_path, line_num, sev, check_id, message)
			result.add_ignored_issue(issue)
		"exceeded":
			# Value exceeded pinned amount - report as warning
			var exceeded_msg := "%s exceeded pinned limit (%d → %d, limit is %d)" % [context, pin_result.pinned, actual_value, limit]
			var issue = IssueClass.create(file_path, line_num, IssueClass.Severity.WARNING, check_id + "-exceeded", exceeded_msg)
			result.add_issue(issue)
		"improved":
			# Value improved but still over limit - report as info
			var improved_msg := "%s now %d (was pinned at %d, limit is %d) - consider tightening" % [context, actual_value, pin_result.pinned, limit]
			var issue = IssueClass.create(file_path, line_num, IssueClass.Severity.INFO, check_id + "-improved", improved_msg)
			result.add_issue(issue)
		"unnecessary":
			# Value is now within limit - ignore is unnecessary
			var unnecessary_msg := "Pinned ignore for %s is now unnecessary (%s is %d, limit is %d)" % [check_id, context, actual_value, limit]
			var issue = IssueClass.create(file_path, line_num, IssueClass.Severity.INFO, check_id + "-unnecessary", unnecessary_msg)
			result.add_issue(issue)
		"normal":
			# No ignore directive - process normally
			var sev = _severity_from_string(severity)
			var issue = IssueClass.create(file_path, line_num, sev, check_id, message)
			result.add_issue(issue)


func _severity_from_string(severity: String) -> int:
	match severity:
		"critical": return IssueClass.Severity.CRITICAL
		"warning": return IssueClass.Severity.WARNING
		"info": return IssueClass.Severity.INFO
		_: return IssueClass.Severity.INFO


func _add_issue(file_path: String, line_num: int, severity, check_id: String, message: String) -> void:
	var issue = IssueClass.create(file_path, line_num, severity, check_id, message)
	if config.respect_ignore_directives and _ignore_handler.should_ignore(line_num, check_id):
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
	var context := "File"
	if line_count > config.line_limit_hard:
		_add_pinned_issue_from_checker(file_path, 1, "critical", "file-length",
			"File exceeds %d lines (%d)" % [config.line_limit_hard, line_count],
			line_count, config.line_limit_hard, context)
	elif line_count > config.line_limit_soft:
		_add_pinned_issue_from_checker(file_path, 1, "warning", "file-length",
			"File exceeds %d lines (%d)" % [config.line_limit_soft, line_count],
			line_count, config.line_limit_soft, context)


func _check_god_class(file_path: String, file_result) -> void:
	if not config.check_god_class:
		return

	var public_funcs := 0
	var signal_count: int = file_result.signals_found.size()

	for func_info in file_result.functions:
		var func_name: String = func_info.get("name", "")
		if not func_name.begins_with("_"):
			public_funcs += 1

	# Check public functions limit
	if public_funcs > config.god_class_functions:
		_add_pinned_issue_from_checker(file_path, 1, "warning", "god-class-functions",
			"God class: %d public functions (max %d)" % [public_funcs, config.god_class_functions],
			public_funcs, config.god_class_functions, "Public functions")

	# Check signals limit
	if signal_count > config.god_class_signals:
		_add_pinned_issue_from_checker(file_path, 1, "warning", "god-class-signals",
			"God class: %d signals (max %d)" % [signal_count, config.god_class_signals],
			signal_count, config.god_class_signals, "Signals")


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
