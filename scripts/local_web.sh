set -euo pipefail

flutter --version
flutter pub get

flutter build web --release \
  --pwa-strategy=none \
  --dart-define=API_BASE_URL=https://crm.microvise.net/api \
  --dart-define=DISABLE_SUPABASE=true

node ./scripts/local_server.js
