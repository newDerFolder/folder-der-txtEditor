# FolderDerTextEditor

一个用 Godot 做的**纯文本编辑器**：左边是文件夹树，右边是编辑区。定位很明确——不追求做 VS Code，只求打开快、能顺着目录翻文件、能改能存。

- 引擎：**Godot 4.7**（`GL Compatibility` 渲染后端）
- 语言：纯 GDScript，没有 C#
- 平台：Windows（`export_presets.cfg` 只有 Windows Desktop 一项）
- 体量：整个应用就是 `page/main.tscn` + `page/main.gd`（约 670 行）

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

退出码 0 = 没问题。这招能抓到大部分 GDScript 的编译错误。

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

### 写 harness 时踩过的四个坑

1. **必须带窗口跑，不要加 `--headless`。** Tree 控件在 headless 下不暴露某些崩溃——历史上那次段错误就是带窗口才复现的。
2. **stdout 被重定向/管道时是块缓冲的**，进程被 `timeout` 杀掉就一个字都不剩。每条断言都同时 `print` **并追加写一个文件**（写完立刻 `close()`），这样即使挂起也能看到跑到哪一步了。
3. **类型推断的报错很啰嗦**：`var r := tree.get_item_area_rect(...)` 会报 `Cannot infer the type`，得写成 `var r: Rect2 = ...`。凡是从引擎方法拿到的返回值，习惯性加上显式类型注解，能省掉一大堆来回。
4. **合成输入可以走完整管线**：`Input.parse_input_event()` 对鼠标点击、双击（第二下带 `double_click = true`）、键盘按修饰键都有效，能端到端验真实输入路径。但**弹过 PopupMenu 之后再合成输入会挂住**，遇到这种就改成直接调用处理函数。

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

### 死的文件（别浪费时间研究）

| 路径 | 说明 |
|---|---|
| `scene/FileItemButton.tscn` | **没有任何地方引用**，是早期方案的残留 |
| `asset/icon/settingIcon.png` | 没被任何场景引用 |
| `asset/bg/loadingBg.png`、`asset/bg/tsBg.png` | 没被引用，只用了 `tsBgHF.png` |
| `addons/godot_ai/` | 第三方 MCP 插件（Godot AI 工具链），**和编辑器业务逻辑完全无关**。它的 autoload `_mcp_game_helper` 是自己注册的 |

> 顺带一提：`addons/godot_ai/` 里有几百个文件，搜索时建议排除，否则结果会被淹掉。

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
| **重命名** | `_prompt_rename()` `_validate_new_name()` `_on_rename_confirmed()` | 校验拆成了纯函数，方便不起弹窗就能测 |
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
| **双击** | （不额外动作） | 载入编辑器 | **弹提醒 → 确认后按文本打开** |
| **右键** | 文件管理器 / 重命名 / 删除 / 复制路径 / 刷新 | 同上 | 同上，**外加第一项「用默认程序打开」** |

几个反直觉的地方，都是故意的：

- **单击不可编辑的文件什么都不做**：读进来是二进制乱码，而 `current_file_path` 会被指过去，接着按 Ctrl+S 就把原文件覆盖成乱码了。
- **双击才是"强制按文本打开"**：这个入口主要给两种情况用——`.toml` / `.env` / `Dockerfile` 这类没进白名单但本来就是文本的文件；以及真想看看 `.docx` 里装了什么。会先弹一个提醒框。
- **双击目录不做事**：双击的第一下已经发过 `item_selected` 把展开状态切过一次了，`item_activated` 里再切一次正好抵消，用户会看到"双击文件夹没反应"。
- **双击当前已打开的文件不重读**：否则顺手双击一下正在编辑的文件，没保存的改动当场被冲掉。

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

- 新建文件 / 新建文件夹（需要再区分"空白处右键"的上下文）
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
