extends Control

# 这些扩展名是**可编辑**的。注意它不再用来过滤文件列表 ——
# 不支持编辑的文件（Word / PPT / 图片……）同样会列在树里，只是图标不同、点击不载入。
const TEXT_EXTENSIONS := [
	"txt", "md", "json", "csv", "log", "ini", "cfg", "yaml", "yml", "xml",
	"gd", "tscn", "tres", "html", "css", "js", "py", "sh", "bat",
]
# 这些目录不展开
const SKIP_DIRS := ["node_modules", "__pycache__", "venv", "env"]
# 目录树的深度上限。懒加载之后它**不再是建树时的刹车**（每次只建一层，本来就建不深），
# 拦的是另一种情况：符号链接成环时，用户可以顺着环一直点下去，每一层都真的建出来。
# 到了这一层就停：条目照样显示、照样能点，只是不再往里建。
const MAX_TREE_DEPTH := 12

# 侧边栏条目标图标的边长（像素）
const ICON_SIZE := 15

const ICON_DIR_PATH := "res://asset/icon/folder.png"
const ICON_FILE_PATH := "res://asset/icon/folderTxt.png"
# 不支持编辑的文件的图标
const ICON_UNSUPPORTED_PATH := "res://asset/icon/UnsupportedEditIcon.png"

# 两张源图尺寸差很多（folder.png 是 32x32，folderTxt.png 是 400x400），直接塞给 Tree
# 会按原始尺寸绘制，400x400 那张能把整行撑爆。Tree 的 icon_size 主题常量在 4.7 里
# 对绘制尺寸无效（实测），所以这里在加载时就把贴图统一重采样成 ICON_SIZE x ICON_SIZE ——
# 比绘制期缩放更清晰，大图小图都精确落在这个尺寸上。
var _icon_dir: Texture2D
var _icon_file: Texture2D
var _icon_unsupported: Texture2D

# ---------------- 预览面板的常量 ----------------

# 扩展名 → 预览模式。**和 TEXT_EXTENSIONS 是两回事**：那个列表管的是"能不能编辑"
# （json / py / gd 都在里面），这个只管"有没有阅读视图"。所以它短得多，而且
# 加一个可编辑类型**不应该**顺带让它有预览 —— 两边共用一个表是将来最容易犯的错。
const PREVIEW_EXT_MODE := {"txt": 1, "md": 2}

# 打字停多久才重排。0.2 是手感和开销的折中：再短等于每敲一键排一次版，
# 再长（0.5+）就能看出"停下来了但它还没跟上"。
const PREVIEW_DEBOUNCE_SEC := 0.2

# 超过这个字符数就不排了，直接给一句提示。
# 排版是 O(n) 的，几 MB 的 txt 每敲一键重排一次会把主线程钉住 —— 宁可明确说
# "太长了不预览"，也不要让程序看起来假死。
const PREVIEW_MAX_CHARS := 120_000

# 手动字号档位，以及默认值（必须**在档位里**，否则弹菜单时没有一个条目是选中的）
const PREVIEW_FONT_SIZES := [12, 14, 16, 18, 20, 22, 24, 28, 32]
const PREVIEW_FONT_DEFAULT := 16

# RichTextLabel 的字体大小是**五个独立的主题项**，各有各的默认值。只改
# normal_font_size 的话，加粗标题会留在 16 而正文变成 24 —— "标题比正文还小"。
# 这不是防御性代码，是实测过的：只覆盖 normal 之后读 bold_font_size，仍然是 16。
const PREVIEW_FONT_ITEMS := [
	"normal_font_size", "bold_font_size", "italics_font_size",
	"bold_italics_font_size", "mono_font_size",
]

# 行距按**字号的倍数**走，不写死像素 —— 写死的话字号一调大，行距相对就变窄了，
# 越调越挤。小说是密排长文，行距要松；Markdown 里块多、留白多，行距要收。
const PREVIEW_LINE_SEP_NOVEL := 0.55
const PREVIEW_LINE_SEP_MARKDOWN := 0.30

# 阅读主题（配色）。**用 preload 而不是裸 class_name**：`--script` 模式的 harness
# 拿的是上一次编辑器扫描的全局类表，新建的脚本不在里面，裸写会报 "Identifier not found"
# 这种看着像真错的假故障（_tmp_verify 文件头记着这条）。preload 在解析期直接从文件走。
const Palette := preload("res://scene/Previewer/PreviewTheme.gd")

# 超长文件那句提示的灰度以前是这里的一个字面量，现在统一走色板（"dim" 键）——
# 它和 MarkdownToBbcode 的 DIM_FG、TextToBbcode 的 BREAK_COLOR 本来就是同一个色值，
# 散成三份的话换主题必然漏两处。

# ---------------- 阅读设置的可选档位 ----------------
#
# **默认值全部等于改动前的行为**，这既让留存 harness 的断言不成片变红，
# 也让"默认外观和以前一样"变成一条能验的事。

# 行距因数：作用在 PREVIEW_LINE_SEP_* 那两个**比例**之上，不是替换它们。
# 直接写死行距像素的话，字号一调大行距相对就变窄了（越调越挤），所以基数必须留给字号。
# 默认 1.0 = 和以前逐字节一样。
const PREVIEW_LINE_SCALES := [0.75, 1.0, 1.25, 1.5, 2.0]
const PREVIEW_LINE_SCALE_DEFAULT := 1.0

# 首行缩进字宽（单位：全角字）。0 = 不缩进。
const PREVIEW_INDENTS := [0, 1, 2, 3, 4]
const PREVIEW_INDENT_DEFAULT := 2

# 阅读宽度（页宽），单位像素。**必须是绝对值、且全部 ≤ 右栏宽度（274）**：
# 按字号推导的话，274px 的栏里绝大多数档位会 clamp 成同一个值，看着像功能坏了（实测见 README）。
# 0 = 全宽（= 改动前的行为）。
const PREVIEW_PAGE_WIDTHS := [0, 180, 220, 260]
const PREVIEW_PAGE_WIDTH_DEFAULT := 0

# 翻页模式。false = 自由滚动（**默认 = 改动前的行为**），true = 一次一屏。
#
# 菜单里的两项。下标 0 = 滚动、1 = 翻页 —— READING_ID_PAGED 那段就是按下标拼 id 的，
# 所以这里的顺序**就是**菜单顺序，和 PREVIEW_PAGE_WIDTHS 同一套约定。
const PREVIEW_PAGED_LABELS: Array[String] = ["滚动", "翻页"]
const PREVIEW_PAGED_DEFAULT := false

# 点击 / 拖拽的分界（像素）。鼠标按下到抬起的位移小于它才算"点击翻页"，
# 超过就是**选字**，交给 RichTextLabel 自己的 selection_enabled 处理，不翻页。
# 取 8 是手抖和真拖拽之间很宽的一段：正常点击的位移是 0～2px，而选字至少要拖十几个像素。
const PREVIEW_CLICK_SLOP := 8.0

# 分页走查的迭代上限。**这是防死循环的兜底，不是正常路径**。
# 段落数与页数都不该超过字符数，所以拿 PREVIEW_MAX_CHARS 当上界刚刚好
# （实测 12 万字符 = 5958 段 / 1192 页，留了两个数量级的余量）。
# 真撞上这个数说明"每页只前进几个像素"，那时候宁可少几页，也不能把主线程钉死。
const PREVIEW_PAGE_WALK_GUARD := PREVIEW_MAX_CHARS

# 阅读设置菜单的 id **分段**。用区间而不是四个独立的连续编号，好处是一眼能判出
# "这个 id 属于哪一项"，判当前档位（_reading_is_current）也不用认识四个菜单对象。
# 段内偏移就是档位表的下标。
#
# ⚠️ 四段**必须互不重叠**：串台不会崩，只会静默打错勾 / 打好几个勾 —— 比崩难查得多。
# 和字号菜单（`_preview_font_menu`）的 0..8 撞了没关系：那是**另一个** PopupMenu，
# 两个菜单的 id 各自独立，永远不会同时进同一个同步函数。
const READING_ID_LINE_SCALE := 0     # 0..4  → PREVIEW_LINE_SCALES
const READING_ID_INDENT := 10        # 10..14 → PREVIEW_INDENTS
const READING_ID_PAGE_WIDTH := 20    # 20..23 → PREVIEW_PAGE_WIDTHS
const READING_ID_SCHEME := 30        # 30..33 → PreviewTheme.NAMES
const READING_ID_PAGED := 40         # 40..41 → PREVIEW_PAGED_LABELS

# 组标题（"行距"、"首行缩进"…）用的保留 id。
#
# ⚠️ **不能图省事用 add_item(label) 的自动 id**：自动 id 是从 **0** 开始的，
# 会正好撞上"行距"那段的 0 号档。而组标题是 disabled 的，撞了**既不报错也点不动**，
# 只会在打勾时拿标题的 id 去索引档位表 —— 静默用错表。
# 取 -2 而不是 -1：-1 是 add_item 的"请自动分配"哨兵值，不是真的能用的 id。
const READING_ID_HEADER := -2

var current_file_path: String = ""
var root_dir: String = ""

@onready var text_edit = $VBC/SpC/SC/TextEdit
@onready var file_tree: Tree = $VBC/SpC/HBC/VBC2/FileTree

# 添加文件对话框节点引用
@onready var file_dialog_save = $FileDialogSave
@onready var file_dialog_open = $FileDialogOpen
@onready var file_dialog_open_dir = $FileDialogOpenDir

# 右键菜单 + 两个确认框
@onready var file_item_menu: PopupMenu = $FileItemMenu
@onready var rename_dialog: ConfirmationDialog = $RenameDialog
@onready var delete_dialog: ConfirmationDialog = $DeleteDialog

# 文件树头部那排「新建」按钮（和 Explorer 标题同一行）
@onready var new_file_button: Button = $VBC/SpC/HBC/VBC2/PC/HBC/NewFileButton
@onready var new_folder_button: Button = $VBC/SpC/HBC/VBC2/PC/HBC/NewFolderButton
# 「收藏当前文件夹」。**这个按钮不是可有可无的便利**：树是 hide_root = true，当前打开的
# 那个目录自己**没有行**，右键永远点不到它 —— 没有这个按钮，当前文件夹根本收藏不了。
@onready var fav_dir_button: Button = $VBC/SpC/HBC/VBC2/PC/HBC/FavDirButton

# 侧边栏那两样：标题，以及左边竖排的两个视图切换按钮。
# 注意 scene 里叫 "Label" 的节点**有两个**（另一个是工具栏上的 "v0.2"），别漏掉 /HBC。
@onready var view_label: Label = $VBC/SpC/HBC/VBC2/PC/HBC/Label
@onready var explorer_button: Button = $VBC/SpC/HBC/VBC/Button
@onready var stars_button: Button = $VBC/SpC/HBC/VBC/Button2
# 左侧竖排的另外两个：上一级 / 前进。场景里叫 Button3 / Button4（没改名，
# 名字是当初放进去时的；对应关系以这两个变量名为准）。
# 它们是**动作**按钮，不是开关 —— 没有"按下态"要显示，和上面那两个 toggle 不一样。
@onready var go_parent_button: Button = $VBC/SpC/HBC/VBC/Button3
@onready var go_forward_button: Button = $VBC/SpC/HBC/VBC/Button4

# ---------------- 预览面板的节点 ----------------
#
# **两个 VBC 重名**，路径别抄错：
#   $VBC/SpC/VBC        ← 右边这一栏（预览）
#   $VBC/SpC/HBC/VBC    ← 左边竖着那排图标按钮
# 下面这些路径里都带 /HBC/，一眼能分辨；不带 HBC 的那两个才是右栏。

# 右栏本身。隐藏它 = 整个预览区收起来、宽度还给编辑器。
@onready var preview_rail: VBoxContainer = $VBC/SpC/VBC
# 右栏所在的 SplitContainer（三个子节点：侧边栏 / 编辑器 / 右栏）
@onready var preview_split: SplitContainer = $VBC/SpC
# 承载渲染结果的那个 RichTextLabel（在 MobileNovelReader 实例里，隔着一层 ScrollContainer）
@onready var preview_rtl: RichTextLabel = $VBC/SpC/VBC/MobileNovelReader/SC/RichTextLabel
# 右栏顶部写着 "Preview" 的标题标签
@onready var preview_title: Label = $VBC/SpC/VBC/PanelContainer/Label
# 右栏顶部那两个按钮
@onready var preview_mode_button: Button = $VBC/SpC/VBC/HFlowContainer/Button2
@onready var preview_font_button: Button = $VBC/SpC/VBC/HFlowContainer/FontSizeButton
# 工具栏上那个 "Preview"（眼睛图标）—— 整栏的开关
@onready var preview_toggle_button: Button = $VBC/PC/HBC/OpenDirButton2

# 防抖 Timer。**在代码里建**（理由见 _setup_preview）：它是用户看不见的管道，
# 没有"长什么样"要落到场景里。
var _preview_timer: Timer
# 两个代码里建的菜单。同理 —— PopupMenu 在场景里也是隐形的，
# 而手写 tscn 加节点要自己编 unique_id，编错就是"点了菜单不出来"。
var _preview_mode_menu: PopupMenu
var _preview_font_menu: PopupMenu

# 用户的**开关意图**（工具栏 Preview 按钮），不等于"右栏此刻可见"：
# 打开一个 .py 时右栏也是不可见的，但那是按扩展名关的，用户切回 .txt 就该自己回来。
var _preview_enabled := true

# 手动指定的预览模式。**粘性**：切文件不重置 —— 用户明确说了"这个当成 Markdown 看"，
# 不该因为换了个文件就忘掉。作用范围见 _effective_preview_mode()。
var _preview_mode_override := PreviewOverride.AUTO

var _preview_font_size := PREVIEW_FONT_DEFAULT

# ---------------- 阅读设置（五项可调，全部持久化） ----------------
#
# 注意这五个的**作用层各不相同**，改一个会牵动不同的东西：
#   * 行距 / 主题 —— 只动 RichTextLabel 的主题项，**不必重跑转换器**
#   * 页宽      —— 只动 ScrollContainer 的尺寸，也不必重跑
#   * 翻页模式  —— 只动 ScrollContainer 的滚动形式和分页表，同样不必重跑
#   * 缩进字宽  —— 落在**输出串**里，必须重跑转换器
# setter 就是按这条分两类的。分错层的症状是"调了没反应"或"每次都白排一遍 12 万字"。
var _preview_line_scale := PREVIEW_LINE_SCALE_DEFAULT
var _preview_indent := PREVIEW_INDENT_DEFAULT
## 页宽的**名义值**（用户选的那个）。实际写给 ScrollContainer 的是它 clamp 到可用宽度后的结果，
## 且 clamp 结果**不写回这里** —— 否则用户把分隔条拖窄一次，他选的页宽就被永久改掉了。
var _preview_page_width := PREVIEW_PAGE_WIDTH_DEFAULT
var _preview_scheme := Palette.Scheme.DEFAULT
var _preview_paged := PREVIEW_PAGED_DEFAULT

# ---------------- 翻页模式的运行态 ----------------
#
# ⚠️ **`_page_index` 是权威页码，绝不从 `scroll_vertical` 反推**。实测（README §7.20 ⑬）：
# 12 万字符的文档末页页首是 861490，而可滚上限只有 861057 —— 引擎会把 `scroll_vertical`
# 夹回上限，于是"反推"在最后一页会算出 倒数第二页，页码**自己往回跳**。
# 反推只在**表刚重建**时做一次（_ensure_pages），用来接住"重排前读到哪儿了"。

## 页码条。`null` = 还没建（_setup_preview 里建，所以不是 @onready）。
var _page_bar: HBoxContainer
var _page_label: Label
var _page_prev_button: Button
var _page_next_button: Button

## 每一页的页首像素 Y。**空 = 作废**（_invalidate_pages）。
var _page_tops := PackedInt32Array()
## 算 _page_tops 时用的视口高。和 _page_tops 配对校验：高度变了表就得重算。
var _page_height := 0
var _page_index := 0
## 延迟合并用的标志，见 _queue_page_refresh()。
var _page_refresh_queued := false
## 重排后要回到的页号，-1 = 没有待办。见 _render_preview 尾部。
var _keep_page_pending := -1

## 左键按下的落点，用来分"点击"和"拖选"。
var _click_pos := Vector2.ZERO
var _click_arming := false
## 待执行的翻页方向，0 = 没有。见 _resolve_pending_turn()。
var _pending_turn := 0
## 这一帧里 meta_clicked 来过没有。**必须延迟一步才读得到**，见 _resolve_pending_turn()。
var _preview_meta_clicked_frame := false

# 章节目录。**普通成员变量，不能 @onready** —— @onready 在 _ready() 之前求值，
# 而这两个节点是 _setup_preview() 里现建的，那时候还不存在。
var _toc_tree: Tree
var _toc_toggle_button: Button
var _reading_button: Button
var _reading_menu: PopupMenu
## 当前渲染出的章节。**存在的意义是"比一比，没变就别重建目录"**：
## 防抖路径每 200ms 走一遍渲染，而打字时章节根本不会变，不比较就会每 200ms
## 重建一次列表（看得见的抖动 + 白烧 CPU）。目录**数据**是同一次转换免费带出来的，
## 只有**建 UI 列表**这一步是有成本的。
var _chapters: Array = []

# 藏右栏之前存下的 split_offsets。**必须先存再藏**，见 _set_preview_rail_visible()。
var _preview_saved_split_offsets := PackedInt32Array()

# 右键菜单项 id。用枚举而不是裸数字，加/删菜单项时不用回来数顺序。
# 新项一律**追加在末尾**：插在中间会让后面所有 id 整体 +1，而 README §2 坑 12 / §7.16
# 里记着 id=4 这类硬编码数字，将来照着调试会踩成"看着像功能坏了"的假故障。
# 菜单的**显示顺序**由 add_item() 的调用顺序决定，和 id 数值无关。
enum MenuId {
	NEW_FILE,               # 新建文件，只对目录出现
	NEW_FOLDER,             # 新建文件夹，只对目录出现
	OPEN_WITH_DEFAULT,      # 用系统默认程序打开，只对不支持编辑的文件出现
	OPEN_IN_FILE_MANAGER,
	RENAME,
	DELETE,
	COPY_PATH,
	REFRESH,
	FAVORITE,               # 收藏 / 取消收藏，两棵树都出现
}

# 右栏此刻渲染的是什么。NONE = 右栏整个收起来。
# 和 MenuId 一样，新成员一律**追加在末尾**：插在中间会让后面的值整体 +1。
enum PreviewMode { NONE, NOVEL, MARKDOWN }

# 用户手动指定的模式。**多一个 AUTO**，所以它和 PreviewMode 不能是同一个枚举 ——
# 拿 PreviewMode.NONE 兼职"自动"的话，就没法表达"用户明确要求不预览"了。
enum PreviewOverride { AUTO, NOVEL, MARKDOWN }

# ---------------- 收藏夹 ----------------

# 收藏列表那棵树。**在代码里建**（理由见 _setup_fav_tree），所以它是普通成员变量 ——
# 不能写成 @onready：@onready 在 _ready() 之前求值，那时候这个节点还不存在。
var fav_tree: Tree
# 收藏的绝对路径，顺序 = 用户收藏的先后（列表就按这个顺序显示）。
# 这是内存里的**唯一真源**：树是从它重建出来的，落盘也是把它整个写进存档资源。
var _favorites: Array[String] = []
# 现在侧边栏显示的是不是收藏视图
var _fav_view: bool = false

# 前进栈：按「上一级」时把**离开的那个目录**压进来，按「前进」再弹出去。
# 只由这一对按钮维护 —— 其他任何换根方式都会清空它（见 set_root_dir 的 keep_forward）。
# 理由是"从别处跳到一个新目录"等于在导航历史里分了个叉：旧的前进目标已经不该再回去了，
# 不清的话 OpenDir 之后按「前进」会跳回一个和当前上下文不相干的目录。
# 浏览器的地址栏是同一个行为。
var _nav_forward: Array[String] = []
# 当前弹出的那个右键菜单是冲着哪棵树弹的（file_tree 或 fav_tree）。
# 菜单是共用的同一个，_build_item_menu / _on_menu_window_input 都要靠它认上下文。
var _menu_source: Tree
# 存档不可用时的告警只弹一次，不然每收藏一个就弹一条
var _save_warned: bool = false

