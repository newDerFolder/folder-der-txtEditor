class_name TextToBbcode
extends RefCounted

## 纯文本 → 「阅读排版」BBCode。
##
## 内容**不做任何解析**：不分章、不做目录、不记阅读进度（README §9）。它只干一件事 ——
## 让一坨 .txt 在窄栏里读起来舒服：首行缩进、段间距、场景分隔行居中。
##
## 拆成独立脚本的理由和 main.gd 的 _validate_name_in_dir() 一样：**纯函数，进 String 出
## String**，不碰节点也不读文件，所以不起界面就能拿它做断言。
##
## 注意这里**没有** font_size 参数：正文字号由 main.gd 通过 RichTextLabel 的主题覆盖统一管，
## 转换器不该知道这件事（两处都管的话，改字号会出现"标题跟着变、正文没变"这种半截效果）。

## 首行缩进用的两个全角空格。
##
## 这是**不能用 [indent] 代替**的：[indent] 缩进的是整个块 —— 每一行，包括自动折行出来的
## 续行。套在正文上整段都会往右挪，那不是首行缩进，读起来是错的。
## 中文排版里首行缩进就是两个字宽，直接写成字符最省事。
const INDENT := "　　"

## 允许当分隔行的符号。**限定字符集**，而不是"任意同一种字符重复 3 次"——
## 后者会把 "。。。。" 吃进来，而中文小说里那是省略号，不是分隔线。
const BREAK_SYMBOLS := "*-—=~☆★◆◇❀※×_"

## 同类符号至少要这么多个才算分隔行。1 个 "-" 是正文里的破折号，不是分隔线。
const BREAK_MIN_RUN := 3

## 分隔行的显示形式
const BREAK_TEXT := "* * *"
const BREAK_COLOR := "#6b7075"


## 把纯文本转成 BBCode。
static func to_bbcode(src: String) -> String:
	var out: Array[String] = []
	for raw in _normalize(src).split("\n"):
		var line := raw.strip_edges()
		# 空行整个丢掉。它是**分隔符**，而视觉上的段间距由 RichTextLabel 的
		# line_separation 主题常量给 —— 留着的话每段之间会空两倍（空行 + 行距）。
		if line.is_empty():
			continue
		if _is_break_line(line):
			out.append("[center][color=%s]%s[/color][/center]" % [BREAK_COLOR, BREAK_TEXT])
			continue
		out.append(_indent_line(line))
	# 段与段之间**不插空行**：有了首行缩进，中文书本来就是密排的，
	# 再插空行会和 line_separation 叠成双倍行距，整页就散了。
	return "\n".join(out)


## 换行统一成 \n、制表符展开、去掉控制字符。
##
## 控制字符是**真会来的**，不是防御性代码：`.docx` 之类的二进制文件可以被"强制按文本打开"
## （main.gd 的 _on_open_as_text_confirmed），GBK 编码的中文也会带进来一堆。RichTextLabel
## 拿到这些会在控制台刷警告，排版也会乱。
static func _normalize(src: String) -> String:
	var s := src.replace("\r\n", "\n").replace("\r", "\n")
	# 制表符先展开成 4 个空格：RichTextLabel 不认识 \t，会画成一个方块。
	s = s.replace("\t", "    ")
	var parts: Array[String] = []
	# 用数组攒再一次 join：GDScript 的字符串相加在循环里是 O(n²)，
	# 几 MB 的 txt 会直接卡住主线程。
	for i in s.length():
		var code := s.unicode_at(i)
		if code < 32:
			if code == 10:      # \n
				parts.append("\n")
			continue            # 其余 C0 控制字符（含 \r \t，上面已经处理过）丢掉
		if code != 127:         # DEL
			parts.append(s[i])
	return "".join(parts)


## 把字面文本转成安全的 BBCode。
##
## **只做一件事**：把 "[" 换成 "[lb]"。RichTextLabel 没有"整段转义"的标签，也没有 `\[`
## 这种反斜杠转义（文档明说要用 [lb] / [rb] 这两个自闭合标签），所以唯一的办法就是逐字符换。
## 右方括号本身是安全的：单独一个 "]" 不构成标签，原样输出即可。
static func _escape(src: String) -> String:
	return src.replace("[", "[lb]")


## 整行只有一种分隔符号、且凑够 BREAK_MIN_RUN 个 —— `* * *`、`---`、`☆☆☆`、`======`。
## 符号之间允许有空格（中文书里的 `* * *` 就是这么写的）。
static func _is_break_line(line: String) -> bool:
	var symbol := ""
	var count := 0
	for i in line.length():
		var c := line[i]
		if c == " " or c == "　":
			continue
		if not BREAK_SYMBOLS.contains(c):
			return false
		if count == 0:
			symbol = c
		elif c != symbol:
			return false        # 混了两种符号，不是分隔行
		count += 1
	return count >= BREAK_MIN_RUN


## 首行缩进。
##
## **已经以全角空格开头的行不加** —— 作者自己缩进过了，再加两个字宽会变成四字缩进，
## 比不缩进还难看。
##
## 半角空格不在这里管：调用方已经 strip_edges 过了，零星的前导半角空白是排版噪音，
## "重排"这件事本身就包含把它抹平、换成统一的全角缩进。
static func _indent_line(line: String) -> String:
	if line.begins_with("　"):
		return _escape(line)
	return INDENT + _escape(line)
