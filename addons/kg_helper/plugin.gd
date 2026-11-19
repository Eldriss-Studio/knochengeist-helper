@tool
extends EditorPlugin
# The Knochengeist helper (#44). Tells the course app what this editor shows, the things on screen
# Stuck? may name (buttons, scene tree rows, inspector properties), and points at the one it names
# with a flying ghost and an inked ring (pointer.gd). The app's side is course/src/lib/server/godot-link.ts.
#
# It talks to the app through app.gd, and reads what's on screen through screen.gd.
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
const Screen := preload("screen.gd")
const App := preload("app.gd")
const Walk := preload("walk.gd")
const CHECK_UPDATES_AFTER_S := 5.0
const SLOTS := [EditorContextMenuPlugin.CONTEXT_SLOT_SCENE_TREE, EditorContextMenuPlugin.CONTEXT_SLOT_FILESYSTEM, EditorContextMenuPlugin.CONTEXT_SLOT_SCRIPT_EDITOR_CODE, EditorContextMenuPlugin.CONTEXT_SLOT_INSPECTOR_PROPERTY]
const CODE_LINES_KEPT := 200
const COURSE_CODE_CHARS := 1200
const NOT_ALLOWED := "Claude Code wasn't run. Ask again to allow it."
const CONSENT_TITLE := "Allow Knochengeist to use Claude Code?"
const README := "https://github.com/Eldriss-Studio/knochengeist-helper#readme"
const RELEASES := "https://github.com/Eldriss-Studio/knochengeist-helper/releases"
const ISSUES := "https://github.com/Eldriss-Studio/knochengeist-helper/issues"
const ALONE := Walk.ALONE
const CONTRACT := 1              # the version of the messages it speaks; the app refuses another

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
var answer_ask := 0              # the last answer's id and the target it named
var answer_target := ""
var project := ""
var ghost: Texture2D
var note: Control                # a short line under the button: thinking, or done
var answer_plan: Array = []      # the last answer's plan, until he presses Show me
var answer_closing := ""
var walk                         # the walk-through (walk.gd)
var walk_ask: int:
	get: return walk.walk_ask
	set(value): walk.walk_ask = value
var walk_clicked: Array:
	get: return walk.walk_clicked
	set(value): walk.walk_clicked = value
var walk_plan: Array:
	get: return walk.walk_plan
	set(value): walk.walk_plan = value
var walk_i: int:
	get: return walk.walk_i
	set(value): walk.walk_i = value
var walk_closing: String:
	get: return walk.walk_closing
	set(value): walk.walk_closing = value
var walk_target: String:
	get: return walk.walk_target
	set(value): walk.walk_target = value
var typed_in: Dictionary:
	get: return walk.typed_in
	set(value): walk.typed_in = value
var pointers: Dictionary:
	get: return walk.pointers
	set(value): walk.pointers = value
var screen := Screen.new()
var places: Dictionary:          # what was on screen when it last looked, kept by screen.gd
	get: return screen.places
var labels: Dictionary:
	get: return screen.labels
var wins: Dictionary:
	get: return screen.wins
var fields: Dictionary:
	get: return screen.fields
var nodes: Dictionary:
	get: return screen.nodes
var app: Node                    # the link to the course app (app.gd)
var app_up: bool:                # the app answered on its port; until then only knock
	get: return app != null and app.app_up
var host: String:
	get: return app.host if app else ""
var port: int:
	get: return app.port if app else 0


func _init() -> void:
	walk = Walk.new(self)


func _enter_tree() -> void:
	var from_env := OS.get_environment("KG_HELPER_URL")
	if DisplayServer.get_name() == "headless" and from_env == "":
		return
	url = (from_env if from_env != "" else "http://127.0.0.1:4173").trim_suffix("/")
	project = ProjectSettings.globalize_path("res://").trim_suffix("/")
	app = App.new(url, project, CONTRACT)
	app.went.connect(_show_up)
	app.refused.connect(_refused)
	app.pointed.connect(_point_came)
	app.next_came.connect(walk.next_came)
	add_child(app)
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
			OS.shell_open(Brain.adapter().INSTALL_PAGE)
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


## Signs in to this tool, or the one in use, in his own setup: Claude Code signs in when it's run,
## Codex with "codex login", Copilot with "copilot login".
func _sign_in(tool: GDScript = null) -> void:
	var adapter: GDScript = tool if tool else Brain.adapter()
	_open_sign_in(adapter.login_args(Brain.find_for(adapter)), adapter)


