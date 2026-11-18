@tool
extends EditorPlugin
# The Knochengeist helper (#44). Tells the course app what this editor shows, the things on screen
# Stuck? may name (buttons, scene tree rows, inspector properties), and points at the one it names
# with a flying ghost and an inked ring (pointer.gd). The app's side is course/src/lib/server/godot-link.ts.
#
# It talks to the app over plain HTTP: a POST of what's on screen whenever that changes (and every
# few seconds, so the app knows it's still here), and one GET held open, waiting for a point. When
# the app isn't running, it knocks on its port every 2 seconds with a plain TCP connection, which
# fails quietly: an HTTP request would print an error in his Output panel each time.
# KG_HELPER_URL is the app's address; without it, a headless Godot (the checker's runs) leaves the
# helper off.
#
# In the toolbar it's one quiet button with the ghost: dimmed while the course page is off, with a
# dot in the editor's accent color once it's connected. Godot's own theme colors, scale and focus
# rules are used for that button; only the ghost, its ring and its cards look like Knochengeist.
#
# Option+G (or the button's menu) asks the ghost anything about Godot without leaving it (ask.gd):
# a general Godot helper, not a lesson one. Words first; Show me then points, when the answer named
# something on screen. After he clicks what was shown, it looks at the screen again and goes on to the
# next click, to the end of what he wanted, like a tutor pointing over his shoulder. It can point
# inside dialogs too (Create New Node): each window gets its own ghost.

const Pointer := preload("pointer.gd")
const Bubble := preload("bubble.gd")
const Ask := preload("ask.gd")
const Stream := preload("stream.gd")
const Brain := preload("brain.gd")
const Tags := preload("tags.gd")
const Menu := preload("menu.gd")
const Settings := preload("settings.gd")
const Context := preload("context.gd")
const Updates := preload("updates.gd")
const Answers := preload("answers.gd")
const Names := preload("names.gd")
const Errors := preload("errors.gd")
const Manual := preload("manual.gd")
const Ring := preload("ring.gd")
const Docs := preload("docs.gd")
const CHECK_UPDATES_AFTER_S := 5.0
const SLOTS := [EditorContextMenuPlugin.CONTEXT_SLOT_SCENE_TREE, EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, EditorContextMenuPlugin.CONTEXT_SLOT_SCRIPT_EDITOR_CODE, EditorContextMenuPlugin.CONTEXT_SLOT_INSPECTOR_PROPERTY]
const CODE_LINES_KEPT := 200
const COURSE_CODE_CHARS := 1200
const NOT_ALLOWED := "Claude Code wasn't run. Ask again to allow it."
const CONSENT_TITLE := "Allow Knochengeist to use Claude Code?"
const README := "https://github.com/Eldriss-Studio/knochengeist-helper#readme"
const RELEASES := "https://github.com/Eldriss-Studio/knochengeist-helper/releases"
const ISSUES := "https://github.com/Eldriss-Studio/knochengeist-helper/issues"
const ALONE := -1
const LOOK_S := 1.0              # how often it looks at what's on screen
const STILL_HERE_S := 5.0        # sends at least this often
const RETRY_S := 2.0
const NOT_THE_APP_RETRY_S := 30.0
const SETTLE_S := 0.25
const LOOK_AGAIN_S := 0.15
const LOOKS_BEFORE_SKIPPING_AHEAD := 6
const LOOKS_BEFORE_ASKING := 20
const WALK_MAX := 15             # clicks in one walk-through, at most
const CONTRACT := 1              # the version of the messages it speaks; the app refuses another
const CONTRACT_HEADER := "x-kg-contract"
const REFUSED_S := 30.0

var url := ""
var button: Button               # in the editor's top bar: the ghost, and whether the course page is connected
var dot: Control
var menu: PopupMenu
var tools_menu: PopupMenu
var course_shown := false
var claude_state := "checking"
var claude_path := ""
var consent_window: ConfirmationDialog
var hello_planned := false
var context_menus: Array = []
var updates: Node
var answers := Answers.new()
var thread: Array = []             # this card's questions and answers, oldest first, for follow-ups
const THREAD_KEPT := 3
const THREAD_ANSWER_CHARS := 600
var answer_record := ""
var ask_sent := ["", ""]           # the system prompt and question last sent for the card, for a name-check retry
var name_retried := false          # this question was already asked again over a name
var name_wrong := PackedStringArray()
var unchecked := PackedStringArray()
var errors := Errors.new()
var errors_seen := 0               # error rows in the Debugger last time it looked
var error_offered := false         # one offer per run of the game
var was_playing := false
var last_error := {}
var errors_in := 0.0
const LOOK_FOR_ERRORS_S := 1.0
const OFFER_S := 12.0   # names still not in his Godot after the retry: the card says to check them            # the record of the answer on the card, for whether it helped and how the walk ended
const SHARED_UNHELPFUL := 5
var docs: Node
var manual: Node
var ring: Control                  # around the toolbar ghost, once the plan's limit is nearly used up
var update_to := ""                # a newer version, once the check finds one
var update_notes := ""
var asking_about := ""             # what he right-clicked, added to the next question
var hello: Control        # the one-time hello under the button
var labels := {}                 # target id -> what to call it
var ask_box: Control             # Stuck?, asked from here
var ask_stream: RefCounted
var brain: RefCounted
var brain_for := ""
var tags: RefCounted
var answer_said := ""
var answer_text := ""
var walk_said := ""
var walk_answer := ""
var ask_words := ""
var ask_reply = null             # the answer's last line: { ask, answer, steps, closing }, or why it couldn't
var tell_req: HTTPRequest        # tells the app he pressed Show me
var answer_ask := 0              # the last answer's id and the target it named
var answer_target := ""
var host := ""
var port := 0
var project := ""
var state_req: HTTPRequest
var hello_req: HTTPRequest
var point_req: HTTPRequest
var ghost: Texture2D
var pointers := {}               # a window's id -> the ghost overlay in it
var wins := {}                   # target id -> the window it's in
var fields := {}                 # target id -> its text field (a weak reference)
var nodes := {}
var note: Control                # a short line under the button: thinking, or done
var next_req: HTTPRequest
var walk_ask := 0                # the ask a walk-through started from; 0 when there's none
var walk_clicked: Array = []     # what he has clicked so far in it
var walk_plan: Array = []        # the clicks planned ahead, each { id, say }; empty when it asks as it goes
var walk_i := 0                  # which planned click he's on
var walk_closing := ""
var walk_tries := 0
var answer_plan: Array = []      # the last answer's plan, until he presses Show me
var answer_closing := ""
var walk_target := ""
var walk_typed := ""             # a field he's typing in: its text when last looked at
var typed_for := 0.0
var typed_changed := false        # he changed the text since the ghost pointed at the field
var prefilled_for := 0.0          # how long a field the ghost points at has held its old text, untouched
const ALREADY_TYPED_S := 2.5      # then it counts as already typed, and the walk goes on
var typed_in := {}                # field id -> what he typed there earlier in this walk
var next_in := -1.0              # counting down to asking for the next click
var switching := false
var places := {}                 # target id -> Callable giving its rect on screen now, or null
var sent := ""
var sending := false
var waiting := false
var look_in := 0.0
var since_sent := 0.0
var retry_in := 0.0
var app_up := false              # the app answered on its port; until then only knock
var knock: StreamPeerTCP = null
var knocking_s := 0.0
var refused_for := 0.0


