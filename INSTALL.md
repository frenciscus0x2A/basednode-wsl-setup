# 📦 Install BasedNode (WSL)

On **Windows**, open your **Ubuntu terminal (WSL)** and run:

```bash
wget https://raw.githubusercontent.com/frenciscus0x2A/basednode-wsl-setup/main/basednode_install.sh -O basednode_install.sh
chmod +x basednode_install.sh
./basednode_install.sh
```

---

## 🛠️ What this script does

- Checks sudo access
- Verifies WSL + Ubuntu version
- Updates system + installs dependencies
- Installs pinned Rust nightly (+ WASM target)
- Clones/updates BasedNode repo
- Ensures chain spec file is present
- Builds BasedNode (with retry on failure)
- Installs binary globally
- Creates config + helper aliases
- Shows available aliases after install
- Starts node (foreground or background) with filtered logs

---

## ✅ After install

Your node will be **built, installed, and syncing**.  
Use these commands:

- `based-run` → run in foreground
- `based-run-bg` → run in background
- `based-logs` → view logs
- `based-stop` / `based-restart` → control node
- `based-status`, `based-sync`, `based-peers`, `based-version`, `based-peerid` → quick checks

---

**Author:** frenciscus_0x2A • **License:** CC0 — No rights reserved. Public Domain.
