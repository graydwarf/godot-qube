# Godot Qube - Settings Manager
# https://poplava.itch.io
@tool
extends RefCounted
class_name QubeSettingsManager
## Handles loading and saving settings from EditorSettings

signal setting_changed(key: String, value: Variant)
signal display_refresh_needed

const CLAUDE_CODE_DEFAULT_COMMAND := "claude --permission-mode plan"
const CLAUDE_CODE_DEFAULT_INSTRUCTIONS := "When analyzing issues, recommend the best solution - which may be a qube:ignore directive instead of refactoring. If code is clean and readable but slightly over a limit, suggest adding an ignore comment rather than restructuring working code. Always explain why you're recommending a refactor vs an ignore directive."

# Settings state
var show_total_issues: bool = true
var show_debt: bool = true
var show_json_export: bool = false
var show_html_export: bool = true
var show_ignored_issues: bool = true
var respect_gdignore: bool = true
var scan_addons: bool = false
var claude_code_enabled: bool = false
var claude_code_command: String = CLAUDE_CODE_DEFAULT_COMMAND
var claude_custom_instructions: String = ""

# References
var config: Resource  # QubeConfig
var controls: Dictionary = {}
var _limits_handler: QubeSettingsLimitsHandler


func _init(p_config: Resource) -> void:
	config = p_config


# Load all settings from EditorSettings and apply to config and UI controls
func load_settings() -> void:
	var editor_settings := EditorInterface.get_editor_settings()

	# Load display settings
	show_total_issues = _get_setting(editor_settings, "code_quality/display/show_issues", true)
	show_debt = _get_setting(editor_settings, "code_quality/display/show_debt", true)
	show_json_export = _get_setting(editor_settings, "code_quality/display/show_json_export", false)
	show_html_export = _get_setting(editor_settings, "code_quality/display/show_html_export", true)
	show_ignored_issues = _get_setting(editor_settings, "code_quality/display/show_ignored", true)

	# Load scanning settings
	respect_gdignore = _get_setting(editor_settings, "code_quality/scanning/respect_gdignore", true)
	config.respect_gdignore = respect_gdignore
	scan_addons = _get_setting(editor_settings, "code_quality/scanning/scan_addons", false)
	config.scan_addons = scan_addons

	# Load analysis limits
	config.line_limit_soft = _get_setting(editor_settings, "code_quality/limits/file_lines_warn", 200)
	config.line_limit_hard = _get_setting(editor_settings, "code_quality/limits/file_lines_critical", 300)
	config.function_line_limit = _get_setting(editor_settings, "code_quality/limits/function_lines", 30)
	config.function_line_critical = _get_setting(editor_settings, "code_quality/limits/function_lines_crit", 60)
	config.cyclomatic_warning = _get_setting(editor_settings, "code_quality/limits/complexity_warn", 10)
	config.cyclomatic_critical = _get_setting(editor_settings, "code_quality/limits/complexity_crit", 15)
	config.max_parameters = _get_setting(editor_settings, "code_quality/limits/max_params", 4)
	config.max_nesting = _get_setting(editor_settings, "code_quality/limits/max_nesting", 3)
	config.god_class_functions = _get_setting(editor_settings, "code_quality/limits/god_class_funcs", 20)
	config.god_class_signals = _get_setting(editor_settings, "code_quality/limits/god_class_signals", 10)

	# Load Claude Code settings
	claude_code_enabled = _get_setting(editor_settings, "code_quality/claude/enabled", false)
	claude_code_command = _get_setting(editor_settings, "code_quality/claude/launch_command", CLAUDE_CODE_DEFAULT_COMMAND)
	claude_custom_instructions = _get_setting(editor_settings, "code_quality/claude/custom_instructions", CLAUDE_CODE_DEFAULT_INSTRUCTIONS)

	# Apply to UI controls if they exist
	_apply_to_ui()


# Apply current settings to UI controls
func _apply_to_ui() -> void:
	if controls.is_empty():
		return

	# Boolean controls (CheckBox/CheckButton)
	var bool_mappings := {
		"show_issues_check": func(): return show_total_issues,
		"show_debt_check": func(): return show_debt,
		"show_json_export_check": func(): return show_json_export,
		"show_html_export_check": func(): return show_html_export,
		"show_ignored_check": func(): return show_ignored_issues,
		"respect_gdignore_check": func(): return respect_gdignore,
		"scan_addons_check": func(): return scan_addons,
		"claude_enabled_check": func(): return claude_code_enabled,
	}

	for control_key in bool_mappings:
		if controls.has(control_key):
			controls[control_key].button_pressed = bool_mappings[control_key].call()

	# Numeric controls (SpinBox)
	var spin_mappings := {
		"max_lines_soft_spin": func(): return config.line_limit_soft,
		"max_lines_hard_spin": func(): return config.line_limit_hard,
		"max_func_lines_spin": func(): return config.function_line_limit,
		"max_complexity_spin": func(): return config.cyclomatic_warning,
		"func_lines_crit_spin": func(): return config.function_line_critical,
		"max_complexity_crit_spin": func(): return config.cyclomatic_critical,
		"max_params_spin": func(): return config.max_parameters,
		"max_nesting_spin": func(): return config.max_nesting,
		"god_class_funcs_spin": func(): return config.god_class_functions,
		"god_class_signals_spin": func(): return config.god_class_signals,
	}

	for control_key in spin_mappings:
		if controls.has(control_key):
			controls[control_key].value = spin_mappings[control_key].call()

	# Text controls (LineEdit/TextEdit)
	var text_mappings := {
		"claude_command_edit": func(): return claude_code_command,
		"claude_instructions_edit": func(): return claude_custom_instructions,
	}

	for control_key in text_mappings:
		if controls.has(control_key):
			controls[control_key].text = text_mappings[control_key].call()