func _enter_tree() -> void:
	var from_env := OS.get_environment("KG_HELPER_URL")
	if DisplayServer.get_name() == "headless" and from_env == "":
		return
	url = (from_env if from_env != "" else "http://127.0.0.1:4173").trim_suffix("/")
	var address := url.trim_prefix("http://").get_slice("/", 0)
	host = address.get_slice(":", 0)
	port = int(address.get_slice(":", 1)) if address.contains(":") else 80
	project = ProjectSettings.globalize_path("res://").trim_suffix("/")
	state_req = HTTPRequest.new()
	state_req.timeout = 10.0
	state_req.request_completed.connect(_state_sent)
	add_child(state_req)
	hello_req = HTTPRequest.new()
	hello_req.timeout = 5.0
	hello_req.request_completed.connect(_hello_came)
	add_child(hello_req)
	point_req = HTTPRequest.new()
	point_req.timeout = 40.0
	point_req.request_completed.connect(_point_came)
	add_child(point_req)
	Brain.offer_settings()
	Menu.offer_shortcut()
	Updates.offer_setting()
	brain = Brain.new()
	brain.piece.connect(_brain_piece)
	brain.done.connect(_brain_done)
	brain.checked.connect(_claude_checked)
	ask_stream = Stream.new()
	ask_stream.line.connect(_answer_line)
	ask_stream.done.connect(_answer_came)
	tell_req = HTTPRequest.new()
	add_child(tell_req)
	next_req = HTTPRequest.new()
	next_req.timeout = 60.0
	next_req.request_completed.connect(_next_came)
	add_child(next_req)
	ghost = _svg("ghost.svg", 44.0)
	ask_box = Ask.new()
	ask_box.mascot = ghost
	ask_box.asked.connect(_ask)
	ask_box.show_me.connect(_show_me)
	ask_box.closed.connect(ask_stream.stop)          # he closed the card: the rest of the answer isn't wanted
	ask_box.closed.connect(brain.stop)
	ask_box.closed.connect(func(): thread.clear())
	ask_box.rated.connect(func(helped: bool, note: String): answers.rated(answer_record, helped, note))
	ask_box.closed.connect(func(): asking_about = "")
	EditorInterface.get_base_control().add_child(ask_box)
	_make_button()
	updates = Updates.new(int(_version()), (get_script() as Script).resource_path.get_base_dir())
	updates.found.connect(func(version: String, notes: String):
		update_to = version
		update_notes = notes
		_show_up(course_shown))
	updates.installed.connect(_updated)
	updates.failed.connect(_update_failed)
	add_child(updates)
	docs = Docs.new()
	add_child(docs)
	manual = Manual.new()
	add_child(manual)
	docs.manual = manual
	get_tree().create_timer(CHECK_UPDATES_AFTER_S).timeout.connect(func():
		if is_instance_valid(updates) and not course_shown:      # the course page keeps its own copy in step
			updates.check())
	for slot in SLOTS:
		var menu_plugin := Context.new(slot, _svg("icon.svg", 16.0))
		menu_plugin.picked.connect(_ask_about)
		add_context_menu_plugin(slot, menu_plugin)
		context_menus.append(menu_plugin)
	set_process(true)
	_show_up(false)
	brain.check()


func _exit_tree() -> void:
	for menu_plugin in context_menus:
		remove_context_menu_plugin(menu_plugin)
	context_menus.clear()
	if is_instance_valid(consent_window):
		consent_window.queue_free()
	if brain:
		brain.stop()
		brain.stop_check()
		brain.kill_all()
	if ask_stream:
		ask_stream.stop()
	for p in pointers.values():
		if is_instance_valid(p):
			p.queue_free()
	if note and is_instance_valid(note):
		note.queue_free()
	if hello:
		hello.queue_free()
	if ask_box:
		ask_box.queue_free()
	if button:
		remove_control_from_container(CONTAINER_TOOLBAR, button)
		button.queue_free()
	if tools_menu:
		remove_tool_menu_item("Knochengeist")       # Godot frees the submenu with it


# Called only when the helper is turned off in Project Settings > Plugins, not when the editor closes.
func _disable_plugin() -> void:
	var settings := EditorInterface.get_editor_settings()
	if settings.has_shortcut(Menu.ASK_SHORTCUT):
		settings.remove_shortcut(Menu.ASK_SHORTCUT)
	for key in ["claude_allowed", "said_hello", Updates.CHECKED_AT]:
		settings.set_project_metadata("knochengeist", key, null)
	_delete_folder(Brain.log_path().get_base_dir())


func _delete_folder(path: String) -> void:
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for dir in DirAccess.get_directories_at(path):
		_delete_folder(path.path_join(dir))
	DirAccess.remove_absolute(path)


# One of the helper's own drawings, at the editor's scale (and sharp on a dense screen).
func _svg(file: String, px: float) -> Texture2D:
	var path: String = (get_script() as Script).resource_path.get_base_dir().path_join(file)
	var image := Image.new()
	# the drawings are 24 units wide
	if image.load_svg_from_string(FileAccess.get_file_as_string(path), px * EditorInterface.get_editor_scale() * 2.0 / 24.0) != OK:
		return null
	return ImageTexture.create_from_image(image)


func _make_button() -> void:
	var scale := EditorInterface.get_editor_scale()
	button = Button.new()
	button.flat = true
	button.icon = _svg("icon.svg", 21.0)     # the ghost fills about three quarters of its box
	button.add_theme_constant_override("icon_max_width", int(21 * scale))
	button.focus_mode = Control.FOCUS_NONE
	ring = Ring.new()
	button.add_child(ring)
	dot = Control.new()
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.set_anchors_preset(Control.PRESET_FULL_RECT)
	dot.draw.connect(func(): dot.draw_circle(Vector2(dot.size.x - 5 * scale, 5 * scale), 3 * scale, button.get_theme_color("accent_color", "Editor")))
	button.add_child(dot)
	menu = PopupMenu.new()
	menu.id_pressed.connect(_chose)
	menu.about_to_popup.connect(func(): _show_up(course_shown))      # the keys he picked may have changed
	button.add_child(menu)
	tools_menu = PopupMenu.new()
	tools_menu.name = "Knochengeist"
	tools_menu.id_pressed.connect(_chose)
	tools_menu.about_to_popup.connect(func(): _show_up(course_shown))
	add_tool_submenu_item("Knochengeist", tools_menu)
	button.pressed.connect(func():
		menu.position = Vector2i(button.get_screen_position() + Vector2(0, button.size.y))
		menu.popup())
	add_control_to_container(CONTAINER_TOOLBAR, button)


