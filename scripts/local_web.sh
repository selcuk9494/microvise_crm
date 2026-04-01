set -euo pipefail

if [ ! -f ".env.local" ] && [ ! -f ".env" ] && [ "${DATABASE_URL:-}" = "" ] && [ "${POSTGRES_URL:-}" = "" ]; then
  echo ".env.local bulunamadı. DATABASE_URL/POSTGRES_URL, JWT_SECRET, MASTER_ADMIN_EMAIL, MASTER_ADMIN_PASSWORD ekleyin."
  exit 1
fi

flutter --version
flutter pub get

flutter build web --release \
  --dart-define=API_BASE_URL=/api \
  --dart-define=DISABLE_SUPABASE=true

node ./scripts/local_server.js
