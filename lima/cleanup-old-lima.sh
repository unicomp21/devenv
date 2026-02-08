#!/bin/bash
set -e

# Cleanup script to remove old Lima instances from default location

echo "Checking for existing Lima instances in default location..."

# Check if lima is installed
if ! command -v limactl &> /dev/null; then
    echo "Lima is not installed. Nothing to clean up."
    exit 0
fi

# Unset LIMA_HOME to check default location
unset LIMA_HOME

# List instances in default location
INSTANCES=$(limactl list --json 2>/dev/null || echo "")

if [ -z "$INSTANCES" ] || [ "$INSTANCES" = "null" ]; then
    echo "No instances found in default location."
    echo ""
    echo "Cleanup complete!"
    exit 0
fi

# Count instances
COUNT=$(echo "$INSTANCES" | jq -s 'length')

if [ "$COUNT" -eq 0 ]; then
    echo "No instances found in default location."
else
    echo "Found $COUNT instance(s) in default location:"

    # Iterate over each instance
    echo "$INSTANCES" | jq -r '.name + " " + .status' | while read -r NAME STATUS; do
        echo "- $NAME ($STATUS)"
        echo "Deleting instance '$NAME'..."

        if limactl delete --force "$NAME"; then
            echo "Successfully deleted '$NAME'"
        else
            echo "Failed to delete '$NAME'"
        fi
    done
fi

echo ""
echo "Cleanup complete!"
