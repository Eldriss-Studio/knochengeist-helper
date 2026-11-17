@tool
extends RefCounted
# Claude Code, as the helper's brain when the course app isn't running. Another AI tool is another
# script with the same signals and functions.

signal piece(text: String)
signal done(text: String, problem: String)      # problem: "", "missing", "signed_out" or "failed"
signal checked(state: String, path: String)     # state: "checking", "ready", "missing", "signed_out" or "not_there"

const PROBLEMS := {
	"missing": "Claude Code isn't installed. Install it from claude.com/claude-code, sign in once in Terminal, then ask again.",
	"signed_out": "Claude Code isn't signed in. Open Terminal, run claude, and sign in. Then ask again.",
	"failed": "That didn't work. Try again, or open Show log in the ghost's menu to see why.",
	"limit": "You've reached your Claude plan's limit. Try again later.",
	"not_there": "There's no Claude Code at the path in Settings. Open Settings in the ghost's menu to change it.",
	"login_skipped": "Claude Code didn't use your sign-in for this question, though it says you're signed in. This helper may need an update. Show log has the details.",
	"unknown": "Claude Code answered in a format this helper doesn't understand. This helper may need an update. Show log has what it said.",
	"billing": "Claude Code reports a billing problem with your account. Check it at claude.ai.",
}

const DISCLOSURE := "To answer, Knochengeist runs your Claude Code on this computer.\n\nEach question sends to Anthropic, using your account:\n• your question\n• the open scene's file name and the selected node\n• the names of what's on your screen in Godot: buttons, nodes in the Scene dock, files and folders in lists, Inspector properties and hints in text boxes\n• during a walk-through, what you clicked and typed in the boxes it pointed at\n• when you ask about something you right-clicked: its name, or the code you selected\n\nIt never sends passwords, stores no logins, and sends nothing else.\n\nSeparately, once a day it asks GitHub whether a newer helper is out. Turn that off in Settings."
const GIVE_UP_S := 120.0
const SHELL_GIVE_UP_S := 8.0
const CHECK_GIVE_UP_S := 15.0
const LOG_MAX_CHARS := 65536
const STOP_GRACE_S := 2.0
const UNKNOWN_KEPT := 400
const LOG_KEPT_CHARS := 32768
const ERRORS_KEPT := 2000
const SIGNED_OUT_EXIT := 1
const MODELS := ["sonnet", "fable", "opus", "haiku"]
const CLAUDE_PATH_SETTING := "knochengeist/claude_path"
const MODEL_SETTING := "knochengeist/model"
const LESS_MOTION_SETTING := "knochengeist/less_motion"
const EXIT_UNKNOWN := -1
const INSTALL_PLACES := ["/.local/bin/claude", "/.claude/local/claude"]
const SYSTEM_PLACES := ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
const NEWLINE := 10
# Godot's one pipe can't close the tool's input on its own, so a shell hands it the prompt file.
const RUN := "cd \"$1\" && f=\"$2\" && shift 2 && exec \"$0\" \"$@\" < \"$f\""

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
var knew_a_line := false
var unknown_lines := ""
var ran_version := ""
var ran_key_source := ""
var stopping := {}                 # pid: seconds left before a hard kill, for runs asked to stop
var claude_version := ""
var check_step := ""
var check_io: FileAccess
var waited := 0.0
var asked := ""                   # this question's prompt file, removed when it's over
var question := 0                 # goes up with each question, so a late answer to an old one is dropped
var state := "checking"
var check_pid := 0
var shell_pid := 0
var shell_io: FileAccess
var shell_waited := 0.0
var check_waited := 0.0
static var from_login_shell := ""


static func find_claude() -> String:
	var from_env := OS.get_environment("KG_HELPER_CLAUDE")
	if from_env != "":
		return from_env
	var chosen := saved_setting(CLAUDE_PATH_SETTING)
	if chosen != "":
		return chosen
	return find_claude_automatically()


## Where Claude Code is when nobody chose a path: the usual places, the PATH, then the login shell.
static func find_claude_automatically() -> String:
	var home := OS.get_environment("HOME")
	for place in INSTALL_PLACES:
		if FileAccess.file_exists(home + place):
			return home + place
	for place in SYSTEM_PLACES:
		if FileAccess.file_exists(place):
			return place
	for dir in OS.get_environment("PATH").split(":", false):
		if FileAccess.file_exists(dir.path_join("claude")):
			return dir.path_join("claude")
	return from_login_shell


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
	var chosen := saved_setting(MODEL_SETTING)
	return chosen if chosen in MODELS else MODELS[0]


