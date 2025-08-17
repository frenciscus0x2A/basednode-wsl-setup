#!/usr/bin/env bash
set -euo pipefail
# Abort on error (-e), undefined variables (-u), and fail pipelines (pipefail).

VERSION="0.1.0"

###############################################################################
# Pretty-print helpers (ASCII only for maximum console compatibility)
###############################################################################
SEP_CHAR='-'
DASH='-'
OK='OK'
WARN='WARN'
INFO='INFO'
ERR='ERROR'

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
WORKDIR="$HOME/basednode"
BUILD_LOG="$HOME/basednode_build.log"
SPEC_PATH="$WORKDIR/mainnet1_raw.json"

echo ""
print_h1 "BasedNode install script"


###############################################################################
# STEP 1 — Prerequisites (sudo + environment checks)
###############################################################################
echo ""
print_h2 "STEP 1 - Prerequisites (sudo + environment checks)"

# Sudo check
if ! sudo -v; then
  say_err "Wrong password or sudo failed multiple times. Exiting."
  exit 1
fi
say_ok "Sudo access confirmed."

# WSL/Ubuntu checks
if ! grep -qi microsoft /proc/version; then
  say_warn "This installer was written with WSL in mind, but should work on Linux in general. Continuing."
else
  say_ok "WSL detected."
fi
. /etc/os-release || true
if [ "${VERSION_ID:-}" != "22.04" ] && [ "${VERSION_ID:-}" != "20.04" ]; then
  say_warn "Ubuntu ${VERSION_ID:-unknown} detected. Script tested on 20.04/22.04 LTS. Continuing anyway."
fi
say_ok "Environment checks passed."

###############################################################################
# STEP 2 — Base packages
###############################################################################
echo ""
print_h2 "STEP 2 - Updating system and installing base tools..."
DEPS=(software-properties-common curl git clang build-essential libssl-dev pkg-config libclang-dev protobuf-compiler jq)
MISSING=()
for pkg in "${DEPS[@]}"; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    MISSING+=("$pkg")
  fi
done

if [ "${#MISSING[@]}" -gt 0 ]; then
  say_info "Installing missing packages: ${MISSING[*]}"
  sudo apt-get update -y
  sudo apt-get install -y "${MISSING[@]}"
else
  say_ok "All required packages already installed."
fi


###############################################################################
# STEP 3 — Rust toolchain (nightly + WASM)
###############################################################################
echo ""
print_h2 "STEP 3 - Checking Rust toolchain (nightly required)..."
PINNED_NIGHTLY="nightly-2025-01-07"   # Pin to reduce upstream breakage

if ! command -v rustup >/dev/null 2>&1; then
  say_info "Rustup not found. Installing rustup and Rust nightly..."
  rm -f rustup-init.sh rustup-install.log
  curl -sSf -o rustup-init.sh https://sh.rustup.rs
  chmod +x rustup-init.sh

  MAX_ATTEMPTS=5
  LOG_FILE="rustup-install.log"
  SUCCESS=false
  for attempt in $(seq 1 $MAX_ATTEMPTS); do
    DELAY=$((attempt * 10))
    say_info "Installing Rust (attempt $attempt/$MAX_ATTEMPTS)..."
    if ./rustup-init.sh -y --default-toolchain "$PINNED_NIGHTLY" --no-modify-path >"$LOG_FILE" 2>&1; then
      SUCCESS=true; break
    else
      say_warn "Attempt $attempt failed. Retrying in $DELAY seconds..."
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
  if ! grep -q 'source $HOME/.cargo/env' "$HOME/.bashrc"; then
    echo 'source $HOME/.cargo/env' >> "$HOME/.bashrc"
  fi
  # shellcheck disable=SC1090
  source "$HOME/.cargo/env"
