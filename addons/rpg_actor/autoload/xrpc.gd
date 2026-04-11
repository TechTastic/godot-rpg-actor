@tool
extends Node
## Handles HTTP and XRPC requests for [ATProto] and [RpgActor].

const MAX_BODY_SIZE: int = 10 * 1024 * 1024  ## 10 MB
const MAX_REDIRECTS: int = 3


static func encode(value: String) -> String:
	return value.uri_encode()

## Escapes BBCode tags in untrusted text so it renders as plain text in RichTextLabel.
static func sanitize_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")

func _to_query_string(params: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in params:
		parts.append(encode(str(k)) + "=" + encode(str(params[k])))
	return "&".join(parts)


## JSON wrapper around [method _http_request_raw].
func _http_request(url: String, method: HTTPClient.Method = HTTPClient.METHOD_GET, headers: PackedStringArray = [], body: Dictionary = {}) -> Variant:
	var raw_body = PackedByteArray()
	if !body.is_empty():
		raw_body = JSON.stringify(body).to_utf8_buffer()
	return await _http_request_raw(url, method, headers, raw_body)


## Low-level HTTP request with size limits and response parsing.
func _http_request_raw(url: String, method: HTTPClient.Method = HTTPClient.METHOD_GET, headers: PackedStringArray = [], body: PackedByteArray = []) -> Variant:
	# HTTPS only (except localhost for OAuth callback)
	if not url.begins_with("https://"):
		if not (url.begins_with("http://localhost") or url.begins_with("http://127.0.0.1")):
			push_error("XRPC: Refusing non-HTTPS URL: %s" % [url])
			return {}

	var req := HTTPRequest.new()
	req.download_chunk_size = 65536
	req.max_redirects = MAX_REDIRECTS
	req.body_size_limit = MAX_BODY_SIZE
	add_child(req)
	await get_tree().process_frame
	req.request_raw(url, headers, method, body)
	var result = await req.request_completed
	req.queue_free()

	var status: int = result[0]
	var code: int = result[1]
	var response_headers: PackedStringArray = result[2]
	var response_body: PackedByteArray = result[3]

	if status != HTTPRequest.RESULT_SUCCESS:
		push_warning("XRPC/HTTP: Request to %s failed with status %d" % [url, status])
		return {}

	# Return raw bytes for image responses
	for header: String in response_headers:
		if header.to_lower().contains("content-type: image/"):
			return response_body

	# Extract DPoP nonce from response headers if present
	for header: String in response_headers:
		if header.to_lower().begins_with("dpop-nonce:"):
			var nonce := header.split(":", true, 1)[1].strip_edges()
			if has_node("/root/ATProtoOAuth"):
				get_node("/root/ATProtoOAuth").set_dpop_nonce(nonce)
			break

	var body_text := response_body.get_string_from_utf8()
	if body_text.is_empty():
		if code >= 200 and code < 300:
			return {}
		push_warning("XRPC/HTTP: %s returned HTTP %d with empty body" % [url, code])
		return {}

	var res = JSON.parse_string(body_text)
	if res == null:
		push_warning("XRPC/HTTP: Failed to parse JSON from %s" % [url])
		return {}

	if code < 200 or code >= 300:
		var warning = "XRPC/HTTP: %s %s returned HTTP Response Code %d" % [ClassDB.class_get_enum_constants("HTTPClient", "Method")[method], url, code]
		if res is Dictionary:
			var error_msg = res.get("error", "")
			if not error_msg.is_empty():
				warning += " with error message: %s" % [error_msg]
		push_warning(warning)
		return {}

	return res


## XRPC request with optional OAuth/DPoP auth. Retries once on nonce rotation.
func _xrpc(pds: String, lexicon: String, method: HTTPClient.Method = HTTPClient.METHOD_GET, params: Dictionary = {}, body: Dictionary = {}, access_token: String = "", dpop_token: String = "") -> Variant:
	var url: String = "%s/%s/%s" % [pds.trim_suffix("/"), "xrpc", lexicon]

	# Auto-attach OAuth tokens for writes if available
	if access_token.is_empty() and dpop_token.is_empty() and method != HTTPClient.METHOD_GET:
		if has_node("/root/ATProtoOAuth"):
			var oauth = get_node("/root/ATProtoOAuth")
			if oauth.is_authenticated():
				var method_str: String = "GET" if method == HTTPClient.METHOD_GET else "POST"
				access_token = oauth.get_access_token()
				dpop_token = await oauth.create_dpop_proof(method_str, url)

	if (access_token.is_empty() or dpop_token.is_empty()) and method != HTTPClient.METHOD_GET:
		push_error("XRPC: Not Authenticated — cannot perform write on %s" % [lexicon])
		return null

	if method == HTTPClient.METHOD_GET and !params.is_empty():
		url += "?" + _to_query_string(params)

	# Retry once on DPoP nonce rotation
	for attempt in range(2):
		var headers: PackedStringArray = []
		if !access_token.is_empty() and !dpop_token.is_empty():
			headers.append_array([
				"Authorization: DPoP %s" % [access_token],
				"DPoP: %s" % [dpop_token]
			])

		var raw_body = PackedByteArray()
		if method == HTTPClient.METHOD_POST and !body.is_empty():
			headers.append("Content-Type: application/json")
			raw_body = JSON.stringify(body).to_utf8_buffer()

		var result = await _http_request_raw(url, method, headers, raw_body)

		# If we got an empty dict back and this is a write, it might be a DPoP nonce
		# rotation. The nonce was already extracted by _http_request_raw, so regenerate
		# the DPoP proof with the fresh nonce and retry once.
		if result is Dictionary and result.is_empty() and method != HTTPClient.METHOD_GET and attempt == 0:
			if has_node("/root/ATProtoOAuth"):
				var oauth = get_node("/root/ATProtoOAuth")
				if oauth.is_authenticated():
					var method_str: String = "POST"
					dpop_token = await oauth.create_dpop_proof(method_str, url)
					push_warning("XRPC: Retrying %s with refreshed DPoP nonce" % [lexicon])
					continue
		return result

	return {}


func xrpc_get(pds: String, lexicon: String, params: Dictionary = {}, access_token: String = "", dpop_token: String = ""):
	return await _xrpc(pds, lexicon, HTTPClient.METHOD_GET, params, {}, access_token, dpop_token)


## Authenticated POST. Tokens can be explicit or auto-attached from OAuth.
func xrpc_post(pds: String, access_token: String, dpop_token: String, lexicon: String, body: Dictionary = {}):
	return await _xrpc(pds, lexicon, HTTPClient.METHOD_POST, {}, body, access_token, dpop_token)


## POST using the active OAuth session (no explicit tokens needed).
func xrpc_post_authed(pds: String, lexicon: String, body: Dictionary = {}) -> Variant:
	return await _xrpc(pds, lexicon, HTTPClient.METHOD_POST, {}, body)


## Uploads a blob to the user's PDS. Requires an active OAuth session.
func upload_blob(pds: String, data: PackedByteArray, mime_type: String = "image/png") -> Variant:
	if not has_node("/root/ATProtoOAuth"):
		push_error("XRPC: upload_blob requires ATProtoOAuth")
		return null
	var oauth = get_node("/root/ATProtoOAuth")
	if not oauth.is_authenticated():
		push_error("XRPC: Not authenticated for blob upload")
		return null

	var url: String = "%s/xrpc/com.atproto.repo.uploadBlob" % [pds.trim_suffix("/")]
	var access_token: String = oauth.get_access_token()
	var dpop_proof: String = await oauth.create_dpop_proof("POST", url)

	var headers: PackedStringArray = [
		"Authorization: DPoP %s" % [access_token],
		"DPoP: %s" % [dpop_proof],
		"Content-Type: %s" % [mime_type]
	]

	var res = await _http_request_raw(url, HTTPClient.METHOD_POST, headers, data)
	if res is Dictionary and res.has("blob"):
		return res.get("blob")
	return res
