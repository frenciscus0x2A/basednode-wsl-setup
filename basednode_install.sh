#!/usr/bin/env bash
set -euo pipefail
# Abort on error (-e), undefined variables (-u), and fail pipelines (pipefail).

VERSION="0.1.3"

###############################################################################
# Pretty printing helpers (robust ASCII-only)
###############################################################################
# Force ASCII for maximum compatibility across all consoles.
# No Unicode symbols to avoid mojibake on non-UTF-8 terminals.
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
SPEC_URL="https://raw.githubusercontent.com/getbasedai/basednode/main/mainnet1_raw.json"
WORKDIR="$HOME/basednode"
BUILD_LOG="$HOME/basednode_build.log"
SPEC_PATH="$WORKDIR/mainnet1_raw.json"

echo ""
print_h1 "BasedNode install script"

###############################################################################
# STEP 1 — Prerequisites (sudo + environment checks)
###############################################################################
echo ""
print_h2 "STEP 1 $DASH Prerequisites (sudo + environment checks)"

# Sudo check
if ! sudo -v; then
  say_err "Wrong password or sudo failed multiple times. Exiting."
  exit 1
fi
say_ok "Sudo access confirmed."

# WSL/Ubuntu checks
if ! grep -qi microsoft /proc/version; then
  say_err "This installer is intended for Windows Subsystem for Linux (WSL). Aborting."
  exit 1
fi
. /etc/os-release || true
if [ "${VERSION_ID:-}" != "22.04" ]; then
  say_warn "Ubuntu ${VERSION_ID:-unknown} detected. This guide is tested on 22.04 LTS. Continuing anyway."
fi
say_ok "WSL/Ubuntu checks passed."

###############################################################################
# STEP 2 — Base packages
###############################################################################
echo ""
print_h2 "STEP 2 $DASH Updating system and installing base tools..."
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
print_h2 "STEP 3 $DASH Checking Rust toolchain (nightly required)..."
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
  say_err "Rust installed, but 'cargo' not found. Close and reopen your terminal, then rerun this script."
  exit 1
fi
say_ok "Rust nightly ($NIGHTLY_VERSION) installed and ready."

###############################################################################
# STEP 4 — Clone & build
###############################################################################
echo ""
print_h2 "STEP 4 $DASH Cloning and building BasedNode..."
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
# STEP 5 — Chain spec
###############################################################################
echo ""
print_h2 "STEP 5 $DASH Ensuring chain spec (mainnet1_raw.json)"
if [ ! -f "$SPEC_PATH" ]; then
  say_info "mainnet1_raw.json not found locally. Downloading from official repo..."
  mkdir -p "$WORKDIR"
  if ! curl -fL -o "$SPEC_PATH" "$SPEC_URL"; then
    say_err "Unable to download chain spec. Check your network or try again later."
    exit 1
  fi
  # Optional: verify a known SHA256 here if you want to pin the artifact.
fi
say_ok "Chain spec ready at: $SPEC_PATH"

###############################################################################
# STEP 6 — Aliases + wrapper commands (work immediately, safer & flexible)
###############################################################################
echo ""
print_h2 "STEP 6 $DASH Creating commands and aliases"

BACKUP_FILE="$HOME/.bashrc.bak.$(date +%Y%m%d%H%M%S)"
cp "$HOME/.bashrc" "$BACKUP_FILE"
say_info "Backup of ~/.bashrc saved to $BACKUP_FILE"

# Common env (defaults; can be overridden by ~/.config/basednode-run.env)
BASED_SPEC="${HOME}/basednode/mainnet1_raw.json"
BASED_BOOT="/dns/mainnet.basedaibridge.com/tcp/30333/p2p/12D3KooWCQy4hiiA9tHxvQ2PPaSY3mUM6NkMnbsYf2v4FKbLAtUh"
BASED_LOG="${HOME}/basednode/basednode.log"
mkdir -p "$WORKDIR" "${HOME}/.config"

