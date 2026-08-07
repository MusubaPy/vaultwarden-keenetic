#!/usr/bin/env bash
# One-command Vaultwarden update for Keenetic MIPS32r2.
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VW_SRC="${VAULTWARDEN_SRC:-$REPO_ROOT/build/source}"
VW_REPO="${VAULTWARDEN_REPO:-https://github.com/dani-garcia/vaultwarden.git}"
ROUTER="${ROUTER:-root@192.168.1.1}"
PORT="${SSH_PORT:-222}"
CONTROL_PATH="${TMPDIR:-/tmp}/vw-keenetic-ssh-%C"
REMOTE_NEW=/opt/bin/vaultwarden.new
REMOTE_OLD=/opt/bin/vaultwarden.previous
REMOTE_BIN=/opt/bin/vaultwarden
INIT=/opt/etc/init.d/S91vaultwarden
LOG=/opt/var/log/vaultwarden.log
LOCAL_LOG="$REPO_ROOT/build/router-vaultwarden.log"

download_log() {
    mkdir -p "$REPO_ROOT/build"
    ssh_cmd "tail -200 '$LOG'" > "$LOCAL_LOG" 2>&1 || true
    printf '\nRecent router log entries:\n' >&2
    tail -40 "$LOCAL_LOG" >&2
    printf '\nFull router log saved locally: %s\n' "$LOCAL_LOG" >&2
}

info() { printf '\033[1;34m→ %s\033[0m\n' "$*"; }
error() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
ssh_base=(ssh -p "$PORT" -o ControlMaster=auto -o ControlPersist=10m -o ControlPath="$CONTROL_PATH" "$ROUTER")
scp_base=(scp -O -P "$PORT" -o ControlMaster=auto -o ControlPersist=10m -o ControlPath="$CONTROL_PATH")
ssh_cmd() { "${ssh_base[@]}" "$@"; }
close_ssh() { ssh -p "$PORT" -o ControlPath="$CONTROL_PATH" -O exit "$ROUTER" >/dev/null 2>&1 || true; }
trap close_ssh EXIT

command -v git >/dev/null || error "git not found"
command -v ssh >/dev/null || error "ssh not found"
command -v scp >/dev/null || error "scp not found"

info "Opening one reusable SSH session"
ssh_cmd true

info "Checking live router configuration"
ssh_cmd "test -x '$INIT' && test -x '$REMOTE_BIN' && grep -q '^export ADMIN_TOKEN=' '$INIT' && test -d /opt/var/vaultwarden" \
    || error "Live binary, init script, ADMIN_TOKEN, or data directory is missing; refusing update"

if [[ ! -d "$VW_SRC/.git" ]]; then
    info "Cloning upstream Vaultwarden"
    mkdir -p "$(dirname "$VW_SRC")"
    git clone "$VW_REPO" "$VW_SRC"
fi

info "Updating upstream Vaultwarden with a clean fast-forward checkout"
git -C "$VW_SRC" remote set-url origin "$VW_REPO"
git -C "$VW_SRC" fetch --prune origin
git -C "$VW_SRC" reset --hard origin/main
git -C "$VW_SRC" clean -fd -- .cargo vendor
git -C "$VW_SRC" submodule update --init --recursive

info "Applying maintained MIPS patches and cross-compiling"
VAULTWARDEN_SRC="$VW_SRC" "$REPO_ROOT/scripts/build.sh"
BINARY="$REPO_ROOT/build/vaultwarden"
[[ -x "$BINARY" ]] || error "Build did not produce $BINARY"
file "$BINARY" | grep -q 'ELF 32-bit MSB.*MIPS' || error "Built binary is not MIPS32 big-endian ELF"

info "Uploading staged binary"
"${scp_base[@]}" "$BINARY" "$ROUTER:$REMOTE_NEW"

info "Installing atomically and restarting"
if ! ssh_cmd "set -e; chmod 755 '$REMOTE_NEW'; '$REMOTE_NEW' --version >/dev/null; '$INIT' stop || true; rm -f '$REMOTE_OLD'; mv '$REMOTE_BIN' '$REMOTE_OLD'; mv '$REMOTE_NEW' '$REMOTE_BIN'; if '$INIT' start; then exit 0; fi; rm -f '$REMOTE_BIN'; mv '$REMOTE_OLD' '$REMOTE_BIN'; '$INIT' start; exit 1"; then
    error "New binary failed to start; previous binary was restored"
fi

info "Verifying process and listening port"
if ! ssh_cmd "i=0; while [ \"\$i\" -lt 15 ]; do '$INIT' status >/dev/null && netstat -lnt 2>/dev/null | grep -q '[:.]8080[[:space:]]' && exit 0; i=\$((i + 1)); sleep 1; done; exit 1"; then
    download_log
    info "Health check failed; rolling back"
    ssh_cmd "set -e; '$INIT' stop || true; rm -f '$REMOTE_BIN'; mv '$REMOTE_OLD' '$REMOTE_BIN'; '$INIT' start"
    error "Health check failed; previous binary was restored. Router log: $LOCAL_LOG"
fi

VERSION="$(ssh_cmd "$REMOTE_BIN --version")"
info "Update complete: $VERSION"
printf '  Public: https://vaultwarden.example.keenetic.pro\n'
printf '  Config and ADMIN_TOKEN: preserved\n'
printf '  Data: /opt/var/vaultwarden (untouched)\n'
