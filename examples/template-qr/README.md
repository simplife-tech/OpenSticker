# 快速二维码插件

在 Sticker 的菜单栏打开「插件管理」，选择「导入或更新」，选中整个
`template-qr` 文件夹。按 `⌥N` 选择「快速二维码」，填写贴纸标题和地址模板。
模板示例为 `https://a.com/{project}/{id}`。每个不同的占位符会生成一个参数，
可配置显示名称和初始值。卡片中修改参数会即时更新二维码，点击链接即可复制。
直接编辑插件文件后，重新导入同一目录即可刷新卡片，已保存的值会保留。

- `manifest.json` 声明插件 ID、名称和格式版本。
- `index.html` 提供 HTML 和内联 CSS。
- `plugin.js` 提供交互和二维码生成，也包含 Kazuhiko Arase 的 MIT 许可
  QR Code Generator for JavaScript 1.4.4，文件开头保留了原作者声明。

宿主在页面内提供 `Sticker.mode`（`create` 或 `card`）、
`Sticker.get(key)`、`Sticker.set(key, value)` 和 `Sticker.copy(value)`。
值为字符串，按贴纸实例保存。复制应从点击事件中同步调用。插件资源在
WebView 内运行，CSS 内联，图片可用 data URL。
