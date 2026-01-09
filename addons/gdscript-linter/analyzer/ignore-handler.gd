# gdlint:ignore-file:file-length=414
# GDScript Linter - Ignore directive handler
# See IGNORE_RULES.md for directive syntax and usage
# https://poplava.itch.io
class_name GDLintIgnoreHandler
extends RefCounted
## Handles parsing and checking of gdlint:ignore directives

const IGNORE_LINE_PATTERN := "gdlint:ignore-line"
const IGNORE_NEXT_LINE_PATTERN := "gdlint:ignore-next-line"
const IGNORE_FUNCTION_PATTERN := "gdlint:ignore-function"
const IGNORE_BLOCK_START_PATTERN := "gdlint:ignore-block-start"
const IGNORE_BLOCK_END_PATTERN := "gdlint:ignore-block-end"
const IGNORE_FILE_PATTERN := "gdlint:ignore-file"
const IGNORE_BELOW_PATTERN := "gdlint:ignore-below"

var _lines: Array = []
var _ignored_ranges: Array = []  # Array of {start: int, end: int, check_id: String, pinned_values: Dictionary}
var _file_ignore_checks: Array = []  # Array of check IDs to ignore for entire file (empty string = all)
var _file_pinned_values: Dictionary = {}  # check_id -> pinned value for file-level ignores
var _ignore_below: Array = []  # Array of {line: int, checks: Array, pinned_values: Dictionary} - ignore from line to EOF
var _inline_pinned_values: Dictionary = {}  # line_num -> {check_id -> pinned_value} for inline ignores


func initialize(lines: Array) -> void:
	_lines = lines
	_ignored_ranges = _parse_ignored_ranges(lines)
	_file_ignore_checks = _parse_file_ignores(lines)
	_ignore_below = _parse_ignore_below(lines)


func clear() -> void:
	_lines = []
	_ignored_ranges = []
	_file_ignore_checks = []
	_file_pinned_values = {}
	_ignore_below = []
	_inline_pinned_values = {}


# Check if an issue should be ignored based on inline comments or ignored ranges
func should_ignore(line_num: int, check_id: String) -> bool:
	if _lines.is_empty():
		return false

	# Check file-level ignores first
	if _is_file_ignored(check_id):
		return true

	# Check ignore-below directives
	if _is_below_ignored(line_num, check_id):
		return true

	var line_idx := line_num - 1
	if line_idx < 0 or line_idx >= _lines.size():
		return false

	# Check if line is within an ignored range (function or block)
	if _is_in_ignored_range(line_num, check_id):
		return true

	var current_line: String = _lines[line_idx]

	# Check current line for # gdlint:ignore-line or # gdlint:ignore-line:check-id
	if _matches_inline_ignore(current_line, check_id):
		return true

	# Check previous line for # gdlint:ignore-next-line
	if line_idx > 0 and _matches_ignore_next_line(_lines[line_idx - 1], check_id):
		return true

	return false


# Check ignore status with pinned value comparison for numeric checks
# Returns: {action: String, pinned: int, actual: int, limit: int}
# Actions: "ignore", "exceeded", "improved", "unnecessary", "normal"
func check_with_pin(line_num: int, check_id: String, actual_value: int, limit: int) -> Dictionary:
	var result := {"action": "normal", "pinned": -1, "actual": actual_value, "limit": limit}

	# Check file-level ignores first
	if _is_file_ignored(check_id):
		var pinned := _file_pinned_values.get(check_id, -1)
		return _evaluate_pinned_result(pinned, actual_value, limit)

	# Check ignore-below directives
	var below_pinned = _get_below_pinned_value(line_num, check_id)
	if below_pinned != null:
		return _evaluate_pinned_result(below_pinned, actual_value, limit)

	# Check if line is within an ignored range (function or block)
	var range_pinned = _get_range_pinned_value(line_num, check_id)
	if range_pinned != null:
		return _evaluate_pinned_result(range_pinned, actual_value, limit)

	var line_idx := line_num - 1
	if line_idx < 0 or line_idx >= _lines.size():
		return result

	var current_line: String = _lines[line_idx]

	# Check current line for inline ignore with pin
	var inline_pinned = _get_inline_pinned_value(current_line, check_id)
	if inline_pinned != null:
		return _evaluate_pinned_result(inline_pinned, actual_value, limit)

	# Check previous line for ignore-next-line with pin
	if line_idx > 0:
		var next_line_pinned = _get_next_line_pinned_value(_lines[line_idx - 1], check_id)
		if next_line_pinned != null:
			return _evaluate_pinned_result(next_line_pinned, actual_value, limit)

	return result


