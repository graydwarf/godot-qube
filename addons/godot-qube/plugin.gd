@tool
extends EditorPlugin
## Godot Qube Plugin - Adds a dock for static analysis with clickable navigation

var dock: Control


func _enter_tree() -> void:
	dock = preload("res://addons/godot-qube/dock.tscn").instantiate()
	add_control_to_bottom_panel(dock, "Godot Qube")


func _exit_tree() -> void:
	if dock:
		remove_control_from_bottom_panel(dock)
		dock.queue_free()
