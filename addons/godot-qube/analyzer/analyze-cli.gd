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

var _target_path: String = "res://"
var _output_format: String = "console"  # "console", "json", "clickable", "html"
var _output_file: String = ""  # For HTML output
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

func _output_json(result) -> void:
	print(JSON.stringify(result.to_dict(), "\t"))

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

# qube:ignore-next-line - Console output formatting requires many print calls
func _output_console(result) -> void:
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
		var f = by_size[i]
		print("%4d lines | %s" % [f.line_count, f.file_path])
	print("")

	# Top files by debt
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

	# Critical issues
	var critical: Array = result.get_issues_by_severity(IssueClass.Severity.CRITICAL)
	if critical.size() > 0:
		print("CRITICAL ISSUES (Fix Immediately)")
		print("-" .repeat(40))
		for issue in critical:
			print("  %s" % issue.get_clickable_format())
		print("")

	# Long functions
	print("LONG FUNCTIONS")
	print("-" .repeat(40))
	var long_func_issues: Array = result.issues.filter(func(i): return i.check_id == "long-function")
	long_func_issues.sort_custom(func(a, b): return a.severity > b.severity)
	for i in range(mini(15, long_func_issues.size())):
		var issue = long_func_issues[i]
		print("  %s" % issue.get_clickable_format())
	print("")

	# TODO/FIXME summary
	var todo_issues: Array = result.issues.filter(func(i): return i.check_id == "todo-comment")
	if todo_issues.size() > 0:
		print("TODO/FIXME COMMENTS (%d total)" % todo_issues.size())
		print("-" .repeat(40))
		for i in range(mini(10, todo_issues.size())):
			var issue = todo_issues[i]
			print("  %s" % issue.get_clickable_format())
		if todo_issues.size() > 10:
			print("  ... and %d more" % (todo_issues.size() - 10))
		print("")

	print("=" .repeat(60))
	print("Run with --clickable for Godot Output panel clickable links")
	print("Run with --json for machine-readable output")
	print("=" .repeat(60))


func _output_html(result) -> void:
	var output_path := _output_file if _output_file != "" else "code_quality_report.html"

	var html := _generate_html_report(result)

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file:
		file.store_string(html)
		file.close()
		print("HTML report saved to: %s" % output_path)
	else:
		push_error("Failed to write HTML report to: %s" % output_path)


# Type display names for HTML report
const ISSUE_TYPES := {
	"file-length": "File Length",
	"long-function": "Long Function",
	"long-line": "Long Line",
	"todo-comment": "TODO/FIXME",
	"print-statement": "Print Statement",
	"empty-function": "Empty Function",
	"magic-number": "Magic Number",
	"commented-code": "Commented Code",
	"missing-type-hint": "Missing Type Hint",
	"missing-return-type": "Missing Return Type",
	"too-many-params": "Too Many Params",
	"deep-nesting": "Deep Nesting",
	"high-complexity": "High Complexity",
	"god-class": "God Class",
	"naming-class": "Naming: Class",
	"naming-function": "Naming: Function",
	"naming-signal": "Naming: Signal",
	"naming-const": "Naming: Constant",
	"naming-enum": "Naming: Enum",
	"unused-variable": "Unused Variable",
	"unused-parameter": "Unused Parameter"
}


