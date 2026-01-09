# GDScript Linter - Function analysis checker
# https://poplava.itch.io
class_name GDLintFunctionChecker
extends RefCounted

var config
var _naming_checker: GDLintNamingChecker


func _init(p_config, naming_checker: GDLintNamingChecker) -> void:
	config = p_config
	_naming_checker = naming_checker


# Analyzes all functions in a file and returns issues array
# Also populates file_result.functions with function metadata
func analyze_functions(lines: Array, file_result, add_issue_callback: Callable, add_pinned_issue_callback: Callable = Callable()) -> void:
	var current_func: Dictionary = {}
	var in_function := false
	var func_body_lines: Array[String] = []

	for i in range(lines.size()):
		var line: String = lines[i]
		var trimmed := line.strip_edges()

		if trimmed.begins_with("func "):
			# Finalize previous function
			if in_function and current_func:
				_finalize_function(current_func, func_body_lines, file_result, add_issue_callback, add_pinned_issue_callback)

			# Start new function
			in_function = true
			func_body_lines = []
			current_func = _parse_function_signature(trimmed, i + 1)

		elif in_function:
			func_body_lines.append(line)

	# Finalize last function
	if in_function and current_func:
		_finalize_function(current_func, func_body_lines, file_result, add_issue_callback, add_pinned_issue_callback)


func _parse_function_signature(line: String, line_num: int) -> Dictionary:
	var func_data := {
		"name": "",
		"line": line_num,
		"params": 0,
		"has_return_type": "->" in line
	}

	# Extract function name
	var after_func := line.substr(5)  # After "func "
	var paren_pos := after_func.find("(")
	if paren_pos > 0:
		func_data.name = after_func.substr(0, paren_pos).strip_edges()

	# Count parameters
	var params_start := line.find("(")
	var params_end := line.find(")")
	if params_start > 0 and params_end > params_start:
		var params_str := line.substr(params_start + 1, params_end - params_start - 1)
		if params_str.strip_edges() != "":
			func_data.params = params_str.split(",").size()

	return func_data


func _finalize_function(func_data: Dictionary, body_lines: Array, file_result, add_issue_callback: Callable, add_pinned_issue_callback: Callable) -> void:
	var line_count := body_lines.size() + 1  # +1 for signature
	var max_nesting := _calculate_max_nesting(body_lines)
	var is_empty := _is_empty_function(body_lines)
	var complexity := _calculate_cyclomatic_complexity(body_lines)

	func_data["line_count"] = line_count
	func_data["max_nesting"] = max_nesting
	func_data["is_empty"] = is_empty
	func_data["complexity"] = complexity
	file_result.add_function(func_data)

	_check_function_length(func_data, line_count, add_pinned_issue_callback)
	_check_parameter_count(func_data, add_pinned_issue_callback)
	_check_nesting_depth(func_data, max_nesting, add_pinned_issue_callback)
	_check_empty_function(func_data, is_empty, add_issue_callback)
	_check_complexity(func_data, complexity, add_pinned_issue_callback)
	_check_return_type(func_data, add_issue_callback)
	_check_naming(func_data, add_issue_callback)


func _check_function_length(func_data: Dictionary, line_count: int, add_pinned_callback: Callable) -> void:
	if not config.check_function_length:
		return
	var func_line: int = func_data.line
	var func_name: String = func_data.name
	var context := "Function '%s'" % func_name
	if line_count > config.function_line_critical:
		add_pinned_callback.call(func_line, "critical", "long-function",
			"Function '%s' exceeds %d lines (%d)" % [func_name, config.function_line_critical, line_count],
			line_count, config.function_line_critical, context)
	elif line_count > config.function_line_limit:
		add_pinned_callback.call(func_line, "warning", "long-function",
			"Function '%s' exceeds %d lines (%d)" % [func_name, config.function_line_limit, line_count],
			line_count, config.function_line_limit, context)


func _check_parameter_count(func_data: Dictionary, add_pinned_callback: Callable) -> void:
	if not config.check_parameters or func_data.params <= config.max_parameters:
		return
	var context := "Function '%s'" % func_data.name
	add_pinned_callback.call(func_data.line, "warning", "too-many-params",
		"Function '%s' has %d parameters (max %d)" % [func_data.name, func_data.params, config.max_parameters],
		func_data.params, config.max_parameters, context)


