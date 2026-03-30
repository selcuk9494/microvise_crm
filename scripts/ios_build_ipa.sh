#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

flutter pub get
flutter build ios --release

ARCHIVE_PATH="$ROOT_DIR/build/ios/archive/Runner.xcarchive"
EXPORT_PATH="$ROOT_DIR/build/ios/ipa"

mkdir -p "$EXPORT_PATH"

xcodebuild \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  -allowProvisioningUpdates

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist ios/ExportOptions_appstore.plist \
  -allowProvisioningUpdates

ls -lah "$EXPORT_PATH"

