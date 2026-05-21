# Raspberry Pi Zero 2W – USB Gadget for Blink Camera (and others) Storage Setup

This guide sets up a Raspberry Pi Zero 2 W as a **USB mass storage device / Flash Drive**, that a camera writes to, while the Pi:

* Reads the virtual USB disk (`/piusb.bin`)
* Detects completed video files
* Automatically copies them to a network share (`/security`)
* Avoids USB unplug/replug entirely


It is designed to avoid:
- Camera “format USB drive” corruption issues
- FAT filesystem inconsistencies
---

What you'll need:
- Raspberry Pi W2<br>
- A Pi Zero USB Dongle Board/case (preferably) Check Amazon for "Geekworm USB Dongle Board"<br>
- MicroSD card for your OS and drive image (Raspberry Pi OS Lite), 16G+ Recommended<br>

```
sudo apt update
sudo apt install util-linux dosfstools
```


---

# ⚙️ System Architecture

```
Camera → USB → Pi (g_mass_storage) → /piusb.bin → loop mount → /mnt/usb_share → sync script → /security
```

---

Install Required Tools

```
sudo apt update
sudo apt install util-linux dosfstools
```

(Optional sync tools later: rsync, cifs-utils)

---

# 🔌 USB Gadget Setup

## Enable required modules

### Edit `/etc/modules`

```
dwc2
```

### Edit `/boot/firmware/config.txt`

```
dtoverlay=dwc2
```

### Edit `/boot/firmware/cmdline.txt`

(Add to existing line, do NOT create a new line)

```
modules-load=dwc2
```

---

# 💾 Create Camera-Safe USB Image (IMPORTANT)

Use 2–4GB depending on camera needs (since you'll be archiving to server share, you can lower your camera's auto-delete range):

```bash
sudo dd if=/dev/zero of=/piusb.bin bs=1M count=4096
```

Attach loop device:

```bash
sudo losetup -Pf /piusb.bin
```

Check device:

```bash
losetup -a
```

Example:

```
/dev/loop1: (/piusb.bin)
```

Create partition:

```bash
sudo fdisk /dev/loop1
```

* `n` → new partition
* `p` → primary
* defaults
* `w` → write

Format:

```bash
sudo mkfs.vfat -F 32 -n CAMERA /dev/loop1p1
```

Detach:

```bash
sudo losetup -d /dev/loop1
```

---

# 🔗 Enable USB Mass Storage

```bash
sudo modprobe g_mass_storage file=/piusb.bin stall=0 removable=1
```

✔ Camera should now detect storage
✔ Format ONCE from camera if required

---

# 📁 Mount for Pi Access

```bash
sudo losetup -Pf /piusb.bin
sudo mount /dev/loop1p1 /mnt/usb_share
```

---

# 🌐 SMB Network Share Setup

## Install CIFS

```bash
sudo apt install cifs-utils
```

## Create credentials file

```bash
sudo nano /root/.smbcred
```

```
username=YOUR_USER
password=YOUR_PASS
```

Secure it:

```bash
chmod 600 /root/.smbcred
```

## Add to `/etc/fstab`

```
//yourserverip/yourservershare/security /security cifs credentials=/root/.smbcred,vers=3.0,iocharset=utf8,_netdev 0 0
```

Mount:

```bash
sudo mount -a
```

---

# 🤖 Sync Script

This script performs a "sync" to ensure any cached files are written to the "drive" before the copy.

## `/usr/local/bin/camera-sync.sh`

