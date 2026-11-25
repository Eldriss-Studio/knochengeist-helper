@tool
extends RefCounted
# Where Claude Code sends its questions: to Anthropic with his Claude plan, as always, or to another
# address that speaks Anthropic's API (OpenRouter, DeepSeek, or a model on his own computer through
# Ollama or LM Studio). Claude Code takes the address, key and model only from its environment, so
# each question gets them for its own run and nothing is saved in Claude Code's settings.

const L := preload("l10n.gd")

const SETTING := "knochengeist/source"
const MODEL_SETTING := "knochengeist/source_model_%s"
const ADDRESS_SETTING := "knochengeist/source_address"
const CLAUDE := "claude"
const CUSTOM := "custom"
const KEY_PREFIX := "source-"
const NO_TOKEN := "none"
const SCHEME := "http://"
const THIS_COMPUTER := ["localhost", "127.0.0.1", "[::1]"]
const MAX_OUTPUT_TOKENS := "4000"    # OpenRouter refuses a request that could cost more than the credit left
const MAX_RETRIES := "3"             # Claude Code's own default retries a closed port for minutes
# label: Claude's is the Claude Code adapter's SOURCE_LABEL. key: "needed", "optional" or "none". address: "" for one he types. maker: a fixed one, or "from model"
# for an id that starts with it (google/gemini-2.5-flash). token: what a local server takes for a key.
const ALL := {
	CLAUDE: {"label": "", "name": "Claude", "address": "", "key": "none", "model": "", "local": false},
	"openrouter": {"label": "OpenRouter", "name": "OpenRouter", "address": "https://openrouter.ai/api", "key": "needed",
		"model": "baidu/ernie-5.5-flash-preview:free", "local": false, "maker": "from model"},
	"deepseek": {"label": "DeepSeek", "name": "DeepSeek", "address": "https://api.deepseek.com/anthropic", "key": "needed",
		"model": "deepseek-flash", "local": false, "maker": "DeepSeek"},
	"ollama": {"label": "Ollama (on this computer)", "name": "Ollama", "address": "http://localhost:11434", "key": "none",
		"model": "qwen3-coder:30b", "local": true, "token": "ollama"},
	"lmstudio": {"label": "LM Studio (on this computer)", "name": "LM Studio", "address": "http://localhost:1234", "key": "none",
		"model": "qwen/qwen3-coder-30b", "local": true, "token": "lmstudio"},
	CUSTOM: {"label": "Another address", "name": "", "address": "", "key": "optional", "model": "", "local": false},
}
const MAKERS := {"google": "Google", "nvidia": "NVIDIA", "anthropic": "Anthropic", "openai": "OpenAI", "meta-llama": "Meta",
	"deepseek": "DeepSeek", "mistralai": "Mistral AI", "qwen": "Alibaba", "baidu": "Baidu", "x-ai": "xAI",
	"moonshotai": "Moonshot AI", "z-ai": "Z.ai", "microsoft": "Microsoft", "amazon": "Amazon", "cohere": "Cohere"}
# %s is the source's name
const PROBLEMS := {
	"no_key": "There's no %s key saved yet. Open Settings in the ghost's menu and add your key.",
	"no_address": "There's no address saved yet. Open Settings in the ghost's menu and add the address under Answers from.",
	"wrong_key": "%s turned down your key. Check it on its website, then save it again in Settings.",
	"no_credit": "Your %s account has no credit left for this model. Add credit, or pick a free model in Settings.",
	"rate_limited": "%s is busy for this model right now. Try again later, or pick another model in Settings.",
	"bad_model": "%s doesn't know the model set in Settings. Check its name, then save it again.",
	"not_running": "Nothing answered from %s. Start it, then ask again.",
}
const LOCAL_MEMORY := "A good model for this needs about 16 to 24 GB of graphics memory."


static func current() -> String:
	var saved := _saved(SETTING)
	return saved if ALL.has(saved) else CLAUDE


static func is_claude(id: String) -> bool:
	return id == CLAUDE


static func needs_key(id: String) -> bool:
	return ALL[id]["key"] == "needed"


