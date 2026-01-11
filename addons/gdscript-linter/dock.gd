# gdlint:ignore-file:file-length
# GDScript Linter - Static code quality analyzer
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
var CodeAnalyzerScript = preload("res://addons/gdscript-linter/analyzer/code-analyzer.gd")
var AnalysisConfigScript = preload("res://addons/gdscript-linter/analyzer/analysis-config.gd")
var IssueScript = preload("res://addons/gdscript-linter/analyzer/issue.gd")
var SettingsCardBuilderScript = preload("res://addons/gdscript-linter/ui/settings-card-builder.gd")
var SettingsManagerScript = preload("res://addons/gdscript-linter/ui/settings-manager.gd")

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

# Claude button interaction state
var _hovered_claude_link: String = ""
var _claude_context_menu: PopupMenu
var _claude_tooltip: PanelContainer
var _grouped_issues_by_type: Dictionary = {}  # check_id -> Array of issues
var _grouped_issues_by_severity: Dictionary = {}  # severity -> Array of issues

# Claude customize dialog
var _claude_customize_popup: PanelContainer
var _claude_customize_context: RichTextLabel  # Shows issue(s) being sent
var _claude_customize_command: LineEdit
var _claude_customize_instructions: TextEdit
var _claude_customize_pending_link: String = ""  # Store link while dialog is open
var _claude_context_menu_link: String = ""  # Store link when context menu opens

# Current config instance for settings
var current_config: Resource

# Settings manager and controls
var settings_manager: RefCounted
var settings_controls: Dictionary = {}

# Busy overlay
var _busy_overlay: Control
var _busy_spinner: Label
var _busy_animation_timer: Timer
var _spinner_frames := ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
var _spinner_frame_index: int = 0

# Export config file dialog
var _export_config_dialog: EditorFileDialog


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
	_setup_busy_overlay()


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

	# Add internal content padding to results label
	var results_style := StyleBoxFlat.new()
	results_style.bg_color = Color(0, 0, 0, 0)  # Transparent background
	results_style.set_content_margin_all(10)
	results_label.add_theme_stylebox_override("normal", results_style)

	# Style toolbar buttons to match Godot theme
	_style_toolbar_buttons()


func _validate_required_nodes() -> bool:
	if not results_label or not scan_button or not severity_filter:
		push_error("Code Quality: Failed to find UI nodes")
		return false
	return true


func _setup_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.212, 0.239, 0.290, 1.0)  # #363D4A
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	move_child(bg, 0)


func _style_toolbar_buttons() -> void:
	# Create button style - #252B34
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.145, 0.169, 0.204, 1.0)  # #252B34
	btn_style.set_corner_radius_all(4)
	btn_style.set_content_margin_all(6)

	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = Color(0.18, 0.21, 0.25, 1.0)  # Lighter hover
	btn_hover.set_corner_radius_all(4)
	btn_hover.set_content_margin_all(6)

	var btn_pressed := StyleBoxFlat.new()
	btn_pressed.bg_color = Color(0.11, 0.13, 0.16, 1.0)  # Darker pressed
	btn_pressed.set_corner_radius_all(4)
	btn_pressed.set_content_margin_all(6)

	for btn in [scan_button, html_export_button, export_button]:
		if btn:
			btn.add_theme_stylebox_override("normal", btn_style)
			btn.add_theme_stylebox_override("hover", btn_hover)
			btn.add_theme_stylebox_override("pressed", btn_pressed)


func _init_config_and_settings_panel() -> void:
	current_config = AnalysisConfigScript.new()
	var reset_icon = load("res://addons/gdscript-linter/icons/arrow-reset.svg")
	var card_builder = SettingsCardBuilderScript.new(reset_icon)
	card_builder.build_settings_panel(settings_panel, settings_controls)


func _init_settings_manager() -> void:
	settings_manager = SettingsManagerScript.new(current_config)
	settings_manager.controls = settings_controls
	settings_manager.display_refresh_needed.connect(_on_display_refresh_needed)
	settings_manager.setting_changed.connect(_on_setting_changed)
	settings_manager.export_config_requested.connect(_on_export_config_requested)
	settings_manager.load_settings()
	settings_manager.connect_controls(export_button, html_export_button)
	_setup_export_config_dialog()


