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

# Naming convention patterns
const SNAKE_CASE_PATTERN := "^[a-z][a-z0-9_]*$"
const PASCAL_CASE_PATTERN := "^[A-Z][a-zA-Z0-9]*$"
const SCREAMING_SNAKE_PATTERN := "^[A-Z][A-Z0-9_]*$"
const PRIVATE_SNAKE_PATTERN := "^_[a-z][a-z0-9_]*$"

var config
var result
var _start_time: int
var _current_lines: Array = []  # Lines of current file being analyzed

func _init(p_config = null) -> void:
	config = p_config if p_config else AnalysisConfigClass.get_default()

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
	_current_lines = lines  # Store for ignore checking
	var file_result = FileResultClass.create(file_path, lines.size())

	_analyze_file_level(lines, file_path, file_result)
	_analyze_functions(lines, file_path, file_result)
	_check_god_class(file_path, file_result)
	_check_unused_variables(lines, file_path)
	_calculate_debt_score(file_result)

	_current_lines = []  # Clear after analysis
	return file_result


# Check if an issue should be ignored based on inline comments
# Supports:
#   # qube:ignore - ignore all issues on this line
#   # qube:ignore:check-id - ignore specific check on this line
#   # qube:ignore-next-line - ignore all issues on next line
#   # qube:ignore-next-line:check-id - ignore specific check on next line
func _should_ignore_issue(line_num: int, check_id: String) -> bool:
	if _current_lines.is_empty():
		return false

	var line_idx := line_num - 1  # Convert to 0-based
	if line_idx < 0 or line_idx >= _current_lines.size():
		return false

	var current_line: String = _current_lines[line_idx]

	# Check current line for # qube:ignore or # qube:ignore:check-id
	if IGNORE_PATTERN in current_line:
		var ignore_pos := current_line.find(IGNORE_PATTERN)
		# Make sure it's not ignore-next-line
		if ignore_pos >= 0 and not IGNORE_NEXT_LINE_PATTERN in current_line:
			var after_ignore := current_line.substr(ignore_pos + IGNORE_PATTERN.length())
			# Check if it's a specific check ignore
			if after_ignore.begins_with(":"):
				var specific_check := after_ignore.substr(1).split(" ")[0].split("\t")[0].strip_edges()
				return specific_check == check_id
			else:
				# General ignore (no specific check)
				return true

	# Check previous line for # qube:ignore-next-line
	if line_idx > 0:
		var prev_line: String = _current_lines[line_idx - 1]
		if IGNORE_NEXT_LINE_PATTERN in prev_line:
			var ignore_pos := prev_line.find(IGNORE_NEXT_LINE_PATTERN)
			if ignore_pos >= 0:
				var after_ignore := prev_line.substr(ignore_pos + IGNORE_NEXT_LINE_PATTERN.length())
				# Check if it's a specific check ignore
				if after_ignore.begins_with(":"):
					var specific_check := after_ignore.substr(1).split(" ")[0].split("\t")[0].strip_edges()
					return specific_check == check_id
				else:
					# General ignore (no specific check)
					return true

	return false


# Add issue only if not ignored by inline comments
func _add_issue(file_path: String, line_num: int, severity, check_id: String, message: String) -> void:
	if _should_ignore_issue(line_num, check_id):
		return
	result.add_issue(IssueClass.create(file_path, line_num, severity, check_id, message))

func _scan_directory(path: String) -> void:
	# Only normalize absolute filesystem paths, not res:// or user:// virtual paths
	var normalized_path := path
	if OS.has_feature("windows") and not path.begins_with("res://") and not path.begins_with("user://"):
		normalized_path = path.replace("/", "\\")
	var dir := DirAccess.open(normalized_path)
	if not dir:
		push_error("Failed to open directory: %s" % path)
		return

	# Skip directories containing .gdignore (matches Godot editor behavior)
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
					# Add file's issues to main result
					for issue in _get_issues_for_file_result(file_result, full_path):
						result.add_issue(issue)

		file_name = dir.get_next()

	dir.list_dir_end()

