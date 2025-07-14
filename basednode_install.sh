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
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1 — Checking sudo access…"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if ! sudo -v; then
    echo "❌ Wrong password or sudo failed multiple times. Exiting."
    exit 1
fi

echo "✅ Sudo access confirmed."

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2 — Updating system and installing base tools…"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

sudo apt update && \
sudo apt upgrade -y && \
sudo apt install -y software-properties-common curl git clang build-essential libssl-dev pkg-config libclang-dev protobuf-compiler jq

echo "✅ System updated and packages installed."

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 3 — Installing Rust toolchain (nightly required)…"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Download rustup-init script
curl -sSf -o rustup-init.sh https://sh.rustup.rs
chmod +x rustup-init.sh

# Install Rust nightly non-interactively
if ! ./rustup-init.sh -y --default-toolchain nightly --no-modify-path; then
    echo "❌ Rust installation failed."
    rm -f rustup-init.sh
    exit 1
fi

# Clean up installer
rm -f rustup-init.sh

# Ensure ~/.cargo/env is sourced to load Cargo into PATH
if ! grep -q 'source $HOME/.cargo/env' ~/.bashrc; then
    echo 'source $HOME/.cargo/env' >> ~/.bashrc
fi

# Source cargo env right now for this session
source "$HOME/.cargo/env"

# Check if cargo is available
if ! command -v cargo >/dev/null 2>&1; then
    echo "❌ Cargo not found in PATH even after sourcing env. Exiting."
    exit 1
fi

echo "✅ Rust nightly toolchain installed and environment loaded."

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 4 — Cloning and building BasedNode…"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cd ~

if [ -d "basednode" ]; then
    echo "Folder 'basednode' exists. Updating repo…"
    cd basednode
    git pull
else
    if ! git clone --branch main https://github.com/BF1337/basednode.git; then
        echo "❌ Failed to clone BasedNode repository."
        exit 1
    fi
    cd basednode
fi

cargo clean
echo "Building BasedNode…"

if ! cargo build --release | tee ~/basednode_build.log; then
    echo "❌ Cargo build failed. Showing last 20 lines of log:"
    tail -n 20 ~/basednode_build.log || true
    exit 1
fi

if [ ! -f ./target/release/basednode ]; then
    echo "❌ Build failed."
    exit 1
fi

echo "✅ Build finished."

sudo cp ./target/release/basednode /usr/local/bin/

if ! command -v basednode >/dev/null 2>&1; then
    echo "❌ BasedNode binary not found in PATH after installation."
    exit 1
fi

echo "✅ BasedNode binary installed globally."

mkdir -p ~/basednode

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 5 — Creating aliases for running BasedNode"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

BACKUP_FILE=~/.bashrc.bak.$(date +%Y%m%d%H%M%S)
cp ~/.bashrc "$BACKUP_FILE"
echo "→ Backup of ~/.bashrc saved to $BACKUP_FILE"

if sed --version >/dev/null 2>&1; then
    sed -i '/alias basednode-run/d' ~/.bashrc
else
    sed -i '' '/alias basednode-run/d' ~/.bashrc
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "INFO — How to use your new BasedNode aliases"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

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
echo "alias check-peers='curl -s http://127.0.0.1:9933 -H \"Content-Type: application/json\" -d '\''{\"id\":1,\"jsonrpc\":\"2.0\",\"method\":\"system_peers\",\"params\":[]}'\'' | jq'" >> ~/.bashrc
echo "alias check-sync='curl -s http://127.0.0.1:9933 -H \"Content-Type: application/json\" -d '\''{\"id\":1,\"jsonrpc\":\"2.0\",\"method\":\"chain_getHeader\",\"params\":[]}'\'' | jq'" >> ~/.bashrc
echo "alias check-version='curl -s http://127.0.0.1:9933 -H \"Content-Type: application/json\" -d '\''{\"id\":1,\"jsonrpc\":\"2.0\",\"method\":\"system_version\",\"params\":[]}'\'' | jq'" >> ~/.bashrc
echo "alias check-authorities='curl -s http://127.0.0.1:9933 -H \"Content-Type: application/json\" -d '\''{\"id\":1,\"jsonrpc\":\"2.0\",\"method\":\"author_pendingExtrinsics\",\"params\":[]}'\'' | jq'" >> ~/.bashrc

source ~/.bashrc

echo "✅ Aliases added."

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 6 — Running BasedNode in foreground"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "✅ BasedNode installation completed!"
echo ""
echo "ℹ️ Note:"
echo "→ Your node will sync and work with the network even without extra options."
echo ""
echo "⚠️ SECURITY REMINDER:"
echo "→ RPC lets other computers talk to your node."
echo "→ NEVER open RPC to the Internet unless you fully understand firewalls, VPNs, and trusted IPs."
echo ""
echo "→ The command below will run your node in foreground with repetitive messages filtered."
echo "→ Your terminal will display logs and remain blocked while it runs."
echo ""
echo "→ To stop your node anytime, press CTRL+C."
echo ""
echo "→ Next time, simply run 'basednode-run' to launch your node in the foreground."
echo "→ Or run it in the background if you prefer."
echo ""

~/basednode/target/release/basednode \
  --name "MyBasedNode" \
  --chain ~/basednode/mainnet1_raw.json \
  --rpc-methods Safe \
  --bootnodes /dns/mainnet.basedaibridge.com/tcp/30333/p2p/12D3KooWCQy4hiiA9tHxvQ2PPaSY3mUM6NkMnbsYf2v4FKbLAtUh \
  --log info 2>&1 | grep -Ev "Successfully ran block step.|Not the block to update emission values."

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "The node has stopped (if you pressed CTRL+C)."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "✅ NEXT STEPS:"
echo ""
echo "→ Run the following to launch BasedNode again:"
echo "     basednode-run"
echo ""
echo "🎉 Installation finished. Happy syncing!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
