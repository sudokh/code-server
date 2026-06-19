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

# 棚卸し済みのユーザー設定をイメージへ入れる。
# /home/coder は名前付きボリュームなので、空のボリュームを初めてマウントしたときに
# 設定と拡張機能がボリュームへコピーされる。既存ボリュームは上書きされない。
COPY --chown=coder:coder config/User/ /home/coder/.local/share/code-server/User/
COPY --chown=coder:coder config/extensions.txt /tmp/code-server-extensions.txt

USER coder

# 棚卸し済みの拡張機能をイメージへインストールする。
# 空行と # から始まるコメントは無視する。
RUN set -eu; \
    while IFS= read -r extension || [ -n "${extension}" ]; do \
      case "${extension}" in \
        ""|\#*) continue ;; \
      esac; \
      code-server --install-extension "${extension}"; \
    done < /tmp/code-server-extensions.txt; \
    rm /tmp/code-server-extensions.txt

# 起動フラグ（--auth none / --disable-telemetry）と開くフォルダは compose の command 側で指定する。
ENTRYPOINT ["/usr/bin/entrypoint.sh"]