# qube:ignore-next-line - Core analysis loop requires branching
func _analyze_file_level(lines: Array, file_path: String, file_result) -> void:
	var line_count := lines.size()

	# Check file length
	if config.check_file_length:
		if line_count > config.line_limit_hard:
			_add_issue(file_path, 1, IssueClass.Severity.CRITICAL, "file-length",
				"File exceeds %d lines (%d)" % [config.line_limit_hard, line_count])
		elif line_count > config.line_limit_soft:
			_add_issue(file_path, 1, IssueClass.Severity.WARNING, "file-length",
				"File exceeds %d lines (%d)" % [config.line_limit_soft, line_count])

	# Line-by-line checks
	for i in range(line_count):
		var line: String = lines[i]
		var trimmed := line.strip_edges()
		var line_num := i + 1  # 1-based

		# Long lines
		if config.check_long_lines and line.length() > config.max_line_length:
			_add_issue(file_path, line_num, IssueClass.Severity.INFO, "long-line",
				"Line exceeds %d chars (%d)" % [config.max_line_length, line.length()])

		# TODO/FIXME comments
		if config.check_todo_comments:
			for pattern in config.todo_patterns:
				if pattern in trimmed:
					var severity := IssueClass.Severity.INFO if pattern == "TODO" else IssueClass.Severity.WARNING
					var comment_text := trimmed.substr(trimmed.find(pattern) + pattern.length()).strip_edges()
					if comment_text.begins_with(":"):
						comment_text = comment_text.substr(1).strip_edges()
					_add_issue(file_path, line_num, severity, "todo-comment",
						"%s: %s" % [pattern, comment_text])
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
						_add_issue(file_path, line_num, IssueClass.Severity.WARNING, "print-statement",
							"Debug print statement: %s" % trimmed.substr(0, mini(60, trimmed.length())))
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

		# Naming convention checks
		if config.check_naming_conventions:
			_check_naming_conventions(line, file_path, line_num)

func _analyze_functions(lines: Array, file_path: String, file_result) -> void:
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

# qube:ignore-next-line - Function finalization requires multiple checks
func _finalize_function(func_data: Dictionary, body_lines: Array, file_path: String, file_result) -> void:
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
			_add_issue(file_path, func_line, IssueClass.Severity.CRITICAL, "long-function",
				"Function '%s' exceeds %d lines (%d)" % [func_data.name, config.function_line_critical, line_count])
		elif line_count > config.function_line_limit:
			_add_issue(file_path, func_line, IssueClass.Severity.WARNING, "long-function",
				"Function '%s' exceeds %d lines (%d)" % [func_data.name, config.function_line_limit, line_count])

	# Parameter count check
	if config.check_parameters and func_data.params > config.max_parameters:
		_add_issue(file_path, func_line, IssueClass.Severity.WARNING, "too-many-params",
			"Function '%s' has %d parameters (max %d)" % [func_data.name, func_data.params, config.max_parameters])

	# Nesting depth check
	if config.check_nesting and max_nesting > config.max_nesting:
		_add_issue(file_path, func_line, IssueClass.Severity.WARNING, "deep-nesting",
			"Function '%s' has %d nesting levels (max %d)" % [func_data.name, max_nesting, config.max_nesting])

	# Empty function check
	if config.check_empty_functions and is_empty:
		_add_issue(file_path, func_line, IssueClass.Severity.INFO, "empty-function",
			"Function '%s' is empty or contains only 'pass'" % func_data.name)

	# Cyclomatic complexity check
	if config.check_cyclomatic_complexity:
		if complexity > config.cyclomatic_critical:
			_add_issue(file_path, func_line, IssueClass.Severity.CRITICAL, "high-complexity",
				"Function '%s' has complexity %d (max %d)" % [func_data.name, complexity, config.cyclomatic_critical])
		elif complexity > config.cyclomatic_warning:
			_add_issue(file_path, func_line, IssueClass.Severity.WARNING, "high-complexity",
				"Function '%s' has complexity %d (warning at %d)" % [func_data.name, complexity, config.cyclomatic_warning])

	# Missing return type check
	if config.check_missing_types and not func_data.has_return_type:
		# Skip _init, _ready, _process, etc. (built-in overrides)
		var func_name: String = func_data.name
		if not func_name.begins_with("_"):
			_add_issue(file_path, func_line, IssueClass.Severity.INFO, "missing-return-type",
				"Function '%s' has no return type annotation" % func_name)

	# Function naming convention check
	_check_function_naming(func_data.name, file_path, func_line)

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

