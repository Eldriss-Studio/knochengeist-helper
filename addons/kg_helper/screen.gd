@tool
extends RefCounted
# What's on screen in the editor: every button, list row, text field and Inspector property he could be
# pointed at, by a stable id, with how to find each one on screen now. The plugin reads it before a
# question and during a walk-through; the walk-through points at what it found.

var places := {}                 # target id -> Callable giving its rect on screen now, or null
var labels := {}                 # target id -> what to call it
var wins := {}                   # target id -> the window it's in
var fields := {}                 # target id -> its text field (a weak reference)
var nodes := {}                  # target id -> the control or tree it's in (a weak reference)


# The window he's working in: a dialog when one is open (Create New Node, a file dialog), else the editor.
static func front_window() -> Window:
	var main := EditorInterface.get_base_control().get_window()
	# The open windows, from Godot itself: drawn inside the editor's window (single-window mode, or no
	# display), or windows of their own. Searching the editor's 18,000 controls for them took 6 ms a look.
	var open: Array = []
	for w in main.get_embedded_subwindows() + _own_windows(main):
		if w is AcceptDialog and (w as Window).visible:
			open.append(w)
	if open.size() == 1:
		return open[0]
	if open.is_empty():
		return main
	var front := main             # two dialogs at once (one opened from the other): the later one in the tree
	for w in main.find_children("*", "AcceptDialog", true, false):
		if (w as Window).visible:
			front = w
	return front


static func _own_windows(main: Window) -> Array:
	var found := []
	for id in DisplayServer.get_window_list():
		var w = instance_from_id(DisplayServer.window_get_attached_instance_id(id))
		if w is Window and w != main:
			found.append(w)
	return found


## Reads the screen now, leaving out the helper's own button and card.
func read(project: String, own_button: Control, ask_box: Control) -> Dictionary:
	places = {}
	labels = {}
	wins = {}
	fields = {}
	nodes = {}
	var targets: Array = []
	var base := EditorInterface.get_base_control()
	var front := front_window()
	var root: Node = base if front == base.get_window() else front
	var screen := Rect2(Vector2.ZERO, front.size)
	var here := func(c: Control) -> bool: return c.is_visible_in_tree() and c.get_window() == front and screen.intersects(c.get_global_rect())
	var shown: Array = []
	_shown(root, shown)          # one walk, not one per kind: the editor holds some 18,000 controls, most of them hidden
	for b in shown.filter(func(c): return c is BaseButton):
		if b == own_button or (b as BaseButton).disabled:
			continue              # not the helper's own button, nor one that can't be pressed
		var found: BaseButton = b
		if not here.call(found) or (ask_box and ask_box.is_ancestor_of(found)):
			continue
		var name := found.tooltip_text.get_slice("\n", 0).strip_edges()
		if name == "" and found is Button:
			name = (found as Button).text.strip_edges()
		name = name.replace("]", ")")
		if name == "":
			continue
		_add(targets, "button:" + name, "the \"%s\" button" % name, _control_place(found), front, found)
	for t in shown.filter(func(c): return c is Tree):
		var tree: Tree = t
		if not here.call(tree):
			continue
		var in_scene_dock := false
		var up := tree.get_parent()
		while up and not in_scene_dock and not (up is Window):
			in_scene_dock = up.get_class() == "SceneTreeDock"
			up = up.get_parent()
		var inside := tree.get_global_rect()
		var item := tree.get_root()
		var listed := 0
		while item and listed < 80:
			var row := item.get_text(0).replace("]", ")")
			if row != "" and item.is_visible_in_tree():
				var at: Vector2 = inside.position + tree.get_item_area_rect(item).position     # already where it is now, scrolling included
				if in_scene_dock:
					_add(targets, "row:" + row, "the %s node in the Scene dock" % row, _row_place(tree, row), front, tree)
					listed += 1
				elif at.y >= inside.position.y and at.y < inside.end.y:
					_add(targets, "item:" + row, "\"%s\" in the list" % row, _row_place(tree, row), front, tree)
					listed += 1
			item = item.get_next_in_tree()
	for f in shown.filter(func(c): return c is LineEdit):
		var field: LineEdit = f
		if field.secret:
			continue
		var hint := field.placeholder_text.strip_edges().replace("]", ")")
		if hint == "" and front != base.get_window():
			hint = "Search"           # a dialog's unnamed box is its search box
		if here.call(field) and field.editable and hint != "" and not (ask_box and ask_box.is_ancestor_of(field)):
			_add(targets, "field:" + hint, "the \"%s\" text field" % hint, _control_place(field), front, field)
			fields["field:" + hint] = weakref(field)
	for p in shown.filter(func(c): return c is EditorProperty):
		var prop: EditorProperty = p
		if here.call(prop):
			var label := prop.label if prop.label != "" else str(prop.get_edited_property())
			_add(targets, "prop:" + str(prop.get_edited_property()), "the %s property in the Inspector" % label, _control_place(prop), front, prop)
	var scene := EditorInterface.get_edited_scene_root()
	var selected := EditorInterface.get_selection().get_selected_nodes()
	return {
		"project": project,
		"scene": scene.scene_file_path if scene else "",
		"selected": str(selected[0].name) if selected.size() > 0 else "",
		"window": front.title if front != base.get_window() else "",
		"targets": targets,
	}


# Every shown control under `node`, in tree order. A hidden control's children are hidden too, so its
# branch is skipped; so is any other window (a dialog is read on its own when it's in front).
static func _shown(node: Node, into: Array) -> void:
	for child in node.get_children(true):
		if child is Window or (child is CanvasItem and not (child as CanvasItem).visible):
			continue
		if child is Control:
			into.append(child)
		_shown(child, into)


func _add(targets: Array, id: String, label: String, place: Callable, win: Window, node: Object) -> void:
	if id.ends_with(":") and id.count(":") == 1:
		return                    # a thing with no name: the app refuses a whole report over one such id
	if places.has(id):
		return                    # the first one on screen wins
	places[id] = place
	wins[id] = win
	nodes[id] = weakref(node)
	labels[id] = label
	targets.append({"id": id, "label": label})


func _control_place(c: Control) -> Callable:
	var ref := weakref(c)
	return func():
		var it = ref.get_ref()
		return it.get_global_rect() if it and it.is_visible_in_tree() else null


func _row_place(tree: Tree, row: String) -> Callable:
	var ref := weakref(tree)
	return func():
		var t = ref.get_ref()
		if not t or not t.is_visible_in_tree():
			return null
		var item: TreeItem = t.get_root()
		while item:
			if item.get_text(0) == row:
				var a: Rect2 = t.get_item_area_rect(item)
				var at: Vector2 = t.get_global_rect().position + a.position
				return Rect2(at, Vector2(t.size.x, a.size.y))
			item = item.get_next_in_tree()
		return null
