class_name CodeAnalyzer
extends RefCounted
## Core code analysis engine - reusable by CLI, plugin, or external tools

var config: AnalysisConfig
var result: AnalysisResult
var _start_time: int


func _init(p_config: AnalysisConfig = null) -> void:
	config = p_config if p_config else AnalysisConfig.get_default()


func analyze_directory(path: String) -> AnalysisResult:
	result = AnalysisResult.new()
	_start_time = Time.get_ticks_msec()

	_scan_directory(path)

	result.analysis_time_ms = Time.get_ticks_msec() - _start_time
	return result


func analyze_file(file_path: String) -> FileResult:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("Failed to open file: %s" % file_path)
		return null

	var content := file.get_as_text()
	return analyze_content(content, file_path)


func analyze_content(content: String, file_path: String) -> FileResult:
	var lines := content.split("\n")
	var file_result := FileResult.create(file_path, lines.size())

	_analyze_file_level(lines, file_path, file_result)
	_analyze_functions(lines, file_path, file_result)
	_check_god_class(file_path, file_result)
	_calculate_debt_score(file_result)

	return file_result


func _scan_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		push_error("Failed to open directory: %s" % path)
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
				var file_result := analyze_file(full_path)
				if file_result:
					result.add_file_result(file_result)
					# Add file's issues to main result
					for issue in _get_issues_for_file_result(file_result, full_path):
						result.add_issue(issue)

		file_name = dir.get_next()

	dir.list_dir_end()


func _analyze_file_level(lines: Array, file_path: String, file_result: FileResult) -> void:
	var line_count := lines.size()

	# Check file length
	if config.check_file_length:
		if line_count > config.line_limit_hard:
			result.add_issue(Issue.create(
				file_path, 1, Issue.Severity.CRITICAL, "file-length",
				"File exceeds %d lines (%d)" % [config.line_limit_hard, line_count]
			))
		elif line_count > config.line_limit_soft:
			result.add_issue(Issue.create(
				file_path, 1, Issue.Severity.WARNING, "file-length",
				"File exceeds %d lines (%d)" % [config.line_limit_soft, line_count]
			))

	# Line-by-line checks
	for i in range(line_count):
		var line: String = lines[i]
		var trimmed := line.strip_edges()
		var line_num := i + 1  # 1-based

		# Long lines
		if config.check_long_lines and line.length() > config.max_line_length:
			result.add_issue(Issue.create(
				file_path, line_num, Issue.Severity.INFO, "long-line",
				"Line exceeds %d chars (%d)" % [config.max_line_length, line.length()]
			))

		# TODO/FIXME comments
		if config.check_todo_comments:
			for pattern in config.todo_patterns:
				if pattern in trimmed:
					var severity := Issue.Severity.INFO if pattern == "TODO" else Issue.Severity.WARNING
					result.add_issue(Issue.create(
						file_path, line_num, severity, "todo-comment",
						"%s: %s" % [pattern, trimmed.substr(trimmed.find(pattern))]
					))
					break  # Only report once per line

		# Print statements
		if config.check_print_statements:
			var is_whitelisted := false
			for whitelist_item in config.print_whitelist:
				if whitelist_item in trimmed:
					is_whitelisted = true
					break

			if not is_whitelisted:
				for pattern in config.print_patterns:
					if pattern in trimmed and not trimmed.begins_with("#"):
						result.add_issue(Issue.create(
							file_path, line_num, Issue.Severity.WARNING, "print-statement",
							"Debug print statement: %s" % trimmed.substr(0, mini(60, trimmed.length()))
						))
						break

		# Track signals
		if trimmed.begins_with("signal "):
			var signal_name := trimmed.substr(7).split("(")[0].strip_edges()
			file_result.signals_found.append(signal_name)

		# Track dependencies
		if trimmed.begins_with("preload(") or trimmed.begins_with("load("):
			var dep := _extract_string_arg(trimmed)
			if dep:
				file_result.dependencies.append(dep)

		# Magic numbers detection
		if config.check_magic_numbers:
			_check_magic_numbers(trimmed, file_path, line_num)

		# Commented-out code detection
		if config.check_commented_code:
			_check_commented_code(trimmed, file_path, line_num)

		# Missing type hints for variables
		if config.check_missing_types:
			_check_variable_type_hints(trimmed, file_path, line_num)


