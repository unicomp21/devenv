#!/bin/bash

# NVM Installation Script
# This script installs Node Version Manager (nvm)

set -e

# NVM version - update as needed
NVM_VERSION="v0.39.7"

echo "Installing NVM ${NVM_VERSION}..."

# Download and install nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash

# Source nvm in current shell
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Add nvm to shell profile if not already present
SHELL_PROFILE="$HOME/.bashrc"
if [ -f "$HOME/.zshrc" ]; then
    SHELL_PROFILE="$HOME/.zshrc"
fi

if ! grep -q "NVM_DIR" "$SHELL_PROFILE"; then
    echo "" >> "$SHELL_PROFILE"
    echo 'export NVM_DIR="$HOME/.nvm"' >> "$SHELL_PROFILE"
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> "$SHELL_PROFILE"
    echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> "$SHELL_PROFILE"
fi

echo "NVM ${NVM_VERSION} installed successfully!"
echo "To use nvm, either:"
echo "  1. Restart your terminal, or"
echo "  2. Run: source $SHELL_PROFILE"
echo ""
echo "Then you can install Node.js with: nvm install node"