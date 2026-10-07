#!/usr/bin/env bash
# ==============================================================================
# Homelab Stack Launcher
# Pure Docker container orchestrator — NO sudo, NO host/laptop config modifications
# ==============================================================================
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

HOMELAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Verify docker socket accessibility
if ! docker ps &>/dev/null; then
    echo -e "${RED}Error: Cannot connect to Docker daemon.${NC}"
    if grep -qw "docker" /etc/group && ! id -nG | grep -qw "docker"; then
        echo -e "${YELLOW}Your user is in the docker group, but this terminal session has not reloaded groups yet.${NC}"
        echo -e "Please run: ${GREEN}newgrp docker${NC} (or open a new terminal window) and run this script again."
    else
        echo -e "Please ensure the Docker service is running: ${GREEN}systemctl status docker${NC}"
    fi
    exit 1
fi

ACTION="${1:-help}"

case "$ACTION" in
    start|up)
        echo -e "${BLUE}==================================================================${NC}"
        echo -e "${GREEN}       🚀 Starting Homelab Services (Zero Host Config Changes)     ${NC}"
        echo -e "${BLUE}==================================================================${NC}"

        # 1. Initialize persistent workspace directories (only in ~/Projects/homeLabs)
        echo -e "\n${YELLOW}[1/3] Verifying workspace storage paths...${NC}"
        mkdir -p "$HOMELAB_DIR/appdata/"{adguard/work,adguard/conf,unbound,npm/data,npm/letsencrypt,tailscale,dockge,uptime-kuma,homepage,immich/postgres,immich/model-cache,immich/redis,filebrowser,jellyfin/config,jellyfin/cache,audiobookshelf/config,audiobookshelf/metadata,homeassistant/config,mosquitto/config,mosquitto/data,mosquitto/log,gluetun,qbittorrent/config,prowlarr/config,radarr/config,sonarr/config,bazarr/config}
        if [ -d "/mnt/storage" ]; then
            mkdir -p /mnt/storage/{media/{movies,tv,music,audiobooks,podcasts},photos,downloads,backups}
        fi
        echo -e "${GREEN}✓ Workspace directories verified.${NC}"

        # 2. Ensure internal bridge network exists
        echo -e "\n${YELLOW}[2/3] Checking Docker internal network (homelab-net)...${NC}"
        if ! docker network inspect homelab-net &>/dev/null; then
            echo "Creating bridge network homelab-net (172.20.0.0/24)..."
            docker network create --subnet 172.20.0.0/24 homelab-net
            echo -e "${GREEN}✓ Created homelab-net.${NC}"
        else
            echo -e "${GREEN}✓ homelab-net already exists.${NC}"
        fi

        # 3. Launch Docker Compose Stacks
        echo -e "\n${YELLOW}[3/3] Deploying containers...${NC}"

        echo -e "\n${BLUE}--> [1/4] Network Stack (AdGuard Home + Unbound + Nginx Proxy Manager + Tailscale)...${NC}"
        (cd "$HOMELAB_DIR/stacks/01-network" && docker compose up -d)

        echo -e "\n${BLUE}--> [2/4] Management Stack (Dockge + Uptime Kuma + Homepage + Dozzle)...${NC}"
        (cd "$HOMELAB_DIR/stacks/02-management" && docker compose up -d)

        echo -e "\n${BLUE}--> [3/4] Storage Stack (Immich Photos + File Browser)...${NC}"
        (cd "$HOMELAB_DIR/stacks/03-storage" && docker compose up -d)

        echo -e "\n${BLUE}--> [4/4] Media Stack (Jellyfin QuickSync QSV + Audiobookshelf)...${NC}"
        (cd "$HOMELAB_DIR/stacks/04-media" && docker compose up -d)

        echo -e "\n${GREEN}==================================================================${NC}"
        echo -e "${GREEN}   ✨ Homelab Stacks Successfully Launched!                      ${NC}"
        echo -e "${GREEN}==================================================================${NC}"

        HOST_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7}' || echo "192.168.1.96")

        echo -e "\n${BLUE}Available Services & Dashboards:${NC}"
        echo -e "  🌐 ${YELLOW}Dockge (Stack UI Manager):${NC}    http://${HOST_IP}:5001"
        echo -e "  🛡️ ${YELLOW}AdGuard Home DNS Setup:${NC}       http://${HOST_IP}:3000 (dashboard: :8080)"
        echo -e "  🔀 ${YELLOW}Nginx Proxy Manager:${NC}          http://${HOST_IP}:81"
        echo -e "  🔒 ${YELLOW}Tailscale Remote Mesh:${NC}        Run 'docker logs tailscale' to pair"
        echo -e "  📊 ${YELLOW}Homepage Dashboard:${NC}           http://${HOST_IP}:3005"
        echo -e "  📈 ${YELLOW}Uptime Kuma Status:${NC}           http://${HOST_IP}:3001"
        echo -e "  📜 ${YELLOW}Dozzle Container Logs:${NC}        http://${HOST_IP}:9999"
        echo -e "  📸 ${YELLOW}Immich Photos & Videos:${NC}       http://${HOST_IP}:2283"
        echo -e "  📁 ${YELLOW}File Browser Web NAS:${NC}         http://${HOST_IP}:8085"
        echo -e "  🎬 ${YELLOW}Jellyfin Media Server:${NC}        http://${HOST_IP}:8096"
        echo -e "  🎧 ${YELLOW}Audiobookshelf:${NC}               http://${HOST_IP}:13378"
        echo -e "  🎮 ${YELLOW}Sunshine Remote Desktop:${NC}       https://${HOST_IP}:47990"

        ;;

    stop|down)
        echo -e "${YELLOW}Stopping all Homelab Docker stacks...${NC}"
        for stack in 04-media 03-storage 02-management 01-network; do
            if [ -d "$HOMELAB_DIR/stacks/$stack" ]; then
                echo -e "Stopping $stack..."
                (cd "$HOMELAB_DIR/stacks/$stack" && docker compose down) || true
            fi
        done
        echo -e "${GREEN}✓ All stacks stopped.${NC}"
        ;;

    status|ps)
        echo -e "${BLUE}=== Homelab Running Containers ===${NC}"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        ;;

    help|*)
        echo -e "${BLUE}Homelab Stack Manager${NC}"
        echo -e "Usage: $0 {start|stop|status}"
        echo ""
        echo -e "  ${GREEN}start${NC}   - Deploy and start all homelab container stacks"
        echo -e "  ${YELLOW}stop${NC}    - Gracefully stop and tear down all stacks"
        echo -e "  ${BLUE}status${NC}  - Show currently running homelab containers"
        echo ""
        echo -e "To toggle laptop lid sleep behavior without touching system configs:"
        echo -e "  Use: ${GREEN}toggle-lid${NC} (or ${GREEN}./toggle-lid-mode.sh${NC})"
        ;;
esac
