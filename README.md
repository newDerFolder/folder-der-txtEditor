# FolderDerTextEditor

一个用 Godot 做的**纯文本编辑器**：左边是文件夹树，右边是编辑区。定位很明确——不追求做 VS Code，只求打开快、能顺着目录翻文件、能改能存。

- 引擎：**Godot 4.7**（`GL Compatibility` 渲染后端）
- 语言：纯 GDScript，没有 C#
- 平台：Windows（`export_presets.cfg` 只有 Windows Desktop 一项）
- 体量：业务代码就是 `page/main.tscn` + `page/main.gd`（约 800 行，其中不小一部分是解释性注释）。
  另有一个框架 addon `addons/der_framework` 注册了 4 个 autoload，但本应用只用到其中
  一个顶部提示接口（见第 3 节）

---

## 1. 跑起来

本机 PATH 上没有 `godot`，引擎在：

```
C:/Users/kldermr/Downloads/Godot_v4.7-stable_win64.exe
```

```bash
# 直接运行
"/c/Users/kldermr/Downloads/Godot_v4.7-stable_win64.exe" --path /c/godotProject/folder-der-txtEditor

# 用编辑器打开
"/c/Users/kldermr/Downloads/Godot_v4.7-stable_win64.exe" -e --path /c/godotProject/folder-der-txtEditor
```

导出配置已经写好，产物固定落在项目外的 `../../app/FolderDerTextEditor.exe`。

---

## 2. 改完代码怎么验证（**新接手的人先看这节**）

没有 CI、没有单元测试框架。这个项目的验证靠两招：

### 第一招：语法检查（秒级，先跑这个）

```bash
"/c/Users/kldermr/Downloads/Godot_v4.7-stable_win64.exe" \
  --headless --path /c/godotProject/folder-der-txtEditor \
  --check-only --script res://page/main.gd
```

**⚠️ 这条命令对 `main.gd` 永远返回 1，不代表你的代码有问题。**
`--check-only` 模式下 autoload 不会注册，所以它必定先报这一条：

```
SCRIPT ERROR: Compile Error: Identifier not found: DMessageManager
```

（`DMessageManager` 是 `addons/der_framework` 注册的 autoload，见第 3 节。）

所以**别拿退出码当结论**，要看输出里有没有**别的**报错 —— 出现 `DMessageManager`
以外的 `Parse Error` / `Compile Error` 才是真问题。这招确实能抓语法错误（实测：故意写一行
非法语法，退出码 1 并报 `Parse Error`），只是没法在这种模式下给你一个"干净通过"的信号。

对不依赖 autoload 的独立脚本，退出码才是可用的：0 = 没问题。

想真正跑通一遍，用第二招（它会加载 autoload，`main.gd` 能正常编译）。

### 第二招：临时 harness（行为验证）

`--check-only` 只能告诉你"语法对"，不能告诉你"点下去会怎样"。要验行为就写一个临时的 `extends SceneTree` 脚本：

```gdscript
extends SceneTree

const FIX := "C:/Users/kldermr/AppData/Local/Temp/fdt_c"   # 测试用的临时目录

func _initialize() -> void:
	_run()

func _run() -> void:
	var scene = load("res://page/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame          # 必须等：_initialize() 跑在节点的 _ready() 之前，
	await process_frame          # 不等的话 @onready 的变量还是 null
	scene.set_root_dir(FIX)
	await process_frame

	# ... 这里写断言 ...
	# scene._item_path(...)、scene._is_editable_file(...) 这些私有函数可以直接调
	quit(0)
```

跑法：

```bash
timeout -k 5 90 "/c/.../Godot_v4.7-stable_win64.exe" \
  --path /c/godotProject/folder-der-txtEditor --script res://_tmp_verify.gd
```

**用完务必删掉 `_tmp_verify.gd` 和 `_tmp_verify.gd.uid`**，别留在项目里。

### 写 harness 时踩过的七个坑

