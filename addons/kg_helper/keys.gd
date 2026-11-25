@tool
extends RefCounted

# Keys the helper keeps (an AI tool's API key), stored in the system's own keychain and nowhere else:
# the macOS Keychain, Windows Credential Manager or the Linux Secret Service. Godot has no keychain,
# and its own settings and files are plain text, so without a keychain no key is kept at all.
# A key never goes on a command line, where other programs could see it: it reaches the keychain tool
# through an environment variable that only that tool's process gets, and is cleared right after.

const SERVICE := "Knochengeist"
const SECRET_VAR := "KG_HELPER_SECRET"
const NAME_VAR := "KG_HELPER_KEY_NAME"
const SERVICE_VAR := "KG_HELPER_KEY_SERVICE"
const TESTS_VAR := "KG_HELPER_KEYS_FOR"     # a test's own corner of a keychain the tests share (Linux, Windows)
const SECURITY := "/usr/bin/security"
const POWERSHELL := "System32/WindowsPowerShell/v1.0/powershell.exe"     # never whatever PATH finds first
const WINDOWS_FOLDER := "C:/Windows"         # where SystemRoot points when it isn't set
const L := preload("l10n.gd")
const Brain := preload("brain.gd")
const NAME_SHAPE := "^[a-z0-9-]+\\z"      # a key's name goes into a keychain command line, so nothing else is allowed
const LINUX_SAVE := """printf %s "$KG_HELPER_SECRET" | secret-tool store --label="$KG_HELPER_KEY_SERVICE $KG_HELPER_KEY_NAME" service "$KG_HELPER_KEY_SERVICE" account "$KG_HELPER_KEY_NAME"
"""
# The key goes to `security -i` on its input, as hex (-X), so it is never on a command line
const MAC_SAVE := """k=""; [ -n "$KG_HELPER_KEYCHAIN" ] && k="\\"$KG_HELPER_KEYCHAIN\\""
printf 'add-generic-password -U -s "%s" -a "%s" -X %s %s\\n' "$KG_HELPER_KEY_SERVICE" "$KG_HELPER_KEY_NAME" "$KG_HELPER_SECRET" "$k" | /usr/bin/security -i"""


## Whether this computer has a keychain the helper can use.
static func available() -> bool:
	match OS.get_name():
		"macOS":
			var chain := OS.get_environment("KG_HELPER_KEYCHAIN")     # a test keychain, so tests never touch the real one
			return FileAccess.file_exists(SECURITY) and (chain == "" or FileAccess.file_exists(chain))
		"Windows":
			return FileAccess.file_exists(_powershell_path())
		_:
			return _sh("command -v secret-tool >/dev/null")["code"] == 0


## Saves the key under this name. Returns "" when it's saved, or what's wrong, in plain words.
static func save(name: String, key: String) -> String:
	if RegEx.create_from_string(NAME_SHAPE).search(name) == null:
		return L.t("Couldn't save the key in this computer's keychain. Show log has the details.")
	if not available():
		return _missing()
	match OS.get_name():
		"macOS":
			_with_secret(name, key.to_utf8_buffer().hex_encode(), func(): return _sh(MAC_SAVE))
		"Windows":
			_with_secret(name, key, func(): return _powershell("save"))
		_:
			_with_secret(name, key, func():
				return _sh(LINUX_SAVE))
	if read(name) != key:
		Brain.log_line("Couldn't save the %s key in the system keychain (%s)." % [name, OS.get_name()])
		return L.t("Couldn't save the key in this computer's keychain. Show log has the details.")
	Brain.log_line("Saved the %s key in the system keychain." % name)
	return ""


## The key saved under this name, or "" when there is none.
static func read(name: String) -> String:
	if not available():
		return ""
	var ran: Dictionary
	match OS.get_name():
		"macOS":
			ran = _run(SECURITY, _in_keychain(["find-generic-password", "-s", _service(), "-a", name, "-w"]))
			return ran["out"].trim_suffix("\n") if ran["code"] == 0 else ""
		"Windows":
			ran = _with_secret(name, "", func(): return _powershell("read"))
			return Marshalls.base64_to_utf8(ran["out"].strip_edges()) if ran["code"] == 0 and ran["out"].strip_edges() != "" else ""
		_:
			ran = _run("secret-tool", ["lookup", "service", _service(), "account", name])
			return ran["out"] if ran["code"] == 0 else ""