else
  say_info "Rustup already installed. Skipping rustup installation."
  if ! rustup toolchain list | grep -q "$PINNED_NIGHTLY"; then
    say_info "Installing pinned nightly toolchain: $PINNED_NIGHTLY"
    rustup toolchain install "$PINNED_NIGHTLY"
  fi
  if ! grep -q 'source $HOME/.cargo/env' "$HOME/.bashrc"; then
    echo 'source $HOME/.cargo/env' >> "$HOME/.bashrc"
  fi
  # shellcheck disable=SC1090
  source "$HOME/.cargo/env"
fi

NIGHTLY_VERSION="$PINNED_NIGHTLY"
say_info "Ensuring WASM target for $NIGHTLY_VERSION..."
if ! rustup target list --toolchain "$NIGHTLY_VERSION" | grep -q 'wasm32-unknown-unknown (installed)'; then
  rustup target add wasm32-unknown-unknown --toolchain "$NIGHTLY_VERSION"
fi

if ! command -v cargo >/dev/null 2>&1; then
  say_err "'cargo' not found in PATH. Close and reopen your terminal, then rerun this script."
  exit 1
fi
say_ok "Rust nightly ($NIGHTLY_VERSION) installed and ready."


###############################################################################
# STEP 4 — Clone & build
###############################################################################
echo ""
print_h2 "STEP 4 - Cloning and building BasedNode..."
cd "$HOME"

if [ -d "basednode" ]; then
  say_info "Folder 'basednode' exists. Updating repo..."
  cd basednode
  MAX_PULL_ATTEMPTS=3
  PULL_SUCCESS=false
  for attempt in $(seq 1 $MAX_PULL_ATTEMPTS); do
    if git pull; then PULL_SUCCESS=true; break
    else say_warn "git pull failed (attempt $attempt). Retrying in 10s..."; sleep 10; fi
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
    else say_warn "Git clone failed (attempt $attempt). Retrying in 10s..."; sleep 10; fi
  done
  if ! $CLONE_SUCCESS; then
    say_err "Failed to clone BasedNode repository after $MAX_CLONE_ATTEMPTS attempts."
    exit 1
  fi
  cd basednode
fi

say_info "Building BasedNode... (this may take several minutes)"
if cargo +"$NIGHTLY_VERSION" build --release -j "$(nproc)" | tee "$BUILD_LOG"; then
  say_ok "Build finished."
else
  say_warn "Build failed. Attempting 'cargo clean' and rebuild with -j 1..."
  cargo clean
  if ! cargo +"$NIGHTLY_VERSION" build --release -j 1 | tee -a "$BUILD_LOG"; then
    say_err "Build failed even after clean. See '$BUILD_LOG' for details."
    exit 1
  fi
  say_ok "Build finished after clean (single job)."
fi

# Install the binary system-wide for consistent usage across aliases and manual runs.
sudo install -m 0755 ./target/release/basednode /usr/local/bin/basednode
if ! command -v basednode >/dev/null 2>&1; then
  say_err "BasedNode binary not found in PATH after installation."
  exit 1
fi
say_ok "BasedNode binary installed globally."
mkdir -p "$WORKDIR"

###############################################################################
# STEP 5 — Chain spec (from BF1337 repo)
###############################################################################
echo ""
print_h2 "STEP 5 - Ensuring chain spec (mainnet1_raw.json)"
# We rely on the spec from the cloned BF1337 repo (no remote download here).
if [ ! -f "$SPEC_PATH" ]; then
  say_err "Spec not found at $SPEC_PATH. Did the clone succeed? (Expected file in repo root)"
  exit 1
fi
say_ok "Chain spec ready at: $SPEC_PATH"


###############################################################################
# STEP 6 — First-run config & bootnodes list (hardcoded peers → BF1337 path)
###############################################################################
echo ""
print_h2 "STEP 6 - Config & bootnodes (write hardcoded peers to ~/.config/basednode-bootnodes.list)"

