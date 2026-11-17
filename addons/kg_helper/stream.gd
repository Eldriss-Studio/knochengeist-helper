@tool
extends RefCounted
# One request to the app whose answer is read line by line while it arrives. Godot's HTTPRequest
# node only hands over a finished answer; HTTPClient can read one in pieces, but has to be polled.

signal line(text: String)
signal done(ok: bool, code: int)

const GIVE_UP_S := 120.0
const NEWLINE := 10

enum { IDLE, CONNECTING, ASKING, READING }

var http: HTTPClient
var stage := IDLE
var path := ""
var headers := PackedStringArray()
var body := ""
var unread := PackedByteArray()
var waited := 0.0


func busy() -> bool:
	return stage != IDLE


func post(host: String, port: int, to: String, with_headers: PackedStringArray, json: String) -> bool:
	stop()
	http = HTTPClient.new()
	if http.connect_to_host(host, port) != OK:
		http = null
		return false
	path = to
	headers = with_headers
	body = json
	unread = PackedByteArray()
	waited = 0.0
	stage = CONNECTING
	return true


func stop() -> void:
	if http:
		http.close()
	http = null
	stage = IDLE


func poll(delta: float) -> void:
	if stage == IDLE:
		return
	waited += delta
	http.poll()
	var status := http.get_status()
	var broke := status in [HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR]
	if waited > GIVE_UP_S or broke or (stage != READING and status == HTTPClient.STATUS_DISCONNECTED):
		_end(false)
	elif stage == CONNECTING and status == HTTPClient.STATUS_CONNECTED:
		stage = ASKING if http.request(HTTPClient.METHOD_POST, path, headers, body) == OK else IDLE
		if stage == IDLE:
			_end(false)
	elif stage == ASKING and status == HTTPClient.STATUS_BODY:
		stage = READING
	elif stage == ASKING and status == HTTPClient.STATUS_CONNECTED:
		_end(http.has_response())             # an answer with nothing in it
	if stage != READING:
		return
	if http.get_status() == HTTPClient.STATUS_BODY:
		unread.append_array(http.read_response_body_chunk())
		_give_lines()
	else:
		_end(true)


# Whole lines only, cut at the newline byte, so a letter of several bytes is never split.
func _give_lines() -> void:
	var at := unread.find(NEWLINE)
	while at >= 0:
		var text := unread.slice(0, at).get_string_from_utf8().strip_edges()
		unread = unread.slice(at + 1)
		if text != "":
			line.emit(text)
		at = unread.find(NEWLINE)


func _end(ok: bool) -> void:
	var code := http.get_response_code() if http and http.has_response() else 0
	var rest := unread.get_string_from_utf8().strip_edges()
	unread = PackedByteArray()
	stop()
	if ok and rest != "":
		line.emit(rest)                       # an answer in one go has no newline at its end
	done.emit(ok, code)
