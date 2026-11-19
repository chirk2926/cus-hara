# 自宅の Linux サーバーでゲームサーバーを動かす（要件#100）

ゲームサーバーは Node.js なので、Windows でなくても動きます（Linux の方が手間は少ない）。
ここでは「自宅の Linux サーバー ＋ Cloudflare Tunnel ＋ 管理画面は家の Windows PC から SSH で開く」の形を書きます。
レンタルの Linux VPS でも同じ手順で動きます。

```
プレイヤー ──HTTPS──▶ Cloudflare ──トンネル──▶ cloudflared（自宅サーバー）──▶ 127.0.0.1:8787 ゲームサーバー
家の Windows PC ──SSH（家の中だけ）──▶ 自宅サーバー ──▶ 127.0.0.1:8790 管理画面
```

- ルーターのポートは開けません（Cloudflare Tunnel は中から外へつなぐだけ）。自宅の IP アドレスも外に出ません。
- ゲームサーバーも管理画面も、サーバーの中の 127.0.0.1 でだけ待ち受けます。外から届くのは、トンネルを通ったゲームの通信だけです。
- **管理画面のポート（8790）は、トンネルにも、ルーターにも、絶対に出さない。**（まちがえて出しても、管理画面は「プロキシを通ってきた接続」と「このマシンの外からの接続」を断りますが、出さないのが前提です）

## 1. 用意するもの
- Linux のマシン（Ubuntu 24.04 など）。メモリ 2GB 以上、24時間つけておけるもの。
- ドメイン（例 `example.com`。年数百〜千円程度）。Cloudflare に登録して、ネームサーバーを Cloudflare にする。
- Cloudflare のアカウント（無料のプランでよい）。
- Claude の APIキー（あとで管理画面から入れる）。

## 2. サーバーを置く
```bash
sudo apt update && sudo apt install -y git curl
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
sudo useradd --system --create-home --home-dir /opt/cus-hara --shell /usr/sbin/nologin cushara
sudo -u cushara git clone https://github.com/<あなた>/cus-hara.git /opt/cus-hara
cd /opt/cus-hara/server && sudo -u cushara npm ci --omit=dev
sudo -u cushara mkdir -p /opt/cus-hara/server/var
```
（リポジトリが非公開なら、`git clone` は GitHub のトークンか SSH の鍵で。データの `data/` も一緒に入ります）

## 3. 自動で起動するようにする（systemd）
```bash
sudo cp /opt/cus-hara/deploy/systemd/cushara.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cushara
sudo systemctl status cushara
```
- 管理画面の「サーバーを再起動」は、このサービスが起動し直します（`Restart=always`）。
- ログを見る: `journalctl -u cushara -f`
- 管理画面の最初のパスワード: `sudo cat /opt/cus-hara/server/var/admin_initial_password.txt`（ログインしたら「パスワード」から変える。変えるとこのファイルは消える）

## 4. Cloudflare Tunnel で公開する
```bash
# cloudflared を入れる（Cloudflare の手順: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/）
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o cloudflared.deb
sudo dpkg -i cloudflared.deb
cloudflared tunnel login                 # ブラウザで Cloudflare にログインしてドメインを選ぶ
cloudflared tunnel create cushara        # トンネルを作る（ID と鍵のファイルが作られる）
cloudflared tunnel route dns cushara game.example.com
sudo mkdir -p /etc/cloudflared
sudo cp ~/.cloudflared/<トンネルのID>.json /etc/cloudflared/
sudo cp /opt/cus-hara/deploy/systemd/cloudflared-config.yml /etc/cloudflared/config.yml
sudo nano /etc/cloudflared/config.yml    # <トンネルのID> と game.example.com を書きかえる
sudo cloudflared service install
sudo systemctl enable --now cloudflared
```
- 確かめる: ブラウザで `https://game.example.com/api/v1/info` を開いて、JSON が出ればよい。
- ゲームの「設定 → ゲームサーバー」（または配る版の既定のサーバー）を `https://game.example.com` にする。WebSocket（対戦）もトンネルをそのまま通ります。
- `TRUST_PROXY=1`（systemd の設定に入れてある）で、プレイヤーの本当の IP（Cloudflare の CF-Connecting-IP）で制限します。これがないと全員が 127.0.0.1 に見えて、アカウント作成などの上限がすぐ埋まります。管理画面の「状態」に、1 でないと警告が出ます。

## 5. 管理画面を家の Windows PC から開く
1. Windows 10/11 には ssh が入っています。初めてのときは、サーバーにログインできるか確かめる: `ssh cushara-admin@192.168.1.20`
   （管理用のユーザーは cushara とは別に作る。例 `sudo adduser cushara-admin`。パスワードより SSH の鍵がおすすめ）
2. `deploy/windows/admin_tunnel.bat` の `SERVER=` を自分の「ユーザー名@サーバーの家の中のアドレス」に書きかえて、ダブルクリック。
3. ブラウザで `http://127.0.0.1:8790/` が開く。パスワードでログイン。
4. 終わったら黒い窓を閉じる（トンネルが切れる）。

コマンドで開くなら:
```bash
ssh -N -L 8790:127.0.0.1:8790 cushara-admin@192.168.1.20
```

## 6. 守り（おすすめ）
```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw allow from 192.168.0.0/16 to any port 22 proto tcp   # SSH は家の中からだけ
sudo ufw enable
```
- ゲームのポート（8787）も管理画面（8790）も 127.0.0.1 だけなので、ファイアウォールで開ける必要はありません。
- `server/var/` にデータベース・APIキー（secrets.json）・管理画面のパスワード（admin_auth.json）が入ります。持ち主だけが読めるようにしてあります。バックアップを取るときは、この3つを安全な場所に。
- OS の更新: `sudo apt update && sudo apt upgrade` をときどき。`unattended-upgrades` を入れると自動。

## 7. 更新するとき
```bash
cd /opt/cus-hara && sudo -u cushara git pull
cd server && sudo -u cushara npm ci --omit=dev
sudo systemctl restart cushara
```
管理画面で変えた設定（DB）と APIキー（secrets.json）は、更新しても残ります。

## 8. 自宅で動かすときの注意
- 停電・回線の工事のあいだは止まります（その間、ゲームは「サーバーにつながりません。1人用は台本で遊べます」になる）。
- プロバイダの利用規約で、自宅でのサーバー公開が禁止されていないか確かめてください（Cloudflare Tunnel は外からの接続を受けないので、多くの場合は問題になりにくい）。
- プレイヤーが増えて重くなったら、同じ手順でレンタルの Linux VPS に移せます（`server/var/` をそのまま持っていく）。
