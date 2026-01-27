FROM ubuntu:24.04

LABEL maintainer="PBJ Project"
LABEL description="Docker VM for running CLI tools"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# ──────────────────────────────────────────────
# Core system utilities
# ──────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Essentials
    bash \
    coreutils \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    sudo \
    locales \
    tzdata \
    # Editors
    vim \
    nano \
    # File utilities
    less \
    tree \
    file \
    zip \
    unzip \
    gzip \
    bzip2 \
    xz-utils \
    p7zip-full \
    rsync \
    # Process & system
    htop \
    procps \
    lsof \
    strace \
    sysstat \
    # Text processing
    jq \
    sed \
    gawk \
    grep \
    ripgrep \
    silversearcher-ag \
    fzf \
    # Version control
    git \
    git-lfs \
    # Networking
    curl \
    wget \
    httpie \
    openssh-client \
    netcat-openbsd \
    socat \
    dnsutils \
    iputils-ping \
    traceroute \
    mtr-tiny \
    iproute2 \
    iptables \
    net-tools \
    nmap \
    tcpdump \
    whois \
    # Build tools
    build-essential \
    cmake \
    pkg-config \
    autoconf \
    automake \
    libtool \
    # Scripting runtimes
    python3 \
    python3-pip \
    python3-venv \
    # Database clients
    postgresql-client \
    mysql-client \
    redis-tools \
    sqlite3 \
    # Misc utilities
    tmux \
    screen \
    bc \
    man-db \
    && rm -rf /var/lib/apt/lists/*

# ──────────────────────────────────────────────
# Node.js (LTS)
# ──────────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# ──────────────────────────────────────────────
# Python CLI tools (installed globally via pip)
# ──────────────────────────────────────────────
RUN pip3 install --no-cache-dir --break-system-packages \
    yq \
    tldr \
    csvkit \
    httpx[cli] \
    rich-cli

# ──────────────────────────────────────────────
# Docker CLI (to manage Docker from inside the VM)
# ──────────────────────────────────────────────
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
       https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# ──────────────────────────────────────────────
# kubectl
# ──────────────────────────────────────────────
RUN curl -fsSL "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/$(dpkg --print-architecture)/kubectl" \
    -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

# ──────────────────────────────────────────────
# AWS CLI v2
# ──────────────────────────────────────────────
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then AWSARCH="x86_64"; else AWSARCH="aarch64"; fi && \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWSARCH}.zip" -o /tmp/awscliv2.zip \
    && unzip -q /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/aws /tmp/awscliv2.zip

# ──────────────────────────────────────────────
# GitHub CLI (gh)
# ──────────────────────────────────────────────
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
       https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# ──────────────────────────────────────────────
# Terraform
# ──────────────────────────────────────────────
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
       https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
       > /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update \
    && apt-get install -y terraform \
    && rm -rf /var/lib/apt/lists/*

# ──────────────────────────────────────────────
# Create a non-root user
# ──────────────────────────────────────────────
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m ${USERNAME} -s /bin/bash \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

# ──────────────────────────────────────────────
# Workspace & volumes
# ──────────────────────────────────────────────
RUN mkdir -p /workspace && chown ${USERNAME}:${USERNAME} /workspace
VOLUME ["/workspace"]

# ──────────────────────────────────────────────
# Entrypoint
# ──────────────────────────────────────────────
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/toolbox.sh /usr/local/bin/toolbox
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/toolbox

USER ${USERNAME}
WORKDIR /workspace

ENTRYPOINT ["entrypoint.sh"]
CMD ["bash"]
