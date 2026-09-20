class_name DerSettingsRes extends Resource

## DerFramework 的设置数据资源
## 修改属性后调用 DSettingsManager.save_settings() 持久化到磁盘

@export_group("音频")
## 主音量（0~1）
@export var master_volume: float = 1.0
## 音乐音量（0~1）
@export var music_volume: float = 1.0
## 音效音量（0~1）
@export var sfx_volume: float = 1.0

@export_group("画面")
## 是否全屏
@export var fullscreen: bool = false
## 是否垂直同步
@export var vsync_enabled: bool = true

@export_group("语言")
## 当前语言（对应 TranslationServer 的 locale）
@export var language: String = "zh_CN"
