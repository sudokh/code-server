# code-server

自宅 Ubuntu サーバで動かす [code-server](https://github.com/coder/code-server)（ブラウザ版 VS Code）環境。
公式イメージ `codercom/code-server:latest` をベースに zsh / tmux / neovim / make を追加したカスタムイメージを Docker Compose で起動する。

メイン用途は **iPad の Safari からの利用**。HTTPS 終端は別途稼働中の Caddy が担う（本リポジトリのスコープ外）。

## 起動

```sh
docker compose up -d --build
```

- アクセス: `http://<サーバIP>:8080`（LAN 内のみ・認証なし）
- iPad から使うときは **必ず Caddy 経由の HTTPS URL** でアクセスすること。
  HTTP 直アクセスだと secure context 要件により webview（Markdown プレビュー等）・PWA 化・クリップボード連携が動かない。

Caddyfile 側は 1 行でよい:

```
code.example.home {
    reverse_proxy <サーバIP>:8080
}
```

> Caddy が code-server と同一ホストで動いている場合は、`docker-compose.yaml` の ports を
> `"127.0.0.1:8080:8080"` に絞ると LAN の他端末から認証なしの HTTP 入口に直接届かなくなる。

## 更新（code-server を最新版にする）

```sh
docker compose build --pull
docker compose up -d
```

`latest` タグでも勝手に更新はされず、このコマンドを叩いたときだけ上がる。

## Ubuntu サーバへの移設

リポジトリを clone して同じコマンドを叩くだけ（公式イメージは amd64 / arm64 両対応なので Mac でも Ubuntu でも同一手順）。

```sh
git clone <このリポジトリ> && cd code-server
docker compose up -d --build
```

バインドマウント（`./data`）の所有者が UID 1000 とずれる場合は、compose のサービスに
`user: "${UID}:${GID}"` を追加すれば fixuid が追従する。

## データの持ち方

| 場所 | 実体 | 内容 |
|---|---|---|
| `/home/coder/project` | `./data`（バインドマウント） | 作業ファイル。ホストから直接見える |
| `/home/coder` | `code-server-home`（名前付きボリューム） | 拡張機能・設定・`.zshrc`・シェル履歴・`.gitconfig`・`.ssh` など |

ホームはボリュームなので、イメージを再ビルドしても拡張機能や git の認証情報は消えない。
初回起動時にイメージ内のホーム内容がボリュームへコピーされ、以後イメージ側のホーム変更は反映されない点に注意。

## メモ

- 拡張機能ストアは [Open VSX](https://open-vsx.org/)（Microsoft Marketplace ではない）。GitHub Copilot 等の MS 専有拡張は入らない。
- iPad では Caddy 経由の HTTPS URL を Safari で開いて「ホーム画面に追加」すると、PWA としてフルスクリーンの専用アプリ風に使える。