# qube:ignore-next-line - HTML generation is inherently complex
func _generate_html_report(result) -> String:
	var critical: Array = result.get_issues_by_severity(IssueClass.Severity.CRITICAL)
	var warnings: Array = result.get_issues_by_severity(IssueClass.Severity.WARNING)
	var info: Array = result.get_issues_by_severity(IssueClass.Severity.INFO)

	# Collect types by severity for linked filtering
	var types_by_severity: Dictionary = {"all": {}, "critical": {}, "warning": {}, "info": {}}
	for issue in result.issues:
		types_by_severity["all"][issue.check_id] = true
	for issue in critical:
		types_by_severity["critical"][issue.check_id] = true
	for issue in warnings:
		types_by_severity["warning"][issue.check_id] = true
	for issue in info:
		types_by_severity["info"][issue.check_id] = true

	# Build type name mapping for JS
	var type_names_json := "{"
	var first := true
	for check_id in types_by_severity["all"].keys():
		if not first:
			type_names_json += ","
		first = false
		var display_name: String = ISSUE_TYPES.get(check_id, check_id)
		type_names_json += "\"%s\":\"%s\"" % [check_id, display_name]
	type_names_json += "}"

	# Build severity->types mapping for JS
	var severity_types_json := "{"
	for sev in ["all", "critical", "warning", "info"]:
		if sev != "all":
			severity_types_json += ","
		var types_arr: Array = types_by_severity[sev].keys()
		types_arr.sort()
		severity_types_json += "\"%s\":%s" % [sev, JSON.stringify(types_arr)]
	severity_types_json += "}"

	var html := """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Godot Qube - Code Quality Report</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #1a1a2e; color: #eee; padding: 20px; line-height: 1.6; }
.container { max-width: 1200px; margin: 0 auto; }
h1 { color: #00d4ff; margin-bottom: 10px; }
h2 { color: #888; font-size: 1.2em; margin: 20px 0 10px; border-bottom: 1px solid #333; padding-bottom: 5px; }
.header { text-align: center; margin-bottom: 30px; }
.subtitle { color: #888; font-size: 0.9em; }
.filters { background: #16213e; border-radius: 8px; padding: 15px; margin-bottom: 20px; display: flex; flex-wrap: wrap; gap: 15px; align-items: center; }
.filters label { color: #aaa; font-size: 0.95em; font-weight: bold; }
.filters select, .filters input { background: #0f3460; border: 1px solid #333; color: #eee; padding: 8px 12px; border-radius: 4px; font-size: 0.9em; }
.filters input { min-width: 400px; }
.filters select:focus, .filters input:focus { outline: none; border-color: #00d4ff; }
.filter-count { color: #00d4ff; font-weight: bold; margin-left: auto; }
.summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 15px; margin-bottom: 30px; }
.stat-card { background: #16213e; border-radius: 8px; padding: 15px; text-align: center; }
.stat-card .value { font-size: 2em; font-weight: bold; }
.stat-card .label { color: #888; font-size: 0.85em; }
.stat-card.critical .value { color: #ff6b6b; }
.stat-card.warning .value { color: #ffd93d; }
.stat-card.info .value { color: #6bcb77; }
.issues-section { margin-bottom: 30px; }
.section-header { display: flex; align-items: center; gap: 10px; margin-bottom: 15px; }
.section-header .icon { font-size: 1.5em; }
.section-header.critical { color: #ff6b6b; }
.section-header.warning { color: #ffd93d; }
.section-header.info { color: #6bcb77; }
.section-header .count { font-size: 0.8em; color: #888; }
.issue { background: #16213e; border-radius: 6px; padding: 12px 15px; margin-bottom: 8px; display: flex; flex-wrap: wrap; gap: 10px; }
.issue.hidden { display: none; }
.issue .location { font-family: 'Consolas', 'Monaco', monospace; font-size: 0.85em; color: #00d4ff; min-width: 300px; word-break: break-all; }
.issue .message { flex: 1; color: #ccc; }
.issue .check-id { font-size: 0.75em; background: #0f3460; padding: 2px 8px; border-radius: 4px; color: #888; }
.footer { text-align: center; margin-top: 40px; padding-top: 20px; border-top: 1px solid #333; color: #666; font-size: 0.85em; }
.footer a { color: #00d4ff; text-decoration: none; }
.no-results { text-align: center; color: #666; padding: 40px; }
</style>
</head>
<body>
<div class="container">
<div class="header">
<h1>🔷 Godot Qube</h1>
<p class="subtitle">Code Quality Report</p>
</div>

<div class="summary">
<div class="stat-card"><div class="value">%d</div><div class="label">Files Analyzed</div></div>
<div class="stat-card"><div class="value">%d</div><div class="label">Lines of Code</div></div>
<div class="stat-card critical"><div class="value">%d</div><div class="label">Critical Issues</div></div>
<div class="stat-card warning"><div class="value">%d</div><div class="label">Warnings</div></div>
<div class="stat-card info"><div class="value">%d</div><div class="label">Info</div></div>
<div class="stat-card"><div class="value">%d</div><div class="label">Debt Score</div></div>
</div>

<div class="filters">
<label>Severity:</label>
<select id="severityFilter" onchange="onSeverityChange()">
<option value="all">All Severities</option>
<option value="critical">Critical</option>
<option value="warning">Warning</option>
<option value="info">Info</option>
</select>
<label>Type:</label>
<select id="typeFilter" onchange="applyFilters()">
<option value="all">All Types</option>
</select>
<label>File:</label>
<input type="text" id="fileFilter" placeholder="Filter by filename..." oninput="applyFilters()">
<span class="filter-count" id="filterCount"></span>
</div>

<div id="issuesContainer">
""" % [result.files_analyzed, result.total_lines, critical.size(), warnings.size(), info.size(), result.get_total_debt_score()]

	if critical.size() > 0:
		html += "<div class=\"issues-section\" data-severity=\"critical\"><div class=\"section-header critical\"><span class=\"icon\">🔴</span><h2>Critical Issues (<span class=\"count\">%d</span>)</h2></div>\n" % critical.size()
		for issue in critical:
			html += _format_html_issue(issue, "critical")
		html += "</div>\n"

	if warnings.size() > 0:
		html += "<div class=\"issues-section\" data-severity=\"warning\"><div class=\"section-header warning\"><span class=\"icon\">🟡</span><h2>Warnings (<span class=\"count\">%d</span>)</h2></div>\n" % warnings.size()
		for issue in warnings:
			html += _format_html_issue(issue, "warning")
		html += "</div>\n"

	if info.size() > 0:
		html += "<div class=\"issues-section\" data-severity=\"info\"><div class=\"section-header info\"><span class=\"icon\">🔵</span><h2>Info (<span class=\"count\">%d</span>)</h2></div>\n" % info.size()
		for issue in info:
			html += _format_html_issue(issue, "info")
		html += "</div>\n"

	html += """</div>
<div id="noResults" class="no-results" style="display:none;">No issues match the current filters</div>

<div class="footer">
<p>Generated by <a href="https://poplava.itch.io">Godot Qube</a> in %dms</p>
</div>
</div>

<script>
// Type name mapping and severity->types data for linked filtering
const TYPE_NAMES = %s;
const SEVERITY_TYPES = %s;

function populateTypeFilter(severity) {
	const typeFilter = document.getElementById('typeFilter');
	const prevValue = typeFilter.value;

	// Clear and rebuild options
	typeFilter.innerHTML = '<option value="all">All Types</option>';

	const types = SEVERITY_TYPES[severity] || [];
	types.forEach(checkId => {
		const option = document.createElement('option');
		option.value = checkId;
		option.textContent = TYPE_NAMES[checkId] || checkId;
		typeFilter.appendChild(option);
	});

	// Try to restore previous selection if it still exists
	const options = Array.from(typeFilter.options);
	const found = options.find(opt => opt.value === prevValue);
	if (found) {
		typeFilter.value = prevValue;
	} else {
		typeFilter.value = 'all';
	}
}

function onSeverityChange() {
	const severity = document.getElementById('severityFilter').value;
	populateTypeFilter(severity);
	applyFilters();
}

function applyFilters() {
	const severity = document.getElementById('severityFilter').value;
	const type = document.getElementById('typeFilter').value;
	const file = document.getElementById('fileFilter').value.toLowerCase();

	const issues = document.querySelectorAll('.issue');
	let visibleCount = 0;

	issues.forEach(issue => {
		const issueSeverity = issue.dataset.severity;
		const issueType = issue.dataset.type;
		const issueFile = issue.dataset.file.toLowerCase();

		const matchSeverity = severity === 'all' || issueSeverity === severity;
		const matchType = type === 'all' || issueType === type;
		const matchFile = file === '' || issueFile.includes(file);

		if (matchSeverity && matchType && matchFile) {
			issue.classList.remove('hidden');
			visibleCount++;
		} else {
			issue.classList.add('hidden');
		}
	});

	// Update section visibility and counts
	document.querySelectorAll('.issues-section').forEach(section => {
		const visibleInSection = section.querySelectorAll('.issue:not(.hidden)').length;
		section.querySelector('.count').textContent = visibleInSection;
		section.style.display = visibleInSection > 0 ? 'block' : 'none';
	});

	// Show/hide no results message
	document.getElementById('noResults').style.display = visibleCount === 0 ? 'block' : 'none';

	// Update filter count
	const total = issues.length;
	document.getElementById('filterCount').textContent = visibleCount === total ? '' : visibleCount + ' / ' + total + ' shown';
}

// Initialize
populateTypeFilter('all');
applyFilters();
</script>
</body>
</html>
""" % [result.analysis_time_ms, type_names_json, severity_types_json]

	return html


func _format_html_issue(issue, severity: String) -> String:
	var escaped_message: String = issue.message.replace("<", "&lt;").replace(">", "&gt;")
	var escaped_path: String = issue.file_path.replace("\\", "/")
	return "<div class=\"issue\" data-severity=\"%s\" data-type=\"%s\" data-file=\"%s\"><span class=\"location\">%s:%d</span><span class=\"message\">%s</span><span class=\"check-id\">%s</span></div>\n" % [severity, issue.check_id, escaped_path, escaped_path, issue.line, escaped_message, issue.check_id]
