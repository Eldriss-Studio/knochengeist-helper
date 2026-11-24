@tool
extends RefCounted
# Where a walk step's thing is when it isn't on screen: in a closed menu, on a tab that isn't open,
# in a folded Inspector section. The walk rings the way in (the menu, the tab, the section) and he
# opens it himself; then the thing shows and the walk rings it. Each kind of hiding place is asked in
# turn; the first that knows the thing answers.

const Screen := preload("screen.gd")
const MENU := "menu"          # a closed menu's title: the way in
const ITEM := "item"          # an open menu's item: the step itself
const TAB := "tab"
const SECTION := "section"

## { "kind": MENU | ITEM | TAB | SECTION, "place": Callable giving its rect now (or null),
##   "name": what it's called, "menu": the PopupMenu, "item": the item's id and "index" its row for menu
##   steps, "native": the menu is in the Mac's own menu bar, where nothing can be drawn, "section": the
##   folded section }. Finding it changes nothing on screen: show() does, when it's rung.
static func way_in(id: String) -> Dictionary:
	var found := _menu(id)
	if found.is_empty():
		found = _tab(id)
	if found.is_empty():
		found = _hiding(id)
	return found


## Scrolls a thing into view in the scrolled list it's in (the Inspector), if it's out of sight.
static func into_view(thing: Control) -> void:
	var up := thing.get_parent()
	while up and not (up is ScrollContainer):
		up = up.get_parent()
	if up and not (up as Control).get_global_rect().encloses(thing.get_global_rect()):
		(up as ScrollContainer).ensure_control_visible(thing)


## Gets a way in ready to be rung: lights the menu item, or scrolls the section into view.
static func show(way: Dictionary) -> void:
	if way.get("kind") == ITEM:
		(way["menu"] as PopupMenu).set_focused_item(way["index"])      # lit up the way the keys would light it
	elif way.get("kind") == SECTION:
		into_view(way["section"])


# "New Scene", "new scene." and "Open Scene..." / "Open Scene…" as Godot writes its menu items.
static func _same(a: String, b: String) -> bool:
	var tidy := func(s: String) -> String: return s.to_lower().strip_edges().trim_suffix("…").trim_suffix(".").strip_edges()
	return tidy.call(a) == tidy.call(b)


# "menu:Scene > New Scene": the menu bar's Scene menu, and its New Scene item.
static func _menu(id: String) -> Dictionary:
	if not id.begins_with("menu:") or not id.contains(">"):
		return {}
	var path := id.trim_prefix("menu:")
	var menu_name := path.get_slice(">", 0).strip_edges()
	var item_name := path.substr(path.find(">") + 1).strip_edges()
	for found in EditorInterface.get_base_control().find_children("*", "MenuBar", true, false):
		var bar := found as MenuBar
		for i in bar.get_menu_count():
			if not _same(bar.get_menu_title(i), menu_name):
				continue
			var popup := bar.get_menu_popup(i)
			for j in popup.item_count:
				if popup.is_item_separator(j) or not _same(popup.get_item_text(j), item_name):
					continue
				var way := {"menu": popup, "item": popup.get_item_id(j), "index": j, "name": bar.get_menu_title(i), "native": bar.is_native_menu()}
				if popup.visible:
					return way.merged({"kind": ITEM, "name": popup.get_item_text(j), "place": func(): return Rect2(popup.position, popup.size) if popup.visible else null})
				return way.merged({"kind": MENU, "place": _title_place(bar, i)})
	return {}


