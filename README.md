# BasedNode Installation Guide

> **Unofficial guide** for running [BF1337/basednode](https://github.com/BF1337/basednode),  
> a maintained community fork of the official [getbasedai/basednode](https://github.com/getbasedai/basednode) by Baselabs.

Run a BasedNode easily on **Ubuntu with WSL (Windows Subsystem for Linux)**, ideal for Windows users, beginners, or the crypto-curious.

Typical install time: **~42 minutes**

---

## 🧐 Why WSL?

- Runs Ubuntu “inside” Windows (no virtual machine required)
- Faster setup, fewer headaches
- Easy to remove if you change your mind

---

## 🔒 Security Note — What is RPC?

RPC (**Remote Procedure Call**) lets you control the node (send commands, read info) from your computer or other software.  
**By default, this script keeps the node’s RPC _private_ (local-only).**

- This means no one outside your computer can connect or control your node.
- As long as you don’t change this, it’s safe for testing on your machine.

> ⚠️ **If you later change node settings to open up RPC or network ports:**  
> Make sure you understand security basics first!  
> For 24/7 or public nodes, use a VPS or a server, not your personal computer.

---

## ✅ How to install Ubuntu (WSL)

1. Open the **Microsoft Store** and search for **Ubuntu 22.04 LTS** (any 22.04.x sub-version is OK).
2. Click **Install**.
3. Launch Ubuntu from the Start menu.
4. Choose a Linux username and password.

---

## ✅ How to install the node

Follow the instructions in `basednode_install.sh`.

---

May your syncs be smooth. GLHF frens!

Author: frenciscus_0x2A