1. **必须带窗口跑，不要加 `--headless`。** Tree 控件在 headless 下不暴露某些崩溃——历史上那次段错误就是带窗口才复现的。
2. **stdout 被重定向/管道时是块缓冲的**，进程被 `timeout` 杀掉就一个字都不剩。每条断言都同时 `print` **并追加写一个文件**（写完立刻 `close()`），这样即使挂起也能看到跑到哪一步了。
3. **类型推断的报错很啰嗦**：`var r := tree.get_item_area_rect(...)` 会报 `Cannot infer the type`，得写成 `var r: Rect2 = ...`。凡是从引擎方法拿到的返回值，习惯性加上显式类型注解，能省掉一大堆来回。
4. **合成输入可以走完整管线**：`Input.parse_input_event()` 对鼠标点击、双击（第二下带 `double_click = true`）、键盘按修饰键都有效，能端到端验真实输入路径。但**弹过 PopupMenu 之后再合成输入会挂住**，遇到这种就改成直接调用处理函数。
5. **合成双击时，两下之间必须 `await process_frame`。** 在同一个事件批次里连着塞两个 press，
   Tree 的行为和真实双击**不一样**（实测：连塞时 `item_selected` 一次都不发，而真实双击的第一下是会发的），
   照着它得出的结论会把你带偏 —— 这个坑真踩过，白改了一版代码。真实双击的两下相隔上百毫秒、必然跨帧，
   所以留一帧才是对的。
6. **按下之前先自检落点**：`get_item_area_rect()` 给的是**内容坐标**（不含滚动偏移），
   而合成事件要的是 Tree 局部坐标，得减掉 `get_scroll()`。算错了就会点在空气上，
   所有断言都会"失败"，看起来像功能坏了。加一句
   `tree.get_item_at_position(pos) == 目标条目` 的自检，能立刻把这类假故障和真故障分开。
7. **harness "卡住"了，先去看 stderr 里有没有 `SCRIPT ERROR`。** 编辑器二进制跑脚本时，
   脚本运行时报错（比如动态读了一个**不存在的成员**）会让进程停在那里不退，
   表现和死锁一模一样 —— 文件日志停在某一行，`timeout` 到点杀进程，退出码 124。
   这个坑花了好几轮才定位：当时写的是 `scene._rename_dialog.hide()`，而本应用里根本没有
   `_rename_dialog` 这个成员（`@onready` 的那个叫 `rename_dialog`，没有下划线前缀），
   于是先怀疑 `hide()` 有问题、再怀疑"两个弹框同时可见"有问题、又怀疑帧内重入 ——
   全错。前两个都写了最小复现（裸 `ConfirmationDialog` 一 pop 一 hide、以及两个弹框同时可见
   再 hide 其中一个）实测过，**都不卡**，所以这不是引擎的毛病，也和应用代码无关。
   **症状是"卡住"，病因是拼错了一个属性名。**
   所以：别把 stderr 丢掉（`> /dev/null 2>&1` 会让你看不见它），
   上面第 2 条的文件日志负责告诉你**停在哪一行**，stderr 负责告诉你**为什么**。

   （顺带一个省时间的结论：4.7 的 `PopupMenu` **没有 `activate_item()`**，别想着用它模拟
   "点了菜单第 N 项"。想验菜单 id 直接 `menu.get_item_id(i)` 逐个对，想验处理函数
   直接 `menu.id_pressed.emit(id)`。）

---

## 3. 目录结构

### 活着的文件