CONF="${HOME}/.config/basednode-run.env"
if [ -f "$CONF" ]; then
  say_info "Config exists at $CONF (leaving as-is)."
else
  say_info "Creating default config at $CONF"

  DEFAULT_NAME="BasedWSL-$("frenciscus_test" | cut -d. -f1)"
  DEFAULT_BOOTNODES="$(jq -r '.bootNodes[]? // empty' "$SPEC_PATH" 2>/dev/null | paste -sd, - || true)"

  cat >"$CONF" <<EOC
# BasedNode runtime configuration (auto-generated)
# You can edit this file later if you want to customize.
BASEDNODE_NAME="$DEFAULT_NAME"
BASED_SPEC="$SPEC_PATH"
BASED_LOG="$WORKDIR/basednode.log"

# Bootnodes (comma-separated). Auto-detected from the chain spec if available.
# If this remains empty, your node may stay with 0 peers until you add some.
BASED_BOOT="${DEFAULT_BOOTNODES}"
EOC
  chmod 600 "$CONF"
  say_ok "Wrote $CONF"
fi

# Destination expected by our wrappers / tooling
DEST_BOOT_FILE="${HOME}/.config/basednode-bootnodes.list"
mkdir -p "$(dirname "$DEST_BOOT_FILE")"

# Write the authoritative list (always overwrite)
cat > "$DEST_BOOT_FILE" <<'EOF'
# One multiaddr per line. Comments (#) and blank lines allowed.
# FORMAT: /ip4/<IP>/tcp/30333/p2p/<PeerId>
/ip4/46.202.178.141/tcp/30333/p2p/12D3KooWAvmfEhsNCSgeMZEMAJGF3LPT5B64fpCYpRy2ch243pG2
/ip4/145.14.157.152/tcp/30333/p2p/12D3KooWC6F9XVH3YPGWkEbMdJp97bdMS4jT1LCPn24yFd6FWnhE
/ip4/108.181.3.21/tcp/30333/p2p/12D3KooWNi3e5Qs2frbfMxmHPBSHiouZgBjLzKgYejW82SUR8s59
/ip4/46.202.132.238/tcp/30333/p2p/12D3KooWEdDRbhGxbbfBtcZLg3Nm6aR1o86EBgpHwEvYFh3ndjxb
/ip4/5.78.122.38/tcp/30333/p2p/12D3KooWMraofyeuaTdLNJDCpNHDUyv5f2yDDt2eY3T28PVxnmHC
/ip4/84.32.25.204/tcp/30333/p2p/12D3KooWFebYXE8aV7eqfdo9ttTpkzSocd2za9a9omqw9mgJgznR
/ip4/92.112.181.7/tcp/30333/p2p/12D3KooWC44HXrfrvJTojAS55xEPToyjatLHbhKaj1JLgCdZVEGz
EOF
chmod 0644 "$DEST_BOOT_FILE"
say_ok "Bootnodes file written to $DEST_BOOT_FILE"

# Ensure config references it (wrappers will read it when BASED_BOOT is empty)
if ! grep -q "^BOOTNODES_FILE=" "$CONF"; then
  echo "BOOTNODES_FILE=\"$DEST_BOOT_FILE\"" >> "$CONF"
fi

###############################################################################
# STEP 7 — Commands (wrappers) + Aliases  — unified naming (`based-*`)
###############################################################################
echo ""
print_h2 "STEP 7 - Creating commands and aliases"

BACKUP_FILE="$HOME/.bashrc.bak.$(date +%Y%m%d%H%M%S)"
# Ensure .bashrc exists before backing up
[ -f "$HOME/.bashrc" ] || touch "$HOME/.bashrc"
cp "$HOME/.bashrc" "$BACKUP_FILE"
say_info "Backup of ~/.bashrc saved to $BACKUP_FILE"

