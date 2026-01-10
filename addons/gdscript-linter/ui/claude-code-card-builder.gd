# GDScript Linter - Claude Code Card UI Builder
# https://poplava.itch.io
@tool
extends RefCounted
class_name GDLintClaudeCodeCardBuilder
## Creates the Claude Code integration settings card

const DEFAULT_COMMAND := "claude --permission-mode plan"

var _reset_icon: Texture2D


func _init(reset_icon: Texture2D) -> void:
	_reset_icon = reset_icon


# Create Claude Code settings collapsible card
func create_card(controls: Dictionary) -> GDLintCollapsibleCard:
	var card := GDLintCollapsibleCard.new("Claude Code Integration", "code_quality/ui/claude_collapsed")
	var vbox := card.get_content_container()

	_add_enable_section(vbox, controls)
	_add_separator(vbox)
	_add_command_section(vbox, controls)
	_add_separator(vbox)
	_add_instructions_section(vbox, controls)

	return card


func _add_separator(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.3, 0.35, 0.4, 0.5))
	parent.add_child(sep)


func _add_section_header(parent: VBoxContainer, title: String, description: String) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	parent.add_child(hbox)

	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.8, 0.82, 0.85))
	hbox.add_child(header)

	var desc := Label.new()
	desc.text = " -   " + description
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.55, 0.57, 0.6))
	hbox.add_child(desc)


func _add_enable_section(parent: VBoxContainer, controls: Dictionary) -> void:
	_add_section_header(parent, "Enable", "Show Claude buttons in issue list")

	controls.claude_enabled_check = CheckBox.new()
	controls.claude_enabled_check.text = "Enable Claude Code buttons"
	parent.add_child(controls.claude_enabled_check)

	var desc := Label.new()
	desc.text = "Adds clickable icons next to issues to launch Claude Code with context."
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.45, 0.47, 0.5))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(desc)


func _add_command_section(parent: VBoxContainer, controls: Dictionary) -> void:
	_add_section_header(parent, "Launch Command", "CLI command to start Claude Code")

	var cmd_hbox := HBoxContainer.new()
	cmd_hbox.add_theme_constant_override("separation", 8)
	parent.add_child(cmd_hbox)

	controls.claude_command_edit = LineEdit.new()
	controls.claude_command_edit.placeholder_text = DEFAULT_COMMAND
	controls.claude_command_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var cmd_border_style := StyleBoxFlat.new()
	cmd_border_style.bg_color = Color(0.09, 0.11, 0.14)  # Input area - darkest
	cmd_border_style.border_color = Color(0.3, 0.32, 0.35)
	cmd_border_style.set_border_width_all(1)
	cmd_border_style.set_corner_radius_all(2)
	cmd_border_style.content_margin_left = 8
	controls.claude_command_edit.add_theme_stylebox_override("normal", cmd_border_style)

	cmd_hbox.add_child(controls.claude_command_edit)

	controls.claude_reset_button = Button.new()
	controls.claude_reset_button.icon = _reset_icon
	controls.claude_reset_button.tooltip_text = "Reset to default"
	controls.claude_reset_button.flat = true
	controls.claude_reset_button.custom_minimum_size = Vector2(16, 16)
	cmd_hbox.add_child(controls.claude_reset_button)

	var hint := Label.new()
	hint.text = "Issue context is passed automatically. Add CLI flags as needed (e.g. --verbose)."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.45, 0.47, 0.5))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(hint)


func _add_instructions_section(parent: VBoxContainer, controls: Dictionary) -> void:
	# Header row with reset button
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	parent.add_child(header_row)

	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 0)
	header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header_hbox)

	var header := Label.new()
	header.text = "Custom Instructions"
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.8, 0.82, 0.85))
	header_hbox.add_child(header)

	var desc := Label.new()
	desc.text = " -   Extra context appended to prompts"
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.55, 0.57, 0.6))
	header_hbox.add_child(desc)

	controls.claude_instructions_reset_button = Button.new()
	controls.claude_instructions_reset_button.icon = _reset_icon
	controls.claude_instructions_reset_button.tooltip_text = "Reset to default"
	controls.claude_instructions_reset_button.flat = true
	controls.claude_instructions_reset_button.custom_minimum_size = Vector2(16, 16)
	header_row.add_child(controls.claude_instructions_reset_button)

	controls.claude_instructions_edit = TextEdit.new()
	controls.claude_instructions_edit.placeholder_text = "Add project-specific guidelines, coding standards, or preferences..."
	controls.claude_instructions_edit.custom_minimum_size = Vector2(0, 120)
	controls.claude_instructions_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.claude_instructions_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY

	var border_style := StyleBoxFlat.new()
	border_style.bg_color = Color(0.09, 0.11, 0.14)  # Input area - darkest
	border_style.border_color = Color(0.3, 0.32, 0.35)
	border_style.set_border_width_all(1)
	border_style.set_corner_radius_all(2)
	border_style.set_content_margin_all(4)
	border_style.content_margin_left = 8
	controls.claude_instructions_edit.add_theme_stylebox_override("normal", border_style)

	parent.add_child(controls.claude_instructions_edit)
