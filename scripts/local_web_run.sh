set -euo pipefail

flutter --version
flutter pub get

flutter run -d web-server \
  --web-hostname=127.0.0.1 \
  --web-port=3000 \
  --dart-define=API_BASE_URL=https://microvisecrmflutter.vercel.app/api \
  --dart-define=DISABLE_SUPABASE=true