func _connect_signals() -> void:
	results_label.meta_underlined = false
	results_label.meta_clicked.connect(_on_link_clicked)
	results_label.meta_hover_started.connect(_on_meta_hover_started)
	results_label.meta_hover_ended.connect(_on_meta_hover_ended)
	results_label.gui_input.connect(_on_results_gui_input)
	scan_button.pressed.connect(_on_scan_pressed)
	export_button.pressed.connect(_on_export_pressed)
	html_export_button.pressed.connect(_on_html_export_pressed)
	severity_filter.item_selected.connect(_on_severity_filter_changed)
	type_filter.item_selected.connect(_on_type_filter_changed)
	file_filter.text_changed.connect(_on_file_filter_changed)
	settings_button.pressed.connect(_on_settings_pressed)
	_setup_claude_context_menu()
	_setup_claude_tooltip()
	_setup_claude_customize_popup()


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
	_restore_saved_filters()


# Restores filter selections from settings if Remember Filters is enabled
func _restore_saved_filters() -> void:
	if not settings_manager.remember_filter_selections:
		return

	# Restore severity filter
	var saved_severity: int = settings_manager.saved_severity_filter
	if saved_severity >= 0 and saved_severity < severity_filter.item_count:
		severity_filter.select(saved_severity)
		match saved_severity:
			0: current_severity_filter = "all"
			1: current_severity_filter = "critical"
			2: current_severity_filter = "warning"
			3: current_severity_filter = "info"

	# Restore file filter text
	file_filter.text = settings_manager.saved_file_filter
	current_file_filter = settings_manager.saved_file_filter.to_lower()

	# Note: Type filter is restored after first scan since it depends on results
	# We store the saved type and apply it in _display_results if valid


func _setup_busy_overlay() -> void:
	# Create overlay container that covers the entire plugin
	_busy_overlay = Control.new()
	_busy_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_busy_overlay.mouse_filter = Control.MOUSE_FILTER_STOP  # Block all mouse input
	_busy_overlay.visible = false
	_busy_overlay.z_index = 50
	add_child(_busy_overlay)

	# Semi-transparent dark background
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.1, 0.12, 0.15, 0.85)
	_busy_overlay.add_child(bg)

	# Center container for spinner and text
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_busy_overlay.add_child(center)

	# Panel for the loading indicator
	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.17, 0.21, 0.95)
	panel_style.set_corner_radius_all(8)
	panel_style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	# VBox for spinner and label
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	# Spinner label (animated braille dots)
	_busy_spinner = Label.new()
	_busy_spinner.text = _spinner_frames[0]
	_busy_spinner.add_theme_font_size_override("font_size", 48)
	_busy_spinner.add_theme_color_override("font_color", Color(0.4, 0.6, 0.9))
	_busy_spinner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_busy_spinner)

	# "Scanning..." label
	var label := Label.new()
	label.text = "Scanning codebase..."
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)

	# Animation timer
	_busy_animation_timer = Timer.new()
	_busy_animation_timer.wait_time = 0.08
	_busy_animation_timer.timeout.connect(_on_busy_animation_tick)
	add_child(_busy_animation_timer)


func _on_busy_animation_tick() -> void:
	_spinner_frame_index = (_spinner_frame_index + 1) % _spinner_frames.size()
	_busy_spinner.text = _spinner_frames[_spinner_frame_index]


func _setup_export_config_dialog() -> void:
	_export_config_dialog = EditorFileDialog.new()
	_export_config_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_export_config_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_export_config_dialog.title = "Export GDLint Config"
	_export_config_dialog.add_filter("*.json", "JSON Config Files")
	_export_config_dialog.current_file = "gdlint-custom.json"
	_export_config_dialog.file_selected.connect(_on_export_config_file_selected)
	add_child(_export_config_dialog)


func _on_export_config_requested() -> void:
	_export_config_dialog.popup_centered(Vector2i(600, 400))


func _on_export_config_file_selected(file_path: String) -> void:
	if settings_manager.export_config_to_path(file_path):
		print("GDLint: Config exported to %s" % file_path)
	else:
		push_error("GDLint: Failed to export config to %s" % file_path)


func _show_busy_overlay() -> void:
	_spinner_frame_index = 0
	_busy_spinner.text = _spinner_frames[0]
	_busy_overlay.visible = true
	_busy_animation_timer.start()


func _hide_busy_overlay() -> void:
	_busy_overlay.visible = false
	_busy_animation_timer.stop()


func _on_display_refresh_needed() -> void:
	if current_result:
		_display_results()


# Track if checks changed while settings panel was open
var _checks_changed_while_settings_open: bool = false

# Called when any setting changes - just track that checks changed, don't re-scan
func _on_setting_changed(key: String, _value: Variant) -> void:
	if key.begins_with("check_") or key == "all_checks":
		_checks_changed_while_settings_open = true


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

	# Show busy overlay and wait for it to render before blocking
	_show_busy_overlay()
	_start_analysis_after_render()


