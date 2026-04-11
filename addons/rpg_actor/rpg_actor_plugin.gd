@tool
extends EditorPlugin


func _enable_plugin():
	add_autoload_singleton("XRPC", "autoload/xrpc.gd")
	add_autoload_singleton("RpgActor", "autoload/rpg_actor_api.gd")
	add_autoload_singleton("ATProto", "autoload/atproto.gd")
	add_autoload_singleton("ATProtoOAuth", "autoload/atproto_oauth.gd")


func _disable_plugin():
	remove_autoload_singleton("ATProtoOAuth")
	remove_autoload_singleton("ATProto")
	remove_autoload_singleton("RpgActor")
	remove_autoload_singleton("XRPC")


func _enter_tree():
	ProjectSettings.set_setting("rpg_actor/api", "https://rpg.actor/api")
	
	ProjectSettings.set_setting("bluesky/api/public", "https://public.api.bsky.app")
	ProjectSettings.set_setting("bluesky/api/auth", "https://bsky.social")
	
	ProjectSettings.set_setting("atproto/plc_directory", "https://plc.directory")
	ProjectSettings.set_setting("atproto/oauth/client_id_url", "http://localhost")
	ProjectSettings.set_setting("atproto/oauth/local_callback_port", 7000)
	ProjectSettings.set_setting("atproto/oauth/scope", "atproto repo:actor.rpg.stats repo:actor.rpg.sprite repo:actor.rpg.master repo:equipment.rpg.item repo:equipment.rpg.give blob:image/*")


func _exit_tree():
	ProjectSettings.set_setting("rpg_actor/api", null)
	
	ProjectSettings.set_setting("bluesky/api/public", null)
	ProjectSettings.set_setting("bluesky/api/auth", null)
	
	ProjectSettings.set_setting("atproto/plc_directory", null)
	ProjectSettings.set_setting("atproto/oauth/client_id_url", null)
	ProjectSettings.set_setting("atproto/oauth/local_callback_port", null)
	ProjectSettings.set_setting("atproto/oauth/scope", null)