func _show_up(up: bool) -> void:
	course_shown = up
	dot.visible = up
	var can := Menu.can_answer(up, claude_state)
	button.modulate = Color(1, 1, 1, 1.0 if can else 0.5)
	var state := Menu.state(up, claude_state)
	button.tooltip_text = "Knochengeist: %s." % state + (" %s to ask." % Menu.ask_keys() if can else " Click to see what's wrong.")
	if ring and brain and not up:
		ring.show_used(float(brain.limit.get("used", -1.0)), brain.limit.get("status") == "allowed_warning")
		if ring.visible:
			button.tooltip_text += " " + brain.usage_line() + "."
	var newer := update_to if not up else ""
	var recent := PackedStringArray(answers.recent(Menu.RECENT).map(func(record): return str(record.get("question", "")).strip_edges()).filter(func(q): return q != ""))
	Menu.fill(menu, up, claude_state, claude_path, brain.plan_lines() if brain else PackedStringArray(), newer, recent, _show_past, not last_error.is_empty())
	Menu.fill(tools_menu, up, claude_state, claude_path, brain.plan_lines() if brain else PackedStringArray(), newer, recent, _show_past, not last_error.is_empty())


func _claude_checked(state: String, path: String) -> void:
	claude_state = state
	claude_path = path
	_show_up(course_shown)
	if state != "checking" and docs:
		docs.start()                     # after the check, so the two don't compete when Godot starts
		manual.start()
	if state != "checking" and not hello_planned:
		hello_planned = true
		get_tree().create_timer(0.5).timeout.connect(_say_hello)    # once the toolbar is laid out


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and brain and claude_state not in ["checking", "ready"]:
		brain.check()


func _chose(id: int) -> void:
	match id:
		Menu.ASK:
			_open_ask()
		Menu.EXPLAIN_ERROR:
			_explain_error()
		Menu.SETTINGS:
			var settings := Settings.new(brain, claude_state, docs)
			settings.sign_in.connect(_sign_in)
			settings.confirmed.connect(brain.check)
			EditorInterface.popup_dialog_centered(_closes_itself(settings))
		Menu.INSTALL:
			OS.shell_open(Menu.INSTALL_PAGE)
		Menu.SIGN_IN:
			_sign_in()
		Menu.SHOW_LOGS:
			if not FileAccess.file_exists(Brain.log_path()):
				Brain.log_line("The log was opened before anything went wrong.")
			OS.shell_open(Brain.log_path())
		Menu.DEBUG_INFO:
			_open_debug_info()
		Menu.ABOUT:
			_open_about()
		Menu.UPDATE:
			_open_update()
		Menu.COURSE_PAGE:
			OS.shell_open(url + "/learn")


func _sign_in() -> void:
	var terminal := OS.get_environment("KG_HELPER_TERMINAL")
	if terminal != "":
		OS.create_process(terminal, [claude_path])
	elif OS.get_name() == "macOS":
		OS.create_process("open", ["-a", "Terminal", claude_path])
	elif OS.get_name() == "Windows":
		OS.create_process("cmd.exe", ["/c", "start", "", "cmd.exe", "/k", claude_path])
	else:
		# Linux: the default terminal, or the first common one there is
		for app in [["x-terminal-emulator", "-e"], ["gnome-terminal", "--"], ["konsole", "-e"], ["xterm", "-e"]]:
			var found := _on_path(app[0])
			if found != "":
				OS.create_process(found, [app[1], claude_path])
				return
		_note("Open a terminal, run claude, and sign in. Then ask again.", 10.0)


static func _on_path(app: String) -> String:
	for dir in OS.get_environment("PATH").split(":", false):
		if FileAccess.file_exists(dir.path_join(app)):
			return dir.path_join(app)
	return ""


func _run_claude(system: String, prompt: String) -> void:
	var claude := Brain.find_claude()
	var settings := EditorInterface.get_editor_settings()
	if not FileAccess.file_exists(claude) or settings.get_project_metadata("knochengeist", "claude_allowed", "") == claude:
		brain.ask(system, prompt)          # with no Claude Code, the brain says how to install it
		return
	if is_instance_valid(consent_window):
		consent_window.queue_free()
	var window := ConfirmationDialog.new()
	consent_window = window
	var asked_for := brain_for
	window.title = CONSENT_TITLE
	window.dialog_text = Brain.DISCLOSURE
	window.dialog_autowrap = true
	window.ok_button_text = "Allow"
	window.cancel_button_text = "Don't allow"
	window.min_size = Vector2i(460, 0) * EditorInterface.get_editor_scale()
	window.confirmed.connect(func():
		settings.set_project_metadata("knochengeist", "claude_allowed", Brain.find_claude())
		var still_wanted := ask_box.visible if asked_for == "ask" else walk_ask != 0
		if still_wanted:
			brain.ask(system, prompt))
	window.canceled.connect(func():
		if asked_for == "ask":
			ask_box.failed(NOT_ALLOWED)
		else:
			walk_ask = 0
			_note(NOT_ALLOWED, 6.0))
	EditorInterface.popup_dialog_centered(_closes_itself(window))


func _version() -> String:
	var cfg := ConfigFile.new()
	cfg.load((get_script() as Script).resource_path.get_base_dir().path_join("plugin.cfg"))
	return str(cfg.get_value("plugin", "version", "?"))


func _open_debug_info() -> void:
	var window := AcceptDialog.new()
	window.title = "Knochengeist debug info"
	window.ok_button_text = "Copy"
	window.add_cancel_button("Close")
	var box := VBoxContainer.new()
	var info := TextEdit.new()
	var base: String = brain.debug_info(_version())
	info.text = base
	info.editable = false
	info.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	info.custom_minimum_size = Vector2(520, 200) * EditorInterface.get_editor_scale()
	box.add_child(info)
	var share := CheckBox.new()
	share.text = "Include my last %d answers that didn't help" % SHARED_UNHELPFUL
	share.toggled.connect(func(on: bool): info.text = base + (_unhelpful_text() if on else ""))
	box.add_child(share)
	window.add_child(box)
	window.confirmed.connect(func(): DisplayServer.clipboard_set(info.text))
	EditorInterface.popup_dialog_centered(_closes_itself(window))


# The conversation so far on this card, for a follow-up: its last few questions and answers.
func _earlier() -> String:
	if thread.is_empty():
		return ""
	var lines := PackedStringArray(["", "Earlier in this conversation:"])
	for said in thread.slice(max(0, thread.size() - THREAD_KEPT)):
		lines.append("They asked: " + str(said["question"]).strip_edges())
		lines.append("You answered: " + str(said["answer"]).left(THREAD_ANSWER_CHARS).replace("\n", " "))
	return "\n".join(lines) + "\n"