```bash
#!/bin/bash

SRC="/mnt/usb_share"
DEST="/security"
IMAGE="/piusb.bin"
LOG="/var/log/camera-sync.log"

echo "=== $(date) camera sync service started ===" >> "$LOG"

while true; do

    #########################################################
    # HEALTH CHECK: SMB SHARE
    #########################################################

    if ! mountpoint -q "$DEST"; then
        echo "$(date) WARNING: $DEST not mounted, attempting mount -a" >> "$LOG"

        mount -a >> "$LOG" 2>&1
        sleep 5

        if ! mountpoint -q "$DEST"; then
            echo "$(date) ERROR: failed to mount $DEST" >> "$LOG"
            sleep 30
            continue
        fi

        echo "$(date) SUCCESS: remounted $DEST" >> "$LOG"
    fi

    #########################################################
    # HEALTH CHECK: USB IMAGE LOOP MOUNT
    #########################################################

    if ! mountpoint -q "$SRC"; then
        echo "$(date) WARNING: $SRC not mounted, attempting recovery" >> "$LOG"

        # Attach loop device if missing
        if ! losetup -a | grep -q "$IMAGE"; then
            losetup -Pf "$IMAGE" >> "$LOG" 2>&1
            sleep 2
        fi

        LOOPDEV=$(losetup -a | grep "$IMAGE" | head -n1 | cut -d: -f1)

        if [ -z "$LOOPDEV" ]; then
            echo "$(date) ERROR: unable to locate loop device for $IMAGE" >> "$LOG"
            sleep 30
            continue
        fi

        # Mount partition
        mount "${LOOPDEV}p1" "$SRC" >> "$LOG" 2>&1
        sleep 2

        if ! mountpoint -q "$SRC"; then
            echo "$(date) ERROR: failed to mount $SRC" >> "$LOG"
            sleep 30
            continue
        fi

        echo "$(date) SUCCESS: remounted $SRC using ${LOOPDEV}p1" >> "$LOG"
    fi

    #########################################################
    # FORCE FAT REFRESH
    #########################################################

    sync
    echo 3 > /proc/sys/vm/drop_caches

    #########################################################
    # FILE SCAN
    #########################################################

    find "$SRC" -type f -print0 | while IFS= read -r -d '' file; do

        # Verify file still exists
        [ ! -f "$file" ] && continue

        rel="${file#$SRC/}"
        dest_file="$DEST/$rel"

        # Skip already copied files
        [ -f "$dest_file" ] && continue

        # Skip files younger than 10 seconds
        age=$(( $(date +%s) - $(stat -c %Y "$file" 2>/dev/null) ))

        [ "$age" -lt 10 ] && continue

        # File size stability check
        size1=$(stat -c%s "$file" 2>/dev/null)

        sleep 2

        size2=$(stat -c%s "$file" 2>/dev/null)

        # Skip if file vanished
        [ -z "$size1" ] || [ -z "$size2" ] && continue

        if [ "$size1" = "$size2" ] && [ "$size1" -gt 0 ]; then

            mkdir -p "$(dirname "$dest_file")"

            if rsync -a "$file" "$dest_file" >> "$LOG" 2>&1; then
                echo "$(date) COPIED: $rel ($size1 bytes)" >> "$LOG"
            else
                echo "$(date) ERROR copying: $rel" >> "$LOG"
            fi
        fi
    done

    sleep 10
done
```

Make executable:

```bash
chmod +x /usr/local/bin/camera-sync.sh
```

---

# ⚙️ Systemd Service

## `/etc/systemd/system/camera-sync.service`

```ini
[Unit]
Description=Camera USB Sync Service
After=network.target

[Service]
ExecStart=/usr/local/bin/camera-sync.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
```

Enable:

```bash
sudo systemctl daemon-reload
sudo systemctl enable camera-sync.service
sudo systemctl start camera-sync.service
```

---

# 🔍 Monitoring

Live logs:

```bash
tail -f /var/log/camera-sync.log
```

---

# ⚠️ Important Behavior Notes

## FAT + USB Gadget Limitation

* Camera writes directly to `/piusb.bin`
* Linux reads same filesystem
* FAT does **NOT support concurrent access**

### Result:

* Files may not appear immediately
* Directory cache becomes stale

---

# ⚡ Reliability Guarantees

✔ No USB unplug required
✔ No camera interruption
✔ Safe file copy (no partial videos)
✔ Handles subfolders automatically
✔ Works after reboot

---

# 🔌 After Power Loss / Reboot

System will:

* auto-load `dwc2`
* auto-load `g_mass_storage`
* expose `/piusb.bin` to camera
* restart sync service automatically

---
