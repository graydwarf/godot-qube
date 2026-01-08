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
	"naming-enum": "Naming: Enum",
	"unused-variable": "Unused Variable",
	"unused-parameter": "Unused Parameter"
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
var show_json_export_check: CheckBox
var show_html_export_check: CheckBox
var respect_gdignore_check: CheckBox
var scan_addons_check: CheckBox
var max_lines_soft_spin: SpinBox
var max_lines_hard_spin: SpinBox
var max_func_lines_spin: SpinBox
var max_complexity_spin: SpinBox
var func_lines_crit_spin: SpinBox
var max_complexity_crit_spin: SpinBox
var max_params_spin: SpinBox
var max_nesting_spin: SpinBox
var god_class_funcs_spin: SpinBox
var god_class_signals_spin: SpinBox

# Claude Code settings controls
var claude_enabled_check: CheckBox
var claude_command_edit: LineEdit
var claude_reset_button: Button
var claude_instructions_edit: TextEdit

# State
var current_result  # AnalysisResult instance
var current_severity_filter: String = "all"
var current_type_filter: String = "all"
var current_file_filter: String = ""

# Settings (persisted via EditorSettings if available)
var show_total_issues: bool = true
var show_debt: bool = true
var show_json_export: bool = false
var show_html_export: bool = true
var respect_gdignore: bool = true  # Skip directories with .gdignore files
var scan_addons: bool = false  # Include addons/ folder in scans (disabled by default)

# Claude Code settings
var claude_code_enabled: bool = false
var claude_code_command: String = "claude --permission-mode plan"
var claude_custom_instructions: String = ""
const CLAUDE_CODE_DEFAULT_COMMAND := "claude --permission-mode plan"

# Analysis limits defaults
const DEFAULT_FILE_LINES_SOFT := 200
const DEFAULT_FILE_LINES_HARD := 300
const DEFAULT_FUNC_LINES := 30
const DEFAULT_FUNC_LINES_CRIT := 60
const DEFAULT_COMPLEXITY_WARN := 10
const DEFAULT_COMPLEXITY_CRIT := 15
const DEFAULT_MAX_PARAMS := 4
const DEFAULT_MAX_NESTING := 3
const DEFAULT_GOD_CLASS_FUNCS := 20
const DEFAULT_GOD_CLASS_SIGNALS := 10

# Preload the analyzer scripts
var CodeAnalyzerScript = preload("res://addons/godot-qube/analyzer/code-analyzer.gd")
var AnalysisConfigScript = preload("res://addons/godot-qube/analyzer/analysis-config.gd")
var IssueScript = preload("res://addons/godot-qube/analyzer/issue.gd")

# Icons
var _claude_icon: Texture2D
var _reset_icon: Texture2D

# Current config instance for settings
var current_config: Resource


# qube:ignore-next-line - UI initialization requires many node references
func _ready() -> void:
	# Load icons
	_claude_icon = load("res://addons/godot-qube/icons/claude.png")
	_reset_icon = load("res://addons/godot-qube/icons/arrow-reset.svg")

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

	# Darken the dock background
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.14, 1.0)  # Darker gray background
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	move_child(bg, 0)  # Move to back

	# Initialize config first (needed for settings cards)
	current_config = AnalysisConfigScript.new()

	# Build settings panel with cards (creates all settings controls)
	_setup_settings_cards()

	# Connect signals - disable visual artifacts on links
	results_label.meta_underlined = false
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
	if show_json_export_check:
		show_json_export_check.toggled.connect(_on_show_json_export_toggled)
	if show_html_export_check:
		show_html_export_check.toggled.connect(_on_show_html_export_toggled)
	# Connect spinbox signals for auto-save
	if max_lines_soft_spin:
		max_lines_soft_spin.value_changed.connect(_on_max_lines_soft_changed)
	else:
		push_error("Code Quality: max_lines_soft_spin is null!")
	if max_lines_hard_spin:
		max_lines_hard_spin.value_changed.connect(_on_max_lines_hard_changed)
	if max_func_lines_spin:
		max_func_lines_spin.value_changed.connect(_on_max_func_lines_changed)
	if max_complexity_spin:
		max_complexity_spin.value_changed.connect(_on_max_complexity_changed)
	if func_lines_crit_spin:
		func_lines_crit_spin.value_changed.connect(_on_func_lines_crit_changed)
	if max_complexity_crit_spin:
		max_complexity_crit_spin.value_changed.connect(_on_max_complexity_crit_changed)
	if max_params_spin:
		max_params_spin.value_changed.connect(_on_max_params_changed)
	if max_nesting_spin:
		max_nesting_spin.value_changed.connect(_on_max_nesting_changed)
	if god_class_funcs_spin:
		god_class_funcs_spin.value_changed.connect(_on_god_class_funcs_changed)
	if god_class_signals_spin:
		god_class_signals_spin.value_changed.connect(_on_god_class_signals_changed)
	print("Code Quality: Spinbox signals connected")

	# Setup severity filter options
	severity_filter.clear()
	severity_filter.add_item("All Severities", 0)
	severity_filter.add_item("Critical", 1)
	severity_filter.add_item("Warnings", 2)
	severity_filter.add_item("Info", 3)

	# Setup type filter options
	_populate_type_filter()

	# Load persisted settings (applies to config and UI controls)
	_load_settings()

	export_button.disabled = true
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


