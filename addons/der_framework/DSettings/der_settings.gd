class_name DerSettings extends Node
## DerFramework 中负责设置读取与保存的模块
## 启动时检查 user://der_settings.tres 是否存在，存在则读取，不存在则创建默认设置

## 设置发生变化时发出（保存成功后触发）
signal settings_changed

const SETTINGS_PATH := "user://der_settings.tres"

## 当前设置数据，直接读写字段后调用 save_settings() 持久化
var settings: DerSettingsRes

func _ready() -> void:
	call_deferred("_send_ready_message")
	call_deferred("_load_or_create")

func apply_settings()->void:
	TranslationServer.set_locale(settings.language)

## 读取已存在的设置文件；不存在或损坏时创建默认设置
func _load_or_create() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		var loaded := ResourceLoader.load(SETTINGS_PATH) as DerSettingsRes
		if loaded != null:
			settings = loaded
			DMessageManager.add_message("[color=green]已加载设置文件", "DerSettings")
			return
		push_warning("设置文件损坏，将重新创建: ", SETTINGS_PATH)

	# 不存在或读取失败：创建默认设置并保存
	settings = DerSettingsRes.new()
	save_settings()
	DMessageManager.add_message("[color=green]已创建默认设置文件", "DerSettings")

## 将当前设置保存到磁盘，成功后发出 settings_changed
func save_settings() -> void:
	var err := ResourceSaver.save(settings, SETTINGS_PATH)
	if err != OK:
		push_error("设置保存失败: ", err, " 路径=", SETTINGS_PATH)
		DMessageManager.add_message("[color=red]设置保存失败", "DerSettings")
		return
	settings_changed.emit()
	DMessageManager.add_message("[color=green]设置保存成功", "DerSettings")

## 恢复默认设置并保存
func reset_to_defaults() -> void:
	settings = DerSettingsRes.new()
	save_settings()

func _send_ready_message() -> void:
	DMessageManager.add_message("[color=green]模块启动", "DerSettings")
