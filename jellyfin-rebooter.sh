#!/bin/sh
set -eu

# ----- CONFIG -----
JELLYFIN_URL="JELLYFIN_URL_HERE" # EG https://your.ip.v4.address:port
API_KEY="JELLYFIN_TOKEN_HERE"
LOG_FILE="LOG_DIRECTORY_HERE"
MAX_LOG_SIZE=500000

DOCKER="docker"

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
    echo "[$(date)] Restarting Jellyfin, NextPVR, and Dispatcharr containers..." >> "$LOG_FILE"

    # Restart specific containers
    echo "Restarting jellyfin container..." >> "$LOG_FILE"
    $DOCKER restart jellyfin >> "$LOG_FILE" 2>&1

    echo "Restarting nextpvr container..." >> "$LOG_FILE"
    $DOCKER restart nextpvr >> "$LOG_FILE" 2>&1

    echo "Restarting dispatcharr container..." >> "$LOG_FILE"
    $DOCKER restart dispatcharr >> "$LOG_FILE" 2>&1

    echo "[$(date)] Restart complete." >> "$LOG_FILE"

else
    echo "[$(date)] Active sessions detected ($ACTIVE_COUNT). Skipping restart." >> "$LOG_FILE"
fi