static func takes_key(id: String) -> bool:
	return ALL[id]["key"] != "none"


static func typed_address(id: String) -> bool:
	return not is_claude(id) and ALL[id]["address"] == ""


static func is_local(id: String) -> bool:
	return ALL[id]["local"] or (typed_address(id) and _host(address(id)).get_slice(":", 0) in THIS_COMPUTER)


static func label(id: String) -> String:
	return L.t(ALL[id]["label"])


## Its name in a sentence: "OpenRouter", or the host he typed for another address.
static func name(id: String) -> String:
	if not typed_address(id):
		return ALL[id]["name"]
	var host := _host(address(id))
	return host if host != "" else L.t("the address in Settings")


## What he typed reads like a link: "localhost:4000/" is http://localhost:4000.
static func address(id: String) -> String:
	if not typed_address(id):
		return ALL[id]["address"]
	var typed := _saved(ADDRESS_SETTING).trim_suffix("/")
	return typed if typed == "" or typed.contains("://") else SCHEME + typed


static func default_model(id: String) -> String:
	return ALL[id]["model"]


static func model(id: String) -> String:
	var saved := _saved(MODEL_SETTING % id)
	return saved if saved != "" else default_model(id)


## Who made the model, when the source says: "Google" for google/gemma-4-31b-it on OpenRouter.
static func maker(id: String, for_model: String) -> String:
	var rule: String = ALL[id].get("maker", "")
	if rule != "from model":
		return rule
	if not for_model.contains("/"):
		return ""
	var prefix := for_model.get_slice("/", 0)
	return MAKERS.get(prefix, prefix.capitalize())


static func key_name(id: String) -> String:
	return KEY_PREFIX + id


## What's missing before a question can go out: "no_key", "no_address", or "" when nothing is.
static func missing(id: String, key: String) -> String:
	if needs_key(id) and key == "":
		return "no_key"
	if typed_address(id) and address(id) == "":
		return "no_address"
	return ""


## What Claude Code's run gets, only for that run: nothing for Claude, which uses his sign-in.
static func env(id: String, key := "") -> Dictionary:
	if is_claude(id):
		return {}
	var asked := model(id)
	var token: String = key if key != "" else ALL[id].get("token", NO_TOKEN)
	return {"ANTHROPIC_BASE_URL": address(id), "ANTHROPIC_AUTH_TOKEN": token, "ANTHROPIC_API_KEY": "",
		"ANTHROPIC_DEFAULT_SONNET_MODEL": asked, "ANTHROPIC_DEFAULT_HAIKU_MODEL": asked, "ANTHROPIC_DEFAULT_OPUS_MODEL": asked,
		"CLAUDE_CODE_MAX_OUTPUT_TOKENS": MAX_OUTPUT_TOKENS, "CLAUDE_CODE_MAX_RETRIES": MAX_RETRIES}


## The refusal a failed run means, from what Claude Code said and the signs it gave in its events
## (auth_failed, hit_limit, billing_failed); "" when it isn't one of them.
static func refusal(said: String, signs: Dictionary) -> String:
	var words := said.to_lower()
	if signs.get("auth_failed", false) or words.contains("api error: 401"):
		return "wrong_key"
	if signs.get("billing_failed", false) or words.contains("api error: 402") or words.contains("more credits"):
		return "no_credit"
	if signs.get("hit_limit", false) or words.contains("(429)") or words.contains("api error: 429"):
		return "rate_limited"
	if words.contains("not a valid model") or words.contains("model not found"):
		return "bad_model"
	if words.contains("econnrefused") or words.contains("connection refused"):
		return "not_running"
	return ""


static func problem_text(id: String, problem: String) -> String:
	var said := L.t(PROBLEMS[problem])
	return said % name(id) if said.contains("%s") else said


static func _saved(setting: String) -> String:
	var settings := EditorInterface.get_editor_settings()
	return str(settings.get_setting(setting)).strip_edges() if settings.has_setting(setting) else ""


static func _host(at: String) -> String:
	return at.get_slice("://", 1).get_slice("/", 0) if at.contains("://") else at