func _start_analysis_after_render() -> void:
	# Wait for 2 frames to ensure overlay is fully rendered and animating
	await get_tree().process_frame
	await get_tree().process_frame
	_run_analysis()


func _run_analysis() -> void:
	var analyzer = CodeAnalyzerScript.new(current_config)
	current_result = analyzer.analyze_directory("res://")

	# Restore saved type filter if Remember Filters is enabled
	_restore_saved_type_filter()

	_display_results()

	scan_button.disabled = false
	export_button.disabled = false
	html_export_button.disabled = false

	# Hide busy overlay when done
	_hide_busy_overlay()


# Restores the saved type filter selection after results are loaded
func _restore_saved_type_filter() -> void:
	if not settings_manager.remember_filter_selections:
		return

	var saved_type: String = settings_manager.saved_type_filter
	if saved_type == "all" or saved_type.is_empty():
		return

	# Repopulate type filter based on current severity filter
	_populate_type_filter(current_severity_filter)

	# Find and select the saved type
	for i in range(type_filter.item_count):
		if type_filter.get_item_metadata(i) == saved_type:
			type_filter.select(i)
			current_type_filter = saved_type
			return

	# If saved type not found (no matching issues), keep "All Types"
	type_filter.select(0)
	current_type_filter = "all"


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
		var AnalysisResultScript = preload("res://addons/gdscript-linter/analyzer/analysis-result.gd")
		current_result = AnalysisResultScript.new()

	var HtmlReportGenerator = preload("res://addons/gdscript-linter/analyzer/html-report-generator.gd")
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

	_save_filter_selections()


func _on_type_filter_changed(index: int) -> void:
	current_type_filter = type_filter.get_item_metadata(index)
	if current_result:
		_display_results()
	_save_filter_selections()


func _on_file_filter_changed(new_text: String) -> void:
	current_file_filter = new_text.to_lower()
	if current_result:
		_display_results()
	_save_filter_selections()


# Saves current filter selections if Remember Filters is enabled
func _save_filter_selections() -> void:
	if settings_manager:
		settings_manager.save_filter_selections(
			severity_filter.selected,
			current_type_filter,
			file_filter.text
		)


func _on_settings_pressed() -> void:
	var was_visible := settings_panel.visible
	settings_panel.visible = not settings_panel.visible
	$VBox/ScrollContainer.visible = not settings_panel.visible

	# If closing settings and checks changed, re-run analysis
	if was_visible and _checks_changed_while_settings_open:
		_checks_changed_while_settings_open = false
		_show_busy_overlay()
		_start_analysis_after_render()


func _setup_claude_context_menu() -> void:
	_claude_context_menu = PopupMenu.new()
	_claude_context_menu.add_item("Plan Fix (default)", 0)
	_claude_context_menu.add_item("Fix Immediately", 1)
	_claude_context_menu.add_separator()
	_claude_context_menu.add_item("Customize...", 2)
	_claude_context_menu.id_pressed.connect(_on_claude_context_menu_selected)
	add_child(_claude_context_menu)