# Evaluate pinned value against actual and limit, return appropriate action
func _evaluate_pinned_result(pinned: int, actual: int, limit: int) -> Dictionary:
	var result := {"action": "ignore", "pinned": pinned, "actual": actual, "limit": limit}

	if pinned < 0:
		# No pin, just ignore
		return result

	if actual <= limit:
		# Value is now within limit - ignore is unnecessary
		result.action = "unnecessary"
	elif actual > pinned:
		# Value exceeded pinned amount - regression
		result.action = "exceeded"
	elif actual < pinned:
		# Value improved but still over limit - consider tightening
		result.action = "improved"
	# else actual == pinned: keep as "ignore"

	return result


# Get pinned value from ignore-below directive if applicable
func _get_below_pinned_value(line_num: int, check_id: String):
	for ignore_entry in _ignore_below:
		if line_num >= ignore_entry.line:
			for ignored_check in ignore_entry.checks:
				if ignored_check == "" or ignored_check == check_id:
					return ignore_entry.pinned_values.get(check_id, -1)
	return null  # Not ignored by below directive


# Get pinned value from ignored range if applicable
func _get_range_pinned_value(line_num: int, check_id: String):
	for ignored_range in _ignored_ranges:
		if line_num >= ignored_range.start and line_num <= ignored_range.end:
			if ignored_range.check_id == "":
				return ignored_range.pinned_values.get(check_id, -1)
			for specific_check in ignored_range.check_id.split(","):
				if specific_check.strip_edges() == check_id:
					return ignored_range.pinned_values.get(check_id, -1)
	return null  # Not in ignored range


# Get pinned value from inline ignore directive
func _get_inline_pinned_value(line: String, check_id: String):
	if IGNORE_LINE_PATTERN not in line or IGNORE_NEXT_LINE_PATTERN in line:
		return null
	if not _check_directive_match(line, IGNORE_LINE_PATTERN, check_id):
		return null
	var extracted := _extract_check_id_with_pin(line, IGNORE_LINE_PATTERN)
	if extracted.check_id == check_id or extracted.check_id == "":
		return extracted.pinned_value if extracted.pinned_value > 0 else -1
	return null


# Get pinned value from ignore-next-line directive
func _get_next_line_pinned_value(line: String, check_id: String):
	if IGNORE_NEXT_LINE_PATTERN not in line:
		return null
	if not _check_directive_match(line, IGNORE_NEXT_LINE_PATTERN, check_id):
		return null
	var extracted := _extract_check_id_with_pin(line, IGNORE_NEXT_LINE_PATTERN)
	if extracted.check_id == check_id or extracted.check_id == "":
		return extracted.pinned_value if extracted.pinned_value > 0 else -1
	return null


# Check if check_id is ignored at file level
func _is_file_ignored(check_id: String) -> bool:
	for ignored_check in _file_ignore_checks:
		if ignored_check == "":
			return true  # Empty string means ignore all
		if ignored_check == check_id:
			return true
	return false


# Check if line_num is below an ignore-below directive for check_id
func _is_below_ignored(line_num: int, check_id: String) -> bool:
	for ignore_entry in _ignore_below:
		if line_num >= ignore_entry.line:
			# Check if this check_id is in the ignored list
			for ignored_check in ignore_entry.checks:
				if ignored_check == "":
					return true  # Empty string means ignore all
				if ignored_check == check_id:
					return true
	return false


