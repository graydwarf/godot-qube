# GDScript Linter - Unused variable/parameter checker
# https://poplava.itch.io
class_name GDLintUnusedChecker
extends RefCounted

var config
var _declarations: Array = []


func _init(p_config) -> void:
	config = p_config


# Check for unused variables and parameters, calls add_issue_callback for each finding
func check_unused(lines: Array, add_issue_callback: Callable) -> void:
	if not config.check_unused_variables and not config.check_unused_parameters:
		return

	_declarations.clear()

	# Pass 1: Collect all declarations
	_collect_declarations(lines)

	# Pass 2: Find usages
	_find_usages(lines)

	# Pass 3: Report unused
	_report_unused(add_issue_callback)


func _collect_declarations(lines: Array) -> void:
	var in_function := false
	var current_func_name := ""

	for i in range(lines.size()):
		var line: String = lines[i]
		var trimmed := line.strip_edges()
		var line_num := i + 1

		# Track function boundaries
		if trimmed.begins_with("func "):
			in_function = true
			current_func_name = _extract_func_name(trimmed)

			# Extract parameters if enabled
			if config.check_unused_parameters:
				_extract_parameters(trimmed, line_num, current_func_name)

		# Skip class-level variables (only check local variables inside functions)
		if not in_function:
			continue

		# Check for variable declarations
		if config.check_unused_variables:
			_extract_variable_declaration(trimmed, line_num)
			_extract_for_loop_variable(trimmed, line_num)


func _extract_func_name(line: String) -> String:
	var after_func := line.substr(5)  # After "func "
	var paren_pos := after_func.find("(")
	if paren_pos > 0:
		return after_func.substr(0, paren_pos).strip_edges()
	return ""


func _extract_parameters(line: String, line_num: int, func_name: String) -> void:
	# Skip built-in virtual methods where parameters may be intentionally unused
	var virtual_methods := ["_ready", "_process", "_physics_process", "_input",
		"_unhandled_input", "_gui_input", "_notification", "_draw", "_enter_tree",
		"_exit_tree", "_init", "_get", "_set", "_get_property_list"]
	if func_name in virtual_methods:
		return

	var params_start := line.find("(")
	var params_end := line.find(")")
	if params_start < 0 or params_end < 0 or params_end <= params_start:
		return

	var params_str := line.substr(params_start + 1, params_end - params_start - 1).strip_edges()
	if params_str.is_empty():
		return

	var params := params_str.split(",")
	for param in params:
		var param_name := _extract_param_name(param.strip_edges())
		if param_name.is_empty():
			continue

		# Skip underscore-prefixed if configured
		if config.ignore_underscore_prefix and param_name.begins_with("_"):
			continue

		_declarations.append({
			"name": param_name,
			"line": line_num,
			"type": "parameter",
			"used": false
		})


func _extract_param_name(param: String) -> String:
	var param_name := param

	# Remove default value
	var eq_pos := param_name.find("=")
	if eq_pos > 0:
		param_name = param_name.substr(0, eq_pos)

	# Remove type annotation
	var colon_pos := param_name.find(":")
	if colon_pos > 0:
		param_name = param_name.substr(0, colon_pos)

	return param_name.strip_edges()


func _extract_variable_declaration(line: String, line_num: int) -> void:
	# Skip @export variables (used by editor)
	if "@export" in line:
		return

	var var_regex := RegEx.new()
	var_regex.compile("^\\s*(?:@onready\\s+)?var\\s+(\\w+)")

	var match_result := var_regex.search(line)
	if match_result:
		var var_name := match_result.get_string(1)

		# Skip underscore-prefixed if configured
		if config.ignore_underscore_prefix and var_name.begins_with("_"):
			return

		_declarations.append({
			"name": var_name,
			"line": line_num,
			"type": "variable",
			"used": false
		})


func _extract_for_loop_variable(line: String, line_num: int) -> void:
	var for_regex := RegEx.new()
	for_regex.compile("^\\s*for\\s+(\\w+)\\s+in\\s+")

	var match_result := for_regex.search(line)
	if match_result:
		var var_name := match_result.get_string(1)

		# Skip underscore-prefixed if configured
		if config.ignore_underscore_prefix and var_name.begins_with("_"):
			return

		_declarations.append({
			"name": var_name,
			"line": line_num,
			"type": "for_loop",
			"used": false
		})


func _find_usages(lines: Array) -> void:
	for decl in _declarations:
		var decl_name: String = decl.name
		var decl_line: int = decl.line

		var usage_regex := RegEx.new()
		usage_regex.compile("\\b" + decl_name + "\\b")

		for i in range(lines.size()):
			var line: String = lines[i]
			var line_num := i + 1

			# Skip the declaration line itself
			if line_num == decl_line:
				continue

			# Skip comments
			var trimmed := line.strip_edges()
			if trimmed.begins_with("#"):
				continue

			# Remove string literals to avoid false positives
			var line_no_strings := _remove_string_literals(line)

			# Remove comments from the line
			var comment_pos := line_no_strings.find("#")
			if comment_pos >= 0:
				line_no_strings = line_no_strings.substr(0, comment_pos)

			# Check for usage
			if usage_regex.search(line_no_strings):
				decl.used = true
				break


func _remove_string_literals(line: String) -> String:
	var result := line

	var dq_regex := RegEx.new()
	dq_regex.compile("\"[^\"]*\"")
	result = dq_regex.sub(result, "\"\"", true)

	var sq_regex := RegEx.new()
	sq_regex.compile("'[^']*'")
	result = sq_regex.sub(result, "''", true)

	return result


func _report_unused(add_issue_callback: Callable) -> void:
	for decl in _declarations:
		if decl.used:
			continue

		var decl_type: String = decl.type
		var decl_name: String = decl.name
		var decl_line: int = decl.line

		match decl_type:
			"variable":
				if config.check_unused_variables:
					add_issue_callback.call(decl_line, "warning", "unused-variable",
						"Variable '%s' is declared but never used" % decl_name)
			"parameter":
				if config.check_unused_parameters:
					add_issue_callback.call(decl_line, "info", "unused-parameter",
						"Parameter '%s' is declared but never used" % decl_name)
			"for_loop":
				if config.check_unused_variables:
					add_issue_callback.call(decl_line, "warning", "unused-variable",
						"Loop variable '%s' is declared but never used" % decl_name)