func _setup_claude_tooltip() -> void:
	var label := Label.new()
	label.text = "Click: Plan mode | Shift+Click: Fix now | Right-click: Options"
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))

	_claude_tooltip = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.13, 0.16, 0.95)  # Darker than #252B34
	style.border_color = Color(0.3, 0.3, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	_claude_tooltip.add_theme_stylebox_override("panel", style)
	_claude_tooltip.add_child(label)
	_claude_tooltip.visible = false
	_claude_tooltip.z_index = 100
	add_child(_claude_tooltip)


func _setup_claude_customize_popup() -> void:
	_claude_customize_popup = _create_popup_container()
	var vbox := _create_popup_vbox()
	_claude_customize_popup.add_child(vbox)

	_add_popup_title(vbox)
	_add_popup_context_section(vbox)
	_add_popup_command_section(vbox)
	_add_popup_instructions_section(vbox)
	_add_popup_buttons(vbox)

	add_child(_claude_customize_popup)


func _create_popup_container() -> PanelContainer:
	var popup := PanelContainer.new()
	popup.custom_minimum_size = Vector2(550, 500)
	popup.visible = false
	popup.z_index = 200
	popup.top_level = true

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.13, 0.16, 0.98)  # Darker than #252B34
	style.border_color = Color(0.3, 0.35, 0.45, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	popup.add_theme_stylebox_override("panel", style)
	return popup


func _create_popup_vbox() -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	return vbox


func _add_popup_title(vbox: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "Customize Claude Launch"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	vbox.add_child(sep)


func _create_section_label(label_text: String) -> Label:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	return label


func _add_popup_context_section(vbox: VBoxContainer) -> void:
	vbox.add_child(_create_section_label("Issue Context:"))

	_claude_customize_context = RichTextLabel.new()
	_claude_customize_context.bbcode_enabled = true
	_claude_customize_context.fit_content = false
	_claude_customize_context.scroll_active = true
	_claude_customize_context.custom_minimum_size = Vector2(0, 100)
	_claude_customize_context.add_theme_font_size_override("normal_font_size", 11)
	_claude_customize_context.add_theme_color_override("default_color", Color(0.7, 0.75, 0.8))

	var context_style := StyleBoxFlat.new()
	context_style.bg_color = Color(0.09, 0.11, 0.14, 1.0)  # Input area - darkest
	context_style.set_corner_radius_all(4)
	context_style.set_content_margin_all(8)
	_claude_customize_context.add_theme_stylebox_override("normal", context_style)
	vbox.add_child(_claude_customize_context)


func _add_popup_command_section(vbox: VBoxContainer) -> void:
	vbox.add_child(_create_section_label("Launch Command:"))

	_claude_customize_command = LineEdit.new()
	_claude_customize_command.placeholder_text = "claude --permission-mode plan"
	_claude_customize_command.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_claude_customize_command)


func _add_popup_instructions_section(vbox: VBoxContainer) -> void:
	vbox.add_child(_create_section_label("Custom Instructions:"))

	_claude_customize_instructions = TextEdit.new()
	_claude_customize_instructions.placeholder_text = "Additional instructions for Claude..."
	_claude_customize_instructions.add_theme_font_size_override("font_size", 12)
	_claude_customize_instructions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_claude_customize_instructions.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vbox.add_child(_claude_customize_instructions)


func _add_popup_buttons(vbox: VBoxContainer) -> void:
	var btn_container := HBoxContainer.new()
	btn_container.alignment = BoxContainer.ALIGNMENT_END
	btn_container.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_container)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(80, 32)
	cancel_btn.pressed.connect(_on_claude_customize_cancel)
	btn_container.add_child(cancel_btn)

	var launch_btn := Button.new()
	launch_btn.text = "Launch"
	launch_btn.custom_minimum_size = Vector2(80, 32)
	launch_btn.pressed.connect(_on_claude_customize_launch)
	btn_container.add_child(launch_btn)


func _show_claude_customize_popup() -> void:
	# Prepopulate from settings
	_claude_customize_command.text = settings_manager.claude_code_command
	_claude_customize_instructions.text = settings_manager.claude_custom_instructions

	# Build issue context display
	var context_text := ""

	if _claude_customize_pending_link.begins_with("claude://"):
		# Single issue
		var encoded_data: String = _claude_customize_pending_link.substr(9)
		var decoded_data: String = encoded_data.uri_decode()
		var parts := decoded_data.split("|")
		if parts.size() >= 5:
			context_text = "[b]Single Issue[/b]\n"
			context_text += "[color=#8899aa]File:[/color] %s\n" % parts[0]
			context_text += "[color=#8899aa]Line:[/color] %s\n" % parts[1]
			context_text += "[color=#8899aa]Type:[/color] %s\n" % parts[2]
			context_text += "[color=#8899aa]Severity:[/color] %s\n" % parts[3]
			context_text += "[color=#8899aa]Message:[/color] %s" % parts[4]

	elif _claude_customize_pending_link.begins_with("claude-type://"):
		# Batch by type
		var type_key: String = _claude_customize_pending_link.substr(14).uri_decode()
		if _grouped_issues_by_type.has(type_key):
			var issues: Array = _grouped_issues_by_type[type_key]
			context_text = "[b]Batch: %d issues of type '%s'[/b]\n\n" % [issues.size(), type_key]
			for i in range(mini(issues.size(), 5)):  # Show first 5
				var issue = issues[i]
				context_text += "[color=#6688aa]%d.[/color] %s:%d - %s\n" % [i + 1, issue.file_path, issue.line, issue.message]
			if issues.size() > 5:
				context_text += "[color=#666677]... and %d more[/color]" % (issues.size() - 5)

	elif _claude_customize_pending_link.begins_with("claude-severity://"):
		# Batch by severity
		var severity_key: String = _claude_customize_pending_link.substr(18)
		if _grouped_issues_by_severity.has(severity_key):
			var issues: Array = _grouped_issues_by_severity[severity_key]
			context_text = "[b]Batch: %d %s issues[/b]\n\n" % [issues.size(), severity_key]
			for i in range(mini(issues.size(), 5)):  # Show first 5
				var issue = issues[i]
				context_text += "[color=#6688aa]%d.[/color] %s:%d - %s\n" % [i + 1, issue.file_path, issue.line, issue.message]
			if issues.size() > 5:
				context_text += "[color=#666677]... and %d more[/color]" % (issues.size() - 5)

	_claude_customize_context.clear()
	_claude_customize_context.append_text(context_text)

	# Center on screen
	var screen_size := DisplayServer.screen_get_size()
	var popup_size := _claude_customize_popup.custom_minimum_size
	_claude_customize_popup.global_position = Vector2(
		(screen_size.x - popup_size.x) / 2,
		(screen_size.y - popup_size.y) / 2
	)
	_claude_customize_popup.visible = true


