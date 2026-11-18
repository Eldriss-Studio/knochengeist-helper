@tool
extends RefCounted
# Codex, for people whose AI plan is ChatGPT. It answers through `codex exec --json` with its shell
# tool disabled, web search off, no saved session and the person's own config ignored, so only the
# question is sent. It answers all at once, and reports no plan usage.

const Finder := preload("finder.gd")

const ID := "codex"
const NAME := "Codex"
const LABEL := "Codex (ChatGPT plans)"
const COMPANY := "OpenAI"
const PATH_SETTING := "knochengeist/codex_path"
const MODEL_SETTING := "knochengeist/codex_model"
const ENV := "KG_HELPER_CODEX"
const COMMAND := "codex"
# The ChatGPT app ships Codex inside it: in /Applications, or the person's own ~/Applications.
const CHATGPT_APP := "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
const INSTALL_PAGE := "https://developers.openai.com/codex/cli"
const INSTALL_COMMAND := "npm install -g @openai/codex"
const INSTALL_HINT := "Install Codex with " + INSTALL_COMMAND + ", or choose where it is."
const LOGIN_HINT := "codex login"
const AUTH_ARGS := ["login", "status"]
const MODEL_HINT := "Codex picks its model for your ChatGPT plan."
const MODELS := []                  # Codex picks its model for the plan
const REPORTS_RESETS := false
const SIGN_IN_CAN_BE_SKIPPED := false
const PROBLEMS := {
	"missing": "Codex isn't installed. Install it with " + INSTALL_COMMAND + ", run codex login once in a terminal, then ask again.",
	"signed_out": "Codex isn't signed in. Open a terminal, run codex login, and sign in. Then ask again.",
	"limit": "You've reached your ChatGPT plan's usage limit for Codex. Try again later.",
	"not_there": "There's no Codex at the path in Settings. Open Settings in the ghost's menu to change it.",
	"unknown": "Codex answered in a format this helper doesn't understand. This helper may need an update. Show log has what it said.",
	"billing": "Codex reports a billing problem with your account. Check it at chatgpt.com.",
}


static func find_automatically() -> String:
	return Finder.find(COMMAND, ["/.local/bin/codex", "/.npm-global/bin/codex", CHATGPT_APP], ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", CHATGPT_APP],
		[OS.get_environment("APPDATA").path_join("npm/codex.cmd")])


static func model_from(saved: String) -> String:
	return saved                         # "" leaves the choice to Codex


static func login_args(path: String) -> PackedStringArray:
	return PackedStringArray([path, "login"])


## `login status` says on stderr: signed in on exit 0, signed out when it says "Not logged in",
## and otherwise it won't start.
static func check_state(brain, exit_code: int, said: String, also: String) -> String:
	var words := said + also
	brain.plan_name = "ChatGPT plan" if words.contains("ChatGPT") else ("API key" if words.to_lower().contains("api key") else "")
	brain.auth_method = "chatgpt" if brain.plan_name == "ChatGPT plan" else ("api_key" if brain.plan_name != "" else "")
	if exit_code == 0:
		return "ready"
	return "signed_out" if words.to_lower().contains("not logged in") else "wont_start"


## Starts one question. Codex reads its question from stdin to the end, so the question goes in a file
## that the shell (or cmd) hands it, with "-" telling it to read stdin.
static func start(brain, program: String, dir: String, system_file: String, prompt: String, model: String) -> Dictionary:
	brain.asking_file = dir.path_join("question-%d-%d.txt" % [OS.get_process_id(), brain.question])
	var file := FileAccess.open(brain.asking_file, FileAccess.WRITE)
	if file == null:
		return {}
	file.store_string(prompt)
	file.close()
	var flags := PackedStringArray(["exec", "--json", "--ephemeral", "--skip-git-repo-check", "--ignore-user-config",
		"--ignore-rules", "--sandbox", "read-only", "--disable", "shell_tool", "-c", "web_search=\"disabled\"",
		"-c", "model_instructions_file=%s" % system_file])
	if model != "":
		flags.append_array(["-m", model])
	flags.append("-")
	return brain._start_from_file(program, dir, flags, brain.asking_file)


## One line of `codex exec --json`, into the brain. False for a line it doesn't know.
static func read(brain, event: Dictionary) -> bool:
	var words := ""
	match str(event.get("type", "")):
		"thread.started", "turn.started", "item.started", "item.updated":
			pass
		"item.completed":
			var item = event.get("item", {})
			if item is Dictionary and item.get("type") == "agent_message":
				brain.add_text(str(item.get("text", "")))
		"turn.completed":
			brain.got_result = true
		"turn.failed":
			brain.got_result = true
			brain.ended_badly = true
			var error = event.get("error", {})
			words = str(error.get("message", "")) if error is Dictionary else str(error)
		"error":
			words = str(event.get("message", ""))
		_:
			return false
	if words != "":
		brain.said_wrong += words + "\n"
		var lower := words.to_lower()
		brain.auth_failed = brain.auth_failed or lower.contains("401") or lower.contains("unauthorized") or lower.contains("not logged in")
	return true
