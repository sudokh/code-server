# コンテナにssh接続
```
$ ssh -p 10022 root@localhost
root@localhost's password: password
```

# 鍵生成
```
ssh-keygen -q -t rsa -N '' -f /.ssh/id_rsa
* -q: メッセージを表示しない
* -t: 暗号化形式を指定
* -N: 新しく設定するパスフレーズを指定
* -f: 生成する鍵ファイルの保存場所を指定

mv /root/.ssh/id_rsa.pub authorized_keys
```