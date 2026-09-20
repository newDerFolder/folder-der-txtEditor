extends Control

# 这些扩展名是**可编辑**的。注意它不再用来过滤文件列表 ——
# 不支持编辑的文件（Word / PPT / 图片……）同样会列在树里，只是图标不同、点击不载入。
const TEXT_EXTENSIONS := [
	"txt", "md", "json", "csv", "log", "ini", "cfg", "yaml", "yml", "xml",
	"gd", "tscn", "tres", "html", "css", "js", "py", "sh", "bat",
]
# 这些目录不展开
const SKIP_DIRS := ["node_modules", "__pycache__", "venv", "env"]
# 递归深度上限，防符号链接成环时无限递归
const MAX_TREE_DEPTH := 12

# 侧边栏条目标图标的边长（像素）
const ICON_SIZE := 15

const ICON_DIR_PATH := "res://asset/icon/folder.png"
const ICON_FILE_PATH := "res://asset/icon/folderTxt.png"
# 不支持编辑的文件的图标
const ICON_UNSUPPORTED_PATH := "res://asset/icon/UnsupportedEditIcon.png"

# 两张源图尺寸差很多（folder.png 是 32x32，folderTxt.png 是 400x400），直接塞给 Tree
# 会按原始尺寸绘制，400x400 那张能把整行撑爆。Tree 的 icon_size 主题常量在 4.7 里
# 对绘制尺寸无效（实测），所以这里在加载时就把贴图统一重采样成 ICON_SIZE x ICON_SIZE ——
# 比绘制期缩放更清晰，大图小图都精确落在这个尺寸上。
var _icon_dir: Texture2D
var _icon_file: Texture2D
var _icon_unsupported: Texture2D

var current_file_path: String = ""
var root_dir: String = ""

@onready var text_edit = $VBC/SpC/SC/TextEdit
@onready var file_tree: Tree = $VBC/SpC/HBC/PC/VBC2/FileTree

# 添加文件对话框节点引用
@onready var file_dialog_save = $FileDialogSave
@onready var file_dialog_open = $FileDialogOpen
@onready var file_dialog_open_dir = $FileDialogOpenDir

# 右键菜单 + 两个确认框
@onready var file_item_menu: PopupMenu = $FileItemMenu
@onready var rename_dialog: ConfirmationDialog = $RenameDialog
@onready var delete_dialog: ConfirmationDialog = $DeleteDialog

# 文件树头部那排「新建」按钮（和 Explorer 标题同一行）
@onready var new_file_button: Button = $VBC/SpC/HBC/PC/VBC2/PC/HBC/NewFileButton
@onready var new_folder_button: Button = $VBC/SpC/HBC/PC/VBC2/PC/HBC/NewFolderButton

# 右键菜单项 id。用枚举而不是裸数字，加/删菜单项时不用回来数顺序。
enum MenuId {
	NEW_FILE,               # 新建文件，只对目录出现
	NEW_FOLDER,             # 新建文件夹，只对目录出现
	OPEN_WITH_DEFAULT,      # 用系统默认程序打开，只对不支持编辑的文件出现
	OPEN_IN_FILE_MANAGER,
	RENAME,
	DELETE,
	COPY_PATH,
	REFRESH,
}

# 当前右键目标（弹菜单时记下，点菜单项时用）
var _menu_path: String = ""
var _menu_is_dir: bool = false
# 这一轮点击里已经切换过展开状态的目录路径，用来给双击去重：
# Tree 把双击拆成"第一下当普通单击 + 第二下发 item_activated"，
# 而第一下切没切取决于那一刻条目是否已被选中，所以第二下得靠这个变量判断。
# 每次左键按下（双击的第二下除外）由 gui_input 清空。
var _toggled_path: String = ""
# 程序化选中（_select_tree_item_for_path）期间，屏蔽掉"目录被选中 = 切换展开状态"这个副作用。
# 不加这个开关的话：重命名一个目录会把它翻成折叠的（里面的文件当场从树里消失），
# 新建文件夹则会得到一个"刚建出来就是折叠"的目录 —— 都是 select() 发 item_selected 惹的。
# 只在这一个函数里、只围着一句 select(0) 有效，见那里的注释。
var _suppress_dir_toggle: bool = false
# 重命名对话框里的输入框，代码创建 —— AcceptDialog 会把子节点收进自己的内容区，
# 手写 tscn 布局容易对不上
var _rename_edit: LineEdit

# 新建文件的对话框（同样代码创建，理由见 _open_as_text_dialog 那边的注释）
var _new_file_dialog: ConfirmationDialog
var _new_file_edit: LineEdit
# 新建文件的目标目录。**在这里存一份**，不要等确认时再去读 _menu_path ——
# 弹框期间用户还能右键别的条目，_menu_path 会跟着变，那样新文件可能落到别处去。
var _new_file_dir: String = ""

# 新建文件夹的那一套，和上面完全对称
var _new_folder_dialog: ConfirmationDialog
var _new_folder_edit: LineEdit
var _new_folder_dir: String = ""

# 双击不支持编辑的文件时的"强制按文本打开"提醒框。
# 同样在代码里建：main.tscn 里这排 AcceptDialog 的节点都带 unique_id，
# 手写 tscn 容易把那个 id 写错或写重，交给 Godot 自己保存场景时落盘更安全。
var _open_as_text_dialog: ConfirmationDialog
# 提醒框确认后要打开的那个文件
var _pending_open_path: String = ""

var font_size=20

