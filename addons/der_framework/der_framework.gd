@tool
extends EditorPlugin


func _enable_plugin() -> void:
	pass

func _disable_plugin() -> void:
	# Remove autoloads here.
	pass


func _enter_tree() -> void:
	add_autoload_singleton("DMainManager","res://addons/der_framework/DMain/DerMain.tscn")
	add_autoload_singleton("DMessageManager","res://addons/der_framework/DMessage/DerMessage.tscn")
	add_autoload_singleton("DSaveManager","res://addons/der_framework/DSave/DerSave.tscn")
	add_autoload_singleton("DSettingsManager","res://addons/der_framework/DSettings/DerSettings.tscn")



func _exit_tree() -> void:
	remove_autoload_singleton("DMainManager")
	remove_autoload_singleton("DMessageManager")
	remove_autoload_singleton("DSaveManager")
	remove_autoload_singleton("DSettingsManager")
