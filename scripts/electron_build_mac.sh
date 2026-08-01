#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Flutter web (Electron, same-origin /api)"
flutter --version
flutter pub get
flutter build web --release \
  --pwa-strategy=none \
  --dart-define=API_BASE_URL=/api \
  --dart-define=DISABLE_SUPABASE=true

echo "==> npm deps (electron + builder)"
npm install

echo "==> electron-builder (mac arm64 .app + dmg)"
# Cursor/IDE ortamında ELECTRON_RUN_AS_NODE=1 olabilir; Electron GUI için kaldır.
env -u ELECTRON_RUN_AS_NODE npx electron-builder --mac --arm64

echo ""
echo "Hazır (Apple Silicon / arm64):"
echo "  dist-electron/mac-arm64/Microvise CRM.app"
echo "  dist-electron/Microvise CRM-1.0.0-arm64.dmg"
echo ""
echo "Çalıştır:"
echo "  open \"dist-electron/mac-arm64/Microvise CRM.app\""
echo "  # geliştirme: npm run electron:dev"
echo ""
echo "Not: İlk açılışta .env.local yoksa proje kökündekini"
echo "  ~/Library/Application Support/Microvise CRM/.env.local"
echo "  altına kopyalar. İmzasız uygulama: Sistem Ayarları > Gizlilik > Yine de Aç."
echo "  Intel Mac için: npx electron-builder --mac --x64"
