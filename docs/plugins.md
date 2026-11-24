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

以下是宿主向插件提供的能力，以及相应的最低版本。

| 能力 | 接口或机制 | 权限与范围 | 版本 |
| --- | --- | --- | --- |
| 运行场景 | `OpenSticker.mode` | 无需授权。创建表单为 `create`，贴纸为 `card`。 | v0.2.0 |
| 界面语言 | `OpenSticker.locale`、清单的 `localizations` | 无需授权。支持 `en`、`zh-Hans`。切换语言会重新加载页面并恢复贴纸数据。 | v0.2.0 |
| 贴纸状态 | `OpenSticker.get(key)`、`OpenSticker.set(key, value)` | 无需授权。读写当前创建草稿或贴纸实例的字符串，缺失值返回空字符串。宿主保留键由相应的宿主界面写入。 | v0.2.0 |
| 复制文本 | `OpenSticker.copy(text)` | 直接在用户点击处理函数中调用。 | v0.2.0 |
| 拖动贴纸 | 宿主处理拖动；`data-sticker-no-drag` 可排除自定义交互区域 | 无需授权。标准输入框、按钮等控件自动排除。 | v0.2.0 |
| 读取共享配置 | `await OpenSticker.config.get(key)` | 清单声明 `configuration`，用户授予读取权限。只读取已声明的键，未设置时返回 `null`。 | v0.2.0 |
| HTTPS 请求 | `await OpenSticker.network.request(options)` | 清单在 `networkHosts` 声明域名，用户授予联网权限。支持 GET、POST，返回状态码、正文、Cookie 和重定向地址。 | v0.2.0 |
| AI 结构化输出 | `await OpenSticker.ai.generate(prompt, schema)` | 清单声明 `usesLocalAI`，用户授予 AI 权限，限贴纸模式。宿主通过已配置的模型服务返回 JSON 对象。 | v0.2.0 |
| 本机只读请求 | `await OpenSticker.network.request(options)` | 联网授权后，只允许 HTTP GET 到声明或用户确认的 `127.0.0.1` 端口。可指定 `responseEncoding: "base64"` 读取二进制。 | v0.2.1 |
| 通过本机代理读取 | `await OpenSticker.network.request({ url, viaLoopbackProxy })` | 联网授权。只允许 GET，经已获准的本机代理访问清单声明的 HTTP 目标。 | v0.2.1 |
| 配置贴纸的本机服务地址 | `await OpenSticker.network.configureLoopback()` | 清单声明 `loopbackAddressKey` 或 `loopbackAddressKeys`，在贴纸上的用户点击中打开宿主确认窗。地址按贴纸保存。 | v0.2.1 |
| 本机 HTTP 监听 | `OpenSticker.network.listener.start()`、`.read(after, stream)`、`.stop()` | 联网授权、清单声明固定端口和 HTTPS 上游，启动和停止由用户确认。 | v0.2.1 |
| 剪贴板历史 | `OpenSticker.history.refresh()`、`OpenSticker.history.perform(action, item?)`、`sticker-history` 事件 | 仅向内置识别的剪贴板历史插件开放。用户会话内授权，记录最近 50 条纯文本。动作包括 `start`、`pause`、`clear`、`copy`。 | v0.2.0 |

`OpenSticker` 和旧的 `Sticker` 指向同一个接口对象。通用插件没有任意文件访问、进程执行或直接读取剪贴板的接口。浏览器直接联网由宿主禁用。

Use `manifest.localizations` to supply translated names, descriptions, and authors by language. In the WebView, select UI strings using `OpenSticker.locale`. The host reloads the page when the language changes and restores the current sticker values.

在 `manifest.localizations` 中按语言填写名称、描述和作者。插件页面用 `OpenSticker.locale` 选择界面文案。语言切换时宿主会重新加载页面，并恢复该贴纸已保存的数据。

Add `data-sticker-no-drag` to custom interactive areas that should not start a card drag. Standard inputs and buttons are already excluded. The general plugin API does not provide filesystem, process, or clipboard-read access. The Clipboard History example uses a separate, user-authorized host capability.

