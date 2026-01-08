# Godot Qube - Code quality analyzer for GDScript  # qube:ignore:file-length
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

# Preload scripts
var CodeAnalyzerScript = preload("res://addons/godot-qube/analyzer/code-analyzer.gd")
var AnalysisConfigScript = preload("res://addons/godot-qube/analyzer/analysis-config.gd")
var IssueScript = preload("res://addons/godot-qube/analyzer/issue.gd")
var SettingsCardBuilderScript = preload("res://addons/godot-qube/ui/settings-card-builder.gd")
var SettingsManagerScript = preload("res://addons/godot-qube/ui/settings-manager.gd")

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

# State
var current_result  # AnalysisResult instance
var current_severity_filter: String = "all"
var current_type_filter: String = "all"
var current_file_filter: String = ""

# Current config instance for settings
var current_config: Resource

# Settings manager and controls
var settings_manager: RefCounted
var settings_controls: Dictionary = {}


func _ready() -> void:
	_init_node_references()
	if not _validate_required_nodes():
		return
	_setup_background()
	_init_config_and_settings_panel()
	_init_settings_manager()
	_connect_signals()
	_setup_filters()
	_apply_initial_visibility()


func _init_node_references() -> void:
	results_label = $VBox/ScrollContainer/ResultsLabel
	scan_button = $VBox/Toolbar/ScanButton
	export_button = $VBox/Toolbar/ExportButton
	html_export_button = $VBox/Toolbar/HTMLExportButton
	severity_filter = $VBox/Toolbar/SeverityFilter
	type_filter = $VBox/Toolbar/TypeFilter
	file_filter = $VBox/Toolbar/FileFilter
	settings_button = $VBox/Toolbar/SettingsButton
	settings_panel = $VBox/SettingsPanel


func _validate_required_nodes() -> bool:
	if not results_label or not scan_button or not severity_filter:
		push_error("Code Quality: Failed to find UI nodes")
		return false
	return true


func _setup_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.14, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	move_child(bg, 0)


func _init_config_and_settings_panel() -> void:
	current_config = AnalysisConfigScript.new()
	var reset_icon = load("res://addons/godot-qube/icons/arrow-reset.svg")
	var card_builder = SettingsCardBuilderScript.new(reset_icon)
	card_builder.build_settings_panel(settings_panel, settings_controls)


func _init_settings_manager() -> void:
	settings_manager = SettingsManagerScript.new(current_config)
	settings_manager.controls = settings_controls
	settings_manager.display_refresh_needed.connect(_on_display_refresh_needed)
	settings_manager.load_settings()
	settings_manager.connect_controls(export_button, html_export_button)


func _connect_signals() -> void:
	results_label.meta_underlined = false
	results_label.meta_clicked.connect(_on_link_clicked)
	scan_button.pressed.connect(_on_scan_pressed)
	export_button.pressed.connect(_on_export_pressed)
	html_export_button.pressed.connect(_on_html_export_pressed)
	severity_filter.item_selected.connect(_on_severity_filter_changed)
	type_filter.item_selected.connect(_on_type_filter_changed)
	file_filter.text_changed.connect(_on_file_filter_changed)
	settings_button.pressed.connect(_on_settings_pressed)


func _setup_filters() -> void:
	severity_filter.clear()
	severity_filter.add_item("All Severities", 0)
	severity_filter.add_item("Critical", 1)
	severity_filter.add_item("Warnings", 2)
	severity_filter.add_item("Info", 3)
	_populate_type_filter()


func _apply_initial_visibility() -> void:
	export_button.visible = settings_manager.show_json_export
	html_export_button.visible = settings_manager.show_html_export
	export_button.disabled = true
	settings_panel.visible = false


func _on_display_refresh_needed() -> void:
	if current_result:
		_display_results()


func _populate_type_filter(sev_filter: String = "all") -> void:
	type_filter.clear()
	var idx := 0

	type_filter.add_item("All Types", idx)
	type_filter.set_item_metadata(idx, "all")
	idx += 1

	var available_types := _get_available_types_for_severity(sev_filter)

	for check_id in ISSUE_TYPES:
		if check_id == "all":
			continue
		if sev_filter == "all" or check_id in available_types:
			type_filter.add_item(ISSUE_TYPES[check_id], idx)
			type_filter.set_item_metadata(idx, check_id)
			idx += 1


