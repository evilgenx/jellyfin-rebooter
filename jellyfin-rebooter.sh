#!/bin/sh
set -eu

# ----- SCRIPT INITIALIZATION -----
SCRIPT_START_TIME=$(date +%s)
SCRIPT_PID=$$

echo "=== Jellyfin Rebooter ==="
echo "Starting script execution at $(date)"
echo "Script PID: $SCRIPT_PID"
echo ""

# ----- CONFIGURATION LOADING -----
CONFIG_FILE="jellyfin-rebooter.conf"

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

# Set default values for optional parameters
ENABLE_EMAIL_NOTIFICATIONS="${ENABLE_EMAIL_NOTIFICATIONS:-false}"
NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-}"
ENABLE_HEALTH_CHECK="${ENABLE_HEALTH_CHECK:-true}"
HEALTH_CHECK_DELAY="${HEALTH_CHECK_DELAY:-5}"
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-3}"
ENABLE_RETRY_LOGIC="${ENABLE_RETRY_LOGIC:-true}"
MAX_RESTART_ATTEMPTS="${MAX_RESTART_ATTEMPTS:-3}"
RETRY_DELAY="${RETRY_DELAY:-2}"
ENABLE_METRICS="${ENABLE_METRICS:-false}"
METRICS_FILE="${METRICS_FILE:-/tmp/jellyfin_rebooter_metrics.prom}"
CONTAINER_DEPENDENCIES="${CONTAINER_DEPENDENCIES:-}"
API_RATE_LIMIT="${API_RATE_LIMIT:-10}"
API_CALL_COUNT_FILE="${API_CALL_COUNT_FILE:-/tmp/jellyfin_api_calls.txt}"

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

# Validate container names format
if ! echo "$CONTAINERS" | grep -qE '^[a-zA-Z0-9_-]+(\s+[a-zA-Z0-9_-]+)*$'; then
    echo "❌ ERROR: Invalid container names format in CONTAINERS"
    echo "   Container names should contain only letters, numbers, underscores, and hyphens"
    exit 1
fi

echo "✅ All required configuration validated"
echo ""

# Enhanced logging function with structured format
log_event() {
    local level="$1"
    local message="$2"
    local timestamp=$(date -Iseconds)
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
        echo "[$level] $message"
    fi
}

# Performance metrics function
record_metric() {
    local metric_name="$1"
    local metric_value="$2"
    if [ "$ENABLE_METRICS" = "true" ] && [ -n "$METRICS_FILE" ]; then
        local timestamp=$(date +%s)
        echo "$metric_name $metric_value $timestamp" >> "$METRICS_FILE"
    fi
}

# Email notification function
send_notification() {
    local subject="$1"
    local message="$2"
    if [ "$ENABLE_EMAIL_NOTIFICATIONS" = "true" ] && [ -n "$NOTIFICATION_EMAIL" ]; then
        if command -v mail >/dev/null 2>&1; then
            echo "$message" | mail -s "$subject" "$NOTIFICATION_EMAIL"
            log_event "INFO" "Email notification sent to $NOTIFICATION_EMAIL"
        else
            log_event "WARN" "Mail command not available, cannot send email notification"
        fi
    fi
}

# API rate limiting function
check_api_rate_limit() {
    if [ "$API_RATE_LIMIT" -gt 0 ]; then
        local current_time=$(date +%s)
        local minute_key=$(date -d "@$current_time" +"%Y%m%d%H%M")
        
        if [ -f "$API_CALL_COUNT_FILE" ]; then
            # Clean old entries (older than 1 minute)
            awk -v cutoff="$minute_key" -F: '$1 >= cutoff' "$API_CALL_COUNT_FILE" > "${API_CALL_COUNT_FILE}.tmp" && mv "${API_CALL_COUNT_FILE}.tmp" "$API_CALL_COUNT_FILE"
            
            # Count calls in current minute
            local current_calls=$(grep "^$minute_key:" "$API_CALL_COUNT_FILE" | wc -l)
            
            if [ "$current_calls" -ge "$API_RATE_LIMIT" ]; then
                log_event "WARN" "API rate limit reached ($API_RATE_LIMIT calls/minute), waiting..."
                sleep 60
            fi
        fi
        
        # Record this API call
        echo "$minute_key:$current_time" >> "$API_CALL_COUNT_FILE"
    fi
}

# Container health check function
check_container_health() {
    local container="$1"
    local max_retries="$2"
    local delay="$3"
    local attempt=1
    
    while [ $attempt -le $max_retries ]; do
        if $DOCKER ps --format "{{.Names}}" | grep -q "^$container$"; then
            log_event "INFO" "Container $container is healthy after restart"
            return 0
        fi
        
        if [ $attempt -lt $max_retries ]; then
            log_event "INFO" "Health check attempt $attempt/$max_retries for $container failed, retrying in ${delay}s..."
            sleep $delay
        fi
        attempt=$((attempt + 1))
    done
    
    log_event "ERROR" "Container $container failed health check after $max_retries attempts"
    return 1
}

