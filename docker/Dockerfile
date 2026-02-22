FROM ubuntu:24.04 AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/root/.deno/bin:${PATH}"
ENV DOTNET_ROOT=/usr/share/dotnet
ENV PATH="${DOTNET_ROOT}:${PATH}"
ENV IS_SANDBOX=1

# Consolidated package installation - single apt-get update for entire build
RUN apt-get update && \
    ARCH=$(dpkg --print-architecture) && \
    echo "Architecture: $ARCH" && \
    apt-get install -y --no-install-recommends \
    # Base packages
    curl wget git build-essential openssh-server unzip python3 software-properties-common zip \
    locales libpcre3-dev zlib1g-dev libxt-dev apt-transport-https ca-certificates gnupg-agent \
    openjdk-21-jdk emacs-nox \
    # Development tools
    protobuf-compiler libprotobuf-dev clang-format clang-tidy clang-tools clang clangd libc++-dev \
    libc++1 libc++abi-dev libc++abi1 libclang-dev libclang1 liblldb-dev libllvm-ocaml-dev \
    libomp-dev libomp5 lld lldb llvm-dev llvm-runtime llvm python3-clang openssl libssl-dev \
    # Python and cert tools
    python3-pip python3-venv ca-certificates \
    # Build dependencies
    cmake g++ libboost-all-dev ninja-build libgtk-3-dev \
    # Linux AIO support
    libaio-dev libaio1t64 \
    # Additional tools
    jq emacs-nox bsdmainutils xxd \
    # Network tools for raw socket development
    tcpdump wireshark-common netcat-openbsd nmap hping3 \
    # Chrome for Flutter web development
    chromium-browser \
    # Mesa utilities for eglinfo
    mesa-utils && \
    # Architecture-specific packages
    if [ "$ARCH" = "amd64" ]; then \
      apt-get install -y --no-install-recommends gcc-multilib g++-multilib libgtk2.0-dev neko; \
    else \
      apt-get install -y --no-install-recommends libgtk2.0-dev; \
    fi && \
    # Docker repository setup
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - && \
    add-apt-repository "deb [arch=$ARCH] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" && \
    apt-get update && \
    apt-get install -y docker-ce docker-ce-cli containerd.io && \
    # .NET SDK installation (install script supports both amd64 and arm64)
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh && \
    chmod +x /tmp/dotnet-install.sh && \
    /tmp/dotnet-install.sh --channel 9.0 --install-dir /usr/share/dotnet && \
    ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet && \
    rm /tmp/dotnet-install.sh && \
    # Git LFS setup
    curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash && \
    apt-get update && \
    apt-get install -y git-lfs && \
    git lfs install && \
    # Final cleanup
    rm -rf /var/lib/apt/lists/*

# Restore full Ubuntu installation (man pages, documentation, etc.)
RUN yes | unminimize

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

WORKDIR /root

RUN mkdir -p /root/repo/dev
WORKDIR /root/repo/dev

COPY clone.root.sh clone.me.sh build-deno.sh ./
RUN chmod +x ./clone.root.sh ./clone.me.sh ./build-deno.sh

RUN chsh -s /bin/bash root

# Install Rust, Deno, Node.js, and other tools
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    && . $HOME/.cargo/env \
    && ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then \
        DENO_ARCH="x86_64-unknown-linux-gnu"; \
    elif [ "$ARCH" = "arm64" ]; then \
        DENO_ARCH="aarch64-unknown-linux-gnu"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    (curl -fsSL https://deno.land/x/install/install.sh | sh || \
        (curl -fsSL "https://github.com/denoland/deno/releases/latest/download/deno-${DENO_ARCH}.zip" -o deno.zip && \
        unzip deno.zip && \
        chmod +x deno && \
        mkdir -p ~/.deno/bin && \
        mv deno ~/.deno/bin/ && \
        rm deno.zip) || \
        (echo "Pre-built binaries failed, using build-deno.sh script..." && \
        cd /root/repo/dev && \
        ./build-deno.sh --dir ~/.deno)) \
    && curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g npm@latest \
    && cargo install cargo-make \
    && cargo install wasmtime-cli

ENV PATH="/root/.npm-global/bin:${PATH}"

# Install SDKMAN! and Kotlin
RUN curl -s "https://get.sdkman.io" | bash \
    && /bin/bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && sdk install kotlin"

RUN echo 'source $HOME/.bashrc' > $HOME/.custom_bashrc \
    && echo 'export BASH_ENV=$HOME/.custom_bashrc' >> $HOME/.profile

# Set environment variables in .bashrc
RUN echo '. "$HOME/.cargo/env"' >> /root/.bashrc \
    && echo 'export DENO_INSTALL="/root/.deno"' >> /root/.bashrc \
    && echo 'export PATH="$DENO_INSTALL/bin:$PATH"' >> /root/.bashrc

RUN echo 'if [ -f ~/.bashrc ]; then . ~/.bashrc; fi' >> ~/.bash_profile \
    && echo "alias python=python3" >> ~/.bashrc \
    && echo "alias emacs='emacs -nw'" >> ~/.bashrc

# Set Chrome executable for Flutter
ENV CHROME_EXECUTABLE=/usr/bin/chromium-browser

RUN mkdir /var/run/sshd \
    && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# Add this line to ensure the .ssh directory exists and has correct permissions
RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh

COPY git.config.ssh /root/
RUN echo "source /root/git.config.ssh" >> ~/.bashrc

RUN echo 'if [ -f ~/.ssh/environment ]; then . ~/.ssh/environment; fi' >> ~/.bashrc

# Skip shellgpt installation for now - can be added later if needed
RUN echo 'export PATH="$HOME/.deno/bin:$PATH"' >> ~/.bashrc

RUN /root/.cargo/bin/rustup update \
    && /root/.cargo/bin/cargo install wasm-pack \
    && /root/.cargo/bin/rustup target add wasm32-unknown-unknown

RUN echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc

# Install Golang with architecture detection
ENV GOLANG_VERSION=1.26.0
ENV GOPATH=/go
ENV GOROOT=/usr/local/go
ENV PATH=$GOPATH/bin:$GOROOT/bin:$PATH
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then \
      wget -q https://dl.google.com/go/go$GOLANG_VERSION.linux-amd64.tar.gz && \
      tar -C /usr/local -xzf go$GOLANG_VERSION.linux-amd64.tar.gz && \
      rm go$GOLANG_VERSION.linux-amd64.tar.gz; \
    elif [ "$ARCH" = "arm64" ]; then \
      wget -q https://dl.google.com/go/go$GOLANG_VERSION.linux-arm64.tar.gz && \
      tar -C /usr/local -xzf go$GOLANG_VERSION.linux-arm64.tar.gz && \
      rm go$GOLANG_VERSION.linux-arm64.tar.gz; \
    else \
      echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"

RUN echo 'export PATH=$GOPATH/bin:$GOROOT/bin:$PATH' >> ~/.bashrc

# Create a temporary Go module and install Pion TURN and WebRTC
WORKDIR /tmp/goinstall
RUN go mod init temp-module \
    && go get github.com/pion/turn/v4@latest \
    && go get github.com/pion/webrtc/v4@v4.2.5 \
    && cp -R /go/pkg/mod/github.com/pion /usr/local/go/src/github.com/

# Clean up
WORKDIR /
RUN rm -rf /tmp/goinstall

RUN echo '(setq make-backup-files nil)' >> ~/.emacs

# Install Bun with architecture detection
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then \
        curl -fsSL https://github.com/oven-sh/bun/releases/latest/download/bun-linux-x64.zip -o bun.zip && \
        unzip bun.zip && \
        chmod +x bun-linux-x64/bun && \
        mv bun-linux-x64/bun /usr/local/bin/; \
    elif [ "$ARCH" = "arm64" ]; then \
        curl -fsSL https://github.com/oven-sh/bun/releases/latest/download/bun-linux-aarch64.zip -o bun.zip && \
        unzip bun.zip && \
        chmod +x bun-linux-aarch64/bun && \
        mv bun-linux-aarch64/bun /usr/local/bin/; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    rm bun.zip

# Install Flutter SDK with architecture detection
ENV FLUTTER_HOME=/usr/local/flutter
ENV PATH="${FLUTTER_HOME}/bin:${PATH}"
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then \
        FLUTTER_ARCH="x64"; \
    elif [ "$ARCH" = "arm64" ]; then \
        FLUTTER_ARCH="arm64"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    FLUTTER_VERSION=$(curl -s https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json | jq -r '.current_release.stable') && \
    FLUTTER_RELEASE=$(curl -s https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json | jq -r --arg version "$FLUTTER_VERSION" --arg arch "$FLUTTER_ARCH" '.releases[] | select(.hash == $version and .dart_sdk_arch == $arch) | .archive') && \
    curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/${FLUTTER_RELEASE}" -o flutter.tar.xz && \
    tar -xf flutter.tar.xz -C /usr/local && \
    rm flutter.tar.xz && \
    git config --global --add safe.directory /usr/local/flutter && \
    flutter config --no-analytics && \
    flutter precache

RUN echo 'export PATH="/usr/local/flutter/bin:$PATH"' >> ~/.bashrc

COPY entrypoint.sh /usr/local/bin/
RUN echo 'export OPENAI_API_ENDPOINT=$OPENAI_API_ENDPOINT' >> ~/.bashrc \
    && echo 'export OPENAI_API_KEY=$OPENAI_API_KEY' >> ~/.bashrc \
    && chmod +x /usr/local/bin/entrypoint.sh

# Install cloudflared with architecture detection
RUN ARCH=$(dpkg --print-architecture) && \
    CLOUDFLARED_VERSION=$(curl -s https://api.github.com/repos/cloudflare/cloudflared/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")') && \
    if [ "$ARCH" = "amd64" ]; then \
        wget "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-amd64.deb" && \
        dpkg -i cloudflared-linux-amd64.deb && \
        rm cloudflared-linux-amd64.deb; \
    elif [ "$ARCH" = "arm64" ]; then \
        wget "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-arm64.deb" && \
        dpkg -i cloudflared-linux-arm64.deb && \
        rm cloudflared-linux-arm64.deb; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi

# Install ngrok with architecture detection
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then \
        curl -fsSL https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz | tar xzf - -C /usr/local/bin; \
    elif [ "$ARCH" = "arm64" ]; then \
        curl -fsSL https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz | tar xzf - -C /usr/local/bin; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    chmod +x /usr/local/bin/ngrok

# Install AWS CLI version 2 with architecture detection
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then \
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"; \
    elif [ "$ARCH" = "arm64" ]; then \
        curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -f awscliv2.zip

# Install AWS CDK
RUN npm install -g aws-cdk

# Verify the installation
RUN cdk --version

# Install rclone
RUN curl https://rclone.org/install.sh | bash

# Install Playwright for testing (required by testing guidelines)
RUN npm install -g playwright@latest

# Create and activate virtual environment
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install Python packages in virtual environment
RUN pip install --upgrade pip setuptools && \
    pip install certbot scapy

# Install kubectl with architecture detection
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then \
        KUBECTL_ARCH="amd64"; \
    elif [ "$ARCH" = "arm64" ]; then \
        KUBECTL_ARCH="arm64"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${KUBECTL_ARCH}/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# Install Helm
RUN curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

# Install k9s with architecture detection
RUN ARCH=$(dpkg --print-architecture) && \
    K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | jq -r '.tag_name') && \
    if [ "$ARCH" = "amd64" ]; then \
        K9S_ARCH="amd64"; \
    elif [ "$ARCH" = "arm64" ]; then \
        K9S_ARCH="arm64"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    curl -fsSL "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${K9S_ARCH}.tar.gz" | tar xzf - -C /usr/local/bin k9s

# Install Cursor Agent CLI and configure PATH
RUN curl https://cursor.com/install -fsSL | bash
ENV PATH="/root/.local/bin:${PATH}"
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> /root/.bashrc && /bin/bash -lc "source /root/.bashrc"

# Install Claude Code CLI
RUN curl -fsSL https://claude.ai/install.sh | bash

# Configure system for linux/aio support
# Increase aio-max-nr for better async I/O performance
RUN echo 'fs.aio-max-nr = 1048576' >> /etc/sysctl.conf

# NOTE: For linux/aio to work properly in containers, you may need to run with:
# --cap-add=SYS_ADMIN (for full functionality)
# OR specific capabilities like:
# --cap-add=SYS_RESOURCE (for resource limit adjustments)
# --cap-add=IPC_LOCK (for memory locking operations)
# 
# Example: docker run --cap-add=SYS_ADMIN your-image
# Or for more restrictive: docker run --cap-add=SYS_RESOURCE --cap-add=IPC_LOCK your-image

# Set the working directory to your project root
WORKDIR /root/repo/dev

# Build stage for specialized dependencies
FROM base AS build

# Install Emscripten for building NanoVDB
WORKDIR /
RUN git clone https://github.com/emscripten-core/emsdk.git
WORKDIR /emsdk
RUN ./emsdk install latest
RUN ./emsdk activate latest
ENV EMSDK=/emsdk
ENV EM_CONFIG=/emsdk/.emscripten
ENV EM_CACHE=/emsdk/cache
ENV EM_PORTS=/emsdk/ports
ENV PATH="/emsdk:${PATH}"
ENV PATH="/emsdk/upstream/emscripten:${PATH}"
# Symlink emsdk's node to a fixed path to avoid hardcoding the version directory
RUN NODE_BIN=$(find /emsdk/node -name "node" -maxdepth 5 -type f | sort | tail -1) && \
    ln -sf "$NODE_BIN" /usr/local/bin/emsdk-node

# Set the appropriate user (e.g., root)
USER root

RUN git clone https://github.com/google/googletest.git \
    && cd googletest \
    && mkdir build \
    && cd build \
    && cmake .. \
    && make -j$(nproc) \
    && make install

RUN ldconfig

# Create temporary certificates for testing
WORKDIR /tmp
RUN openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes -subj '/CN=localhost' \
    && openssl pkcs12 -export -out certificate.pfx -inkey key.pem -in cert.pem -password pass:yourCertificatePassword \
    && cp cert.pem cert.crt \
    && cp cert.crt /usr/local/share/ca-certificates/cert.crt \
    && update-ca-certificates

# Install Zig with architecture detection
ENV ZIG_VERSION=0.15.2
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then \
        wget https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz && \
        tar -xf zig-x86_64-linux-${ZIG_VERSION}.tar.xz && \
        mv zig-x86_64-linux-${ZIG_VERSION} /usr/local/zig && \
        rm zig-x86_64-linux-${ZIG_VERSION}.tar.xz; \
    elif [ "$ARCH" = "arm64" ]; then \
        wget https://ziglang.org/download/${ZIG_VERSION}/zig-aarch64-linux-${ZIG_VERSION}.tar.xz && \
        tar -xf zig-aarch64-linux-${ZIG_VERSION}.tar.xz && \
        mv zig-aarch64-linux-${ZIG_VERSION} /usr/local/zig && \
        rm zig-aarch64-linux-${ZIG_VERSION}.tar.xz; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi

ENV PATH="/usr/local/zig:${PATH}"

# Add this near the end of the Dockerfile
COPY setup-ssh.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/setup-ssh.sh

# Modify the ENTRYPOINT to run our setup script
ENTRYPOINT ["/bin/bash", "-c", "/usr/local/bin/setup-ssh.sh && /usr/local/bin/entrypoint.sh"]

# Reset working directory to root
WORKDIR /root

# Final stage
FROM build AS final

EXPOSE 22


