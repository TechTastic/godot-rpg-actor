extends Node

func _ready():
	var data = await RpgActor.resolve_handle("godotguy.rpg.actor")
	print(await RpgActor.metrics())
	print(await RpgActor.health())
	#print(await RpgActor.get_masters_for_player(data.did))
	#print(await RpgActor.get_masters_by_authority("did:plc:kwgllf365cwmxbnxitx4pjdj"))
	print(await RpgActor.get_creator_pricing())
	print(await RpgActor.check_creator(data.did))
	
	print(await RpgActor.get_record(data.pds, data.did, "equipment.rpg.item"))
	pass