# Common env (defaults; can be overridden by ~/.config/basednode-run.env)
BASED_SPEC="${HOME}/basednode/mainnet1_raw.json"
BASED_BOOT=""   # no hard-coded defaults here
BASED_LOG="${HOME}/basednode/basednode.log"
mkdir -p "$WORKDIR" "${HOME}/.config"

# Ensure target dir exists
sudo install -d -m 0755 /usr/local/bin

# --- Wrappers in /usr/local/bin (NEW NAMES) ---
sudo tee /usr/local/bin/based-run >/dev/null <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
set -o pipefail

# Load optional user config
CONF="${HOME}/.config/basednode-run.env"
[[ -f "$CONF" ]] && source "$CONF"

# Defaults if not provided in env/config
: "${BASED_SPEC:=${HOME}/basednode/mainnet1_raw.json}"
: "${BASED_BOOT:=}"   # no hard-coded default
: "${BASED_LOG:=${HOME}/basednode/basednode.log}"
: "${BOOTNODES_FILE:=${HOME}/.config/basednode-bootnodes.list}"

mkdir -p "$(dirname "$BASED_LOG")"

# If BASED_BOOT is empty, try loading from file (one addr per line)
if [ -z "${BASED_BOOT:-}" ] && [ -s "$BOOTNODES_FILE" ]; then
  BASED_BOOT="$(grep -E '^[[:space:]]*/' "$BOOTNODES_FILE" | tr '\n' ' ' | xargs || true)"
fi

# Support multiple bootnodes (comma- or whitespace-separated) + validation
IFS=',' read -r -a _BN_ARR <<< "${BASED_BOOT// /,}"
BOOT_ARGS=()
VALID_RE='^/(ip4|dns4)/[^/]+/tcp/[0-9]+(/ws)?/p2p/[1-9A-HJ-NP-Za-km-z]{46,}$'
for bn in "${_BN_ARR[@]}"; do
  bn="$(echo "$bn" | tr -d ' \t\n\r')"
  [[ -z "$bn" ]] && continue
  if [[ "$bn" =~ $VALID_RE ]]; then
    BOOT_ARGS+=( --bootnodes "$bn" )
  else
    echo "WARN Invalid bootnode skipped: $bn" >&2
  fi
done

basednode \
  --name "${BASEDNODE_NAME:-MyBasedNode}" \
  --chain "$BASED_SPEC" \
  --rpc-methods safe \
  --rpc-cors=none \
  "${BOOT_ARGS[@]}" \
  --log info "$@" 2>&1 \
| tee -a "$BASED_LOG" \
| grep -Ev "Successfully ran block step.|Not the block to update emission values." || true
WRAP
sudo chmod +x /usr/local/bin/based-run

sudo tee /usr/local/bin/based-run-bg >/dev/null <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
set -o pipefail

CONF="${HOME}/.config/basednode-run.env"
[[ -f "$CONF" ]] && source "$CONF"

: "${BASED_SPEC:=${HOME}/basednode/mainnet1_raw.json}"
: "${BASED_BOOT:=}"
: "${BASED_LOG:=${HOME}/basednode/basednode.log}"
: "${BOOTNODES_FILE:=${HOME}/.config/basednode-bootnodes.list}"

mkdir -p "$(dirname "$BASED_LOG")"

# If BASED_BOOT is empty, try loading from file (one addr per line)
if [ -z "${BASED_BOOT:-}" ] && [ -s "$BOOTNODES_FILE" ]; then
  BASED_BOOT="$(grep -E '^[[:space:]]*/' "$BOOTNODES_FILE" | tr '\n' ' ' | xargs || true)"
fi

IFS=',' read -r -a _BN_ARR <<< "${BASED_BOOT// /,}"
BOOT_ARGS=()
VALID_RE='^/(ip4|dns4)/[^/]+/tcp/[0-9]+(/ws)?/p2p/[1-9A-HJ-NP-Za-km-z]{46,}$'
for bn in "${_BN_ARR[@]}"; do
  bn="$(echo "$bn" | tr -d ' \t\n\r')"
  [[ -z "$bn" ]] && continue
  if [[ "$bn" =~ $VALID_RE ]]; then
    BOOT_ARGS+=( --bootnodes "$bn" )
  else
    echo "WARN Invalid bootnode skipped: $bn" >&2
  fi
