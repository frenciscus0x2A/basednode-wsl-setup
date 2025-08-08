#!/usr/bin/env bash
set -euo pipefail
# Abort on error (-e), undefined variables (-u), and fail pipelines (pipefail).

VERSION="0.1.3"

###############################################################################
# Pretty printing helpers (robust + ASCII-first)
###############################################################################
# Rules:
# - Default to ASCII (portable)
# - Only use Unicode if: stdout is a TTY AND locale is UTF-8 AND NO_UNICODE is not set
USE_UNICODE=0
if [[ -z "${NO_UNICODE:-}" ]] && [[ -t 1 ]] && command -v locale >/dev/null 2>&1; then
  if locale charmap 2>/dev/null | grep -qi 'utf-8'; then
    USE_UNICODE=1
  fi
fi

SEP_CHAR='-'
DASH='-'
OK='OK'
WARN='WARN'
INFO='INFO'
ERR='ERROR'
if [[ "$USE_UNICODE" -eq 1 ]]; then
  SEP_CHAR='━'
  DASH='—'
  OK='✅'
  WARN='⚠️'
  INFO='ℹ️'
  ERR='❌'
fi

print_sep() {
  # Cap width to 80 cols to avoid ultra-long bars in some consoles
  local cols="${COLUMNS:-80}"
  [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
  (( cols > 80 )) && cols=80
  printf '%*s\n' "$cols" '' | tr ' ' "$SEP_CHAR"
}
print_h1() { print_sep; printf " %s %s version %s\n" "$1" "$DASH" "$VERSION"; print_sep; }
print_h2() { print_sep; printf " %s\n" "$1"; print_sep; }

say_ok()   { printf "%s %s\n" "$OK"   "$*"; }
say_warn() { printf "%s %s\n" "$WARN" "$*"; }
say_info() { printf "%s %s\n" "$INFO" "$*"; }
say_err()  { printf "%s %s\n" "$ERR"  "$*"; }

# Gracefully handle Ctrl+C interrupts.
on_interrupt() { echo ""; say_warn "Script interrupted. Exiting safely."; exit 1; }
trap on_interrupt INT

###############################################################################
# Constants (single source of truth)
###############################################################################
REPO_URL="https://github.com/BF1337/basednode.git"
REPO_BRANCH="main"
SPEC_URL="https://raw.githubusercontent.com/getbasedai/basednode/main/mainnet1_raw.json"
WORKDIR="$HOME/basednode"
BUILD_LOG="$HOME/basednode_build.log"
SPEC_PATH="$WORKDIR/mainnet1_raw.json"

echo ""
print_h1 "BasedNode install script"

###############################################################################
# STEP 1 — Sudo
###############################################################################
echo ""
print_h2 "STEP 1 $DASH Checking sudo access…"
if ! sudo -v; then
  say_err "Wrong password or sudo failed multiple times. Exiting."
  exit 1
fi
say_ok "Sudo access confirmed."

###############################################################################
# STEP 1.5 — Environment checks
###############################################################################
echo ""
print_h2 "STEP 1.5 $DASH Environment checks (WSL & Ubuntu)"
if ! grep -qi microsoft /proc/version; then
  say_err "This installer is intended for Windows Subsystem for Linux (WSL). Aborting."
  exit 1
fi
# Detect WSL by checking /proc/version for "microsoft" (case-insensitive).

. /etc/os-release || true
if [ "${VERSION_ID:-}" != "22.04" ]; then
  say_warn "Ubuntu ${VERSION_ID:-unknown} detected. This guide is tested on 22.04 LTS. Continuing anyway."
fi
say_ok "WSL/Ubuntu checks passed."

###############################################################################
# STEP 2 — Base packages
###############################################################################
echo ""
print_h2 "STEP 2 $DASH Updating system and installing base tools…"
DEPS=(software-properties-common curl git clang build-essential libssl-dev pkg-config libclang-dev protobuf-compiler jq)
MISSING=()
for pkg in "${DEPS[@]}"; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    MISSING+=("$pkg")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  say_info "Missing packages detected: ${MISSING[*]}"
  sudo apt update
  sudo apt install -y "${MISSING[@]}"
else
  say_info "All dependencies already installed, skipping apt install."
fi
say_ok "System updated and packages installed."

###############################################################################
# STEP 3 — Rust toolchain (nightly + WASM)
###############################################################################
echo ""
print_h2 "STEP 3 $DASH Checking Rust toolchain (nightly required)…"
PINNED_NIGHTLY="nightly-2025-01-07"   # Pin to reduce upstream breakage

if ! command -v rustup >/dev/null 2>&1; then
  say_info "Rustup not found. Installing rustup and Rust nightly…"
  rm -f rustup-init.sh rustup-install.log
  curl -sSf -o rustup-init.sh https://sh.rustup.rs
  chmod +x rustup-init.sh

  MAX_ATTEMPTS=5
  LOG_FILE="rustup-install.log"
  SUCCESS=false
  for attempt in $(seq 1 $MAX_ATTEMPTS); do
    DELAY=$((attempt * 10))
    say_info "Installing Rust (attempt $attempt/$MAX_ATTEMPTS)…"
    if ./rustup-init.sh -y --default-toolchain "$PINNED_NIGHTLY" --no-modify-path >"$LOG_FILE" 2>&1; then
      SUCCESS=true; break
    else
      say_warn "Attempt $attempt failed. Retrying in $DELAY seconds…"
      sleep $DELAY
    fi
  done
  rm -f rustup-init.sh
  if ! $SUCCESS; then
    echo ""
    say_err "Rust install failed after $MAX_ATTEMPTS attempts. See '$LOG_FILE' for details."
    exit 1
  fi

  # Ensure PATH for cargo
  if ! grep -q 'source $HOME/.cargo/env' ~/.bashrc; then
    echo 'source $HOME/.cargo/env' >> ~/.bashrc
  fi
  # shellcheck disable=SC1090
  source "$HOME/.cargo/env"
else
  say_info "Rustup already installed. Skipping rustup installation."
  if ! rustup toolchain list | grep -q "$PINNED_NIGHTLY"; then
    say_info "Installing pinned nightly toolchain: $PINNED_NIGHTLY"
    rustup toolchain install "$PINNED_NIGHTLY"
  fi
  if ! grep -q 'source $HOME/.cargo/env' ~/.bashrc; then
    echo 'source $HOME/.cargo/env' >> ~/.bashrc
  fi
  # shellcheck disable=SC1090
  source "$HOME/.cargo/env"
fi

NIGHTLY_VERSION="$PINNED_NIGHTLY"
say_info "Ensuring WASM target for $NIGHTLY_VERSION…"
if ! rustup target list --toolchain "$NIGHTLY_VERSION" | grep -q 'wasm32-unknown-unknown (installed)'; then
  rustup target add wasm32-unknown-unknown --toolchain "$NIGHTLY_VERSION"
fi

if ! command -v cargo >/dev/null 2>&1; then
  say_err "Rust installed, but 'cargo' not found. Close and reopen your terminal, then rerun this script."
  exit 1
fi
say_ok "Rust nightly ($NIGHTLY_VERSION) installed and ready."

###############################################################################
# STEP 4 — Clone & build
###############################################################################
echo ""
print_h2 "STEP 4 $DASH Cloning and building BasedNode…"
cd "$HOME"

if [ -d "basednode" ]; then
  say_info "Folder 'basednode' exists. Updating repo…"
  cd basednode
  MAX_PULL_ATTEMPTS=3
  PULL_SUCCESS=false
  for attempt in $(seq 1 $MAX_PULL_ATTEMPTS); do
    if git pull; then PULL_SUCCESS=true; break
    else say_warn "git pull failed (attempt $attempt). Retrying in 10s…"; sleep 10; fi
  done
  if ! $PULL_SUCCESS; then
    say_err "Failed to update BasedNode repository after $MAX_PULL_ATTEMPTS attempts."
    exit 1
  fi
else
  MAX_CLONE_ATTEMPTS=3
  CLONE_SUCCESS=false
  for attempt in $(seq 1 $MAX_CLONE_ATTEMPTS); do
    if git clone --branch "$REPO_BRANCH" "$REPO_URL"; then CLONE_SUCCESS=true; break
    else say_warn "Git clone failed (attempt $attempt). Retrying in 10s…"; sleep 10; fi
  done
  if ! $CLONE_SUCCESS; then
    say_err "Failed to clone BasedNode repository after $MAX_CLONE_ATTEMPTS attempts."
    exit 1
  fi
  cd basednode
fi

say_info "Building BasedNode… (this may take several minutes)"
if cargo +"$NIGHTLY_VERSION" build --release -j "$(nproc)" | tee "$BUILD_LOG"; then
  say_ok "Build finished."
else
  say_warn "Build failed. Attempting 'cargo clean' and rebuild with -j 1…"
  cargo clean
  if ! cargo +"$NIGHTLY_VERSION" build --release -j 1 | tee -a "$BUILD_LOG"; then
    say_err "Build failed even after clean. See '$BUILD_LOG' for details."
    exit 1
  fi
  say_ok "Build finished after clean (single job)."
fi
# Fallback to single-threaded build to reduce RAM usage (common OOM in WSL).

# Install the binary system-wide for consistent usage across aliases and manual runs.
sudo install -m 0755 ./target/release/basednode /usr/local/bin/basednode
if ! command -v basednode >/dev/null 2>&1; then
  say_err "BasedNode binary not found in PATH after installation."
  exit 1
fi
say_ok "BasedNode binary installed globally."
mkdir -p "$WORKDIR"

###############################################################################
# STEP 4.5 — Chain spec
###############################################################################
echo ""
print_h2 "STEP 4.5 $DASH Ensuring chain spec (mainnet1_raw.json)"
if [ ! -f "$SPEC_PATH" ]; then
  say_info "mainnet1_raw.json not found locally. Downloading from official repo…"
  mkdir -p "$WORKDIR"
  if ! curl -fL -o "$SPEC_PATH" "$SPEC_URL"; then
    say_err "Unable to download chain spec. Check your network or try again later."
    exit 1
  fi
  # Optional: verify a known SHA256 here if you want to pin the artifact.
fi
say_ok "Chain spec ready at: $SPEC_PATH"

###############################################################################
# STEP 5 — Aliases
###############################################################################
echo ""
print_h2 "STEP 5 $DASH Creating aliases for running BasedNode"

BACKUP_FILE="$HOME/.bashrc.bak.$(date +%Y%m%d%H%M%S)"
cp "$HOME/.bashrc" "$BACKUP_FILE"
say_info "Backup of ~/.bashrc saved to $BACKUP_FILE"

# Clean previous BasedNode alias block (idempotent re-run).
sed -i '/# === BasedNode aliases ===/,/# ========================/d' "$HOME/.bashrc"

# Updated alias block (add/remove here ONLY)
cat <<'EOF' >> "$HOME/.bashrc"

# === BasedNode aliases ===
# Centralize spec/bootnode/log to make updates trivial in one place.
BASED_SPEC="$HOME/basednode/mainnet1_raw.json"
BASED_BOOT="/dns/mainnet.basedaibridge.com/tcp/30333/p2p/12D3KooWCQy4hiiA9tHxvQ2PPaSY3mUM6NkMnbsYf2v4FKbLAtUh"
BASED_LOG="$HOME/basednode/basednode.log"

alias basednode-run='(basednode \
  --name "${BASEDNODE_NAME:-MyBasedNode}" \
  --chain "$BASED_SPEC" \
  --rpc-methods Safe \
  --rpc-cors=none \
  --bootnodes "$BASED_BOOT" \
  --log info 2>&1 | tee -a "$BASED_LOG" | grep -Ev "Successfully ran block step.|Not the block to update emission values.")'
# Foreground run with filtered logs and persistent log file.

alias basednode-run-bg='nohup basednode \
  --name "${BASEDNODE_NAME:-MyBasedNode}" \
  --chain "$BASED_SPEC" \
  --rpc-methods Safe \
  --rpc-cors=none \
  --bootnodes "$BASED_BOOT" \
  --log info >> "$BASED_LOG" 2>&1 & echo $! > "$HOME/basednode/basednode.pid" && echo "Started in background (PID $(cat $HOME/basednode/basednode.pid))"'
# Background execution with nohup; PID stored for reference.

alias stop-node='if pgrep -f "basednode"; then pkill -f basednode && echo "Node stopped."; else echo "No node running."; fi'
alias restart-node='stop-node; sleep 1; basednode-run'
alias node-logs='tail -n 500 -f "$BASED_LOG"'
# View last 500 log lines and follow updates in real-time.

alias check-health='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"system_health","params":[]}'\'' | jq'
alias check-peers='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"system_peers","params":[]}'\'' | jq'
alias check-sync='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"system_syncState","params":[]}'\'' | jq'
alias check-version='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"system_version","params":[]}'\'' | jq'
alias check-pending='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"author_pendingExtrinsics","params":[]}'\'' | jq'
alias node-peerid='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"system_localPeerId","params":[]}'\'' | jq -r .result'
alias basednode-help='cat ~/basednode/BASENODE_COMMANDS.txt'
# ========================
EOF

# Generate the unique help file (source of truth for all aliases).
cat <<'DOC' > "$WORKDIR/BASENODE_COMMANDS.txt"
-------------------------------------------------------------------------------
BasedNode — Useful commands (aliases)
-------------------------------------------------------------------------------
basednode-run        # Start BasedNode with filtered logs
basednode-run-bg     # Start BasedNode in background (nohup)
stop-node            # Stop the running node
restart-node         # Restart the node
node-logs            # View node logs (background mode)
check-health         # Check node health (RPC)
check-peers          # List connected peers
check-sync           # Check blockchain sync status
check-version        # Show node software version
check-pending        # Show pending extrinsics
node-peerid          # Show your node's Peer ID
basednode-help       # Display this help
-------------------------------------------------------------------------------
DOC

# Reload aliases for this session (so they’re usable immediately).
# shellcheck disable=SC1090
source "$HOME/.bashrc"
say_ok "Aliases added."

echo ""
print_h2 "INFO $DASH How to use your new BasedNode aliases"
cat "$WORKDIR/BASENODE_COMMANDS.txt"
echo ""

###############################################################################
# STEP 6 — Final foreground run
###############################################################################
print_h2 "STEP 6 $DASH Running BasedNode in foreground"

say_ok "BasedNode installation completed!"
say_info "Your node will sync and connect automatically."
say_warn "RPC lets other programs (or people) control your node. Do NOT open RPC to the Internet unless you know what you’re doing."
say_info "To stop BasedNode, press CTRL+C anytime."
say_info "Next time, use 'basednode-run' (foreground) or 'basednode-run-bg' (background)."

BASED_LOG="$WORKDIR/basednode.log"
basednode \
  --name "${BASEDNODE_NAME:-MyBasedNode}" \
  --chain "$SPEC_PATH" \
  --rpc-methods Safe \
  --rpc-cors=none \
  --bootnodes /dns/mainnet.basedaibridge.com/tcp/30333/p2p/12D3KooWCQy4hiiA9tHxvQ2PPaSY3mUM6NkMnbsYf2v4FKbLAtUh \
  --log info 2>&1 | tee -a "$BASED_LOG" | grep -Ev "Successfully ran block step.|Not the block to update emission values."

echo ""
print_h2 "The node has stopped (if you pressed CTRL+C)."

say_info "NEXT STEPS:"
echo "  • To launch BasedNode again:  basednode-run"
echo "  • To run in background:       basednode-run-bg"
echo "  • To view logs:               node-logs"

print_sep
echo ""
print_sep
