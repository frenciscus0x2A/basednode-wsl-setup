#!/usr/bin/env bash
set -euo pipefail
# Abort on error (-e), undefined variables (-u), and fail pipelines (pipefail).

VERSION="0.1.2"

trap 'echo ""; echo "⚠️ Script interrupted. Exiting safely."; exit 1' INT
# Gracefully handle Ctrl+C interrupts.

###############################################################################
# Pretty printing helpers (adaptive separators)
###############################################################################
# Use a Unicode line if UTF-8 appears available; otherwise plain ASCII.
if [[ "${LANG:-}" =~ (UTF|utf)-?8 ]]; then
  SEP_CHAR='━'
else
  SEP_CHAR='-'
fi

print_sep() {
  # Draw a full-width separator; default to 60 columns if unknown.
  local cols="${COLUMNS:-60}"
  printf '%*s\n' "$cols" '' | tr ' ' "$SEP_CHAR"
}

print_h1() {
  print_sep
  printf " %s — version %s\n" "$1" "$VERSION"
  print_sep
}

print_h2() {
  print_sep
  printf " %s\n" "$1"
  print_sep
}

echo ""
print_h1 "BasedNode install script"

echo ""
print_h2 "STEP 1 — Checking sudo access…"

if ! sudo -v; then
  echo "❌ Wrong password or sudo failed multiple times. Exiting."
  exit 1
fi
# Ensure sudo privileges are available before continuing.
echo "✅ Sudo access confirmed."


echo ""
print_h2 "STEP 1.5 — Environment checks (WSL & Ubuntu)"

if ! grep -qi microsoft /proc/version; then
  echo "❌ This installer is intended for Windows Subsystem for Linux (WSL). Aborting."
  exit 1
fi
# Detect WSL by checking /proc/version for "microsoft" (case-insensitive).

. /etc/os-release || true
if [ "${VERSION_ID:-}" != "22.04" ]; then
  echo "⚠️ Ubuntu ${VERSION_ID:-unknown} detected. This guide is tested on 22.04. Continuing anyway."
fi
# Warn if not running on the tested Ubuntu release (22.04 LTS).
echo "✅ WSL/Ubuntu checks passed."


echo ""
print_h2 "STEP 2 — Updating system and installing base tools…"

DEPS=(software-properties-common curl git clang build-essential libssl-dev pkg-config libclang-dev protobuf-compiler jq)
MISSING=()
for pkg in "${DEPS[@]}"; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    MISSING+=("$pkg")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "Missing packages detected: ${MISSING[*]}"
  sudo apt update
  sudo apt install -y "${MISSING[@]}"
else
  echo "All dependencies already installed, skipping apt install."
fi

echo "✅ System updated and packages installed."


echo ""
print_h2 "STEP 3 — Checking Rust toolchain (nightly required)…"

PINNED_NIGHTLY="nightly-2025-01-07"
# Pin Rust nightly to avoid breakage from upstream changes in toolchain.

if ! command -v rustup >/dev/null 2>&1; then
  echo "Rustup not found. Installing rustup and Rust nightly…"
  rm -f rustup-init.sh rustup-install.log

  curl -sSf -o rustup-init.sh https://sh.rustup.rs
  chmod +x rustup-init.sh

  MAX_ATTEMPTS=5
  LOG_FILE="rustup-install.log"
  SUCCESS=false

  for attempt in $(seq 1 $MAX_ATTEMPTS); do
    DELAY=$((attempt * 10))
    echo "🔧 Installing Rust (attempt $attempt/$MAX_ATTEMPTS)…"
    if ./rustup-init.sh -y --default-toolchain "$PINNED_NIGHTLY" --no-modify-path >"$LOG_FILE" 2>&1; then
      SUCCESS=true
      break
    else
      echo "❌ Attempt $attempt failed. Retrying in $DELAY seconds…"
      sleep $DELAY
    fi
  done
  rm -f rustup-init.sh
  if ! $SUCCESS; then
    echo ""
    echo "🚨 Rust install failed after $MAX_PULL_ATTEMPTS attempts."
    echo "See 'rustup-install.log' for error details."
    exit 1
  fi

  # PATH
  if ! grep -q 'source $HOME/.cargo/env' ~/.bashrc; then
    echo 'source $HOME/.cargo/env' >> ~/.bashrc
  fi
  # shellcheck disable=SC1090
  source "$HOME/.cargo/env"
