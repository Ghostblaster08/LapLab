# 🏗️ Homelab Architecture & System Blueprint

This document details the multi-tiered architecture, container topology, storage hierarchy, and hardware offloading capabilities of this modular laptop homelab.

---

## 1. System Topology & Stack Layout

The homelab is partitioned into 6 decoupled, modular Docker Compose stacks connected by an isolated Docker bridge network (`homelab-net`):

```mermaid
graph TD
    subgraph Host ["💻 Host Environment (Omarchy Linux / Arch)"]
        Kernel["Linux Kernel (i915 VA-API DRM)"]
        PipeWire["PipeWire Audio/Video Server"]
        Sunshine["Sunshine Low-Latency Streamer (:47990)"]
        SSH["OpenSSH Daemon (:22)"]
    end

    subgraph Stacks ["🐳 Modular Docker Compose Stacks"]
        subgraph S1 ["01-Network"]
            Tailscale["Tailscale (Host Mode / Exit Node)"]
            AdGuard["AdGuard Home (:8080, :53)"]
            Unbound["Unbound Recursive DNS (:5335)"]
            NPM["Nginx Proxy Manager (:80, :443, :81)"]
        end

        subgraph S2 ["02-Management"]
            Homepage["Homepage Dashboard (:3005)"]
            Dockge["Dockge Compose UI (:5001)"]
            UptimeKuma["Uptime Kuma Monitor (:3001)"]
            Dozzle["Dozzle Live Log Streamer (:9999)"]
        end

        subgraph S3 ["03-Storage"]
            ImmichServer["Immich Web/App (:2283)"]
            ImmichML["Immich ML (CLIP/InsightFace)"]
            ImmichDB["PostgreSQL 16 (pgvector)"]
            ImmichRedis["Valkey 8 Redis Cache"]
            FileBrowser["File Browser Cloud Drive (:8085)"]
        end

        subgraph S4 ["04-Media"]
            Jellyfin["Jellyfin 4K Transcoder (:8096)"]
            Audiobookshelf["Audiobookshelf (:13378)"]
        end

        subgraph S5 ["05-Automation (Optional)"]
            HomeAssistant["Home Assistant (:8123)"]
            Mosquitto["Mosquitto MQTT (:1883)"]
        end

        subgraph S6 ["06-Servarr (Optional)"]
            Gluetun["Gluetun VPN Tunnel"]
            QBit["qBittorrent (:8080)"]
            ArrStack["Sonarr / Radarr / Prowlarr"]
        end
    end

    Kernel --> Jellyfin
    Kernel --> Sunshine
    PipeWire --> Sunshine
    S1 --- S2
    S2 --- S3
    S3 --- S4
```

---

## 2. Storage Tiering & Filesystem Architecture

To balance high-speed database operations with large-capacity media storage without triggering file-locking issues, the homelab employs a tiered storage layout:

```text
/
├── home/ghostblaster/Projects/homeLabs/
│   ├── appdata/                 # Tier 1: Fast NVMe SSD (btrfs/ext4)
│   │   ├── immich/postgres/     # PostgreSQL pgvector transactional data
│   │   ├── dockge/              # Dockge SQLite database (WAL mode)
│   │   ├── uptime-kuma/         # Uptime Kuma time-series database
│   │   ├── filebrowser/database # BoltDB user metadata
│   │   └── jellyfin/cache/      # Transcoding scratch directory
│   └── stacks/                  # Version-controlled Docker Compose definitions
│
└── mnt/storage/                 # Tier 2: Bulk Secondary Drive (1TB NTFS/ext4)
    ├── media/                   # Jellyfin & Audiobookshelf libraries
    │   ├── movies/
    │   ├── tv/
    │   ├── audiobooks/
    │   └── podcasts/
    ├── photos/                  # Immich original photo and video vault
    ├── downloads/               # Bulk downloads
    └── backups/                 # Container state and volume archives
```

> [!IMPORTANT]
> **Why Database Files Must Never Live on NTFS:**
> SQLite's Write-Ahead Log (`WAL`) and PostgreSQL's lock manager require native POSIX advisory file locking (`fcntl()`). Storing active database volumes on NTFS partitions mounted via `ntfs-3g` causes database corruption or persistent file lock timeouts. All database folders reside strictly in Tier 1 (`appdata/` on NVMe).

---

## 3. Hardware Acceleration & Intel QuickSync (QSV)

The host machine utilizes an **Intel Core i5-1035G1** processor featuring **Intel Iris Plus / UHD Graphics**.

Jellyfin and Sunshine tap directly into the silicon video processing engine:
* **Host Device Nodes:** `/dev/dri/renderD128` or `/dev/dri/renderD129`
* **Driver Stack:** Linux `i915` kernel driver ➔ userspace `libva` / `va-api` ➔ Intel Media Driver (`iHD`)
* **Codec Capabilities:**
  - H.264 (AVC): 8-bit hardware encode and decode
  - H.265 (HEVC): 8-bit and 10-bit hardware encode and decode
  - VP9: 8-bit and 10-bit profile 0/2 hardware decode
* **Docker Passthrough:**
  ```yaml
  devices:
    - /dev/dri/renderD129:/dev/dri/renderD129
  group_add:
    - "video"
    - "render"
  ```
This enables real-time 4K-to-1080p video transcoding on Jellyfin with sub-5% CPU utilization.
