# Jellyfin Rebooter

A robust shell script that automatically restarts Docker containers when no active Jellyfin sessions are detected.

## Features

- **Configuration File**: Uses a `config.conf` file for easy customization
- **Console Output**: Shows output on console (configurable)
- **Dry Run Mode**: Test the script without actually restarting containers
- **Error Handling**: Comprehensive validation and error messages
- **Log Rotation**: Automatic log file rotation to prevent disk space issues
- **Container Health Checks**: Verify containers are running after restart
- **Retry Logic**: Automatic retry on restart failures
- **Email Notifications**: Get notified when restarts occur or fail
- **Performance Metrics**: Track script performance and success rates
- **API Rate Limiting**: Prevent API abuse with configurable rate limits
- **Structured Logging**: Enhanced logging with timestamps and severity levels
- **24-Hour Cooldown**: Configurable cooldown period to prevent excessive restarts

## Quick Start

1. **Configure the script**:
   Edit `config.conf` and replace the placeholder values with your actual settings:
   ```bash
   # Edit the configuration file
   nano config.conf
   ```

2. **Make the script executable**:
   ```bash
   chmod +x jellyfin-rebooter.sh
   ```

3. **Test in dry-run mode**:
   ```bash
   ./jellyfin-rebooter.sh
   ```
   (The script will show what it would do without actually restarting containers)

4. **Enable actual restarts**:
   Set `DRY_RUN="false"` in `config.conf`

## Configuration

Edit `config.conf` to customize the script behavior:

### Required Settings
- `JELLYFIN_URL`: Your Jellyfin server URL (e.g., `https://your.server:8096`)
- `API_KEY`: Your Jellyfin API token
- `LOG_FILE`: Path where logs will be written
- `DOCKER`: Path to Docker binary
- `CONTAINERS`: Space-separated list of container names to restart

### Optional Settings
- `MAX_LOG_SIZE`: Maximum log file size in bytes (default: 500000)
- `SHOW_CONSOLE_OUTPUT`: Show output on console (`true`/`false`, default: `true`)
- `DRY_RUN`: Test mode without actual restarts (`true`/`false`, default: `false`)

### Advanced Features

#### Container Health Checks
- `ENABLE_HEALTH_CHECK`: Enable container health verification after restart (`true`/`false`, default: `true`)
- `HEALTH_CHECK_DELAY`: Seconds to wait before health check (default: 5)
- `HEALTH_CHECK_RETRIES`: Number of health check attempts (default: 3)

#### Retry Logic
- `ENABLE_RETRY_LOGIC`: Enable automatic retry on restart failures (`true`/`false`, default: `true`)
- `MAX_RESTART_ATTEMPTS`: Maximum restart attempts per container (default: 3)
- `RETRY_DELAY`: Seconds to wait between retry attempts (default: 2)

#### Email Notifications
- `ENABLE_EMAIL_NOTIFICATIONS`: Enable email notifications (`true`/`false`, default: `false`)
- `NOTIFICATION_EMAIL`: Email address for notifications

#### Performance Monitoring
- `ENABLE_METRICS`: Enable performance metrics collection (`true`/`false`, default: `false`)
- `METRICS_FILE`: Prometheus-style metrics file path (default: `/tmp/jellyfin_rebooter_metrics.prom`)

#### API Rate Limiting
- `API_RATE_LIMIT`: Maximum API calls per minute (default: 10)
- `API_CALL_COUNT_FILE`: File to track API call counts (default: `/tmp/jellyfin_api_calls.txt`)

#### Container Dependencies (Future Enhancement)
- `CONTAINER_DEPENDENCIES`: Define container startup order (format: `"container1:dep1,dep2 container2:dep3"`)

## Usage Examples

### Check current configuration
```bash
./jellyfin-rebooter.sh
```

### Test with dry-run mode enabled
```bash
# Edit config.conf and set DRY_RUN="true"
./jellyfin-rebooter.sh
```

### Run with actual container restarts
```bash
# Edit config.conf and set DRY_RUN="false"
./jellyfin-rebooter.sh
```

