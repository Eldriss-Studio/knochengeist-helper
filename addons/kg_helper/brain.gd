@tool
extends RefCounted

const L := preload("l10n.gd")
# The AI tool that answers when the course page isn't running: it finds the tool, checks it, asks it,
# and reads its answer. Each tool is its own adapter script (claude.gd, codex.gd, copilot.gd).

signal piece(text: String)
signal done(text: String, problem: String)      # problem: "", "missing", "signed_out" or "failed"
signal checked(state: String, path: String)     # state: "checking", "ready", "missing", "signed_out" or "not_there"

const PROBLEMS := {
	"missing": "Claude Code isn't installed. Click the ghost and choose Install Claude Code… from its menu. Then sign in once, and ask again.",
	"signed_out": "Claude Code isn't signed in. Open a terminal, run claude, and sign in. Then ask again.",
	"failed": "That didn't work. Try again, or open Show log in the ghost's menu to see why.",
	"limit": "You've reached your Claude plan's limit. Try again later.",
	"not_there": "Claude Code isn't at the file you chose. Open Settings in the ghost's menu, then choose its file again or pick Find automatically.",
	"login_skipped": "Claude Code didn't use your sign-in for this question, though it says you're signed in. This helper may need an update. Show log has the details.",
	"unknown": "Claude Code sent an answer Knochengeist can't read yet. Update Knochengeist, or open Show log to see what it said.",
	"billing": "Claude Code reports a billing problem with your account. Check it at claude.ai.",
}

const DISCLOSURE := "To answer, Knochengeist runs your Claude Code on this computer.\n\nEach question sends to Anthropic, using your account:\n• your question\n• the open scene's file name and the selected node\n• the names of what's on your screen in Godot: buttons, nodes in the Scene dock, files and folders in lists, Inspector properties and hints in text boxes\n• during a walk-through, what you clicked and typed in the boxes it pointed at\n• when you ask about something you right-clicked: its name, or the code you selected\n• in a follow-up, your last few questions and answers in that conversation\n• when your question names something in Godot, its reference pages from your own Godot\n• when you ask about an error from your game: its text and the script lines around it\n\nIt never sends your password or sign-in, and it sends nothing else.\n\nSeparately, once a day it asks GitHub whether a newer helper is out (turn that off in Settings), and once per Godot version it downloads Godot's manual from GitHub."
const GIVE_UP_S := 120.0
const SHELL_GIVE_UP_S := 8.0
const CHECK_GIVE_UP_S := 15.0
const LOG_MAX_CHARS := 65536
const STOP_GRACE_S := 2.0
const UNKNOWN_KEPT := 400
const LOG_KEPT_CHARS := 32768
const ERRORS_KEPT := 2000
const MODELS := ["sonnet", "fable", "opus", "haiku"]      # Claude Code's, which Settings lists
const CLAUDE_PATH_SETTING := "knochengeist/claude_path"
const MODEL_SETTING := "knochengeist/model"
const LESS_MOTION_SETTING := "knochengeist/less_motion"
const EXIT_UNKNOWN := -1
const NEWLINE := 10
const Claude := preload("claude.gd")
const Codex := preload("codex.gd")
const Copilot := preload("copilot.gd")
# Every AI tool the helper can answer through, by id. To add one (Copilot CLI, Cursor CLI…): copy
# codex.gd, give it every name below, add it here, and give its tests a stand-in like fake-codex.ts.
# A test checks each tool here has the whole surface.
const TOOLS := {"claude": Claude, "codex": Codex, "copilot": Copilot}
const ADAPTER_CONSTANTS := ["ID", "NAME", "LABEL", "COMPANY", "PATH_SETTING", "MODEL_SETTING", "ENV", "COMMAND",
	"INSTALL_PAGE", "INSTALL_HINT", "LOGIN_HINT", "AUTH_ARGS", "MODELS", "MODEL_HINT", "REPORTS_RESETS",
	"SIGN_IN_CAN_BE_SKIPPED", "CHECKS_SIGN_IN", "SIGNED_OUT_SAYS", "PROBLEMS"]