func _get_available_types_for_severity(sev_filter: String) -> Dictionary:
	var available: Dictionary = {}
	if not current_result:
		return available

	var Issue = IssueScript
	for issue in current_result.issues:
		var matches_severity := false
		match sev_filter:
			"all": matches_severity = true
			"critical": matches_severity = issue.severity == Issue.Severity.CRITICAL
			"warning": matches_severity = issue.severity == Issue.Severity.WARNING
			"info": matches_severity = issue.severity == Issue.Severity.INFO

		if matches_severity:
			available[issue.check_id] = true

	return available


func _on_scan_pressed() -> void:
	settings_panel.visible = false
	$VBox/ScrollContainer.visible = true

	scan_button.disabled = true
	export_button.disabled = true
	html_export_button.disabled = true
	results_label.text = "[color=#888888]Analyzing codebase...[/color]"

	call_deferred("_run_analysis")


func _run_analysis() -> void:
	var analyzer = CodeAnalyzerScript.new(current_config)
	current_result = analyzer.analyze_directory("res://")

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
		var script = load(export_path)
		if script:
			EditorInterface.edit_resource(script)
	else:
		push_error("Code Quality: Failed to write export file")
		OS.alert("Failed to write JSON export file:\n%s" % export_path, "Export Error")


func _on_html_export_pressed() -> void:
	if not current_result:
		var AnalysisResultScript = preload("res://addons/godot-qube/analyzer/analysis-result.gd")
		current_result = AnalysisResultScript.new()

	var HtmlReportGenerator = preload("res://addons/godot-qube/analyzer/html-report-generator.gd")
	var html := HtmlReportGenerator.generate(current_result)
	var export_path := "res://code_quality_report.html"

	var file := FileAccess.open(export_path, FileAccess.WRITE)
	if file:
		file.store_string(html)
		file.close()
		OS.shell_open(ProjectSettings.globalize_path(export_path))
	else:
		push_error("Code Quality: Failed to write HTML report")
		OS.alert("Failed to write HTML export file:\n%s" % export_path, "Export Error")


func _on_severity_filter_changed(index: int) -> void:
	match index:
		0: current_severity_filter = "all"
		1: current_severity_filter = "critical"
		2: current_severity_filter = "warning"
		3: current_severity_filter = "info"

	if current_result:
		var prev_type := current_type_filter
		_populate_type_filter(current_severity_filter)

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
	$VBox/ScrollContainer.visible = not settings_panel.visible


func _display_results() -> void:
	if not current_result:
		return

	var bbcode := "[b]Code Quality Report[/b]\n"
	bbcode += "Files: %d | Lines: %d | Time: %dms\n" % [
		current_result.files_analyzed,
		current_result.total_lines,
		current_result.analysis_time_ms
	]

	var summary_parts: Array[String] = []
	if settings_manager.show_total_issues:
		summary_parts.append("Issues: %d" % current_result.issues.size())
	if settings_manager.show_debt:
		summary_parts.append("Debt: %d" % current_result.get_total_debt_score())
	if summary_parts.size() > 0:
		bbcode += " | ".join(summary_parts) + "\n"
	bbcode += "\n"

	var issues_to_show: Array = current_result.issues.duplicate()
	var Issue = IssueScript

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
			Issue.Severity.CRITICAL: critical.append(issue)
			Issue.Severity.WARNING: warnings.append(issue)
			Issue.Severity.INFO: info.append(issue)

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

	# Display ignored issues section
	if settings_manager.show_ignored_issues:
		bbcode += _format_ignored_section()

	results_label.text = bbcode


func _format_issues_by_type(issues: Array, color: String) -> String:
	var bbcode := ""

	var by_type: Dictionary = {}
	for issue in issues:
		var check_id: String = issue.check_id
		if not by_type.has(check_id):
			by_type[check_id] = []
		by_type[check_id].append(issue)

	var type_keys := by_type.keys()
	type_keys.sort_custom(func(a, b): return by_type[a].size() > by_type[b].size())

	var is_first_type := true
	for check_id in type_keys:
		var type_issues: Array = by_type[check_id]
		var type_name: String = ISSUE_TYPES.get(check_id, check_id)

		if not is_first_type:
			bbcode += "\n"
		is_first_type = false

		bbcode += "  [color=#aaaaaa]── %s (%d) ──[/color]\n" % [type_name, type_issues.size()]

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
	if settings_manager.claude_code_enabled:
		var severity_str: String = "unknown"
		var Issue = IssueScript
		match issue.severity:
			Issue.Severity.CRITICAL: severity_str = "critical"
			Issue.Severity.WARNING: severity_str = "warning"
			Issue.Severity.INFO: severity_str = "info"

		var claude_data := "%s|%d|%s|%s|%s" % [
			issue.file_path, issue.line, issue.check_id, severity_str,
			issue.message.replace("|", "-")
		]
		line += " [url=claude://%s][img=20x20]res://addons/godot-qube/icons/claude.png[/img][/url]" % claude_data.uri_encode()

	return line + "\n"


