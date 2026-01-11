# GDScript Linter - Static code quality analyzer
# https://poplava.itch.io
class_name GDLintConfig
extends Resource
## Configuration for analysis thresholds and enabled checks

# File limits
@export var line_limit_soft: int = 200
@export var line_limit_hard: int = 300

# Function limits
@export var function_line_limit: int = 30
@export var function_line_critical: int = 60
@export var max_parameters: int = 4
@export var max_nesting: int = 3

# Style limits
@export var max_line_length: int = 120

# Enabled checks (all enabled by default)
@export var check_file_length: bool = true
@export var check_function_length: bool = true
@export var check_parameters: bool = true
@export var check_nesting: bool = true
@export var check_todo_comments: bool = true
@export var check_long_lines: bool = true
@export var check_print_statements: bool = true
@export var check_empty_functions: bool = true
@export var check_magic_numbers: bool = true
@export var check_commented_code: bool = true
@export var check_missing_types: bool = true
@export var check_cyclomatic_complexity: bool = true
@export var check_god_class: bool = true
@export var check_naming_conventions: bool = true
@export var check_unused_variables: bool = true
@export var check_unused_parameters: bool = true
@export var check_missing_return_type: bool = true  # Public functions without return type annotation
@export var ignore_underscore_prefix: bool = true  # Skip _var names as intentionally unused

# Scanning options
@export var respect_gdignore: bool = true  # Skip directories containing .gdignore files
@export var scan_addons: bool = false  # Include addons/ folder in scans (disabled by default)
@export var respect_ignore_directives: bool = true  # Process gdlint:ignore comments (false = show all issues)

# Complexity thresholds
@export var cyclomatic_warning: int = 10
@export var cyclomatic_critical: int = 15

# God class thresholds
@export var god_class_functions: int = 20
@export var god_class_signals: int = 10
@export var god_class_exports: int = 15

# Paths to exclude from analysis
@export var excluded_paths: Array[String] = [
	"addons/",
	".godot/",
	"tests/mocks/",
	"screenshots/"
]

# Patterns for TODO detection
var todo_patterns: Array[String] = ["TODO", "FIXME", "HACK", "XXX", "BUG", "TEMP"]

# Patterns for print detection (whitelist DebugLogger)
var print_patterns: Array[String] = ["print(", "print_debug(", "prints(", "printt(", "printraw("]  # gdlint:ignore-line:print-statement
var print_whitelist: Array[String] = ["DebugLogger"]

# Allowed magic numbers (won't be flagged)
# gdlint:ignore-next-line:magic-number
var allowed_numbers: Array = [0, 1, -1, 2, 0.0, 1.0, 0.5, 2.0, -1.0, 100, 255, 10, 60, 90, 180, 360]

# Patterns that indicate commented-out code (not regular comments)
var commented_code_patterns: Array[String] = [
	"#var ", "#func ", "#if ", "#for ", "#while ", "#match ", "#return ",
	"#elif ", "#else:", "#class ", "#signal ", "#const ", "#@export",
	"#.connect(", "#.emit(", "#await ", "#preload(", "#load("
]

static func get_default():
	var config = load("res://addons/gdscript-linter/analyzer/analysis-config.gd").new()
	config.load_project_config()
	return config


# Load settings from .gdlint.cfg if it exists in project root
func load_project_config(project_path: String = "res://") -> void:
	var config_path := project_path.path_join(".gdlint.cfg")
	if not FileAccess.file_exists(config_path):
		return

	var file := FileAccess.open(config_path, FileAccess.READ)
	if not file:
		return

	var current_section := ""
	while not file.eof_reached():
		var line := file.get_line().strip_edges()

		# Skip empty lines and comments
		if line.is_empty() or line.begins_with("#") or line.begins_with(";"):
			continue

		# Section header
		if line.begins_with("[") and line.ends_with("]"):
			current_section = line.substr(1, line.length() - 2).to_lower()
			continue

		# Key-value pair
		var eq_pos := line.find("=")
		if eq_pos > 0:
			var key := line.substr(0, eq_pos).strip_edges().to_lower()
			var value := line.substr(eq_pos + 1).strip_edges()
			_apply_config_value(current_section, key, value)


func _apply_config_value(section: String, key: String, value: String) -> void:
	match section:
		"limits": _apply_limits_value(key, value)
		"checks": _apply_checks_value(key, value)
		"exclude": _apply_exclude_value(key, value)


