#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"

trap 'echo ""; echo "⚠️ Script interrupted. Exiting safely."; exit 1' INT

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " BasedNode install script — version $VERSION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

###############################################################################
# BasedNode Installation Guide (Unofficial Fork)
#
# This script helps you install:
#   - BasedNode node → https://github.com/BF1337/basednode (Unofficial Fork)
#
# IMPORTANT:
#   → BasedNode requires the Rust NIGHTLY toolchain.
#
# HOW TO USE THIS SCRIPT
#
#   Type all the commands below in your Ubuntu console.
#
#   1. Download the script:
#
#        wget https://raw.githubusercontent.com/frenciscus0x2A/basednode-wsl-setup/main/basednode_install.sh -O basednode_install.sh
#
#   2. Make the script executable:
#
#        chmod +x basednode_install.sh
#
#   3. Run the script:
#
#        ./basednode_install.sh
#
# WHAT DOES THIS SCRIPT DO?
#
# → Checks sudo access
# → Updates your system and installs dependencies
# → Installs Rust (nightly toolchain + WASM target)
# → Clones and builds BasedNode
# → Installs the binary globally
# → Creates helpful aliases for running and managing your node
# → Reloads your shell settings
# → Launches BasedNode with filtered logs
#
# At the end, your node will be running and syncing!
#
# Author: frenciscus_0x2A
###############################################################################

echo ""
echo "𓆏 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1 — Checking sudo access…"
echo "𓆏 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if ! sudo -v; then
    echo "❌ Wrong password or sudo failed multiple times. Exiting."
    exit 1
fi

echo "✅ Sudo access confirmed."

echo ""
echo "𓆏 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2 — Updating system and installing base tools…"
echo "𓆏 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

sudo apt update && \
sudo apt upgrade -y && \
sudo apt install -y software-properties-common curl git clang build-essential libssl-dev pkg-config libclang-dev protobuf-compiler jq

echo "✅ System updated and packages installed."

echo ""
echo "𓆏 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 3 — Installing Rust toolchain (nightly required)…"
echo "𓆏 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# PRECHECK: Test static.rust-lang.org CDN before starting install
echo "𓆏 Checking connection to Rust download servers…"
if ! curl -sf --max-time 10 https://static.rust-lang.org/dist/channel-rust-nightly.toml > /dev/null; then
  echo "𓆏 ⚠️ Can't quickly reach static.rust-lang.org"
  echo "𓆏 Your connection is slow or blocked (firewall, hotel/campus network, etc)."
  echo "𓆏 The Rust install may take a long time, or fail with a timeout error."
  echo "𓆏 If you see errors, try again later or switch Wi-Fi/network!"
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
    echo "𓆏 🔧 Installing Rust (attempt $attempt/$MAX_ATTEMPTS)…"
    if ./rustup-init.sh -y --default-toolchain nightly --no-modify-path >"$LOG_FILE" 2>&1; then
        SUCCESS=true
        break
    else
        echo "𓆏 ❌ Attempt $attempt failed. Retrying in $DELAY seconds…"
        sleep $DELAY
    fi
done

rm -f rustup-init.sh

if ! $SUCCESS; then
    echo ""
    echo "𓆏 🚨 Rust install failed after $MAX_ATTEMPTS attempts."
    echo "𓆏 This is almost always a temporary network/CDN issue (slow, blocked, or unreliable connection)."
    echo "𓆏 What to try:"
    echo "  • Change your Wi-Fi or use a wired network if possible"
    echo "  • Try disabling VPN or proxy"
    echo "  • Run the script again at another time (off-peak, or after rebooting your box)"
    echo "  • If possible, try on another connection (mobile hotspot, etc)"
    echo "𓆏 See 'rustup-install.log' for error details."
    echo ""
    echo "𓆏 Advanced: You can try manually downloading:"
    echo "     curl --retry 5 -O https://static.rust-lang.org/dist/channel-rust-nightly.toml"
    echo "If that is also slow or fails, your network is the problem!"
    exit 1
fi

# Setup Rust env for the rest of the script and future shells
if ! grep -q 'source $HOME/.cargo/env' ~/.bashrc; then
    echo 'source $HOME/.cargo/env' >> ~/.bashrc
fi
source "$HOME/.cargo/env"

