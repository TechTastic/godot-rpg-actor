@tool
@icon("res://addons/rpg_actor/assets/RPGActor.png")
extends Node

var base_api: String:
	get: return ProjectSettings.get_setting("rpg_actor/base_api", "https://rpg.actor/api")
var plc_directory: String:
	get: return ProjectSettings.get_setting("rpg_actor/plc_directory", "https://plc.directory")
var blsk_api: String:
	get: return ProjectSettings.get_setting("rpg_actor/bluesky_api", "https://public.api.bsky.app")

signal logging_in(profile: Dictionary)
signal session_expired
signal request_failed(error: String)

var did: String = ""
var pds: String = ""
var _handle: String = ""
var _access_token: String = ""
var _refresh_token: String = ""
var _refresh_timer: Timer

var logged_in: bool:
	get: return _access_token.is_empty()


func _ready():
	if !Engine.is_editor_hint():
		pass
	
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 1800.0
	#_refresh_timer.timeout.connect(_refresh_session)
	add_child(_refresh_timer)

## XRPC Handlers
func resolve_handle(handle: String) -> Dictionary:
	var clean = handle.lstrip("@")
	var res = await _http_request("%s/xrpc/com.atproto.identity.resolveHandle?handle=%s" % [blsk_api, clean])
	if res.is_empty(): return {}
	var did: String = res.get("did", "")
	var doc = await _http_request(plc_directory + "/" + did)
	var pds = _extract_pds(doc)
	return { "did": did, "pds": pds }


func get_record(pds: String, repo: String, collection: String, rkey: String = "self") -> Dictionary:
	var url = "%s/xrpc/com.atproto.repo.getRecord?repo=%s&collection=%s&rkey=%s" \
		% [pds, repo, collection, rkey]
	return await _get(url)


func put_record(pds: String, collection: String, rkey: String, record: Dictionary, access_token: String, dpop_header: String) -> Dictionary:
	return await _http_request(
		pds + "/xrpc/com.atproto.repo.putRecord",
		HTTPClient.METHOD_POST,
		["Authorization: DPoP " + access_token, "DPoP: " + dpop_header],
		JSON.stringify({ "repo": "self", "collection": collection, "rkey": rkey, "record": record })
	)

## Login Handlers
func login(handle: String) -> void:
	var identity = await resolve_handle(handle)
	if identity.is_empty():
		request_failed.emit("Could not resolve handle: " + handle)
		return
	did = identity["did"]
	pds = identity["pds"]
	#_start_oauth_flow(_pds)


func logout() -> void:
	_access_token = ""
	_refresh_token = ""
	did = ""
	_handle = ""
	_refresh_timer.stop()

## Internal Helpers
func _http_request(url: String, method: HTTPClient.Method = HTTPClient.METHOD_GET, headers: PackedStringArray = [], body: String = "") -> Dictionary:
	var req := HTTPRequest.new()
	add_child(req)
	await get_tree().process_frame
	req.request(url, headers, method, body)
	var result = await req.request_completed
	req.queue_free()
	print(result)
	var code: int = result[1]
	if code != 200:
		push_warning("RpgActorXRPC: %s %s returned HTTP Response Code %d" % [ClassDB.class_get_enum_constants("HTTPClient", "Method")[method], url, code])
		return {}
	return JSON.parse_string(result[3].get_string_from_utf8())


func _extract_pds(plc_doc: Dictionary) -> String:
	for service in plc_doc.get("service", []):
		if service.get("type") == "AtprotoPersonalDataServer":
			return service.get("serviceEndpoint", "")
	return ""
