<img width="128" height="128" alt="Godot icon overlaying rpg.actor icon" src="https://raw.githubusercontent.com/TechTastic/godot-rpg-actor/refs/heads/main/icon.png" />


# godot-rpg-actor
This is a Godot 4 plugin for interacting with [rpg.actor](https://rpg.actor) through the [AT protocol](https://atproto.com/).

It allows players to login to games via their [Bluesky account](https://docs.bsky.app/) *(or any other [Personal Data Server](https://atproto.com/guides/self-hosting))* and utilize a persistent character through records kept in their own data. Through it, games can look up characters, display their sprites, read and write stats for multiple systems, manage and validate user inventory items, and authenticate players through secure OAuth logins.

### Setup

1. Copy the `addons/rpg_actor` folder into your Godot project
2. Enable the plugin in Project > Project Settings > Plugins
3. The plugin registers four autoloads: `XRPC`, `RpgActor`, `ATProto`, and `ATProtoOAuth`

All project settings (API URLs, OAuth scope, callback port) are set automatically when the plugin loads.

### Using rpg.actor

The main [rpg.actor API](https://rpg.actor/dev-guide) offers a handful of useful calls that can help you quickly access information about a character and populate sprites or stats without the need for user verification. Since all data is public, this can be used to quickly populate NPCs or handle character usage in any experience that does not need to write to the player's records (which requires authority to do so).

All calls are currently rate limited as detailed in the [Developer Guide](https://rpg.actor/dev-guide).

**Reading Data (no auth required):**

| Method | What it does |
|---|---|
| `get_actors(full)` | List all registered actors. Pass `true` for full cached data. |
| `search_actors(query)` | Search by handle or display name (min 2 characters). |
| `get_sprite(did)` | Get a normalized 144x192 PNG sprite sheet as raw bytes. |
| `get_open_graphic_card(did)` | Get a 1200x630 Open Graph card image as raw bytes. |
| `metrics()` | Registry summary: actor count, system count, master count. |
| `health()` | Service health and uptime. |
| `get_masters_for_player(did)` | Master/GM validations for a player. |
| `get_masters_by_authority(did)` | All players validated by a specific master/GM. |
| `get_equipment()` | Equipment index summary. |
| `get_equipment_by_player(did)` | All items and gives for a player. |
| `get_equipment_by_provider(did)` | All gives issued by a provider. |
| `get_creator_pricing()` | Current pricing tiers and PDS status. |
| `check_creator(did)` | Returns `true` if the DID is a registered creator. |
| `validate_handle(handle)` | Check that a handle has valid format (e.g. `name.bsky.social`). |
| `validate_did(did)` | Check that a DID string is well-formed (`did:plc:...` or `did:web:...`). |

**Writing Data (experimental):**

The API is capable of writing to accounts native to the [rpg.actor PDS](https://rpg.actor/creator), which are only available through a [Creator Account](https://rpg.actor/creator). These provide a means for games to generate new accounts for characters and manage them, though is in an early and experimental phase.

| Method | What it does |
|---|---|
| `pds_login(handle, password)` | Password login for rpg.actor native accounts. |
| `update_email(did, password, email)` | Update account email. |
| `change_password(did, current, new)` | Change account password. |
| `refresh_actor(did)` | Tell rpg.actor to re-read a player's PDS data. Useful after writing stats. |
| `contact(email, subject, message)` | Submit a contact form. |


### ATProtoOAuth

This portion handles a browser-based [OAuth](https://atproto.com/guides/auth) login using PKCE and DPoP. This is how players authenticate their [AT Protocol PDS](https://atproto.com/guides/self-hosting), which is mandatory for writing to the player's records in any form.

The login flow opens a browser window, runs a local callback server, and exchanges the authorization code for access and refresh tokens. Tokens refresh automatically but must be reinitialized with each session.

| Method | What it does |
|---|---|
| `login(handle)` | Start the full OAuth flow. Returns `{ success, did, handle }`. |
| `logout()` | Clear all tokens and session data. |
| `is_authenticated()` | Returns `true` if a valid session exists. |
| `get_access_token()` | The current access token (used internally by XRPC). |
| `get_session_did()` | The logged-in user's DID. |
| `get_session_handle()` | The logged-in user's handle. |
| `get_user_pds()` | The logged-in user's PDS endpoint URL. |
| `refresh_tokens()` | Manually refresh the access token. Normally automatic. |
| `create_dpop_proof(method, url)` | Generate a DPoP proof for a request. Used internally by XRPC. |

```gdscript
# Start OAuth login (opens the user's browser)
var result = await ATProtoOAuth.login("player.bsky.social")

if result.success:
    var did = ATProtoOAuth.get_session_did()
    var pds = ATProtoOAuth.get_user_pds()
    print("Authenticated: ", did, " on ", pds)
```

Any AT Protocol handle works here, whether it ends in `.bsky.social`, `.rpg.actor`, or a custom domain.

**Signals:**

- `login_completed(success, did)` - Emitted when login finishes.
- `login_failed(error)` - Emitted on login failure.
- `logout_completed()` - Emitted after logout.


### ATProto

AT Protocol identity resolution and record operations. Works with any [AT Protocol PDS](https://atproto.com/guides/self-hosting), not just [rpg.actor](https://rpg.actor) or [Bluesky](https://docs.bsky.app/).

| Method | What it does |
|---|---|
| `resolve_handle(handle)` | Resolve a handle to `{ did, pds }`. |
| `resolve_pds_from_did(did)` | Get the PDS endpoint for a DID. Supports `did:plc` and `did:web`. |
| `get_record(pds, repo, collection, rkey)` | Read a record from a PDS. |
| `put_record(pds, repo, collection, rkey, record)` | Write a record to a PDS. Requires active OAuth session. |
| `merge_and_put_stats(pds, repo, system_key, data)` | Fetch existing stats, merge in your data under one key, and write back. Other systems' data is preserved. Refreshes rpg.actor cache after. |
| `list_records(pds, repo, collection)` | List all records in a collection. |


### XRPC

Low-level HTTP and XRPC transport. You generally do not call this directly.

| Method | What it does |
|---|---|
| `xrpc_get(pds, lexicon, params)` | XRPC GET request. |
| `xrpc_post(pds, token, dpop, lexicon, body)` | XRPC POST with explicit tokens. |
| `xrpc_post_authed(pds, lexicon, body)` | XRPC POST using the active OAuth session. |
| `upload_blob(pds, data, mime_type)` | Upload a binary blob (image, etc.) to the user's PDS. |
| `XRPC.encode(value)` | URI-encode a string. |
| `XRPC.sanitize_bbcode(text)` | Escape BBCode tags in untrusted text for safe display in RichTextLabel. |

All requests enforce HTTPS (localhost is excepted for the OAuth callback). Write operations automatically attach OAuth/DPoP tokens and retry once on nonce rotation.

### Example: Read and Write Stats

See the [Developer Guide](https://rpg.actor/dev-guide) for full details on the stats, sprites, and equipment lexicons.

```gdscript
# Log in
var result = await ATProtoOAuth.login("yourname.rpg.actor")
if not result.success:
    return

var did = ATProtoOAuth.get_session_did()
var pds = ATProtoOAuth.get_user_pds()

# Read current stats
var record = await ATProto.get_record(pds, did, "actor.rpg.stats")
print(record)

# Write stats for your game system (non-destructive, preserves other systems)
var my_stats = {
    "systemName": "My Game",
    "items": [
        { "name": "Level", "value": 5 },
        { "name": "HP", "value": 100, "max": 100 }
    ]
}
await ATProto.merge_and_put_stats(pds, did, "my_game", my_stats)
```

### Project Settings

These are set automatically by the plugin but can be changed in Project Settings:

| Setting | Default |
|---|---|
| `rpg_actor/api` | `https://rpg.actor/api` |
| `bluesky/api/public` | `https://public.api.bsky.app` |
| `bluesky/api/auth` | `https://bsky.social` |
| `atproto/plc_directory` | `https://plc.directory` |
| `atproto/oauth/client_id_url` | `http://localhost` |
| `atproto/oauth/local_callback_port` | `7000` |
| `atproto/oauth/scope` | `atproto repo:actor.rpg.stats repo:actor.rpg.sprite ...` |

### Links

Built for the [rpg.actor Game Jam](https://rpg.actor/jam) by [@techtastic.bsky.social](https://bsky.app/profile/techtastic.bsky.social) (also known as [@godotguy.rpg.actor](https://bsky.app/profile/godotguy.rpg.actor)).

Follow [@rpg.actor](https://bsky.app/profile/rpg.actor) on Bluesky, check out the [Developer Guide](https://rpg.actor/dev-guide) for more, and make a character at [rpg.actor](https://rpg.actor) to try it yourself!
