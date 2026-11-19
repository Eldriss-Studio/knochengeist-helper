@tool
extends RefCounted
# The helper's own words in the language set for the Godot editor. They live in a translation domain
# of their own, so they never mix with the game's translations or the editor's, and only the .po files
# in locale/ for the editor's language are loaded: a domain otherwise falls back to the game project's
# fallback language. Strings are English in the code: L.t("Install %s…") % name, the value put in
# after translating. tools/l10n_pot.py collects them into locale/kg_helper.pot.

const DOMAIN := &"addons/kg_helper"
const LOCALE_DIR := "res://addons/kg_helper/locale"


## Loads the translations for the editor's language. Called once when the plugin starts.
static func load_all() -> void:
	unload()                          # starts clean when the plugin is turned off and on again
	var domain := TranslationServer.get_or_add_domain(DOMAIN)
	var language := TranslationServer.get_locale().get_slice("_", 0)
	for file in DirAccess.get_files_at(LOCALE_DIR):
		if file.get_extension() != "po":
			continue
		var translation := load(LOCALE_DIR.path_join(file)) as Translation
		if translation and translation.locale.get_slice("_", 0) == language:
			domain.add_translation(translation)


static func unload() -> void:
	if TranslationServer.has_domain(DOMAIN):
		TranslationServer.remove_domain(DOMAIN)


## This English text in the editor's language, or as it is when there's no translation.
static func t(text: String, context := "") -> String:
	if text == "" or not TranslationServer.has_domain(DOMAIN):
		return text
	return String(TranslationServer.get_or_add_domain(DOMAIN).translate(text, context))


## The form for this count: t_n("%d page", "%d pages", n) % n.
static func t_n(one: String, many: String, n: int) -> String:
	if not TranslationServer.has_domain(DOMAIN):
		return one if n == 1 else many
	return String(TranslationServer.get_or_add_domain(DOMAIN).translate_plural(one, many, n))