| 路径 | 作用 |
|---|---|
| `page/main.tscn` | 唯一的场景。整个 UI 都在这里 |
| `page/main.gd` | 唯一的脚本。全部逻辑 |
| `resource/folder.tres` | 主题，只设了 `TextEdit/font_sizes/font_size = 20` |
| `resource/new_code_highlighter.tres` | 语法高亮配色，挂在 TextEdit 的 `syntax_highlighter` 上 |
| `asset/bg/tsBgHF.png` | 编辑区的背景图（`TextureRect`） |
| `asset/icon/folder.png` | 目录图标 |
| `asset/icon/folderTxt.png` | **可编辑**文件的图标 |
| `asset/icon/UnsupportedEditIcon.png` | **不可编辑**文件的图标 |
| `asset/icon/saveIcon.png` `txtIcon.png` `folderIcon.png` | 工具栏按钮的图标 |
| `scene/SettingWin.tscn` | 设置窗口。**按钮当前是隐藏的**（见下），等于没启用 |
| `export_presets.cfg` | Windows 导出配置 |
| `addons/der_framework/` | **活着的，不是死的**。`project.godot` 里 4 个 autoload 全是它的场景：`DerMain` / `DerMessage` / `DerSave` / `DerSettings`。`main.gd` 保存成功时那行顶部提示就来自 `DMessageManager.add_top_message()`（`main.gd:182`），**这是本应用唯一用到它的地方**；另外三个 autoload 被加载着但 `main.gd` 没碰 |
| `addons/godot_ai/` | 第三方 MCP 插件（Godot AI 工具链），**和编辑器业务逻辑完全无关**。它的 autoload `_mcp_game_helper` 是自己注册的 |

### 死的文件（别浪费时间研究）

| 路径 | 说明 |
|---|---|
| `scene/FileItemButton.tscn` | **没有任何地方引用**，是早期方案的残留 |
| `asset/icon/settingIcon.png` | 没被任何场景引用 |
| `asset/bg/loadingBg.png`、`asset/bg/tsBg.png` | 没被引用，只用了 `tsBgHF.png` |

> 顺带一提：光 `addons/` 两个目录加起来就有 300 多个文件，搜索时建议排除，否则结果会被淹掉。

---

## 4. `main.gd` 代码地图

文件按功能分了几块，找代码按这个顺序定位（行号会漂，以函数名为准）：

| 区域 | 关键函数 | 干什么的 |
|---|---|---|
| **配置常量**（文件头） | `TEXT_EXTENSIONS` `SKIP_DIRS` `MAX_TREE_DEPTH` `ICON_*` | 扩展名白名单、跳过的目录、递归深度上限、图标路径 |
| **启动** | `_ready()` | 建树、读命令行参数、连信号 |
| **存/开** | `open_and_show()` `save_file()` `_on_save_as_file_selected()` | 读写文件。**所有数据风险的源头都在这一块** |
| **快捷键** | `_input()` | Ctrl+S / Ctrl+Shift+S / Ctrl+O / F11 / 缩放 / 小地图 |
| **右键菜单** | `_setup_item_menu()` `_on_file_tree_gui_input()` `_build_item_menu()` `_on_menu_id_pressed()` | 见第 6 节 |
| **新建文件** | `_prompt_new_file()` `_default_new_file_name()` `_on_new_file_confirmed()` | 只对目录出现。默认名 `新建文件.txt`，撞名自动往后数 (2) (3) |
| **重命名** | `_prompt_rename()` `_validate_new_name()` `_on_rename_confirmed()` | 校验拆成了纯函数，方便不起弹窗就能测 |
| **名字校验** | `_validate_name_in_dir()` | 空名 / 非法字符 / 撞名三档，**新建和重命名共用这一套**（`_validate_new_name()` 只是委托它），省得两边各自长歪 |
| **删除** | `_prompt_delete()` `_on_delete_confirmed()` | 走系统回收站 |
| **文件树** | `_setup_file_tree()` `set_root_dir()` `refresh_file_tree()` `_populate_dir()` | 建树、换根、刷新、递归填充 |
| **折叠状态** | `_collect_collapsed_paths()` `_restore_collapsed_paths()` | 刷新时保住用户的折叠状态 |
| **条目判定** | `_item_path()` `_item_is_dir()` `_is_editable_file()` `_is_under()` | 几个纯查询函数 |
| **点击** | `_on_file_tree_item_selected()` `_on_file_tree_item_activated()` `_on_open_as_text_confirmed()` | 单击 / 双击 两条不同的路 |

