@tool
@icon("res://addons/rpg_actor/assets/RPGActorSprite3D.svg")
extends AnimatedSprite3D
class_name RPGActorSprite3D
## [RPGActorSprite3D] is an [AnimatedSprite3D] which automagically gets the [member RPGActorSprite3D.handle] rpg.actor and sets up its sprite sheet including animations.

## Handle for the rpg.actor to render
@export var handle: String = "godotguy.rpg.actor":
	set(h):
		handle = h
		_resolve_handle()
var _did: String = "":
	set(d):
		_did = d
		_load_actor()

func _ready():
	_resolve_handle()
	_load_actor()

func _resolve_handle():
	var data = await ATProto.resolve_handle(handle)
	_did = data.get("did", "")

func _load_actor() -> void:
	if _did.is_empty():
		return
	
	var data: PackedByteArray = await RpgActor.get_sprite(_did)
	var image = Image.new()
	var err = image.load_png_from_buffer(data)
	if err != OK:
		push_error("Failed to load image")
	
	var texture = ImageTexture.create_from_image(image)
	pause()
	sprite_frames = SpriteFrames.new()
	for rows in range(4):
		var animation_name: String
		match rows:
			0:
				animation_name = "walk_down"
			1:
				animation_name = "walk_left"
			2:
				animation_name = "walk_right"
			3:
				animation_name = "walk_up"
		sprite_frames.add_animation(animation_name)
		for columns in range(3):
			var frame_texture = AtlasTexture.new()
			frame_texture.atlas = texture
			frame_texture.region = Rect2(columns * 48, rows * 48, 48, 48)
			sprite_frames.add_frame(animation_name, frame_texture, 1, columns)
	animation = "walk_down"
	set_frame_and_progress(1, 1)