done

nohup basednode \
  --name "${BASEDNODE_NAME:-MyBasedNode}" \
  --chain "$BASED_SPEC" \
  --rpc-methods safe \
  --rpc-cors=none \
  "${BOOT_ARGS[@]}" \
  --log info "$@" >> "$BASED_LOG" 2>&1 &

echo $! > "${HOME}/basednode/basednode.pid"
echo "Started in background (PID $(cat "${HOME}/basednode/basednode.pid"))"
WRAP
sudo chmod +x /usr/local/bin/based-run-bg

sudo tee /usr/local/bin/based-logs >/dev/null <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
: "${BASED_LOG:=${HOME}/basednode/basednode.log}"
mkdir -p "$(dirname "$BASED_LOG")"
exec tail -n 500 -f "$BASED_LOG"
WRAP
sudo chmod +x /usr/local/bin/based-logs

sudo tee /usr/local/bin/based-stop >/dev/null <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
if pgrep -x basednode >/dev/null; then
  pkill -x basednode && echo "Node stopped."
else
  echo "No node running."
fi
WRAP
sudo chmod +x /usr/local/bin/based-stop

sudo tee /usr/local/bin/based-restart >/dev/null <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
based-stop || true
sleep 1
exec based-run "$@"
WRAP
sudo chmod +x /usr/local/bin/based-restart

# --- Back-compat symlinks (old names -> new names) ---
sudo ln -sf /usr/local/bin/based-run       /usr/local/bin/basednode-run
sudo ln -sf /usr/local/bin/based-run-bg    /usr/local/bin/basednode-run-bg
sudo ln -sf /usr/local/bin/based-logs      /usr/local/bin/node-logs
sudo ln -sf /usr/local/bin/based-stop      /usr/local/bin/stop-node
sudo ln -sf /usr/local/bin/based-restart   /usr/local/bin/restart-node

# Uninstaller (removes both new and old names)
sudo tee /usr/local/bin/based-uninstall-wrappers >/dev/null <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
for f in based-run based-run-bg based-logs based-stop based-restart \
         basednode-run basednode-run-bg node-logs stop-node restart-node; do
  sudo rm -f "/usr/local/bin/$f"
done
echo "Wrappers removed."
WRAP
sudo chmod +x /usr/local/bin/based-uninstall-wrappers

# --- Aliases (RPC info) — unified prefix `based-*` ---
# Safe cleanup: only delete old block if BOTH markers exist
START_RE='^# === BasedNode aliases ===$'
END_RE='^# ========================$'
if grep -q "$START_RE" "$HOME/.bashrc"; then
  if grep -q "$END_RE" "$HOME/.bashrc"; then
    sed -i "/$START_RE/,/$END_RE/d" "$HOME/.bashrc"
  else
    say_warn "Alias block start marker found but END marker missing -> skipping cleanup to avoid truncating ~/.bashrc. Remove old block manually if needed."
  fi
fi

# Append fresh block (includes start/end markers)
cat <<'EOF' >> "$HOME/.bashrc"

# === BasedNode aliases ===
export BASED_SPEC="$HOME/basednode/mainnet1_raw.json"
# export BASED_BOOT="/ip4/AAA.BBB.CCC.DDD/tcp/30333/p2p/12D3Koo..."  # <-- set real bootnodes here (comma-separated)
export BASED_LOG="$HOME/basednode/basednode.log"