## Removes the key saved under this name. True when none is left.
static func remove(name: String) -> bool:
	if not available():
		return true
	match OS.get_name():
		"macOS":
			_run(SECURITY, _in_keychain(["delete-generic-password", "-s", _service(), "-a", name]))
		"Windows":
			_with_secret(name, "", func(): return _powershell("remove"))
		_:
			_run("secret-tool", ["clear", "service", _service(), "account", name])
	return read(name) == ""


static func _service() -> String:
	var tests := OS.get_environment(TESTS_VAR)
	return SERVICE + "-" + tests if RegEx.create_from_string(NAME_SHAPE).search(tests) else SERVICE


# A test keychain, when one is named, so tests never touch the real one.
static func _in_keychain(args: Array) -> Array:
	var chain := OS.get_environment("KG_HELPER_KEYCHAIN")
	return args + ([chain] if chain != "" else [])


static func _missing() -> String:
	match OS.get_name():
		"macOS":
			return L.t("This Mac's keychain can't be reached, so the key wasn't saved.")
		_:
			return L.t("This computer has no keychain the helper can use, so the key wasn't saved. Install libsecret-tools (secret-tool), then try again.")


# Runs `work` with the name and key in the environment its child process inherits, then clears them.
static func _with_secret(name: String, secret: String, work: Callable) -> Dictionary:
	OS.set_environment(NAME_VAR, name)
	OS.set_environment(SECRET_VAR, secret)
	OS.set_environment(SERVICE_VAR, _service())
	var ran: Dictionary = work.call()
	OS.unset_environment(SECRET_VAR)
	OS.unset_environment(NAME_VAR)
	OS.unset_environment(SERVICE_VAR)
	return ran


# Runs a shell script from a file: a script given as an argument loses its quotes on the way out of Godot.
# The script holds no key; the key is only in the environment.
static func _sh(script: String) -> Dictionary:
	var path := OS.get_cache_dir().path_join("kg_helper_keys.sh")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"code": -1, "out": ""}
	file.store_string(script + "\n")
	file.close()
	return _run("/bin/sh", [path])


static func _run(program: String, args: Array) -> Dictionary:
	var out := []
	var code := OS.execute(program, PackedStringArray(args), out, false)
	return {"code": code, "out": out[0] if not out.is_empty() else ""}


# Windows Credential Manager through PowerShell and Windows' own credential functions. The script
# reads the name and key from the environment; a read prints the key in base64.
static func _powershell(action: String) -> Dictionary:
	var script := """
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class KgCred {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct CREDENTIAL { public uint Flags; public uint Type; public string TargetName; public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public uint CredentialBlobSize; public IntPtr CredentialBlob;
    public uint Persist; public uint AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName; }
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool CredWrite(ref CREDENTIAL c, uint flags);
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool CredRead(string target, uint type, uint flags, out IntPtr c);
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool CredDelete(string target, uint type, uint flags);
  [DllImport("advapi32.dll")] static extern void CredFree(IntPtr c);
  public static bool Save(string t, string s) { byte[] b = Encoding.Unicode.GetBytes(s); var c = new CREDENTIAL(); c.Type = 1; c.TargetName = t; c.UserName = "Knochengeist"; c.Persist = 2;
    c.CredentialBlobSize = (uint)b.Length; c.CredentialBlob = Marshal.AllocHGlobal(Math.Max(b.Length, 1)); Marshal.Copy(b, 0, c.CredentialBlob, b.Length);
    try { return CredWrite(ref c, 0); } finally { Marshal.FreeHGlobal(c.CredentialBlob); } }
  public static string Read(string t) { IntPtr p; if (!CredRead(t, 1, 0, out p)) return null;
    try { var c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL)); return Marshal.PtrToStringUni(c.CredentialBlob, (int)c.CredentialBlobSize / 2); } finally { CredFree(p); } }
  public static bool Remove(string t) { return CredDelete(t, 1, 0); }
}
'@
$target = $env:KG_HELPER_KEY_SERVICE + ':' + $env:KG_HELPER_KEY_NAME
switch ('%s') {
  'save' { if (-not [KgCred]::Save($target, $env:KG_HELPER_SECRET)) { exit 1 } }
  'read' { $k = [KgCred]::Read($target); if ($k -eq $null) { exit 1 }; [Console]::Out.Write([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($k))) }
  'remove' { [void][KgCred]::Remove($target) }
}
""" % action
	var encoded := Marshalls.raw_to_base64(script.to_utf16_buffer())
	return _run(_powershell_path(), ["-NoProfile", "-NonInteractive", "-EncodedCommand", encoded])


static func _powershell_path() -> String:
	var root := OS.get_environment("SystemRoot")
	return (root if root != "" else WINDOWS_FOLDER).path_join(POWERSHELL)
