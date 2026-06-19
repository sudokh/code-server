#!/usr/bin/env bash
#
# code-server-home ボリュームの日常状態から、再現に必要な設定だけを config/ へ棚卸しする。
# globalStorage / workspaceStorage / History / 認証情報 / 拡張機能本体は対象にしない。
#
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(pwd)"

MODE="write"
case "${1:-}" in
  "")
    ;;
  --check)
    MODE="check"
    ;;
  *)
    echo "Usage: $0 [--check]" >&2
    exit 2
    ;;
esac

SERVICE="code-server"
REMOTE_USER_DIR="/home/coder/.local/share/code-server/User"
CONFIG_DIR="${ROOT}/config"
CONFIG_USER_DIR="${CONFIG_DIR}/User"
TMP_DIR="$(mktemp -d "${ROOT}/.inventory.XXXXXX")"
TMP_USER_DIR="${TMP_DIR}/User"

cleanup() {
  rm -rf -- "${TMP_DIR}"
}
trap cleanup EXIT

if ! command -v docker >/dev/null 2>&1; then
  echo "[inventory][ERROR] docker コマンドが見つかりません" >&2
  exit 1
fi

if ! docker compose ps --status running --services 2>/dev/null | grep -qx "${SERVICE}"; then
  echo "[inventory][ERROR] ${SERVICE} が起動していません。先に make up を実行してください" >&2
  exit 1
fi

mkdir -p "${TMP_USER_DIR}/snippets"

echo "[inventory] ユーザー設定を取得"
if docker compose exec -T "${SERVICE}" test -f "${REMOTE_USER_DIR}/settings.json"; then
  docker compose cp "${SERVICE}:${REMOTE_USER_DIR}/settings.json" "${TMP_USER_DIR}/settings.json" >/dev/null
else
  echo "[inventory][ERROR] settings.json が見つかりません" >&2
  exit 1
fi

if docker compose exec -T "${SERVICE}" test -f "${REMOTE_USER_DIR}/keybindings.json"; then
  docker compose cp "${SERVICE}:${REMOTE_USER_DIR}/keybindings.json" "${TMP_USER_DIR}/keybindings.json" >/dev/null
else
  printf '[]\n' > "${TMP_USER_DIR}/keybindings.json"
fi

if docker compose exec -T "${SERVICE}" test -d "${REMOTE_USER_DIR}/snippets"; then
  docker compose cp "${SERVICE}:${REMOTE_USER_DIR}/snippets/." "${TMP_USER_DIR}/snippets/" >/dev/null
fi

if find "${TMP_USER_DIR}/snippets" -type l -print -quit | grep -q .; then
  echo "[inventory][ERROR] snippets 内にシンボリックリンクがあるため中止します" >&2
  exit 1
fi

UNEXPECTED_SNIPPETS="$(
  find "${TMP_USER_DIR}/snippets" \
    -type f \
    ! -name '*.json' \
    ! -name '*.code-snippets' \
    -print
)"
if [[ -n "${UNEXPECTED_SNIPPETS}" ]]; then
  echo "[inventory][ERROR] snippets 内に想定外のファイルがあります:" >&2
  while IFS= read -r file; do
    printf '  - %s\n' "${file#${TMP_USER_DIR}/}" >&2
  done <<< "${UNEXPECTED_SNIPPETS}"
  exit 1
fi

echo "[inventory] 拡張機能一覧を取得"
docker compose exec -T "${SERVICE}" code-server --list-extensions --show-versions \
  | tr -d '\r' \
  | sed '/^[[:space:]]*$/d' \
  | LC_ALL=C sort -fu \
  > "${TMP_DIR}/extensions.txt"

show_diff() {
  local changed=0

  if ! diff -u "${CONFIG_USER_DIR}/settings.json" "${TMP_USER_DIR}/settings.json"; then
    changed=1
  fi
  if ! diff -u "${CONFIG_USER_DIR}/keybindings.json" "${TMP_USER_DIR}/keybindings.json"; then
    changed=1
  fi
  if [[ -d "${CONFIG_USER_DIR}/snippets" ]]; then
    if ! diff -ruN "${CONFIG_USER_DIR}/snippets" "${TMP_USER_DIR}/snippets"; then
      changed=1
    fi
  elif find "${TMP_USER_DIR}/snippets" -type f -print -quit | grep -q .; then
    echo "--- ${CONFIG_USER_DIR}/snippets（ディレクトリなし）"
    echo "+++ ${TMP_USER_DIR}/snippets"
    find "${TMP_USER_DIR}/snippets" -type f -print | LC_ALL=C sort
    changed=1
  fi
  if ! diff -u "${CONFIG_DIR}/extensions.txt" "${TMP_DIR}/extensions.txt"; then
    changed=1
  fi

  return "${changed}"
}

if [[ "${MODE}" == "check" ]]; then
  echo "[inventory] Git管理中の基準状態と比較"
  if show_diff; then
    echo "[inventory] 差分はありません"
    exit 0
  fi

  echo "[inventory] 差分があります。反映するには make inventory を実行してください"
  exit 1
fi

echo "[inventory] config/ へ反映"
if [[ -L "${CONFIG_USER_DIR}" || -L "${CONFIG_USER_DIR}/snippets" ]]; then
  echo "[inventory][ERROR] config/User または snippets がシンボリックリンクのため中止します" >&2
  exit 1
fi

mkdir -p "${CONFIG_USER_DIR}/snippets"
cp "${TMP_USER_DIR}/settings.json" "${CONFIG_USER_DIR}/settings.json"
cp "${TMP_USER_DIR}/keybindings.json" "${CONFIG_USER_DIR}/keybindings.json"

# snippets はボリューム側を正として同期する。削除済みスニペットも棚卸しへ反映する。
find "${CONFIG_USER_DIR}/snippets" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
cp -R "${TMP_USER_DIR}/snippets/." "${CONFIG_USER_DIR}/snippets/"
cp "${TMP_DIR}/extensions.txt" "${CONFIG_DIR}/extensions.txt"

SENSITIVE_PATTERN='"[^"]*(token|password|secret|api[_-]?key|access[_-]?key|private[_-]?key)[^"]*"[[:space:]]*:'
SENSITIVE_FILES="$(
  grep -RIlE \
    --include='*.json' \
    --include='*.code-snippets' \
    "${SENSITIVE_PATTERN}" \
    "${CONFIG_USER_DIR}" 2>/dev/null || true
)"
if [[ -n "${SENSITIVE_FILES}" ]]; then
  echo "[inventory][WARN] 秘密情報らしいキー名を検出しました。Gitへ追加する前に確認してください:"
  while IFS= read -r file; do
    printf '  - %s\n' "${file#${ROOT}/}"
  done <<< "${SENSITIVE_FILES}"
fi

echo "[inventory] 棚卸し完了"
git status --short -- config
git diff -- config
