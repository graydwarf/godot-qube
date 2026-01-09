# GDScript Linter - Settings Limits Handler
# https://poplava.itch.io
@tool
extends RefCounted
class_name GDLintSettingsLimitsHandler
## Handles analysis limit SpinBox changes and persistence

var _config: Resource  # GDLintConfig
var _controls: Dictionary
var _save_callback: Callable


func _init(p_config: Resource, p_controls: Dictionary, p_save_callback: Callable) -> void:
	_config = p_config
	_controls = p_controls
	_save_callback = p_save_callback


# Connect all limit-related control signals
func connect_controls() -> void:
	if _controls.has("max_lines_soft_spin"):
		_controls.max_lines_soft_spin.value_changed.connect(_on_max_lines_soft_changed)
	if _controls.has("max_lines_hard_spin"):
		_controls.max_lines_hard_spin.value_changed.connect(_on_max_lines_hard_changed)
	if _controls.has("max_func_lines_spin"):
		_controls.max_func_lines_spin.value_changed.connect(_on_max_func_lines_changed)
	if _controls.has("max_complexity_spin"):
		_controls.max_complexity_spin.value_changed.connect(_on_max_complexity_changed)
	if _controls.has("func_lines_crit_spin"):
		_controls.func_lines_crit_spin.value_changed.connect(_on_func_lines_crit_changed)
	if _controls.has("max_complexity_crit_spin"):
		_controls.max_complexity_crit_spin.value_changed.connect(_on_max_complexity_crit_changed)
	if _controls.has("max_params_spin"):
		_controls.max_params_spin.value_changed.connect(_on_max_params_changed)
	if _controls.has("max_nesting_spin"):
		_controls.max_nesting_spin.value_changed.connect(_on_max_nesting_changed)
	if _controls.has("god_class_funcs_spin"):
		_controls.god_class_funcs_spin.value_changed.connect(_on_god_class_funcs_changed)
	if _controls.has("god_class_signals_spin"):
		_controls.god_class_signals_spin.value_changed.connect(_on_god_class_signals_changed)
	if _controls.has("reset_all_limits_btn"):
		_controls.reset_all_limits_btn.pressed.connect(_on_reset_all_limits_pressed)


func _on_max_lines_soft_changed(value: float) -> void:
	_config.line_limit_soft = int(value)
	_save_callback.call("code_quality/limits/file_lines_warn", int(value))


func _on_max_lines_hard_changed(value: float) -> void:
	_config.line_limit_hard = int(value)
	_save_callback.call("code_quality/limits/file_lines_critical", int(value))


func _on_max_func_lines_changed(value: float) -> void:
	_config.function_line_limit = int(value)
	_save_callback.call("code_quality/limits/function_lines", int(value))


func _on_max_complexity_changed(value: float) -> void:
	_config.cyclomatic_warning = int(value)
	_save_callback.call("code_quality/limits/complexity_warn", int(value))


func _on_func_lines_crit_changed(value: float) -> void:
	_config.function_line_critical = int(value)
	_save_callback.call("code_quality/limits/function_lines_crit", int(value))


func _on_max_complexity_crit_changed(value: float) -> void:
	_config.cyclomatic_critical = int(value)
	_save_callback.call("code_quality/limits/complexity_crit", int(value))


func _on_max_params_changed(value: float) -> void:
	_config.max_parameters = int(value)
	_save_callback.call("code_quality/limits/max_params", int(value))


func _on_max_nesting_changed(value: float) -> void:
	_config.max_nesting = int(value)
	_save_callback.call("code_quality/limits/max_nesting", int(value))


func _on_god_class_funcs_changed(value: float) -> void:
	_config.god_class_functions = int(value)
	_save_callback.call("code_quality/limits/god_class_funcs", int(value))


func _on_god_class_signals_changed(value: float) -> void:
	_config.god_class_signals = int(value)
	_save_callback.call("code_quality/limits/god_class_signals", int(value))


func _on_reset_all_limits_pressed() -> void:
	if _controls.has("max_lines_soft_spin"):
		_controls.max_lines_soft_spin.value = 200
	if _controls.has("max_lines_hard_spin"):
		_controls.max_lines_hard_spin.value = 300
	if _controls.has("max_func_lines_spin"):
		_controls.max_func_lines_spin.value = 30
	if _controls.has("func_lines_crit_spin"):
		_controls.func_lines_crit_spin.value = 60
	if _controls.has("max_complexity_spin"):
		_controls.max_complexity_spin.value = 10
	if _controls.has("max_complexity_crit_spin"):
		_controls.max_complexity_crit_spin.value = 15
	if _controls.has("max_params_spin"):
		_controls.max_params_spin.value = 4
	if _controls.has("max_nesting_spin"):
		_controls.max_nesting_spin.value = 3
	if _controls.has("god_class_funcs_spin"):
		_controls.god_class_funcs_spin.value = 20
	if _controls.has("god_class_signals_spin"):
		_controls.god_class_signals_spin.value = 10
