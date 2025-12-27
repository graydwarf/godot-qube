@tool
extends SceneTree
## CLI runner for code analysis
## Usage: godot --headless --script res://addons/godot-qube/analyzer/analyze-cli.gd
## Options:
##   -- --path "C:/path/to/project"   Analyze external project
##   -- --format json                  Output as JSON (default: console)
##   -- --clickable                    Use Godot Output panel clickable format

var _target_path: String = "res://"
var _output_format: String = "console"  # "console", "json", "clickable"
var _exit_code: int = 0


func _init() -> void:
	_parse_arguments()
	_run_analysis()
	quit(_exit_code)


func _parse_arguments() -> void:
	var args := OS.get_cmdline_user_args()

	var i := 0
	while i < args.size():
		var arg: String = args[i]

		match arg:
			"--path":
				if i + 1 < args.size():
					_target_path = args[i + 1]
					i += 1
			"--format":
				if i + 1 < args.size():
					_output_format = args[i + 1]
					i += 1
			"--clickable":
				_output_format = "clickable"
			"--json":
				_output_format = "json"
			"--help", "-h":
				_print_help()
				quit(0)
				return

		i += 1


func _print_help() -> void:
	print("")
	print("Godot Qube - Code Quality Analyzer for GDScript")
	print("")
	print("Usage:")
	print("  godot --headless --script res://addons/godot-qube/analyzer/analyze-cli.gd [options]")
	print("")
	print("Options:")
	print("  --path <dir>     Analyze project at specified path (default: res://)")
	print("  --format <type>  Output format: console, json, clickable (default: console)")
	print("  --json           Shorthand for --format json")
	print("  --clickable      Shorthand for --format clickable (Godot Output panel format)")
	print("  --help, -h       Show this help message")
	print("")
	print("Exit codes:")
	print("  0 = No issues")
	print("  1 = Warnings only")
	print("  2 = Critical issues found")
	print("")


func _run_analysis() -> void:
	var config := AnalysisConfig.get_default()
	var analyzer := CodeAnalyzer.new(config)

	var result := analyzer.analyze_directory(_target_path)

	match _output_format:
		"json":
			_output_json(result)
		"clickable":
			_output_clickable(result)
		_:
			_output_console(result)

	_exit_code = result.get_exit_code()


func _output_json(result: AnalysisResult) -> void:
	print(JSON.stringify(result.to_dict(), "\t"))


func _output_clickable(result: AnalysisResult) -> void:
	# Format that Godot Output panel makes clickable
	print("")
	print("=== Code Analysis Results ===")
	print("Files: %d | Lines: %d | Issues: %d" % [
		result.files_analyzed, result.total_lines, result.issues.size()
	])
	print("")

	# Group by severity
	var critical := result.get_issues_by_severity(Issue.Severity.CRITICAL)
	var warnings := result.get_issues_by_severity(Issue.Severity.WARNING)
	var info := result.get_issues_by_severity(Issue.Severity.INFO)

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


func _output_console(result: AnalysisResult) -> void:
	print("")
	print("=" .repeat(60))
	print("GODOT QUBE - CODE QUALITY REPORT")
	print("=" .repeat(60))
	print("")

	# Summary
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

	# Top files by size
	print("TOP 10 FILES BY SIZE")
	print("-" .repeat(40))
	var by_size: Array = result.file_results.duplicate()
	by_size.sort_custom(func(a, b): return a.line_count > b.line_count)
	for i in range(mini(10, by_size.size())):
		var f: FileResult = by_size[i]
		print("%4d lines | %s" % [f.line_count, f.file_path])
	print("")

	# Top files by debt
	print("TOP 10 FILES BY DEBT SCORE")
	print("-" .repeat(40))
	var by_debt: Array = result.file_results.duplicate()
	by_debt.sort_custom(func(a, b): return a.debt_score > b.debt_score)
	for i in range(mini(10, by_debt.size())):
		var f: FileResult = by_debt[i]
		if f.debt_score == 0:
			break
		print("Score %3d | %4d lines | %s" % [f.debt_score, f.line_count, f.file_path])
	print("")

	# Critical issues
	var critical := result.get_issues_by_severity(Issue.Severity.CRITICAL)
	if critical.size() > 0:
		print("CRITICAL ISSUES (Fix Immediately)")
		print("-" .repeat(40))
		for issue in critical:
			print("  %s" % issue.get_clickable_format())
		print("")

	# Long functions
	print("LONG FUNCTIONS")
	print("-" .repeat(40))
	var long_func_issues := result.issues.filter(func(i): return i.check_id == "long-function")
	long_func_issues.sort_custom(func(a, b): return a.severity > b.severity)
	for i in range(mini(15, long_func_issues.size())):
		var issue: Issue = long_func_issues[i]
		print("  %s" % issue.get_clickable_format())
	print("")

	# TODO/FIXME summary
	var todo_issues := result.issues.filter(func(i): return i.check_id == "todo-comment")
	if todo_issues.size() > 0:
		print("TODO/FIXME COMMENTS (%d total)" % todo_issues.size())
		print("-" .repeat(40))
		for i in range(mini(10, todo_issues.size())):
			var issue: Issue = todo_issues[i]
			print("  %s" % issue.get_clickable_format())
		if todo_issues.size() > 10:
			print("  ... and %d more" % (todo_issues.size() - 10))
		print("")

	print("=" .repeat(60))
	print("Run with --clickable for Godot Output panel clickable links")
	print("Run with --json for machine-readable output")
	print("=" .repeat(60))
