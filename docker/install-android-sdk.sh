#!/bin/bash
set -e

# Android SDK Installation Script for Flutter Development
# Installs command-line tools, platform-tools (adb), and build-tools
# Handles ARM64 hosts with x86_64 emulation via qemu

ANDROID_SDK_ROOT="${ANDROID_HOME:-/usr/lib/android-sdk}"
CMDLINE_TOOLS_VERSION="11076708"  # Latest as of 2024
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip"

echo "Installing Android SDK to: $ANDROID_SDK_ROOT"

# Detect architecture
ARCH=$(uname -m)
echo "Detected architecture: $ARCH"

# Install dependencies
apt-get update
apt-get install -y wget unzip openjdk-17-jdk

# For ARM64 hosts, set up x86_64 emulation for Android tools
if [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    echo "ARM64 detected - setting up x86_64 emulation..."
    apt-get install -y qemu-user-static

    # Add amd64 architecture
    dpkg --add-architecture amd64

    # Add x86_64 Ubuntu archive for amd64 packages
    if [[ ! -f /etc/apt/sources.list.d/amd64.list ]]; then
        echo "deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
deb [arch=amd64] http://archive.ubuntu.com/ubuntu noble-security main restricted universe multiverse" > /etc/apt/sources.list.d/amd64.list
    fi

    # Fix ubuntu.sources to only use arm64 from ports
    if [[ -f /etc/apt/sources.list.d/ubuntu.sources ]]; then
        sed -i '/^URIs: http:\/\/ports\.ubuntu\.com/a Architectures: arm64' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true
    fi

    apt-get update
    apt-get install -y libc6:amd64
fi

# Create SDK directory
mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"

# Download and extract command-line tools
echo "Downloading Android command-line tools..."
cd /tmp
wget -q "$CMDLINE_TOOLS_URL" -O cmdline-tools.zip
unzip -q -o cmdline-tools.zip
rm -rf "$ANDROID_SDK_ROOT/cmdline-tools/latest"
mv cmdline-tools "$ANDROID_SDK_ROOT/cmdline-tools/latest"
rm cmdline-tools.zip

# Set up environment variables
export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

# Accept licenses
echo "Accepting Android SDK licenses..."
yes | sdkmanager --licenses > /dev/null 2>&1 || true

# Install SDK components (include both versions Flutter may need)
echo "Installing SDK components..."
sdkmanager "platform-tools" "build-tools;34.0.0" "build-tools;28.0.3" "platforms;android-34" "platforms;android-36"

# Add environment variables to shell config
SHELL_RC="$HOME/.bashrc"
if [[ -f "$HOME/.zshrc" ]]; then
    SHELL_RC="$HOME/.zshrc"
fi

if ! grep -q "ANDROID_HOME" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# Android SDK" >> "$SHELL_RC"
    echo "export ANDROID_HOME=$ANDROID_SDK_ROOT" >> "$SHELL_RC"
    echo "export ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT" >> "$SHELL_RC"
    echo 'export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"' >> "$SHELL_RC"
    echo "Added Android SDK environment variables to $SHELL_RC"
fi

echo ""
echo "Android SDK installation complete!"
echo "Run 'source $SHELL_RC' or restart your terminal, then run 'flutter doctor' again."
