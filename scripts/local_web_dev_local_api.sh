set -euo pipefail

if [ ! -f ".env.local" ] && [ ! -f ".env" ] && [ "${DATABASE_URL:-}" = "" ] && [ "${POSTGRES_URL:-}" = "" ]; then
  echo ".env.local bulunamadı. DATABASE_URL/POSTGRES_URL, JWT_SECRET, MASTER_ADMIN_EMAIL, MASTER_ADMIN_PASSWORD ekleyin."
  exit 1
fi

PORT=4000 node ./scripts/local_server.js &
SERVER_PID=$!
trap "kill $SERVER_PID 2>/dev/null || true" EXIT

flutter --version
flutter pub get

flutter run -d web-server \
  --web-hostname=127.0.0.1 \
  --web-port=3000 \
  --dart-define=API_BASE_URL=http://127.0.0.1:4000/api \
  --dart-define=DISABLE_SUPABASE=true

