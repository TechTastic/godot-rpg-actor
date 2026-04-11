@tool
extends Node
## AT Protocol OAuth with PKCE and DPoP.
##
## Handles browser-based login: PDS discovery, DPoP keypair generation,
## PKCE challenge, local callback server, and token exchange.
##
## [codeblock]
## var result = await ATProtoOAuth.login("yourname.bsky.social")
## if result.success:
##     print("Logged in as: ", result.did)
## [/codeblock]

signal login_completed(success: bool, did: String)
signal login_failed(error: String)
signal logout_completed()

## OAuth scope from project settings.
var _scope: String:
	get: return ProjectSettings.get_setting("atproto/oauth/scope", "atproto repo:actor.rpg.stats repo:actor.rpg.sprite repo:actor.rpg.master repo:equipment.rpg.item repo:equipment.rpg.give blob:image/*")

## How long to wait for the browser callback before timing out (seconds).
const CALLBACK_TIMEOUT := 300.0

# --- Session state ---
var _access_token: String = ""
var _refresh_token: String = ""
var _session_did: String = ""
var _session_handle: String = ""
var _user_pds: String = ""
var _dpop_nonce: String = ""
var _oauth_meta: Dictionary = {}

# --- Crypto state ---
var _crypto: Crypto
var _ecdsa_key: CryptoKey
var _public_jwk: Dictionary = {}

# --- PKCE state ---
var _code_verifier: String = ""
var _code_challenge: String = ""

# --- OAuth flow state ---
var _oauth_state: String = ""
var _callback_server: TCPServer
var _callback_port: int = 0
var _is_waiting_for_callback: bool = false
var _client_id: String = ""

# --- Refresh timer ---
var _refresh_timer: Timer


func _ready():
	_crypto = Crypto.new()
	_setup_refresh_timer()


func _setup_refresh_timer():
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 25 * 60.0
	_refresh_timer.one_shot = false
	_refresh_timer.timeout.connect(_on_refresh_timer)
	add_child(_refresh_timer)


func _process(_delta: float):
	if _is_waiting_for_callback and _callback_server != null:
		_poll_callback_server()


# ============================================================
#  Public API
# ============================================================


## Returns true if we have an active access token.
func is_authenticated() -> bool:
	return not _access_token.is_empty()


## Returns the current access token, or empty string if not authenticated.
func get_access_token() -> String:
	return _access_token


## Returns the DID of the authenticated user.
func get_session_did() -> String:
	return _session_did


## Returns the handle of the authenticated user.
func get_session_handle() -> String:
	return _session_handle


## Returns the PDS endpoint of the authenticated user.
func get_user_pds() -> String:
	return _user_pds


## Called by XRPC when the server sends a new DPoP nonce.
func set_dpop_nonce(nonce: String) -> void:
	_dpop_nonce = nonce