func _ready():
	_setup_explorer_buttons()
	_setup_file_tree()

	# 取命令行传入的第一个真实文件。
	# 「打开方式」传的是裸参数（get_cmdline_args），带 `--` 的调用 / 编辑器「启动参数」
	# 则落在 user_args 里，所以两边都读。
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("-"):
			continue          # 跳过 --path 之类的引擎参数
		if a.begins_with("res://") or a.begins_with("user://"):
			continue          # 侧边栏浏览的是真实文件系统，虚拟路径不认
		if not FileAccess.file_exists(a):
			continue          # 编辑器里运行时混进来的非文件参数
		# 和侧边栏同一条规矩：不支持编辑的类型不往编辑器里载。
		# 「打开方式」里把本编辑器设成默认程序时也会走到这里，
		# 真载进来就是二进制乱码，再一保存就把原文件覆盖了。
		if not _is_editable_file(a):
			continue
		open_and_show(a)
		break             # 只认第一个，避免被后面的参数覆盖

	text_edit.grab_focus()

	# 连接文件对话框信号
	file_dialog_save.file_selected.connect(_on_save_as_file_selected)
	file_dialog_open.file_selected.connect(_on_open_file_selected)
	file_dialog_open_dir.dir_selected.connect(_on_open_dir_selected)

	_setup_item_menu()

func _process(delta: float) -> void:
	$VBC/PC2/HBC/Label3.text = str(text_edit.text.length())

func open_and_show(path: String) -> void:
	# 统一成 set_root_dir 用的规范形式（正斜杠、无 ./ 和 ../），
	# 否则和树里 metadata 存的路径对不上，选中定位会失效
	path = path.replace("\\", "/").simplify_path()

	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		OS.alert("打开失败：" + path)
		return

	text_edit.text = f.get_as_text()
	current_file_path = path
	$VBC/PC/HBC/Label4.text = current_file_path

	# 用打开的文件反推根目录，但只在文件位于当前树之外时才重定。
	# 这样 OpenDir 选定一个目录后，点树里的文件不会把树缩到文件所在的那层子目录去；
	# 而空树启动、或用 Ctrl+O 打开别处的文件时，树依然会跟过去。
	if path.is_absolute_path() and not _is_under(path, root_dir):
		set_root_dir(path.get_base_dir())
	_select_tree_item_for_path(path)

# path 是否位于 dir 之内（或就是 dir）。两边都按 set_root_dir 的规范形式比较：
# 正斜杠、无结尾斜杠。
func _is_under(path: String, dir: String) -> bool:
	if dir == "":
		return false
	return path == dir or path.begins_with(dir + "/")

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
		text_edit.add_theme_font_size_override("font_size",font_size)
	if Input.is_action_pressed("zoom_up"):
		if font_size<100:
			font_size+=1
		text_edit.add_theme_font_size_override("font_size",font_size)
	if Input.is_action_just_pressed("map"):
		text_edit.minimap_draw=not text_edit.minimap_draw
func _on_save_button_pressed() -> void:
	save_file()

func save_file():
	if current_file_path == "":
		OS.alert("没有打开任何文件")
		return

	var f = FileAccess.open(current_file_path, FileAccess.WRITE)
	if f:
		f.store_string(text_edit.text)   # 统一使用 text_edit
		DMessageManager.add_top_message("保存成功")
	else:
		OS.alert("保存失败：" + str(FileAccess.get_open_error()))

# 另存为按钮 - 弹出保存文件对话框
func _on_save_as_button_pressed() -> void:
	file_dialog_save.popup_centered(Vector2i(600, 400))

# 另存为对话框选择文件后的处理
func _on_save_as_file_selected(path: String) -> void:
	path = path.replace("\\", "/")
	current_file_path = path
	$VBC/PC/HBC/Label4.text = current_file_path

	var f = FileAccess.open(current_file_path, FileAccess.WRITE)
	if f == null:
		OS.alert("保存失败：" + str(FileAccess.get_open_error()))
		return
	f.store_string(text_edit.text)

	# 存进当前根目录就刷新树，让新文件立刻出现
	if path.get_base_dir() == root_dir:
		refresh_file_tree()
	_select_tree_item_for_path(path)

# 打开按钮 - 弹出打开文件对话框
func _on_open_pressed() -> void:
	file_dialog_open.popup_centered(Vector2i(600, 400))

# 打开对话框选择文件后的处理
func _on_open_file_selected(path: String) -> void:
	open_and_show(path)

# OpenDir 按钮 - 弹出选择目录对话框
func _on_open_dir_pressed() -> void:
	file_dialog_open_dir.popup_centered(Vector2i(600, 400))

# 选定目录后的处理：只换树根，不动当前打开的文件
func _on_open_dir_selected(path: String) -> void:
	set_root_dir(path)

# ---------------- 条目右键菜单 ----------------