# 当前右键目标（弹菜单时记下，点菜单项时用）
var _menu_path: String = ""
var _menu_is_dir: bool = false
# 这一轮点击里已经切换过展开状态的目录路径，用来给双击去重：
# Tree 把双击拆成"第一下当普通单击 + 第二下发 item_activated"，
# 而第一下切没切取决于那一刻条目是否已被选中，所以第二下得靠这个变量判断。
# 每次左键按下（双击的第二下除外）由 gui_input 清空。
var _toggled_path: String = ""
# 程序化选中（_select_tree_item_for_path）期间，屏蔽掉"目录被选中 = 切换展开状态"这个副作用。
# 不加这个开关的话：重命名一个目录会把它翻成折叠的（里面的文件当场从树里消失），
# 新建文件夹则会得到一个"刚建出来就是折叠"的目录 —— 都是 select() 发 item_selected 惹的。
# 只在这一个函数里、只围着一句 select(0) 有效，见那里的注释。
var _suppress_dir_toggle: bool = false
# 重命名对话框里的输入框，代码创建 —— AcceptDialog 会把子节点收进自己的内容区，
# 手写 tscn 布局容易对不上
var _rename_edit: LineEdit

# 新建文件的对话框（同样代码创建，理由见 _open_as_text_dialog 那边的注释）
var _new_file_dialog: ConfirmationDialog
var _new_file_edit: LineEdit
# 新建文件的目标目录。**在这里存一份**，不要等确认时再去读 _menu_path ——
# 弹框期间用户还能右键别的条目，_menu_path 会跟着变，那样新文件可能落到别处去。
var _new_file_dir: String = ""

# 新建文件夹的那一套，和上面完全对称
var _new_folder_dialog: ConfirmationDialog
var _new_folder_edit: LineEdit
var _new_folder_dir: String = ""

# 双击不支持编辑的文件时的"强制按文本打开"提醒框。
# 同样在代码里建：main.tscn 里这排 AcceptDialog 的节点都带 unique_id，
# 手写 tscn 容易把那个 id 写错或写重，交给 Godot 自己保存场景时落盘更安全。
var _open_as_text_dialog: ConfirmationDialog
# 提醒框确认后要打开的那个文件
var _pending_open_path: String = ""

var font_size=20

func _ready():
	_setup_explorer_buttons()
	_setup_file_tree()
	# 收藏树必须排在 _setup_file_tree() 之后：条目的图标是在那边备好的（_icon_dir/_icon_file/
	# _icon_unsupported），先建的话行里会没图标，而且不报错。
	_setup_fav_tree()
	# 同理，也排在上面那个命令行参数循环之前 —— 启动时就带一个文件时，_ready() 里那句
	# open_and_show 会顺着信号链碰到视图相关的东西，得保证 fav_tree 已经在了。
	_setup_view_buttons()
	# 上一级 / 前进。排在命令行参数循环**之前**：没有参数时（正常启动）它们就该是禁用的，
	# 而那一次设置由 _setup_nav_buttons() 尾巴上的 _update_nav_buttons() 完成；
	# 带参数启动时 open_and_show() → set_root_dir() → refresh_file_tree() 会再刷一次。
	_setup_nav_buttons()
	# 预览必须排在下面那个命令行参数循环**之前**：带一个 .txt 启动时，
	# open_and_show() 里那句 _update_preview() 会立刻要读 preview_rtl 和防抖 Timer，
	# 那时候它们得已经在了（同 _setup_fav_tree 排在前面的理由）。
	_setup_preview()

	# 取命令行传入的第一个真实文件。
	# 「打开方式」传的是裸参数（get_cmdline_args），带 `--` 的调用 / 编辑器「启动参数」
	# 则落在 user_args 里，所以两边都读。
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("-"):
			continue          # 跳过 --path 之类的引擎参数
		if a.begins_with("res://") or a.begins_with("user://"):
			continue          # 侧边栏浏览的是真实文件系统，虚拟路径不认
		if not FileAccess.file_exists(a):
			continue          # 编辑器里运行时混进来的非文件参数
		# 和侧边栏同一条规矩：不支持编辑的类型不往编辑器里载。
		# 「打开方式」里把本编辑器设成默认程序时也会走到这里，
		# 真载进来就是二进制乱码，再一保存就把原文件覆盖了。
		if not _is_editable_file(a):
			continue
		open_and_show(a)
		break             # 只认第一个，避免被后面的参数覆盖

	text_edit.grab_focus()

	# 连接文件对话框信号
	file_dialog_save.file_selected.connect(_on_save_as_file_selected)
	file_dialog_open.file_selected.connect(_on_open_file_selected)
	file_dialog_open_dir.dir_selected.connect(_on_open_dir_selected)

	_setup_item_menu()

func _process(delta: float) -> void:
	$VBC/PC2/HBC/Label3.text = str(text_edit.text.length())

func open_and_show(path: String) -> void:
	# 统一成 set_root_dir 用的规范形式（正斜杠、无 ./ 和 ../），
	# 否则和树里 metadata 存的路径对不上，选中定位会失效
	path = path.replace("\\", "/").simplify_path()

	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		OS.alert("打开失败：" + path)
		return

	text_edit.text = f.get_as_text()
	current_file_path = path
	$VBC/PC/HBC/Label4.text = current_file_path

	# 用打开的文件反推根目录，但只在文件位于当前树之外时才重定。
	# 这样 OpenDir 选定一个目录后，点树里的文件不会把树缩到文件所在的那层子目录去；
	# 而空树启动、或用 Ctrl+O 打开别处的文件时，树依然会跟过去。
	if path.is_absolute_path() and not _is_under(path, root_dir):
		set_root_dir(path.get_base_dir())
	_select_tree_item_for_path(path)
	# 放在最后：上面那句 set_root_dir 会重建文件树，先把文件本身安顿好再刷预览，
	# 免得中途从编辑器读到的还是上一份文本。
	_update_preview()

# path 是否位于 dir 之内（或就是 dir）。两边都按 set_root_dir 的规范形式比较：
# 正斜杠、无结尾斜杠。
func _is_under(path: String, dir: String) -> bool:
	if dir == "":
		return false
	return path == dir or path.begins_with(dir + "/")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_save") or \
	   (event is InputEventKey and event.keycode == KEY_S and event.pressed and \
		(Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META))):
		save_file()
		get_viewport().set_input_as_handled()
	# 新增：快速另存为 Ctrl+Shift+S
	if event is InputEventKey and event.keycode == KEY_S and event.pressed and \
	   (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)) and \
	   Input.is_key_pressed(KEY_SHIFT):
		_on_save_as_button_pressed()
		get_viewport().set_input_as_handled()

	# 新增：快速打开 Ctrl+O
	if event is InputEventKey and event.keycode == KEY_O and event.pressed and \
	   (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)):
		_on_open_pressed()
		get_viewport().set_input_as_handled()

	if event.is_action_pressed("f11"):
		$VBC/PC.visible = not $VBC/PC.visible
		$VBC/PC2.visible = not $VBC/PC2.visible

	if Input.is_action_pressed("zoom_down"):
		if font_size>1:
			font_size-=1
		text_edit.add_theme_font_size_override("font_size",font_size)
	if Input.is_action_pressed("zoom_up"):
		if font_size<100:
			font_size+=1
		text_edit.add_theme_font_size_override("font_size",font_size)
	if Input.is_action_just_pressed("map"):
		text_edit.minimap_draw=not text_edit.minimap_draw
func _on_save_button_pressed() -> void:
	save_file()

func save_file():
	if current_file_path == "":
		OS.alert("没有打开任何文件")
		return

	var f = FileAccess.open(current_file_path, FileAccess.WRITE)
	if f:
		f.store_string(text_edit.text)   # 统一使用 text_edit
		DMessageManager.add_top_message("保存成功")
	else:
		OS.alert("保存失败：" + str(FileAccess.get_open_error()))

# 另存为按钮 - 弹出保存文件对话框
func _on_save_as_button_pressed() -> void:
	file_dialog_save.popup_centered(Vector2i(600, 400))

# 另存为对话框选择文件后的处理
func _on_save_as_file_selected(path: String) -> void:
	# 工具栏是和视图无关的，在收藏视图下按它必须看得见结果，
	# 否则选中项在**藏起来的**那棵树里被改掉，用户只会觉得"点了没反应"。
	_set_view(false)
	path = path.replace("\\", "/")
	current_file_path = path
	$VBC/PC/HBC/Label4.text = current_file_path

	var f = FileAccess.open(current_file_path, FileAccess.WRITE)
	if f == null:
		OS.alert("保存失败：" + str(FileAccess.get_open_error()))
		return
	f.store_string(text_edit.text)

	# 存进当前根目录就刷新树，让新文件立刻出现
	if path.get_base_dir() == root_dir:
		refresh_file_tree()
	_select_tree_item_for_path(path)
	# 另存为**能换扩展名**（a.txt → a.md），预览模式跟着扩展名走，所以要重刷。
	_update_preview()

# 打开按钮 - 弹出打开文件对话框
func _on_open_pressed() -> void:
	file_dialog_open.popup_centered(Vector2i(600, 400))

# 打开对话框选择文件后的处理
func _on_open_file_selected(path: String) -> void:
	_set_view(false)          # 同上：工具栏按钮的结果必须看得见
	open_and_show(path)

# OpenDir 按钮 - 弹出选择目录对话框
func _on_open_dir_pressed() -> void:
	file_dialog_open_dir.popup_centered(Vector2i(600, 400))

# 选定目录后的处理：只换树根，不动当前打开的文件
func _on_open_dir_selected(path: String) -> void:
	_set_view(false)          # 同上；这里尤其明显 —— 收藏视图下换根，画面上什么都没发生
	set_root_dir(path)

# ---------------- 条目右键菜单 ----------------

func _setup_item_menu() -> void:
	file_item_menu.id_pressed.connect(_on_menu_id_pressed)
	# 菜单开着时的输入只能从菜单这边拿（原因见 _on_menu_window_input）
	file_item_menu.window_input.connect(_on_menu_window_input)

	# 重命名输入框
	_rename_edit = LineEdit.new()
	_rename_edit.custom_minimum_size = Vector2(360, 0)
	rename_dialog.add_child(_rename_edit)
	rename_dialog.register_text_enter(_rename_edit)   # 输入框里回车 = 点确定
	rename_dialog.confirmed.connect(_on_rename_confirmed)

	delete_dialog.confirmed.connect(_on_delete_confirmed)

	# 新建文件的输入框和弹框。和重命名那条一样：AcceptDialog 会把子节点收进
	# 自己的内容区，所以输入框代码里 new 出来塞进去。
	_new_file_dialog = ConfirmationDialog.new()
	_new_file_dialog.title = "新建文件"
	_new_file_dialog.ok_button_text = "新建"
	_new_file_dialog.cancel_button_text = "取消"
	_new_file_dialog.min_size = Vector2i(420, 130)
	_new_file_edit = LineEdit.new()
	_new_file_edit.custom_minimum_size = Vector2(360, 0)
	_new_file_dialog.add_child(_new_file_edit)
	_new_file_dialog.register_text_enter(_new_file_edit)   # 输入框里回车 = 点确定
	_new_file_dialog.confirmed.connect(_on_new_file_confirmed)
	add_child(_new_file_dialog)

	# 新建文件夹：除了标题、按钮文案和默认名，其余和上面那份一模一样
	_new_folder_dialog = ConfirmationDialog.new()
	_new_folder_dialog.title = "新建文件夹"
	_new_folder_dialog.ok_button_text = "新建"
	_new_folder_dialog.cancel_button_text = "取消"
	_new_folder_dialog.min_size = Vector2i(420, 130)
	_new_folder_edit = LineEdit.new()
	_new_folder_edit.custom_minimum_size = Vector2(360, 0)
	_new_folder_dialog.add_child(_new_folder_edit)
	_new_folder_dialog.register_text_enter(_new_folder_edit)
	_new_folder_dialog.confirmed.connect(_on_new_folder_confirmed)
	add_child(_new_folder_dialog)

func _on_file_tree_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return

	# 左键按下 = 一轮新点击的开始，把"这一轮已经切过哪个目录"的记账清掉。
	# 只能在这里清：双击的两下之间不会再有任何信号，只有在按下那一刻清，
	# 第二下才判断得出第一下到底切没切（见 _on_file_tree_item_activated）。
	# 双击的第二下（double_click = true）**不能清**，否则正好把要判断的东西抹掉了。
	if event.button_index == MOUSE_BUTTON_LEFT:
		if not event.double_click:
			_toggled_path = ""
		return

	if event.button_index != MOUSE_BUTTON_RIGHT:
		return

	# 用 event.position（Tree 局部坐标）换算成视口坐标去查条目，而不是读 get_selected()：
	# 右键点在空处时选中项还停在原来那个条目上，读选中项会弹出上一个文件的菜单。
	# 用 event.position 而不是读实时鼠标位置：真实点击时两者本就一致，
	# 但这样不依赖"弹菜单那一刻鼠标还在原地"。
	_open_item_menu_at(file_tree.get_global_position() + event.position, file_tree)

# 在**视口坐标**的 pos 处把条目菜单弹出来。空处不弹（什么也不做）。
# 三个入口都走这里：两棵树的 gui_input（第一次右键），以及菜单自己的 window_input
# （菜单开着时的右键 —— 那种情况下主视口收不到输入，见 _on_menu_window_input）。
# tree 是"冲着哪棵树弹的"：菜单只有**一个**（file_item_menu），收藏列表复用它 ——
# 那套丝滑逻辑（关旧开新、点外面穿透）和"哪棵树"无关，它只看菜单自己的 position/size，
# 树只影响这里的命中测试和菜单项内容。
func _open_item_menu_at(vp_pos: Vector2, tree: Tree) -> void:
	if tree == null:
		return
	# 点在树外面（编辑区、工具栏）就别弹了
	if not tree.get_global_rect().has_point(vp_pos):
		return
	var item := tree.get_item_at_position(vp_pos - tree.get_global_position())
	var path := _item_path(item)
	if path == "":
		return      # 点到空白处，或 "未指定目录" / "还没有收藏" 占位条目

	_menu_path = path
	_menu_is_dir = _item_is_dir(item)
	# 过了上面所有守卫才记上下文：半路 return 的话 _menu_source 必须还是上一轮那个，
	# 否则 _on_menu_window_input 里的 call_deferred 会拿它去弹错树。
	_menu_source = tree
	_build_item_menu()

	# 必须显式给坐标：Godot 4 的无参 popup() 弹在 (0,0)，不读鼠标位置
	# （那是 Godot 3 的行为，别按老文档想当然）。
	# 实测 popup(rect) 的 rect 吃的是**视口局部坐标**，和上面算 vp_pos 用的是同一套。
	file_item_menu.popup(Rect2i(Vector2i(vp_pos), Vector2i.ZERO))

# 菜单开着的时候，主视口**收不到任何输入** —— 嵌入式子窗口会把事件全吞掉，
# 只转发到它自己的视口（实测：主视口那边连一次 gui_input 都不发，见 README §7.16）。
# 所以"在菜单外面又点了一下"这件事，只有菜单自己能告诉我们，window_input 就是那个口子。
# 不接它的话症状就是用户说的那个：右键一个条目弹出菜单后，再右键别的条目**没反应**
# （菜单还开着，也不换目标），得先左键点一下把菜单关掉再来 —— 就是"不丝滑"。
func _on_menu_window_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return

	# 点在菜单**里面**是"选条目"，交回给菜单自己处理，别插手
	if Rect2(Vector2.ZERO, file_item_menu.size).has_point(mb.position):
		return

	# event.position 是菜单**局部**坐标，加上菜单位置才是视口坐标
	# （实测菜单局部 (0,-61.5) + 菜单在 (172,151) = 当初点下去的那个 (172,89.5)）
	var vp_pos := Vector2(file_item_menu.position) + mb.position
	file_item_menu.hide()

	if mb.button_index != MOUSE_BUTTON_RIGHT:
		# 左键点外面：关掉菜单就完事 —— **但不必手动补发点击**。实测这一下会自己
		# 继续走到主视口上：菜单一藏，同一个按下事件就落到它盖着的那一行，
		# 该载入的载入、该展开的展开（跟没开菜单时点它一模一样，也和 VS Code 一致）。
		# 这里什么都别做，多做一步反而变成"点一下触发两次"。
		return

	# 左键在上面就 return 了，所以这里只可能是右键：关掉旧菜单，**就着这一下**
	# 把新菜单弹出来 —— 一次右键既关旧的又开新的，这才是"丝滑"。
	# call_deferred 不要顺手改成同步调用：这次 window_input 是菜单**正在处理这一轮输入**
	# 的过程中发出来的，同步 popup 会被这一轮的收尾搅掉，延后到帧末才稳（这一版实测 44 条断言全过）。
	# 另外更正一个曾经写在这里的说法：引擎**不会**自己把这个菜单关掉，
	# 早先日志里那句 popup_hide 是本函数上面自己的 hide() 发的，见 README §7.16。
	# call_deferred 的参数在**调用那一刻**求值，所以这里传的 _menu_source 正是本轮菜单
	# 所属的那棵树（此刻菜单还没被换掉）。别顺手改成传个字面量。
	_open_item_menu_at.call_deferred(vp_pos, _menu_source)

func _build_item_menu() -> void:
	file_item_menu.clear()

	# 收藏列表是另一个上下文，菜单项另起一套（理由见 _build_fav_item_menu）
	if _menu_source == fav_tree:
		_build_fav_item_menu()
		return

	# 菜单项 id 走枚举，所以在这里按条件增删不会影响别的项。
	# 「新建文件」只对目录出现 —— 文件条目的上下文里"新建"没有说得通的目标目录。
	# 放最上面是跟着资源管理器的习惯。
	if _menu_is_dir:
		file_item_menu.add_item("新建文件", MenuId.NEW_FILE)
		file_item_menu.add_item("新建文件夹", MenuId.NEW_FOLDER)
		file_item_menu.add_separator()
	# 「用默认程序打开」只对"看得见但本编辑器打不开"的文件才有意义：
	# 目录用「在文件管理器中打开」就够了，可编辑的文件本来就单击即开。
	elif not _is_editable_file(_menu_path):
		file_item_menu.add_item("用默认程序打开", MenuId.OPEN_WITH_DEFAULT)
		file_item_menu.add_separator()
	file_item_menu.add_item("在文件管理器中打开", MenuId.OPEN_IN_FILE_MANAGER)
	# 收藏 / 取消收藏是同一条目上的两态。文案跟着**当前状态**走，
	# 用户扫一眼就知道点下去是加还是减，不用去猜。
	file_item_menu.add_item("取消收藏" if _is_favorite(_menu_path) else "收藏", MenuId.FAVORITE)
	file_item_menu.add_separator()
	file_item_menu.add_item("重命名", MenuId.RENAME)
	file_item_menu.add_item("删除", MenuId.DELETE)
	file_item_menu.add_separator()
	file_item_menu.add_item("复制完整路径", MenuId.COPY_PATH)
	file_item_menu.add_item("刷新文件树", MenuId.REFRESH)

# 收藏列表里的右键菜单。这里只给「取消收藏」+「在文件管理器中打开」：
# 重命名 / 删除这些在收藏视图里操作的是**文件系统上的真实文件**，
# 而用户点的时候心里想的是"这个收藏"，极易误删 —— 真要用，去 Explorer 视图里点。
func _build_fav_item_menu() -> void:
	file_item_menu.add_item("取消收藏", MenuId.FAVORITE)
	file_item_menu.add_separator()
	file_item_menu.add_item("在文件管理器中打开", MenuId.OPEN_IN_FILE_MANAGER)

	# 路径不存在时判断不出它当初是文件还是目录，shell_show_in_file_manager 会失败，
	# 而框架那边失败就 OS.alert —— 那东西在 Windows 上是**阻塞**的（README §7.8）。
	# 所以直接禁掉这一项；「取消收藏」必须留着，那是用户唯一的出路。
	if not _path_exists(_menu_path):
		var idx := file_item_menu.get_item_index(MenuId.OPEN_IN_FILE_MANAGER)
		if idx >= 0:
			file_item_menu.set_item_disabled(idx, true)

