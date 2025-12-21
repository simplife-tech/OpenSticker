#!/bin/bash

set -e

APP_PATH="$1"

if [ -z "$APP_PATH" ]; then
  echo "❌ 用法: ./adhoc-sign.sh /Applications/Sticker.app"
  exit 1
fi

if [ ! -d "$APP_PATH" ]; then
  echo "❌ 找不到 app: $APP_PATH"
  exit 1
fi

echo "🔐 开始 ad-hoc 重签名: $APP_PATH"

# 1. 清理 quarantine（非常关键）
echo "🧹 清理 quarantine"
xattr -dr com.apple.quarantine "$APP_PATH"

# 2. 删除旧签名
echo "🧼 删除旧签名"
codesign --remove-signature "$APP_PATH" || true

# 3. ad-hoc 重新签名（含子组件）
echo "✍️ ad-hoc codesign"
codesign \
  --force \
  --deep \
  --sign - \
  "$APP_PATH"

# 4. 校验
echo "🔍 验证签名"
codesign -dv --verbose=2 "$APP_PATH"

echo "✅ ad-hoc 签名完成，可以直接运行"

