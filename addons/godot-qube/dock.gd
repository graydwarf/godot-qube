# Godot Qube - Code quality analyzer for GDScript
# https://poplava.itch.io
@tool
extends Control
## Displays analysis results with clickable navigation

const ISSUES_PER_CATEGORY := 100

# Issue type display names mapped to check_ids
const ISSUE_TYPES := {
	"all": "All Types",
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
	"naming-enum": "Naming: Enum"
}

# UI References
var results_label: RichTextLabel
var scan_button: Button
var export_button: Button
var html_export_button: Button
var severity_filter: OptionButton
var type_filter: OptionButton
var file_filter: LineEdit
var settings_button: Button
var settings_panel: PanelContainer

# Settings controls
var show_issues_check: CheckBox
var show_debt_check: CheckBox
var show_export_check: CheckBox
var max_lines_soft_spin: SpinBox
var max_lines_hard_spin: SpinBox
var max_func_lines_spin: SpinBox
var max_complexity_spin: SpinBox

# State
var current_result  # AnalysisResult instance
var current_severity_filter: String = "all"
var current_type_filter: String = "all"
var current_file_filter: String = ""

# Settings (persisted via EditorSettings if available)
var show_total_issues: bool = true
var show_debt: bool = true
var show_export_button: bool = false

# Preload the analyzer scripts
var CodeAnalyzerScript = preload("res://addons/godot-qube/analyzer/code-analyzer.gd")
var AnalysisConfigScript = preload("res://addons/godot-qube/analyzer/analysis-config.gd")
var IssueScript = preload("res://addons/godot-qube/analyzer/issue.gd")

# Current config instance for settings
var current_config: Resource


func _ready() -> void:
	# Get node references
	results_label = $VBox/ScrollContainer/ResultsLabel
	scan_button = $VBox/Toolbar/ScanButton
	export_button = $VBox/Toolbar/ExportButton
	html_export_button = $VBox/Toolbar/HTMLExportButton
	severity_filter = $VBox/Toolbar/SeverityFilter
	type_filter = $VBox/Toolbar/TypeFilter
	file_filter = $VBox/Toolbar/FileFilter
	settings_button = $VBox/Toolbar/SettingsButton
	settings_panel = $VBox/SettingsPanel

	if not results_label or not scan_button or not severity_filter:
		push_error("Code Quality: Failed to find UI nodes")
		return

	# Get settings controls
	show_issues_check = $VBox/SettingsPanel/Margin/SettingsVBox/DisplayGroup/ShowIssuesCheck
	show_debt_check = $VBox/SettingsPanel/Margin/SettingsVBox/DisplayGroup/ShowDebtCheck
	show_export_check = $VBox/SettingsPanel/Margin/SettingsVBox/DisplayGroup/ShowExportCheck
	max_lines_soft_spin = $VBox/SettingsPanel/Margin/SettingsVBox/LimitsGroup/MaxLinesSoftSpin
	max_lines_hard_spin = $VBox/SettingsPanel/Margin/SettingsVBox/LimitsGroup/MaxLinesHardSpin
	max_func_lines_spin = $VBox/SettingsPanel/Margin/SettingsVBox/LimitsGroup/MaxFuncLinesSpin
	max_complexity_spin = $VBox/SettingsPanel/Margin/SettingsVBox/LimitsGroup/MaxComplexitySpin

	# Connect signals
	results_label.meta_clicked.connect(_on_link_clicked)
	scan_button.pressed.connect(_on_scan_pressed)
	export_button.pressed.connect(_on_export_pressed)
	html_export_button.pressed.connect(_on_html_export_pressed)
	severity_filter.item_selected.connect(_on_severity_filter_changed)
	type_filter.item_selected.connect(_on_type_filter_changed)
	file_filter.text_changed.connect(_on_file_filter_changed)
	settings_button.pressed.connect(_on_settings_pressed)

	# Connect settings controls
	if show_issues_check:
		show_issues_check.toggled.connect(_on_show_issues_toggled)
	if show_debt_check:
		show_debt_check.toggled.connect(_on_show_debt_toggled)
	if show_export_check:
		show_export_check.toggled.connect(_on_show_export_toggled)
	if max_lines_soft_spin:
		max_lines_soft_spin.value_changed.connect(_on_max_lines_soft_changed)
	if max_lines_hard_spin:
		max_lines_hard_spin.value_changed.connect(_on_max_lines_hard_changed)
	if max_func_lines_spin:
		max_func_lines_spin.value_changed.connect(_on_max_func_lines_changed)
	if max_complexity_spin:
		max_complexity_spin.value_changed.connect(_on_max_complexity_changed)

	# Setup severity filter options
	severity_filter.clear()
	severity_filter.add_item("All Severities", 0)
	severity_filter.add_item("Critical", 1)
	severity_filter.add_item("Warnings", 2)
	severity_filter.add_item("Info", 3)

	# Setup type filter options
	_populate_type_filter()

	# Initialize config
	current_config = AnalysisConfigScript.new()
	_load_settings()

	export_button.disabled = true
	html_export_button.disabled = true
	settings_panel.visible = false

	print("Code Quality: Plugin ready")