## Opens the browser for OAuth login. Returns { success, did, handle, error }.
func login(handle: String) -> Dictionary:
	if handle.is_empty():
		return { "success": false, "error": "Handle is required" }

	var clean_handle := handle.lstrip("@")
	push_warning("ATProtoOAuth: Starting OAuth for %s" % [clean_handle])

	# Step 1: Resolve handle -> DID + PDS
	var identity = await ATProto.resolve_handle(clean_handle)
	if identity.is_empty() or identity.get("did", "").is_empty():
		var err := "Failed to resolve handle: %s" % [clean_handle]
		login_failed.emit(err)
		return { "success": false, "error": err }

	_session_did = identity.get("did", "")
	_user_pds = identity.get("pds", "")
	_session_handle = clean_handle

	if _user_pds.is_empty():
		var err := "Could not find PDS for %s" % [clean_handle]
		login_failed.emit(err)
		return { "success": false, "error": err }

	# Step 2: Discover OAuth metadata from the PDS
	var meta_result = await _fetch_auth_metadata(_user_pds)
	if meta_result.is_empty():
		var err := "PDS does not support OAuth"
		login_failed.emit(err)
		return { "success": false, "error": err }
	_oauth_meta = meta_result

	if not _oauth_meta.has("authorization_endpoint") or not _oauth_meta.has("token_endpoint"):
		var err := "PDS OAuth metadata is incomplete"
		login_failed.emit(err)
		return { "success": false, "error": err }

	# Step 3: Generate DPoP keypair, PKCE challenge, and CSRF state
	_ecdsa_key = _crypto.generate_rsa(2048)
	await _generate_dpop_keypair()

	# Step 4: Generate PKCE
	_generate_pkce()

	# Step 5: Generate state for CSRF protection
	_oauth_state = _random_b64u(16)

	# Step 6: Start local HTTP server to receive the browser callback
	var port_setting = ProjectSettings.get_setting("atproto/oauth/local_callback_port", 7000)
	_callback_server = TCPServer.new()
	var err_code = _callback_server.listen(port_setting, "127.0.0.1")
	if err_code != OK:
		# Try a random port if configured port is busy
		err_code = _callback_server.listen(0, "127.0.0.1")
		if err_code != OK:
			var err := "Failed to start callback server"
			login_failed.emit(err)
			return { "success": false, "error": err }
	_callback_port = port_setting
	var redirect_uri := "http://127.0.0.1:%d/callback" % [_callback_port]

	# Step 7: Build client_id
	var client_id_setting: String = ProjectSettings.get_setting("atproto/oauth/client_id_url", "http://localhost")
	if client_id_setting.begins_with("http://localhost"):
		_client_id = "http://localhost?redirect_uri=%s&scope=%s" % [
			redirect_uri.uri_encode(),
			_scope.uri_encode()
		]
	else:
		_client_id = client_id_setting

	# Step 8: Build authorization URL
	var auth_params := {
		"response_type": "code",
		"client_id": _client_id,
		"redirect_uri": redirect_uri,
		"scope": _scope,
		"state": _oauth_state,
		"code_challenge": _code_challenge,
		"code_challenge_method": "S256",
		"login_hint": clean_handle
	}

	var auth_url: String
	if _oauth_meta.has("pushed_authorization_request_endpoint"):
		var par_url: String = _oauth_meta["pushed_authorization_request_endpoint"]
		var par_body := _dict_to_urlencoded(auth_params)
		var dpop_proof := await _create_dpop_jwt("POST", par_url)

		var par_headers: PackedStringArray = [
			"Content-Type: application/x-www-form-urlencoded",
			"DPoP: %s" % [dpop_proof]
		]
		var par_result = await XRPC._http_request_raw(par_url, HTTPClient.METHOD_POST, par_headers, par_body.to_utf8_buffer())
		if par_result is Dictionary and par_result.has("request_uri"):
			auth_url = "%s?client_id=%s&request_uri=%s" % [
				_oauth_meta["authorization_endpoint"],
				_client_id.uri_encode(),
				str(par_result["request_uri"]).uri_encode()
			]
		else:
			auth_url = _oauth_meta["authorization_endpoint"] + "?" + _dict_to_urlencoded(auth_params)
	else:
		auth_url = _oauth_meta["authorization_endpoint"] + "?" + _dict_to_urlencoded(auth_params)

	# Step 9: Open browser
	OS.shell_open(auth_url)

	# Step 10: Wait for callback
	_is_waiting_for_callback = true
	var callback_result := await _wait_for_callback(redirect_uri)
	_is_waiting_for_callback = false

	if _callback_server != null:
		_callback_server.stop()
		_callback_server = null

	if callback_result.get("error", "") != "":
		var err_msg: String = callback_result.get("error", "OAuth failed")
		login_failed.emit(err_msg)
		return { "success": false, "error": err_msg }

	# Step 11: Verify state (CSRF protection)
	if callback_result.get("state", "") != _oauth_state:
		var err := "OAuth state mismatch — possible CSRF attack"
		login_failed.emit(err)
		return { "success": false, "error": err }

	# Step 12: Exchange code for tokens
	var code: String = callback_result.get("code", "")
	var token_result = await _exchange_code_for_tokens(code, redirect_uri)
	if token_result.get("error", "") != "":
		var err_msg: String = token_result.get("error", "Token exchange failed")
		login_failed.emit(err_msg)
		return { "success": false, "error": err_msg }

	_access_token = token_result.get("access_token", "")
	_refresh_token = token_result.get("refresh_token", "")
	if token_result.has("sub"):
		_session_did = token_result["sub"]

	_refresh_timer.start()
	# Bring the Godot window back to the foreground after browser auth
	DisplayServer.window_move_to_foreground()

	push_warning("ATProtoOAuth: Authenticated as %s (%s)" % [_session_handle, _session_did])
	login_completed.emit(true, _session_did)
	return { "success": true, "did": _session_did, "handle": _session_handle }