# qube:ignore-next-line - Settings loading requires many conditional reads
func _load_settings() -> void:
	var editor_settings := EditorInterface.get_editor_settings()

	# Load display settings from EditorSettings
	show_total_issues = editor_settings.get_setting("code_quality/display/show_issues") if editor_settings.has_setting("code_quality/display/show_issues") else true
	show_debt = editor_settings.get_setting("code_quality/display/show_debt") if editor_settings.has_setting("code_quality/display/show_debt") else true
	show_json_export = editor_settings.get_setting("code_quality/display/show_json_export") if editor_settings.has_setting("code_quality/display/show_json_export") else false
	show_html_export = editor_settings.get_setting("code_quality/display/show_html_export") if editor_settings.has_setting("code_quality/display/show_html_export") else true
	respect_gdignore = editor_settings.get_setting("code_quality/scanning/respect_gdignore") if editor_settings.has_setting("code_quality/scanning/respect_gdignore") else true
	current_config.respect_gdignore = respect_gdignore
	scan_addons = editor_settings.get_setting("code_quality/scanning/scan_addons") if editor_settings.has_setting("code_quality/scanning/scan_addons") else false
	current_config.scan_addons = scan_addons

	# Load analysis limits
	current_config.line_limit_soft = editor_settings.get_setting("code_quality/limits/file_lines_warn") if editor_settings.has_setting("code_quality/limits/file_lines_warn") else 200
	current_config.line_limit_hard = editor_settings.get_setting("code_quality/limits/file_lines_critical") if editor_settings.has_setting("code_quality/limits/file_lines_critical") else 300
	current_config.function_line_limit = editor_settings.get_setting("code_quality/limits/function_lines") if editor_settings.has_setting("code_quality/limits/function_lines") else 30
	current_config.function_line_critical = editor_settings.get_setting("code_quality/limits/function_lines_crit") if editor_settings.has_setting("code_quality/limits/function_lines_crit") else 60
	current_config.cyclomatic_warning = editor_settings.get_setting("code_quality/limits/complexity_warn") if editor_settings.has_setting("code_quality/limits/complexity_warn") else 10
	current_config.cyclomatic_critical = editor_settings.get_setting("code_quality/limits/complexity_crit") if editor_settings.has_setting("code_quality/limits/complexity_crit") else 15
	current_config.max_parameters = editor_settings.get_setting("code_quality/limits/max_params") if editor_settings.has_setting("code_quality/limits/max_params") else 4
	current_config.max_nesting = editor_settings.get_setting("code_quality/limits/max_nesting") if editor_settings.has_setting("code_quality/limits/max_nesting") else 3
	current_config.god_class_functions = editor_settings.get_setting("code_quality/limits/god_class_funcs") if editor_settings.has_setting("code_quality/limits/god_class_funcs") else 20
	current_config.god_class_signals = editor_settings.get_setting("code_quality/limits/god_class_signals") if editor_settings.has_setting("code_quality/limits/god_class_signals") else 10

	# Apply to UI
	show_issues_check.button_pressed = show_total_issues
	show_debt_check.button_pressed = show_debt
	show_json_export_check.button_pressed = show_json_export
	show_html_export_check.button_pressed = show_html_export
	respect_gdignore_check.button_pressed = respect_gdignore
	scan_addons_check.button_pressed = scan_addons
	export_button.visible = show_json_export
	html_export_button.visible = show_html_export

	max_lines_soft_spin.value = current_config.line_limit_soft
	max_lines_hard_spin.value = current_config.line_limit_hard
	max_func_lines_spin.value = current_config.function_line_limit
	max_complexity_spin.value = current_config.cyclomatic_warning
	func_lines_crit_spin.value = current_config.function_line_critical
	max_complexity_crit_spin.value = current_config.cyclomatic_critical
	max_params_spin.value = current_config.max_parameters
	max_nesting_spin.value = current_config.max_nesting
	god_class_funcs_spin.value = current_config.god_class_functions
	god_class_signals_spin.value = current_config.god_class_signals

	# Load Claude Code settings
	claude_code_enabled = editor_settings.get_setting("code_quality/claude/enabled") if editor_settings.has_setting("code_quality/claude/enabled") else false
	claude_code_command = editor_settings.get_setting("code_quality/claude/launch_command") if editor_settings.has_setting("code_quality/claude/launch_command") else CLAUDE_CODE_DEFAULT_COMMAND
	claude_custom_instructions = editor_settings.get_setting("code_quality/claude/custom_instructions") if editor_settings.has_setting("code_quality/claude/custom_instructions") else ""
	claude_enabled_check.button_pressed = claude_code_enabled
	claude_command_edit.text = claude_code_command
	claude_instructions_edit.text = claude_custom_instructions


