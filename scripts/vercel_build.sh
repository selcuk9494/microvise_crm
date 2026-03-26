set -euo pipefail

FLUTTER_VERSION="3.41.2"
FLUTTER_DIR=".flutter"

if [ ! -d "$FLUTTER_DIR" ]; then
  echo "Flutter indiriliyor ($FLUTTER_VERSION)..."
  curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o flutter.tar.xz
  tar -xJf flutter.tar.xz
  rm flutter.tar.xz
  mv flutter "$FLUTTER_DIR"
fi

export PATH="$PWD/$FLUTTER_DIR/bin:$PATH"

flutter --version
flutter pub get
BUILD_DEFINES=()

if [ "${SUPABASE_URL:-}" != "" ]; then
  BUILD_DEFINES+=("--dart-define=SUPABASE_URL=${SUPABASE_URL}")
fi

if [ "${SUPABASE_ANON_KEY:-}" != "" ]; then
  BUILD_DEFINES+=("--dart-define=SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}")
fi

flutter build web --release "${BUILD_DEFINES[@]}"