func _format_ignored_section() -> String:
	if not current_result or current_result.ignored_issues.size() == 0:
		return ""

	var Issue = IssueScript
	var ignored: Array = current_result.ignored_issues.duplicate()

	# Filter by severity (same logic as main issues)
	if current_severity_filter != "all":
		var filtered: Array = []
		for issue in ignored:
			match current_severity_filter:
				"critical":
					if issue.severity == Issue.Severity.CRITICAL:
						filtered.append(issue)
				"warning":
					if issue.severity == Issue.Severity.WARNING:
						filtered.append(issue)
				"info":
					if issue.severity == Issue.Severity.INFO:
						filtered.append(issue)
		ignored = filtered

	# Filter by file
	if current_file_filter != "":
		var filtered: Array = []
		for issue in ignored:
			if current_file_filter in issue.file_path.to_lower():
				filtered.append(issue)
		ignored = filtered

	if ignored.size() == 0:
		return ""

	# Group by type
	var by_type: Dictionary = {}
	for issue in ignored:
		var check_id: String = issue.check_id
		if not by_type.has(check_id):
			by_type[check_id] = []
		by_type[check_id].append(issue)

	var bbcode := "\n[color=#666666][b]── Ignored (%d) ──[/b][/color]\n" % ignored.size()

	# Sort by count descending
	var type_keys := by_type.keys()
	type_keys.sort_custom(func(a, b): return by_type[a].size() > by_type[b].size())

	for check_id in type_keys:
		var type_issues: Array = by_type[check_id]
		var type_name: String = ISSUE_TYPES.get(check_id, check_id)

		# Show type with all references on one line (or multiple if many)
		if type_issues.size() <= 3:
			var refs: Array[String] = []
			for issue in type_issues:
				var short_path: String = issue.file_path.get_file()
				var link := "%s:%d" % [issue.file_path, issue.line]
				refs.append("[url=%s]%s:%d[/url]" % [link, short_path, issue.line])
			bbcode += "  [color=#555555]%s: %s[/color]\n" % [type_name.to_lower(), ", ".join(refs)]
		else:
			bbcode += "  [color=#555555]%s (%d):[/color]\n" % [type_name.to_lower(), type_issues.size()]
			var shown := 0
			for issue in type_issues:
				if shown >= ISSUES_PER_CATEGORY:
					bbcode += "    [color=#444444]... and %d more[/color]\n" % (type_issues.size() - shown)
					break
				var short_path: String = issue.file_path.get_file()
				var link := "%s:%d" % [issue.file_path, issue.line]
				bbcode += "    [url=%s][color=#555555]%s:%d[/color][/url] %s\n" % [
					link, short_path, issue.line, issue.message
				]
				shown += 1

	return bbcode


func _on_link_clicked(meta: Variant) -> void:
	var location := str(meta)

	# Handle Claude Code links
	if location.begins_with("claude://"):
		var encoded_data: String = location.substr(9)
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

	var parts := location.rsplit(":", true, 1)

	if parts.size() < 2:
		push_warning("Invalid link format: %s" % location)
		return

	var file_path: String = parts[0]
	var line_num := int(parts[1])

	var script = load(file_path)
	if script:
		EditorInterface.edit_script(script, line_num, 0)
		EditorInterface.set_main_screen_editor("Script")
	else:
		push_warning("Could not load script: %s" % file_path)


func _on_claude_button_pressed(issue: Dictionary) -> void:
	var project_path := ProjectSettings.globalize_path("res://")

	var prompt := "Code quality issue to fix:\n\n"
	prompt += "File: %s\n" % issue.file_path
	prompt += "Line: %d\n" % issue.line
	prompt += "Type: %s\n" % issue.check_id
	prompt += "Severity: %s\n" % issue.severity
	prompt += "Message: %s\n\n" % issue.message
	prompt += "Analyze this issue and suggest a fix."

	if not settings_manager.claude_custom_instructions.strip_edges().is_empty():
		prompt += "\n\n" + settings_manager.claude_custom_instructions

	var escaped_prompt := prompt.replace("'", "''")

	var args: PackedStringArray = [
		"-d", project_path,
		"powershell", "-NoProfile", "-NoExit",
		"-Command", "%s '%s'" % [settings_manager.claude_code_command, escaped_prompt]
	]
	OS.create_process("wt", args)
