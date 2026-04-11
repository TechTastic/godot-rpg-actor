@tool
@icon("res://addons/rpg_actor/assets/RpgActor.svg")
extends Node
## Wraps the [url=https://rpg.actor/dev-guide#atproto-api]rpg.actor API[/url].


var base_api: String:
	get: return ProjectSettings.get_setting("rpg_actor/api", "https://rpg.actor/api")

var _sprite_cache: Dictionary = {}


## Returns all actors, or full cached data if [param full] is true.
## [br][br]
## [code lang=text]GET /api/actors[/code]
## [br]
## [code lang=text]GET /api/actors/full[/code]
func get_actors(full: bool = false) -> Dictionary:
	var endpoint = "actors"
	if full:
		endpoint += "/full"
	return await XRPC._http_request("%s/%s" % [base_api, endpoint])


## Searches actors by handle or display name (min 2 chars, max 10 results).
## [br][br]
## [code lang=text]GET /api/search?q=...[/code]
func search_actors(query: String) -> Array:
	if query == null or query.is_empty():
		return []
	if query.length() < 2:
		push_error("Query must be atleast 2 characters in length!")
		return []
	return await XRPC._http_request("%s/%s%s" % [base_api, "search?q=", query.uri_encode()])


## Registry summary: actor count, system count, master authority count.
## [br][br]
## [code lang=text]GET /api/stats[/code]
func metrics() -> Dictionary:
	return await XRPC._http_request("%s/%s" % [base_api, "stats"])


## Service health, actor/master counts, and uptime.
## [br][br]
## [code lang=text]GET /api/health[/code]
func health() -> Dictionary:
	return await XRPC._http_request("%s/%s" % [base_api, "health"])


## Master validations for a player (add &verify=true to check live).
## [br][br]
## [code lang=text]GET /api/masters?player=did:...[/code]
func get_masters_for_player(player_did: String) -> Dictionary:
	if not validate_did(player_did): return {}
	return await XRPC._http_request("%s/%s%s" % [base_api, "masters?player=", player_did.uri_encode()])


## All players validated by a specific master/GM.
## [br][br]
## [code lang=text]GET /api/masters/by-authority?authority=did:...[/code]
func get_masters_by_authority(authority_did: String) -> Dictionary:
	if not validate_did(authority_did): return {}
	return await XRPC._http_request("%s/%s%s" % [base_api, "masters/by-authority?authority=", authority_did.uri_encode()])


## Standard 144×192 PNG sprite sheet for any actor.
## [br][br]
## [color=gold]Warning[/color]: rpg.actor allows custom sprites of any size which may produce inaccurate spritesheets.
## [br][br]
## [code lang=text]GET /api/sprite/normalized?did=...[/code]
func get_sprite(did: String) -> PackedByteArray:
	if not validate_did(did): return PackedByteArray()
	var data = await XRPC._http_request("%s/%s%s" % [base_api, "sprite/normalized?did=", did.uri_encode()])
	return _sprite_cache.get_or_add(did, data)


## Generated 1200×630 Open Graph card image.
## [br][br]
## [code lang=text]GET /api/og/image?id=...[/code]
func get_open_graphic_card(did: String) -> PackedByteArray:
	if not validate_did(did): return PackedByteArray()
	return await XRPC._http_request("%s/%s%s" % [base_api, "og/image?id=", did.uri_encode()])


## Equipment index summary.
## [br][br]
## [code lang=text]GET /api/equipment[/code]
func get_equipment() -> Dictionary:
	return await XRPC._http_request("%s/%s" % [base_api, "equipment"])


## All items and gives for a player.
## [br][br]
## [code lang=text]GET /api/equipment?player=did:...[/code]
func get_equipment_by_player(did: String) -> Dictionary:
	if not validate_did(did): return {}
	return await XRPC._http_request("%s/%s%s" % [base_api, "equipment?player=", did.uri_encode()])


## All gives issued by a provider.
## [br][br]
## [code lang=text]GET /api/equipment?provider=did:...[/code]
func get_equipment_by_provider(did: String) -> Dictionary:
	if not validate_did(did): return {}
	return await XRPC._http_request("%s/%s%s" % [base_api, "equipment?provider=", did.uri_encode()])


