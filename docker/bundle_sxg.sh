#!/bin/bash

set -e

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for required commands
for cmd in go file certbot; do
    if ! command_exists $cmd; then
        echo "Error: $cmd is not installed. Please install it and try again."
        exit 1
    fi
done

# Update WebBundle tools
echo "Updating WebBundle tools..."
go install github.com/WICG/webpackage/go/bundle/cmd/...@latest
go install github.com/WICG/webpackage/go/signedexchange/cmd/...@latest

# Prompt for domain
read -p "Enter your domain (e.g., lunchgamer.com): " DOMAIN
DOMAIN=${DOMAIN#https://}  # Remove https:// if present
DOMAIN=${DOMAIN:-"lunchgamer.com"}

# Prompt for email
read -p "Enter your email address for Let's Encrypt notifications: " EMAIL

# Use Certbot to obtain SSL/TLS certificate with DNS authentication
echo "Obtaining SSL/TLS certificate using Certbot with DNS authentication..."
certbot certonly --manual --preferred-challenges=dns --email "$EMAIL" --agree-tos -d "$DOMAIN"

# Set paths for the obtained certificate and key
CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

# Check if certificate files exist
if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
    echo "Error: Certificate files not found. Certbot may have failed to obtain the certificate."
    exit 1
fi

# Prompt for SPA directory path
read -p "Enter the SPA directory path (default: /root/repo/dev/mono-root/dagr/node/dist): " SPA_DIR
SPA_DIR=${SPA_DIR:-"/root/repo/dev/mono-root/dagr/node/dist"}

# Check if directory exists
if [ ! -d "$SPA_DIR" ]; then
    echo "Error: Directory $SPA_DIR does not exist."
    exit 1
fi

# Generate manifest (for reference, not used in bundle generation)
echo "Generating manifest..."
echo '{' > manifest.json
find "$SPA_DIR" -type f | while read -r file; do
    mime=$(file -b --mime-type "$file")
    relative_path="${file#$SPA_DIR/}"
    echo "  \"$relative_path\": {\"content-type\": \"$mime\"}," >> manifest.json
done
sed -i '$ s/,$//' manifest.json  # Remove the trailing comma
echo '}' >> manifest.json

# Generate bundle
echo "Generating bundle..."
gen-bundle \
    -dir "$SPA_DIR" \
    -baseURL "https://$DOMAIN/" \
    -primaryURL "https://$DOMAIN/" \
    -o bundle.wbn

# Sign bundle
echo "Signing bundle..."
gen-signedexchange \
    -uri "https://$DOMAIN/bundle.sxg" \
    -content bundle.wbn \
    -certificate "$CERT_PATH" \
    -privateKey "$KEY_PATH" \
    -validityUrl "https://$DOMAIN/validity.msg" \
    -expire 604800s \
    -o bundle.sxg

echo "SXG bundle created: bundle.sxg"
echo "Manifest file created: manifest.json (not included in the bundle)"

echo "Warning: The certificate obtained through Certbot does not include the necessary extensions for SXG."
echo "For production use, you'll need to obtain an SXG-capable certificate from a supported CA."
