@tool
extends EditorPlugin


func _enable_plugin():
	add_autoload_singleton("RpgActor", "autoload/rpg_actor_api.gd")


func _disable_plugin():
	remove_autoload_singleton("RpgActor")


func _enter_tree():
	ProjectSettings.set_setting("rpg_actor/base_api", "https://rpg.actor/api")
	ProjectSettings.set_setting("rpg_actor/plc_directory", "https://plc.directory")
	ProjectSettings.set_setting("rpg_actor/bluesky_api", "https://public.api.bsky.app")


func _exit_tree():
	ProjectSettings.set_setting("rpg_actor/base_api", null)
	ProjectSettings.set_setting("rpg_actor/plc_directory", null)
	ProjectSettings.set_setting("rpg_actor/bluesky_api", null)
