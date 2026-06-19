# code-server

自宅 Ubuntu サーバで動かす [code-server](https://github.com/coder/code-server)（ブラウザ版 VS Code）環境。
公式イメージ `codercom/code-server:latest` をベースに zsh / tmux / neovim / make / openssh-client を追加したカスタムイメージを Docker Compose で起動する。

メイン用途は **iPad の Safari からの利用**。HTTPS 終端は別途稼働中の Caddy が担う（本リポジトリのスコープ外）。

## 設計方針

- **code-server 本体はコンテナ化**：新品マシンでも `git clone → make init → make up` で再現できる（可搬性）。
- **ターミナルはホストへSSH**：統合ターミナルを開くと、コンテナの中ではなく **code-server が動いているホストマシンへ SSH** する。「そのマシンにSSHしているかのように」作業できる。
- **編集はホストの作業ディレクトリに対して**：作業ディレクトリ（`PROJECT_DIR`）を **ホストと同一の絶対パス** でコンテナにマウントする。エディタで開くパスと、ターミナル（ホスト）のパスが一致するので食い違わない。
- **日常状態はvolume、基準状態はGitとイメージ**：普段の設定変更や拡張機能追加は `code-server-home` に保存し、`make inventory` で再現に必要なものだけをGit管理領域へ棚卸しする。
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
make inventory  # volume の日常状態を config/ へ棚卸し
make check-inventory # volume と Git 管理中の基準状態を比較
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
| `${PROJECT_DIR}`（例: `/home/<user>/Project`） | ホストの同一パスをバインドマウント | 作業ファイル。ホスト・エディタ・ホストSSHターミナルすべてが同じパスで見る |
| `/home/coder` | `code-server-home`（名前付きボリューム） | 拡張機能・設定・`.zshrc`・シェル履歴・`.gitconfig` など |
| `/home/coder/.ssh/id_host` | `./ssh/id_ed25519`（read-only バインド） | ホストSSH用の秘密鍵（`make init` が生成） |

ホームはボリュームなので、イメージを再ビルドしても拡張機能や git の認証情報は消えない。
空のvolumeを初めてマウントしたときは、イメージ内の `/home/coder` に焼いた設定と拡張機能がvolumeへコピーされる。以後はvolume側が日常状態の本体となり、イメージを再ビルドしても既存volumeには反映されない。

### 設定と拡張機能のIaC

再現可能な基準状態として、次をGit管理する。

```text
config/
├── User/
│   ├── settings.json
│   ├── keybindings.json
│   └── snippets/
└── extensions.txt
```

- `settings.json`：ユーザー設定
- `keybindings.json`：キーボードショートカット
- `snippets/`：ユーザースニペット
- `extensions.txt`：拡張機能のIDとバージョン

Dockerのビルド時に `config/User/` をイメージ内の `/home/coder` へコピーし、`extensions.txt` に記録された拡張機能をインストールする。拡張機能本体はGit管理しない。

日常利用ではcode-server上で自由に設定や拡張機能を変更し、定期的に棚卸しする。

```sh
make inventory
git status --short -- config
git diff -- config
```

`make inventory` がvolumeから取得するのは、設定、ショートカット、スニペット、拡張機能一覧だけ。`globalStorage`、`workspaceStorage`、編集履歴、ログ、キャッシュ、認証情報、拡張機能本体は取得しない。秘密情報らしいキー名を検出した場合は警告するが、Gitへ追加する前に必ず差分を確認すること。棚卸しはステージやコミットを行わない。

基準状態との差分だけを確認したい場合は次を使う。このコマンドは `config/` を更新せず、差分があれば終了コード1を返す。

```sh
make check-inventory
```

新しいマシンでは通常どおりセットアップする。

```sh
git clone <このリポジトリ> && cd code-server
make init
make up
```

新規作成された空の `code-server-home` には、最後に棚卸ししてビルドした基準状態が初期投入される。棚卸し後に既存volumeへ基準状態を反映したい場合は、volumeを作り直す必要がある。volumeの削除は、棚卸しされていない日常変更や認証情報も失うため、事前に確認すること。

## ターミナルの使い分け

- 既定プロファイル **host** … ホストへSSH（通常はこちら）。
- プロファイル **bash (container)** … コンテナ内のシェル。デバッグ用。
  - 切り替えはターミナルパネルの「＋」横のプルダウンから。

## メモ

- 拡張機能ストアは [Open VSX](https://open-vsx.org/)（Microsoft Marketplace ではない）。GitHub Copilot 等の MS 専有拡張は入らない。
- iPad では Caddy 経由の HTTPS URL を Safari で開いて「ホーム画面に追加」すると、PWA としてフルスクリーンの専用アプリ風に使える。
- tmux の複数行コピーは、ホスト側 tmux で `set -s set-clipboard on`（OSC 52）を有効にし、HTTPS（secure context）でアクセスすれば iPad のクリップボードへ直接入る。旧構成の `sync_tmux.sh` 的なファイル橋渡しは不要。
- `${PROJECT_DIR}` の所有者が UID 1000 とずれる場合は、compose のサービスに `user: "${UID}:${GID}"` を追加すれば fixuid が追従する。
