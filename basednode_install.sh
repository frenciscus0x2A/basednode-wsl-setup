#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.2"

trap 'echo ""; echo "⚠️ Script interrupted. Exiting safely."; exit 1' INT

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " BasedNode install script — version $VERSION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

###############################################################################
# BasedNode WSL Installation Guide (Unofficial Fork)
#
# Installs:
#   - BasedNode from https://github.com/BF1337/basednode (Community Fork)
#
# 🛠️ Requirements: Rust NIGHTLY toolchain
#
# HOW TO USE (Ubuntu WSL terminal):
#
#   1. Download this script:
#        wget https://raw.githubusercontent.com/frenciscus0x2A/basednode-wsl-setup/main/basednode_install.sh -O basednode_install.sh
#
#   2. Make it executable:
#        chmod +x basednode_install.sh
#
#   3. Run it:
#        ./basednode_install.sh
#
# What this script does:
#   • Checks sudo access
#   • Updates your system and installs dependencies
#   • Installs Rust nightly (+ WASM)
#   • Clones/builds BasedNode
#   • Installs the binary globally
#   • Creates useful aliases in your shell
#   • Launches the node with filtered logs
#
# At the end: your node will be running and syncing!
#
# Author: frenciscus_0x2A
###############################################################################

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1 — Checking sudo access…"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if ! sudo -v; then
    echo "❌ Wrong password or sudo failed multiple times. Exiting."
    exit 1
fi

echo "✅ Sudo access confirmed."

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2 — Updating system and installing base tools…"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

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
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 3 — Checking Rust toolchain (nightly required)…"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

PINNED_NIGHTLY="nightly-2025-01-07"  # adapte la date si besoin

# 1. rustup present ?
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
        echo "🚨 Rust install failed after $MAX_ATTEMPTS attempts."
        echo "See 'rustup-install.log' for error details."
        exit 1
    fi

    # PATH
    if ! grep -q 'source $HOME/.cargo/env' ~/.bashrc; then
        echo 'source $HOME/.cargo/env' >> ~/.bashrc
    fi
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
    source "$HOME/.cargo/env"
fi

# Use pinned nightly moving forward
NIGHTLY_VERSION="$PINNED_NIGHTLY"

# Ensure wasm target
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
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 4 — Cloning and building BasedNode…"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

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
        echo "Check your network connection, or try again later."
        exit 1
    fi
else
    # Clone with retry if network is unreliable
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
        echo "Check your network connection, or try again later."
        exit 1
    fi
    cd basednode
fi

# Ensure Rust toolchain & WASM target
NIGHTLY_VERSION=$(rustup show active-toolchain 2>/dev/null | grep nightly | cut -d' ' -f1)
if [ -z "$NIGHTLY_VERSION" ]; then
    NIGHTLY_VERSION=$(rustup toolchain list | grep nightly | head -1 | cut -d' ' -f1)
    [ -z "$NIGHTLY_VERSION" ] && NIGHTLY_VERSION="nightly"
fi
echo "Ensuring WASM target is installed for Rust toolchain: $NIGHTLY_VERSION…"
if ! rustup target list --toolchain $NIGHTLY_VERSION | grep -q 'wasm32-unknown-unknown (installed)'; then
    rustup target add wasm32-unknown-unknown --toolchain $NIGHTLY_VERSION
fi

echo "Building BasedNode… (this may take several minutes)"

BUILD_SUCCESS=false

# Try a fast build first; clean & rebuild if it fails
if cargo +$NIGHTLY_VERSION build --release | tee ~/basednode_build.log; then
    echo "✅ Build finished."
    BUILD_SUCCESS=true
else
    echo "❌ Build failed. Attempting 'cargo clean' and rebuild…"
    cargo clean
    if cargo +$NIGHTLY_VERSION build --release | tee -a ~/basednode_build.log; then
        echo "✅ Build finished after cleaning."
        BUILD_SUCCESS=true
    fi
