# GDScript Linter - Static code quality analyzer
# https://poplava.itch.io
@tool
extends EditorPlugin
## Adds a dock for static analysis with clickable navigation

var dock: Control


func _enter_tree() -> void:
	dock = preload("res://addons/gdscript-linter/dock.tscn").instantiate()
	add_control_to_bottom_panel(dock, "Code Quality")


func _exit_tree() -> void:
	if dock:
		remove_control_from_bottom_panel(dock)
		dock.queue_free()
