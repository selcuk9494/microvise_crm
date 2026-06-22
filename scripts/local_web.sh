set -euo pipefail

flutter --version
flutter pub get

flutter build web --release \
  --dart-define=API_BASE_URL=https://microvisecrmflutter.vercel.app/api \
  --dart-define=DISABLE_SUPABASE=true

node ./scripts/local_server.js
