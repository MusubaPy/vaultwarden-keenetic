#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# build.sh — Cross-compile Vaultwarden for MIPS32r2 (Entware)
# ──────────────────────────────────────────────────────────────
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VW_SRC="${VAULTWARDEN_SRC:-$REPO_ROOT/build/source}"
MANAGED_SRC="$REPO_ROOT/build/source"
VW_REPO="${VAULTWARDEN_REPO:-https://github.com/dani-garcia/vaultwarden.git}"
SDK="${ENTWARE_SDK:-$HOME/tmp/entware-sdk}"
TOOLCHAIN="$SDK/staging_dir/toolchain-mips_mips32r2_gcc-8.4.0_glibc-2.27"
OUTPUT="$REPO_ROOT/build/vaultwarden"

info()  { printf "\033[1;34m→ %s\033[0m\n" "$*"; }
error() { printf "\033[1;31m✗ %s\033[0m\n" "$*" >&2; exit 1; }

build_heartbeat() {
    local frames='|/-\\' frame=0 elapsed=0 status
    while true; do
        status="$(tail -1 "${BUILD_LOG:-/dev/null}" 2>/dev/null | tr '\r\n' '  ' | cut -c1-80)"
        printf '\r\033[K\033[1;34m%s Building locally: %d s\033[0m' "${frames:frame++%4:1}" "$elapsed" >&2
        [[ -z "$status" ]] || printf ' | %s' "$status" >&2
        sleep 1
        ((elapsed += 1))
    done
}

stop_heartbeat() {
    if [[ -n "${HEARTBEAT_PID:-}" ]]; then
        kill "$HEARTBEAT_PID" 2>/dev/null || true
        wait "$HEARTBEAT_PID" 2>/dev/null || true
        printf '\r\033[K' >&2
    fi
}

# ── Preflight ────────────────────────────────────────────────
if [[ "$VW_SRC" != "$MANAGED_SRC" ]]; then
    error "Refusing to modify external VAULTWARDEN_SRC=$VW_SRC; updates use the managed checkout at $MANAGED_SRC"
fi
if [[ ! -e "$VW_SRC" ]]; then
    info "Cloning Vaultwarden source into $VW_SRC"
    mkdir -p "$(dirname "$VW_SRC")"
    git clone "$VW_REPO" "$VW_SRC"
elif [[ ! -d "$VW_SRC/.git" ]]; then
    error "Managed source path exists but is not a Git checkout: $VW_SRC"
fi

# Return the managed checkout to its upstream state before injecting local patches.
git -C "$VW_SRC" reset --hard HEAD >/dev/null
git -C "$VW_SRC" clean -fd -- .cargo vendor >/dev/null
[[ -d "$TOOLCHAIN" ]] || error "Entware SDK not found at $SDK
  Download: https://wiki.keenetic.com/entware"
command -v cargo >/dev/null  || error "Rust toolchain not found
  Install: curl https://sh.rustup.rs -sSf | sh"
rustup toolchain list | grep -q nightly || error "Rust nightly not found
  Install: rustup toolchain install nightly && rustup +nightly component add rust-src"

# ── Apply patches ────────────────────────────────────────────
# The checkout under build/ is disposable and managed exclusively by this script.
info "Applying maintained MIPS vendor snapshots to $VW_SRC"
rm -rf "$VW_SRC/vendor/cached" "$VW_SRC/vendor/mea" "$VW_SRC/vendor/getrandom"
mkdir -p "$VW_SRC/vendor"
cp -a "$REPO_ROOT/vendor/cached" "$VW_SRC/vendor/"
cp -a "$REPO_ROOT/vendor/mea" "$VW_SRC/vendor/"
cp -a "$REPO_ROOT/vendor/getrandom" "$VW_SRC/vendor/"
# ── Cargo config ─────────────────────────────────────────────
info "Writing .cargo/config.toml"
mkdir -p "$VW_SRC/.cargo"
sed "s|__TOOLCHAIN_DIR__|$TOOLCHAIN|g" \
    "$REPO_ROOT/config/.cargo/config.toml" > "$VW_SRC/.cargo/config.toml"

# Ensure [patch.crates-io] is in Cargo.toml
PATCH_BLOCK='[patch.crates-io]
mea = { path = "vendor/mea" }
cached = { path = "vendor/cached" }
getrandom = { path = "vendor/getrandom" }'
if grep -q '^\[patch\.crates-io\]$' "$VW_SRC/Cargo.toml"; then
    error "Cargo.toml already contains [patch.crates-io]; reset the managed checkout before building"
fi
info "Adding maintained [patch.crates-io] overrides"
printf '\n%s\n' "$PATCH_BLOCK" >> "$VW_SRC/Cargo.toml"

# Skip compilation when all build inputs match the existing binary.
BUILD_FINGERPRINT_FILE="$REPO_ROOT/build/build.fingerprint"
BUILD_FINGERPRINT="$(
    {
        git -C "$VW_SRC" rev-parse HEAD
        rustc +nightly --version
        printf '%s\n' 'target=mips-unknown-linux-gnu' 'features=sqlite,vendored_openssl' 'build-std=std,panic_abort'
        sha256sum "$VW_SRC/Cargo.toml" "$VW_SRC/Cargo.lock" "$VW_SRC/.cargo/config.toml"
        find "$VW_SRC/vendor/cached" "$VW_SRC/vendor/mea" "$VW_SRC/vendor/getrandom" -type f -print0 \
            | sort -z \
            | xargs -0 sha256sum
    } | sha256sum | cut -d' ' -f1
)"

if [[ -x "$OUTPUT" && -f "$BUILD_FINGERPRINT_FILE" ]] \
    && [[ "$(cat "$BUILD_FINGERPRINT_FILE")" == "$BUILD_FINGERPRINT" ]]; then
    info "Build inputs unchanged; reusing $OUTPUT"
    exit 0
fi

# Build
info "Building Vaultwarden locally on this PC"
cd "$VW_SRC"
BUILD_LOG="$REPO_ROOT/build/cargo-build.log"
mkdir -p "$REPO_ROOT/build"
build_heartbeat &
HEARTBEAT_PID=$!
trap stop_heartbeat EXIT INT TERM
if STAGING_DIR="$SDK/staging_dir" \
    CC_mips_unknown_linux_gnu="$TOOLCHAIN/bin/mips-openwrt-linux-gnu-gcc" \
    AR_mips_unknown_linux_gnu="$TOOLCHAIN/bin/mips-openwrt-linux-gnu-ar" \
    cargo +nightly build \
        -Z build-std=std,panic_abort \
        --release \
        --features sqlite,vendored_openssl >"$BUILD_LOG" 2>&1; then
    stop_heartbeat
    HEARTBEAT_PID=
    trap - EXIT INT TERM
else
    status=$?
    stop_heartbeat
    HEARTBEAT_PID=
    trap - EXIT INT TERM
    cat "$BUILD_LOG" >&2
    exit "$status"
fi

# Output
mkdir -p "$REPO_ROOT/build"
cp "$VW_SRC/target/mips-unknown-linux-gnu/release/vaultwarden" "$OUTPUT"
chmod +x "$OUTPUT"
printf '%s\n' "$BUILD_FINGERPRINT" > "$BUILD_FINGERPRINT_FILE"

echo ""
info "Build complete"
echo "  Binary: $OUTPUT"
echo "  Size:   $(du -h "$OUTPUT" | cut -f1)"
echo ""
file "$OUTPUT"