func _on_menu_id_pressed(id: int) -> void:
	match id:
		MenuId.NEW_FILE:
			_prompt_new_file()
		MenuId.NEW_FOLDER:
			_prompt_new_folder()
		MenuId.OPEN_WITH_DEFAULT:
			var err := OS.shell_open(_menu_path)
			if err != OK:
				OS.alert("打开失败：" + error_string(err))
		MenuId.OPEN_IN_FILE_MANAGER:
			# 目录直接进去，文件在父目录里选中它
			var err := OS.shell_show_in_file_manager(_menu_path, _menu_is_dir)
			if err != OK:
				OS.alert("打开文件管理器失败：" + error_string(err))
		MenuId.RENAME:
			_prompt_rename()
		MenuId.DELETE:
			_prompt_delete()
		MenuId.COPY_PATH:
			DisplayServer.clipboard_set(_menu_path)
		MenuId.REFRESH:
			refresh_file_tree()
		MenuId.FAVORITE:
			# 两棵树的菜单共用这一个 id：都是"把 _menu_path 这个目标的收藏状态翻一下"
			_toggle_favorite(_menu_path)

# ---------------- 新建文件 ----------------

# 右键菜单进来的：目标是右键的那个目录
func _prompt_new_file() -> void:
	_prompt_new_file_in(_menu_path)

func _prompt_new_file_in(dir: String) -> void:
	# 目标目录在这里就定下来。弹框期间用户还能右键别的条目、把 _menu_path 改掉，
	# 等确认时再读就不是当初右键的那个目录了。
	_new_file_dir = dir
	var default_name := _default_new_file_name(_new_file_dir)
	_new_file_edit.text = default_name
	# 弹框里显示目录名而不是完整路径 —— 就是用户刚右键的那个，够认了
	_new_file_dialog.dialog_text = "在「%s」里新建文件：" % _new_file_dir.get_file()
	_new_file_dialog.popup_centered()
	_new_file_edit.grab_focus()
	_select_base_name_in(_new_file_edit)

# 默认名。撞名就依次试「新建文件 (2).txt」这种，别让用户一打开弹框就先吃一个
# "已存在同名文件"。上限纯粹是防死循环的保险，正常目录撞不到 1000 个。
func _default_new_file_name(dir: String) -> String:
	const BASE := "新建文件"
	const EXT := ".txt"
	var candidate := BASE + EXT
	var i := 2
	while FileAccess.file_exists(dir.path_join(candidate)) or \
		  DirAccess.dir_exists_absolute(dir.path_join(candidate)):
		candidate = "%s (%d)%s" % [BASE, i, EXT]
		i += 1
		if i > 999:
			break
	return candidate

func _on_new_file_confirmed() -> void:
	var dir := _new_file_dir
	var name := _new_file_edit.text.strip_edges()

	var reason := _validate_name_in_dir(dir, name)
	if reason != "":
		OS.alert(reason)
		return

	var new_path := dir.path_join(name)
	var f := FileAccess.open(new_path, FileAccess.WRITE)
	if f == null:
		OS.alert("新建失败：" + str(FileAccess.get_open_error()))
		return
	f.close()     # 建完立刻关掉，别让句柄一直挂着

	refresh_file_tree()
	# 注意：这个助手会把新文件**载入编辑器**（它内部的 TreeItem.select() 会发
	# item_selected，而那个信号的处理就是载入文件）。这是有意的，不是副作用失控 ——
	# 本应用靠这条链子维持一个不变量：**树里的选中项和编辑器里的内容永远一致**，
	# 另存为 / Ctrl+O 也都走它。不载入的话，用户新建完直接打字，敲进去的其实是
	# 上一个还开着的文件，然后 Ctrl+S 就把它覆盖了。
	_select_tree_item_for_path(new_path)

# ---------------- 新建文件夹 ----------------

# 右键菜单进来的：目标是右键的那个目录
func _prompt_new_folder() -> void:
	_prompt_new_folder_in(_menu_path)

func _prompt_new_folder_in(dir: String) -> void:
	_new_folder_dir = dir
	_new_folder_edit.text = _default_new_folder_name(_new_folder_dir)
	_new_folder_dialog.dialog_text = "在「%s」里新建文件夹：" % _new_folder_dir.get_file()
	_new_folder_dialog.popup_centered()
	_new_folder_edit.grab_focus()
	# 文件夹名没有扩展名，_select_base_name_in 里的 get_basename() 会原样返回整个名字，
	# 于是全选 —— 正是想要的，直接打字就整体替换。
	_select_base_name_in(_new_folder_edit)

# 和 _default_new_file_name 同一套逻辑，只是没有扩展名
func _default_new_folder_name(dir: String) -> String:
	const BASE := "新建文件夹"
	var candidate := BASE
	var i := 2
	while FileAccess.file_exists(dir.path_join(candidate)) or \
		  DirAccess.dir_exists_absolute(dir.path_join(candidate)):
		candidate = "%s (%d)" % [BASE, i]
		i += 1
		if i > 999:
			break
	return candidate

func _on_new_folder_confirmed() -> void:
	var dir := _new_folder_dir
	var name := _new_folder_edit.text.strip_edges()

	var reason := _validate_name_in_dir(dir, name)
	if reason != "":
		OS.alert(reason)
		return

	var new_path := dir.path_join(name)
	# make_dir_absolute 只建一层，父目录必须已经在 —— 这里正合适：父目录就是用户
	# 刚点的那个目录，一定存在。不走 DirAccess.make_dir_recursive_absolute，
	# 那会把名字里带 / 的路径整个建出来（校验已经挡了 /，但少一层依赖更稳）。
	var err := DirAccess.make_dir_absolute(new_path)
	if err != OK:
		OS.alert("新建文件夹失败：" + error_string(err))
		return

	refresh_file_tree()
	# 选中新建的文件夹（顺便逐级展开它的祖先链），让用户看得见建出来的东西。
	# 这里不用管展开状态：_select_tree_item_for_path 已经屏蔽了"选中目录 = 切换展开"，
	# 新目录保持默认的折叠态 —— 懒加载之下那也就是"还没建下一层"，
	# 反正刚建出来的文件夹是空的，展开也看不到东西。
	_select_tree_item_for_path(new_path)

# ---------------- 文件树头部那排按钮（新建文件 / 新建文件夹 / 收藏当前文件夹） ----------------

func _setup_explorer_buttons() -> void:
	new_file_button.pressed.connect(_on_new_file_button_pressed)
	new_folder_button.pressed.connect(_on_new_folder_button_pressed)
	# toggle_mode 只为把"当前文件夹已经收藏了"显示出来。连 pressed 而不是 toggled：
	# toggled 在状态没变时可能根本不发。回调里不去读按钮自己的状态 ——
	# 状态是 _update_fav_dir_button() 用 set_pressed_no_signal() 同步过去的，
	# 读它就等于让显示反过来决定行为（和两个视图按钮同一个道理）。
	fav_dir_button.toggle_mode = true
	fav_dir_button.pressed.connect(_on_fav_dir_button_pressed)
	_update_new_buttons()

# 头部按钮的目标目录 = **当前打开的这个文件夹**（root_dir），不看树里的选中项。
# 这套按钮的语义是"往我现在打开的文件夹里放东西"，跟位置无关 —— 选中谁都不该改变它，
# 否则"我明明开着 A 目录，东西却跑进选中的子目录里了"。
# 想放进某个子目录就走那个子目录的右键菜单（右键 → 新建文件 / 新建文件夹）：
# 那里有明确的"对着谁操作"的上下文，比这里靠选中项猜要可靠。
func _new_target_dir() -> String:
	return root_dir

# 现在到底有没有"打开着的那个文件夹"。头部这排按钮全都以它为操作对象，所以共用这一个判断。
func _has_open_dir() -> bool:
	return root_dir != "" and DirAccess.dir_exists_absolute(root_dir)

# 一个目录都没打开的时候把两个按钮禁掉。
# 这不只是"灰着好看"：那种状态下 root_dir 是空串，path_join 出来是个**相对路径**，
# 新建会落到进程的工作目录里去 —— 用户根本不知道文件建到哪儿了。
func _update_new_buttons() -> void:
	var can := _has_open_dir()
	new_file_button.disabled = not can
	new_folder_button.disabled = not can

# 没收藏时那颗星星的灰度。**光靠 toggle 那层"按下"底色是看不出来的** ——
# 实测（两张截图逐像素比）按下只让按钮背景从 (40,42,43) 变成 (32,34,35)，差 15/255，
# 一屏图标里根本认不出来。而这个按钮是个**开关**，再点一下就是取消收藏：
# 状态看不出来的话，用户会点第二下把自己刚存的收藏悄悄删掉。
# 用 modulate 染灰而不是再切一张图：主题里普通状态的底色几乎是透明的，乘上去看不出来。
const FAV_DIR_OFF_TINT := Color(0.45, 0.45, 0.45, 1.0)

# 收藏按钮的可用状态 + 按下态 + 图标明暗 + tooltip，全都只看两样东西：root_dir 和 _favorites。
# **挂钩点只有三处**：refresh_file_tree()（换根目录 / 有没有目录，跟着 _update_new_buttons 走）、
# _setup_fav_tree()（那时收藏才读进来）、_toggle_favorite()（收藏状态变了）。
# 挂漏一处的症状就是"按钮显示的和实际状态对不上"。
func _update_fav_dir_button() -> void:
	var can := _has_open_dir()
	fav_dir_button.disabled = not can
	var faved := can and _is_favorite(root_dir)
	# 禁用时也要把按下态和亮星星清掉：不禁的话，开着收藏过的 A 目录 → 关掉目录 →
	# 按钮还亮着，看着像"还开着个收藏过的文件夹"
	fav_dir_button.set_pressed_no_signal(faved)
	fav_dir_button.modulate = Color.WHITE if faved else FAV_DIR_OFF_TINT
	if not can:
		fav_dir_button.tooltip_text = "收藏当前文件夹（先打开一个文件夹）"
	elif faved:
		fav_dir_button.tooltip_text = "已收藏当前文件夹，点击取消"
	else:
		fav_dir_button.tooltip_text = "收藏当前文件夹"

func _on_new_file_button_pressed() -> void:
	_prompt_new_file_in(_new_target_dir())

func _on_new_folder_button_pressed() -> void:
	_prompt_new_folder_in(_new_target_dir())

# 目标恒为 root_dir，和「新建文件 / 新建文件夹」同源（理由见 _new_target_dir）：
# 这排按钮说的都是"我现在打开的这个文件夹"，跟树里选中谁无关。
func _on_fav_dir_button_pressed() -> void:
	_toggle_favorite(_new_target_dir())

# ---------------- 重命名 ----------------

func _prompt_rename() -> void:
	rename_dialog.dialog_text = "输入新的" + ("文件夹名" if _menu_is_dir else "文件名")
	_rename_edit.text = _menu_path.get_file()
	rename_dialog.popup_centered()
	_rename_edit.grab_focus()
	_select_base_name()

# 重命名弹框里预选名字。目录没有扩展名，全选。
func _select_base_name() -> void:
	if _menu_is_dir:
		_rename_edit.select_all()
		return
	_select_base_name_in(_rename_edit)

# 只选中主名、不含扩展名，直接输入就能整体覆盖，又不用手动删掉 ".txt"。
# 新建文件也走这个，所以默认名是 "新建文件.txt" 时，用户一打字就把"新建文件"
# 整个替换掉、".txt" 后缀留着 —— 这就是那句"默认 txt"落到实处的地方。
func _select_base_name_in(edit: LineEdit) -> void:
	var base := edit.text.get_basename()
	edit.select(0, base.length())
	edit.caret_column = base.length()

# 校验新名称能不能用。返回 "" 表示可用，否则返回给用户看的原因。
# 单独拆出来是为了不起弹窗也能测 —— OS.alert 在 Windows 上是阻塞的，
# 埋在里面的分支没法从脚本里驱动。
func _validate_new_name(old_path: String, new_name: String) -> String:
	return _validate_name_in_dir(old_path.get_base_dir(), new_name)

# 校验 new_name 能不能落在 dir 这个目录里。重命名 / 新建文件 / 新建文件夹
# 共用同一套规则（目标目录 / 空名 / 非法字符 / 撞名），拆出来是为了三边不会各自长歪。
func _validate_name_in_dir(dir: String, new_name: String) -> String:
	if dir == "":
		# 兜底：没有目标目录时 path_join 出来是个相对路径，写入会落到进程的工作目录，
		# 用户根本找不到自己刚建的东西。正常流程走不到这儿（按钮会禁用、菜单也不会弹），
		# 但这条错误值得在这里挡一次，毕竟代价是"文件消失在一个没人知道的地方"。
		return "没有可用的目标目录"
	if new_name == "":
		return "名称不能为空"
	if new_name.contains("/") or new_name.contains("\\") or \
	   new_name.contains(":") or new_name.contains("*") or new_name.contains("?") or \
	   new_name.contains("\"") or new_name.contains("<") or new_name.contains(">") or \
	   new_name.contains("|"):
		return "名称不能包含下列字符：/ \\ : * ? \" < > |"
	var new_path := dir.path_join(new_name)
	if FileAccess.file_exists(new_path) or DirAccess.dir_exists_absolute(new_path):
		return "已存在同名文件或文件夹：" + new_name
	return ""

func _on_rename_confirmed() -> void:
	var new_name := _rename_edit.text.strip_edges()
	var old_path := _menu_path

	# 没改就什么都不做。这一条必须排在存在性校验前面 ——
	# 不然后面会把"改成自己原来的名字"判成"已存在同名"。
	if new_name == old_path.get_file():
		return

	var reason := _validate_new_name(old_path, new_name)
	if reason != "":
		OS.alert(reason)
		return

	var new_path := old_path.get_base_dir().path_join(new_name)
	var err := DirAccess.rename_absolute(old_path, new_path)
	if err != OK:
		OS.alert("重命名失败：" + error_string(err))
		return

	# 改的正是当前打开的文件时，保存路径要跟着走，
	# 否则 Ctrl+S 会把内容写回旧名字，等于凭空多出一个文件
	if current_file_path == old_path:
		current_file_path = new_path
		$VBC/PC/HBC/Label4.text = current_file_path

	refresh_file_tree()
	_select_tree_item_for_path(new_path)
	# 改名**也能换扩展名**（笔记.txt → 笔记.md），和另存为同一个理由。
	_update_preview()

# ---------------- 删除 ----------------

func _prompt_delete() -> void:
	var what := "文件夹" if _menu_is_dir else "文件"
	var text := "确定要把%s「%s」移入回收站吗？" % [what, _menu_path.get_file()]
	if _menu_is_dir:
		text += "\n（文件夹里的全部内容会一并移入）"
	delete_dialog.dialog_text = text
	delete_dialog.popup_centered()

func _on_delete_confirmed() -> void:
	var path := _menu_path
	# move_to_trash 只认全局绝对路径，不吃 res:// 这类虚拟路径
	var err := OS.move_to_trash(path)
	if err != OK:
		OS.alert("删除失败：" + error_string(err))
		return

	# 删掉的正是当前打开的文件（或它所在的目录）时，必须把路径解绑。
	# 否则按 Ctrl+S 会通过 FileAccess.open(..., WRITE) 把刚删掉的文件原地重建出来。
	# 编辑器里的文本保留不动 —— 用户可能正想另存为到别处。
	if current_file_path != "" and \
	   (current_file_path == path or _is_under(current_file_path, path)):
		current_file_path = ""
		$VBC/PC/HBC/Label4.text = "no file"

	refresh_file_tree()
	# 路径没了 → 模式判成 NONE → 右栏收起来，宽度还给编辑器。
	# 编辑器里的文本**故意保留**（上面那句注释），所以不能顺手把预览也清空 ——
	# 收栏是按"当前没有可预览的文件"收的，不是按"文本没了"收的。
	_update_preview()

# ---------------- 侧边栏文件树 ----------------

