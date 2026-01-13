#!/bin/sh
set -eu

# ----- CONFIGURATION LOADING -----
CONFIG_FILE="config.conf"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file '$CONFIG_FILE' not found!"
    echo "Please create a config.conf file with your settings."
    echo "You can use the provided config.conf template as a starting point."
    exit 1
fi

# Load configuration from file
if ! . "$(pwd)/$CONFIG_FILE"; then
    echo "ERROR: Failed to load configuration from '$CONFIG_FILE'"
    echo "Current directory: $(pwd)"
    echo "Looking for: $(pwd)/$CONFIG_FILE"
    exit 1
fi

# Validate required configuration
if [ -z "$JELLYFIN_URL" ] || [ "$JELLYFIN_URL" = "https://your.jellyfin.server:8096" ]; then
    echo "ERROR: JELLYFIN_URL is not configured in config.conf"
    echo "Please edit config.conf and set your actual Jellyfin server URL"
    exit 1
fi

if [ -z "$API_KEY" ] || [ "$API_KEY" = "your_jellyfin_api_token_here" ]; then
    echo "ERROR: API_KEY is not configured in config.conf"
    echo "Please edit config.conf and set your actual Jellyfin API token"
    exit 1
fi

if [ -z "$LOG_FILE" ]; then
    echo "ERROR: LOG_FILE is not configured in config.conf"
    exit 1
fi

if [ -z "$DOCKER" ]; then
    echo "ERROR: DOCKER path is not configured in config.conf"
    exit 1
fi

if [ -z "$CONTAINERS" ]; then
    echo "ERROR: CONTAINERS list is not configured in config.conf"
    exit 1
fi

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
    if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
        echo "No active Jellyfin sessions found."
    fi
    
    echo "[$(date)] Restarting containers: $CONTAINERS..." >> "$LOG_FILE"
    if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
        echo "Restarting containers: $CONTAINERS..."
    fi

    # Restart containers from config
    for container in $CONTAINERS; do
        echo "[$(date)] Restarting $container container..." >> "$LOG_FILE"
        if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
            echo "Restarting $container container..."
        fi
        
        if [ "$DRY_RUN" = "true" ]; then
            echo "[$(date)] [DRY RUN] Would restart $container container" >> "$LOG_FILE"
            if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
                echo "[DRY RUN] Would restart $container container"
            fi
        else
            if $DOCKER restart "$container" >> "$LOG_FILE" 2>&1; then
                echo "[$(date)] Successfully restarted $container container" >> "$LOG_FILE"
                if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
                    echo "Successfully restarted $container container"
                fi
            else
                echo "[$(date)] ERROR: Failed to restart $container container" >> "$LOG_FILE"
                if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
                    echo "ERROR: Failed to restart $container container"
                fi
            fi
        fi
    done

    echo "[$(date)] Restart complete." >> "$LOG_FILE"
    if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
        echo "Restart complete."
    fi

else
    echo "[$(date)] Active sessions detected ($ACTIVE_COUNT). Skipping restart." >> "$LOG_FILE"
    if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
        echo "Active sessions detected ($ACTIVE_COUNT). Skipping restart."
    fi
fi
