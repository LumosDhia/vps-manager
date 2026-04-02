# VPS Home Server Roadmap

This roadmap outlines the development of a lightweight, interactive management script to deploy and manage a Docker-based home server on Ubuntu VPS.

## Phase 0: Aesthetics & UI Constants
- **Visual Identity**: Implemented the **Catppuccin Latte** palette using high-fidelity TrueColor ANSI escapes.
- **Modern UI Elements**: Used a minimalist header with a nerd-font style separator (`──────────────────`).
- **Standardized Messaging**: Defined specific color mappings for logic states (e.g., Mauve for Headers, Green for Success, Red for Errors).

## Phase 1: Environment Validation & User Pre-flight
- **System Sanity Check**: 
  - Validate OS (Ubuntu 22.04+ / Debian 12+) and Architecture (x86_64/arm64).
  - Check for mandatory dependencies: `curl`, `git`, `jq`, `gawk`, `openssl`.
- **The "Deployment User" Logic**:
  - **Context Aware**: If run as `root`, strictly enforce the creation or selection of a non-root `sudo` user for actual deployment.
  - **Auto-Transition**: Script should `sudo -u <user> -H $0 --child` to re-execute itself under the correct context if permission switching is needed.
- **Modular Bootstrap**: Initialize a `manager.log` and a hidden state file `.vps_state.json` to track deployment progress.

## Phase 2: Core Infrastructure (The Foundation)
- **Docker Engine 2.0**: Official repository integration (no `apt install docker.io`) with Docker Compose V2.
- **Internal Networking**: Create a dedicated Docker network (e.g., `proxy-nw`) to isolate services from the public internet.
- **Mandatory Reverse Proxy**: 
  - Deploy **Nginx Proxy Manager** or **Caddy** as the "Entry Gate".
  - Logic to auto-configure SSL via Let's Encrypt (DNS-01 or HTTP-01 challenges).
- **Firewall Sync**: Logic to automatically open only required ports (80, 443, and the custom SSH port) using `ufw` or `iptables`.

## Phase 3: The Interactive Engine & App Store
- **State Management**: Use a JSON-based database for installed services to avoid duplicate deployments or port conflicts.
- **Service Templating**: 
  - Logic to inject variables into boilerplate `docker-compose.yml` snippets.
  - **Lightweight First**: Default to Alpine-based images where possible.
- **Image Selection Policy**: Prioritize Alpine-based images (e.g., `linuxserver.io` images) to minimize VPS resource usage.
- **Persistent Storage**: Implement a standardized directory structure (e.g., `~/server-data/app_name`) for configs and media.

## Phase 4: Service Catalog (Initial Suites)
- **Tier 1: Management**: Homarr (Dashboard), Portainer (Visualizer).
- **Tier 2: Personal Cloud**: FileBrowser, Nextcloud (Lightweight version).
- **Tier 3: Media**: Jellyfin (Alpine), Prowlarr.
- **Tier 4: Security Lab**: 
  - Customized Kali Linux container with web-based VNC access.
  - Logic to toggle the lab "On/Off" to save RAM.

## Phase 5: Maintenance, Monitoring & Guardrails
- **Health Checks**: A "Doctor" command to scan for container restarts, high RAM usage, or expiring SSL certificates.
- **Prune & Clean**: Smart cleanup that removes unused images but preserves "Volume Orphans" unless explicitly told to purge.
- **Backup Strategy**: 
  - Implement `restic` or `rclone` integration.
  - One-click backup of `~/server-data` to an external S3 or SFTP target.
- **Security Hardening**:
  - Fail2Ban jail templates for Docker-exposed services.
  - Post-deployment lockdown: Optionally strip `sudo` from the deployment user.

---

### Script CLI Structure
```bash
./manager.sh [command]

Commands:
  up       - Enter the interactive deployment menu
  down     - Stop and remove a specific service
  status   - Show visual health dashboard
  backup   - Run the automated backup task
  doctor   - Run system diagnostic and security audit
  clean    - Prune unused docker assets
```

### Planned Project Structure
```text
home-server-manager/
├── manager.sh      # Main interactive script
├── configs/        # App-specific environment templates
└── data/           # Persistent volumes for apps
```
