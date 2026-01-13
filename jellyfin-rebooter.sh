#!/bin/sh
set -eu

# ----- SCRIPT INITIALIZATION -----
echo "=== Jellyfin Rebooter ==="
echo "Starting script execution at $(date)"
echo ""

# ----- CONFIGURATION LOADING -----
CONFIG_FILE="config.conf"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ ERROR: Configuration file '$CONFIG_FILE' not found!"
    echo "   Please create a config.conf file with your settings."
    echo "   You can use the provided config.conf template as a starting point."
    echo ""
    echo "   Current directory: $(pwd)"
    echo "   Expected file: $(pwd)/$CONFIG_FILE"
    exit 1
fi

echo "📁 Loading configuration from: $CONFIG_FILE"

# Load configuration from file
if ! . "$(pwd)/$CONFIG_FILE"; then
    echo "❌ ERROR: Failed to load configuration from '$CONFIG_FILE'"
    echo "   Current directory: $(pwd)"
    echo "   Looking for: $(pwd)/$CONFIG_FILE"
    exit 1
fi

echo "✅ Configuration loaded successfully"
echo ""

# Validate required configuration
if [ -z "$JELLYFIN_URL" ] || [ "$JELLYFIN_URL" = "https://your.jellyfin.server:8096" ]; then
    echo "❌ ERROR: JELLYFIN_URL is not configured in config.conf"
    echo "   Please edit config.conf and set your actual Jellyfin server URL"
    exit 1
fi

if [ -z "$API_KEY" ] || [ "$API_KEY" = "your_jellyfin_api_token_here" ]; then
    echo "❌ ERROR: API_KEY is not configured in config.conf"
    echo "   Please edit config.conf and set your actual Jellyfin API token"
    exit 1
fi

if [ -z "$LOG_FILE" ]; then
    echo "❌ ERROR: LOG_FILE is not configured in config.conf"
    exit 1
fi

if [ -z "$DOCKER" ]; then
    echo "❌ ERROR: DOCKER path is not configured in config.conf"
    exit 1
fi

if [ -z "$CONTAINERS" ]; then
    echo "❌ ERROR: CONTAINERS list is not configured in config.conf"
    exit 1
fi

echo "✅ All required configuration validated"
echo ""

# Display current configuration (sanitized)
echo "📋 Current Configuration:"
echo "   Jellyfin URL: $JELLYFIN_URL"
echo "   API Key: ${API_KEY:0:4}***$(echo ${#API_KEY} | awk '{print substr($0, length($0)-3)}')"
echo "   Log File: $LOG_FILE"
echo "   Docker Path: $DOCKER"
echo "   Containers: $CONTAINERS"
echo "   Console Output: $SHOW_CONSOLE_OUTPUT"
echo "   Dry Run Mode: $DRY_RUN"
echo "   24-Hour Cooldown: $ENABLE_24_HOUR_COOLDOWN"
echo "   Cooldown Hours: $COOLDOWN_HOURS"
echo ""

