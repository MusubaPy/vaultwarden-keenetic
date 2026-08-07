#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# gen-tls.sh — Generate a self-signed TLS certificate for Vaultwarden
# ──────────────────────────────────────────────────────────────
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOMAIN="${1:?Usage: $0 DOMAIN [ROUTER_IP]}"
ROUTER_IP="${2:-192.168.1.1}"

info()  { printf "\033[1;34m→ %s\033[0m\n" "$*"; }

info "Generating TLS certificate for $DOMAIN"

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$REPO_ROOT/config/key.pem" \
    -out "$REPO_ROOT/config/cert.pem" \
    -days 3650 \
    -subj "/CN=$DOMAIN" \
    -addext "subjectAltName=DNS:$DOMAIN,IP:$ROUTER_IP"

echo ""
info "Certificate generated"
echo "  cert: $REPO_ROOT/config/cert.pem"
echo "  key:  $REPO_ROOT/config/key.pem"