if ! command -v cargo >/dev/null 2>&1; then
    echo "𓆏 ❌ Rust installed, but 'cargo' not found."
    echo "𓆏 Try closing and reopening your terminal, then rerun this script."
    exit 1
fi

echo "𓆏 ✅ Rust nightly installed and ready."

echo ""
echo "𓆏 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 4 — Cloning and building BasedNode…"
echo "𓆏 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd ~

if [ -d "basednode" ]; then
    echo "Folder 'basednode' exists. Updating repo…"
    cd basednode
    git pull
else
    # Wrap clone in retry in case of temporary network failure
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

cargo clean
echo "Building BasedNode… (this may take several minutes)"

MAX_BUILD_ATTEMPTS=3
for attempt in $(seq 1 $MAX_BUILD_ATTEMPTS); do
    if cargo +nightly build --release | tee ~/basednode_build.log; then
        echo "✅ Build finished."
        break
    else
        echo "❌ Build failed (attempt $attempt). Retrying in 10s…"
        sleep 10
    fi
done

if [ ! -f ./target/release/basednode ]; then
    echo "❌ Build failed after $MAX_BUILD_ATTEMPTS attempts."
    echo "Check your network connection, then try:"
    echo "    cargo +nightly build --release"
    echo "See '~/basednode_build.log' for more details."
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
echo "𓆏 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 5 — Creating aliases for running BasedNode"
echo "𓆏 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

BACKUP_FILE=~/.bashrc.bak.$(date +%Y%m%d%H%M%S)
cp ~/.bashrc "$BACKUP_FILE"
echo "→ Backup of ~/.bashrc saved to $BACKUP_FILE"

if sed --version >/dev/null 2>&1; then
    sed -i '/alias basednode-run/d' ~/.bashrc
else
    sed -i '' '/alias basednode-run/d' ~/.bashrc
fi

echo ""
echo "𓆏 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "INFO — How to use your new BasedNode aliases"
echo "𓆏 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "✅ Your BasedNode is about to start in the foreground."
echo ""
echo "⚠️ IMPORTANT:"
echo "→ As long as BasedNode runs in foreground, your terminal is LOCKED on its logs."
echo ""
echo "→ To run commands like the aliases below, either:"
echo "   - Open a new Ubuntu console window (WSL)"
echo "   - OR run BasedNode in the background later (using basednode-run &)"
echo ""
echo "ℹ️ Foreground means your console shows logs and stays busy."
echo "   Background means BasedNode runs silently, and your console prompt returns."
echo ""
echo "ℹ️ WSL is Linux running inside Windows. All these commands work as in Linux."
echo ""
echo "✅ Available aliases:"
echo ""
echo "   basednode-run        # Start BasedNode with logs filtered"
echo "   stop-node            # Stop the running node"
echo "   restart-node         # Restart the node"
echo "   node-logs            # Tail logs if node is running in background"
echo ""
echo "   check-health         # Check node health via RPC"
echo "   check-peers          # List peers connected to your node"
echo "   check-sync           # Check blockchain sync status"
echo "   check-version        # Print node software version"
echo "   check-authorities    # See pending extrinsics for authorities"
echo ""
echo "ℹ️ For background mode, run:"
echo "   basednode-run &"
echo ""

echo "alias basednode-run='~/basednode/target/release/basednode \
  --name \"MyBasedNode\" \
  --chain ~/basednode/mainnet1_raw.json \
  --rpc-methods Safe \
  --bootnodes /dns/mainnet.basedaibridge.com/tcp/30333/p2p/12D3KooWCQy4hiiA9tHxvQ2PPaSY3mUM6NkMnbsYf2v4FKbLAtUh \
  --log info \
  2>&1 | grep -Ev \"Successfully ran block step.|Not the block to update emission values.\"'" >> ~/.bashrc

echo "alias stop-node='pkill -f basednode && echo Node stopped.'" >> ~/.bashrc
echo "alias restart-node='stop-node; basednode-run'" >> ~/.bashrc
echo "alias node-logs='tail -f ~/basednode/basednode.log'" >> ~/.bashrc

echo "alias check-health='curl -s http://127.0.0.1:9933 -H \"Content-Type: application/json\" -d '\''{\"id\":1,\"jsonrpc\":\"2.0\",\"method\":\"system_health\",\"params\":[]}'\'' | jq'" >> ~/.bashrc
echo "alias check-peers='curl -s http://127.0.0.1:9933 -H \"Content-Type: appl
