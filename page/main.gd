extends Control

var current_file_path: String = ""
@onready var text_edit = $VBC/SC/TextEdit   # 确定你场景里正确的路径



func _ready():
	var args = OS.get_cmdline_args()
	for a in args:
		#if a.ends_with(".txt") or a.ends_with(".csv") or a.ends_with(".json"):
		current_file_path = a
		$VBC/PC2/HBC/Label4.text=current_file_path
		open_and_show(a)
	text_edit.grab_focus()

func _process(delta: float) -> void:
	$VBC/PC2/HBC/Label3.text=str(text_edit.text.length())

func open_and_show(path: String):
	var f = FileAccess.open(path, FileAccess.READ)
	if f:
		text_edit.text = f.get_as_text()
		

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_save") or \
	   (event is InputEventKey and event.keycode == KEY_S and event.pressed and \
		(Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META))):
		save_file()
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("f11"):
		$VBC/PC.visible=not $VBC/PC.visible
		$VBC/PC2.visible=not $VBC/PC2.visible

func _on_save_button_pressed() -> void:
	save_file()

func save_file():
	if current_file_path == "":
		OS.alert("没有打开任何文件")
		return

	var f = FileAccess.open(current_file_path, FileAccess.WRITE)
	if f:
		f.store_string(text_edit.text)   # 统一使用 text_edit
	else:
		OS.alert("保存失败：" + str(FileAccess.get_open_error()))