func _setup_item_menu() -> void:
	file_item_menu.id_pressed.connect(_on_menu_id_pressed)
	# 菜单开着时的输入只能从菜单这边拿（原因见 _on_menu_window_input）
	file_item_menu.window_input.connect(_on_menu_window_input)

	# 重命名输入框
	_rename_edit = LineEdit.new()
	_rename_edit.custom_minimum_size = Vector2(360, 0)
	rename_dialog.add_child(_rename_edit)
	rename_dialog.register_text_enter(_rename_edit)   # 输入框里回车 = 点确定
	rename_dialog.confirmed.connect(_on_rename_confirmed)

	delete_dialog.confirmed.connect(_on_delete_confirmed)

	# 新建文件的输入框和弹框。和重命名那条一样：AcceptDialog 会把子节点收进
	# 自己的内容区，所以输入框代码里 new 出来塞进去。
	_new_file_dialog = ConfirmationDialog.new()
	_new_file_dialog.title = "新建文件"
	_new_file_dialog.ok_button_text = "新建"
	_new_file_dialog.cancel_button_text = "取消"
	_new_file_dialog.min_size = Vector2i(420, 130)
	_new_file_edit = LineEdit.new()
	_new_file_edit.custom_minimum_size = Vector2(360, 0)
	_new_file_dialog.add_child(_new_file_edit)
	_new_file_dialog.register_text_enter(_new_file_edit)   # 输入框里回车 = 点确定
	_new_file_dialog.confirmed.connect(_on_new_file_confirmed)
	add_child(_new_file_dialog)

	# 新建文件夹：除了标题、按钮文案和默认名，其余和上面那份一模一样
	_new_folder_dialog = ConfirmationDialog.new()
	_new_folder_dialog.title = "新建文件夹"
	_new_folder_dialog.ok_button_text = "新建"
	_new_folder_dialog.cancel_button_text = "取消"
	_new_folder_dialog.min_size = Vector2i(420, 130)
	_new_folder_edit = LineEdit.new()
	_new_folder_edit.custom_minimum_size = Vector2(360, 0)
	_new_folder_dialog.add_child(_new_folder_edit)
	_new_folder_dialog.register_text_enter(_new_folder_edit)
	_new_folder_dialog.confirmed.connect(_on_new_folder_confirmed)
	add_child(_new_folder_dialog)

func _on_file_tree_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return

	# 左键按下 = 一轮新点击的开始，把"这一轮已经切过哪个目录"的记账清掉。
	# 只能在这里清：双击的两下之间不会再有任何信号，只有在按下那一刻清，
	# 第二下才判断得出第一下到底切没切（见 _on_file_tree_item_activated）。
	# 双击的第二下（double_click = true）**不能清**，否则正好把要判断的东西抹掉了。
	if event.button_index == MOUSE_BUTTON_LEFT:
		if not event.double_click:
			_toggled_path = ""
		return

	if event.button_index != MOUSE_BUTTON_RIGHT:
		return

	# 用 event.position（Tree 局部坐标）换算成视口坐标去查条目，而不是读 get_selected()：
	# 右键点在空处时选中项还停在原来那个条目上，读选中项会弹出上一个文件的菜单。
	# 用 event.position 而不是读实时鼠标位置：真实点击时两者本就一致，
	# 但这样不依赖"弹菜单那一刻鼠标还在原地"。
	_open_item_menu_at(file_tree.get_global_position() + event.position)

# 在**视口坐标**的 pos 处把条目菜单弹出来。空处不弹（什么也不做）。
# 两个入口都走这里：Tree 的 gui_input（第一次右键），以及菜单自己的 window_input
# （菜单开着时的右键 —— 那种情况下主视口收不到输入，见 _on_menu_window_input）。
func _open_item_menu_at(vp_pos: Vector2) -> void:
	# 点在树外面（编辑区、工具栏）就别弹了
	if not file_tree.get_global_rect().has_point(vp_pos):
		return
	var item := file_tree.get_item_at_position(vp_pos - file_tree.get_global_position())
	var path := _item_path(item)
	if path == "":
		return      # 点到空白处，或 "未指定目录" 占位条目

	_menu_path = path
	_menu_is_dir = _item_is_dir(item)
	_build_item_menu()

	# 必须显式给坐标：Godot 4 的无参 popup() 弹在 (0,0)，不读鼠标位置
	# （那是 Godot 3 的行为，别按老文档想当然）。
	# 实测 popup(rect) 的 rect 吃的是**视口局部坐标**，和上面算 vp_pos 用的是同一套。
	file_item_menu.popup(Rect2i(Vector2i(vp_pos), Vector2i.ZERO))

# 菜单开着的时候，主视口**收不到任何输入** —— 嵌入式子窗口会把事件全吞掉，
# 只转发到它自己的视口（实测：主视口那边连一次 gui_input 都不发，见 README §7.16）。
# 所以"在菜单外面又点了一下"这件事，只有菜单自己能告诉我们，window_input 就是那个口子。
# 不接它的话症状就是用户说的那个：右键一个条目弹出菜单后，再右键别的条目**没反应**
# （菜单还开着，也不换目标），得先左键点一下把菜单关掉再来 —— 就是"不丝滑"。
func _on_menu_window_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return

	# 点在菜单**里面**是"选条目"，交回给菜单自己处理，别插手
	if Rect2(Vector2.ZERO, file_item_menu.size).has_point(mb.position):
		return

	# event.position 是菜单**局部**坐标，加上菜单位置才是视口坐标
	# （实测菜单局部 (0,-61.5) + 菜单在 (172,151) = 当初点下去的那个 (172,89.5)）
	var vp_pos := Vector2(file_item_menu.position) + mb.position
	file_item_menu.hide()

	if mb.button_index != MOUSE_BUTTON_RIGHT:
		# 左键点外面：关掉菜单就完事 —— **但不必手动补发点击**。实测这一下会自己
		# 继续走到主视口上：菜单一藏，同一个按下事件就落到它盖着的那一行，
		# 该载入的载入、该展开的展开（跟没开菜单时点它一模一样，也和 VS Code 一致）。
		# 这里什么都别做，多做一步反而变成"点一下触发两次"。
		return

	# 左键在上面就 return 了，所以这里只可能是右键：关掉旧菜单，**就着这一下**
	# 把新菜单弹出来 —— 一次右键既关旧的又开新的，这才是"丝滑"。
	# call_deferred 不要顺手改成同步调用：这次 window_input 是菜单**正在处理这一轮输入**
	# 的过程中发出来的，同步 popup 会被这一轮的收尾搅掉，延后到帧末才稳（这一版实测 44 条断言全过）。
	# 另外更正一个曾经写在这里的说法：引擎**不会**自己把这个菜单关掉，
	# 早先日志里那句 popup_hide 是本函数上面自己的 hide() 发的，见 README §7.16。
	_open_item_menu_at.call_deferred(vp_pos)

