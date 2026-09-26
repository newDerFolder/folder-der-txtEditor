class_name PreviewTheme
extends RefCounted

## 阅读主题（配色）。**单一真源**：所有色值都只在这里写一次。
##
## ## 为什么不能只靠覆盖 RichTextLabel 的主题项
##
## `[color=...]` 的优先级**高于** RTL 的主题项 `default_color`。而 Markdown 转换器把 8 个
## 颜色**直接拼进了输出串**（代码块底色、行内代码、链接、引用、标题、灰字、水平线）。
## 所以只调 `add_theme_color_override("default_color", ...)` 的话，**那些地方一处都不会变**，
## 只有没被 `[color]` 包住的正文会变 —— 看着像"主题只生效了一半"。
##
## 结论：**节点主题覆盖**和**输出串换色**两件事都得做，不是二选一。本文件同时提供两者：
##   * `apply_to(rtl, theme)` —— 管没被 `[color]` 包住的正文、背景、选中色
##   * `retint(bb, theme)`     —— 管拼进输出串里的那 10 处
##
## ## retint 为什么是安全的（这是它能成立的关键）
##
## 它对**成品字符串**做替换，而替换目标是**完整的标签形式**（`[color=#7aa2f7]`），
## 不是裸色值。两个转换器的 `_escape()` 把文档内容里**每一个** `[` 都换成了 `[lb]`，
## 所以输出串里凡是 `[color=` 开头的地方，都只可能是转换器自己吐出来的 ——
## 用户没法用「在正文里写一个 hex」来伪造一个标签出来。
##
## 反过来说：**裸色值替换（把 `#7aa2f7` 直接换成别的）是不安全的**，
## 代码块里恰好写着这个 hex 就会被染色。所以这里只换标签形式。

## 主题清单。**顺序就是菜单顺序**，追加新主题请加在末尾（id 会被持久化）。
##
## 名字叫 Scheme 而不是 Theme：`Theme` 是 Godot 的**原生类**，
## 用它当枚举名会直接 `Parse Error: The member "Theme" shadows a native class`。
enum Scheme {
	DEFAULT,    ## 现状（深色底，正文白色、背景透出底图）
	PAPER,      ## 纸白
	SEPIA,      ## 米黄
	NIGHT,      ## 夜间（比现状更黑，OLED 省电）
}

## 菜单里显示的名字。**必须和 Scheme 一一对应**（长度对不上会断言失败）
const NAMES: Array[String] = ["默认", "纸白", "米黄", "夜间"]


# ---------------- 色值常量（唯一书写处） ----------------
#
# 分成两类是**有意的**：`正文/背景/选中` 这组只用在节点主题项上，不进输出串；
# `dim/hr/link/quote/heading/inline_code*` 这组会被拼进输出串，必须能被 retint 换掉。
# 「背景」和「前景」也要分开放 —— 亮色主题下代码块底色变浅是必须的，
# 混在一块写常量最容易在换主题时漏掉它，露出一块黑斑。

## 正文色。**实测等于 RTL 内建的 default_color**，所以 DEFAULT 下覆盖它 = 视觉零变化。
## （依据：`resource/folder.tres` 里 **0 处** RichTextLabel 条目，所以走内建值。
## 这一条在 harness 里是**验过的**，不是靠记忆 —— 换主题资源时要重跑那条断言。）
const C_TEXT := "#ffffff"

## 选中背景。**内建值原样抄在这里**，用 Color 而不是 hex。
##
## 为什么非得是 Color：内建的是 `(0.1, 0.1, 1.0, 0.8)`，而 0.1 写成 hex 只能得到 `#1a`，
## 反算回来是 26/255 ≈ 0.10196 ≠ 0.1 —— 于是"默认主题零变化"会**差在最后一位**，
## 而 Color 的 `==` 是逐浮点比较，这条不变量就验不过了。hex 表示不了这个值。
const C_SEL := Color(0.1, 0.1, 1.0, 0.8)

## 选中文字色。内建值是**全透明黑** —— 语义是"选中不改字色"，字保持正文色。
## 不是"黑色"：alpha=0 才是重点（内建也是 0，所以同样必须用 Color 精确表示）。
const C_SEL_TEXT := Color(0, 0, 0, 0)