func _on_claude_customize_cancel() -> void:
	_claude_customize_popup.visible = false
	_claude_customize_pending_link = ""


func _on_claude_customize_launch() -> void:
	_claude_customize_popup.visible = false

	if _claude_customize_pending_link.is_empty():
		return

	var custom_command := _claude_customize_command.text.strip_edges()
	var custom_instructions := _claude_customize_instructions.text

	# Handle single issue links
	if _claude_customize_pending_link.begins_with("claude://"):
		var encoded_data: String = _claude_customize_pending_link.substr(9)
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
			_launch_claude_code_custom(issue_data, custom_command, custom_instructions)

	# Handle batch type-level links
	elif _claude_customize_pending_link.begins_with("claude-type://"):
		var type_key: String = _claude_customize_pending_link.substr(14).uri_decode()
		if _grouped_issues_by_type.has(type_key):
			_launch_claude_code_batch_custom(_grouped_issues_by_type[type_key], custom_command, custom_instructions)

	# Handle batch severity-level links
	elif _claude_customize_pending_link.begins_with("claude-severity://"):
		var severity_key: String = _claude_customize_pending_link.substr(18)
		if _grouped_issues_by_severity.has(severity_key):
			_launch_claude_code_batch_custom(_grouped_issues_by_severity[severity_key], custom_command, custom_instructions)

	_claude_customize_pending_link = ""


func _on_meta_hover_started(meta: Variant) -> void:
	var link := str(meta)
	if link.begins_with("claude://") or link.begins_with("claude-type://") or link.begins_with("claude-severity://"):
		_hovered_claude_link = link
		_show_claude_tooltip()


func _on_meta_hover_ended(_meta: Variant) -> void:
	_hovered_claude_link = ""
	_hide_claude_tooltip()


func _show_claude_tooltip() -> void:
	if not _claude_tooltip or not settings_manager.claude_code_enabled:
		return
	var mouse_pos := get_global_mouse_position()
	_claude_tooltip.global_position = mouse_pos + Vector2(15, -30)
	_claude_tooltip.visible = true


func _hide_claude_tooltip() -> void:
	if _claude_tooltip:
		_claude_tooltip.visible = false


func _on_results_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if _hovered_claude_link != "" and settings_manager.claude_code_enabled:
				_hide_claude_tooltip()
				_claude_context_menu_link = _hovered_claude_link  # Store before menu opens
				_claude_context_menu.position = DisplayServer.mouse_get_position() + Vector2i(16, -8)
				_claude_context_menu.popup()
				get_viewport().set_input_as_handled()


func _on_claude_context_menu_selected(id: int) -> void:
	if _claude_context_menu_link == "":
		return

	# Handle Customize option - show dialog instead of launching
	if id == 2:
		_claude_customize_pending_link = _claude_context_menu_link
		_show_claude_customize_popup()
		return

	var use_plan_mode := (id == 0)

	# Handle single issue links
	if _claude_context_menu_link.begins_with("claude://"):
		var encoded_data: String = _claude_context_menu_link.substr(9)
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
			_launch_claude_code(issue_data, use_plan_mode)
		return

	# Handle batch type-level links
	if _claude_context_menu_link.begins_with("claude-type://"):
		var type_key: String = _claude_context_menu_link.substr(14).uri_decode()
		if _grouped_issues_by_type.has(type_key):
			_launch_claude_code_batch(_grouped_issues_by_type[type_key], use_plan_mode)
		return

	# Handle batch severity-level links
	if _claude_context_menu_link.begins_with("claude-severity://"):
		var severity_key: String = _claude_context_menu_link.substr(18)
		if _grouped_issues_by_severity.has(severity_key):
			_launch_claude_code_batch(_grouped_issues_by_severity[severity_key], use_plan_mode)


func _matches_severity(issue) -> bool:
	if current_severity_filter == "all":
		return true
	var Issue = IssueScript
	match current_severity_filter:
		"critical": return issue.severity == Issue.Severity.CRITICAL
		"warning": return issue.severity == Issue.Severity.WARNING
		"info": return issue.severity == Issue.Severity.INFO
	return false


