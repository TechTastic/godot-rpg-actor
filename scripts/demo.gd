extends Node

func _ready():
	var data = await RpgActor.resolve_handle("godotguy.rpg.actor")
	#print(await RpgActor.metrics())
	#print(await RpgActor.health())
	#print(await RpgActor.get_masters_for_player(data.did))
	#print(await RpgActor.get_masters_by_authority("did:plc:kwgllf365cwmxbnxitx4pjdj"))
	#print(await RpgActor.get_creator_pricing())
	#print(await RpgActor.check_creator(data.did))
	
	print(await RpgActor.get_record(data.pds, data.did, "equipment.rpg.item", "tops"))
	#print(await RpgActor._http_request("https://rpg.actor/api/pds-login", HTTPClient.METHOD_POST, [
		#"Content-Type: application/json"
	#], JSON.stringify({
		#"handle": "godotguy.rpg.actor",
		#"password": "Sep!10Az"
	#})))
	pass
