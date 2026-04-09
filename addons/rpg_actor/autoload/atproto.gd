@tool
@icon("res://addons/rpg_actor/assets/ATProto.svg")
extends Node
## [ATProto] is a class meant to wrap necessary AT Protocol XRPC API calls from [RpgActor].
## [br][br]
## If you want to learn more about the AT Protocol specifications, [url=https://atproto.com/docs]here[/url] is their documentation.
## [br][br]
## [b]Why I decided not to implement AT Protocol's OAuth flow:[/b]
## [br]
## This project ballooned out of necessity for the [url=https://itch.io/jam/rpgactor]rpg.actor game jam[/url] and I am over halfway through the jam time writing documentation.
## [br]
## Also, the OAuth flow is very complicated and very heavy on specification.
## [br][br]
## If you want or need to implement OAuth yourself, [url=https://atproto.com/guides/oauth-patterns]here[/url] is their documentation and [url=https://atproto.com/specs/oauth]here[/url] is their specification.
## [br]
## If you implement their OAuth flow, feel free to make a Pull Request on [url=https://github.com/TechTastic/godot-rpg-actor]Github[/url]


## The PLC Directory is a decentralized identity directory, primarily used by the AT Protocol, that maps decentralized identifiers (did:plc) to user profile data.
## [br][br]
## This value can be changed in Project Settings under ATProto -> PLC Directory.
var plc_directory: String:
	get: return ProjectSettings.get_setting("atproto/plc_directory", "https://plc.directory")
## This is the public API for Bluesky used to resolve handles into DIDs.
## [br][br]
## This value can be changed in Project Settings under Bluesky -> API -> Public.
var public_blsk_api: String:
	get: return ProjectSettings.get_setting("bluesky/api/public", "https://public.api.bsky.app")
## This is the other public API for Bluesky which needs authentication. Thisi s currently unused in the project.
## [br][br]
## This value can be changed in Project Settings under Bluesky -> API -> Auth.
var auth_blsk_api: String:
	get: return ProjectSettings.get_setting("bluesky/api/auth", "https://bsky.social")

## This method is used to get both the DID (via Bluesky's public API) and PDS (via the PLC Directory) related to a given AT Protocol handle
func resolve_handle(handle: String) -> Dictionary:
	var clean = handle.lstrip("@")
	RpgActor.validate_handle(clean)
	var res = await XRPC.xrpc_get(public_blsk_api, "com.atproto.identity.resolveHandle", { "handle": clean })
	if res.is_empty(): return {}
	var did: String = res.get("did", "")
	var doc = await XRPC._http_request(plc_directory + "/" + did)
	var pds = _extract_pds(doc)
	return { "did": did, "pds": pds }


## This method is used for retrieving AT protocol records from the provided [param pds], in the provided [param repo], in the provided [param collection] and under the [param rkey].
## [br][br]
## While most records are public, in the event authentication is needed, [param access_token] and [param dpop_header] are exposed for use via AT Protocol's OAuth flow.
## [br][br]
## Without Authentication:
## [codeblock lang=text]
## GET {pds}/xrpc/com.atproto.repo.getRecord
##   ?repo=did:plc:...
##   &collection=actor.rpg.stats
##   &rkey=self
## [/codeblock]
## [br]
## With Authentication:
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
	RpgActor.validate_did(repo)
	return await XRPC.xrpc_get(pds, "com.atproto.repo.getRecord", { "repo": repo, "collection": collection, "rkey": rkey }, access_token, dpop_token)

## This method is used for putting AT protocol records onto the provided [param pds], in the provided [param repo], in the [param collection] and under the [param rkey].
## [br][br]
## The [param access_token] and [param dpop_header] are exposed for use via AT Protocol's OAuth flow.
## [br][br]
## [b][color=red]WARNING[/color]: Doing this overwrites any existing record in the same place. The expected use is to pull, merged, then put![/b]
## [codeblock lang=text]
## POST {pds}/xrpc/com.atproto.repo.putRecord
##   ?repo=self
##   &collection=actor.rpg.stats
##   &rkey=self
##
##   Content-Type: application/json
##   Authorization: DPoP access_token
##   DPoP: dpop_token
##
##   { record }
## [/codeblock]
func put_record(pds: String, access_token: String, dpop_header: String, collection: String, rkey: String, record: Dictionary) -> Dictionary:
	return await XRPC.xrpc_post(pds, access_token, dpop_header, "com.atproto.repo.putRecord", { "repo": "self", "collection": collection, "rkey": rkey, "record": record })


## This method is used for retrieving a list of AT protocol records from the provided [param pds], in the provided [param repo] and in the provided [param collection].
## [br][br]
## While most records are public, in the event authentication is needed, [param access_token] and [param dpop_header] are exposed for use via AT Protocol's OAuth flow.
## [br][br]
## Without Authentication:
## [codeblock lang=text]
## GET {pds}/xrpc/com.atproto.repo.listRecords
##   ?repo=did:plc:...
##   &collection=actor.rpg.stats
## [/codeblock]
## With Authentication:
## [codeblock lang=text]
## GET {pds}/xrpc/com.atproto.repo.listRecords
##   ?repo=did:plc:...
##   &collection=actor.rpg.stats
##
##   Authorization: DPoP access_token
##   DPoP: dpop_token
## [/codeblock]
func list_records(pds: String, repo: String, collection: String, access_token: String = "", dpop_header: String = "") -> Dictionary:
	RpgActor.validate_did(repo)
	return await XRPC.xrpc_get(pds, "com.atproto.repo.listRecords", { "repo": repo, "collection": collection }, access_token, dpop_header)


## An internal method used by [method ATProto.resolve_handle] to extract the PDS endpoint from the given PLC Directory entry.
func _extract_pds(plc_doc: Dictionary) -> String:
	for service in plc_doc.get("service", []):
		if service.get("type") == "AtprotoPersonalDataServer":
			return service.get("serviceEndpoint", "")
	return ""