# A question from Recent questions: its answer again, from this computer, ready for a follow-up.
func _show_past(i: int) -> void:
	var found: Array = answers.recent(Menu.RECENT)
	if i >= found.size():
		return
	var record: Dictionary = found[i]
	_open_ask()
	answer_said = str(record.get("question", ""))
	answer_record = str(record.get("id", ""))
	answer_plan = []
	thread = [{"question": answer_said, "answer": str(record.get("answer", ""))}]
	ask_box.answered(str(record.get("answer", "")).replace("[", "[lb]"), false)
	ask_box.position = _under_button(ask_box)


# The answers he marked as not helpful, as he'll see them before copying.
func _unhelpful_text() -> String:
	var found: Array = answers.recent_unhelpful(SHARED_UNHELPFUL)
	if found.is_empty():
		return "\n\nAnswers that didn't help: none yet."
	var lines := PackedStringArray(["", "", "Answers that didn't help:"])
	for i in found.size():
		lines.append("%d. Question: %s" % [i + 1, found[i].get("question", "")])
		lines.append("   Answer: %s" % str(found[i].get("answer", "")).replace("\n", " "))
		lines.append("   Note: %s" % found[i].get("note", ""))
	return "\n".join(lines)


func _open_about() -> void:
	var about := AcceptDialog.new()
	about.title = "About Knochengeist"
	var box := VBoxContainer.new()
	var words := Label.new()
	words.text = "Knochengeist helper, version %s.\nAsk anything about Godot with %s. Answers come from your Claude Code, or from the course page when it's running." % [_version(), Menu.ask_keys()]
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.custom_minimum_size = Vector2(460, 0) * EditorInterface.get_editor_scale()
	box.add_child(words)
	var sends := LinkButton.new()
	sends.text = "What it sends to Anthropic"
	sends.pressed.connect(func():
		about.hide()                  # Godot opens one exclusive window at a time
		_open_disclosure.call_deferred())
	box.add_child(sends)
	for each in [["Read how it works", README], ["What's new in each version", RELEASES], ["Report a problem", ISSUES]]:
		var link := LinkButton.new()
		link.text = each[0]
		link.uri = each[1]
		box.add_child(link)
	var credit := Label.new()
	credit.text = "The Godot manual pages: CC BY 3.0, by Juan Linietsky, Ariel Manzur and the Godot community."
	credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credit.custom_minimum_size = Vector2(460, 0) * EditorInterface.get_editor_scale()
	credit.modulate = Color(1, 1, 1, 0.7)
	box.add_child(credit)
	var license := LinkButton.new()
	license.text = "The CC BY 3.0 license"
	license.uri = "https://creativecommons.org/licenses/by/3.0/"
	box.add_child(license)
	about.add_child(box)
	EditorInterface.popup_dialog_centered(_closes_itself(about))


func _open_update() -> void:
	var window := ConfirmationDialog.new()
	window.title = "Update Knochengeist"
	window.ok_button_text = "Update"
	window.cancel_button_text = "Not now"
	var words := Label.new()
	var notes := update_notes.replace("**", "").strip_edges()
	words.text = "Version %s is out. You have version %s.\n\nWhat's new:\n%s\n\nUpdating replaces the helper's folder, then asks you to reload the project." % [update_to, _version(), notes if notes != "" else "See the release notes on GitHub."]
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.custom_minimum_size = Vector2(460, 0) * EditorInterface.get_editor_scale()
	window.add_child(words)
	window.confirmed.connect(updates.install)
	EditorInterface.popup_dialog_centered(_closes_itself(window))


func _updated(version: String) -> void:
	update_to = ""
	var window := ConfirmationDialog.new()
	window.title = "Knochengeist updated"
	window.ok_button_text = "Reload"
	window.cancel_button_text = "Later"
	window.dialog_text = "Version %s is installed. Reload the project to use it." % version
	window.confirmed.connect(func(): EditorInterface.restart_editor(true))
	EditorInterface.popup_dialog_centered(_closes_itself(window))


func _update_failed(why: String) -> void:
	var window := AcceptDialog.new()
	window.title = "Knochengeist didn't update"
	window.dialog_text = why + " Show log has the details."
	EditorInterface.popup_dialog_centered(_closes_itself(window))


func _open_disclosure() -> void:
	var window := AcceptDialog.new()
	window.title = "What Knochengeist sends"
	var words := Label.new()
	words.text = Brain.DISCLOSURE
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.custom_minimum_size = Vector2(460, 0) * EditorInterface.get_editor_scale()
	window.add_child(words)
	EditorInterface.popup_dialog_centered(_closes_itself(window))


func _closes_itself(dialog: AcceptDialog) -> AcceptDialog:
	dialog.visibility_changed.connect(func(): if not dialog.visible: dialog.queue_free())
	return dialog


func _say_hello() -> void:
	var settings := EditorInterface.get_editor_settings()
	if settings.get_project_metadata("knochengeist", "said_hello", false):
		return
	settings.set_project_metadata("knochengeist", "said_hello", true)
	var scale := EditorInterface.get_editor_scale()
	hello = Bubble.new()
	if Menu.can_answer(course_shown, claude_state):
		hello.say("[b]I'm here.[/b] Press %s to ask me anything about Godot, and I'll show you where to click." % Menu.ask_keys(), 260.0)
	else:
		hello.say("[b]I'm here[/b], but there's a problem: %s. Click the ghost above to fix it." % Menu.state(course_shown, claude_state).to_lower().replace("claude code", "Claude Code"), 260.0)
	var base := EditorInterface.get_base_control()
	base.add_child(hello)
	hello.position = _under_button(hello)
	var gone := hello
	get_tree().create_timer(9.0).timeout.connect(func(): if is_instance_valid(gone): gone.queue_free())


func _process(delta: float) -> void:
	if url == "":
		return
	_walk(delta)
	errors_in -= delta
	if errors_in <= 0.0:
		errors_in = LOOK_FOR_ERRORS_S
		_look_for_errors()
	ask_stream.poll(delta)
	brain.poll(delta)
	if refused_for > 0.0:
		refused_for -= delta
		return
	if not app_up:
		_knock(delta)
		return
	since_sent += delta
	look_in -= delta
	if look_in <= 0.0 and not sending:
		look_in = LOOK_S
		var body := JSON.stringify(_state())
		if body != sent or since_sent >= STILL_HERE_S:
			sending = true
			if _send(state_req, "/api/godot/state", body):
				sent = body
				since_sent = 0.0
			else:
				sending = false
	if not waiting:
		retry_in -= delta
		if retry_in <= 0.0:
			waiting = _send(point_req, "/api/godot/point?project=" + project.uri_encode())
			if not waiting:
				retry_in = RETRY_S


# `body` is JSON to POST; without one it's a GET.
func _send(req: HTTPRequest, path: String, body := "") -> bool:
	if body == "":
		return req.request(url + path, _headers(false)) == OK
	return req.request(url + path, _headers(true), HTTPClient.METHOD_POST, body) == OK


func _headers(with_body: bool) -> PackedStringArray:
	var headers := PackedStringArray(["X-KG-Contract: %d" % CONTRACT])
	if with_body:
		headers.append("Content-Type: application/json")
	return headers