func _make_icon(path: String) -> Texture2D:
	var tex := load(path) as Texture2D
	if tex == null:
		push_warning("图标加载失败：" + path)   # 缺图标时条目会变成没图标的空行，别静默吞掉
		return null
	var img := tex.get_image()
	if img == null:
		return tex   # 取不到像素数据（压缩纹理等），退回原图
	img.resize(ICON_SIZE, ICON_SIZE, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

func _setup_file_tree() -> void:
	_icon_dir = _make_icon(ICON_DIR_PATH)
	_icon_file = _make_icon(ICON_FILE_PATH)
	_icon_unsupported = _make_icon(ICON_UNSUPPORTED_PATH)

	file_tree.hide_root = true
	# 注意：不要开 allow_reselect。它会让 Tree 在重选同一项时重复发 item_selected，
	# 而折叠一个已选中的条目会触发 Tree 内部重选 —— 于是折叠 -> 重选 -> 折叠 形成死循环，
	# 每帧振荡，同步处理时直接段错误崩溃。
	file_tree.allow_reselect = false
	file_tree.item_selected.connect(_on_file_tree_item_selected)
	# 双击 / 选中后回车
	file_tree.item_activated.connect(_on_file_tree_item_activated)
	# 展开箭头。**必须接**：点箭头不发 item_selected，懒加载没有别的时机去填内容。
	# 详见 _on_file_tree_item_collapsed —— 那里也解释了为什么它只处理"展开"那一半。
	file_tree.item_collapsed.connect(_on_file_tree_item_collapsed)

	_open_as_text_dialog = ConfirmationDialog.new()
	_open_as_text_dialog.title = "按文本打开"
	_open_as_text_dialog.ok_button_text = "仍要打开"
	_open_as_text_dialog.cancel_button_text = "取消"
	# 文案有三行，默认尺寸会挤成一团
	_open_as_text_dialog.min_size = Vector2i(560, 200)
	_open_as_text_dialog.confirmed.connect(_on_open_as_text_confirmed)
	# 取消时把待办清掉，免得那个变量留着一个已经作废的目标
	_open_as_text_dialog.canceled.connect(func(): _pending_open_path = "")
	add_child(_open_as_text_dialog)
	# 右键也选中条目，给个高亮反馈
	file_tree.allow_rmb_select = true
	# 用 gui_input 而不是 Tree 的 item_mouse_selected 拿右键：
	# item_mouse_selected 回调里给的 mouse_position 实测是**屏幕坐标**
	# （窗口在屏幕上的位置也算进去了），而 get_item_at_position() 要的是 Tree 局部坐标，
	# 两者对不上，喂进去永远返回 null。gui_input 里 event.position 才是局部坐标，实测正确。
	file_tree.gui_input.connect(_on_file_tree_gui_input)
	refresh_file_tree()

# 设置文件树的根目录。目录没变时直接返回 ——
# 这是防止每次点文件都重建整棵树、把所有展开状态重置掉的关键守卫。
#
# keep_forward：「上一级 / 前进」这两个按钮自己换根时传 true —— 它们要么会自己补压栈、
# 要么已经把目标从栈里弹掉了，不能让这里顺手清空（清了「前进」就再也回不去）。
# 其余所有调用点都用默认的 false，语义是"从别处跳到新目录 = 历史在这里分叉，
# 旧的前进目标作废"：OpenDir、Ctrl+O 打开别处的文件、双击收藏里不在当前根下的目录。
#
# 早退那条路上**不动**前进栈，这是对的：root_dir 没变，等于什么都没发生。
func set_root_dir(dir: String, keep_forward := false) -> void:
	var normalized := dir.replace("\\", "/").simplify_path()
	if normalized.ends_with("/") and normalized.length() > 1:
		normalized = normalized.substr(0, normalized.length() - 1)
	if normalized == root_dir:
		return
	root_dir = normalized
	if not keep_forward:
		_nav_forward.clear()
	refresh_file_tree()

func refresh_file_tree() -> void:
	# 整棵重建会把展开状态清零，深层目录里改个名整棵树就塌回去，很难用。
	# 懒加载之后默认态**反过来了**：新建出来的目录一律是折叠的（不折就意味着要把整棵
	# 子树建出来，那正是打开 C 盘卡死的原因），所以要保留的变成了"用户展开过"的那些。
	# 恢复展开的同时会把它们的下一层重新建出来，看到的和刷新前一模一样。
	# 换根目录时旧路径在新树里找不到，恢复自然是空操作。
	var expanded := _collect_expanded_paths()

	# 每一条能改变"有没有目录"的路径最后都会走到这里（换根、刷新、_setup_file_tree），
	# 所以按钮的可用状态在这里统一更新，不用逐个调用点去接。
	_update_new_buttons()
	# 收藏按钮同理：换根目录会让"当前文件夹收藏没有"整个变掉，跟着这里走。
	# （这里跑的时候 _favorites 可能还没读进来 —— 那时它是空的，按下态由
	#   _setup_fav_tree() 尾巴上那一次补上。）
	_update_fav_dir_button()
	# 上一级 / 前进同理，两个都跟着 root_dir 变：
	#   上一级的可用性 = 这个目录还有没有上级；
	#   前进的可用性看 _nav_forward —— 而**所有**外部换根都会把它清掉（见 set_root_dir），
	#   所以它必须在这里刷，不能只在那两个按钮的回调里更新，否则 OpenDir 换根之后
	#   「前进」还亮着，按下去却什么都不发生。
	# 位置和上面两个一样，在下面那个"未指定目录"的早退**之前** —— 那条路也要更新按钮。
	_update_nav_buttons()

	file_tree.clear()
	var root := file_tree.create_item()

	if root_dir == "" or not DirAccess.dir_exists_absolute(root_dir):
		var hint := file_tree.create_item(root)
		hint.set_text(0, "未指定目录")
		hint.set_tooltip_text(0, "用 Ctrl+O 打开一个文件，侧边栏会自动定位到它所在的目录")
		hint.set_selectable(0, false)
		return

	_populate_dir(root, root_dir, 0)
	_restore_expanded_paths(expanded)

# 收集当前处于**展开**状态的目录路径。
# 懒加载下"展开"恰好等价于"用户点开过" —— 没建出来的目录一律是折叠的，
# 收进来只会让恢复时白跑一趟。只认目录：文件的 collapsed 恒为默认值，
# 收进来没意义还可能误伤。
func _collect_expanded_paths() -> Array[String]:
	var out: Array[String] = []
	_collect_expanded_rec(file_tree.get_root(), out)
	return out

# 递归进所有子条目，折叠的也进 —— 折叠目录里面可能还留着"被展开过但现在看不见"
# 的子目录（先展开 A/B、再把 A 收起来），那个状态同样要保住。
func _collect_expanded_rec(item: TreeItem, out: Array[String]) -> void:
	if item == null:
		return
	var child := item.get_first_child()
	while child != null:
		if _item_is_dir(child) and not child.collapsed:
			out.append(_item_path(child))
		_collect_expanded_rec(child, out)
		child = child.get_next()

# 把刷新前展开着的目录重新展开（顺带把它们的下一层重建出来）。
# 走 _materialize_path(p, false)：**不**展开沿途祖先，理由见那个函数的注释。
# 收集顺序是前序（父在子前），所以父目录总是先被处理好，子目录走下来时直接命中。
func _restore_expanded_paths(paths: Array[String]) -> void:
	for p in paths:
		var item := _materialize_path(p, false)
		if item != null and _item_is_dir(item):
			_set_dir_collapsed(item, false)

func _populate_dir(parent: TreeItem, dir_path: String, depth: int) -> void:
	if depth >= MAX_TREE_DEPTH:
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return   # 无权限等，静默跳过，不打断整棵树

	var sub_dirs: Array[String] = []
	var files: Array[String] = []

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			if dir.current_is_dir():
				if not entry.begins_with(".") and not SKIP_DIRS.has(entry):
					sub_dirs.append(entry)
			else:
				# 不再按扩展名过滤：打不开的文件也要列出来，用不同的图标区分。
				# 这样目录里到底有什么一眼能看全，右键的重命名 / 删除也能直接作用在它们身上。
				files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()

	# 先收集再排序，保证目录在前、各自按自然序
	sub_dirs.sort_custom(_name_less)
	files.sort_custom(_name_less)

	# **只建这一层。** 子目录只建出它自己那一行，里面的东西等用户点开再建
	# （见 _ensure_dir_loaded）—— 递归就是在这里被砍掉的，不是靠某个开关关掉的。
	# 这一段是"打开 C 盘不再卡死"的全部要点：以前这里会顺着整个盘一路建到底，
	# 几十万个条目，界面和内存一起被拖死（README §8.7）。
	for n in sub_dirs:
		var sub_path := dir_path.path_join(n)
		var dir_item := file_tree.create_item(parent)
		dir_item.set_text(0, n)
		dir_item.set_icon(0, _icon_dir)
		dir_item.set_tooltip_text(0, sub_path)
		# 深度存在 metadata 里，不靠父链现算：MAX_TREE_DEPTH 那道守卫在 _populate_dir
		# 开头判，而懒加载之后这个函数不再从根一路递归下来，每一层得自己知道有多深。
		dir_item.set_metadata(0, {
			"path": sub_path, "dir": true, "loaded": false, "depth": depth + 1,
		})
		# 建出来就是折上的。**这一步不能省**：collapsed 是个独立的存储位
		# （实测 4.7.2：在空条目上设 true，之后再加子条目它依然是 true），
		# 不设的话它默认是 false = 展开态，用户点它反而会把它收起来 —— 交互整个反了。
		dir_item.collapsed = true
		# 再挂个占位子条目，把展开箭头撑出来（原因见 _add_lazy_placeholder）。
		# 顺序不能反：先设 collapsed 再挂，挂上去时才是折着的。
		_add_lazy_placeholder(dir_item)

	for n in files:
		var file_path := dir_path.path_join(n)
		var file_item := file_tree.create_item(parent)
		file_item.set_text(0, n)
		file_item.set_icon(0, _icon_file if _is_editable_file(n) else _icon_unsupported)
		file_item.set_metadata(0, {"path": file_path, "dir": false})

# 把某个目录条目的**下一层**建出来。懒加载唯一往树里加东西的地方（除了整棵重建）。
# 判据是 metadata 里的 "loaded"，**不是"有没有子条目"** —— 空目录建完也是空的，
# 拿子条目数当判据会让它每次点开都重扫一遍磁盘，空目录尤其明显。
# 树根不归这里管：它没有 metadata（见 _materialize_path 里那段），
# 而它的下一层在 refresh_file_tree() 里就已经建好了，本来就是"已加载"的。
func _ensure_dir_loaded(item: TreeItem) -> void:
	if item == null:
		return
	var m = item.get_metadata(0)
	if not (m is Dictionary) or not m["dir"]:
		return                      # 文件条目 / 占位条目 / 树根，都不是可展开的目录
	if m["loaded"]:
		return
	# 先置位再建。_populate_dir 半路出错返回时（目录读不了）也不会被反复重试 ——
	# 它返回之后这个目录就是"展开着但是空的"，和真正的空目录表现一致。
	m["loaded"] = true
	item.set_metadata(0, m)
	# 把占位子条目清掉（就是它撑着那个展开箭头）。到这一步它是唯一的子条目 ——
	# 上面 loaded 那道早退保证了这里只可能建第一次。
	# 目录真的空的话，清完这个条目就没有子节点了，箭头也跟着消失 —— 那是对的。
	# TreeItem 没有 clear_children()，只有 remove_child()，而且它**不负责释放**
	# （4.7 文档原话："This does not free the TreeItem"），得自己补一个 free()，
	# 不然每展开一个目录就漏一个 Object。
	for ph in item.get_children():
		item.remove_child(ph)
		ph.free()
	_populate_dir(item, m["path"], m["depth"])

# 展开 / 折叠一个目录条目。**我们自己**改 collapsed 的地方一律走这里。
# 填充靠的是 _ensure_dir_loaded，而这个函数只是它的一个入口 —— 另一个入口是
# _on_file_tree_item_collapsed（引擎点箭头那条路）。两个入口缺一不可：
# 少后者，点箭头展开出来的是空壳；少前者，程序化那一串（新建 / 重命名 / 收藏跳转）
# 就找不到刚建出来的子条目。
# 走这里的四处：单击（_on_file_tree_item_selected）、双击（_on_file_tree_item_activated）、
# 程序化定位（_materialize_path 展开祖先链）、恢复展开状态（_restore_expanded_paths）。
#
# **build_now = true（默认）：程序化路径**（新建 / 重命名 / 从收藏跳过来 / 恢复展开状态）。
# 不在鼠标事件里，直接同步把下一层建出来 —— 后面几步往往马上就要在这些子条目里找东西，
# 拖到帧末会让 _materialize_path 那一串中途断掉。
#
# **build_now = false：鼠标点出来的展开（单击 / 双击）。** 这一下**不能**同步建，理由见
# _on_file_tree_item_collapsed 上面那段（引擎禁止在鼠标选择事件里建条目，硬来会崩）。
# 这里也**不用自己排队**：赋值 collapsed 就会发 item_collapsed，那个信号会去排。
# 明明能靠信号就别重复处理，不然每展开一次要多跑一趟 _materialize_path。
#
# 附带一条没写进官方文档的引擎规则（照抄自被这段取代的 _restore_collapsed_rec）：
# 如果当前选中项正位于某个目录内部，给那个目录赋 collapsed = true 会被**静默忽略**
# （赋值当场读回还是 false，不报错也不发信号），引擎在拦"不能把选中项折叠没了"。
# UI 上也走不到那个状态 ——选中项在里面时用户本来就点不折叠，所以这里不需要处理。
func _set_dir_collapsed(item: TreeItem, collapsed: bool, build_now := true) -> void:
	# 先建再展开：反过来的话会先摊开一个空行、下一帧才补上内容
	if not collapsed and build_now:
		_ensure_dir_loaded(item)
	item.collapsed = collapsed

# Tree 自己把 collapsed 翻过去的时候走这里。两条路都会进来：
#   1. 用户点了展开箭头 —— 引擎只翻 collapsed、**不发 item_selected**（实测：同一坐标
#      点未建过的目录会得到 item_selected，点已建过的只会得到 collapsed）。懒加载下
#      这条路是"唯一"能靠得住的那个钩子，不接，点箭头展开出来的目录就是个空壳。
#   2. 上面 _set_dir_collapsed(build_now = false) 赋的那一下。同步那半（build_now = true）
#      是先建完才赋值，所以走到这儿 loaded 已经是 true，自然空转一次。
#
# 只处理"展开"那一半：收起来不用建东西。而 _populate_dir 给每个新建的目录条目设
# collapsed = true 也会发这个信号，那一下必须跳过 —— 不然一建树就把整棵树全展开了。
#
# **为什么非得拖到帧末**（这才是 build_now 存在的全部理由）：Tree 处理鼠标选择事件的
# 过程中**禁止**建条目，硬来会是这样（实测，真点一下才暴露）：
#     Condition "blocked > 0" is true. Returning: nullptr
#     scene/gui/tree.cpp:5614 @ create_item()
# 后果不止"没建出来"—— create_item 返回 null，紧跟着的 set_text 就崩在 null 上，
# 整个游戏进程停在断点。
# 这条坑第二招（harness）**验不出来**：那里用 select() 驱动，是程序化选中，
# 不设那个 blocked 计数，怎么跑都是绿的。只有真的往树里发一次鼠标点击才现形。
func _on_file_tree_item_collapsed(item: TreeItem) -> void:
	if item.collapsed:
		return
	# 传**路径**而不是 TreeItem：等这一帧的工夫里树可能被整个重建过
	# （刷新 / 换根 / 改名），攥着一个已经释放的条目去调用会报 freed object。
	_ensure_dir_loaded_for.call_deferred(_item_path(item))

# 帧末补建。由 _on_file_tree_item_collapsed 排进来 ——
# 到这一步 Tree 的鼠标选择事件已经结束，建条目合法了。已经建过的（loaded = true）空转。
# 目标可能已经不在树里（刷新 / 换根 / 改名），_materialize_path 返回 null，静默跳过。
func _ensure_dir_loaded_for(path: String) -> void:
	var item := _materialize_path(path, false)
	if item != null:
		_ensure_dir_loaded(item)

# 给还没建过下一层的目录挂一个占位子条目。
# **这不是装饰，是必需的。** Godot 的 Tree 按"条目有没有子节点"决定画不画展开箭头，
# 没有子节点的条目压根不画（实测：同一坐标点未建过的目录会选中整行、点已建过的才切展开）。
# 不挂的话，用户刚打开一个文件夹看到的是一**列没有任何三角的目录** —— 看着像坏了，
# 而且"点小三角展开"这个习惯动作根本没有落点，只能去猜"点名字也能展开"。
# 展开时 _ensure_dir_loaded 会把它清掉换成真内容（见那里）；目录真是空的话清完就没
# 子节点了、箭头随之消失 —— 空目录本来就不该有箭头。
# 它**没有 metadata**，所以 _item_path() 返回空串：右键菜单、展开状态收集这些按路径认
# 条目的地方都会自动跳过它，不需要到处加判断。
func _add_lazy_placeholder(item: TreeItem) -> void:
	var ph := file_tree.create_item(item)
	ph.set_text(0, "")
	ph.set_selectable(0, false)        # 点不中它：一行空行被选中会像卡住了

# 这个文件能不能在本编辑器里编辑。传文件名或完整路径都行（get_extension 只看最后一段）。
# 没有扩展名的文件（README、Makefile、LICENSE……）这里也算"不可编辑"：
# 判断不出类型时，宁可少编辑一个文本文件（用户能改名成 .txt 绕过），
# 也不要赌一把把二进制的乱码灌进编辑器、还可能顺着 Ctrl+S 覆盖回原文件。
func _is_editable_file(path: String) -> bool:
	return TEXT_EXTENSIONS.has(path.get_extension().to_lower())

func _name_less(a: String, b: String) -> bool:
	return a.naturalnocasecmp_to(b) < 0

# 条目 metadata 统一存 {"path": 绝对路径, "dir": bool}。
# 以前只有文件存 metadata、目录靠 metadata == null 反推，右键菜单拿不到目录路径，
# 所以改成两边都存。没有 metadata 的条目（"未指定目录" 占位）返回空串。
func _item_path(item: TreeItem) -> String:
	if item == null:
		return ""
	var m = item.get_metadata(0)
	if m is Dictionary:
		return m["path"]
	return ""

func _item_is_dir(item: TreeItem) -> bool:
	if item == null:
		return false
	var m = item.get_metadata(0)
	return m is Dictionary and m["dir"]

func _on_file_tree_item_selected() -> void:
	# 右键只负责弹菜单，不应该把文件载入编辑器。
	# Tree 在右键时会不会连带发 item_selected 各版本行为不一致，这里直接挡掉，
	# 无论如何右键点文件都不该换掉编辑器内容。
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return

	var item := file_tree.get_selected()
	if item == null:
		return

	if _item_is_dir(item):
		# 程序化选中不算"用户点了这个目录"。这一条挡的是 select() 顺带发出来的那次信号：
		# 重命名目录 / 新建文件夹都会选中目标，用户没点它，就不该动它的展开状态。
		if _suppress_dir_toggle:
			return
		# 目录：展开 / 折叠。展开那一下顺带把下一层建出来（懒加载的填充点，见 _set_dir_collapsed）。
		# build_now = false：这里正处在 Tree 的鼠标选择事件里，建条目会被引擎挡下来。
		_set_dir_collapsed(item, not item.collapsed, false)
		# 记账：这一轮点击已经切过这个目录了。双击的第二下靠它去重，
		# 不然会再切一次、两次正好抵消。见 _on_file_tree_item_activated。
		_toggled_path = _item_path(item)
		return

	var path := _item_path(item)
	if path == "":
		return                                # 占位条目，没有对应文件

	# 不支持编辑的类型（Word / PPT / 图片……）：单击只选中高亮，什么都不打开。
	# 不能让单击就载进来 —— 读进来是二进制乱码，而 current_file_path 会被指过去，
	# 接着按一下 Ctrl+S 就把原文件覆盖成乱码了，这是真会丢数据的。
	# 想看内容：双击按文本打开（会先弹个提醒，见 _on_file_tree_item_activated），
	# 或者右键「用默认程序打开」交给 Word / PPT 本尊。
	if not _is_editable_file(path):
		return

	# 已经是当前文件就别重复加载。
	# 这一条同时也是 _select_tree_item_for_path 选中条目的递归刹车。
	if path == current_file_path:
		return
	open_and_show(path)                       # 可编辑的文件：单击直接载入编辑器

# 双击条目（或选中后按回车）。
func _on_file_tree_item_activated() -> void:
	var item := file_tree.get_selected()
	if item == null:
		return

	# 目录：双击 = 展开 / 折叠。
	# 这一下是双击的**第二下**，要不要切取决于第一下有没有已经切过 ——
	# Tree 在双击的第一下会做一次普通单击该做的事：
	#   第一下点在**没选中**的目录上 -> 发 item_selected -> _on_file_tree_item_selected
	#                                那边已经切过一次了 -> 这里必须跳过
	#   第一下点在**已选中**的目录上 -> allow_reselect=false 让 Tree 什么都不发
	#                                -> 这里必须补切一次
	# 不区分的话前者会切两次、净效果为零，就是用户看到的"双击文件夹没反应"。
	# 记账在 _toggled_path，由 gui_input 在每次**非双击的**左键按下时清空。
	if _item_is_dir(item):
		# 只有鼠标双击才在目录上做事；键盘回车进来的直接放过（老行为就是回车不管目录）。
		# 实测：双击的第二下触发这里时左键仍是按下状态，回车则不是，所以这个判断是准的。
		# 不加这道判断的话，回车会不会切就取决于上一次点击是不是"重选"，成了一个说不清的行为。
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			return
		if _toggled_path == _item_path(item):
			return
		# build_now = false，同单击那条：这也是一条鼠标事件里的路（回车进来时延后一帧
		# 也无所谓，用户看不出来）。
		_set_dir_collapsed(item, not item.collapsed, false)
		return

	_activate_file_path(_item_path(item))

# 「把这个文件打开」这件事**只在这里做一份**，文件树双击和收藏列表双击都走它。
# 抽出来是因为下面两道守卫都是防丢字的，而 open_and_show() 自己一道都没有
# （它由调用者负责，见 README §6）：
#   1) `path == current_file_path` 那道：少了它，双击一个正在编辑的文件就会
#      用盘上的旧内容把未保存的改动当场冲掉；
#   2) 不在白名单里的文件必须经过 _open_as_text_dialog 的提醒：直接 open_and_show
#      会绕过它，.docx 那类会灌一屏乱码进来，此时 Ctrl+S 就把原文件覆盖了。
func _activate_file_path(path: String) -> void:
	if path == "":
		return                                # "未指定目录" / "还没有收藏" 占位条目

	# 已经在编辑器里就不重读。读盘会把没保存的改动直接冲掉 ——
	# 顺手双击一下当前文件就丢字，那是比"没反应"糟得多的结果。
	if path == current_file_path:
		return

	# 白名单里的正常打开。
	if _is_editable_file(path):
		open_and_show(path)
		return

	# 不在白名单里 = "强制按文本打开"，先提醒一句再动手。这个入口主要给两种情况用：
	#   1) .toml / .env / Dockerfile / README 这类没进白名单、但本来就是文本的文件
	#   2) 真想看看 .docx / .pptx 里面到底有什么
	# 提醒是必要的，因为第 2 种情况下读进来是一堆乱码，而 current_file_path
	# 已经指过去了 —— 此时按 Ctrl+S 会拿编辑器里的内容覆盖掉原文件，不可逆。
	_pending_open_path = path
	_open_as_text_dialog.dialog_text = (
		"「%s」不在可编辑类型列表里，按文本打开多半是乱码。\n\n"
		+ "如果它本来就是文本文件（比如 .toml、.env），确认即可。\n"
		+ "如果不是，看完别保存 —— Ctrl+S 会用编辑器里的内容覆盖原文件。"
	) % path.get_file()
	_open_as_text_dialog.popup_centered()

# 提醒框点了「仍要打开」
func _on_open_as_text_confirmed() -> void:
	if _pending_open_path == "":
		return
	var path := _pending_open_path
	_pending_open_path = ""     # 先清再打开：open_and_show 会发 item_selected，别让它重入
	# 这条链子也可能从收藏视图发起（双击收藏的 .docx）。打开动作一律回到 Explorer 视图
	_set_view(false)
	open_and_show(path)

# 在树里定位并选中某个条目，同时逐级展开它的祖先目录。返回选中项（找不到返回 null）。
# 懒加载之后不能再"整棵树找一遍"了 —— 目标那一层很可能根本还没建出来，
# 所以改成从根开始一层层把路建出来（见 _materialize_path）。
func _select_tree_item_for_path(path: String) -> TreeItem:
	var item := _materialize_path(path)
	if item == null:
		return null

	# select() 会**同步**发 item_selected。如果选中的正是一个目录，那边会把它"展开/折叠"切一下，
	# 于是重命名目录就成了"把它收起来"（用户刚改完名字，里面的东西当场从树里消失）。
	# 这两句必须紧贴着 select()：中间不能有 await，也不能提前 return。
	_suppress_dir_toggle = true
	item.select(0)
	_suppress_dir_toggle = false
	return item

# 从根开始，把 path 这条链一层层建出来，返回它对应的条目。
#
# expand_ancestors = true：沿途的祖先一并展开，"跳过去看得见"要的就是这个。
# expand_ancestors = false：只建、不展开。恢复展开状态时用这个（见 _restore_expanded_paths）——
# 那时手里只有"用户展开过的那些"，顺手把没收起来的父目录摊开就错了，
# "父目录收着、里面的子目录展开着"是合法状态。
#
# path 不在当前根下、就是根自己、或半路上某个目录已经不存在时，返回 null。
func _materialize_path(path: String, expand_ancestors := true) -> TreeItem:
	var root := file_tree.get_root()
	# path == root_dir 这条是**故意**返回 null 的，不是漏了：树根条目没有 metadata
	# （_item_path(root) 恒为空串），一旦选中它就会走 _on_file_tree_item_selected 的
	# 目录分支、把 root.collapsed 翻成 true，而 hide_root = true 之下整个 Explorer
	# 会当场空掉。上面 _reveal_in_file_tree 里那段老注释说的是同一件事，两头都要挡。
	if root == null or path == "" or path == root_dir or not _is_under(path, root_dir):
		return null

	var parts := path.substr(root_dir.length() + 1).split("/")
	var parent := root
	for i in parts.size():
		# 顺序不能反：先把这一层建出来，下面才找得到它的子条目。
		# 树根走到这里是空操作（它没有 metadata，_ensure_dir_loaded 直接返回），
		# 而它的下一层在 refresh_file_tree 里就建好了，所以对得上。
		_ensure_dir_loaded(parent)
		var child := _find_child_item(parent, parts[i])
		if child == null:
			return null        # 半路被删掉了（改名 / 删除之后紧接着的那一次定位）
		if expand_ancestors and i < parts.size() - 1:
			_set_dir_collapsed(child, false)
		parent = child
	return parent

# 在 parent 的**直接子条目**里按名字找一个。不能按完整路径找 ——
# 懒加载下目标那一层还没建，只能一层层往下走，而每层手里只有名字。
# 同名不可能撞车：同一个目录里不会有两条同名条目（Windows 上还是大小写不敏感的）。
func _find_child_item(parent: TreeItem, name: String) -> TreeItem:
	if parent == null:
		return null
	var child := parent.get_first_child()
	while child != null:
		if child.get_text(0) == name:
			return child
		child = child.get_next()
	return null

# ---------------- 收藏夹 ----------------

# 收藏列表那棵树。**在代码里建**，不往 main.tscn 里手写节点：
# 这排 AcceptDialog 之外的节点都带 unique_id，手写 tscn 容易把 id 写错或写重，
# 交给 Godot 自己保存场景时落盘更安全（README §7.9 的老规矩）。
# 它和 FileTree 是同一个 VBoxContainer 里的兄弟节点，靠 visible 互斥显示出切换效果。
func _setup_fav_tree() -> void:
	fav_tree = Tree.new()
	fav_tree.name = "FavTree"
	fav_tree.hide_root = true
	# 右键也选中条目，给个高亮反馈（和 FileTree 一致）
	fav_tree.allow_rmb_select = true
	# 不开 allow_reselect，理由和 FileTree 一样：折叠 -> 重选 -> 折叠 会每帧振荡到崩
	fav_tree.allow_reselect = false
	fav_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fav_tree.visible = false
	# 只接 item_activated（双击 / 回车）。**不接 item_selected** —— 需求就是"单击不做任何事"，
	# 所以这里完全用不上 FileTree 那套服务于单击的记账（_toggled_path / _suppress_dir_toggle）。
	fav_tree.item_activated.connect(_on_fav_item_activated)
	fav_tree.gui_input.connect(_on_fav_tree_gui_input)
	# 追加在 FileTree 之后，和它并排（同一个 VBoxContainer）
	file_tree.get_parent().add_child(fav_tree)

	_load_favorites()
	refresh_fav_tree()
	# 收藏读进来之后才谈得上"当前文件夹收藏没有"，所以同步放在这里（不是 _setup_explorer_buttons）
	_update_fav_dir_button()

# 从存档资源里把收藏读回内存。读不到就当空收藏夹，不报错 ——
# 存档不可用是"功能没得用"，而"打开软件先挨一条错误"对用户没有任何帮助。
func _load_favorites() -> void:
	_favorites.clear()
	if DSaveManager == null or DSaveManager.cur_res == null:
		return
	# 老存档里没有 favorite_paths 这个字段，取到的是默认的空数组，其余字段照旧
	for p in DSaveManager.cur_res.favorite_paths:
		var norm := _normalize_path(p)
		if norm != "" and not _favorites.has(norm):
			_favorites.append(norm)

# 把内存里的收藏写回存档资源。
func _save_favorites() -> void:
	var res = DSaveManager.cur_res
	if res == null or res.save_name == "":
		# 存不了必须**说出来**。"收藏了一堆、重启全没了"这种静默失败，
		# 比一条错误提示糟得多 —— 用户要到下次开机才发现，那时已经找不回来了。
		if not _save_warned:
			_save_warned = true
			push_warning("收藏夹无法保存：DSaveManager.cur_res 不可用")
			DMessageManager.add_top_message("收藏无法保存：存档不可用")
		return
	res.favorite_paths = _favorites.duplicate()
	# 注意这条会顺手更新 last_modified_timestamp，并弹一条"存档保存成功"的顶部提示 ——
	# 是用户明确要求的存法（走框架的 save_cur_res()），接受。
	DSaveManager.save_cur_res()

# 路径的规范形式：正斜杠、无 ./ 和 ../、无结尾斜杠。
# 统一了才比得准 —— 否则同一个目录从对话框选进来是 "C:/a/b/"，从树里点出来是 "C:/a/b"，
# 会被当成两个不同的收藏各存一条。
func _normalize_path(p: String) -> String:
	if p.strip_edges() == "":
		return ""
	var n := p.replace("\\", "/").simplify_path()
	if n.length() > 1 and n.ends_with("/"):
		n = n.substr(0, n.length() - 1)
	return n

func _path_exists(path: String) -> bool:
	# 两头都要判：收藏的可能是文件也可能是目录。
	# 只判文件的话，每一个收藏的文件夹都会被标成"路径不存在"。
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)