func _analyze_functions(lines: Array, file_path: String, file_result: FileResult) -> void:
	var current_func: Dictionary = {}
	var in_function := false
	var func_start_line := 0
	var func_body_lines: Array[String] = []

	for i in range(lines.size()):
		var line: String = lines[i]
		var trimmed := line.strip_edges()

		if trimmed.begins_with("func "):
			# Finalize previous function
			if in_function and current_func:
				_finalize_function(current_func, func_body_lines, file_path, file_result)

			# Start new function
			in_function = true
			func_start_line = i
			func_body_lines = []
			current_func = _parse_function_signature(trimmed, i + 1)

		elif in_function:
			func_body_lines.append(line)

	# Finalize last function
	if in_function and current_func:
		_finalize_function(current_func, func_body_lines, file_path, file_result)


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


func _finalize_function(func_data: Dictionary, body_lines: Array, file_path: String, file_result: FileResult) -> void:
	var line_count := body_lines.size() + 1  # +1 for signature
	var max_nesting := _calculate_max_nesting(body_lines)
	var is_empty := _is_empty_function(body_lines)
	var complexity := _calculate_cyclomatic_complexity(body_lines)

	func_data["line_count"] = line_count
	func_data["max_nesting"] = max_nesting
	func_data["is_empty"] = is_empty
	func_data["complexity"] = complexity
	file_result.add_function(func_data)

	var func_line: int = func_data.line

	# Function length check
	if config.check_function_length:
		if line_count > config.function_line_critical:
			result.add_issue(Issue.create(
				file_path, func_line, Issue.Severity.CRITICAL, "long-function",
				"Function '%s' exceeds %d lines (%d)" % [func_data.name, config.function_line_critical, line_count]
			))
		elif line_count > config.function_line_limit:
			result.add_issue(Issue.create(
				file_path, func_line, Issue.Severity.WARNING, "long-function",
				"Function '%s' exceeds %d lines (%d)" % [func_data.name, config.function_line_limit, line_count]
			))

	# Parameter count check
	if config.check_parameters and func_data.params > config.max_parameters:
		result.add_issue(Issue.create(
			file_path, func_line, Issue.Severity.WARNING, "too-many-params",
			"Function '%s' has %d parameters (max %d)" % [func_data.name, func_data.params, config.max_parameters]
		))

	# Nesting depth check
	if config.check_nesting and max_nesting > config.max_nesting:
		result.add_issue(Issue.create(
			file_path, func_line, Issue.Severity.WARNING, "deep-nesting",
			"Function '%s' has %d nesting levels (max %d)" % [func_data.name, max_nesting, config.max_nesting]
		))

	# Empty function check
	if config.check_empty_functions and is_empty:
		result.add_issue(Issue.create(
			file_path, func_line, Issue.Severity.INFO, "empty-function",
			"Function '%s' is empty or contains only 'pass'" % func_data.name
		))

	# Cyclomatic complexity check
	if config.check_cyclomatic_complexity:
		if complexity > config.cyclomatic_critical:
			result.add_issue(Issue.create(
				file_path, func_line, Issue.Severity.CRITICAL, "high-complexity",
				"Function '%s' has complexity %d (max %d)" % [func_data.name, complexity, config.cyclomatic_critical]
			))
		elif complexity > config.cyclomatic_warning:
			result.add_issue(Issue.create(
				file_path, func_line, Issue.Severity.WARNING, "high-complexity",
				"Function '%s' has complexity %d (warning at %d)" % [func_data.name, complexity, config.cyclomatic_warning]
			))

	# Missing return type check
	if config.check_missing_types and not func_data.has_return_type:
		# Skip _init, _ready, _process, etc. (built-in overrides)
		var func_name: String = func_data.name
		if not func_name.begins_with("_"):
			result.add_issue(Issue.create(
				file_path, func_line, Issue.Severity.INFO, "missing-return-type",
				"Function '%s' has no return type annotation" % func_name
			))


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


func _extract_string_arg(line: String) -> String:
	var start := line.find("\"")
	var end := line.rfind("\"")
	if start >= 0 and end > start:
		return line.substr(start + 1, end - start - 1)
	return ""


func _get_issues_for_file_result(_file_result: FileResult, _file_path: String) -> Array[Issue]:
	# Issues are added directly during analysis, this is for potential future use
	return []


