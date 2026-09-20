class_name DerMessage extends CanvasLayer

@onready var right_scroll = $C/VBC/HBC/PC2/SC
@onready var right_list = $C/VBC/HBC/PC2/SC/VBC

@export var message_arr:Array[String]=[]
@export var max_messages := 1000  # 最大消息数量

@export_group("UI Message")
## 开启将会在UI界面上显示消息
@export var is_show_ui:=true
## 要忽略显示的消息组列表
@export var ignore_groups: Array[String] = []
@export var key:InputEventKey

var _was_pressed := false

func _process(delta: float) -> void:
	var is_pressed = Input.is_physical_key_pressed(key.keycode)
	
	if is_pressed and not _was_pressed:
		visible = not visible
	
	_was_pressed = is_pressed


func add_message(message:String,group="default"):
	if group=="default":
		message_arr.append(message)
	else:
		message_arr.append("["+group+"]"+message)
	
	# 只管理数组大小，超过上限则移除最旧的
	while message_arr.size() > max_messages:
		message_arr.remove_at(0)
	
	if group in ignore_groups:
		return
		
	if is_show_ui:
		var mes = MessageLabel.new()
		mes.group=group
		mes.message = message
		right_list.add_child(mes)

func add_top_message(message:String):
	var node=preload("res://addons/der_framework/DMessage/scene/BigOutLineLabel.tscn").instantiate()
	node.text=message
	$C/VBC/C.add_child(node)

func refresh():
	pass

func _ready() -> void:
	add_message("[color=green]模块启动","DerMessage")
	add_message("按键 ~ 以切换消息面板可见性","DerMessage")
	scroll_to_bottom()
	$C/VBC/HBC/PC2.visible=is_show_ui

func scroll_to_bottom():
	await get_tree().process_frame
	right_scroll.scroll_vertical = right_scroll.get_v_scroll_bar().max_value
