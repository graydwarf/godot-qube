# Godot Qube - Settings Card UI Builder
# https://poplava.itch.io
@tool
extends RefCounted
class_name QubeSettingsCardBuilder
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
const CLAUDE_CODE_DEFAULT_COMMAND := "claude --permission-mode plan"

var _reset_icon: Texture2D


func _init(reset_icon: Texture2D) -> void:
	_reset_icon = reset_icon


# Creates the standard card style used by all settings cards
static func create_card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.17, 0.22, 0.9)
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

	# Create all cards
	cards_vbox.add_child(create_display_options_card(controls))
	cards_vbox.add_child(create_limits_card(controls))
	cards_vbox.add_child(create_claude_code_card(controls))
	cards_vbox.add_child(create_about_card())

	settings_panel.add_child(scroll)
	settings_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL


# Create Display Options card with checkboxes
func create_display_options_card(controls: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", create_card_style())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	# Header
	var header := Label.new()
	header.text = "Display Options"
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	vbox.add_child(header)

	# First row of checkboxes
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	vbox.add_child(hbox)

	controls.show_issues_check = _create_checkbox("Show Issues", hbox)
	controls.show_debt_check = _create_checkbox("Show Debt", hbox)
	controls.show_json_export_check = _create_checkbox("Show JSON Export", hbox)
	controls.show_html_export_check = _create_checkbox("Show HTML Export", hbox)
	controls.show_ignored_check = _create_checkbox("Show Ignored", hbox, "Show ignored issues in a separate section")

	# Second row for scanning options
	var hbox2 := HBoxContainer.new()
	hbox2.add_theme_constant_override("separation", 15)
	vbox.add_child(hbox2)

	controls.respect_gdignore_check = _create_checkbox("Respect .gdignore", hbox2,
		"Skip directories containing .gdignore files (matches Godot editor behavior)")
	controls.scan_addons_check = _create_checkbox("Scan addons/", hbox2,
		"Include addons/ folder in code quality scans (disabled by default)")

	return card


# Create Analysis Limits card with spinboxes
func create_limits_card(controls: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", create_card_style())

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
	controls.reset_all_limits_btn = reset_all_btn
	header_row.add_child(reset_all_btn)

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


# Create Claude Code settings card
func create_claude_code_card(controls: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", create_card_style())

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
	controls.claude_enabled_check = CheckBox.new()
	controls.claude_enabled_check.text = "Enable Claude Code buttons"
	vbox.add_child(controls.claude_enabled_check)

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

	controls.claude_command_edit = LineEdit.new()
	controls.claude_command_edit.placeholder_text = CLAUDE_CODE_DEFAULT_COMMAND
	controls.claude_command_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmd_hbox.add_child(controls.claude_command_edit)

	controls.claude_reset_button = Button.new()
	controls.claude_reset_button.icon = _reset_icon
	controls.claude_reset_button.tooltip_text = "Reset to default"
	controls.claude_reset_button.flat = true
	controls.claude_reset_button.custom_minimum_size = Vector2(16, 16)
	cmd_hbox.add_child(controls.claude_reset_button)

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
	controls.claude_instructions_edit = TextEdit.new()
	controls.claude_instructions_edit.placeholder_text = "Add extra instructions to append to the prompt..."
	controls.claude_instructions_edit.custom_minimum_size = Vector2(0, 60)
	controls.claude_instructions_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(controls.claude_instructions_edit)

	return card


# Create About section card
func create_about_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", create_card_style())

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
