#!/bin/bash

# Copy SSH keys if they exist
if [ -d /tmp/.ssh ]; then
  mkdir -p /root/.ssh
  cp -r /tmp/.ssh/* /root/.ssh/
  chmod 700 /root/.ssh
  chmod 600 /root/.ssh/*
fi

# Fix for SSH prompt directory syncing
echo 'PROMPT_COMMAND="printf \"\033]0;%s@%s:%s\007\" \"\${USER}\" \"\${HOSTNAME%%.*}\" \"\${PWD/#\$HOME/\~}\""' >> /root/.bashrc
echo 'PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >> /root/.bashrc

# SSH service will be started by entrypoint.sh
