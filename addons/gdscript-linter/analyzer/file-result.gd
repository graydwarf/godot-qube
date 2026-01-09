# GDScript Linter - Static code quality analyzer
# https://poplava.itch.io
class_name GDLintFileResult
extends RefCounted
## Holds analysis results for a single file

var file_path: String
var line_count: int
var debt_score: int = 0
var functions: Array[Dictionary] = []
var signals_found: Array[String] = []
var dependencies: Array[String] = []

static func create(path: String, lines: int):
	var result = load("res://addons/gdscript-linter/analyzer/file-result.gd").new()
	result.file_path = path
	result.line_count = lines
	return result

func add_function(func_data: Dictionary) -> void:
	functions.append(func_data)

func to_dict() -> Dictionary:
	return {
		"path": file_path,
		"lines": line_count,
		"debt_score": debt_score,
		"function_count": functions.size(),
		"signal_count": signals_found.size()
	}