# 重建收藏列表（和 refresh_file_tree 一个风格：整个清掉重来）。
# 挂钩点只有三处：_setup_fav_tree() 尾部、_set_view(true) 开头、_toggle_favorite() 尾部。
# **不要**挂到 refresh_file_tree() 上 —— 它在"未指定目录"那条路上是 return，
# 挂函数尾会被直接跳过。
func refresh_fav_tree() -> void:
	if fav_tree == null:
		return
	fav_tree.clear()
	var root := fav_tree.create_item()

	if _favorites.is_empty():
		var hint := fav_tree.create_item(root)
		hint.set_text(0, "还没有收藏")
		hint.set_tooltip_text(0, "在文件树里右键文件或文件夹 → 收藏")
		hint.set_selectable(0, false)     # 占位条目点不动，也就不会把双击送出去
		return

	for path in _favorites:
		var is_dir := DirAccess.dir_exists_absolute(path)
		var missing := not is_dir and not FileAccess.file_exists(path)
		var item := fav_tree.create_item(root)
		# 只写名字的话，几个同名文件（各目录下的 README.md）在一屏里分不清，所以带上父目录。
		# 带的是父目录**名字**而不是完整路径：侧边栏默认只有 300 像素，Tree 从右边裁长文本，
		# 写全路径实测显示成 "a.txt  —  C:/Users/klderm…" —— 留下的恰好是所有条目都相同的
		# 那一截前缀，等于什么都没写，还白占半行。父目录名才是能区分开的那一个词。
		# 完整路径在 tooltip 里，鼠标一停就有（下面那行），需要时也可以拖宽侧边栏。
		var parent_name := path.get_base_dir().get_file()
		if parent_name.length() > 20:
			parent_name = "…" + parent_name.substr(parent_name.length() - 20)
		item.set_text(0, "%s  —  %s" % [path.get_file(), parent_name])
		item.set_icon(0, _icon_dir if is_dir else \
			(_icon_unsupported if missing else _icon_file))
		item.set_tooltip_text(0, path + ("\n（路径不存在）" if missing else ""))
		item.set_metadata(0, {"path": path, "dir": is_dir, "missing": missing})
		if missing:
			# 灰显而不是删掉：外接盘 / 网络盘临时断线是常有的事，
			# 不能因为这一次读不到就把用户存的东西自动清掉。
			item.set_custom_color(0, Color(1, 1, 1, 0.4))

func _is_favorite(path: String) -> bool:
	return _favorites.has(_normalize_path(path))

# 收藏 / 取消收藏某个路径（文件或文件夹都行）
func _toggle_favorite(path: String) -> void:
	var norm := _normalize_path(path)
	if norm == "":
		return
	if _favorites.has(norm):
		_favorites.erase(norm)
	else:
		_favorites.append(norm)     # 追加在末尾：列表顺序 = 收藏的先后
	_save_favorites()
	refresh_fav_tree()
	_update_fav_dir_button()    # 收藏的可能正是当前文件夹，按钮的按下态要跟着变

func _on_fav_tree_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_RIGHT:
		return
	# 和 _on_file_tree_gui_input 同一个套路：用 event.position（Tree 局部）换算成视口坐标，
	# 而不是读 get_selected() —— 右键点在空处时选中项还停在原来那个条目上。
	_open_item_menu_at(fav_tree.get_global_position() + event.position, fav_tree)

# 收藏列表里双击条目（或选中后回车）
func _on_fav_item_activated() -> void:
	var item := fav_tree.get_selected()
	if item == null:
		return
	var m = item.get_metadata(0)
	if not (m is Dictionary):
		return          # "还没有收藏" 占位条目

	var path: String = m["path"]

	if m["missing"]:
		# 只提示，**不**自动删收藏 —— 见 refresh_fav_tree 里的理由。
		# 而且刻意留在收藏视图：用户多半正想右键「取消收藏」清理它。
		DMessageManager.add_top_message("路径不存在：" + path)
		return

	if m["dir"]:
		_reveal_in_file_tree(path)
		return

	# 文件：切回文件预览再走统一的打开链路
	_set_view(false)
	_activate_file_path(path)

# 在文件树里把某个**目录**显示出来（收藏列表双击文件夹走这里）。
func _reveal_in_file_tree(path: String) -> void:
	_set_view(false)          # 先切回文件预览，再操作那棵看得见的树

	if path == root_dir:
		# 收藏的就是当前根目录。根条目本身不显示（hide_root = true），
		# 切回视图就已经是"跳过去了"。
		return

	if not _is_under(path, root_dir):
		# 不在当前根下：换根过去，等同按 OpenDir。
		# 之后**不要**再 _select_tree_item_for_path()：树根条目没有 metadata，
		# _item_path(root) 恒为空串，永远找不到（白调）；而万一将来有人给根条目加了
		# metadata，一次 select() 落到根上会把 root.collapsed 翻成 true，
		# 在 hide_root = true 之下整个 Explorer 会**空掉**。
		set_root_dir(path)
		return

	var it := _select_tree_item_for_path(path)
	# _select_tree_item_for_path 只展开**祖先链**，目标自己的 collapsed 它一个指头都不碰
	# （_suppress_dir_toggle 正好把它压住了）。需求要的是"跳过去看得见"，
	# 所以这里补一句展开它自己 —— 不然双击一个已折叠的收藏文件夹会"选中了但还是收着的"。
	# 展开同时会把它的下一层建出来，所以这一下也是"跳过去之后里面的东西就在"。
	if it != null and _item_is_dir(it):
		# build_now = false：这条路是收藏列表的双击进来的，也在鼠标事件里。
		# （同形状的 set_root_dir → create_item 在下面那个分支里是同步的，一直没事 ——
		#   说明被挡的只是"正在处理鼠标事件的那棵树"自己。不过延后一帧在这里零代价，
		#   不值得为省它去赌引擎内部记账的粒度。）
		_set_dir_collapsed(it, false, false)
		file_tree.scroll_to_item(it)

# ---------------- 导航（上一级 / 前进） ----------------

func _setup_nav_buttons() -> void:
	# 连 pressed 而不是按钮自己的状态：这两个是**动作**按钮，不是开关，
	# 没有"按下态"要显示 —— 对比上面 explorer_button / stars_button 那两个 toggle。
	go_parent_button.pressed.connect(_go_to_parent)
	go_forward_button.pressed.connect(_go_forward)
	_update_nav_buttons()

# dir 的上一级目录；已经到顶时返回空串（按钮据此禁用）。
func _parent_dir_of(dir: String) -> String:
	if dir == "":
		return ""
	var parent := dir.get_base_dir().replace("\\", "/")
	# 到顶了。下面这组是**实测**出来的（Godot 4.7.2 / Windows）：
	#   "C:/Users" -> "C:/Users" 的上一级是 "C:/Users" 的父目录，正常
	#   "C:/"      -> "C:/"      返回的是它自己
	#   "/"        -> "/"        同样是它自己
	#   "C:"       -> ""         退化成空串
	#   "foo"（相对路径）-> ""      也退化成空串
	# **这一条必须排在"父目录存在"检查之前**：实测 DirAccess.dir_exists_absolute("")
	# 返回 true，光靠存在性检查会把空串当成一个合法目录放过去，按钮就永远不禁用了。
	if parent == "" or parent == dir:
		return ""
	# 父目录得真实存在。路径在半路上被删掉时，点下去会落进"未指定目录"那棵空树。
	if not DirAccess.dir_exists_absolute(parent):
		return ""
	return parent

func _go_to_parent() -> void:
	var parent := _parent_dir_of(root_dir)
	if parent == "":
		# 没有上一级（没开目录 / 已经到盘符根）。按钮此刻本该是禁用的，这条是兜底。
		return
	# 和工具栏那几个动作同一个道理：收藏视图下换根，画面上不会发生任何可见的变化，
	# 用户只会觉得"点了没反应"（README §7.17 ⑨）。所以先切回文件树。
	_set_view(false)
	# 记下离开的那个目录，之后按「前进」能回到这里。
	_nav_forward.append(root_dir)
	# keep_forward = true：上面刚压完栈，不能让 set_root_dir 顺手把它清掉。
	set_root_dir(parent, true)

func _go_forward() -> void:
	# 前进目标可能在离开的这段时间里被删掉了（整个目录被移走之类）。
	# 跳过去比落进"未指定目录"那棵空树好 —— 后者看着像按钮坏了，
	# 而且 root_dir 会指向一个死路径。
	while not _nav_forward.is_empty():
		var target: String = _nav_forward.pop_back()
		if DirAccess.dir_exists_absolute(target):
			_set_view(false)          # 同上：换根必须看得见
			set_root_dir(target, true)
			break
	# 无条件补刷一次。set_root_dir 在"目标就是当前目录"时会早退，那条路上
	# refresh_file_tree() 不会跑，按钮会停在"前进还能按"的旧状态上。
	# 多调一次是幂等的，比去论证那条路到底可不可达便宜。
	_update_nav_buttons()

# 两个按钮的可用状态。**挂钩点只有两处**：refresh_file_tree()（换根 / 有没有目录，
# 和 _update_new_buttons / _update_fav_dir_button 同一组）和 _go_forward() 尾部
# （它 pop 之后可能根本没换根）。漏挂的症状是"按钮显示的和实际能做的对不上"。
func _update_nav_buttons() -> void:
	go_parent_button.disabled = _parent_dir_of(root_dir) == ""
	go_forward_button.disabled = _nav_forward.is_empty()

# ---------------- 视图切换（Explorer / 收藏） ----------------

func _setup_view_buttons() -> void:
	# toggle_mode 只为把"现在在哪一边"显示出来。连的是 **pressed** 而不是 toggled：
	# toggled 在状态没变时可能根本不发（点已经按下的那一个），回调就漏了。
	# 回调里显式 bind 目标视图，不读按钮自己的状态 —— 状态是被 _set_view 同步过去的，
	# 读它就等于让显示反过来决定行为。
	explorer_button.toggle_mode = true
	stars_button.toggle_mode = true
	explorer_button.pressed.connect(_set_view.bind(false))
	stars_button.pressed.connect(_set_view.bind(true))
	# 初始那一次也走 _set_view，按钮按下态和标题才不会漏设
	_set_view(false)

func _set_view(fav: bool) -> void:
	_fav_view = fav

	if fav:
		refresh_fav_tree()     # 进收藏视图时重建列表：期间文件可能被删了/新增了收藏

	file_tree.visible = not fav
	fav_tree.visible = fav
	view_label.text = "收藏" if fav else "Explorer"
	# 一、二、三个头部按钮的语义都是"对着当前打开的那个文件夹做点什么"，收藏视图里
	# Explorer 整个不在，它们没有落脚点，一起藏起来。
	# （作用目标本来就是 root_dir，和树里选中谁无关，见 _new_target_dir）
	new_file_button.visible = not fav
	new_folder_button.visible = not fav
	fav_dir_button.visible = not fav
	# set_pressed_**no_signal**：set_pressed() 会发 toggled，
	# 程序化同步一下就绕回去了。
	explorer_button.set_pressed_no_signal(not fav)
	stars_button.set_pressed_no_signal(fav)
	# 两棵树在同一个容器里，隐藏的那棵会被跳过、可见的那棵吃掉全部高度 ——
	# 但容器会不会重排取决于 min size 有没有变，两棵树的 min size 又可能一样。
	# 不主动排一次的话症状是"切过去只有半高，拖一下窗口才正常"。
	file_tree.get_parent().queue_sort()

# ---------------- 预览面板 ----------------
#
# 右栏按扩展名自动给出阅读视图：.txt → 小说排版，.md → Markdown 渲染，其余收起整栏。
# 两条转换链都是**纯函数**（scene/Previewer/ 下的两个脚本），这里只管接线、节流和字号。
#
# 阅读可调项有**五项，作用层各不相同** —— 分错层的症状都是"调了没反应"：
#
# | 可调项 | 作用层 | 走哪个函数 |
# |---|---|---|
# | 行距   | RTL 的**主题常量** `line_separation` | `_apply_preview_font_size()` |
# | 首行缩进字宽 | **转换器**（拼进输出串的全角空格） | `_update_preview()` |
# | 阅读宽度 | **布局**：外层 ScrollContainer 的 min 宽 + 居中 | `_apply_preview_page_width()` |
# | 翻页模式 | **布局**：ScrollContainer 的滚动形式 + 分页表 | `_apply_preview_paged()` |
# | 阅读主题 | **两层都要**：RTL 主题项 **+** 输出串换色 | `_apply_preview_scheme()` + `_update_preview()` |
#
# 只有**缩进字宽**那一行落在输出串上（要重跑转换器）；其余四项都只改布局/主题项，
# 切一下是 O(1) 到 O(段落数)，**一次转换都不重跑**。
#
# 主题那一行最容易做半截：`[color=...]` 的优先级高于主题项 `default_color`，而两个转换器
# 把 8 个颜色**直接拼进了输出串**。只调主题项的话，代码块底色 / 链接 / 引用 / 标题
# 一处都不会变。见 scene/Previewer/PreviewTheme.gd 的头注释。
#
# 章节目录是转换器**同一次转换免费带出来的**（它本来就在逐行过），不扫第二遍；
# 跳转靠 `RTL.get_paragraph_offset()`，一行 —— 见 `_jump_to_paragraph()`。
#
# 预览的源永远是 text_edit.text（编辑器里的当前文本），**不是磁盘上那个文件** ——
# 所以"没保存就切走了"这类事和预览无关，预览也不碰被预览的那个文件。
#
# ⚠️ 但**别再把这句话读成"预览不写任何文件"**（以前这里就是这么写的，加了持久化之后
# 它变成了假话）：五项可调**会落盘**，走的是 `user://der_settings.tres`
# （`_save_reading_settings()`）。写的是**设置**，不是用户正在编辑的文档 ——
# 这个区别是承重的：harness 里的持久化用例必须先把那个文件备份下来再还回去。