---

## 5. 三个核心状态

理解这三样，代码基本就通了：

### `current_file_path: String`

当前编辑器里的内容对应的磁盘文件。**空串 = 没有对应文件**（可能是新写的、也可能刚被删掉）。

它是好几处危险的枢纽：`save_file()` 直接 `FileAccess.open(current_file_path, WRITE)` **原地覆盖**。所以任何让这个路径"指错地方"的改动，都会变成数据丢失。规则：

- 重命名当前文件 → 必须同步更新它（否则 Ctrl+S 写回旧名字，凭空多一个文件）
- 删除当前文件（或它所在的目录）→ 必须置空（否则 Ctrl+S 把刚删的文件原地重建出来）

### `root_dir: String`

文件树的根目录。`set_root_dir()` 里有**同目录直接 return** 的守卫——这是防止每次点文件都重建整棵树、把所有折叠状态重置掉的关键。

### `TreeItem` 的 metadata

树里**每个条目**（目录和文件都有）都挂一个字典：

```gdscript
item.set_metadata(0, {"path": "/abs/path", "dir": true/false})
```

早期只有文件挂 metadata、目录靠 `metadata == null` 反推，导致右键菜单拿不到目录路径，所以改成了统一字典。读的时候一律走 `_item_path(item)` / `_item_is_dir(item)` 这两个助手，别直接读 `get_metadata(0)`。

> 没有 metadata 的条目是"未指定目录"那个占位提示，`_item_path()` 会返回空串——多处守卫靠"空串"来判断"这不是个真条目"。

---

## 6. 交互行为总表

| 操作 | 目录 | 可编辑文件（`.txt` `.md` …） | 不可编辑文件（`.docx` `.pptx` …） |
|---|---|---|---|
| **单击** | 展开 / 折叠 | 载入编辑器 | **只选中高亮，不载入** |
| **双击** | 展开 / 折叠 | 载入编辑器 | **弹提醒 → 确认后按文本打开** |
| **右键** | **第一项「新建文件」** + 文件管理器 / 重命名 / 删除 / 复制路径 / 刷新 | 文件管理器 / 重命名 / 删除 / 复制路径 / 刷新 | 同上，**外加第一项「用默认程序打开」** |

几个反直觉的地方，都是故意的：

- **单击不可编辑的文件什么都不做**：读进来是二进制乱码，而 `current_file_path` 会被指过去，接着按 Ctrl+S 就把原文件覆盖成乱码了。
- **双击才是"强制按文本打开"**：这个入口主要给两种情况用——`.toml` / `.env` / `Dockerfile` 这类没进白名单但本来就是文本的文件；以及真想看看 `.docx` 里装了什么。会先弹一个提醒框。
- **双击目录 = 展开 / 折叠，但实现上有个弯**（详见 7.11）：Tree 把双击拆成"第一下当普通单击 + 第二下发 `item_activated`"，而第一下切没切取决于那一刻条目**是否已被选中**，所以第二下必须靠 `_toggled_path` 判断要不要补切。不判断就会在"未选中"那条路上切两次、净效果为零 —— 那正是之前"双击文件夹没反应"的原因，而且只在**已选中**的目录上才复现。
- **双击当前已打开的文件不重读**：否则顺手双击一下正在编辑的文件，没保存的改动当场被冲掉。
- **「新建文件」只对目录出现**：文件条目的上下文里没有说得通的目标目录。默认名是 `新建文件.txt`
  （`.txt` 在 `TEXT_EXTENSIONS` 白名单里，建完能直接编辑），同目录已有同名的就往后数成 `新建文件 (2).txt`。
  弹框里**预选的是主名、不含 `.txt`**（复用重命名那套 `_select_base_name_in()`），所以用户一打字就把
  "新建文件"整个替换掉、后缀留着 —— 这就是"默认 txt"落到实处的地方。
- **右键新建完会把新文件打开**（详见 7.14）：看着像副作用，其实是有意依赖的链路，别顺手把它去掉。

