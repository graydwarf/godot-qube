# Godot Qube - Help Card UI Builder
# https://poplava.itch.io
@tool
extends RefCounted
class_name QubeHelpCardBuilder
## Creates the Help section card with ignore rules, CLI usage, and shortcuts


# Create Help card (returns content to be added to a collapsible card)
func create_card_content(container: VBoxContainer) -> void:
	_add_ignore_rules_section(container)
	_add_separator(container)
	_add_cli_section(container)
	_add_separator(container)
	_add_shortcuts_section(container)
	_add_separator(container)
	_add_license_section(container)


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
	desc.text = " - " + description
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.55, 0.57, 0.6))
	hbox.add_child(desc)


func _add_code_block(parent: VBoxContainer, code: String) -> void:
	var code_label := Label.new()
	code_label.text = code
	code_label.add_theme_font_size_override("font_size", 12)
	code_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.6))
	code_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(code_label)


func _add_ignore_rules_section(parent: VBoxContainer) -> void:
	_add_section_header(parent, "Ignore Rules", "Suppress warnings for intentional code patterns")

	# Summary table
	_add_ignore_table(parent)

	# Examples for each directive
	_add_thin_separator(parent)
	_add_ignore_example(parent, "qube:ignore-file",
		"# qube:ignore-file\n# qube:ignore-file:file-length,long-function")

	_add_thin_separator(parent)
	_add_ignore_example(parent, "qube:ignore-below",
		"# qube:ignore-below\n# qube:ignore-below:magic-number")

	_add_thin_separator(parent)
	_add_ignore_example(parent, "qube:ignore-function",
		"# qube:ignore-function\nfunc _debug(): ...\n\n# qube:ignore-function:print-statement\nfunc _log(): ...")

	_add_thin_separator(parent)
	_add_ignore_example(parent, "qube:ignore-block-start/end",
		"# qube:ignore-block-start:magic-number\nvar x = 42\nvar y = 100\n# qube:ignore-block-end")

	_add_thin_separator(parent)
	_add_ignore_example(parent, "qube:ignore-next-line",
		"# qube:ignore-next-line\nvar magic = 42")

	_add_thin_separator(parent)
	_add_ignore_example(parent, "qube:ignore",
		"var magic = 42  # qube:ignore\nvar x = 100  # qube:ignore:magic-number")


func _add_ignore_table(parent: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 2)
	parent.add_child(grid)

	var directives := [
		["qube:ignore-file", "Entire file"],
		["qube:ignore-below", "Line to EOF"],
		["qube:ignore-function", "Entire function"],
		["qube:ignore-block-start/end", "Code block"],
		["qube:ignore-next-line", "Next line"],
		["qube:ignore", "Same line"],
	]

	for entry in directives:
		var directive_label := Label.new()
		directive_label.text = entry[0]
		directive_label.add_theme_font_size_override("font_size", 12)
		directive_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.6))
		grid.add_child(directive_label)

		var scope_label := Label.new()
		scope_label.text = entry[1]
		scope_label.add_theme_font_size_override("font_size", 12)
		scope_label.add_theme_color_override("font_color", Color(0.55, 0.57, 0.6))
		grid.add_child(scope_label)


func _add_ignore_example(parent: VBoxContainer, directive: String, code: String) -> void:
	# Directive name as mini-header
	var header := Label.new()
	header.text = directive
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.7, 0.8, 0.6))
	parent.add_child(header)

	# Code example
	var code_label := Label.new()
	code_label.text = code
	code_label.add_theme_font_size_override("font_size", 11)
	code_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	parent.add_child(code_label)


func _add_thin_separator(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	sep.add_theme_color_override("separator", Color(0.25, 0.28, 0.32, 0.4))
	parent.add_child(sep)


func _add_cli_section(parent: VBoxContainer) -> void:
	_add_section_header(parent, "CLI Usage", "Run analysis from command line")

	# Output formats table
	_add_cli_table(parent, "Output Formats", [
		["--clickable", "Godot Output panel (default)"],
		["--json", "JSON format"],
		["--html -o file.html", "HTML report"],
	])

	# Exit codes table
	_add_cli_table(parent, "Exit Codes", [
		["0", "No issues"],
		["1", "Warnings only"],
		["2", "Critical issues"],
	])

	# Examples
	_add_thin_separator(parent)
	_add_cli_example(parent, "Basic scan",
		"godot --headless --script res://addons/godot-qube/analyzer/analyze-cli.gd")

	_add_thin_separator(parent)
	_add_cli_example(parent, "JSON output",
		"godot --headless --script res://addons/godot-qube/analyzer/analyze-cli.gd -- --json")

	_add_thin_separator(parent)
	_add_cli_example(parent, "HTML report",
		"godot --headless --script res://addons/godot-qube/analyzer/analyze-cli.gd -- --html -o report.html")

	_add_thin_separator(parent)
	_add_cli_example(parent, "Scan external project",
		"godot --headless --script res://addons/godot-qube/analyzer/analyze-cli.gd -- --path \"C:/my/project\"")


func _add_cli_table(parent: VBoxContainer, title: String, entries: Array) -> void:
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 12)
	title_label.add_theme_color_override("font_color", Color(0.7, 0.72, 0.75))
	parent.add_child(title_label)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 2)
	parent.add_child(grid)

	for entry in entries:
		var key_label := Label.new()
		key_label.text = entry[0]
		key_label.add_theme_font_size_override("font_size", 12)
		key_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.6))
		grid.add_child(key_label)

		var value_label := Label.new()
		value_label.text = entry[1]
		value_label.add_theme_font_size_override("font_size", 12)
		value_label.add_theme_color_override("font_color", Color(0.55, 0.57, 0.6))
		grid.add_child(value_label)


func _add_cli_example(parent: VBoxContainer, title: String, command: String) -> void:
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 12)
	title_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.6))
	parent.add_child(title_label)

	var cmd_label := Label.new()
	cmd_label.text = command
	cmd_label.add_theme_font_size_override("font_size", 11)
	cmd_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	cmd_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(cmd_label)


func _add_shortcuts_section(parent: VBoxContainer) -> void:
	_add_section_header(parent, "Claude Code Shortcuts", "When Claude Code integration is enabled")

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)

	var shortcuts := [
		["Click", "Plan mode (safe, reviews first)"],
		["Shift+Click", "Immediate mode (fixes directly)"],
		["Right-click", "Context menu with options"]
	]

	for shortcut in shortcuts:
		var key_label := Label.new()
		key_label.text = shortcut[0]
		key_label.add_theme_font_size_override("font_size", 12)
		key_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.6))
		grid.add_child(key_label)

		var desc_label := Label.new()
		desc_label.text = shortcut[1]
		desc_label.add_theme_font_size_override("font_size", 12)
		desc_label.add_theme_color_override("font_color", Color(0.55, 0.57, 0.6))
		grid.add_child(desc_label)


func _add_license_section(parent: VBoxContainer) -> void:
	var license_lbl := Label.new()
	license_lbl.text = "MIT License - Copyright (c) 2025 Poplava"
	license_lbl.add_theme_font_size_override("font_size", 11)
	license_lbl.add_theme_color_override("font_color", Color(0.45, 0.47, 0.5))
	parent.add_child(license_lbl)
