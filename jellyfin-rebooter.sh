#!/bin/sh
set -eu

# ----- CONFIG -----
JELLYFIN_URL="JELLYFIN_URL_HERE" # EG https://your.ip.v4.address:port
API_KEY="JELLYFIN_TOKEN_HERE"
LOG_FILE="LOG_DIRECTORY_HERE"
MAX_LOG_SIZE=500000

DOCKER="/usr/local/AppCentral/docker-ce/bin/docker"
PORTAINER_SERVICE="portainer-ce"
PORTAINER_CONTROL="/usr/local/AppCentral/$PORTAINER_SERVICE/CONTROL/start-stop.sh"

# ----- LOG ROTATION -----
if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt $MAX_LOG_SIZE ]; then
    mv "$LOG_FILE" "${LOG_FILE}.1"
fi

# ----- VALIDATE DOCKER BINARY -----
if [ ! -x "$DOCKER" ]; then
    echo "[$(date)] ERROR: Docker binary not found at $DOCKER" >> "$LOG_FILE"
    exit 1
fi

echo "[$(date)] Checking Jellyfin activity..." >> "$LOG_FILE"

# ----- GET SESSIONS -----
SESSIONS=$(curl -ks -H "X-Emby-Token: $API_KEY" "$JELLYFIN_URL/Sessions" || true)

if [ -z "$SESSIONS" ]; then
    echo "[$(date)] ERROR: Failed to retrieve Jellyfin sessions." >> "$LOG_FILE"
    exit 1
fi

ACTIVE_COUNT=$(echo "$SESSIONS" | grep -o '"DeviceId"' | wc -l)

# ----- NO ACTIVE USERS -----
if [ "$ACTIVE_COUNT" -eq 0 ]; then
    echo "[$(date)] No active Jellyfin sessions found." >> "$LOG_FILE"
    echo "[$(date)] Restarting Portainer and all containers..." >> "$LOG_FILE"

    # Identify Portainer container ID (if any)
    PORTAINER_ID=$($DOCKER ps -aqf "name=portainer" || true)

    echo "Stopping containers..." >> "$LOG_FILE"
    $DOCKER ps -q | grep -v "$PORTAINER_ID" | xargs -r -n1 $DOCKER stop >> "$LOG_FILE" 2>&1

    echo "Restarting Portainer service..." >> "$LOG_FILE"
    $PORTAINER_CONTROL restart >> "$LOG_FILE" 2>&1

    sleep 5

    echo "Starting containers..." >> "$LOG_FILE"
    $DOCKER ps -a -q | grep -v "$PORTAINER_ID" | xargs -r -n1 $DOCKER start >> "$LOG_FILE" 2>&1

    echo "[$(date)] Restart complete." >> "$LOG_FILE"

else
    echo "[$(date)] Active sessions detected ($ACTIVE_COUNT). Skipping restart." >> "$LOG_FILE"
fi
