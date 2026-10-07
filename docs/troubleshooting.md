# 🛠️ Homelab Troubleshooting & Operational Runbook

This guide covers real-world failure modes, firewall routing quirks, systemd edge cases, and resolution procedures encountered in this modular laptop homelab.

---

## 1. Tailscale & Mobile Remote Access Issues

### Symptom: Phone connects to Tailscale but cannot reach Docker containers
* **Root Cause:** By default, Linux `ufw` (Uncomplicated Firewall) drops forwarded packets between network interfaces (`DEFAULT_FORWARD_POLICY="DROP"`). While standard `ufw allow in on tailscale0` opens traffic to the host's direct ports, Docker containers reside on private bridge networks (e.g. `172.20.0.0/16`), requiring packet routing.
* **Fix:**
  ```bash
  # Allow UFW to forward incoming WireGuard traffic from tailscale0 into Docker bridges
  sudo ufw route allow in on tailscale0
  sudo ufw allow in on tailscale0
  sudo ufw reload
  ```

---

### Symptom: Tailscale fails to start on boot with "device or resource busy"
* **Error Log:** `tstun.New("tailscale0"): device or resource busy`
* **Root Cause:** If the native OS package for Tailscale (`/usr/sbin/tailscaled`) was ever installed on the host and enabled via systemd, it boots before Docker and locks `/dev/net/tun`. The Docker container is then unable to claim the virtual TUN device.
* **Fix:**
  ```bash
  # Stop and permanently disable the host daemon so the container has exclusive access
  sudo systemctl disable --now tailscaled
  docker restart tailscale
  ```

---

### Symptom: SSH over Tailscale times out after changing Wi-Fi networks
* **Root Cause:** When moving between Wi-Fi networks (e.g. home router to mobile hotspot or university network), the laptop's local IP changes. Tailscale's `magicsock` requires a few seconds to renegotiate UDP hole-punching through NAT to discover new peer endpoints.
* **Fix:**
  ```bash
  # Trigger an immediate WireGuard handshake
  docker exec tailscale tailscale ping <peer-ip>
  ```

---

## 2. DNS & AdGuard Home Issues

### Symptom: AdGuard fails to start with "cannot assign requested address"
* **Root Cause:** Binding port 53 to a changing local LAN IP (e.g. `192.168.1.96:53`) will crash Docker when the laptop connects to a different Wi-Fi subnet (e.g. `192.168.22.x`).
* **Fix:**
  Bind AdGuard's DNS port exclusively to your static Tailscale IP (`${TAILSCALE_IP}:53:53`), which remains constant across all networks:
  ```yaml
  ports:
    - "${TAILSCALE_IP}:53:53/tcp"
    - "${TAILSCALE_IP}:53:53/udp"
  ```

---

### Symptom: Phone is on Tailscale but ads are not being blocked
* **Diagnostic:** Open AdGuard Query Log at `http://100.82.40.45:8080`. If queries from your phone (`100.x.y.z`) are 0, your phone is bypassing the VPN resolver.
* **Resolution Checklist:**
  1. **Tailscale Console:** In [Tailscale DNS Settings](https://login.tailscale.com/admin/dns), add your laptop's Tailscale IP as a Custom Nameserver and toggle **"Override local DNS"** ON.
  2. **Android Private DNS:** On Samsung/Android devices, go to **Settings ➔ Connections ➔ More connection settings ➔ Private DNS** and set it to **Off** (when set to *Automatic*, Android routes queries directly to Google via DoT, bypassing VPNs).
  3. **Chrome Secure DNS:** In Chrome, open **Settings ➔ Privacy and security ➔ Use secure DNS** and turn it **Off**.

---

## 3. Storage & Database Permissions

### Symptom: SQLite WAL locking errors on secondary drives
* **Root Cause:** If persistent database directories (`/appdata/`) are located on NTFS-formatted partitions, SQLite's Write-Ahead Logging (`WAL`) mode fails due to POSIX vs NTFS lock incompatibilities (`fcntl` vs Windows locking).
* **Fix:**
  Always keep database files (`dockge.db`, `kuma.db`, `postgres/`, `filebrowser.db`) on the native Linux NVMe/ext4/btrfs filesystem under `HOMELAB_ROOT/appdata/`. Use the secondary NTFS partition only for bulk media storage (movies, TV, photos) mounted under `STORAGE_PATH`.

---

### Symptom: File Browser rejects password updates ("password is too short" / "too easy")
* **Root Cause:** Upstream File Browser enforces strict password validation rules (minimum 12 characters and blocks dictionary words).
* **Fix:**
  ```bash
  docker stop filebrowser
  docker run --rm \
    -v "$APPDATA_PATH/filebrowser/database:/database" \
    -v "$APPDATA_PATH/filebrowser/config:/config" \
    filebrowser/filebrowser users update admin -p "YourSecure12CharPass!" -d /database/filebrowser.db
  docker start filebrowser
  ```

---

## 4. Laptop Headless Server Operation

### Symptom: Laptop suspends when the lid is closed
* **Control:** Use the included [`toggle-lid-mode.sh`](file:///home/ghostblaster/Projects/homeLabs/toggle-lid-mode.sh) utility:
  ```bash
  # Enable server mode (prevents sleep on lid close)
  ./toggle-lid-mode.sh server

  # Revert to normal laptop mode (suspends on lid close)
  ./toggle-lid-mode.sh normal
  ```
