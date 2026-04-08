extends Node

func _ready():
	#print(await RpgActor._http_request("https://public.api.bsky.app/xrpc/com.atproto.identity.resolveHandle?handle=godotguy.rpg.actor"))
	print(await RpgActor.resolve_handle("@godotguy.rpg.actor"))
	pass
