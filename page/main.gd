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

# 右键菜单项 id。用枚举而不是裸数字，加/删菜单项时不用回来数顺序。
enum MenuId {
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
# 重命名对话框里的输入框，代码创建 —— AcceptDialog 会把子节点收进自己的内容区，
# 手写 tscn 布局容易对不上
var _rename_edit: LineEdit

# 双击不支持编辑的文件时的"强制按文本打开"提醒框。
# 同样在代码里建：main.tscn 里这排 AcceptDialog 的节点都带 unique_id，
# 手写 tscn 容易把那个 id 写错或写重，交给 Godot 自己保存场景时落盘更安全。
var _open_as_text_dialog: ConfirmationDialog
# 提醒框确认后要打开的那个文件
var _pending_open_path: String = ""

var font_size=20

func _ready():
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

	# 重命名输入框
	_rename_edit = LineEdit.new()
	_rename_edit.custom_minimum_size = Vector2(360, 0)
	rename_dialog.add_child(_rename_edit)
	rename_dialog.register_text_enter(_rename_edit)   # 输入框里回车 = 点确定
	rename_dialog.confirmed.connect(_on_rename_confirmed)

	delete_dialog.confirmed.connect(_on_delete_confirmed)

func _on_file_tree_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and \
			event.button_index == MOUSE_BUTTON_RIGHT):
		return      # 只管右键按下；左键走 item_selected

	# 这里必须用 event.position（Tree 局部坐标）来查条目，而不是读 get_selected()：
	# 右键点在空处时选中项还停在原来那个条目上，读选中项会弹出上一个文件的菜单。
	var item := file_tree.get_item_at_position(event.position)
	var path := _item_path(item)
	if path == "":
		return      # 点到空白处，或 "未指定目录" 占位条目

	_menu_path = path
	_menu_is_dir = _item_is_dir(item)
	_build_item_menu()

	# 必须显式给坐标：Godot 4 的无参 popup() 弹在 (0,0)，不读鼠标位置
	# （那是 Godot 3 的行为，别按老文档想当然）。
	# 实测 popup(rect) 的 rect 吃的是**视口局部坐标**，所以把 Tree 局部坐标加上
	# Tree 自身的全局位置换算过去。用 event.position 而不是读实时鼠标位置：
	# 真实点击时两者本就一致，但这样不依赖"弹菜单那一刻鼠标还在原地"。
	file_item_menu.popup(Rect2i(file_tree.get_global_position() + event.position, Vector2i.ZERO))

func _build_item_menu() -> void:
	file_item_menu.clear()
	# 「用默认程序打开」只对"看得见但本编辑器打不开"的文件才有意义：
	# 目录用「在文件管理器中打开」就够了，可编辑的文件本来就单击即开。
	# 菜单项 id 走枚举，所以在这里按条件增删不会影响别的项。
	if not _menu_is_dir and not _is_editable_file(_menu_path):
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

# ---------------- 重命名 ----------------

func _prompt_rename() -> void:
	rename_dialog.dialog_text = "输入新的" + ("文件夹名" if _menu_is_dir else "文件名")
	_rename_edit.text = _menu_path.get_file()
	rename_dialog.popup_centered()
	_rename_edit.grab_focus()
	_select_base_name()

# 只选中主名、不含扩展名，直接输入就能整体覆盖，又不用手动删掉 ".txt"
func _select_base_name() -> void:
	var full := _rename_edit.text
	if _menu_is_dir:
		_rename_edit.select_all()
		return
	var base := full.get_basename()
	_rename_edit.select(0, base.length())
	_rename_edit.caret_column = base.length()

# 校验新名称能不能用。返回 "" 表示可用，否则返回给用户看的原因。
# 单独拆出来是为了不起弹窗也能测 —— OS.alert 在 Windows 上是阻塞的，
# 埋在里面的分支没法从脚本里驱动。
func _validate_new_name(old_path: String, new_name: String) -> String:
	if new_name == "":
		return "名称不能为空"
	if new_name.contains("/") or new_name.contains("\\") or \
	   new_name.contains(":") or new_name.contains("*") or new_name.contains("?") or \
	   new_name.contains("\"") or new_name.contains("<") or new_name.contains(">") or \
	   new_name.contains("|"):
		return "名称不能包含下列字符：/ \\ : * ? \" < > |"
	var new_path := old_path.get_base_dir().path_join(new_name)
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
		item.collapsed = not item.collapsed   # 目录：展开 / 折叠
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

	# 目录：这里什么都不做。双击的第一下已经发过 item_selected、把展开状态切过一次了，
	# 再切一次正好抵消，用户会看到"双击文件夹没反应"。
	if _item_is_dir(item):
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
	item.select(0)

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
