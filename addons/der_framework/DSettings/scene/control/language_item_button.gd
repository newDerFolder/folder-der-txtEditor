class_name LanguageItemButton extends Button

@export var language_id="en"


func _pressed() -> void:
	DSettingsManager.settings.language=language_id
	TranslationServer.set_locale(language_id)
	DMessageManager.add_message("语言已更改","DerSettings")

func _process(delta: float) -> void:
	if DSettingsManager.settings.language==language_id:
		modulate=Color.YELLOW
	else:
		modulate=Color.WHITE
