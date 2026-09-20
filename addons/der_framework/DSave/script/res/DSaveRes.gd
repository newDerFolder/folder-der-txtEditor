class_name DerSaveRes extends Resource

## 创建时间的 Unix 时间戳（秒）
@export var create_timestamp: int = 0

## 最后修改时间的 Unix 时间戳（秒）
@export var last_modified_timestamp: int = 0

## 总游玩时长（分）
@export var playtime: int = 0

## 存档名称
@export var save_name: String = "NewSave"

## 收藏的文件 / 文件夹的绝对路径（正斜杠、无结尾斜杠）。
## 存全路径而不是相对路径：收藏的目的就是跨目录跳，相对某个 root_dir 没有意义。
## 老存档里没有这个字段，加载时取默认值 []，其余字段照旧。
@export var favorite_paths: Array[String] = []

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