const ADAPTER_FUNCTIONS := ["find_automatically", "model_from", "login_args", "check_state", "start", "read", "process_env", "install_args"]
const TOOL_SETTING := "knochengeist/tool"
# Codex reads its question from stdin to the end, so a shell hands it the question's file.
const RUN_FROM_FILE := "cd \"$1\" && f=\"$2\" && shift 2 && exec \"$0\" \"$@\" < \"$f\""
# Godot's one pipe can't close the tool's input on its own, so a shell hands it the prompt file.
const RUN := "cd \"$1\" && shift && exec \"$0\" \"$@\""   # in the helper's own folder, not the game's

var checking_tool: GDScript = null   # set when Settings checks a tool that isn't the one in use yet
var pid := 0
var io: FileAccess
var errors: FileAccess
var unread := PackedByteArray()
var text := ""
var auth_failed := false
var ended_badly := false
var hit_limit := false
var billing_failed := false
var said_wrong := ""
var auth_method := ""
var plan_name := ""                # "Claude Max 20x"; "" with an API key or before the check
var limit := {}                    # the last run's: kind, used (0 to 1), status, resets_at (Unix seconds)
var last_cost := -1.0
var answered_by := ""              # the model that answered last, as Claude Code names it: claude-fable-5-2
var windows := {}                  # every usage window the last run reported: name -> used (0 to 1)
var warned := false
const LIMIT_NAMES := {"seven_day": "weekly limit", "five_hour": "5-hour limit"}
const NEAR_LIMIT := 0.8
var unknown_lines := ""
var ran_version := ""
var ran_key_source := ""
var stopping := {}                 # pid: seconds left before a hard kill, for runs asked to stop
var claude_version := ""
var check_step := ""
var check_io: FileAccess
var check_err: FileAccess                       # Codex says whether it's signed in on stderr
var waited := 0.0
var asked := ""                   # this question's system prompt file, removed when it's over
var asking_file := ""              # Codex's question file, removed with it
var got_result := false            # Claude Code said its result: the run is done, though it waits on stdin
var question := 0                 # goes up with each question, so a late answer to an old one is dropped
var state := "checking"
var check_pid := 0
var shell_pid := 0
var shell_io: FileAccess
var shell_waited := 0.0
var check_waited := 0.0
static var from_login_shell := ""


## The adapter for the AI tool the person picked (Claude Code unless they picked another).
static func adapter() -> GDScript:
	return TOOLS.get(saved_setting(TOOL_SETTING), Claude)


static func tool() -> String:
	return adapter().ID


static func tool_name() -> String:
	return adapter().NAME


static func company() -> String:
	return adapter().COMPANY


static func path_setting() -> String:
	return adapter().PATH_SETTING


static func _path_from_env() -> String:
	return OS.get_environment(adapter().ENV)


## Where the picked tool is: told by the environment, chosen in Settings, or found.
static func find_claude() -> String:
	return find_for(adapter())


## Where this tool is: told by the environment, chosen in Settings, or found.
static func find_for(tool: GDScript) -> String:
	var from_env := OS.get_environment(tool.ENV)
	if from_env != "":
		return from_env
	var chosen := saved_setting(tool.PATH_SETTING)
	if chosen != "":
		return chosen
	var found: String = tool.find_automatically()
	return found if found != "" or OS.get_name() == "Windows" or tool != adapter() else from_login_shell


