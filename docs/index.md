---
layout: home

hero:
  name: WTidy
  text: 原生 macOS 窗口分屏工具
  tagline: Swift + AppKit 原生重制 · 致敬 Window Tidy · arm64 原生 · 无 Rosetta
  image:
    src: /logo-512.png
    alt: WTidy
  actions:
    - theme: brand
      text: 快速开始
      link: /guide/getting-started
    - theme: alt
      text: 下载
      link: https://github.com/crazy-airhead/WTidy/releases/latest
    - theme: alt
      text: 使用指南
      link: /guide/
    - theme: alt
      text: GitHub
      link: https://github.com/crazy-airhead/WTidy

features:
  - icon: 🪟
    title: 拖拽分屏
    details: 按住任意窗口标题栏拖动，屏幕上浮现紧凑布局图标条；瞄准在图标内完成，悬停即整屏落点预览，松手吸附，其他位置松手不打扰。
  - icon: 🧩
    title: 布局自定义
    details: 内置 8 种布局，原版「网格 + 区域」模型自由编辑（如 6×6 网格区域 (2,2)-(5,5) = 居中），实时预览缩略图，支持按显示器设置作用域。
  - icon: 📋
    title: 菜单栏应用布局
    details: 子菜单列出全部布局（带迷你预览图），区域按窗口中心投影选择；一键恢复本会话吸附过的全部窗口，发送窗口到另一块屏。
  - icon: 🎬
    title: 吸附动画
    details: 窗口吸附带平滑动画；跨屏吸附自动分三阶段（移到目标屏原点 → 调整尺寸 → 移到位），大窗口跨屏不再被裁剪。
  - icon: 🧲
    title: 自动分组
    details: 相邻的同网格互补布局自动合并为一个图标，图标内投影选区——「左右半屏」和「右左半屏」只需占一个图标位。
  - icon: ⌨️
    title: 每区域快捷键
    details: 在布局列表行内直接录制，按下直接把前台窗口吸到指定区域；固定方向快捷键（⌥⌘← 等）兜底，冲突自动拦截。
  - icon: 🛡️
    title: 可靠性
    details: 看门狗自愈（事件驱动重挂 + 10 秒心跳 + 60 秒重建），菜单栏双态图标让静默失效看得见，SMAppService 现代登录项，全程日志可追溯。
  - icon: 🌐
    title: 中英双语
    details: 界面跟随系统语言自动切换（简体中文 / English）；源码构建仅需 Command Line Tools，无需 Xcode。
---
