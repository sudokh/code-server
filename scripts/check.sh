#!/usr/bin/env bash
#
# make check から呼ばれる事前点検スクリプト。
# 「ホスト上で make up が成立し、ターミナルのホストSSHまで通る」ための前提を確認する。
# ホスト上で実行する前提（docker と sshd はホストのものを見る）。
#
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail=0
ok()   { printf '  [OK]   %s\n' "$1"; }
ng()   { printf '  [NG]   %s\n' "$1"; fail=1; }
warn() { printf '  [WARN] %s\n' "$1"; }

echo "== code-server 事前点検 =="

# 1. docker 本体
if command -v docker >/dev/null 2>&1; then
  ok "docker コマンドあり（$(docker --version 2>/dev/null)）"
else
  ng "docker コマンドが無い → Docker をインストールしてください"
fi

# 2. docker デーモンに繋がるか（バイナリがあっても起動していないことがある）
if docker info >/dev/null 2>&1; then
  ok "docker デーモン稼働中"
else
  ng "docker デーモンに接続できない → 起動/権限を確認（sudo systemctl enable --now docker、docker グループ）"
fi

# 3. docker compose v2 プラグイン
if docker compose version >/dev/null 2>&1; then
  ok "docker compose v2 あり（$(docker compose version --short 2>/dev/null)）"
else
  ng "docker compose（v2 プラグイン）が無い → docker-compose-plugin を導入"
fi

# 4. ホストの sshd（ターミナルのSSH先）
if (command -v systemctl >/dev/null 2>&1 && \
    (systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null)); then
  ok "ホスト sshd 稼働中"
elif pgrep -x sshd >/dev/null 2>&1; then
  ok "ホスト sshd 稼働中（pgrep）"
else
  ng "ホスト sshd が動いていない → sudo apt install -y openssh-server && sudo systemctl enable --now ssh"
fi

# 5. make init 済みか（.env・鍵）
if [[ -f .env ]]; then
  ok ".env あり"
  HOST_USER="$(grep -E '^HOST_USER=' .env | cut -d= -f2-)"
  PROJECT_DIR="$(grep -E '^PROJECT_DIR=' .env | cut -d= -f2-)"
  [[ -n "${HOST_USER:-}" ]]   && ok "HOST_USER=${HOST_USER}"     || ng ".env の HOST_USER が空"
  if [[ -n "${PROJECT_DIR:-}" ]]; then
    if [[ -d "${PROJECT_DIR}" ]]; then ok "PROJECT_DIR=${PROJECT_DIR}（存在）"
    else warn "PROJECT_DIR=${PROJECT_DIR} がまだ無い（make init / make up 時に作成）"; fi
  else
    ng ".env の PROJECT_DIR が空"
  fi
else
  ng ".env が無い → make init を実行"
fi

# 6. SSH鍵と authorized_keys 登録
if [[ -f ssh/id_ed25519 && -f ssh/id_ed25519.pub ]]; then
  ok "SSH鍵あり（ssh/id_ed25519）"
  if [[ -f "${HOME}/.ssh/authorized_keys" ]] && grep -qF "$(cat ssh/id_ed25519.pub)" "${HOME}/.ssh/authorized_keys" 2>/dev/null; then
    ok "公開鍵がホストの authorized_keys に登録済み"
  else
    warn "公開鍵がホストの authorized_keys に未登録 → make init を実行"
  fi
else
  ng "SSH鍵が無い → make init を実行"
fi

echo
if [[ "${fail}" -eq 0 ]]; then
  echo "結果: OK（make up で起動できます）"
else
  echo "結果: NG（上の [NG] を解消してください）"
fi
exit "${fail}"