func _check_nesting_depth(func_data: Dictionary, max_nesting: int, add_pinned_callback: Callable) -> void:
	if not config.check_nesting or max_nesting <= config.max_nesting:
		return
	var context := "Function '%s'" % func_data.name
	add_pinned_callback.call(func_data.line, "warning", "deep-nesting",
		"Function '%s' has %d nesting levels (max %d)" % [func_data.name, max_nesting, config.max_nesting],
		max_nesting, config.max_nesting, context)


func _check_empty_function(func_data: Dictionary, is_empty: bool, add_issue_callback: Callable) -> void:
	if not config.check_empty_functions or not is_empty:
		return
	add_issue_callback.call(func_data.line, "info", "empty-function",
		"Function '%s' is empty or contains only 'pass'" % func_data.name)


func _check_complexity(func_data: Dictionary, complexity: int, add_pinned_callback: Callable) -> void:
	if not config.check_cyclomatic_complexity:
		return
	var func_line: int = func_data.line
	var func_name: String = func_data.name
	var context := "Function '%s'" % func_name
	if complexity > config.cyclomatic_critical:
		add_pinned_callback.call(func_line, "critical", "high-complexity",
			"Function '%s' has complexity %d (max %d)" % [func_name, complexity, config.cyclomatic_critical],
			complexity, config.cyclomatic_critical, context)
	elif complexity > config.cyclomatic_warning:
		add_pinned_callback.call(func_line, "warning", "high-complexity",
			"Function '%s' has complexity %d (warning at %d)" % [func_name, complexity, config.cyclomatic_warning],
			complexity, config.cyclomatic_warning, context)


func _check_return_type(func_data: Dictionary, add_issue_callback: Callable) -> void:
	if not config.check_missing_return_type or func_data.has_return_type:
		return
	# Skip _init, _ready, _process, etc. (built-in overrides)
	if not func_data.name.begins_with("_"):
		add_issue_callback.call(func_data.line, "info", "missing-return-type",
			"Function '%s' has no return type annotation" % func_data.name)


func _check_naming(func_data: Dictionary, add_issue_callback: Callable) -> void:
	if not _naming_checker:
		return
	var naming_issue = _naming_checker.check_function_naming(func_data.name, func_data.line)
	if naming_issue:
		add_issue_callback.call(naming_issue.line, naming_issue.severity, naming_issue.check_id, naming_issue.message)


func _calculate_max_nesting(body_lines: Array) -> int:
	var max_indent := 0
	var base_indent := -1

	for line in body_lines:
		if line.strip_edges() == "":
			continue

		var indent := _get_indent_level(line)
		if base_indent < 0:
			base_indent = indent

		var relative_indent := indent - base_indent
		if relative_indent > max_indent:
			max_indent = relative_indent

	return max_indent


func _is_empty_function(body_lines: Array) -> bool:
	for line in body_lines:
		var trimmed: String = line.strip_edges()
		if trimmed != "" and trimmed != "pass":
			return false
	return true


func _get_indent_level(line: String) -> int:
	var spaces := 0
	for c in line:
		if c == '\t':
			spaces += 4
		elif c == ' ':
			spaces += 1
		else:
			break
	return spaces / 4


# gdlint:ignore-next-line:high-complexity - Complexity calculation is naturally complex
func _calculate_cyclomatic_complexity(body_lines: Array) -> int:
	var complexity := 1  # Base complexity

	for line in body_lines:
		var trimmed: String = line.strip_edges()

		# Skip comments
		if trimmed.begins_with("#"):
			continue

		# Count decision points
		if trimmed.begins_with("if ") or " if " in trimmed:
			complexity += 1
		if trimmed.begins_with("elif "):
			complexity += 1
		if trimmed.begins_with("for ") or " for " in trimmed:
			complexity += 1
		if trimmed.begins_with("while "):
			complexity += 1
		if trimmed.begins_with("match "):
			complexity += 1
		# Count boolean operators (each adds a path)
		complexity += trimmed.count(" and ")
		complexity += trimmed.count(" or ")
		# Ternary operator
		complexity += trimmed.count(" if ") if not trimmed.begins_with("if ") else 0

	return complexity
