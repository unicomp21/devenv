# Lima VM with Local Storage

This Lima VM setup stores all VM data in the current directory instead of the default `~/.lima` location.

## Key Changes

1. **VM Storage Location**: `/Volumes/MacOS/Lima/VM/` for all persistence concerns
2. **Disk Size**: Increased to 256GB
3. **Location**: `/Volumes/MacOS/Lima/`

## Usage

### Using the Management Script

```bash
# Show help
./lima

# Start the VM
./lima start

# Connect to VM shell
./lima shell

# Check VM status
./lima status

# Stop the VM
./lima stop

# Delete the VM
./lima delete
```

### Using launch.sh

```bash
# Create and start the VM (interactive shell)
./launch.sh
```

### Cleanup

```bash
# Remove all VMs and clean up
./purge.sh

# Remove old Lima instances from default location
./cleanup-old-lima.sh
```

## VM Configuration

- **CPU**: 8 cores
- **Memory**: 16GB
- **Disk**: 256GB
- **VM Type**: vz (Apple Virtualization Framework)
- **Architecture**: Automatic (arm64/x86_64)
- **OS**: Ubuntu Noble (24.04)

## Included Software

- Docker CE with Docker Compose
- Deno runtime
- 32GB swap file
- SSH agent forwarding

## File Structure

```
/Volumes/MacOS/Lima/
├── VM/                 # Lima VM storage (created on first run)
├── lima                # Management script
├── lima.ts             # TypeScript implementation
├── launch.sh           # Full VM launch script
├── purge.sh            # Cleanup script
└── cleanup-old-lima.sh # Remove old instances
``` 