# Enhanced restart function with retry logic
restart_container_with_retry() {
    local container="$1"
    local max_attempts="$2"
    local retry_delay="$3"
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_event "INFO" "Restart attempt $attempt/$max_attempts for container $container"
        
        if $DOCKER restart "$container" >> "$LOG_FILE" 2>&1; then
            log_event "INFO" "Successfully restarted $container"
            
            # Check health if enabled
            if [ "$ENABLE_HEALTH_CHECK" = "true" ]; then
                sleep $HEALTH_CHECK_DELAY
                if check_container_health "$container" "$HEALTH_CHECK_RETRIES" "$HEALTH_CHECK_DELAY"; then
                    return 0
                else
                    log_event "ERROR" "Container $container health check failed after restart"
                    return 1
                fi
            fi
            return 0
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            log_event "WARN" "Restart attempt $attempt failed for $container, waiting ${retry_delay}s before retry..."
            sleep $retry_delay
        fi
        attempt=$((attempt + 1))
    done
    
    log_event "ERROR" "Failed to restart $container after $max_attempts attempts"
    return 1
}

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
echo "   Email Notifications: $ENABLE_EMAIL_NOTIFICATIONS"
echo "   Health Check: $ENABLE_HEALTH_CHECK (delay: ${HEALTH_CHECK_DELAY}s, retries: $HEALTH_CHECK_RETRIES)"
echo "   Retry Logic: $ENABLE_RETRY_LOGIC (max attempts: $MAX_RESTART_ATTEMPTS, delay: ${RETRY_DELAY}s)"
echo "   Performance Metrics: $ENABLE_METRICS"
echo ""

# Log script start after functions are defined
log_event "INFO" "=== Jellyfin Rebooter Script Started ==="
log_event "INFO" "Script PID: $SCRIPT_PID"

# ----- CRITICAL SAFETY CHECK: JELLYFIN SESSIONS -----
echo "🔒 CRITICAL SAFETY CHECK: Verifying no active Jellyfin sessions..."
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

# CRITICAL: NEVER restart if there are active sessions, regardless of cooldown status
if [ "$ACTIVE_COUNT" -gt 0 ]; then
    echo "🔒 CRITICAL SAFETY: Active sessions detected - ABORTING ALL RESTARTS"
    echo "   This prevents interrupting users who are actively watching content"
    echo "[$(date)] CRITICAL SAFETY: Active sessions ($ACTIVE_COUNT) detected. Aborting all restarts to protect users." >> "$LOG_FILE"
    
    if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
        echo "Active sessions detected ($ACTIVE_COUNT). Skipping restart for user safety."
    fi
    
    echo ""
    echo "🏁 Script execution completed at $(date) (user safety protection active)"
    exit 0
fi

echo "✅ No active sessions detected - proceeding with safety checks"
echo "[$(date)] No active Jellyfin sessions found. Proceeding with safety checks." >> "$LOG_FILE"

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

# ----- CONTAINER RESTART PROCESS -----
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
        
        # Use enhanced restart function with retry logic and health checks
        if [ "$ENABLE_RETRY_LOGIC" = "true" ]; then
            if restart_container_with_retry "$container" "$MAX_RESTART_ATTEMPTS" "$RETRY_DELAY"; then
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            else
                FAILURE_COUNT=$((FAILURE_COUNT + 1))
            fi
        else
            # Use basic restart without retry logic
            if $DOCKER restart "$container" >> "$LOG_FILE" 2>&1; then
                echo "✅ Successfully restarted $container container" >> "$LOG_FILE"
                if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
                    echo "✅ Successfully restarted $container container"
                fi
                
                # Check health if enabled
                if [ "$ENABLE_HEALTH_CHECK" = "true" ]; then
                    sleep $HEALTH_CHECK_DELAY
                    if check_container_health "$container" "$HEALTH_CHECK_RETRIES" "$HEALTH_CHECK_DELAY"; then
                        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                    else
                        FAILURE_COUNT=$((FAILURE_COUNT + 1))
                    fi
                else
                    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                fi
            else
                echo "❌ ERROR: Failed to restart $container container" >> "$LOG_FILE"
                if [ "$SHOW_CONSOLE_OUTPUT" = "true" ]; then
                    echo "❌ ERROR: Failed to restart $container container"
                fi
                FAILURE_COUNT=$((FAILURE_COUNT + 1))
            fi
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

# Calculate and record performance metrics
SCRIPT_END_TIME=$(date +%s)
SCRIPT_DURATION=$((SCRIPT_END_TIME - SCRIPT_START_TIME))
TOTAL_CONTAINERS=$(echo "$CONTAINERS" | wc -w)

log_event "INFO" "Script execution completed. Duration: ${SCRIPT_DURATION}s, Success: $SUCCESS_COUNT, Failed: $FAILURE_COUNT, Total: $TOTAL_CONTAINERS"

# Record performance metrics
if [ "$ENABLE_METRICS" = "true" ]; then
    record_metric "jellyfin_rebooter_script_duration_seconds" "$SCRIPT_DURATION"
    record_metric "jellyfin_rebooter_success_count" "$SUCCESS_COUNT"
    record_metric "jellyfin_rebooter_failure_count" "$FAILURE_COUNT"
    record_metric "jellyfin_rebooter_total_containers" "$TOTAL_CONTAINERS"
    record_metric "jellyfin_rebooter_script_exit_code" "0"
    log_event "INFO" "Performance metrics recorded to $METRICS_FILE"
fi

# Send email notification if enabled
if [ "$ENABLE_EMAIL_NOTIFICATIONS" = "true" ] && [ $SUCCESS_COUNT -gt 0 ]; then
    local notification_subject="Jellyfin Rebooter: $SUCCESS_COUNT containers restarted successfully"
    local notification_message="Script completed successfully at $(date)
Duration: ${SCRIPT_DURATION}s
Successful restarts: $SUCCESS_COUNT
Failed restarts: $FAILURE_COUNT
Total containers processed: $TOTAL_CONTAINERS"
    send_notification "$notification_subject" "$notification_message"
fi

echo ""
echo "🏁 Script execution completed at $(date)"
echo "⏱️  Total execution time: ${SCRIPT_DURATION}s"
echo "📊 Summary: $SUCCESS_COUNT successful, $FAILURE_COUNT failed out of $TOTAL_CONTAINERS containers"
