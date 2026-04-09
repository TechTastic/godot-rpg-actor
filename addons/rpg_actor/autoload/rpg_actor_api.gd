@tool
@icon("res://addons/rpg_actor/assets/RPGActor.png")
extends Node

var base_api: String:
	get: return ProjectSettings.get_setting("rpg_actor/base_api", "https://rpg.actor/api")
var plc_directory: String:
	get: return ProjectSettings.get_setting("rpg_actor/plc_directory", "https://plc.directory")
var blsk_api: String:
	get: return ProjectSettings.get_setting("rpg_actor/bluesky_api", "https://public.api.bsky.app")


## rpg.actor API Handlers
func get_actors(full: bool = false) -> Dictionary:
	var endpoint = "actors"
	if full:
		endpoint += "/full"
	return await _http_request("%s/%s" % [base_api, endpoint])


func search_actors(query: String) -> Array:
	if query == null or query.is_empty():
		return []
	if query.length() < 2:
		push_error("Query must be atleast 2 characters in length!")
	return await _http_request("%s/%s%s" % [base_api, "search?q=", query])


func metrics() -> Dictionary:
	return await _http_request("%s/%s" % [base_api, "stats"])


func health() -> Dictionary:
	return await _http_request("%s/%s" % [base_api, "health"])


func get_masters_for_player(player_did: String) -> Dictionary:
	return await _http_request("%s/%s%s" % [base_api, "masters?player=", player_did])


func get_masters_by_authority(authority_did: String) -> Dictionary:
	return await _http_request("%s/%s%s" % [base_api, "masters/by-authority?authority=", authority_did])


func get_sprite(did: String) -> Dictionary:
	return await _http_request("%s/%s%s" % [base_api, "sprite/normalized?did=", did])


func get_open_graphic_card(did: String) -> Dictionary:
	return await _http_request("%s/%s%s" % [base_api, "og/image?id=", did])


# TODO: Implement this
func give_equipment(pds: String, access_token: String, dpop_header: String):
	pass


# TODO: Implement this
func revoke_equipment():
	pass


func get_creator_pricing() -> Dictionary:
	return await _http_request("%s/%s" % [base_api, "creator/pricing"])


func check_creator(did: String) -> bool:
	var data = await _http_request("%s/%s%s" % [base_api, "creator/check?did=", did])
	return data.get("isCreator", false)


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
	return await _http_request(url)


func put_record(pds: String, collection: String, rkey: String, record: Dictionary, access_token: String, dpop_header: String) -> Dictionary:
	return await _http_request(
		pds + "/xrpc/com.atproto.repo.putRecord",
		HTTPClient.METHOD_POST,
		["Authorization: DPoP " + access_token, "DPoP: " + dpop_header],
		JSON.stringify({ "repo": "self", "collection": collection, "rkey": rkey, "record": record })
	)


## Internal Helpers
func _http_request(url: String, method: HTTPClient.Method = HTTPClient.METHOD_GET, headers: PackedStringArray = [], body: String = "") -> Variant:
	var req := HTTPRequest.new()
	add_child(req)
	await get_tree().process_frame
	req.request(url, headers, method, body)
	var result = await req.request_completed
	req.queue_free()
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
