# BasedNode Installation Guide

> Installs the community-maintained [BF1337/basednode](https://github.com/BF1337/basednode) fork (not the original repo).

Welcome to the **BasedNode Unofficial Install Guide**—ideal for beginners, local testing, or anyone just curious about running a node on Windows.

This guide helps you install and run a BasedNode on **Ubuntu under WSL (Windows Subsystem for Linux)**.  
Perfect for Windows users new to Linux.

Typical install time: **~42 minutes**.

---

## 🚀 Why WSL?

- Run Ubuntu directly inside Windows
- No virtual machines needed
- Easier setup—less security/config headaches for testing
- Great for local tests and learning

⚠️ **Note:**  
This script does **not** expose the node's RPC port to the public internet.  
For testing and learning, it’s safe to run your node locally for several days on WSL—**as long as you don’t modify the script to open RPC to the outside**.

If you change the node’s configuration or open ports to the network,  
make sure you understand security best practices before going further.  
For 24/7 or public nodes, using a VPS or dedicated server is strongly recommended.

---

## ✅ How to install Ubuntu (WSL)

1. Open the **Microsoft Store** and search for **Ubuntu 22.04 LTS** (any sub-version is OK).
2. Click **Install**.
3. Launch Ubuntu from the Start menu.
4. Choose a Linux username and password.

---

## ✅ How to run the install script

Once Ubuntu is installed and running, refer to the `basednode_install.sh` script for all installation steps.

---

Happy syncing!

_Author: frenciscus_0x2A_