## 接线。可见 UI 已经全部在 main.tscn 里了，这里只连行为 ——
## 和侧边栏那排按钮同一套界线（README §7.9）：长什么样归场景，做什么事归代码。
func _setup_preview() -> void:
	preview_mode_button.pressed.connect(_on_preview_mode_button_pressed)
	preview_font_button.pressed.connect(_on_preview_font_button_pressed)
	# 开关做成 toggle 态，按钮才显示得出"现在是开还是关"。
	# toggle_mode 写在代码里而不是场景里：它改的是行为不是外观，和上面那句同一套界线。
	preview_toggle_button.toggle_mode = true
	preview_toggle_button.pressed.connect(_on_preview_toggle_pressed)

	# 两个菜单在代码里建。PopupMenu 在场景里是**隐形**的，没有"长什么样"要落盘；
	# 而手写 tscn 加节点得自己编 unique_id，编错或编重就是"点了菜单不出来"，不报错。
	if _preview_mode_menu == null:
		_preview_mode_menu = PopupMenu.new()
		_preview_mode_menu.name = "PreviewModeMenu"
		_preview_mode_menu.add_item("自动（按扩展名）", PreviewOverride.AUTO)
		_preview_mode_menu.add_item("小说预览", PreviewOverride.NOVEL)
		_preview_mode_menu.add_item("Markdown 预览", PreviewOverride.MARKDOWN)
		_preview_mode_menu.id_pressed.connect(_on_preview_mode_id_pressed)
		add_child(_preview_mode_menu)

	if _preview_font_menu == null:
		_preview_font_menu = PopupMenu.new()
		_preview_font_menu.name = "PreviewFontMenu"
		for i in PREVIEW_FONT_SIZES.size():
			_preview_font_menu.add_item("%d px" % PREVIEW_FONT_SIZES[i], i)
		_preview_font_menu.id_pressed.connect(_on_preview_font_id_pressed)
		add_child(_preview_font_menu)

	if _reading_menu == null:
		# 五项设置合成**一个平铺**菜单（分组标题 + 选项），不用子菜单。
		#
		# 为什么平铺：PopupMenu 的子菜单要靠**节点名**去找子 PopupMenu
		# （add_submenu_item(label, name)），名字对不上就是"子菜单弹出来是空的"这种
		# 不报错的坏法。平铺只用 add_item/add_separator/set_item_disabled，
		# 全是本项目已经在用的 API（_setup_item_menu）。
		#
		# 为什么合成一个菜单而不是五个按钮：右栏固定 274px，放不下五个文字按钮；
		# 五个图标按钮（约 180px）会把这行挤到换行，而 HFlowContainer 每换一行就
		# **永久**吃掉约 30px 阅读高度。一个齿轮 + 一个菜单是唯一不损失高度的形状。
		_reading_menu = PopupMenu.new()
		_reading_menu.name = "PreviewReadingMenu"
		_add_reading_section(_reading_menu, "行距",
			["0.75×", "1×", "1.25×", "1.5×", "2×"], READING_ID_LINE_SCALE)
		_reading_menu.add_separator()
		_add_reading_section(_reading_menu, "首行缩进",
			["不缩进", "1 字", "2 字", "3 字", "4 字"], READING_ID_INDENT)
		_reading_menu.add_separator()
		_add_reading_section(_reading_menu, "阅读宽度",
			["全宽", "180 px", "220 px", "260 px"], READING_ID_PAGE_WIDTH)
		_reading_menu.add_separator()
		_add_reading_section(_reading_menu, "阅读主题", Palette.NAMES, READING_ID_SCHEME)
		# 翻页模式放在**最后**：它是这份菜单里唯一"换一种读法"的项，不是排版细节，
		# 排在四组排版参数之后比夹在中间更好找。
		#
		# **不进工具栏**：工具栏 4 个控件已占 232/274px，再加一个文字按钮（~48px）必然触发
		# HFlowContainer 换行，而每换一行就**永久**吃掉约 30px 阅读高度。
		_reading_menu.add_separator()
		_add_reading_section(_reading_menu, "翻页模式", PREVIEW_PAGED_LABELS, READING_ID_PAGED)
		_reading_menu.id_pressed.connect(_on_preview_reading_id_pressed)
		add_child(_reading_menu)

	# 防抖 Timer。回调必须是 **IDLE**：project.godot 把物理帧设成了 1Hz
	# （physics/common/physics_ticks_per_second，README §7.16 记着这个坑），
	# 接物理帧的话 0.2 秒的防抖会变成 1 秒一刷，打字时预览明显跟不上。
	_preview_timer = Timer.new()
	_preview_timer.name = "PreviewDebounce"
	_preview_timer.one_shot = true
	_preview_timer.process_callback = Timer.TIMER_PROCESS_IDLE
	_preview_timer.wait_time = PREVIEW_DEBOUNCE_SEC
	_preview_timer.timeout.connect(_on_preview_debounce_timeout)
	add_child(_preview_timer)

	# 工具栏那两个新按钮**在代码里建**，和上面几个菜单同一套理由（PopupMenu 隐形、
	# 没有"长什么样"要落盘，而手写 tscn 加节点要自己编 unique_id，编错就是静默坏）。
	# 父节点从 preview_mode_button 反推，不写死路径。
	var toolbar := preview_mode_button.get_parent()

	_reading_button = Button.new()
	_reading_button.name = "PreviewReadingButton"
	_reading_button.tooltip_text = "阅读设置（行距 / 缩进 / 阅读宽度 / 主题）"
	_reading_button.icon = preload("res://asset/icon/settingIcon.png")
	# ⚠️ **expand_icon 必须写**。settingIcon.png 是 400×400，且 .import 里没设
	# size_limit（不缩放）—— 不写 expand_icon 的话按钮的 min 宽直接是 400px，
	# 比整条右栏（274）还宽，会把 split_offsets 顶开。README §7.20 记着这条。
	_reading_button.expand_icon = true
	_reading_button.custom_minimum_size = Vector2(32, 31)
	_reading_button.pressed.connect(_on_preview_reading_button_pressed)
	toolbar.add_child(_reading_button)

	_toc_toggle_button = Button.new()
	_toc_toggle_button.name = "PreviewTocButton"
	_toc_toggle_button.text = "目录"
	_toc_toggle_button.tooltip_text = "显示 / 隐藏章节目录"
	_toc_toggle_button.toggle_mode = true
	_toc_toggle_button.pressed.connect(_on_preview_toc_toggle_pressed)
	toolbar.add_child(_toc_toggle_button)

	# 目录树。做法照 _setup_fav_tree()（hide_root + 代码建 + 接信号）。
	#
	# 位置：**插在工具栏和阅读器之间**。preview_rail 的子节点顺序是
	# 0 = 标题 PanelContainer、1 = 工具栏 HFlowContainer、2 = MobileNovelReader，
	# 所以插到 index 2 就落在它们中间。
	_toc_tree = Tree.new()
	_toc_tree.name = "PreviewTocTree"
	_toc_tree.hide_root = true
	_toc_tree.columns = 1
	_toc_tree.allow_rmb_select = false
	# ⚠️ 这里**开** allow_reselect，和 FileTree / fav_tree 的做法相反，是有意的：
	# 它们关掉是因为"选中 → 折叠 → 树变了 → 又选中"会每帧振荡到崩（README §7.1）。
	# 目录没有这个回路 —— 选中只滚一下 RichTextLabel 外层，**不回改树**。
	# 而关掉的话，"滚走了再点同一章"就点不动了，那恰恰是目录最常用的操作。
	_toc_tree.allow_reselect = true
	# 只占它自己那 160px，**不抢**阅读区的高度（不 EXPAND）：目录是拿来认路的，
	# 不该在右栏里和正文对半分。
	_toc_tree.size_flags_vertical = Control.SIZE_FILL
	_toc_tree.custom_minimum_size = Vector2(0, 160)
	_toc_tree.visible = false
	_toc_tree.item_selected.connect(_on_toc_item_selected)
	preview_rail.add_child(_toc_tree)
	preview_rail.move_child(_toc_tree, 2)

	# 页码条：翻页模式下才出现的一行（上一页 / 页码 / 下一页）。
	#
	# **挂在 MobileNovelReader 上，不挂 preview_rail**：_toc_tree 已经用
	# move_child(..., 2) 在挪 preview_rail 的下标，再往那儿加节点就是两个人在挪同一份
	# 子节点顺序。MobileNovelReader 是个 VBox，今天是 0 = SC，页码条追加到 1
	# 就正好落在"阅读区下方一行"。
	#
	# ⚠️ **更不能插在 SC 和 RTL 之间**：那条路径上有一句
	# `preview_rtl.get_parent() as ScrollContainer`，插一层会**静默**拿到 null
	# （`as` 失败不报错），滚动保活当场失效（见 _apply_preview_page_width 头注释）。
	# 挂在 MobileNovelReader 上不在这条路径上。
	#
	# 不写进 tscn：和 _toc_tree / _reading_button 同一套理由（手写 tscn 要自己编
	# unique_id，编错是静默坏；而这一行是"有没有"和"长什么样"都由模式决定的东西）。
	var reader := preview_rtl.get_parent().get_parent()
	_page_bar = HBoxContainer.new()
	_page_bar.name = "PreviewPageBar"
	_page_bar.visible = false

	_page_prev_button = Button.new()
	_page_prev_button.name = "PrevPageButton"
	# ⚠️ 用 **«** » 而**不是** ◀ ▶。项目里一个字体文件都没有（走内建 Open Sans SemiBold），
	# 实测 ◀(U+25C0) ▶(U+25B6) —— 连**兜底字体**里都没有字形，一定会渲染成豆腐块。
	# «(U+00AB) »(U+00BB) 在拉丁补充区，字体覆盖度好得多，实测两个都有字形。
	_page_prev_button.text = "«"
	_page_prev_button.tooltip_text = "上一页"
	_page_prev_button.pressed.connect(_on_page_prev_pressed)
	_page_bar.add_child(_page_prev_button)

	_page_label = Label.new()
	_page_label.name = "PageLabel"
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_bar.add_child(_page_label)

	_page_next_button = Button.new()
	_page_next_button.name = "NextPageButton"
	_page_next_button.text = "»"
	_page_next_button.tooltip_text = "下一页"
	_page_next_button.pressed.connect(_on_page_next_pressed)
	_page_bar.add_child(_page_next_button)

	reader.add_child(_page_bar)

	text_edit.text_changed.connect(_on_preview_text_changed)

	# meta_clicked 是 RichTextLabel 自己的信号，不在场景里连 —— 和上面三个按钮一样，
	# 接线归代码。
	preview_rtl.meta_clicked.connect(_on_preview_meta_clicked)

	# 翻页模式的输入**接在 RTL 上**，不是外层 SC：滚轮要从"最上层控件往上冒"的路上
	# 被拦下来（RTL 就是鼠标下最上层那个），拦在 SC 上就晚了 —— 它自己已经处理完了。
	preview_rtl.gui_input.connect(_on_preview_rtl_gui_input)

	var sc := preview_rtl.get_parent() as ScrollContainer
	if sc != null:
		# 阅读区高度变了，每页装得下的量就变了（见 _on_preview_sc_resized）。
		sc.resized.connect(_on_preview_sc_resized)

	# 页宽要跟着分隔条走：右栏宽度变了，clamp 的结果得重算（见 _apply_preview_page_width）。
	preview_split.resized.connect(_apply_preview_page_width)

	_apply_preview_font_size()
	_apply_preview_scheme()
	_apply_preview_page_width()
	_apply_preview_paged()
	_update_preview_toggle_button()
	_update_preview()

	# 阅读设置是**延迟读**的，而且必须压在 DSettingsManager 之后：它的 _load_or_create()
	# 走的是 call_deferred，而 autoload 的 _ready 又排在主场景之前，deferred 队列要等
	# 主场景 _ready 跑完才 flush —— 所以这里同步读**必然拿到 null**。
	# 两条 deferred 同在一个 FIFO 队列里，它先入队，于是"先加载、后读取"是天然成立的。
	# （不能用 settings_changed 兜底：文件已存在时 _load_or_create() **不发**那个信号。）
	call_deferred("_load_reading_settings")


## 纯函数：路径 → 自动模式。不碰节点、不读文件，只有这一条判断。
static func _resolve_preview_mode(path: String) -> PreviewMode:
	if path == "":
		return PreviewMode.NONE
	match path.get_extension().to_lower():
		"txt":
			return PreviewMode.NOVEL
		"md":
			return PreviewMode.MARKDOWN
	return PreviewMode.NONE


## 最终生效的模式。**这里的判断顺序本身就是需求保证**：
## 先看扩展名，自动判出 NONE 就一律 NONE —— 手动覆盖在这个分支里被直接拦掉。
##
## 为什么不能让手动覆盖越过它：一个 .docx 被"强制按文本打开"（_on_open_as_text_confirmed）
## 之后是一屏二进制垃圾。如果用户上一轮手动选了 Markdown，而覆盖是粘性的，
## 这屏垃圾就会被当成 Markdown 排进阅读器里 —— 比收起右栏糟得多。
## 所以「非 txt/md 收起整栏」是**无条件**的，覆盖只对本来就有预览的文件生效。
func _effective_preview_mode() -> PreviewMode:
	var auto := _resolve_preview_mode(current_file_path)
	if auto == PreviewMode.NONE:
		return PreviewMode.NONE
	if _preview_mode_override == PreviewOverride.NOVEL:
		return PreviewMode.NOVEL
	if _preview_mode_override == PreviewOverride.MARKDOWN:
		return PreviewMode.MARKDOWN
	if not _preview_enabled:
		return PreviewMode.NONE
	return auto


## 纯函数：模式 → 右栏标题上那个词。
static func _mode_name(mode: PreviewMode) -> String:
	match mode:
		PreviewMode.NOVEL:
			return "Preview · 小说"
		PreviewMode.MARKDOWN:
			return "Preview · Markdown"
	return "Preview"


## 右栏该不该出现。**这里区分了两种"模式是 NONE"**，它们长得一样但处理相反：
##
##   ① 打开了文件、但不是可预览的类型（.py / .json / 被强制按文本打开的 .docx…）
##      → 无条件收起，把宽度还给编辑器。这是用户选的规矩。
##   ② 根本没打开文件
##      → **照旧空着**（和这次改动之前一模一样），听用户的开关。
##
## ②不能跟着①一起收，有两个具体后果：启动时右栏凭空消失，画面和以前不一样；
## 而且工具栏那颗 Preview 按钮会变成**死键** —— 没文件时模式恒为 NONE，
## 于是按下去了栏也开不出来，用户点两次只会觉得按钮坏了。
func _should_show_preview_rail(mode: PreviewMode) -> bool:
	if current_file_path == "":
		return _preview_enabled
	return mode != PreviewMode.NONE


## 重新判定模式并渲染。**所有会改变"该显示什么"的地方都要调它**：
## 打开文件、另存为、改名、删除、切模式、改字号、切开关。
## 少调一处的症状是"内容对但右栏没跟着开/关"，属于看着像没坏的那种坏。
func _update_preview() -> void:
	# 摊上一轮还没跑的防抖：这次是显式刷新，权威，不需要那个迟到的回调再来一次。
	if _preview_timer != null:
		_preview_timer.stop()

	var mode := _effective_preview_mode()
	_set_preview_rail_visible(_should_show_preview_rail(mode))

	if mode == PreviewMode.NONE:
		# 没有可渲染的东西，**把上一次的内容清掉**：否则"打开 a.txt 再把它删了"
		# 会在右栏留一屏已经不属于任何文件的旧文本，看起来像预览还活着。
		preview_rtl.text = ""
		# 目录同理会留一屏属于**上一个文件**的章节 —— 点一下还会滚到一个空位置。
		_set_chapters([])
		# 页码条同理（_refresh_page_bar 见到 NONE 会自己藏掉，这里把表也作废）。
		_invalidate_pages()
		_refresh_page_bar()
		preview_title.text = _mode_name(PreviewMode.NONE)
		return

	preview_title.text = _mode_name(mode)
	_render_preview(mode)


## 预览的源文本。**永远取编辑器里的当前文本**，不读磁盘 ——
## 用户看到的就是他正在编辑的东西，没保存也不会不一致。
func _preview_source_text() -> String:
	return text_edit.text


## 重排一屏。**五项可调里只有两项从这里过**（缩进字宽、配色），另外三项不走这里：
## 行距是 RTL 的主题常量（_apply_preview_font_size）、页宽是外层 SC 的 min 尺寸
## （_apply_preview_page_width）、翻页模式是 SC 的滚动形式（_apply_preview_paged）
## —— 那三项重设一次主题项/布局就行，不需要重跑转换器。
##
## 反过来说，**缩进和配色改了就一定得重跑这一趟**：它们影响的是转换器吐出来的字符串本身。
func _render_preview(mode: PreviewMode) -> void:
	var src := _preview_source_text()

	if src.length() > PREVIEW_MAX_CHARS:
		# 超长文件给一句话，不硬排。排版本身是 O(n)，几 MB 的 .txt 每敲一键重排一次
		# 会把主线程钉住 —— 那看起来就是程序死了。宁可明确说"太长了不预览"。
		# 这句提示**在转换器之外**、直接写进同一个 RTL，够不到色板参数，所以灰度要单独取。
		preview_rtl.text = "[color=%s][i]文件太长（%s 字符），预览已停用。[/i][/color]" % [
			Palette.color(_preview_scheme, "dim"), _thousands(src.length())]
		# 这条分支**也要清目录**：否则右栏写着"预览已停用"，左边的目录还列着章节。
		_set_chapters([])
		# 页码表同理会留着**上一个文件**的页数（还是按旧文本的折行算的），
		# 翻页会跳到一个空位置。一并作废。
		_invalidate_pages()
		_refresh_page_bar()
		return

	# 目录是**同一次转换免费带出来的**（转换器本来就在逐行过，认出来时顺手记下下标），
	# 所以这里不需要为了目录再扫第二遍源文本。
	var res: Dictionary
	if mode == PreviewMode.MARKDOWN:
		# Markdown 要 base_font_size：标题字号是**相对正文**算出来的（+10/+7/+5…），
		# 转换器不知道主题里字号被调成了多少，只能问我们。
		res = MarkdownToBbcode.to_bbcode_with_toc(src, _preview_font_size, _preview_scheme)
	else:
		res = TextToBbcode.to_bbcode_with_toc(src, {
			"indent": _preview_indent,
			"theme": _preview_scheme,
			# 章节标题要比正文大一点，而正文字号由这里的主题覆盖决定，转换器不知道 ——
			# 所以由我们告诉它。0 是"别发字号标签"，这里永远不是 0。
			"font_size": _preview_font_size,
		})

	# 滚动位置**存在外层 ScrollContainer 上**，不在 RichTextLabel 上：
	# fit_content = true 让 RTL 正好和内容等高，它自己根本没得滚，滚动条是外层的。
	# 而 rtl.text = ... 会把外层也复位 —— 不手动保的话，在长文末尾打字时视图
	# 会一路跳回顶部，等于没法边看边改。
	var sc := preview_rtl.get_parent() as ScrollContainer
	var keep: int = sc.scroll_vertical if sc != null else 0
	# 翻页模式下要保的是**页号**，不是像素：页号不随折行漂移，而旧折行下的像素值
	# 在新折行里会落到另一页的中间。表作废前先把它记下来 —— 这是**改动前**的页号。
	var keep_page := _page_index
	preview_rtl.text = String(res["bbcode"])
	# 放在 text 赋值**之后**：目录里的段落号是"输出串的第几行"，和 text 是同一份东西，
	# 中途更新会让 _rebuild_toc 去索引一个还不存在的段落号。
	_set_chapters(res["chapters"])
	# text 一换，折行全变，页码表里存的像素偏移就全是**旧文本**的了 —— 留着它比没有更坏
	# （翻页会跳到错误的段落）。这一步必须在 text 赋值**之后**：之前作废的话，
	# 走查会拿着旧文本去算。
	_invalidate_pages()
	if sc != null and _preview_paged:
		_keep_page_pending = maxi(0, keep_page)
		_queue_page_refresh()
	elif keep > 0 and sc != null:
		# set_deferred 而不是直接赋值：text 刚换掉时布局还没跑，ScrollContainer 的
		# 滚动上限还是**旧的**（旧文本的高度），此刻写进去会被它按旧上限夹一次。
		# 延到帧末，布局已经跑完，接住的就是新上限内的位置。
		sc.set_deferred("scroll_vertical", keep)