# Parse file-level ignore directives from the first few lines
# Looks for # gdlint:ignore-file or # gdlint:ignore-file:check-id or # gdlint:ignore-file:check-id=value
func _parse_file_ignores(lines: Array) -> Array:
	var checks: Array = []
	_file_pinned_values = {}

	# Only check first 10 lines for file-level ignores (typically at top of file)
	var max_lines := mini(10, lines.size())
	for i in range(max_lines):
		var line: String = lines[i]
		if IGNORE_FILE_PATTERN in line:
			var result := _extract_check_id_with_pin(line, IGNORE_FILE_PATTERN)
			if result.check_id == "":
				checks.append("")  # Ignore all checks
			else:
				# Support comma-separated check IDs (pins only work for single check)
				for specific_check in result.check_id.split(","):
					var clean_check: String = specific_check.strip_edges()
					checks.append(clean_check)
					if result.pinned_value > 0:
						_file_pinned_values[clean_check] = result.pinned_value

	return checks


# Parse ignore-below directives - ignore from that line to end of file
# Looks for # gdlint:ignore-below or # gdlint:ignore-below:check-id or # gdlint:ignore-below:check-id=value
func _parse_ignore_below(lines: Array) -> Array:
	var result: Array = []

	for i in range(lines.size()):
		var line: String = lines[i]
		if IGNORE_BELOW_PATTERN in line:
			var extracted := _extract_check_id_with_pin(line, IGNORE_BELOW_PATTERN)
			var checks: Array = []
			var pinned_values: Dictionary = {}
			if extracted.check_id == "":
				checks.append("")  # Ignore all checks
			else:
				# Support comma-separated check IDs (pins only work for single check)
				for specific_check in extracted.check_id.split(","):
					var clean_check: String = specific_check.strip_edges()
					checks.append(clean_check)
					if extracted.pinned_value > 0:
						pinned_values[clean_check] = extracted.pinned_value
			result.append({"line": i + 1, "checks": checks, "pinned_values": pinned_values})

	return result


# Check if line number falls within any ignored range
# Supports comma-separated check IDs in the range's check_id
func _is_in_ignored_range(line_num: int, check_id: String) -> bool:
	for ignored_range in _ignored_ranges:
		if line_num >= ignored_range.start and line_num <= ignored_range.end:
			if ignored_range.check_id == "":
				return true
			# Support comma-separated check IDs
			for specific_check in ignored_range.check_id.split(","):
				if specific_check.strip_edges() == check_id:
					return true
	return false


# Check if line has inline gdlint:ignore-line directive matching check_id
func _matches_inline_ignore(line: String, check_id: String) -> bool:
	if IGNORE_LINE_PATTERN not in line or IGNORE_NEXT_LINE_PATTERN in line:
		return false
	return _check_directive_match(line, IGNORE_LINE_PATTERN, check_id)


# Check if line has gdlint:ignore-next-line directive matching check_id
func _matches_ignore_next_line(line: String, check_id: String) -> bool:
	if IGNORE_NEXT_LINE_PATTERN not in line:
		return false
	return _check_directive_match(line, IGNORE_NEXT_LINE_PATTERN, check_id)


# Check if a directive in line matches the check_id (or ignores all if no specific id)
# Supports comma-separated check IDs: gdlint:ignore-line:check1,check2,check3
# Supports pinned value syntax: gdlint:ignore-line:check-id=value
func _check_directive_match(line: String, pattern: String, check_id: String) -> bool:
	var ignore_pos := line.find(pattern)
	if ignore_pos < 0:
		return false

	var after_ignore := line.substr(ignore_pos + pattern.length())
	if after_ignore.begins_with(":"):
		var check_list := after_ignore.substr(1).split(" ")[0].split("\t")[0].strip_edges()
		# Support comma-separated check IDs
		for specific_check in check_list.split(","):
			var clean_check := specific_check.strip_edges()
			# Strip pinned value if present (e.g., "long-function=35" -> "long-function")
			var equals_pos := clean_check.find("=")
			if equals_pos > 0:
				clean_check = clean_check.substr(0, equals_pos)
			if clean_check == check_id:
				return true
		return false

	return true


