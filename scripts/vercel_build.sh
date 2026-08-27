set -euo pipefail

FLUTTER_VERSION="3.41.2"
CACHE_DIR="${VERCEL_CACHE_DIR:-$PWD/.vercel/cache}"
FLUTTER_DIR="$CACHE_DIR/flutter/$FLUTTER_VERSION"
COMMIT_SHA="${VERCEL_GIT_COMMIT_SHA:-local}"
BUILD_MARKER="$CACHE_DIR/flutter_web_built_${COMMIT_SHA}"
PUBLIC_DIR="$PWD/public"

# Vercel may invoke vercel-build once per serverless function. Build Flutter web only once.
if [ -f "$BUILD_MARKER" ] && [ -f "$PUBLIC_DIR/index.html" ] && [ -f "$PUBLIC_DIR/main.dart.js" ]; then
  echo "Flutter web already built for ${COMMIT_SHA}; skipping duplicate build."
  exit 0
fi

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  echo "Flutter indiriliyor ($FLUTTER_VERSION)..."
  mkdir -p "$CACHE_DIR/flutter"
  curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o flutter.tar.xz
  tar -xJf flutter.tar.xz -C "$CACHE_DIR/flutter"
  rm flutter.tar.xz
  mv "$CACHE_DIR/flutter/flutter" "$FLUTTER_DIR"
  # Keep cache smaller so Vercel does not discard it next run
  rm -rf "$FLUTTER_DIR/bin/cache/artifacts" \
    "$FLUTTER_DIR/bin/cache/downloads" \
    "$FLUTTER_DIR/examples" \
    "$FLUTTER_DIR/dev" \
    "$FLUTTER_DIR/packages/flutter_tools/test" 2>/dev/null || true
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
# Always allow network: restored pub cache can miss newly added packages
# (offline mode prints a red failure even when the online retry succeeds).
flutter pub get

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

BUILD_DEFINES+=("--dart-define=API_BASE_URL=${API_BASE_URL:-https://crm.microvise.net/api}")

# Faster CI web build. Engine JS stays on CDN so Vercel does not treat canvaskit/skwasm as Node functions.
flutter build web --release --no-source-maps --no-tree-shake-icons --pwa-strategy=none \
  --no-wasm-dry-run \
  "${BUILD_DEFINES[@]}"

rm -rf "$PUBLIC_DIR"
mkdir -p "$PUBLIC_DIR"
cp -a build/web/. "$PUBLIC_DIR/"

# Local engine bundles are huge and Vercel mis-compiles their ESM entrypoints as serverless
# functions, which blows up deploy time/size. Flutter loader will fetch CanvasKit from CDN.
rm -rf "$PUBLIC_DIR/canvaskit"
rm -f "$PUBLIC_DIR"/wimp.js "$PUBLIC_DIR"/skwasm*.js 2>/dev/null || true

# Avoid a second scan of build/web as function candidates
rm -rf build/web

mkdir -p "$CACHE_DIR"
touch "$BUILD_MARKER"
echo "Flutter web build complete for ${COMMIT_SHA} -> public/"
