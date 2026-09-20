class_name DerSave extends Node
## DerFramework中负责存档功能的模块

@export var save_path := "user://DerSave/"
@export var cur_res:DerSaveRes
## 自动创建和使用自动存档这在制作休闲游戏等常常不需要进行多存档管理的项目时非常省事，默认开启，当你打算开发galgame或者是rpg时可以考虑关掉
@export var use_auto_slot=true

const AUTO_SLOT_NAME := "AutoSlot"

func _ready() -> void:
	_ensure_save_dir_exists()
	if use_auto_slot:
		_setup_auto_slot()
	call_deferred("_send_ready_message")

func save_cur_res():
	if cur_res!=null:
		save_resource(cur_res)

func _setup_auto_slot() -> void:
	# 检查是否已有 AutoSlot 存档
	var existing_save := load_resource(AUTO_SLOT_NAME)
	if existing_save != null:
		cur_res = existing_save
		DMessageManager.add_message("[color=green]已加载自动存档 [%s]" % AUTO_SLOT_NAME, "DerSave")
	else:
		# 创建新的自动存档
		var new_save := DerSaveRes.new()
		new_save.save_name = AUTO_SLOT_NAME
		save_resource(new_save)
		cur_res = new_save
		DMessageManager.add_message("[color=green]已创建并启用自动存档 [%s]" % AUTO_SLOT_NAME, "DerSave")

func add_cur_res_player_time():
	if cur_res!=null:
		cur_res.playtime+=1

func delete_resource(res: DerSaveRes) -> void:
	if res == null:
		push_error("尝试删除空存档资源")
		return
	
	# 防止删除自动存档
	if res.save_name == AUTO_SLOT_NAME:
		DMessageManager.add_message("[color=yellow]自动存档不可删除", "DerSave")
		return
	
	var save_name := res.save_name
	if save_name.is_empty():
		push_error("存档资源的 save_name 为空，无法删除")
		return
	
	delete_save(save_name)
	
	# 如果删除的是当前正在使用的存档，清空 cur_res
	if cur_res == res or (cur_res != null and cur_res.save_name == save_name):
		cur_res = null
		DMessageManager.add_message("已清除当前使用的存档引用", "DerSave")
	
	DMessageManager.add_message("[color=red]存档 [%s] 已删除" % save_name, "DerSave")

func set_cur_res(res:DerSaveRes):
	cur_res=res
	DMessageManager.add_message("已更改当前使用的存档", "DerSave")

func _ensure_save_dir_exists() -> void:
	var err := DirAccess.make_dir_recursive_absolute(save_path)
	if err != OK:
		push_error("创建存档目录失败: ", err, " -> ", save_path)

func create_resource(save_name: String):
	# 防止手动创建同名自动存档
	if save_name == AUTO_SLOT_NAME:
		DMessageManager.add_message("[color=yellow]不能手动创建自动存档", "DerSave")
		return
	
	DMessageManager.add_message("[color=green]正在创建存档", "DerSave")
	var r = DerSaveRes.new()
	r.save_name = save_name
	save_resource(r)

func _send_ready_message() -> void:
	DMessageManager.add_message("[color=green]模块启动", "DerSave")

func save_resource(res: DerSaveRes) -> void:
	_ensure_save_dir_exists()
	
	var now := int(Time.get_unix_time_from_system())
	res.last_modified_timestamp = now
	if res.create_timestamp == 0:
		res.create_timestamp = now
	
	var full_path := save_path.path_join(res.save_name+".tres")
	print("实际保存路径: ", full_path)
	
	var err := ResourceSaver.save(res, full_path)
	if err != OK:
		DMessageManager.add_message("[color=red]存档保存失败", "DerSave")
		push_error("保存失败: ", err, " 路径=", full_path)
	else:
		DMessageManager.add_message("[color=green]存档保存成功", "DerSave")
		print("保存成功: ", full_path)

func load_resource(save_name: String) -> DerSaveRes:
	var full_path := save_path.path_join(save_name+".tres")
	if FileAccess.file_exists(full_path):
		return ResourceLoader.load(full_path) as DerSaveRes
	push_warning("文件不存在: ", full_path)
	return null

func save_exists(save_name: String) -> bool:
	return FileAccess.file_exists(save_path.path_join(save_name+".tres"))

func delete_save(save_name: String) -> void:
	# 防止删除自动存档
	if save_name == AUTO_SLOT_NAME:
		DMessageManager.add_message("[color=yellow]自动存档不可删除", "DerSave")
		return
	
	var full_path := save_path.path_join(save_name+".tres")
	if FileAccess.file_exists(full_path):
		DirAccess.remove_absolute(full_path)

func list_saves() -> Array[String]:
	var dir := DirAccess.open(save_path)
	if dir == null:
		return []
	var saves: Array[String] = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.ends_with(".tres"):
			var full_path := save_path.path_join(f)
			var res := ResourceLoader.load(full_path) as DerSaveRes
			if res != null and res.save_name != "":
				saves.append(res.save_name)
		f = dir.get_next()
	dir.list_dir_end()
	return saves
