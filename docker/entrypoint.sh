#!/bin/bash

# Save Docker environment variables
cat /proc/1/environ | tr '\0' '\n' | sed 's/^\(.*\)$/export \1/g' > /root/.ssh/environment

# Start the SSH server
exec /usr/sbin/sshd -D