func _build_item_menu() -> void:
	file_item_menu.clear()
	# 菜单项 id 走枚举，所以在这里按条件增删不会影响别的项。
	# 「新建文件」只对目录出现 —— 文件条目的上下文里"新建"没有说得通的目标目录。
	# 放最上面是跟着资源管理器的习惯。
	if _menu_is_dir:
		file_item_menu.add_item("新建文件", MenuId.NEW_FILE)
		file_item_menu.add_item("新建文件夹", MenuId.NEW_FOLDER)
		file_item_menu.add_separator()
	# 「用默认程序打开」只对"看得见但本编辑器打不开"的文件才有意义：
	# 目录用「在文件管理器中打开」就够了，可编辑的文件本来就单击即开。
	elif not _is_editable_file(_menu_path):
		file_item_menu.add_item("用默认程序打开", MenuId.OPEN_WITH_DEFAULT)
		file_item_menu.add_separator()
	file_item_menu.add_item("在文件管理器中打开", MenuId.OPEN_IN_FILE_MANAGER)
	file_item_menu.add_separator()
	file_item_menu.add_item("重命名", MenuId.RENAME)
	file_item_menu.add_item("删除", MenuId.DELETE)
	file_item_menu.add_separator()
	file_item_menu.add_item("复制完整路径", MenuId.COPY_PATH)
	file_item_menu.add_item("刷新文件树", MenuId.REFRESH)

func _on_menu_id_pressed(id: int) -> void:
	match id:
		MenuId.NEW_FILE:
			_prompt_new_file()
		MenuId.NEW_FOLDER:
			_prompt_new_folder()
		MenuId.OPEN_WITH_DEFAULT:
			var err := OS.shell_open(_menu_path)
			if err != OK:
				OS.alert("打开失败：" + error_string(err))
		MenuId.OPEN_IN_FILE_MANAGER:
			# 目录直接进去，文件在父目录里选中它
			var err := OS.shell_show_in_file_manager(_menu_path, _menu_is_dir)
			if err != OK:
				OS.alert("打开文件管理器失败：" + error_string(err))
		MenuId.RENAME:
			_prompt_rename()
		MenuId.DELETE:
			_prompt_delete()
		MenuId.COPY_PATH:
			DisplayServer.clipboard_set(_menu_path)
		MenuId.REFRESH:
			refresh_file_tree()

# ---------------- 新建文件 ----------------

# 右键菜单进来的：目标是右键的那个目录
func _prompt_new_file() -> void:
	_prompt_new_file_in(_menu_path)

func _prompt_new_file_in(dir: String) -> void:
	# 目标目录在这里就定下来。弹框期间用户还能右键别的条目、把 _menu_path 改掉，
	# 等确认时再读就不是当初右键的那个目录了。
	_new_file_dir = dir
	var default_name := _default_new_file_name(_new_file_dir)
	_new_file_edit.text = default_name
	# 弹框里显示目录名而不是完整路径 —— 就是用户刚右键的那个，够认了
	_new_file_dialog.dialog_text = "在「%s」里新建文件：" % _new_file_dir.get_file()
	_new_file_dialog.popup_centered()
	_new_file_edit.grab_focus()
	_select_base_name_in(_new_file_edit)

# 默认名。撞名就依次试「新建文件 (2).txt」这种，别让用户一打开弹框就先吃一个
# "已存在同名文件"。上限纯粹是防死循环的保险，正常目录撞不到 1000 个。
func _default_new_file_name(dir: String) -> String:
	const BASE := "新建文件"
	const EXT := ".txt"
	var candidate := BASE + EXT
	var i := 2
	while FileAccess.file_exists(dir.path_join(candidate)) or \
		  DirAccess.dir_exists_absolute(dir.path_join(candidate)):
		candidate = "%s (%d)%s" % [BASE, i, EXT]
		i += 1
		if i > 999:
			break
	return candidate

func _on_new_file_confirmed() -> void:
	var dir := _new_file_dir
	var name := _new_file_edit.text.strip_edges()

	var reason := _validate_name_in_dir(dir, name)
	if reason != "":
		OS.alert(reason)
		return

	var new_path := dir.path_join(name)
	var f := FileAccess.open(new_path, FileAccess.WRITE)
	if f == null:
		OS.alert("新建失败：" + str(FileAccess.get_open_error()))
		return
	f.close()     # 建完立刻关掉，别让句柄一直挂着

	refresh_file_tree()
	# 注意：这个助手会把新文件**载入编辑器**（它内部的 TreeItem.select() 会发
	# item_selected，而那个信号的处理就是载入文件）。这是有意的，不是副作用失控 ——
	# 本应用靠这条链子维持一个不变量：**树里的选中项和编辑器里的内容永远一致**，
	# 另存为 / Ctrl+O 也都走它。不载入的话，用户新建完直接打字，敲进去的其实是
	# 上一个还开着的文件，然后 Ctrl+S 就把它覆盖了。
	_select_tree_item_for_path(new_path)

# ---------------- 新建文件夹 ----------------

# 右键菜单进来的：目标是右键的那个目录
func _prompt_new_folder() -> void:
	_prompt_new_folder_in(_menu_path)

func _prompt_new_folder_in(dir: String) -> void:
	_new_folder_dir = dir
	_new_folder_edit.text = _default_new_folder_name(_new_folder_dir)
	_new_folder_dialog.dialog_text = "在「%s」里新建文件夹：" % _new_folder_dir.get_file()
	_new_folder_dialog.popup_centered()
	_new_folder_edit.grab_focus()
	# 文件夹名没有扩展名，_select_base_name_in 里的 get_basename() 会原样返回整个名字，
	# 于是全选 —— 正是想要的，直接打字就整体替换。
	_select_base_name_in(_new_folder_edit)

