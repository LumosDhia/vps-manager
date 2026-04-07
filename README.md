![Logo](assets/logo.png)

# VPS Home Server Manager

This toolkit is an interactive bash script to deploy and manage web services on personal VPS (Ubuntu or Debian). It uses Docker as the core engine and provides a Catppuccin themed CLI for visibility.

## What is this for?

Setting up a home server on a cloud provider usually involves manual firewall configuration, reverse proxy setup, and persistent data management. This project automates those steps:

- Automated system bootstrapping (Docker, Network, Firewall).
- App store interface to deploy pre-configured services (Home dashboards, Cloud storage, Media servers).
- Built-in reverse proxy (Nginx Proxy Manager) with automatic SSL provisioning.
- Real-time health dashboard for monitoring container status and system resources.
- Global security auditing (Doctor command) to check for resource leaks and SSL expiry.

## Prerequisites

- Operating System: Ubuntu 22.04+ or Debian 12+.
- Permissions: Must be run with a sudo-capable user.
- Packages: git, curl, jq, gawk, openssl.

## Quick Start

Download the repository and run the entry script:

```bash
git clone https://github.com/LumosDhia/vps-setup.git
cd vps-setup
chmod +x manager.sh
./manager.sh
```

Follow the menu instructions. It is recommended to run "Initialize VPS" first to set up the foundation.

## Project Architecture

- **manager.sh**: Entry point for the CLI.
- **lib/**: Modularized logic for UI, infrastructure, services, and command handling.
- **docker-files/**: Supplemental configuration and custom Dockerfiles for integrated apps.
- **~/.config/personal-server/**: Default path for local persistent configs.

## Features

- **State Persistence**: Service data is tracked in a JSON-based local database.
- **Parallel Pulls**: Images are fetched in the background to speed up bulk deployments.
- **Firewall Integration**: Automatically syncs service ports with UFW rules.
