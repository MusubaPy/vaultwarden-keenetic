#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# deploy.sh — Deploy Vaultwarden to Keenetic router via SSH
# ──────────────────────────────────────────────────────────────
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROUTER="${ROUTER:-root@192.168.1.1}"
PORT="${SSH_PORT:-222}"

info()  { printf "\033[1;34m→ %s\033[0m\n" "$*"; }
error() { printf "\033[1;31m✗ %s\033[0m\n" "$*" >&2; exit 1; }

ssh_cmd() { ssh -p "$PORT" -o StrictHostKeyChecking=no "$ROUTER" "$@"; }
scp_cmd() { scp -O -P "$PORT" -o StrictHostKeyChecking=no "$@"; }

# ── Preflight ────────────────────────────────────────────────
BINARY="$REPO_ROOT/build/vaultwarden"
[[ -f "$BINARY" ]] || error "Binary not found. Run: ./scripts/build.sh"

# ── Create directories ───────────────────────────────────────
info "Creating directories on router"
ssh_cmd "mkdir -p /opt/bin /opt/lib /opt/etc/ssl/certs /opt/etc/vaultwarden \
    /opt/share/vaultwarden/web-vault /opt/var/vaultwarden /opt/var/log /opt/var/run /opt/etc/init.d"

# ── Upload binary ────────────────────────────────────────────
info "Uploading vaultwarden binary"
scp_cmd "$BINARY" "$ROUTER:/opt/bin/vaultwarden"

# ── Upload libatomic ─────────────────────────────────────────
LIBATOMIC="$SDK/staging_dir/toolchain-mips_mips32r2_gcc-8.4.0_glibc-2.27/mips-openwrt-linux-gnu/lib/libatomic.so.1.2.0"
if [[ -f "${LIBATOMIC:-}" ]]; then
    info "Uploading libatomic.so.1"
    scp_cmd "$LIBATOMIC" "$ROUTER:/opt/lib/libatomic.so.1"
fi

# ── CA certificates ──────────────────────────────────────────
info "Uploading CA certificates"
if [[ ! -f "$REPO_ROOT/config/ca-certificates.crt" ]]; then
    curl -sSL -o "$REPO_ROOT/config/ca-certificates.crt" https://curl.se/ca/cacert.pem
fi
scp_cmd "$REPO_ROOT/config/ca-certificates.crt" "$ROUTER:/opt/etc/ssl/certs/ca-certificates.crt"

# ── TLS certificate ──────────────────────────────────────────
if [[ -f "$REPO_ROOT/config/cert.pem" && -f "$REPO_ROOT/config/key.pem" ]]; then
    info "Uploading TLS certificate"
    scp_cmd "$REPO_ROOT/config/cert.pem" "$ROUTER:/opt/etc/vaultwarden/cert.pem"
    scp_cmd "$REPO_ROOT/config/key.pem"  "$ROUTER:/opt/etc/vaultwarden/key.pem"
fi

# ── Web vault ────────────────────────────────────────────────
info "Uploading web vault"
if [[ ! -d "$REPO_ROOT/build/web-vault" ]]; then
    info "  Downloading web vault..."
    LATEST=$(curl -sSL "https://api.github.com/repos/dani-garcia/bw_web_builds/releases/latest" | grep '"tag_name"' | cut -d'"' -f4)
    curl -sSL -o /tmp/vw-webvault.tar.gz "https://github.com/dani-garcia/bw_web_builds/releases/download/$LATEST/bw_web_$LATEST.tar.gz"
    mkdir -p "$REPO_ROOT/build"
    tar xzf /tmp/vw-webvault.tar.gz -C "$REPO_ROOT/build/"
fi
scp_cmd -r "$REPO_ROOT/build/web-vault/" "$ROUTER:/opt/share/vaultwarden/web-vault/"

# ── Init script ──────────────────────────────────────────────
info "Uploading init script"
scp_cmd "$REPO_ROOT/config/S91vaultwarden" "$ROUTER:/opt/etc/init.d/S91vaultwarden"
ssh_cmd "chmod +x /opt/bin/vaultwarden /opt/etc/init.d/S91vaultwarden && ldconfig"

# ── Start ────────────────────────────────────────────────────
info "Starting Vaultwarden"
ssh_cmd "kill \$(pgrep vaultwarden) 2>/dev/null || true; /opt/etc/init.d/S91vaultwarden start"
sleep 3
ssh_cmd "/opt/etc/init.d/S91vaultwarden status"

echo ""
info "Deploy complete"
echo "  Local:  https://192.168.1.1:8080"
echo "  Admin:  https://192.168.1.1:8080/admin"
echo ""
echo "  1. Accept the self-signed certificate warning"
echo "  2. Create your account"
echo "  3. Login to /admin and disable signups"