const C_DIM := "#6b7075"            ## 灰字：不可点的链接目标、说明、txt 的分隔行
const C_HR := "#3a3d3f"
const C_LINK := "#7aa2f7"
const C_QUOTE := "#9aa0a6"
const C_HEADING := "#e8eaed"
const C_INLINE_CODE_FG := "#e0a878"
const C_CODE_BG := "#1e2124"
const C_INLINE_CODE_BG := "#26292d"

## `[hr]` 标签的属性前缀。**MarkdownToBbcode 拼 hr 时用的就是它**，
## 这样"输出格式"和"retint 的匹配目标"不可能各写各的而悄悄漂移。
const HR_ATTR := "[hr height=1 width=100% align=l color="

## 会被拼进输出串、因而需要 retint 的键。`text`/`bg`/`sel`/`sel_text` 不在此列。
const EMITTED_KEYS: Array[String] = [
	"dim", "hr", "link", "quote", "heading",
	"inline_code_fg", "code_bg", "inline_code_bg",
]

## 现状色板。**retint 的替换表就是拿它做源**，所以它必须和上面那些常量逐字一致。
const DEFAULT_PALETTE := {
	"text": C_TEXT,
	"bg": "",                       ## 空 = 不设背景，透出 main.tscn 的底图（= 现状）
	"sel": C_SEL,
	"sel_text": C_SEL_TEXT,
	"dim": C_DIM,
	"hr": C_HR,
	"link": C_LINK,
	"quote": C_QUOTE,
	"heading": C_HEADING,
	"inline_code_fg": C_INLINE_CODE_FG,
	"code_bg": C_CODE_BG,
	"inline_code_bg": C_INLINE_CODE_BG,
}

const PALETTES := {
	Scheme.DEFAULT: DEFAULT_PALETTE,

	# 纸白：正文近黑、代码块底色变浅。**代码块底色必须跟着变** ——
	# 沿用深色底会在白底上糊出一块黑斑，这是换主题最容易漏的一处。
	Scheme.PAPER: {
		"text": "#2b2d30",
		"bg": "#fdfdfb",
		"sel": "#b8cdf0",
		"sel_text": "#1a1c1e",
		"dim": "#8a8f94",
		"hr": "#c9ced3",
		"link": "#1a5fb4",
		"quote": "#5c6369",
		"heading": "#17191b",
		"inline_code_fg": "#9c4a12",
		"code_bg": "#eceef0",
		"inline_code_bg": "#e2e5e8",
	},

	# 米黄（护眼纸）：偏暖，长时间读小说用这个。
	Scheme.SEPIA: {
		"text": "#3b332a",
		"bg": "#f6ecd9",
		"sel": "#dfc79a",
		"sel_text": "#2e2820",
		"dim": "#8b7f6d",
		"hr": "#d8caad",
		"link": "#1f6f8b",
		"quote": "#6b6152",
		"heading": "#2e2820",
		"inline_code_fg": "#9c4a1a",
		"code_bg": "#efe5d2",
		"inline_code_bg": "#e7dcc6",
	},

	# 夜间：比现状更暗（纯黑底 + 压暗的前景），暗环境下不刺眼。
	Scheme.NIGHT: {
		"text": "#c8ccd0",
		"bg": "#0a0b0d",
		"sel": "#2a3b55",
		"sel_text": "#dfe3e8",
		"dim": "#5a6068",
		"hr": "#2a2d30",
		"link": "#6c9ce8",
		"quote": "#878d95",
		"heading": "#dfe3e8",
		"inline_code_fg": "#d69a6a",
		"code_bg": "#121416",
		"inline_code_bg": "#191c1f",
	},
}


## 取色板里那一项。**"没有这一项"和"这一项是空字符串"都返回 null**，
## 两个取值函数据此各自回落。
static func _value(theme: int, key: String) -> Variant:
	var pal: Dictionary = PALETTES.get(theme, DEFAULT_PALETTE)
	if not pal.has(key):
		pal = DEFAULT_PALETTE
		if not pal.has(key):
			return null
	var v: Variant = pal[key]
	# 空字符串是"没有这个色"的约定写法（DEFAULT 的 bg），和"键不存在"一样处理。
	return null if (v is String and v == "") else v


