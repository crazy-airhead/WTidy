import { defineConfig } from 'vitepress'

// 站点内容：首页 + docs/guide（使用指南）+ 更新记录。
// docs/design/ 是仓库内部的设计语言规范（面向开发者，随代码演进），经 srcExclude 排除不发布。
const guideSidebar = [
  {
    text: '开始',
    collapsed: false,
    items: [
      { text: '指南总览', link: '/guide/' },
      { text: '快速开始', link: '/guide/getting-started' },
    ],
  },
  {
    text: '核心功能',
    collapsed: false,
    items: [
      { text: '拖拽分屏与布局条', link: '/guide/drag-snap' },
      { text: '布局自定义', link: '/guide/layouts' },
      { text: '快捷键', link: '/guide/hotkeys' },
    ],
  },
  {
    text: '设置与帮助',
    collapsed: false,
    items: [
      { text: '设置页详解', link: '/guide/settings' },
      { text: '常见问题', link: '/guide/faq' },
    ],
  },
]

export default defineConfig({
  lang: 'zh-CN',
  title: 'WTidy',
  description:
    '原生重制的 macOS 窗口分屏工具 —— Swift + AppKit，致敬 Window Tidy；拖拽分屏 / 布局自定义 / 每区域快捷键，arm64 原生、无 Rosetta',
  base: '/WTidy/',
  lastUpdated: true,
  sitemap: { hostname: 'https://crazy-airhead.github.io/WTidy/' },
  srcExclude: ['**/design/**', '**/_*.md'],
  // head 标签不会自动加 base 前缀，favicon 需写全路径
  head: [['link', { rel: 'icon', href: '/WTidy/logo.png' }]],
  themeConfig: {
    logo: '/logo.png',
    nav: [
      { text: '首页', link: '/' },
      { text: '使用指南', link: '/guide/', activeMatch: '/guide/' },
      { text: '更新记录', link: '/changelog' },
      {
        text: '下载',
        items: [
          { text: '最新版本', link: 'https://github.com/crazy-airhead/WTidy/releases/latest' },
          { text: '全部版本', link: 'https://github.com/crazy-airhead/WTidy/releases' },
        ],
      },
    ],
    sidebar: {
      '/guide/': guideSidebar,
    },
    socialLinks: [
      { icon: 'github', link: 'https://github.com/crazy-airhead/WTidy' },
    ],
    editLink: {
      pattern: 'https://github.com/crazy-airhead/WTidy/edit/main/docs/:path',
      text: '在 GitHub 上编辑此页',
    },
    search: {
      provider: 'local',
    },
    outline: { level: [2, 3], label: '本页目录' },
    docFooter: { prev: '上一篇', next: '下一篇' },
    lastUpdated: { text: '最后更新' },
    returnToTopLabel: '回到顶部',
    sidebarMenuLabel: '菜单',
    darkModeSwitchLabel: '主题',
    lightModeSwitchTitle: '切换到浅色',
    darkModeSwitchTitle: '切换到深色',
    footer: {
      message: '原生 AppKit · 无遥测 · 开源（Apache 2.0）',
      copyright: 'Copyright © 2026 crazy-airhead',
    },
  },
})