### 白名单

能直接编辑的扩展名在 `TEXT_EXTENSIONS`（文件头那个常量）。**没有扩展名的文件（`README`、`Makefile`、`LICENSE`）也算"不可编辑"**——判断不出类型时选了保守方向：宁可少编辑一个文本文件（改名成 `.txt` 就能编辑），也不要赌一把把二进制灌进编辑器。想编辑它们用双击。

加扩展名就往那个数组里加，一处生效（图标、单击行为、菜单项都跟着变）。

---

## 7. 【重点】引擎坑位 —— 这些是实测出来的，别照直觉改回去

这一节是整个文档里最值钱的部分。下面每一条都是踩过之后在代码注释里钉住的，**改之前先读注释**。

### 7.1 `file_tree.allow_reselect` 必须保持 `false`

开了它，Tree 在重选同一项时会重复发 `item_selected`。而折叠一个**已选中**的条目会触发 Tree 内部重选 → 于是形成 `折叠 → 重选 → 折叠` 的死循环，**每帧振荡，同步处理时直接段错误崩溃**。

### 7.2 右键不能接 `item_mouse_selected`

那个信号回调里给的 `mouse_position` 实测是**屏幕坐标**（窗口在屏幕上的位置也算进去了），而 `get_item_at_position()` 要的是 Tree 局部坐标，两者对不上，喂进去永远返回 `null`。

改用 `gui_input`，里面 `event.position` 才是局部坐标。

### 7.3 右键会连带触发 `item_selected`

也就是说：右键点一个文件，如果不拦，会把它载入编辑器。所以 `_on_file_tree_item_selected()` 开头有一道 `Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)` 的守卫。

### 7.4 Godot 4 的无参 `popup()` 弹在 `(0,0)`

**它不读鼠标位置**——那是 Godot 3 的行为，网上大量文档还在那么写。必须显式给坐标：

```gdscript
file_item_menu.popup(Rect2i(file_tree.get_global_position() + event.position, Vector2i.ZERO))
```

而且 `popup(rect)` 的 `rect` 吃的是**视口局部坐标**（窗口内容坐标系），不是屏幕坐标。

### 7.5 `TreeItem.collapsed` 默认是 `false`（展开）

所以 `refresh_file_tree()` 里保留的是**被折叠的**路径集合，不是展开的。记反了的话保存逻辑会变成空操作，用户手动折叠的目录会每次刷新都弹开。

### 7.6 Tree 会静默拒绝折叠"包含当前选中项"的目录

给那个目录赋 `collapsed = true` 当场读回来还是 `false`，不报错也不发信号。通过 UI 走不到这个状态，所以不用额外处理，但写测试时会遇到（别以为是自己的 bug）。

### 7.7 Tree 的 `icon_size` 主题常量在 4.7 对绘制尺寸无效

图标是按原始尺寸画的，源图 400×400 能把整行撑爆。所以 `_make_icon()` 在**加载时**就用 `Image.resize()` 统一重采样到 15×15，而不是靠主题常量。

### 7.8 `OS.alert()` 在 Windows 上是**阻塞**的

任何埋在它后面的分支都没法从脚本里驱动（测试会直接挂住）。所以校验逻辑拆成了纯函数——典型例子是 `_validate_new_name(old_path, new_name) -> String`，返回 `""` 表示可用，否则返回给用户看的原因。

### 7.9 场景里所有节点都带 `unique_id`

这是这套 tscn 格式的必需字段（`main.tscn` 里 44 个节点全都有）。**手写 tscn 加节点容易把 id 写错或写重**，所以新加的对话框（重命名的 `LineEdit`、"按文本打开"的提醒框）都是在代码里 `new()` 出来的，让 Godot 自己保存场景时落盘更安全。

### 7.10 `SettingButton` 的代码不在 `main.gd` 里

