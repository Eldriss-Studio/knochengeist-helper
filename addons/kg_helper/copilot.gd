@tool
extends RefCounted
# GitHub Copilot CLI, for people whose AI plan is Copilot (Free included). It answers with
# `--output-format json` and every tool off, its own instructions and the person's MCP servers ignored,
# in a home of its own so the helper's questions stay out of the person's Copilot history. It has no
# free way to check sign-in, so the first question finds out. It answers all at once, and reports no
# plan usage.

const Finder := preload("finder.gd")

const ID := "copilot"
const NAME := "Copilot"
const LABEL := "Copilot (GitHub Copilot plan)"
const COMPANY := "GitHub"
const PATH_SETTING := "knochengeist/copilot_path"
const MODEL_SETTING := "knochengeist/copilot_model"
const ENV := "KG_HELPER_COPILOT"
const COMMAND := "copilot"
const INSTALL_PAGE := "https://docs.github.com/en/copilot/how-tos/copilot-cli"
const INSTALL_HINT := "Not installed yet. Use Install… above, or choose where it is."
const LOGIN_HINT := "copilot login"
const AUTH_ARGS := []                # no free check: checking while signed in would spend a request
const CHECKS_SIGN_IN := false
const SIGNED_OUT_SAYS := ["no authentication information found", "authentication failed"]
const MODEL_HINT := "Copilot chooses the model. You can't change it here."
const MODELS := []                   # Free plans can only use Auto, so the helper never picks one
const REPORTS_RESETS := false
const SIGN_IN_CAN_BE_SKIPPED := false
const PROBLEMS := {
	"missing": "Copilot isn't installed. Pick Install Copilot… in the ghost's menu, sign in with copilot login, then ask again.",
	"signed_out": "Copilot isn't signed in. Open a terminal, run copilot login, and sign in. Then ask again.",
	"limit": "You've reached your Copilot plan's limit for now. Try again later.",
	"not_there": "There's no Copilot at the path in Settings. Open Settings in the ghost's menu to change it.",
	"unknown": "Copilot answered in a format this helper doesn't understand. This helper may need an update. Show log has what it said.",
	"billing": "Copilot reports a billing problem with your account. Check it at github.com/settings/copilot.",
}
const NO_TOOLS := ["--output-format", "json", "--available-tools=", "--deny-tool=shell,write,read,url,memory",
	"--no-custom-instructions", "--disable-builtin-mcps", "--no-ask-user", "--no-auto-update", "--sync-session=off"]
const KNOWN_EVENTS := ["session.", "assistant.", "tool.", "user.", "model.", "commands.", "instruction."]   # event types it sends besides the three read here
const LAST_ANSWER := "copilot_answer"   # the latest message with text, kept on the brain until the result line


static func find_automatically() -> String:
	return Finder.find(COMMAND, ["/.local/bin/copilot", "/.npm-global/bin/copilot"], ["/opt/homebrew/bin/copilot", "/usr/local/bin/copilot"],
		[OS.get_environment("APPDATA").path_join("npm/copilot.cmd"), OS.get_environment("LOCALAPPDATA").path_join("Microsoft/WinGet/Links/copilot.exe")])


## Its own installer, which needs no Node, for a terminal the person watches.
static func install_args() -> PackedStringArray:
	if OS.get_name() == "Windows":
		return PackedStringArray(["winget", "install", "GitHub.Copilot"])
	return PackedStringArray(["/bin/sh", "-c", "curl -fsSL https://gh.io/copilot-install | bash"])


static func model_from(_saved: String) -> String:
	return ""


static func login_args(path: String) -> PackedStringArray:
	return PackedStringArray([path, "login"])


## A home of its own, so the helper's questions stay out of his Copilot history. It finds his sign-in
## (kept in his keychain) through the account his own Copilot names in config.json, so only those
## two account fields are copied, fresh each time: never a token.
static func process_env() -> Dictionary:
	var home := OS.get_user_data_dir().path_join("kg_helper").path_join("copilot-home")
	DirAccess.make_dir_recursive_absolute(home)
	var account := {}
	var his: Dictionary = _his_config()
	for key in ["loggedInUsers", "lastLoggedInUser"]:
		if his.has(key):
			account[key] = his[key]
	var file := FileAccess.open(home.path_join("config.json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(account))
		file.close()
	return {"COPILOT_HOME": home}


## His own Copilot's config.json, which starts with // comment lines.
static func _his_config() -> Dictionary:
	var his_home := OS.get_environment("COPILOT_HOME")
	if his_home == "":
		his_home = OS.get_environment("USERPROFILE" if OS.get_name() == "Windows" else "HOME").path_join(".copilot")
	var lines := PackedStringArray()
	for line in FileAccess.get_file_as_string(his_home.path_join("config.json")).split("\n"):
		if not line.strip_edges().begins_with("//"):
			lines.append(line)
	var parsed = JSON.parse_string("\n".join(lines))
	return parsed if parsed is Dictionary else {}


static func check_state(_brain, _exit_code: int, _said: String, _also: String) -> String:
	return "ready"                       # never asked: AUTH_ARGS is empty


## Starts one question. Copilot takes no system prompt, so the instructions go first in the text it
## reads from stdin. That also keeps a question that starts with / or @ from being read as a command.
static func start(brain, program: String, dir: String, system_file: String, prompt: String, _model: String) -> Dictionary:
	var work := dir.path_join("copilot-work")
	DirAccess.make_dir_recursive_absolute(work)
	brain.asking_file = dir.path_join("question-%d-%d.txt" % [OS.get_process_id(), brain.question])
	var file := FileAccess.open(brain.asking_file, FileAccess.WRITE)
	if file == null:
		return {}
	file.store_string(FileAccess.get_file_as_string(system_file) + "\n\n" + prompt)
	file.close()
	if brain.has_meta(LAST_ANSWER):
		brain.remove_meta(LAST_ANSWER)
	var flags := PackedStringArray(NO_TOOLS)
	flags.append_array(["-C", work])
	return brain._start_from_file(program, dir, flags, brain.asking_file)


## One line of its JSONL output, into the brain. False for a line it doesn't know.
static func read(brain, event: Dictionary) -> bool:
	var type := str(event.get("type", ""))
	var data = event.get("data", {})
	if not data is Dictionary:
		data = {}
	if type == "assistant.message":
		if str(data.get("content", "")) != "":
			brain.set_meta(LAST_ANSWER, str(data["content"]))   # a tool call's message has none
	elif type == "session.error":
		var words := str(data.get("message", ""))
		var kind := str(data.get("errorType", "")).to_lower()
		brain.said_wrong += words + "\n"
		brain.hit_limit = brain.hit_limit or kind.contains("rate") or words.to_lower().contains("rate limit")
		brain.auth_failed = brain.auth_failed or kind.contains("auth")
	elif type == "result":
		brain.got_result = true
		brain.ended_badly = int(event.get("exitCode", 0)) != 0
		if not brain.ended_badly and brain.has_meta(LAST_ANSWER):
			brain.add_text(brain.get_meta(LAST_ANSWER))
	else:
		return KNOWN_EVENTS.any(func(prefix: String) -> bool: return type.begins_with(prefix))
	return true