# 和 _default_new_file_name 同一套逻辑，只是没有扩展名
func _default_new_folder_name(dir: String) -> String:
	const BASE := "新建文件夹"
	var candidate := BASE
	var i := 2
	while FileAccess.file_exists(dir.path_join(candidate)) or \
		  DirAccess.dir_exists_absolute(dir.path_join(candidate)):
		candidate = "%s (%d)" % [BASE, i]
		i += 1
		if i > 999:
			break
	return candidate

func _on_new_folder_confirmed() -> void:
	var dir := _new_folder_dir
	var name := _new_folder_edit.text.strip_edges()

	var reason := _validate_name_in_dir(dir, name)
	if reason != "":
		OS.alert(reason)
		return

	var new_path := dir.path_join(name)
	# make_dir_absolute 只建一层，父目录必须已经在 —— 这里正合适：父目录就是用户
	# 刚点的那个目录，一定存在。不走 DirAccess.make_dir_recursive_absolute，
	# 那会把名字里带 / 的路径整个建出来（校验已经挡了 /，但少一层依赖更稳）。
	var err := DirAccess.make_dir_absolute(new_path)
	if err != OK:
		OS.alert("新建文件夹失败：" + error_string(err))
		return

	refresh_file_tree()
	# 选中新建的文件夹（顺便逐级展开它的祖先链），让用户看得见建出来的东西。
	# 这里不用管展开状态：_select_tree_item_for_path 已经屏蔽了"选中目录 = 切换展开"，
	# 新目录保持默认的展开态。
	_select_tree_item_for_path(new_path)

# ---------------- 文件树头部的新建按钮 ----------------

func _setup_explorer_buttons() -> void:
	new_file_button.pressed.connect(_on_new_file_button_pressed)
	new_folder_button.pressed.connect(_on_new_folder_button_pressed)
	_update_new_buttons()

# 头部按钮的目标目录 = **当前打开的这个文件夹**（root_dir），不看树里的选中项。
# 这套按钮的语义是"往我现在打开的文件夹里放东西"，跟位置无关 —— 选中谁都不该改变它，
# 否则"我明明开着 A 目录，东西却跑进选中的子目录里了"。
# 想放进某个子目录就走那个子目录的右键菜单（右键 → 新建文件 / 新建文件夹）：
# 那里有明确的"对着谁操作"的上下文，比这里靠选中项猜要可靠。
func _new_target_dir() -> String:
	return root_dir

# 一个目录都没打开的时候把两个按钮禁掉。
# 这不只是"灰着好看"：那种状态下 root_dir 是空串，path_join 出来是个**相对路径**，
# 新建会落到进程的工作目录里去 —— 用户根本不知道文件建到哪儿了。
func _update_new_buttons() -> void:
	var can := root_dir != "" and DirAccess.dir_exists_absolute(root_dir)
	new_file_button.disabled = not can
	new_folder_button.disabled = not can

func _on_new_file_button_pressed() -> void:
	_prompt_new_file_in(_new_target_dir())

func _on_new_folder_button_pressed() -> void:
	_prompt_new_folder_in(_new_target_dir())

# ---------------- 重命名 ----------------

func _prompt_rename() -> void:
	rename_dialog.dialog_text = "输入新的" + ("文件夹名" if _menu_is_dir else "文件名")
	_rename_edit.text = _menu_path.get_file()
	rename_dialog.popup_centered()
	_rename_edit.grab_focus()
	_select_base_name()

# 重命名弹框里预选名字。目录没有扩展名，全选。
func _select_base_name() -> void:
	if _menu_is_dir:
		_rename_edit.select_all()
		return
	_select_base_name_in(_rename_edit)

# 只选中主名、不含扩展名，直接输入就能整体覆盖，又不用手动删掉 ".txt"。
# 新建文件也走这个，所以默认名是 "新建文件.txt" 时，用户一打字就把"新建文件"
# 整个替换掉、".txt" 后缀留着 —— 这就是那句"默认 txt"落到实处的地方。
func _select_base_name_in(edit: LineEdit) -> void:
	var base := edit.text.get_basename()
	edit.select(0, base.length())
	edit.caret_column = base.length()

# 校验新名称能不能用。返回 "" 表示可用，否则返回给用户看的原因。
# 单独拆出来是为了不起弹窗也能测 —— OS.alert 在 Windows 上是阻塞的，
# 埋在里面的分支没法从脚本里驱动。
func _validate_new_name(old_path: String, new_name: String) -> String:
	return _validate_name_in_dir(old_path.get_base_dir(), new_name)

# 校验 new_name 能不能落在 dir 这个目录里。重命名 / 新建文件 / 新建文件夹
# 共用同一套规则（目标目录 / 空名 / 非法字符 / 撞名），拆出来是为了三边不会各自长歪。
func _validate_name_in_dir(dir: String, new_name: String) -> String:
	if dir == "":
		# 兜底：没有目标目录时 path_join 出来是个相对路径，写入会落到进程的工作目录，
		# 用户根本找不到自己刚建的东西。正常流程走不到这儿（按钮会禁用、菜单也不会弹），
		# 但这条错误值得在这里挡一次，毕竟代价是"文件消失在一个没人知道的地方"。
		return "没有可用的目标目录"
	if new_name == "":
		return "名称不能为空"
	if new_name.contains("/") or new_name.contains("\\") or \
	   new_name.contains(":") or new_name.contains("*") or new_name.contains("?") or \
	   new_name.contains("\"") or new_name.contains("<") or new_name.contains(">") or \
	   new_name.contains("|"):
		return "名称不能包含下列字符：/ \\ : * ? \" < > |"
	var new_path := dir.path_join(new_name)
	if FileAccess.file_exists(new_path) or DirAccess.dir_exists_absolute(new_path):
		return "已存在同名文件或文件夹：" + new_name
	return ""

