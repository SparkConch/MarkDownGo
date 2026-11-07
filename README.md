# MarkDownGo

macOS 上的 Markdown 编辑器。

[中文](#中文) · [English](#english)

## 中文

### 功能

- 三种模式：源码 `⌘1`、分屏预览 `⌘2`、WYSIWYG `⌘3`
- 源码本身就带样式：标题按层级改字号和颜色，代码块等宽，引用、列表、链接分色，打字时实时更新
- WYSIWYG 模式藏掉 `#`、`**` 这类标记；光标所在行仍然显示源码，改结构不用猜
- 预览支持表格、任务列表、删除线、脚注，以及 KaTeX 公式和 Mermaid 图。资源都打在 App 里，不联网
- 访达里按空格就能预览：三档可选——渲染后（最全）、所见即所得（原生排版，秒开）、源码
- 左侧大纲，点标题跳到对应位置
- 编辑即保存。想丢掉这次改动，用「文件 ▸ 恢复到打开时」
- 粘贴或拖入图片，存到文档旁边的 `images/`，或内联成 base64，在设置里选
- 界面中英文，默认跟随系统，也可以在设置里固定
- 首页列最近文件，带打开和新建两个入口

### 安装

从 Releases 下载 `MarkDownGo-<版本>-arm64.dmg`。只支持 Apple Silicon，系统要求 macOS 12 及以上。

首次打开会被系统拦下。这个应用没有签名和公证（公证需要付费开发者账号）。放行方法：

1. 把 App 拖进「应用程序」，双击一次，提示无法验证开发者时点「好」
2. 打开「系统设置 ▸ 隐私与安全性」，滚到底点「仍要打开」，输入密码
3. 再双击 App，选「打开」

或者在终端执行：

```bash
xattr -d com.apple.quarantine /Applications/MarkDownGo.app
```

### 自己构建

需要 macOS 12 及以上、Xcode 16 及以上、[xcodegen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

```bash
make project   # 生成 MarkDownGo.xcodeproj
make build     # 构建，adhoc 签名
make test      # 跑单元测试
make dmg       # 输出 dist/MarkDownGo-<版本>-arm64.dmg
make run       # 构建并启动
make icon      # 从 design/logo.svg 重新生成各尺寸图标
```

### 结构

编辑内核是 `NSTextView`（TextKit 1）。样式由一段行扫描解析器算出来，结果按行分组，光标移动时只重刷受影响的行。预览是 WKWebView，走自定义 `mdg-preview://` 协议从 App 内取资源。渲染交给 cmark-gfm。

图标源文件是 `design/logo.svg`，`make icon` 会渲染 16 到 1024 的全部尺寸。

### 许可

[GPL-3.0](LICENSE)。

## English

### What it does

- Three modes: source `⌘1`, split preview `⌘2`, WYSIWYG `⌘3`
- The source is styled: headings change size and color by level, code is monospaced, quotes, lists and links are color coded, live while typing
- WYSIWYG hides the `#` and `**` markers. The line holding the caret still shows them, so structure stays editable
- Preview handles tables, task lists, strikethrough, footnotes, KaTeX math and Mermaid diagrams. Everything ships inside the app; nothing is fetched
- Space bar preview in Finder, three ways: rendered (fullest), WYSIWYG (native type, instant), source
- Outline sidebar. Click a heading to jump
- Saves as you type. Use File ▸ Revert to Opened State to drop the session's edits
- Paste or drop an image: saved to `images/` next to the document, or inlined as base64 — your choice in Settings
- Chinese and English UI, following the system language by default
- Home window with recent files, Open and New

### Install

Grab `MarkDownGo-<version>-arm64.dmg` from Releases. Apple Silicon only, macOS 12 or later.

First launch is blocked by Gatekeeper. The app is unsigned and unnotarized (notarization needs a paid developer account). To open it:

1. Drag the app to Applications, double-click once, dismiss the "cannot verify developer" dialog
2. Open System Settings ▸ Privacy & Security, scroll down, click Open Anyway, authenticate
3. Double-click the app again and choose Open

Or run:

```bash
xattr -d com.apple.quarantine /Applications/MarkDownGo.app
```

### Build

Needs macOS 12+, Xcode 16+, and [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
make project   # generate MarkDownGo.xcodeproj
make build     # build, ad-hoc signed
make test      # run unit tests
make dmg       # write dist/MarkDownGo-<version>-arm64.dmg
make run       # build and launch
make icon      # regenerate icon sizes from design/logo.svg
```

### How it is put together

The editor is a single `NSTextView` (TextKit 1). A line scanner produces the style tokens, bucketed per line, so a caret move only restyles the lines it touches. The preview is a WKWebView fed over a custom `mdg-preview://` scheme that serves resources from inside the app; rendering is cmark-gfm.

The icon master is `design/logo.svg`; `make icon` renders every size from 16 to 1024.

### License

[GPL-3.0](LICENSE).
