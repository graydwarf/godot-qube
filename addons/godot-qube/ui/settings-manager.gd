# Godot Qube - Settings Manager
# https://poplava.itch.io
@tool
extends RefCounted
class_name QubeSettingsManager
## Handles loading and saving settings from EditorSettings

signal setting_changed(key: String, value: Variant)
signal display_refresh_needed

const CLAUDE_CODE_DEFAULT_COMMAND := "claude --permission-mode plan"

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
	claude_custom_instructions = _get_setting(editor_settings, "code_quality/claude/custom_instructions", "")

	# Apply to UI controls if they exist
	_apply_to_ui()


# Apply current settings to UI controls
func _apply_to_ui() -> void:
	if controls.is_empty():
		return

	# Display options
	if controls.has("show_issues_check"):
		controls.show_issues_check.button_pressed = show_total_issues
	if controls.has("show_debt_check"):
		controls.show_debt_check.button_pressed = show_debt
	if controls.has("show_json_export_check"):
		controls.show_json_export_check.button_pressed = show_json_export
	if controls.has("show_html_export_check"):
		controls.show_html_export_check.button_pressed = show_html_export
	if controls.has("show_ignored_check"):
		controls.show_ignored_check.button_pressed = show_ignored_issues
	if controls.has("respect_gdignore_check"):
		controls.respect_gdignore_check.button_pressed = respect_gdignore
	if controls.has("scan_addons_check"):
		controls.scan_addons_check.button_pressed = scan_addons

	# Analysis limits
	if controls.has("max_lines_soft_spin"):
		controls.max_lines_soft_spin.value = config.line_limit_soft
	if controls.has("max_lines_hard_spin"):
		controls.max_lines_hard_spin.value = config.line_limit_hard
	if controls.has("max_func_lines_spin"):
		controls.max_func_lines_spin.value = config.function_line_limit
	if controls.has("max_complexity_spin"):
		controls.max_complexity_spin.value = config.cyclomatic_warning
	if controls.has("func_lines_crit_spin"):
		controls.func_lines_crit_spin.value = config.function_line_critical
	if controls.has("max_complexity_crit_spin"):
		controls.max_complexity_crit_spin.value = config.cyclomatic_critical
	if controls.has("max_params_spin"):
		controls.max_params_spin.value = config.max_parameters
	if controls.has("max_nesting_spin"):
		controls.max_nesting_spin.value = config.max_nesting
	if controls.has("god_class_funcs_spin"):
		controls.god_class_funcs_spin.value = config.god_class_functions
	if controls.has("god_class_signals_spin"):
		controls.god_class_signals_spin.value = config.god_class_signals

	# Claude Code settings
	if controls.has("claude_enabled_check"):
		controls.claude_enabled_check.button_pressed = claude_code_enabled
	if controls.has("claude_command_edit"):
		controls.claude_command_edit.text = claude_code_command
	if controls.has("claude_instructions_edit"):
		controls.claude_instructions_edit.text = claude_custom_instructions


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

	# Analysis limits
	if controls.has("max_lines_soft_spin"):
		controls.max_lines_soft_spin.value_changed.connect(_on_max_lines_soft_changed)
	if controls.has("max_lines_hard_spin"):
		controls.max_lines_hard_spin.value_changed.connect(_on_max_lines_hard_changed)
	if controls.has("max_func_lines_spin"):
		controls.max_func_lines_spin.value_changed.connect(_on_max_func_lines_changed)
	if controls.has("max_complexity_spin"):
		controls.max_complexity_spin.value_changed.connect(_on_max_complexity_changed)
	if controls.has("func_lines_crit_spin"):
		controls.func_lines_crit_spin.value_changed.connect(_on_func_lines_crit_changed)
	if controls.has("max_complexity_crit_spin"):
		controls.max_complexity_crit_spin.value_changed.connect(_on_max_complexity_crit_changed)
	if controls.has("max_params_spin"):
		controls.max_params_spin.value_changed.connect(_on_max_params_changed)
	if controls.has("max_nesting_spin"):
		controls.max_nesting_spin.value_changed.connect(_on_max_nesting_changed)
	if controls.has("god_class_funcs_spin"):
		controls.god_class_funcs_spin.value_changed.connect(_on_god_class_funcs_changed)
	if controls.has("god_class_signals_spin"):
		controls.god_class_signals_spin.value_changed.connect(_on_god_class_signals_changed)
	if controls.has("reset_all_limits_btn"):
		controls.reset_all_limits_btn.pressed.connect(_on_reset_all_limits_pressed)

	# Claude Code settings
	if controls.has("claude_enabled_check"):
		controls.claude_enabled_check.toggled.connect(_on_claude_enabled_toggled)
	if controls.has("claude_command_edit"):
		controls.claude_command_edit.text_changed.connect(_on_claude_command_changed)
	if controls.has("claude_instructions_edit"):
		controls.claude_instructions_edit.text_changed.connect(_on_claude_instructions_changed)
	if controls.has("claude_reset_button"):
		controls.claude_reset_button.pressed.connect(_on_claude_reset_pressed)


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