# The plan from `claude auth status`. Its email and organization are never read.
static func _plan_name(status: Dictionary) -> String:
	var tier := str(status.get("planTier", status.get("subscriptionType", "")))
	if tier == "" or tier == "<null>":
		return ""
	var words := tier.split("_")
	var named := "Claude " + words[0].capitalize()
	return named + (" " + " ".join(words.slice(1)) if words.size() > 1 else "")


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
		lines.append("API key: billed per question")
		if last_cost >= 0.0:
			lines.append("Last question cost $%.4f" % last_cost)
	elif plan_name != "":
		lines.append(plan_name)
	if usage_line() != "":
		lines.append(usage_line())
	for name in windows:
		if name != limit.get("kind", "") and not name.contains("overage") and windows[name] > 0.0:
			lines.append("%s: %d%% used" % [_window_name(name), roundi(windows[name] * 100)])
	if answered_by != "":
		lines.append("Last model: " + model_name(answered_by))
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
	var said := name.replace("seven_day", "this week").replace("five_hour", "the 5-hour window").replace("_", " ")
	return said[0].to_upper() + said.substr(1)


func usage_line() -> String:
	if limit.is_empty() or float(limit.get("used", -1.0)) < 0.0:
		return ""
	return "%s: %d%% used, resets %s" % [_limit_name()[0].to_upper() + _limit_name().substr(1), roundi(limit["used"] * 100), _when(limit["resets_at"])]


func warning() -> String:
	if warned or limit.is_empty() or not (limit.get("status") == "allowed_warning" or float(limit.get("used", 0.0)) >= NEAR_LIMIT):
		return ""
	warned = true
	return "Heads up: you've used %d%% of your %s. It resets %s." % [roundi(limit["used"] * 100), _limit_name(), _when(limit["resets_at"])]


func problem_message(problem: String) -> String:
	if problem == "limit" and float(limit.get("resets_at", 0.0)) > 0.0:
		return "You've used all of your Claude plan's %s. It resets %s." % [_limit_name(), _when(limit["resets_at"])]
	return problem_text(problem)


func _limit_name() -> String:
	return LIMIT_NAMES.get(limit.get("kind", ""), "usage limit")


static func _when(resets_at: float) -> String:
	var left := resets_at - Time.get_unix_time_from_system()
	if left < 3600.0:
		return "in %d minutes" % maxi(1, roundi(left / 60.0))
	if left < 86400.0:
		return "in about %d hours" % roundi(left / 3600.0) if roundi(left / 3600.0) > 1 else "in about an hour"
	return "in %d days" % floori(left / 86400.0) if floori(left / 86400.0) > 1 else "tomorrow"


static func problem_text(problem: String) -> String:
	return PROBLEMS.get(problem, PROBLEMS["failed"])


func check() -> void:
	stop_check()
	if state == "checking":
		_now("checking", "")
	var claude := find_claude()
	if claude == "" and OS.get_environment("KG_HELPER_CLAUDE") == "":
		_ask_login_shell()
	else:
		_check_sign_in(claude)


# A Godot opened from the Dock doesn't get the PATH his Terminal has, so his login shell is asked.
func _ask_login_shell() -> void:
	var shell := OS.get_environment("SHELL")
	var started := OS.execute_with_pipe(shell if shell != "" else "/bin/zsh", ["-lc", "command -v claude"], false)
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
	var started := OS.execute_with_pipe(claude, PackedStringArray(args), false)
	check_waited = 0.0
	if started.is_empty():
		_now(_missing(), claude)
		return
	check_pid = started["pid"]
	check_io = started["stdio"]
	check_step = step


func _missing() -> String:
	var set_in_settings := OS.get_environment("KG_HELPER_CLAUDE") == "" and saved_setting(CLAUDE_PATH_SETTING) != ""
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
		_check_sign_in(find_claude())
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
			_start_check(find_claude(), ["auth", "status"], "auth")
			return
		var status = JSON.parse_string(said)
		auth_method = str(status.get("authMethod", "")) if status is Dictionary else ""
		plan_name = _plan_name(status) if status is Dictionary else ""
		var now := "ready" if exit_code in [0, EXIT_UNKNOWN] else ("signed_out" if exit_code == SIGNED_OUT_EXIT else "wont_start")
		if now == "wont_start":
			log_line("Claude Code check: it exited with %d. It said: %s" % [exit_code, said.strip_edges().left(300).replace("\n", " ")])
		_now(now, find_claude())


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
		log_line("Claude Code check: %s %s" % [new_state, _short(path)])
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
		"Claude Code: %s" % (claude if claude != "" else "not found"),
		"Claude Code version: %s" % version,
		"Signed in with: %s" % (auth_method if auth_method != "" else "unknown"),
		"State: %s" % state,
	])


# A path in his home folder is written with ~, so a log or debug info he shares doesn't carry his name.
static func _short(path: String) -> String:
	var home := OS.get_environment("HOME")
	return "~" + path.substr(home.length()) if home != "" and path.begins_with(home) else path


func busy() -> bool:
	return pid != 0


