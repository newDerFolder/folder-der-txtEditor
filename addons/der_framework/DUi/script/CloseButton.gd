@tool
class_name CloseButton extends Button


@export var page:Node

func _ready() -> void:
	expand_icon=true
	icon=load("res://addons/der_framework/asset/icon/redClose.png")
	custom_minimum_size.x=50
	custom_minimum_size.y=50

func _input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		close_page()

func _pressed() -> void:
	close_page()

func close_page():
	if page==null:
		return
	page.queue_free()
