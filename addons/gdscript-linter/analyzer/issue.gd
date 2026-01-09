# GDScript Linter - Static code quality analyzer
# https://poplava.itch.io
class_name GDLintIssue
extends RefCounted
## Represents a single code quality issue with location info for navigation

enum Severity { INFO, WARNING, CRITICAL }

var file_path: String      ## "res://scenes/board/board.gd"
var line: int              ## 1-based line number
var column: int            ## 0-based column (optional)
var severity: Severity
var check_id: String       ## "long-function", "todo-comment", etc.
var message: String        ## Human-readable description
var context: String        ## The offending line/code snippet (optional)

static func create(p_file: String, p_line: int, p_severity: Severity, p_check_id: String, p_message: String):
	var issue = load("res://addons/gdscript-linter/analyzer/issue.gd").new()
	issue.file_path = p_file
	issue.line = p_line
	issue.column = 0
	issue.severity = p_severity
	issue.check_id = p_check_id
	issue.message = p_message
	issue.context = ""
	return issue

# Returns "res://path/file.gd:42"
func get_location_string() -> String:
	return "%s:%d" % [file_path, line]

# Returns format that Godot Output panel auto-links
func get_clickable_format() -> String:
	return "%s:%d: %s" % [file_path, line, message]

func get_severity_string() -> String:
	match severity:
		Severity.CRITICAL: return "critical"
		Severity.WARNING: return "warning"
		_: return "info"

func get_severity_icon() -> String:
	match severity:
		Severity.CRITICAL: return "🔴"
		Severity.WARNING: return "🟡"
		_: return "🔵"

func to_dict() -> Dictionary:
	return {
		"file_path": file_path,
		"line": line,
		"column": column,
		"severity": get_severity_string(),
		"check_id": check_id,
		"message": message,
		"context": context
	}
