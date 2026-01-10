# GDScript Linter - Settings Card UI Builder
# https://poplava.itch.io
@tool
extends RefCounted
class_name GDLintSettingsCardBuilder
## Creates settings panel cards with consistent styling

# Default analysis limits
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

var _reset_icon: Texture2D
var _claude_card_builder: GDLintClaudeCodeCardBuilder
var _help_card_builder: GDLintHelpCardBuilder


func _init(reset_icon: Texture2D) -> void:
	_reset_icon = reset_icon
	_claude_card_builder = GDLintClaudeCodeCardBuilder.new(reset_icon)
	_help_card_builder = GDLintHelpCardBuilder.new()


# Creates the standard card style used by all settings cards
static func create_card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.145, 0.169, 0.204, 1.0)  # #252B34
	style.border_color = Color(0.3, 0.35, 0.45, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	return style


# Creates the scroll container wrapper for settings panel
func build_settings_panel(settings_panel: PanelContainer, controls: Dictionary) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	scroll.add_child(margin)

	var cards_vbox := VBoxContainer.new()
	cards_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(cards_vbox)

	# Header bar (non-collapsible)
	cards_vbox.add_child(create_header_bar())

	# Collapsible cards (all collapsed by default)
	cards_vbox.add_child(create_display_options_card(controls))
	cards_vbox.add_child(create_scan_options_card(controls))
	cards_vbox.add_child(create_code_checks_card(controls))
	cards_vbox.add_child(create_limits_card(controls))
	cards_vbox.add_child(_claude_card_builder.create_card(controls))
	cards_vbox.add_child(_create_help_card())

	settings_panel.add_child(scroll)
	settings_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL


# Create Display Options collapsible card with checkboxes
func create_display_options_card(controls: Dictionary) -> GDLintCollapsibleCard:
	var card := GDLintCollapsibleCard.new("Display Options", "code_quality/ui/display_options_collapsed")
	var vbox := card.get_content_container()

	# Row of checkboxes for display toggles
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	vbox.add_child(hbox)

	controls.show_issues_check = _create_checkbox("Show Issues", hbox)
	controls.show_debt_check = _create_checkbox("Show Debt", hbox)
	controls.show_json_export_check = _create_checkbox("Show JSON Export", hbox)
	controls.show_html_export_check = _create_checkbox("Show HTML Export", hbox)
	controls.show_ignored_check = _create_checkbox("Show Ignored", hbox, "Show ignored issues in a separate section")
	controls.show_full_path_check = _create_checkbox("Show Full Path", hbox, "Show full res:// path instead of just filename")

	return card


# Create Scan Options collapsible card
func create_scan_options_card(controls: Dictionary) -> GDLintCollapsibleCard:
	var card := GDLintCollapsibleCard.new("Scan Options", "code_quality/ui/scan_options_collapsed")
	var vbox := card.get_content_container()

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	vbox.add_child(hbox)

	controls.respect_gdignore_check = _create_checkbox("Respect .gdignore", hbox,
		"Skip directories containing .gdignore files")
	controls.scan_addons_check = _create_checkbox("Scan addons/", hbox,
		"Include addons/ folder in scans")
	controls.remember_filters_check = _create_checkbox("Remember Filters", hbox,
		"Persist Severity, Type, and Filter selections across restarts")

	return card


# Create Code Checks collapsible card with toggles for all analysis checks
func create_code_checks_card(controls: Dictionary) -> GDLintCollapsibleCard:
	var card := GDLintCollapsibleCard.new("Code Checks", "code_quality/ui/code_checks_collapsed")
	var vbox := card.get_content_container()

	# Enable All / Disable All buttons row
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	controls.enable_all_checks_btn = Button.new()
	controls.enable_all_checks_btn.text = "Enable All"
	controls.enable_all_checks_btn.flat = true
	controls.enable_all_checks_btn.tooltip_text = "Enable all code checks"
	btn_row.add_child(controls.enable_all_checks_btn)

	controls.disable_all_checks_btn = Button.new()
	controls.disable_all_checks_btn.text = "Disable All"
	controls.disable_all_checks_btn.flat = true
	controls.disable_all_checks_btn.tooltip_text = "Disable all code checks"
	btn_row.add_child(controls.disable_all_checks_btn)

	# Naming section
	_add_section_header(vbox, "Naming")
	var naming_grid := _create_check_grid(vbox)
	controls.check_naming_conventions = _add_check_to_grid(naming_grid, "Naming Conventions",
		"Check class, function, signal, const, and enum naming")

	# Style section
	_add_section_header(vbox, "Style")
	var style_grid := _create_check_grid(vbox)
	controls.check_long_lines = _add_check_to_grid(style_grid, "Long Lines",
		"Lines exceeding max length")
	controls.check_todo_comments = _add_check_to_grid(style_grid, "TODO Comments",
		"TODO, FIXME, HACK, etc.")
	controls.check_print_statements = _add_check_to_grid(style_grid, "Print Statements",
		"Debug print statements")
	controls.check_magic_numbers = _add_check_to_grid(style_grid, "Magic Numbers",
		"Hardcoded numbers")
	controls.check_commented_code = _add_check_to_grid(style_grid, "Commented Code",
		"Commented-out code blocks")
	controls.check_missing_types = _add_check_to_grid(style_grid, "Missing Types",
		"Variables without type hints")

	# Functions section
	_add_section_header(vbox, "Functions")
	var funcs_grid := _create_check_grid(vbox)
	controls.check_function_length = _add_check_to_grid(funcs_grid, "Long Functions",
		"Functions exceeding line limits")
	controls.check_parameters = _add_check_to_grid(funcs_grid, "Too Many Params",
		"Functions with too many parameters")
	controls.check_nesting = _add_check_to_grid(funcs_grid, "Deep Nesting",
		"Excessive nesting depth")
	controls.check_cyclomatic_complexity = _add_check_to_grid(funcs_grid, "High Complexity",
		"High cyclomatic complexity")
	controls.check_empty_functions = _add_check_to_grid(funcs_grid, "Empty Functions",
		"Functions with no implementation")
	controls.check_missing_return_type = _add_check_to_grid(funcs_grid, "Missing Return Type",
		"Public functions without return type")

	# Structure section
	_add_section_header(vbox, "Structure")
	var struct_grid := _create_check_grid(vbox)
	controls.check_file_length = _add_check_to_grid(struct_grid, "Long Files",
		"Files exceeding line limits")
	controls.check_god_class = _add_check_to_grid(struct_grid, "God Class",
		"Classes with too many members")
	controls.check_unused_variables = _add_check_to_grid(struct_grid, "Unused Variables",
		"Local variables never used")
	controls.check_unused_parameters = _add_check_to_grid(struct_grid, "Unused Parameters",
		"Function parameters never used")

	return card


# Helper to add a section header label
func _add_section_header(container: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
	container.add_child(label)


# Helper to create a 2-column grid for checkboxes
func _create_check_grid(container: VBoxContainer) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 4)
	container.add_child(grid)
	return grid


# Helper to add a checkbox to a grid
func _add_check_to_grid(grid: GridContainer, label_text: String, tooltip: String) -> CheckBox:
	var check := CheckBox.new()
	check.text = label_text
	check.tooltip_text = tooltip
	check.button_pressed = true  # Default to enabled
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(check)
	return check


# Create Analysis Limits collapsible card with spinboxes
func create_limits_card(controls: Dictionary) -> GDLintCollapsibleCard:
	var card := GDLintCollapsibleCard.new("Analysis Limits", "code_quality/ui/limits_collapsed")
	var vbox := card.get_content_container()

	# Reset All button row
	var reset_row := HBoxContainer.new()
	reset_row.add_theme_constant_override("separation", 8)
	vbox.add_child(reset_row)

	var reset_all_btn := Button.new()
	reset_all_btn.icon = _reset_icon
	reset_all_btn.text = "Reset All"
	reset_all_btn.tooltip_text = "Reset all limits to defaults"
	reset_all_btn.flat = true
	controls.reset_all_limits_btn = reset_all_btn
	reset_row.add_child(reset_all_btn)

	# Grid for spinboxes (6 columns: label, spin, reset, label, spin, reset)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)

	# Row 1: File lines soft/hard
	controls.max_lines_soft_spin = _add_spin_row(grid, "File Lines (warn):", 50, 1000, DEFAULT_FILE_LINES_SOFT, DEFAULT_FILE_LINES_SOFT)
	controls.max_lines_hard_spin = _add_spin_row(grid, "File Lines (crit):", 100, 2000, DEFAULT_FILE_LINES_HARD, DEFAULT_FILE_LINES_HARD)

	# Row 2: Function lines / complexity warning
	controls.max_func_lines_spin = _add_spin_row(grid, "Func Lines:", 10, 200, DEFAULT_FUNC_LINES, DEFAULT_FUNC_LINES)
	controls.max_complexity_spin = _add_spin_row(grid, "Complexity (warn):", 5, 50, DEFAULT_COMPLEXITY_WARN, DEFAULT_COMPLEXITY_WARN)

	# Row 3: Func lines critical / complexity critical
	controls.func_lines_crit_spin = _add_spin_row(grid, "Func Lines (crit):", 20, 300, DEFAULT_FUNC_LINES_CRIT, DEFAULT_FUNC_LINES_CRIT)
	controls.max_complexity_crit_spin = _add_spin_row(grid, "Complexity (crit):", 5, 50, DEFAULT_COMPLEXITY_CRIT, DEFAULT_COMPLEXITY_CRIT)

	# Row 4: Max params / nesting
	controls.max_params_spin = _add_spin_row(grid, "Max Params:", 2, 15, DEFAULT_MAX_PARAMS, DEFAULT_MAX_PARAMS)
	controls.max_nesting_spin = _add_spin_row(grid, "Max Nesting:", 2, 10, DEFAULT_MAX_NESTING, DEFAULT_MAX_NESTING)

	# Row 5: God class thresholds
	controls.god_class_funcs_spin = _add_spin_row(grid, "God Class Funcs:", 5, 50, DEFAULT_GOD_CLASS_FUNCS, DEFAULT_GOD_CLASS_FUNCS)
	controls.god_class_signals_spin = _add_spin_row(grid, "God Class Signals:", 3, 30, DEFAULT_GOD_CLASS_SIGNALS, DEFAULT_GOD_CLASS_SIGNALS)

	return card


# Create header bar with title and links (non-collapsible)
func create_header_bar() -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)

	# Title: "GDScript Linter" in accent color
	var title := Label.new()
	title.text = "GDScript Linter"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(0.4, 0.75, 1.0))
	hbox.add_child(title)

	# Subtitle: " - Code Quality Analyzer for GDScript" in muted color
	var subtitle := Label.new()
	subtitle.text = " -   Code Quality Analyzer for GDScript"
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	hbox.add_child(subtitle)

	# Spacer to push links to the right
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	# Links
	var link_data := [
		["Discord", "https://discord.gg/9GnrTKXGfq"],
		["GitHub", "https://github.com/graydwarf/godot-gdscript-linter"],
		["More Tools", "https://poplava.itch.io"]
	]
	for data in link_data:
		var btn := Button.new()
		btn.text = data[0]
		btn.flat = true
		btn.tooltip_text = data[1]
		btn.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(0.7, 0.85, 1.0))
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var url: String = data[1]
		btn.pressed.connect(func(): OS.shell_open(url))
		hbox.add_child(btn)

	return hbox


# Helper to create a checkbox and add it to a container
func _create_checkbox(label_text: String, container: HBoxContainer, tooltip: String = "") -> CheckBox:
	var check := CheckBox.new()
	check.text = label_text
	if tooltip != "":
		check.tooltip_text = tooltip
	container.add_child(check)
	return check


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


# Create Help collapsible card
func _create_help_card() -> GDLintCollapsibleCard:
	var card := GDLintCollapsibleCard.new("Help", "code_quality/ui/help_collapsed")
	_help_card_builder.create_card_content(card.get_content_container())
	return card
