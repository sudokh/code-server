FROM codercom/code-server:latest

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    zsh \
    tmux \
    neovim \
    git \
    curl \
    make \
    && rm -rf /var/lib/apt/lists/*

USER coder

# LAN内利用のみのため認証なし（HTTPS終端は外部のCaddyが担う）
ENTRYPOINT ["/usr/bin/entrypoint.sh", "--bind-addr", "0.0.0.0:8080", "--auth", "none", "/home/coder/project"]
