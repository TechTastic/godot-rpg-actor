@tool
extends Node
## [XRPC] is meant to handle all HTTP and XRPC calls from [ATProto] and [RpgActor].

## This is an internal method for turning a [param params] [Dictionary] and turns it into a URI query string.
func _to_query_string(params: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in params:
		parts.append(k + "=" + str(params[k]))
	return "&".join(parts)


## This method is a wrapper for [method XRPC._http_request_raw] for handling [JSON] bodies or lack thereof.
func _http_request(url: String, method: HTTPClient.Method = HTTPClient.METHOD_GET, headers: PackedStringArray = [], body: Dictionary = {}) -> Variant:
	var raw_body = PackedByteArray()
	if !body.is_empty():
		raw_body = JSON.stringify(body).to_utf8_buffer()
	return await _http_request_raw(url, method, headers, raw_body)


## This method is used to handle all HTTP and XPRC calls by creating a [HTTPRequest] instance, adding it as a child, and sending its request as well as parsing the response or lack thereof.
func _http_request_raw(url: String, method: HTTPClient.Method = HTTPClient.METHOD_GET, headers: PackedStringArray = [], body: PackedByteArray = []) -> Variant:
	var req := HTTPRequest.new()
	add_child(req)
	await get_tree().process_frame
	req.request_raw(url, headers, method, body)
	var result = await req.request_completed
	req.queue_free()
	var code: int = result[1]
	for header: String in result[2]:
		if header.contains("Content-Type: image/"):
			return result[3]
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


## This method wraps [method XPRC._http_request_raw] explicitly for handling XRPC requests, namely those used by the [ATProto] class.
## [br][br]
## The necessary [param pds] URI can be gotten from [method ATProto.resolve_handle] by providing an AT protocol handle.
## [br]
## The [param lexicon] you'd want entirely depends on the target PDS and whatever lexicons is has/
## [br][br]
## The [param access_token] and [param dpop_header] are used for authentication via [url=https://atproto.com/specs/oauth]AT Protocol's OAuth flow[/url] which I decided not to implement.
func _xrpc(pds: String, lexicon: String, method: HTTPClient.Method = HTTPClient.METHOD_GET, params: Dictionary = {}, body: Dictionary = {}, access_token: String = "", dpop_token: String = "") -> Variant:
	if (access_token.is_empty() or dpop_token.is_empty()) and method != HTTPClient.METHOD_GET:
		push_error("XRPC: Not Authenticated")
		return null
	
	var url: String = "%s/%s/%s" % [pds.trim_suffix("/"), "xrpc", lexicon]
	if method == HTTPClient.METHOD_GET and !params.is_empty():
		url += "?" + _to_query_string(params)
	
	var headers = []
	if !access_token.is_empty() and !dpop_token.is_empty():
		headers.append_array([
			"Authorization: DPoP %s" % [access_token],
			"DPoP: %s" % [dpop_token]
		])
	
	var raw_body = PackedByteArray()
	if method == HTTPClient.METHOD_POST and !body.is_empty():
		headers.append("Content-Type: application/json")
		raw_body = JSON.stringify(body).to_utf8_buffer()
	
	return await _http_request_raw(url, method, headers, raw_body)


## This method wraps [method XPRC._xrpc] explicitly for handling XRPC GET requests, namely those used by the [ATProto] class.
## [br][br]
## The necessary [param pds] URI can be gotten from [method ATProto.resolve_handle] by providing an AT protocol handle.
## [br]
## The [param lexicon] you'd want entirely depends on the target PDS and whatever lexicons is has/
## [br][br]
## The [param access_token] and [param dpop_header] are used for authentication via [url=https://atproto.com/specs/oauth]AT Protocol's OAuth flow[/url] which I decided not to implement.
func xrpc_get(pds: String, lexicon: String, params: Dictionary = {}, access_token: String = "", dpop_token: String = ""):
	return await _xrpc(pds, lexicon, HTTPClient.METHOD_GET, params, {}, access_token, dpop_token)


## This method wraps [method XPRC._xrpc] explicitly for handling XRPC POST requests, namely those used by the [ATProto] class.
## [br]
## The necessary [param pds] URI can be gotten from [method ATProto.resolve_handle] by providing an AT protocol handle.
## The [param lexicon] you'd want entirely depends on the target PDS and whatever lexicons is has/
## [br]
## The [param access_token] and [param dpop_header] are used for authentication via [url=https://atproto.com/specs/oauth]AT Protocol's OAuth flow[/url] which I decided not to implement.
func xrpc_post(pds: String, access_token: String, dpop_token: String, lexicon: String, body: Dictionary = {}):
	return await _xrpc(pds, lexicon, HTTPClient.METHOD_POST, {}, body, access_token, dpop_token)
