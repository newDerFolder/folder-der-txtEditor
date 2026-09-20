## 处理主要循环和统计的核心
class_name DerMain extends Node

func _ready() -> void:
	call_deferred("_send_ready_message")



func _send_ready_message() -> void:
	DMessageManager.add_message("[color=green]模块启动","DerMain")
	DMessageManager.add_message("开始检查FuncRange系列插件情况","DerMain")
	if has_custom_class("EasyBagResource"):
		DMessageManager.add_message("[color=green]插件 EasyBag 存在","DerMain")
	else:
		DMessageManager.add_message("[color=red]插件 EasyBag 获取错误.请检查插件是否存在或启用后重新尝试","DerMain")
	if has_custom_class("ForMap"):
		DMessageManager.add_message("[color=green]插件 ForMap 存在","DerMain")
	else:
		DMessageManager.add_message("[color=red]插件 ForMap 获取错误.请检查插件是否存在或启用后重新尝试","DerMain")
	if has_custom_class("ActTea"):
		DMessageManager.add_message("[color=green]插件 ActTea 存在","DerMain")
	else:
		DMessageManager.add_message("[color=red]插件 ActTea 获取错误.请检查插件是否存在或启用后重新尝试","DerMain")


# 检查项目中是否存在指定名称的自定义类（使用 class_name 定义）
func has_custom_class(class_name_to_check: String) -> bool:
	var global_classes = ProjectSettings.get_global_class_list()
	
	for class_info in global_classes:
		if class_info["class"] == class_name_to_check:
			return true
	
	return false

func _minute_update():
	DMessageManager.add_message("_minute_update","DerMain")
	DSaveManager.add_cur_res_player_time()

func _on_minute_timer_timeout() -> void:
	_minute_update()
