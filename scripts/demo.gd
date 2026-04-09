extends Node

func _ready():
	print(await RpgActor.metrics())
	print(await RpgActor.health())
