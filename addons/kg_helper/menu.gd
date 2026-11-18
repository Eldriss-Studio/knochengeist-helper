@tool
extends RefCounted

const Brain := preload("brain.gd")

enum { STATE, WHERE, INSTALL, SIGN_IN, ASK, SETTINGS, SHOW_LOGS, DEBUG_INFO, ABOUT, COURSE_PAGE, UPDATE, EXPLAIN_ERROR }

const PLAN := 100                # the plan lines take ids from here on, one each

const LINES := {
	"checking": "Looking for Claude Code…",
	"ready": "Using Claude Code",
	"missing": "Claude Code not found",
	"signed_out": "Not signed in to Claude Code",
	"not_there": "No Claude Code at the path in Settings",
	"wont_start": "Claude Code won't start",
}
const SHORT_PATH := 40
const RECENT := 5
const RECENT_CHARS := 50

const ASK_SHORTCUT := "knochengeist/ask"


static func fill(menu: PopupMenu, course_up: bool, claude: String, claude_path: String, plan_lines := PackedStringArray(), update_to := "", recent := PackedStringArray(), show_past := Callable(), has_error := false) -> void:
	menu.clear()
	_line(menu, state(course_up, claude), STATE)
	if not course_up and claude == "ready":
		for i in plan_lines.size():
			_line(menu, plan_lines[i], PLAN + i)
		_line(menu, short_path(claude_path), WHERE)
	menu.add_separator()
	if update_to != "":
		menu.add_item("Update to version %s…" % update_to, UPDATE)
	if not course_up and claude == "missing":
		menu.add_item("Install %s…" % Brain.tool_name(), INSTALL)
	if not course_up and claude == "signed_out":
		menu.add_item("Sign in to %s…" % Brain.tool_name(), SIGN_IN)
	menu.add_item("Ask the ghost", ASK)
	var shortcuts := EditorInterface.get_editor_settings()
	if shortcuts.has_shortcut(ASK_SHORTCUT):
		menu.set_item_shortcut(menu.get_item_index(ASK), shortcuts.get_shortcut(ASK_SHORTCUT))
	if has_error:
		menu.add_item("Explain the last error", EXPLAIN_ERROR)
	if not recent.is_empty():
		var past: PopupMenu = menu.get_node_or_null("Recent")
		if past == null:
			past = PopupMenu.new()
			past.name = "Recent"
			menu.add_child(past)
		past.clear()
		for i in recent.size():
			past.add_item(recent[i] if recent[i].length() <= RECENT_CHARS else recent[i].left(RECENT_CHARS - 1).strip_edges() + "…", i)
		if show_past.is_valid() and not past.id_pressed.is_connected(show_past):
			past.id_pressed.connect(show_past)
		menu.add_submenu_node_item("Recent questions", past)
	menu.add_item("Settings…", SETTINGS)
	menu.add_item("Show log", SHOW_LOGS)
	menu.add_item("Copy debug info…", DEBUG_INFO)
	menu.add_item("About Knochengeist", ABOUT)
	if course_up:
		menu.add_separator()
		menu.add_item("Open the course page", COURSE_PAGE)


static func _line(menu: PopupMenu, text: String, id: int) -> void:
	menu.add_item(text, id)
	menu.set_item_disabled(menu.get_item_index(id), true)


## ~ for the home folder, and only the last two parts of a long path: the menu stays narrow.
static func short_path(path: String) -> String:
	var home := OS.get_environment("HOME")
	var shown := "~" + path.substr(home.length()) if home != "" and path.begins_with(home) else path
	if shown.length() <= SHORT_PATH:
		return shown
	var slash := "\\" if shown.contains("\\") else "/"     # a Windows path keeps its own slashes
	var parts := shown.split(slash)
	return "…" + slash + slash.join(parts.slice(parts.size() - 2))


static func state(course_up: bool, claude: String) -> String:
	return "Using the course page" if course_up else LINES.get(claude, LINES["checking"]).replace("Claude Code", Brain.tool_name())


static func can_answer(course_up: bool, claude: String) -> bool:
	return course_up or claude in ["checking", "ready"]


# Registered once: after that the keys are his, kept by Godot through restarts.
static func offer_shortcut() -> void:
	var shortcuts := EditorInterface.get_editor_settings()
	if shortcuts.has_shortcut(ASK_SHORTCUT):
		return
	var keys := InputEventKey.new()
	keys.keycode = KEY_G
	keys.alt_pressed = true
	var shortcut := Shortcut.new()
	shortcut.resource_name = "Ask the ghost"
	shortcut.events = [keys]
	shortcuts.add_shortcut(ASK_SHORTCUT, shortcut)


static func ask_keys() -> String:
	var shortcuts := EditorInterface.get_editor_settings()
	return shortcuts.get_shortcut(ASK_SHORTCUT).get_as_text() if shortcuts.has_shortcut(ASK_SHORTCUT) else "Option+G"