# --- Write wrappers in /usr/local/bin (no need to 'source ~/.bashrc') ---
sudo tee /usr/local/bin/basednode-run >/dev/null <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
set -o pipefail

# Load optional user config
CONF="${HOME}/.config/basednode-run.env"
[[ -f "$CONF" ]] && source "$CONF"

# Defaults if not provided in env/config
: "${BASED_SPEC:=${HOME}/basednode/mainnet1_raw.json}"
: "${BASED_BOOT:=/dns/mainnet.basedaibridge.com/tcp/30333/p2p/12D3KooWCQy4hiiA9tHxvQ2PPaSY3mUM6NkMnbsYf2v4FKbLAtUh}"
: "${BASED_LOG:=${HOME}/basednode/basednode.log}"

mkdir -p "$(dirname "$BASED_LOG")"

# Support multiple bootnodes (comma- or whitespace-separated)
IFS=',' read -r -a _BN_ARR <<< "${BASED_BOOT// /,}"
BOOT_ARGS=()
for bn in "${_BN_ARR[@]}"; do
  [[ -n "$bn" ]] && BOOT_ARGS+=( --bootnodes "$bn" )
done

# Bind RPC explicitly to loopback for safety; expose Prometheus only locally.
exec basednode \
  --name "${BASEDNODE_NAME:-MyBasedNode}" \
  --chain "$BASED_SPEC" \
  --rpc-listen-addr 127.0.0.1:9933 \
  --rpc-methods Safe \
  --rpc-cors=none \
  "${BOOT_ARGS[@]}" \
  --log info \
  "$@" 2>&1 \
| tee -a "$BASED_LOG" \
| grep -Ev "Successfully ran block step.|Not the block to update emission values."
WRAP
sudo chmod +x /usr/local/bin/basednode-run

sudo tee /usr/local/bin/basednode-run-bg >/dev/null <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
set -o pipefail

CONF="${HOME}/.config/basednode-run.env"
[[ -f "$CONF" ]] && source "$CONF"

: "${BASED_SPEC:=${HOME}/basednode/mainnet1_raw.json}"
: "${BASED_BOOT:=/dns/mainnet.basedaibridge.com/tcp/30333/p2p/12D3KooWCQy4hiiA9tHxvQ2PPaSY3mUM6NkMnbsYf2v4FKbLAtUh}"
: "${BASED_LOG:=${HOME}/basednode/basednode.log}"

mkdir -p "$(dirname "$BASED_LOG")"

IFS=',' read -r -a _BN_ARR <<< "${BASED_BOOT// /,}"
BOOT_ARGS=()
for bn in "${_BN_ARR[@]}"; do
  [[ -n "$bn" ]] && BOOT_ARGS+=( --bootnodes "$bn" )
done

nohup basednode \
  --name "${BASEDNODE_NAME:-MyBasedNode}" \
  --chain "$BASED_SPEC" \
  --rpc-listen-addr 127.0.0.1:9933 \
  --rpc-methods Safe \
  --rpc-cors=none \
  "${BOOT_ARGS[@]}" \
  --log info \
  "$@" >> "$BASED_LOG" 2>&1 &

echo $! > "${HOME}/basednode/basednode.pid"
echo "Started in background (PID $(cat "${HOME}/basednode/basednode.pid"))"
WRAP
sudo chmod +x /usr/local/bin/basednode-run-bg

sudo tee /usr/local/bin/node-logs >/dev/null <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
: "${BASED_LOG:=${HOME}/basednode/basednode.log}"
mkdir -p "$(dirname "$BASED_LOG")"
exec tail -n 500 -f "$BASED_LOG"
WRAP
sudo chmod +x /usr/local/bin/node-logs

sudo tee /usr/local/bin/stop-node >/dev/null <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
if pgrep -f "[b]asednode" >/dev/null; then
  pkill -f basednode && echo "Node stopped."
else
  echo "No node running."
fi
WRAP
sudo chmod +x /usr/local/bin/stop-node

