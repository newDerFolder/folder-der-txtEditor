extends Control

var current_file_path: String = ""
@onready var text_edit = $VBC/SC/TextEdit   # 确定你场景里正确的路径

# 添加文件对话框节点引用
@onready var file_dialog_save = $FileDialogSave
@onready var file_dialog_open = $FileDialogOpen

var font_size=20

func _ready():
	var args = OS.get_cmdline_args()
	for a in args:
		current_file_path = a
		$VBC/PC/HBC/Label4.text = current_file_path
		open_and_show(a)
	text_edit.grab_focus()
	
	# 连接文件对话框信号
	file_dialog_save.file_selected.connect(_on_save_as_file_selected)
	file_dialog_open.file_selected.connect(_on_open_file_selected)

func _process(delta: float) -> void:
	$VBC/PC2/HBC/Label3.text = str(text_edit.text.length())

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
	# 新增：快速另存为 Ctrl+Shift+S
	if event is InputEventKey and event.keycode == KEY_S and event.pressed and \
	   (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)) and \
	   Input.is_key_pressed(KEY_SHIFT):
		_on_save_as_button_pressed()
		get_viewport().set_input_as_handled()
		
	# 新增：快速打开 Ctrl+O
	if event is InputEventKey and event.keycode == KEY_O and event.pressed and \
	   (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)):
		_on_open_pressed()
		get_viewport().set_input_as_handled()
		
	if event.is_action_pressed("f11"):
		$VBC/PC.visible = not $VBC/PC.visible
		$VBC/PC2.visible = not $VBC/PC2.visible
	
	if Input.is_action_pressed("zoom_down"):
		if font_size>1:
			font_size-=1
		$VBC/SC/TextEdit.add_theme_font_size_override("font_size",font_size)
	if Input.is_action_pressed("zoom_up"):
		if font_size<100:
			font_size+=1
		$VBC/SC/TextEdit.add_theme_font_size_override("font_size",font_size)
	if Input.is_action_just_pressed("map"):
		$VBC/SC/TextEdit.minimap_draw=not $VBC/SC/TextEdit.minimap_draw
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

# 另存为按钮 - 弹出保存文件对话框
func _on_save_as_button_pressed() -> void:
	file_dialog_save.popup_centered(Vector2i(600, 400))

# 另存为对话框选择文件后的处理
func _on_save_as_file_selected(path: String) -> void:
	current_file_path = path
	$VBC/PC/HBC/Label4.text = current_file_path
	
	var f = FileAccess.open(current_file_path, FileAccess.WRITE)
	if f:
		f.store_string(text_edit.text)
	else:
		OS.alert("保存失败：" + str(FileAccess.get_open_error()))

# 打开按钮 - 弹出打开文件对话框
func _on_open_pressed() -> void:
	file_dialog_open.popup_centered(Vector2i(600, 400))

# 打开对话框选择文件后的处理
func _on_open_file_selected(path: String) -> void:
	current_file_path = path
	$VBC/PC/HBC/Label4.text = current_file_path
	open_and_show(path)
