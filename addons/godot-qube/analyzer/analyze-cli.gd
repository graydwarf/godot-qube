# Godot Qube - Code quality analyzer for GDScript
# https://poplava.itch.io
@tool
extends SceneTree
## CLI runner for code analysis
## Usage: godot --headless --script res://addons/godot-qube/analyzer/analyze-cli.gd
## Options:
##   -- --path "C:/path/to/project"   Analyze external project
##   -- --format json                  Output as JSON (default: console)
##   -- --clickable                    Use Godot Output panel clickable format

const AnalysisConfigClass = preload("res://addons/godot-qube/analyzer/analysis-config.gd")
const CodeAnalyzerClass = preload("res://addons/godot-qube/analyzer/code-analyzer.gd")
const AnalysisResultClass = preload("res://addons/godot-qube/analyzer/analysis-result.gd")
const FileResultClass = preload("res://addons/godot-qube/analyzer/file-result.gd")
const IssueClass = preload("res://addons/godot-qube/analyzer/issue.gd")
const HtmlReportGenerator = preload("res://addons/godot-qube/analyzer/html-report-generator.gd")

var _target_path: String = "res://"
var _output_format: String = "console"  # "console", "json", "clickable", "html"
var _output_file: String = ""  # For HTML output
var _exit_code: int = 0

func _init() -> void:
	_parse_arguments()
	_run_analysis()
	quit(_exit_code)

# qube:ignore-function:long-function - CLI argument parsing with many options
func _parse_arguments() -> void:
	var args := OS.get_cmdline_user_args()

	var i := 0
	while i < args.size():
		var arg: String = args[i]

		match arg:
			"--path":
				if i + 1 < args.size():
					# Normalize path separators for Windows compatibility
					var raw_path: String = args[i + 1]
					_target_path = raw_path.replace("/", "\\") if OS.has_feature("windows") else raw_path
					i += 1
			"--format":
				if i + 1 < args.size():
					_output_format = args[i + 1]
					i += 1
			"--clickable":
				_output_format = "clickable"
			"--json":
				_output_format = "json"
			"--html":
				_output_format = "html"
			"--output", "-o":
				if i + 1 < args.size():
					_output_file = args[i + 1]
					i += 1
			"--help", "-h":
				_print_help()
				quit(0)
				return

		i += 1

# qube:ignore-function:print-statement - CLI help output
func _print_help() -> void:
	print("")
	print("Godot Qube - Code Quality Analyzer for GDScript")
	print("")
	print("Usage:")
	print("  godot --headless --script res://addons/godot-qube/analyzer/analyze-cli.gd [options]")
	print("")
	print("Options:")
	print("  --path <dir>      Analyze project at specified path (default: res://)")
	print("  --format <type>   Output format: console, json, clickable, html (default: console)")
	print("  --json            Shorthand for --format json")
	print("  --clickable       Shorthand for --format clickable (Godot Output panel format)")
	print("  --html            Shorthand for --format html (generates HTML report)")
	print("  --output, -o <f>  Output file path (required for --html, default: code_quality_report.html)")
	print("  --help, -h        Show this help message")
	print("")
	print("Exit codes:")
	print("  0 = No issues")
	print("  1 = Warnings only")
	print("  2 = Critical issues found")
	print("")

func _run_analysis() -> void:
	var config = AnalysisConfigClass.get_default()
	var analyzer = CodeAnalyzerClass.new(config)

	var result = analyzer.analyze_directory(_target_path)

	match _output_format:
		"json":
			_output_json(result)
		"clickable":
			_output_clickable(result)
		"html":
			_output_html(result)
		_:
			_output_console(result)

	_exit_code = result.get_exit_code()

# qube:ignore-function:print-statement - CLI JSON output
func _output_json(result) -> void:
	print(JSON.stringify(result.to_dict(), "\t"))

# qube:ignore-function:print-statement,long-function - CLI clickable output
func _output_clickable(result) -> void:
	# Format that Godot Output panel makes clickable
	print("")
	print("=== Code Analysis Results ===")
	print("Files: %d | Lines: %d | Issues: %d" % [
		result.files_analyzed, result.total_lines, result.issues.size()
	])
	print("")

	# Group by severity
	var critical: Array = result.get_issues_by_severity(IssueClass.Severity.CRITICAL)
	var warnings: Array = result.get_issues_by_severity(IssueClass.Severity.WARNING)
	var info: Array = result.get_issues_by_severity(IssueClass.Severity.INFO)

	if critical.size() > 0:
		print("--- CRITICAL (%d) ---" % critical.size())
		for issue in critical:
			print(issue.get_clickable_format())
		print("")

	if warnings.size() > 0:
		print("--- WARNINGS (%d) ---" % warnings.size())
		for issue in warnings:
			print(issue.get_clickable_format())
		print("")

	if info.size() > 0:
		print("--- INFO (%d) ---" % info.size())
		for issue in info:
			print(issue.get_clickable_format())
		print("")

	print("Debt Score: %d | Time: %dms" % [result.get_total_debt_score(), result.analysis_time_ms])

