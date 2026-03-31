set -euo pipefail

FLUTTER_VERSION="3.41.2"
CACHE_DIR="${VERCEL_CACHE_DIR:-$PWD/.vercel/cache}"
FLUTTER_DIR="$CACHE_DIR/flutter/$FLUTTER_VERSION"

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  echo "Flutter indiriliyor ($FLUTTER_VERSION)..."
  mkdir -p "$CACHE_DIR/flutter"
  curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o flutter.tar.xz
  tar -xJf flutter.tar.xz -C "$CACHE_DIR/flutter"
  rm flutter.tar.xz
  mv "$CACHE_DIR/flutter/flutter" "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"
export PUB_CACHE="$CACHE_DIR/.pub-cache"
mkdir -p "$PUB_CACHE"

export GIT_CONFIG_GLOBAL="$PWD/.vercel_gitconfig"
if command -v git >/dev/null 2>&1; then
  git config --global --add safe.directory "$PWD"
  git config --global --add safe.directory "$FLUTTER_DIR"
  git config --global --add safe.directory "$(dirname "$FLUTTER_DIR")"
fi

flutter --version
if [ -d "$PUB_CACHE" ] && [ "$(ls -A "$PUB_CACHE" 2>/dev/null | wc -l)" -gt 0 ]; then
  flutter pub get --offline || flutter pub get
else
  flutter pub get
fi

# Pre-cache web engine/tooling into the Vercel cache so subsequent builds are fast
if [ ! -f "$FLUTTER_DIR/bin/cache/flutter_tools.stamp" ]; then
  flutter precache --web
fi

BUILD_DEFINES=()

if [ "${SUPABASE_URL:-}" != "" ]; then
  BUILD_DEFINES+=("--dart-define=SUPABASE_URL=${SUPABASE_URL}")
fi

if [ "${SUPABASE_PUBLISHABLE_KEY:-}" != "" ]; then
  BUILD_DEFINES+=("--dart-define=SUPABASE_PUBLISHABLE_KEY=${SUPABASE_PUBLISHABLE_KEY}")
fi

if [ "${SUPABASE_ANON_KEY:-}" != "" ]; then
  BUILD_DEFINES+=("--dart-define=SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}")
fi

# Build faster: skip source maps and icon tree shaking for CI web builds
flutter build web --release --no-source-maps --no-tree-shake-icons "${BUILD_DEFINES[@]}"
