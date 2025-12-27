@tool
extends Control
## Code Quality Dock - Displays analysis results with clickable navigation

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
	"god-class": "God Class"
}

# UI References
var results_label: RichTextLabel
var scan_button: Button
var export_button: Button
var severity_filter: OptionButton
var type_filter: OptionButton
var file_filter: LineEdit
var status_label: Label
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
var show_export_button: bool = true

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
	severity_filter = $VBox/Toolbar/SeverityFilter
	type_filter = $VBox/Toolbar/TypeFilter
	file_filter = $VBox/Toolbar/FileFilter
	status_label = $VBox/Toolbar/StatusLabel
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
	settings_panel.visible = false

	print("Code Quality: Plugin ready")


func _populate_type_filter() -> void:
	type_filter.clear()
	var idx := 0
	for check_id in ISSUE_TYPES:
		type_filter.add_item(ISSUE_TYPES[check_id], idx)
		type_filter.set_item_metadata(idx, check_id)
		idx += 1


func _load_settings() -> void:
	# Load display settings
	show_issues_check.button_pressed = show_total_issues
	show_debt_check.button_pressed = show_debt
	show_export_check.button_pressed = show_export_button
	export_button.visible = show_export_button

	# Load config values into spinboxes
	max_lines_soft_spin.value = current_config.line_limit_soft
	max_lines_hard_spin.value = current_config.line_limit_hard
	max_func_lines_spin.value = current_config.function_line_limit
	max_complexity_spin.value = current_config.cyclomatic_warning


func _on_scan_pressed() -> void:
	print("Code Quality: Scan button pressed")
	scan_button.disabled = true
	export_button.disabled = true
	status_label.text = "Scanning..."
	results_label.text = "[color=#888888]Analyzing codebase...[/color]"

	# Use call_deferred to allow UI to update
	call_deferred("_run_analysis")


func _run_analysis() -> void:
	print("Code Quality: Starting analysis...")

	var analyzer = CodeAnalyzerScript.new(current_config)
	current_result = analyzer.analyze_directory("res://")

	print("Code Quality: Analysis complete - %d issues found" % current_result.issues.size())

	_display_results()
	_update_status()

	scan_button.disabled = false
	export_button.disabled = false


func _update_status() -> void:
	if not current_result:
		status_label.text = "Ready"
		return

	var parts: Array[String] = []
	if show_total_issues:
		parts.append("Issues: %d" % current_result.issues.size())
	if show_debt:
		parts.append("Debt: %d" % current_result.get_total_debt_score())

	status_label.text = " | ".join(parts) if parts.size() > 0 else "Ready"


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
		status_label.text = "Exported to code_quality_report.json"

		# Open the file in the editor
		var script = load(export_path)
		if script:
			EditorInterface.edit_resource(script)
	else:
		push_error("Code Quality: Failed to write export file")
		status_label.text = "Export failed!"


func _on_severity_filter_changed(index: int) -> void:
	match index:
		0: current_severity_filter = "all"
		1: current_severity_filter = "critical"
		2: current_severity_filter = "warning"
		3: current_severity_filter = "info"

	if current_result:
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
	_update_status()


func _on_show_debt_toggled(pressed: bool) -> void:
	show_debt = pressed
	_update_status()


func _on_show_export_toggled(pressed: bool) -> void:
	show_export_button = pressed
	export_button.visible = pressed


func _on_max_lines_soft_changed(value: float) -> void:
	current_config.line_limit_soft = int(value)


func _on_max_lines_hard_changed(value: float) -> void:
	current_config.line_limit_hard = int(value)


func _on_max_func_lines_changed(value: float) -> void:
	current_config.function_line_limit = int(value)


func _on_max_complexity_changed(value: float) -> void:
	current_config.cyclomatic_warning = int(value)


func _display_results() -> void:
	if not current_result:
		return

	var bbcode := "[b]Code Quality Report[/b]\n"
	bbcode += "Files: %d | Lines: %d | Time: %dms\n\n" % [
		current_result.files_analyzed,
		current_result.total_lines,
		current_result.analysis_time_ms
	]

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
		bbcode += "[color=#ff6b6b][b]CRITICAL (%d)[/b][/color]\n" % critical.size()
		for issue in critical.slice(0, ISSUES_PER_CATEGORY):
			bbcode += _format_issue(issue, "#ff6b6b")
		if critical.size() > ISSUES_PER_CATEGORY:
			bbcode += "[color=#888888]  ... and %d more (use filters or export JSON)[/color]\n" % (critical.size() - ISSUES_PER_CATEGORY)
		bbcode += "\n"

	if warnings.size() > 0:
		bbcode += "[color=#ffd93d][b]WARNINGS (%d)[/b][/color]\n" % warnings.size()
		for issue in warnings.slice(0, ISSUES_PER_CATEGORY):
			bbcode += _format_issue(issue, "#ffd93d")
		if warnings.size() > ISSUES_PER_CATEGORY:
			bbcode += "[color=#888888]  ... and %d more (use filters or export JSON)[/color]\n" % (warnings.size() - ISSUES_PER_CATEGORY)
		bbcode += "\n"

	if info.size() > 0:
		bbcode += "[color=#6bcb77][b]INFO (%d)[/b][/color]\n" % info.size()
		for issue in info.slice(0, ISSUES_PER_CATEGORY):
			bbcode += _format_issue(issue, "#6bcb77")
		if info.size() > ISSUES_PER_CATEGORY:
			bbcode += "[color=#888888]  ... and %d more (use filters or export JSON)[/color]\n" % (info.size() - ISSUES_PER_CATEGORY)

	if issues_to_show.size() == 0:
		bbcode += "[color=#888888]No issues matching current filters[/color]"

	results_label.text = bbcode


func _format_issue(issue, color: String) -> String:
	var icon: String = issue.get_severity_icon()
	var short_path: String = issue.file_path.get_file()
	var link := "%s:%d" % [issue.file_path, issue.line]

	return "%s [url=%s][color=%s]%s:%d[/color][/url] %s\n" % [
		icon, link, color, short_path, issue.line, issue.message
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
