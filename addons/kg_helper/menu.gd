@tool
extends RefCounted

const L := preload("l10n.gd")

const Brain := preload("brain.gd")

enum { STATE, WHERE, INSTALL, SIGN_IN, ASK, SETTINGS, SHOW_LOGS, DEBUG_INFO, ABOUT, COURSE_PAGE, UPDATE, EXPLAIN_ERROR }

const PLAN := 100                # the plan lines take ids from here on, one each

const LINES := {
	"checking": "Looking for %s…",
	"ready": "Using %s",
	"missing": "%s not found",
	"signed_out": "Not signed in to %s",
	"not_there": "%s isn't at the file you chose",
	"wont_start": "%s won't start",
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
		menu.add_item(L.t("Update to version %s…") % update_to, UPDATE)
	if not course_up and claude == "missing":
		menu.add_item(L.t("Install %s…") % Brain.tool_name(), INSTALL)
	if not course_up and claude == "signed_out":
		menu.add_item(L.t("Sign in to %s…") % Brain.tool_name(), SIGN_IN)
	menu.add_item(L.t("Ask the ghost"), ASK)
	var shortcuts := EditorInterface.get_editor_settings()
	if shortcuts.has_shortcut(ASK_SHORTCUT):
		menu.set_item_shortcut(menu.get_item_index(ASK), shortcuts.get_shortcut(ASK_SHORTCUT))
	if has_error:
		menu.add_item(L.t("Explain the last error"), EXPLAIN_ERROR)
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
		menu.add_submenu_node_item(L.t("Recent questions"), past)
	menu.add_item(L.t("Settings…"), SETTINGS)
	menu.add_item(L.t("Show log"), SHOW_LOGS)
	menu.add_item(L.t("Copy debug info…"), DEBUG_INFO)
	menu.add_item(L.t("About Knochengeist"), ABOUT)
	if course_up:
		menu.add_separator()
		menu.add_item(L.t("Open the course page"), COURSE_PAGE)


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


## The line that says what's answering. `tool_name` names another tool than the one in use (Settings).
static func state(course_up: bool, claude: String, tool_name := "") -> String:
	var named := tool_name if tool_name != "" else (Brain.shown_name() if claude == "ready" else Brain.tool_name())
	return L.t("Using the course page") if course_up else L.t(LINES.get(claude, LINES["checking"])) % named


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
