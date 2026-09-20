class_name MessageLabel extends RichTextLabel

@export var group="temp"
@export var message=""


func _ready() -> void:
	fit_content=true
	bbcode_enabled=true
	if group=="default":
		text=message
	else:
		text="["+group+"]"+message
	await get_tree().create_timer(60).timeout
	queue_free()