sudo tee /usr/local/bin/restart-node >/dev/null <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
stop-node || true
sleep 1
exec basednode-run "$@"
WRAP
sudo chmod +x /usr/local/bin/restart-node

# Optional: uninstall helper
sudo tee /usr/local/bin/basednode-uninstall-wrappers >/dev/null <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
for f in basednode-run basednode-run-bg node-logs stop-node restart-node; do
  sudo rm -f "/usr/local/bin/$f"
done
echo "Wrappers removed."
WRAP
sudo chmod +x /usr/local/bin/basednode-uninstall-wrappers

# --- Aliases (bonus; handy in interactive shells) ---
sed -i '/# === BasedNode aliases ===/,/# ========================/d' "$HOME/.bashrc"
cat <<'EOF' >> "$HOME/.bashrc"

# === BasedNode aliases ===
export BASED_SPEC="$HOME/basednode/mainnet1_raw.json"
export BASED_BOOT="/dns/mainnet.basedaibridge.com/tcp/30333/p2p/12D3KooWCQy4hiiA9tHxvQ2PPaSY3mUM6NkMnbsYf2v4FKbLAtUh"
export BASED_LOG="$HOME/basednode/basednode.log"

alias check-health='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"system_health","params":[]}'\'' | jq'
alias check-peers='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"system_peers","params":[]}'\'' | jq'
alias check-sync='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"system_syncState","params":[]}'\'' | jq'
alias check-version='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"system_version","params":[]}'\'' | jq'
alias check-pending='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"author_pendingExtrinsics","params":[]}'\'' | jq'
alias node-peerid='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"system_localPeerId","params":[]}'\'' | jq -r .result'
alias basednode-help='cat ~/basednode/BASENODE_COMMANDS.txt'
# ========================
EOF

say_ok "Wrappers installed. Commands ready: basednode-run, basednode-run-bg, node-logs, stop-node, restart-node (args passthrough supported)."

###############################################################################
# STEP 7 — Final foreground run
###############################################################################
print_h2 "STEP 7 $DASH Running BasedNode in foreground"

say_ok "BasedNode installation completed!"
say_info "Your node will sync and connect automatically."
say_warn "RPC lets other programs (or people) control your node. Do NOT open RPC to the Internet unless you know what you are doing."
say_info "To stop BasedNode, press CTRL+C anytime."
say_info "Next time, use 'basednode-run' (foreground) or 'basednode-run-bg' (background)."

BASED_LOG="$WORKDIR/basednode.log"

# Make the log-filtering pipeline robust under -e/pipefail:
# - grep -Ev returns 1 when it filters out all lines (not an error) and 2 on real errors.
# - We tolerate rc_grep 0/1 and fail only on 2, while still failing if the node or tee fail.
set +e
set +o pipefail

basednode \
  --name "${BASEDNODE_NAME:-MyBasedNode}" \
  --chain "$SPEC_PATH" \
  --rpc-methods Safe \
  --rpc-cors=none \
  --bootnodes /dns/mainnet.basedaibridge.com/tcp/30333/p2p/12D3KooWCQy4hiiA9tHxvQ2PPaSY3mUM6NkMnbsYf2v4FKbLAtUh \
  --log info 2>&1 \
| tee -a "$BASED_LOG" \
| grep -Ev "Successfully ran block step.|Not the block to update emission values."

rc_node=${PIPESTATUS[0]}
rc_tee=${PIPESTATUS[1]}
rc_grep=${PIPESTATUS[2]}

set -e
set -o pipefail

if [ "$rc_node" -ne 0 ] || [ "$rc_tee" -ne 0 ] || [ "$rc_grep" -eq 2 ]; then
  say_err "Log pipeline failed (node=$rc_node, tee=$rc_tee, grep=$rc_grep)"
  exit 1
fi

echo ""
print_h2 "The node has stopped (if you pressed CTRL+C)."

say_info "NEXT STEPS:"
echo "  • To launch BasedNode again:  basednode-run"
echo "  • To run in background:       basednode-run-bg"
echo "  • To view logs:               node-logs"

print_sep
echo ""
print_sep
