
DO NOT USE CURRENTLY TESTING!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

# 🔧 Custom SteamOS Recovery Installer (External Drive–Friendly)


### 1. Boot Into the SteamOS Recovery USB

- Plug in the USB stick
- On a Steam Deck, hold **Volume Down + Power** to open the boot menu
- Select the USB and boot into the recovery environment

---

### 2. Open a Terminal

Launch **Konsole** from the desktop, or press `Ctrl + Alt + T`.

---

### 3. Clone This Repo

```bash
git clone https://github.com/Volanaro/steamos_desktop_install.git
cd steamos_custom_install 
```
---

### 4. Make the Script Executable

```bash
chmod +x repair_device.sh
```
---
### 5. Run the Installer Script

```bash
sudo ./repair_device.sh all
```

You’ll be prompted to:
- Enter the target disk (e.g. `/dev/sda`)
- Confirm that you really want to wipe and reinstall SteamOS

---
