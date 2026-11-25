@tool
extends RefCounted
# Claude Code, for people whose AI plan is Claude: where it is, how it's checked, how a question is
# asked, and how its stream-json answer reads. The brain asks whichever tool is picked the same way.

const Finder := preload("finder.gd")
const Sources := preload("sources.gd")
const Keys := preload("keys.gd")

const ID := "claude"
const NAME := "Claude Code"
const LABEL := "Claude Code (Claude plan)"
const THROUGH_CLAUDE_CODE := "This runs through Claude Code on this computer. You don't need a Claude plan."     # under every other source in Settings' AI list
const COMPANY := "Anthropic"
const PATH_SETTING := "knochengeist/claude_path"
const MODEL_SETTING := "knochengeist/model"
const ENV := "KG_HELPER_CLAUDE"
const COMMAND := "claude"
const INSTALL_PAGE := "https://claude.com/claude-code"
const INSTALL_HINT := "Not installed yet. Click Install…, or choose its file."
const LOGIN_HINT := "claude"
const AUTH_ARGS := ["auth", "status"]
const MODEL_HINT := ""
const EFFORT_SETTING := "knochengeist/effort"
const EFFORTS := ["low", "medium", "high"]   # how long it thinks before answering; low answers soonest
const EFFORT_HINT := ""
const MODELS := ["sonnet", "fable", "opus", "haiku"]
const REPORTS_RESETS := true        # its limit events say when the limit resets
const CHECKS_SIGN_IN := true
const SIGNED_OUT_SAYS := []          # it says so in its events, which read() handles
const SIGN_IN_CAN_BE_SKIPPED := true    # it can answer with an API key though its sign-in says otherwise
const SIGNED_OUT_EXIT := 1
const PROBLEMS := {
	"missing": "Claude Code isn't installed. Click the ghost and choose Install Claude Code… from its menu. Then sign in once, and ask again.",
	"signed_out": "Claude Code isn't signed in. Open a terminal, run claude, and sign in. Then ask again.",
	"limit": "You've reached your Claude plan's limit. Try again later.",
	"not_there": "Claude Code isn't at the file you chose. Open Settings in the ghost's menu, then choose its file again or pick Find automatically.",
	"login_skipped": "Claude Code didn't use your sign-in for this question, though it says you're signed in. This helper may need an update. Show log has the details.",
	"unknown": "Claude Code sent an answer Knochengeist can't read yet. Update Knochengeist, or open Show log to see what it said.",
	"billing": "Claude Code reports a billing problem with your account. Check it at claude.ai.",
}


static func find_automatically() -> String:
	return Finder.find(COMMAND, ["/.local/bin/claude", "/.claude/local/claude"], ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"],
		[OS.get_environment("USERPROFILE").path_join(".local/bin/claude.exe"), OS.get_environment("APPDATA").path_join("npm/claude.cmd")])


## Its own installer, which needs no Node, for a terminal the person watches.
static func install_args() -> PackedStringArray:
	if OS.get_name() == "Windows":
		return PackedStringArray(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "irm https://claude.ai/install.ps1 | iex"])
	return PackedStringArray(["/bin/sh", "-c", "curl -fsSL https://claude.ai/install.sh | bash"])


static func model_from(saved: String) -> String:
	return saved if saved in MODELS else MODELS[0]


static func login_args(path: String) -> PackedStringArray:
	return PackedStringArray([path])          # it signs in when it's run


static func process_env() -> Dictionary:
	var source := Sources.current()
	return Sources.env(source, Keys.read(Sources.key_name(source)) if Sources.takes_key(source) else "")


## The sign-in check's answer from `auth status` JSON on stdout. Signed out only when it says so
## ({"loggedIn": false}); any other failure means it won't start. Another source needs no sign-in.
static func check_state(brain, exit_code: int, said: String, _also: String) -> String:
	if not Sources.is_claude(Sources.current()):
		brain.auth_method = ""
		brain.plan_name = ""
		return "ready"
	var status = JSON.parse_string(said)
	brain.auth_method = str(status.get("authMethod", "")) if status is Dictionary else ""
	brain.plan_name = _plan_name(status) if status is Dictionary else ""
	var says_signed_out: bool = status is Dictionary and status.get("loggedIn") == false
	if exit_code in [0, brain.EXIT_UNKNOWN]:
		return "ready"
	return "signed_out" if exit_code == SIGNED_OUT_EXIT and says_signed_out else "wont_start"


static func _plan_name(status: Dictionary) -> String:
	var tier := str(status.get("planTier", status.get("subscriptionType", "")))
	if tier == "" or tier == "<null>":
		return ""
	var words := tier.split("_")
	var named := "Claude " + words[0].capitalize()
	return named + (" " + " ".join(words.slice(1)) if words.size() > 1 else "")


## Starts one question: the system prompt from a file, the question as a stream-json line on stdin,
## so no shell has to carry either, the same on every computer.
static func start(brain, program: String, dir: String, system_file: String, prompt: String, model: String) -> Dictionary:
	var flags := PackedStringArray(["-p", "--model", model, "--effort", brain.effort(), "--tools=",
		"--setting-sources=", "--strict-mcp-config", "--no-session-persistence", "--input-format", "stream-json",
		"--output-format", "stream-json", "--verbose", "--include-partial-messages", "--system-prompt-file", system_file])
	var started: Dictionary = brain._start(program, dir, flags)
	if not started.is_empty():
		started["stdio"].store_string(JSON.stringify({"type": "user", "message": {"role": "user", "content": prompt}}) + "\n")
	return started


## One line of its stream-json, into the brain. False for a line it doesn't know.
static func read(brain, event: Dictionary) -> bool:
	var type := str(event.get("type", ""))
	if not type in ["system", "stream_event", "assistant", "user", "result", "rate_limit_event"]:
		return false
	if type == "system" and event.get("subtype") == "init":
		brain.ran_version = str(event.get("claude_code_version", ""))
		if event.get("model") is String:
			brain.answered_by = event["model"]
		brain.ran_key_source = str(event.get("apiKeySource", ""))
	elif type == "stream_event":
		var delta = event.get("event", {}).get("delta", {})
		if delta is Dictionary and delta.get("type") == "text_delta" and delta.get("text") is String:
			brain.add_text(delta["text"])
	elif type == "assistant" and event.get("error") == "authentication_failed":
		brain.auth_failed = true
	elif type == "assistant" and event.get("error") == "rate_limit":
		brain.hit_limit = true
	elif type == "system" and event.get("subtype") == "api_retry":
		brain.hit_limit = brain.hit_limit or event.get("error") == "rate_limit"
		brain.billing_failed = brain.billing_failed or event.get("error") == "billing_error"
	elif type == "rate_limit_event":
		brain._read_limit(event.get("rate_limit_info", {}))
	elif type == "result":
		brain.got_result = true
		brain.ended_badly = event.get("is_error") == true
		if event.get("total_cost_usd") is float or event.get("total_cost_usd") is int:
			brain.last_cost = float(event["total_cost_usd"])
		if brain.ended_badly and event.get("result") is String:
			brain.said_wrong += event["result"] + "\n"
		if brain.text == "" and not brain.ended_badly and event.get("result") is String:
			brain.add_text(event["result"])
	return true
