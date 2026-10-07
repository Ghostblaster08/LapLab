#!/usr/bin/env bash
# ==============================================================================
# Toggle Laptop Lid Behavior (Normal Laptop Mode vs 24/7 Homelab Server Mode)
# ==============================================================================
set -e

LID_CONF="/etc/systemd/logind.conf.d/lid.conf"
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

get_status() {
    if [ -f "$LID_CONF" ] && grep -q "HandleLidSwitch=ignore" "$LID_CONF" 2>/dev/null; then
        echo "server"
    else
        echo "normal"
    fi
}

CURRENT_STATUS=$(get_status)

case "$1" in
    status)
        if [ "$CURRENT_STATUS" = "server" ]; then
            echo -e "${GREEN}Current Mode: SERVER MODE${NC} (Laptop stays awake when lid is closed)"
        else
            echo -e "${BLUE}Current Mode: NORMAL LAPTOP MODE${NC} (Laptop suspends when lid is closed)"
        fi
        exit 0
        ;;
    on|server)
        TARGET="server"
        ;;
    off|normal|laptop)
        TARGET="normal"
        ;;
    toggle|"")
        if [ "$CURRENT_STATUS" = "server" ]; then
            TARGET="normal"
        else
            TARGET="server"
        fi
        ;;
    *)
        echo "Usage: $0 [toggle|status|on|off]"
        echo "  status  - Show current lid switch state"
        echo "  toggle  - Switch between Normal and Server modes"
        echo "  on      - Enable Server Mode (stay awake with lid closed)"
        echo "  off     - Enable Normal Mode (suspend when lid closed)"
        exit 1
        ;;
esac

if [ "$TARGET" = "server" ]; then
    echo -e "${YELLOW}Switching to SERVER MODE (ignoring lid close)...${NC}"
    sudo mkdir -p /etc/systemd/logind.conf.d/
    echo -e "[Login]\nHandleLidSwitch=ignore\nHandleLidSwitchDocked=ignore\nHandleLidSwitchExternalPower=ignore" | sudo tee "$LID_CONF" > /dev/null
    sudo systemctl restart systemd-logind
    echo -e "${GREEN}✓ Done: Laptop will now stay awake when the lid is closed.${NC}"
else
    echo -e "${YELLOW}Switching to NORMAL LAPTOP MODE (suspends on lid close)...${NC}"
    if [ -f "$LID_CONF" ]; then
        sudo rm -f "$LID_CONF"
        sudo systemctl restart systemd-logind
    fi
    echo -e "${BLUE}✓ Done: Laptop will now suspend normally when the lid is closed.${NC}"
fi