alias based-status='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"system_health","params":[]}'\'' | jq'
alias based-peers='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"system_peers","params":[]}'\'' | jq'
alias based-sync='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"system_syncState","params":[]}'\'' | jq'
alias based-version='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"system_version","params":[]}'\'' | jq'
alias based-pending='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"author_pendingExtrinsics","params":[]}'\'' | jq'
alias based-peerid='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"system_localPeerId","params":[]}'\'' | jq -r .result'
alias based-help='cat ~/basednode/BASENODE_COMMANDS.txt'
# ========================
EOF

# Help file
tee "$WORKDIR/BASENODE_COMMANDS.txt" >/dev/null <<'TXT'
BasedNode quick commands

Run / Control:
  based-run            # foreground
  based-run-bg         # background
  based-logs           # tail -f last logs
  based-stop           # stop node
  based-restart        # stop then start (foreground)

Status & info (RPC):
  based-status         # health
  based-peers          # peers
  based-sync           # sync progress
  based-version        # node version
  based-pending        # pending tx
  based-peerid         # your libp2p peer ID

Tip:
  You can also put overrides in ~/.config/basednode-run.env

Examples:
  BASED_BOOT="/ip4/1.2.3.4/tcp/30333/p2p/<PeerId>,/dns4/node.example.com/tcp/30333/p2p/<PeerId>" based-run
  based-run --log libp2p=trace
TXT

say_ok "Wrappers installed."
say_info "Wrappers (usable now): based-run, based-run-bg, based-logs, based-stop, based-restart"
say_info "Aliases (after restarting terminal or 'source ~/.bashrc'): based-status, based-peers, based-sync, based-version, based-pending, based-peerid, based-help"
echo ""
say_info "Back-compat: old names still work (basednode-run, basednode-run-bg, node-logs, stop-node, restart-node)"

###############################################################################
# STEP 8 — Final foreground run
###############################################################################
print_h2 "STEP 8 - Running BasedNode in foreground"

say_ok "BasedNode installation completed!"
say_info "Your node will sync after discovering peers."
say_warn "Do NOT open RPC to the Internet unless you know what you are doing."
say_info "To stop BasedNode, press CTRL+C anytime."
say_info "Next time, use 'based-run' (foreground) or 'based-run-bg' (background)."

# Load optional user config to mirror wrappers behavior
CONF="${HOME}/.config/basednode-run.env"
[[ -f "$CONF" ]] && source "$CONF"

# Defaults if not provided in env/config
: "${BASED_SPEC:=${HOME}/basednode/mainnet1_raw.json}"
: "${BASED_BOOT:=}"
: "${BASED_LOG:=${WORKDIR}/basednode.log}"
: "${BOOTNODES_FILE:=${HOME}/.config/basednode-bootnodes.list}"

mkdir -p "$(dirname "$BASED_LOG")"

# If BASED_BOOT is empty, try loading from file (one addr per line)
if [ -z "${BASED_BOOT:-}" ] && [ -s "$BOOTNODES_FILE" ]; then
  BASED_BOOT="$(grep -E '^[[:space:]]*/' "$BOOTNODES_FILE" | tr '\n' ' ' | xargs || true)"
fi

# Bootnodes parsing (no validation here; the wrapper already validates before final exec)
IFS=',' read -r -a _BN_ARR <<< "${BASED_BOOT// /,}"
BOOT_ARGS=()
for bn in "${_BN_ARR[@]}"; do
  [[ -n "$bn" ]] && BOOT_ARGS+=( --bootnodes "$bn" )
done

# Hint if empty
if [ -z "${BASED_BOOT:-}" ]; then
  say_warn "No bootnodes configured. Discovery may stall at 0 peers."
fi

# Kill existing process if any (exact match on the binary name)
if pgrep -x basednode >/dev/null; then
  say_warn "An existing BasedNode process is running. Stopping it before starting a new one..."
  pkill -x basednode || true
  sleep 1
fi

