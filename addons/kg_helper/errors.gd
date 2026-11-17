@tool
extends RefCounted
# The errors a run of his game printed, read from Godot's Debugger > Errors tab. Godot marks each
# error row with the meta "_is_error" and gives it the script's [file, line] and a tooltip with the
# details, the same in every editor language (script_editor_debugger.cpp, Godot 4.7).

var trees: Array = []              # the Trees that can hold error rows, found once and kept


## Every error row now in the Errors tab, oldest first: { message, file, line, details }.
func all() -> Array:
	if trees.is_empty() or not trees.all(func(t): return is_instance_valid(t)):
		trees = EditorInterface.get_base_control().find_children("*", "Tree", true, false).filter(func(t): return (t as Tree).columns == 2 and (t as Tree).hide_root)
	var out: Array = []
	for tree in trees:
		var root: TreeItem = (tree as Tree).get_root()
		if root == null:
			continue
		for row in root.get_children():
			if not row.has_meta("_is_error"):
				continue                   # warnings stay in the Debugger
			var where = row.get_metadata(0)
			var file: String = str(where[0]) if where is Array and where.size() > 1 else ""
			var line: int = int(where[1]) if where is Array and where.size() > 1 else 0
			var details := row.get_tooltip_text(1)
			out.append({"message": row.get_text(1), "file": file, "line": line, "details": details if details != "" else row.get_text(1)})
	return out


## The lines around the one the error names, numbered, that line marked with ">".
static func lines_around(file: String, line: int, around := 5) -> String:
	if not file.begins_with("res://") or not FileAccess.file_exists(file) or line <= 0:
		return ""
	var lines := FileAccess.get_file_as_string(file).split("\n")
	var out := PackedStringArray()
	for i in range(maxi(1, line - around), mini(lines.size(), line + around) + 1):
		out.append("%s%d  %s" % ["> " if i == line else "  ", i, lines[i - 1]])
	return "\n".join(out)
