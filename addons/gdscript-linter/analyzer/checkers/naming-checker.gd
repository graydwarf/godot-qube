# GDScript Linter - Naming convention checker
# https://poplava.itch.io
class_name GDLintNamingChecker
extends RefCounted

const SNAKE_CASE_PATTERN := "^[a-z][a-z0-9_]*$"
const PASCAL_CASE_PATTERN := "^[A-Z][a-zA-Z0-9]*$"
const SCREAMING_SNAKE_PATTERN := "^[A-Z][A-Z0-9_]*$"
const PRIVATE_SNAKE_PATTERN := "^_[a-z][a-z0-9_]*$"

var config


func _init(p_config) -> void:
	config = p_config


func is_snake_case(name_to_check: String) -> bool:
	var regex := RegEx.new()
	regex.compile(SNAKE_CASE_PATTERN)
	return regex.search(name_to_check) != null


func is_private_snake_case(name_to_check: String) -> bool:
	var regex := RegEx.new()
	regex.compile(PRIVATE_SNAKE_PATTERN)
	return regex.search(name_to_check) != null


func is_pascal_case(name_to_check: String) -> bool:
	var regex := RegEx.new()
	regex.compile(PASCAL_CASE_PATTERN)
	return regex.search(name_to_check) != null


func is_screaming_snake_case(name_to_check: String) -> bool:
	var regex := RegEx.new()
	regex.compile(SCREAMING_SNAKE_PATTERN)
	return regex.search(name_to_check) != null


# Returns array of issue dictionaries: { line: int, severity: String, check_id: String, message: String }
# gdlint:ignore-function:long-function - Linear structure with 4 parallel naming checks, refactoring would reduce readability
func check_line(line: String, line_num: int) -> Array:
	var issues := []
	var trimmed := line.strip_edges()

	# Check class_name
	if trimmed.begins_with("class_name "):
		var class_name_val := trimmed.substr(11).split(" ")[0].strip_edges()
		if not is_pascal_case(class_name_val):
			issues.append({
				"line": line_num,
				"severity": "warning",
				"check_id": "naming-class",
				"message": "Class name '%s' should be PascalCase" % class_name_val
			})

	# Check signal names
	if trimmed.begins_with("signal "):
		var signal_name := trimmed.substr(7).split("(")[0].strip_edges()
		if not is_snake_case(signal_name):
			issues.append({
				"line": line_num,
				"severity": "info",
				"check_id": "naming-signal",
				"message": "Signal '%s' should be snake_case" % signal_name
			})

	# Check const names
	if trimmed.begins_with("const "):
		var after_const := trimmed.substr(6).strip_edges()
		var const_name := after_const.split(":")[0].split("=")[0].strip_edges()
		if not is_screaming_snake_case(const_name) and not is_pascal_case(const_name):
			issues.append({
				"line": line_num,
				"severity": "info",
				"check_id": "naming-const",
				"message": "Constant '%s' should be SCREAMING_SNAKE_CASE or PascalCase" % const_name
			})

	# Check enum names
	if trimmed.begins_with("enum "):
		var after_enum := trimmed.substr(5).strip_edges()
		var enum_name := after_enum.split("{")[0].split(" ")[0].strip_edges()
		if enum_name != "" and not is_pascal_case(enum_name):
			issues.append({
				"line": line_num,
				"severity": "info",
				"check_id": "naming-enum",
				"message": "Enum '%s' should be PascalCase" % enum_name
			})

	return issues


# Returns issue dictionary or null
# gdlint:ignore-function:long-function - Linear validation flow, minimal overage (32 lines)
func check_function_naming(func_name: String, line_num: int) -> Variant:
	if not config.check_naming_conventions:
		return null

	# Skip built-in overrides
	var builtins := ["_init", "_ready", "_process", "_physics_process", "_enter_tree",
		"_exit_tree", "_input", "_unhandled_input", "_gui_input", "_draw", "_notification",
		"_get", "_set", "_get_property_list", "_to_string", "_get_configuration_warnings"]
	if func_name in builtins:
		return null

	# Private functions should be _snake_case
	if func_name.begins_with("_"):
		if not is_private_snake_case(func_name):
			return {
				"line": line_num,
				"severity": "info",
				"check_id": "naming-function",
				"message": "Private function '%s' should be _snake_case" % func_name
			}
	else:
		# Public functions should be snake_case
		if not is_snake_case(func_name):
			return {
				"line": line_num,
				"severity": "info",
				"check_id": "naming-function",
				"message": "Function '%s' should be snake_case" % func_name
			}

	return null
