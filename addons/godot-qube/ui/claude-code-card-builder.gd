# Godot Qube - Claude Code Card UI Builder
# https://poplava.itch.io
@tool
extends RefCounted
class_name QubeClaudeCodeCardBuilder
## Creates the Claude Code integration settings card

const DEFAULT_COMMAND := "claude --permission-mode plan"

var _reset_icon: Texture2D


func _init(reset_icon: Texture2D) -> void:
	_reset_icon = reset_icon


# Create Claude Code settings collapsible card
func create_card(controls: Dictionary) -> QubeCollapsibleCard:
	var card := QubeCollapsibleCard.new("Claude Code Integration", "code_quality/ui/claude_collapsed")
	var vbox := card.get_content_container()

	_add_enable_checkbox(vbox, controls)
	_add_description(vbox)
	_add_command_section(vbox, controls)
	_add_hint(vbox)
	_add_instructions_section(vbox, controls)

	return card


func _add_enable_checkbox(parent: VBoxContainer, controls: Dictionary) -> void:
	controls.claude_enabled_check = CheckBox.new()
	controls.claude_enabled_check.text = "Enable Claude Code buttons"
	parent.add_child(controls.claude_enabled_check)


func _add_description(parent: VBoxContainer) -> void:
	var desc := Label.new()
	desc.text = "Adds Claude Code button to launch directly into plan mode with issue context."
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color(0.5, 0.52, 0.55))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(desc)


func _add_command_section(parent: VBoxContainer, controls: Dictionary) -> void:
	var cmd_label := Label.new()
	cmd_label.text = "Launch Command:"
	cmd_label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.75))
	parent.add_child(cmd_label)

	var cmd_hbox := HBoxContainer.new()
	cmd_hbox.add_theme_constant_override("separation", 8)
	parent.add_child(cmd_hbox)

	controls.claude_command_edit = LineEdit.new()
	controls.claude_command_edit.placeholder_text = DEFAULT_COMMAND
	controls.claude_command_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmd_hbox.add_child(controls.claude_command_edit)

	controls.claude_reset_button = Button.new()
	controls.claude_reset_button.icon = _reset_icon
	controls.claude_reset_button.tooltip_text = "Reset to default"
	controls.claude_reset_button.flat = true
	controls.claude_reset_button.custom_minimum_size = Vector2(16, 16)
	cmd_hbox.add_child(controls.claude_reset_button)


func _add_hint(parent: VBoxContainer) -> void:
	var hint := Label.new()
	hint.text = "Issue context is passed automatically. Add CLI flags as needed (e.g. --verbose)."
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.45, 0.47, 0.5))
	parent.add_child(hint)


func _add_instructions_section(parent: VBoxContainer, controls: Dictionary) -> void:
	var instructions_label := Label.new()
	instructions_label.text = "Custom Instructions (optional):"
	instructions_label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.75))
	parent.add_child(instructions_label)

	controls.claude_instructions_edit = TextEdit.new()
	controls.claude_instructions_edit.placeholder_text = "Add extra instructions to append to the prompt..."
	controls.claude_instructions_edit.custom_minimum_size = Vector2(0, 120)
	controls.claude_instructions_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.claude_instructions_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	parent.add_child(controls.claude_instructions_edit)
