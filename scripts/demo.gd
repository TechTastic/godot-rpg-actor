extends Control

@onready var handle_input: LineEdit = %HandleInput
@onready var login_button: Button = %LoginButton
@onready var status_label: Label = %StatusLabel
@onready var sprite_rect: TextureRect = %SpriteRect
@onready var stats_display: RichTextLabel = %StatsDisplay
@onready var write_stats_button: Button = %WriteStatsButton
@onready var write_item_button: Button = %WriteItemButton
@onready var refresh_button: Button = %RefreshButton
@onready var log_output: RichTextLabel = %LogOutput

var _did: String = ""
var _pds: String = ""
var _handle: String = ""
var _stats_record: Dictionary = {}

# AT Protocol TID:  base32-sortable, 13 chars
const _TID_CHARS := "234567abcdefghijklmnopqrstuvwxyz"
var _tid_clock_id: int = -1


func _generate_tid() -> String:
	if _tid_clock_id < 0:
		_tid_clock_id = randi() % 1024
	var us := int(Time.get_unix_time_from_system() * 1_000_000)
	var out := ""
	var ts := us
	for i in range(11):
		out = _TID_CHARS[ts & 0x1F] + out
		ts >>= 5
	var cid := _tid_clock_id
	for i in range(2):
		out += _TID_CHARS[cid & 0x1F]
		cid >>= 5
	return out


