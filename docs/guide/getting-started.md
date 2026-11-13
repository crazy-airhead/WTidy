# 快速开始

从下载安装到完成首次授权，大约需要两分钟。

---

## 1. 下载安装

1. 前往 [Releases 最新版本](https://github.com/crazy-airhead/WTidy/releases/latest)，下载 `WTidy-vX.Y.Z-macos-arm64.zip`
2. 解压得到 `WTidy.app`，拖入「应用程序」文件夹
3. 双击启动，菜单栏出现 WTidy 图标即运行中（WTidy 是菜单栏应用，没有 Dock 图标和主窗口）

> **macOS 未公证提示**：应用为 ad-hoc 签名、未做 Apple 公证，首次打开若提示无法验证开发者，**右键 App →「打开」**，或执行 `xattr -d com.apple.quarantine /Applications/WTidy.app` 后再打开。

---

## 2. 首次使用：辅助功能授权

WTidy 依赖 macOS 辅助功能（Accessibility）API 监听窗口拖拽、读取与移动窗口，首次启动会自动弹出引导页：

1. 点引导页中的授权入口（或手动前往 **系统设置 → 隐私与安全性 → 辅助功能**）
2. 把 WTidy 加入并打开开关
3. 回到引导页，条目自动打勾后点「开始使用」

> **重新构建 / 覆盖安装后需要重新授权**：macOS 以代码签名识别辅助功能授权，ad-hoc 签名每次构建都会变——从源码重新安装后，需在辅助功能列表中先移除旧条目再重新添加。

---

## 3. 试一下

按住任意窗口的标题栏拖动：

- 屏幕上浮现**布局图标条**，悬停图标后整屏显示落点预览
- **瞄准在图标内完成**：「左右半屏」图标偏左 = 左半、偏右 = 右半，单图标即可选区
- 松手在图标上即吸附；移入屏内松手为精确选区；其他位置松手 = 正常拖拽，不打扰

也可以不动鼠标，直接用快捷键：`⌥⌘←` 把前台窗口吸到左半屏。全部快捷键见[快捷键](hotkeys.md)。

---

## 4. 与 macOS 原生分屏共存

macOS 15+ 自带「窗口拖到屏幕边缘磁贴」，与 WTidy 可共存：WTidy 由顶部布局图标条触发，原生磁贴由屏幕边缘触发，二者入口不同。若嫌干扰，可在 **系统设置 → 桌面与程序坞** 中关闭「将窗口拖到屏幕边缘时平铺」。

---

## 5. 从源码构建（进阶）

仅需 Command Line Tools（无需 Xcode）：

```bash
git clone git@github.com:crazy-airhead/WTidy.git
cd WTidy
swift build -c Release          # 编译
scripts/build-app.sh            # 组装 + ad-hoc 签名 → build/WTidy.app
scripts/build-app.sh --install  # 安装到 /Applications 并启动
```

运行测试（CLT 的 Testing 宏插件在子目录，需显式指定路径）：

```bash
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

---

## 6. 下一步

- [拖拽分屏与布局条](drag-snap.md)：招牌交互的完整细节
- [布局自定义](layouts.md)：编辑出自己的布局
- [快捷键](hotkeys.md)：为常用区域录制专属快捷键
- [常见问题](faq.md)：图标条不出现、授权失效等排查