func _get_issues_for_file_result(_file_result, _file_path: String) -> Array:
	# Issues are added directly during analysis, this is for potential future use
	return []

func _calculate_debt_score(file_result) -> void:
	var score := 0
	var line_count: int = file_result.line_count

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

		_add_issue(file_path, line_num, IssueClass.Severity.INFO, "magic-number",
			"Magic number %s (consider using a named constant)" % num_str)
		break  # Only report first magic number per line

func _check_commented_code(line: String, file_path: String, line_num: int) -> void:
	for pattern in config.commented_code_patterns:
		if line.begins_with(pattern) or ("\t" + pattern) in line or (" " + pattern) in line:
			_add_issue(file_path, line_num, IssueClass.Severity.INFO, "commented-code",
				"Commented-out code detected")
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

	_add_issue(file_path, line_num, IssueClass.Severity.INFO, "missing-type-hint",
		"Variable '%s' has no type annotation" % var_name)

# qube:ignore-next-line - Complexity calculation is naturally complex
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

func _check_god_class(file_path: String, file_result) -> void:
	if not config.check_god_class:
		return

	var public_funcs := 0
	var signal_count: int = file_result.signals_found.size()
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
		_add_issue(file_path, 1, IssueClass.Severity.WARNING, "god-class",
			"God class detected: %s" % ", ".join(reasons))


# ========== Naming Convention Checks ==========

func _is_snake_case(name: String) -> bool:
	var regex := RegEx.new()
	regex.compile(SNAKE_CASE_PATTERN)
	return regex.search(name) != null

func _is_private_snake_case(name: String) -> bool:
	var regex := RegEx.new()
	regex.compile(PRIVATE_SNAKE_PATTERN)
	return regex.search(name) != null

func _is_pascal_case(name: String) -> bool:
	var regex := RegEx.new()
	regex.compile(PASCAL_CASE_PATTERN)
	return regex.search(name) != null

func _is_screaming_snake_case(name: String) -> bool:
	var regex := RegEx.new()
	regex.compile(SCREAMING_SNAKE_PATTERN)
	return regex.search(name) != null

func _check_naming_conventions(line: String, file_path: String, line_num: int) -> void:
	var trimmed := line.strip_edges()

	# Check class_name
	if trimmed.begins_with("class_name "):
		var class_name_val := trimmed.substr(11).split(" ")[0].strip_edges()
		if not _is_pascal_case(class_name_val):
			_add_issue(file_path, line_num, IssueClass.Severity.WARNING, "naming-class",
				"Class name '%s' should be PascalCase" % class_name_val)

	# Check signal names
	if trimmed.begins_with("signal "):
		var signal_name := trimmed.substr(7).split("(")[0].strip_edges()
		if not _is_snake_case(signal_name):
			_add_issue(file_path, line_num, IssueClass.Severity.INFO, "naming-signal",
				"Signal '%s' should be snake_case" % signal_name)

	# Check const names
	if trimmed.begins_with("const "):
		var after_const := trimmed.substr(6).strip_edges()
		var const_name := after_const.split(":")[0].split("=")[0].strip_edges()
		if not _is_screaming_snake_case(const_name) and not _is_pascal_case(const_name):
			_add_issue(file_path, line_num, IssueClass.Severity.INFO, "naming-const",
				"Constant '%s' should be SCREAMING_SNAKE_CASE or PascalCase" % const_name)

	# Check enum names
	if trimmed.begins_with("enum "):
		var after_enum := trimmed.substr(5).strip_edges()
		var enum_name := after_enum.split("{")[0].split(" ")[0].strip_edges()
		if enum_name != "" and not _is_pascal_case(enum_name):
			_add_issue(file_path, line_num, IssueClass.Severity.INFO, "naming-enum",
				"Enum '%s' should be PascalCase" % enum_name)