func _matches_type(issue) -> bool:
	return current_type_filter == "all" or issue.check_id == current_type_filter


func _matches_file(issue) -> bool:
	return current_file_filter == "" or current_file_filter in issue.file_path.to_lower()


func _matches_current_filters(issue) -> bool:
	return _matches_severity(issue) and _matches_type(issue) and _matches_file(issue)


func _filter_issues(issues: Array) -> Array:
	return issues.filter(_matches_current_filters)


func _build_report_header() -> String:
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
	return bbcode


func _build_active_filters_text(count: int) -> String:
	var active: Array[String] = []
	if current_severity_filter != "all":
		active.append(current_severity_filter.capitalize())
	if current_type_filter != "all":
		active.append(ISSUE_TYPES.get(current_type_filter, current_type_filter))
	if current_file_filter != "":
		active.append("\"%s\"" % current_file_filter)
	if active.size() > 0:
		return "[color=#888888]Filters: %s (%d matches)[/color]\n\n" % [", ".join(active), count]
	return ""


func _group_issues_by_severity(issues: Array) -> Dictionary:
	var Issue = IssueScript
	var grouped := {"critical": [], "warning": [], "info": []}
	for issue in issues:
		match issue.severity:
			Issue.Severity.CRITICAL: grouped.critical.append(issue)
			Issue.Severity.WARNING: grouped.warning.append(issue)
			Issue.Severity.INFO: grouped.info.append(issue)
	return grouped


func _format_severity_section(issues: Array, label: String, emoji: String, color: String, severity_key: String) -> String:
	if issues.size() == 0:
		return ""
	var bbcode := "[color=%s][b]%s %s (%d)[/b][/color]" % [color, emoji, label, issues.size()]

	# Add Claude Code button for severity level if enabled
	if settings_manager.claude_code_enabled:
		bbcode += " [url=claude-severity://%s][img=20x20]res://addons/gdscript-linter/icons/claude.png[/img][/url]" % severity_key

	bbcode += "\n"
	bbcode += _format_issues_by_type(issues, color, severity_key)
	return bbcode + "\n"


func _display_results() -> void:
	if not current_result:
		return

	# Clear grouped issues for batch Claude operations
	_grouped_issues_by_type.clear()
	_grouped_issues_by_severity.clear()

	var bbcode := _build_report_header()
	var filtered := _filter_issues(current_result.issues.duplicate())

	bbcode += _build_active_filters_text(filtered.size())

	var grouped := _group_issues_by_severity(filtered)

	# Store grouped issues for batch Claude operations
	_grouped_issues_by_severity = {
		"critical": grouped.critical,
		"warning": grouped.warning,
		"info": grouped.info
	}

	bbcode += _format_severity_section(grouped.critical, "CRITICAL", "🔴", "#ff6b6b", "critical")
	bbcode += _format_severity_section(grouped.warning, "WARNINGS", "🟡", "#ffd93d", "warning")
	bbcode += _format_severity_section(grouped.info, "INFO", "🔵", "#6bcb77", "info")

	if filtered.size() == 0:
		bbcode += "[color=#888888]No issues matching current filters[/color]"

	if settings_manager.show_ignored_issues:
		bbcode += _format_ignored_section()

	results_label.text = bbcode


func _format_issues_by_type(issues: Array, color: String, severity_key: String) -> String:
	var bbcode := ""

	var by_type: Dictionary = {}
	for issue in issues:
		var check_id: String = issue.check_id
		if not by_type.has(check_id):
			by_type[check_id] = []
		by_type[check_id].append(issue)

	# Store grouped issues by type for batch Claude operations
	for check_id in by_type:
		var type_key := "%s|%s" % [severity_key, check_id]
		_grouped_issues_by_type[type_key] = by_type[check_id]

	var type_keys := by_type.keys()
	type_keys.sort_custom(func(a, b): return by_type[a].size() > by_type[b].size())

	var is_first_type := true
	for check_id in type_keys:
		var type_issues: Array = by_type[check_id]
		var type_name: String = ISSUE_TYPES.get(check_id, check_id)

		if not is_first_type:
			bbcode += "\n"
		is_first_type = false

		bbcode += "  [color=#aaaaaa]── %s (%d)[/color]" % [type_name, type_issues.size()]

		# Add Claude Code button for type level if enabled
		if settings_manager.claude_code_enabled:
			var type_key := "%s|%s" % [severity_key, check_id]
			bbcode += " [url=claude-type://%s][img=16x16]res://addons/gdscript-linter/icons/claude.png[/img][/url]" % type_key.uri_encode()

		bbcode += " [color=#aaaaaa]──[/color]\n"

		var shown := 0
		for issue in type_issues:
			if shown >= ISSUES_PER_CATEGORY:
				bbcode += "  [color=#888888]  ... and %d more[/color]\n" % (type_issues.size() - shown)
				break
			bbcode += _format_issue(issue, color)
			shown += 1

	return bbcode