static func offer_settings() -> void:
	_offer(CLAUDE_PATH_SETTING, "", {"type": TYPE_STRING, "hint": PROPERTY_HINT_GLOBAL_FILE})
	_offer(MODEL_SETTING, MODELS[0], {"type": TYPE_STRING, "hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(MODELS)})
	var settings := EditorInterface.get_editor_settings()
	if not settings.has_setting(LESS_MOTION_SETTING):
		settings.set_setting(LESS_MOTION_SETTING, false)
	settings.set_initial_value(LESS_MOTION_SETTING, false, false)
	settings.add_property_info({"name": LESS_MOTION_SETTING, "type": TYPE_BOOL})


static func less_motion() -> bool:
	var settings := EditorInterface.get_editor_settings()
	return settings.has_setting(LESS_MOTION_SETTING) and settings.get_setting(LESS_MOTION_SETTING) == true


static func _offer(name: String, initial: String, info: Dictionary) -> void:
	var settings := EditorInterface.get_editor_settings()
	if not settings.has_setting(name):
		settings.set_setting(name, initial)
	settings.set_initial_value(name, initial, false)
	info["name"] = name
	settings.add_property_info(info)


static func saved_setting(name: String) -> String:
	var settings := EditorInterface.get_editor_settings()
	return str(settings.get_setting(name)).strip_edges() if settings.has_setting(name) else ""


static func model() -> String:
	return adapter().model_from(saved_setting(adapter().MODEL_SETTING))


# The plan from `claude auth status`. Its email and organization are never read.
func _read_limit(info) -> void:
	if not (info is Dictionary):
		return
	var kind := str(info.get("rateLimitType", ""))
	var window = info.get("unifiedWindows", {}).get(kind, {}) if info.get("unifiedWindows") is Dictionary else {}
	var used = window.get("utilization", info.get("utilization")) if window is Dictionary else info.get("utilization")
	windows = {}
	if info.get("unifiedWindows") is Dictionary:
		for name in info["unifiedWindows"]:
			var other = info["unifiedWindows"][name]
			if other is Dictionary and (other.get("utilization") is float or other.get("utilization") is int):
				windows[name] = float(other["utilization"])
	limit = {"kind": kind, "used": float(used) if used is float or used is int else -1.0, "status": str(info.get("status", "")), "resets_at": float(info.get("resetsAt", 0))}


func billed() -> bool:
	return state == "ready" and plan_name == "" and auth_method != "" and auth_method != "claude.ai"


## The lines that say whose AI answers and how much is left, for the menu and Settings.
func plan_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if billed():
		lines.append(L.t("API key: billed per question"))
		if last_cost >= 0.0:
			lines.append(L.t("Last question cost $%.4f") % last_cost)
	elif plan_name != "":
		lines.append(L.t(plan_name))
	if usage_line() != "":
		lines.append(usage_line())
	for name in windows:
		if name != limit.get("kind", "") and not name.contains("overage") and windows[name] > 0.0:
			lines.append(L.t("%s: %d%% used") % [_window_name(name), roundi(windows[name] * 100)])
	if answered_by != "":
		lines.append(L.t("Last model: %s") % model_name(answered_by))
	return lines


## claude-fable-5-2 becomes Fable 5.2.
static func model_name(id: String) -> String:
	var parts := id.trim_prefix("claude-").split("-")
	var words := PackedStringArray()
	var numbers := PackedStringArray()
	for part in parts:
		if part.is_valid_int():
			numbers.append(part)
		else:
			words.append(part.capitalize())
	return " ".join(words) + (" " + ".".join(numbers) if not numbers.is_empty() else "")


static func _window_name(name: String) -> String:
	var said: String = {"seven_day": L.t("This week"), "five_hour": L.t("The 5-hour window")}.get(name, name.replace("_", " "))
	return said[0].to_upper() + said.substr(1)


func usage_line() -> String:
	if limit.is_empty() or float(limit.get("used", -1.0)) < 0.0:
		return ""
	return L.t("%s: %d%% used, resets %s") % [_limit_name()[0].to_upper() + _limit_name().substr(1), roundi(limit["used"] * 100), _when(limit["resets_at"])]


func warning() -> String:
	if warned or limit.is_empty() or not (limit.get("status") == "allowed_warning" or float(limit.get("used", 0.0)) >= NEAR_LIMIT):
		return ""
	warned = true
	return L.t("Heads up: you've used %d%% of your %s. It resets %s.") % [roundi(limit["used"] * 100), _limit_name(), _when(limit["resets_at"])]


func problem_message(problem: String) -> String:
	if problem == "limit" and adapter().REPORTS_RESETS and float(limit.get("resets_at", 0.0)) > 0.0:
		return L.t("You've used all of your Claude plan's %s. It resets %s.") % [_limit_name(), _when(limit["resets_at"])]
	return problem_text(problem)


func _limit_name() -> String:
	return L.t(LIMIT_NAMES.get(limit.get("kind", ""), "usage limit"))


static func _when(resets_at: float) -> String:
	var left := resets_at - Time.get_unix_time_from_system()
	if left < 3600.0:
		var minutes := maxi(1, roundi(left / 60.0))
		return L.t_n("in %d minute", "in %d minutes", minutes) % minutes
	if left < 86400.0:
		return L.t("in about %d hours") % roundi(left / 3600.0) if roundi(left / 3600.0) > 1 else L.t("in about an hour")
	return L.t("in %d days") % floori(left / 86400.0) if floori(left / 86400.0) > 1 else L.t("tomorrow")


static func problem_text(problem: String) -> String:
	if adapter().PROBLEMS.has(problem):
		return L.t(adapter().PROBLEMS[problem])
	return L.t(PROBLEMS.get(problem, PROBLEMS["failed"])).replace("Claude Code", tool_name())


## What a question sends, and to whom, for the tool in use.
static func disclosure() -> String:
	return L.t(DISCLOSURE).replace("Claude Code", tool_name()).replace("Anthropic", company())


## The tool this brain checks: the one in use, or one Settings shows before it's saved.
func _tool() -> GDScript:
	return checking_tool if checking_tool else adapter()


func check() -> void:
	stop_check()
	if state == "checking":
		_now("checking", "")
	var claude := find_for(_tool())
	if claude == "" and OS.get_environment(_tool().ENV) == "" and OS.get_name() != "Windows":
		_ask_login_shell()                # Windows has no login shell to ask
	else:
		_check_sign_in(claude)


# A Godot opened from the Dock doesn't get the PATH his Terminal has, so his login shell is asked.
func _ask_login_shell() -> void:
	var shell := OS.get_environment("SHELL")
	var started := OS.execute_with_pipe(shell if shell != "" else ("/bin/zsh" if OS.get_name() == "macOS" else "/bin/bash"), ["-lc", "command -v " + _tool().COMMAND], false)
	if started.is_empty():
		_check_sign_in("")
		return
	shell_pid = started["pid"]
	shell_io = started["stdio"]
	shell_waited = 0.0


func _check_sign_in(claude: String) -> void:
	if claude == "" or not FileAccess.file_exists(claude):
		_now(_missing(), claude)
		return
	_start_check(claude, ["--version"], "version")


func _start_check(claude: String, args: Array, step: String) -> void:
	var started := {}
	if OS.get_name() == "Windows" and claude.get_extension().to_lower() in ["cmd", "bat"]:
		started = OS.execute_with_pipe("cmd.exe", PackedStringArray(["/d", "/c", claude] + args), false)
	else:
		started = OS.execute_with_pipe(claude, PackedStringArray(args), false)
	check_err = started.get("stderr")
	check_waited = 0.0
	if started.is_empty():
		_now(_missing(), claude)
		return
	check_pid = started["pid"]
	check_io = started["stdio"]
	check_step = step


func _missing() -> String:
	var set_in_settings := OS.get_environment(_tool().ENV) == "" and saved_setting(_tool().PATH_SETTING) != ""
	return "not_there" if set_in_settings else "missing"


func _poll_check(delta: float) -> void:
	if shell_pid != 0:
		shell_waited += delta
		if OS.is_process_running(shell_pid) and shell_waited < SHELL_GIVE_UP_S:
			return
		var said := shell_io.get_buffer(shell_io.get_length()).get_string_from_utf8() if shell_io else ""
		if OS.is_process_running(shell_pid):
			OS.kill(shell_pid)
		shell_pid = 0
		shell_io = null
		for line in said.split("\n", false):
			if FileAccess.file_exists(line.strip_edges()):
				from_login_shell = line.strip_edges()
		_check_sign_in(find_for(_tool()))
	elif check_pid != 0:
		check_waited += delta
		if OS.is_process_running(check_pid) and check_waited < CHECK_GIVE_UP_S:
			return
		var finished := not OS.is_process_running(check_pid)
		var exit_code := OS.get_process_exit_code(check_pid) if finished else EXIT_UNKNOWN
		var said := check_io.get_buffer(check_io.get_length()).get_string_from_utf8() if check_io else ""
		var step := check_step
		stop_check()
		if step == "version":
			claude_version = said.strip_edges().get_slice("\n", 0)
			if _tool().AUTH_ARGS.is_empty():
				_now("ready" if exit_code in [0, EXIT_UNKNOWN] else "wont_start", find_for(_tool()))   # no free sign-in check: the first question finds out
				return
			_start_check(find_for(_tool()), _tool().AUTH_ARGS, "auth")
			return
		var also := check_err.get_buffer(check_err.get_length()).get_string_from_utf8() if check_err else ""
		var now: String = _tool().check_state(self, exit_code, said, also)
		if now == "wont_start":
			log_line("%s check: it exited with %d. It said: %s" % [_tool().NAME, exit_code, (said + also).strip_edges().left(300).replace("\n", " ")])
		_now(now, find_for(_tool()))


func stop_check() -> void:
	for running in [shell_pid, check_pid]:
		if running != 0 and OS.is_process_running(running):
			OS.kill(running)
	shell_pid = 0
	shell_io = null
	check_pid = 0
	check_io = null
	check_step = ""


func _now(new_state: String, path: String) -> void:
	if new_state != "checking":
		log_line("%s check: %s %s" % [tool_name(), new_state, _short(path)])
	state = new_state
	checked.emit(state, path)


static func log_path() -> String:
	return OS.get_user_data_dir().path_join("kg_helper").path_join("helper.log")


static func log_line(line: String) -> void:
	DirAccess.make_dir_recursive_absolute(log_path().get_base_dir())
	var kept := FileAccess.get_file_as_string(log_path()) if FileAccess.file_exists(log_path()) else ""
	if kept.length() > LOG_MAX_CHARS:
		kept = kept.right(LOG_KEPT_CHARS)
		kept = kept.substr(kept.find("\n") + 1)
	var file := FileAccess.open(log_path(), FileAccess.WRITE)
	if file:
		file.store_string(kept + "%s  %s\n" % [Time.get_datetime_string_from_system(), line])


func debug_info(helper_version: String) -> String:
	var claude := _short(find_claude())
	var version := claude_version if claude_version != "" else "unknown"
	return "\n".join([
		"Knochengeist helper %s" % helper_version,
		"Godot %s" % Engine.get_version_info().string,
		"%s %s" % [OS.get_name(), OS.get_version()],
		"%s: %s" % [tool_name(), claude if claude != "" else "not found"],
		"%s version: %s" % [tool_name(), version],
		"Signed in with: %s" % (auth_method if auth_method != "" else "unknown"),
		"State: %s" % state,
	])


# A path in his home folder is written with ~, so a log or debug info he shares doesn't carry his name.
static func _short(path: String) -> String:
	var home := OS.get_environment("HOME")
	return "~" + path.substr(home.length()) if home != "" and path.begins_with(home) else path


func busy() -> bool:
	return pid != 0


## For an editor not in English: answer in its language, and keep on-screen names as they are.
static func language_line() -> String:
	var locale := TranslationServer.get_tool_locale()   # what the editor shows, "auto" resolved to the Mac's language
	if locale == "" or locale == "en" or locale.begins_with("en_"):
		return ""
	return "\n\nWrite everything you say to them in %s, the language their Godot editor is set to. Copy the names of buttons, fields and nodes exactly as they appear on screen, in tags and in words." % _language_name(locale)


# "Portuguese, Brazil" reads as "Portuguese (Brazil)" in a sentence.
static func _language_name(locale: String) -> String:
	var parts := TranslationServer.get_locale_name(locale).split(", ", false, 1)
	return parts[0] + (" (%s)" % parts[1] if parts.size() > 1 else "")


func ask(system: String, prompt: String) -> void:
	system += language_line()
	stop()
	var claude := find_claude()
	if claude == "" or not FileAccess.file_exists(claude):
		_finish.call_deferred(_missing(), question)
		return
	var dir := OS.get_user_data_dir().path_join("kg_helper")
	DirAccess.make_dir_recursive_absolute(dir)
	asked = dir.path_join("system-%d-%d.txt" % [OS.get_process_id(), question])
	var file := FileAccess.open(asked, FileAccess.WRITE)
	if file == null:
		_finish.call_deferred("failed", question)
		return
	file.store_string(system)
	file.close()
	var before := _set_env(adapter().process_env())
	var started: Dictionary = adapter().start(self, claude, dir, asked, prompt, model())
	_set_env(before)                      # the child copied its environment when it started
	if started.is_empty():
		_finish.call_deferred("failed", question)
		return
	pid = started["pid"]
	io = started["stdio"]
	got_result = false
	errors = started["stderr"]
	unread = PackedByteArray()
	text = ""
	auth_failed = false
	ended_badly = false
	hit_limit = false
	billing_failed = false
	said_wrong = ""
	unknown_lines = ""
	ran_version = ""
	ran_key_source = ""
	waited = 0.0


# Claude Code in the helper's folder: through sh on a Mac or Linux; on Windows straight, since its
# arguments are all plain flags and paths now.
static func _start(claude: String, dir: String, flags: PackedStringArray) -> Dictionary:
	if OS.get_name() == "Windows":
		# Blocking pipes: a non-blocking one on Windows makes Claude Code's first read of an empty stdin
		# look like its end, so the question never arrives. The helper only reads what's already there.
		if claude.get_extension().to_lower() in ["cmd", "bat"]:
			var through := PackedStringArray(["/d", "/c", claude])
			through.append_array(flags)
			return OS.execute_with_pipe("cmd.exe", through, true)
		return OS.execute_with_pipe(claude, flags, true)
	var args := PackedStringArray(["-c", RUN, claude, dir])
	args.append_array(flags)
	return OS.execute_with_pipe("/bin/sh", args, false)


# A tool that reads its question from stdin to the end: stdin is the question's file.
static func _start_from_file(program: String, dir: String, flags: PackedStringArray, input: String) -> Dictionary:
	if OS.get_name() == "Windows":
		var line := PackedStringArray(["\"%s\"" % program])
		for flag in flags:
			line.append("\"%s\"" % flag.replace("\"", "") if flag.contains(" ") else flag)
		line.append("< \"%s\"" % input)
		# Godot already wraps an argument with spaces in quotes, which /s takes off again: one more pair breaks it
		return OS.execute_with_pipe("cmd.exe", PackedStringArray(["/d", "/s", "/c", " ".join(line)]), true)
	var args := PackedStringArray(["-c", RUN_FROM_FILE, program, dir, input])
	args.append_array(flags)
	return OS.execute_with_pipe("/bin/sh", args, false)


## Ends a run and everything it started.
static func end_process(running: int, gently: bool) -> void:
	if OS.get_name() == "Windows":
		OS.create_process("taskkill", ["/PID", str(running), "/T", "/F"])
	elif gently:
		OS.create_process("/bin/kill", ["-INT", str(running)])      # SIGINT ends Claude Code's turn cleanly; OS.kill can't be caught
	else:
		OS.kill(running)


func stop() -> void:
	question += 1
	if pid != 0 and OS.is_process_running(pid):
		end_process(pid, true)
		stopping[pid] = STOP_GRACE_S
	pid = 0
	io = null
	errors = null
	if asked != "":
		DirAccess.remove_absolute(asked)
		asked = ""
	if asking_file != "":
		DirAccess.remove_absolute(asking_file)
		asking_file = ""


## Ends at once whatever was asked to stop, for when the plugin leaves.
func kill_all() -> void:
	for running in stopping.keys():
		if OS.is_process_running(running):
			end_process(running, false)
	stopping.clear()


func poll(delta: float) -> void:
	_poll_check(delta)
	for running in stopping.keys():
		stopping[running] -= delta
		if not OS.is_process_running(running):
			stopping.erase(running)
		elif stopping[running] <= 0.0:
			end_process(running, false)
			stopping.erase(running)
	if pid == 0:
		return
	waited += delta
	_read()
	_keep_errors()
	if OS.is_process_running(pid) and not got_result:
		if waited > GIVE_UP_S:
			log_line("A question ended: no answer after %d s. %s said: %s" % [GIVE_UP_S, tool_name(), said_wrong.strip_edges().replace("\n", " ")])
			_end("failed")
		return
	_read()
	if unread.size() > 0:
		_line(unread.get_string_from_utf8())
	_keep_errors()
	for words in adapter().SIGNED_OUT_SAYS:     # what a tool that says it on stderr says
		auth_failed = auth_failed or said_wrong.to_lower().contains(words)
	var crashed := not got_result and OS.get_process_exit_code(pid) not in [0, EXIT_UNKNOWN]
	var failed := ended_badly or crashed or text.strip_edges() == ""
	var wrong := said_wrong.to_lower()
	var limit_hit := failed and (wrong.contains("usage limit") or (hit_limit and (wrong.contains("limit") or wrong.contains("429"))))
	var billing := failed and billing_failed and (wrong.contains("billing") or wrong.contains("credit"))
	var at_limit: bool = limit_hit or (failed and limit.get("status", "") == "rejected")
	var problem := "signed_out" if auth_failed else ("limit" if at_limit else ("billing" if billing else ("failed" if failed else "")))
	if auth_failed and state == "ready" and adapter().SIGN_IN_CAN_BE_SKIPPED:
		problem = "login_skipped"
	elif problem == "failed" and text.strip_edges() == "" and unknown_lines != "":   # no answer, and lines it didn't know: likely a newer format
		problem = "unknown"
		said_wrong += unknown_lines
	if problem != "":
		log_line("A question ended: %s (%s %s, sign-in %s). It said: %s" % [problem, tool_name(), ran_version if ran_version != "" else "?", ran_key_source if ran_key_source != "" else "?", said_wrong.strip_edges().replace("\n", " ")])
	_end(problem)


# Read even when unused: a full pipe would stall the tool.
func _keep_errors() -> void:
	if errors and errors.get_length() > 0:
		said_wrong = (said_wrong + errors.get_buffer(errors.get_length()).get_string_from_utf8()).right(ERRORS_KEPT)


func _read() -> void:
	var n := io.get_length() if io else 0
	if n <= 0:
		return
	unread.append_array(io.get_buffer(n))
	var at := unread.find(NEWLINE)
	while at >= 0:
		_line(unread.slice(0, at).get_string_from_utf8())
		unread = unread.slice(at + 1)
		at = unread.find(NEWLINE)


func _line(raw: String) -> void:
	var event = JSON.parse_string(raw)
	if not (event is Dictionary) or not adapter().read(self, event):
		if unknown_lines.length() < UNKNOWN_KEPT:
			unknown_lines += raw.left(UNKNOWN_KEPT) + "\n"
		return


## A piece of the answer, as it comes.
## Sets these environment variables in Godot's own process, for a child about to start, and returns
## what they were so they can be put back. OS.execute_with_pipe takes no environment of its own.
static func _set_env(vars: Dictionary) -> Dictionary:
	var before := {}
	for key in vars:
		before[key] = OS.get_environment(key) if OS.has_environment(key) else null
		if vars[key] == null:
			OS.unset_environment(key)
		else:
			OS.set_environment(key, vars[key])
	return before


func add_text(more: String) -> void:
	if more == "":
		return
	text += more
	piece.emit(more)


# The question is over: everything about it goes, then the answer is given.
func _end(problem: String) -> void:
	var for_question := question
	stop()
	_finish(problem, for_question + 1)


func _finish(problem: String, for_question: int) -> void:
	if for_question != question:
		return
	if problem in ["missing", "not_there", "signed_out"]:
		stop_check()
		_now(_missing() if problem == "missing" else problem, find_claude())
	elif problem == "" and state != "ready":
		stop_check()
		_now("ready", find_claude())
	done.emit(text, problem)
