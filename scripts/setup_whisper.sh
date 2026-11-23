#!/bin/bash
# Downloads whisper.cpp at the commit Sotto was built against and compiles
# the static libraries that Sotto links to.
# Run:  bash "scripts/setup_whisper.sh"
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/vendor/whisper.cpp"
COMMIT="6fc7c33b4c3a2cec83e4b65abd5e96a890480375"

if ! command -v cmake >/dev/null 2>&1; then
  echo "CMake is required. Install it with:  brew install cmake" >&2
  exit 1
fi

if [ ! -d "$SRC/.git" ]; then
  echo "==> Downloading whisper.cpp..."
  mkdir -p "$ROOT/vendor"
  git clone https://github.com/ggml-org/whisper.cpp "$SRC"
fi
git -C "$SRC" checkout --quiet "$COMMIT"

echo "==> Building whisper.cpp (this takes a few minutes)..."
cmake -S "$SRC" -B "$SRC/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DGGML_BLAS=ON \
  -DGGML_BLAS_VENDOR=Apple \
  -DGGML_OPENMP=OFF \
  -DWHISPER_BUILD_EXAMPLES=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF
cmake --build "$SRC/build" --config Release -j

test -f "$SRC/build/src/libwhisper.a"
echo "==> whisper.cpp ready."