它用的是**内联在 `main.tscn` 里的 sub_resource GDScript**（搜 `GDScript_cee7s` 能看到），点了会 `load("res://scene/SettingWin.tscn")` 挂到按钮底下。

后果：在 `main.gd` 里 grep 是**找不到**设置按钮的处理的，别以为功能没实现。

而且该节点是 `visible = false` 的，等于整个设置窗口目前没启用。

### 7.11 Tree 的"双击"= 一次普通单击 + 一次 `item_activated`

实测（合成真实鼠标事件，两下之间留一帧）：

| 双击时条目状态 | 第一下 | 第二下 |
|---|---|---|
| 原本**没选中** | 发 `item_selected` —— 等于一次普通单击，目录会被顺势切一次 | 发 `item_activated` |
| 原本**已选中** | **什么都不发**（`allow_reselect = false` 把重选吞掉了） | 发 `item_activated` |

所以在 `item_activated` 里切换目录时，**必须先知道第一下有没有已经切过**：

- 未选中那条路：第一下已经切过了，再切一次正好抵消 → 看起来"双击没反应"
- 已选中那条路：第一下什么都没发生，这里**必须**补切一次

`_toggled_path` 就是干这个的：`gui_input` 在**非双击的**左键按下时清空它，`item_selected`
切过之后把路径写进去，`item_activated` 发现路径对得上就跳过。

> 双击的第二下（`double_click = true`）**不能**清这个变量，否则正好把要判断的东西抹掉。
> 这个 bug 只在"已选中"的目录上复现，所以单看未选中的目录会以为双击是好的。

### 7.12 展开箭头是 Tree 自己处理的，别插手

点条目前面那个三角形，Tree **原生**就会切换折叠状态，而且它**既不发 `item_selected`
也不发 `item_activated`**（实测两者都是 0 次）。

好处是这条路完全不用我们管。代价是：**别想着在 `gui_input` 里按鼠标位置也去切一下** —— 那样
箭头会被切两次、净效果为零。所以目录的切换只能挂在 `item_selected` / `item_activated` 上，
不能挂在"按下的位置落在哪个条目上"这种判断上。

### 7.13 回车和双击在信号里长得一样，用鼠标状态区分

`item_activated` 既被"双击的第二下"触发，也被"键盘回车"触发，回调里拿不到事件、区分不出来。
用 `Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)` 区分：实测双击第二下触发时它是
`true`，回车是 `false`（合成事件也准，因为按下和释放是分开发、按序处理的）。

不加这道判断，回车会不会切换目录就取决于"上一次点击是不是重选"，成了说不清的行为。
现在目录只响应鼠标，回车保持老样子（不该目录做事）。

### 7.14 `TreeItem.select()` 会发 `item_selected`，所以 `_select_tree_item_for_path()` 会**打开文件**

`TreeItem.select(column)` 不是"只改高亮状态"，它会把 `item_selected` 发出来。而本应用里
`item_selected` 的处理就是"载入编辑器"，所以 `_select_tree_item_for_path(p)` 的真实副作用是
**把 p 载入编辑器**，不只是让树里那一项亮起来。四个调用点都吃这个副作用：
`open_and_show()`（尾）`save_file()`（尾）`_on_new_file_confirmed()` `_on_rename_confirmed()`。

新建文件那一版就是这么被"惊到"的：断言写的是"新建之后编辑器内容还在"，实测
`current_file_path` 变成了新文件、编辑框被清空。**查下来这不是 bug，是有意保留的**——
本应用靠这条链路维持一个不变量：**树里的选中项和编辑器里的内容永远一致**。

为什么不去掉：新建后如果不载入，`current_file_path` 还指着上一个文件，用户新建完直接打字，
敲进去的其实是**上一个还开着的文件**，然后 Ctrl+S 就把它覆盖了 —— 静默的跨文件覆盖，
比"新建之后编辑框被清空"糟得多。真要改得先做"切换文件前询问未保存改动"。
注意这个代价不是新建独有的：点树里任何一个别的文件本来就是这行为。