# Knocking again at once would only be refused again.
func _refused() -> void:
	refused_for = REFUSED_S
	sent = ""
	_show_up(false)
	_note("The course app and this helper are different versions. Reload this project: Project > Reload Current Project.", REFUSED_S)


func _state_sent(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	sending = false
	if code == HTTPClient.RESPONSE_UPGRADE_REQUIRED:
		_refused()
		return
	if result != HTTPRequest.RESULT_SUCCESS or code >= 300:
		sent = ""                 # the app missed it: send it again once it's back
		_app_gone()


func _point_came(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	waiting = false
	if code == HTTPClient.RESPONSE_UPGRADE_REQUIRED:
		_refused()
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_app_gone()
		return
	retry_in = 0.0
	var answer = JSON.parse_string(body.get_string_from_utf8())
	if answer is Dictionary and answer.get("target") is String and places.has(answer["target"]):
		# he pressed Show me on the course page: start (or restart) the walk from that ask
		walk_ask = int(answer["ask"]) if answer.get("ask") != null else 0
		walk_clicked = []
		typed_in = {}
		walk_plan = []
		_point(answer["target"], _say(answer["target"]))


# ---------------------------------------------------------------- pointing, and going on

# The ghost overlay for a window (the editor itself, or a dialog), made the first time it's needed.
func _pointer_in(win: Window) -> Control:
	var key := win.get_instance_id()
	if pointers.has(key) and is_instance_valid(pointers[key]):
		return pointers[key]
	var p: Control = Pointer.new()
	p.ghost = ghost
	var base := EditorInterface.get_base_control()
	if win == base.get_window():
		base.add_child(p)
	else:
		win.add_child(p, false, Node.INTERNAL_MODE_BACK)      # not part of the dialog's own layout
	p.finished.connect(_pointed)
	pointers[key] = p
	return p


func _point(id: String, text: String) -> void:
	_stop_pointing()
	if note and is_instance_valid(note):
		note.queue_free()
	walk_target = id
	var field_now = (fields[id] as WeakRef).get_ref() if fields.has(id) else null
	walk_typed = (field_now as LineEdit).text if field_now else ""      # what's already there isn't new typing
	typed_changed = false
	prefilled_for = 0.0
	typed_for = 0.0
	var win: Window = wins.get(id, EditorInterface.get_base_control().get_window())
	var p := _pointer_in(win)
	p.stays = fields.has(id)
	p.point(places[id], text)


# Takes every ghost down without ending the walk-through.
func _stop_pointing() -> void:
	switching = true
	for p in pointers.values():
		if is_instance_valid(p):
			p.stop()
	switching = false


func _pointed(clicked: bool, cancelled: bool, gave_up: bool) -> void:
	if switching:
		return
	if walk_ask == 0 or cancelled:
		walk_ask = 0
		return
	if gave_up:
		walk_ask = 0
		answers.walk_ended(answer_record, "stopped")
		_note("I'll stop here. Ask me again anytime.", 8.0)
		return
	if clicked:
		walk_clicked.append(str(labels.get(walk_target, walk_target)))
		walk_i += 1
	walk_tries = 0
	next_in = SETTLE_S


func _walk(delta: float) -> void:
	# the cards under the button grow as their words change: keep them inside the window
	for card in [note, hello, ask_box]:
		if card and is_instance_valid(card) and card.visible:
			card.position = _under_button(card)
	# a text field he was pointed at: once he has typed and paused, go on
	if walk_ask != 0 and fields.has(walk_target) and next_in < 0.0:
		var field = (fields[walk_target] as WeakRef).get_ref()
		if field and (field as LineEdit).text != walk_typed:
			walk_typed = (field as LineEdit).text
			typed_changed = true
			typed_for = 0.0
		elif field and not typed_changed and walk_typed != "" and typed_in.get(walk_target, "") == walk_typed:
			# pointed back at a box that already holds text: if he leaves it, it was typed already
			prefilled_for += delta
			if prefilled_for > ALREADY_TYPED_S:
				prefilled_for = -INF
				_stop_pointing()
				walk_i += 1
				walk_tries = 0
				next_in = 0.0
		elif field and typed_changed and walk_typed != "":
			typed_for += delta
			if typed_for > 1.2:
				walk_clicked.append("typed \"%s\" in %s" % [walk_typed, str(labels.get(walk_target, "the field"))])
				typed_in[walk_target] = walk_typed
				typed_changed = false             # counted once; waiting for the next click mustn't count it again
				_stop_pointing()
				walk_i += 1
				walk_tries = 0
				next_in = 0.0
	if next_in >= 0.0:
		next_in -= delta
		if next_in < 0.0:
			_ask_next()


# Whether a plan step already done pointed at this same thing.
func _used_before(id: String) -> bool:
	for i in walk_i:
		if str(walk_plan[i].get("id", "")) == id:
			return true
	return false


func _ask_next() -> void:
	if walk_ask == 0 or (walk_ask != ALONE and not app_up):
		return
	# the clicks were planned ahead: go straight to the next one when it's where the plan said
	if walk_plan.size() > 0:
		if walk_i >= walk_plan.size():
			walk_ask = 0
			answers.walk_ended(answer_record, "finished")
			_note(walk_closing if walk_closing != "" else "That's it.", 7.0)
			return
		_state()
		var found := _find(str(walk_plan[walk_i].get("id", "")))
		var at := walk_i
		# Not at once: right after a click the old screen is still up, and a later step may be on it.
		if found == "" and walk_tries >= LOOKS_BEFORE_SKIPPING_AHEAD:
			for j in range(walk_i + 1, walk_plan.size()):
				if _changes_what_is_made(str(walk_plan[j - 1].get("id", ""))):
					break              # skipping a box to type in or an item to pick would make the wrong thing
				if _used_before(str(walk_plan[j].get("id", ""))):
					break              # the same box or button as a done step: the screen hasn't moved on, so it's not that step yet
				found = _find(str(walk_plan[j].get("id", "")))
				if found != "":
					at = j
					break
		if found != "":
			walk_i = at
			_point(found, "[b]Step %d of %d:[/b] " % [at + 1, walk_plan.size()] + str(walk_plan[at].get("say", "")).replace("[", "[lb]"))
			return
		walk_tries += 1
		if walk_tries < LOOKS_BEFORE_ASKING:
			next_in = LOOK_AGAIN_S
			return
		walk_plan = []                 # the plan and the screen disagree: ask as it goes from here
	if walk_clicked.size() >= WALK_MAX:
		walk_ask = 0
		answers.walk_ended(answer_record, "stopped")
		_note("That was a long one. Ask me again if there's more to do.", 6.0)
		return
	var body := _state()
	if walk_ask == ALONE:
		brain_for = "next"
		tags = Tags.new()
		_run_claude(_prompt("guide"), _fill(_prompt("turn"), {
			"wanted": walk_said.strip_edges() if walk_said.strip_edges() != "" else "help with what they are building",
			"answer": walk_answer,
			"clicked": "(nothing yet)" if walk_clicked.is_empty() else "".join(walk_clicked.map(func(c): return "\n- " + str(c))),
			"screen": _screen(body, "point"),
		}))
		_note("", 60.0)
		return
	body["ask"] = walk_ask
	body["clicked"] = walk_clicked
	if _send(next_req, "/api/godot/next", JSON.stringify(body)):
		_note("", 60.0)
	else:
		walk_ask = 0


func _next_came(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var reply = JSON.parse_string(body.get_string_from_utf8())
	if walk_ask == 0:
		return
	if code == HTTPClient.RESPONSE_UPGRADE_REQUIRED:
		walk_ask = 0
		_refused()
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not (reply is Dictionary):
		walk_ask = 0
		_note("I lost track of where we were. Ask me again with %s." % Menu.ask_keys(), 6.0)
		return
	_next_reply(reply)


func _next_reply(reply: Dictionary) -> void:
	var say := str(reply.get("say", "")).replace("[", "[lb]")
	_state()                                  # where things are now
	if reply.get("target") is String and places.has(reply["target"]) and walk_clicked.count(str(labels.get(reply["target"], ""))) < 2:
		_point(reply["target"], "[b]Next:[/b] " + say)
	else:
		walk_ask = 0
		_note(say if say != "" else "That's it.", 7.0)


# A short line under the helper's button, for a few seconds.
func _note(text: String, seconds: float) -> void:
	if note and is_instance_valid(note):
		note.queue_free()
	note = Bubble.new()
	note.mascot = ghost
	if text == "":
		note.muse()                    # working out the next click
	else:
		note.say(text, 250.0)
	EditorInterface.get_base_control().add_child(note)
	note.position = _under_button(note)
	var gone := note
	get_tree().create_timer(seconds).timeout.connect(func(): if is_instance_valid(gone): gone.queue_free())


# Where a card goes: under the helper's button, kept on screen.
func _under_button(card: Control) -> Vector2:
	var base := EditorInterface.get_base_control()
	var at := button.get_global_rect()
	var scale := EditorInterface.get_editor_scale()
	var x := clampf(at.end.x - card.size.x, 8, base.size.x - card.size.x - 14 * scale)
	var inspector := EditorInterface.get_inspector().get_global_rect()
	var left_of_it := inspector.position.x - card.size.x - 8 * scale
	if inspector.has_area() and x + card.size.x > inspector.position.x and left_of_it >= 8:
		x = left_of_it                # keep the Inspector in view: he may be asking about it
	return Vector2(x, at.end.y + 8 * scale) - base.get_global_rect().position


func _shortcut_input(event: InputEvent) -> void:
	if url == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var shortcuts := EditorInterface.get_editor_settings()
	if shortcuts.has_shortcut(Menu.ASK_SHORTCUT) and shortcuts.get_shortcut(Menu.ASK_SHORTCUT).matches_event(event):
		_open_ask()
		get_viewport().set_input_as_handled()


func _open_ask() -> void:
	if hello and is_instance_valid(hello):
		hello.queue_free()
	walk_ask = 0
	asking_about = ""
	thread.clear()
	_stop_pointing()
	ask_box.open(app_up)
	ask_box.position = _under_button(ask_box)


# Opens the card with a question about what he right-clicked, ready to send or change.
func _ask_about(kind: String, what: Dictionary) -> void:
	var question := ""
	var note := ""
	var about := ""
	match kind:
		"node":
			question = "What does the %s node (%s) do, and what can I do with it?" % [what["name"], what["type"]]
			about = "They are asking about the node %s (a %s) at %s in the open scene." % [what["name"], what["type"], what["path"]]
		"file":
			question = "What is %s for?" % what["path"]
			about = "They are asking about the file %s." % what["path"]
		"property":
			question = "What does the %s property%s do?" % [what["property"], (" of " + what["class"]) if what["class"] != "" else ""]
			about = "They are asking about the %s property of a %s in the Inspector." % [what["property"], what["class"]]
		"error":
			question = "What does this error mean, and how do I fix it?"
			var where := "line %d of %s" % [what["line"], str(what["file"]).get_file()] if str(what["file"]) != "" else ""
			about = "They ran their game and it stopped with this error:\n%s" % str(what["details"]).strip_edges()
			var code := Errors.lines_around(str(what["file"]), int(what["line"]))
			if code != "":
				about += "\nIn %s, around line %d (the line marked >):\n```gdscript\n%s\n```" % [what["file"], what["line"], code]
			note = "With the error%s." % ((" and " + where) if where != "" else "")
		"code":
			var lines: PackedStringArray = str(what["code"]).split("\n")
			var kept := "\n".join(lines.slice(0, CODE_LINES_KEPT))
			question = "Explain this code%s." % ((" from " + what["path"]) if what["path"] != "" else "")
			about = "They are asking about these lines%s:\n```gdscript\n%s\n```" % [(" of " + what["path"]) if what["path"] != "" else "", kept]
			note = "With %d selected line%s." % [mini(lines.size(), CODE_LINES_KEPT), "" if lines.size() == 1 else "s"]
	_open_ask()
	asking_about = about
	ask_box.ask_about(question, note)


# Errors from a run of his game: the first one of a run gets an offer to explain it, never sent on its own.
func _look_for_errors() -> void:
	var playing := EditorInterface.is_playing_scene()
	if playing and not was_playing:
		error_offered = false          # a new run
	was_playing = playing
	var found: Array = errors.all()
	if found.size() > errors_seen:
		last_error = found[-1]
		_show_up(course_shown)
		if not error_offered and Menu.can_answer(course_shown, claude_state):
			error_offered = true
			Brain.log_line("Offered to explain an error.")
			_note("Your game hit an error. Click me to have it explained.", OFFER_S)
			note.mouse_filter = Control.MOUSE_FILTER_STOP
			note.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			note.gui_input.connect(func(event: InputEvent):
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					_explain_error())
	errors_seen = found.size()


func _explain_error() -> void:
	if last_error.is_empty():
		return
	if note and is_instance_valid(note):
		note.queue_free()
	_ask_about("error", last_error)


# The class reference passages the question needs, as a block for the prompt: empty when it names
# nothing in Godot, or when the index isn't ready.
func _from_the_docs(text: String) -> String:
	if docs == null:
		return ""
	var found: Array = docs.passages_for(text)
	if found.is_empty():
		return ""
	var lines := PackedStringArray(["", "From the class reference of their Godot %s (trust these over memory when they disagree):" % _godot_version()])
	for passage in found:
		lines.append("- [%s] %s" % [passage["id"], passage["text"]])
	return "\n".join(lines) + "\n"


# The manual's pages that answer the question, as a block for the prompt, with their links: empty
# when none matches, or when the manual isn't there.
func _from_the_manual(text: String) -> String:
	if manual == null:
		return ""
	var found: Array = manual.search(text)
	if found.is_empty():
		return ""
	var lines := PackedStringArray(["", "From the Godot manual for their Godot %s (trust these over memory when they disagree; link a page when it helps):" % manual.minor])
	for page in found:
		lines.append("- %s (%s): %s" % [page.get("title", ""), page.get("url", ""), str(page.get("text", "")).replace("\n", " ").left(900)])
	return "\n".join(lines) + "\n"


func _godot_version() -> String:
	return (docs.version if docs and docs.version != "" else Docs.running_version()).rsplit(".", true, 1)[0]


func _ask(said: String) -> void:
	name_retried = false
	unchecked = PackedStringArray()
	ask_box.thinking()
	ask_words = ""
	ask_reply = null
	answer_said = said
	var earlier := _earlier()
	if not app_up:
		brain_for = "ask"
		tags = Tags.new()
		var about := ("\n" + asking_about + "\n") if asking_about != "" else ""
		about += _from_the_docs(said + "\n" + asking_about) + _from_the_manual(said)
		asking_about = ""
		ask_sent = [_prompt("godot"), _screen(_state(), "plan") + about + earlier + "\nTheir question: " + (said.strip_edges() if said.strip_edges() != "" else "They are stuck, and did not say on what.")]
		_run_claude(ask_sent[0], ask_sent[1])
		return
	var from_docs := _from_the_docs(said + "\n" + asking_about)
	if asking_about != "":
		said = said + "\n\n" + asking_about.left(COURSE_CODE_CHARS)
		asking_about = ""
	if earlier != "":
		said = earlier.strip_edges() + "\n\nTheir question: " + said
	said += from_docs + _from_the_manual(said)
	if not ask_stream.post(host, port, "/api/godot/ask", _headers(true), JSON.stringify({"project": project, "said": said, "stream": true})):
		ask_box.failed("That didn't work. Try again.")


# One line of the answer: { say } is the next words, anything else is its last line.
func _answer_line(text: String) -> void:
	var message = JSON.parse_string(text)
	if not (message is Dictionary):
		return
	if not (message.get("say") is String):
		ask_reply = message
		return
	ask_words += message["say"]
	ask_box.saying(_plain(ask_words))
	ask_box.position = _under_button(ask_box)


# The card reads [..] as formatting.
func _plain(text: String) -> String:
	return text.strip_edges().replace("[", "[lb]").replace("**", "")


func _answer_came(ok: bool, code: int) -> void:
	var reply = ask_reply
	if not ok or not (reply is Dictionary):
		ask_box.failed("That didn't work. Is the course page still running?")
		return
	if code == HTTPClient.RESPONSE_UPGRADE_REQUIRED:
		_refused()
	if code != 200 or reply.has("code"):
		var claude := {"signed_out": "Claude isn't signed in. Open a terminal, type claude, and sign in. Then ask again.", "missing": "The claude command isn't installed on this computer yet."}
		ask_box.failed(claude.get(reply.get("code", ""), str(reply.get("message", "That didn't work. Try again."))))
		return
	_answered(reply)


func _answered(reply: Dictionary) -> void:
	answer_ask = int(reply.get("ask", 0))
	answer_plan = reply["steps"] if reply.get("steps") is Array else []
	answer_closing = str(reply.get("closing", ""))
	answer_text = str(reply.get("answer", ""))
	_state()
	answer_target = _find(str(answer_plan[0].get("id", ""))) if answer_plan.size() > 0 else ""
	var steps := PackedStringArray(answer_plan.map(func(step): return str(step.get("say", "")) if step is Dictionary else ""))
	answer_record = answers.added(answer_said, _plain(answer_text), steps, brain.answered_by if not app_up else "the course page", _version())
	thread.append({"question": answer_said, "answer": _plain(answer_text)})
	_show_up(course_shown)
	ask_box.answered(_plain(str(reply.get("answer", ""))), places.has(answer_target))
	if not unchecked.is_empty():
		ask_box.note("I couldn't find %s in your Godot %s, so check that name." % [", ".join(unchecked), _godot_version()])
	ask_box.position = _under_button(ask_box)


func _brain_piece(piece: String) -> void:
	if brain_for != "ask":
		return
	var words: String = tags.push(piece)
	if words == "":
		return
	ask_words += words
	ask_box.saying(_plain(ask_words))
	ask_box.position = _under_button(ask_box)


func _brain_done(whole: String, problem: String) -> void:
	var asked_for := brain_for
	brain_for = ""
	if asked_for == "next":
		if walk_ask != ALONE:
			return
		if problem != "":
			walk_ask = 0
			_note(brain.problem_message(problem), 8.0)
			return
		var said: String = tags.push(whole) + tags.end()
		_next_reply({"say": said.strip_edges(), "target": tags.point if tags.point != "" else null})
		return
	if asked_for != "ask":
		return
	if problem != "":
		ask_box.failed(brain.problem_message(problem))
		return
	_show_up(course_shown)               # the ring and tooltip follow this run's limit
	var heads_up: String = brain.warning()
	if heads_up != "":
		_note(heads_up, 10.0)
	ask_words += tags.end()
	var plan: Dictionary = Tags.plan_of(whole)
	var steps: Array = plan["steps"]
	if steps.is_empty() and tags.point != "":
		steps = [{"id": tags.point, "say": ""}]
	if _names_wrong(ask_words + "\n" + "\n".join(steps.map(func(step): return str(step.get("say", ""))))):
		return
	_answered({"ask": ALONE, "answer": ask_words.strip_edges(), "steps": steps, "closing": plan["closing"]})


# The name check: Godot names in the answer that his Godot doesn't have. The first time, asks again
# with the real reference and returns true; after that, the card shows the answer with a note.
func _names_wrong(said: String) -> bool:
	if docs == null or docs.state != "ready":
		return false
	var wrong := Names.missing(said, answer_said, docs.knows)
	if name_retried:
		Brain.log_line("Name check: %s isn't in Godot %s; asked again: %s." % [", ".join(name_wrong), _godot_version(), "still there" if not wrong.is_empty() else "fixed"])
		unchecked = wrong
		return false
	if wrong.is_empty():
		return false
	name_retried = true
	name_wrong = wrong
	var lines := PackedStringArray(["", "", "Your last answer named these, but they aren't in their Godot %s: %s. Don't use them. From the class reference of their Godot, the closest real ones:" % [_godot_version(), ", ".join(wrong)]])
	for passage in docs.search(answer_said + " " + " ".join(wrong), 5):
		lines.append("- [%s] %s" % [passage["id"], passage["text"]])
	lines.append("Answer their question again, with names from their Godot.")
	ask_words = ""
	tags = Tags.new()
	brain_for = "ask"
	ask_box.saying("Checking a name against your Godot…")
	_run_claude(ask_sent[0], ask_sent[1] + "\n".join(lines))
	return true


func _prompt(name: String) -> String:
	return FileAccess.get_file_as_string((get_script() as Script).resource_path.get_base_dir().path_join("prompts/%s.txt" % name)).strip_edges()


# What Godot shows, then what to do with it (`then` names a prompt): the course app builds the same.
func _screen(state: Dictionary, then: String) -> String:
	var lines: Array = (state.get("targets", []) as Array).map(func(t): return "- %s: %s" % [t["id"], t["label"]])
	var scene := str(state.get("scene", ""))
	var selected := str(state.get("selected", ""))
	var shown := _fill(_prompt("screen"), {"scene": scene if scene != "" else "none", "selected": selected if selected != "" else "none", "targets": "\n".join(lines)})
	return "\n%s\n%s\n" % [shown, _prompt(then)]


# Fills a prompt's {name} places in one pass, so a value can't fill a later place.
func _fill(template: String, values: Dictionary) -> String:
	var out := ""
	var from := 0
	for m in RegEx.create_from_string("\\{(\\w+)\\}").search_all(template):
		out += template.substr(from, m.get_start() - from) + str(values.get(m.get_string(1), m.get_string()))
		from = m.get_end()
	return out + template.substr(from)


# Words first, then where: he asked to be shown what the answer named.
func _show_me() -> void:
	if not places.has(answer_target):
		return
	ask_box.close()
	walk_ask = answer_ask
	walk_said = answer_said
	walk_answer = answer_text
	walk_clicked = []
	typed_in = {}
	# one click and no closing line isn't a plan (an "I'm stuck on my step" answer): ask as it goes
	walk_plan = answer_plan if answer_plan.size() > 1 or answer_closing != "" else []
	walk_closing = answer_closing
	walk_i = 0
	var first := str(answer_plan[0].get("say", "")) if answer_plan.size() > 0 else ""
	var label := ("[b]Step 1 of %d:[/b] " % walk_plan.size()) if walk_plan.size() > 1 else "[b]First:[/b] "
	_point(answer_target, (label + first.replace("[", "[lb]")) if first != "" else _say(answer_target))
	if answer_ask != ALONE:
		_send(tell_req, "/api/godot/show", JSON.stringify({"ask": answer_ask}))


# A planned click on today's screen: the thing with that id, give or take capitals and a full stop
# (the plan predicts names for things that weren't on screen when it was made). "" when it isn't
# here. Nothing looser than that: "Create" is not "Add/Create a New Node" nor "Create a new resource",
# and an entry in a dialog's list is not the node of the same name in the Scene dock. When the plan
# and the screen disagree, the helper asks what's next instead of guessing.
func _find(id: String) -> String:
	if places.has(id):
		return id
	var want := id.to_lower().trim_suffix(".").strip_edges()
	for other in places:
		if str(other).to_lower().trim_suffix(".").strip_edges() == want:
			return other
	# A box or an item planned before its dialog opened has a guessed name ("Search Nodes" for
	# "Search"): take the one on screen of the same kind whose name holds the other, if only one does.
	if not _changes_what_is_made(id):
		return ""
	var kind := want.get_slice(":", 0) + ":"
	var name := want.trim_prefix(kind)
	var near: Array = []
	for other in places:
		var theirs := str(other).to_lower().trim_suffix(".").strip_edges()
		if theirs.begins_with(kind) and name != "" and (theirs.trim_prefix(kind).contains(name) or name.contains(theirs.trim_prefix(kind))):
			near.append(other)
	return near[0] if near.size() == 1 else ""


func _changes_what_is_made(id: String) -> bool:
	return id.begins_with("field:") or id.begins_with("item:")


# What the ghost says beside the thing: the action, and the thing's own name.
func _say(id: String) -> String:
	var kind := id.get_slice(":", 0)
	var name := id.substr(kind.length() + 1).trim_suffix(".")
	match kind:
		"button": return "[b]Click here:[/b] " + name
		"row": return "[b]This node:[/b] " + name
		"prop": return "[b]This property:[/b] " + name
		"item": return "[b]This one:[/b] " + name
		"field": return "[b]Type here:[/b] " + name
	return name


func _app_gone() -> void:
	app_up = false
	retry_in = RETRY_S
	_show_up(false)


# Knocks on the app's port; once it answers, the HTTP side starts.
func _knock(delta: float) -> void:
	if knock == null:
		retry_in -= delta
		if retry_in > 0.0:
			return
		knock = StreamPeerTCP.new()
		knocking_s = 0.0
		if knock.connect_to_host(host, port) != OK:
			knock = null
			retry_in = RETRY_S
		return
	knock.poll()
	knocking_s += delta
	var status := knock.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTING and knocking_s < RETRY_S:
		return
	knock.disconnect_from_host()
	knock = null
	if status == StreamPeerTCP.STATUS_CONNECTED:
		retry_in = NOT_THE_APP_RETRY_S             # until the answer says it's the course app
		if hello_req.request(url + "/api/godot/status", _headers(false)) != OK:
			retry_in = RETRY_S
	else:
		retry_in = RETRY_S


# Something answered on the course app's port: only the course app itself turns course mode on.
func _hello_came(_result: int, code: int, headers: PackedStringArray, _body: PackedByteArray) -> void:
	var says_contract := false
	for header in headers:
		says_contract = says_contract or header.to_lower().begins_with(CONTRACT_HEADER + ":")
	if code == HTTPClient.RESPONSE_UPGRADE_REQUIRED:
		_refused()
		return
	if code != 200 or not says_contract:
		return
	app_up = true
	_show_up(true)
	sent = ""
	look_in = 0.0
	retry_in = 0.0


# ---------------------------------------------------------------- what's on screen

# The window he's working in: a dialog when one is open (Create New Node, a file dialog), else the editor.
func _front() -> Window:
	var main := EditorInterface.get_base_control().get_window()
	var front := main
	for w in main.find_children("*", "AcceptDialog", true, false):
		if (w as Window).visible:
			front = w
	return front


func _state() -> Dictionary:
	places = {}
	labels = {}
	wins = {}
	fields = {}
	nodes = {}
	var targets: Array = []
	var base := EditorInterface.get_base_control()
	var front := _front()
	var root: Node = base if front == base.get_window() else front
	var screen := Rect2(Vector2.ZERO, front.size)
	var here := func(c: Control) -> bool: return c.is_visible_in_tree() and c.get_window() == front and screen.intersects(c.get_global_rect())
	for b in root.find_children("*", "BaseButton", true, false):
		if b == self.button or (b as BaseButton).disabled:
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
	for t in root.find_children("*", "Tree", true, false):
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
	for f in root.find_children("*", "LineEdit", true, false):
		var field: LineEdit = f
		if field.secret:
			continue
		var hint := field.placeholder_text.strip_edges().replace("]", ")")
		if hint == "" and front != base.get_window():
			hint = "Search"           # a dialog's unnamed box is its search box
		if here.call(field) and field.editable and hint != "" and not (ask_box and ask_box.is_ancestor_of(field)):
			_add(targets, "field:" + hint, "the \"%s\" text field" % hint, _control_place(field), front, field)
			fields["field:" + hint] = weakref(field)
	for p in root.find_children("*", "EditorProperty", true, false):
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