func _apply_limits_value(key: String, value: String) -> void:
	match key:
		"file_lines_soft": line_limit_soft = int(value)
		"file_lines_hard": line_limit_hard = int(value)
		"function_lines": function_line_limit = int(value)
		"function_lines_critical": function_line_critical = int(value)
		"max_parameters": max_parameters = int(value)
		"max_nesting": max_nesting = int(value)
		"max_line_length": max_line_length = int(value)
		"cyclomatic_warning": cyclomatic_warning = int(value)
		"cyclomatic_critical": cyclomatic_critical = int(value)
		"god_class_functions": god_class_functions = int(value)
		"god_class_signals": god_class_signals = int(value)


func _apply_checks_value(key: String, value: String) -> void:
	var enabled := value.to_lower() in ["true", "1", "yes", "on"]
	match key:
		"file_length": check_file_length = enabled
		"function_length": check_function_length = enabled
		"cyclomatic_complexity": check_cyclomatic_complexity = enabled
		"parameters": check_parameters = enabled
		"nesting": check_nesting = enabled
		"todo_comments": check_todo_comments = enabled
		"print_statements": check_print_statements = enabled
		"empty_functions": check_empty_functions = enabled
		"magic_numbers": check_magic_numbers = enabled
		"commented_code": check_commented_code = enabled
		"missing_types": check_missing_types = enabled
		"god_class": check_god_class = enabled
		"long_lines": check_long_lines = enabled
		"naming_conventions": check_naming_conventions = enabled
		"unused_variables": check_unused_variables = enabled
		"unused_parameters": check_unused_parameters = enabled
		"missing_return_type": check_missing_return_type = enabled
		"ignore_underscore_prefix": ignore_underscore_prefix = enabled
		"respect_gdignore": respect_gdignore = enabled


func _apply_exclude_value(key: String, value: String) -> void:
	if key == "paths":
		excluded_paths.clear()
		for path in value.split(","):
			var trimmed := path.strip_edges()
			if not trimmed.is_empty():
				excluded_paths.append(trimmed)


func is_path_excluded(path: String) -> bool:
	for excluded in excluded_paths:
		# Skip addons/ exclusion if scan_addons is enabled
		if excluded == "addons/" and scan_addons:
			continue
		if path.contains(excluded):
			return true
	return false


