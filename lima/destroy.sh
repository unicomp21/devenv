#!/bin/bash
set -e

# Destroy the Lima VM created by launch.sh

# Match LIMA_HOME logic from launch.sh
if [ -d "/Volumes/MacOS" ]; then
    export LIMA_HOME="/Volumes/MacOS/Lima/VM"
else
    export LIMA_HOME="$HOME/.lima/VM"
fi

echo "LIMA_HOME: $LIMA_HOME"

if ! command -v limactl &> /dev/null; then
    echo "Lima is not installed. Nothing to destroy."
    exit 0
fi

if ! limactl ls | grep -q "default"; then
    echo "No instance found."
    exit 0
fi

read -r -p "Destroy the default Lima VM? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
    echo "Aborted."
    exit 0
fi

echo "Stopping and deleting VM..."
limactl delete --force default
echo "VM destroyed."
