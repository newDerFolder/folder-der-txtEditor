extends Control

# 侧边栏只列这些扩展名的文件
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

# 两张源图尺寸差很多（folder.png 是 32x32，folderTxt.png 是 400x400），直接塞给 Tree
# 会按原始尺寸绘制，400x400 那张能把整行撑爆。Tree 的 icon_size 主题常量在 4.7 里
# 对绘制尺寸无效（实测），所以这里在加载时就把贴图统一重采样成 ICON_SIZE x ICON_SIZE ——
# 比绘制期缩放更清晰，大图小图都精确落在这个尺寸上。
var _icon_dir: Texture2D
var _icon_file: Texture2D

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
	file_item_menu.add_item("在文件管理器中打开", MenuId.OPEN_IN_FILE_MANAGER)
	file_item_menu.add_separator()
	file_item_menu.add_item("重命名", MenuId.RENAME)
	file_item_menu.add_item("删除", MenuId.DELETE)
	file_item_menu.add_separator()
	file_item_menu.add_item("复制完整路径", MenuId.COPY_PATH)
	file_item_menu.add_item("刷新文件树", MenuId.REFRESH)

func _on_menu_id_pressed(id: int) -> void:
	match id:
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
		return null
	var img := tex.get_image()
	if img == null:
		return tex   # 取不到像素数据（压缩纹理等），退回原图
	img.resize(ICON_SIZE, ICON_SIZE, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

func _setup_file_tree() -> void:
	_icon_dir = _make_icon(ICON_DIR_PATH)
	_icon_file = _make_icon(ICON_FILE_PATH)

	file_tree.hide_root = true
	# 注意：不要开 allow_reselect。它会让 Tree 在重选同一项时重复发 item_selected，
	# 而折叠一个已选中的条目会触发 Tree 内部重选 —— 于是折叠 -> 重选 -> 折叠 形成死循环，
	# 每帧振荡，同步处理时直接段错误崩溃。
	file_tree.allow_reselect = false
	file_tree.item_selected.connect(_on_file_tree_item_selected)
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
			elif _is_text_file(entry):
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
		file_item.set_icon(0, _icon_file)
		file_item.set_metadata(0, {"path": file_path, "dir": false})

func _is_text_file(file_name: String) -> bool:
	return TEXT_EXTENSIONS.has(file_name.get_extension().to_lower())

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

	# 已经是当前文件就别重复加载。
	# 这一条同时也是 _select_tree_item_for_path 选中条目的递归刹车。
	if path == current_file_path:
		return
	open_and_show(path)                       # 文件：单击直接载入编辑器

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
