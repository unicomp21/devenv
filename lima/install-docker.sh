#!/bin/bash
set -e

# Remove any old Docker installations
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    sudo apt-get remove -y $pkg || true
done

# Add Docker's official GPG key
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add the repository to Apt sources
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker packages
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add current user to docker group
sudo usermod -aG docker $USER

# Configure Docker daemon with DNS settings
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json <<EOF
{
    "dns": ["8.8.8.8", "1.1.1.1"]
}
EOF

# Configure system DNS
sudo cp /etc/resolv.conf /etc/resolv.conf.backup
echo "nameserver 8.8.8.8
nameserver 1.1.1.1" | sudo tee /etc/resolv.conf

# Ensure systemd-resolved is running
sudo systemctl start systemd-resolved
sudo systemctl enable systemd-resolved

# Start/restart Docker service
sudo systemctl restart docker

# Activate the new group membership in current session
if [ -n "$SUDO_USER" ]; then
    # If script is run with sudo, get the actual user
    REAL_USER=$SUDO_USER
else
    REAL_USER=$USER
fi

# Print success message
echo "Docker has been installed successfully!"
echo "Your user ($REAL_USER) has been added to the docker group."
echo "DNS configuration has been updated."

# Test DNS resolution
echo "Testing DNS resolution..."
ping -c 1 registry-1.docker.io || true

# Activate new group membership without logging out
exec sg docker -c 'echo "Docker group membership activated. You can now run Docker commands." && bash'

git config --global user.email "jdavis@pcprogramming.com"
git config --global user.name "John Davis"