func _check_function_naming(func_name: String, file_path: String, line_num: int) -> void:
	if not config.check_naming_conventions:
		return

	# Skip built-in overrides
	var builtins := ["_init", "_ready", "_process", "_physics_process", "_enter_tree",
		"_exit_tree", "_input", "_unhandled_input", "_gui_input", "_draw", "_notification",
		"_get", "_set", "_get_property_list", "_to_string", "_get_configuration_warnings"]
	if func_name in builtins:
		return

	# Private functions should be _snake_case
	if func_name.begins_with("_"):
		if not _is_private_snake_case(func_name):
			_add_issue(file_path, line_num, IssueClass.Severity.INFO, "naming-function",
				"Private function '%s' should be _snake_case" % func_name)
	else:
		# Public functions should be snake_case
		if not _is_snake_case(func_name):
			_add_issue(file_path, line_num, IssueClass.Severity.INFO, "naming-function",
				"Function '%s' should be snake_case" % func_name)


# ========== Unused Variable/Parameter Detection ==========

# Declaration info structure: { name: String, line: int, type: String, used: bool }
var _declarations: Array = []
var _current_file_path: String = ""

func _check_unused_variables(lines: Array, file_path: String) -> void:
	if not config.check_unused_variables and not config.check_unused_parameters:
		return

	_declarations.clear()
	_current_file_path = file_path

	# Pass 1: Collect all declarations
	_collect_declarations(lines)

	# Pass 2: Find usages
	_find_usages(lines)

	# Pass 3: Report unused
	_report_unused(file_path)


func _collect_declarations(lines: Array) -> void:
	var in_function := false
	var current_func_name := ""
	var current_func_line := 0

	for i in range(lines.size()):
		var line: String = lines[i]
		var trimmed := line.strip_edges()
		var line_num := i + 1

		# Track function boundaries
		if trimmed.begins_with("func "):
			in_function = true
			current_func_name = _extract_func_name(trimmed)
			current_func_line = line_num

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
	# Extract function name from "func name(...)"
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

	# Extract parameters from "func name(param1, param2: Type, param3 = default)"
	var params_start := line.find("(")
	var params_end := line.find(")")
	if params_start < 0 or params_end < 0 or params_end <= params_start:
		return

	var params_str := line.substr(params_start + 1, params_end - params_start - 1).strip_edges()
	if params_str.is_empty():
		return

	# Split by comma, handling potential default values
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
	# Handle "name", "name: Type", "name = default", "name: Type = default"
	var name := param

	# Remove default value
	var eq_pos := name.find("=")
	if eq_pos > 0:
		name = name.substr(0, eq_pos)

	# Remove type annotation
	var colon_pos := name.find(":")
	if colon_pos > 0:
		name = name.substr(0, colon_pos)

	return name.strip_edges()


func _extract_variable_declaration(line: String, line_num: int) -> void:
	# Skip @export variables (used by editor)
	if "@export" in line:
		return

	# Match "var name", "var name: Type", "var name = value"
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
	# Match "for item in items:"
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

		# Create regex for word boundary match
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
				break  # Found usage, no need to continue


func _remove_string_literals(line: String) -> String:
	# Remove double-quoted strings
	var result := line
	var dq_regex := RegEx.new()
	dq_regex.compile("\"[^\"]*\"")
	result = dq_regex.sub(result, "\"\"", true)

	# Remove single-quoted strings
	var sq_regex := RegEx.new()
	sq_regex.compile("'[^']*'")
	result = sq_regex.sub(result, "''", true)

	return result


func _report_unused(file_path: String) -> void:
	for decl in _declarations:
		if decl.used:
			continue

		var decl_type: String = decl.type
		var decl_name: String = decl.name
		var decl_line: int = decl.line

		# Check if this issue should be ignored
		if _should_ignore_issue(decl_line, "unused-" + decl_type):
			continue

		match decl_type:
			"variable":
				if config.check_unused_variables:
					result.add_issue(IssueClass.create(file_path, decl_line, IssueClass.Severity.WARNING,
						"unused-variable", "Variable '%s' is declared but never used" % decl_name))
			"parameter":
				if config.check_unused_parameters:
					result.add_issue(IssueClass.create(file_path, decl_line, IssueClass.Severity.INFO,
						"unused-parameter", "Parameter '%s' is declared but never used" % decl_name))
			"for_loop":
				if config.check_unused_variables:
					result.add_issue(IssueClass.create(file_path, decl_line, IssueClass.Severity.WARNING,
						"unused-variable", "Loop variable '%s' is declared but never used" % decl_name))