func _ready():
	login_button.pressed.connect(_on_login_pressed)
	write_stats_button.pressed.connect(_on_write_stats_pressed)
	write_item_button.pressed.connect(_on_write_item_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	_log("Ready. Enter a handle and click Login.")


# ============================================================
#  Logging helper
# ============================================================

func _log(msg: String):
	var timestamp := Time.get_time_string_from_system()
	log_output.append_text("[color=gray][%s][/color] %s\n" % [timestamp, msg])
	print(msg)


## OAuth login flow.
func _on_login_pressed():
	var handle := handle_input.text.strip_edges()
	if handle.is_empty():
		_log("[color=red]Enter a handle first.[/color]")
		return

	login_button.disabled = true
	status_label.text = "Logging in..."
	_log("Starting OAuth for %s..." % [handle])

	var result = await ATProtoOAuth.login(handle)
	login_button.disabled = false

	if not result.success:
		status_label.text = "Login failed"
		_log("[color=red]Login failed: %s[/color]" % [result.error])
		return

	_did = result.did
	_handle = result.handle
	_pds = ATProtoOAuth.get_user_pds()
	status_label.text = "Logged in as @%s" % [_handle]
	_log("[color=green]Authenticated as @%s (%s)[/color]" % [_handle, _did])
	_log("PDS: %s" % [_pds])

	# Enable action buttons
	write_stats_button.disabled = false
	write_item_button.disabled = false
	refresh_button.disabled = false

	# Load character data
	await _load_character()


## Loads the actor's sprite and stats from PDS.
func _load_character():
	_log("Loading character data...")

	# Load sprite via rpg.actor normalized API
	var sprite_data: PackedByteArray = await RpgActor.get_sprite(_did)
	if sprite_data.size() > 0:
		var image := Image.new()
		if image.load_png_from_buffer(sprite_data) == OK:
			# Show the full sprite sheet scaled up
			var tex := ImageTexture.create_from_image(image)
			sprite_rect.texture = tex
			_log("Sprite loaded (%dx%d)" % [image.get_width(), image.get_height()])
		else:
			_log("[color=yellow]Sprite data received but failed to decode PNG[/color]")
	else:
		_log("[color=yellow]No sprite found for this actor[/color]")

	# Load stats from PDS
	var record_resp = await ATProto.get_record(_pds, _did, "actor.rpg.stats")
	if record_resp is Dictionary and record_resp.has("value"):
		_stats_record = record_resp["value"].duplicate(true)
		_render_stats(_stats_record)
		_log("Stats loaded from PDS")
	else:
		_stats_record = {}
		stats_display.text = "No actor.rpg.stats record found."
		_log("[color=yellow]No stats record on PDS[/color]")


## Renders all system keys in the stats record as BBCode.
func _render_stats(val: Dictionary):
	var bbcode := ""

	# List every system key present
	var system_keys := []
	for key in val:
		if key not in ["$type", "createdAt", "updatedAt"]:
			system_keys.append(key)

	if system_keys.is_empty():
		stats_display.text = "Empty stats record."
		return

	for sys_key in system_keys:
		bbcode += "[b][color=gold]%s[/color][/b]\n" % [XRPC.sanitize_bbcode(sys_key.to_upper())]
		var sys_data = val[sys_key]
		if sys_data is Dictionary:
			bbcode += _render_dict(sys_data, 1)
		bbcode += "\n"

	if val.has("updatedAt"):
		bbcode += "[color=gray]Updated: %s[/color]\n" % [XRPC.sanitize_bbcode(str(val["updatedAt"]))]

	stats_display.clear()
	stats_display.append_text(bbcode)


## Recursively renders a dictionary into indented BBCode lines.
func _render_dict(d: Dictionary, indent: int) -> String:
	var pad := "  ".repeat(indent)
	var out := ""
	for key in d:
		var v = d[key]
		if v is Dictionary:
			out += "%s[color=silver]%s:[/color]\n" % [pad, XRPC.sanitize_bbcode(str(key))]
			out += _render_dict(v, indent + 1)
		elif v is Array:
			out += "%s[color=silver]%s:[/color]\n" % [pad, XRPC.sanitize_bbcode(str(key))]
			for item in v:
				if item is Dictionary:
					var name_str := XRPC.sanitize_bbcode(str(item.get("name", "")))
					var val_str := XRPC.sanitize_bbcode(str(item.get("value", "")))
					var max_str := XRPC.sanitize_bbcode(str(item.get("max", ""))) if item.has("max") else ""
					var cat_str := XRPC.sanitize_bbcode(str(item.get("category", ""))) if item.has("category") else ""
					var line := "%s  %s: [b]%s[/b]" % [pad, name_str, val_str]
					if not max_str.is_empty():
						line += " / %s" % [max_str]
					if not cat_str.is_empty():
						line += "  [color=gray][%s][/color]" % [cat_str]
					out += line + "\n"
				else:
					out += "%s  • %s\n" % [pad, XRPC.sanitize_bbcode(str(item))]
		else:
			out += "%s[color=silver]%s:[/color] [b]%s[/b]\n" % [pad, XRPC.sanitize_bbcode(str(key)), XRPC.sanitize_bbcode(str(v))]
	return out


## Writes Godot Warriors stats, merging into existing record.
func _on_write_stats_pressed():
	write_stats_button.disabled = true
	_log("Writing stats...")

	var custom_data := {
		"systemName": "Godot Warriors",
		"systemVersion": "1.0",
		"stats": [
			{ "name": "Class", "value": "Developer", "category": "identity" },
			{ "name": "Level", "value": 5, "category": "identity" },
			{ "name": "HP", "value": 48, "max": 48, "category": "vitals" },
			{ "name": "SP", "value": 30, "max": 30, "category": "vitals" },
			{ "name": "Logic", "value": 14, "category": "attributes" },
			{ "name": "Refactor", "value": 12, "category": "attributes" },
			{ "name": "Debug", "value": 10, "category": "attributes" },
			{ "name": "Deploy", "value": 8, "category": "attributes" },
			{ "name": "Compile Speed", "value": 7, "category": "combat" },
			{ "name": "Code Review", "value": 6, "category": "combat" },
		]
	}

	var result = await ATProto.merge_and_put_stats(_pds, _did, "custom", custom_data)
	if result is Dictionary and not result.is_empty():
		_log("[color=green]Stats written![/color] CID: %s" % [result.get("cid", "?")])
		# Reload to show merged record
		var record_resp = await ATProto.get_record(_pds, _did, "actor.rpg.stats")
		if record_resp is Dictionary and record_resp.has("value"):
			_stats_record = record_resp["value"].duplicate(true)
			_render_stats(_stats_record)
	else:
		_log("[color=red]putRecord failed — check Output panel[/color]")

	write_stats_button.disabled = false


## Writes a self-issued equipment item to the PDS.
func _on_write_item_pressed():
	write_item_button.disabled = true
	_log("Writing equipment.rpg.item record...")

	var rkey := _generate_tid()
	var item_record := {
		"$type": "equipment.rpg.item",
		"item": "godot_demo_sword",
		"title": "Godot Demo Sword",
		"kind": "inventory",
		"category": "weapon",
		"description": "A proof-of-concept sword created by the Godot rpg.actor plugin.",
		"provider": _did,
		"give": "",
		"acceptedAt": Time.get_datetime_string_from_system(true) + "Z",
		"stats": { "attack": 3, "element": "code" },
		"context": "Self-issued from Godot demo"
	}

	var result = await ATProto.put_record(_pds, _did, "equipment.rpg.item", rkey, item_record)
	if result is Dictionary and not result.is_empty():
		_log("[color=green]Item written![/color] URI: %s" % [result.get("uri", "?")])
		_log("CID: %s" % [result.get("cid", "?")])
	else:
		_log("[color=red]Item putRecord failed — check Output panel[/color]")

	write_item_button.disabled = false


## Re-reads sprite and stats from PDS.
func _on_refresh_pressed():
	refresh_button.disabled = true
	_log("Refreshing character from PDS...")
	await _load_character()
	refresh_button.disabled = false
	_log("Refresh complete.")
