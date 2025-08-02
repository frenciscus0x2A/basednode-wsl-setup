#!/usr/bin/env bash
set -euo pipefail

v0.1.2: clarify comments, optimize build & git retry, robust alias step, improved onboarding

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
echo "STEP 3 — Installing Rust toolchain (nightly required)…"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Checking connection to Rust download servers…"
if ! curl -sf --max-time 10 https://static.rust-lang.org/dist/channel-rust-nightly.toml > /dev/null; then
  echo "⚠️ Can't quickly reach static.rust-lang.org"
  echo "Network is slow or blocked (firewall, captive portal, etc)."
  echo "Rust install may take a long time, or fail."
  echo "If you see errors, retry later or switch network!"
  sleep 5
fi

rm -f rustup-init.sh rustup-install.log

curl -sSf -o rustup-init.sh https://sh.rustup.rs
chmod +x rustup-init.sh

MAX_ATTEMPTS=5
LOG_FILE="rustup-install.log"
SUCCESS=false

for attempt in $(seq 1 $MAX_ATTEMPTS); do
    DELAY=$((attempt * 10))
    echo "🔧 Installing Rust (attempt $attempt/$MAX_ATTEMPTS)…"
    if ./rustup-init.sh -y --default-toolchain nightly --no-modify-path >"$LOG_FILE" 2>&1; then
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
    echo "This is usually a temporary network problem."
    echo "Try these steps:"
    echo "  • Switch Wi-Fi or use wired"
    echo "  • Disable VPN/proxy"
    echo "  • Retry later"
    echo "  • Try another connection (mobile hotspot)"
    echo "See 'rustup-install.log' for error details."
    echo ""
    echo "Advanced: Try manual download:"
    echo "     curl --retry 5 -O https://static.rust-lang.org/dist/channel-rust-nightly.toml"
    exit 1
fi

# Setup Rust env for the rest of the script and future shells
if ! grep -q 'source $HOME/.cargo/env' ~/.bashrc; then
    echo 'source $HOME/.cargo/env' >> ~/.bashrc
fi
source "$HOME/.cargo/env"

if ! command -v cargo >/dev/null 2>&1; then
    echo "❌ Rust installed, but 'cargo' not found."
    echo "Close and reopen your terminal, then rerun this script."
    exit 1
fi

echo "✅ Rust nightly installed and ready."

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
echo "STEP 5 — Creating aliases for running BasedNode"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

BACKUP_FILE=~/.bashrc.bak.$(date +%Y%m%d%H%M%S)
cp ~/.bashrc "$BACKUP_FILE"
echo "→ Backup of ~/.bashrc saved to $BACKUP_FILE"

# Clean previous BasedNode alias block
sed -i '/# === BasedNode aliases ===/,/# ========================/d' ~/.bashrc

cat <<'EOF' >> ~/.bashrc

# === BasedNode aliases ===
alias basednode-run='~/basednode/target/release/basednode \
  --name "MyBasedNode" \
  --chain ~/basednode/mainnet1_raw.json \
  --rpc-methods Safe \
  --bootnodes /dns/mainnet.basedaibridge.com/tcp/30333/p2p/12D3KooWCQy4hiiA9tHxvQ2PPaSY3mUM6NkMnbsYf2v4FKbLAtUh \
  --log info 2>&1 | grep -Ev "Successfully ran block step.|Not the block to update emission values."'
alias stop-node='pkill -f basednode && echo Node stopped.'
alias restart-node='stop-node; basednode-run'
alias node-logs='tail -f ~/basednode/basednode.log'
alias check-health='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"system_health","params":[]}'\'' | jq'
alias check-peers='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"system_peers","params":[]}'\'' | jq'
alias check-sync='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"chain_getHeader","params":[]}'\'' | jq'
alias check-version='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"system_version","params":[]}'\'' | jq'
alias check-authorities='curl -s http://127.0.0.1:9933 -H "Content-Type: application/json" -d '\''{"id":1,"jsonrpc":"2.0","method":"author_pendingExtrinsics","params":[]}'\'' | jq'
# ========================
EOF

# Reload aliases for this session (full reload on next terminal)
source ~/.bashrc

echo "✅ Aliases added."


echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "INFO — How to use your new BasedNode aliases"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Your BasedNode is about to start in the foreground."
echo ""
echo "ℹ️  When running in foreground, your terminal will be busy showing logs."
echo "   To keep your terminal free, you can run BasedNode in the background:"
echo "      basednode-run &"
echo ""
echo "Available aliases:"
echo "   basednode-run      # Start BasedNode with filtered logs"
echo "   stop-node          # Stop the running node"
echo "   restart-node       # Restart the node"
echo "   node-logs          # View logs (if running in background)"
echo "   check-health       # Check node health (RPC)"
echo "   check-peers        # List connected peers"
echo "   check-sync         # Check blockchain sync status"
echo "   check-version      # Show node software version"
echo "   check-authorities  # See pending extrinsics"
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
echo "• Or use 'basednode-run &' to run it in background."
echo ""

~/basednode/target/release/basednode \
  --name "MyBasedNode" \
  --chain ~/basednode/mainnet1_raw.json \
  --rpc-methods Safe \
  --bootnodes /dns/mainnet.basedaibridge.com/tcp/30333/p2p/12D3KooWCQy4hiiA9tHxvQ2PPaSY3mUM6NkMnbsYf2v4FKbLAtUh \
  --log info 2>&1 | grep -Ev "Successfully ran block step.|Not the block to update emission values."

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
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━