func _save_setting(key: String, value: Variant) -> void:
	var editor_settings := EditorInterface.get_editor_settings()
	editor_settings.set_setting(key, value)
	print("Code Quality: Saved %s = %s" % [key, value])


func _on_scan_pressed() -> void:
	print("Code Quality: Scan button pressed")

	# Hide settings, show results
	settings_panel.visible = false
	$VBox/ScrollContainer.visible = true

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
	# Create empty result if none exists yet
	if not current_result:
		var AnalysisResultScript = preload("res://addons/godot-qube/analyzer/analysis-result.gd")
		current_result = AnalysisResultScript.new()

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


# qube:ignore-next-line - HTML generation is inherently complex
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
	# Settings and results are mutually exclusive
	$VBox/ScrollContainer.visible = not settings_panel.visible


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


func _on_show_json_export_toggled(pressed: bool) -> void:
	show_json_export = pressed
	_save_setting("code_quality/display/show_json_export", pressed)
	export_button.visible = pressed


func _on_show_html_export_toggled(pressed: bool) -> void:
	show_html_export = pressed
	_save_setting("code_quality/display/show_html_export", pressed)
	html_export_button.visible = pressed


func _on_respect_gdignore_toggled(pressed: bool) -> void:
	respect_gdignore = pressed
	current_config.respect_gdignore = pressed
	_save_setting("code_quality/scanning/respect_gdignore", pressed)


func _on_scan_addons_toggled(pressed: bool) -> void:
	scan_addons = pressed
	current_config.scan_addons = pressed
	_save_setting("code_quality/scanning/scan_addons", pressed)


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


func _on_func_lines_crit_changed(value: float) -> void:
	current_config.function_line_critical = int(value)
	_save_setting("code_quality/limits/function_lines_crit", int(value))


func _on_max_complexity_crit_changed(value: float) -> void:
	current_config.cyclomatic_critical = int(value)
	_save_setting("code_quality/limits/complexity_crit", int(value))


func _on_max_params_changed(value: float) -> void:
	current_config.max_parameters = int(value)
	_save_setting("code_quality/limits/max_params", int(value))


func _on_max_nesting_changed(value: float) -> void:
	current_config.max_nesting = int(value)
	_save_setting("code_quality/limits/max_nesting", int(value))


