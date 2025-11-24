# jellyfin-rebooter
This is a script I've created to solve a particular problem - run as a Cron job on an Asustor NAS to reboot on a schedule. See the README file for more details.

Welcome to the Jellyfin Reebooter script!

This script was created for a very specific purpose on a very particular setup. I run Jellyfin on an ASUSTOR NAS with 1 gigabyte of RAM, which is not upgradable. While this setup works, Jellyfin can sometimes use a little bit more RAM than I'm comfortable with after playing media. I also use Caddy to manage the reverse proxy as that handles websockets better than the Asustor stuff. This allows me to do Sync Play remotely. Because of this, I manage the Docker containers via Portainer. The purpose of this script is to run as a cron job to regularly restart the Jellyfin services so that the RAM usage doesn't get too out of control.

This script does a little bit more than just blindly reboot everything. It hooks into the Jellyfin API to ensure nobody has an active session. If that's the case, it reboots the Portainer containers. IF there is an active session, it leaves it be. This way I can reboot the containers regularly, but try to avoid interrupting any active sessions.

The basic setup process is this:

- Create a new API key in your Jellyfin instance
- Get the Jellyfin token and put it where it says "JELLYFIN_TOKEN_HERE"
- Get your Jellyfin URL and put it where it says "JELLYFIN_URL_HERE"
- Nominate where you want the log files to be saved where it says "LOG_DIRECTORY_HERE" - this is somewhere where the script has write access
- Log into your NAS via SSH
- Use your favourite text editor to create a new script file and paste the script in
- Set appropriate file permissions
- Use crontab to create a schedule to run the scipt
- That's it!

This script is to solve a particular problem using a particular setup. YMMV. Hopefully somebody other than myself finds this useful.
