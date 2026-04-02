# VPS Security Guide

## Updating your system
- `sudo apt update` - Update the package list.
- `sudo apt upgrade` - Upgrade the software packages.

## Create and use an SSH key
- `ssh-keygen -t ed25519` - Generate an SSH key pair on your local machine.
- `ssh-copy-id -i ~/.ssh/id_ed25519.pub username@server_ip` - Deploy the public key to the VPS.

## Changing the default SSH listening port
- `sudo nano /etc/ssh/sshd_config` - Modify the service configuration file.
- `sudo cat /etc/services` - View the ports currently assigned on the system.
- `sudo systemctl restart sshd` - Restart the SSH service.
- `sudo reboot` - Reboot the VPS to apply changes.
- `sudo nano /lib/systemd/system/ssh.socket` - Update the ListenStream for Ubuntu 24.04 and later.
- `sudo systemctl daemon-reload` - Reload systemd manager configuration.
- `sudo systemctl restart ssh.socket` - Restart the SSH socket service.
- `ssh username@IPv4_VPS -p NewPortNumber` - Connect to the server using the new SSH port.

## Creating a user with restricted rights
- `adduser <username>` - Create a new standard user.
- `usermod -aG sudo <username>` - Grant the user administrative (sudo) privileges.

## Configuring the internal firewall (iptables)
- `iptables -L` - Verify active firewall rules.

## Installing Fail2ban
- `sudo apt install fail2ban` - Install the Fail2ban package.
- `sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local` - Create a local configuration file.
- `sudo nano /etc/fail2ban/jail.local` - Open the local configuration file for editing.
- `sudo systemctl restart fail2ban` - Restart the Fail2ban service using systemctl.
- `sudo service fail2ban restart` - Restart the Fail2ban service using legacy method.

## Configuring the OVHcloud Network Firewall
- (Managed via the OVHcloud Control Panel; no local commands)

## Backing up your system and your data
- (Use the backup/snapshot tools available in the OVHcloud Control Panel)
