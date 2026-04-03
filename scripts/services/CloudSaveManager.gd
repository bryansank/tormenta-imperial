extends Node
## Supabase cloud save integration.
## Handles auth (anonymous or email) and save/load to Supabase PostgreSQL.
## Falls back to local save if offline or unconfigured.
##
## Setup: Set SUPABASE_URL and SUPABASE_ANON_KEY in .env file or directly below.
## Table required: "saves" with columns: id (uuid), user_id (text), save_data (jsonb), updated_at (timestamptz)

# ── Config (set these or load from .env) ──
var supabase_url := ""    # e.g. "https://xxxxx.supabase.co"
var supabase_anon_key := ""  # e.g. "eyJhbGciOiJIUzI1NiIs..."

# ── State ──
var _user_id := ""
var _access_token := ""
var _is_authenticated := false
var _http: HTTPRequest

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_load_config()

func _load_config() -> void:
	# Try loading from .env file
	var env_path := "res://.env"
	if FileAccess.file_exists(env_path):
		var file := FileAccess.open(env_path, FileAccess.READ)
		while not file.eof_reached():
			var line := file.get_line().strip_edges()
			if line.begins_with("SUPABASE_URL="):
				supabase_url = line.substr(13)
			elif line.begins_with("SUPABASE_ANON_KEY="):
				supabase_anon_key = line.substr(18)

func is_configured() -> bool:
	return supabase_url != "" and supabase_anon_key != ""

func is_authenticated() -> bool:
	return _is_authenticated

# ── Anonymous Auth ──

func sign_in_anonymous() -> void:
	if not is_configured():
		EventBus.notification_posted.emit(Tr.t("NOTIF_CLOUD_NOT_CONFIGURED"), "warning", Color(0.8, 0.6, 0.3))
		return

	var url := supabase_url + "/auth/v1/signup"
	var headers := [
		"Content-Type: application/json",
		"apikey: " + supabase_anon_key,
	]
	var body := JSON.stringify({"data": {}})

	_http.request_completed.connect(_on_auth_response, CONNECT_ONE_SHOT)
	_http.request(url, headers, HTTPClient.METHOD_POST, body)

func sign_in_email(email: String, password: String) -> void:
	if not is_configured():
		return

	var url := supabase_url + "/auth/v1/token?grant_type=password"
	var headers := [
		"Content-Type: application/json",
		"apikey: " + supabase_anon_key,
	]
	var body := JSON.stringify({"email": email, "password": password})

	_http.request_completed.connect(_on_auth_response, CONNECT_ONE_SHOT)
	_http.request(url, headers, HTTPClient.METHOD_POST, body)

func sign_up_email(email: String, password: String) -> void:
	if not is_configured():
		return

	var url := supabase_url + "/auth/v1/signup"
	var headers := [
		"Content-Type: application/json",
		"apikey: " + supabase_anon_key,
	]
	var body := JSON.stringify({"email": email, "password": password})

	_http.request_completed.connect(_on_auth_response, CONNECT_ONE_SHOT)
	_http.request(url, headers, HTTPClient.METHOD_POST, body)

func _on_auth_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code >= 400:
		EventBus.notification_posted.emit(Tr.t("NOTIF_CLOUD_AUTH_FAILED"), "danger", Color(0.9, 0.3, 0.2))
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return
	var data: Dictionary = json.data
	_access_token = data.get("access_token", "")
	_user_id = data.get("user", {}).get("id", "")
	_is_authenticated = _access_token != "" and _user_id != ""

	if _is_authenticated:
		EventBus.notification_posted.emit(Tr.t("NOTIF_CLOUD_CONNECTED"), "positive", Color(0.3, 0.8, 0.5))

# ── Cloud Save ──

func cloud_save(save_data: Dictionary) -> void:
	if not _is_authenticated:
		return

	var url := supabase_url + "/rest/v1/saves"
	var headers := _auth_headers()
	headers.append("Prefer: resolution=merge-duplicates")

	var body := JSON.stringify({
		"user_id": _user_id,
		"save_data": save_data,
		"updated_at": Time.get_datetime_string_from_system(true),
	})

	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	http.request_completed.connect(func(_r, code, _h, _b):
		if code < 300:
			EventBus.notification_posted.emit(Tr.t("NOTIF_CLOUD_SAVED"), "info", Color(0.4, 0.7, 0.9))
		http.queue_free()
	, CONNECT_ONE_SHOT)
	http.request(url, headers, HTTPClient.METHOD_POST, body)

func cloud_load() -> void:
	if not _is_authenticated:
		return

	var url := supabase_url + "/rest/v1/saves?user_id=eq." + _user_id + "&select=save_data&order=updated_at.desc&limit=1"
	var headers := _auth_headers()

	_http.request_completed.connect(_on_cloud_load_response, CONNECT_ONE_SHOT)
	_http.request(url, headers, HTTPClient.METHOD_GET)

func _on_cloud_load_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code >= 400:
		EventBus.notification_posted.emit(Tr.t("NOTIF_CLOUD_LOAD_FAILED"), "danger", Color(0.9, 0.3, 0.2))
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return
	var rows: Array = json.data
	if rows.is_empty():
		EventBus.notification_posted.emit(Tr.t("NOTIF_CLOUD_NO_SAVE"), "info", Color(0.7, 0.7, 0.5))
		return

	var save_data: Dictionary = rows[0].get("save_data", {})
	if save_data.is_empty():
		return

	# Write to local save path and reload
	var file := FileAccess.open(GameManager.SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
	EventBus.notification_posted.emit(Tr.t("NOTIF_CLOUD_LOADED"), "positive", Color(0.3, 0.8, 0.5))
	# Reload the game with cloud data
	GameManager.clear_save_and_reload_from(save_data)

# ── Helpers ──

func _auth_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"apikey: " + supabase_anon_key,
		"Authorization: Bearer " + _access_token,
	])
