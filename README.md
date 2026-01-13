# Jellyfin Rebooter

A shell script that automatically restarts Docker containers when no active Jellyfin sessions are detected.

## Features

- **Configuration File**: Uses a `config.conf` file for easy customization
- **Console Output**: Shows output on console (configurable)
- **Dry Run Mode**: Test the script without actually restarting containers
- **Error Handling**: Comprehensive validation and error messages
- **Log Rotation**: Automatic log file rotation to prevent disk space issues

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

## Security Notes

- Keep your `config.conf` file secure as it contains your Jellyfin API key
- The API key provides access to your Jellyfin server
- Consider setting appropriate file permissions: `chmod 600 config.conf`

## License

This project is licensed under the MIT License - see the LICENSE file for details.