func _populate_type_filter(severity_filter: String = "all") -> void:
	type_filter.clear()
	var idx := 0

	# Always add "All Types" first
	type_filter.add_item("All Types", idx)
	type_filter.set_item_metadata(idx, "all")
	idx += 1

	# Get available types based on severity filter
	var available_types := _get_available_types_for_severity(severity_filter)

	for check_id in ISSUE_TYPES:
		if check_id == "all":
			continue  # Already added
		# Only add types that have issues at this severity (or all if no filter)
		if severity_filter == "all" or check_id in available_types:
			type_filter.add_item(ISSUE_TYPES[check_id], idx)
			type_filter.set_item_metadata(idx, check_id)
			idx += 1


func _get_available_types_for_severity(severity_filter: String) -> Dictionary:
	# Returns a dictionary of check_ids that have issues at the given severity
	var available: Dictionary = {}
	if not current_result:
		return available

	var Issue = IssueScript
	for issue in current_result.issues:
		var matches_severity := false
		match severity_filter:
			"all":
				matches_severity = true
			"critical":
				matches_severity = issue.severity == Issue.Severity.CRITICAL
			"warning":
				matches_severity = issue.severity == Issue.Severity.WARNING
			"info":
				matches_severity = issue.severity == Issue.Severity.INFO

		if matches_severity:
			available[issue.check_id] = true

	return available


func _load_settings() -> void:
	var editor_settings := EditorInterface.get_editor_settings()

	# Load display settings from EditorSettings
	show_total_issues = editor_settings.get_setting("code_quality/display/show_issues") if editor_settings.has_setting("code_quality/display/show_issues") else true
	show_debt = editor_settings.get_setting("code_quality/display/show_debt") if editor_settings.has_setting("code_quality/display/show_debt") else true
	show_export_button = editor_settings.get_setting("code_quality/display/show_export") if editor_settings.has_setting("code_quality/display/show_export") else false

	# Load analysis limits
	current_config.line_limit_soft = editor_settings.get_setting("code_quality/limits/file_lines_warn") if editor_settings.has_setting("code_quality/limits/file_lines_warn") else 200
	current_config.line_limit_hard = editor_settings.get_setting("code_quality/limits/file_lines_critical") if editor_settings.has_setting("code_quality/limits/file_lines_critical") else 300
	current_config.function_line_limit = editor_settings.get_setting("code_quality/limits/function_lines") if editor_settings.has_setting("code_quality/limits/function_lines") else 30
	current_config.cyclomatic_warning = editor_settings.get_setting("code_quality/limits/complexity_warn") if editor_settings.has_setting("code_quality/limits/complexity_warn") else 10

	# Apply to UI
	show_issues_check.button_pressed = show_total_issues
	show_debt_check.button_pressed = show_debt
	show_export_check.button_pressed = show_export_button
	export_button.visible = show_export_button

	max_lines_soft_spin.value = current_config.line_limit_soft
	max_lines_hard_spin.value = current_config.line_limit_hard
	max_func_lines_spin.value = current_config.function_line_limit
	max_complexity_spin.value = current_config.cyclomatic_warning


