#!/usr/bin/env bash
#
# make init から呼ばれるセットアップスクリプト。
# このスクリプトは「code-server を動かすホスト上」で、そのホストのユーザーとして実行される前提。
# だから鍵生成も authorized_keys への登録もその場で完結できる。
#
#   git clone ... && cd code-server
#   make init   # ← これ（鍵・.env・authorized_keys を用意）
#   make up
#
set -euo pipefail

# リポジトリのルートへ移動（scripts/ の一つ上）
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

KEY="ssh/id_ed25519"
USER_NAME="$(id -un)"
PROJECT_DIR_DEFAULT="${HOME}/Project"

echo "[init] code-server セットアップを開始"

# 1. .env（ホスト固有設定）を生成
if [[ -f .env ]]; then
  echo "[init] .env は既存のため再利用"
  # shellcheck disable=SC1091
  PROJECT_DIR="$(grep -E '^PROJECT_DIR=' .env | cut -d= -f2-)"
else
  read -rp "[init] 作業ディレクトリ（ホスト上の絶対パス） [${PROJECT_DIR_DEFAULT}]: " ans
  PROJECT_DIR="${ans:-$PROJECT_DIR_DEFAULT}"
  cat > .env <<EOF
# make init が自動生成。手で消してもう一度 make init すれば作り直される。
HOST_USER=${USER_NAME}
PROJECT_DIR=${PROJECT_DIR}
PORT=8080
EOF
  echo "[init] .env を作成（HOST_USER=${USER_NAME} / PROJECT_DIR=${PROJECT_DIR}）"
fi

# 2. 作業ディレクトリを用意
mkdir -p "${PROJECT_DIR}"
echo "[init] 作業ディレクトリを確認: ${PROJECT_DIR}"

# 3. コンテナ→ホストSSH用の鍵を生成（イメージには焼かず、ここで作って read-only マウントする）
mkdir -p ssh
if [[ -f "${KEY}" ]]; then
  echo "[init] SSH鍵は既存のため再利用: ${KEY}"
else
  ssh-keygen -t ed25519 -N '' -C "code-server-container@${USER_NAME}" -f "${KEY}" >/dev/null
  echo "[init] SSH鍵を生成: ${KEY}"
fi
chmod 600 "${KEY}"

# 4. 公開鍵をホスト自身の authorized_keys に登録（このスクリプトはホストユーザーとして動いている）
mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"
touch "${HOME}/.ssh/authorized_keys" && chmod 600 "${HOME}/.ssh/authorized_keys"
PUB="$(cat "${KEY}.pub")"
if grep -qF "${PUB}" "${HOME}/.ssh/authorized_keys"; then
  echo "[init] 公開鍵は登録済み: ${HOME}/.ssh/authorized_keys"
else
  printf '%s\n' "${PUB}" >> "${HOME}/.ssh/authorized_keys"
  echo "[init] 公開鍵を登録: ${HOME}/.ssh/authorized_keys"
fi

# 5. ホスト sshd の稼働チェック（make init では起動まではしない＝sudo が要るため）
if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet ssh 2>/dev/null; then
  echo "[init] ホスト sshd: 稼働中"
elif command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet sshd 2>/dev/null; then
  echo "[init] ホスト sshd: 稼働中"
else
  echo "[init][警告] ホストで sshd が稼働していないようです。ターミナルのホストSSHを使うには:"
  echo "             sudo apt install -y openssh-server && sudo systemctl enable --now ssh"
fi

echo "[init] 完了。'make up' で起動できます。"
