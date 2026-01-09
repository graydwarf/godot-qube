# GDScript Linter - HTML Report Generator
# https://poplava.itch.io
@tool
extends RefCounted
## Generates HTML code quality reports from analysis results

const IssueClass = preload("res://addons/gdscript-linter/analyzer/issue.gd")

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


static func generate(result) -> String:
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

	var html := _get_html_header(result, critical.size(), warnings.size(), info.size())

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

	html += _get_html_footer(result.analysis_time_ms, type_names_json, severity_types_json)

	return html


static func _get_html_header(result, critical_count: int, warning_count: int, info_count: int) -> String:
	return """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>GDScript Linter - Code Quality Report</title>
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
<h1>🔷 GDScript Linter</h1>
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
""" % [result.files_analyzed, result.total_lines, critical_count, warning_count, info_count, result.get_total_debt_score()]


static func _get_html_footer(analysis_time_ms: int, type_names_json: String, severity_types_json: String) -> String:
	return """</div>
<div id="noResults" class="no-results" style="display:none;">No issues match the current filters</div>

<div class="footer">
<p>Generated by <a href="https://poplava.itch.io">GDScript Linter</a> in %dms</p>
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
""" % [analysis_time_ms, type_names_json, severity_types_json]


static func _format_html_issue(issue, severity: String) -> String:
	var escaped_message: String = issue.message.replace("<", "&lt;").replace(">", "&gt;")
	var escaped_path: String = issue.file_path.replace("\\", "/")
	return "<div class=\"issue\" data-severity=\"%s\" data-type=\"%s\" data-file=\"%s\"><span class=\"location\">%s:%d</span><span class=\"message\">%s</span><span class=\"check-id\">%s</span></div>\n" % [severity, issue.check_id, escaped_path, escaped_path, issue.line, escaped_message, issue.check_id]