fi

if ! $BUILD_SUCCESS; then
    echo "❌ Build failed even after 'cargo clean'."
    echo "Check '~/basednode_build.log' for details."
    echo "Try: cargo +$NIGHTLY_VERSION build --release"
    exit 1
fi

sudo cp ./target/release/basednode /usr/local/bin/

if ! command -v basednode >/dev/null 2>&1; then
    echo "❌ BasedNode binary not found in PATH after installation."
    exit 1
fi

echo "✅ BasedNode binary installed globally."
mkdir -p ~/basednode


echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 4.5 — Ensuring chain spec (mainnet1_raw.json)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

SPEC_PATH="$HOME/basednode/mainnet1_raw.json"
if [ ! -f "$SPEC_PATH" ]; then
  echo "ℹ️ mainnet1_raw.json not found locally. Downloading from official repo…"
  mkdir -p "$HOME/basednode"
  if ! curl -fL -o "$SPEC_PATH" "https://raw.githubusercontent.com/getbasedai/basednode/main/mainnet1_raw.json"; then
    echo "❌ Unable to download chain spec. Check your network or try again later."
    exit 1
  fi
  # Optionnel: vérifier un SHA256 connu ici (si tu veux pinner)
fi
echo "✅ Chain spec ready at: $SPEC_PATH"


echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 5 — Creating aliases for running BasedNode"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

BACKUP_FILE=~/.bashrc.bak.$(date +%Y%m%d%H%M%S)
cp ~/.bashrc "$BACKUP_FILE"
echo "→ Backup of ~/.bashrc saved to $BACKUP_FILE"

# Clean previous BasedNode alias block
sed -i '/# === BasedNode aliases ===/,/# ========================/d' ~/.bashrc

# Updated alias block (add/remove here ONLY)
cat <<'EOF' >> ~/.bashrc

# === BasedNode aliases ===
BASED_SPEC="$HOME/basednode/mainnet1_raw.json"
BASED_BOOT="/dns/mainnet.basedaibridge.com/tcp/30333/p2p/12D3KooWCQy4hiiA9tHxvQ2PPaSY3mUM6NkMnbsYf2v4FKbLAtUh"
BASED_LOG="$HOME/basednode/basednode.log"

alias basednode-run='(basednode \
  --name "${BASEDNODE_NAME:-MyBasedNode}" \
  --chain "$BASED_SPEC" \
  --rpc-methods Safe \
  --bootnodes "$BASED_BOOT" \
  --log info 2>&1 | tee -a "$BASED_LOG" | grep -Ev "Successfully ran block step.|Not the block to update emission values.")'

alias basednode-run-bg='nohup basednode \
  --name "${BASEDNODE_NAME:-MyBasedNode}" \
  --chain "$BASED_SPEC" \
  --rpc-methods Safe \
  --bootnodes "$BASED_BOOT" \
  --log info >> "$BASED_LOG" 2>&1 & echo $! > "$HOME/basednode/basednode.pid" && echo "Started in background (PID $(cat $HOME/basednode/basednode.pid))"'

alias stop-node='if pgrep -f "basednode"; then pkill -f basednode && echo "Node stopped."; else echo "No node running."; fi'
alias restart-node='stop-node; sleep 1; basednode-run'
alias node-logs='tail -n 500 -f "$BASED_LOG"'
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

# Reload aliases for this session (needed if you want to use them directly in this shell)
source ~/.bashrc

echo "✅ Aliases added."


echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "INFO — How to use your new BasedNode aliases"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat ~/basednode/BASENODE_COMMANDS.txt
echo ""


echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 6 — Running BasedNode in foreground"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

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

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "The node has stopped (if you pressed CTRL+C)."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "✅ NEXT STEPS:"
echo "• To launch BasedNode again:"
echo "     basednode-run"
echo ""
echo "🎉 Installation finished. Your node is syncing!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"


echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━