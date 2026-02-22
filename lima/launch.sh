#!/bin/bash
set -e
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
USER_NAME=$(whoami)

# Set LIMA_HOME to VM directory for all persistence concerns
# Check if /Volumes/MacOS exists, otherwise use root drive
if [ -d "/Volumes/MacOS" ]; then
    export LIMA_HOME="/Volumes/MacOS/Lima/VM"
else
    # Fall back to root drive (home directory)
    export LIMA_HOME="$HOME/.lima/VM"
fi
echo "Setting LIMA_HOME to: $LIMA_HOME"

# Ensure SSH agent is running and key is loaded
if [ -z "$SSH_AUTH_SOCK" ]; then
    eval "$(ssh-agent -s)"
fi

# Add the ED25519 key if not already loaded
ssh-add -l | grep -q "$(ssh-keygen -lf ~/.ssh/id_ed25519.pub 2>/dev/null | awk '{print $2}')" || ssh-add ~/.ssh/id_ed25519

# Verify key is loaded
if ! ssh-add -l | grep -q "ED25519"; then
    echo "Failed to load SSH key"
    exit 1
fi

# Get host architecture
HOST_ARCH=$(uname -m)
echo "Host architecture: $HOST_ARCH"

# Ask for directory to mount as /data in the VM
DEFAULT_DATA_DIR="/Volumes/MacOS/data"
read -r -p "Directory to mount as /data in VM [$DEFAULT_DATA_DIR]: " DATA_DIR
DATA_DIR="${DATA_DIR:-$DEFAULT_DATA_DIR}"

# Validate the directory exists
if [ ! -d "$DATA_DIR" ]; then
    read -r -p "$DATA_DIR does not exist. Create it? [Y/n]: " CREATE_DIR
    CREATE_DIR="${CREATE_DIR:-Y}"
    if [[ "$CREATE_DIR" =~ ^[Yy] ]]; then
        mkdir -p "$DATA_DIR"
        echo "Created $DATA_DIR"
    else
        echo "Directory $DATA_DIR does not exist. Aborting."
        exit 1
    fi
fi

echo "Mounting $DATA_DIR as /data in VM"

# Generate lima.yaml dynamically with current user and add sudo privileges
cat > "$SCRIPT_DIR/lima.generated.yaml" <<EOF
vmType: "vz"
images:
  - location: "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img"
    arch: "aarch64"
  - location: "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    arch: "x86_64"
cpus: 8
memory: "16GiB"
disk: "256GiB"
mountType: "virtiofs"
mounts:
  - location: "~"
    writable: true
  - location: "/Users/$USER_NAME/repo"
    mountPoint: "/Users/$USER_NAME/repo"
    writable: true
  - location: "$DATA_DIR"
    mountPoint: "/data"
    writable: true
  - location: "/Volumes"
    mountPoint: "/Volumes"
    writable: true
ssh:
  forwardAgent: true
  forwardX11: false
  localPort: 60006

# DNS Configuration
hostResolver:
  enabled: false  # Disable the host resolver
dns:
  - 8.8.8.8  # Google DNS
  - 1.1.1.1  # Cloudflare DNS

user:
  name: "$USER_NAME"

provision:
  - mode: system
    script: |
      #!/bin/bash
      set -eux
      # Install prerequisites
      apt-get update
      apt-get install -y git curl openssh-client ca-certificates gnupg unzip p7zip-full

      # Configure system DNS
      cp /etc/resolv.conf /etc/resolv.conf.backup
      echo "nameserver 8.8.8.8
      nameserver 1.1.1.1" > /etc/resolv.conf

      # Add Docker's official GPG key
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      chmod a+r /etc/apt/keyrings/docker.gpg

      # Add Docker repository
      echo \
        "deb [arch=\"\$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        \$(. /etc/os-release && echo \"\${VERSION_CODENAME}\") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

      # Install Docker packages
      apt-get update
      apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin

      # Install latest Docker Compose from GitHub
      DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -o '"tag_name": ".*"' | cut -d'"' -f4)
      curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
      chmod +x /usr/local/bin/docker-compose

      # Configure Docker daemon with DNS settings
      mkdir -p /etc/docker
      echo '{
        "dns": ["8.8.8.8", "1.1.1.1"]
      }' > /etc/docker/daemon.json

      # Add user to docker and sudo groups
      usermod -aG docker $USER_NAME
      usermod -aG sudo $USER_NAME

      # Start and enable Docker
      systemctl enable docker
      systemctl start docker

      # Install Deno for all users
      echo "Installing Deno..."
      DENO_VERSION=\$(curl -s https://api.github.com/repos/denoland/deno/releases/latest | grep -o '"tag_name": ".*"' | cut -d'"' -f4)
      DENO_ARCH=\$(dpkg --print-architecture | sed 's/arm64/aarch64/' | sed 's/amd64/x86_64/')
      echo "Deno version: \$DENO_VERSION, Architecture: \$DENO_ARCH"
      
      curl -fsSL https://github.com/denoland/deno/releases/download/\${DENO_VERSION}/deno-\${DENO_ARCH}-unknown-linux-gnu.zip -o /tmp/deno.zip
      unzip /tmp/deno.zip -d /tmp/
      mv /tmp/deno /usr/local/bin/deno
      chmod +x /usr/local/bin/deno
      rm /tmp/deno.zip

      # Verify Deno installation
      echo "Verifying Deno installation..."
      /usr/local/bin/deno --version
      ls -la /usr/local/bin/deno

      # Create 32GB swap file
      fallocate -l 32G /swapfile
      chmod 600 /swapfile
      mkswap /swapfile
      swapon /swapfile
      echo '/swapfile none swap sw 0 0' >> /etc/fstab
      echo 'vm.swappiness=10' >> /etc/sysctl.conf
      echo 'vm.vfs_cache_pressure=50' >> /etc/sysctl.conf
      sysctl -p


      # Ensure /usr/local/bin is in PATH for user sessions
      echo 'export PATH="/usr/local/bin:$PATH"' >> /home/$USER_NAME/.bashrc
      echo 'export PATH="/usr/local/bin:$PATH"' >> /home/$USER_NAME/.profile

      # Set ownership of user files
      chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/.bashrc /home/$USER_NAME/.profile

portForwards:
  - guestPort: 2222
    hostPort: 2222
  # Add any other port forwards you need
EOF

# Create VM directory if it doesn't exist
mkdir -p "$LIMA_HOME"

# Check if instance exists in VM directory
if limactl ls | grep -q "default"; then
    # Try to start the instance
    echo "Existing instance found in $LIMA_HOME. Attempting to start..."
    if ! limactl start default; then
        echo "Failed to start instance. Recreating with correct architecture."
        limactl delete --force default
        echo "Creating new Lima instance..."
        limactl create --name=default --tty=false "$SCRIPT_DIR/lima.generated.yaml"
        # Explicitly start after creation
        echo "Starting Lima instance..."
        limactl start default
    fi
else
    # Create new instance
    echo "Creating new Lima instance in VM directory..."
    limactl create --name=default --tty=false "$SCRIPT_DIR/lima.generated.yaml"
    # Explicitly start after creation
    echo "Starting Lima instance..."
    limactl start default
fi

# Give VM a moment to fully start
echo "Waiting for VM to start..."
sleep 5

# Verify correct user setup
USER=$(limactl shell default whoami || echo "")
if [[ "$USER" != "$USER_NAME" ]]; then
    echo "Warning: VM user is not '$USER_NAME' as expected (got: $USER)"
    echo "VM may not be fully initialized yet. Please try again in a moment."
    exit 1
fi

echo "VM started successfully with user: $USER"
limactl shell default
