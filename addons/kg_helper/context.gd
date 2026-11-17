@tool
extends EditorContextMenuPlugin
# "Ask the ghost about this" in one of Godot's right-click menus. Each slot names what was picked in
# its own way; asking is the helper's.

signal picked(kind: String, what: Dictionary)

var slot := 0
var icon: Texture2D
var script_path := ""


func _init(for_slot: int, ghost: Texture2D) -> void:
	slot = for_slot
	icon = ghost


func _popup_menu(paths: PackedStringArray) -> void:
	var open_script := EditorInterface.get_script_editor().get_current_script() if slot == CONTEXT_SLOT_SCRIPT_EDITOR_CODE else null
	script_path = open_script.resource_path if open_script else ""
	add_context_menu_item("Ask the ghost about this", _chosen, icon)


func _chosen(from) -> void:
	match slot:
		CONTEXT_SLOT_SCENE_TREE:
			var nodes: Array = from if from is Array else [from]
			if not nodes.is_empty() and nodes[0] is Node:
				var node: Node = nodes[0]
				var root := EditorInterface.get_edited_scene_root()
				picked.emit("node", {"name": str(node.name), "type": node.get_class(), "path": str(root.get_path_to(node)) if root else str(node.name)})
		CONTEXT_SLOT_FILESYSTEM:
			var files: Array = Array(from) if from is PackedStringArray or from is Array else [str(from)]
			if not files.is_empty():
				picked.emit("file", {"path": str(files[0])})
		CONTEXT_SLOT_SCRIPT_EDITOR_CODE:
			if from is CodeEdit:
				var code := from as CodeEdit
				var lines := code.get_selected_text() if code.has_selection() else code.get_line(code.get_caret_line())
				picked.emit("code", {"path": script_path, "code": lines})
		CONTEXT_SLOT_INSPECTOR_PROPERTY:
			var object = EditorInterface.get_inspector().get_edited_object()
			var property := str(from[0]) if from is Array and not from.is_empty() else str(from)
			picked.emit("property", {"property": property, "class": object.get_class() if object else ""})
