#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export PATH="$PREFIX/bin:/system/bin"
export DEBIAN_FRONTEND=noninteractive
export UV_NO_CONFIG=1
export UV_LINK_MODE=copy
export CARGO_BUILD_JOBS=1
export CARGO_INCREMENTAL=0

REPO_DIR="${1:?repository path required}"
BUILD_ROOT="${2:-$HOME/termux-hermes-build}"
BUILD_MODE="${3:-android}"
case "$BUILD_MODE" in
  android|docker) ;;
  *) echo "Unknown build mode: $BUILD_MODE" >&2; exit 1 ;;
esac
MANIFEST="$REPO_DIR/manifest/wheels.json"
PYTHON_DEB="$BUILD_ROOT/python3.13_3.13.13_aarch64.deb"
PYTHON_SHA256="f1b37543613eb40afeaaeaf25056bf1d2a7ed851e6f27a25213667cb66545e69"

mkdir -p "$BUILD_ROOT"
ARCH="$(dpkg --print-architecture 2>/dev/null || true)"
[ "$ARCH" = aarch64 ] || { echo "This immutable wheelhouse must build on aarch64 Termux, got: ${ARCH:-unknown}" >&2; exit 1; }
if [ "$BUILD_MODE" = docker ]; then
  case "$(uname -m)" in
    aarch64|arm64) ;;
    *) echo "Termux Docker host is not arm64" >&2; exit 1 ;;
  esac
else
  [ "$(getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r')" = arm64-v8a ] || { echo "Android ABI is not arm64-v8a" >&2; exit 1; }
fi
printf '%s\n' 'deb https://packages.termux.dev/apt/termux-main stable main' > "$PREFIX/etc/apt/sources.list"
apt-get update
dpkg --force-confnew --configure -a
apt-get -o Dpkg::Options::="--force-confnew" -f install -y
apt-get -o Dpkg::Options::="--force-confnew" install -y \
  git curl ca-certificates coreutils dpkg tur-repo uv clang rust make pkg-config \
  binutils patchelf cmake ninja gdbm libandroid-posix-semaphore \
  libandroid-support libbz2 libcrypt libexpat libffi liblzma libsqlite \
  ncurses ncurses-ui-libs openssl readline zlib libjpeg-turbo libpng \
  freetype libwebp openjpeg littlecms libtiff libyaml
apt-get update

(cd "$BUILD_ROOT" && rm -f "$(basename "$PYTHON_DEB")" && apt-get download python3.13=3.13.13)
[ -f "$PYTHON_DEB" ] || { echo "APT did not retrieve $(basename "$PYTHON_DEB")" >&2; exit 1; }
printf '%s  %s\n' "$PYTHON_SHA256" "$PYTHON_DEB" | sha256sum -c -
[ "$(dpkg-deb -f "$PYTHON_DEB" Package)" = python3.13 ]
[ "$(dpkg-deb -f "$PYTHON_DEB" Version)" = 3.13.13 ]
[ "$(dpkg-deb -f "$PYTHON_DEB" Architecture)" = aarch64 ]
apt-get install -y "$PYTHON_DEB"
[ "$(dpkg-query -W -f='${Version}' python3.13)" = 3.13.13 ]

PYTHON="$PREFIX/bin/python3.13"
"$PYTHON" - <<'PY'
import platform
import sys

assert sys.platform == "android", sys.platform
assert sys.version_info[:3] == (3, 13, 13), sys.version
assert platform.machine().lower() in {"aarch64", "arm64"}, platform.machine()
PY

rm -rf "$BUILD_ROOT/venv" "$BUILD_ROOT/work" "$BUILD_ROOT/wheelhouse"
uv venv --python "$PYTHON" "$BUILD_ROOT/venv"
VENV_PY="$BUILD_ROOT/venv/bin/python"

readarray -t BUILD_TOOLS < <("$PYTHON" - "$MANIFEST" <<'PY'
import json, sys
m=json.load(open(sys.argv[1]))['build_tools']
for name in ('setuptools','wheel','packaging','cython','pycparser','pybind11','maturin'):
    print(f'{name}=={m[name]}')
PY
)
uv pip install --python "$VENV_PY" "${BUILD_TOOLS[@]}"

"$VENV_PY" "$REPO_DIR/scripts/build_wheels.py" \
  --manifest "$MANIFEST" \
  --output "$BUILD_ROOT/wheelhouse" \
  --work "$BUILD_ROOT/work" \
  --python "$VENV_PY" \
  --uv "$PREFIX/bin/uv" \
  --curl "$PREFIX/bin/curl"

"$VENV_PY" "$REPO_DIR/scripts/verify_wheelhouse.py" \
  --manifest "$MANIFEST" \
  --wheelhouse "$BUILD_ROOT/wheelhouse" \
  --resolved "$REPO_DIR/audit/resolved.txt" \
  --uv "$PREFIX/bin/uv" \
  --python "$VENV_PY" \
  --install-test
dpkg-query -W -f='${Package}=${Version}\n' | LC_ALL=C sort > "$BUILD_ROOT/wheelhouse/system-packages.txt"
"$VENV_PY" "$REPO_DIR/scripts/checksum_artifact.py" \
  "$BUILD_ROOT/wheelhouse/SHA256SUMS" \
  "$BUILD_ROOT/wheelhouse/system-packages.txt"