# ========== Analysis Limits Handlers ==========

func _on_max_lines_soft_changed(value: float) -> void:
	config.line_limit_soft = int(value)
	save_setting("code_quality/limits/file_lines_warn", int(value))


func _on_max_lines_hard_changed(value: float) -> void:
	config.line_limit_hard = int(value)
	save_setting("code_quality/limits/file_lines_critical", int(value))


func _on_max_func_lines_changed(value: float) -> void:
	config.function_line_limit = int(value)
	save_setting("code_quality/limits/function_lines", int(value))


func _on_max_complexity_changed(value: float) -> void:
	config.cyclomatic_warning = int(value)
	save_setting("code_quality/limits/complexity_warn", int(value))


func _on_func_lines_crit_changed(value: float) -> void:
	config.function_line_critical = int(value)
	save_setting("code_quality/limits/function_lines_crit", int(value))


func _on_max_complexity_crit_changed(value: float) -> void:
	config.cyclomatic_critical = int(value)
	save_setting("code_quality/limits/complexity_crit", int(value))


func _on_max_params_changed(value: float) -> void:
	config.max_parameters = int(value)
	save_setting("code_quality/limits/max_params", int(value))


func _on_max_nesting_changed(value: float) -> void:
	config.max_nesting = int(value)
	save_setting("code_quality/limits/max_nesting", int(value))


func _on_god_class_funcs_changed(value: float) -> void:
	config.god_class_functions = int(value)
	save_setting("code_quality/limits/god_class_funcs", int(value))


func _on_god_class_signals_changed(value: float) -> void:
	config.god_class_signals = int(value)
	save_setting("code_quality/limits/god_class_signals", int(value))


func _on_reset_all_limits_pressed() -> void:
	if controls.has("max_lines_soft_spin"):
		controls.max_lines_soft_spin.value = 200
	if controls.has("max_lines_hard_spin"):
		controls.max_lines_hard_spin.value = 300
	if controls.has("max_func_lines_spin"):
		controls.max_func_lines_spin.value = 30
	if controls.has("func_lines_crit_spin"):
		controls.func_lines_crit_spin.value = 60
	if controls.has("max_complexity_spin"):
		controls.max_complexity_spin.value = 10
	if controls.has("max_complexity_crit_spin"):
		controls.max_complexity_crit_spin.value = 15
	if controls.has("max_params_spin"):
		controls.max_params_spin.value = 4
	if controls.has("max_nesting_spin"):
		controls.max_nesting_spin.value = 3
	if controls.has("god_class_funcs_spin"):
		controls.god_class_funcs_spin.value = 20
	if controls.has("god_class_signals_spin"):
		controls.god_class_signals_spin.value = 10


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


func _on_claude_reset_pressed() -> void:
	claude_code_command = CLAUDE_CODE_DEFAULT_COMMAND
	if controls.has("claude_command_edit"):
		controls.claude_command_edit.text = CLAUDE_CODE_DEFAULT_COMMAND
	save_setting("code_quality/claude/launch_command", CLAUDE_CODE_DEFAULT_COMMAND)
