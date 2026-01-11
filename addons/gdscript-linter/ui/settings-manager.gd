# GDScript Linter - Settings Manager
# https://poplava.itch.io
@tool
extends RefCounted
class_name GDLintSettingsManager
## Handles loading and saving settings from EditorSettings

signal setting_changed(key: String, value: Variant)
signal display_refresh_needed
signal export_config_requested

const CLAUDE_CODE_DEFAULT_COMMAND := "claude --permission-mode plan"
const CLAUDE_CODE_DEFAULT_INSTRUCTIONS := "When analyzing issues, recommend the best solution - which may be a gdlint:ignore directive instead of refactoring. If code is clean and readable but slightly over a limit, suggest adding an ignore comment rather than restructuring working code. Always explain why you're recommending a refactor vs an ignore directive. Adhere to res://addons/gdscript-linter/IGNORE_RULES.md syntax for ignores."

# Settings state - Display
var show_total_issues: bool = true
var show_debt: bool = true
var show_json_export: bool = false
var show_html_export: bool = true
var show_ignored_issues: bool = true
var show_full_path: bool = false

# Settings state - Scanning
var respect_gdignore: bool = true
var scan_addons: bool = false
var remember_filter_selections: bool = false

# Persisted filter selections (only used when remember_filter_selections is true)
var saved_severity_filter: int = 0  # Index in dropdown
var saved_type_filter: String = "all"  # check_id or "all"
var saved_file_filter: String = ""

# Settings state - Code Checks (all enabled by default)
var check_naming_conventions: bool = true
var check_long_lines: bool = true
var check_todo_comments: bool = true
var check_print_statements: bool = true
var check_magic_numbers: bool = true
var check_commented_code: bool = true
var check_missing_types: bool = true
var check_function_length: bool = true
var check_parameters: bool = true
var check_nesting: bool = true
var check_cyclomatic_complexity: bool = true
var check_empty_functions: bool = true
var check_missing_return_type: bool = true
var check_file_length: bool = true
var check_god_class: bool = true
var check_unused_variables: bool = true
var check_unused_parameters: bool = true

# Settings state - Claude Code
var claude_code_enabled: bool = false
var claude_code_command: String = CLAUDE_CODE_DEFAULT_COMMAND
var claude_custom_instructions: String = ""

# All check control keys for Enable All / Disable All
var _check_control_keys: Array[String] = [
	"check_naming_conventions", "check_long_lines", "check_todo_comments",
	"check_print_statements", "check_magic_numbers", "check_commented_code",
	"check_missing_types", "check_function_length", "check_parameters",
	"check_nesting", "check_cyclomatic_complexity", "check_empty_functions",
	"check_missing_return_type", "check_file_length", "check_god_class",
	"check_unused_variables", "check_unused_parameters"
]

# References
var config: Resource  # GDLintConfig
var controls: Dictionary = {}
var _limits_handler: GDLintSettingsLimitsHandler


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
	show_full_path = _get_setting(editor_settings, "code_quality/display/show_full_path", false)

	# Load scanning settings
	respect_gdignore = _get_setting(editor_settings, "code_quality/scanning/respect_gdignore", true)
	config.respect_gdignore = respect_gdignore
	scan_addons = _get_setting(editor_settings, "code_quality/scanning/scan_addons", false)
	config.scan_addons = scan_addons
	remember_filter_selections = _get_setting(editor_settings, "code_quality/scanning/remember_filters", false)

	# Load saved filter selections
	saved_severity_filter = _get_setting(editor_settings, "code_quality/filters/severity", 0)
	saved_type_filter = _get_setting(editor_settings, "code_quality/filters/type", "all")
	saved_file_filter = _get_setting(editor_settings, "code_quality/filters/file", "")

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

	# Load code checks settings
	_load_check_settings(editor_settings)

	# Load Claude Code settings
	claude_code_enabled = _get_setting(editor_settings, "code_quality/claude/enabled", false)
	claude_code_command = _get_setting(editor_settings, "code_quality/claude/launch_command", CLAUDE_CODE_DEFAULT_COMMAND)
	claude_custom_instructions = _get_setting(editor_settings, "code_quality/claude/custom_instructions", CLAUDE_CODE_DEFAULT_INSTRUCTIONS)

	# Apply to UI controls if they exist
	_apply_to_ui()