## Current pricing tiers and PDS status.
## [br][br]
## [code lang=text]GET /api/creator/pricing[/code]
func get_creator_pricing() -> Dictionary:
	return await XRPC._http_request("%s/%s" % [base_api, "creator/pricing"])


## Checks if a DID is a registered creator.
## [br][br]
## [code lang=text]GET /api/creator/check?did=...[/code]
func check_creator(did: String) -> bool:
	if not validate_did(did): return false
	var data = await XRPC._http_request("%s/%s%s" % [base_api, "creator/check?did=", did.uri_encode()])
	return data.get("isCreator", false)


## Password login for rpg.actor native accounts.
## [br][br]
## [code lang=text]POST /api/pds-login[/code]
## @experimental
func pds_login(handle: String, password: String) -> Dictionary:
	if not validate_handle(handle): return {}
	return await XRPC._http_request("%s/%s" % [base_api, "pds-login"], HTTPClient.METHOD_POST, [
		"Content-Type: application/json"
	], {
		"handle": handle,
		"password": password
	})


## Updates PDS account email.
## [br][br]
## [code lang=text]POST /api/account/update-email[/code]
## @experimental
func update_email(did: String, password: String, email: String) -> Dictionary:
	if not validate_did(did): return {}
	return await XRPC._http_request("%s/%s" % [base_api, "account/update-email"], HTTPClient.METHOD_POST, [
		"Content-Type: application/json"
	], {
		"did": did,
		"password": password,
		"email": email
	})


## Changes account password.
## [br][br]
## [code lang=text]POST /api/account/change-password[/code]
## @experimental
func change_password(did: String, current_password: String, new_password: String) -> Dictionary:
	if not validate_did(did): return {}
	return await XRPC._http_request("%s/%s" % [base_api, "account/change-password"], HTTPClient.METHOD_POST, [
		"Content-Type: application/json"
	], {
		"did": did,
		"current_password": current_password,
		"new_password": new_password
	})


## Triggers an immediate cache refresh after a stat/sprite mutation.
## [br][br]
## [code lang=text]POST /api/refresh-actor[/code]
## @experimental
func refresh_actor(did: String) -> Variant:
	if not validate_did(did): return null
	var data = await XRPC._http_request("%s/%s" % [base_api, "refresh-actor"], HTTPClient.METHOD_POST, [
		"Content-Type: application/json"
	], {
		"did": did
	})
	if data is Dictionary and data.get("status") == "ok":
		_sprite_cache.erase(did)
	return data


## Submits a contact form.
## [br][br]
## [code lang=text]POST /api/contact[/code]
## @experimental
func contact(email: String, subject: String, message: String, handle: String = "") -> Dictionary:
	var data = {
		"email": email,
		"subject": subject,
		"message": message
	}
	if !handle.is_empty():
		if not validate_handle(handle):
			return {}
		data.set("handle", handle)
	return await XRPC._http_request("%s/%s" % [base_api, "contact"], HTTPClient.METHOD_POST, [
		"Content-Type: application/json"
	], data)


## Validates an AT Protocol handle (at least 2 dot-separated segments, alphanumeric + . -).
func validate_handle(handle: String) -> bool:
	var parts = handle.split(".")
	if parts.size() < 2:
		push_error("Provided handle %s is not a valid AT protocol handle!" % [handle])
		return false
	var valid_chars := RegEx.new()
	valid_chars.compile("^[a-zA-Z0-9][a-zA-Z0-9.-]*$")
	if not valid_chars.search(handle):
		push_error("Provided handle %s contains invalid characters!" % [handle])
		return false
	return true


## Validates an AT Protocol DID (did:plc or did:web).
func validate_did(did: String) -> bool:
	var parts = did.split(":")
	if parts.size() < 3 or parts[0] != "did":
		push_error("Provided DID %s is not a valid AT protocol DID string!" % [did])
		return false
	if parts[1] != "plc" and parts[1] != "web":
		push_error("Provided DID %s uses unsupported method '%s' (expected plc or web)" % [did, parts[1]])
		return false
	return true