func _on_god_class_funcs_changed(value: float) -> void:
	current_config.god_class_functions = int(value)
	_save_setting("code_quality/limits/god_class_funcs", int(value))


func _on_god_class_signals_changed(value: float) -> void:
	current_config.god_class_signals = int(value)
	_save_setting("code_quality/limits/god_class_signals", int(value))


func _on_claude_enabled_toggled(pressed: bool) -> void:
	claude_code_enabled = pressed
	_save_setting("code_quality/claude/enabled", pressed)
	if current_result:
		_display_results()


func _on_claude_command_changed(new_text: String) -> void:
	claude_code_command = new_text
	_save_setting("code_quality/claude/launch_command", new_text)


func _on_claude_instructions_changed() -> void:
	claude_custom_instructions = claude_instructions_edit.text
	_save_setting("code_quality/claude/custom_instructions", claude_custom_instructions)


func _on_claude_reset_pressed() -> void:
	claude_code_command = CLAUDE_CODE_DEFAULT_COMMAND
	claude_command_edit.text = CLAUDE_CODE_DEFAULT_COMMAND
	_save_setting("code_quality/claude/launch_command", CLAUDE_CODE_DEFAULT_COMMAND)


# qube:ignore-next-line - Results display requires formatting for all issue types
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

	var line := "    [url=%s][color=%s]%s:%d[/color][/url] %s" % [
		link, color, short_path, issue.line, issue.message
	]

	# Add Claude Code button if enabled
	if claude_code_enabled:
		var severity_str: String = "unknown"
		var Issue = IssueScript
		match issue.severity:
			Issue.Severity.CRITICAL:
				severity_str = "critical"
			Issue.Severity.WARNING:
				severity_str = "warning"
			Issue.Severity.INFO:
				severity_str = "info"

		# Encode issue data in URL (use | as separator since it's URL-safe)
		var claude_data := "%s|%d|%s|%s|%s" % [
			issue.file_path,
			issue.line,
			issue.check_id,
			severity_str,
			issue.message.replace("|", "-")  # Escape any | in message
		]
		# Use invisible padding character to avoid URL styling artifacts
		line += " [url=claude://%s][img=20x20]res://addons/godot-qube/icons/claude.png[/img][/url]" % claude_data.uri_encode()

	return line + "\n"


func _on_link_clicked(meta: Variant) -> void:
	var location := str(meta)

	# Handle Claude Code links
	if location.begins_with("claude://"):
		var encoded_data: String = location.substr(9)  # Remove "claude://"
		var decoded_data: String = encoded_data.uri_decode()
		var parts := decoded_data.split("|")

		if parts.size() >= 5:
			var issue_data := {
				"file_path": parts[0],
				"line": int(parts[1]),
				"check_id": parts[2],
				"severity": parts[3],
				"message": parts[4]
			}
			_on_claude_button_pressed(issue_data)
		else:
			push_warning("Invalid Claude link format: %s" % location)
		return

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


# Launch Claude Code with issue context
func _on_claude_button_pressed(issue: Dictionary) -> void:
	var project_path := ProjectSettings.globalize_path("res://")

	# Build the prompt with issue details
	var prompt := "Code quality issue to fix:\n\n"
	prompt += "File: %s\n" % issue.file_path
	prompt += "Line: %d\n" % issue.line
	prompt += "Type: %s\n" % issue.check_id
	prompt += "Severity: %s\n" % issue.severity
	prompt += "Message: %s\n\n" % issue.message
	prompt += "Analyze this issue and suggest a fix."

	# Append custom instructions if provided
	if not claude_custom_instructions.strip_edges().is_empty():
		prompt += "\n\n" + claude_custom_instructions

	# Escape single quotes for PowerShell
	var escaped_prompt := prompt.replace("'", "''")

	print("Code Quality: Launching Claude Code for %s:%d" % [issue.file_path, issue.line])

	# Launch via Windows Terminal with customizable command
	var args: PackedStringArray = [
		"-d", project_path,
		"powershell", "-NoProfile", "-NoExit",
		"-Command", "%s '%s'" % [claude_code_command, escaped_prompt]
	]
	OS.create_process("wt", args)