# The menu bar draws its titles itself and has no rect for them: each is its text plus its box's
# margins wide, with the bar's gap between them.
static func _title_place(bar: MenuBar, index: int) -> Callable:
	var ref := weakref(bar)
	return func():
		var b := ref.get_ref() as MenuBar
		if b == null or not b.is_visible_in_tree():
			return null
		var font := b.get_theme_font("font")
		var size := b.get_theme_font_size("font_size")
		var box := b.get_theme_stylebox("normal")
		var gap := b.get_theme_constant("h_separation")
		var x := 0.0
		var wide := 0.0
		for i in index + 1:
			wide = font.get_string_size(b.get_menu_title(i), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT)
			if i < index:
				x += wide + gap
		return Rect2(b.get_global_rect().position + Vector2(x, 0), Vector2(wide, b.size.y))


# "tab:Output": a tab on screen with that name.
static func _tab(id: String) -> Dictionary:
	if not id.begins_with("tab:"):
		return {}
	var wanted := id.trim_prefix("tab:")
	for found in EditorInterface.get_base_control().find_children("*", "TabBar", true, false):
		var bar := found as TabBar
		if bar.is_visible_in_tree():
			for i in bar.tab_count:
				if _same(bar.get_tab_title(i), wanted):
					return {"kind": TAB, "name": bar.get_tab_title(i), "place": _tab_place(bar, i)}
	return {}


static func _tab_place(bar: TabBar, index: int) -> Callable:
	var ref := weakref(bar)
	return func():
		var b := ref.get_ref() as TabBar
		if b == null or not b.is_visible_in_tree() or index >= b.tab_count:
			return null
		var r := b.get_tab_rect(index)
		return Rect2(b.get_global_rect().position + r.position, r.size)


# Any other step: the thing somewhere in the editor, shown or not, and what keeps it out of sight.
static func _hiding(id: String) -> Dictionary:
	var thing := _thing(id)
	if thing == null:
		return {}
	var closed_page: Control = null
	var folded_section: Control = null
	var up := thing as Node
	while up and up != EditorInterface.get_base_control():
		if _is_closed_page(up):
			closed_page = up          # the outermost one wins: it's the one he can open now
		if up != thing and _is_folded_section(up):
			folded_section = up
		up = up.get_parent()
	if closed_page:
		var tabs := closed_page.get_parent() as TabContainer
		var index := tabs.get_tab_idx_from_control(closed_page)
		return {"kind": TAB, "name": tabs.get_tab_title(index), "place": _tab_place(tabs.get_tab_bar(), index)}
	if folded_section:
		var ref := weakref(folded_section)
		return {"kind": SECTION, "name": folded_section.tooltip_text, "section": folded_section, "place": func():
			var s := ref.get_ref() as Control
			return s.get_global_rect() if s and s.is_visible_in_tree() else null}
	return {}


# A tab's page that isn't the open one, on a tab bar he can see.
static func _is_closed_page(node: Node) -> bool:
	var parent := node.get_parent()
	return parent is TabContainer and node is Control and not (node as Control).visible and (parent as Control).is_visible_in_tree()


# An Inspector section he can see, folded shut (its section name is in its tooltip).
static func _is_folded_section(node: Node) -> bool:
	return node.get_class() == "EditorInspectorSection" and not (node.call("get_vbox") as Control).visible and (node as Control).is_visible_in_tree()


# The control a step's id names, among every control in the editor's own window (not its dialogs
# or menus, each a window of its own): named as screen.gd names what's on screen.
static func _thing(id: String) -> Control:
	var kind := id.get_slice(":", 0)
	var name := id.substr(kind.length() + 1)
	var all: Array = []
	_every(EditorInterface.get_base_control(), all)
	for c in all:
		match kind:
			"button":
				if c is BaseButton and not (c as BaseButton).disabled and _same(Screen.button_name(c), name):
					return c
			"field":
				if c is LineEdit and not (c as LineEdit).secret and _same((c as LineEdit).placeholder_text, name):
					return c
			"prop":
				if c is EditorProperty and str((c as EditorProperty).get_edited_property()) == name:
					return c
	return null


static func _every(node: Node, into: Array) -> void:
	for child in node.get_children(true):
		if child is Window:
			continue
		if child is Control:
			into.append(child)
		_every(child, into)
