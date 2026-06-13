FROM codercom/code-server:latest

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    zsh \
    tmux \
    neovim \
    git \
    curl \
    make \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# 統合ターミナルからホストへSSHするラッパ。鍵はイメージに焼かず compose で read-only マウントする。
COPY scripts/ssh-host.sh /usr/local/bin/ssh-host
RUN chmod +x /usr/local/bin/ssh-host

# 既定ターミナルプロファイルを「host（=ホストへSSH）」に。
# /home/coder は名前付きボリュームなので、ボリューム初回作成時にこの内容がコピーされる。
COPY --chown=coder:coder config/settings.json /home/coder/.local/share/code-server/User/settings.json

USER coder

# 起動フラグ（--auth none / --disable-telemetry）と開くフォルダは compose の command 側で指定する。
ENTRYPOINT ["/usr/bin/entrypoint.sh"]
