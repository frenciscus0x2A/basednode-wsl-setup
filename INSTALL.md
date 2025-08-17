## 📦 Install in 3 steps

On **Windows**, open the **Ubuntu terminal window**, then copy-paste:

```bash
wget https://raw.githubusercontent.com/frenciscus0x2A/basednode-wsl-setup/main/basednode_install.sh -O basednode_install.sh
chmod +x basednode_install.sh
./basednode_install.sh
```

> **What this script does:**
>
> - Checks sudo access
> - Verifies WSL and Ubuntu version
> - Updates your system and installs missing dependencies
> - Installs pinned Rust nightly (+ WASM target)
> - Clones or updates BasedNode repository
> - Ensures chain specification file is present
> - Builds BasedNode (with retry on failure)
> - Installs the binary globally
> - Creates useful aliases and helper commands
> - Displays available aliases after installation
> - Launches the node with filtered logs (foreground or background)

✅ At the end: your node will be running and syncing!<br>
**Author:** frenciscus_0x2A
