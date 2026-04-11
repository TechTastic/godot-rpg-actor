@tool
@icon("res://addons/rpg_actor/assets/ATProto.svg")
extends Node
## AT Protocol identity resolution and record operations.
## Supports [code]did:plc[/code] and [code]did:web[/code].


var plc_directory: String:
	get: return ProjectSettings.get_setting("atproto/plc_directory", "https://plc.directory")

var public_blsk_api: String:
	get: return ProjectSettings.get_setting("bluesky/api/public", "https://public.api.bsky.app")

var auth_blsk_api: String:
	get: return ProjectSettings.get_setting("bluesky/api/auth", "https://bsky.social")


## Resolves a handle to its DID and PDS endpoint.
func resolve_handle(handle: String) -> Dictionary:
	var clean = handle.lstrip("@")
	if not RpgActor.validate_handle(clean):
		return {}
	var res = await XRPC.xrpc_get(public_blsk_api, "com.atproto.identity.resolveHandle", { "handle": clean })
	if res == null or (res is Dictionary and res.is_empty()):
		return {}
	var did: String = res.get("did", "")
	if did.is_empty():
		return {}
	var pds = await resolve_pds_from_did(did)
	return { "did": did, "pds": pds }


## Resolves the PDS endpoint for a DID.
func resolve_pds_from_did(did: String) -> String:
	if not RpgActor.validate_did(did):
		return ""
	var doc: Dictionary
	if did.begins_with("did:plc:"):
		doc = await XRPC._http_request(plc_directory + "/" + did.uri_encode())
	elif did.begins_with("did:web:"):
		var domain = did.replace("did:web:", "").replace("%3A", ":").replace("%2F", "/")
		doc = await XRPC._http_request("https://%s/.well-known/did.json" % [domain])
	else:
		push_error("ATProto: Unsupported DID method: %s" % [did])
		return ""
	if doc == null or doc.is_empty():
		return ""
	return _extract_pds(doc)


## Gets a record from a PDS.
## [br][br]
## [codeblock lang=text]
## GET {pds}/xrpc/com.atproto.repo.getRecord
##   ?repo=did:plc:...
##   &collection=actor.rpg.stats
##   &rkey=self
##
##   Authorization: DPoP access_token
##   DPoP: dpop_token
## [/codeblock]
func get_record(pds: String, repo: String, collection: String, rkey: String = "self", access_token: String = "", dpop_token: String = "") -> Dictionary:
	if not RpgActor.validate_did(repo):
		return {}
	return await XRPC.xrpc_get(pds, "com.atproto.repo.getRecord", { "repo": repo, "collection": collection, "rkey": rkey }, access_token, dpop_token)


## Writes a record to a PDS. Pull, merge, then put!
## [br][br]
## [codeblock lang=text]
## GET {pds}/xrpc/com.atproto.repo.putRecords
##   ?repo=did:plc:...
##   &collection=actor.rpg.stats
##   &reky=...
##
##   Authorization: DPoP access_token
##   DPoP: dpop_token
##
##   record
## [/codeblock]
func put_record(pds: String, repo: String, collection: String, rkey: String, record: Dictionary, access_token: String = "", dpop_token: String = "") -> Dictionary:
	if not RpgActor.validate_did(repo):
		return {}
	return await XRPC.xrpc_post(pds, access_token, dpop_token, "com.atproto.repo.putRecord", { "repo": repo, "collection": collection, "rkey": rkey, "record": record })


## Fetches the existing stats record, merges a single system key, and puts it back.
## Only touches the key you specify — other systems' data is preserved.
## Optionally calls refresh_actor to update the rpg.actor cache.
func merge_and_put_stats(pds: String, repo: String, system_key: String, data: Dictionary, refresh: bool = true) -> Dictionary:
	if not RpgActor.validate_did(repo):
		return {}

	# Fetch existing record
	var existing = await get_record(pds, repo, "actor.rpg.stats")
	var record: Dictionary = {}
	if existing is Dictionary and existing.has("value"):
		record = existing["value"].duplicate(true)
	else:
		record["createdAt"] = Time.get_datetime_string_from_system(true) + "Z"

	# Merge only the specified key
	record["$type"] = "actor.rpg.stats"
	record[system_key] = data
	record["updatedAt"] = Time.get_datetime_string_from_system(true) + "Z"

	var result = await put_record(pds, repo, "actor.rpg.stats", "self", record)

	# Refresh rpg.actor cache so the site shows updated data
	if refresh and result is Dictionary and not result.is_empty():
		await RpgActor.refresh_actor(repo)

	return result


## Lists records in a collection.
## [br][br]
## [codeblock lang=text]
## GET {pds}/xrpc/com.atproto.repo.listRecords
##   ?repo=did:plc:...
##   &collection=actor.rpg.stats
##
##   Authorization: DPoP access_token
##   DPoP: dpop_token
## [/codeblock]
func list_records(pds: String, repo: String, collection: String, access_token: String = "", dpop_header: String = "") -> Dictionary:
	if not RpgActor.validate_did(repo):
		return {}
	return await XRPC.xrpc_get(pds, "com.atproto.repo.listRecords", { "repo": repo, "collection": collection }, access_token, dpop_header)


## Extracts the PDS endpoint from a DID document.
func _extract_pds(plc_doc: Dictionary) -> String:
	for service in plc_doc.get("service", []):
		if service.get("id") == "#atproto_pds" or service.get("type") == "AtprotoPersonalDataServer":
			return service.get("serviceEndpoint", "")
	return ""
