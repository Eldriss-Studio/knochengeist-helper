@tool
extends Node

const L := preload("l10n.gd")
# Finds a newer helper on its public repo's releases, and installs it: the whole folder replaced at once.

signal found(version: String, notes: String)
signal installed(version: String)
signal failed(why: String)

const Brain := preload("brain.gd")
const LATEST := "https://api.github.com/repos/Eldriss-Studio/knochengeist-helper/releases/latest"
const SETTING := "knochengeist/check_for_updates"
const CHECKED_AT := "update_checked_at"
const DAY_S := 86400
const TAG := "helper-v"
const INSIDE_ZIP := "addons/kg_helper/"
const TIMEOUT_S := 15.0

var current := 0
var release := {}                  # the newer release: version, notes, zip, digest
var asking: HTTPRequest
var fetching: HTTPRequest
var helper_dir := ""               # the folder this helper runs from


func _init(running_version: int, folder: String) -> void:
	current = running_version
	helper_dir = folder


static func offer_setting() -> void:
	var settings := EditorInterface.get_editor_settings()
	if not settings.has_setting(SETTING):
		settings.set_setting(SETTING, true)
	settings.set_initial_value(SETTING, true, false)
	settings.add_property_info({"name": SETTING, "type": TYPE_BOOL})


static func on() -> bool:
	var settings := EditorInterface.get_editor_settings()
	return not settings.has_setting(SETTING) or settings.get_setting(SETTING) == true


func _ready() -> void:
	asking = HTTPRequest.new()
	asking.timeout = TIMEOUT_S
	asking.request_completed.connect(_answered)
	add_child(asking)
	fetching = HTTPRequest.new()
	fetching.timeout = TIMEOUT_S * 4
	fetching.request_completed.connect(_downloaded)
	add_child(fetching)


## Asks for the latest release, at most once a day, and never with the setting off.
func check() -> void:
	if not on() or not is_inside_tree():
		return
	var checked: int = EditorInterface.get_editor_settings().get_project_metadata("knochengeist", CHECKED_AT, 0)
	if Time.get_unix_time_from_system() - checked < DAY_S:
		return
	var url := OS.get_environment("KG_HELPER_UPDATES_URL")
	asking.cancel_request()
	asking.request(url if url != "" else LATEST, ["User-Agent: knochengeist-helper", "Accept: application/vnd.github+json"])


func _answered(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		Brain.log_line("Couldn't check for updates (result %d, HTTP %d)." % [result, code])
		return
	var latest = JSON.parse_string(body.get_string_from_utf8())
	if not latest is Dictionary or not str(latest.get("tag_name", "")).begins_with(TAG):
		Brain.log_line("The update check got something that isn't a helper release.")
		return
	var version := int(str(latest["tag_name"]).trim_prefix(TAG))
	var zip := {}
	for asset in latest.get("assets", []):
		if asset is Dictionary and str(asset.get("name", "")).ends_with(".zip"):
			zip = asset
	if version <= current or zip.is_empty():
		EditorInterface.get_editor_settings().set_project_metadata("knochengeist", CHECKED_AT, int(Time.get_unix_time_from_system()))
		return
	release = {"version": str(version), "notes": str(latest.get("body", "")), "zip": str(zip.get("browser_download_url", "")), "digest": str(zip.get("digest", ""))}
	found.emit(release["version"], release["notes"])


func _download_path() -> String:
	return OS.get_user_data_dir().path_join("kg_helper").path_join("update.zip")


## Downloads the newer release and replaces this helper's folder with it.
func install() -> void:
	if release.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(_download_path().get_base_dir())
	fetching.cancel_request()
	fetching.download_file = _download_path()
	if fetching.request(release["zip"], ["User-Agent: knochengeist-helper"]) != OK:
		_fail("The update didn't download, so nothing changed. Try again later.", "Couldn't start the update download.")


func _downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("The update didn't download, so nothing changed. Try again later.", "The update download failed (result %d, HTTP %d)." % [result, code])
		return
	var got := "sha256:" + FileAccess.get_sha256(_download_path())
	if got != release["digest"]:
		_fail("The update didn't download correctly, so nothing changed.", "Update to %s: the download's digest %s isn't the release's %s." % [release["version"], got, release["digest"]])
		return
	var why := _replace_folder()
	DirAccess.remove_absolute(_download_path())
	if why != "":
		_fail("The update couldn't be installed, so nothing changed.", "Update to %s: %s" % [release["version"], why])
		return
	Brain.log_line("Updated the helper from version %d to %s." % [current, release["version"]])
	installed.emit(release["version"])


# Unpacks next to the helper's folder, then swaps the two folders, so a failure leaves the old one whole.
func _replace_folder() -> String:
	var here := ProjectSettings.globalize_path(helper_dir).trim_suffix("/")
	var fresh := here.get_base_dir().path_join(".kg_helper_new")
	var old := here.get_base_dir().path_join(".kg_helper_old")
	_remove(fresh)
	_remove(old)
	var zip := ZIPReader.new()
	if zip.open(_download_path()) != OK:
		return "the download isn't a zip."
	for name in zip.get_files():
		if name.ends_with("/"):
			continue
		if not name.begins_with(INSIDE_ZIP) or name.contains("..") or name.contains("\\"):
			zip.close()
			_remove(fresh)
			return "the zip has %s, outside addons/kg_helper." % name
		var to := fresh.path_join(name.trim_prefix(INSIDE_ZIP))
		DirAccess.make_dir_recursive_absolute(to.get_base_dir())
		var file := FileAccess.open(to, FileAccess.WRITE)
		if file == null:
			zip.close()
			_remove(fresh)
			return "couldn't write %s." % to
		file.store_buffer(zip.read_file(name))
		file.close()
	zip.close()
	var cfg := ConfigFile.new()
	if cfg.load(fresh.path_join("plugin.cfg")) != OK or str(cfg.get_value("plugin", "version", "")) != release["version"]:
		_remove(fresh)
		return "the zip's plugin.cfg isn't version %s." % release["version"]
	if DirAccess.rename_absolute(here, old) != OK:
		_remove(fresh)
		return "couldn't move the old helper aside."
	if DirAccess.rename_absolute(fresh, here) != OK:
		DirAccess.rename_absolute(old, here)
		_remove(fresh)
		return "couldn't put the new helper in place."
	_remove(old)
	return ""


func _fail(said: String, logged: String) -> void:
	Brain.log_line(logged)
	failed.emit(L.t(said))


static func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	for dir in DirAccess.get_directories_at(path):
		_remove(path.path_join(dir))
	DirAccess.remove_absolute(path)