# ----- 24-HOUR COOLDOWN CHECK -----
if [ "$ENABLE_24_HOUR_COOLDOWN" = "true" ]; then
    echo "⏰ Checking 24-hour cooldown status..."
    
    if [ -f "$COOLDOWN_TRACKING_FILE" ]; then
        LAST_REBOOT_TIME=$(cat "$COOLDOWN_TRACKING_FILE" 2>/dev/null)
        if [ -n "$LAST_REBOOT_TIME" ]; then
            CURRENT_TIME=$(date +%s)
            LAST_REBOOT_EPOCH=$(date -d "$LAST_REBOOT_TIME" +%s 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$LAST_REBOOT_EPOCH" ]; then
                TIME_DIFF=$((CURRENT_TIME - LAST_REBOOT_EPOCH))
                COOLDOWN_SECONDS=$((COOLDOWN_HOURS * 3600))
                
                if [ $TIME_DIFF -lt $COOLDOWN_SECONDS ]; then
                    COOLDOWN_REMAINING=$((COOLDOWN_SECONDS - TIME_DIFF))
                    COOLDOWN_HOURS_REMAINING=$((COOLDOWN_REMAINING / 3600))
                    COOLDOWN_MINUTES_REMAINING=$(((COOLDOWN_REMAINING % 3600) / 60))
                    
                    echo "⏸️  24-hour cooldown active - last reboot was $(date -d "$LAST_REBOOT_TIME")"
                    echo "   Remaining cooldown: ${COOLDOWN_HOURS_REMAINING}h ${COOLDOWN_MINUTES_REMAINING}m"
                    echo "[$(date)] 24-hour cooldown active. Last reboot: $LAST_REBOOT_TIME. Skipping restart." >> "$LOG_FILE"
                    
                    if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
                        echo "24-hour cooldown active. Skipping restart."
                    fi
                    
                    echo ""
                    echo "🏁 Script execution completed at $(date) (cooldown active)"
                    exit 0
                else
                    echo "✅ 24-hour cooldown expired - proceeding with script"
                    echo "[$(date)] 24-hour cooldown expired. Last reboot: $LAST_REBOOT_TIME. Proceeding with restart." >> "$LOG_FILE"
                fi
            else
                echo "⚠️  Warning: Could not parse last reboot time from tracking file"
                echo "   Continuing with script execution"
            fi
        else
            echo "⚠️  Warning: Tracking file exists but is empty"
            echo "   Continuing with script execution"
        fi
    else
        echo "✅ No previous reboot tracking found - proceeding with script"
    fi
    echo ""
else
    echo "⏭️  24-hour cooldown disabled - proceeding with script"
    echo ""
fi

# Show dry-run mode prominently
if [ "$DRY_RUN" = "true" ]; then
    echo "🧪 DRY RUN MODE ENABLED - No containers will actually be restarted"
    echo "   This is a test run to verify the script works correctly."
    echo ""
fi

# ----- LOG ROTATION -----
if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE") -gt $MAX_LOG_SIZE ]; then
    echo "🔄 Rotating log file (size: $(stat -c%s "$LOG_FILE") bytes)"
    mv "$LOG_FILE" "${LOG_FILE}.1"
    echo "✅ Log file rotated successfully"
fi

# ----- VALIDATE DOCKER BINARY -----
echo "🐳 Validating Docker installation..."
if [ ! -x "$DOCKER" ]; then
    echo "❌ ERROR: Docker binary not found at $DOCKER"
    echo "   Please check that Docker is installed and the path is correct in config.conf"
    exit 1
fi

# Test Docker functionality
if ! $DOCKER version >/dev/null 2>&1; then
    echo "❌ ERROR: Docker is not running or accessible"
    echo "   Please ensure Docker daemon is running"
    exit 1
fi

echo "✅ Docker validation successful"
echo ""

# ----- VALIDATE CONTAINERS -----
echo "📦 Validating containers..."
for container in $CONTAINERS; do
    if ! $DOCKER inspect "$container" >/dev/null 2>&1; then
        echo "❌ ERROR: Container '$container' not found"
        echo "   Please check the container name in config.conf"
        exit 1
    fi
done
echo "✅ All containers validated successfully"
echo ""

# ----- NETWORK CONNECTIVITY CHECK -----
echo "🌐 Testing network connectivity to Jellyfin server..."
# Test basic connectivity
if ! curl -s --connect-timeout 10 --max-time 15 -I "$JELLYFIN_URL" >/dev/null 2>&1; then
    echo "❌ ERROR: Cannot reach Jellyfin server at $JELLYFIN_URL"
    echo "   Please check:"
    echo "   - Server URL is correct"
    echo "   - Server is running"
    echo "   - Network connectivity"
    echo "   - Firewall settings"
    exit 1
fi

echo "✅ Network connectivity to Jellyfin server confirmed"
echo ""

# ----- CHECK JELLYFIN API ACCESSIBILITY -----
echo "🔑 Testing Jellyfin API access..."
API_TEST=$(curl -s --connect-timeout 10 --max-time 15 -H "X-Emby-Token: $API_KEY" "$JELLYFIN_URL/System/Info" 2>&1)
if [ $? -ne 0 ]; then
    echo "❌ ERROR: Cannot connect to Jellyfin API"
    echo "   Please check:"
    echo "   - API key is correct"
    echo "   - Server is accessible"
    echo "   - API endpoint is valid"
    exit 1
fi

# Check if API returned an error (simple JSON validation)
if ! echo "$API_TEST" | grep -q '"Version\|ServerName\|Id"'; then
    echo "❌ ERROR: Invalid API response format"
    echo "   Response: $API_TEST"
    exit 1
fi

echo "✅ Jellyfin API access confirmed"
echo ""

echo "[$(date)] Checking Jellyfin activity..." >> "$LOG_FILE"

# ----- GET SESSIONS -----
echo "📡 Checking Jellyfin sessions..."
SESSIONS=$(curl -s --connect-timeout 10 --max-time 15 -H "X-Emby-Token: $API_KEY" "$JELLYFIN_URL/Sessions" 2>&1)

if [ $? -ne 0 ]; then
    echo "❌ ERROR: Failed to retrieve Jellyfin sessions"
    echo "   Please check:"
    echo "   - Jellyfin server is running"
    echo "   - API key is correct"
    echo "   - Network connectivity"
    echo "   - API response: $SESSIONS"
    exit 1
fi

# Check if API returned an error (simple JSON validation)
if ! echo "$SESSIONS" | grep -q '"DeviceId\|DeviceName\|UserName"'; then
    echo "❌ ERROR: Invalid API response format"
    echo "   Response: $SESSIONS"
    exit 1
fi

ACTIVE_COUNT=$(echo "$SESSIONS" | grep -o '"DeviceId"' | wc -l)

echo "📊 Session Analysis:"
echo "   Total active sessions: $ACTIVE_COUNT"
if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
    echo "   $ACTIVE_COUNT active sessions detected"
fi
echo "[$(date)] Active sessions: $ACTIVE_COUNT" >> "$LOG_FILE"

# ----- DECISION LOGIC -----
if [ "$ACTIVE_COUNT" -eq 0 ]; then
    echo "✅ No active sessions - proceeding with container restart"
    echo "[$(date)] No active Jellyfin sessions found. Proceeding with restart." >> "$LOG_FILE"
    
    if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
        echo "No active Jellyfin sessions found. Proceeding with restart."
    fi
    
    echo ""
    echo "🚀 Starting container restart process..."
    echo "   Containers to restart: $CONTAINERS"
    echo "[$(date)] Restarting containers: $CONTAINERS..." >> "$LOG_FILE"
    
    if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
        echo "Restarting containers: $CONTAINERS..."
    fi

    # Restart containers from config
    SUCCESS_COUNT=0
    FAILURE_COUNT=0
    
    for container in $CONTAINERS; do
        echo ""
        echo "🔄 Processing container: $container"
        echo "[$(date)] Restarting $container container..." >> "$LOG_FILE"
        
        if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
            echo "Restarting $container container..."
        fi
        
        if [ "$DRY_RUN" = "true" ]; then
            echo "🧪 [DRY RUN] Would restart $container container" >> "$LOG_FILE"
            if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
                echo "🧪 [DRY RUN] Would restart $container container"
            fi
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            # Check if container is running before attempting restart
            if ! $DOCKER ps --format "{{.Names}}" | grep -q "^$container$"; then
                echo "⚠️  Container '$container' is not running, skipping restart" >> "$LOG_FILE"
                if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
                    echo "⚠️  Container '$container' is not running, skipping restart"
                fi
                continue
            fi
            
            if $DOCKER restart "$container" >> "$LOG_FILE" 2>&1; then
                echo "✅ Successfully restarted $container container" >> "$LOG_FILE"
                if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
                    echo "✅ Successfully restarted $container container"
                fi
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            else
                echo "❌ ERROR: Failed to restart $container container" >> "$LOG_FILE"
                if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
                    echo "❌ ERROR: Failed to restart $container container"
                fi
                FAILURE_COUNT=$((FAILURE_COUNT + 1))
            fi
        fi
    done

    echo ""
    echo "📈 Restart Summary:"
    echo "   Successful restarts: $SUCCESS_COUNT"
    if [ $FAILURE_COUNT -gt 0 ]; then
        echo "   Failed restarts: $FAILURE_COUNT"
    fi
    echo "   Total containers processed: $SUCCESS_COUNT"
    
    echo "[$(date)] Restart process completed. Success: $SUCCESS_COUNT, Failed: $FAILURE_COUNT" >> "$LOG_FILE"
    if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
        echo "Restart process completed."
    fi
    
    # Update cooldown tracking file on successful restart
    if [ "$ENABLE_24_HOUR_COOLDOWN" = "true" ] && [ $SUCCESS_COUNT -gt 0 ]; then
        echo "⏰ Updating 24-hour cooldown tracking..."
        CURRENT_TIMESTAMP=$(date -Iseconds)
        echo "$CURRENT_TIMESTAMP" > "$COOLDOWN_TRACKING_FILE"
        echo "✅ Cooldown tracking updated: $CURRENT_TIMESTAMP"
        echo "[$(date)] 24-hour cooldown tracking updated: $CURRENT_TIMESTAMP" >> "$LOG_FILE"
    fi

else
    echo "⏸️  Active sessions detected - skipping container restart for user safety"
    echo "[$(date)] Active sessions detected ($ACTIVE_COUNT). Skipping restart for user safety." >> "$LOG_FILE"
    
    if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
        echo "Active sessions detected ($ACTIVE_COUNT). Skipping restart for user safety."
    fi
fi

echo ""
echo "🏁 Script execution completed at $(date)"