## 藏掉右栏 = 那个可见子节点不参与分配，剩下的重新分宽度，编辑器拿到全部剩余宽度。
##
## ⚠️ **必须先存 split_offsets 再藏**。SplitContainer 隐藏子节点后会按可见子节点
## 重排偏移表 —— 实测三段的 [221, -274] 藏掉第三段之后变成 [221]，那 274 就再也
## 找不回来了（恢复时右栏会塌成 0 或跳成一个默认值）。所以藏之前 duplicate() 存一份，
## 显示时原样写回。这一步是**承重**的，不是保险。
func _set_preview_rail_visible(on: bool) -> void:
	if preview_rail.visible == on:
		return          # 没变就别碰 offsets：否则每次刷新都会把用户的拖动结果覆盖掉
	if on:
		preview_rail.visible = true
		if _preview_saved_split_offsets.size() > 0:
			preview_split.split_offsets = _preview_saved_split_offsets
	else:
		_preview_saved_split_offsets = preview_split.split_offsets.duplicate()
		preview_rail.visible = false
	# 宽度变了要主动排一次。不排的话取决于 min size 有没有变 ——
	# 症状是"切过去宽度不对，拖一下窗口才正常"。和 _set_view() 尾巴上那句同一个理由。
	preview_split.queue_sort()


## 把字号铺到 RichTextLabel 的**五个**字体项上。
##
## 这五个是互相独立的主题项，各有自己的默认值。只改 normal_font_size 的话，
## 加粗标题会留在默认值而正文变了 —— 字号调大时"标题比正文还小"，字号调小时
## 标题突兀地大。这不是防御性代码，是实测过的：只覆盖 normal 之后读
## bold_font_size，仍然纹丝不动。README §7.20 记了这条。
func _apply_preview_font_size() -> void:
	for item in PREVIEW_FONT_ITEMS:
		preview_rtl.add_theme_font_size_override(item, _preview_font_size)

	# 行距按字号的倍数算，不写死像素（写死的话字号一调大，行距相对就变窄）。
	# 比例随模式走：小说是密排长文要松，Markdown 块多留白多要收。
	var ratio := PREVIEW_LINE_SEP_NOVEL if _effective_preview_mode() == PreviewMode.NOVEL \
		else PREVIEW_LINE_SEP_MARKDOWN
	# 用户那个"行距"档位是**乘在比例上**的因数，不是替换掉比例 ——
	# 默认 1.0 时 ×1.0 在 IEEE754 里是精确的，所以默认值和改动前逐位相同。
	preview_rtl.add_theme_constant_override(
		"line_separation", int(round(_preview_font_size * ratio * _preview_line_scale)))


## 把阅读主题铺上去。**必须同时管两处**（这是本次最容易做半截的地方）：
##
##   * `Palette.apply_to()` 管 RTL 的主题项 —— 没被 `[color]` 包住的正文、背景、选中色
##   * 转换器那条路上 `Palette.retint()` 管**拼进输出串**的那 10 处色值
##
## 只做前者的话，代码块底色 / 链接 / 引用 / 标题这些**一处都不会变**，
## 因为 `[color=...]` 的优先级高于主题项 `default_color` —— 看着像"主题只生效了一半"。
func _apply_preview_scheme() -> void:
	Palette.apply_to(preview_rtl, _preview_scheme)


## 应用阅读宽度（页宽）。
##
## 走 **ScrollContainer 自己的 min 宽 + SIZE_SHRINK_CENTER**，场景文件一行都不用改。
## 为什么不去插节点（这是有意的选择，两个候选方案都会**静默**坏掉）：
##
##   * 在 SC 和 RTL **之间**插一层 → main.gd 那句
##     `preview_rtl.get_parent() as ScrollContainer` 会拿到 **null**（`as` 失败返回 null，
##     不报错），滚动保活当场失效，症状正是"长文末尾打字视图一路跳回顶部"。
##   * 在 SC **上面**插 CenterContainer / 改 preview_rail 的 min size → min size 会
##     向上传播，和 split_offsets 的存/恢复反复打架（_set_preview_rail_visible），
##     窗口变窄时还会和容器形成拉锯。
##
## 宽度从 **preview_split.size.x** 派生（不是 preview_rail.size.x —— 那正是会被自己的
## min 宽影响的那个值），clamp 结果**不写回 `_preview_page_width`**：名义值是用户的，
## 应用值是当下可用的，混在一起的话用户把分隔条拖窄一次就把他选的页宽永久改掉了。
func _apply_preview_page_width() -> void:
	var sc := preview_rtl.get_parent() as ScrollContainer
	if sc == null:
		return
	_apply_reading_column_size(sc, _preview_page_width)
	# 页码条（翻页模式）跟着正文列一起收，窄栏时两者**同宽对齐**。
	# `_page_bar != null` 才做：_load_reading_settings 是 deferred 的、排在 _setup_preview
	# 之后，但字号菜单那条路（_on_preview_font_id_pressed）也可能更早碰到它。
	if _page_bar != null:
		_apply_reading_column_size(_page_bar, _preview_page_width)


## 把"阅读宽度"那套施加到一个控件上。**正文列（SC）和页码条共用这一份实现** ——
## 两处各写一遍的话，改了其中一处就会一条宽一条窄，而且窄得**很轻微**、一眼看不出来。
##
## `want <= 0` = 全宽 = 改动前的行为：默认的 FILL 标志 + min 0，不做任何居中。
##
## 实测（README §7.20）：SC 的 min.x 默认只有 **1**，所以 SHRINK_CENTER **必须**和
## custom_minimum_size.x 成对出现 —— 单设居中会把控件塌成 1px 宽。
func _apply_reading_column_size(c: Control, want: int) -> void:
	if want <= 0:
		c.size_flags_horizontal = Control.SIZE_FILL
		if c.custom_minimum_size.x != 0:
			c.custom_minimum_size.x = 0
		return
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var avail := int(preview_split.size.x)
	var applied := want if avail <= 0 else mini(want, avail)
	# 相同就别写：这个函数接在 preview_split.resized 上，而改 min size 本身会触发重排，
	# 无条件写就是在布局里反复推布局。
	if c.custom_minimum_size.x != applied:
		c.custom_minimum_size.x = applied


## 切换滚动 / 翻页。
##
## **只改布局，不重跑转换器** —— 和页宽同类（见 _on_preview_reading_id_pressed 的表格）：
## 同一份 BBCode，换个滚法而已，没有哪个字符会变。
##
## ⚠️ 顺序是**先切模式再作废表**：藏滚条会让 RTL 宽出 8px、正文重新折行，
## 表必须在新的折行下重建。反过来做就会拿着旧折行的页首去翻页，落在半行上。
func _apply_preview_paged() -> void:
	var sc := preview_rtl.get_parent() as ScrollContainer
	if sc == null:
		return
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER if _preview_paged \
		else ScrollContainer.SCROLL_MODE_AUTO
	_invalidate_pages()
	if _preview_paged:
		# 进翻页模式时**保住阅读位置**：表重建时 _ensure_pages() 会从当前
		# scroll_vertical 反推出页码，正好落在读者原来读到的地方。
		_queue_page_refresh()
	else:
		# 回滚动模式：页码条藏起来，表也用不上了。
		_refresh_page_bar()


# ---------------- 翻页模式 ----------------
#
# 一份 BBCode，两种读法：自由滚动（默认）和一次一屏。**纯表现层** ——
# 转换器、场景文件、`scene/Previewer/*.gd` 三处**一行都不用改**。
#
# 机制是 `ScrollContainer.SCROLL_MODE_SHOW_NEVER`（能滚、但滚条不画）+ 按页写
# `scroll_vertical`。实测确认这条可行：`SCROLL_MODE_SHOW_NEVER` **不收缩滚动范围**，
# 写进去的 `scroll_vertical` 照读回来。
# ⚠️ 一律走 `vertical_scroll_mode`，**绝不** `hide()` / `queue_free()` 那个
# `get_v_scroll_bar()` —— 它是引擎内部节点，官方文档明说 free 它会崩。
#
# ⚠️ 藏了滚条，RTL 会**宽出正好 8px**（266 → 274，原来那条竖滚条的位置），
# 正文因此**重新折行**（实测同一份文档内容高 356000 → 323669）。
# 所以页码表**必须在模式切完之后**重算 —— 见 _invalidate_pages()。


## 走查全篇，得出每一页的页首像素 Y。
#
## 页首**对齐到段落起点**，不按 `cur + h` 硬切：硬切会把一行字拦腰截断，
## 页首是半行 —— 那不是"翻页"，那是"跳着滚"。宁可**重复一段**，绝不切断一行。
##
## **为什么这样一定收敛**（别"优化"成 `cur + h`，那会重新切出半行）：
##   * `cand > cur` 是显式护栏 → next 严格递增；
##   * 一个段落比整页还高时 `cand == cur` → 落到 `cur + h` 兜底，仍然前进一屏；
##   * 重复的**最多一个段落**：`offset(k-1) <= boundary`，所以回退量 ≤ 一个段高，
##     而前进量 ≥ `h - 段高`，永远是大步前进。
##
## **成本（实测）**：段落数 + 页数都是线性的，12 万字符（PREVIEW_MAX_CHARS 的上限，
## 也是本函数的最坏输入）→ 5958 段落 / 1192 页 / **10.2ms**。
## 对比同一份文档的排版要 1092ms，所以这是个小头 —— 但它是**一次性**的，
## 必须只挂在"缓存失效"上，绝不能进每帧路径（见 _queue_page_refresh）。
func _walk_pages(h: int) -> PackedInt32Array:
	var tops := PackedInt32Array()
	if h <= 0:
		return tops
	var pc := preview_rtl.get_paragraph_count()
	var total := preview_rtl.get_content_height()
	var cur := 0
	var k := 0                       # 还没被当作"页首候选"的第一个段落
	var guard := 0
	while cur + h < total and guard < PREVIEW_PAGE_WALK_GUARD:
		guard += 1
		tops.append(cur)
		var boundary := cur + h
		while k < pc and int(preview_rtl.get_paragraph_offset(k)) <= boundary:
			k += 1
		var next := cur + h
		if k > 0:
			# k-1 是"起点落在本页内"的最后一个段落 —— 它被页底切到了，
			# 所以下一页**从它的开头重来**。
			var cand := int(preview_rtl.get_paragraph_offset(k - 1))
			if cand > cur:
				next = cand
		cur = next
	# 收尾用 `while cur + h < total`：余下内容已经装得下，就不再回退去重复最后一段了。
	tops.append(cur)
	return tops


## 像素 Y → 页码。返回**最后一个**页首 ≤ y 的页，也就是"y 落在哪一页里"。
##
## 线性扫描，不二分：页数是千级，而它只在**跳转 / 重排后复位**时被调用一次
## （实测 1192 页的线性扫一遍是微秒级），不在每帧路径上。
func _page_index_for(y: int) -> int:
	var idx := 0
	for i in _page_tops.size():
		if _page_tops[i] > y:
			break
		idx = i
	return idx


## 保证 `_page_tops` 和"当前视口高"配套且有效。**这是唯一真正算分页的地方。**
##
## 惰性：调用方只该是"要翻页 / 要刷页码 / 要跳转"，不该是"每帧"。
## 返回 false = 现在还量不出高度（SC 还没布局），调用方别拿空表当"只有一页"。
func _ensure_pages() -> bool:
	var sc := preview_rtl.get_parent() as ScrollContainer
	if sc == null:
		return false
	var h := int(sc.size.y)
	if h <= 0:
		return false
	if _page_tops.is_empty() or _page_height != h:
		_page_height = h
		_page_tops = _walk_pages(h)
		# 表换了 → 当前页码按**新的**表重新定位，接住"重排前读到哪儿了"。
		# 这是**唯一**一处从 scroll_vertical 反推，见 _page_index 的头注释。
		_page_index = _page_index_for(int(sc.scroll_vertical))
	return true


## 页码表作废。**只置脏，不重算** —— 重算在 _ensure_pages()。
##
## 作废的时机全是"折行会变"的那些：换 text、改字号/行距/缩进/主题/页宽、
## 切翻页模式、阅读区尺寸变化。
func _invalidate_pages() -> void:
	_page_tops = PackedInt32Array()
	_page_height = 0


## 把重算合并成"帧末一次"。
##
## **可重入安全**：拖动分隔条时 `resized` 会连发，不加这个标志就会往 deferred 队列里
## 塞几百个回调，每个都跑一遍全篇走查。
func _queue_page_refresh() -> void:
	if _page_refresh_queued:
		return
	_page_refresh_queued = true
	_refresh_page_bar_deferred.call_deferred()


func _refresh_page_bar_deferred() -> void:
	_page_refresh_queued = false
	_refresh_page_bar()
	# 重排后回到原来那一页。**保的是页号不是像素**：页号不随折行漂移，
	# 而旧折行下的像素值在新折行里会落到另一页的中间。
	if _keep_page_pending >= 0:
		var p := _keep_page_pending
		_keep_page_pending = -1
		_goto_page(p, true)


## 页码条的内容与可见性。**内部会 _ensure_pages()** —— 所以别在每帧路径上调它。
func _refresh_page_bar() -> void:
	if _page_bar == null:
		return
	# 只在"翻页模式 + 真的有东西可读"时出现。没有文件时右栏是**可见的空壳**
	# （见 _should_show_preview_rail 的 ②），不加这道闸就会在空壳底下挂一条"第 1 / 1 页"。
	if not _preview_paged or _effective_preview_mode() == PreviewMode.NONE:
		_page_bar.visible = false
		return
	_page_bar.visible = true
	if not _ensure_pages():
		# 高度还没出来（刚切模式 / 栏刚显示）—— 下一帧再试。
		# **只在栏真的可见时才重试**：栏藏起来时 SC 的高度恒为 0，
		# 无条件重试会变成一个永不停止的 deferred 自旋。
		if preview_rail.visible:
			_queue_page_refresh()
		return
	var n := _page_tops.size()
	_page_index = clampi(_page_index, 0, n - 1)
	_page_label.text = "第 %d / %d 页" % [_page_index + 1, n]
	# 到头了就把按钮变灰 —— 比"点了没反应"清楚。只有一页时两个都灰。
	_page_prev_button.disabled = _page_index <= 0
	_page_next_button.disabled = _page_index >= n - 1


## 把当前 `_page_index` 落到滚动位置上。
##
## `deferred`：刚改完 text / 刚切完模式时**必须**用 —— 那一刻 SC 的滚动上限还是旧值的，
## 直接写会被按旧上限夹一次（和 _render_preview 尾部、_jump_to_paragraph 同一个理由）。
func _scroll_to_page(deferred: bool) -> void:
	var sc := preview_rtl.get_parent() as ScrollContainer
	if sc == null or _page_tops.is_empty():
		return
	if _page_index < 0 or _page_index >= _page_tops.size():
		return
	# ⚠️ 末页页首**可能超过可滚上限**（实测 861490 > 861057），那时引擎会夹到上限。
	# 视觉效果正是想要的（末页把结尾顶到底），而 `_page_index` 不受影响 ——
	# 它就是为此才当权威的。
	var y := int(_page_tops[_page_index])
	if deferred:
		sc.set_deferred("scroll_vertical", y)
	else:
		sc.scroll_vertical = y
	_refresh_page_bar()


## 翻到第 i 页（越界会被夹到首/末页）。
func _goto_page(i: int, deferred := false) -> void:
	if not _ensure_pages():
		return
	_page_index = clampi(i, 0, _page_tops.size() - 1)
	_scroll_to_page(deferred)


## 翻一页。delta = -1 上一页 / +1 下一页。
##
## **到头就原地不动**：第 0 页再往回、末页再往前都是 no-op ——
## 不能回绕（那会让"读完了"变成"跳回开头"，很吓人），也不能归零。
func _turn_page(delta: int) -> void:
	if not _preview_paged or delta == 0:
		return
	if not _ensure_pages():
		return
	var want := clampi(_page_index + delta, 0, _page_tops.size() - 1)
	if want == _page_index:
		return
	_page_index = want
	_scroll_to_page(false)


func _on_page_prev_pressed() -> void:
	_turn_page(-1)


func _on_page_next_pressed() -> void:
	_turn_page(1)