func _save_setting(key: String, value: Variant) -> void:
	var editor_settings := EditorInterface.get_editor_settings()
	editor_settings.set_setting(key, value)


func _on_scan_pressed() -> void:
	print("Code Quality: Scan button pressed")
	scan_button.disabled = true
	export_button.disabled = true
	html_export_button.disabled = true
	results_label.text = "[color=#888888]Analyzing codebase...[/color]"

	# Use call_deferred to allow UI to update
	call_deferred("_run_analysis")


func _run_analysis() -> void:
	print("Code Quality: Starting analysis...")

	var analyzer = CodeAnalyzerScript.new(current_config)
	current_result = analyzer.analyze_directory("res://")

	print("Code Quality: Analysis complete - %d issues found" % current_result.issues.size())

	_display_results()

	scan_button.disabled = false
	export_button.disabled = false
	html_export_button.disabled = false


func _on_export_pressed() -> void:
	if not current_result:
		return

	var json_str := JSON.stringify(current_result.to_dict(), "\t")
	var export_path := "res://code_quality_report.json"

	var file := FileAccess.open(export_path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()
		print("Code Quality: Exported to %s" % export_path)

		# Open the file in the editor
		var script = load(export_path)
		if script:
			EditorInterface.edit_resource(script)
	else:
		push_error("Code Quality: Failed to write export file")
		OS.alert("Failed to write JSON export file:\n%s" % export_path, "Export Error")


func _on_html_export_pressed() -> void:
	if not current_result:
		return

	var html := _generate_html_report()
	var export_path := "res://code_quality_report.html"

	var file := FileAccess.open(export_path, FileAccess.WRITE)
	if file:
		file.store_string(html)
		file.close()
		print("Code Quality: HTML report exported to %s" % export_path)
		OS.shell_open(ProjectSettings.globalize_path(export_path))
	else:
		push_error("Code Quality: Failed to write HTML report")
		OS.alert("Failed to write HTML export file:\n%s" % export_path, "Export Error")


func _generate_html_report() -> String:
	var critical: Array = current_result.get_issues_by_severity(IssueScript.Severity.CRITICAL)
	var warnings: Array = current_result.get_issues_by_severity(IssueScript.Severity.WARNING)
	var info: Array = current_result.get_issues_by_severity(IssueScript.Severity.INFO)

	# Collect types by severity for linked filtering
	var types_by_severity: Dictionary = {
		"all": {},
		"critical": {},
		"warning": {},
		"info": {}
	}
	for issue in current_result.issues:
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
""" % [current_result.files_analyzed, current_result.total_lines, critical.size(), warnings.size(), info.size(), current_result.get_total_debt_score()]

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
""" % [current_result.analysis_time_ms, type_names_json, severity_types_json]

	return html


func _format_html_issue(issue, severity: String) -> String:
	var escaped_message: String = issue.message.replace("<", "&lt;").replace(">", "&gt;")
	var escaped_path: String = issue.file_path.replace("\\", "/")
	return "<div class=\"issue\" data-severity=\"%s\" data-type=\"%s\" data-file=\"%s\"><span class=\"location\">%s:%d</span><span class=\"message\">%s</span><span class=\"check-id\">%s</span></div>\n" % [severity, issue.check_id, escaped_path, escaped_path, issue.line, escaped_message, issue.check_id]


func _on_severity_filter_changed(index: int) -> void:
	match index:
		0: current_severity_filter = "all"
		1: current_severity_filter = "critical"
		2: current_severity_filter = "warning"
		3: current_severity_filter = "info"

	if current_result:
		# Remember current type selection
		var prev_type := current_type_filter

		# Repopulate type filter based on new severity
		_populate_type_filter(current_severity_filter)

		# Try to restore previous type selection, or reset to "all"
		var restored := false
		for i in range(type_filter.item_count):
			if type_filter.get_item_metadata(i) == prev_type:
				type_filter.select(i)
				current_type_filter = prev_type
				restored = true
				break

		if not restored:
			type_filter.select(0)
			current_type_filter = "all"

		_display_results()


func _on_type_filter_changed(index: int) -> void:
	current_type_filter = type_filter.get_item_metadata(index)
	if current_result:
		_display_results()


func _on_file_filter_changed(new_text: String) -> void:
	current_file_filter = new_text.to_lower()
	if current_result:
		_display_results()


func _on_settings_pressed() -> void:
	settings_panel.visible = not settings_panel.visible


func _on_show_issues_toggled(pressed: bool) -> void:
	show_total_issues = pressed
	_save_setting("code_quality/display/show_issues", pressed)
	if current_result:
		_display_results()


func _on_show_debt_toggled(pressed: bool) -> void:
	show_debt = pressed
	_save_setting("code_quality/display/show_debt", pressed)
	if current_result:
		_display_results()


func _on_show_export_toggled(pressed: bool) -> void:
	show_export_button = pressed
	_save_setting("code_quality/display/show_export", pressed)
	export_button.visible = pressed


func _on_max_lines_soft_changed(value: float) -> void:
	current_config.line_limit_soft = int(value)
	_save_setting("code_quality/limits/file_lines_warn", int(value))


func _on_max_lines_hard_changed(value: float) -> void:
	current_config.line_limit_hard = int(value)
	_save_setting("code_quality/limits/file_lines_critical", int(value))


func _on_max_func_lines_changed(value: float) -> void:
	current_config.function_line_limit = int(value)
	_save_setting("code_quality/limits/function_lines", int(value))


func _on_max_complexity_changed(value: float) -> void:
	current_config.cyclomatic_warning = int(value)
	_save_setting("code_quality/limits/complexity_warn", int(value))


func _display_results() -> void:
	if not current_result:
		return

	var bbcode := "[b]Code Quality Report[/b]\n"
	bbcode += "Files: %d | Lines: %d | Time: %dms\n" % [
		current_result.files_analyzed,
		current_result.total_lines,
		current_result.analysis_time_ms
	]

	# Add Issues/Debt summary on line 2 based on settings
	var summary_parts: Array[String] = []
	if show_total_issues:
		summary_parts.append("Issues: %d" % current_result.issues.size())
	if show_debt:
		summary_parts.append("Debt: %d" % current_result.get_total_debt_score())
	if summary_parts.size() > 0:
		bbcode += " | ".join(summary_parts) + "\n"
	bbcode += "\n"

	var issues_to_show: Array = []
	var Issue = IssueScript  # Reference for severity enum

	# Start with all issues
	issues_to_show = current_result.issues.duplicate()

	# Filter by severity
	if current_severity_filter != "all":
		var severity_filtered: Array = []
		for issue in issues_to_show:
			match current_severity_filter:
				"critical":
					if issue.severity == Issue.Severity.CRITICAL:
						severity_filtered.append(issue)
				"warning":
					if issue.severity == Issue.Severity.WARNING:
						severity_filtered.append(issue)
				"info":
					if issue.severity == Issue.Severity.INFO:
						severity_filtered.append(issue)
		issues_to_show = severity_filtered

	# Filter by type
	if current_type_filter != "all":
		var type_filtered: Array = []
		for issue in issues_to_show:
			if issue.check_id == current_type_filter:
				type_filtered.append(issue)
		issues_to_show = type_filtered

	# Filter by filename
	if current_file_filter != "":
		var filtered: Array = []
		for issue in issues_to_show:
			if current_file_filter in issue.file_path.to_lower():
				filtered.append(issue)
		issues_to_show = filtered

	# Show active filters
	var active_filters: Array[String] = []
	if current_severity_filter != "all":
		active_filters.append(current_severity_filter.capitalize())
	if current_type_filter != "all":
		active_filters.append(ISSUE_TYPES.get(current_type_filter, current_type_filter))
	if current_file_filter != "":
		active_filters.append("\"%s\"" % current_file_filter)

	if active_filters.size() > 0:
		bbcode += "[color=#888888]Filters: %s (%d matches)[/color]\n\n" % [", ".join(active_filters), issues_to_show.size()]

	# Group by severity
	var critical: Array = []
	var warnings: Array = []
	var info: Array = []

	for issue in issues_to_show:
		match issue.severity:
			Issue.Severity.CRITICAL:
				critical.append(issue)
			Issue.Severity.WARNING:
				warnings.append(issue)
			Issue.Severity.INFO:
				info.append(issue)

	if critical.size() > 0:
		bbcode += "[color=#ff6b6b][b]🔴 CRITICAL (%d)[/b][/color]\n" % critical.size()
		bbcode += _format_issues_by_type(critical, "#ff6b6b")
		bbcode += "\n"

	if warnings.size() > 0:
		bbcode += "[color=#ffd93d][b]🟡 WARNINGS (%d)[/b][/color]\n" % warnings.size()
		bbcode += _format_issues_by_type(warnings, "#ffd93d")
		bbcode += "\n"

	if info.size() > 0:
		bbcode += "[color=#6bcb77][b]🔵 INFO (%d)[/b][/color]\n" % info.size()
		bbcode += _format_issues_by_type(info, "#6bcb77")

	if issues_to_show.size() == 0:
		bbcode += "[color=#888888]No issues matching current filters[/color]"

	results_label.text = bbcode


func _format_issues_by_type(issues: Array, color: String) -> String:
	var bbcode := ""

	# Group issues by check_id
	var by_type: Dictionary = {}
	for issue in issues:
		var check_id: String = issue.check_id
		if not by_type.has(check_id):
			by_type[check_id] = []
		by_type[check_id].append(issue)

	# Sort types by count (most issues first)
	var type_keys := by_type.keys()
	type_keys.sort_custom(func(a, b): return by_type[a].size() > by_type[b].size())

	var is_first_type := true
	for check_id in type_keys:
		var type_issues: Array = by_type[check_id]
		var type_name: String = ISSUE_TYPES.get(check_id, check_id)

		# Add blank line between type groups (except before first)
		if not is_first_type:
			bbcode += "\n"
		is_first_type = false

		# Type sub-heading
		bbcode += "  [color=#aaaaaa]── %s (%d) ──[/color]\n" % [type_name, type_issues.size()]

		# Show issues for this type (limited)
		var shown := 0
		for issue in type_issues:
			if shown >= ISSUES_PER_CATEGORY:
				bbcode += "  [color=#888888]  ... and %d more[/color]\n" % (type_issues.size() - shown)
				break
			bbcode += _format_issue(issue, color)
			shown += 1

	return bbcode


func _format_issue(issue, color: String) -> String:
	var short_path: String = issue.file_path.get_file()
	var link := "%s:%d" % [issue.file_path, issue.line]

	return "    [url=%s][color=%s]%s:%d[/color][/url] %s\n" % [
		link, color, short_path, issue.line, issue.message
	]


func _on_link_clicked(meta: Variant) -> void:
	var location := str(meta)
	print("Code Quality: Link clicked - %s" % location)

	var parts := location.rsplit(":", true, 1)

	if parts.size() < 2:
		push_warning("Invalid link format: %s" % location)
		return

	var file_path: String = parts[0]
	var line_num := int(parts[1])

	# Load and open the script
	var script = load(file_path)
	if script:
		EditorInterface.edit_script(script, line_num, 0)
		EditorInterface.set_main_screen_editor("Script")
	else:
		push_warning("Could not load script: %s" % file_path)