func _calculate_debt_score(file_result: FileResult) -> void:
	var score := 0
	var line_count := file_result.line_count

	# Line count scoring
	if line_count > config.line_limit_hard:
		score += 50
	elif line_count > config.line_limit_soft:
		score += 20

	# Function scoring
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

		# Complexity scoring
		var complexity: int = func_info.get("complexity", 0)
		if complexity > config.cyclomatic_critical:
			score += 25
		elif complexity > config.cyclomatic_warning:
			score += 10

	file_result.debt_score = score


func _check_magic_numbers(line: String, file_path: String, line_num: int) -> void:
	# Skip comments, const declarations, and common safe patterns
	if line.begins_with("#") or line.begins_with("const "):
		return
	if "enum " in line or "@export" in line:
		return

	# Regex to find numbers (int and float)
	var regex := RegEx.new()
	regex.compile("(?<![a-zA-Z_])(-?\\d+\\.?\\d*)(?![a-zA-Z_\\d])")

	for regex_match in regex.search_all(line):
		var num_str: String = regex_match.get_string()
		var num_val: float = float(num_str)

		# Skip allowed numbers
		if num_val in config.allowed_numbers:
			continue

		# Skip if it's part of a variable name or in a string
		var pos: int = regex_match.get_start()
		if pos > 0 and line[pos - 1] == '"':
			continue

		result.add_issue(Issue.create(
			file_path, line_num, Issue.Severity.INFO, "magic-number",
			"Magic number %s (consider using a named constant)" % num_str
		))
		break  # Only report first magic number per line


func _check_commented_code(line: String, file_path: String, line_num: int) -> void:
	for pattern in config.commented_code_patterns:
		if line.begins_with(pattern) or ("\t" + pattern) in line or (" " + pattern) in line:
			result.add_issue(Issue.create(
				file_path, line_num, Issue.Severity.INFO, "commented-code",
				"Commented-out code detected"
			))
			return


func _check_variable_type_hints(line: String, file_path: String, line_num: int) -> void:
	# Check for untyped variable declarations
	if not line.begins_with("var ") and not line.begins_with("\tvar "):
		return

	# Skip if it has a type annotation
	if ":" in line.split("=")[0]:
		return

	# Skip @onready and inferred types from literals
	if "@onready" in line:
		return

	# Extract variable name
	var after_var := line.strip_edges().substr(4)  # After "var "
	var var_name := after_var.split("=")[0].split(":")[0].strip_edges()

	result.add_issue(Issue.create(
		file_path, line_num, Issue.Severity.INFO, "missing-type-hint",
		"Variable '%s' has no type annotation" % var_name
	))


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
		# Count match arms (patterns before :)
		if ":" in trimmed and not trimmed.begins_with("if") and not trimmed.begins_with("for"):
			if _get_indent_level(line) > 0:  # Inside a match block
				var before_colon := trimmed.split(":")[0]
				if not "func" in before_colon and not "class" in before_colon:
					if before_colon.strip_edges() != "" and not before_colon.begins_with("#"):
						# This might be a match arm
						pass
		# Count boolean operators (each adds a path)
		complexity += trimmed.count(" and ")
		complexity += trimmed.count(" or ")
		# Ternary operator
		complexity += trimmed.count(" if ") if not trimmed.begins_with("if ") else 0

	return complexity


func _check_god_class(file_path: String, file_result: FileResult) -> void:
	if not config.check_god_class:
		return

	var public_funcs := 0
	var signal_count := file_result.signals_found.size()
	var export_count := 0

	# Count public functions (not starting with _)
	for func_info in file_result.functions:
		var func_name: String = func_info.get("name", "")
		if not func_name.begins_with("_"):
			public_funcs += 1

	# Count exports by re-reading (we'd need to track this during analysis)
	# For now, estimate from dependencies or skip

	var is_god_class := false
	var reasons: Array[String] = []

	if public_funcs > config.god_class_functions:
		is_god_class = true
		reasons.append("%d public functions (max %d)" % [public_funcs, config.god_class_functions])

	if signal_count > config.god_class_signals:
		is_god_class = true
		reasons.append("%d signals (max %d)" % [signal_count, config.god_class_signals])

	if is_god_class:
		result.add_issue(Issue.create(
			file_path, 1, Issue.Severity.WARNING, "god-class",
			"God class detected: %s" % ", ".join(reasons)
		))