## 取某个主题下某个键的色值（**字符串形式**，给 BBCode 的 `%s` 用）。
## 主题或键不存在时回落到 DEFAULT，不报错 —— 设置文件里存了个未来的主题 id 时，
## 用户看到的是"回到默认配色"，而不是一个空字符串把 `[color=]` 拼坏。
##
## ⚠️ 这一路只给**会被拼进输出串的那 8 个键**（EMITTED_KEYS）用，它们全是 hex 字符串。
## `sel` / `sel_text` 存的是 Color，真被问到也能转（`to_html`），但别用 —— 它们走 rgba()。
static func color(theme: int, key: String) -> String:
	var v: Variant = _value(theme, key)
	if v == null:
		return ""
	if v is Color:
		var c := v as Color
		return c.to_html(c.a < 1.0)
	return String(v)


## 同上，但要 **Color 对象**（给 `add_theme_color_override` 用）。
##
## 色板里这两类值都收：hex 字符串（那 8 个发射色）和 Color（`sel`/`sel_text` ——
## 内建值 `0.1` 表示不成 hex，见 C_SEL 的注释）。
## 取不到、或者值是空字符串时返回**全透明**，调用方（`has_bg`）据此判断"要不要设背景"。
static func rgba(theme: int, key: String) -> Color:
	var v: Variant = _value(theme, key)
	if v == null:
		return Color(0, 0, 0, 0)
	if v is Color:
		return v as Color
	return Color(String(v))


## 主题是否有自己的背景色。DEFAULT 没有（透出底图），其余都有。
static func has_bg(theme: int) -> bool:
	return color(theme, "bg") != ""


## 把**转换器吐出来的** BBCode 换成指定主题的配色。
##
## DEFAULT 直接原样返回 —— 于是"默认主题下输出逐字节等于改动前"是**结构性保证**，
## 不是靠人肉核对色值有没有写错。
static func retint(bb: String, theme: int) -> String:
	if theme == Scheme.DEFAULT or not PALETTES.has(theme):
		return bb
	var out := bb
	for key in EMITTED_KEYS:
		var old := String(DEFAULT_PALETTE[key])
		var new := String(PALETTES[theme][key])
		if old == new:
			continue
		# 只换标签形式。见文件头的论证：文档内容里的 `[` 已被 _escape() 换成 [lb]，
		# 所以这里的匹配目标只可能是转换器自己写出来的。
		out = out.replace("[color=" + old + "]", "[color=" + new + "]")
		out = out.replace("[bgcolor=" + old + "]", "[bgcolor=" + new + "]")
		out = out.replace(HR_ATTR + old + "]", HR_ATTR + new + "]")
	return out


## 把主题应用到承载正文的那个 RichTextLabel 上。
##
## **DEFAULT 也要显式走一遍**，不能 early-return：用户从"夜间"切回"默认"时，
## 必须把上一套覆盖清掉 / 换回原值，否则会残留在那儿。
static func apply_to(rtl: RichTextLabel, theme: int) -> void:
	rtl.add_theme_color_override("default_color", rgba(theme, "text"))
	rtl.add_theme_color_override("selection_color", rgba(theme, "sel"))
	rtl.add_theme_color_override("font_selected_color", rgba(theme, "sel_text"))
	if has_bg(theme):
		var sb := StyleBoxFlat.new()
		sb.bg_color = rgba(theme, "bg")
		# 左右留一点内边距，否则背景色和文字贴边，窄栏里看着很挤。
		sb.content_margin_left = 8.0
		sb.content_margin_right = 8.0
		rtl.add_theme_stylebox_override("normal", sb)
	else:
		# 回到"没有背景"，让 main.tscn 的 TextureRect 底图透出来。
		# 直接 add 一个透明 StyleBox 是不够的 —— 那仍然会盖住底图。
		rtl.remove_theme_stylebox_override("normal")
