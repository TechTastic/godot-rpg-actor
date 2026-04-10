extends Node

func _ready():
	var data = await ATProto.resolve_handle("godotguy.rpg.actor")
	print(data)
	print(await RpgActor.metrics())
	print(await RpgActor.health())
	print(await RpgActor.get_equipment())
	print(await RpgActor.get_equipment_by_player(data.did))