顺带一个连带效果：`open_and_show()` 自己也会在结尾调它，看起来像是要无限递归，
实际停在两层 —— `_on_file_tree_item_selected()` 开头有 `if path == current_file_path: return`
（`main.gd:707`），而 `open_and_show()` 早就把 `current_file_path` 设好了，
所以它自己触发的那次 `item_selected` 会当场刹车。**删那一句之前先想清楚这个刹车。**

---

## 8. 已知问题

### 8.1 Ctrl+Shift+S 会先原地保存一次（已验证）

`_input()` 里两个 `if` 是并列的，不是 `elif`：

- 第一个判断"Ctrl+S"时写的是 `event.keycode == KEY_S and ... Input.is_key_pressed(KEY_CTRL)`，**它没排除 Shift**；
- 所以按 Ctrl+Shift+S 时第一个分支也成立，`save_file()` 先执行，然后才弹另存为对话框。

实测确认：按完之后磁盘上的文件内容**已经被改写了**。

平时的后果是"多写一次同样的内容"，无害；但如果在**没有打开任何文件**的状态下按，会先弹一个阻塞的「没有打开任何文件」提示框——这个比较烦人。修法是在第一个条件里加上 `and not Input.is_key_pressed(KEY_SHIFT)`。

### 8.2 强制按文本打开后 Ctrl+S 会损坏原文件

双击 `.docx` 打开后，`current_file_path` 指向那个 docx，此时 Ctrl+S 会用编辑器里的乱码**覆盖原文件**，不可逆。

打开前的提醒框已经把这个风险讲清楚了，**没有做硬拦截**——理由是 `.toml` / `.env` 这类文件本来就要能正常保存，硬拦会让它们每次保存都被问一遍。

如果想加兜底，可以在 `save_file()` 里判断当前文件不在白名单时改成弹确认框（「另存为」不受限）。

### 8.3 没有编码处理

`open_and_show()` 用的是 `FileAccess.get_as_text()`，非 UTF-8 的文件（比如 GBK 编码的中文 txt）会显示成乱码，保存回去会把原编码也改掉。没做编码检测。

### 8.4 大文件会卡

整个文件一次读进 `TextEdit`，没有分块或虚拟滚动。几 MB 的文件就会明显卡顿。

---

## 9. 明确没做的（别以为是漏了）

- 新建**文件夹**（新建文件已经做了，见 §6；文件夹还没做）
- 在**空白处**右键弹菜单（现在只有对着条目右键才有菜单）
- 新建时选扩展名（现在固定 `.txt`；想建 `.md` / `.json` 只能在弹框里把后缀改掉）
- 在选中目录打开终端
- 永久删除——只有回收站一条路（`OS.move_to_trash`）
- 多选批量操作
- 查找 / 替换、撤销栈以外的编辑增强
- 设置窗口（UI 建好了，按钮是隐藏的）
- 标签页 / 多文件同时打开——**同时只有一个文件**

---

## 10. 快捷键与状态

| 键 | 作用 |
|---|---|
| `Ctrl+S` | 保存（原地覆盖 `current_file_path`） |
| `Ctrl+Shift+S` | 另存为（**注意 8.1**） |
| `Ctrl+O` | 打开文件。对话框过滤 `*.txt *.json *.csv` |
| `F11` | 专注模式（藏起上下两条工具栏） |
| `Ctrl` + `=` / `-` | 字号增减（按住会连续变化），也可以 `Ctrl` + 滚轮 |
| `Ctrl+M` | 开关 TextEdit 的小地图 |

输入动作定义在 `project.godot` 的 `[input]` 段：`ui_save` `f11` `zoom_up` `zoom_down` `map`。

窗口启动即最大化（`display/window/size/mode=2`）。`run/max_fps=144`，物理引擎设成了 `Dummy`（这不是游戏，物理没意义）。

底部状态栏左侧的字符数由 `_process()` **每帧**刷新——所以别指望往 `Label3` 上挂临时提示，会被覆盖掉。
