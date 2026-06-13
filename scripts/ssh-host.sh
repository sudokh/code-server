#!/usr/bin/env bash
#
# code-server の統合ターミナルから、code-server が動いているホストマシンへ SSH するラッパ。
# これを既定ターミナルプロファイルにすることで「ターミナル＝そのマシンにSSHしている」状態になる。
#
# - 鍵: make init がホスト側で生成し、compose が read-only でマウントしたものを使う（イメージには焼かない）
# - 宛先: host.docker.internal（Linux ホストでは compose の extra_hosts で host-gateway に解決）
# - ユーザー: compose の environment 経由で渡る HOST_USER
#
set -euo pipefail
exec ssh \
  -i /home/coder/.ssh/id_host \
  -o StrictHostKeyChecking=accept-new \
  -o UserKnownHostsFile=/home/coder/.ssh/known_hosts \
  "${HOST_USER:-root}@host.docker.internal"