# Parse ignored ranges from gdlint:ignore-function and gdlint:ignore-block directives
func _parse_ignored_ranges(lines: Array) -> Array:
	var ranges: Array = []

	# Track block starts for matching with ends
	var block_starts: Array = []  # Array of {line: int, check_id: String, pinned_values: Dictionary}

	for i in range(lines.size()):
		var line: String = lines[i]
		var line_num := i + 1

		# Check for ignore-function directive
		if IGNORE_FUNCTION_PATTERN in line:
			var extracted := _extract_check_id_with_pin(line, IGNORE_FUNCTION_PATTERN)
			var func_range := _find_function_range(lines, i)
			if func_range.start > 0:
				var pinned_values: Dictionary = {}
				if extracted.pinned_value > 0:
					pinned_values[extracted.check_id] = extracted.pinned_value
				ranges.append({
					"start": func_range.start,
					"end": func_range.end,
					"check_id": extracted.check_id,
					"pinned_values": pinned_values
				})

		# Check for ignore-block-start directive
		if IGNORE_BLOCK_START_PATTERN in line:
			var extracted := _extract_check_id_with_pin(line, IGNORE_BLOCK_START_PATTERN)
			var pinned_values: Dictionary = {}
			if extracted.pinned_value > 0:
				pinned_values[extracted.check_id] = extracted.pinned_value
			block_starts.append({"line": line_num, "check_id": extracted.check_id, "pinned_values": pinned_values})

		# Check for ignore-block-end directive
		if IGNORE_BLOCK_END_PATTERN in line:
			if block_starts.size() > 0:
				var block_start = block_starts.pop_back()
				ranges.append({
					"start": block_start.line,
					"end": line_num,
					"check_id": block_start.check_id,
					"pinned_values": block_start.pinned_values
				})

	return ranges


# Extract optional check_id from directive (e.g., "gdlint:ignore-function:print-statement" -> "print-statement")
func _extract_check_id(line: String, pattern: String) -> String:
	var result := _extract_check_id_with_pin(line, pattern)
	return result.check_id


# Extract check_id and optional pinned value from directive
# e.g., "gdlint:ignore-function:long-function=35" -> {check_id: "long-function", pinned_value: 35}
# e.g., "gdlint:ignore-function:print-statement" -> {check_id: "print-statement", pinned_value: -1}
func _extract_check_id_with_pin(line: String, pattern: String) -> Dictionary:
	var pos := line.find(pattern)
	if pos < 0:
		return {"check_id": "", "pinned_value": -1}

	var after := line.substr(pos + pattern.length())
	if not after.begins_with(":"):
		return {"check_id": "", "pinned_value": -1}

	var check_str := after.substr(1).split(" ")[0].split("\t")[0].strip_edges()

	# Check for pinned value syntax: check-id=value
	var equals_pos := check_str.find("=")
	if equals_pos > 0:
		var check_id := check_str.substr(0, equals_pos)
		var value_str := check_str.substr(equals_pos + 1)
		var pinned_value := value_str.to_int() if value_str.is_valid_int() else -1
		return {"check_id": check_id, "pinned_value": pinned_value}

	return {"check_id": check_str, "pinned_value": -1}


# Find the range of a function starting after the given line index
func _find_function_range(lines: Array, start_idx: int) -> Dictionary:
	var func_start := -1
	var func_end := -1

	# Find the next func declaration after the ignore comment
	for i in range(start_idx + 1, lines.size()):
		var trimmed: String = lines[i].strip_edges()
		if trimmed.begins_with("func "):
			func_start = i + 1  # Convert to 1-based line number
			break

	if func_start < 0:
		return {"start": -1, "end": -1}

	# Find where the function ends (next func or end of file)
	for i in range(func_start, lines.size()):
		var trimmed: String = lines[i].strip_edges()
		if trimmed.begins_with("func "):
			func_end = i  # Line before next func (0-based, so already correct as 1-based end)
			break

	# If no next function found, function extends to end of file
	if func_end < 0:
		func_end = lines.size()

	return {"start": func_start, "end": func_end}
