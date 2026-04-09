@tool
@icon("res://addons/rpg_actor/assets/RPGActor.png")
extends Node

var base_api: String:
	get: return ProjectSettings.get_setting("rpg_actor/base_api", "https://rpg.actor/api")
var plc_directory: String:
	get: return ProjectSettings.get_setting("rpg_actor/plc_directory", "https://plc.directory")
var blsk_api: String:
	get: return ProjectSettings.get_setting("rpg_actor/bluesky_api", "https://public.api.bsky.app")


## Registry
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


## Masters
func get_masters_for_player(player_did: String) -> Dictionary:
	return await _http_request("%s/%s%s" % [base_api, "masters?player=", player_did])


func get_masters_by_authority(authority_did: String) -> Dictionary:
	return await _http_request("%s/%s%s" % [base_api, "masters/by-authority?authority=", authority_did])


## Sprites and Media
func get_sprite(did: String) -> Dictionary:
	return await _http_request("%s/%s%s" % [base_api, "sprite/normalized?did=", did])


func get_open_graphic_card(did: String) -> Dictionary:
	return await _http_request("%s/%s%s" % [base_api, "og/image?id=", did])


## Equipment
# TODO: Implement this
func give_equipment(pds: String, access_token: String, dpop_header: String):
	pass


# TODO: Implement this
func revoke_equipment():
	pass


## Creator
func get_creator_pricing() -> Dictionary:
	return await _http_request("%s/%s" % [base_api, "creator/pricing"])


func check_creator(did: String) -> bool:
	var data = await _http_request("%s/%s%s" % [base_api, "creator/check?did=", did])
	return data.get("isCreator", false)


## Account
func pds_login(handle: String, password: String) -> Dictionary:
	return await _http_request("%s/%s" % [base_api, "api/pds-login"], HTTPClient.METHOD_POST, [
		"Content-Type: application/json"
	], JSON.stringify({
		"handle": handle,
		"password": password
	}))


func update_email(did: String, password: String, email: String) -> Dictionary:
	return await _http_request("%s/%s" % [base_api, "api/account/update-email"], HTTPClient.METHOD_POST, [
		"Content-Type: application/json"
	], JSON.stringify({
		"did": did,
		"password": password,
		"email": email
	}))


func change_password(did: String, current_password: String, new_password: String) -> Dictionary:
	return await _http_request("%s/%s" % [base_api, "api/account/change-password"], HTTPClient.METHOD_POST, [
		"Content-Type: application/json"
	], JSON.stringify({
		"did": did,
		"current_password": current_password,
		"new_password": new_password
	}))


func refresh_actor(did: String) -> Dictionary:
	return await _http_request("%s/%s" % [base_api, "api/refresh-actor"], HTTPClient.METHOD_POST, [
		"Content-Type: application/json"
	], JSON.stringify({
		"did": did
	}))


func contact(email: String, subject: String, message: String, handle: String = "") -> Dictionary:
	var data = {
		"email": email,
		"subject": subject,
		"message": message
	}
	if !handle.is_empty():
		data.set("handle", handle)
	return await _http_request("%s/%s" % [base_api, "api/contact"], HTTPClient.METHOD_POST, [
		"Content-Type: application/json"
	], JSON.stringify(data))


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
	var res = JSON.parse_string(result[3].get_string_from_utf8())
	if code != 200:
		var warning = "XRPC/HTTP: %s %s returned HTTP Response Code %d" % [ClassDB.class_get_enum_constants("HTTPClient", "Method")[method], url, code]
		if res is Dictionary:
			var error = res.get("error", "")
			if !error.is_empty():
				warning += " with error message: %s" % [error]
		push_warning(warning)
		return {}
	return res


func _extract_pds(plc_doc: Dictionary) -> String:
	for service in plc_doc.get("service", []):
		if service.get("type") == "AtprotoPersonalDataServer":
			return service.get("serviceEndpoint", "")
	return ""
