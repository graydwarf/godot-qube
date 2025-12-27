class_name AnalysisConfig
extends Resource
## Configuration for code analysis thresholds and enabled checks

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
	"tests/mocks/"
]

# Patterns for TODO detection
var todo_patterns: Array[String] = ["TODO", "FIXME", "HACK", "XXX", "BUG", "TEMP"]

# Patterns for print detection (whitelist DebugLogger)
var print_patterns: Array[String] = ["print(", "print_debug(", "prints(", "printt(", "printraw("]
var print_whitelist: Array[String] = ["DebugLogger"]

# Allowed magic numbers (won't be flagged)
var allowed_numbers: Array = [0, 1, -1, 2, 0.0, 1.0, 0.5, 2.0, -1.0, 100, 255, 10, 60, 90, 180, 360]

# Patterns that indicate commented-out code (not regular comments)
var commented_code_patterns: Array[String] = [
	"#var ", "#func ", "#if ", "#for ", "#while ", "#match ", "#return ",
	"#elif ", "#else:", "#class ", "#signal ", "#const ", "#@export",
	"#.connect(", "#.emit(", "#await ", "#preload(", "#load("
]


static func get_default() -> AnalysisConfig:
	return AnalysisConfig.new()


func is_path_excluded(path: String) -> bool:
	for excluded in excluded_paths:
		if path.contains(excluded):
			return true
	return false