# Load all code check settings from EditorSettings and apply to config
func _load_check_settings(editor_settings: EditorSettings) -> void:
	# Map of setting key suffix -> (local var name, config property name)
	var check_mappings := {
		"naming_conventions": "check_naming_conventions",
		"long_lines": "check_long_lines",
		"todo_comments": "check_todo_comments",
		"print_statements": "check_print_statements",
		"magic_numbers": "check_magic_numbers",
		"commented_code": "check_commented_code",
		"missing_types": "check_missing_types",
		"function_length": "check_function_length",
		"parameters": "check_parameters",
		"nesting": "check_nesting",
		"cyclomatic_complexity": "check_cyclomatic_complexity",
		"empty_functions": "check_empty_functions",
		"missing_return_type": "check_missing_return_type",
		"file_length": "check_file_length",
		"god_class": "check_god_class",
		"unused_variables": "check_unused_variables",
		"unused_parameters": "check_unused_parameters",
	}

	for key_suffix: String in check_mappings:
		var prop_name: String = check_mappings[key_suffix]
		var setting_key: String = "code_quality/checks/" + key_suffix
		var value: bool = _get_setting(editor_settings, setting_key, true)
		set(prop_name, value)
		if config.get(prop_name) != null:
			config.set(prop_name, value)


# Apply current settings to UI controls
func _apply_to_ui() -> void:
	if controls.is_empty():
		return

	# Boolean controls (CheckBox/CheckButton)
	var bool_mappings := {
		# Display options
		"show_issues_check": func(): return show_total_issues,
		"show_debt_check": func(): return show_debt,
		"show_json_export_check": func(): return show_json_export,
		"show_html_export_check": func(): return show_html_export,
		"show_ignored_check": func(): return show_ignored_issues,
		"show_full_path_check": func(): return show_full_path,
		# Scanning options (now in Code Checks card)
		"respect_gdignore_check": func(): return respect_gdignore,
		"scan_addons_check": func(): return scan_addons,
		"remember_filters_check": func(): return remember_filter_selections,
		# Code checks - Naming
		"check_naming_conventions": func(): return check_naming_conventions,
		# Code checks - Style
		"check_long_lines": func(): return check_long_lines,
		"check_todo_comments": func(): return check_todo_comments,
		"check_print_statements": func(): return check_print_statements,
		"check_magic_numbers": func(): return check_magic_numbers,
		"check_commented_code": func(): return check_commented_code,
		"check_missing_types": func(): return check_missing_types,
		# Code checks - Functions
		"check_function_length": func(): return check_function_length,
		"check_parameters": func(): return check_parameters,
		"check_nesting": func(): return check_nesting,
		"check_cyclomatic_complexity": func(): return check_cyclomatic_complexity,
		"check_empty_functions": func(): return check_empty_functions,
		"check_missing_return_type": func(): return check_missing_return_type,
		# Code checks - Structure
		"check_file_length": func(): return check_file_length,
		"check_god_class": func(): return check_god_class,
		"check_unused_variables": func(): return check_unused_variables,
		"check_unused_parameters": func(): return check_unused_parameters,
		# Claude Code
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
	if controls.has("show_full_path_check"):
		controls.show_full_path_check.toggled.connect(_on_show_full_path_toggled)

	# Code checks - Scanning options
	if controls.has("respect_gdignore_check"):
		controls.respect_gdignore_check.toggled.connect(_on_respect_gdignore_toggled)
	if controls.has("scan_addons_check"):
		controls.scan_addons_check.toggled.connect(_on_scan_addons_toggled)
	if controls.has("remember_filters_check"):
		controls.remember_filters_check.toggled.connect(_on_remember_filters_toggled)

	# Code checks - Enable All / Disable All buttons
	if controls.has("enable_all_checks_btn"):
		controls.enable_all_checks_btn.pressed.connect(_on_enable_all_checks)
	if controls.has("disable_all_checks_btn"):
		controls.disable_all_checks_btn.pressed.connect(_on_disable_all_checks)

	# Code checks - Individual toggles
	_connect_check_signals()

	# Analysis limits (delegated to handler)
	_limits_handler = GDLintSettingsLimitsHandler.new(config, controls, save_setting)
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

	# Export config button
	if controls.has("export_config_btn"):
		controls.export_config_btn.pressed.connect(_on_export_config_pressed)


# Helper to get setting with default value
func _get_setting(editor_settings: EditorSettings, key: String, default_value: Variant) -> Variant:
	return editor_settings.get_setting(key) if editor_settings.has_setting(key) else default_value


# Save a single setting
func save_setting(key: String, value: Variant) -> void:
	var editor_settings := EditorInterface.get_editor_settings()
	editor_settings.set_setting(key, value)
	setting_changed.emit(key, value)

	# Auto-sync analysis settings to project config (gdlint.json)
	# Only sync settings that affect analysis results (not display/filter/claude settings)
	if _is_analysis_setting(key):
		_sync_config_to_json()


# Check if this setting affects analysis and should be synced to project config
func _is_analysis_setting(key: String) -> bool:
	return (key.begins_with("code_quality/limits/") or
			key.begins_with("code_quality/checks/") or
			key.begins_with("code_quality/scanning/respect_gdignore") or
			key.begins_with("code_quality/scanning/scan_addons"))


# Sync current config state to gdlint.json in project root
func _sync_config_to_json() -> void:
	if config == null:
		return
	config.save_to_json("res://gdlint.json")


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


func _on_show_full_path_toggled(pressed: bool) -> void:
	show_full_path = pressed
	save_setting("code_quality/display/show_full_path", pressed)
	display_refresh_needed.emit()


func _on_respect_gdignore_toggled(pressed: bool) -> void:
	respect_gdignore = pressed
	config.respect_gdignore = pressed
	save_setting("code_quality/scanning/respect_gdignore", pressed)


func _on_scan_addons_toggled(pressed: bool) -> void:
	scan_addons = pressed
	config.scan_addons = pressed
	save_setting("code_quality/scanning/scan_addons", pressed)


func _on_remember_filters_toggled(pressed: bool) -> void:
	remember_filter_selections = pressed
	save_setting("code_quality/scanning/remember_filters", pressed)


# Save filter selections (called by dock.gd when filters change)
func save_filter_selections(severity_index: int, type_id: String, file_text: String) -> void:
	if not remember_filter_selections:
		return
	saved_severity_filter = severity_index
	saved_type_filter = type_id
	saved_file_filter = file_text
	save_setting("code_quality/filters/severity", severity_index)
	save_setting("code_quality/filters/type", type_id)
	save_setting("code_quality/filters/file", file_text)


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


# ========== Config Export Handlers ==========

func _on_export_config_pressed() -> void:
	export_config_requested.emit()


# Export config to a custom file path (called by dock after file dialog selection)
func export_config_to_path(file_path: String) -> bool:
	if config == null:
		push_error("GDLint: Cannot export config - config is null")
		return false
	return config.save_to_json(file_path)


# ========== Code Checks Handlers ==========

# Connect all individual check toggle signals
func _connect_check_signals() -> void:
	var check_mappings := {
		"check_naming_conventions": "naming_conventions",
		"check_long_lines": "long_lines",
		"check_todo_comments": "todo_comments",
		"check_print_statements": "print_statements",
		"check_magic_numbers": "magic_numbers",
		"check_commented_code": "commented_code",
		"check_missing_types": "missing_types",
		"check_function_length": "function_length",
		"check_parameters": "parameters",
		"check_nesting": "nesting",
		"check_cyclomatic_complexity": "cyclomatic_complexity",
		"check_empty_functions": "empty_functions",
		"check_missing_return_type": "missing_return_type",
		"check_file_length": "file_length",
		"check_god_class": "god_class",
		"check_unused_variables": "unused_variables",
		"check_unused_parameters": "unused_parameters",
	}

	for control_key in check_mappings:
		if controls.has(control_key):
			var setting_suffix: String = check_mappings[control_key]
			controls[control_key].toggled.connect(
				func(pressed): _on_check_toggled(control_key, setting_suffix, pressed)
			)


# Generic handler for any code check toggle
func _on_check_toggled(control_key: String, setting_suffix: String, pressed: bool) -> void:
	set(control_key, pressed)
	if config.get(control_key) != null:
		config.set(control_key, pressed)
	save_setting("code_quality/checks/" + setting_suffix, pressed)
	setting_changed.emit("check_" + setting_suffix, pressed)


# Enable All checks button handler
func _on_enable_all_checks() -> void:
	_set_all_checks(true)


# Disable All checks button handler
func _on_disable_all_checks() -> void:
	_set_all_checks(false)


# Set all code checks to a specific value
func _set_all_checks(enabled: bool) -> void:
	for control_key in _check_control_keys:
		if controls.has(control_key):
			controls[control_key].button_pressed = enabled
	# Emit a single refresh signal after bulk change
	setting_changed.emit("all_checks", enabled)
