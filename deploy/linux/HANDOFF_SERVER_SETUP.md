# 引き継ぎ: 自宅の Ubuntu サーバーに「本番」と「テスト」のゲームサーバーを作る

この文書は、**サーバー機（Ubuntu）の上で動く Claude Code** に作業を引き継ぐためのもの。
最初にこの文書を全部読んでから始めること。報告・質問は日本語で、短く。

## 0. 目的と、決まっていること

- ゲーム「カスハラ防衛線」のゲームサーバー（Node.js 22.18 以上。`server/`）を、このサーバー機に **本番** と **テスト** の2つ作る。
- 決定済み（依頼者に確認済み。聞き直さない）:
  - 本番もテストも、ブランチ `claude/wizardly-keller-c3rj2v` の最新で動かす。データ（DB・AIのキー・管理画面のパスワード）は別々。
  - テストも外から使えるようにする（別のサブドメイン `test.<ドメイン>`）。ただし **ドメインはまだ決まっていない** ので、Cloudflare Tunnel は今回はやらない（手順だけ伝える）。
  - OS は Ubuntu / Debian 系。
- 作るものの一覧:

| | 本番 | テスト |
|---|---|---|
| systemd のサービス | `cushara` | `cushara-test` |
| 動かすユーザー（ログイン不可） | `cushara` | `cushara-test` |
| 置き場所 | `/opt/cus-hara` | `/opt/cus-hara-test` |
| ゲーム | 127.0.0.1:8787 | 127.0.0.1:8788 |
| 管理画面 | 127.0.0.1:8790 | 127.0.0.1:8791 |

これは全部 `deploy/linux/setup.sh` がやる（何度流してもよい）。自分で同じことを手で組み立て直さないこと。

## 1. 今の状態（2026-11-24 時点）

- サーバー機: ホスト名 `us-g101`、作業ユーザー `chirk`（sudo できる）。
- `sudo git clone git@github.com:chirk2926/cus-hara.git ...` が `Permission denied (publickey)` で失敗した。
  原因: リポジトリは非公開で、**root に GitHub の鍵が無い**（sudo の git は root の鍵を使う）。github.com のホスト鍵は root の known_hosts に登録済み。
- 依頼者が `sudo chmod -R 755 /srv/` を実行している。`/srv/cus` は今回の作業では使わない（触らなくてよい）。
- まだ何も作られていない（`/opt/cus-hara*`・サービス・ユーザーは無い）。

## 2. 手順

### 2.1 root のデプロイキー（読むだけ）を用意する
スクリプトも、更新のコマンド（`cushara-update`）も root で git を使うので、root に鍵を作る。
```bash
sudo test -f /root/.ssh/id_ed25519 || sudo ssh-keygen -t ed25519 -N "" -f /root/.ssh/id_ed25519 -C cushara-deploy
sudo cat /root/.ssh/id_ed25519.pub
```
表示された1行（`ssh-ed25519 ...` の **公開鍵だけ**）を依頼者に見せて、登録してもらう:
- `https://github.com/chirk2926/cus-hara/settings/keys` →「Add deploy key」
- Title は `cushara-server`、**「Allow write access」はチェックしない**
- 秘密鍵（`/root/.ssh/id_ed25519`）は絶対に表示・送信しない。

登録されたか確かめる:
```bash
sudo ssh -T git@github.com    # "successfully authenticated" が出ればよい（終了コード 1 は正常）
```

### 2.2 取ってきて、セットアップを流す
```bash
sudo git clone git@github.com:chirk2926/cus-hara.git /opt/cus-hara-setup
cd /opt/cus-hara-setup
sudo REPO_URL=git@github.com:chirk2926/cus-hara.git bash deploy/linux/setup.sh
```
- `/opt/cus-hara-setup` は、スクリプトのひな形を読むための写し（ゲームはここでは動かさない）。
- Node.js が 22.18 より古い・無いときは、スクリプトが NodeSource から入れる（`/usr/bin/node` に入る。systemd はここを使う）。
- 最後に「できました」と、本番・テストそれぞれの管理画面の最初のパスワードの **場所** が出る。