func _on_rename_confirmed() -> void:
	var new_name := _rename_edit.text.strip_edges()
	var old_path := _menu_path

	# 没改就什么都不做。这一条必须排在存在性校验前面 ——
	# 不然后面会把"改成自己原来的名字"判成"已存在同名"。
	if new_name == old_path.get_file():
		return

	var reason := _validate_new_name(old_path, new_name)
	if reason != "":
		OS.alert(reason)
		return

	var new_path := old_path.get_base_dir().path_join(new_name)
	var err := DirAccess.rename_absolute(old_path, new_path)
	if err != OK:
		OS.alert("重命名失败：" + error_string(err))
		return

	# 改的正是当前打开的文件时，保存路径要跟着走，
	# 否则 Ctrl+S 会把内容写回旧名字，等于凭空多出一个文件
	if current_file_path == old_path:
		current_file_path = new_path
		$VBC/PC/HBC/Label4.text = current_file_path

	refresh_file_tree()
	_select_tree_item_for_path(new_path)

# ---------------- 删除 ----------------

func _prompt_delete() -> void:
	var what := "文件夹" if _menu_is_dir else "文件"
	var text := "确定要把%s「%s」移入回收站吗？" % [what, _menu_path.get_file()]
	if _menu_is_dir:
		text += "\n（文件夹里的全部内容会一并移入）"
	delete_dialog.dialog_text = text
	delete_dialog.popup_centered()

func _on_delete_confirmed() -> void:
	var path := _menu_path
	# move_to_trash 只认全局绝对路径，不吃 res:// 这类虚拟路径
	var err := OS.move_to_trash(path)
	if err != OK:
		OS.alert("删除失败：" + error_string(err))
		return

	# 删掉的正是当前打开的文件（或它所在的目录）时，必须把路径解绑。
	# 否则按 Ctrl+S 会通过 FileAccess.open(..., WRITE) 把刚删掉的文件原地重建出来。
	# 编辑器里的文本保留不动 —— 用户可能正想另存为到别处。
	if current_file_path != "" and \
	   (current_file_path == path or _is_under(current_file_path, path)):
		current_file_path = ""
		$VBC/PC/HBC/Label4.text = "no file"

	refresh_file_tree()

# ---------------- 侧边栏文件树 ----------------

