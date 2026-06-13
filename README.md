# code-server

自宅 Ubuntu サーバで動かす [code-server](https://github.com/coder/code-server)（ブラウザ版 VS Code）環境。
公式イメージ `codercom/code-server:latest` をベースに zsh / tmux / neovim / make / openssh-client を追加したカスタムイメージを Docker Compose で起動する。

メイン用途は **iPad の Safari からの利用**。HTTPS 終端は別途稼働中の Caddy が担う（本リポジトリのスコープ外）。

## 設計方針

- **code-server 本体はコンテナ化**：新品マシンでも `git clone → make init → make up` で再現できる（可搬性）。
- **ターミナルはホストへSSH**：統合ターミナルを開くと、コンテナの中ではなく **code-server が動いているホストマシンへ SSH** する。「そのマシンにSSHしているかのように」作業できる。
- **編集はホストの作業ディレクトリに対して**：作業ディレクトリ（`PROJECT_DIR`）を **ホストと同一の絶対パス** でコンテナにマウントする。エディタで開くパスと、ターミナル（ホスト）のパスが一致するので食い違わない。
- **ホスト固有のものはイメージに焼かない**：`HOST_USER` / 作業パス / SSH鍵は `make init` がホスト側で生成し `.env` と `ssh/` に置く（どちらも git 管理外）。イメージは汎用のまま。

## セットアップ（ホスト上で）

```sh
git clone <このリポジトリ> && cd code-server
make init     # 鍵生成・.env作成・ホストの authorized_keys に公開鍵登録
make up       # docker compose up -d --build
```

- アクセス: `http://<サーバIP>:8080`（LAN 内のみ・認証なし）
- iPad から使うときは **必ず Caddy 経由の HTTPS URL** でアクセスすること。
  HTTP 直アクセスだと secure context 要件により webview（Markdown プレビュー等）・PWA 化・クリップボード連携が動かない。

### 前提：ホストで sshd が動いていること

ターミナルのホストSSHを使うには、ホストで sshd が稼働している必要がある（`make init` は稼働チェックして警告するだけ。起動には sudo が要るため自動ではやらない）。

```sh
sudo apt install -y openssh-server && sudo systemctl enable --now ssh
```

ufw 等のファイアウォールを使っている場合は、Docker ブリッジ（`host.docker.internal` 経由）からの 22 番への接続を許可しておくこと。

## make ターゲット

```sh
make            # ヘルプ
make init       # 初回セットアップ（ホスト上で1回）
make up         # 起動（ビルド込み）
make down       # 停止して削除
make restart    # 再起動
make logs       # ログ追従
make exec       # コンテナ側の bash に入る（ホストではなくコンテナ）
make pull       # code-server を最新イメージへ更新
```

`latest` タグでも勝手には更新されない。上げたいときだけ `make pull`。

## Caddy 側

Caddyfile は 1 行でよい:

```
code.example.home {
    reverse_proxy <サーバIP>:8080
}
```

> Caddy が code-server と同一ホストで動いている場合は、`.env` の `PORT` 運用に加えて
> `docker-compose.yaml` の ports を `"127.0.0.1:${PORT}:8080"` に絞ると、LAN の他端末から
> 認証なしの HTTP 入口に直接届かなくなる。

## データの持ち方

| 場所 | 実体 | 内容 |
|---|---|---|
| `${PROJECT_DIR}`（例: `/home/sudou/Project`） | ホストの同一パスをバインドマウント | 作業ファイル。ホスト・エディタ・ホストSSHターミナルすべてが同じパスで見る |
| `/home/coder` | `code-server-home`（名前付きボリューム） | 拡張機能・設定・`.zshrc`・シェル履歴・`.gitconfig` など |
| `/home/coder/.ssh/id_host` | `./ssh/id_ed25519`（read-only バインド） | ホストSSH用の秘密鍵（`make init` が生成） |

ホームはボリュームなので、イメージを再ビルドしても拡張機能や git の認証情報は消えない。
初回起動時にイメージ内のホーム内容（既定ターミナルプロファイル等）がボリュームへコピーされ、以後イメージ側のホーム変更は反映されない点に注意。ターミナル設定をやり直したいときは `docker compose down -v` でボリュームごと作り直す。

## ターミナルの使い分け

- 既定プロファイル **host** … ホストへSSH（通常はこちら）。
- プロファイル **bash (container)** … コンテナ内のシェル。デバッグ用。
  - 切り替えはターミナルパネルの「＋」横のプルダウンから。

## メモ

- 拡張機能ストアは [Open VSX](https://open-vsx.org/)（Microsoft Marketplace ではない）。GitHub Copilot 等の MS 専有拡張は入らない。
- iPad では Caddy 経由の HTTPS URL を Safari で開いて「ホーム画面に追加」すると、PWA としてフルスクリーンの専用アプリ風に使える。
- tmux の複数行コピーは、ホスト側 tmux で `set -s set-clipboard on`（OSC 52）を有効にし、HTTPS（secure context）でアクセスすれば iPad のクリップボードへ直接入る。旧構成の `sync_tmux.sh` 的なファイル橋渡しは不要。
- `${PROJECT_DIR}` の所有者が UID 1000 とずれる場合は、compose のサービスに `user: "${UID}:${GID}"` を追加すれば fixuid が追従する。