# ========== Settings Card UI ==========

# Create About section card
# qube:ignore-next-line - UI card creation requires many style and layout calls
func _create_about_card() -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.17, 0.22, 0.9)
	style.border_color = Color(0.3, 0.35, 0.45, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	# Header
	var header := Label.new()
	header.text = "About"
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	vbox.add_child(header)

	# Plugin title
	var title := Label.new()
	title.text = "Godot Qube"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.4, 0.75, 1.0))
	vbox.add_child(title)

	# Subtitle
	var subtitle := Label.new()
	subtitle.text = "Code Quality Analyzer for GDScript"
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	vbox.add_child(subtitle)

	# License
	var license_lbl := Label.new()
	license_lbl.text = "MIT License - Copyright (c) 2025 Poplava"
	license_lbl.add_theme_font_size_override("font_size", 11)
	license_lbl.add_theme_color_override("font_color", Color(0.5, 0.52, 0.55))
	vbox.add_child(license_lbl)

	# Links row
	var links := HBoxContainer.new()
	links.add_theme_constant_override("separation", 15)
	vbox.add_child(links)

	var link_data := [
		["Discord", "https://discord.gg/9GnrTKXGfq"],
		["GitHub", "https://github.com/graydwarf/godot-qube"],
		["More Tools", "https://poplava.itch.io"]
	]
	for data in link_data:
		var btn := Button.new()
		btn.text = data[0]
		btn.flat = true
		btn.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(0.7, 0.85, 1.0))
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var url: String = data[1]
		btn.pressed.connect(func(): OS.shell_open(url))
		links.add_child(btn)

	return card


# Setup settings panel with cards and scroll container (creates all controls)
func _setup_settings_cards() -> void:
	# Create ScrollContainer wrapper
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	# Create margin container (10px all sides)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	scroll.add_child(margin)

	# Create cards container (10px between cards)
	var cards_vbox := VBoxContainer.new()
	cards_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(cards_vbox)

	# Create Display Options card
	var display_card := _create_display_options_card()
	cards_vbox.add_child(display_card)

	# Create Analysis Limits card
	var limits_card := _create_limits_card()
	cards_vbox.add_child(limits_card)

	# Create Claude Code card
	var claude_card := _create_claude_code_card()
	cards_vbox.add_child(claude_card)

	# Create About card
	var about_card := _create_about_card()
	cards_vbox.add_child(about_card)

	# Add scroll to settings panel
	settings_panel.add_child(scroll)

	# Settings panel fills available height
	settings_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL


# Create Display Options card with checkboxes
# qube:ignore-next-line - UI card creation requires many style and layout calls
func _create_display_options_card() -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.17, 0.22, 0.9)
	style.border_color = Color(0.3, 0.35, 0.45, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	# Header
	var header := Label.new()
	header.text = "Display Options"
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	vbox.add_child(header)

	# Checkboxes row
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	vbox.add_child(hbox)

	show_issues_check = CheckBox.new()
	show_issues_check.text = "Show Issues"
	show_issues_check.button_pressed = show_total_issues
	hbox.add_child(show_issues_check)

	show_debt_check = CheckBox.new()
	show_debt_check.text = "Show Debt"
	show_debt_check.button_pressed = show_debt
	hbox.add_child(show_debt_check)

	show_json_export_check = CheckBox.new()
	show_json_export_check.text = "JSON Export"
	show_json_export_check.button_pressed = show_json_export
	hbox.add_child(show_json_export_check)

	show_html_export_check = CheckBox.new()
	show_html_export_check.text = "HTML Export"
	show_html_export_check.button_pressed = show_html_export
	hbox.add_child(show_html_export_check)

	# Second row for scanning options
	var hbox2 := HBoxContainer.new()
	hbox2.add_theme_constant_override("separation", 15)
	vbox.add_child(hbox2)

	respect_gdignore_check = CheckBox.new()
	respect_gdignore_check.text = "Respect .gdignore"
	respect_gdignore_check.tooltip_text = "Skip directories containing .gdignore files (matches Godot editor behavior)"
	respect_gdignore_check.button_pressed = respect_gdignore
	respect_gdignore_check.toggled.connect(_on_respect_gdignore_toggled)
	hbox2.add_child(respect_gdignore_check)

	scan_addons_check = CheckBox.new()
	scan_addons_check.text = "Scan addons/"
	scan_addons_check.tooltip_text = "Include addons/ folder in code quality scans (disabled by default)"
	scan_addons_check.button_pressed = scan_addons
	scan_addons_check.toggled.connect(_on_scan_addons_toggled)
	hbox2.add_child(scan_addons_check)

	return card


# Create Analysis Limits card with spinboxes
# qube:ignore-next-line - UI card creation requires many style and layout calls
func _create_limits_card() -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.17, 0.22, 0.9)
	style.border_color = Color(0.3, 0.35, 0.45, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	# Header row with Reset All button
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	vbox.add_child(header_row)

	var header := Label.new()
	header.text = "Analysis Limits"
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	header_row.add_child(header)

	var reset_all_btn := Button.new()
	reset_all_btn.icon = _reset_icon
	reset_all_btn.tooltip_text = "Reset all limits to defaults"
	reset_all_btn.flat = true
	reset_all_btn.custom_minimum_size = Vector2(16, 16)
	reset_all_btn.pressed.connect(_on_reset_all_limits_pressed)
	header_row.add_child(reset_all_btn)

	# Grid for spinboxes (6 columns: label, spin, reset, label, spin, reset)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)

	# Row 1: File lines soft/hard
	max_lines_soft_spin = _add_spin_row(grid, "File Lines (warn):", 50, 1000, current_config.line_limit_soft if current_config else DEFAULT_FILE_LINES_SOFT, DEFAULT_FILE_LINES_SOFT)
	max_lines_hard_spin = _add_spin_row(grid, "File Lines (crit):", 100, 2000, current_config.line_limit_hard if current_config else DEFAULT_FILE_LINES_HARD, DEFAULT_FILE_LINES_HARD)

	# Row 2: Function lines / complexity warning
	max_func_lines_spin = _add_spin_row(grid, "Func Lines:", 10, 200, current_config.function_line_limit if current_config else DEFAULT_FUNC_LINES, DEFAULT_FUNC_LINES)
	max_complexity_spin = _add_spin_row(grid, "Complexity (warn):", 5, 50, current_config.cyclomatic_warning if current_config else DEFAULT_COMPLEXITY_WARN, DEFAULT_COMPLEXITY_WARN)

	# Row 3: Func lines critical / complexity critical
	func_lines_crit_spin = _add_spin_row(grid, "Func Lines (crit):", 20, 300, current_config.function_line_critical if current_config else DEFAULT_FUNC_LINES_CRIT, DEFAULT_FUNC_LINES_CRIT)
	max_complexity_crit_spin = _add_spin_row(grid, "Complexity (crit):", 5, 50, current_config.cyclomatic_critical if current_config else DEFAULT_COMPLEXITY_CRIT, DEFAULT_COMPLEXITY_CRIT)

	# Row 4: Max params / nesting
	max_params_spin = _add_spin_row(grid, "Max Params:", 2, 15, current_config.max_parameters if current_config else DEFAULT_MAX_PARAMS, DEFAULT_MAX_PARAMS)
	max_nesting_spin = _add_spin_row(grid, "Max Nesting:", 2, 10, current_config.max_nesting if current_config else DEFAULT_MAX_NESTING, DEFAULT_MAX_NESTING)

	# Row 5: God class thresholds
	god_class_funcs_spin = _add_spin_row(grid, "God Class Funcs:", 5, 50, current_config.god_class_functions if current_config else DEFAULT_GOD_CLASS_FUNCS, DEFAULT_GOD_CLASS_FUNCS)
	god_class_signals_spin = _add_spin_row(grid, "God Class Signals:", 3, 30, current_config.god_class_signals if current_config else DEFAULT_GOD_CLASS_SIGNALS, DEFAULT_GOD_CLASS_SIGNALS)

	return card


# Helper to add a label + spinbox + reset button to a grid
func _add_spin_row(grid: GridContainer, label_text: String, min_val: int, max_val: int, current_val: int, default_val: int) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.75))
	grid.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.value = current_val
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(spin)

	var reset_btn := Button.new()
	reset_btn.icon = _reset_icon
	reset_btn.tooltip_text = "Reset to default (%d)" % default_val
	reset_btn.flat = true
	reset_btn.custom_minimum_size = Vector2(16, 16)
	reset_btn.pressed.connect(func(): spin.value = default_val)
	grid.add_child(reset_btn)

	return spin