### Run silently (log file only)
```bash
# Edit config.conf and set SHOW_CONSOLE_OUTPUT="false"
./jellyfin-rebooter.sh
```

### Enable email notifications
```bash
# Edit config.conf:
ENABLE_EMAIL_NOTIFICATIONS="true"
NOTIFICATION_EMAIL="your-email@example.com"
./jellyfin-rebooter.sh
```

### Enable performance monitoring
```bash
# Edit config.conf:
ENABLE_METRICS="true"
METRICS_FILE="/var/log/jellyfin_rebooter_metrics.prom"
./jellyfin-rebooter.sh
```

### Configure retry logic and health checks
```bash
# Edit config.conf:
ENABLE_RETRY_LOGIC="true"
MAX_RESTART_ATTEMPTS=5
RETRY_DELAY=3
ENABLE_HEALTH_CHECK="true"
HEALTH_CHECK_DELAY=10
HEALTH_CHECK_RETRIES=2
./jellyfin-rebooter.sh
```

### Enable API rate limiting
```bash
# Edit config.conf:
API_RATE_LIMIT=5
API_CALL_COUNT_FILE="/tmp/jellyfin_api_calls.txt"
./jellyfin-rebooter.sh
```

## Setting up API Key

To get your Jellyfin API key:

1. Open Jellyfin web interface
2. Go to Settings → Advanced
3. Click "Show API Keys"
4. Copy your API key and paste it into `config.conf`

## Scheduling with Cron

To run the script automatically, add a cron job:

```bash
# Edit crontab
crontab -e

# Add a line to run every 30 minutes
*/30 * * * * /path/to/jellyfin-rebooter.sh
```

## Troubleshooting

### Common Issues

1. **"Configuration file not found"**
   - Make sure `config.conf` exists in the same directory as the script

2. **"JELLYFIN_URL is not configured"**
   - Edit `config.conf` and set your actual Jellyfin server URL

3. **"API_KEY is not configured"**
   - Edit `config.conf` and set your actual Jellyfin API token

4. **"Docker binary not found"**
   - Check that Docker is installed and update the `DOCKER` path in `config.conf`

5. **"Failed to retrieve Jellyfin sessions"**
   - Verify your Jellyfin URL and API key are correct
   - Check that Jellyfin is running and accessible

### Log Files

The script writes detailed logs to the file specified in `LOG_FILE`. Check this file if you encounter issues.

### Performance Metrics

When `ENABLE_METRICS="true"`, the script records performance metrics to the specified metrics file in Prometheus format:

- `jellyfin_rebooter_script_duration_seconds`: Total script execution time
- `jellyfin_rebooter_success_count`: Number of successful container restarts
- `jellyfin_rebooter_failure_count`: Number of failed container restarts
- `jellyfin_rebooter_total_containers`: Total number of containers processed
- `jellyfin_rebooter_script_exit_code`: Script exit code (0 = success)

### Monitoring and Alerting

#### Email Notifications
Configure email notifications to get alerts when:
- Containers are successfully restarted
- Restart failures occur
- Script execution completes

#### Log Analysis
The structured logging format includes:
- Timestamps in ISO 8601 format
- Log levels (INFO, WARN, ERROR)
- Detailed event descriptions

Example log entry:
```
[2024-01-15T14:30:25+00:00] [INFO] Successfully restarted jellyfin
```

#### Metrics Integration
The Prometheus-style metrics can be integrated with:
- Grafana dashboards
- Prometheus monitoring
- Custom alerting systems

Example metrics file content:
```
jellyfin_rebooter_script_duration_seconds 45 1705321825
jellyfin_rebooter_success_count 3 1705321825
jellyfin_rebooter_failure_count 0 1705321825
jellyfin_rebooter_total_containers 3 1705321825
jellyfin_rebooter_script_exit_code 0 1705321825
```

## Security Notes

- Keep your `config.conf` file secure as it contains your Jellyfin API key
- The API key provides access to your Jellyfin server
- Consider setting appropriate file permissions: `chmod 600 config.conf`

## License

This project is licensed under the MIT License - see the LICENSE file for details.