else
  echo "Rustup already installed. Skipping rustup installation."
  if ! rustup toolchain list | grep -q "$PINNED_NIGHTLY"; then
    echo "Installing pinned nightly toolchain: $PINNED_NIGHTLY"
    rustup toolchain install "$PINNED_NIGHTLY"
  fi
  if ! grep -q 'source $HOME/.cargo/env' ~/.bashrc; then
    echo 'source $HOME/.cargo/env' >> ~/.bashrc
  fi
  # shellcheck disable=SC1090
  source "$HOME/.cargo/env"
fi

# Use pinned nightly moving forward.
NIGHTLY_VERSION="$PINNED_NIGHTLY"

# Ensure WASM target (required for Substrate runtimes).
echo "Ensuring WASM target is installed for: $NIGHTLY_VERSION…"
if ! rustup target list --toolchain "$NIGHTLY_VERSION" | grep -q 'wasm32-unknown-unknown (installed)'; then
  rustup target add wasm32-unknown-unknown --toolchain "$NIGHTLY_VERSION"
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "❌ Rust installed, but 'cargo' not found."
  echo "Close and reopen your terminal, then rerun this script."
  exit 1
fi

echo "✅ Rust nightly ($NIGHTLY_VERSION) installed and ready."


echo ""
print_h2 "STEP 4 — Cloning and building BasedNode…"

cd ~

if [ -d "basednode" ]; then
  echo "Folder 'basednode' exists. Updating repo…"
  cd basednode
  MAX_PULL_ATTEMPTS=3
  PULL_SUCCESS=false
  for attempt in $(seq 1 $MAX_PULL_ATTEMPTS); do
    if git pull; then
      PULL_SUCCESS=true
      break
    else
      echo "❌ git pull failed (attempt $attempt). Retrying in 10s…"
      sleep 10
    fi
  done
  if ! $PULL_SUCCESS; then
        echo "❌ Failed to update BasedNode repository after $MAX_PULL_ATTEMPTS attempts."
    exit 1
  fi
else
  MAX_CLONE_ATTEMPTS=3
  CLONE_SUCCESS=false
  for attempt in $(seq 1 $MAX_CLONE_ATTEMPTS); do
    if git clone --branch main https://github.com/BF1337/basednode.git; then
      CLONE_SUCCESS=true
      break
    else
      echo "❌ Git clone failed (attempt $attempt). Retrying in 10s…"
      sleep 10
    fi
  done
  if ! $CLONE_SUCCESS; then
    echo "❌ Failed to clone BasedNode repository after $MAX_CLONE_ATTEMPTS attempts."
    exit 1
  fi
  cd basednode
fi

echo "Building BasedNode… (this may take several minutes)"
BUILD_LOG="$HOME/basednode_build.log"
if cargo +"$NIGHTLY_VERSION" build --release -j "$(nproc)" | tee "$BUILD_LOG"; then
  echo "✅ Build finished."
else
  echo "❌ Build failed. Attempting 'cargo clean' and rebuild with -j 1…"
  cargo clean
  if ! cargo +"$NIGHTLY_VERSION" build --release -j 1 | tee -a "$BUILD_LOG"; then
    echo "❌ Build failed even after clean. See '$BUILD_LOG' for details."
    exit 1
  fi
  echo "✅ Build finished after clean (single job)."
fi
# Fallback to single-threaded build to reduce RAM usage (common OOM in WSL).

# Install the binary system-wide for consistent usage across aliases and manual runs.
sudo install -m 0755 ./target/release/basednode /usr/local/bin/basednode

if ! command -v basednode >/dev/null 2>&1; then
  echo "❌ BasedNode binary not found in PATH after installation."
  exit 1
fi

echo "✅ BasedNode binary installed globally."
mkdir -p ~/basednode


echo ""
print_h2 "STEP 4.5 — Ensuring chain spec (mainnet1_raw.json)"