# qube:ignore-function:print-statement - Console output formatting
func _output_console(result) -> void:
	_print_console_header(result)
	_print_top_files_by_size(result)
	_print_top_files_by_debt(result)
	_print_critical_issues(result)
	_print_long_functions(result)
	_print_todo_comments(result)
	_print_console_footer()

# qube:ignore-function:print-statement - CLI console output
func _print_console_header(result) -> void:
	print("")
	print("=" .repeat(60))
	print("GODOT QUBE - CODE QUALITY REPORT")
	print("=" .repeat(60))
	print("")
	print("SUMMARY")
	print("-" .repeat(40))
	print("Total files analyzed: %d" % result.files_analyzed)
	print("Total lines of code: %d" % result.total_lines)
	print("Critical issues: %d" % result.get_critical_count())
	print("Warnings: %d" % result.get_warning_count())
	print("Info: %d" % result.get_info_count())
	print("Total debt score: %d" % result.get_total_debt_score())
	print("Analysis time: %dms" % result.analysis_time_ms)
	print("")

# qube:ignore-function:print-statement - CLI console output
func _print_top_files_by_size(result) -> void:
	print("TOP 10 FILES BY SIZE")
	print("-" .repeat(40))
	var by_size: Array = result.file_results.duplicate()
	by_size.sort_custom(func(a, b): return a.line_count > b.line_count)
	for i in range(mini(10, by_size.size())):
		var f = by_size[i]
		print("%4d lines | %s" % [f.line_count, f.file_path])
	print("")

# qube:ignore-function:print-statement - CLI console output
func _print_top_files_by_debt(result) -> void:
	print("TOP 10 FILES BY DEBT SCORE")
	print("-" .repeat(40))
	var by_debt: Array = result.file_results.duplicate()
	by_debt.sort_custom(func(a, b): return a.debt_score > b.debt_score)
	for i in range(mini(10, by_debt.size())):
		var f = by_debt[i]
		if f.debt_score == 0:
			break
		print("Score %3d | %4d lines | %s" % [f.debt_score, f.line_count, f.file_path])
	print("")

# qube:ignore-function:print-statement - CLI console output
func _print_critical_issues(result) -> void:
	var critical: Array = result.get_issues_by_severity(IssueClass.Severity.CRITICAL)
	if critical.size() == 0:
		return
	print("CRITICAL ISSUES (Fix Immediately)")
	print("-" .repeat(40))
	for issue in critical:
		print("  %s" % issue.get_clickable_format())
	print("")

# qube:ignore-function:print-statement - CLI console output
func _print_long_functions(result) -> void:
	print("LONG FUNCTIONS")
	print("-" .repeat(40))
	var long_func_issues: Array = result.issues.filter(func(i): return i.check_id == "long-function")
	long_func_issues.sort_custom(func(a, b): return a.severity > b.severity)
	for i in range(mini(15, long_func_issues.size())):
		var issue = long_func_issues[i]
		print("  %s" % issue.get_clickable_format())
	print("")

# qube:ignore-function:print-statement - CLI console output
func _print_todo_comments(result) -> void:
	var todo_issues: Array = result.issues.filter(func(i): return i.check_id == "todo-comment")
	if todo_issues.size() == 0:
		return
	print("TODO/FIXME COMMENTS (%d total)" % todo_issues.size())
	print("-" .repeat(40))
	for i in range(mini(10, todo_issues.size())):
		var issue = todo_issues[i]
		print("  %s" % issue.get_clickable_format())
	if todo_issues.size() > 10:
		print("  ... and %d more" % (todo_issues.size() - 10))
	print("")

# qube:ignore-function:print-statement - CLI console output
func _print_console_footer() -> void:
	print("=" .repeat(60))
	print("Run with --clickable for Godot Output panel clickable links")
	print("Run with --json for machine-readable output")
	print("=" .repeat(60))


# qube:ignore-function:print-statement - CLI HTML output
func _output_html(result) -> void:
	var output_path := _output_file if _output_file != "" else "code_quality_report.html"

	var html := HtmlReportGenerator.generate(result)

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file:
		file.store_string(html)
		file.close()
		print("HTML report saved to: %s" % output_path)
	else:
		push_error("Failed to write HTML report to: %s" % output_path)
