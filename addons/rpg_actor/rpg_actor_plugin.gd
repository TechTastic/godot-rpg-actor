@tool
extends EditorPlugin


func _enable_plugin():
	add_autoload_singleton("XRPC", "autoload/xrpc.gd")
	add_autoload_singleton("RpgActor", "autoload/rpg_actor_api.gd")
	add_autoload_singleton("ATProto", "autoload/atproto.gd")


func _disable_plugin():
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


func _exit_tree():
	ProjectSettings.set_setting("rpg_actor/api", null)
	
	ProjectSettings.set_setting("bluesky/api/public", null)
	ProjectSettings.set_setting("bluesky/api/auth", null)
	
	ProjectSettings.set_setting("atproto/plc_directory", null)
	ProjectSettings.set_setting("atproto/oauth/client_id_url", null)
	ProjectSettings.set_setting("atproto/oauth/local_callback_port", null)