### 2.3 確かめる
```bash
systemctl status cushara cushara-test --no-pager
curl -s http://127.0.0.1:8787/api/v1/status; echo
curl -s http://127.0.0.1:8788/api/v1/status; echo
sudo ls -la /opt/cus-hara/server/var /opt/cus-hara-test/server/var
stat -c '%U %n' /opt/cus-hara/server/src/main.ts      # root であること
ss -ltnp | grep -E ':(8787|8788|8790|8791)\b'           # 4つとも 127.0.0.1 で待っていること
```
- `status` は `{"game":"ok","ai":"down",...}` でよい（AI のキーはまだ入れていないので down が正しい）。
- `server/var` は、それぞれのユーザーだけが読み書きできる（700）こと。
- 4つのポートが **0.0.0.0 や外向きの住所で待っていない** こと。

### 2.4 依頼者に報告する（日本語で短く）
- できたもの（上の表）と、確かめた結果。
- 管理画面の最初のパスワードは `sudo cat /opt/cus-hara/server/var/admin_initial_password.txt`（テストは `/opt/cus-hara-test/...`）で **依頼者自身が見る** こと。チャットに中身を出さない。
- 次に依頼者がすること:
  1. 家の Windows から管理画面を開く: `deploy/windows/admin_tunnel.bat`（本番）・`admin_tunnel_test.bat`（テスト）。中の `SERVER=` を `chirk@<サーバーの家の中のアドレス>` にする。ログインしたらパスワードを変える（本番とテストで別々）。
  2. 管理画面の「AIのAPI」でキーを登録する（本番とテストで別々）。
  3. ドメインが決まったら Cloudflare Tunnel（`docs/HOME_SERVER.md` 4節。`deploy/systemd/cloudflared-config.yml` に本番 `game.<ドメイン>`→8787、テスト `test.<ドメイン>`→8788）。

## 3. 守ること（重要）

- **管理画面のポート（8790・8791）は、絶対に外へ出さない。** Cloudflare Tunnel・ufw・ルーターのどれでも開けない。開くのは SSH のトンネル経由だけ。
- パスワード・API キー・秘密鍵・`server/var` の中身（`secrets.json`・`admin_auth.json`・`admin_initial_password.txt`・DB）を、チャット・ログ・コミットに出さない。
- サーバーの上でリポジトリのファイルを書きかえない（更新は `git` で取ってくるだけ。`cushara-update` はブランチの最新に強制的にそろえる）。直す必要があれば、依頼者に伝えて、元のリポジトリ側で直してもらう。
- `rm -rf` など大きく消す操作・`chmod -R`・`chown -R` を、`/opt/cus-hara*` 以外に対してしない。迷ったら依頼者に聞く。
- 依頼者の作業ユーザー `chirk` の SSH の設定は、依頼者が「公開鍵の認証に変える」と言っている。頼まれたら手伝う:
  - 依頼者の PC の公開鍵を `~chirk/.ssh/authorized_keys` に入れ、**鍵でログインできることを別の窓で確かめてから**、`/etc/ssh/sshd_config`（または `/etc/ssh/sshd_config.d/*.conf`）で `PasswordAuthentication no`・`PermitRootLogin no` にして `sudo systemctl reload ssh`。確かめる前に切ると締め出される。
  - インターネットに SSH（22番）を出しているなら、ルーターの転送を止めるか、家の中からだけにすることをすすめる（`docs/HOME_SERVER.md` 6節の ufw）。

## 4. 困ったとき

| 症状 | 見る所・直し方 |
|---|---|
| `Permission denied (publickey)` | 2.1 のデプロイキーが未登録。`sudo ssh -T git@github.com` で確かめる |
| サービスが起動しない | `journalctl -u cushara -n 50 --no-pager`（テストは `cushara-test`） |
| `npm ci` が失敗 | Node.js の版（`node -v` が 22.18 以上か）、ネットにつながるか |
| ポートが使われている | `ss -ltnp \| grep 8787` で何が使っているか。ほかのものなら止めてよいか依頼者に聞く |
| 更新したい | `sudo cushara-update test`（テストだけ）/ `prod` / `all`。起動しなければ前の版に戻る |

詳しくは `docs/HOME_SERVER.md`（0節がこの作業の説明）、サーバーの中身は `docs/SERVER.md`。
