#!/bin/bash

# Write only non-sensitive env vars needed by SSH sessions to the environment file.
# Secrets (OPENAI_API_KEY, etc.) are intentionally excluded - they remain in memory only.
{
    for var in NATS_ENDPOINT NATS_JS_ENDPOINT NATS_WS_ENDPOINT REDIS_ENDPOINT; do
        if [ -n "${!var}" ]; then
            echo "export ${var}=${!var}"
        fi
    done
} > /root/.ssh/environment

# Start the SSH server
exec /usr/sbin/sshd -D
