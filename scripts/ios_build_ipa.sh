#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

flutter pub get

SDKROOT_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
echo "Using SdkRoot=$SDKROOT_PATH"

API_BASE_URL="${API_BASE_URL:-https://crm.microvise.net/api}"
echo "Using API_BASE_URL=$API_BASE_URL"

flutter build ipa \
  --release \
  --no-tree-shake-icons \
  --export-options-plist ios/ExportOptions_appstore.plist \
  --dart-define=SdkRoot="$SDKROOT_PATH" \
  --dart-define=API_BASE_URL="$API_BASE_URL"

ls -lah "$ROOT_DIR/build/ios/ipa"
