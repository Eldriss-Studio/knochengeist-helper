@tool
extends RefCounted
# The Godot names in an answer that aren't in the person's own Godot: a made-up class, or a method
# from an older Godot. The same rules as the answer evals' "names exist" check, which were tuned on
# real answers so that the answer's own variables, node paths and strings don't count.

const NOT_CLASSES := ["GodotSteam", "SteamPipe", "Steamworks", "GDScript", "GDExtension", "GDShader", "FileSystem", "GitHub", "JavaScript", "TypeScript", "OpenGL", "DirectX", "WebGL", "VSync", "MacOS", "PlayStation", "YouTube", "AssetLib"]
const CLASS_LIKE := "\\b[A-Z][A-Za-z0-9]*(?:[a-z0-9][A-Z]|[0-9])[A-Za-z0-9]*\\b"
const MEMBER_LIKE := "\\b_?[a-z][a-z0-9]*(?:_[a-z0-9]+)+\\b|\\b_[a-z][a-z0-9]*\\b"


## The names in the answer that the reference doesn't know, in the order they appear. `knows` is
## Callable(name) -> bool.
static func missing(answer: String, question: String, knows: Callable) -> PackedStringArray:
	var quoted := _all("[\"']([A-Za-z_]\\w*)[\"']", answer, 1)
	var defined := _all("(?i)\\b(?:func|var|const|signal|class_name|enum|name it|named|called|call it)\\s+[\"']?([A-Za-z_]\\w*)", answer, 1)
	var asked := _all(CLASS_LIKE, question, 0)
	asked.append_array(_all(MEMBER_LIKE, question, 0))
	var node_paths := _all("[$%]([A-Za-z_]\\w*)", answer, 1)
	var own := func(name: String) -> bool:
		return asked.has(name) or asked.has(name.trim_suffix("s")) or quoted.has(name) or defined.has(name) or name.begins_with("_on_") or name.begins_with("ui_")
	var is_class := func(name: String) -> bool:
		return knows.call(name) or knows.call(name.trim_suffix("s")) or knows.call(name + "2D") or knows.call(name + "3D")
	var plain := _words(answer)
	var out := PackedStringArray()
	for name in _all(CLASS_LIKE, plain, 0):
		if not own.call(name) and not NOT_CLASSES.has(name) and not node_paths.has(name) and not is_class.call(name) and not out.has(name):
			out.append(name)
	# the answer's own variables: what something is read off (my_scene.instantiate()), what it awaits,
	# names read off one of them (some_node.some_signal), and the plain names passed in a call
	var variables := _all("\\b(_?[a-z]\\w*)\\.(?=[a-z_])", answer, 1)
	variables.append_array(_all("\\bawait\\s+(_?[a-z]\\w*)\\b(?!\\.[a-z_])", answer, 1))
	for found in RegEx.create_from_string("\\b(_?[a-z]\\w*)\\.(_?[a-z]\\w*)").search_all(answer):
		if not knows.call(found.get_string(1)) and found.get_string(1) != "self":
			variables.append(found.get_string(2))
	for found in RegEx.create_from_string("\\(([^()]*)\\)").search_all(answer):
		for arg in found.get_string(1).split(","):
			if RegEx.create_from_string("^\\s*_?[a-z]\\w*\\s*$").search(arg):
				variables.append(arg.strip_edges())
	for name in _all(MEMBER_LIKE, plain, 0):
		if not own.call(name) and not variables.has(name) and not knows.call(name) and not out.has(name):
			out.append(name)
	return out


# The answer without paths, project settings, file names and strings: those name no class.
static func _words(text: String) -> String:
	text = RegEx.create_from_string("\\S*/\\S*").sub(text, " ", true)
	text = RegEx.create_from_string("\\b\\w+\\.(?:gd|tscn|scn|tres|res|png|jpg|svg|wav|ogg|mp3|glb|gltf|obj)\\b").sub(text, " ", true)
	return RegEx.create_from_string("[\"'][^\"'\\n]*[\"']").sub(text, " ", true)


static func _all(pattern: String, text: String, group: int) -> PackedStringArray:
	var out := PackedStringArray()
	for found in RegEx.create_from_string(pattern).search_all(text):
		out.append(found.get_string(group))
	return out
