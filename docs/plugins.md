# Sticker plugins · 插件开发

[English README](../README.md) · [简体中文](../README.zh-CN.md)

A plugin defines a sticker type. Start from the [Quick QR example](../examples/template-qr). Import the folder with **Manage Plugins → +**, then choose its type in the composer. Reimport the same plugin ID to reload it and keep existing sticker data.

每个插件定义一种贴纸类型。可以从[快速二维码示例](../examples/template-qr)开始。在「插件管理 → ＋」导入目录，再在创建窗口选择该类型。重新导入同一插件 ID 可即时更新，并保留已有贴纸的数据。

| File | Purpose |
| --- | --- |
| `manifest.json` | Required fields: `formatVersion` (currently `1`), `id`, and `name`. Optional fields include `version`, `description`, `author`, and `localizations`. |
| `index.html` | Markup and inline CSS. Use data URLs for embedded images. |
| `plugin.js` | JavaScript loaded by the host after the document is ready. Bundle your dependencies in this file. |

## Host API · 宿主接口

| JavaScript | Behavior |
| --- | --- |
| `Sticker.mode` | `"create"` for the creation form or `"card"` for the sticker itself. |
| `Sticker.locale` | `"en"` or `"zh-Hans"`. |
| `Sticker.get(key)` | Read a saved string. A missing key returns `""`. |
| `Sticker.set(key, value)` | Save a string in the draft or current sticker instance. |
| `Sticker.copy(text)` | Write text to the clipboard. Call it synchronously from a user click. |

Use `manifest.localizations` to supply translated names, descriptions, and authors by language. In the WebView, select UI strings using `Sticker.locale`. The host reloads the page when the language changes and restores the current sticker values.

在 `manifest.localizations` 中按语言填写名称、描述和作者。插件页面用 `Sticker.locale` 选择界面文案。语言切换时宿主会重新加载页面，并恢复该贴纸已保存的数据。

Add `data-sticker-no-drag` to custom interactive areas that should not start a card drag. Standard inputs and buttons are already excluded. The general plugin API does not provide filesystem, process, network, or clipboard-read access. The Clipboard History example uses a separate, user-authorized host capability.

自定义交互区域可以加 `data-sticker-no-drag`，让鼠标操作不会拖动整张贴纸。标准输入框和按钮已排除。通用接口不提供文件、进程、网络或剪贴板读取权限。剪贴板历史示例使用单独授权的宿主能力。