## Quick health check (robust)
say_info "Starting BasedNode in background for quick health check..."
basednode \
  --name "${BASEDNODE_NAME:-MyBasedNode}" \
  --chain "$BASED_SPEC" \
  --rpc-methods safe \
  --rpc-cors=none \
  "${BOOT_ARGS[@]}" \
  --log warn "$@" >> "$BASED_LOG" 2>&1 &
NODE_PID=$!

cleanup_quicktest() { kill "$NODE_PID" >/dev/null 2>&1 || true; }
trap cleanup_quicktest EXIT

RPC_URL="http://127.0.0.1:9933"

# Wait for RPC to come up (up to ~60s)
READY=false
for i in {1..12}; do
  if curl --max-time 3 -s -H "Content-Type: application/json" \
       -d '{"id":1,"jsonrpc":"2.0","method":"system_health","params":[]}' \
       "$RPC_URL" | jq . >/dev/null 2>&1; then
    READY=true; break
  fi
  sleep 5
done

say_info "Performing quick RPC checks..."
if ! $READY; then
  say_warn "RPC not ready yet. Check logs with 'based-logs' (peers may be 0 or bootnodes invalid)."
else
  if command -v curl >/dev/null && command -v jq >/dev/null; then
    HEALTH_JSON=$(curl --max-time 3 -s -H "Content-Type: application/json" \
      -d '{"id":1,"jsonrpc":"2.0","method":"system_health","params":[]}' "$RPC_URL")
    if [ -n "$HEALTH_JSON" ]; then
      say_ok "Node health:"; echo "$HEALTH_JSON" | jq
    else
      say_warn "No response for system_health."
    fi

    say_ok "Peer list:"
    PEERS_RPC=$(curl --max-time 3 -s -H "Content-Type: application/json" \
      -d '{"id":1,"jsonrpc":"2.0","method":"system_peers","params":[]}' "$RPC_URL")
    if [ -n "$PEERS_RPC" ]; then
      echo "$PEERS_RPC" | jq
      PEER_COUNT=$(echo "$PEERS_RPC" | jq -r '.result | length' 2>/dev/null || echo 0)
    else
      say_warn "No response for system_peers."
      PEER_COUNT=0
    fi

    say_ok "Sync state:"
    SYNC_RPC=$(curl --max-time 3 -s -H "Content-Type: application/json" \
      -d '{"id":1,"jsonrpc":"2.0","method":"system_syncState","params":[]}' "$RPC_URL")
    if [ -n "$SYNC_RPC" ]; then
      echo "$SYNC_RPC" | jq
    else
      say_warn "No response for system_syncState."
    fi

    if [ "${PEER_COUNT:-0}" -eq 0 ]; then
      say_info "0 peers so far. If this persists, provide valid live bootnodes:"
      echo "    - Edit: $HOME/.config/basednode-run.env (set BASED_BOOT=...)"
      echo "    - Or update: $BOOTNODES_FILE (one /ip4.../tcp/30333/p2p/<PeerId> per line)"
      echo "    - Or run: BASED_BOOT=\"<addr1>,<addr2>\" based-run --log libp2p=trace"
    fi
  else
    say_warn "curl/jq not available for quick test output."
  fi
fi

kill "$NODE_PID" >/dev/null 2>&1 || true
sleep 1
trap - EXIT
say_ok "Quick test completed. Your node responds to RPC."

say_info "We will now start your node in the foreground."
say_info "💡 Remember this command for later: based-run"
say_info "Other useful commands:"
echo "   • based-run-bg    → run in background"
echo "   • based-logs      → follow logs"
echo "   • based-stop      → stop node"
echo "   • based-restart   • restart in foreground"
say_warn "Keep RPC closed to the Internet unless you fully understand the risks."
echo ""
exec based-run

###############################################################################
# --- END OF STEP 8 ---
# Will only run if 'exec based-run' fails.
###############################################################################
say_err "Failed to exec based-run. Try launching it manually:"
echo "  based-run"
exit 1