## 翻页模式的输入。**接在 RTL 上**（`_setup_preview` 里连的）。
##
## Godot 的 GUI 分发是"从鼠标下最上层控件往上冒"，`accept_event()` 能挡住祖先 SC ——
## **实测确认**（README §7.20 ⑬）：不 accept 时外层 `scroll_vertical` 0 → 108，
## accept 之后停在 0。前提是 `rtl.mouse_filter == STOP`（实测成立）。
##
## **不翻页模式时一个字都不做、也不 accept** —— 滚轮照旧冒泡到外层 SC，
## 和改动前逐位相同。这条 early-return 是整个功能"默认行为零变化"的落点。
func _on_preview_rtl_gui_input(ev: InputEvent) -> void:
	if not _preview_paged:
		return
	if ev is not InputEventMouseButton:
		return
	var mb := ev as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		# 滚轮**永远**被吃掉（哪怕已经在头/尾页）：翻页模式下正文就不该能自由滚动，
		# 放一个滚轮下去会变成"翻了一页又滑了半屏"，比不动还难受。
		_turn_page(-1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		preview_rtl.accept_event()
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_click_pos = mb.position
		_click_arming = true
		return
	if not _click_arming:
		return
	_click_arming = false
	# 位移超过阈值 = **拖选文字**，不翻页。`RTL.selection_enabled` 是开着的，
	# 没有这一条的话选字会顺带翻一页，等于没法复制正文。
	if (mb.position - _click_pos).length() > PREVIEW_CLICK_SLOP:
		return
	# 左半屏上一页、右半屏下一页。用 **RTL 自己的宽**取半，不是窗口或 SC 的 ——
	# 选了"阅读宽度"之后正文列是居中的，按窗口取半会和用户看到的半屏对不上。
	_pending_turn = -1 if mb.position.x < preview_rtl.size.x * 0.5 else 1
	_resolve_pending_turn.call_deferred()


## 抬手时登记的那个翻页决定，在这里兑现 —— **存在的唯一理由是"点链接不翻页"**。
##
## 为什么不能直接在抬手处判：`meta_clicked` 排在 `gui_input` 信号**之后**。
## 这是**实测**出来的次序（README §7.20 ⑬）：
##     ["gui_input:press", "gui_input:release", "meta_clicked", "deferred"]
## 所以"meta_clicked 置标志、点击处理器读标志"这种护栏**永远失效**，
## 而且失效得**很安静**：不报错、不崩，只是每点一次链接就多翻一页。
## 延迟一步再问就没这个问题 —— 实测 `deferred` 排在 `meta_clicked` **之后**。
##
## （也试过别的路，全死了：`is_meta_hovered()` 在 4.7 里**不存在**；
## `meta_hover_started/ended` 在鼠标精确落在链接上时**一次都不发**；
## RTL 的 meta 相关方法只有 push/set/remove/get_meta_list 那八个，
## **没有任何一个能回答"鼠标下的字是不是链接"**。）
func _resolve_pending_turn() -> void:
	var d := _pending_turn
	_pending_turn = 0
	var was_link := _preview_meta_clicked_frame
	_preview_meta_clicked_frame = false
	if d != 0 and not was_link:
		_turn_page(d)


## 阅读区尺寸变了 → 每页装得下的量变了 → 页码表作废。
##
## **只置脏 + 帧末合并重算，不在这里同步跑走查**：拖动分隔条会连发 resized，
## 同步重算就是每帧一次全篇走查（12 万字符 10.2ms/帧），拖动会明显发涩。
## 合并之后**仍然是每帧最多一次**，但至少不会一次信号一次 ——
## 而且滚动模式下这个函数什么都不做（表根本用不上）。
func _on_preview_sc_resized() -> void:
	_invalidate_pages()
	if _preview_paged:
		_queue_page_refresh()


## 纯函数：1234567 → "1,234,567"。只为了让那句"文件太长"好读。
static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out


func _update_preview_toggle_button() -> void:
	# set_pressed_**no_signal**：set_pressed() 会发 toggled（这里是 pressed），
	# 程序化同步一下就绕回 _on_preview_toggle_pressed 再跑一遍。
	# 和 _set_view() 里同步那两个视图按钮用的是同一条规矩。
	preview_toggle_button.set_pressed_no_signal(_preview_enabled)


# ---------------- 预览面板的事件 ----------------

func _on_preview_toggle_pressed() -> void:
	_preview_enabled = preview_toggle_button.button_pressed
	_update_preview()


## 编辑器里的文本变了。
##
## **闸门按"模式"而不是"可见性"关**，这一点容易写错：没打开文件时右栏是**可见的**
## （空壳，见 _should_show_preview_rail），按可见性判的话，用户随手敲几个字就会
## 把内容当小说排进右栏 —— 明明没有文件可预览。
##
## 除了这道闸门，它还是省 CPU 的关键：编辑器里完全可能开着几 MB 的 .py / .json，
## 没这道闸门就是每敲一键排一次版，白烧 CPU 还什么都看不见。
func _on_preview_text_changed() -> void:
	if _effective_preview_mode() == PreviewMode.NONE:
		return
	_preview_timer.start()


func _on_preview_debounce_timeout() -> void:
	# 只重排，不重新判定开关/模式：这 200ms 里用户没可能换文件，
	# 而 _update_preview() 会把防抖 Timer 停掉，等于自己踩自己。
	# 但模式还是要现问一次 —— 这 200ms 里文件**确实**可能被删掉（模式就变 NONE 了）。
	var mode := _effective_preview_mode()
	if mode == PreviewMode.NONE:
		return
	_render_preview(mode)


func _on_preview_mode_button_pressed() -> void:
	_popup_preview_menu(_preview_mode_menu, preview_mode_button)


func _on_preview_font_button_pressed() -> void:
	_popup_preview_menu(_preview_font_menu, preview_font_button)


## 弹菜单，并把"当前选中项"标出来。
##
## **必须显式给坐标**：Godot 4 的无参 popup() 弹在 (0,0)，不读鼠标位置 ——
## 那是 Godot 3 的行为，别按老文档想当然（README §7.16 记着这条）。
## rect 吃的是**视口局部坐标**，和 _open_item_menu_at 用的是同一套约定。
func _popup_preview_menu(menu: PopupMenu, anchor: Control) -> void:
	if menu == null:
		return
	_sync_preview_menu_checks(menu)
	menu.popup(Rect2i(Vector2i(anchor.get_global_rect().position), Vector2i.ZERO))


## 把"当前生效的那一项"打上勾。
##
## ⚠️ 原来这里是「mode 菜单 early-return，**其余一律当字号菜单**」，加第三个菜单就会
## 静默串台：阅读菜单的 id 0..4 会被拿去索引 PREVIEW_FONT_SIZES，打错勾；id 12 直接下标越界。
## 所以改成三个菜单**各认各的**，最后一个分支才是字号，并且带上下界检查 ——
## 未知菜单宁可一个勾都不打，也不要去索引一张不属于它的表。
func _sync_preview_menu_checks(menu: PopupMenu) -> void:
	for i in menu.item_count:
		# 分隔线和组标题都不该有勾（组标题还是 disabled 的，打勾更怪）。
		if menu.is_item_separator(i):
			continue
		var id := menu.get_item_id(i)
		if id == READING_ID_HEADER:
			continue
		var on := false
		if menu == _preview_mode_menu:
			on = id == _preview_mode_override
		elif menu == _reading_menu:
			on = _reading_is_current(id)
		elif menu == _preview_font_menu:
			on = id >= 0 and id < PREVIEW_FONT_SIZES.size() \
				and PREVIEW_FONT_SIZES[id] == _preview_font_size
		menu.set_item_checked(i, on)


## 阅读菜单里，这个 id 是不是当前生效的那一档。
##
## 判断顺序就是"从大到小"：五段的基准是 40 / 30 / 20 / 10 / 0，所以 `>= 基准` 就是从最大
## 那段开始回落 —— 写成从小到大会全部落进"行距"那一段（`id=42 >= 0` 就返回了）。
##
## ⚠️ **加新段必须给它一个比现有最大值更大的基准，并且插在链子的最前面**。
## 新段基准比某个旧段小的话，它会被那个旧段**整个吞掉**：不崩，只是永远打错勾。
func _reading_is_current(id: int) -> bool:
	if id >= READING_ID_PAGED:
		var p := id - READING_ID_PAGED
		return p < PREVIEW_PAGED_LABELS.size() and (p == 1) == _preview_paged
	if id >= READING_ID_SCHEME:
		var s := id - READING_ID_SCHEME
		return s < Palette.NAMES.size() and s == _preview_scheme
	if id >= READING_ID_PAGE_WIDTH:
		var w := id - READING_ID_PAGE_WIDTH
		return w < PREVIEW_PAGE_WIDTHS.size() and PREVIEW_PAGE_WIDTHS[w] == _preview_page_width
	if id >= READING_ID_INDENT:
		var n := id - READING_ID_INDENT
		return n < PREVIEW_INDENTS.size() and PREVIEW_INDENTS[n] == _preview_indent
	var k := id - READING_ID_LINE_SCALE
	return k >= 0 and k < PREVIEW_LINE_SCALES.size() \
		and PREVIEW_LINE_SCALES[k] == _preview_line_scale


## 往阅读菜单里加一段：一个禁用的组标题 + 若干选项。
## 选项 id = 基准 + 下标（见 READING_ID_* 那组常量）。
func _add_reading_section(menu: PopupMenu, title: String, labels: Array, base_id: int) -> void:
	menu.add_item(title, READING_ID_HEADER)
	menu.set_item_disabled(menu.item_count - 1, true)
	for i in labels.size():
		menu.add_item(String(labels[i]), base_id + i)


func _on_preview_mode_id_pressed(id: int) -> void:
	_preview_mode_override = id as PreviewOverride
	# 手动选模式**顺带把右栏打开**：用户点"更改预览器"就是想看东西，
	# 如果上一轮用 Preview 按钮把栏关了，这里不打开的话点了像没反应。
	if _effective_preview_mode() != PreviewMode.NONE:
		_preview_enabled = true
		_update_preview_toggle_button()
	# 模式变了行距比例也跟着变（见 _apply_preview_font_size），要重铺一次
	_apply_preview_font_size()
	_update_preview()


func _on_preview_font_id_pressed(id: int) -> void:
	if id < 0 or id >= PREVIEW_FONT_SIZES.size():
		return
	_preview_font_size = PREVIEW_FONT_SIZES[id]
	_apply_preview_font_size()
	# 字号还喂给了 MarkdownToBbcode 当基准（标题字号按它算），所以得整篇重排，
	# 不是只调主题就完事。
	_update_preview()
	_save_reading_settings()


# ---------------- 阅读设置（五项可调） ----------------

func _on_preview_reading_button_pressed() -> void:
	_popup_preview_menu(_reading_menu, _reading_button)


## 阅读菜单里选了一项。**每个 setter 的重渲染粒度不同**，这是本函数唯一要小心的地方：
##
## | 改的是 | 要做什么 | 为什么 |
## |---|---|---|
## | 行距 | 重设主题常量 | 只影响 RTL 的排版参数，重跑转换器纯属白烧 |
## | 缩进字宽 | **整篇重排** | 缩进是转换器拼进字符串里的（全角空格） |
## | 阅读宽度 | 重设 SC 的 min 尺寸 | 布局参数，同上 |
## | 翻页模式 | 重设 SC 的滚动形式 + 重建分页表 | 布局参数，同上；分页表是**惰性**重算的 |
## | 阅读主题 | **整篇重排** | 那 10 处 `[color=]` 是拼在输出串里的 |
##
## 主题这一条最容易想当然：`_apply_preview_scheme()` **不够**，它只覆盖 RTL 的主题项，
## 而 `[color=...]` 的优先级**高于**主题项 —— 代码块底色、链接、引用、标题一处都不会变。
## 所以主题必须先 apply 再整篇重排（retint 在转换器返回前跑）。
func _on_preview_reading_id_pressed(id: int) -> void:
	if id < 0:
		return          # 组标题（disabled，正常点不到，但显式挡一下比越界崩掉便宜）
	if id >= READING_ID_PAGED:
		var p := id - READING_ID_PAGED
		if p >= PREVIEW_PAGED_LABELS.size() or (p == 1) == _preview_paged:
			return
		_preview_paged = p == 1
		# 和"阅读宽度"同档：只改布局，**不重跑转换器**（同一份 BBCode 换个滚法）。
		_apply_preview_paged()
	elif id >= READING_ID_SCHEME:
		var s := id - READING_ID_SCHEME
		if s >= Palette.NAMES.size() or s == _preview_scheme:
			return
		_preview_scheme = s
		_apply_preview_scheme()
		_update_preview()
	elif id >= READING_ID_PAGE_WIDTH:
		var w := id - READING_ID_PAGE_WIDTH
		if w >= PREVIEW_PAGE_WIDTHS.size() or PREVIEW_PAGE_WIDTHS[w] == _preview_page_width:
			return
		_preview_page_width = PREVIEW_PAGE_WIDTHS[w]
		_apply_preview_page_width()
	elif id >= READING_ID_INDENT:
		var n := id - READING_ID_INDENT
		if n >= PREVIEW_INDENTS.size() or PREVIEW_INDENTS[n] == _preview_indent:
			return
		_preview_indent = PREVIEW_INDENTS[n]
		_update_preview()
	else:
		var k := id - READING_ID_LINE_SCALE
		if k < 0 or k >= PREVIEW_LINE_SCALES.size() or PREVIEW_LINE_SCALES[k] == _preview_line_scale:
			return
		_preview_line_scale = PREVIEW_LINE_SCALES[k]
		_apply_preview_font_size()
	# 关掉菜单就落盘。**不节流**：这几项都是人手点出来的，一次点击一次写盘远比
	# "拖了半天忘保存"划算。真正的重活（重排）已经在上面按各自的粒度做完了。
	_save_reading_settings()


func _on_preview_toc_toggle_pressed() -> void:
	if _toc_tree == null:
		return
	# 没目录就不给开：右栏只有 274px 宽，开一个空框纯占地方。
	_toc_tree.visible = _toc_toggle_button.button_pressed and not _chapters.is_empty()
	if _toc_toggle_button.button_pressed and _chapters.is_empty():
		# 按钮自己回弹，否则它会显示成"开着"而框是空的，下次点又什么都不发生。
		_toc_toggle_button.set_pressed_no_signal(false)


func _on_toc_item_selected() -> void:
	var item := _toc_tree.get_selected()
	if item == null:
		return
	var p: Variant = item.get_metadata(0)
	if p == null:
		return
	_jump_to_paragraph(int(p))


## 跳到第 p 段（0 基）。段落号 = **输出** BBCode 的行号，见 to_bbcode_with_toc 的头注释。
##
## 整个跳转就这一行，因为 `get_paragraph_offset()` 直接给出该段的垂直像素偏移，
## 而且**跟随折行**（实测：宽度 274→160 时同一段 595→1094）——
## 于是"按字体度量自己估算折行"那套方案根本不需要。
##
## 为什么读 offset 前不用等帧：目录是**点击**触发的，点的时候 RTL 早已按当前文本排完版
## （没有任何一条路径会"改完 text 立刻跳"）。但要滚的**不是 RTL 自己** ——
## `fit_content = true` 让它正好和内容等高、自己没得滚，滚动条在外层 ScrollContainer 上，
## 所以落点必须设在 SC 上，并且要 `set_deferred`（同 _render_preview 的理由：
## 索引刚变时 SC 的滚动上限可能还是旧值，直接写会被按旧上限夹一次）。
func _jump_to_paragraph(p: int) -> void:
	var sc := preview_rtl.get_parent() as ScrollContainer
	if sc == null:
		return
	if p < 0 or p >= preview_rtl.get_paragraph_count():
		return
	var y := int(preview_rtl.get_paragraph_offset(p))
	if _preview_paged:
		# 翻页模式下**吸附到该段所在页的页首**，不直接落到段落偏移上 ——
		# 否则跳过去的位置在页中间，下一页就从半路开始了（同一页里会读到两段半）。
		# 段首 → 页号走的是和翻页、重排复位同一套反查。
		#
		# ⚠️ 这里用**立即写**，不是 set_deferred。上面那段"点击触发，RTL 早已排完版"
		# 的推理对滚动作数同样成立，所以不存在"上限还是旧值"的问题。
		# 而延迟写会开一个窗口：从这次调用到帧末真正写下去之间，任何一次表重建都会把
		# `_page_index` 按**当时还没更新的 scroll** 反推一遍，把刚定好的页码冲掉。
		# 立即写没有这个窗口。
		if _ensure_pages():
			_page_index = _page_index_for(y)
			_scroll_to_page(false)
			return
		# 表还建不起来（高度为 0）就退回落点写法，至少不比改动前差。
	sc.set_deferred("scroll_vertical", y)


## 换一份目录。**只有真的变了才重建列表。**
##
## 这条门控是打字场景的性能关键：防抖每 200ms 重排一次，而重排必然带出新的 chapters
## 数组 —— 但用户敲的是正文，章节一个都没变。无条件重建的话，打字时目录每 200ms
## 清空重填一次（还会把用户展开的层级、滚动位置全抖掉）。
func _set_chapters(chapters: Array) -> void:
	if _same_chapters(chapters):
		return
	_chapters = chapters
	_rebuild_toc()


## 新旧目录是不是同一份。**只比 title / paragraph / level** —— source_line 是给调试看的，
## 改个空行就会变，拿它参与比较会让"只挪了空行"也触发重建。
func _same_chapters(other: Array) -> bool:
	if other.size() != _chapters.size():
		return false
	for i in other.size():
		var a: Dictionary = _chapters[i]
		var b: Dictionary = other[i]
		if String(a.get("title", "")) != String(b.get("title", "")):
			return false
		if int(a.get("paragraph", -1)) != int(b.get("paragraph", -1)):
			return false
		if int(a.get("level", 0)) != int(b.get("level", 0)):
			return false
	return true


## 重建目录树。层级靠 level（1 = 卷/部/篇，2 = 章）嵌套，用栈做父子推导。
##
## 栈的做法照 FileTree 那套"代码建树"的模板（hide_root + create_item），
## 唯一多出来的就是 level 的父子关系。
func _rebuild_toc() -> void:
	if _toc_tree == null:
		return
	_toc_tree.clear()
	var root := _toc_tree.create_item()
	# 栈里存的是"每一层最近的那个条目"：stack[0] = 最近的 level 1，stack[1] = 它下面的 level 2。
	var stack: Array[TreeItem] = []
	for c in _chapters:
		var level: int = maxi(1, int(c.get("level", 2)))
		# 回退到"这一层的父层"。level 1 会把栈清空，于是下一个 level 1 又是顶级。
		while stack.size() >= level:
			stack.pop_back()
		# 栈空 = 这一层没有父（比如一章都没有就来了个 level 2）—— 挂到根上，
		# 不能让它落不下去：挂不上就等于整条目录少了几章，而且不报错。
		var parent: TreeItem = root if stack.is_empty() else stack[stack.size() - 1]
		var item := _toc_tree.create_item(parent)
		var title := String(c.get("title", ""))
		item.set_text(0, title)
		item.set_metadata(0, int(c.get("paragraph", 0)))
		# 提示里**必须带上标题全文**，不能只有段落号。右栏固定 274px，而目录的左缩进
		# 每层还要吃十几个像素 —— 长标题（"第一章 在那个下着大雨的傍晚我终于想起来了"）
		# 在树里一定是被**裁掉**的。单列 Tree 的列宽会撑满树宽，所以溢出部分连横向
		# 滚动条都出不来（不是没开，是根本没有溢出）。悬停提示是唯一能读到全文的地方。
		item.set_tooltip_text(0, "%s\n（第 %d 段）" % [title, int(c.get("paragraph", 0)) + 1])
		stack.append(item)

	# 没章节时把目录收掉：不留空框，也不留一个"看似开着"的按钮。
	var has := not _chapters.is_empty()
	_toc_toggle_button.disabled = not has
	if not has and _toc_tree.visible:
		_toc_tree.visible = false
		_toc_toggle_button.set_pressed_no_signal(false)


# ---------------- 阅读设置的持久化 ----------------
#
# 走 DSettingsManager（不是 DSaveManager）：阅读偏好语义上是"设置"不是"存档进度"，
# 塞进存档会把 last_modified_timestamp 顶来顶去、还多弹一条顶部消息。
#
# 形状照抄 _load_favorites() / _save_favorites()，只有守卫不同：
# 存档那边判的是 save_name == ""，设置这边判的是 **settings == null**。
# 那个 null 是**真的会出现**的：settings 是 call_deferred 加载的，见 _setup_preview() 尾注释。

## 把当前五项（外加字号、手动模式）读回来。
##
## ⚠️ **最后必须把五个应用函数全调一遍**，尤其是 `_update_preview()` ——
## 少了它，存盘的值**永远不会生效**：不是"第一帧先用默认值"那么轻，是按了重启还是不生效。
## 因为 _preview_* 只在设置菜单的 setter 里被应用，而设置菜单要用户点一下才会走。
func _load_reading_settings() -> void:
	if DSettingsManager.settings == null:
		return
	var s: DerSettingsRes = DSettingsManager.settings

	# 每一项都**先验档位表里有没有**再认。设置文件是可以被手改、也可以来自旧版本的，
	# 直接赋值的话，一个越界的下标会让菜单打不出任何勾（而不是报错），很难查。
	if PREVIEW_FONT_SIZES.has(s.preview_font_size):
		_preview_font_size = s.preview_font_size
	if PREVIEW_LINE_SCALES.has(s.preview_line_scale):
		_preview_line_scale = s.preview_line_scale
	if PREVIEW_INDENTS.has(s.preview_indent):
		_preview_indent = s.preview_indent
	if PREVIEW_PAGE_WIDTHS.has(s.preview_page_width):
		_preview_page_width = s.preview_page_width
	if s.preview_scheme >= 0 and s.preview_scheme < Palette.NAMES.size():
		_preview_scheme = s.preview_scheme
	# 布尔项不需要"档位表里有没有"那套校验（它只有两个合法值，读出来必然是其一）。
	_preview_paged = s.preview_paged
	# 用 AUTO..MARKDOWN 这个闭区间，不写 `PreviewOverride.size()`：枚举名字在这里是
	# 常量字典，`.size()` 能不能用要看解析上下文，而闭区间是白纸黑字、也不会因为
	# 以后往中间插一个模式而悄悄放宽。
	if s.preview_mode_override >= int(PreviewOverride.AUTO) \
			and s.preview_mode_override <= int(PreviewOverride.MARKDOWN):
		_preview_mode_override = s.preview_mode_override as PreviewOverride

	# 五项各自的"应用层"，一个都不能漏：
	_apply_preview_font_size()     # 字号 + 行距（主题常量）
	_apply_preview_scheme()        # 配色（RTL 主题项）
	_apply_preview_page_width()    # 页宽（外层 SC 的 min 尺寸）
	_apply_preview_paged()         # 翻页模式（外层 SC 的滚动模式）—— 同理，只改布局
	_update_preview()              # 缩进 / 配色（转换器）—— 顺带把右栏该不该显示也判一次


## 落盘。`settings == null` 时**直接不写**：那说明设置模块还没 deferred 加载完，
## 这时候新建一个 DerSettingsRes 覆盖上去，会把用户已存的音频/画面/语言全冲成默认值。
func _save_reading_settings() -> void:
	if DSettingsManager.settings == null:
		return
	var s: DerSettingsRes = DSettingsManager.settings
	s.preview_font_size = _preview_font_size
	s.preview_mode_override = int(_preview_mode_override)
	s.preview_line_scale = _preview_line_scale
	s.preview_indent = _preview_indent
	s.preview_page_width = _preview_page_width
	s.preview_scheme = _preview_scheme
	s.preview_paged = _preview_paged
	DSettingsManager.save_settings()


## 点预览里的链接。**这里再挡一次白名单**。
##
## 转换器那道（MarkdownToBbcode.safe_url）已经挡过了，这里是第二道，不是冗余：
## 预览文本将来可能从别的路径塞进来，而 OS.shell_open 是**用户内容直接驱动系统调用**
## 的唯一一处 —— javascript: 交给默认浏览器是什么后果取决于机器上装了什么。
## 两道防线的代价总共是一次字符串比较。
func _on_preview_meta_clicked(meta: Variant) -> void:
	# **第一行就置标志**，位置是有讲究的：翻页模式的点击护栏靠它
	# （_resolve_pending_turn 在帧末读，那时它一定已经置起来了 —— 实测次序见那里）。
	# 放在 safe_url 之后、shell_open 之前都不行：`javascript:` 这类被挡掉的链接
	# 也是"点到了链接"，同样不该顺带翻一页。
	_preview_meta_clicked_frame = true
	var url := MarkdownToBbcode.safe_url(str(meta))
	if url == "":
		return
	OS.shell_open(url)