# Reset all analysis limits to defaults
func _on_reset_all_limits_pressed() -> void:
	max_lines_soft_spin.value = DEFAULT_FILE_LINES_SOFT
	max_lines_hard_spin.value = DEFAULT_FILE_LINES_HARD
	max_func_lines_spin.value = DEFAULT_FUNC_LINES
	func_lines_crit_spin.value = DEFAULT_FUNC_LINES_CRIT
	max_complexity_spin.value = DEFAULT_COMPLEXITY_WARN
	max_complexity_crit_spin.value = DEFAULT_COMPLEXITY_CRIT
	max_params_spin.value = DEFAULT_MAX_PARAMS
	max_nesting_spin.value = DEFAULT_MAX_NESTING
	god_class_funcs_spin.value = DEFAULT_GOD_CLASS_FUNCS
	god_class_signals_spin.value = DEFAULT_GOD_CLASS_SIGNALS


# Create Claude Code settings card
# qube:ignore-next-line - UI card creation requires many style and layout calls
func _create_claude_code_card() -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.17, 0.22, 0.9)
	style.border_color = Color(0.3, 0.35, 0.45, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	# Header
	var header := Label.new()
	header.text = "Claude Code Integration"
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	vbox.add_child(header)

	# Enable checkbox
	claude_enabled_check = CheckBox.new()
	claude_enabled_check.text = "Enable Claude Code buttons"
	claude_enabled_check.button_pressed = claude_code_enabled
	claude_enabled_check.toggled.connect(_on_claude_enabled_toggled)
	vbox.add_child(claude_enabled_check)

	# Description
	var desc := Label.new()
	desc.text = "Adds Claude Code button to launch directly into plan mode with issue context."
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color(0.5, 0.52, 0.55))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	# Command label
	var cmd_label := Label.new()
	cmd_label.text = "Launch Command:"
	cmd_label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.75))
	vbox.add_child(cmd_label)

	# Command input with reset button
	var cmd_hbox := HBoxContainer.new()
	cmd_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(cmd_hbox)

	claude_command_edit = LineEdit.new()
	claude_command_edit.text = claude_code_command
	claude_command_edit.placeholder_text = CLAUDE_CODE_DEFAULT_COMMAND
	claude_command_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	claude_command_edit.text_changed.connect(_on_claude_command_changed)
	cmd_hbox.add_child(claude_command_edit)

	claude_reset_button = Button.new()
	claude_reset_button.icon = _reset_icon
	claude_reset_button.tooltip_text = "Reset to default"
	claude_reset_button.flat = true
	claude_reset_button.custom_minimum_size = Vector2(16, 16)
	claude_reset_button.pressed.connect(_on_claude_reset_pressed)
	cmd_hbox.add_child(claude_reset_button)

	# Hint label
	var hint := Label.new()
	hint.text = "Issue context is passed automatically. Add CLI flags as needed (e.g. --verbose)."
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.45, 0.47, 0.5))
	vbox.add_child(hint)

	# Custom instructions label
	var instructions_label := Label.new()
	instructions_label.text = "Custom Instructions (optional):"
	instructions_label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.75))
	vbox.add_child(instructions_label)

	# Custom instructions text area
	claude_instructions_edit = TextEdit.new()
	claude_instructions_edit.placeholder_text = "Add extra instructions to append to the prompt..."
	claude_instructions_edit.custom_minimum_size = Vector2(0, 60)
	claude_instructions_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	claude_instructions_edit.text_changed.connect(_on_claude_instructions_changed)
	vbox.add_child(claude_instructions_edit)

	return card
