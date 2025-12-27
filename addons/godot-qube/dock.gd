@tool
extends Control
## Godot Qube Dock - Displays analysis results with clickable navigation

const ISSUES_PER_CATEGORY := 100

var results_label: RichTextLabel
var scan_button: Button
var export_button: Button
var filter_option: OptionButton
var file_filter: LineEdit
var status_label: Label

var current_result  # AnalysisResult instance
var current_filter: String = "all"
var current_file_filter: String = ""

# Preload the analyzer scripts
var CodeAnalyzerScript = preload("res://addons/godot-qube/analyzer/code-analyzer.gd")
var AnalysisConfigScript = preload("res://addons/godot-qube/analyzer/analysis-config.gd")
var IssueScript = preload("res://addons/godot-qube/analyzer/issue.gd")


func _ready() -> void:
	# Get node references
	results_label = $VBox/ScrollContainer/ResultsLabel
	scan_button = $VBox/Toolbar/ScanButton
	export_button = $VBox/Toolbar/ExportButton
	filter_option = $VBox/Toolbar/FilterOption
	file_filter = $VBox/Toolbar/FileFilter
	status_label = $VBox/Toolbar/StatusLabel

	if not results_label or not scan_button or not filter_option:
		push_error("Godot Qube: Failed to find UI nodes")
		return

	# Connect signals
	results_label.meta_clicked.connect(_on_link_clicked)
	scan_button.pressed.connect(_on_scan_pressed)
	export_button.pressed.connect(_on_export_pressed)
	filter_option.item_selected.connect(_on_filter_changed)
	file_filter.text_changed.connect(_on_file_filter_changed)

	# Setup filter options
	filter_option.clear()
	filter_option.add_item("All", 0)
	filter_option.add_item("Critical", 1)
	filter_option.add_item("Warnings", 2)
	filter_option.add_item("Info", 3)

	export_button.disabled = true

	print("Godot Qube: Plugin ready")


func _on_scan_pressed() -> void:
	print("Godot Qube: Scan button pressed")
	scan_button.disabled = true
	export_button.disabled = true
	status_label.text = "Scanning..."
	results_label.text = "[color=#888888]Analyzing codebase...[/color]"

	# Use call_deferred to allow UI to update
	call_deferred("_run_analysis")


func _run_analysis() -> void:
	print("Godot Qube: Starting analysis...")

	var config = AnalysisConfigScript.new()
	var analyzer = CodeAnalyzerScript.new(config)

	current_result = analyzer.analyze_directory("res://")

	print("Godot Qube: Analysis complete - %d issues found" % current_result.issues.size())

	_display_results()

	scan_button.disabled = false
	export_button.disabled = false
	status_label.text = "Issues: %d | Debt: %d" % [current_result.issues.size(), current_result.get_total_debt_score()]


func _on_export_pressed() -> void:
	if not current_result:
		return

	var json_str := JSON.stringify(current_result.to_dict(), "\t")
	var export_path := "res://code_quality_report.json"

	var file := FileAccess.open(export_path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()
		print("Godot Qube: Exported to %s" % export_path)
		status_label.text = "Exported to code_quality_report.json"

		# Open the file in the editor
		var script = load(export_path)
		if script:
			EditorInterface.edit_resource(script)
	else:
		push_error("Godot Qube: Failed to write export file")
		status_label.text = "Export failed!"


func _on_filter_changed(index: int) -> void:
	match index:
		0: current_filter = "all"
		1: current_filter = "critical"
		2: current_filter = "warning"
		3: current_filter = "info"

	if current_result:
		_display_results()


func _on_file_filter_changed(new_text: String) -> void:
	current_file_filter = new_text.to_lower()
	if current_result:
		_display_results()


func _display_results() -> void:
	if not current_result:
		return

	var bbcode := "[b]Godot Qube - Code Quality Report[/b]\n"
	bbcode += "Files: %d | Lines: %d | Time: %dms\n\n" % [
		current_result.files_analyzed,
		current_result.total_lines,
		current_result.analysis_time_ms
	]

	var issues_to_show: Array = []
	var Issue = IssueScript  # Reference for severity enum

	# First filter by severity
	match current_filter:
		"critical":
			issues_to_show = current_result.get_issues_by_severity(Issue.Severity.CRITICAL)
		"warning":
			issues_to_show = current_result.get_issues_by_severity(Issue.Severity.WARNING)
		"info":
			issues_to_show = current_result.get_issues_by_severity(Issue.Severity.INFO)
		_:
			issues_to_show = current_result.issues.duplicate()

	# Then filter by filename if specified
	if current_file_filter != "":
		var filtered: Array = []
		for issue in issues_to_show:
			if current_file_filter in issue.file_path.to_lower():
				filtered.append(issue)
		issues_to_show = filtered
		bbcode += "[color=#888888]Filtered by: \"%s\" (%d matches)[/color]\n\n" % [current_file_filter, issues_to_show.size()]

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
			bbcode += "[color=#888888]  ... and %d more (use filename filter or export JSON)[/color]\n" % (critical.size() - ISSUES_PER_CATEGORY)
		bbcode += "\n"

	if warnings.size() > 0:
		bbcode += "[color=#ffd93d][b]WARNINGS (%d)[/b][/color]\n" % warnings.size()
		for issue in warnings.slice(0, ISSUES_PER_CATEGORY):
			bbcode += _format_issue(issue, "#ffd93d")
		if warnings.size() > ISSUES_PER_CATEGORY:
			bbcode += "[color=#888888]  ... and %d more (use filename filter or export JSON)[/color]\n" % (warnings.size() - ISSUES_PER_CATEGORY)
		bbcode += "\n"

	if info.size() > 0:
		bbcode += "[color=#6bcb77][b]INFO (%d)[/b][/color]\n" % info.size()
		for issue in info.slice(0, ISSUES_PER_CATEGORY):
			bbcode += _format_issue(issue, "#6bcb77")
		if info.size() > ISSUES_PER_CATEGORY:
			bbcode += "[color=#888888]  ... and %d more (use filename filter or export JSON)[/color]\n" % (info.size() - ISSUES_PER_CATEGORY)

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
	print("Godot Qube: Link clicked - %s" % location)

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