## Clears all session state.
func logout() -> void:
	_access_token = ""
	_refresh_token = ""
	_session_did = ""
	_session_handle = ""
	_user_pds = ""
	_dpop_nonce = ""
	_oauth_meta = {}
	_refresh_timer.stop()
	if _callback_server != null:
		_callback_server.stop()
		_callback_server = null
	_is_waiting_for_callback = false
	push_warning("ATProtoOAuth: Logged out")
	logout_completed.emit()


## Creates a DPoP proof JWT for an authenticated request.
func create_dpop_proof(http_method: String, target_url: String) -> String:
	return await _create_dpop_jwt(http_method, target_url, _access_token)


## Refreshes OAuth tokens using the refresh token.
func refresh_tokens() -> bool:
	if _refresh_token.is_empty() or not _oauth_meta.has("token_endpoint"):
		push_warning("ATProtoOAuth: No session to refresh")
		return false

	var token_url: String = _oauth_meta["token_endpoint"]
	var body_params := {
		"grant_type": "refresh_token",
		"refresh_token": _refresh_token,
		"client_id": _client_id
	}
	var body_str := _dict_to_urlencoded(body_params)
	var dpop_proof := await _create_dpop_jwt("POST", token_url)

	var headers: PackedStringArray = [
		"Content-Type: application/x-www-form-urlencoded",
		"DPoP: %s" % [dpop_proof]
	]

	var res = await XRPC._http_request_raw(token_url, HTTPClient.METHOD_POST, headers, body_str.to_utf8_buffer())

	if res is Dictionary and res.has("access_token"):
		_access_token = res["access_token"]
		if res.has("refresh_token"):
			_refresh_token = res["refresh_token"]
		if res.has("sub"):
			_session_did = res["sub"]
		push_warning("ATProtoOAuth: Tokens refreshed")
		return true

	push_warning("ATProtoOAuth: Token refresh failed")
	return false


# ============================================================
#  OAuth metadata discovery
# ============================================================

func _fetch_auth_metadata(pds: String) -> Dictionary:
	# Step 1: PDS is a resource server — ask it for the authorization server
	var resource_meta = await XRPC._http_request(pds.trim_suffix("/") + "/.well-known/oauth-protected-resource")
	if resource_meta == null or not resource_meta is Dictionary:
		return {}
	var auth_servers = resource_meta.get("authorization_servers", [])
	if auth_servers is Array and auth_servers.size() == 0:
		return {}
	var auth_server_url: String = auth_servers[0]

	# Step 2: Fetch OAuth metadata from the authorization server
	var meta = await XRPC._http_request(auth_server_url.trim_suffix("/") + "/.well-known/oauth-authorization-server")
	if meta == null or not meta is Dictionary:
		return {}
	meta["_authorization_server_url"] = auth_server_url
	return meta


## Generates an RSA-2048 keypair for DPoP proof signing.
## True ES256 requires a GDExtension; RSA works with most AT Protocol servers.
func _generate_dpop_keypair() -> void:
	_ecdsa_key = _crypto.generate_rsa(2048)
	var pub_pem := _ecdsa_key.save_to_string(true)
	_public_jwk = _pem_to_jwk(pub_pem)


## Converts a PEM public key to a JWK dictionary for the DPoP header.
func _pem_to_jwk(pem: String) -> Dictionary:
	# Strip PEM headers and decode base64
	var clean = pem.replace("-----BEGIN PUBLIC KEY-----", "").replace("-----END PUBLIC KEY-----", "").replace("-----BEGIN RSA PUBLIC KEY-----", "").replace("-----END RSA PUBLIC KEY-----", "").strip_edges().replace("\n", "").replace("\r", "")
	var der := Marshalls.base64_to_raw(clean)
	var params := _extract_rsa_params(der)
	return {
		"kty": "RSA",
		"use": "sig",
		"alg": "RS256",
		"n": _b64u_encode_bytes(params[0]),
		"e": _b64u_encode_bytes(params[1])
	}