SPEC_PATH="$HOME/basednode/mainnet1_raw.json"
if [ ! -f "$SPEC_PATH" ]; then
  echo "ℹ️ mainnet1_raw.json not found locally. Downloading from official repo…"
  mkdir -p "$HOME/basednode"
  if ! curl -fL -o "$SPEC_PATH" "https://raw.githubusercontent.com/getbasedai/basednode/main/mainnet1_raw.json"; then
    echo "❌ Unable to download chain spec. Check your network or try again later."
    exit 1
  fi
  # Optional: verify a known SHA256 here if you want to pin the artifact.
fi
echo "✅ Chain spec ready at: $SPEC_PATH"
# Ensure the chain specification is present; download from canonical repo if missing.


echo ""
print_h2 "STEP 5 — Creating aliases for running BasedNode"

BACKUP_FILE=~/.bashrc.bak.$(date +%Y%m%d%H%M%S)
cp ~/.bashrc "$BACKUP_FILE"
echo "→ Backup of ~/.bashrc saved to $BACKUP_FILE"

# Clean previous BasedNode alias block (idempotent re-run).
sed -i '/# === BasedNode aliases ===/,/# ========================/d' ~/.bashrc

# Updated alias block (add/remove here ONLY)
cat <<'EOF' >> ~/.bashrc

# === BasedNode aliases ===
# Centralize spec/bootnode/log to make updates trivial in one place.
BASED_SPEC="$HOME/basednode/mainnet1_raw.json"
BASED_BOOT="/dns/mainnet.basedaibridge.com/tcp/30333/p2p/12D3KooWCQy4hiiA9tHxvQ2PPaSY3mUM6NkMnbsYf2v4FKbLAtUh"
BASED_LOG="$HOME/basednode/basednode.log"

alias basednode-run='(basednode \
  --name "${BASEDNODE_NAME:-MyBasedNode}" \
  --chain "$BASED_SPEC" \
  --rpc-methods Safe \
  --bootnodes "$BASED_BOOT" \
  --log info 2>&1 | tee -a "$BASED_LOG" | grep -Ev "Successfully ran block step.|Not the block to update emission values.")'
# Foreground run with filtered logs and persistent log file.

alias basednode-run-bg='nohup basednode \
  --name "${BASEDNODE_NAME:-MyBasedNode}" \
  --chain "$BASED_SPEC" \
  --rpc-methods Safe \
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

# Generate the unique help file (source of truth for all aliases)
cat <<'DOC' > ~/basednode/BASENODE_COMMANDS.txt
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🦴 BasedNode — Useful commands (aliases)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
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
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DOC

# Reload aliases for this session (so they’re usable immediately).
# shellcheck disable=SC1090
source ~/.bashrc

echo "✅ Aliases added."


echo ""
print_h2 "INFO — How to use your new BasedNode aliases"
cat ~/basednode/BASENODE_COMMANDS.txt
echo ""


print_h2 "STEP 6 — Running BasedNode in foreground"

echo ""
echo "✅ BasedNode installation completed!"
echo ""
echo "ℹ️  Note:"
echo "• Your node will sync and connect automatically."
echo ""
echo "⚠️  SECURITY TIP:"
echo "• RPC lets other programs (or people) control your node."
echo "• Do NOT open RPC to the internet unless you know exactly what you’re doing."
echo ""
echo "• To stop BasedNode, press CTRL+C anytime."
echo ""
echo "• Next time, simply run 'basednode-run' to start your node."
echo "• Or use 'basednode-run-bg' to run it in background."
echo ""

BASED_LOG="$HOME/basednode/basednode.log"
basednode \
  --name "${BASEDNODE_NAME:-MyBasedNode}" \
  --chain "$SPEC_PATH" \
  --rpc-methods Safe \
  --bootnodes /dns/mainnet.basedaibridge.com/tcp/30333/p2p/12D3KooWCQy4hiiA9tHxvQ2PPaSY3mUM6NkMnbsYf2v4FKbLAtUh \
  --log info 2>&1 | tee -a "$BASED_LOG" | grep -Ev "Successfully ran block step.|Not the block to update emission values."
# Final foreground run uses the same parameters and log handling as aliases to maintain consistency.

echo ""
print_h2 "The node has stopped (if you pressed CTRL+C)."

echo ""
echo "✅ NEXT STEPS:"
echo "• To launch BasedNode again:"
echo "     basednode-run"
echo ""
echo "🎉 Installation finished. Your node is syncing!"
print_sep
echo ""
print_sep