func ask(system: String, prompt: String) -> void:
	stop()
	var claude := find_claude()
	if claude == "" or not FileAccess.file_exists(claude):
		_finish.call_deferred(_missing(), question)
		return
	var dir := OS.get_user_data_dir().path_join("kg_helper")
	DirAccess.make_dir_recursive_absolute(dir)
	asked = dir.path_join("question-%d-%d.txt" % [OS.get_process_id(), question])
	var file := FileAccess.open(asked, FileAccess.WRITE)
	if file == null:
		_finish.call_deferred("failed", question)
		return
	file.store_string(prompt)
	file.close()
	var args := PackedStringArray(["-c", RUN, claude, dir, asked, "-p", "--model", model(), "--tools", "",
		"--setting-sources", "", "--strict-mcp-config", "--no-session-persistence",
		"--output-format", "stream-json", "--verbose", "--include-partial-messages", "--system-prompt", system])
	var started := OS.execute_with_pipe("/bin/sh", args, false)
	if started.is_empty():
		_finish.call_deferred("failed", question)
		return
	pid = started["pid"]
	io = started["stdio"]
	errors = started["stderr"]
	unread = PackedByteArray()
	text = ""
	auth_failed = false
	ended_badly = false
	hit_limit = false
	billing_failed = false
	said_wrong = ""
	knew_a_line = false
	unknown_lines = ""
	ran_version = ""
	ran_key_source = ""
	waited = 0.0


func stop() -> void:
	question += 1
	if pid != 0 and OS.is_process_running(pid):
		OS.create_process("/bin/kill", ["-INT", str(pid)])      # SIGINT ends Claude Code's turn cleanly; OS.kill can't be caught
		stopping[pid] = STOP_GRACE_S
	pid = 0
	io = null
	errors = null
	if asked != "":
		DirAccess.remove_absolute(asked)
		asked = ""


## Ends at once whatever was asked to stop, for when the plugin leaves.
func kill_all() -> void:
	for running in stopping.keys():
		if OS.is_process_running(running):
			OS.kill(running)
	stopping.clear()


func poll(delta: float) -> void:
	_poll_check(delta)
	for running in stopping.keys():
		stopping[running] -= delta
		if not OS.is_process_running(running):
			stopping.erase(running)
		elif stopping[running] <= 0.0:
			OS.kill(running)
			stopping.erase(running)
	if pid == 0:
		return
	waited += delta
	_read()
	_keep_errors()
	if OS.is_process_running(pid):
		if waited > GIVE_UP_S:
			log_line("A question ended: no answer after %d s. Claude Code said: %s" % [GIVE_UP_S, said_wrong.strip_edges().replace("\n", " ")])
			_end("failed")
		return
	_read()
	if unread.size() > 0:
		_line(unread.get_string_from_utf8())
	_keep_errors()
	var crashed := OS.get_process_exit_code(pid) not in [0, EXIT_UNKNOWN]
	var failed := ended_badly or crashed or text.strip_edges() == ""
	var wrong := said_wrong.to_lower()
	var limit_hit := failed and (wrong.contains("usage limit") or (hit_limit and (wrong.contains("limit") or wrong.contains("429"))))
	var billing := failed and billing_failed and (wrong.contains("billing") or wrong.contains("credit"))
	var at_limit: bool = limit_hit or (failed and limit.get("status", "") == "rejected")
	var problem := "signed_out" if auth_failed else ("limit" if at_limit else ("billing" if billing else ("failed" if failed else "")))
	if auth_failed and state == "ready":
		problem = "login_skipped"
	elif failed and not knew_a_line and unknown_lines != "":
		problem = "unknown"
		said_wrong += unknown_lines
	if problem != "":
		log_line("A question ended: %s (Claude Code %s, sign-in %s). Claude Code said: %s" % [problem, ran_version if ran_version != "" else "?", ran_key_source if ran_key_source != "" else "?", said_wrong.strip_edges().replace("\n", " ")])
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
	if not (event is Dictionary) or not (event.get("type") in ["system", "stream_event", "assistant", "user", "result", "rate_limit_event"]):
		if unknown_lines.length() < UNKNOWN_KEPT:
			unknown_lines += raw.left(UNKNOWN_KEPT) + "\n"
		return
	knew_a_line = true
	if event.get("type") == "system" and event.get("subtype") == "init":
		ran_version = str(event.get("claude_code_version", ""))
		if event.get("model") is String:
			answered_by = event["model"]
		ran_key_source = str(event.get("apiKeySource", ""))
	elif event.get("type") == "stream_event":
		var delta = event.get("event", {}).get("delta", {})
		if delta is Dictionary and delta.get("type") == "text_delta" and delta.get("text") is String:
			text += delta["text"]
			piece.emit(delta["text"])
	elif event.get("type") == "assistant" and event.get("error") == "authentication_failed":
		auth_failed = true
	elif event.get("type") == "system" and event.get("subtype") == "api_retry":
		hit_limit = hit_limit or event.get("error") == "rate_limit"
		billing_failed = billing_failed or event.get("error") == "billing_error"
	elif event.get("type") == "rate_limit_event":
		_read_limit(event.get("rate_limit_info", {}))
	elif event.get("type") == "result":
		ended_badly = event.get("is_error") == true
		if event.get("total_cost_usd") is float or event.get("total_cost_usd") is int:
			last_cost = float(event["total_cost_usd"])
		if ended_badly and event.get("result") is String:
			said_wrong += event["result"] + "\n"
		if text == "" and not ended_badly and event.get("result") is String:
			text = event["result"]
			piece.emit(text)


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