## Parses DER SPKI to extract RSA modulus and exponent.
func _extract_rsa_params(der: PackedByteArray) -> Array:
	var pos := _der_skip_tag_length(der, 0)
	pos = _der_skip_tlv(der, pos)
	pos += 1
	var result := _der_read_length(der, pos)
	pos = result[1]
	pos += 1
	pos = _der_skip_tag_length(der, pos)
	pos += 1
	result = _der_read_length(der, pos)
	var n_len: int = result[0]
	pos = result[1]
	var n_bytes := der.slice(pos, pos + n_len)
	if n_bytes.size() > 0 and n_bytes[0] == 0:
		n_bytes = n_bytes.slice(1)
	pos += n_len
	pos += 1
	result = _der_read_length(der, pos)
	var e_len: int = result[0]
	pos = result[1]
	var e_bytes := der.slice(pos, pos + e_len)
	if e_bytes.size() > 0 and e_bytes[0] == 0:
		e_bytes = e_bytes.slice(1)
	return [n_bytes, e_bytes]


func _der_skip_tag_length(der: PackedByteArray, pos: int) -> int:
	pos += 1
	var result := _der_read_length(der, pos)
	return result[1]  # position right after the length bytes


func _der_skip_tlv(der: PackedByteArray, pos: int) -> int:
	pos += 1
	var result := _der_read_length(der, pos)
	return result[1] + result[0]  # jump past length bytes + content


func _der_read_length(der: PackedByteArray, pos: int) -> Array:
	if der[pos] < 0x80:
		return [der[pos], pos + 1]
	var num_bytes := der[pos] & 0x7F
	pos += 1
	var length := 0
	for i in range(num_bytes):
		length = (length << 8) | der[pos]
		pos += 1
	return [length, pos]


## Builds a DPoP proof JWT. Binds to the HTTP method and URL.
func _create_dpop_jwt(http_method: String, target_url: String, access_token: String = "") -> String:
	var header := {
		"typ": "dpop+jwt",
		"alg": "RS256",
		"jwk": _public_jwk
	}

	var base_url := target_url.split("?")[0]
	var payload := {
		"jti": _random_b64u(16),
		"htm": http_method,
		"htu": base_url,
		"iat": int(Time.get_unix_time_from_system())
	}

	if not _dpop_nonce.is_empty():
		payload["nonce"] = _dpop_nonce

	if not access_token.is_empty():
		var ath := _sha256_b64u(access_token)
		payload["ath"] = ath

	return _sign_jwt(header, payload)


## Signs a JWT with the RSA key. Pre-hashes the input for Crypto.sign().
func _sign_jwt(header: Dictionary, payload: Dictionary) -> String:
	var h := _b64u_encode_string(JSON.stringify(header))
	var p := _b64u_encode_string(JSON.stringify(payload))
	var signing_input := h + "." + p
	var hash_ctx := HashingContext.new()
	hash_ctx.start(HashingContext.HASH_SHA256)
	hash_ctx.update(signing_input.to_utf8_buffer())
	var digest := hash_ctx.finish()
	var signature := _crypto.sign(HashingContext.HASH_SHA256, digest, _ecdsa_key)
	var s := _b64u_encode_bytes(signature)
	return signing_input + "." + s


## Generates PKCE code verifier and S256 challenge.
func _generate_pkce() -> void:
	_code_verifier = _random_b64u(32)
	var hash_ctx := HashingContext.new()
	hash_ctx.start(HashingContext.HASH_SHA256)
	hash_ctx.update(_code_verifier.to_utf8_buffer())
	var digest := hash_ctx.finish()
	_code_challenge = _b64u_encode_bytes(digest)


## Exchanges the authorization code for access + refresh tokens.
func _exchange_code_for_tokens(code: String, redirect_uri: String) -> Dictionary:
	var token_url: String = _oauth_meta.get("token_endpoint", "")
	if token_url.is_empty():
		return { "error": "No token endpoint" }

	var body_params := {
		"grant_type": "authorization_code",
		"code": code,
		"redirect_uri": redirect_uri,
		"client_id": _client_id,
		"code_verifier": _code_verifier
	}
	var body_str := _dict_to_urlencoded(body_params)
	var dpop_proof := await _create_dpop_jwt("POST", token_url)

	var headers: PackedStringArray = [
		"Content-Type: application/x-www-form-urlencoded",
		"DPoP: %s" % [dpop_proof]
	]

	var res = await XRPC._http_request_raw(token_url, HTTPClient.METHOD_POST, headers, body_str.to_utf8_buffer())

	if res is Dictionary and res.has("access_token"):
		return res
	if res is Dictionary and res.has("error"):
		return { "error": res.get("error_description", res.get("error", "Token exchange failed")) }
	return { "error": "Unknown token exchange error" }