自定义交互区域可以加 `data-sticker-no-drag`，让鼠标操作不会拖动整张贴纸。标准输入框和按钮已排除。通用接口不提供文件、进程或剪贴板读取权限。剪贴板历史示例使用单独授权的宿主能力。

## Shared configuration · 共享配置

Declare shared settings in `manifest.json`. Use a stable namespaced key such as `example/username`. OpenSticker displays one setting per key even when several plugins declare it. If any declaration marks a key as `secret`, the settings window masks input for that key. Use `localizations` on each entry for translated field labels.

在 `manifest.json` 的 `configuration` 中声明共享配置。相同的键在「插件配置」里只有一份。只要任一插件将它声明为 `secret`，设置窗口就会遮住输入。所有值保存在 macOS 钥匙串里。

```json
{
  "configuration": [
    { "key": "example/username", "type": "text", "label": "用户名", "localizations": { "en": "Username" } },
    { "key": "example/password", "type": "secret", "label": "密码" },
    { "key": "example/api_key", "type": "secret", "label": "API 密钥" }
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

For a local read-only service, declare the exact numeric loopback address and TCP port in `networkHosts` (for example, `127.0.0.1:8081`). The bridge accepts HTTP GET for that exact address and port. Set `responseEncoding: "base64"` on local requests when the response contains binary data.

For a per-sticker loopback endpoint, declare `loopbackAddressKey` as a reserved sticker-state key. Call `Sticker.network.configureLoopback()` from a card button to open a native confirmation dialog. The host stores the confirmed address under that key. WebView scripts can read it with `Sticker.get(key)`, and only the native dialog can change it. The network grant allows HTTP GET to the confirmed port.

For local proxy control interfaces, a plugin may declare exact target hosts in `loopbackProxyHosts`. Set `viaLoopbackProxy` to a declared or user-confirmed `127.0.0.1:PORT` in `network.request`. The bridge sends a GET through that local proxy to the declared HTTP target. Expanding the target hosts requires renewed network authorization.

For multiple independently saved addresses, declare `loopbackAddressKeys` and pass the corresponding key to `OpenSticker.network.configureLoopback(key)`. Each key is confirmed in the native dialog and belongs to that sticker.

## Local listener · 本机监听

从 v0.2.1 起，插件可在清单声明一个临时 HTTP 监听器。宿主只绑定 `127.0.0.1`，接受声明路径的 POST，并向清单中的固定 HTTPS 上游转发。可声明允许的 `Origin`；没有 `Origin` 的请求也可接受。扩大监听范围需要重新联网授权。

```json
{
  "listener": {
    "port": 8765,
    "path": "/ingest",
    "upstream": "https://api.example.com/ingest",
    "origins": ["https://app.example.com"]
  }
}
```

- `OpenSticker.network.listener.start()` 和 `.stop()` 在贴纸按钮的点击处理函数中调用，经宿主确认后启动或停止。取消返回 `null`。
- `await OpenSticker.network.listener.read(after, stream)` 返回 `{ state, stream, received, packets }`。状态为 `stopped`、`starting`、`running` 或 `failed`。每个包含 `id`、Unix 秒时间戳 `time` 和 Base64 请求体 `body`。保存已读的最后一个 `id` 和 `stream`，下次用它们读新增。不同 `stream` 表示监听器重启，游标从头开始。
- 同一插件 ID 的贴纸共享一个监听器和队列。队列只存在内存，最多 100 个包和 8 MiB。每个请求体上限 2 MiB。退出宿主、卸载插件或撤销权限会停止监听。
- 宿主保留原查询参数并回传上游 HTTP 状态和响应体。上游失败返回 502。使用代理映射时，先停用映射再停止监听或退出宿主。

This capability is available from v0.2.1. The listener is explicitly started, shared by cards for the same plugin, and stops when OpenSticker quits. It forwards only matching POST requests to the declared HTTPS upstream, and exposes bounded, in-memory packets to cards through a cursor.