# Save configuration to JSON file
func save_to_json(path: String) -> bool:
	var data := {
		"limits": {
			"file_lines_soft": line_limit_soft,
			"file_lines_hard": line_limit_hard,
			"function_lines": function_line_limit,
			"function_lines_critical": function_line_critical,
			"max_parameters": max_parameters,
			"max_nesting": max_nesting,
			"max_line_length": max_line_length,
			"cyclomatic_warning": cyclomatic_warning,
			"cyclomatic_critical": cyclomatic_critical,
			"god_class_functions": god_class_functions,
			"god_class_signals": god_class_signals,
			"god_class_exports": god_class_exports,
		},
		"checks": {
			"file_length": check_file_length,
			"function_length": check_function_length,
			"parameters": check_parameters,
			"nesting": check_nesting,
			"todo_comments": check_todo_comments,
			"long_lines": check_long_lines,
			"print_statements": check_print_statements,
			"empty_functions": check_empty_functions,
			"magic_numbers": check_magic_numbers,
			"commented_code": check_commented_code,
			"missing_types": check_missing_types,
			"cyclomatic_complexity": check_cyclomatic_complexity,
			"god_class": check_god_class,
			"naming_conventions": check_naming_conventions,
			"unused_variables": check_unused_variables,
			"unused_parameters": check_unused_parameters,
			"missing_return_type": check_missing_return_type,
			"ignore_underscore_prefix": ignore_underscore_prefix,
		},
		"scanning": {
			"respect_gdignore": respect_gdignore,
			"scan_addons": scan_addons,
			"respect_ignore_directives": respect_ignore_directives,
		},
		"exclude": {
			"paths": excluded_paths,
		},
	}

	var json_string := JSON.stringify(data, "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("GDLint: Failed to save config to %s: %s" % [path, FileAccess.get_open_error()])
		return false

	file.store_string(json_string)
	file.close()
	return true


# Load configuration from JSON file
# Config loading requires checking each property existence - inherent complexity
# gdlint:ignore-function:high-complexity=45
# gdlint:ignore-function:long-function=85
func load_from_json(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return false

	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(json_string)
	if parse_result != OK:
		push_error("GDLint: Failed to parse JSON config at %s: %s" % [path, json.get_error_message()])
		return false

	var data: Dictionary = json.data
	if not data is Dictionary:
		push_error("GDLint: Invalid config format at %s" % path)
		return false

	# Apply limits
	if data.has("limits"):
		var limits: Dictionary = data.limits
		if limits.has("file_lines_soft"): line_limit_soft = int(limits.file_lines_soft)
		if limits.has("file_lines_hard"): line_limit_hard = int(limits.file_lines_hard)
		if limits.has("function_lines"): function_line_limit = int(limits.function_lines)
		if limits.has("function_lines_critical"): function_line_critical = int(limits.function_lines_critical)
		if limits.has("max_parameters"): max_parameters = int(limits.max_parameters)
		if limits.has("max_nesting"): max_nesting = int(limits.max_nesting)
		if limits.has("max_line_length"): max_line_length = int(limits.max_line_length)
		if limits.has("cyclomatic_warning"): cyclomatic_warning = int(limits.cyclomatic_warning)
		if limits.has("cyclomatic_critical"): cyclomatic_critical = int(limits.cyclomatic_critical)
		if limits.has("god_class_functions"): god_class_functions = int(limits.god_class_functions)
		if limits.has("god_class_signals"): god_class_signals = int(limits.god_class_signals)
		if limits.has("god_class_exports"): god_class_exports = int(limits.god_class_exports)

	# Apply checks
	if data.has("checks"):
		var checks: Dictionary = data.checks
		if checks.has("file_length"): check_file_length = bool(checks.file_length)
		if checks.has("function_length"): check_function_length = bool(checks.function_length)
		if checks.has("parameters"): check_parameters = bool(checks.parameters)
		if checks.has("nesting"): check_nesting = bool(checks.nesting)
		if checks.has("todo_comments"): check_todo_comments = bool(checks.todo_comments)
		if checks.has("long_lines"): check_long_lines = bool(checks.long_lines)
		if checks.has("print_statements"): check_print_statements = bool(checks.print_statements)
		if checks.has("empty_functions"): check_empty_functions = bool(checks.empty_functions)
		if checks.has("magic_numbers"): check_magic_numbers = bool(checks.magic_numbers)
		if checks.has("commented_code"): check_commented_code = bool(checks.commented_code)
		if checks.has("missing_types"): check_missing_types = bool(checks.missing_types)
		if checks.has("cyclomatic_complexity"): check_cyclomatic_complexity = bool(checks.cyclomatic_complexity)
		if checks.has("god_class"): check_god_class = bool(checks.god_class)
		if checks.has("naming_conventions"): check_naming_conventions = bool(checks.naming_conventions)
		if checks.has("unused_variables"): check_unused_variables = bool(checks.unused_variables)
		if checks.has("unused_parameters"): check_unused_parameters = bool(checks.unused_parameters)
		if checks.has("missing_return_type"): check_missing_return_type = bool(checks.missing_return_type)
		if checks.has("ignore_underscore_prefix"): ignore_underscore_prefix = bool(checks.ignore_underscore_prefix)

	# Apply scanning options
	if data.has("scanning"):
		var scanning: Dictionary = data.scanning
		if scanning.has("respect_gdignore"): respect_gdignore = bool(scanning.respect_gdignore)
		if scanning.has("scan_addons"): scan_addons = bool(scanning.scan_addons)
		if scanning.has("respect_ignore_directives"): respect_ignore_directives = bool(scanning.respect_ignore_directives)

	# Apply excluded paths
	if data.has("exclude"):
		var exclude: Dictionary = data.exclude
		if exclude.has("paths") and exclude.paths is Array:
			excluded_paths.clear()
			for p in exclude.paths:
				excluded_paths.append(str(p))

	return true


# Static helper to load config from project root
static func load_project_config_auto(project_path: String = "res://") -> GDLintConfig:
	var config = load("res://addons/gdscript-linter/analyzer/analysis-config.gd").new()
	var json_path := project_path.path_join("gdlint.json")
	config.load_from_json(json_path)
	return config