func _open_sign_in(run: PackedStringArray, adapter: GDScript) -> void:
	var terminal := OS.get_environment("KG_HELPER_TERMINAL")
	if terminal != "":
		OS.create_process(terminal, run)
	elif OS.get_name() == "macOS":
		if run.size() == 1:
			OS.create_process("open", ["-a", "Terminal", run[0]])
		else:
			# Terminal opens a file, not a command line: a small .command file runs it.
			var script := OS.get_user_data_dir().path_join("kg_helper").path_join("sign-in.command")
			DirAccess.make_dir_recursive_absolute(script.get_base_dir())
			var file := FileAccess.open(script, FileAccess.WRITE)
			if file:
				var line := PackedStringArray()
				for part in run:
					line.append("'%s'" % part.replace("'", "'\\''"))
				file.store_string("#!/bin/sh\nexec %s\n" % " ".join(line))
				file.close()
				OS.execute("chmod", ["+x", script])
				OS.create_process("open", ["-a", "Terminal", script])
	elif OS.get_name() == "Windows":
		var console := PackedStringArray(["/c", "start", "", "cmd.exe", "/k"])
		console.append_array(run)
		OS.create_process("cmd.exe", console)
	else:
		# Linux: the default terminal, or the first common one there is
		for app in [["x-terminal-emulator", "-e"], ["gnome-terminal", "--"], ["konsole", "-e"], ["xterm", "-e"]]:
			var found := _on_path(app[0])
			if found != "":
				var args := PackedStringArray([app[1]])
				args.append_array(run)
				OS.create_process(found, args)
				return
		_note("Open a terminal, run %s, and sign in. Then ask again." % adapter.LOGIN_HINT, 10.0)


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
	window.title = CONSENT_TITLE.replace("Claude Code", Brain.tool_name())
	window.dialog_text = Brain.disclosure()
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
			ask_box.failed(NOT_ALLOWED.replace("Claude Code", Brain.tool_name()))
		else:
			walk_ask = 0
			_note(NOT_ALLOWED.replace("Claude Code", Brain.tool_name()), 6.0))
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
	words.text = "Knochengeist helper, version %s.\nAsk anything about Godot with %s. Answers come from your %s, or from the course page when it's running." % [_version(), Menu.ask_keys(), Brain.tool_name()]
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
	words.text = Brain.disclosure()
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
		hello.say("[b]I'm here[/b], but there's a problem: %s. Click the ghost above to fix it." % Menu.state(course_shown, claude_state).to_lower().replace(Brain.tool_name().to_lower(), Brain.tool_name()), 260.0)
	var base := EditorInterface.get_base_control()
	base.add_child(hello)
	hello.position = _under_button(hello)
	var gone := hello
	get_tree().create_timer(9.0).timeout.connect(func(): if is_instance_valid(gone): gone.queue_free())


func _process(delta: float) -> void:
	if url == "":
		return
	for card in [note, hello, ask_box]:       # the cards under the button grow as their words change: keep them inside the window
		if card and is_instance_valid(card) and card.visible:
			card.position = _under_button(card)
	walk.tick(delta)
	errors_in -= delta
	if errors_in <= 0.0:
		errors_in = LOOK_FOR_ERRORS_S
		_look_for_errors()
	ask_stream.poll(delta)
	brain.poll(delta)
	app.poll(delta, _state)


# The app speaks another contract version: app.gd stops knocking for a while.
func _refused() -> void:
	_show_up(false)
	_note("The course app and this helper are different versions. Reload this project: Project > Reload Current Project.", App.REFUSED_S)


func _point_came(answer: Dictionary) -> void:
	if places.has(answer["target"]):
		# he pressed Show me on the course page: start (or restart) the walk from that ask
		walk_ask = int(answer["ask"]) if answer.get("ask") != null else 0
		walk_clicked = []
		typed_in = {}
		walk_plan = []
		_point(answer["target"], _say(answer["target"]))


# ---------------------------------------------------------------- pointing, and going on (walk.gd)

func _point(id: String, text: String) -> void:
	walk.point(id, text)


func _stop_pointing() -> void:
	walk.stop_pointing()


func _next_reply(reply: Dictionary) -> void:
	walk.next_reply(reply)


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
	if not ask_stream.post(host, port, "/api/godot/ask", app.headers(true), JSON.stringify({"project": project, "said": said, "stream": true})):
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
		app.refuse()
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
		app.tell_shown(answer_ask)


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


# ---------------------------------------------------------------- what's on screen (screen.gd)

func _front() -> Window:
	return Screen.front_window()


func _state() -> Dictionary:
	return screen.read(project, button, ask_box)
