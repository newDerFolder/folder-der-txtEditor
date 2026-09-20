class_name DerSaveRes extends Resource

## 创建时间的 Unix 时间戳（秒）
@export var create_timestamp: int = 0

## 最后修改时间的 Unix 时间戳（秒）
@export var last_modified_timestamp: int = 0

## 总游玩时长（分）
@export var playtime: int = 0

## 存档名称
@export var save_name: String = "NewSave"

# 获取格式化的创建时间字符串
func get_create_time_str() -> String:
	if create_timestamp > 0:
		return Time.get_datetime_string_from_unix_time(create_timestamp, true)
	return ""

# 获取格式化的最后修改时间字符串
func get_last_modified_str() -> String:
	if last_modified_timestamp > 0:
		return Time.get_datetime_string_from_unix_time(last_modified_timestamp, true)
	return ""
