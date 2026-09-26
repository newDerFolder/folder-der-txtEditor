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

# ---------------- 阅读（小说预览器） ----------------
#
# 这一组是**可调项的持久化**。取值一律是"档位下标 / 档位值"，不是像素或颜色 ——
# 认值不认名字：以后往档位表末尾追加一档，老文件读进来仍然是合法下标，不会串档。
#
# ⚠️ 每一项的默认值都**必须**等于 main.gd 里那个 `_DEFAULT` 常量，否则"第一次启动"
# 和"设置文件丢了重建"会得到两套不同的外观。两边对不上时 harness 会断言失败。

@export_group("阅读")
## 正文字号（像素）。档位表 main.gd::PREVIEW_FONT_SIZES
@export var preview_font_size: int = 16
## 手动指定的预览器。0=自动 1=小说 2=Markdown（main.gd::PreviewOverride）
@export var preview_mode_override: int = 0
## 行距因数。乘在"按字号算出的基准行距"上，1.0 = 不改
@export var preview_line_scale: float = 1.0
## 首行缩进字宽（全角字数）
@export var preview_indent: int = 2
## 阅读宽度（页宽，像素）。0 = 全宽
@export var preview_page_width: int = 0
## 阅读主题（配色）。见 scene/Previewer/PreviewTheme.gd::Scheme
@export var preview_scheme: int = 0
## 翻页模式。false = 自由滚动（默认，= 改动前的行为），true = 一次一屏
@export var preview_paged: bool = false