func _make_icon(path: String) -> Texture2D:
	var tex := load(path) as Texture2D
	if tex == null:
		push_warning("图标加载失败：" + path)   # 缺图标时条目会变成没图标的空行，别静默吞掉
		return null
	var img := tex.get_image()
	if img == null:
		return tex   # 取不到像素数据（压缩纹理等），退回原图
	img.resize(ICON_SIZE, ICON_SIZE, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

func _setup_file_tree() -> void:
	_icon_dir = _make_icon(ICON_DIR_PATH)
	_icon_file = _make_icon(ICON_FILE_PATH)
	_icon_unsupported = _make_icon(ICON_UNSUPPORTED_PATH)

	file_tree.hide_root = true
	# 注意：不要开 allow_reselect。它会让 Tree 在重选同一项时重复发 item_selected，
	# 而折叠一个已选中的条目会触发 Tree 内部重选 —— 于是折叠 -> 重选 -> 折叠 形成死循环，
	# 每帧振荡，同步处理时直接段错误崩溃。
	file_tree.allow_reselect = false
	file_tree.item_selected.connect(_on_file_tree_item_selected)
	# 双击 / 选中后回车
	file_tree.item_activated.connect(_on_file_tree_item_activated)

	_open_as_text_dialog = ConfirmationDialog.new()
	_open_as_text_dialog.title = "按文本打开"
	_open_as_text_dialog.ok_button_text = "仍要打开"
	_open_as_text_dialog.cancel_button_text = "取消"
	# 文案有三行，默认尺寸会挤成一团
	_open_as_text_dialog.min_size = Vector2i(560, 200)
	_open_as_text_dialog.confirmed.connect(_on_open_as_text_confirmed)
	# 取消时把待办清掉，免得那个变量留着一个已经作废的目标
	_open_as_text_dialog.canceled.connect(func(): _pending_open_path = "")
	add_child(_open_as_text_dialog)
	# 右键也选中条目，给个高亮反馈
	file_tree.allow_rmb_select = true
	# 用 gui_input 而不是 Tree 的 item_mouse_selected 拿右键：
	# item_mouse_selected 回调里给的 mouse_position 实测是**屏幕坐标**
	# （窗口在屏幕上的位置也算进去了），而 get_item_at_position() 要的是 Tree 局部坐标，
	# 两者对不上，喂进去永远返回 null。gui_input 里 event.position 才是局部坐标，实测正确。
	file_tree.gui_input.connect(_on_file_tree_gui_input)
	refresh_file_tree()

# 设置文件树的根目录。目录没变时直接返回 ——
# 这是防止每次点文件都重建整棵树、把所有展开状态重置掉的关键守卫。
func set_root_dir(dir: String) -> void:
	var normalized := dir.replace("\\", "/").simplify_path()
	if normalized.ends_with("/") and normalized.length() > 1:
		normalized = normalized.substr(0, normalized.length() - 1)
	if normalized == root_dir:
		return
	root_dir = normalized
	refresh_file_tree()

func refresh_file_tree() -> void:
	# 整棵重建会把折叠状态清零，深层目录里改个名整棵树就塌回去，很难用。
	# 记录的是**被折叠的**目录而不是展开的：TreeItem.collapsed 默认就是 false，
	# 新建出来的目录天生展开，所以要保留的恰恰是"用户手动折叠过"这个例外。
	# 换根目录时旧路径在新树里找不到，恢复自然是空操作。
	var collapsed := _collect_collapsed_paths()

	# 每一条能改变"有没有目录"的路径最后都会走到这里（换根、刷新、_setup_file_tree），
	# 所以按钮的可用状态在这里统一更新，不用逐个调用点去接。
	_update_new_buttons()

	file_tree.clear()
	var root := file_tree.create_item()

	if root_dir == "" or not DirAccess.dir_exists_absolute(root_dir):
		var hint := file_tree.create_item(root)
		hint.set_text(0, "未指定目录")
		hint.set_tooltip_text(0, "用 Ctrl+O 打开一个文件，侧边栏会自动定位到它所在的目录")
		hint.set_selectable(0, false)
		return

	_populate_dir(root, root_dir, 0)
	_restore_collapsed_paths(collapsed)

# 收集当前处于折叠状态的目录路径。只认目录：文件的 collapsed 恒为默认值，
# 收进来没意义还可能误伤。
func _collect_collapsed_paths() -> Dictionary:
	var out := {}
	_collect_collapsed_rec(file_tree.get_root(), out)
	return out

func _collect_collapsed_rec(item: TreeItem, out: Dictionary) -> void:
	if item == null:
		return
	var child := item.get_first_child()
	while child != null:
		if _item_is_dir(child) and child.collapsed:
			out[_item_path(child)] = true
		_collect_collapsed_rec(child, out)
		child = child.get_next()

func _restore_collapsed_paths(collapsed: Dictionary) -> void:
	if collapsed.is_empty():
		return
	_restore_collapsed_rec(file_tree.get_root(), collapsed)

# 注意一个 Tree 的内部规则：如果当前选中项正位于某个目录内部，
# 给那个目录赋 collapsed = true 会被**静默忽略**（赋值当场读回还是 false，
# 不报错也不发信号）。这是引擎在拦"不能把选中项折叠没了"，UI 上也因此走不到这个状态
# ——选中项在里面时，用户本来就点不折叠。所以这里不需要额外处理。
func _restore_collapsed_rec(item: TreeItem, collapsed: Dictionary) -> void:
	if item == null:
		return
	var child := item.get_first_child()
	while child != null:
		if _item_is_dir(child) and collapsed.has(_item_path(child)):
			child.collapsed = true
		_restore_collapsed_rec(child, collapsed)
		child = child.get_next()

func _populate_dir(parent: TreeItem, dir_path: String, depth: int) -> void:
	if depth >= MAX_TREE_DEPTH:
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return   # 无权限等，静默跳过，不打断整棵树

	var sub_dirs: Array[String] = []
	var files: Array[String] = []

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			if dir.current_is_dir():
				if not entry.begins_with(".") and not SKIP_DIRS.has(entry):
					sub_dirs.append(entry)
			else:
				# 不再按扩展名过滤：打不开的文件也要列出来，用不同的图标区分。
				# 这样目录里到底有什么一眼能看全，右键的重命名 / 删除也能直接作用在它们身上。
				files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()

	# 先收集再排序，保证目录在前、各自按自然序
	sub_dirs.sort_custom(_name_less)
	files.sort_custom(_name_less)

	for n in sub_dirs:
		var sub_path := dir_path.path_join(n)
		var dir_item := file_tree.create_item(parent)
		dir_item.set_text(0, n)
		dir_item.set_icon(0, _icon_dir)
		dir_item.set_tooltip_text(0, sub_path)
		dir_item.set_metadata(0, {"path": sub_path, "dir": true})
		_populate_dir(dir_item, sub_path, depth + 1)

	for n in files:
		var file_path := dir_path.path_join(n)
		var file_item := file_tree.create_item(parent)
		file_item.set_text(0, n)
		file_item.set_icon(0, _icon_file if _is_editable_file(n) else _icon_unsupported)
		file_item.set_metadata(0, {"path": file_path, "dir": false})

# 这个文件能不能在本编辑器里编辑。传文件名或完整路径都行（get_extension 只看最后一段）。
# 没有扩展名的文件（README、Makefile、LICENSE……）这里也算"不可编辑"：
# 判断不出类型时，宁可少编辑一个文本文件（用户能改名成 .txt 绕过），
# 也不要赌一把把二进制的乱码灌进编辑器、还可能顺着 Ctrl+S 覆盖回原文件。
func _is_editable_file(path: String) -> bool:
	return TEXT_EXTENSIONS.has(path.get_extension().to_lower())

func _name_less(a: String, b: String) -> bool:
	return a.naturalnocasecmp_to(b) < 0

# 条目 metadata 统一存 {"path": 绝对路径, "dir": bool}。
# 以前只有文件存 metadata、目录靠 metadata == null 反推，右键菜单拿不到目录路径，
# 所以改成两边都存。没有 metadata 的条目（"未指定目录" 占位）返回空串。
func _item_path(item: TreeItem) -> String:
	if item == null:
		return ""
	var m = item.get_metadata(0)
	if m is Dictionary:
		return m["path"]
	return ""

func _item_is_dir(item: TreeItem) -> bool:
	if item == null:
		return false
	var m = item.get_metadata(0)
	return m is Dictionary and m["dir"]

func _on_file_tree_item_selected() -> void:
	# 右键只负责弹菜单，不应该把文件载入编辑器。
	# Tree 在右键时会不会连带发 item_selected 各版本行为不一致，这里直接挡掉，
	# 无论如何右键点文件都不该换掉编辑器内容。
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return

	var item := file_tree.get_selected()
	if item == null:
		return

	if _item_is_dir(item):
		# 程序化选中不算"用户点了这个目录"。这一条挡的是 select() 顺带发出来的那次信号：
		# 重命名目录 / 新建文件夹都会选中目标，用户没点它，就不该动它的展开状态。
		if _suppress_dir_toggle:
			return
		item.collapsed = not item.collapsed   # 目录：展开 / 折叠
		# 记账：这一轮点击已经切过这个目录了。双击的第二下靠它去重，
		# 不然会再切一次、两次正好抵消。见 _on_file_tree_item_activated。
		_toggled_path = _item_path(item)
		return

	var path := _item_path(item)
	if path == "":
		return                                # 占位条目，没有对应文件

	# 不支持编辑的类型（Word / PPT / 图片……）：单击只选中高亮，什么都不打开。
	# 不能让单击就载进来 —— 读进来是二进制乱码，而 current_file_path 会被指过去，
	# 接着按一下 Ctrl+S 就把原文件覆盖成乱码了，这是真会丢数据的。
	# 想看内容：双击按文本打开（会先弹个提醒，见 _on_file_tree_item_activated），
	# 或者右键「用默认程序打开」交给 Word / PPT 本尊。
	if not _is_editable_file(path):
		return

	# 已经是当前文件就别重复加载。
	# 这一条同时也是 _select_tree_item_for_path 选中条目的递归刹车。
	if path == current_file_path:
		return
	open_and_show(path)                       # 可编辑的文件：单击直接载入编辑器

# 双击条目（或选中后按回车）。
func _on_file_tree_item_activated() -> void:
	var item := file_tree.get_selected()
	if item == null:
		return

	# 目录：双击 = 展开 / 折叠。
	# 这一下是双击的**第二下**，要不要切取决于第一下有没有已经切过 ——
	# Tree 在双击的第一下会做一次普通单击该做的事：
	#   第一下点在**没选中**的目录上 -> 发 item_selected -> _on_file_tree_item_selected
	#                                那边已经切过一次了 -> 这里必须跳过
	#   第一下点在**已选中**的目录上 -> allow_reselect=false 让 Tree 什么都不发
	#                                -> 这里必须补切一次
	# 不区分的话前者会切两次、净效果为零，就是用户看到的"双击文件夹没反应"。
	# 记账在 _toggled_path，由 gui_input 在每次**非双击的**左键按下时清空。
	if _item_is_dir(item):
		# 只有鼠标双击才在目录上做事；键盘回车进来的直接放过（老行为就是回车不管目录）。
		# 实测：双击的第二下触发这里时左键仍是按下状态，回车则不是，所以这个判断是准的。
		# 不加这道判断的话，回车会不会切就取决于上一次点击是不是"重选"，成了一个说不清的行为。
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			return
		if _toggled_path == _item_path(item):
			return
		item.collapsed = not item.collapsed
		return

	var path := _item_path(item)
	if path == "":
		return                                # "未指定目录" 占位条目

	# 已经在编辑器里就不重读。读盘会把没保存的改动直接冲掉 ——
	# 顺手双击一下当前文件就丢字，那是比"没反应"糟得多的结果。
	if path == current_file_path:
		return

	# 白名单里的正常打开。
	if _is_editable_file(path):
		open_and_show(path)
		return

	# 不在白名单里 = "强制按文本打开"，先提醒一句再动手。这个入口主要给两种情况用：
	#   1) .toml / .env / Dockerfile / README 这类没进白名单、但本来就是文本的文件
	#   2) 真想看看 .docx / .pptx 里面到底有什么
	# 提醒是必要的，因为第 2 种情况下读进来是一堆乱码，而 current_file_path
	# 已经指过去了 —— 此时按 Ctrl+S 会拿编辑器里的内容覆盖掉原文件，不可逆。
	_pending_open_path = path
	_open_as_text_dialog.dialog_text = (
		"「%s」不在可编辑类型列表里，按文本打开多半是乱码。\n\n"
		+ "如果它本来就是文本文件（比如 .toml、.env），确认即可。\n"
		+ "如果不是，看完别保存 —— Ctrl+S 会用编辑器里的内容覆盖原文件。"
	) % path.get_file()
	_open_as_text_dialog.popup_centered()

# 提醒框点了「仍要打开」
func _on_open_as_text_confirmed() -> void:
	if _pending_open_path == "":
		return
	var path := _pending_open_path
	_pending_open_path = ""     # 先清再打开：open_and_show 会发 item_selected，别让它重入
	open_and_show(path)

# 在树里定位并选中某个文件，同时逐级展开它的祖先目录
func _select_tree_item_for_path(path: String) -> void:
	var item := _find_tree_item(file_tree.get_root(), path)
	if item == null:
		return

	var ancestor := item.get_parent()
	while ancestor != null and ancestor != file_tree.get_root():
		ancestor.collapsed = false
		ancestor = ancestor.get_parent()
	# select() 会**同步**发 item_selected。如果选中的正是一个目录，那边会把它"展开/折叠"切一下，
	# 于是重命名成了"把目录收起来"、新建文件夹成了"建出来就是折叠的"。
	# 这两句必须紧贴着 select()：中间不能有 await，也不能提前 return。
	_suppress_dir_toggle = true
	item.select(0)
	_suppress_dir_toggle = false

func _find_tree_item(parent: TreeItem, path: String) -> TreeItem:
	if parent == null:
		return null
	var child := parent.get_first_child()
	while child != null:
		if _item_path(child) == path:
			return child
		var found := _find_tree_item(child, path)
		if found != null:
			return found
		child = child.get_next()
	return null
