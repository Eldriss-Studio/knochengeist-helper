@tool
extends Node
# The link to the course app, over plain HTTP: a POST of what's on screen whenever that changes (and
# every few seconds, so the app knows it's still here), and one GET held open, waiting for a point.
# When the app isn't running, it knocks on its port every 2 seconds with a plain TCP connection, which
# fails quietly: an HTTP request would print an error in his Output panel each time. The app's side is
# course/src/lib/server/godot-link.ts.

signal went(up: bool)                 # the course app answered, or stopped answering
signal refused                        # the app speaks another contract version
signal pointed(answer: Dictionary)    # he pressed Show me on the course page
signal next_came(result: int, code: int, reply)   # the next click of a walk-through, or why there's none

const LOOK_S := 1.0              # how often it looks at what's on screen
const STILL_HERE_S := 5.0        # sends at least this often
const RETRY_S := 2.0
const NOT_THE_APP_RETRY_S := 30.0
const CONTRACT_HEADER := "x-kg-contract"
const REFUSED_S := 30.0
const STATE_TIMEOUT_S := 10.0
const HELLO_TIMEOUT_S := 5.0
const POINT_TIMEOUT_S := 40.0      # the GET held open, waiting for a point
const NEXT_TIMEOUT_S := 60.0       # the app thinks about the next click

var url := ""
var host := ""
var port := 0
var project := ""
var contract := 0
var app_up := false              # the app answered on its port; until then only knock
var state_req: HTTPRequest
var hello_req: HTTPRequest
var point_req: HTTPRequest
var next_req: HTTPRequest
var tell_req: HTTPRequest        # tells the app he pressed Show me
var sent := ""
var sending := false
var waiting := false
var look_in := 0.0
var since_sent := 0.0
var retry_in := 0.0
var knock: StreamPeerTCP = null
var knocking_s := 0.0
var refused_for := 0.0


func _init(app_url: String, project_dir: String, speaks: int) -> void:
	url = app_url
	project = project_dir
	contract = speaks
	var address := url.trim_prefix("http://").get_slice("/", 0)
	host = address.get_slice(":", 0)
	port = int(address.get_slice(":", 1)) if address.contains(":") else 80
	state_req = _request(STATE_TIMEOUT_S, _state_sent)
	hello_req = _request(HELLO_TIMEOUT_S, _hello_came)
	point_req = _request(POINT_TIMEOUT_S, _point_came)
	next_req = _request(NEXT_TIMEOUT_S, func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		next_came.emit(result, code, JSON.parse_string(body.get_string_from_utf8())))
	tell_req = _request(0.0, Callable())


func _request(timeout: float, done: Callable) -> HTTPRequest:
	var req := HTTPRequest.new()
	req.timeout = timeout
	if done.is_valid():
		req.request_completed.connect(done)
	add_child(req)
	return req


## Each frame: knocks until the app is there, then sends what's on screen and waits for a point.
func poll(delta: float, read_screen: Callable) -> void:
	if refused_for > 0.0:
		refused_for -= delta
		return
	if not app_up:
		_knock(delta)
		return
	since_sent += delta
	look_in -= delta
	if look_in <= 0.0 and not sending:
		look_in = LOOK_S
		var body := JSON.stringify(read_screen.call())
		if body != sent or since_sent >= STILL_HERE_S:
			sending = true
			if send(state_req, "/api/godot/state", body):
				sent = body
				since_sent = 0.0
			else:
				sending = false
	if not waiting:
		retry_in -= delta
		if retry_in <= 0.0:
			waiting = send(point_req, "/api/godot/point?project=" + project.uri_encode())
			if not waiting:
				retry_in = RETRY_S


## Asks the app for a walk-through's next click; next_came says what came back.
func ask_next(body: Dictionary) -> bool:
	return send(next_req, "/api/godot/next", JSON.stringify(body))


## Tells the app he pressed Show me in Godot.
func tell_shown(ask: int) -> void:
	send(tell_req, "/api/godot/show", JSON.stringify({"ask": ask}))


# `body` is JSON to POST; without one it's a GET.
func send(req: HTTPRequest, path: String, body := "") -> bool:
	if body == "":
		return req.request(url + path, headers(false)) == OK
	return req.request(url + path, headers(true), HTTPClient.METHOD_POST, body) == OK


func headers(with_body: bool) -> PackedStringArray:
	var said := PackedStringArray(["X-KG-Contract: %d" % contract])
	if with_body:
		said.append("Content-Type: application/json")
	return said


## Knocking again at once would only be refused again.
func refuse() -> void:
	refused_for = REFUSED_S
	sent = ""
	refused.emit()


func _state_sent(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	sending = false
	if code == HTTPClient.RESPONSE_UPGRADE_REQUIRED:
		refuse()
		return
	if result != HTTPRequest.RESULT_SUCCESS or code >= 300:
		sent = ""                 # the app missed it: send it again once it's back
		_gone()


func _point_came(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	waiting = false
	if code == HTTPClient.RESPONSE_UPGRADE_REQUIRED:
		refuse()
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_gone()
		return
	retry_in = 0.0
	var answer = JSON.parse_string(body.get_string_from_utf8())
	if answer is Dictionary and answer.get("target") is String:
		pointed.emit(answer)


func _gone() -> void:
	app_up = false
	retry_in = RETRY_S
	went.emit(false)


# Knocks on the app's port; once it answers, the HTTP side starts.
func _knock(delta: float) -> void:
	if knock == null:
		retry_in -= delta
		if retry_in > 0.0:
			return
		knock = StreamPeerTCP.new()
		knocking_s = 0.0
		if knock.connect_to_host(host, port) != OK:
			knock = null
			retry_in = RETRY_S
		return
	knock.poll()
	knocking_s += delta
	var status := knock.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTING and knocking_s < RETRY_S:
		return
	knock.disconnect_from_host()
	knock = null
	if status == StreamPeerTCP.STATUS_CONNECTED:
		retry_in = NOT_THE_APP_RETRY_S             # until the answer says it's the course app
		if hello_req.request(url + "/api/godot/status", headers(false)) != OK:
			retry_in = RETRY_S
	else:
		retry_in = RETRY_S


# Something answered on the course app's port: only the course app itself turns course mode on.
func _hello_came(_result: int, code: int, said: PackedStringArray, _body: PackedByteArray) -> void:
	var says_contract := false
	for header in said:
		says_contract = says_contract or header.to_lower().begins_with(CONTRACT_HEADER + ":")
	if code == HTTPClient.RESPONSE_UPGRADE_REQUIRED:
		refuse()
		return
	if code != 200 or not says_contract:
		return
	app_up = true
	sent = ""
	look_in = 0.0
	retry_in = 0.0
	went.emit(true)