## Blocks until the browser redirects back or we time out.
func _wait_for_callback(redirect_uri: String) -> Dictionary:
	var timeout_time := Time.get_ticks_msec() + int(CALLBACK_TIMEOUT * 1000)

	while _is_waiting_for_callback:
		if Time.get_ticks_msec() > timeout_time:
			return { "error": "OAuth timed out — no response from browser" }
		await get_tree().process_frame

	# Result was set by _poll_callback_server
	return _callback_result


var _callback_result: Dictionary = {}


## Polls the TCP server for an incoming OAuth callback connection.
func _poll_callback_server():
	if _callback_server == null or not _callback_server.is_listening():
		return
	if not _callback_server.is_connection_available():
		return

	var peer := _callback_server.take_connection()
	if peer == null:
		return

	# Read the HTTP request
	peer.set_no_delay(true)
	var request_data := ""
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 3000:
		if peer.get_available_bytes() > 0:
			request_data += peer.get_utf8_string(peer.get_available_bytes())
			if "\r\n\r\n" in request_data:
				break
		else:
			await get_tree().process_frame

	if request_data.is_empty():
		peer.disconnect_from_host()
		return

	# Parse the request line
	var first_line := request_data.split("\r\n")[0]
	var parts := first_line.split(" ")
	if parts.size() < 2:
		peer.disconnect_from_host()
		return

	var path := parts[1]
	if not path.begins_with("/callback"):
		var response := "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
		peer.put_data(response.to_utf8_buffer())
		peer.disconnect_from_host()
		return

	# Parse query parameters from the callback URL
	var query_start := path.find("?")
	var params := {}
	if query_start >= 0:
		var query_str := path.substr(query_start + 1)
		for pair in query_str.split("&"):
			var kv := pair.split("=", true, 1)
			if kv.size() == 2:
				params[kv[0]] = kv[1].uri_decode()

	var code := params.get("code", "")
	var state := params.get("state", "")
	var error := params.get("error", "")

	# Send a nice response page
	var title := "Authentication Failed" if not error.is_empty() else "Signed In"
	var body_msg: String
	if not error.is_empty():
		body_msg = "<p>%s</p><p>Close this tab and try again.</p>" % [error.xml_escape()]
	else:
		body_msg = "<p>Authentication successful!</p><p>You can close this tab and return to the game.</p>"

	var html := "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>RPG Actor — %s</title>" % [title]
	html += "<style>*{margin:0;padding:0;box-sizing:border-box}"
	html += "body{min-height:100vh;display:flex;align-items:center;justify-content:center;"
	html += "background:#0d1b2a;font-family:system-ui,sans-serif;color:#e0e0e0}"
	html += ".card{background:#1a2744;border-radius:16px;padding:40px 48px;text-align:center;"
	html += "box-shadow:0 8px 32px rgba(0,0,0,0.5);max-width:380px}"
	html += "h1{font-size:22px;color:white;margin-bottom:8px}"
	html += "p{font-size:14px;color:#aabbcc;margin:4px 0}</style></head>"
	html += "<body><div class=\"card\"><h1>%s</h1>%s</div></body></html>" % [title, body_msg]

	var response := "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\n\r\n%s" % [html.to_utf8_buffer().size(), html]
	peer.put_data(response.to_utf8_buffer())

	# Give the browser time to receive the response
	await get_tree().create_timer(0.5).timeout
	peer.disconnect_from_host()

	if not error.is_empty():
		_callback_result = { "error": "OAuth denied: %s" % [error] }
	else:
		_callback_result = { "code": code, "state": state }

	_is_waiting_for_callback = false


## Auto-refresh runs every 25 minutes while logged in.
func _on_refresh_timer():
	if _refresh_token.is_empty():
		return
	var success := await refresh_tokens()
	if not success:
		push_warning("ATProtoOAuth: Auto-refresh failed")


func _random_b64u(byte_length: int) -> String:
	var bytes := _crypto.generate_random_bytes(byte_length)
	return _b64u_encode_bytes(bytes)


func _b64u_encode_bytes(data: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(data).replace("+", "-").replace("/", "_").rstrip("=")


func _b64u_encode_string(text: String) -> String:
	return _b64u_encode_bytes(text.to_utf8_buffer())


func _sha256_b64u(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return _b64u_encode_bytes(ctx.finish())


func _dict_to_urlencoded(params: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in params:
		parts.append("%s=%s" % [str(k).uri_encode(), str(params[k]).uri_encode()])
	return "&".join(parts)