# Connect all UI control signals
func connect_controls(export_btn: Button, html_export_btn: Button) -> void:
	# Display options
	if controls.has("show_issues_check"):
		controls.show_issues_check.toggled.connect(_on_show_issues_toggled)
	if controls.has("show_debt_check"):
		controls.show_debt_check.toggled.connect(_on_show_debt_toggled)
	if controls.has("show_json_export_check"):
		controls.show_json_export_check.toggled.connect(func(pressed): _on_show_json_export_toggled(pressed, export_btn))
	if controls.has("show_html_export_check"):
		controls.show_html_export_check.toggled.connect(func(pressed): _on_show_html_export_toggled(pressed, html_export_btn))
	if controls.has("show_ignored_check"):
		controls.show_ignored_check.toggled.connect(_on_show_ignored_toggled)
	if controls.has("respect_gdignore_check"):
		controls.respect_gdignore_check.toggled.connect(_on_respect_gdignore_toggled)
	if controls.has("scan_addons_check"):
		controls.scan_addons_check.toggled.connect(_on_scan_addons_toggled)

	# Analysis limits (delegated to handler)
	_limits_handler = QubeSettingsLimitsHandler.new(config, controls, save_setting)
	_limits_handler.connect_controls()

	# Claude Code settings
	if controls.has("claude_enabled_check"):
		controls.claude_enabled_check.toggled.connect(_on_claude_enabled_toggled)
	if controls.has("claude_command_edit"):
		controls.claude_command_edit.text_changed.connect(_on_claude_command_changed)
	if controls.has("claude_instructions_edit"):
		controls.claude_instructions_edit.text_changed.connect(_on_claude_instructions_changed)
	if controls.has("claude_reset_button"):
		controls.claude_reset_button.pressed.connect(_on_claude_command_reset_pressed)
	if controls.has("claude_instructions_reset_button"):
		controls.claude_instructions_reset_button.pressed.connect(_on_claude_instructions_reset_pressed)


# Helper to get setting with default value
func _get_setting(editor_settings: EditorSettings, key: String, default_value: Variant) -> Variant:
	return editor_settings.get_setting(key) if editor_settings.has_setting(key) else default_value


# Save a single setting
func save_setting(key: String, value: Variant) -> void:
	var editor_settings := EditorInterface.get_editor_settings()
	editor_settings.set_setting(key, value)
	setting_changed.emit(key, value)


# ========== Display Options Handlers ==========

func _on_show_issues_toggled(pressed: bool) -> void:
	show_total_issues = pressed
	save_setting("code_quality/display/show_issues", pressed)
	display_refresh_needed.emit()


func _on_show_debt_toggled(pressed: bool) -> void:
	show_debt = pressed
	save_setting("code_quality/display/show_debt", pressed)
	display_refresh_needed.emit()


func _on_show_json_export_toggled(pressed: bool, export_btn: Button) -> void:
	show_json_export = pressed
	save_setting("code_quality/display/show_json_export", pressed)
	export_btn.visible = pressed


func _on_show_html_export_toggled(pressed: bool, html_export_btn: Button) -> void:
	show_html_export = pressed
	save_setting("code_quality/display/show_html_export", pressed)
	html_export_btn.visible = pressed


func _on_show_ignored_toggled(pressed: bool) -> void:
	show_ignored_issues = pressed
	save_setting("code_quality/display/show_ignored", pressed)
	display_refresh_needed.emit()


func _on_respect_gdignore_toggled(pressed: bool) -> void:
	respect_gdignore = pressed
	config.respect_gdignore = pressed
	save_setting("code_quality/scanning/respect_gdignore", pressed)


func _on_scan_addons_toggled(pressed: bool) -> void:
	scan_addons = pressed
	config.scan_addons = pressed
	save_setting("code_quality/scanning/scan_addons", pressed)


# ========== Claude Code Handlers ==========

func _on_claude_enabled_toggled(pressed: bool) -> void:
	claude_code_enabled = pressed
	save_setting("code_quality/claude/enabled", pressed)
	display_refresh_needed.emit()


func _on_claude_command_changed(new_text: String) -> void:
	claude_code_command = new_text
	save_setting("code_quality/claude/launch_command", new_text)


func _on_claude_instructions_changed() -> void:
	if controls.has("claude_instructions_edit"):
		claude_custom_instructions = controls.claude_instructions_edit.text
		save_setting("code_quality/claude/custom_instructions", claude_custom_instructions)


func _on_claude_command_reset_pressed() -> void:
	claude_code_command = CLAUDE_CODE_DEFAULT_COMMAND
	if controls.has("claude_command_edit"):
		controls.claude_command_edit.text = CLAUDE_CODE_DEFAULT_COMMAND
	save_setting("code_quality/claude/launch_command", CLAUDE_CODE_DEFAULT_COMMAND)


func _on_claude_instructions_reset_pressed() -> void:
	claude_custom_instructions = CLAUDE_CODE_DEFAULT_INSTRUCTIONS
	if controls.has("claude_instructions_edit"):
		controls.claude_instructions_edit.text = CLAUDE_CODE_DEFAULT_INSTRUCTIONS
	save_setting("code_quality/claude/custom_instructions", CLAUDE_CODE_DEFAULT_INSTRUCTIONS)
