# OpenSticker plugins · 插件开发

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
| `OpenSticker.mode` | `"create"` for the creation form or `"card"` for the sticker itself. |
| `OpenSticker.locale` | `"en"` or `"zh-Hans"`. |
| `OpenSticker.get(key)` | Read a saved string. A missing key returns `""`. |
| `OpenSticker.set(key, value)` | Save a string in the draft or current sticker instance. |
| `OpenSticker.copy(text)` | Write text to the clipboard. Call it synchronously from a user click. |

Use `manifest.localizations` to supply translated names, descriptions, and authors by language. In the WebView, select UI strings using `OpenSticker.locale`. The host reloads the page when the language changes and restores the current sticker values.

在 `manifest.localizations` 中按语言填写名称、描述和作者。插件页面用 `OpenSticker.locale` 选择界面文案。语言切换时宿主会重新加载页面，并恢复该贴纸已保存的数据。

Add `data-sticker-no-drag` to custom interactive areas that should not start a card drag. Standard inputs and buttons are already excluded. The general plugin API does not provide filesystem, process, or clipboard-read access. The Clipboard History example uses a separate, user-authorized host capability.

自定义交互区域可以加 `data-sticker-no-drag`，让鼠标操作不会拖动整张贴纸。标准输入框和按钮已排除。通用接口不提供文件、进程或剪贴板读取权限。剪贴板历史示例使用单独授权的宿主能力。

## Shared configuration · 共享配置

Declare shared settings in `manifest.json`. Use a stable namespaced key such as `bili/username`. OpenSticker displays one setting per key even when several plugins declare it. If any declaration marks a key as `secret`, the settings window masks input for that key. Use `localizations` on each entry for translated field labels.

在 `manifest.json` 的 `configuration` 中声明共享配置。相同的键在「插件配置」里只有一份。只要任一插件将它声明为 `secret`，设置窗口就会遮住输入。所有值保存在 macOS 钥匙串里。

```json
{
  "configuration": [
    { "key": "bili/username", "type": "text", "label": "用户名", "localizations": { "en": "Username" } },
    { "key": "bili/password", "type": "secret", "label": "密码" },
    { "key": "bili/totp_secret", "type": "secret", "label": "TOTP 密钥" }
  ]
}
```

After the user grants the plugin access in **Plugin Settings**, `await OpenSticker.config.get(key)` returns the current string or `null` if unset. It rejects undeclared keys and requests from unauthorized plugins. Plugins receive the actual value when authorized. There is no plugin API for changing these settings.

在「插件配置」授权后，`await OpenSticker.config.get(key)` 会返回配置原值，未配置时返回 `null`。未声明或未授权的读取会失败，插件不能写入共享配置。可导入[共享配置示例](../examples/shared-config)，用测试值检查配置状态。

## Network access · 网络权限

Declare exact HTTPS hostnames with `"networkHosts": ["api.example.com"]` in the manifest. The user grants or revokes access in **Plugin Settings**.  Browser networking remains disabled.

在清单用 `networkHosts` 声明准确的 HTTPS 域名，再到「插件配置」授权。

```js
const result = await OpenSticker.network.request({
  url: "https://api.example.com/search",
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ query: "example" })
});
const { status, body, cookies } = result;
```

The bridge supports GET and POST. It returns HTTP status, the UTF-8 body and response cookies as `{ name, value }` entries. Redirects are returned without following them, with an optional `location` string. No cookies or credentials are stored by the bridge. Plugins can explicitly pass a Cookie header within their granted hosts. Keep session cookies in memory and never store them in sticker content. Requests outside declared hosts are rejected.

## AI capabilities · AI 能力

Declare `"usesLocalAI": true` in the manifest. After authorizing the plugin in **Plugin Settings**, call `await OpenSticker.ai.generate(prompt, schema)` from the card. The schema must describe a JSON object. OpenSticker appends `/chat/completions` to the configured HTTP or HTTPS base URL and requests JSON mode from the OpenAI-compatible provider. It passes the schema as instructions and parses the returned JSON object. Plugins should validate the fields they use.

在「插件配置」填写 Base URL（例如以 `/v1` 结尾的服务地址）、API Key 和模型名称。API Key 存在钥匙串里，由宿主发送给模型服务。插件自行编排工作流，只传模型需要的信息。

Updates with the same plugin ID and source retain grants for unchanged or narrowed scopes. Adding configuration keys or network hosts requires reauthorizing that permission. Removing a permission clears its grant.

同 ID、同来源更新时，范围相同或缩小的授权会保留，包括通过「添加插件」重新导入相同版本。新增配置键或联网域名时，对应权限需要重新授权。删除权限声明会清除对应授权。

Existing plugins can continue to use the `window.Sticker` alias.