func _format_issue(issue, color: String) -> String:
	var display_path: String = issue.file_path if settings_manager.show_full_path else issue.file_path.get_file()
	var link := "%s:%d" % [issue.file_path, issue.line]

	var line := "    [url=%s][color=%s]%s:%d[/color][/url] %s" % [
		link, color, display_path, issue.line, issue.message
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
		line += " [url=claude://%s][img=20x20]res://addons/gdscript-linter/icons/claude.png[/img][/url]" % claude_data.uri_encode()

	return line + "\n"


func _matches_severity_and_file(issue) -> bool:
	return _matches_severity(issue) and _matches_file(issue)


func _format_ignored_section() -> String:
	if not current_result or current_result.ignored_issues.size() == 0:
		return ""

	var ignored: Array = current_result.ignored_issues.filter(_matches_severity_and_file)

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
				var display_path: String = issue.file_path if settings_manager.show_full_path else issue.file_path.get_file()
				var link := "%s:%d" % [issue.file_path, issue.line]
				refs.append("[url=%s]%s:%d[/url]" % [link, display_path, issue.line])
			bbcode += "  [color=#555555]%s: %s[/color]\n" % [type_name.to_lower(), ", ".join(refs)]
		else:
			bbcode += "  [color=#555555]%s (%d):[/color]\n" % [type_name.to_lower(), type_issues.size()]
			var shown := 0
			for issue in type_issues:
				if shown >= ISSUES_PER_CATEGORY:
					bbcode += "    [color=#444444]... and %d more[/color]\n" % (type_issues.size() - shown)
					break
				var display_path: String = issue.file_path if settings_manager.show_full_path else issue.file_path.get_file()
				var link := "%s:%d" % [issue.file_path, issue.line]
				bbcode += "    [url=%s][color=#555555]%s:%d[/color][/url] %s\n" % [
					link, display_path, issue.line, issue.message
				]
				shown += 1

	return bbcode


func _on_link_clicked(meta: Variant) -> void:
	var location := str(meta)

	if location.begins_with("claude://"):
		_handle_claude_single_link(location)
	elif location.begins_with("claude-type://"):
		_handle_claude_type_link(location)
	elif location.begins_with("claude-severity://"):
		_handle_claude_severity_link(location)
	else:
		_handle_file_link(location)


func _handle_claude_single_link(location: String) -> void:
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


func _handle_claude_type_link(location: String) -> void:
	var type_key: String = location.substr(14).uri_decode()
	if _grouped_issues_by_type.has(type_key):
		var issues: Array = _grouped_issues_by_type[type_key]
		var use_plan_mode := not Input.is_key_pressed(KEY_SHIFT)
		_launch_claude_code_batch(issues, use_plan_mode)
	else:
		push_warning("No issues found for type key: %s" % type_key)


func _handle_claude_severity_link(location: String) -> void:
	var severity_key: String = location.substr(18)
	if _grouped_issues_by_severity.has(severity_key):
		var issues: Array = _grouped_issues_by_severity[severity_key]
		var use_plan_mode := not Input.is_key_pressed(KEY_SHIFT)
		_launch_claude_code_batch(issues, use_plan_mode)
	else:
		push_warning("No issues found for severity: %s" % severity_key)


func _handle_file_link(location: String) -> void:
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
	var use_plan_mode := not Input.is_key_pressed(KEY_SHIFT)
	_launch_claude_code(issue, use_plan_mode)


# Launches Claude Code with the given issue context
# use_plan_mode: true = plan mode (safe), false = immediate execution
func _launch_claude_code(issue: Dictionary, use_plan_mode: bool) -> void:
	var project_path := ProjectSettings.globalize_path("res://")

	var prompt := "Code quality issue to fix:\n\n"
	prompt += "File: %s\n" % issue.file_path
	prompt += "Line: %d\n" % issue.line
	prompt += "Type: %s\n" % issue.check_id
	prompt += "Severity: %s\n" % issue.severity
	prompt += "Message: %s\n\n" % issue.message

	if use_plan_mode:
		prompt += "Analyze this issue and suggest a fix."
	else:
		prompt += "Fix this issue now."

	if not settings_manager.claude_custom_instructions.strip_edges().is_empty():
		prompt += "\n\n" + settings_manager.claude_custom_instructions

	var escaped_prompt := prompt.replace("'", "''")

	# Determine command based on mode
	var command: String
	if use_plan_mode:
		command = settings_manager.claude_code_command
	else:
		# Remove --permission-mode plan if present for immediate execution
		command = settings_manager.claude_code_command.replace("--permission-mode plan", "").strip_edges()
		if command.is_empty():
			command = "claude"

	var args: PackedStringArray = [
		"-d", project_path,
		"powershell", "-NoProfile", "-NoExit",
		"-Command", "%s '%s'" % [command, escaped_prompt]
	]
	OS.create_process("wt", args)


# Launches Claude Code with multiple issues (batch fix)
func _launch_claude_code_batch(issues: Array, use_plan_mode: bool) -> void:
	if issues.is_empty():
		return

	var project_path := ProjectSettings.globalize_path("res://")
	var Issue = IssueScript

	var prompt := "Code quality issues to fix (%d total):\n\n" % issues.size()

	for i in range(issues.size()):
		var issue = issues[i]
		var severity_str: String = "unknown"
		match issue.severity:
			Issue.Severity.CRITICAL: severity_str = "critical"
			Issue.Severity.WARNING: severity_str = "warning"
			Issue.Severity.INFO: severity_str = "info"

		prompt += "%d. %s:%d\n" % [i + 1, issue.file_path, issue.line]
		prompt += "   Type: %s | Severity: %s\n" % [issue.check_id, severity_str]
		prompt += "   %s\n\n" % issue.message

	if use_plan_mode:
		prompt += "Analyze these issues and suggest fixes for each."
	else:
		prompt += "Fix all these issues now."

	if not settings_manager.claude_custom_instructions.strip_edges().is_empty():
		prompt += "\n\n" + settings_manager.claude_custom_instructions

	var escaped_prompt := prompt.replace("'", "''")

	var command: String
	if use_plan_mode:
		command = settings_manager.claude_code_command
	else:
		command = settings_manager.claude_code_command.replace("--permission-mode plan", "").strip_edges()
		if command.is_empty():
			command = "claude"

	var args: PackedStringArray = [
		"-d", project_path,
		"powershell", "-NoProfile", "-NoExit",
		"-Command", "%s '%s'" % [command, escaped_prompt]
	]
	OS.create_process("wt", args)


# Launches Claude Code with custom command and instructions (from customize dialog)
func _launch_claude_code_custom(issue: Dictionary, custom_command: String, custom_instructions: String) -> void:
	var project_path := ProjectSettings.globalize_path("res://")

	var prompt := "Code quality issue to fix:\n\n"
	prompt += "File: %s\n" % issue.file_path
	prompt += "Line: %d\n" % issue.line
	prompt += "Type: %s\n" % issue.check_id
	prompt += "Severity: %s\n" % issue.severity
	prompt += "Message: %s\n\n" % issue.message
	prompt += "Fix this issue."

	if not custom_instructions.strip_edges().is_empty():
		prompt += "\n\n" + custom_instructions

	var escaped_prompt := prompt.replace("'", "''")

	var command := custom_command if not custom_command.is_empty() else "claude"

	var args: PackedStringArray = [
		"-d", project_path,
		"powershell", "-NoProfile", "-NoExit",
		"-Command", "%s '%s'" % [command, escaped_prompt]
	]
	OS.create_process("wt", args)


# Launches Claude Code with multiple issues using custom command/instructions
func _launch_claude_code_batch_custom(issues: Array, custom_command: String, custom_instructions: String) -> void:
	if issues.is_empty():
		return

	var project_path := ProjectSettings.globalize_path("res://")
	var Issue = IssueScript

	var prompt := "Code quality issues to fix (%d total):\n\n" % issues.size()

	for i in range(issues.size()):
		var issue = issues[i]
		var severity_str: String = "unknown"
		match issue.severity:
			Issue.Severity.CRITICAL: severity_str = "critical"
			Issue.Severity.WARNING: severity_str = "warning"
			Issue.Severity.INFO: severity_str = "info"

		prompt += "%d. %s:%d\n" % [i + 1, issue.file_path, issue.line]
		prompt += "   Type: %s | Severity: %s\n" % [issue.check_id, severity_str]
		prompt += "   %s\n\n" % issue.message

	prompt += "Fix all these issues."

	if not custom_instructions.strip_edges().is_empty():
		prompt += "\n\n" + custom_instructions

	var escaped_prompt := prompt.replace("'", "''")

	var command := custom_command if not custom_command.is_empty() else "claude"

	var args: PackedStringArray = [
		"-d", project_path,
		"powershell", "-NoProfile", "-NoExit",
		"-Command", "%s '%s'" % [command, escaped_prompt]
	]
	OS.create_process("wt", args)