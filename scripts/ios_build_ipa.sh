#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

flutter pub get

SDKROOT_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
echo "Using SdkRoot=$SDKROOT_PATH"

flutter build ipa \
  --release \
  --export-options-plist ios/ExportOptions_appstore.plist \
  --dart-define=SdkRoot="$SDKROOT_PATH"

ls -lah "$ROOT_DIR/build/ios/ipa"
